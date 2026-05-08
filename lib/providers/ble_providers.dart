import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ble_models.dart';
import '../repositories/ble_repository.dart';
import '../repositories/mock_ble_repository.dart';

/// 앱 전체에서 사용하는 [BLERepository] 싱글턴 인스턴스를 제공하는 Provider.
///
/// 현재는 [MockBLERepository]를 반환하며, 실제 BLE 연동이 필요할 때
/// `return FlutterBluePlusRepository()` 로 한 줄만 바꾸면 된다.
///
/// [ref.onDispose]: Provider가 해제될 때(앱 종료 또는 ProviderScope 제거 시)
/// repo.dispose()를 자동 호출해 StreamController, 타이머 등 리소스를 정리한다.
final bleRepositoryProvider = Provider<BLERepository>((ref) {
  final repo = MockBLERepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// 블루투스 활성화 여부를 비동기로 확인하는 Provider.
///
/// [FutureProvider]: 비동기 단일 값을 제공할 때 사용한다.
/// UI에서 `.when(data:, loading:, error:)`로 로딩·성공·오류 상태를 분기 처리한다.
/// [bleRepositoryProvider]를 watch해 Repository가 바뀌면 자동으로 재실행된다.
final isBluetoothEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(bleRepositoryProvider).isBluetoothEnabled();
});

/// 현재 BLE 스캔이 진행 중인지 여부를 나타내는 Provider.
///
/// [StateProvider]: 단순한 단일 값 상태에 적합하다.
/// [BleScanNotifier]가 startScan()/stopScan() 호출 시 이 값을 true/false로 전환한다.
/// UI의 FAB 버튼 색상, StatusBar 표시 내용이 이 값에 반응한다.
final bleIsScanningProvider = StateProvider<bool>((ref) => false);

/// 스캔 중 발견된 BLE 장치 목록을 보관하는 Provider.
///
/// [BleScanNotifier.startScan]이 [BLERepository.scanResults] 스트림을 구독해
/// 새 장치가 발견될 때마다 이 Provider의 값을 갱신한다.
/// stopScan() 또는 다음 startScan() 호출 시 빈 목록으로 초기화된다.
final discoveredDevicesProvider = StateProvider<List<BLEDevice>>((ref) => []);

/// 현재 연결된 장치들의 ID 집합을 보관하는 Provider.
///
/// [BleConnectionNotifier.connect]가 연결 성공 후 deviceId를 추가하고,
/// [BleConnectionNotifier.disconnect]가 연결 해제 후 deviceId를 제거한다.
/// Set<String>으로 관리해 동일 장치의 중복 연결 등록을 방지한다.
final connectedDevicesProvider = StateProvider<Set<String>>((ref) => {});

/// BLE 스캔 시작/중지를 제어하는 StateNotifier.
///
/// [AsyncValue<void>]를 상태로 사용해 스캔 작업의 로딩·완료·오류 상태를 UI에 전달한다.
/// void인 이유: 스캔 결과는 [discoveredDevicesProvider]가 별도로 관리하므로
/// 이 Notifier는 작업 성공/실패 여부만 알리면 충분하다.
class BleScanNotifier extends StateNotifier<AsyncValue<void>> {
  /// [Ref]를 직접 보유해 다른 Provider를 읽고 쓸 수 있다.
  BleScanNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  /// BLE 장치 탐색을 시작한다.
  ///
  /// 처리 순서:
  /// 1. 상태를 loading으로 전환 (UI에 로딩 표시)
  /// 2. 이전 탐색 결과 초기화
  /// 3. isScanning 상태를 true로 전환
  /// 4. [BLERepository.scanResults] 스트림 구독 → 새 장치 발견 시 [discoveredDevicesProvider] 갱신
  /// 5. [BLERepository.startScan] 호출
  /// 6. 성공 시 상태를 data로, 실패 시 error로 전환
  Future<void> startScan() async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(bleRepositoryProvider);
      _ref.read(discoveredDevicesProvider.notifier).state = [];
      _ref.read(bleIsScanningProvider.notifier).state = true;

      // scanResults 스트림을 구독해 장치 발견 이벤트를 discoveredDevicesProvider에 전달한다.
      // listen()은 구독을 시작하고 즉시 반환되므로 await 없이 사용한다.
      repo.scanResults.listen((devices) {
        _ref.read(discoveredDevicesProvider.notifier).state = devices;
      });

      await repo.startScan();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      _ref.read(bleIsScanningProvider.notifier).state = false;
      state = AsyncValue.error(e, st);
    }
  }

  /// 진행 중인 BLE 탐색을 중단한다.
  ///
  /// Repository의 stopScan()을 호출한 뒤 [bleIsScanningProvider]를 false로 전환한다.
  Future<void> stopScan() async {
    await _ref.read(bleRepositoryProvider).stopScan();
    _ref.read(bleIsScanningProvider.notifier).state = false;
    state = const AsyncValue.data(null);
  }
}

/// [BleScanNotifier]를 생성하고 외부에 제공하는 Provider.
///
/// UI에서 스캔을 시작하려면:
///   `ref.read(bleScanNotifierProvider.notifier).startScan()`
/// 스캔 작업의 로딩/오류 상태를 구독하려면:
///   `ref.watch(bleScanNotifierProvider)`
final bleScanNotifierProvider =
    StateNotifierProvider<BleScanNotifier, AsyncValue<void>>(
  (ref) => BleScanNotifier(ref),
);

