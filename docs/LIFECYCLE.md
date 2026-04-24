# Synchorus 앱 라이프사이클

> **목차**
> - **§1~3**: 앱 내부 **재생 라이프사이클** (방 생성 → 동기화 → 재생 → 나가기)와 용어
> - **앱 라이프사이클 (AppLifecycleState)**: 5가지 상태 의미 + Android/iOS 차이 + 역할 × 라이프사이클 매트릭스
> - **소켓 에러 코드 (errno)**: TCP 에러 POSIX 번호별 해석 + 판정 트리
> - **연결 복구 전략 (3중 안전망)**: 프로토콜 / 소켓 이벤트 / watchdog 조합으로 모든 단절 시나리오 커버
>
> 앞의 3섹션은 "정상 흐름", 뒤의 3섹션은 "장애/라이프사이클 전환 시 복구" 관점.

## 1. 전체 흐름도

```
+-------------------------------------------------------------------+
|                         앱 시작                                     |
|                      (Home Screen)                                 |
+----------------+--------------------------+-----------------------+
                 |                          |
          +------v------+           +-------v--------+
          |   방 만들기   |           |   방 참가하기    |
          |   (HOST)     |           |   (GUEST)      |
          +------+------+           +-------+--------+
                 |                          |
          +------v------+           +-------v--------+
          | P2P 서버     |           | UDP 검색        |
          | TCP:41235    |<----------| 또는 IP 직접입력  |
          | UDP 브로드캐스트|           |                |
          +------+------+           +-------+--------+
                 |                          |
                 |       TCP 연결            |
                 |<-------------------------+
                 |    join --> welcome       |
                 |                          |
          +------v--------------------------v--------+
          |              ROOM SCREEN                  |
          +------+--------------------------+--------+
                 |                          |
          +------v------+           +-------v--------------+
          | 호스트:       |           | 게스트:                |
          | sync-ping    |           | (1) syncWithHost(30p) |
          | 핸들러 시작    |           | (2) startPeriodicSync |
          |              |<----------| (3) audio-request     |
          +------+------+           +-------+--------------+
                 |                          |
                 v                          v
```

### 오디오 공유 & 재생

```
     호스트                                     게스트
      |                                          |
      |  +--------------+                        |
      +--| 파일 선택      |                        |
      |  | + 디코드       |                        |
      |  | + HTTP 서버    |                        |
      |  +------+-------+                        |
      |         |                                |
      |         |  == audio-url =============>   |
      |         |                        +-------v-------+
      |         |                        | HTTP 다운로드   |
      |         |                        | + 디코드        |
      |         |                        +-------+-------+
      |         |                                |
      |  +------v-------+                        |
      +--| >> 재생 시작   |                        |
      |  +------+-------+                        |
      |         |                                |
      |         |  == audio-obs (500ms) =====>   |
      |         |                        +-------v-------+
      |         |                        | >> 재생 시작   |
      |         |                        +-------+-------+
      |         |                                |
```

### 게스트 동기화 보정 루프

```
  +-----------------------------------------------------+
  |       게스트 Timestamp 수신 (200ms 주기)                |
  +-------------------------+---------------------------+
                            |
                            v
                   +----------------+
                   | offset 수렴됨?  |
                   |(isOffsetStable)|
                   +----+------+----+
                   NO   |      |  YES
                        v      v
             +-----------+   +----------------+
             | FALLBACK  |   | anchor 있음?    |
             | VF 기반    |   +---+--------+---+
             | +/-30ms   |   NO  |        | YES
             | 보정       |       v        v
             +-----------+  +----------+ +---------------+
                            | ANCHOR   | | DRIFT 계산     |
                            | 설정      | | (HAL framePos)|
                            | + seek   | | +/-2ms 정밀도   |
                            +----------+ +-------+-------+
                                                  |
                                                  v
                                         +---------------+
                                         | drift > 20ms? |
                                         +--+--------+---+
                                        YES |        | NO
                                            v        v
                                      +----------+ (유지)
                                      | seek 보정 |
                                      | gain=0.8 |
                                      | +cooldown|
                                      +----------+
```

