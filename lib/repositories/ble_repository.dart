import '../models/ble_models.dart';

/// BLE 통신의 모든 기능을 정의하는 추상 인터페이스.
///
/// 이 인터페이스가 UI 레이어와 실제 BLE 구현 사이의 경계(seam) 역할을 한다.
/// UI와 Provider는 항상 이 인터페이스에만 의존하고, 구체적인 구현체를 직접 참조하지 않는다.
///
/// 덕분에 구현체를 교체해도 UI 코드를 전혀 수정할 필요가 없다:
/// - 개발/테스트 환경: [MockBLERepository]
/// - 실제 기기 연동:  FlutterBluePlusRepository (BLERepository 구현)
///
/// 메서드 분류:
/// - 시스템 상태 확인: [isBluetoothEnabled]
/// - 스캔:           [startScan], [stopScan], [scanResults], [isScanning]
/// - 연결:           [connect], [disconnect], [connectionState], [isConnected]
/// - GATT 탐색:      [discoverServices]
/// - 특성 조작:       [readCharacteristic], [writeCharacteristic], [notifyCharacteristic]
/// - 리소스 해제:     [dispose]
abstract class BLERepository {
  /// 기기의 블루투스가 현재 켜져 있는지 확인한다.
  ///
  /// BLE 스캔이나 연결을 시도하기 전에 반드시 확인해야 한다.
  /// 꺼져 있으면 startScan()이 실패하거나 아무 장치도 발견되지 않는다.
  Future<bool> isBluetoothEnabled();

  /// 주변 BLE 장치 탐색을 시작한다.
  ///
  /// 장치가 발견될 때마다 [scanResults] 스트림에 현재까지 발견된 전체 목록을 방출한다.
  /// [timeout] 시간이 지나면 자동으로 스캔을 중단한다.
  /// 이미 스캔 중이면 호출을 무시한다.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)});

  /// 진행 중인 BLE 장치 탐색을 즉시 중단한다.
  ///
  /// 이미 중단된 상태이면 호출을 무시한다.
  Future<void> stopScan();

  /// 스캔 중 발견된 BLE 장치 목록을 실시간으로 방출하는 스트림.
  ///
  /// 새 장치가 발견될 때마다 기존 목록에 추가된 전체 목록을 방출한다.
  /// 즉, 이전 값과 비교하지 않고 항상 전체 목록이 방출된다.
  Stream<List<BLEDevice>> get scanResults;

  /// 현재 스캔이 진행 중인지 여부를 동기적으로 반환한다.
  bool get isScanning;

  /// 지정된 장치에 BLE 연결을 시도한다.
  ///
  /// 내부적으로 연결 상태가 connecting → connected 순서로 전환된다.
  /// [connectionState] 스트림을 구독하면 전환 과정을 실시간으로 관찰할 수 있다.
  /// 연결 실패 시 [BLEException]을 던진다.
  Future<void> connect(String deviceId);

  /// 지정된 장치와의 BLE 연결을 해제한다.
  ///
  /// 내부적으로 연결 상태가 disconnecting → disconnected 순서로 전환된다.
  /// 연결되지 않은 장치에 호출하면 [BLEException]을 던진다.
  Future<void> disconnect(String deviceId);

  /// 지정된 장치의 BLE 연결 상태 변화를 실시간으로 방출하는 스트림.
  ///
  /// connect() 호출 시: connecting → connected
  /// disconnect() 호출 시: disconnecting → disconnected
  /// 예상치 못한 연결 끊김 시: disconnected (즉시)
  Stream<BLEConnectionState> connectionState(String deviceId);

  /// 지정된 장치가 현재 연결되어 있는지 동기적으로 반환한다.
  ///
  /// discoverServices(), readCharacteristic() 등 연결이 필요한 작업 전에 확인한다.
  bool isConnected(String deviceId);

  /// 연결된 장치의 GATT 서비스 목록을 탐색해 반환한다.
  ///
  /// [isConnected]가 false인 장치에 호출하면 [BLEException]을 던진다.
  /// 반환된 [BLEService]에는 해당 서비스의 모든 특성 목록이 포함된다.
  Future<List<BLEService>> discoverServices(String deviceId);

  /// 지정된 특성의 현재 값을 한 번 읽어 반환한다.
  ///
  /// 반환값은 원시 바이트 배열(List<int>)이며, 해석은 특성 UUID에 따라 달라진다.
  /// 연결되지 않은 장치나 read 속성이 없는 특성에 호출하면 [BLEException]을 던진다.
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// 지정된 특성에 바이트 배열 값을 전송한다.
  ///
  /// [value]는 전송할 원시 바이트 배열이다.
  /// 연결되지 않은 장치나 write 속성이 없는 특성에 호출하면 [BLEException]을 던진다.
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
  });

  /// 지정된 특성의 값 변경 알림을 실시간으로 방출하는 스트림을 반환한다.
  ///
  /// 스트림을 구독하면 장치가 알림을 보낼 때마다 새 값(바이트 배열)을 방출한다.
  /// notify 속성이 없는 특성에 호출하면 [BLEException]을 던진다.
  /// 구독을 취소하면 장치의 알림 구독도 해제된다.
  Stream<List<int>> notifyCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Repository가 사용하는 모든 스트림, 타이머, 연결을 정리하고 해제한다.
  ///
  /// 앱 종료 또는 Provider의 onDispose 콜백에서 반드시 호출해야 한다.
  /// 호출하지 않으면 StreamController나 타이머가 메모리에 남아 누수가 발생한다.
  Future<void> dispose();
}
