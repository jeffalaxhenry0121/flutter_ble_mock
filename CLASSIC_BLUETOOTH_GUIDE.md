# Classic Bluetooth 완전 정복 가이드

> "BLE랑 이름이 비슷한데 Classic Bluetooth는 뭐가 달라요?"  
> 에어팟, 차량 오디오, 아두이노 통신… 우리 주변의 수많은 기기가 Classic BT를 씁니다.  
> 차이점과 연결 과정을 처음부터 쉽게 설명해드릴게요.

---

## 먼저, BLE와 Classic BT는 어떻게 다른가요?

한 건물 안에 두 종류의 직원이 있다고 생각해보세요.

```
Classic BT 직원:
  "저는 말을 빠르게 많이 할 수 있어요.
   대신 배터리를 좀 많이 써요.
   음악도 틀고, 전화도 받고, 파일도 보낼 수 있어요."

BLE 직원:
  "저는 말을 조금씩 하지만 건전지 하나로 몇 년도 버텨요.
   주로 센서 데이터처럼 작은 정보만 주고받아요."
```

| 비교 항목 | Classic BT (이 가이드) | BLE |
|----------|----------------------|-----|
| 전력 소모 | 많음 | 매우 적음 |
| 전송 속도 | 빠름 (최대 3 Mbps) | 느림 (최대 2 Mbps) |
| 주요 용도 | 이어폰, 스피커, 파일전송, 아두이노 | 스마트워치, 센서, 의료기기 |
| 페어링 | 반드시 필요 | 선택 사항 |
| 통신 방식 | 소켓 (원시 바이트 스트림) | GATT (서비스/특성 구조) |
| 탐색 속도 | 느림 (8~12초) | 빠름 (1~3초) |

---

## Classic BT의 "프로파일"이란?

BLE에서는 모든 장치가 동일한 GATT 규칙을 따르지만,
Classic BT는 **용도별로 완전히 다른 규칙(프로파일)** 을 사용해요.

마치 회사에서 직무마다 일하는 방식이 다른 것처럼요.

```
SPP  (직렬 포트)    → 아두이노, IoT 모듈과 데이터 통신
                      "예전 컴퓨터 COM 포트를 무선으로!"

A2DP (고음질 오디오) → 블루투스 이어폰, 스피커
                      "MP3를 무선으로 전송!"

HFP  (핸즈프리)     → 차량 스피커, 블루투스 헤드셋 통화
                      "운전 중 전화를 손 없이!"

HID  (입력 장치)    → 블루투스 키보드, 마우스, 게임패드
                      "키보드 신호를 무선으로!"

OPP  (파일 전송)    → 사진, 문서 파일 전송
                      "옛날 핸드폰 파일 주고받기!"
```

이 앱에서 시뮬레이션하는 장치들:

| 장치 | MAC 주소 | 프로파일 | 기능 |
|------|----------|----------|------|
| Arduino Nano BT | 00:11:22:33:44:55 | SPP | 온도/습도 센서 데이터 |
| Windows Laptop | AA:BB:CC:00:11:22 | SPP + OPP | 상태 메시지 + 파일 전송 |
| BT Keyboard | DE:AD:BE:EF:00:01 | HID | 키보드 입력 (미리 페어링됨) |
| Car Head Unit | 11:22:33:AA:BB:CC | A2DP + HFP | 음악 + 핸즈프리 (미리 페어링됨) |

---

## 전체 흐름 — BLE와 비교해서 보기

```
[BLE 흐름]                    [Classic BT 흐름]

1. 블루투스 켜기               1. 블루투스 켜기
       ↓                             ↓
2. 스캔 (1~3초)               2. 탐색/Inquiry (8~12초) ← 훨씬 느림!
       ↓                             ↓
3. 연결                        3. 페어링  ← BLE에 없는 단계!
       ↓                             ↓
4. GATT 서비스 탐색             4. 연결 (SPP 소켓 열기)
       ↓                             ↓
5. 특성 Read/Write/Notify       5. 데이터 송수신 (원시 바이트)
```

**가장 큰 차이: Classic BT는 "페어링"이 반드시 필요해요!**

---

## 1단계: 준비 — 블루투스 켜기

BLE와 동일해요. 코드도 거의 같습니다.

```dart
// lib/providers/bt_providers.dart
final btIsBluetoothEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(btRepositoryProvider).isBluetoothEnabled();
});
```