### Seek 처리

```
     호스트                                     게스트
      |                                          |
      |  사용자 seek                               |
      |  +-- seekToFrame (엔진)                   |
      |  +-- obs 즉시 브로드캐스트                   |
      |  |                                       |
      |  +== seek-notify (targetMs) =========>   |
      |                                   +------v---------+
      |                                   | seekToFrame    |
      |                                   | anchor 무효화   |
      |                                   | cooldown 1000ms|
      |                                   +----------------+
```

### 방 나가기

```
  +---------------------------------------------+
  |              방 나가기                         |
  +---------------------+-----------------------+
                        |
     +------------------v------------------+
     |  1. 구독(listener) 전부 취소          |
     |  2. audio_handler detach + stop     |
     |  3. sync.reset()                    |
     |  4. p2p.disconnect()               |
     |  5. audio.clearTempFiles()          |
     |  6. provider invalidate             |
     +------------------+------------------+
                        |
                        v
                 [ Home Screen ]
```

---

## 2. 각 단계 상세 설명

### 2-1. 방 생성 (호스트)

| 순서 | 동작 | 설명 |
|:---:|------|------|
| 1 | `p2p.startHost()` | TCP 서버를 41235 포트에 바인딩. 게스트의 연결을 대기 |
| 2 | `generateRoomCode()` | 4자리 숫자 코드 생성 (1000~9999). 게스트가 방을 식별하는 용도 |
| 3 | `discovery.startBroadcast()` | UDP 브로드캐스트로 같은 WiFi의 게스트에게 존재를 알림 |
| 4 | RoomScreen 진입 | `sync.startHostHandler()` -- sync-ping 수신 대기 시작 |
| 5 | | `audio.startListening(isHost: true)` -- 측정 로거 시작 + 메시지 리스너 |

### 2-2. 방 참가 (게스트)

| 순서 | 동작 | 설명 |
|:---:|------|------|
| 1 | 호스트 발견 | UDP 검색으로 자동 발견하거나, IP를 직접 입력 |
| 2 | `p2p.connectToHost()` | 호스트 IP:41235로 TCP 연결 + join 메시지 전송 |
| 3 | welcome 수신 | 호스트가 보낸 환영 메시지 (방 코드, 참가자 수 포함) |
| 4 | RoomScreen 진입 | `audio.startListening(isHost: false)` -- 메시지 리스너 시작 |

### 2-3. 시간 동기화 (게스트 --> 호스트)

**초기 핸드셰이크** -- 30회 ping-pong으로 clock offset 측정

| 순서 | 동작 | 설명 |
|:---:|------|------|
| 1 | 게스트: sync-ping 전송 | `{t1: 전송시각, rid: 요청ID}` 를 100ms 간격으로 30회 |
| 2 | 호스트: sync-pong 응답 | `{t1, hostTime: 수신시각, rid}` 즉시 반환 |
| 3 | 게스트: offset 계산 | `RTT = 수신시각 - t1`, `offset = hostTime - (t1 + RTT/2)` |
| 4 | best RTT 선택 | RTT가 가장 작은 샘플의 offset을 초기값으로 확정 |

**주기적 EMA 동기화** -- 1초 간격으로 지속적 보정

| 순서 | 동작 | 설명 |
|:---:|------|------|
| 1 | 1초마다 ping 1회 | 음수 rid로 초기 핸드셰이크와 구분 |
| 2 | sliding window | 최근 5개 샘플 유지, 그 중 min-RTT 샘플 선택 |
| 3 | EMA 필터 | 처음 10샘플: alpha=0.5 (빠른 수렴), 이후: alpha=0.1 (안정 유지) |
| 4 | 안정 판정 | offset 변화 < 2ms가 5회 연속이면 `isOffsetStable = true` |

