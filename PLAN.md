# Synchorus - 구현 계획서

여러 핸드폰을 동기화된 스피커로 만드는 모바일 앱 (Flutter)

## 현재 진행 상황

### Phase 1 완료 항목
- [x] 프로젝트 생성 (Flutter, 패키지명: com.synchorus.synchorus)
- [x] GitHub 연동 (https://github.com/shnskr/synchorus.git)
- [x] 개발 환경 세팅 (Flutter SDK, Android Studio, Xcode, CocoaPods)
- [x] 패키지 구조 생성 (screens, services, models, providers, widgets)
- [x] P2P 연결 코드 작성
  - p2p_service.dart: TCP 소켓 통신 (호스트/참가자)
  - discovery_service.dart: UDP 브로드캐스트 (디바이스 발견)
  - home_screen.dart: 홈 화면 (방 만들기/참가)
  - room_screen.dart: 방 화면 (연결 상태/로그)
  - models (peer.dart, room.dart)
  - providers (app_providers.dart)
- [x] 시간 동기화 구현
  - sync_service.dart: ping/pong 방식 offset 계산 (best RTT 기준)
  - room_screen에서 참가 시 자동 동기화 수행
- [x] 오디오 재생/공유 구현
  - audio_service.dart: just_audio 기반 재생, 파일 전송(청크), URL 공유, 동기화 play/pause/seek
  - player_screen.dart: 플레이어 UI (파일 선택, URL 입력, 시크바, 볼륨)

### 실기기 테스트 및 버그 수정 (진행 중)

테스트 환경: 에뮬레이터(Pixel 6 API 34) + Galaxy S22 (SM-S901N)

#### 완료된 수정사항
- [x] Android 네트워크 권한 추가 (INTERNET, ACCESS_WIFI_STATE 등 + usesCleartextTraffic)
- [x] IP 직접 입력으로 방 참가 (에뮬레이터는 UDP 브로드캐스트 불가)
- [x] TCP 패킷 분할 문제 해결 (UTF-8 문자열 버퍼링 → 바이트 단위 버퍼링)
- [x] 포트 재사용 에러 해결 (disconnect() 후 startHost, ServerSocket shared: true)
- [x] 시스템 뒤로가기 지원 (PopScope 적용)
- [x] 다중 참가 방지 (_isJoining 플래그)
- [x] 게스트 roomCode 표시 (welcome 메시지에 roomCode 포함)
- [x] 파일 변경 시 상태 초기화 (_handleAudioMeta에서 이전 상태 클리어)
- [x] 방 나가기 시 임시 파일 삭제 (clearTempFiles)
- [x] play/pause에 positionMs 포함 (반복 재생 시 싱크 밀림 방지)
- [x] state-request/response 프로토콜 (게스트 늦은 입장 시 호스트 상태 동기화)
- [x] audio.startListening을 RoomScreen으로 이동 (PlayerScreen 열기 전에도 메시지 수신)
- [x] 5초 앞/뒤 건너뛰기 버튼
- [x] 파일 수신 중 로딩 인디케이터 (호스트/게스트 모두)
- [x] 호스트 나가기 확인 팝업 ("모든 참가자의 연결이 끊어집니다")
- [x] 호스트 연결 끊김 시 게스트 자동 퇴장 (onDisconnected 스트림)
- [x] socket.close() → socket.destroy() (TCP 종료 핸드셰이크 대기 제거)
- [x] _sendTo에 try-catch + socket.add() (소켓 에러 시 크래시 방지)
- [x] socket.done.catchError 추가 (Broken pipe unhandled exception 방지)
- [x] Navigator.popUntil(route.isFirst) (PlayerScreen 위에서도 홈까지 복귀)
- [x] 구독 먼저 취소 후 disconnect (cleanup 중 setState 콜백 방지)
- [x] mounted 체크 (_addLog, _startSync에서 dispose 후 setState 방지)
- [x] 파일 캐시 + 새 피어 입장 시 오디오 자동 전송 (sendCurrentAudioToPeer)
- [x] 세대 카운터 (_sendGeneration) - 파일 전송 충돌 시 이전 전송 자동 취소
- [x] audio-request 방식으로 변경 - 게스트가 sync 완료 후 직접 오디오 요청 (호스트 백그라운드 문제 해결)
- [x] 호스트 IP 표시 및 복사 기능 (RoomScreen 카드에 IP 표시 + 복사 버튼)
- [x] WiFi 연결 체크 (connectivity_plus) - 방 만들기/참가/검색 시 WiFi 미연결 차단
- [x] WiFi 끊김 감지 시 자동 퇴장 (onConnectivityChanged)
- [x] TCP 연결 타임아웃 5초 추가 (Socket.connect timeout)
- [x] 참가 시 로딩 표시 (IP 입력, 방 목록 모두)
- [x] 연결 실패 시 "같은 WiFi 확인" 안내 메시지
- [x] permission_handler 패키지 및 불필요 권한 제거 (위치 권한 불필요)
- [x] WiFi 재연결 후 방 생성 시 stale 이벤트 방지 (1초 대기 + checkConnectivity 재확인)
- [x] Heartbeat 메커니즘 추가 (3초 간격 ping/ack, 9초 타임아웃으로 죽은 피어 감지)
- [x] 피어 퇴장 시 접속자 수 즉시 반영 (_peerNames → _peerMap으로 변경)
- [x] 중복 퇴장 이벤트 방지 (heartbeat 제거 후 socket.done 중복 발화 차단)
- [x] 게스트 접속자 수 표시 (welcome peerCount + peer-joined/peer-left 추적)
- [x] 재생 시 재동기화 (게스트가 play 수신 시 3회 빠른 re-sync)
- [x] 지연 초과 시 position 보정 (delayMs <= 0이면 늦은 만큼 position 앞으로 조정)
- [x] 호스트 메시지 핸들러 가드 추가 (play/pause/seek/audio-meta 등 게스트 전용 메시지 차단)
- [x] file_picker 캐시 삭제 문제 해결 (앱 임시 디렉토리에 복사 후 플레이어 로드)
- [x] 음소거 버튼 추가 (컨트롤 영역 왼쪽, 이전 볼륨 복원)
- [x] SafeArea 적용 (하단 네비게이션 바 영역 겹침 방지)
- [x] 게스트 안내 문구 개선 ("음악 대기 중")
- [x] 방 만들기/참가 시 검색 모드 자동 중지
- [x] print → debugPrint 마이그레이션 (avoid_print 경고 해결)
- [x] 기존 lint 이슈 전체 해결 (use_build_context_synchronously, unused_import, unused_local_variable)

#### 알려진 이슈 / 다음에 확인할 것
- [ ] 호스트 파일선택 창 열고 있는 동안 게스트 입퇴장 시 안정성 (audio-request 방식으로 개선 완료, 추가 테스트 필요)
- [x] 대용량 파일 전송 중 TCP 연결 끊김 (청크 32KB, 딜레이 20ms로 조정, 20MB 테스트 통과)
- [x] 호스트가 재생 중 파일 로드 시 가끔 호스트만 재생 안 되는 현상 (원인: file_picker 캐시 삭제 → 앱 임시 디렉토리에 복사하여 해결)
- [x] 에뮬레이터 ↔ 실기기 간 네트워크 (UDP 브로드캐스트 불가 → IP 직접 입력으로 연결 가능)

### 사용 중인 패키지
```yaml
flutter_riverpod: ^2.6.1      # 상태 관리/DI
network_info_plus: ^6.1.1     # WiFi IP 확인 (호스트 IP 표시용)
connectivity_plus: ^7.1.0     # WiFi 연결 여부 확인
just_audio: ^0.9.43           # 오디오 재생
file_picker: ^8.1.7           # 파일 선택
path_provider: ^2.1.5         # 임시 파일 저장 경로
```

### 추가 예정 패키지 (백그라운드 재생 구현 시)
```yaml
audio_service: ^0.18.x        # 백그라운드 재생 + 잠금화면 컨트롤
```

## 핵심 요구사항

1. 각각의 핸드폰이 모두 스피커가 되어 같은 오디오를 재생
2. 동시 재생이므로 싱크가 맞게끔 재생
3. 음원 파일 선택 또는 URL로 재생 가능

## 핵심 기술 설계 (v2)

### 1. 기기간 연결

**목표**: P2P 연결 (지연 최소화)

**현재 (Phase 1~2)**: 같은 WiFi + TCP/UDP 소켓 (`dart:io`)
- 디바이스 발견: UDP 브로드캐스트 (포트 41234)
- 데이터 통신: TCP 소켓 (포트 41235)
- 연결 유지: Heartbeat (3초 간격)

**확장 (Phase 4)**: WebRTC로 전환
- 같은 WiFi: ICE가 로컬 후보 선택 (현재와 동일 성능)
- 원격: STUN/TURN으로 P2P 연결
- 시그널링 서버: Firebase (Phase 3에서 연동)
- 연결 계층을 추상화하여 TCP → WebRTC 교체 시 상위 코드 변경 없음

```dart
// 연결 계층 추상화
abstract class ConnectionService {
  Future<void> connect(String peerId);
  void send(Uint8List data);
  Stream<Uint8List> get onData;
}

class TcpConnection implements ConnectionService { ... }     // Phase 1~2
class WebRtcConnection implements ConnectionService { ... }  // Phase 4
```

### 2. 오디오 소스 공유

**기존 방식 (제거 예정)**: Base64 인코딩 + 32KB 청크 + JSON 전송
- 문제: 33% 오버헤드, 제어 채널 간섭, 전체 다운로드 후 재생, 복잡한 워크어라운드

**새 방식: HTTP 서버**
- 호스트가 로컬 HTTP 서버 오픈 (같은 WiFi 내, 인터넷 불필요)
- 게스트에게 URL만 전달 → just_audio가 스트리밍 재생
- 다운로드 완료 전에도 재생 가능 (스트리밍)
- Base64 인코딩, 청크, 세대 카운터 등 전부 불필요

**오디오 소스 유형**:

| 소스 | 공유 방법 |
|------|----------|
| 로컬 파일 | 호스트가 HTTP 서버로 제공 → URL 전달 |
| 외부 URL | URL 문자열만 전달 |

→ 결국 둘 다 **"URL을 공유한다"**로 통일

### 3. Offset 계산 (시간 동기화)

**원리**: 게스트가 호스트와의 시계 차이(offset)를 계산하여 시간 변환

```
게스트                          호스트
  |--- ping (t1) ------------->|
  |<-- pong (t1, hostTime) ----|

  RTT = t2 - t1
  offset = hostTime - (t1 + RTT/2)
  → guestTime + offset = hostTime
```

**초기 계산**: 방 입장 시 핑퐁 10회, best RTT 기준으로 offset 확정

**offset 유지**: 백그라운드에서 주기적으로 핑퐁 10회 재계산 (클럭 드리프트 보정)
- 네트워크 안정적 (RTT < 3ms): 간격 늘림 (60초)
- 네트워크 불안정: 간격 줄임 (10초)
- offset 급변 시: 즉시 집중 재계산
- 원격 확장 시 적응형 주기 조절이 더 중요해짐

**play 시점에 핑퐁 안 함**: 이미 유지 중인 offset으로 즉시 재생 시점 계산

### 4. 같은 타이밍에 재생

**기존 방식 (제거)**: 고정 2초 딜레이 + play 시마다 핑퐁 3회

**새 방식: 즉시 재생 + 경과 시간 계산**

```
호스트: play 버튼 → 즉시 재생 → { hostTime, positionMs } 전송

게스트: 수신 → 조건 체크
  ├── offset 계산 완료?
  ├── 오디오 로드 완료?
  └── 둘 다 완료 →
        경과시간 = (내 시간 + offset) - hostTime
        seek(positionMs + 경과시간) → play
```

- 고정 딜레이 없음, 호스트는 즉시 재생
- 게스트 준비 안 됐으면 준비 완료 후 같은 로직으로 진입
- **늦게 입장한 게스트도 동일한 로직** (별도 state-request 불필요)

**오디오 엔진 레이턴시 보정**:
- 방 입장 시 무음 play() 테스트 → engineLatency 측정
- play() 호출부터 position이 움직이기 시작하는 시점까지의 시간
- 같은 기기에서는 일정하므로 한 번 측정 후 재사용
- 재생 스케줄링 시 engineLatency만큼 보정

**게스트 방 입장 시 초기화 순서**:
```
1. 핑퐁 10회 → offset 계산
2. 무음 play() → engineLatency 측정
3. 오디오 로드 (HTTP 스트리밍)
4. 모두 완료 → play 신호 대기 or 이미 재생 중이면 바로 진입
```

### 5. 재생 중 싱크 보정

offset 보정(3번)과 별개 계층. offset은 시계 차이, 이건 재생 위치 차이.

**호스트 → 게스트 position 전송**: 5초마다 `{ hostTime, positionMs }` 전송

**게스트 보정 로직**:
```
호스트 position 추정 = positionMs + 경과시간
내 position과 비교 → 차이 계산

차이 < 20ms   → 무시 (충분히 정확)
차이 20~100ms → 재생 속도 조절로 서서히 보정
차이 > 100ms  → seek로 즉시 보정
```

**재생 속도 조절**:
- 뒤처짐: 1.02x로 재생 (초당 20ms 따라잡음)
- 앞서감: 0.98x로 재생 (초당 20ms 늦춤)
- 필요한 만큼만 조절 후 1.0x 복귀 (예: 50ms 뒤처짐 → 2.5초간 1.02x → 복귀)
- 2% 속도 변화는 사람이 인지 불가

**버퍼링 복구**: 5초 대기하지 않고 just_audio 버퍼링 종료 이벤트 감지 → 즉시 position 비교 → seek

**블루투스 레이턴시**: 수동 조절 슬라이더로 대응 (향후 추가)

## 아키텍처: 하이브리드 (P2P + 클라우드)

### 설계 원칙

- **오디오 싱크/전송은 P2P** → 같은 WiFi 내 직접 연결, 지연 최소화, 서버 트래픽 비용 0
- **인증/결제/분석은 클라우드 서버** → 수익화, 사용자 관리, 제품 개선

### 전체 구조

```
┌─────────────────────────────────────────────────┐
│                 클라우드 서버                      │
│          (인증 / 결제 검증 / 분석)                  │
│       Firebase Auth + Cloud Functions (TS)        │
└──────────┬──────────────────┬────────────────────┘
           │ 로그인/결제       │ 사용 통계
           │                  │
    ┌──────▼──────┐    ┌──────▼──────┐
    │  호스트 폰   │    │  참가자 폰   │
    │ TCP 서버 오픈 │◄───│ TCP 연결     │
    │             │───►│             │
    └─────────────┘    └─────────────┘
         같은 WiFi 내 P2P 직접 연결
      (디바이스 발견 / 오디오 전송 / 싱크)
```

### 왜 하이브리드인가

| 역할 | P2P (로컬) | 클라우드 서버 |
|------|-----------|-------------|
| 오디오 데이터 전송 | O | X (트래픽 비용 큼) |
| 재생 싱크 명령 | O | X (지연 발생) |
| 시간 동기화 | O (호스트 기준) | X |
| 사용자 인증 | X | O |
| 결제/구독 검증 | X (크랙 취약) | O (서버에서 영수증 검증) |
| 사용 통계/분석 | X | O |
| 원격 기능 (향후) | X | O |

## 기술 스택

| 구성 | 기술 | 이유 |
|------|------|------|
| 앱 | Flutter (Dart) | iOS/Android 하나의 코드베이스, 네이티브 성능 |
| P2P 통신 (현재) | `dart:io` (TCP/UDP 소켓) | 외부 의존 없이 로컬 네트워크 직접 통신 |
| P2P 통신 (향후) | WebRTC | 원격 P2P 지원, NAT traversal |
| 디바이스 발견 | UDP 브로드캐스트 | 같은 WiFi 내 호스트 자동 감지 |
| 오디오 재생 | `just_audio` | 정밀한 position 제어, 버퍼링 관리, 백그라운드 재생 |
| 오디오 서비스 | `audio_service` | 백그라운드 재생 + 잠금화면 컨트롤 |
| 파일 공유 | 로컬 HTTP 서버 | Base64 전송 대체, 스트리밍 재생 가능 |
| 파일 선택 | `file_picker` | 로컬 음원 파일 선택 |
| 상태 관리 | `riverpod` | 간결하고 테스트 가능한 상태 관리 |
| 클라우드 (인증/결제) | Firebase Auth + Cloud Functions (TypeScript) | 빠른 구축, 확장 가능, Flutter 공식 연동 |
| 분석 | Firebase Analytics | 사용 패턴 수집 |

## P2P 프로토콜 정의

### 메시지 포맷 (JSON over TCP)

```json
{
  "type": "이벤트명",
  "data": { ... },
  "timestamp": 1234567890
}
```

### 이벤트 목록

| 이벤트 | 방향 | 데이터 | 설명 |
|--------|------|--------|------|
| `join` | 참가->호스트 | `{ name }` | 방 입장 |
| `welcome` | 호스트->참가 | `{ peerId, peerList }` | 입장 승인 + 참가자 목록 |
| `peer-joined` | 호스트->전체 | `{ peerId, name }` | 새 참가자 알림 |
| `peer-left` | 호스트->전체 | `{ peerId }` | 참가자 퇴장 알림 |
| `sync-ping` | 참가->호스트 | `{ t1 }` | 시간 동기화 ping |
| `sync-pong` | 호스트->참가 | `{ t1, hostTime }` | 시간 동기화 pong |
| `audio-url` | 호스트->전체 | `{ url }` | 오디오 URL 공유 (HTTP 서버 URL 또는 외부 URL) |
| `play` | 호스트->전체 | `{ hostTime, positionMs }` | 재생 (호스트 시간 + position) |
| `pause` | 호스트->전체 | `{ positionMs }` | 일시정지 |
| `seek` | 호스트->전체 | `{ hostTime, positionMs }` | 탐색 |
| `sync-position` | 호스트->전체 | `{ hostTime, positionMs }` | 재생 중 position 동기화 (5초마다) |
| `volume` | 로컬 전용 | - | 각 디바이스 개별 볼륨 (전송 불필요) |

### 제거된 이벤트 (v2에서 불필요)

| 이벤트 | 제거 이유 |
|--------|----------|
| `audio-meta` | HTTP 서버 방식으로 전환, 파일 메타 전송 불필요 |
| `audio-transfer` | HTTP 서버 방식으로 전환, 청크 전송 불필요 |
| `audio-request` | HTTP URL 공유로 대체 |
| `state-request/response` | play 메시지의 hostTime+position으로 통합 |

## 화면 구성

### 홈 화면 (HomeScreen)
- **방 만들기** 버튼 → 방 코드 + "대기 중..." 표시
- **방 참가** → 자동 감지된 방 목록 or 코드 입력
- 로그인 상태 표시

### 플레이어 화면 (PlayerScreen)
- 호스트 전용: 파일 선택 버튼, URL 입력 필드
- 공통: 재생/일시정지, 시크바, 현재 재생 시간
- 접속자 목록 + 싱크 상태 표시
- 볼륨 조절 슬라이더

### 설정 화면 (SettingsScreen)
- 계정 관리
- 구독 상태 / 결제
- 오디오 출력 설정
- 오디오 지연 보정 슬라이더 (블루투스 등, 향후 추가)

## 수익화 전략

### 프리미엄 모델 (추천)

| 기능 | 무료 | 프리미엄 |
|------|------|---------|
| 동시 연결 디바이스 | 2대 | 무제한 |
| 재생 시간 | 30분/세션 | 무제한 |
| 오디오 품질 | 표준 | 고음질 (무손실) |
| 이퀄라이저 | X | O |
| 스테레오 분리 | X | O |
| 광고 | 배너 | 없음 |

### 결제 검증 흐름

```
앱 → 앱스토어/플레이스토어 결제 → 영수증 → Cloud Functions에서 검증 → 프리미엄 활성화
```

## 고려사항 / 한계

- **네트워크**: 같은 WiFi 필수 (Phase 4에서 WebRTC로 원격 지원 예정)
- **iOS 백그라운드**: `audio_service` 설정 + Info.plist에 background mode 추가 필요
- **Android 백그라운드**: foreground service 알림 필요
- **오디오 포맷**: mp3, m4a, wav, ogg, flac 등 `just_audio` 지원 포맷
- **방화벽/AP 격리**: 일부 공용 WiFi에서는 P2P 차단될 수 있음
- **로컬 네트워크 권한**: iOS 14+에서 로컬 네트워크 접근 권한 팝업 필요
- **블루투스 레이턴시**: 자동 보정 어려움, 수동 슬라이더로 대응 예정

## 출시 전략

Flutter 앱만으로 핵심 기능이 전부 동작 (서버 불필요) → 무료 앱 먼저 출시 → 유저 반응 확인 → Firebase 붙여서 수익화

```
Phase 1~2: Flutter 앱만 개발 → 무료 출시 (서버 비용 0원)
Phase 3:   유저 반응 좋으면 → Firebase 연동해서 프리미엄 모델 도입
Phase 4:   확장 기능 추가
```

## 구현 순서 (MVP → 확장)

### Phase 1: MVP (Flutter 앱만, 서버 없음) → 출시 가능
- [x] P2P 연결 (TCP 소켓 + UDP 디바이스 발견)
- [x] 시간 동기화
- [x] 오디오 파일 공유 + 동기화 재생/일시정지
- [x] 기본 UI (홈 + 플레이어)

### Phase 2: 안정화 + 핵심 기술 개선 (Flutter 앱만, 서버 없음) → 업데이트
- [ ] 오디오 공유 방식 변경 (Base64 청크 → 로컬 HTTP 서버)
- [ ] offset 계산 개선 (10회 핑퐁 + 백그라운드 주기적 재계산)
- [ ] 동기화 재생 개선 (2초 딜레이 제거 → 즉시 재생 + 경과 시간 계산)
- [ ] 재생 중 싱크 보정 (5초마다 position 비교 + 속도 조절/seek)
- [ ] engineLatency 측정 및 보정
- [ ] 연결 계층 추상화 (향후 WebRTC 전환 대비)
- [ ] 백그라운드 재생
- [ ] 연결 끊김 시 자동 재연결
- [ ] 에러 처리 + UX 개선

### Phase 3: 수익화 (Firebase 연동 시작)
- [ ] Firebase 인증 + 결제 연동
- [ ] 프리미엄 기능 게이팅
- [ ] Firebase Analytics 연동

### Phase 4: 확장
- [ ] WebRTC 전환 (원격 P2P 지원)
- [ ] 볼륨 개별 제어 (디바이스별)
- [ ] 스테레오 분리 (L/R 채널 할당)
- [ ] 재생 목록 (Playlist)
- [ ] QR 코드로 방 참가
- [ ] 이퀄라이저
- [ ] 블루투스 레이턴시 수동 보정 슬라이더
