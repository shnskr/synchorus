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

#### 2026-04-05 작업 내역

**백그라운드 오디오 구현 (audio_service 패키지)**
- [x] `audio_handler.dart` 신규 생성 — `BaseAudioHandler` 구현, 알림바/잠금화면 재생 컨트롤
- [x] AndroidManifest에 FOREGROUND_SERVICE, AudioService, MediaButtonReceiver 등록
- [x] iOS Info.plist에 백그라운드 오디오 모드 추가
- [x] MainActivity를 FlutterFragmentActivity로 변경
- [x] `pipe()` → `listen()` 변경 (super.stop() 충돌 해결, 방 나가기 시 ANR 수정)
- [x] 앱 종료 시 알림 안 사라지는 문제 수정 (room_screen dispose에서 clearTempFiles 호출)

**싱크 보정 로직 변경**
- [x] speed 보정(1.05/0.95) 전체 제거 → seek만 사용으로 변경 (speed 보정이 수렴 안 됨)
- [x] 임계값: 20ms 미만 무시, 20ms 이상 즉시 seek
- [x] seek 후 1초 쿨다운 추가 (버퍼링 복구/sync-position 충돌 방지)
- [x] 500ms 후 post-play 보정 제거 (5초마다 sync-position으로 충분)

**게스트 즉시 퇴장 감지**
- [x] 게스트 disconnect 시 `leave` 메시지 전송 → 호스트가 즉시 peer 제거

**코드 품질**
- [x] discovery_service: `int.parse` → `int.tryParse` null 안전 처리
- [x] player_screen: `double.infinity` → `double.maxFinite`, 빈 initState 제거
- [x] sync_service: periodic sync 에러 로깅 추가
- [x] audio_service 내부 플레이어 호출에 await 추가 (race condition 방지)
- [x] `_onMessage` async + try-catch 래핑

**문서**
- [x] TEST_SCENARIOS.md 신규 작성 (10개 테스트 시나리오)

#### 2026-04-05 코드 리뷰 및 Phase 2 안정화

**코드 리뷰 버그 수정**
- [x] welcome 메시지 소실 방지 (broadcast stream을 connect 전에 먼저 listen)
- [x] SyncService 상태 초기화 (`reset()` 추가, 방 나가기 시 offset/RTT/synced 클리어)
- [x] join 아닌 첫 메시지 수신 시 소켓 즉시 끊기 (잘못된 클라이언트 방어)
- [x] discovery_service socket 누수 방지 (startBroadcast/discoverHosts 호출 시 기존 소켓 먼저 정리)
- [x] room_screen dispose에서 `cleanupSync()` 사용 (async 누락 문제 해결)

**자동 재연결**
- [x] 게스트 연결 끊김 시 자동 재연결 3회 시도 (1/2/3초 간격)
- [x] 재연결 후 재동기화 + 오디오 상태 복원 (`_reconnectSync` — 엔진 레이턴시 재측정 스킵)
- [x] WiFi 끊김 시 게스트 15초간 복구 대기 (3초 간격 체크) → WiFi 복구 시 자동 재연결

**에러 처리 + UX 개선**
- [x] 동기화 실패 시 "동기화 재시도" 버튼 표시
- [x] 호스트 URL 로드 실패 시 SnackBar 에러 메시지
- [x] 게스트 오디오 URL 로드 실패 시 2초 후 자동 재시도 + 실패 시 `errorStream`으로 UI 알림
- [x] `const` 누락 수정 (home_screen SnackBar)

#### 2026-04-06 작업 내역

**싱크 보정 로직 대폭 개선**
- [x] 임계값 20ms → 30ms로 변경 (30ms 미만 무시, 30ms 이상 seek)
- [x] 속도 조절(1.05/0.95) 재시도 후 최종 제거 — 에뮬레이터에서 `setSpeed(1.05)` 시 오히려 차이 증가 확인
- [x] `_commandSeq` 패턴 도입 — 빠른 재생/정지 반복 시 stale async 무효화
- [x] `_syncSeeking` 플래그 — sync-position 보정 중 재진입 방지
- [x] 버퍼링 복구 2초 쿨다운 — seek 후 버퍼링→ready 전환 감지, 연쇄 반응 방지
- [x] pause는 동기 처리 (await 안 함) — 즉시 정지 보장