---

## 2단계: 탐색 (Inquiry) — BLE 스캔보다 훨씬 느려요

### 왜 느린가요?

BLE 기기는 항상 "나 여기 있어요!"를 외치고 있어서 금방 발견되지만,
Classic BT 기기는 **평소엔 조용히 있다가** 탐색 신호가 오면 그때서야 대답해요.

```
BLE 스캔:
  폰: 귀를 기울인다
  기기들: "나 여기!", "나 여기!", "나 여기!" (항상 외침)
  결과: 1~3초면 발견

Classic BT 탐색(Inquiry):
  폰: "주변에 누구 있어요?" (신호 발송)
  기기들: (신호 수신 후 잠시 대기...)
  기기1: "네, 저 여기요!"
  기기2: "저도요!"  ← 타이밍이 제각각
  결과: 8~12초가 걸림
```

### 이 앱의 시뮬레이션

```
0.0초: 탐색 시작
1.5초: Arduino Nano BT 발견!
3.0초: Windows Laptop 발견!
4.5초: BT Keyboard 발견! (이미 페어링됨 ✓)
6.0초: Car Head Unit 발견! (이미 페어링됨 ✓)
```

### 코드 흐름

```dart
// 탐색 시작
await btRepository.startDiscovery();

// discoveryResults 스트림에서 장치가 하나씩 도착
btRepository.discoveryResults.listen((devices) {
  // 발견된 장치 목록 화면에 표시
});
```

---

## 3단계: 페어링 — Classic BT만의 특별한 단계

### 일상 비유

처음 만나는 사람과 명함을 교환하는 것이에요.

```
한 번 명함 교환 (페어링) → 이후엔 명함 없이도 서로 알아볼 수 있음

BT 장치 페어링:
  폰: "비밀번호(PIN)가 뭔가요?"
  장치: "1234예요" (또는 자동으로 교환)
  폰: "확인됐어요. 이제 서로 기억해요!"
  → 스마트폰 "페어링된 기기 목록"에 영구 저장
```

### 페어링이 필요한 이유

보안 때문이에요.  
아무나 내 블루투스 키보드에 연결해서 내가 치는 글자를 훔쳐보면 안 되잖아요.  
페어링은 "이 스마트폰만 이 장치에 연결할 수 있다"는 약속을 만드는 과정이에요.

### 페어링 상태 3단계

```
notPaired ──→ pairing ──→ paired
(처음 만남)   (명함 교환 중)   (친구 등록!)
```

### 이 앱의 코드

```dart
// lib/repositories/mock_bt_repository.dart
Future<void> pair(String address) async {
  controller.add(BTPairState.pairing); // 즉시: "페어링 중..."
  await Future.delayed(Duration(milliseconds: 1500)); // PIN 교환 시뮬레이션
  _pairedAddresses.add(address);
  controller.add(BTPairState.paired);  // 완료: "페어링됨!"
}
```

### 페어링된 장치는 기억된다

페어링이 완료되면 스마트폰 OS가 영구적으로 기억해요.  
앱을 종료했다 켜도, 심지어 스마트폰을 재부팅해도  
**페어링 목록에서 사라지지 않아요.**

```dart
// 앱 시작 시 이미 페어링된 장치 목록 불러오기
final pairedBTDevicesProvider = FutureProvider<List<BTDevice>>((ref) {
  return ref.watch(btRepositoryProvider).getPairedDevices();
});
```

이 앱의 Mock에서는 `BT Keyboard`와 `Car Head Unit`이 미리 페어링된 상태로 시작해요.

---

## 4단계: 연결 — SPP 소켓 열기

### 일상 비유

명함(페어링)을 교환했으니 이제 **전화를 거는** 단계예요.

Classic BT 연결은 전화 통화와 비슷해요:
- 연결되면 두 쪽이 자유롭게 말을 주고받을 수 있어요
- 끊기 전까지 계속 연결이 유지돼요

### SPP 소켓이란?

예전 컴퓨터에 COM 포트(직렬 포트)가 있었어요.  
Arduino를 컴퓨터에 연결하면 `COM3`, `COM4` 같은 포트가 생기는 거 보셨나요?

SPP는 그 COM 포트를 **무선(블루투스)으로** 흉내낸 거예요.  
그래서 "가상 직렬 포트"라고도 불러요.

