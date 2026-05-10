import 'dart:async';
import 'dart:math';

import 'package:logger/logger.dart';

import '../models/bt_models.dart';
import 'bt_repository.dart';

/// [BTRepository]의 Mock 구현체.
///
/// 실제 Bluetooth 하드웨어 없이 4개의 가상 Classic BT 장치를 시뮬레이션한다.
/// 각 장치는 실제 제품에서 볼 수 있는 이름, MAC 주소, 프로파일을 갖는다.
///
/// 시뮬레이션 장치:
/// 1. Arduino Nano BT  — SPP (직렬 데이터 통신)
/// 2. Windows Laptop   — SPP + OPP (파일 전송)
/// 3. BT Keyboard      — HID (이미 페어링됨)
/// 4. Car Head Unit    — A2DP + HFP (이미 페어링됨)
class MockBTRepository implements BTRepository {
  final _logger = Logger();
  final _random = Random();

  bool _isDiscovering = false;
  final _discoveryController = StreamController<List<BTDevice>>.broadcast();
  final _connectionControllers = <String, StreamController<BTConnectionState>>{};
  final _pairControllers = <String, StreamController<BTPairState>>{};
  final _receiveControllers = <String, StreamController<BTMessage>>{};

  /// 현재 연결된 장치 MAC 주소 집합
  final _connectedDevices = <String>{};

  /// 탐색 및 RSSI 갱신 타이머
  Timer? _discoveryTimer;
  Timer? _rssiTimer;

  /// SPP 수신 데이터 타이머 (장치별)
  final _receiveTimers = <String, Timer>{};

  /// 현재까지 발견된 장치 목록 (탐색 중 누적)
  final _discoveredDevices = <BTDevice>[];

  /// 페어링 상태를 인메모리로 관리한다.
  /// 앱을 재시작하면 초기화되지만, Mock이므로 허용한다.
  final _pairedAddresses = <String>{
    'DE:AD:BE:EF:00:01', // BT Keyboard — 미리 페어링된 장치
    '11:22:33:AA:BB:CC', // Car Head Unit — 미리 페어링된 장치
  };

  /// 가상 Classic BT 장치 목록.
  ///
  /// 실제 제품을 모방해 이름, MAC 주소, RSSI 기준값, 지원 프로파일을 설정한다.
  /// OUI(MAC 앞 3바이트)도 실제 제조사 코드를 사용해 현실감을 높였다.
  static const _mockDevices = [
    (
      address: '00:11:22:33:44:55',
      name: 'Arduino Nano BT',
      rssi: -50,
      profiles: [BTProfile.spp],
    ),
    (
      address: 'AA:BB:CC:00:11:22',
      name: 'Windows Laptop',
      rssi: -60,
      profiles: [BTProfile.spp, BTProfile.opp],
    ),
    (
      address: 'DE:AD:BE:EF:00:01',
      name: 'BT Keyboard',
      rssi: -55,
      profiles: [BTProfile.hid],
    ),
    (
      address: '11:22:33:AA:BB:CC',
      name: 'Car Head Unit',
      rssi: -70,
      profiles: [BTProfile.a2dp, BTProfile.hfp],
    ),
  ];

  /// SPP 장치별로 전송할 시뮬레이션 데이터 메시지 목록.
  ///
  /// Arduino는 센서값을, Laptop은 상태 메시지를 주기적으로 보낸다.
  static const _sppMessages = {
    '00:11:22:33:44:55': [
      'TEMP:24.5\r\n',
      'TEMP:25.1\r\n',
      'HUM:62\r\n',
      'TEMP:24.8\r\n',
      'LIGHT:340\r\n',
      'TEMP:25.3\r\n',
    ],
    'AA:BB:CC:00:11:22': [
      'STATUS:OK\r\n',
      'CPU:12%\r\n',
      'MEM:4.2GB\r\n',
      'STATUS:OK\r\n',
      'DISK:87%\r\n',
    ],
  };

  /// 각 장치의 SPP 메시지 순환 인덱스
  final _sppMessageIndex = <String, int>{};

  @override
  Future<bool> isBluetoothEnabled() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  // ─── 탐색 ────────────────────────────────────────────────────────────────────