**엔진 출력 레이턴시 보정**
- [x] 플랫폼 채널로 엔진 레이턴시 측정 (Android: AudioManager, iOS: AVAudioSession)
- [x] 호스트가 play/sync-position/seek 메시지에 `engineLatencyMs` 포함
- [x] 게스트가 `(myLatency - hostLatency)` 만큼 position 보정
- [x] S22: ~4ms, 에뮬레이터: ~22ms → 게스트가 18ms 앞서서 재생하여 스피커 출력 시점 맞춤

**seek 레이턴시 대칭화**
- [x] 호스트 `syncPlay()`에서 `seek(현재position) → play()` 순서로 변경
- [x] 호스트/게스트 모두 동일한 seek → play 경로를 타서 seek 소요시간 상쇄

**state-request 방식으로 전환**
- [x] `_pendingPlay` 제거 → `_hostPlaying` 플래그로 교체
- [x] 게스트 준비 미완료 시 play/pause → 플래그만 저장, 시간 값 무시
- [x] 게스트 준비 완료 시 `_hostPlaying == true`면 `state-request` → 호스트가 최신 상태 응답
- [x] `state-request` / `state-response` 프로토콜 추가
- [x] 모든 `audio-url` 메시지에 `playing` 상태 포함 (최초 입장 시 `_hostPlaying` 설정)
- [x] `_handleSeek`, `_handlePause`에 `_audioReady` 가드 추가
- [x] `_handleStateResponse`에 idle 상태 체크 + 오디오 재로드 추가
- [x] `sendCurrentAudioToPeer`에서 play 메시지 직접 전송 제거 (게스트가 알아서 요청)

**오디오 에러 복구**
- [x] seek 중 404 에러 시 자동 오디오 재로드 (`_reloadAudio`)
- [x] play 시 플레이어 idle/에러 상태 감지 → 자동 재로드
- [x] 재로드 실패 시 호스트에게 `audio-request` 재요청

**UX 개선**
- [x] 로그 자동 스크롤 (새 로그 추가 시 맨 아래로, 수동 스크롤 시 자동 스크롤 중지, 다시 아래로 내리면 재개)

**버퍼링 복구 state-request 전환**
- [x] 버퍼링 복구 시 캐시 데이터(`_lastSyncPositionMs`) 기반 seek → `state-request`로 변경
  - 기존 문제: 호스트가 버퍼링 도중 seek/pause/play 시 캐시가 stale → 틀린 위치로 복구
  - 수정: 버퍼링 복구 시 호스트에게 최신 상태 요청 → 정확한 위치로 seek
- [x] `_lastSyncHostTime`, `_lastSyncPositionMs` 캐시 변수 제거 (더 이상 사용하지 않음)

**syncSeek 순서 수정**
- [x] `syncSeek()`에서 seek → broadcast 순서를 broadcast → seek으로 변경
  - 기존 문제: 호스트가 seek 완료 후 시간을 찍으므로, seek 소요시간만큼 게스트와 비대칭
  - `syncPlay()`는 이미 올바른 순서(broadcast 먼저)였으나 `syncSeek()`만 반대였음

#### 알려진 이슈 / 다음에 확인할 것
- [ ] 엔진 레이턴시 보정값이 실제와 약간 차이 (에뮬 기준 ~10ms 오차) — 수동 보정 슬라이더 추가 예정
- [ ] 호스트 백그라운드 진입 시 파일 서버 연결 끊김 → 게스트 seek 시 404 (자동 재로드로 대응)
- [ ] 디버그 모드에서 호스트 플레이어 간헐적 스터터 (position이 실시간보다 느리게 진행)
- [ ] 호스트 파일선택 창 열고 있는 동안 게스트 입퇴장 시 안정성 (추가 테스트 필요)
- [x] 대용량 파일 전송 중 TCP 연결 끊김 (청크 32KB, 딜레이 20ms로 조정, 20MB 테스트 통과)
- [x] 호스트가 재생 중 파일 로드 시 가끔 호스트만 재생 안 되는 현상 (원인: file_picker 캐시 삭제 → 앱 임시 디렉토리에 복사하여 해결)
- [x] 에뮬레이터 ↔ 실기기 간 네트워크 (UDP 브로드캐스트 불가 → IP 직접 입력으로 연결 가능)
- [x] 에뮬레이터 싱크 ~100ms 차이 — 엔진 레이턴시 보정으로 해결 (diff 10~20ms 수준으로 개선)

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

