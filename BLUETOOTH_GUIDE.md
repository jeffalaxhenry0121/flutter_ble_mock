# Flutter × 블루투스 완전 정복 가이드

> "스마트폰이 블루투스 이어폰을 찾아서 연결하는 과정, 앱으로는 어떻게 만들까?"  
> 코딩을 몰라도, 블루투스를 몰라도 괜찮아요. 처음부터 차근차근 설명해드릴게요.

---

## 먼저, 블루투스가 뭔가요?

블루투스는 **선 없이 두 기기가 대화하는 기술**이에요.

예전에는 이어폰을 쓰려면 잭을 꽂아야 했죠. 블루투스는 그 "선"을 "눈에 안 보이는 전파"로 바꾼 거예요.

```
📱 스마트폰  ←─────────────→  🎧 이어폰
            (전파로 연결)
```

우리가 만드는 앱은 이 "대화하는 과정"을 코드로 직접 제어해요.

---

## BLE가 뭔가요? 일반 블루투스랑 뭐가 달라요?

블루투스에는 두 종류가 있어요.

| | 일반 블루투스 | BLE (Bluetooth Low Energy) |
|---|---|---|
| 별명 | 클래식 블루투스 | 저전력 블루투스 |
| 주 용도 | 이어폰, 스피커 (소리 전달) | 스마트워치, 심박 센서 (데이터 전달) |
| 전력 소모 | 많음 | 매우 적음 (건전지로 몇 년도 가능) |
| 속도 | 빠름 | 느림 (대신 전력 아낌) |

이 앱은 **BLE** 를 다뤄요.  
스마트워치, 피트니스 밴드, 혈압계, 체온계처럼  
**작은 데이터를 오래오래 보내는 기기들**이 모두 BLE를 씁니다.

---

## 전체 흐름을 한눈에

블루투스 기기와 연결하는 과정은 딱 **5단계**예요.

```
1단계         2단계         3단계         4단계         5단계
[준비]  →→→  [스캔]  →→→  [연결]  →→→  [탐색]  →→→  [통신]

블루투스       주변 기기      기기와        기기의        데이터
켜져 있나?     찾기          악수하기       기능 목록     주고받기
                            (연결)        확인하기
```

마치 **처음 가는 카페**에 가는 과정과 똑같아요.

```
1. 지갑 있나 확인  →  2. 카페 찾기  →  3. 문 열고 들어가기  →  4. 메뉴판 보기  →  5. 주문하기
```

이제 하나씩 자세히 볼게요!

---

## 1단계: 준비 — 블루투스가 켜져 있나요?

### 일상 비유

카페에 가기 전에 지갑이 있는지 확인하는 것처럼,  
앱은 먼저 **스마트폰의 블루투스가 켜져 있는지** 확인해요.

꺼져 있으면? → 앱이 "블루투스를 켜 주세요!"라고 알려줘야 해요.

### 이 앱의 코드

`lib/repositories/ble_repository.dart`

```dart
Future<bool> isBluetoothEnabled();
```

`lib/providers/ble_providers.dart`

```dart
final isBluetoothEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(bleRepositoryProvider).isBluetoothEnabled();
});
```

### 화면에서는?

`lib/screens/home_screen.dart`의 AppBar 오른쪽 아이콘이에요.

```
블루투스 켜짐  →  파란 아이콘 🔵
블루투스 꺼짐  →  회색 아이콘 ⚫
```

### Mock에서는 어떻게?

실제 스마트폰의 블루투스 상태를 확인하는 대신,  
`MockBLERepository`는 **항상 "켜져 있음"(true)을 반환**해요.

```dart
// lib/repositories/mock_ble_repository.dart
Future<bool> isBluetoothEnabled() async {
  await Future.delayed(const Duration(milliseconds: 200)); // 실제 확인하는 척 200ms 대기
  return true; // 항상 켜져 있다고 대답
}
```

---

## 2단계: 스캔 — 주변 기기 찾기

### 일상 비유

동네를 걸어다니면서 **어떤 카페가 있나 둘러보는 것**이에요.

BLE 기기들은 항상 "나 여기 있어요!"라는 신호를 주변에 보내고 있어요.  
이걸 **광고(Advertising)** 라고 해요.  
스캔은 그 신호를 받아서 "아, 저기 스마트워치가 있구나!" 하고 감지하는 과정이에요.