```
예전 (유선):
  컴퓨터 ──── 시리얼 케이블 ──── Arduino
  COM3 포트                    TX/RX 핀

지금 (무선 SPP):
  스마트폰 ~~~~~ 블루투스 ~~~~~ Arduino BT 모듈
  가상 소켓                    HC-05, HC-06 등
```

### 연결 상태 전환

```
disconnected ─→ connecting (즉시) ─→ connected (1초 후)
```

---

## 5단계: 데이터 송수신 — 원시 바이트 스트림

### BLE vs Classic BT 통신 방식 비교

```
BLE 통신 (GATT 구조):
  ┌─ Heart Rate 서비스
  │   ├─ HR Measurement 특성  [Read][Notify]
  │   └─ Body Sensor Location [Read]
  └─ Battery 서비스
      └─ Battery Level        [Read][Notify]
  
  → 데이터에 "이름표"가 붙어있어서 뭔지 알 수 있음

Classic BT 통신 (원시 스트림):
  기기 → [0x54 0x45 0x4D 0x50 0x3A 0x32 0x35 0x0D 0x0A]
  
  → 그냥 바이트가 줄줄 흘러옴 (프로토콜을 직접 해석해야 함!)
```

### 이 앱에서 Arduino가 보내는 데이터

Arduino는 2초마다 이런 형식으로 데이터를 보내요:

```
TEMP:24.5\r\n     ← 온도 24.5도
HUM:62\r\n        ← 습도 62%
LIGHT:340\r\n     ← 조도 340
```

`\r\n`은 "줄 바꿈" 신호예요. 시리얼 통신에서는 이 신호로 메시지의 끝을 구분해요.

### 데이터 수신 코드

```dart
// lib/repositories/mock_bt_repository.dart
// 연결 후 2초마다 자동으로 데이터 방출
_receiveTimers[address] = Timer.periodic(Duration(seconds: 2), (_) {
  final message = 'TEMP:24.5\r\n';
  controller.add(BTMessage(
    data: message.codeUnits,   // 문자열을 바이트 배열로 변환
    timestamp: DateTime.now(),
    isFromDevice: true,
  ));
});
```

### 데이터 송신 코드

```dart
// 텍스트 명령을 바이트로 변환해 전송
Future<void> _send(String text) async {
  final data = '$text\r\n'.codeUnits; // 텍스트 → 바이트 배열
  await repository.sendData(address, data);
}

// 예: "LED_ON" 전송 → Arduino가 LED를 켬
_send('LED_ON');
```

### SPP 터미널 화면

이 앱의 SPP 터미널은 **채팅처럼** 메시지를 표시해요:

```
┌─────────────────────────────────┐
│ SPP Terminal              🗑️    │
├─────────────────────────────────┤
│ 📡 Device                       │
│  TEMP:24.5                      │
│  10:23:45                       │
│                                 │
│                  📱 You         │
│               LED_ON            │
│               10:23:47          │
│                                 │
│ 📡 Device                       │
│  HUM:62                         │
│  10:23:48                       │
├─────────────────────────────────┤
│ [Type a command...    ] [➤]     │
└─────────────────────────────────┘
```

---

## 전체 흐름 — 드라마처럼 보기

```
👩 앱의 "Classic BT" 탭을 탭한다
        ↓
📱 앱이 이미 페어링된 장치 목록을 불러온다
    → BT Keyboard (페어링됨 ✓)
    → Car Head Unit (페어링됨 ✓)
        ↓
👩 "Discover" 버튼을 탭한다
        ↓
📡 앱이 주변에 "누구 있어요?" 신호 발송
🔧 Arduino: (1.5초 후) "저 여기요!"
💻 Laptop: (3.0초 후) "저도요!"
⌨️ Keyboard: (4.5초 후) "저 이미 아는 사이잖아요!"
🚗 Car: (6.0초 후) "저도 아는 사이요!"
        ↓
👩 "Arduino Nano BT" 카드를 탭한다
        ↓
📱 Arduino가 페어링 안 됐음 → "Pair Device" 버튼 표시
        ↓
👩 "Pair Device" 버튼 탭!
        ↓
⚙️ PIN 코드 교환 중... (1.5초)
✅ 페어링 완료! → "Connect (SPP)" 버튼 등장
        ↓
👩 "Connect (SPP)" 버튼 탭!
        ↓
🔌 SPP 소켓 열리는 중... (1초)
✅ 연결 완료! → SPP Terminal 등장
        ↓
📡 Arduino: "TEMP:24.5\r\n"  →  채팅창 왼쪽에 표시
📡 Arduino: "HUM:62\r\n"     →  채팅창 왼쪽에 표시
        ↓
👩 입력창에 "LED_ON" 입력 후 전송 버튼 탭
        ↓
📱 → Arduino: [76 45 44 5F 4F 4E 0D 0A]  →  채팅창 오른쪽에 표시
        ↓
👩 만족! "Disconnect" 버튼 탭
        ↓
🔌 소켓 닫힘
📱 앱: "연결이 끊어졌어요" (페어링은 유지됨)
```