### 2-4. 오디오 파일 공유

| 순서 | 호스트 | 게스트 |
|:---:|--------|--------|
| 1 | 파일 선택 + 네이티브 엔진 디코드 | -- |
| 2 | HTTP 서버 시작 (포트 41236) | -- |
| 3 | `audio-url` 브로드캐스트 | audio-url 수신 |
| 4 | -- | HTTP로 파일 다운로드 |
| 5 | -- | 네이티브 엔진 디코드 + 준비 완료 |
| 6 | -- | 호스트가 이미 재생 중이면 즉시 재생 시작 |

### 2-5. 재생 & 동기화 유지

**호스트:**
- 재생 시작/정지/seek 시 즉시 `audio-obs` 브로드캐스트
- 이후 500ms 주기로 `audio-obs` 반복 전송
- obs 내용: `{virtualFrame, framePos, hostTimeMs, sampleRate, playing}`

**게스트 보정 루프 (2단계):**

| 단계 | 이름 | 조건 | 정밀도 | 동작 |
|:---:|------|------|--------|------|
| 1 | **Fallback** | offset 미수렴 또는 HAL 없음 | +/-8ms | VF 기반. 30ms 이상 차이 시 seek. 1초 쿨다운 |
| 2 | **Anchor** | offset 수렴 + HAL 가능 | +/-2ms | framePos 기반. anchor 설정 후 drift 추적. 20ms 이상 시 seek (gain=0.8) |

### 2-6. Seek 처리

| 규칙 | 설명 |
|------|------|
| **absolute targetMs** | seek-notify는 절대 위치(ms)를 전송. 중복 수신해도 결과 동일 (멱등) |
| **anchor 무효화** | seek 후 기존 anchor는 무의미 --> 리셋 |
| **cooldown 1000ms** | seek 직후 stale obs로 잘못된 anchor 설정 방지 |
| **obs 즉시 전송** | seek 후 호스트가 새 obs를 바로 보내서 게스트가 빠르게 재정렬 |

### 2-7. 방 나가기 & 정리

| 순서 | 동작 | 목적 |
|:---:|------|------|
| 1 | 모든 StreamSubscription 취소 | 정리 중 콜백 방지 |
| 2 | audio_handler detach + stop | 백그라운드 알림 제거 |
| 3 | `sync.reset()` | offset/timer/EMA 상태 초기화 |
| 4 | `p2p.disconnect()` | TCP 소켓 닫기 + leave 메시지 전송 |
| 5 | `audio.clearTempFiles()` | 다운로드된 파일 삭제 + 엔진 unload |
| 6 | Provider invalidate | Riverpod에서 서비스 dispose 트리거 |

**호스트 측 게스트 이탈 감지:**
- 명시적: 게스트가 leave 메시지 전송
- 암묵적: heartbeat 응답 없음 (9초 타임아웃) --> 자동 제거

---

## 3. 용어 사전

### 네트워크 / P2P

| 용어 | 설명 |
|------|------|
| **Host (호스트)** | 방을 만든 기기. 기준 시간(clock)이자 오디오 원본 소유자. TCP 서버 역할 |
| **Guest (게스트)** | 방에 참가한 기기. 호스트의 시간과 동기화하여 재생 |
| **P2P** | Peer-to-Peer. 서버 없이 기기끼리 직접 TCP로 통신 |
| **TCP:41235** | P2P 메시지 통신 포트 (sync-ping, audio-obs, seek-notify 등) |
| **TCP:41236** | HTTP 파일 서버 포트 (오디오 파일 다운로드용) |
| **UDP 브로드캐스트** | 같은 WiFi 내 호스트를 자동 발견하는 방식 |
| **heartbeat** | 3초 간격 생존 확인. 9초 무응답 시 연결 끊김 처리 |

### 시간 동기화

