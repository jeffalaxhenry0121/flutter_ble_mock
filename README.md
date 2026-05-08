# flutter_ble_mock

BLE(Bluetooth Low Energy) 통신 기능을 실제 하드웨어 없이 Mock으로 구현한 Flutter 샘플 프로젝트입니다.  
Repository 패턴, Riverpod 상태 관리, 스트림 기반 비동기 처리, 그리고 표준 BLE 서비스 시뮬레이션을 통해 실제 BLE 앱 개발 방식을 그대로 따르면서도 테스트 환경에서 완전히 동작하는 데모 앱입니다.

---

## 목차

1. [프로젝트 개요](#1-프로젝트-개요)
2. [주요 기능](#2-주요-기능)
3. [아키텍처](#3-아키텍처)
4. [프로젝트 구조](#4-프로젝트-구조)
5. [의존성](#5-의존성)
6. [데이터 모델](#6-데이터-모델)
7. [Repository 패턴](#7-repository-패턴)
8. [상태 관리 (Riverpod)](#8-상태-관리-riverpod)
9. [UI 화면](#9-ui-화면)
10. [Mock 시뮬레이션 상세](#10-mock-시뮬레이션-상세)
11. [테스트](#11-테스트)
12. [시작하기](#12-시작하기)
13. [플랫폼 지원](#13-플랫폼-지원)
14. [활용 방안](#14-활용-방안)

---

## 1. 프로젝트 개요

실제 BLE 기기 없이도 BLE 앱의 전체 흐름(스캔 → 연결 → 서비스 탐색 → 특성 읽기/쓰기/알림)을 개발하고 테스트할 수 있도록 설계된 Flutter 프로젝트입니다.

실무에서 BLE 앱을 개발할 때 겪는 문제점—하드웨어 의존성, 재현 불가능한 버그, 테스트 자동화 어려움—을 해결하기 위해 Mock 레이어를 추상화하여 실제 BLE 라이브러리(`flutter_blue_plus` 등)로의 교체가 `BLERepository` 인터페이스 구현 하나로 완료되도록 설계되었습니다.

---

## 2. 주요 기능

- **BLE 장치 스캔**: 주변 BLE 장치를 검색하고 목록으로 표시
- **신호 강도(RSSI) 표시**: 신호 세기를 색상 및 텍스트로 직관적으로 표현
- **장치 연결/해제**: 다중 장치 동시 연결 지원
- **서비스 탐색**: 연결된 장치의 GATT 서비스 자동 탐색
- **특성(Characteristic) 조작**:
  - Read: 특성 값 읽기
  - Write: 특성에 데이터 쓰기
  - Notify: 실시간 알림 구독
- **HEX/ASCII 이중 포맷 출력**: 바이너리 데이터를 두 가지 형식으로 표시
- **실시간 상태 업데이트**: 연결 상태, 알림 값이 UI에 즉시 반영
- **완전한 테스트 커버리지**: 단위·Provider·위젯 테스트 포함

---

## 3. 아키텍처

```
┌─────────────────────────────────────────┐
│              UI Layer (Screens)          │
│  HomeScreen ──── DeviceDetailScreen     │
└──────────────────┬──────────────────────┘
                   │ Riverpod Providers
┌──────────────────▼──────────────────────┐
│           State Management Layer        │
│  BleScanNotifier  BleConnectionNotifier │
│  discoveredDevicesProvider              │
│  bleServicesProvider (family)           │
│  bleNotifyCharacteristicProvider (family│
└──────────────────┬──────────────────────┘
                   │ BLERepository interface
┌──────────────────▼──────────────────────┐
│           Repository Layer              │
│  BLERepository (abstract interface)     │
│       └── MockBLERepository             │
│            (실제 BLE 교체 지점)          │
└─────────────────────────────────────────┘
```

### 핵심 설계 원칙

| 원칙 | 적용 방식 |
|------|-----------|
| **Clean Architecture** | UI → Provider → Repository 단방향 의존 |
| **Dependency Inversion** | UI와 Provider는 추상 `BLERepository`에만 의존 |
| **Immutable State** | 모든 모델 클래스에 `@immutable` + `copyWith()` 적용 |
| **Stream-Based Async** | 스캔 결과, 연결 상태, 알림 값은 모두 `Stream`으로 전달 |
| **Resource Management** | Provider의 `onDispose`로 StreamController, Timer 정리 |

---

## 4. 프로젝트 구조

```
flutter_ble_mock/
├── lib/
│   ├── main.dart                        # 앱 진입점, ProviderScope 설정
│   ├── models/
│   │   └── ble_models.dart              # BLE 데이터 모델 및 열거형
│   ├── providers/
│   │   └── ble_providers.dart           # Riverpod 상태 관리 전체
│   ├── repositories/
│   │   ├── ble_repository.dart          # BLE 추상 인터페이스
│   │   └── mock_ble_repository.dart     # Mock 구현체
│   └── screens/
│       ├── home_screen.dart             # 장치 스캔 화면
│       └── device_detail_screen.dart    # 장치 상세 및 조작 화면
└── test/
    ├── widget_test.dart                 # 위젯 테스트
    ├── providers/
    │   └── ble_providers_test.dart      # Provider 단위 테스트
    └── repositories/
        └── mock_ble_repository_test.dart # Repository 단위 테스트
```

---

## 5. 의존성

```yaml
dependencies:
  flutter_riverpod: ^2.4.0      # 상태 관리 프레임워크
  riverpod_annotation: ^2.3.0   # 코드 생성 어노테이션
  flutter_hooks: ^0.20.0        # 함수형 위젯 훅
  hooks_riverpod: ^2.4.0        # Hooks + Riverpod 통합
  logger: ^2.0.0                # 구조화된 로그 출력

dev_dependencies:
  flutter_test:                 # Flutter 테스트 프레임워크
  flutter_lints: ^3.0.0        # Dart 린트 규칙
  riverpod_generator: ^2.3.0   # Riverpod 코드 생성기
  build_runner: ^2.4.0         # 코드 생성 실행기
```

---

## 6. 데이터 모델

`lib/models/ble_models.dart`에 BLE 도메인의 핵심 데이터 구조가 정의되어 있습니다.

### 열거형 (Enums)

```dart
// BLE 연결 상태를 나타내는 라이프사이클
enum BLEConnectionState {
  disconnected,   // 연결 없음
  connecting,     // 연결 시도 중
  connected,      // 연결 완료
  disconnecting,  // 연결 해제 중
}

// BLE 특성의 기능 속성
enum BLECharacteristicProperty {
  read,     // 값 읽기 가능
  write,    // 값 쓰기 가능
  notify,   // 변경 알림 구독 가능
  indicate, // 확인 응답 포함 알림
}
```

### BLEDevice

장치 하나를 표현하는 불변 클래스입니다.

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | `String` | 장치 고유 식별자 |
| `name` | `String` | 장치 표시 이름 |
| `rssi` | `int` | 수신 신호 강도 (dBm) |
| `isConnectable` | `bool` | 연결 가능 여부 |
| `services` | `List<BLEService>` | 탐색된 GATT 서비스 목록 |

```dart
// signalStrength getter: RSSI 값을 문자열로 변환
// rssi >= -60  → "Excellent"
// rssi >= -70  → "Good"
// rssi >= -80  → "Fair"
// rssi <  -80  → "Poor"
String get signalStrength { ... }
```

### BLEService

GATT 서비스를 표현합니다.

| 필드 | 타입 | 설명 |
|------|------|------|
| `uuid` | `String` | 서비스 UUID |
| `name` | `String` | 서비스 이름 (예: "Heart Rate") |
| `characteristics` | `List<BLECharacteristic>` | 포함된 특성 목록 |

### BLECharacteristic

개별 특성을 표현하며, 속성에 따른 편의 getter를 제공합니다.

| 필드 / Getter | 타입 | 설명 |
|---------------|------|------|
| `uuid` | `String` | 특성 UUID |
| `name` | `String` | 특성 이름 |
| `properties` | `List<BLECharacteristicProperty>` | 지원 속성 목록 |
| `value` | `List<int>?` | 마지막으로 읽은 값 (바이트 배열) |
| `canRead` | `bool` | read 속성 포함 여부 |
| `canWrite` | `bool` | write 속성 포함 여부 |
| `canNotify` | `bool` | notify 속성 포함 여부 |

### BLEException

BLE 작업 중 발생하는 커스텀 예외입니다.

```dart
class BLEException implements Exception {
  final String message;
  final int? errorCode; // 선택적 오류 코드
}
```

---

## 7. Repository 패턴

### 추상 인터페이스 (`lib/repositories/ble_repository.dart`)

실제 BLE 라이브러리(`flutter_blue_plus`, `flutter_reactive_ble` 등)로 교체할 때 이 인터페이스만 새로 구현하면 됩니다.

```dart
abstract class BLERepository {
  // --- 시스템 상태 ---
  Future<bool> isBluetoothEnabled();

  // --- 스캔 ---
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)});
  Future<void> stopScan();
  Stream<List<BLEDevice>> get scanResults;  // 발견된 장치 스트림
  bool get isScanning;

  // --- 연결 ---
  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);
  Stream<BLEConnectionState> connectionState(String deviceId);
  bool isConnected(String deviceId);

  // --- GATT 서비스 탐색 ---
  Future<List<BLEService>> discoverServices(String deviceId);

  // --- 특성 조작 ---
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });

  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
  });

  Stream<List<int>> notifyCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });

  Future<void> dispose();
}
```

### Mock 구현체 (`lib/repositories/mock_ble_repository.dart`)

4개의 가상 BLE 장치를 시뮬레이션합니다.

#### 시뮬레이션 장치 목록

| ID | 이름 | RSSI | 서비스 수 |
|----|------|------|-----------|
| `device_1` | Smart Watch | -45 dBm | 4개 |
| `device_2` | Fitness Band | -55 dBm | 3개 |
| `device_3` | Heart Rate Monitor | -65 dBm | 2개 |
| `device_4` | Bluetooth Speaker | -70 dBm | 2개 |

#### 지원 GATT 서비스

| UUID | 이름 | 특성 |
|------|------|------|
| `180A` | Device Information | Manufacturer Name, Serial Number |
| `180D` | Heart Rate | HR Measurement (notify), Body Sensor Location |
| `180F` | Battery Service | Battery Level |
| `FFE0` | Custom Service | Custom Data |

#### 시뮬레이션 동작 세부사항

- **스캔**: 장치를 약 0.8초 간격으로 점진적으로 발견 (3.2초에 4개 완료)
- **RSSI 변동**: 매 스캔마다 ±5 dBm 범위에서 랜덤하게 변화 (현실적 신호 반영)
- **연결 상태 전환**:
  - `connect()` 호출 → `connecting` (즉시) → `connected` (1초 후)
  - `disconnect()` 호출 → `disconnecting` (즉시) → `disconnected` (0.5초 후)
- **Read 시뮬레이션**:
  - Heart Rate: 60–99 범위의 랜덤 심박수
  - Battery Level: 70–99 범위의 랜덤 배터리 잔량
  - 기타: 3바이트 랜덤 값
- **Notify 시뮬레이션**: 1초 간격으로 주기적인 값 업데이트 발행
- **리소스 관리**: `dispose()` 호출 시 모든 StreamController와 Timer 정리

---

## 8. 상태 관리 (Riverpod)

`lib/providers/ble_providers.dart`에 앱의 모든 상태가 집중 관리됩니다.

### Provider 구조

```
bleRepositoryProvider (Provider<BLERepository>)
│
├── isBluetoothEnabledProvider (FutureProvider<bool>)
├── bleIsScanningProvider (StateProvider<bool>)
├── discoveredDevicesProvider (StateProvider<List<BLEDevice>>)
├── connectedDevicesProvider (StateProvider<Set<String>>)
│
├── bleScanNotifierProvider (StateNotifierProvider<BleScanNotifier, AsyncValue<void>>)
│   ├── startScan() → discoveredDevicesProvider 업데이트
│   └── stopScan() → bleIsScanningProvider 업데이트
│
├── bleConnectionNotifierProvider (StateNotifierProvider<BleConnectionNotifier, AsyncValue<void>>)
│   ├── connect(deviceId) → connectedDevicesProvider 업데이트
│   └── disconnect(deviceId) → connectedDevicesProvider 업데이트
│
├── bleConnectionStateProvider.family(deviceId) (StreamProvider.family<BLEConnectionState, String>)
├── bleServicesProvider.family(deviceId) (FutureProvider.family<List<BLEService>, String>)
├── bleReadCharacteristicProvider.family(params) (FutureProvider.family<List<int>, ...>)
└── bleNotifyCharacteristicProvider.family(params) (StreamProvider.family<List<int>, ...>)
```

### BleScanNotifier

```dart
class BleScanNotifier extends StateNotifier<AsyncValue<void>> {
  // startScan(): 스캔 시작, 결과 스트림을 구독해 discoveredDevicesProvider 갱신
  // stopScan(): 스캔 중단, bleIsScanningProvider를 false로 전환
}
```

### BleConnectionNotifier

```dart
class BleConnectionNotifier extends StateNotifier<AsyncValue<void>> {
  // connect(String deviceId): 장치 연결, connectedDevicesProvider에 추가
  // disconnect(String deviceId): 장치 해제, connectedDevicesProvider에서 제거
}
```

### Family Provider 파라미터

`bleReadCharacteristicProvider`와 `bleNotifyCharacteristicProvider`는 다음 파라미터를 받습니다.

```dart
// 튜플 (deviceId, serviceUuid, characteristicUuid) 로 식별
final provider = bleReadCharacteristicProvider(
  (deviceId: 'device_1', serviceUuid: '180D', characteristicUuid: '2A37')
);
```

---

## 9. UI 화면

### HomeScreen — BLE 스캔 화면

**파일**: `lib/screens/home_screen.dart`

주변 BLE 장치를 스캔하고 목록으로 표시하는 메인 화면입니다.

| 컴포넌트 | 역할 |
|----------|------|
| AppBar 블루투스 아이콘 | 블루투스 활성화 상태 시각화 (파란색/회색) |
| 상태 바 | 스캔 중 여부, 발견된 장치 수 표시 |
| 장치 카드 | 이름, RSSI 값, 신호 품질(Excellent/Good/Fair/Poor), 연결 상태 배지 |
| 신호 아이콘 | 신호 강도별 색상 코드 (초록/주황/빨강) |
| FAB 버튼 | 스캔 시작/중지 토글 (활성 시 색상 변경) |
| 빈 상태 UI | 장치 미발견 시 안내 플레이스홀더 |

### DeviceDetailScreen — 장치 상세 화면

**파일**: `lib/screens/device_detail_screen.dart`

선택한 장치의 정보를 보고 GATT 서비스/특성과 상호작용하는 화면입니다.

| 컴포넌트 | 역할 |
|----------|------|
| DeviceInfoCard | 장치 이름, ID, 신호 강도, 연결 상태 표시 |
| 연결/해제 버튼 | 로딩 상태 포함 토글 버튼 |
| 서비스 섹션 | 탐색된 서비스 확장/축소 목록 |
| ServiceCard | 서비스 UUID, 이름, 포함된 특성 목록 |
| CharacteristicTile | 특성별 Read/Write/Notify 버튼 및 현재 값 표시 |
| Write 다이얼로그 | 16진수 또는 문자열 형태로 값 입력 후 전송 |
| 값 포맷 출력 | HEX와 ASCII 이중 포맷으로 바이너리 데이터 표시 |

**값 출력 형식 예시:**
```
HEX: 3A 2B 4F 1C  |  ASCII: :+O.
```

---

## 10. Mock 시뮬레이션 상세

### 스캔 동작 흐름

```
startScan() 호출
    │
    ├─ 0.0s: device_1 (Smart Watch, -45 dBm) 발견
    ├─ 0.8s: device_2 (Fitness Band, -55 dBm) 발견
    ├─ 1.6s: device_3 (Heart Rate Monitor, -65 dBm) 발견
    ├─ 2.4s: device_4 (Bluetooth Speaker, -70 dBm) 발견
    └─ 3.2s: 스캔 완료 (또는 stopScan() 호출 시 즉시 중단)

※ 각 발견 시마다 RSSI 값 ±5 범위 랜덤 변동
```

### 연결 상태 전환

```
connect('device_1') 호출
    │
    ├─ 즉시: BLEConnectionState.connecting
    └─ 1초 후: BLEConnectionState.connected

disconnect('device_1') 호출
    │
    ├─ 즉시: BLEConnectionState.disconnecting
    └─ 0.5초 후: BLEConnectionState.disconnected
```

### Smart Watch (device_1) 서비스 구성

```
Smart Watch
├── Device Information (180A)
│   ├── Manufacturer Name (2A29) [read]
│   └── Serial Number (2A25) [read]
├── Heart Rate (180D)
│   ├── HR Measurement (2A37) [notify] → 1초마다 60-99 bpm 랜덤 발행
│   └── Body Sensor Location (2A38) [read]
├── Battery Service (180F)
│   └── Battery Level (2A19) [read, notify] → 70-99% 랜덤
└── Custom Service (FFE0)
    └── Custom Data (FFE1) [read, write, notify]
```

---

## 11. 테스트

### 테스트 파일 구조

```
test/
├── widget_test.dart                      # 화면 렌더링 기본 검증
├── providers/
│   └── ble_providers_test.dart           # Provider 상태 변화 검증
└── repositories/
    └── mock_ble_repository_test.dart     # Repository 동작 검증
```

### Widget 테스트

```dart
// 앱 로드 시 기본 UI 요소 존재 여부 확인
testWidgets('HomeScreen renders correctly', (tester) async {
  // "BLE Device Scanner" 제목 렌더링 확인
  // "Start Scan" 버튼 존재 확인
});
```

### Provider 테스트 항목

| 테스트 케이스 | 검증 내용 |
|---------------|-----------|
| `isBluetoothEnabledProvider` | `true` 반환 |
| `bleIsScanningProvider` | 초기 상태 `false` |
| `discoveredDevicesProvider` | 초기 상태 빈 목록 |
| `connectedDevicesProvider` | 초기 상태 빈 집합 |
| `BleScanNotifier.startScan()` | 스캔 시작 후 장치 목록 채워짐 |
| `BleScanNotifier.stopScan()` | `isScanning`이 `false`로 전환 |
| `BleConnectionNotifier.connect()` | 장치 ID가 `connectedDevicesProvider`에 추가 |
| `BleConnectionNotifier.disconnect()` | 장치 ID가 `connectedDevicesProvider`에서 제거 |
| 다중 연결 | 여러 장치 동시 연결 상태 유지 |
| `bleServicesProvider` | 연결 후 서비스 목록 반환 |
| `bleConnectionStateProvider` | 스트림에서 상태 값 방출 확인 |

### Repository 테스트 항목

| 테스트 케이스 | 검증 내용 |
|---------------|-----------|
| `isBluetoothEnabled()` | `true` 반환 |
| `startScan()` / `stopScan()` | `isScanning` 상태 전환 |
| `scanResults` 스트림 | 장치 방출, RSSI 범위 검증 |
| 중복 장치 방지 | 동일 ID 장치 중복 추가 방지 |
| `connect()` / `disconnect()` | `isConnected()` 상태 변화 |
| `connectionState()` 스트림 | 상태 전환 순서 검증 |
| `discoverServices()` | 미연결 시 예외, 연결 시 서비스 반환 |
| 서비스 수 검증 | Smart Watch 4개, Fitness Band 3개 등 |
| `readCharacteristic()` | 미연결 시 예외, HR 범위(60-99) 검증 |
| `writeCharacteristic()` | 미연결 시 예외, 연결 시 정상 완료 |
| `notifyCharacteristic()` | 주기적 값 방출 확인 |

### 테스트 실행

```bash
# 전체 테스트 실행
flutter test

# 특정 파일 테스트
flutter test test/repositories/mock_ble_repository_test.dart

# 커버리지 포함
flutter test --coverage
```

---

## 12. 시작하기

### 요구사항

- Flutter SDK 3.x 이상
- Dart SDK 3.0.0 이상
- Android Studio / VS Code (Flutter 플러그인 포함)

### 설치 및 실행

```bash
# 1. 저장소 클론
git clone https://github.com/your-username/flutter_ble_mock.git
cd flutter_ble_mock

# 2. 의존성 설치
flutter pub get

# 3. 코드 생성 (Riverpod annotation 사용 시)
dart run build_runner build

# 4. 앱 실행
flutter run

# 5. 특정 플랫폼으로 실행
flutter run -d ios
flutter run -d android
flutter run -d macos
flutter run -d chrome
```

### 코드 생성 (변경 감지 모드)

```bash
dart run build_runner watch --delete-conflicting-outputs
```

---

## 13. 플랫폼 지원

| 플랫폼 | 지원 여부 | 비고 |
|--------|-----------|------|
| Android | ✅ | Kotlin, Gradle |
| iOS | ✅ | Xcode, Swift/ObjC |
| macOS | ✅ | 데스크탑 앱 |
| Linux | ✅ | 데스크탑 앱 |
| Windows | ✅ | 데스크탑 앱 |
| Web | ✅ | Chrome 기반 |

> Mock 구현이므로 실제 BLE 하드웨어 권한 없이도 모든 플랫폼에서 동작합니다.

---

## 14. 활용 방안

### 실제 BLE 라이브러리로 교체

`MockBLERepository` 대신 실제 BLE 라이브러리 구현체를 만들어 교체하면 됩니다.

```dart
// 1. BLERepository를 구현하는 실제 클래스 생성
class FlutterBluePlusRepository implements BLERepository {
  // flutter_blue_plus 라이브러리를 사용하여 구현
}

// 2. bleRepositoryProvider에서 구현체 교체
final bleRepositoryProvider = Provider<BLERepository>((ref) {
  // MockBLERepository() 대신 실제 구현체 사용
  return FlutterBluePlusRepository();
});
```

### 학습 활용

- Riverpod의 `StateNotifier`, `FutureProvider`, `StreamProvider`, `family` 패턴 학습
- Flutter에서의 Stream 기반 실시간 UI 업데이트 패턴 이해
- Repository 패턴을 통한 테스트 가능한 코드 구조 설계
- BLE GATT 프로토콜 구조 (Service → Characteristic → Property) 이해

### 프로토타입 개발

실제 하드웨어가 없는 상황에서도 스마트워치, 피트니스 밴드, 심박 모니터, 블루투스 스피커 등의 BLE 앱 UI와 로직을 완전히 개발하고 검증할 수 있습니다.

---

## 라이선스

이 프로젝트는 학습 및 데모 목적으로 공개되어 있습니다.