---

## 이 앱의 특별한 설계

### BLE와 Classic BT가 완전히 분리되어 있는 이유

실제 라이브러리도 분리되어 있기 때문이에요:

```
BLE 연동 → flutter_blue_plus 라이브러리
Classic BT 연동 → flutter_bluetooth_serial 라이브러리
```

이 앱은 그 구조를 그대로 반영해서:

```
lib/
├── repositories/
│   ├── ble_repository.dart          ← BLE 인터페이스
│   ├── mock_ble_repository.dart     ← BLE Mock
│   ├── bt_repository.dart           ← Classic BT 인터페이스
│   └── mock_bt_repository.dart      ← Classic BT Mock
├── providers/
│   ├── ble_providers.dart           ← BLE 상태 관리
│   └── bt_providers.dart            ← Classic BT 상태 관리
└── screens/
    ├── home_screen.dart             ← BLE 화면
    ├── device_detail_screen.dart    ← BLE 상세
    ├── bt_home_screen.dart          ← Classic BT 화면
    └── bt_device_detail_screen.dart ← Classic BT 상세
```

### 실제 라이브러리로 교체하기

```dart
// lib/providers/bt_providers.dart 에서 한 줄만 변경

// 현재 (Mock):
final btRepositoryProvider = Provider<BTRepository>((ref) {
  return MockBTRepository();
});

// 실제 기기 연동:
final btRepositoryProvider = Provider<BTRepository>((ref) {
  return FlutterBluetoothSerialRepository(); // 교체!
});
```

---

## 자주 하는 질문

### Q. 페어링 없이 연결할 수는 없나요?

없어요. Classic BT의 보안 모델 자체가 페어링 기반이에요.  
(BLE는 페어링 없이도 연결 가능하도록 설계되었어요.)

### Q. 페어링한 장치를 삭제하려면?

스마트폰의 블루투스 설정에서 직접 삭제하거나,  
앱에서 `unpair()` 메서드를 호출하면 OS의 페어링 목록에서도 삭제돼요.

### Q. A2DP(음악)나 HFP(통화) 프로파일은 왜 SPP 터미널이 없나요?

A2DP와 HFP는 데이터를 직접 주고받는 게 아니라  
OS의 오디오 시스템이 자동으로 처리해요.  
SPP처럼 앱이 직접 바이트를 읽고 쓰는 구조가 아니에요.

```
SPP:  앱 ←→ 직접 바이트 통신 ←→ 장치
A2DP: OS 오디오 드라이버 ←→ 장치 (앱이 개입 불필요)
HFP:  OS 전화 앱 ←→ 장치 (앱이 개입 불필요)
```

### Q. 아두이노에 블루투스를 연결하려면 어떤 모듈이 필요한가요?

가장 흔하게 쓰이는 모듈들이에요:

| 모듈 | 타입 | 특징 |
|------|------|------|
| HC-05 | Classic BT (SPP) | 가장 저렴하고 흔함. AT 명령으로 설정 가능 |
| HC-06 | Classic BT (SPP) | HC-05의 Slave 전용 버전 |
| HM-10 | BLE | BLE 전용. 스마트폰과 직접 통신에 유리 |

HC-05/HC-06은 이 앱의 Classic BT 탭으로,  
HM-10은 BLE 탭으로 연결해서 사용할 수 있어요.

---

## 한 줄 요약

```
블루투스 켜기 → 탐색 (느림, 8~12초)
→ 페어링 (처음 한 번, PIN 교환)
→ 연결 (SPP 소켓)
→ 바이트 스트림으로 데이터 자유롭게 주고받기
```

BLE는 "정해진 규격(GATT)"으로 통신하고,  
Classic BT(SPP)는 "직접 바이트를 주고받는 전화선"이라고 생각하면 돼요. 🎉
