import '../models/bt_models.dart';

/// Classic Bluetooth 통신의 모든 기능을 정의하는 추상 인터페이스.
///
/// BLE의 [BLERepository]와 동일한 역할을 한다:
/// UI·Provider는 항상 이 인터페이스에만 의존하고 구현체를 직접 참조하지 않는다.
///
/// Classic BT와 BLE의 핵심 차이점:
/// | 항목         | BLE                  | Classic BT           |
/// |-------------|----------------------|----------------------|
/// | 탐색         | startScan (빠름)      | startDiscovery (느림) |
/// | 페어링       | 선택 사항             | 연결 전 필수           |
/// | 통신 구조    | GATT Service/Char     | SPP 소켓 (원시 바이트) |
/// | 식별자       | MAC 또는 UUID         | 항상 MAC 주소          |
///
/// 구현체 교체:
/// - 개발/테스트: [MockBTRepository]
/// - 실제 기기:  FlutterBluetoothSerialRepository (flutter_bluetooth_serial 라이브러리)
abstract class BTRepository {
  /// 스마트폰의 블루투스가 현재 켜져 있는지 확인한다.
  Future<bool> isBluetoothEnabled();

  // ─── 장치 탐색 (Inquiry) ────────────────────────────────────────────────────

  /// 주변 Classic Bluetooth 장치 탐색(Inquiry)을 시작한다.
  ///
  /// BLE 스캔보다 훨씬 느리다. 실제 환경에서는 완전 탐색에 8~12초가 걸린다.
  /// 장치가 발견될 때마다 [discoveryResults] 스트림에 전체 목록을 방출한다.
  /// [timeout] 후 자동으로 탐색을 중단한다.
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 12)});

  /// 진행 중인 탐색을 즉시 중단한다.
  Future<void> stopDiscovery();

  /// 탐색 중 발견된 장치 목록을 실시간으로 방출하는 스트림.
  Stream<List<BTDevice>> get discoveryResults;

  /// 현재 탐색 진행 중 여부
  bool get isDiscovering;

  // ─── 페어링된 장치 목록 ─────────────────────────────────────────────────────

  /// 스마트폰에 이미 페어링된 Classic BT 장치 목록을 반환한다.
  ///
  /// 페어링 정보는 OS가 관리하며, 앱을 재시작해도 유지된다.
  /// 탐색 없이도 호출 가능하다.
  Future<List<BTDevice>> getPairedDevices();

  // ─── 페어링 ─────────────────────────────────────────────────────────────────

  /// 지정된 주소의 장치와 페어링을 시도한다.
  ///
  /// 내부적으로 PIN 코드 교환 및 링크 키 생성이 진행된다.
  /// [pairState] 스트림: notPaired → pairing → paired
  /// 실패 시 [BTException]을 던진다.
  Future<void> pair(String address);

  /// 지정된 장치와의 페어링을 해제한다.
  ///
  /// 페어링 해제 시 OS의 페어링 목록에서도 제거된다.
  Future<void> unpair(String address);

  /// 지정된 장치의 페어링 상태 변화를 실시간으로 방출하는 스트림.
  Stream<BTPairState> pairState(String address);

  // ─── 연결 (SPP Socket) ──────────────────────────────────────────────────────

  /// 페어링된 장치에 SPP(직렬 포트) 소켓 연결을 시도한다.
  ///
  /// 미페어링 장치에 호출하면 [BTException]을 던진다.
  /// [connectionState] 스트림: disconnected → connecting → connected
  Future<void> connect(String address);

  /// 연결된 장치와의 SPP 소켓 연결을 해제한다.
  Future<void> disconnect(String address);

  /// 지정된 장치의 연결 상태 변화를 실시간으로 방출하는 스트림.
  Stream<BTConnectionState> connectionState(String address);

  /// 지정된 장치가 현재 연결되어 있는지 동기적으로 반환한다.
  bool isConnected(String address);

  // ─── SPP 데이터 송수신 ───────────────────────────────────────────────────────

  /// 연결된 장치에 바이트 배열을 전송한다.
  ///
  /// 미연결 상태에서 호출하면 [BTException]을 던진다.
  /// SPP는 원시 바이트 스트림이므로 프로토콜/패킷 구조는 앱이 직접 정의해야 한다.
  Future<void> sendData(String address, List<int> data);

  /// 연결된 장치에서 수신되는 [BTMessage] 스트림을 반환한다.
  ///
  /// 장치가 데이터를 보낼 때마다 새 [BTMessage]가 방출된다.
  /// 연결이 끊어지면 스트림이 종료된다.
  Stream<BTMessage> receiveData(String address);

  // ─── 리소스 해제 ────────────────────────────────────────────────────────────

  /// 모든 StreamController, 타이머, 소켓 연결을 정리하고 해제한다.
  Future<void> dispose();
}