### 3. 핵심 로직: 동기화 재생

여러 기기에서 같은 음악을 **동시에** 들리게 하는 것이 이 앱의 핵심.
"소프트웨어상 같은 position" ≠ "실제로 같은 타이밍에 소리가 남". 이 차이를 줄이는 게 전부.

#### 3-1. 동기화에 관여하는 모든 지연시간

호스트가 Play를 누른 순간부터 게스트 스피커에서 소리가 나기까지의 전체 경로:

```
호스트 Play 누름
  │
  ├─ [1] JSON 직렬화 + TCP 송신 버퍼      ─┐
  ├─ [2] WiFi 네트워크 전송                 ├─ 메시지 전달 구간
  ├─ [3] TCP 수신 버퍼 + JSON 역직렬화      ─┘
  │
  ├─ [4] seek 처리 (디코더 재위치, 버퍼 flush/refill)
  ├─ [5] play() → 오디오 엔진 디코딩
  ├─ [6] 오디오 출력 버퍼 (ringbuffer)      ─┐
  ├─ [7] DAC 출력 레이턴시                   ├─ engineLatency
  └─ [8] 스피커 물리적 지연 (~무시 가능)      ─┘
```

#### 3-2. 보정 현황

| 지연 요소 | 보정 방법 | 상태 |
|---|---|---|
| **시계 차이 (clock offset)** | RTT/2 기반 핑퐁 10회, best RTT 채택 | **보정됨** |
| **메시지 전달 지연 [1][2][3]** | `elapsed = nowAsHostTime - hostTime` | **보정됨** |
| **기기 간 engineLatency 차이 [6][7]** | `내 engineLatency - 호스트 engineLatency` | **보정됨** |
| **seek 비용 비대칭 [4]** | 호스트도 동일하게 seek → play 경로 (양쪽 상쇄) | **보정됨** |
| 오디오 엔진 디코딩 [5] | API로 측정 불가, 기기마다 비슷하므로 양쪽 상쇄 | 측정 불가 |
| 네트워크 비대칭 (업/다운 속도 차이) | RTT/2가 정확하지 않은 원인, 통계적으로만 줄일 수 있음 | 측정 불가 |
| 클럭 드리프트 | 30초 주기 재동기화 + 5초마다 sync-position 보정 | 간접 대응 |
| GC / 스레드 스케줄링 지터 | OS 레벨, 제어 불가 | 간접 대응 |
| 백그라운드 throttling | foreground service로 대응 | 간접 대응 |
| 블루투스 출력 레이턴시 | 수동 보정 슬라이더 (향후 추가) | 미구현 |

**핵심 원칙**: 측정 가능한 것은 계산으로 보정하고, 측정 불가능한 것은 호스트/게스트가 동일한 경로를 타게 하여 상쇄시킨다.

#### 3-3. 시계 동기화 (clock offset)

게스트가 호스트와의 시계 차이를 계산하여, 이후 모든 시간 계산의 기반이 됨.

```
게스트                          호스트
  |--- ping (t1) ------------->|
  |<-- pong (t1, hostTime) ----|

  RTT = t2 - t1
  offset = hostTime - (t1 + RTT/2)
  → guestTime + offset = hostTime
```

- **초기 계산**: 방 입장 시 핑퐁 10회, best RTT 기준으로 offset 확정
- **offset 유지**: 백그라운드에서 주기적으로 핑퐁 10회 재계산 (클럭 드리프트 보정)
- **한계**: RTT/2는 네트워크 대칭을 가정. 업/다운 속도가 다르면 오차 발생 (측정 불가)

#### 3-4. 엔진 레이턴시 측정

play() 호출 후 실제 스피커에서 소리가 나기까지의 시간. OS API로 측정.

- Android: `AudioManager.getProperty(OUTPUT_LATENCY)` + `framesPerBuffer / sampleRate`
- iOS: `AVAudioSession.outputLatency` + `ioBufferDuration`

**포함**: 오디오 출력 버퍼 + DAC 변환 대기
**미포함**: 오디오 엔진 디코딩 시간 (API 없음, 측정 불가 → 양쪽 상쇄로 대응)