/// BLE 장치 연결/해제를 제어하는 StateNotifier.
///
/// [AsyncValue<void>]를 상태로 사용해 연결 작업의 로딩·완료·오류 상태를 UI에 전달한다.
/// 연결 성공/실패 여부를 UI에 알리고, 실제 연결 목록은 [connectedDevicesProvider]가 관리한다.
class BleConnectionNotifier extends StateNotifier<AsyncValue<void>> {
  BleConnectionNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  /// 지정된 장치에 BLE 연결을 시도한다.
  ///
  /// 처리 순서:
  /// 1. 상태를 loading으로 전환 (UI에 로딩 표시)
  /// 2. [BLERepository.connect] 호출 (내부적으로 connecting → connected 전환)
  /// 3. 성공 시 [connectedDevicesProvider]에 deviceId 추가
  ///
  /// Set을 직접 수정하지 않고 스프레드 연산자({...기존Set})로 새 Set을 만들어 할당한다.
  /// 이렇게 해야 StateProvider가 값 변경을 감지해 구독 위젯을 리빌드할 수 있다.
  Future<void> connect(String deviceId) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(bleRepositoryProvider).connect(deviceId);
      // 불변 방식으로 Set 업데이트: 기존 Set을 복사한 뒤 새 ID를 추가한다.
      final connected = {..._ref.read(connectedDevicesProvider)}..add(deviceId);
      _ref.read(connectedDevicesProvider.notifier).state = connected;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 지정된 장치와의 BLE 연결을 해제한다.
  ///
  /// 처리 순서:
  /// 1. 상태를 loading으로 전환
  /// 2. [BLERepository.disconnect] 호출 (내부적으로 disconnecting → disconnected 전환)
  /// 3. 성공 시 [connectedDevicesProvider]에서 deviceId 제거
  Future<void> disconnect(String deviceId) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(bleRepositoryProvider).disconnect(deviceId);
      // 불변 방식으로 Set 업데이트: 기존 Set을 복사한 뒤 ID를 제거한다.
      final connected = {..._ref.read(connectedDevicesProvider)}
        ..remove(deviceId);
      _ref.read(connectedDevicesProvider.notifier).state = connected;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// [BleConnectionNotifier]를 생성하고 외부에 제공하는 Provider.
///
/// UI에서 장치에 연결하려면:
///   `ref.read(bleConnectionNotifierProvider.notifier).connect(deviceId)`
/// 연결 작업의 로딩/오류 상태를 구독하려면:
///   `ref.watch(bleConnectionNotifierProvider)`
final bleConnectionNotifierProvider =
    StateNotifierProvider<BleConnectionNotifier, AsyncValue<void>>(
  (ref) => BleConnectionNotifier(ref),
);

/// 특정 장치의 BLE 연결 상태 변화를 실시간으로 제공하는 Provider.
///
/// [StreamProvider.family]: 매개변수(deviceId)를 받아 장치별로 독립된 Provider를 생성한다.
/// 동일한 deviceId로 여러 위젯이 구독해도 스트림은 공유된다.
///
/// 사용 예: `ref.watch(bleConnectionStateProvider('device_1'))`
/// 반환값: AsyncValue<BLEConnectionState> (loading → data(connecting/connected/...))
final bleConnectionStateProvider =
    StreamProvider.family<BLEConnectionState, String>((ref, deviceId) {
  return ref.watch(bleRepositoryProvider).connectionState(deviceId);
});

/// 연결된 장치의 GATT 서비스 목록을 비동기로 제공하는 Provider.
///
/// [FutureProvider.family]: deviceId별로 독립된 Provider를 생성한다.
/// connect() 완료 후 호출해야 하며, 미연결 장치에 대해 watch하면 BLEException이 발생한다.
///
/// 사용 예: `ref.watch(bleServicesProvider('device_1'))`
final bleServicesProvider =
    FutureProvider.family<List<BLEService>, String>((ref, deviceId) {
  return ref.watch(bleRepositoryProvider).discoverServices(deviceId);
});

/// 특정 특성의 값을 한 번 읽어 제공하는 Provider.
///
/// [FutureProvider.family]: (deviceId, serviceUuid, characteristicUuid) 튜플을 파라미터로 받는다.
/// Dart의 named record 타입을 파라미터로 사용해 여러 값을 하나로 묶었다.
///
/// 사용 예:
/// ```dart
/// ref.watch(bleReadCharacteristicProvider((
///   deviceId: 'device_1',
///   serviceUuid: '180D',
///   characteristicUuid: '2A37',
/// )))
/// ```
final bleReadCharacteristicProvider = FutureProvider.family<
    List<int>,
    ({
      String deviceId,
      String serviceUuid,
      String characteristicUuid,
    })>((ref, params) {
  return ref.watch(bleRepositoryProvider).readCharacteristic(
        deviceId: params.deviceId,
        serviceUuid: params.serviceUuid,
        characteristicUuid: params.characteristicUuid,
      );
});

/// 특정 특성의 실시간 알림 값을 스트림으로 제공하는 Provider.
///
/// [StreamProvider.family]: (deviceId, serviceUuid, characteristicUuid) 튜플을 파라미터로 받는다.
/// 구독 중에는 장치가 값을 보낼 때마다 AsyncValue<List<int>>가 갱신된다.
/// Provider 구독이 해제되면 내부 스트림 구독도 자동으로 취소된다.
///
/// 사용 예:
/// ```dart
/// ref.watch(bleNotifyCharacteristicProvider((
///   deviceId: 'device_1',
///   serviceUuid: '180D',
///   characteristicUuid: '2A37',
/// )))
/// ```
final bleNotifyCharacteristicProvider = StreamProvider.family<
    List<int>,
    ({
      String deviceId,
      String serviceUuid,
      String characteristicUuid,
    })>((ref, params) {
  return ref.watch(bleRepositoryProvider).notifyCharacteristic(
        deviceId: params.deviceId,
        serviceUuid: params.serviceUuid,
        characteristicUuid: params.characteristicUuid,
      );
});
