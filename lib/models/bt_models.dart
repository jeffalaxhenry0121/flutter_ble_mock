import 'package:flutter/foundation.dart';

/// Classic Bluetooth 연결 라이프사이클 상태.
///
/// BLE와 동일한 전환 순서를 따른다:
///   disconnected → connecting → connected → disconnecting → disconnected
enum BTConnectionState {
  /// 연결 없음
  disconnected,
  /// connect() 호출 후 소켓 연결이 완료되기 전
  connecting,
  /// SPP 소켓 연결 완료. 이 상태에서만 sendData/receiveData 가능
  connected,
  /// disconnect() 호출 후 완전히 끊어지기 전
  disconnecting,
}

/// 장치와의 페어링(Pairing) 상태.
///
/// Classic BT는 BLE와 달리 연결 전에 반드시 페어링이 필요하다.
/// 페어링은 한 번만 하면 되며, 이후에는 스마트폰이 장치를 기억해둔다.
enum BTPairState {
  /// 페어링된 적 없는 새 장치
  notPaired,
  /// pair() 호출 후 PIN 교환 및 키 생성 중
  pairing,
  /// 페어링 완료. 스마트폰의 "페어링된 기기 목록"에 등록된 상태
  paired,
}

/// Classic Bluetooth 장치가 지원하는 프로파일(기능 종류).
///
/// Classic BT는 BLE의 GATT 대신 "프로파일"로 기능을 정의한다.
/// 하나의 장치가 여러 프로파일을 동시에 지원할 수 있다.
enum BTProfile {
  /// Serial Port Profile: 가상 직렬 통신. 아두이노, 모듈 등 데이터 송수신에 사용
  spp,
  /// Advanced Audio Distribution Profile: 고품질 음악 스트리밍 (이어폰, 스피커)
  a2dp,
  /// Hands-Free Profile: 전화 통화, 마이크 입출력 (차량, 헤드셋)
  hfp,
  /// Human Interface Device: 키보드, 마우스, 게임패드
  hid,
  /// Object Push Profile: 파일 전송
  opp,
}

/// [BTProfile]을 사람이 읽기 쉬운 이름으로 변환하는 확장.
extension BTProfileName on BTProfile {
  String get displayName {
    switch (this) {
      case BTProfile.spp:  return 'Serial Port';
      case BTProfile.a2dp: return 'Audio (Music)';
      case BTProfile.hfp:  return 'Hands-Free';
      case BTProfile.hid:  return 'Input Device';
      case BTProfile.opp:  return 'File Transfer';
    }
  }
}

/// 하나의 Classic Bluetooth 장치를 표현하는 불변 데이터 클래스.
///
/// BLE의 [BLEDevice]와 달리 [address]가 항상 실제 MAC 주소다.
/// iOS도 Classic BT에서는 MAC 주소를 노출한다.
///
/// [address]로 동등성을 판단하며, 불변 객체이므로 상태 변경 시 [copyWith]를 사용한다.
@immutable
class BTDevice {
  /// Bluetooth MAC 주소. 형식: "AA:BB:CC:DD:EE:FF"
  /// Classic BT는 iOS 포함 모든 플랫폼에서 MAC 주소가 노출된다.
  final String address;

  /// 장치 이름 (장치 자체에 설정된 이름)
  final String name;

  /// 수신 신호 강도. 단위: dBm (항상 음수, 0에 가까울수록 강함)
  final int rssi;

  /// 현재 페어링 상태
  final BTPairState pairState;

  /// 이 장치가 지원하는 Bluetooth 프로파일 목록
  final List<BTProfile> profiles;

  const BTDevice({
    required this.address,
    required this.name,
    required this.rssi,
    this.pairState = BTPairState.notPaired,
    this.profiles = const [],
  });

  /// 페어링 완료 여부를 간편하게 확인하는 getter
  bool get isPaired => pairState == BTPairState.paired;

  /// SPP 프로파일 지원 여부. true이면 데이터 송수신이 가능하다.
  bool get supportsSPP => profiles.contains(BTProfile.spp);

  /// RSSI를 사람이 읽기 쉬운 신호 품질 문자열로 변환한다.
  String get signalStrength {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Very Good';
    if (rssi >= -70) return 'Good';
    if (rssi >= -80) return 'Fair';
    return 'Poor';
  }

  /// 일부 필드만 변경한 새 [BTDevice] 인스턴스를 반환한다.
  BTDevice copyWith({
    String? address,
    String? name,
    int? rssi,
    BTPairState? pairState,
    List<BTProfile>? profiles,
  }) {
    return BTDevice(
      address: address ?? this.address,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      pairState: pairState ?? this.pairState,
      profiles: profiles ?? this.profiles,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BTDevice && address == other.address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'BTDevice(address: $address, name: $name, rssi: $rssi)';
}

/// SPP(직렬 통신) 채널을 통해 주고받은 메시지 하나를 표현하는 불변 클래스.
///
/// Classic BT의 SPP는 GATT 특성 없이 원시 바이트를 주고받는다.
/// [isFromDevice]로 수신/송신 방향을 구분해 채팅 UI처럼 표시할 수 있다.
@immutable
class BTMessage {
  /// 메시지 원시 바이트 배열
  final List<int> data;

  /// 메시지 수신/송신 시각
  final DateTime timestamp;

  /// true: 기기에서 앱으로 수신된 메시지, false: 앱에서 기기로 송신한 메시지
  final bool isFromDevice;

  const BTMessage({
    required this.data,
    required this.timestamp,
    required this.isFromDevice,
  });

  /// 바이트 배열을 출력 가능한 ASCII 문자열로 변환한다. 비출력 문자는 제거한다.
  String get text => String.fromCharCodes(
        data.where((b) => b >= 32 && b < 127),
      );

  /// 바이트 배열을 16진수 공백 구분 형식으로 변환한다. 예: "54 45 4d 50"
  String get hex =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

/// Classic BT 작업 실패 시 던지는 커스텀 예외.
///
/// 미페어링 상태에서 연결 시도, 미연결 상태에서 데이터 전송 등의 오류에 사용한다.
class BTException implements Exception {
  final String message;
  final String? code;

  const BTException(this.message, {this.code});

  @override
  String toString() => 'BTException: $message';
}