```
스마트워치: "나 여기 있어요! 나 여기 있어요! 나 여기 있어요!"
                        ↓
           📡 스마트폰이 신호를 수신
                        ↓
           앱: "스마트워치 발견! RSSI: -45 dBm"
```

### RSSI가 뭔가요?

**RSSI(신호 강도)** 는 쉽게 말해 "얼마나 가까이 있나요?"예요.

```
-30 dBm   아주 가까움 (바로 옆)     ████████ Excellent
-50 dBm   가까움                   ██████   Very Good  
-70 dBm   보통                     ████     Good
-90 dBm   멀거나 장애물 있음         ██       Fair / Poor
```

숫자가 0에 가까울수록(절댓값이 작을수록) 신호가 강해요.  
-30이 -90보다 훨씬 가까운 거예요.

### 이 앱의 코드 흐름

```
사용자가 "Start Scan" 버튼 탭
        ↓
BleScanNotifier.startScan() 호출
        ↓
bleIsScanningProvider → true (스캔 중 표시)
        ↓
BLERepository.startScan() 실행
        ↓
scanResults 스트림에서 기기가 하나씩 도착
        ↓
discoveredDevicesProvider 목록에 추가
        ↓
화면이 자동으로 새로 그려짐 (목록에 카드 추가)
```

### Mock에서는 어떻게?

실제로는 전파를 받아야 하지만, Mock은 **0.8초마다 장치를 하나씩 꺼내 놓는** 방식으로 시뮬레이션해요.

```dart
// lib/repositories/mock_ble_repository.dart
_scanTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
  // 0.8초마다 장치 목록에서 하나씩 꺼낸다
  final device = _mockDevices[deviceIndex++];
  _scanController.add([...발견된 장치들]);
  //             ↑
  //    이 값이 scanResults 스트림을 통해 앱으로 전달됨
});
```

타임라인으로 보면:
```
0.0초: 스캔 시작
0.8초: Smart Watch 발견!        [Smart Watch]
1.6초: Fitness Band 발견!       [Smart Watch, Fitness Band]
2.4초: Heart Rate Monitor 발견! [Smart Watch, Fitness Band, Heart Rate Monitor]
3.2초: Bluetooth Speaker 발견!  [Smart Watch, Fitness Band, Heart Rate Monitor, Bluetooth Speaker]
```

---

## 3단계: 연결 — 기기와 악수하기

### 일상 비유

카페를 발견했어요. 이제 **문을 열고 들어가는** 과정이에요.

BLE 연결은 단순히 "나 연결됐어!"가 아니라,  
**악수처럼 여러 단계를 거쳐요**.

```
앱: "연결해도 될까요?"
기기: "네, 잠깐만요..."
기기: "자리 준비됐어요. 들어오세요!"
앱: "감사합니다, 들어갑니다!"
```

### 연결 상태 4단계

```
disconnected  ──→  connecting  ──→  connected
   (미연결)          (연결 중)         (연결됨)
                                         │
disconnected  ←──  disconnecting  ←──────┘
   (미연결)          (해제 중)
```

### 이 앱의 코드 흐름

```dart
// lib/repositories/mock_ble_repository.dart
Future<void> connect(String deviceId) async {
  // 1. 즉시 "연결 시도 중" 상태 알림
  controller.add(BLEConnectionState.connecting);

  // 2. 실제 BLE 핸드셰이크 시간 시뮬레이션 (0.8초)
  await Future.delayed(const Duration(milliseconds: 800));

  // 3. 연결 완료 처리
  _connectedDevices.add(deviceId);
  controller.add(BLEConnectionState.connected);
}
```

### 화면에서는?

`device_detail_screen.dart`의 연결 버튼이에요.

```
미연결 상태:  [ 🔗 Connect   ]  ← 파란 버튼
연결 시도 중: [  ○ (스피너)  ]  ← 로딩
연결 완료:    [ 🔗 Disconnect ]  ← 빨간 버튼으로 바뀜
```

---

## 4단계: 탐색 — 기기의 기능 목록 확인하기

### 일상 비유

카페에 들어왔어요. 이제 **메뉴판을 보는** 단계예요.

