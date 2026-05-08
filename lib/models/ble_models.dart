import 'package:flutter/foundation.dart';

/// BLE 장치와의 연결 라이프사이클 상태를 나타내는 열거형.
///
/// 실제 BLE 연결은 즉시 완료되지 않으므로 중간 전환 상태(connecting, disconnecting)가 필요하다.
/// UI는 이 값을 구독해 연결 버튼 활성화 여부나 로딩 인디케이터 표시를 제어한다.
///
/// 상태 전환 순서:
///   disconnected → connecting → connected → disconnecting → disconnected
enum BLEConnectionState {
  /// 연결이 없는 초기 상태
  disconnected,
  /// connect() 호출 후 실제 연결이 완료되기 전까지의 중간 상태
  connecting,
  /// 연결이 완전히 수립된 상태. 이 상태에서만 GATT 서비스 탐색과 특성 조작이 가능하다.
  connected,
  /// disconnect() 호출 후 연결이 완전히 끊어지기 전까지의 중간 상태
  disconnecting,
}

/// BLE 특성(Characteristic)이 지원하는 기능 속성을 나타내는 열거형.
///
/// 하나의 특성은 여러 속성을 동시에 가질 수 있다.
/// 예를 들어 Heart Rate Measurement 특성은 [read]와 [notify]를 모두 지원한다.
enum BLECharacteristicProperty {
  /// GATT Read 절차로 값을 1회 읽을 수 있다.
  read,
  /// GATT Write 절차로 값을 장치에 전송할 수 있다.
  write,
  /// 장치가 값 변경 시 주기적으로 알림을 보내도록 구독할 수 있다. (확인 응답 없음)
  notify,
  /// notify와 동일하지만 각 알림마다 중앙 장치의 확인 응답(ACK)을 요구한다.
  indicate,
}

/// 하나의 BLE 주변 장치(Peripheral)를 표현하는 불변 데이터 클래스.
///
/// 스캔 중에 발견되며, 발견 시점에는 [services]가 빈 목록이고
/// [discoverServices] 호출 후에 서비스 정보가 채워진다.
///
/// [id]로 동등성을 판단하므로 동일한 장치는 RSSI가 달라도 같은 객체로 취급한다.
/// 불변 객체이므로 RSSI 갱신 등 상태 변경 시 [copyWith]로 새 인스턴스를 만들어야 한다.
@immutable
class BLEDevice {
  /// 앱 내부에서 장치를 식별하는 고유 ID.
  /// 실제 flutter_blue_plus에서는 Android의 경우 MAC 주소와 동일한 값이 된다.
  final String id;

  /// 장치의 Bluetooth MAC 주소. 형식: "AA:BB:CC:DD:EE:FF"
  /// iOS에서는 CoreBluetooth가 MAC 주소를 숨기고 시스템 UUID를 대신 제공한다.
  final String macAddress;

  /// 장치가 광고(Advertising)할 때 함께 보내는 표시 이름
  final String name;

  /// 수신 신호 강도(Received Signal Strength Indicator). 단위: dBm (항상 음수)
  /// 0에 가까울수록 신호가 강하다. 예: -45 dBm > -70 dBm
  final int rssi;

  /// 이 장치에 연결 시도를 허용하는지 여부.
  /// false이면 스캔에는 보이지만 connect()를 호출해도 응답하지 않는다.
  final bool isConnectable;

  /// discoverServices() 호출 후 채워지는 GATT 서비스 목록.
  /// 스캔 직후에는 빈 목록이다.
  final List<BLEService> services;

  const BLEDevice({
    required this.id,
    required this.macAddress,
    required this.name,
    required this.rssi,
    this.isConnectable = true,
    this.services = const [],
  });

  /// 일부 필드만 변경한 새 [BLEDevice] 인스턴스를 반환한다.
  ///
  /// 불변 객체이므로 직접 필드를 수정할 수 없다.
  /// 주로 RSSI 갱신 시 사용한다: `device.copyWith(rssi: newRssi)`
  BLEDevice copyWith({
    String? id,
    String? macAddress,
    String? name,
    int? rssi,
    bool? isConnectable,
    List<BLEService>? services,
  }) {
    return BLEDevice(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      isConnectable: isConnectable ?? this.isConnectable,
      services: services ?? this.services,
    );
  }

  /// RSSI 수치를 사람이 읽기 쉬운 신호 품질 문자열로 변환한다.
  ///
  /// | RSSI 범위       | 반환값      | 의미         |
  /// |----------------|-------------|-------------|
  /// | -50 dBm 이상   | 'Excellent' | 매우 가까운 거리 |
  /// | -60 dBm 이상   | 'Very Good' | 양호한 신호  |
  /// | -70 dBm 이상   | 'Good'      | 보통 신호    |
  /// | -80 dBm 이상   | 'Fair'      | 약한 신호    |
  /// | -80 dBm 미만   | 'Poor'      | 매우 약한 신호 |
  String get signalStrength {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Very Good';
    if (rssi >= -70) return 'Good';
    if (rssi >= -80) return 'Fair';
    return 'Poor';
  }

