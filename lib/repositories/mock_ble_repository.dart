import 'dart:async';
import 'dart:math';

import 'package:logger/logger.dart';

import '../models/ble_models.dart';
import 'ble_repository.dart';

/// [BLERepository]의 Mock 구현체.
///
/// 실제 Bluetooth 하드웨어나 OS BLE API를 전혀 사용하지 않고,
/// Timer와 StreamController만으로 실제 BLE 장치와 유사한 동작을 시뮬레이션한다.
///
/// 시뮬레이션하는 장치 목록은 [_mockDevices]에 정의되며, 4개의 가상 장치를 포함한다.
/// 이 구현체를 [FlutterBluePlusRepository] 등 실제 구현으로 교체하면
/// Provider와 UI 코드 변경 없이 실제 기기와 통신할 수 있다.
class MockBLERepository implements BLERepository {
  final _logger = Logger();

  /// 난수 생성기. RSSI 변동, mock 센서 값 생성에 사용한다.
  final _random = Random();

  /// 현재 스캔 진행 여부
  bool _isScanning = false;

  /// scanResults 스트림의 컨트롤러.
  /// broadcast로 생성해 여러 리스너가 동시에 구독할 수 있다.
  final _scanController = StreamController<List<BLEDevice>>.broadcast();

  /// 장치 ID별 연결 상태 스트림 컨트롤러 맵.
  /// connect()/disconnect() 호출 시 해당 장치의 컨트롤러에 상태를 방출한다.
  final _connectionControllers = <String, StreamController<BLEConnectionState>>{};

  /// 특성 알림 스트림 컨트롤러 맵. 키 형식: '$deviceId:$characteristicUuid'
  final _notifyControllers = <String, StreamController<List<int>>>{};

  /// 현재 연결된 장치 ID들의 집합
  final _connectedDevices = <String>{};

  /// 스캔 중 발견된 장치 목록. stopScan() 또는 startScan() 호출 시 초기화된다.
  final _discoveredDevices = <BLEDevice>[];

  /// 장치를 순차적으로 발견하는 타이머 (0.8초 간격)
  Timer? _scanTimer;

  /// 발견된 장치들의 RSSI를 주기적으로 갱신하는 타이머 (2초 간격)
  Timer? _rssiTimer;

  /// 시뮬레이션할 가상 BLE 장치 목록.
  ///
  /// 각 장치는 id, macAddress, name, rssi(기준값), serviceIds로 구성된다.
  /// macAddress는 실제 BLE 장치처럼 "XX:XX:XX:XX:XX:XX" 형식을 따른다.
  static const _mockDevices = [
    (
      id: 'device_1',
      macAddress: 'A4:C3:F0:12:34:56',
      name: 'Smart Watch',
      rssi: -45,
      serviceIds: ['180A', '180D', '180F', 'FFE0'],
    ),
    (
      id: 'device_2',
      macAddress: 'B8:27:EB:AA:BB:CC',
      name: 'Fitness Band',
      rssi: -55,
      serviceIds: ['180A', '180D', '180F'],
    ),
    (
      id: 'device_3',
      macAddress: 'C8:FD:19:11:22:33',
      name: 'Heart Rate Monitor',
      rssi: -65,
      serviceIds: ['180A', '180D'],
    ),
    (
      id: 'device_4',
      macAddress: 'F0:7B:CB:44:55:66',
      name: 'Bluetooth Speaker',
      rssi: -70,
      serviceIds: ['180A', 'FFE0'],
    ),
  ];