| 용어 | 설명 |
|------|------|
| **offset** | 게스트와 호스트의 시계 차이 (ms). `게스트시간 + offset = 호스트시간` |
| **RTT** | Round-Trip Time. ping을 보내고 pong을 받기까지 걸린 시간 |
| **EMA** | Exponential Moving Average. 새 값에 가중치(alpha)를 주고 기존 값과 혼합하는 필터. 노이즈 제거용 |
| **alpha (fast/slow)** | EMA의 반응 속도. fast=0.5(초기, 빠른 수렴), slow=0.1(안정기, 노이즈 무시) |
| **isOffsetStable** | offset 변화가 2ms 미만으로 5회 연속이면 true. anchor 설정의 전제 조건 |
| **rid** | Request ID. 양수=초기 핸드셰이크, 음수=주기적 sync. 서로 다른 ping/pong이 섞이지 않도록 구분 |

### 오디오 엔진

| 용어 | 설명 |
|------|------|
| **네이티브 엔진** | Android=Oboe(C++), iOS=AVAudioEngine(Swift). Flutter가 아닌 플랫폼 네이티브 코드로 오디오 재생 |
| **sampleRate** | 초당 샘플 수. 44100Hz(CD 품질) 또는 48000Hz(영상/폰 기본) 등. 기기 하드웨어와 파일에 따라 다름 |
| **HAL** | Hardware Abstraction Layer. OS가 오디오 하드웨어와 통신하는 계층. 정밀한 framePos/timestamp 제공 |
| **framePos** | HAL이 보고하는 프레임 위치. 단조증가(monotonic)하며 seek해도 리셋 안 됨. rate drift 추적용 |
| **virtualFrame (VF)** | seek를 인식하는 가상 재생 위치. `seekOffset + 재생된프레임수`. 콘텐츠 위치 추적용 |
| **framesPerMs** | `sampleRate / 1000`. 1ms당 프레임 수. frame <--> ms 변환에 사용 |
| **디코딩** | 압축 파일(MP3 등)을 PCM(원시 오디오)으로 변환. 재생 전 필수 |
| **Oboe** | Google의 Android 오디오 라이브러리. AAudio/OpenSL ES를 자동 선택 + SRC 지원 |
| **SRC** | Sample Rate Conversion. 파일 rate(44.1kHz)와 하드웨어 rate(48kHz)가 다를 때 자동 변환 |

### 동기화 보정

| 용어 | 설명 |
|------|------|
| **audio-obs** | Audio Observation. 호스트가 500ms마다 보내는 자기 재생 상태 스냅샷 |
| **Fallback 모드** | VF(virtualFrame)만으로 대략 정렬. HAL 없거나 offset 수렴 전에 사용. 정밀도 +/-8ms |
| **Anchor 모드** | HAL framePos 기반 정밀 drift 추적. offset 수렴 후 활성화. 정밀도 +/-2ms |
| **anchor (앵커)** | drift=0인 기준점. 호스트/게스트의 framePos 쌍을 기록. 이후 각각의 진행량 차이로 drift 계산 |
| **drift** | 호스트와 게스트의 재생 위치 차이 (ms). 양수=게스트가 앞서감, 음수=뒤처짐 |
| **drift-report** | 게스트가 호스트에게 보내는 drift 측정 보고. 호스트의 CSV 로거에 기록 |
| **seek-notify** | 호스트 seek 시 게스트에게 보내는 절대 위치(ms). 멱등(idempotent). 게스트가 재생 중이 아니어도 엔진 VF/seekFrameOffset 갱신 적용 |
| **cooldown (쿨다운)** | 보정 seek 후 일정 시간(1초) 동안 추가 보정을 금지. 진동(oscillation) 방지 |
| **gain=0.8** | seek 보정 시 drift의 80%만 보정. 오버슈트(과잉 보정 --> 반대쪽으로 벗어남) 방지 |
| **cross-rate 비교** | 호스트(48kHz)와 게스트(44.1kHz)의 frame을 직접 비교하지 않고 각각 ms로 변환 후 비교 |

### 기타