#### 3-5. 호스트 동작

호스트는 시간의 기준. 계산 없이 실행하고 알려주기만 함.

**Play**: seek(현재position) → play() → 메시지 전송 `{ hostTime, positionMs, engineLatencyMs }`
**Pause**: pause() → 메시지 전송 `{ positionMs }`
**Seek**: 메시지 전송 `{ hostTime, positionMs, engineLatencyMs }` → seek(position)
**5초마다**: sync-position 브로드캐스트 `{ hostTime, positionMs, engineLatencyMs }`
**sync-ping 수신**: sync-pong 응답
**state-request 수신**: 현재 상태 응답 `{ hostTime, positionMs, playing, engineLatencyMs }`

#### 3-6. 게스트 동작 — 상태별 케이스

모든 계산은 게스트에서 일어남. 게스트 상태에 따라 처리가 달라짐.

**게스트 상태 정의**:
```
준비 단계:
  [A] TCP 연결만 됨 (offset 미계산, 오디오 미로드)
  [B] offset 계산 완료, 오디오 미로드 또는 로드 중
  [C] 모두 준비 완료 (offset 계산 + 오디오 로드 완료)

재생 상태:
  [C-1] 준비 완료, 정지 중
  [C-2] 준비 완료, 재생 중
```

**게스트 플래그**: `_hostPlaying` — 호스트가 재생 중인지 여부
- play 수신 → `_hostPlaying = true`
- pause 수신 → `_hostPlaying = false`

---

##### 케이스 1: 준비 완료 상태에서 play 수신 [C-1 → C-2]

가장 정확한 케이스. elapsed가 네트워크 지연 수준으로 최소.

```
호스트: play 전송 (hostTime, positionMs, engineLatencyMs)
게스트: 수신
  _hostPlaying = true
  elapsed = nowAsHostTime - hostTime              ← 네트워크 지연만 (~20ms)
  latencyCompensation = 내 engineLatency - 호스트 engineLatency
  targetPosition = positionMs + elapsed + latencyCompensation
  seek(targetPosition) → play()
```

**타임라인 예시** (offset=-10ms, 네트워크 20ms, seek 15ms, 호스트 engineLatency 15ms, 게스트 10ms):
```
호스트:
  10:00:00.000  Play 누름, 메시지 전송, seek(5000ms)  15ms
  10:00:00.015  play(), engineLatency                  15ms
  10:00:00.030  소리 출력 (position ~5030ms)

게스트:
  10:00:00.020  메시지 수신, elapsed=20ms, target=5015ms
                seek(5015ms)                           15ms
  10:00:00.035  play(), engineLatency                  10ms
  10:00:00.045  소리 출력 (position ~5025ms)

결과: 5030ms vs 5025ms = ~5ms 차이 (측정 불가능한 영역)
```

##### 케이스 2: 준비 미완료 중 play 수신 [A/B → 나중에 C]

게스트가 아직 준비 중일 때 호스트가 play를 보낸 경우. **시간 값은 무시하고 상태만 기억**.

```
호스트: play 전송
게스트: 준비 안 됨
  _hostPlaying = true                   ← 상태만 저장, hostTime/positionMs 무시
  (offset 계산 중... 오디오 로드 중...)
  
  준비 완료!
  _hostPlaying == true → 호스트에게 state-request 전송
  호스트: 응답 (hostTime=지금, positionMs=지금position, playing=true, engineLatencyMs)
  게스트: elapsed = 네트워크 지연만 (~20ms) ← 오래된 값이 아니라 최신 값!
  targetPosition = positionMs + elapsed + latencyCompensation
  seek(targetPosition) → play()
```

**기존 방식과의 차이**:
```
기존: play 수신 → pendingPlay에 저장 → 준비 완료 후 오래된 hostTime으로 계산
      elapsed = 네트워크 지연 + 대기 시간 (수초~수십초) → 부정확

새 방식: play 수신 → 플래그만 저장 → 준비 완료 후 최신 상태 요청
         elapsed = 네트워크 지연만 (~20ms) → 항상 정확
```

##### 케이스 3: 준비 완료 상태에서 pause 수신 [C-2 → C-1]