  /// 표준 GATT 서비스 UUID를 [BLEService] 객체로 변환한다.
  ///
  /// Bluetooth SIG 표준 서비스 UUID:
  /// - 180A: Device Information (제조사, 시리얼 번호)
  /// - 180D: Heart Rate (심박수, 센서 위치)
  /// - 180F: Battery Service (배터리 잔량)
  /// - FFE0: 제조사 커스텀 서비스 (커스텀 데이터 송수신)
  ///
  /// 알 수 없는 UUID가 들어오면 이름을 "Unknown Service"로 반환한다.
  BLEService _buildService(String serviceId) {
    switch (serviceId) {
      case '180A':
        return const BLEService(
          uuid: '180A',
          name: 'Device Information',
          characteristics: [
            BLECharacteristic(
              uuid: '2A29',
              name: 'Manufacturer Name',
              properties: [BLECharacteristicProperty.read],
            ),
            BLECharacteristic(
              uuid: '2A25',
              name: 'Serial Number',
              properties: [BLECharacteristicProperty.read],
            ),
          ],
        );
      case '180D':
        return const BLEService(
          uuid: '180D',
          name: 'Heart Rate',
          characteristics: [
            BLECharacteristic(
              uuid: '2A37',
              name: 'Heart Rate Measurement',
              properties: [
                BLECharacteristicProperty.read,
                BLECharacteristicProperty.notify,
              ],
            ),
            BLECharacteristic(
              uuid: '2A38',
              name: 'Body Sensor Location',
              properties: [BLECharacteristicProperty.read],
            ),
          ],
        );
      case '180F':
        return const BLEService(
          uuid: '180F',
          name: 'Battery',
          characteristics: [
            BLECharacteristic(
              uuid: '2A19',
              name: 'Battery Level',
              properties: [
                BLECharacteristicProperty.read,
                BLECharacteristicProperty.notify,
              ],
            ),
          ],
        );
      case 'FFE0':
        return const BLEService(
          uuid: 'FFE0',
          name: 'Custom Service',
          characteristics: [
            BLECharacteristic(
              uuid: 'FFE1',
              name: 'Custom Data',
              properties: [
                BLECharacteristicProperty.read,
                BLECharacteristicProperty.write,
                BLECharacteristicProperty.notify,
              ],
            ),
          ],
        );
      default:
        return BLEService(uuid: serviceId, name: 'Unknown Service');
    }
  }

  /// 특성 UUID에 따라 현실적인 mock 읽기 값을 생성해 반환한다.
  ///
  /// 각 UUID별 반환 형식은 Bluetooth SIG 표준 데이터 형식을 따른다:
  /// - 2A29 (Manufacturer Name): ASCII 문자열 바이트
  /// - 2A25 (Serial Number):     ASCII 문자열 바이트
  /// - 2A37 (Heart Rate):        [플래그 바이트(0x00), 심박수(60~99 bpm)] 2바이트
  /// - 2A38 (Sensor Location):   [위치 코드(0x01 = Chest)] 1바이트
  /// - 2A19 (Battery Level):     [잔량(70~99%)] 1바이트
  /// - FFE1 (Custom Data):       4바이트 랜덤 데이터
  List<int> _mockReadValue(String serviceUuid, String characteristicUuid) {
    switch (characteristicUuid) {
      case '2A29':
        return 'MockCorp'.codeUnits;
      case '2A25':
        // 시리얼 번호는 호출마다 다른 값을 반환해 동적 데이터를 시뮬레이션한다.
        return 'SN-${_random.nextInt(99999)}'.codeUnits;
      case '2A37':
        // Heart Rate Measurement 형식: 첫 바이트는 플래그(8비트 값 형식), 두 번째는 bpm
        final bpm = 60 + _random.nextInt(40);
        return [0x00, bpm];
      case '2A38':
        // Body Sensor Location: 0x01 = Chest(가슴)
        return [0x01];
      case '2A19':
        return [70 + _random.nextInt(30)];
      case 'FFE1':
        return List.generate(4, (_) => _random.nextInt(256));
      default:
        return [0x00];
    }
  }

  /// 블루투스가 활성화되어 있는지 확인한다.
  ///
  /// Mock이므로 실제 OS 상태와 무관하게 항상 true를 반환한다.
  /// 200ms 지연은 실제 시스템 API 호출 지연을 시뮬레이션한다.
  @override
  Future<bool> isBluetoothEnabled() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  /// BLE 장치 탐색을 시작한다.
  ///
  /// [_mockDevices] 목록의 장치를 0.8초 간격으로 하나씩 [_scanController]에 방출한다.
  /// 모든 장치 발견 후에는 2초마다 RSSI 값을 ±2 범위에서 갱신해 신호 변동을 시뮬레이션한다.
  /// [timeout] 후에는 [stopScan]을 자동 호출한다.
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;
    _logger.d('MockBLE: startScan');
    _isScanning = true;
    _discoveredDevices.clear();