  /// 동등성 비교는 [id]만으로 판단한다.
  /// RSSI나 서비스 목록이 달라도 같은 장치(같은 id)면 동일한 객체로 취급한다.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BLEDevice && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BLEDevice(id: $id, mac: $macAddress, name: $name, rssi: $rssi)';
}

/// BLE GATT 서비스 하나를 표현하는 불변 데이터 클래스.
///
/// GATT(Generic Attribute Profile) 서비스는 관련된 특성들의 묶음이다.
/// 예를 들어 Heart Rate 서비스(0x180D)는 심박수 측정과 센서 위치 특성을 포함한다.
///
/// Bluetooth SIG가 정의한 표준 서비스는 16비트 UUID(예: "180D")를 사용하고,
/// 제조사 고유 서비스는 128비트 UUID를 사용한다.
@immutable
class BLEService {
  /// 서비스를 식별하는 UUID. 표준 서비스는 16비트(예: "180D"), 커스텀은 128비트 형식
  final String uuid;

  /// 서비스의 사람이 읽을 수 있는 이름. 예: "Heart Rate", "Battery Service"
  final String name;

  /// 이 서비스에 포함된 특성(Characteristic) 목록
  final List<BLECharacteristic> characteristics;

  const BLEService({
    required this.uuid,
    required this.name,
    this.characteristics = const [],
  });

  /// 동등성 비교는 [uuid]로만 판단한다.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BLEService && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => 'BLEService(uuid: $uuid, name: $name)';
}

/// BLE GATT 특성(Characteristic) 하나를 표현하는 불변 데이터 클래스.
///
/// 특성은 BLE 통신의 실질적인 데이터 단위다.
/// 각 특성은 고유한 UUID와 허용된 작업([properties])을 가지며,
/// 읽기/쓰기/알림 구독 가능 여부는 [canRead], [canWrite], [canNotify]로 확인한다.
///
/// [value]는 마지막으로 읽거나 수신한 바이트 배열 값이며, 아직 읽지 않았으면 null이다.
@immutable
class BLECharacteristic {
  /// 특성을 식별하는 UUID. 표준 특성은 16비트(예: "2A37"), 커스텀은 128비트 형식
  final String uuid;

  /// 특성의 사람이 읽을 수 있는 이름. 예: "Heart Rate Measurement", "Battery Level"
  final String name;

  /// 이 특성이 지원하는 GATT 작업 목록. 복수의 속성을 동시에 가질 수 있다.
  final List<BLECharacteristicProperty> properties;

  /// 마지막으로 읽거나 notify로 수신한 값(바이트 배열).
  /// readCharacteristic() 또는 notifyCharacteristic()을 통해 채워진다.
  /// 한 번도 읽지 않은 상태에서는 null이다.
  final List<int>? value;

  const BLECharacteristic({
    required this.uuid,
    required this.name,
    required this.properties,
    this.value,
  });

  /// [properties]에 [BLECharacteristicProperty.read]가 포함되어 있는지 확인한다.
  /// true이면 readCharacteristic() 호출이 가능하다.
  bool get canRead => properties.contains(BLECharacteristicProperty.read);

  /// [properties]에 [BLECharacteristicProperty.write]가 포함되어 있는지 확인한다.
  /// true이면 writeCharacteristic() 호출이 가능하다.
  bool get canWrite => properties.contains(BLECharacteristicProperty.write);

  /// [properties]에 [BLECharacteristicProperty.notify]가 포함되어 있는지 확인한다.
  /// true이면 notifyCharacteristic() 스트림 구독이 가능하다.
  bool get canNotify => properties.contains(BLECharacteristicProperty.notify);

  /// 일부 필드만 변경한 새 [BLECharacteristic] 인스턴스를 반환한다.
  ///
  /// 주로 읽기 결과를 반영할 때 사용한다: `characteristic.copyWith(value: readResult)`
  BLECharacteristic copyWith({
    String? uuid,
    String? name,
    List<BLECharacteristicProperty>? properties,
    List<int>? value,
  }) {
    return BLECharacteristic(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      properties: properties ?? this.properties,
      value: value ?? this.value,
    );
  }

  /// 동등성 비교는 [uuid]로만 판단한다.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BLECharacteristic && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => 'BLECharacteristic(uuid: $uuid, name: $name)';
}

/// BLE 작업 실패 시 던지는 커스텀 예외.
///
/// 미연결 상태에서 서비스 탐색을 시도하거나, 쓰기 권한이 없는 특성에 write를 시도하는 등
/// BLE 관련 오류 상황에서 사용한다.
/// [code]는 선택 사항이며, 오류를 세분화해 UI에서 다르게 처리할 때 활용한다.
class BLEException implements Exception {
  /// 오류 상황을 설명하는 메시지
  final String message;

  /// 오류를 구분하는 선택적 코드. 예: "NOT_CONNECTED", "PERMISSION_DENIED"
  final String? code;

  const BLEException(this.message, {this.code});

  @override
  String toString() => 'BLEException: $message';
}