| 용어 | 설명 |
|------|------|
| **MethodChannel** | Flutter <--> 네이티브(Kotlin/Swift) 간 명령 호출 통로. `loadFile`, `seekToFrame` 등 |
| **EventChannel** | 네이티브 --> Flutter 방향의 연속 데이터 스트림. timestamp 관측값을 200ms마다 전송 |
| **Riverpod Provider** | 서비스 인스턴스(P2P, Sync, Audio)의 생명주기 관리. 방 나가기 시 invalidate로 정리 |
| **멱등 (idempotent)** | 같은 요청을 여러 번 보내도 결과가 동일. seek-notify가 absolute targetMs인 이유 |
| **NativeTimestamp** | 네이티브 엔진이 보내는 관측 데이터. `{framePos, timeNs, virtualFrame, sampleRate, wallMs, ok}` |
| **CSV 로거** | 호스트에서 drift-report를 파일로 기록. 테스트 후 분석용 |

---

## 앱 라이프사이클 (AppLifecycleState)

Flutter가 Android/iOS의 앱 상태 전환을 단일 enum으로 추상화한 것. `WidgetsBindingObserver.didChangeAppLifecycleState`로 받는다.

### 상태 (5가지)

Flutter 공식 state machine (api.flutter.dev):

```
+-----------+                           +-----------+
| detached  |-------------------------->|  resumed  |
+-----------+                           +-----------+
      ^                                     ^
      |                                     |
      |                                     v
+-----------+   +--------------+   +-----------+
|  paused   |<->|    hidden   |<->| inactive  |
+-----------+   +--------------+   +-----------+
```

| 상태 | 의미 | 우리 앱에서 언제 발생? |
|------|------|----------------------|
| **resumed** | foreground + 입력 포커스 있음 (정상 사용 중) | 앱 정상 사용, 복귀 직후 |
| **inactive** | foreground이지만 입력 못 받음 (transient 전환) | 알림 드롭다운 살짝 내림, Control Center, 앱 전환 애니메이션 중, Siri 호출 |
| **hidden** | 모든 view 숨김 (background 전환 과정) | paused 직전/직후 짧게. 대부분 무시 가능 |
| **paused** | background. 앱 실행 중단, OS가 프로세스 억제 가능 | 홈 버튼, 다른 앱 전환, 화면 잠금, 파일 선택 창(file_picker Intent), 전화 수신 전체화면 |
| **detached** | 모든 view 분리 (종료 직전) | 앱 종료 (정상/스와이프 스와이프/OS kill 중 Dart가 살아있을 때만) |

### OS가 paused 상태 앱에 하는 일

**Android**:
- foreground service 없으면 프로세스 "cached/background"로 강등
- CPU 스케줄러 우선순위 낮춤
- Timer·네트워크 억제 (Doze / App Standby)
- 수 분 후 cgroup freezer로 CPU 아예 중단 (Android 12+)
- 메모리 부족 시 OOM killer 대상 1순위

**iOS**:
- background audio mode 없으면 수 초 내 suspended
- suspended 상태에서 CPU/network/Timer 모두 정지
- 메모리 부족 시 kill

**foreground service / background audio mode**: 위 제약을 면제받는 OS 공식 수단. 하지만 UX상 알림 필수.

### 플랫폼별 실전 차이 (같은 enum 써도 동작이 미묘히 다름)

| 이벤트 | Android | iOS |
|---|---|---|
| 정상 종료 (`finish()` / `Scene dismiss`) | detached 도달 | detached 도달 (`UIApplicationWillTerminate`, `UISceneDidDisconnect`) |
| 앱 스위처 스와이프 | detached **보통 도달** (프로세스 짧게 살아있음) | detached **거의 도달 안 함** (OS 바로 kill) |
| OS 메모리 kill | detached 도달 확률 낮음 | detached 도달 안 함 |
| 크래시 | detached 안 옴 | detached 안 옴 |