    int deviceIndex = 0;
    // 0.8초마다 장치를 하나씩 발견하는 타이머
    _scanTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (deviceIndex < _mockDevices.length) {
        final d = _mockDevices[deviceIndex++];
        final device = BLEDevice(
          id: d.id,
          macAddress: d.macAddress,
          name: d.name,
          // 기준 RSSI에 ±2 dBm 랜덤 변동을 추가해 실제 환경의 신호 불안정성을 표현한다.
          rssi: d.rssi + _random.nextInt(5) - 2,
        );
        _discoveredDevices.add(device);
        // 새 장치 추가 때마다 전체 목록의 불변 복사본을 방출한다.
        _scanController.add(List.unmodifiable(_discoveredDevices));
      } else {
        timer.cancel();
      }
    });

    // 모든 장치 발견 후에도 2초마다 RSSI를 갱신해 신호 변동을 지속 시뮬레이션한다.
    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_discoveredDevices.isNotEmpty) {
        final updated = _discoveredDevices.map((d) {
          final base = _mockDevices.firstWhere((m) => m.id == d.id);
          return d.copyWith(rssi: base.rssi + _random.nextInt(5) - 2);
        }).toList();
        _discoveredDevices
          ..clear()
          ..addAll(updated);
        _scanController.add(List.unmodifiable(_discoveredDevices));
      }
    });

    // timeout 후 자동으로 스캔 중단
    Future.delayed(timeout, stopScan);
  }

  /// 진행 중인 BLE 탐색을 중단한다.
  ///
  /// 장치 발견 타이머([_scanTimer])와 RSSI 갱신 타이머([_rssiTimer])를 모두 취소한다.
  @override
  Future<void> stopScan() async {
    if (!_isScanning) return;
    _logger.d('MockBLE: stopScan');
    _scanTimer?.cancel();
    _rssiTimer?.cancel();
    _isScanning = false;
  }

  @override
  Stream<List<BLEDevice>> get scanResults => _scanController.stream;

  @override
  bool get isScanning => _isScanning;

  /// 지정된 장치에 BLE 연결을 시도한다.
  ///
  /// 연결 상태 전환: connecting (즉시) → connected (800ms 후)
  /// 800ms 지연은 실제 BLE 핸드셰이크 시간을 시뮬레이션한다.
  @override
  Future<void> connect(String deviceId) async {
    _logger.d('MockBLE: connect $deviceId');
    final controller = _getOrCreateConnectionController(deviceId);

    controller.add(BLEConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 800));

    _connectedDevices.add(deviceId);
    controller.add(BLEConnectionState.connected);
  }

  /// 지정된 장치와의 BLE 연결을 해제한다.
  ///
  /// 연결 상태 전환: disconnecting (즉시) → disconnected (400ms 후)
  /// 연결 해제 시 해당 장치의 notify 스트림 컨트롤러도 함께 닫는다.
  @override
  Future<void> disconnect(String deviceId) async {
    _logger.d('MockBLE: disconnect $deviceId');
    final controller = _getOrCreateConnectionController(deviceId);

    controller.add(BLEConnectionState.disconnecting);
    await Future.delayed(const Duration(milliseconds: 400));

    _connectedDevices.remove(deviceId);
    // 연결 해제 시 해당 장치의 모든 알림 구독도 함께 종료한다.
    // 키 형식은 notifyCharacteristic의 '$deviceId:$characteristicUuid'이다.
    final prefix = '$deviceId:';
    final keysToRemove =
        _notifyControllers.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      final c = _notifyControllers.remove(key);
      await c?.close();
    }
    controller.add(BLEConnectionState.disconnected);
  }

  /// 지정된 장치의 연결 상태 변화를 방출하는 스트림을 반환한다.
  ///
  /// 스트림이 없으면 [_getOrCreateConnectionController]로 새로 생성한다.
  @override
  Stream<BLEConnectionState> connectionState(String deviceId) {
    return _getOrCreateConnectionController(deviceId).stream;
  }

  @override
  bool isConnected(String deviceId) => _connectedDevices.contains(deviceId);

  /// 연결된 장치의 GATT 서비스 목록을 탐색해 반환한다.
  ///
  /// 미연결 상태에서 호출하면 [BLEException]을 던진다.
  /// 500ms 지연은 실제 GATT 서비스 탐색에 걸리는 시간을 시뮬레이션한다.
  /// [_mockDevices]에서 해당 장치의 serviceIds를 찾아 [_buildService]로 변환한다.
  @override
  Future<List<BLEService>> discoverServices(String deviceId) async {
    if (!isConnected(deviceId)) {
      throw const BLEException('Device not connected');
    }
    await Future.delayed(const Duration(milliseconds: 500));

    final deviceRecord = _mockDevices.where((d) => d.id == deviceId).firstOrNull;
    if (deviceRecord == null) return [];

    return deviceRecord.serviceIds.map(_buildService).toList();
  }

  /// 지정된 특성의 값을 읽어 바이트 배열로 반환한다.
  ///
  /// 미연결 상태에서 호출하면 [BLEException]을 던진다.
  /// 200ms 지연은 실제 GATT Read 응답 지연을 시뮬레이션한다.
  /// 반환 값은 [_mockReadValue]가 특성 UUID에 맞는 현실적인 데이터를 생성한다.
  @override
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (!isConnected(deviceId)) {
      throw const BLEException('Device not connected');
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return _mockReadValue(serviceUuid, characteristicUuid);
  }

  /// 지정된 특성에 바이트 배열 값을 전송한다.
  ///
  /// 미연결 상태에서 호출하면 [BLEException]을 던진다.
  /// Mock이므로 실제 전송 없이 로그만 출력하고 성공으로 처리한다.
  /// 200ms 지연은 실제 GATT Write 응답 지연을 시뮬레이션한다.
  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
  }) async {
    if (!isConnected(deviceId)) {
      throw const BLEException('Device not connected');
    }
    await Future.delayed(const Duration(milliseconds: 200));
    _logger.d('MockBLE: write $characteristicUuid = $value');
  }

  /// 지정된 특성의 값 변경 알림을 1초마다 방출하는 스트림을 반환한다.
  ///
  /// 스트림을 구독하면 [_mockReadValue]가 1초마다 새 값을 생성해 방출한다.
  /// 장치 연결이 해제되거나 스트림 컨트롤러가 닫히면 타이머도 자동 취소된다.
  ///
  /// 키 형식: '$deviceId:$characteristicUuid'로 장치별·특성별로 독립된 스트림을 관리한다.
  @override
  Stream<List<int>> notifyCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    final key = '$deviceId:$characteristicUuid';
    final controller = StreamController<List<int>>.broadcast(
      onListen: () => _logger.d('MockBLE: subscribe $characteristicUuid'),
      onCancel: () => _logger.d('MockBLE: unsubscribe $characteristicUuid'),
    );
    _notifyControllers[key] = controller;

    // 1초마다 새 값을 방출한다. 연결 해제되거나 컨트롤러가 닫히면 타이머를 취소한다.
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (controller.isClosed || !isConnected(deviceId)) {
        timer.cancel();
        return;
      }
      controller.add(_mockReadValue(serviceUuid, characteristicUuid));
    });

    return controller.stream;
  }

  /// 장치 ID에 대한 연결 상태 스트림 컨트롤러를 반환한다.
  ///
  /// 이미 존재하면 기존 것을 반환하고, 없으면 새로 생성한다.
  /// broadcast로 생성해 여러 위젯이 동시에 같은 장치의 연결 상태를 구독할 수 있다.
  StreamController<BLEConnectionState> _getOrCreateConnectionController(
    String deviceId,
  ) {
    return _connectionControllers.putIfAbsent(
      deviceId,
      () => StreamController<BLEConnectionState>.broadcast(),
    );
  }

  /// Repository가 사용하는 모든 리소스를 해제한다.
  ///
  /// 해제 대상:
  /// - [_scanTimer], [_rssiTimer]: 스캔 관련 타이머
  /// - [_scanController]: 스캔 결과 스트림
  /// - [_connectionControllers]: 모든 장치의 연결 상태 스트림
  /// - [_notifyControllers]: 모든 장치·특성의 알림 스트림
  ///
  /// Provider의 onDispose 콜백에서 자동 호출된다.
  @override
  Future<void> dispose() async {
    _scanTimer?.cancel();
    _rssiTimer?.cancel();
    await _scanController.close();
    for (final c in _connectionControllers.values) {
      await c.close();
    }
    for (final c in _notifyControllers.values) {
      await c.close();
    }
    _connectionControllers.clear();
    _notifyControllers.clear();
  }
}