BLE 기기는 자신이 할 수 있는 기능들을 **서비스(Service)** 와 **특성(Characteristic)** 으로 분류해서 알려줘요.

```
카페 메뉴판 = 서비스 목록
  ☕ 커피 메뉴판 = "Heart Rate" 서비스
    - 아메리카노 = "Heart Rate Measurement" 특성
    - 카페라떼   = "Body Sensor Location" 특성
  🥤 음료 메뉴판 = "Battery" 서비스
    - 주스      = "Battery Level" 특성
```

### 서비스(Service)란?

서비스는 **기능들의 묶음**이에요.

```
Heart Rate 서비스 (UUID: 180D)
  └── 심박수 측정 특성
  └── 센서 위치 특성

Battery 서비스 (UUID: 180F)
  └── 배터리 잔량 특성
```

UUID는 서비스의 **주민등록번호** 같은 거예요.  
어느 회사 제품이든 "180D"라고 하면 무조건 "심박수 서비스"를 뜻해요.  
전 세계 공통 약속이에요!

### 특성(Characteristic)이란?

특성은 서비스 안의 **실제 데이터 항목** 하나하나예요.

각 특성에는 할 수 있는 작업이 정해져 있어요:

```
📖 Read   → 값을 한 번 읽어올 수 있어요  (메뉴 가격 확인)
✏️ Write  → 값을 보낼 수 있어요          (주문하기)
🔔 Notify → 바뀔 때마다 자동으로 알려줘요 (진동벨 받기)
```

### 이 앱의 서비스 구성

```
Smart Watch
├── Device Information (180A) — 제조사 정보
│   ├── Manufacturer Name [📖 Read]   → "MockCorp"
│   └── Serial Number     [📖 Read]   → "SN-12345"
│
├── Heart Rate (180D) — 심박수
│   ├── HR Measurement    [📖 Read] [🔔 Notify]  → [0x00, 72]
│   └── Body Sensor Loc.  [📖 Read]              → [0x01] (가슴)
│
├── Battery (180F) — 배터리
│   └── Battery Level     [📖 Read] [🔔 Notify]  → [85] (85%)
│
└── Custom Service (FFE0) — 커스텀
    └── Custom Data       [📖 Read] [✏️ Write] [🔔 Notify]
```

### 이 앱의 코드 흐름

```dart
// lib/repositories/mock_ble_repository.dart
Future<List<BLEService>> discoverServices(String deviceId) async {
  // 연결 안 됐으면 오류
  if (!isConnected(deviceId)) {
    throw BLEException('Device not connected');
  }

  // 실제 탐색 시간 시뮬레이션 (0.5초)
  await Future.delayed(const Duration(milliseconds: 500));

  // 장치에 맞는 서비스 목록 반환
  return deviceRecord.serviceIds.map(_buildService).toList();
}
```

---

## 5단계: 통신 — 데이터 주고받기

드디어 실제로 **데이터를 주고받는** 단계예요!  
세 가지 방식이 있어요.

---

### 5-1. Read — 값 한 번 읽기

#### 일상 비유

카페에서 "이 메뉴 얼마예요?" 하고 **한 번 물어보는** 것이에요.  
물어봤을 때만 대답해줘요.

```
앱: "배터리 잔량 알려주세요"
기기: "85%예요"
(끝, 다음에 또 물어봐야 알 수 있어요)
```

#### 코드와 화면

```dart
// 📖 Read 버튼을 탭하면 실행
Future<void> _read() async {
  final value = await ref.read(bleRepositoryProvider).readCharacteristic(
    deviceId: 'device_1',
    serviceUuid: '180F',
    characteristicUuid: '2A19', // Battery Level UUID
  );
  // value = [85]  ← 1바이트: 85%를 의미
}
```

화면에는 이렇게 표시돼요:

```
Battery Level
2A19
HEX: 55  |  ASCII: U
      ↑               ↑
   85를 16진수로    문자로는 'U'
```

#### 바이트가 뭔가요?

컴퓨터는 모든 데이터를 숫자로 저장해요.  
85%는 숫자 85 = 16진수로 55 = ASCII 문자로 'U'  
다 같은 값인데 표현 방식만 달라요!