→ **detached 이벤트는 best-effort**. 이 이벤트만 믿고 정리 로직을 걸면 안 됨.

### 우리 앱의 역할 × 라이프사이클 대응 매트릭스

역할(role) 정의:
- **idle**: 방 없음 (홈 화면, 로그인 등)
- **host**: 방 만들고 TCP 서버 운영 중
- **guest**: 방 참가해서 호스트에 연결 중

| 상태 | idle | host | guest |
|---|---|---|---|
| inactive | 무시 | 무시 | 무시 |
| hidden | 무시 | 무시 | 무시 |
| **paused** | 무시 | `host-paused` broadcast + heartbeat 정지 | (자기 pause는 호스트가 감지) |
| **resumed** | 무시 | `host-resumed` broadcast + heartbeat 재개 + 모든 peer `lastSeen` 리셋 | TCP 상태 점검, 끊겼으면 재접속 |
| **detached** | 무시 | `host-closed` broadcast (best-effort) + disconnect | `leave` 메시지 + disconnect |

현재 v0.0.25: host 측 paused/resumed만 구현. detached는 미구현(추후 보완).

---

## 소켓 에러 코드 (errno)

TCP 소켓 에러가 발생하면 `SocketException.osError.errorCode`에 POSIX errno 숫자가 담긴다. POSIX 이름은 같아도 **숫자값이 Linux(Android) / Darwin(iOS/macOS)에서 다르다** — 관측 값은 양쪽을 모두 체크해야 함.

### 주요 errno (이 앱에서 실제 관측된 것 포함)

| 이름 | Linux | Darwin | 의미 | 우리 앱에서의 해석 |
|---|---|---|---|---|
| **ECONNREFUSED** | 111 | **61** | 상대가 listen 안 함 | 호스트 TCP 서버 죽음 → 호스트 프로세스 종료 거의 확정 |
| **ETIMEDOUT** | 110 | 60 | 응답 없음 (SYN timeout) | 호스트 paused 상태 or 네트워크 지연 → 잠깐 기다릴 가치 있음 |
| **EHOSTUNREACH** | 113 | **65** | 호스트로 경로 없음 | 호스트가 AP 나감 or WiFi 변경 |
| **ENETUNREACH** | 101 | **51** | 네트워크 자체 사용 불가 | 내 WiFi 끊김 |
| **ECONNRESET** | 104 | 54 | 상대가 RST 보냄 | 상대 OS의 socket cleanup (대부분 상대 정상 종료) |
| **ECONNABORTED** | 103 | 53 | 로컬 소켓 abort | 내 OS가 내 앱의 socket 정리 (Android paused 직후 흔함) |
| **EPIPE** | 32 | 32 | 이미 끊긴 소켓에 write | 이전에 RST 받은 소켓에 send 시도 |

> **Linux/Darwin errno 차이**: v0.0.29까지 코드가 Linux 값(111/113/101)만 하드코딩했다가 2026-04-24 iPhone 실측에서 `errno=61`(Darwin ECONNREFUSED)이 감지 안 되어 빠른 포기 경로 미작동으로 드러남. v0.0.30에서 `{Linux, Darwin}` 집합으로 확장: `room_lifecycle_coordinator.dart`의 `_refusedErrnos` / `_networkUnreachableErrnos` 상수.

### 판정 트리 (ECONNREFUSED 분기는 v0.0.27, EHOSTUNREACH/ENETUNREACH 분기는 v0.0.28 구현, v0.0.30 Darwin 대응)