  /// Classic BT 탐색(Inquiry)을 시작한다.
  ///
  /// BLE보다 훨씬 느린 탐색을 시뮬레이션하기 위해 1.5초 간격으로 장치를 발견한다.
  /// 실제 환경의 8~12초 탐색 시간을 축소 시뮬레이션한 것이다.
  @override
  Future<void> startDiscovery({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_isDiscovering) return;
    _logger.d('MockBT: startDiscovery');
    _isDiscovering = true;
    _discoveredDevices.clear();

    int deviceIndex = 0;
    // BLE(0.8초)보다 느린 1.5초 간격으로 장치를 발견해 Classic BT 특성을 표현한다.
    _discoveryTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (deviceIndex < _mockDevices.length) {
        final d = _mockDevices[deviceIndex++];
        final device = BTDevice(
          address: d.address,
          name: d.name,
          rssi: d.rssi + _random.nextInt(6) - 3,
          pairState: _pairedAddresses.contains(d.address)
              ? BTPairState.paired
              : BTPairState.notPaired,
          profiles: d.profiles,
        );
        _discoveredDevices.add(device);
        _discoveryController.add(List.unmodifiable(_discoveredDevices));
      } else {
        timer.cancel();
      }
    });

    // 3초마다 이미 발견된 장치들의 RSSI를 갱신한다.
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_discoveredDevices.isNotEmpty) {
        final updated = _discoveredDevices.map((d) {
          final base = _mockDevices.firstWhere((m) => m.address == d.address);
          return d.copyWith(rssi: base.rssi + _random.nextInt(6) - 3);
        }).toList();
        _discoveredDevices
          ..clear()
          ..addAll(updated);
        _discoveryController.add(List.unmodifiable(_discoveredDevices));
      }
    });

    Future.delayed(timeout, stopDiscovery);
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    _logger.d('MockBT: stopDiscovery');
    _discoveryTimer?.cancel();
    _rssiTimer?.cancel();
    _isDiscovering = false;
  }

  @override
  Stream<List<BTDevice>> get discoveryResults => _discoveryController.stream;

  @override
  bool get isDiscovering => _isDiscovering;

  // ─── 페어링된 장치 목록 ──────────────────────────────────────────────────────

  /// 미리 페어링된 장치 목록을 반환한다.
  ///
  /// 실제 OS는 앱 시작 시 즉시 반환하지만, Mock은 300ms 지연을 두어 자연스럽게 표현한다.
  @override
  Future<List<BTDevice>> getPairedDevices() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockDevices
        .where((d) => _pairedAddresses.contains(d.address))
        .map((d) => BTDevice(
              address: d.address,
              name: d.name,
              rssi: d.rssi + _random.nextInt(6) - 3,
              pairState: BTPairState.paired,
              profiles: d.profiles,
            ))
        .toList();
  }

  // ─── 페어링 ──────────────────────────────────────────────────────────────────

  /// 지정된 장치와 페어링을 시도한다.
  ///
  /// 상태 전환: notPaired → pairing (즉시) → paired (1.5초 후)
  /// 1.5초 지연은 실제 PIN 교환 및 링크 키 생성 시간을 시뮬레이션한다.
  @override
  Future<void> pair(String address) async {
    _logger.d('MockBT: pair $address');
    final controller = _getOrCreatePairController(address);

    controller.add(BTPairState.pairing);
    await Future.delayed(const Duration(milliseconds: 1500));

    _pairedAddresses.add(address);
    controller.add(BTPairState.paired);

    // 발견된 장치 목록에서도 페어링 상태를 업데이트한다.
    final idx = _discoveredDevices.indexWhere((d) => d.address == address);
    if (idx != -1) {
      _discoveredDevices[idx] =
          _discoveredDevices[idx].copyWith(pairState: BTPairState.paired);
      _discoveryController.add(List.unmodifiable(_discoveredDevices));
    }
  }

  /// 지정된 장치와의 페어링을 해제하고 OS 목록에서 제거한다.
  @override
  Future<void> unpair(String address) async {
    _logger.d('MockBT: unpair $address');
    _pairedAddresses.remove(address);
    _getOrCreatePairController(address).add(BTPairState.notPaired);

    final idx = _discoveredDevices.indexWhere((d) => d.address == address);
    if (idx != -1) {
      _discoveredDevices[idx] =
          _discoveredDevices[idx].copyWith(pairState: BTPairState.notPaired);
      _discoveryController.add(List.unmodifiable(_discoveredDevices));
    }
  }

  @override
  Stream<BTPairState> pairState(String address) {
    return _getOrCreatePairController(address).stream;
  }

  // ─── 연결 ────────────────────────────────────────────────────────────────────

  /// 페어링된 장치에 SPP 소켓 연결을 시도한다.
  ///
  /// 미페어링 장치에 호출하면 [BTException]을 던진다.
  /// 상태 전환: connecting (즉시) → connected (1초 후)
  @override
  Future<void> connect(String address) async {
    if (!_pairedAddresses.contains(address)) {
      throw const BTException('Device not paired');
    }
    _logger.d('MockBT: connect $address');
    final controller = _getOrCreateConnectionController(address);

    controller.add(BTConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 1000));

    _connectedDevices.add(address);
    controller.add(BTConnectionState.connected);

    // 연결 즉시 SPP 데이터 수신 타이머를 시작한다.
    _startReceiving(address);
  }

  /// SPP 소켓 연결을 해제한다.
  ///
  /// 상태 전환: disconnecting (즉시) → disconnected (500ms 후)
  /// 연결 해제 시 수신 타이머도 함께 취소한다.
  @override
  Future<void> disconnect(String address) async {
    _logger.d('MockBT: disconnect $address');
    final controller = _getOrCreateConnectionController(address);

    controller.add(BTConnectionState.disconnecting);
    await Future.delayed(const Duration(milliseconds: 500));

    _connectedDevices.remove(address);
    _receiveTimers[address]?.cancel();
    _receiveTimers.remove(address);
    _receiveControllers[address]?.close();
    _receiveControllers.remove(address);
    controller.add(BTConnectionState.disconnected);
  }

  @override
  Stream<BTConnectionState> connectionState(String address) {
    return _getOrCreateConnectionController(address).stream;
  }

  @override
  bool isConnected(String address) => _connectedDevices.contains(address);

  // ─── SPP 데이터 ──────────────────────────────────────────────────────────────

  /// 연결된 장치에 바이트 배열을 전송한다.
  ///
  /// Mock이므로 실제 전송 없이 로그만 출력한다.
  /// 텍스트 명령이면 ASCII로, 아니면 HEX로 로그에 기록한다.
  @override
  Future<void> sendData(String address, List<int> data) async {
    if (!isConnected(address)) {
      throw const BTException('Device not connected');
    }
    await Future.delayed(const Duration(milliseconds: 50));
    final text = String.fromCharCodes(data.where((b) => b >= 32 && b < 127));
    _logger.d('MockBT: send [$address] → "$text"');
  }

  /// 연결된 장치에서 주기적으로 데이터를 수신하는 스트림을 반환한다.
  ///
  /// SPP 장치(Arduino, Laptop)는 2초마다 새 메시지를 보낸다.
  /// HID, A2DP 등 데이터 통신을 지원하지 않는 프로파일은 빈 스트림을 반환한다.
  @override
  Stream<BTMessage> receiveData(String address) {
    return _getOrCreateReceiveController(address).stream;
  }

  // ─── 내부 헬퍼 ──────────────────────────────────────────────────────────────

  /// 연결 완료 후 장치 유형에 맞는 SPP 수신 시뮬레이션 타이머를 시작한다.
  void _startReceiving(String address) {
    final messages = _sppMessages[address];
    if (messages == null) return; // SPP 미지원 장치면 수신 없음

    _sppMessageIndex[address] = 0;
    final controller = _getOrCreateReceiveController(address);

    // 2초마다 메시지 목록을 순환하면서 수신 이벤트를 방출한다.
    _receiveTimers[address] = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isConnected(address) || controller.isClosed) return;

      final idx = _sppMessageIndex[address]! % messages.length;
      _sppMessageIndex[address] = idx + 1;

      final text = messages[idx];
      controller.add(BTMessage(
        data: text.codeUnits,
        timestamp: DateTime.now(),
        isFromDevice: true,
      ));
    });
  }

  StreamController<BTConnectionState> _getOrCreateConnectionController(
    String address,
  ) {
    return _connectionControllers.putIfAbsent(
      address,
      () => StreamController<BTConnectionState>.broadcast(),
    );
  }

  StreamController<BTPairState> _getOrCreatePairController(String address) {
    return _pairControllers.putIfAbsent(
      address,
      () => StreamController<BTPairState>.broadcast(),
    );
  }

  StreamController<BTMessage> _getOrCreateReceiveController(String address) {
    return _receiveControllers.putIfAbsent(
      address,
      () => StreamController<BTMessage>.broadcast(),
    );
  }

  // ─── 리소스 해제 ─────────────────────────────────────────────────────────────

  /// 모든 타이머와 StreamController를 닫고 리소스를 해제한다.
  @override
  Future<void> dispose() async {
    _discoveryTimer?.cancel();
    _rssiTimer?.cancel();
    for (final t in _receiveTimers.values) {
      t.cancel();
    }
    await _discoveryController.close();
    for (final c in _connectionControllers.values) {
      await c.close();
    }
    for (final c in _pairControllers.values) {
      await c.close();
    }
    for (final c in _receiveControllers.values) {
      await c.close();
    }
    _connectionControllers.clear();
    _pairControllers.clear();
    _receiveControllers.clear();
    _receiveTimers.clear();
  }
}
