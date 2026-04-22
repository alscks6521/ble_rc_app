# ble_rc_car_app

Flutter + Arduino로 만든 4WD RC카 블루투스 컨트롤러

---

## 기술 스택

- **Flutter** — Android 앱 (BLE 컨트롤러)
- **Arduino Uno R3** — RC카 제어
- **HM-10** — BLE 4.0 통신 모듈
- **L298N** — 모터 드라이버

---

## 프로젝트 구조

```
lib/
├── main.dart
├── screens/
│   ├── scan_screen.dart        # BLE 디바이스 검색 & 연결
│   └── controller_screen.dart  # 조이스틱 조종 화면
├── services/
│   └── ble_service.dart        # BLE 연결 / 명령 전송
└── widgets/
    └── joystick.dart           # 아날로그 조이스틱 + 탱크드라이브 믹싱
```

---

## 시스템 흐름

```
[Flutter 조이스틱]
      ↓  (x, y) 좌표
[탱크 드라이브 믹싱]
  left  = y + x
  right = y - x
      ↓  "L200R060\n"  (100ms 간격)
[HM-10 BLE]
      ↓  UART 9600bps
[Arduino]
  → L298N PWM 제어
  → 모터 4개 구동
```

---

## 통신 프로토콜

```
주행:  L{0~255}R{0~255}\n    (128 = 정지, 255 = 최대전진, 0 = 최대후진)
정지:  S\n
```

예시

| 명령 | 동작 |
|------|------|
| `L255R255\n` | 직진 |
| `L0R0\n` | 후진 |
| `L255R0\n` | 제자리 우회전 |
| `L220R140\n` | 전진하며 우곡선 |

---

## 하드웨어 배선

| Arduino | 연결 대상 | 설명 |
|---------|---------|------|
| 3.3V | HM-10 VCC | ⚠️ 반드시 3.3V!! |
| D2 | HM-10 TXD | BLE 수신 |
| D3 | HM-10 RXD | BLE 송신 |
| D5 PWM | L298N ENA | 좌측 속도 |
| D6 PWM | L298N ENB | 우측 속도 |
| D7 / D8 | L298N IN1 / IN2 | 좌측 방향 |
| D9 / D10 | L298N IN3 / IN4 | 우측 방향 |
| 5V | L298N 5VOUT | Arduino 전원 수전 |

> L298N의 ENA, ENB 점퍼를 제거해야 PWM 속도 제어됨.

전원: 18650 × 2 직렬 (7.4V) → L298N 12V 단자

---


> 아두이노 업로드 시 HM-10 D2/D3 선을 잠깐 분리.

---

## 주요 의존성

```yaml
flutter_blue_plus: ^2.2.1  
permission_handler: ^12.0.1
```
  

![alt text](imgss/image.png)  
  
  
---

```
1 — HM-10 BLE → 아두이노 우노
VCC	→	3.3V	⚠ 반드시 3.3V — 5V 연결 시 모듈 손상
GND	→	GND	공통 GND
TXD	→	D2	모듈 송신 → 아두이노 수신 (SoftSerial RX)
RXD	→	D3	아두이노 송신 → 모듈 수신 (SoftSerial TX)
STATE	—	미연결	선택 사항
BRK	—	미연결	선택 사항
2 — 아두이노 우노 → L298N
D5 (PWM)	→	ENA	좌측 모터 속도 — 점퍼 제거 필수
D6 (PWM)	→	ENB	우측 모터 속도 — 점퍼 제거 필수
D7	→	IN1	좌측 모터 방향 A
D8	→	IN2	좌측 모터 방향 B
D9	→	IN3	우측 모터 방향 A
D10	→	IN4	우측 모터 방향 B
GND	→	GND	공통 GND — 반드시 연결
5V	←	5V OUT	L298N이 아두이노에 전원 공급 (역방향)
ENA, ENB 자리의 노란 점퍼 2개를 반드시 뽑아야 PWM 속도 제어가 됩니다. 점퍼가 꽂혀 있으면 항상 최대 속도로만 동작합니다.
3 — 배터리 → L298N
+ 빨간선	→	12V (VCC)	7.4V 입력 (명칭이 12V여도 7~12V 가능)
- 검은선	→	GND	공통 GND
4 — L298N → 모터 4개
OUT1 / OUT2	→	좌측 앞 모터	병렬 연결
OUT1 / OUT2	→	좌측 뒤 모터	앞 모터와 같은 단자에 병렬
OUT3 / OUT4	→	우측 앞 모터	병렬 연결
OUT3 / OUT4	→	우측 뒤 모터	앞 모터와 같은 단자에 병렬
모터가 반대로 돌면 해당 모터의 OUT 두 선을 서로 바꿔 꽂으면 됩니다. 코드 수정 불필요.
조립 순서
1
배터리 → L298N 연결 (아직 배터리 삽입 금지)
빨간 → 12V, 검은 → GND
2
ENA, ENB 점퍼 제거
L298N 보드의 노란 점퍼 2개 뽑기
3
L298N → 아두이노 연결
ENA/ENB/IN1~IN4/GND/5VOUT 순서로 연결
4
모터 4개 연결
좌측 2개 → OUT1/OUT2 병렬, 우측 2개 → OUT3/OUT4 병렬
5
HM-10 → 아두이노 연결
VCC → 3.3V, GND, TXD → D2, RXD → D3
6
아두이노 코드 업로드
업로드 전 HM-10 D2/D3 선 잠깐 분리 → 업로드 완료 후 재연결
7
배터리 삽입 후 테스트
시리얼 모니터(9600bps)로 수신 명령 확인 가능
```