```
10진수:  85
16진수:  55   (앞자리 5 × 16 + 뒷자리 5 = 85)
ASCII:   U    (ASCII 코드 85번 문자)
```

---

### 5-2. Write — 값 보내기

#### 일상 비유

카페에서 "아메리카노 한 잔 주세요"라고 **주문하는** 것이에요.  
앱이 기기에게 명령을 보내는 거죠.

```
앱: "LED 켜줘!"  →  기기: (LED를 켬)
앱: "모터 돌려!"  →  기기: (모터 작동)
```

#### 코드와 화면

Write 버튼을 탭하면 입력 창이 뜨고,  
입력한 텍스트가 바이트로 변환되어 전송돼요.

```dart
// ✏️ Write 버튼 → 다이얼로그 → Write 확인 버튼 탭하면 실행
Future<void> _write(List<int> value) async {
  await ref.read(bleRepositoryProvider).writeCharacteristic(
    deviceId: 'device_1',
    serviceUuid: 'FFE0',
    characteristicUuid: 'FFE1', // Custom Data UUID
    value: value,               // [104, 101, 108, 108, 111] = "hello"
  );
}
```

"hello"를 입력하면:

```
h → 104
e → 101
l → 108
l → 108
o → 111
━━━━━━━━━━━━━━━━
전송 데이터: [104, 101, 108, 108, 111]
```

---

### 5-3. Notify — 실시간 알림 받기

#### 일상 비유

카페에서 진동벨을 받는 것이에요.  
준비되면 카페가 **알아서 나에게 신호를 보내줘요**.  
매번 물어볼 필요 없이 **변화가 생기면 자동으로 알려줘요**.

```
앱: "심박수 바뀔 때마다 알려줘!"
1초 후 기기: "72 bpm이에요"
1초 후 기기: "74 bpm이에요"
1초 후 기기: "71 bpm이에요"
...계속...
```

#### Read vs Notify 차이

```
Read (물어보기 방식):
  앱 ────질문────→ 기기
  앱 ←────대답──── 기기
  (매번 물어봐야 알 수 있음)

Notify (알림 방식):
  앱: "구독할게요!"
  기기 ──알림──→ 앱  (1초마다)
  기기 ──알림──→ 앱  (1초마다)
  기기 ──알림──→ 앱  (1초마다)
  앱: "구독 취소할게요"
```

#### 코드와 화면

```dart
// 🔔 Notify 버튼을 탭하면 _isNotifying = true → _NotifyValue 위젯 등장
// _NotifyValue 안에서:
Stream<List<int>> notifyStream = repository.notifyCharacteristic(
  deviceId: 'device_1',
  serviceUuid: '180D',
  characteristicUuid: '2A37', // Heart Rate Measurement
);

// 스트림을 구독하면 1초마다 새 값이 도착:
// [0x00, 72]  → "NOTIFY: 00 48"
// [0x00, 74]  → "NOTIFY: 00 4a"
// [0x00, 71]  → "NOTIFY: 00 47"
```

화면에는 이렇게 실시간으로 바뀌어요:

```
Heart Rate Measurement
2A37
NOTIFY: 00 48   ← 1초마다 숫자가 바뀜!
```

---

## 전체 흐름 한 번 더 — 드라마처럼 보기

```
👩 사용자가 앱을 켠다
        ↓
📱 앱: "블루투스 켜져 있나요?"
🔵 OS: "네, 켜져 있어요"
        ↓
👩 "Start Scan" 버튼 탭!
        ↓
📡 앱이 주변에 귀를 기울인다
⌚ Smart Watch: "나 여기 있어요! (RSSI: -45 dBm)"
🏃 Fitness Band: "나 여기 있어요! (RSSI: -55 dBm)"
💓 Heart Rate Monitor: "나 여기 있어요!"
🔊 Bluetooth Speaker: "나 여기 있어요!"
        ↓
👩 "Smart Watch" 카드를 탭!
        ↓
📱 앱: "Smart Watch랑 연결 중..."  [스피너 표시]
⌚ Smart Watch: (악수 준비)
📱 앱: "연결됐어요!"  [Connected 뱃지]
        ↓
📱 앱이 자동으로 메뉴판을 가져온다 (서비스 탐색)
⌚ Smart Watch: "Device Info, Heart Rate, Battery, Custom 서비스 있어요"
        ↓
👩 "Heart Rate" 서비스를 펼친다
        ↓
👩 "HR Measurement" 오른쪽 🔔 버튼 탭!
        ↓
⌚ Smart Watch: "72 bpm"  →  NOTIFY: 00 48
⌚ Smart Watch: "74 bpm"  →  NOTIFY: 00 4a
⌚ Smart Watch: "71 bpm"  →  NOTIFY: 00 47
        ↓
👩 만족! 🔔 버튼 다시 탭해서 구독 취소
        ↓
👩 "Disconnect" 버튼 탭
        ↓
📱 앱: "연결 해제 중..."
⌚ Smart Watch: "안녕히 가세요!"
📱 앱: "연결이 끊어졌어요"
```