```
호스트: pause 전송 (positionMs)
게스트:
  _hostPlaying = false
  pause()
  seek(positionMs)     ← 호스트와 같은 위치로 맞춤
```

##### 케이스 4: 준비 미완료 중 pause 수신 [A/B]

```
호스트: pause 전송
게스트: _hostPlaying = false     ← 상태만 저장
  준비 완료 후 _hostPlaying == false → 아무것도 안 함 (대기)
```

##### 케이스 5: 준비 완료, 재생 중 seek 수신 [C-2]

```
호스트: seek 전송 (hostTime, positionMs, engineLatencyMs)
게스트:
  재생 중이면:
    elapsed = nowAsHostTime - hostTime
    targetPosition = positionMs + elapsed + latencyCompensation
    seek(targetPosition) → play()
  정지 중이면:
    seek(positionMs)    ← 단순 위치 이동만
```

##### 케이스 6: 재생 중 sync-position 수신 [C-2]

5초마다 호스트가 보내는 위치 보정 신호.

```
호스트: sync-position (hostTime, positionMs, engineLatencyMs)
게스트:
  expectedPosition = positionMs + elapsed + latencyCompensation
  diff = expectedPosition - 내 position

  diff < 30ms   → 무시
  diff >= 30ms  → seek(expectedPosition)
```

**안전장치**:
- `_syncSeeking`: seek 진행 중 다음 sync-position 무시
- `_lastBufferingRecovery`: 버퍼링 복구/seek 후 2초 쿨다운
- `_commandSeq`: 빠른 재생/정지 반복 시 stale async 무효화

##### 케이스 7: 재생 중 버퍼링 발생 후 복구 [C-2]

네트워크 지연으로 HTTP 스트리밍 버퍼가 비어서 재생이 멈췄다가 복구된 경우.

```
버퍼링 발생 → 재생 멈춤
버퍼 채워짐 → ready 전환 감지
  state-request → 호스트가 최신 상태 응답 → seek(보정position)
  (2초 쿨다운: 연쇄 반응 방지)
```

##### 케이스 8: 재생 중 오디오 에러 (404 등) [C-2]

호스트 백그라운드 진입 등으로 HTTP 서버 연결이 끊긴 경우.

```
seek 중 에러 발생
  → _reloadAudio() (URL 다시 로드 시도)
  → 실패 시 호스트에게 audio-request 재요청
  → URL 수신 → 로드 → state-request → seek → play
```

##### 케이스 9: 재생 중 네트워크 끊김 → 재연결 [C-2 → A → C]

```
네트워크 끊김 감지
  → 자동 재연결 3회 시도 (1/2/3초 간격)
  → WiFi 끊김이면 15초간 복구 대기
  → 재연결 성공
  → 핑퐁 10회 재동기화
  → state-request → 최신 상태 수신 → seek → play
```

##### 케이스 10: 늦은 입장 (호스트 이미 재생 중) [A → B → C]

별도 처리 없음. 케이스 2와 동일한 흐름.

```
게스트 입장 → offset 계산 → 오디오 로드
준비 완료 → _hostPlaying == true → state-request → seek → play
```

#### 3-7. Play 신호 타임라인 — 정리

```
호스트 Play 누름
  │
  ├─ 호스트: seek(position) → play() → 메시지 전송
  │
  ├─ 게스트 (준비 완료):
  │    메시지 수신 → elapsed 계산 → seek(보정position) → play()
  │
  └─ 게스트 (준비 미완료):
       _hostPlaying = true (상태만 저장)
       ... 준비 완료 ...
       state-request → 최신 상태 수신 → seek(보정position) → play()
```

#### 3-8. 재생 중 싱크 유지 구조

```
[시계 동기화 계층]     30초마다 핑퐁 10회 → offset 갱신
        ↓
[위치 보정 계층]       5초마다 sync-position → 30ms 이상 차이 시 seek
        ↓
[버퍼링/에러 복구]     버퍼링 복구 시 state-request로 최신 상태 수신, 에러 시 재로드
```

#### 3-9. 게스트 방 입장 시 초기화 순서

```
1. TCP 연결
2. 핑퐁 10회 → clock offset 계산
3. 엔진 레이턴시 측정 (플랫폼 채널)
4. 호스트에게 audio-request → URL 수신 → 오디오 로드 (HTTP 스트리밍, 메타+초기 버퍼)
5. 준비 완료 → _hostPlaying 확인
   ├── true  → state-request → 최신 상태 수신 → seek → play
   └── false → 대기
```