```
소켓 에러 발생 시:
  ├─ ECONNREFUSED (Linux 111 / Darwin 61)
  │    → 호스트 프로세스 죽음 확률↑
  │    → 2회 연속이면 즉시 leaveRoom (빠른 포기)
  │
  ├─ ETIMEDOUT (110 / 60)
  │    → 호스트 paused 가능성 (foreground service 없는 상태)
  │    → 주기 재시도 (watchdog까지 유지)
  │
  ├─ EHOSTUNREACH (113 / 65) / ENETUNREACH (101 / 51)
  │    → connectivity_plus로 내 WiFi 상태 재확인
  │         ├─ WiFi 있음 → 호스트 네트워크 문제 → 재시도
  │         └─ WiFi 없음 → 내 WiFi 복구 대기 (기존 `_waitForWifiAndReconnect` 로직)
  │
  ├─ ECONNRESET (104 / 54)
  │    → 상대 정상/비정상 종료 (대부분)
  │    → `_hostAway=true`면 watchdog, 아니면 기존 reconnectToHost 플로우
  │
  └─ ECONNABORTED (103 / 53)
       → 내 측 abort (호스트가 paused로 강등되며 OS가 처리한 경우 흔함)
       → 보통 `host-paused` 메시지가 앞서서 도달했을 것이라 이미 `_hostAway=true` 상태
```

### 한계

- errno 숫자값은 **Linux/Darwin에서 다름** — 관측된 값은 양쪽을 명시적으로 OR 체크해야 함 (v0.0.30)
- 원격 호스트의 실제 상태를 100% 알 방법 없음 → 휴리스틱 판정일 뿐
- 최종 확신은 재접속 성공/실패 + 시간 기반 watchdog으로만 가능

---

## 연결 복구 전략 (3중 안전망)

앞의 "앱 라이프사이클"과 "errno"를 조합해 P2P 연결이 다양한 실패 모드를 견디도록 설계한 구조. 상위 계층이 실패해도 하위 계층이 안전망으로 작동.

> **구현 위치**: v0.0.29부터 1~3층 전체가 `lib/services/room_lifecycle_coordinator.dart`의 `RoomLifecycleCoordinator`에 모여 있다. UI(`room_screen.dart`)는 `hostAway` / `hostClosed` `ValueNotifier` 구독과 액션 콜백(`onLeaveRequested`, `onReconnectSyncRequested`, `onLog`, `onSnackbar`)만 처리. 라이프사이클 분기 추가/수정은 모두 코디네이터 한 파일에서.

### 1층 — 프로토콜 메시지 ("정상 경로")

양쪽 앱이 **살아있고 통신 가능할 때** 의도를 명시적으로 주고받는다.

| 메시지 | 방향 | 트리거 | 효과 |
|---|---|---|---|
| `host-paused` | 호스트 → 전체 게스트 | 호스트 `AppLifecycleState.paused` | 게스트 자리비움 배너 표시, 재접속 중단 |
| `host-resumed` | 호스트 → 전체 게스트 | 호스트 `AppLifecycleState.resumed` | 게스트 자리비움 해제, heartbeat 재개 |
| `host-closed` | 호스트 → 전체 게스트 | 호스트 방 나가기 버튼 / (장래) detached | 게스트 즉시 홈 화면 복귀 |

### 2층 — TCP 소켓 이벤트 ("비정상 감지")

1층 메시지가 오지 못하는 상황을 OS 수준에서 포착.

- `Socket.onDone`: 상대가 FIN을 보낸 경우 (정상 종료)
- `Socket.onError` + `SocketException.osError.errorCode`: RST / timeout / unreachable 등
- errno 기반 판정 트리 (위 "소켓 에러 코드" 섹션)

### 3층 — 시간 기반 watchdog ("최종 안전망")

1층·2층 모두 실패해도 앱이 멈추지 않도록 하는 하드 타임아웃.

- 게스트가 `_hostAway=true` 상태 + TCP 끊김 상태에서 `_startAwayReconnectLoop()` 시작
- 5초 주기로 1회씩 `reconnectToHost(retries: 1)` 시도
- N회(현재 12회, 약 60~120초) 실패 시 `leaveRoom()` 강제 호출 → 홈 화면으로
- 성공 시 재동기화 진행

WiFi 완전 끊김처럼 TCP RST도 오지 않는 극단 케이스에 이 층이 유일한 방어선.