---

## 이 앱의 특별한 점 — Mock 구조

실제 BLE 앱을 만들 때 가장 불편한 점은  
**개발할 때마다 실제 블루투스 기기가 있어야 한다**는 거예요.

이 앱은 그 문제를 **Mock(가짜)** 으로 해결했어요.

```
실제 앱:
  Flutter 코드 ──→ flutter_blue_plus ──→ 스마트폰 BLE 칩 ──→ 실제 기기

이 앱:
  Flutter 코드 ──→ MockBLERepository ──→ 가상 기기 4대
                   (코드로만 존재)        (코드로만 존재)
```

### 인터페이스 교체가 쉬운 이유

```
Provider ──→ BLERepository (약속)
                  ↑
         이 "약속"만 지키면
         누가 구현해도 됨!

MockBLERepository     ← 지금 사용 중 (개발/테스트용)
FlutterBluePlusRepository ← 나중에 교체 (실제 기기 연동)
ReactivebleRepository ← 다른 라이브러리 사용도 가능
```

이걸 **인터페이스(Interface)** 패턴이라고 해요.  
마치 콘센트처럼, 모양(약속)만 같으면 어떤 기기든 꽂을 수 있어요!

```
콘센트 (BLERepository)
  ├── 선풍기 (MockBLERepository)
  ├── 청소기 (FlutterBluePlusRepository)
  └── 충전기 (ReactiveBleRepository)
```

---

## 자주 하는 질문

### Q. BLE 기기를 연결할 때 왜 MAC 주소가 필요한가요?

MAC 주소는 **블루투스 기기의 주민등록번호**예요.

세상에 수없이 많은 스마트워치가 있는데,  
"Smart Watch 연결해줘"라고 하면 어떤 워치에 연결해야 할지 모르잖아요.

그래서 `AA:BB:CC:11:22:33` 같은 **유일한 주소**로 정확히 특정해요.

> iOS에서는 MAC 주소를 보여주지 않아요.  
> 개인정보 보호를 위해 Apple이 임의의 UUID를 대신 제공해요.  
> (매번 바뀌어서 추적이 어려워요)

### Q. 연결이 끊기면 어떻게 되나요?

BLE 기기들은 범위(보통 10~30m)를 벗어나거나 배터리가 없어지면 자동으로 연결이 끊겨요.  
좋은 앱은 이 상황을 감지해서 자동으로 재연결을 시도해요.  
이 앱의 `connectionState` 스트림이 바로 그 역할을 해요.

### Q. 왜 데이터가 숫자(바이트)로 오나요?

블루투스는 아주 작은 데이터를 최대한 빠르게 보내야 해요.  
그래서 "배터리 85%" 대신 그냥 숫자 `85` 하나를 보내는 거예요.  
앱이 그 숫자의 의미를 해석하는 역할을 해요.

### Q. Notify는 얼마나 자주 업데이트되나요?

기기마다 달라요.  
심박수 센서는 보통 1초마다,  
가속도 센서는 10분의 1초마다 값을 보내기도 해요.  
이 앱의 Mock은 **1초마다** 값을 보내도록 설정되어 있어요.

---

## 한 줄 요약

```
블루투스 켜기 → 주변 기기 스캔 → 원하는 기기에 연결
→ 서비스/특성 목록 확인 → Read로 읽기 / Write로 보내기 / Notify로 구독
```

이 다섯 단계가 스마트워치 앱, 혈압계 앱, 스마트 잠금장치 앱…  
모든 BLE 앱의 공통 뼈대예요. 🎉