#### 3-10. 설계 결정 기록

| 결정 | 이유 |
|---|---|
| 속도 조절(1.05x/0.95x) 제거 | 에뮬레이터에서 setSpeed(1.05) 시 오히려 차이 증가, 실기기에서도 보장 불가 |
| seek 단일 보정 방식 | 속도 조절보다 예측 가능하고 즉시 반영됨 |
| 호스트도 seek → play | seek 소요시간을 측정하지 않고도 양쪽 상쇄로 해결 |
| 준비 미완료 시 state-request | pendingPlay의 오래된 hostTime 대신 최신 값을 받아 elapsed 최소화 |
| _hostPlaying 플래그 | 준비 미완료 중 play/pause 상태를 추적, 준비 완료 후 적절히 대응 |
| 버퍼링 복구 시 state-request | 캐시 데이터는 호스트 seek/pause 시 stale → 항상 최신 상태 요청 |
| syncSeek도 broadcast 먼저 | syncPlay와 동일하게 시간 찍고 메시지 먼저 → seek (seek 비용 대칭화) |
| 임계값 30ms | 20ms에서 상향 — 너무 민감하면 불필요한 seek 빈발 |
| sync-position 5초 간격 | 드리프트/지터를 주기적으로 잡되, 너무 잦으면 seek 과다 |
| bestRtt는 로그 전용 | offset 선택 기준으로만 사용, 이후 계산에 미사용 |
| 블루투스 레이턴시 | engineLatency에 미포함, 수동 슬라이더로 대응 예정 |

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
| `audio-url` | 호스트->전체 | `{ url, playing }` | 오디오 URL 공유 + 현재 재생 상태 |
| `play` | 호스트->전체 | `{ hostTime, positionMs, engineLatencyMs }` | 재생 (호스트 시간 + position + 엔진 레이턴시) |
| `pause` | 호스트->전체 | `{ positionMs }` | 일시정지 |
| `seek` | 호스트->전체 | `{ hostTime, positionMs, engineLatencyMs }` | 탐색 |
| `sync-position` | 호스트->전체 | `{ hostTime, positionMs, engineLatencyMs }` | 재생 중 position 동기화 (5초마다) |
| `state-request` | 참가->호스트 | `{}` | 게스트가 준비 완료 후 호스트의 최신 상태 요청 |
| `state-response` | 호스트->참가 | `{ hostTime, positionMs, playing, engineLatencyMs }` | 호스트의 현재 재생 상태 응답 |
| `volume` | 로컬 전용 | - | 각 디바이스 개별 볼륨 (전송 불필요) |

### 제거된 이벤트 (v2에서 불필요)

| 이벤트 | 제거 이유 |
|--------|----------|
| `audio-meta` | HTTP 서버 방식으로 전환, 파일 메타 전송 불필요 |
| `audio-transfer` | HTTP 서버 방식으로 전환, 청크 전송 불필요 |
| `audio-request` | ~~HTTP URL 공유로 대체~~ → 다시 활용 (게스트 동기화 완료 후 현재 오디오 요청, 에러 복구 시 재요청) |
| `state-request/response` | ~~play 메시지의 hostTime+position으로 통합~~ → 다시 활용 (게스트 준비 완료 후 최신 상태 요청, pendingPlay 대체) |

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
- [x] 오디오 공유 방식 변경 (Base64 청크 → 로컬 HTTP 서버)
- [x] offset 계산 개선 (10회 핑퐁 + 백그라운드 주기적 재계산)
- [x] 동기화 재생 개선 (2초 딜레이 제거 → 즉시 재생 + 경과 시간 계산)
- [x] 재생 중 싱크 보정 (5초마다 position 비교 + seek 보정)
- [x] engineLatency 측정 및 보정 (플랫폼 채널 + 호스트-게스트 차이 보정)
- [x] 백그라운드 재생 (audio_service + 알림바/잠금화면 컨트롤)
- [ ] 연결 계층 추상화 (향후 WebRTC 전환 대비, Phase 4에서 진행)
- [x] 연결 끊김 시 자동 재연결
- [x] 에러 처리 + UX 개선

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
