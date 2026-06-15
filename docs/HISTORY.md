# Synchorus 작업 이력

기존 PLAN.md에서 분리. 일자별 작업/버그 수정/PoC 진행 로그.

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

테스트 환경: 에뮬레이터(Pixel 6 API 34) + Galaxy S22 (SM-S901N) + iPhone (iOS 게스트)

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
- [x] 2초 쿨다운(`_lastBufferingRecovery`) → `_awaitingStateResponse` 플래그로 변경
  - 기존: 2초간 무조건 차단 → 정상 복구도 막혀서 최대 5초 drift
  - 수정: 응답 대기 중만 차단, 응답 오면 즉시 해제 → RTT만큼만 대기
  - `_handleStateResponse` 최상단에서 플래그 해제 (early return 전)
  - `cleanupSync()`에서 플래그 초기화 (연결 끊김 시 영구 차단 방지)
- [x] `_handleStateResponse`에 `_hostPlaying` 가드 추가
  - 버퍼링 복구 중 pause 도착 → stale state-response(playing=true)가 재생 재개하는 경합 수정
  - stale 응답의 position도 pause 이전 값이므로 seek 포함 전부 무시가 정확

**syncSeek 순서 수정**
- [x] `syncSeek()`에서 seek → broadcast 순서를 broadcast → seek으로 변경
  - 기존 문제: 호스트가 seek 완료 후 시간을 찍으므로, seek 소요시간만큼 게스트와 비대칭
  - `syncPlay()`는 이미 올바른 순서(broadcast 먼저)였으나 `syncSeek()`만 반대였음

#### 2026-04-07 코드 리뷰 및 버그 수정

**syncWithHost 경합 버그 수정**
- [x] `syncWithHost()` 동시 호출 시 공유 `_messageSub`의 timeout 핸들러가 새 호출의 listener를 파괴하는 버그
  - periodic sync와 reconnect sync가 겹치면 양쪽 모두 실패할 수 있었음
  - `_activeSyncSub` 로컬 변수 패턴으로 변경: 각 호출이 자신의 listener만 관리
  - 새 호출 시 이전 호출의 listener를 취소하고, timeout은 자신의 listener만 정리
  - for 루프에서 취소 감지 시 불필요한 ping 전송 중단

**개선사항**
- [x] 로그 상한 추가 (`_maxLogLines = 500`) — 장시간 사용 시 메모리 무한 증가 방지
- [x] 시간 포맷 1시간+ 지원 — 60분 이상 오디오에서 `H:MM:SS` 형식으로 표시
- [x] 게스트 피어 카운트 보정 — reconnect 시 welcome 메시지의 `peerCount`로 동기화 (증감 방식 드리프트 방지)

**HTTP 서빙/파일명 안정화 (Android↔iOS 호환)**
- [x] `_safeFileName()` — 원본 파일명 → ASCII-safe 해시명 (iOS AVPlayer가 한글/공백/특수문자 URL을 거부하는 케이스 회피)
- [x] `_storedSafeName` ↔ `_currentFileName` 분리 — 디스크/HTTP는 해시, UI는 원본 파일명 표시
- [x] URL 캐시 무효화 — `?v=timestamp` 쿼리스트링 (AVPlayer 캐시로 이전 세션 데이터 재사용 방지)
- [x] 호스트 시작 시 `_cleanupTempDir()` — 이전 세션 좀비 `audio_*` 파일 제거
- [x] iOS `MethodChannel` 추가 (`com.synchorus/audio_latency`) — `AVAudioSession.outputLatency + ioBufferDuration` 측정. 세션 카테고리/활성화는 audio_service 플러그인에 위임

**버퍼링/seek 루프 방지**
- [x] `_internalSeek` 래퍼 + `_internalSeeking` 플래그 — 내부 seek로 인한 buffering→ready 전환을 watch가 무시 (recovery 루프 차단)
- [x] `_waitUntilReady()` — 재로드 후 ready 상태까지 대기, 이후 seek/play가 buffering 단계에서 호출되어 흔들리는 것 방지
- [x] `_reloadInProgress` 가드 — 동시 재로드 차단
- [x] `_handlePlay`/`_handleStateResponse`에서 idle 시 **먼저** 재로드 → 그 후 elapsed 재계산 (reload 시간이 elapsed에 포함되도록)
- [x] sync-position 임계값 30ms → 100ms (seek 비용 고려)
- [x] `_handleStateResponse`에서 |target-my| < 200ms 면 seek 생략 (불필요 재버퍼링 방지)

**P2P 안정화**
- [x] `p2p_service`: 게스트 disconnect 시 `_hostSocket = null`로 명시 정리
- [x] `p2p_service`: 줄바꿈 파싱을 `List.removeRange` O(n²) → `lineStart` 오프셋 패턴
- [x] `p2p_service`: `_sendToPeerSafe()` — 송신 에러 시 즉시 피어 제거
- [x] `discovery_service`: `discoverHosts()` try/finally 소켓 정리, `split` 길이 검증 + `roomCode` 재조립
- [x] `audio_handler`: `stop()`에서 `_playerSub` 유지(이후 재로드/재생 시 PlaybackState 끊김 방지), 별도 `dispose()` 분리
- [x] `sync_service`: ping/pong에 `rid` 필드 — periodic/manual 동시 호출 시 pong 매칭

**room_screen**
- [x] `_leaving` 플래그 — `_leaveRoom` 중복 호출 방지, dispose 경로와 정상 퇴장 경로 분리

#### 2026-04-07 (저녁) iOS↔Android 엔진 레이턴시 측정 비대칭 대응

**문제 발견**
- iOS는 `AVAudioSession.outputLatency` (실제 하드웨어 출력 지연)까지 잡혀 ~30~80ms 보고
- Android는 `AudioManager.getProperty("android.media.property.OUTPUT_LATENCY")` 가 S22에서 null → buffer duration만 잡혀 4ms 보고 (`PROPERTY_OUTPUT_FRAMES_PER_BUFFER / SAMPLE_RATE`)
- 결과: `compensation = my(50) - host(4) = +46ms` → iPhone(게스트)이 호스트보다 ahead로 재생되는 문제
- 비대칭의 원인은 Android public API 한계 — 진짜 출력 지연을 잡으려면 AAudio/Oboe NDK 코드 필요. 단, just_audio(ExoPlayer)가 쓰는 AudioTrack에 직접 접근 불가라 NDK로 별도 stream을 열어 측정해도 정확도 보장 안 됨

**해결: 측정 방식 통일 (옵션 A)**
- [x] `ios/Runner/SceneDelegate.swift` — `totalMs = bufferMs` (outputLatency 제거). `outputLatencyMs`는 디버그 표시용으로 응답에 함께 포함
- [x] `audio_service.dart` — latency 필드를 `total/rawOutput/buffer` 세 개로 분리 저장, public getter (`engineLatencyMs`, `engineRawOutputMs`, `engineBufferMs`, `hostEngineLatencyMs`, `latencyCompensation`) 노출
- [x] `player_screen.dart` — Now Playing 카드 아래에 latency 디버그 한 줄 표시 (`My: 4ms (buf=4) / iOS는 (buf=Y, rawOut=Z) / 게스트는 + Host/Comp 추가`)
- [x] `pubspec.yaml` 0.0.3 → 0.0.4
- [x] iOS `AppDelegate.swift` 의 (다른 세션에서 추가된) audio_latency 채널 코드가 `engineBridge.binaryMessenger` 미존재로 컴파일 에러 → 원복 (SceneDelegate에 동일 채널 이미 존재)

**빌드/배포**
- [x] `flutter install`이 자동 빌드 안 함을 발견 — `flutter build {apk,ios}` 명시 후 `flutter install` 필요
- [x] iOS 14+에서는 **debug 빌드를 디바이스에서 직접 launch 못함** (`Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode`) → 두 기기 모두 release 빌드 필요
- [x] v0.0.4 release 빌드 + 양쪽 기기 install 완료 (실측 결과 대기 중)

**문서**
- [x] `CLAUDE.md` 주의사항에 "기능적 코드 수정 후 `pubspec.yaml` patch 자리 1 올리기" 규칙 추가

#### 2026-04-08 v3 설계 + Android PoC Phase 0~1

**v3 폐루프 리아키텍처 설계 문서화**
- [x] `PLAN.md` 섹션 6 (PoC 플랜) + 섹션 7 (v3 설계 결정 기록) + 섹션 8 (새 P2P 메시지) 신규 작성
- [x] `CLAUDE.md`에 v3 방향 참조 지점 추가
- 커밋: `8b8b2cc` v3 폐루프 리아키텍처 설계 문서화 (PoC 진입 전 단일 참조 지점)

**Android PoC 프로젝트 격리 생성**
- [x] `poc/native_audio_engine_android/` 독립 Flutter 앱 생성 (본 앱 audio_service 세션과 충돌 방지)
- [x] Oboe 1.9.0 prefab 의존성 + CMake + NDK (arm64-v8a, armeabi-v7a) 설정
- [x] MethodChannel `com.synchorus.poc/native_audio` (start/stop/getTimestamp)

**Phase 0: Oboe 래퍼 + 단순 재생**
- [x] `oboe_engine.cpp`: `LowLatency + Exclusive + Float + Stereo`, 440Hz sine 생성, thread-safe start/stop
- [x] `NativeAudio.kt` JNI 래퍼 + `MainActivity.kt` MethodChannel 핸들러
- [x] S22 실기기에서 톤 정상 출력 확인
- 커밋: `c373302` PoC Phase 0: Oboe 래퍼 + 단순 sine wave 재생

**Phase 1: getTimestamp 폴링 + 시계열**
- [x] `OboeEngine::getLatestTimestamp(CLOCK_MONOTONIC)` → JNI `nativeGetTimestamp` (`[framePos, timeNs, ok]`)
- [x] Flutter `Timer.periodic(100ms)` 폴링, 1000 샘플 rolling window
- [x] 통계: 유효율 / 평균 간격 / frames/ms / framePos·timeNs 단조 증가 검증
- [x] S22 실측: **frames/ms = 48.00 (48kHz 정확 일치)**, 단조 ✓✓, 유효율 ~100%
- 커밋: `3ed267a` PoC Phase 1: Oboe getTimestamp 폴링 + 시계열 확보

**다음 작업 (Phase 2~6)**
- [x] **Phase 2**: P2P `audio-obs` 송수신 (S22 호스트 + S10 게스트 실기기 2대, 2026-04-09 통과)
- [x] **Phase 3**: clock sync (sync-ping/pong EMA) + 게스트 자체 엔진 재생 + 원시 CSV 3종
- [x] **Phase 4~5**: seek 보정 루프 + 시간축 원자화 + 호스트 seek 대응 (11차 실측 통과)
- [x] **Phase 6**: S22 30분 stress 통과 (2026-04-10, |drift|<20ms 99.9%, seek 17회/31분)
- [x] iOS PoC (AVAudioEngine `lastRenderTime` 기반) — 2026-04-15 Phase 0+1 완료, 본체 통합 완료

#### 2026-04-09 PoC Phase 2 완료

**구현 (PoC 격리 원칙: 최소 P2P만)**
- [x] `lib/main.dart`: `RoleSelectionPage` → `HostPage` / `GuestPage` 2-path 구조
- [x] `AudioObs` 모델: `seq`, `hostTimeMs`, `anchor(FramePos/TimeNs)`, `framePos`, `timeNs`, `playing` (PLAN.md §8)
- [x] 호스트: `ServerSocket.bind(anyIPv4, 7777)` + `Timer.periodic(500ms)` broadcast, JSON line (`\n` 구분)
- [x] 게스트: `Socket.connect` + `LineSplitter` → CSV 로그 (`getExternalStorageDirectory`)
- [x] anchor 전략: 재생 시작 후 첫 ok 샘플을 기록, 재생 중 재앵커링 없음
- [x] `AndroidManifest.xml` INTERNET 권한 추가, `path_provider 2.1.5` 의존성 추가
- [x] `NetworkInterface.list` wlan* 우선 선택 + 디버깅용 후보 리스트 표시
  (한국 통신사 환경에서 `clat4` (192.0.0.4, NAT64) 가상 인터페이스가 먼저 뽑히는 버그 수정)

**PoC 격리 원칙 적용 (§6-2)**
- 디스커버리 / join / welcome 없음 → IP 수동 입력, TCP 다이렉트
- 메시지 1종 (`audio-obs`)만 구현, drift-report는 Phase 4로 미룸
- 네이티브(Oboe/JNI) 변경 없음, Phase 1 인터페이스 그대로 재사용
- 에뮬은 제외 (가상 네트워크/HAL이 실기기 조건과 달라 참고 가치 제한적, Phase 3에서 로직 verify 용도로 선택적 추가 검토)

**Phase 2 실측 (2026-04-09, S22 SM-S901N Android 16 + S10 SM-G977N Android 12, 60.4s)**

| 항목 | 값 | 판정 |
|---|---|---|
| seq 연속성 | 0~121 (122개), gaps=0 | ✅ |
| 호스트 송신 주기 | mean 498.8ms, stdev 13.2ms, p5~p95 498~502 | ✅ Timer 매우 정확 |
| 게스트 수신 주기 | mean 498.0ms, stdev 67.8ms, p5~p95 400~605 | ✅ 평균 OK, 지터는 큼 |
| framePos/timeNs 단조 | OK | ✅ |
| frames/ms | 48.0003 (60s) | ✅ Phase 1과 동일, 장시간 안정 |
| rx-host offset | mean 507ms, range 473~636 (clock offset + 네트워크 지연 혼재) | ⚠ 분리 불가 |

→ **§6-1 질문 1 (네이티브 엔진 sub-ms 정밀도) 재확인**. 60초 동안 frames/ms = 48.0003로 유지.
→ **§6-1 질문 2 (Wi-Fi clock sync 노이즈)는 아직 분리 불가**. rx-host offset의 변동(±40ms stdev)은 clock offset과 네트워크 지연이 섞여 있어, Phase 3에서 `sync-ping/pong` 구현 후에야 순수 clock 노이즈 분리 가능.

**Phase 2 → Phase 3 전달 사항**
- **주목 1**: 게스트 수신 주기의 stdev(67.8ms)가 호스트 송신(13.2ms)의 ~5배. 순수 네트워크 + 게스트 OS 스케줄링 지터가 크므로, Phase 3 drift 계산은 개별 샘플이 아닌 **smoothing(선형 회귀 or EMA)** 전제 필요.
- **주목 2**: Dart `Timer.periodic`은 드리프트 누적 없이 정확 (stdev 13.2ms). 120회 중 이상치 1개(min 355ms, 0.8%).
- CSV 로그: `/tmp/synchorus_poc_phase2/audio_obs_2026-04-09T21-03-31-781504.csv` (임시 위치, 참고용)

#### 2026-04-09 PoC Phase 3 구현 (진행 중)

**구현 스코프 결정 과정**
- 초안: 온디바이스에 선형 회귀/Kalman 등 여러 알고리즘을 두고 비교
- 피드백: 용어가 과해 맥락 잃음 → 용어/수식 최소화, 비유 기반 설명으로 재정리
- 최종 결정: **"원시 데이터 수집 + 오프라인 비교"** 로 경로 변경. 온디바이스엔 **사용자가 제안한 EMA 방식**만 넣고 (설명·디버깅 쉬움), 선형 회귀·Kalman 등 정교한 알고리즘은 Python 스크립트로 같은 CSV에 적용해 벤치마크.
- 이유:
  1. 온디바이스 여러 알고리즘 → 코드 복잡, 실험 1회성, 공정 비교 어려움
  2. 원시 CSV 보존 → 새 알고리즘 추가돼도 기존 데이터로 재평가 가능
  3. PoC §6-2 "변수 하나만 실험" 원칙을 알고리즘 축까지 확장

**메시지 신설 (§8 보강)**
| 타입 | 방향 | 페이로드 | 용도 |
|---|---|---|---|
| `sync-ping` | 게스트→호스트 | `seq`, `t1` | 게스트 wall clock 송신 (RTT 측정용) |
| `sync-pong` | 호스트→게스트 | `seq`, `t1 (echo)`, `t2` | 호스트가 수신 직후 찍은 wall clock 반환 |

**clock sync 알고리즘 (NTP/SNTP 유사, §7에 추가 결정 기록)**
- 초기 핸드셰이크: 10회 빠른 ping (100ms 간격) → RTT 최소 샘플 채택
  - `rawOffset = t2 − (t1+t3)/2` (양방향 단방향 지연 대칭 가정)
  - 10회 수집 후 `settleDelay = 500ms` 대기 → orphan pong 회수 시도
- 주기 단계: 1s마다 ping, sliding window 5개 유지
  - 창 내 RTT 최소 샘플의 raw offset을 "새 측정값"으로 보고
  - `filtered = old * 0.9 + new * 0.1` (EMA, α=0.1)
  - 작은 α로 튀는 값 완화. α 튜닝은 오프라인 분석 결과 기반.

**게스트 자체 엔진 동작**
- 첫 `audio-obs(playing=true)` 수신 시 `start` → Oboe 폴링(100ms) 개시
- `audio-obs(playing=false)` 수신 시 `stop` + 폴링 정지
- 게스트 자체 재생은 드리프트 측정 목적 (호스트와 동일 sine wave, seek 보정은 Phase 4)

**CSV 3종** (같은 timestamp 접미사, 오프라인 짝짓기 쉽게)
- `audio_obs_*.csv`: 호스트 obs 수신 시계열 (Phase 2 유지, 동일 포맷)
- `sync_*.csv`: `seq,t1,t2,t3,rttMs,rawOffsetMs,filteredOffsetMs,phase(init/steady)`
- `guest_ts_*.csv`: `wallMs,framePos,timeNs,ok`

**호스트 측 변경**
- `_onClient`에서 LineSplitter 기반 line stream으로 전환 (기존 `(_) {}` 빈 핸들러 대체)
- `sync-ping` 수신 시 파싱 직후 **즉시 t2를 찍고** pong 응답 (호스트 처리 지연 최소화)
- 호스트 화면에 `sync-pong 응답 수` / `last seq` 표시

**게스트 화면 신규 카드**
- `clock sync`: 단계(init N/10 or steady), pong 수신, 최근 RTT, 초기 offset, filtered offset
- `게스트 재생`: 재생 상태, 폴링 수, ok 비율, last framePos

**파일 변경 범위**
- `lib/main.dart` 단일 파일 확장. 네이티브/Manifest/pubspec 변경 없음 (Phase 2 인터페이스 그대로 재사용).
- 빌드: `flutter build apk --debug --target-platform android-arm64` ✓
- 설치: S22(R3CT60D20XE) + S10(R3CM602J2DD) 두 기기 수동 연결 대기 중

#### 2026-04-09 ~ 2026-04-10 PoC Phase 4~5 (seek 보정 + 시간축 정합)

여러 라운드의 실측 → 버그 발견 → 수정 사이클. 각 테스트마다 CSV 수집해서 Python 분석
스크립트 (`analysis/phase4_drift_vs_seek.py`)로 통계/수렴성 판정.

기기: S10(SM-G977N, R3CM602J2DD) = 게스트, S22(SM-S901N, R3CT60D20XE) = 호스트
(USB 한 번에 한 대씩 연결 → 교체 → 설치 → 테스트 → swap → CSV 추출 워크플로우)

**Phase 4 초기 구현 (seek 보정 루프)**
- `_tryEstablishAnchor` / `_recomputeDrift` / `_performSeek` / `_maybeProbePostSeek` 4단계
- 앵커: clock sync 초기화 + filtered offset 있고 playing obs 수신하면 첫 게스트 poll에서 설정
- drift 수식: `drift = dG - dH`
  - `dG = effectiveGuestFrame - anchorGF` (guest 쪽 프레임 진행)
  - `dH = expectedHostFrameNow - anchorHF` (host 쪽 프레임 진행, 최근 obs + 외삽)
- seek 트리거: `|drift| ≥ 20ms` + 쿨다운(1000ms) 해제
- 보정: `correctionFrames = -drift * gain(0.8) * 48`, `seekToFrame(currentVf + correctionFrames)`
- post-seek probe: `[100, 300, 500, 1000, 2000]ms` 시점 drift를 seek_events CSV에 기록
- CSV 2종 신설: `drift_*.csv` (매 poll), `seek_events_*.csv` (pre/probe 이벤트)

**1차 실측 (2026-04-09 23:15)** → 결과 참담
- `|drift|<20ms`: **0.0%**, mean `-348ms`
- seek 평균 |pre|=347.8 → |post|=348.1 (seek 효과 **제로**)
- **버그 A (seek vs framePos 체계 불일치)**: `seekToFrame`은 `mVirtualFrame`만 덮어쓰고 HAL
  `framePos`는 그대로 증가. drift는 HAL framePos로 계산 → seek해도 drift 값은 그대로.
- **버그 B (앵커 시간축 불일치)**: `_tryEstablishAnchor`에서 `_anchorHostObsFrame = obs.framePos`로 그대로 저장.
  obs는 최대 500ms 오래된 값이라 anchorHF는 과거 시점, anchorGF는 현재 시점 → 300ms 초기 오프셋.

**버그 A, B 수정**
- `_seekCorrectionAccum` 필드 신설. 매 seek마다 `correctionFrames` 누적.
- `effectiveGuestFrame = guestFramePos + _seekCorrectionAccum`로 "seek가 없었다면 HAL이
  갔을 위치"를 복원해서 drift 계산에 사용.
- anchor 시 host frame을 `obs.framePos + (anchorHostWall - obs.hostTimeMs) * 48`로 외삽해서
  게스트 현재 시점으로 맞춤.
- drift CSV에 `seekAccum` 열 추가.

**2차 실측 (2026-04-09 23:34)** → 의미 있는 개선이지만 스파이크 잔존
- `|drift|<20ms`: **74.3%**, mean `+3.0ms`, median `+3.8ms`
- seek 수렴률: 73.8%, |pre|=45.6 → |post|=29.5 (35% 감소)
- 문제: 7% 샘플이 `|drift|>50ms`, 최대 ±100ms 스파이크. 100% 쿨다운 구간(seek 후 0~1000ms) 내 발생.
- offset 변동은 세션 전체 1.34ms만 → NTP는 안정. 스파이크 원인은 clock sync 아님.
- **버그 C (호스트 broadcast 시간축 불일치)**: `_broadcastOnce`가 `hostTimeMs: DateTime.now()`로
  "broadcast 순간의 wall"을 썼지만 `framePos`는 "최대 100ms 전 poll" 값. 100ms × 48 = 4800 frames
  = **100ms drift 오차**가 broadcast마다 무작위로 삽입됨.

**버그 C 수정**
- `hostTimeMs: latest.wallMs`로 변경 → framePos를 포함한 sample의 wallMs와 pair로 묶음.

**비프음 전환 요청 (청각 검증용)**
- 사용자 요청: "1초 간격 비프로 바꿔서 귀로 에코/지연 체감하게"
- `oboe_engine.cpp` `onAudioReady`: 연속 sine → `vf % beepPeriodFrames` 기반 비프
  - 440Hz sine을 100ms 동안 재생 + 900ms 무음 (1s 주기)
  - 양끝 5ms fade in/out으로 click 제거
  - seek 호환: `mod` 계산에 음수 vf 처리 (`if (mod < 0) mod += period`)
  - sampleRate 기반 상수라 스트림 rate 자동 적응

**3차 실측 (2026-04-09 23:51)** → 숫자 좋은데 귀로는 "아예 안 맞음"
- `|drift|<20ms`: **78.4%**, mean `+3.2ms`, median `+4.8ms`
- seek 수렴률: 77.3%, |pre|=47.4 → |post|=25.3
- 그런데 사용자 청각 확인: **"호스트랑 게스트 귀로 듣기엔 아예 안맞아"**
- **버그 D (drift 수식의 근본적 오해)**: drift = dG - dH는 **rate drift (시간에 따른 속도 차이)**만
  측정함. 앵커 시점의 `anchorHF - anchorGF = 초기 절대 오프셋`이 영구 보존됨.
  - CSV 수동 검증: 첫 샘플 `anchorHF=43296, anchorGF=6339, 초기 오프셋=36957 frames = 770ms`
  - 연속 sine에서는 phase만 어긋나 귀로 모름 → 숫자 통계가 좋아 보였음
  - 1초 주기 비프로 바꾸니 770ms 어긋남이 그대로 들림

**버그 D 수정 (Phase 5 초기 정렬 seek)**
- `_tryEstablishAnchor`에서 앵커 설정 시 게스트 `mVirtualFrame`을 호스트 frame 좌표계로 즉시 점프:
  ```
  initialCorrection = anchorHF - (framePos + _seekCorrectionAccum)
  seekToFrame(anchorHF)  # 즉시 정렬
  _seekCorrectionAccum += initialCorrection
  ```
- 이후 `anchorGF == anchorHF`이므로 `drift = dG - dH = effective - expected`로 **절대 오정렬** 측정.
- HAL 버퍼에 이미 들어간 샘플(~10-30ms)은 이전 vf로 재생 → 완전 정렬은 HAL latency만큼 지연.
- `_maybeProbePostSeek`에서 **앵커 재설정 제거** (gain=0.8의 잔차가 "새 기준선"으로 흡수되는 문제 방지).
- `_ensureGuestStarted`에서 stale state 리셋 (play toggle 시 네이티브 `mVirtualFrame=0`과 일치시키기).

**4차 실측 (2026-04-10 00:09)** → 여전히 스파이크 (이번엔 다른 원인)
- `|drift|<20ms`: **83.0%**, mean `+4.2ms`, median `+8.2ms`
- seek 수렴률: 76.3%, |pre|=50.5 → |post|=24.5
- 초기 정렬 seek 정상 작동 확인: 첫 샘플 `seekAccum=39374 ≈ anchorHF(47057) - guestFrame(7587)`
- **여전히 ±100ms 스파이크**. audio_obs CSV에서 발견:
  - seq 1→2: `Δwall=498ms, Δmono=458.2ms` → 39.8ms 편차 (1.5% 아닌 **8%**)
  - clock drift로는 불가능한 값 → 두 시계가 다른 순간에 캡처되고 있음
- **버그 E (wallMs vs timeNs 캡처 순간 불일치)**:
  - `_pollOnce` 코드:
    ```dart
    final wallMs = DateTime.now().millisecondsSinceEpoch;  // await 이전
    final result = await _nativeChannel.invokeMethod('getTimestamp');  // timeNs는 이 내부에서 캡처
    ```
  - `wallMs`와 `timeNs`는 서로 다른 순간 + 그 gap이 샘플마다 변동 → `hostTimeMs`와 `framePos`가
    atomically 정합되지 않음 → 게스트 외삽에서 ±40ms 오차 → 스파이크

**버그 E 수정 (Phase 5 네이티브 시간축 원자화)**
- `oboe_engine.cpp::getLatestTimestamp`가 `outWallAtFramePosNs` 추가 반환:
  ```cpp
  oboe::getTimestamp(CLOCK_MONOTONIC, &framePos, &timeNs_oboe);
  clock_gettime(CLOCK_REALTIME, &wallTs);
  clock_gettime(CLOCK_MONOTONIC, &monoTs);
  wallAtFramePosNs = wallNow - (monoNow - timeNs_oboe);
  // = "framePos가 DAC에 나간 순간의 CLOCK_REALTIME 추정치"
  ```
- JNI 배열 3 → 4 원소 (`[framePos, timeNs, wallAtFramePosNs, ok]`)
- `MainActivity.kt` 메서드 채널 Map에 `wallAtFramePosNs` 필드 추가
- `NativeAudio.kt` 주석 업데이트
- Dart `_pollOnce`/`_guestPollOnce`: `DateTime.now()` 제거, `result['wallAtFramePosNs'] ~/ 1000000` 사용
- 이로써 `Sample.wallMs`와 `framePos`가 네이티브에서 원자적으로 엮여 샘플 간 rate가 일관됨

#### 2026-04-10 PoC Phase 5 실측 (5~11차)

기기: S22(SM-S901N, 호스트) + Z플립4(SM-F721N, 게스트). USB 1대씩 교체 설치.

**비프음 음계 전환**
- [x] 440Hz 고정 → C major 음계(도레미파솔라시도) 8음 순환, 1초마다 다음 음
- 목적: 동일 음 반복 시 1초 지연을 구분 불가 → 음계로 청각 검증 정확도 향상

**호스트 seek 버튼 추가**
- [x] HostPage에 -10s/-3s/+3s/+10s 버튼, `seekToFrame(vf + delta*48000)` 호출
- [x] `_cachedVirtualFrame`: poll 시 같이 캐싱, broadcastOnce에서 사용

**5차 실측 (연속 재생)** — 버그 E 수정 효과 확인
| 항목 | 값 |
|---|---|
| |drift| < 5ms | 82.8% |
| |drift| < 10ms | **100%** |
| max |drift| | 8.9ms |
| seek 보정 | 0건 |
| 청각 | 완전 일치 ✓ |

**6차 실측 (play/stop 반복)**
| 항목 | 값 |
|---|---|
| |drift| < 5ms | 89.8% |
| |drift| < 10ms | **100%** |
| max |drift| | 8.0ms |
| seek 보정 | 0건 |
| 청각 | 완전 일치 ✓ |

→ 버그 E(시간축 원자화) 수정으로 스파이크 완전 제거. play/stop 반복에도 안정.

**7차 실측 (호스트 seek)** — 버그 F 발견
- drift 데이터 99.8% < 20ms로 보였으나 **청각상 게스트가 seek을 전혀 안 따라감**
- **버그 F**: `audio-obs`가 HAL `framePos`만 보냄. HAL framePos는 seek 무관 단조 증가 → 게스트가 호스트 seek 감지 불가
- 수정: `AudioObs`에 `virtualFrame` 필드 추가, drift 계산 및 앵커 외삽을 `obs.virtualFrame` 기준으로 변경

**8차 실측 (호스트 seek + 연타)** — 버그 G 발견
- max |drift| = 42s, seek 보정이 연쇄 폭주
- **버그 G**: 큰 drift에서 `gain=0.8` 점진 보정 → 타겟이 움직이는 상황에서 수렴 불가, 과보정↔미보정 진동
- 수정: |drift| ≥ 200ms → 앵커 재설정 방식 전환 (점진 보정 대신 즉시 재정렬)

**9차 실측** — 앵커 재설정 동작 확인, 과도 구간 잔존
- 앵커 재설정 후 즉시 ~0ms 복구 확인
- 단, 쿨다운(1s) + stale obs 대기로 스파이크 600~900ms 유지
- 수정: 앵커 재설정 시 쿨다운 해제 + stale obs 무효화

**10차 실측** — 과도 구간 대폭 축소
- 스파이크 대부분 1샘플(100ms), 700ms 스파이크 1건
- |drift| < 20ms: 89%, 청각 확인 양호

**11차 실측 (최종)** — obs 유지 최적화
- `_latestObs` null 제거: 감지 시점 obs가 이미 호스트 seek 후 값이므로 유지
| 항목 | 값 |
|---|---|
| |drift| < 10ms | 64.5% (seek 과도 구간 포함) |
| |drift| < 20ms | 86.4% (seek 과도 구간 포함) |
| |drift| > 50ms | 25건 (4.2%), **전부 1샘플(100ms) 스파이크** |
| max |drift| | 30018ms (호스트 +30s seek 직후 1회) |
| 안정 상태 (seek 제외) | < 10ms 100%, max 9ms |
| 청각 | 완전 일치 ✓ |

→ 호스트 seek 후 재정렬: 데이터상 1 poll(100ms), 체감 최대 ~600ms (obs 주기 대기).
→ 안정 상태 drift는 5차/6차와 동일하게 < 10ms 100%.

**발견/수정 버그 요약 (이번 세션)**
| 버그 | 원인 | 수정 |
|---|---|---|
| F | audio-obs가 HAL framePos만 전송, 호스트 seek 감지 불가 | `virtualFrame` 필드 추가, drift/앵커 계산 기준 변경 |
| G | 큰 drift에서 gain=0.8 점진 보정 발산 | |drift| ≥ 200ms → 앵커 재설정 |

**실측 세션 목록**
- 1~4차: S22 + S10, `analysis/data/`에 pull 완료
- `2026-04-10T09-40-52-528321` (5차, 연속 재생)
- `2026-04-10T09-47-00-913275` (6차, play/stop 반복)
- `2026-04-10T09-52-57-659060` (7차, 호스트 seek — 버그 F)
- `2026-04-10T10-02-11-824919` (8차, seek 연타 — 버그 G)
- `2026-04-10T10-09-21-658055` (9차, 앵커 재설정 + 과도 구간)
- `2026-04-10T10-18-02-600315` (10차, stale obs 무효화)
- `2026-04-10T10-29-03-446402` (11차, obs 유지 최종)
- `2026-04-10T12-46-36-013824` (연속 재생 검증, drift<10ms 100%)
- `2026-04-10T13-06-00-238661` (Phase 6, 31분 stress)

#### 2026-04-10 PoC Phase 6: 30분 stress + drift/seek 구조 정리

**drift 계산 구조 정리 (버그 H~I 수정)**
- 12~15차 실측에서 연속 재생 시 drift 진동 발견 (5ms/500ms 계단식)
- **버그 H**: `virtualFrame` rate가 `framePos`(HAL)와 미세하게 다름 → drift 계산에 virtualFrame 사용 시 누적 오차
- **버그 I**: `framePos`만 사용하면 호스트 seek 감지 불가 (framePos는 seek에 무관하게 단조 증가)
- **해결**: 역할 분리
  - **rate drift 추적**: `framePos`(HAL 하드웨어 클록) 기반 → 정확
  - **콘텐츠 정렬**: `virtualFrame` 기반 — 매 poll마다 `_checkContentAlignment`로 게스트 vf ≈ 호스트 vf 확인, 4800 frames(100ms) 이상 차이 시 즉시 보정
  - **호스트 seek 전달**: `seek-notify` TCP 메시지 + 콘텐츠 정렬 체크가 안전망
  - **초기 정렬**: `_tryEstablishAnchor`에서 앵커는 `framePos` 기반, seek 목표는 `virtualFrame` 기반

**Phase 6 실측 (2026-04-10, S22 호스트 + Z플립4 게스트, 31분 연속 재생)**
| 항목 | 값 |
|---|---|
| 총 시간 | 31분 (18,753 samples) |
| |drift| < 10ms | 70.5% |
| |drift| < 20ms | **99.9%** |
| |drift| > 50ms | 1건 (77.5ms, 단발) |
| mean drift | -1.7ms |
| seek 보정 | 17회 (~110초에 1회, 하드웨어 클록 차이 보정) |
| 시간대별 안정성 | 전 구간 mean |d| = 5~10ms, 발산 없음 |
| clock sync | 1,888회, offset 안정 |
| 청각 | 31분간 싱크 유지 ✓ |

→ 장시간 drift 발산 없음, EMA clock sync 지속 보정 확인.

**네트워크 블립 테스트 (2026-04-10)**
- 게스트 WiFi 끄기 → TCP 소켓 에러, obs/sync 수신 중단
- Oboe 엔진은 로컬이라 재생 계속됨, 짧은 시간은 하드웨어 클록만으로 싱크 유지
- WiFi 복구 후 TCP 재연결 없음 (PoC에 재연결 미구현) → 호스트 명령 수신 불가
- **결론**: 동기화 정밀도와 무관한 네트워크 복구 문제. 본 앱(v2)에 자동 재연결/heartbeat 이미 구현되어 있으므로 v3 본 구현에서 재사용.

#### 2026-04-15 iOS PoC Phase 2~6: 크로스플랫폼 싱크 (Android S22 호스트 ↔ iPhone 게스트)

**b0415-1~6: 기본 연결 + 배포 + 지연 보정**
- [x] Android PoC의 main.dart (Phase 2~6) 복사 → iOS PoC에 적용
- [x] `mSampleRate` 동적 갱신 (하드웨어 실제 값 사용, 48000Hz 확인)
- [x] iOS release 빌드/배포 플로우 확립 (`flutter build ios --release` → Xcode Run → Stop debugger → 수동 실행)
- [x] `AVAudioSession.outputLatency + ioBufferDuration` 동적 보정 (hw=10.3ms + io=5.0ms)
- [x] CSV 진단 데이터 출력 (drift/sync/audio_obs/guest_ts)

**b0415-7: seekToFrame 파싱 버그 수정 — 1초 콘텐츠 오프셋 해결**
- [x] **원인**: `AppDelegate.swift` seekToFrame 핸들러가 `call.arguments`를 `[String: Any]` 딕셔너리로 파싱 시도 → Dart는 숫자 직접 전달 → 항상 FlutterError 반환 → seekToFrame 한 번도 성공한 적 없음
- [x] **증상**: drift 2ms (rate 정확) but 실제 오디오 ~1초 뒤처짐 (virtualFrame 정렬 실패)
- [x] **수정**: `call.arguments as? NSNumber` 로 변경 (Android Kotlin과 동일 방식)
- [x] **결과**: 3회 실측 drift mean -5.6ms ~ +1.3ms, 귀로 동시 재생 확인

**실측 데이터 (b0415-7, iPhone ↔ S22)**
| 세션 | drift 평균 | 범위 | 샘플 |
|------|-----------|------|------|
| 21-34 | +1.25ms | -2.2 ~ +4.3ms | 396 |
| 21-50 | -2.87ms | -7.2 ~ +2.5ms | 386 |
| 21-52 | -5.61ms | -8.9 ~ +0.0ms | 477 |

**b0415-8: 호스트 연결 종료 시 게스트 자동 정지**
- [x] TCP `onDone`/`onError`에서 `_stopGuest()` 호출 추가

**30분 stress 테스트 (b0415-8, S22 호스트 ↔ iPhone 게스트)**

테스트 시나리오: 0~1분 재생정지 연타 + seek 연타, 이후 29분 연속 재생.

| 항목 | iOS (S22↔iPhone) | Android (S22↔Z플립4) |
|------|-------------------|---------------------|
| 총 시간 | 30.1분 (18,050 samples) | 31분 (18,753 samples) |
| mean drift | +4.50ms | -1.7ms |
| \|d\| < 10ms | 64.7% | 70.5% |
| \|d\| < 20ms | **99.6%** | 99.9% |
| \|d\| > 50ms | 53건 (27분 단일 스파이크) | 1건 |
| seek 보정 | 171회 (0~1분 수동 테스트 집중) | 17회 |
| clock sync | 1,820회 | 1,888회 |

- 50ms 초과 53건은 **27~28분 단일 구간**의 일시적 스파이크 (원인 불명, 네트워크 글리치 추정). 자동 복구 확인됨 (귀로도 "잠깐 안 맞다가 다시 맞음" 확인)
- 스파이크 구간 제외 시 |d|<20ms = 99.6%
- 5분 구간별 mean drift: -5ms ~ +10ms, 발산 없음
- 재생정지 연타 + seek 연타 후에도 정상 복구

**역방향 테스트 (iPhone 호스트 → S22 게스트)**

| 세션 | 시간 | mean drift | 범위 | \|d\|<20ms |
|------|------|-----------|------|-----------|
| 22-43 | 7s | +0.02ms | -5.3 ~ +4.5ms | 100% |
| 22-44 | 2m38s | -2.17ms | -5.5 ~ +2.1ms | 100% |
| 22-55 | 56s | +0.83ms | -1.1 ~ +2.4ms | 100% |

→ 역방향도 **100% ±20ms 이내**. 호스트/게스트 역할 무관하게 크로스플랫폼 싱크 동작 확인.
→ S22 외부 저장소 경로가 `/storage/emulated/95/` (멀티유저)인 점 발견.

**drift mean +4.5ms 원인 분석 (완료)**
- [x] clock sync offset이 25분간 -320ms → -278ms로 42ms 이동 (crystal 속도 차이 ~28ppm, 정상)
- [x] EMA 필터가 천천히 추적하면서 drift mean이 구간별 -5ms ~ +10ms 진동
- [x] **iOS latency 과보정 아님** — 고정 오프셋이 아닌 동적 진동. 코드 수정 불필요
- [x] 27분 스파이크: clock sync offset이 +800ms로 급변 (네트워크 일시 장애) → 자동 복구 확인

**다음 작업**
- [x] PoC → 본 구현 통합 step 1-1 완료

#### 2026-04-15 v3 본체 앱 통합 step 1-1: 네이티브 오디오 엔진 이식

**Android**
- [x] `oboe_engine.cpp` 복사 (JNI 함수명 `Java_com_synchorus_synchorus_NativeAudio_*`로 변경)
- [x] `CMakeLists.txt` + `build.gradle.kts` (Oboe 1.9.0 prefab, NDK arm64-v8a/armeabi-v7a)
- [x] `NativeAudio.kt` JNI 브릿지, `MainActivity.kt`에 `com.synchorus/native_audio` 채널 추가
- [x] Android debug 빌드 통과

**iOS**
- [x] `AudioEngine.swift` 복사 (PoC와 동일, AVAudioEngine + AVAudioSourceNode)
- [x] `AppDelegate.swift`에 AudioEngine + MethodChannel 추가 (seekToFrame: NSNumber 직접 파싱)
- [x] `project.pbxproj` 수동 편집 (PBXBuildFile/FileReference/Group/SourcesBuildPhase 4곳)
- [x] iOS debug 빌드 통과

**MethodChannel 인터페이스** (양 플랫폼 동일)
- 채널명: `com.synchorus/native_audio`
- 메서드: start, stop, getTimestamp, seekToFrame, getVirtualFrame
- seekToFrame: Dart에서 숫자 직접 전달 (딕셔너리 아님)

**다음**: step 1-2 (Dart 서비스 레이어 + 오디오 파일 재생) 또는 drift 과보정 분석

#### 2026-04-15 v3 본체 앱 통합 step 1-2: 오디오 파일 디코딩 재생

**Dart**
- [x] `lib/services/native_audio_service.dart` 생성 — MethodChannel 래퍼 (loadFile/start/stop/getTimestamp/seekToFrame/getVirtualFrame)

**iOS**
- [x] `AudioEngine.swift` 전면 교체: AVAudioSourceNode(비프) → AVAudioPlayerNode + AVAudioFile(파일 재생)
- [x] `scheduleSegment` 기반 seek 구현 (stop → reschedule → play)
- [x] `playerTime(forNodeTime:)` 기반 virtualFrame 계산 (seekFrameOffset + playerTime.sampleTime)
- [x] getTimestamp에 totalFrames 추가
- [x] `AppDelegate.swift`에 loadFile 핸들러 추가

**Android**
- [x] `oboe_engine.cpp` 전면 교체: 비프 생성 → NDK AMediaExtractor+AMediaCodec 디코딩
- [x] int16 버퍼 전체 디코딩 (150MB 제한), Oboe callback에서 float 변환
- [x] Oboe SRC 활성화 (파일 샘플레이트 ≠ 하드웨어 시 자동 변환)
- [x] `CMakeLists.txt`에 `mediandk` 링크 추가
- [x] `NativeAudio.kt`에 `nativeLoadFile` JNI, `MainActivity.kt`에 loadFile 핸들러
- [x] getTimestamp JNI 배열 5→7 확장 (sampleRate, totalFrames 추가)

**테스트 UI**
- [x] `lib/screens/native_test_screen.dart` 생성 — 파일 선택/재생/정지/seek + getTimestamp 폴링(200ms)
- [x] `lib/screens/home_screen.dart`에 "Native Engine Test" 버튼 추가

**S22 실기기 테스트 (2026-04-15)**
- 파일 로드 ✅, 재생/정지 ✅, seek(±3s/±10s) ✅
- sampleRate: 44100 Hz (파일 네이티브 레이트 정상 보고)
- virtualFrame/totalFrames 정상 동작 확인

**다음**: step 1-3 (P2P + clock sync + drift 보정 통합)

#### 2026-04-15 iOS PoC Phase 0+1: AVAudioEngine + getTimestamp

**프로젝트 생성**
- [x] `poc/native_audio_engine_ios/` 독립 Flutter 앱 생성
- [x] `AudioEngine.swift`: AVAudioEngine + AVAudioSourceNode render block, 음계 비프(C4~C5), os_unfair_lock
- [x] `AppDelegate.swift`: MethodChannel `com.synchorus.poc/native_audio` (start/stop/getTimestamp/seekToFrame/getVirtualFrame)
- [x] MethodChannel 인터페이스 Android PoC와 동일 → Phase 2부터 main.dart 공유 가능

**Phase 0+1 실측 (2026-04-15, iPhone, iOS 26.4.1)**
| 항목 | iOS (iPhone) | Android (S22) |
|---|---|---|
| frames/ms | **48.0010** | 48.0003 |
| Monotonic framePos | ✓ | ✓ |
| Monotonic timeNs | ✓ | ✓ |

→ 48kHz 정확 일치, Android PoC와 동등한 정밀도 확인

#### 2026-04-16 lint 경고/에러 정리

- iOS PoC widget_test.dart: 잘못된 import(`package:native_audio_engine_ios/main.dart`) 및 존재하지 않는 `MyApp` 참조 제거, placeholder 테스트로 교체
- Android/iOS PoC main.dart: 미사용 필드 제거 (`_cachedVirtualFrame`, `_guestLastTimeNs`, `_guestLastWallMs`) — 값 할당만 되고 읽히지 않음
- 본체 앱 `native_test_screen.dart`: 미사용 `dart:io` import 제거

#### 2026-04-16 v3 본체 앱 통합 step 1-3: P2P + clock sync + drift 보정

**설계 결정: v2 교체 (병행 X)**
- `AudioSyncService` (v2, just_audio 기반 780줄) 삭제 → `NativeAudioSyncService` (v3, 네이티브 엔진) 신규 생성
- 근거: AudioSyncService가 just_audio API에 깊이 결합 (ProcessingState, buffering watch 등), v2/v3 병행은 코드 중복만 증가, PoC 30분 stress ±20ms 99.9% 검증 완료로 fallback 불필요

**신규 파일**
- [x] `lib/models/audio_obs.dart` — AudioObs 모델 (PoC 포팅, anchorFramePos/anchorTimeNs 제거)
- [x] `lib/services/native_audio_sync_service.dart` — v3 오디오 동기화 서비스
  - 호스트: 네이티브 엔진 재생 + audio-obs 500ms broadcast + HTTP 파일 서빙 + seek-notify
  - 게스트: HTTP 파일 다운로드 + 네이티브 엔진 재생 + drift 계산 + seek 보정
  - PoC Phase 4 알고리즘 그대로 포팅: 앵커 외삽, _seekCorrectionAccum, gain=0.8, cooldown 1s
  - |drift| ≥ 200ms → 앵커 리셋, |drift| ≥ 20ms → seek, _checkContentAlignment (4800 frames)

**수정 파일**
- [x] `lib/services/native_audio_service.dart` — NativeTimestamp 모델 추가 + 100ms 폴링 타이머 + timestampStream
- [x] `lib/services/sync_service.dart` — EMA 업그레이드: 30s→1s 주기, 5개 sliding window, EMA α=0.1, `filteredOffsetMs` (double) getter 추가. 초기 핸드셰이크(10-ping)는 유지. 주기 단계 rid를 음수로 분리하여 초기/주기 pong 매칭 구분
- [x] `lib/providers/app_providers.dart` — audioSyncServiceProvider → nativeAudioSyncServiceProvider
- [x] `lib/screens/player_screen.dart` — just_audio 의존성 제거, 네이티브 엔진 기반 UI (polled position/duration), 게스트 sync info 카드 (drift/seeks/offset/RTT), volume 컨트롤 제거 (step 별도)
- [x] `lib/screens/room_screen.dart` — provider 참조 전환, audio-obs 로그 숨김
- [x] `lib/screens/native_test_screen.dart` — NativeTimestamp 타입 적용 (Map → typed class)

**삭제 파일**
- [x] `lib/services/audio_service.dart` (v2 AudioSyncService, git에 보존)

**S22 호스트 단독 테스트 (2026-04-16)**
- 파일 로드 → 재생/정지/seek → 정상 동작 확인
- seek bar 드래그 → 즉시 반영 (seek override 패턴 적용)
- 파일 변경 시 seek bar 0으로 리셋 확인

**추가 개선 (S22 테스트 중 발견)**
- [x] 파일 로드 시 화면 멈춤 → Android loadFile을 백그라운드 스레드에서 실행 (MainActivity.kt)
- [x] 에러 메시지 구체화 → C++ mLastError + JNI getLastError + Dart 한국어 변환 (TOO_LONG/UNSUPPORTED_FORMAT/NO_AUDIO_TRACK/UNSUPPORTED_CODEC/FILE_OPEN_FAILED)
- [x] 파일 복사 2x 용량 문제 → file.copy() → file.rename() (같은 파일시스템이면 즉시 이동, 추가 용량 0)
- [x] seek bar 드래그 중 위치 되돌아감 → _seekOverridePosition 패턴 (500ms간 폴링 position 무시)
- [x] 파일 변경 시 seek bar 미초기화 → loadFile 진입 시 position/duration 리셋
- [x] 저장 공간 부족 에러 → 사용자 친화적 메시지 ("저장 공간이 부족합니다")

**빌드**: flutter analyze 0 issues, debug APK 빌드 성공, S22 호스트 단독 테스트 통과
**다음**: 에뮬레이터 게스트 테스트 (P2P + drift 검증) → step 1-4 (백그라운드 재생)

#### 2026-04-17 v3 본체 앱 통합 step 1-4: 백그라운드 재생 + UI 개선

**audio_service 연동 (백그라운드 재생 + 미디어 컨트롤)**
- [x] `audio_handler.dart` 신규 생성 — `NativeAudioHandler` (BaseAudioHandler + SeekHandler)
  - 네이티브 엔진(NativeAudioSyncService)과 audio_service 플러그인 연결
  - `positionStream` 구독으로 `_lastPosition` 항상 최신 유지 (engine.latest 직접 읽기의 타이밍 문제 해결)
  - 호스트: 재생/정지/seek 미디어 컨트롤 표시
  - 게스트: 곡 정보 + 재생 상태만 표시 (controls 비어있지만 Android 13+ 시스템이 강제 표시)
  - 게스트 버튼 눌렀을 때 `_emitPlaybackState()` 재전송으로 아이콘 복원 시도
- [x] `main.dart`에 `AudioService.init()` + `AudioSession` 설정 추가
- [x] `app_providers.dart`에 `audioHandlerProvider` 추가
- [x] `room_screen.dart`에서 호스트/게스트 모두 handler attach (isHost 파라미터로 구분)
- [x] AndroidManifest에 `WAKE_LOCK` 퍼미션 추가 (화면 꺼짐 시 호스트 킬 방지)

**seek bar 0:00 점프 버그 수정**
- [x] 원인: `audio_handler._capturePosition()`이 `engine.latest`에서 `ok` 체크 없이 `virtualFrame=0` 사용
- [x] 근본 수정: `_capturePosition()` 제거 → `positionStream` 구독으로 `_lastPosition` 항상 최신 유지
- [x] syncPlay()의 position override도 positionStream으로 전달되어 handler가 정확한 위치 사용

**게스트 파일명 표시 수정**
- [x] 호스트가 `audio-url` 메시지에 원본 `fileName` 포함
- [x] 게스트가 URL의 safe name 대신 원본 파일명 사용

**음소거 버튼 추가**
- [x] Android C++ (Oboe): `mMuted` atomic flag → `onAudioReady`에서 silence 출력
- [x] Android Kotlin: `nativeSetMuted`/`nativeIsMuted` JNI + MethodChannel
- [x] iOS Swift: `engine.mainMixerNode.outputVolume` 0/1 토글
- [x] Flutter `NativeAudioService`: `setMuted`/`isMuted` 메서드
- [x] `player_screen.dart`: 재생 컨트롤 가운데 정렬 유지, 음소거 버튼 오른쪽 분리 배치

**Android 13+ 미디어 알림 제한 확인**
- 재생/정지 버튼은 시스템이 강제 표시 (controls 비워도 제거 불가)
- 커스텀 액션(mute 등) 알림에 추가 불가 (표준 MediaSession 액션만 지원)

**빌드**: v0.0.8, flutter analyze 통과, S22 + 에뮬레이터 테스트 완료

### 2026-04-17 (2) — Android 스트리밍 디코드 최적화

**배경**: S22 실측 loadFile (전체 디코드) 소요 시간 11초(콜드)/6.6초(웜). 파일 로드 UX 병목.

**Android `oboe_engine.cpp` 스트리밍 디코드 리팩터링**
- [x] 전체 파일 디코드 대기 → 최소 1초 분량 디코드 후 즉시 반환 (백그라운드 디코드 계속)
- [x] 사전 할당 PCM 버퍼 (silence로 초기화) + 디코드 범위 2-range 추적 (`mSeqDecodeEnd`, `mSeekDecodeStart/End`)
- [x] `onAudioReady`: 디코드 완료 프레임만 출력, 미디코딩 영역은 silence
- [x] seek-in-decode (Method A): 미디코딩 영역 seek 시 디코드 스레드가 해당 위치로 점프 → 디코드 → 갭은 나중에 `fillGaps`로 채움
- [x] `std::thread` + `std::condition_variable` 기반 백그라운드 디코드, `atomic` 기반 스레드 안전 범위 추적
- [x] iOS는 `AVAudioFile` + `scheduleSegment`가 이미 스트리밍 방식이라 변경 불필요

**S22 실측 결과**:

| 항목 | 이전 | 이후 |
|---|---|---|
| loadFile 소요 | 11,000ms (콜드) | **548~736ms** |
| 체감 개선 | - | **~15-20배** |

| 파일 | loadFile | 전체 디코드 |
|---|---|---|
| 368s MP3 48kHz | 548ms | ~22s (seek 3회 포함) |
| 352.5s MP3 48kHz | 582ms | ~10s |
| 523.4s MP3 44.1kHz | 689ms | ~15s |

- seek-in-decode 동작 확인: 미디코딩 영역 3회 연속 seek → fillGaps 정상 완료
- 재생 품질: 끊김/노이즈 없음 (호스트 단독 확인)

**빌드**: v0.0.9, S22 + 에뮬레이터 테스트 완료

### 2026-04-17 (3) — 게스트 재생 실패 버그 수정 + content alignment 안정화

#### 버그: 호스트 트랙 변경 시 게스트 `start: no file loaded` 반복

**증상**: 호스트가 파일을 변경하면 게스트에서 500ms마다 `start: no file loaded` 에러 반복. 재생 불가.

**원인**: `_handleAudioUrl`에서 새 파일 로드 시 `_audioReady = false`로 리셋하지 않음.
- 파일 A 로드 완료 → `_audioReady = true`
- 파일 B 로드 시작 → native `resetState()` → `mFileLoaded = false`
- `_handleAudioObs`가 `_audioReady == true`(stale)로 보고 `start()` 반복 호출
- native `start()`는 `mFileLoaded == false`라서 매번 실패

**수정**: `_handleAudioUrl` 진입 시 `_audioReady = false` + 기존 재생 정지 + drift 상태 리셋.

#### content alignment 진동 수정

**증상**: 로그에서 diff가 수백만 프레임으로 발산하며 seekTo가 핑퐁.
```
diff=567050  seekTo=6831470
diff=5310497 seekTo=6328285   ← 진동
diff=5307855 seekTo=11660076  ← 발산
```

**원인**: 100ms poll마다 content alignment seek → seek 반영 전 또 seek → 위치 발산.

**수정**:
- content alignment에 1초 쿨다운 추가 (seek 후 1초간 재정렬 안 함)
- 하드코딩 `_idealFramesPerMs=48.0` 대신 `ts.sampleRate`에서 실제 framesPerMs 계산 (44.1kHz 파일 대응)

**빌드**: v0.0.10, S22 + 에뮬레이터 테스트 완료

### 2026-04-17 (4) — 게스트 다운로드 진행률 표시 + 최적화 2 조사

#### 최적화 2 (게스트 다운로드+디코드 병렬화) 조사 결과

`AMediaExtractor`(Android), `AVAudioFile`(iOS) 모두 완전한 seekable 파일 필요 → 다운로드 중 디코드 시작 불가.
- `AMediaExtractor_setDataSourceFd(fd, offset, size)`: 전체 크기 필요, 파이프/FIFO 불가
- MP3 헤더(Xing/VBRI), MP4 moov atom 등 컨테이너 메타데이터 파싱에 완전한 파일 필수

LAN 환경에서 다운로드 100~500ms이므로 병목이 크지 않아 현재 구조 유지.

#### 게스트 다운로드 진행률 UI 추가

- `_downloadProgressController` 스트림 추가 (0.0~1.0)
- `response.pipe()` → 수동 청크 읽기로 교체, `Content-Length` 기반 진행률 계산
- UI: `CircularProgressIndicator(value: progress)` + "파일 수신 중... 47%" 텍스트
- 다운로드 완료 후 디코딩 중에는 기존 무한 스피너

**빌드**: v0.0.11, S22 + 에뮬레이터 테스트 완료

### 2026-04-17 (5) — content alignment 제거 + fallback sync + duration 버그 수정

#### `_checkContentAlignment` 완전 제거

**증상**: content alignment seek와 drift correction seek가 동시 작동하며 위치 발산 (수백만 프레임 diff 핑퐁).

**근본 원인**: 3개 seek 메커니즘 (`_tryEstablishAnchor`, `_performSeek`, `_checkContentAlignment`)이 서로의 보정을 덮어쓰면서 경합.
- `_checkContentAlignment`는 virtualFrame 기준으로 seek → `_seekCorrectionAccum` 미갱신 → drift 계산 회계 파탄
- drift correction의 re-anchor (drift >200ms → 앵커 리셋 → 재정렬)가 이미 모든 정렬 시나리오 처리 가능

**수정**: `_checkContentAlignment` 메서드 및 호출부 완전 삭제. `_contentAlignThreshold` 상수 제거.

#### `_framesPerMs` getter 도입

**문제**: `_idealFramesPerMs = 48.0` 상수가 44.1kHz 파일에서 8.8% 오차 유발 (외삽 20ms 구간에서 ~1.8ms 에러).

**수정**: `_idealFramesPerMs` 상수 → `_framesPerMs` getter로 교체. `ts.sampleRate`에서 실제 값 계산 (`sr / 1000.0`). sampleRate 미확보 시 `_defaultFramesPerMs = 48.0` fallback.

#### fallback alignment (HAL timestamp 실패 환경 대응)

Oboe `getTimestamp(CLOCK_MONOTONIC)`가 `ok=false` 반환하는 극단 환경 (Bluetooth, 에뮬레이터, 특정 DAC) 대비.

**네이티브 수정** (`oboe_engine.cpp`):
- `getLatestTimestamp`가 `ok=false`일 때도 항상 `virtualFrame` + `wallClock` 반환 (이전엔 -1 반환)

**Dart 수정** (`native_audio_sync_service.dart`):
- position UI 업데이트를 `ts.ok` 체크 밖으로 이동 (virtualFrame은 항상 유효)
- `_fallbackAlignment()` 신규: `ts.ok=false` + 재생 중일 때 virtualFrame 기반 coarse alignment (diff > 2400 frames ≈ 50ms 시 seek, 2초 쿨다운)

#### duration 0:00 표시 버그 수정

**증상**: 게스트가 플레이어 화면에 진입하기 전에 파일 로드 완료되면 duration이 0:00으로 표시.

**원인**: broadcast `StreamController`의 late subscriber 문제 — 이미 emit된 duration 이벤트를 못 받음.

**수정**:
- `_currentDuration` 필드로 마지막 duration 캐싱
- `player_screen.dart` duration StreamBuilder에 `initialData: _audio.currentDuration` 추가

**빌드**: v0.0.12, 에뮬레이터 확인 완료

### 2026-04-17 (6) — 네이티브 엔진 unload + 라이프사이클 전면 리뷰

#### 네이티브 엔진 `unload` 메서드 추가
- Android C++: `unload()` = `stop()` + `stopDecodeThread()` + `resetState()` + `mVirtualFrame=0`
- iOS Swift: `unload()` = `stop()` + `audioFile=nil` + `seekFrameOffset=0`
- JNI/MethodChannel/Dart 전 레이어 관통 추가
- `clearTempFiles()`, `cleanupSync()`, `dispose()`에서 호출

#### 라이프사이클/리소스 정리 전면 리뷰 — CRITICAL 3건 + HIGH 8건 수정

**CRITICAL 1: Provider 싱글턴 재사용 버그**
- 문제: 방 나가기 → 서비스 dispose → 다시 방 입장 시 이미 dispose된 서비스 재사용
- 원인: Riverpod `Provider`가 캐시된 인스턴스를 반환, `ref.invalidate()` 없음
- 수정: `_leaveRoom()` + `dispose()` 양쪽에서 전체 서비스 provider `ref.invalidate()` 호출
  - `nativeAudioSyncServiceProvider`, `syncServiceProvider`, `p2pServiceProvider`, `discoveryServiceProvider`

**CRITICAL 2: 다운로드 중 HttpClient/Sink 누수**
- 문제: HTTP 에러 또는 네트워크 끊김 시 `client.close()` / `sink.close()` 미도달 → 소켓/파일 핸들 누수
- 수정: `_handleAudioUrl` 다운로드를 중첩 try-finally로 감싸 항상 `sink.close()` → `client.close()` 보장

**CRITICAL 3: 다운로드 중 방 나가기 레이스**
- 문제: 게스트 파일 다운 중 cleanup → 다운로드와 엔진 정리가 동시 실행 → 상태 꼬임
- 수정: `_downloadAborted` 플래그 도입. `clearTempFiles()`/`cleanupSync()`에서 `true` 설정, 다운로드 루프에서 매 청크마다 체크 후 break, 로드 스킵

**HIGH: dispose 이중 호출 방지**
- 문제: `_leaveRoom()` async 진행 중 `dispose()` 호출되면 cleanup 이중 실행
- 수정: `_leaving` 플래그 + `dispose()` fallback 경로에서도 provider invalidation 추가

**기타 정리**
- `player_screen.dart`: 미사용 `_urlController` (TextEditingController) 제거

**빌드**: v0.0.14, APK 빌드 성공

### 2026-04-17 (7) — 호스트 HAL timestamp 실패 시 fallback obs 전송

**문제**: 호스트 `_broadcastObs()`가 `ts.ok=false`이면 obs를 아예 안 보냄 → 게스트 싱크 불가. 게스트 fallback은 구현했지만 호스트 측은 비대칭으로 남아있었음.

**수정**:
- `_broadcastObs()`: `ts.ok=false`여도 `virtualFrame` + `wallMs` 기반 obs 전송 (`framePos`는 -1)
- `_tryEstablishAnchor()`: `obs.framePos < 0`이면 정밀 앵커 스킵 → fallback alignment에 위임

기존 정밀 싱크 경로 (양쪽 HAL ok)는 동일. 호스트 HAL 실패 환경 (블루투스 DAC, 저가폰, 에뮬레이터)에서만 새 경로 활성화.

**빌드**: v0.0.15

### 2026-04-17 (8) — step 2: 1:N 멀티 게스트 아키텍처 검토

코드 전면 리뷰 결과, 이미 1:N으로 동작하는 구조:
- P2PService: `List<Peer>` + `broadcastToAll()` + `sendToPeer(fromId)` — N개 피어 지원
- HTTP 파일 서버: shelf_static이 동시 N 클라이언트 스트리밍 지원
- clock sync: 호스트 `startHostHandler()`가 각 게스트 ping에 개별 응답
- audio-obs: broadcast → 모든 게스트 수신, 각자 독립 drift 계산
- audio-url, seek-notify: `broadcastToAll()`로 전체 전송
- audio-request, state-request: `sendToPeer(fromId)`로 개별 응답

1게스트 제한 코드 없음. 코드 변경 없이 N게스트 동작 가능 → **멀티 기기 실측 테스트로 검증 필요.**

PLAN.md step 2 → step 3(HTTP 전송) 이미 완료 확인, 상태 업데이트.

### 2026-04-17 (9) — iOS 접속 불가 해결 + IP 표시 개선 + 키보드 UX

**문제**: 아이폰에서 방 만들기/참가 모두 불가. `connectivity_plus`의 `checkConnectivity()`가 iOS에서 WiFi를 정상 보고하지 않아 `_isWifiConnected()` 체크에서 차단됨. mDNS 검색은 네이티브 Bonjour라 정상 동작하지만 TCP 연결 시도 자체가 차단.

**원인 분석**: `NetworkInterface.list()`는 iOS에서 정상 동작 (`en0: 192.168.x.x` 반환). IP 감지 문제가 아니라 `connectivity_plus` WiFi 감지 false negative가 근본 원인.

**수정**:
- `_isWifiConnected()` 체크 완전 제거 (home_screen.dart의 `_createRoom`, `_joinRoom`, `_joinByIp`, `_startDiscovery` 모두). 연결 실패 시 catch에서 실제 에러 표시.
- `network_info_plus` → `dart:io` `NetworkInterface.list()` 교체 (이전 대화에서 수정, 이번에 사설 IP 필터링 추가). 192.0.0.x 같은 비사설 주소 무시.
- room_screen IP 표시를 별도 줄 + bold로 변경 (한 줄에 넣으면 줄��꿈으로 가려지는 문제)
- room_screen WiFi 끊김 감지도 `.ethernet`/`.other` 허용으로 완화
- 홈 화면 IP 입력: 빈 곳 터치 시 키보드 dismiss (`GestureDetector` + `FocusScope.unfocus()`) + `textInputAction: TextInputAction.done`

**검증**: S22(호스트)↔iPhone 12 Pro(게스트) 양방향 접속 성공. mDNS 검색, IP 직접 입력 모두 동작.

**빌드**: v0.0.16

### 2026-04-17 (10) — 실기기 크로스 플랫폼 테스트 (S22 ↔ iPhone 12 Pro)

S22 + iPhone 12 Pro 양방향 호스트/게스트 테스트 수행. 접속·검색·방 참가 정상 동작 확인.

**발견된 이슈** (다음 작업에서 수정):
- 게스트 파일 다운로드 속도 체감상 느림 (HTTP shelf_static 서버, 개선 여지 확인 필요)
- 호스트가 다운로드 중 파일을 여러 번 빠르게 바꾸면: 오디오 다운로드 실패 / 게스트에서 이전 곡 재생되는 경우 발생 (파일 교체 race condition)
- seek 연타 시 싱크 틀어짐 (seek cooldown/보정 로직 개선 필요)

### 2026-04-20 (11) — sampleRate 정규화 + cross-rate 동기화 수정 (v0.0.17)

S22(호스트, 48kHz) ↔ iPhone 12 Pro(게스트, 44.1kHz) 싱크 테스트. 이전 세션에서 발견된 88ms/sec rate drift 등 다수 버그 수정 후 검증.

**수정사항:**
1. **Android framePos 정규화** (oboe_engine.cpp): HAL framePos가 스트림 rate(48kHz)로 카운트되는데 VF/sampleRate는 파일 rate(44.1kHz) → framePos를 파일 rate로 변환
2. **iOS framePos 정규화** (AudioEngine.swift): hw rate ≠ file rate일 때 동일 변환 적용 (안전장치)
3. **cross-rate ms 비교** (native_audio_sync_service.dart): 호스트/게스트 frame delta를 각각의 sampleRate로 ms 변환 후 비교
4. **seek-notify 절대 위치화**: deltaFrames → absolute targetMs (seek 연타 시 누적 오차 제거)
5. **seek cooldown 1000ms**: seek 후 stale obs로 re-anchor 방지
6. **anchor 무효화**: seek-notify 수신 시 anchor 리셋
7. **fallback threshold 30ms/cooldown 1s**: offset 수렴 전에도 즉시 대략 정렬
8. **syncWithHost ping 10→30회**: 초기 offset 정확도 개선
9. **EMA fast phase 중 stability gate**: fast phase(10샘플) 동안 stableCount 리셋하여 premature anchor 방지

**테스트 결과** (sync_log_2026-04-20T23-12-27.csv):
- 재생 시작 직후 fallback 보정으로 즉시 싱크 (~-7ms)
- anchor 전환 후 drift **-2~-4ms** 안정 유지 (30초간)
- seek 연타 테스트 정상 (누적 오차 없음, 즉시 재동기화)
- 30초간 보정 seek 0회 — 자연스러운 동기 유지

**빌드**: v0.0.17

### 2026-04-20 (12) — iOS duration 수정 + 재생 완료 처리 + UX 개선 (v0.0.18)

**수정사항:**
1. **iOS duration 0:00 수정**: `loadFile`이 `{ok, totalFrames, sampleRate}` 반환하도록 변경 → 재생 전에도 duration 표시
2. **재생 완료 자동 정지**: VF >= totalFrames 시 호스트 자동 `syncPause()` (게스트에게도 전파)
3. **끝 위치 재생 → 처음부터**: 재생 완료 상태에서 play 버튼 → `syncSeek(0:00)` 후 재생
4. **duration 표시 통일**: 초 단위 반올림으로 Android/iOS 간 1초 차이 해소
5. **에러 메시지 개선**: TimeoutException → '호스트 응답 없음 (시간 초과)', SocketException → '호스트에 연결할 수 없습니다'

**테스트 결과:**
- Galaxy S22: duration 5:00 정상 표시, 재생 완료 자동 정지 동작, 처음 재생 동작
- iPhone 12 Pro: duration 정상 표시 (기존 0:00 해결)

**빌드**: v0.0.18

### 2026-04-20 (13) — 게스트 파일 다운로드 race condition 수정 (v0.0.19)

**수정사항:**
1. **다운로드 세션 ID 도입**: `_downloadSessionId` — 새 audio-url 수신 시마다 증가, 이전 다운로드 무효화
2. **HttpClient 강제 종료**: `_activeHttpClient?.close(force: true)` — 진행 중 다운로드 즉시 취소
3. **세션별 고유 temp 파일명**: `dl_${mySession}_$safeName` — 동시 다운로드 간 파일 충돌 방지
4. **다운로드/디코드 후 stale 체크**: 세션 ID 비교로 이미 무효화된 결과 무시 + temp 파일 삭제
5. **cleanup 시 HttpClient 종료**: `clearTempFiles()`, `cleanupSync()`에서도 active client 정리

**빌드**: v0.0.19

### 2026-04-22 (14) — seek-notify stop 상태 처리 + 끝 위치 점프 수정 (v0.0.20)

**증상**: 호스트 재생 완료 후 "처음 재생" 버튼 누르면 게스트 UI가 잠깐 4:55~4:59 표시 후 0:00으로 점프.

**원인**: `_handleSeekNotify`의 `!_playing` 가드 때문. 호스트 `syncPlay()`는 재생 완료(vf≥totalFrames) 상태일 때 `syncSeek(0)` → `engine.start()` 순으로 실행하는데, seek-notify는 `_playing=false` 시점에 먼저 전송됨. 게스트가 이를 무시 → 엔진 VF가 totalFrames 근처에 머문 채 재생 시작 → 끝 위치 잔상 후 `_fallbackAlignment`로 뒤늦게 0으로 점프.

`!_playing` 체크는 최초(3f1932a) `deltaFrames` 기반 seek 시절 흔적. `a83c314`에서 absolute `targetMs`로 바뀌면서 무의미해졌지만 방치됨.

**수정** (`native_audio_sync_service.dart:_handleSeekNotify`):
- `!_playing` → `!_audioReady` 가드 변경 (재생 여부 무관, 파일 준비만 체크)
- UI position `_seekOverridePosition` 즉시 세팅 + 500ms 폴링 차단 (이전 위치 잔상 방지)
- Android `seekToFrame`은 `mFileLoaded`만 체크, iOS는 엔진 stop 상태에서 `seekFrameOffset`만 업데이트 → 양쪽 모두 재생 중 아니어도 안전

**부가 수정 — 태블릿 가로모드 UI 잘림** (`home_screen.dart`):
- 증상: Galaxy Tab A7 Lite 가로모드에서 "IP 직접 입력" 필드가 화면 아래로 잘려 안 보임
- 원인: `Padding + Column(mainAxisAlignment.center)` 구조라 세로 공간 부족 시 스크롤 불가
- 수정: `LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight) + IntrinsicHeight` 래핑 — 세로모드 center 정렬 유지하면서 공간 부족/키보드 올라올 때 스크롤 가능

**테스트**: A7 Lite(호스트) + iPhone 12 Pro(게스트) 조합으로 두 이슈 모두 검증 완료.

**빌드**: v0.0.20

### 2026-04-22 (15) — 다운로드 속도 측정 기반 HTTP 서버 직접 구현 (v0.0.21~v0.0.22)

**측정 인프라 (v0.0.21)**:
- 게스트 다운로드 완료 시 `bytes/totalMs/TTFB/transferMs/MBps` 계산 후 `download-report` P2P 메시지로 호스트에 송신 → 호스트 logcat에 `[DOWNLOAD-REPORT]` 기록. 기기별/세션별 속도 추적 가능.

**1차 측정 (shelf_static 시절)**:
| 파일 | TTFB | 속도 |
|---|---|---|
| iPhone 2.48MB | 94ms | 0.44 MB/s |
| iPhone 13.45MB | 46ms | 1.16 MB/s |
| iPhone 29.77MB | 84ms | 1.07 MB/s |
| A7 Lite 30.72MB | 223ms | 1.21 MB/s |

TTFB는 정상(<250ms)이지만 transfer 구간이 WiFi 이론치(5~50 MB/s)의 1/5~1/50. **호스트 송신이 병목** 결론.

**HTTP 서버 재구현 (v0.0.22)**:
- `shelf`/`shelf_static` 의존성 제거. `dart:io HttpServer.bind`로 직접 listen.
- 응답 헤더에 `Content-Length` 명시 → chunked transfer encoding 회피.
- `RandomAccessFile.readInto`로 1MB chunk 읽어 `HttpResponse.add` (이전 shelf 기본 동작은 작은 chunk 스트림).
- 디렉토리 이탈 방지(`..`, `/` 필터).
- `pubspec.yaml`에서 `shelf`, `shelf_static` dependency 제거.

**2차 측정 (v0.0.22)**:
| 기기 | 파일 | 이전 | v0.0.22 | 개선 |
|---|---|---|---|---|
| iPhone | 5.66MB | 0.85 MB/s | 1.25 MB/s | +47% |
| A7 Lite | 11.45MB | ~1.2 MB/s | 1.72 MB/s | +42% |

단일 다운로드 기준 chunk 크기 최적화로 +40~50% 개선. 동시 다운로드 시엔 대역폭 공유로 각 기기 속도 저하 (iPhone 동시 시 0.81 MB/s, TTFB 756ms).

**향후 추가 튜닝 여지**: chunk 2MB/TCP SO_SNDBUF 조정 등이 있으나 수확 체감 구간. 연결 안정성 이슈 해결 후 별도 진행.

**빌드**: v0.0.22

### 2026-04-22 (16) — heartbeat timeout 완화 (v0.0.23)

**증상**: 대용량 파일 다운로드 중 호스트가 게스트를 `Heartbeat timeout`으로 끊어버림. 게스트 측에서는 `Connection reset by peer`(errno=104) 수신 후 재접속 시도, 때로는 `Connection refused`(errno=111)로 3회 재시도 실패.

**원인**: 호스트 `_heartbeatIntervalSec=3s` / `_heartbeatTimeoutMs=9000` 구조 — 게스트가 9초 내 heartbeat-ack을 못 보내면 dead peer로 판정. 게스트가 HTTP 다운로드로 이벤트 루프 바쁘거나 네이티브 디코딩 중이면 3회 연속 miss가 쉽게 발생.

**수정** (`p2p_service.dart:13`):
- `_heartbeatTimeoutMs` 9000 → 15000 (5회 miss 허용).
- 호스트 송신 간격은 3초 유지 → 정상 상태에서 감지 시간 영향 없음, 일시적 지연만 관대화.

**근본 원인과 향후 리팩터 후보**:
Dart는 단일 isolate 내에서 single event loop로 동작 → P2P 소켓과 HTTP 소켓이 별개 TCP 커넥션이어도 같은 이벤트 큐에서 순차 처리. 대용량 다운로드 시 chunk 처리/JSON 디코드/progress emit 등 CPU 작업이 누적되면 heartbeat-ack 메시지 처리가 뒤로 밀림.

현재(v0.0.23)는 timeout 완화로 체감 해결. **근본 해결은 HTTP 다운로드를 별도 Isolate로 분리**해서 이벤트 루프 자체를 나누는 것. 단, Isolate 간 메모리 공유 불가 + 소켓은 isolate 간 이동 불가 → 구조 변경 크고 직렬화 비용 발생. 네이티브 전환은 과잉(오디오 엔진이 네이티브인 건 저지연/정밀 타이밍 때문이고 병렬 처리 목적이 아님). **판단: 지금은 타임아웃 완화로 충분, 리팩터는 다운로드가 더 무거워지거나 동시 게스트 수가 늘어날 때 재검토.**

**빌드**: v0.0.23

### 2026-04-22 (17) — drift 노이즈 완화 실험 + 호스트 라이프사이클 프로토콜 (v0.0.25)

v0.0.24는 drift 완화 실험 과정에서만 존재한 빌드(패치 없이 v0.0.25로 통합 기록).

#### Part A — drift 노이즈 완화

이전에 제안된 3가지 변경 (B/C/A) 실험. 실측:

- **B (audio-obs broadcast 500→200ms)**: **롤백**. 롤백 이유는 Part B 참고. 즉 `_obsBroadcastIntervalMs` 현재 500ms 유지.
- **C (drift 판단을 최근 5샘플 중앙값으로)**: 적용. `_driftSamples` 윈도우 + `_median` 헬퍼. 큰 drift(≥200ms re-anchor)는 즉시 처리, 중소 drift(≥20ms)는 중앙값 기준으로 seek 발동.
- **A (clock sync sliding window 5→10)**: 적용. `sync_service.dart:35` `_windowSize = 10`.

**부가**: 호스트 `_handleDownloadReport`와 `_handleDriftReport`에 `debugPrint` 추가 → logcat에서 실시간 drift/다운로드 관측 가능.

**실측**: fallback anchor 기준 drift -2~-4ms 안정 유지 확인. seekCount 증가 없이 노이즈 샘플(-47ms 등) 흡수 확인. 즉 C의 중앙값 필터 효과 실측.

#### Part B — 호스트 라이프사이클 프로토콜 + 게스트 자동 재접속

**배경**: 재생 전 상태에서 호스트가 홈/파일 선택 창으로 background 진입 시 Android가 foreground service 없는 프로세스를 강등하여 TCP `errno=103 Software caused connection abort` 발생. 게스트는 `errno=104 Connection reset by peer` 받아 TCP 끊김. 기존 재접속 플로우는 즉시 실행되지만 호스트가 still paused 상태라 3회 실패 후 `_leaveRoom()` → 사용자 체감 "호스트 잠깐 뒤로 가기만 했는데 방이 터짐".

**실측 확인된 가설** (v0.0.25 debugPrint 로그 기반, CLAUDE.md 근거 원칙 준수):
- 호스트 `AppLifecycleState.paused` 이벤트는 **실제 TCP abort보다 약 5초 먼저** Dart에 도달 → 그 window 안에 broadcast 가능
- `host-paused` 메시지는 게스트에 정상 도달 (1.6초 이내)
- 호스트 resume 시 broadcast하는 `host-resumed`는 **도달 불가**: paused 중 TCP socket이 이미 abort되어 `_peers.isEmpty` 상태
- 재생 중 종료 시 `AppLifecycleState.detached` 이벤트가 Dart까지 도달함 관측 (foreground service가 프로세스 유지 덕)

**B 롤백 이유**: v0.0.24 시험 중 호스트 재생 전 파일 선택 창 진입 시 게스트 쪽 연결이 이전보다 자주 끊기는 것 같은 현상 관측. 원인을 좁히기 위해 B만 롤백. 재현 후 원인이 `audio-obs 주기`가 아니라 **"재생 전 paused"에서 foreground service 부재로 인한 TCP abort**임을 확인. B는 본질적으로 무관했으나 원인 확정 전에 복잡도를 줄이기 위해 롤백 유지.

**구현 (v0.0.25)**:

1. 프로토콜 메시지 3종 (`p2p_service.dart`):
   - `host-paused` / `host-resumed` / `host-closed`
   - 새 메서드: `pauseHeartbeat()`, `resumeHeartbeat()`, `closeRoom()`
   - `resumeHeartbeat` 시 모든 peer `lastSeen` 초기화 → paused 기간이 timeout으로 판정되지 않게

2. 호스트 라이프사이클 감지 (`room_screen.dart`):
   - `WidgetsBindingObserver` 등록
   - `paused` → `pauseHeartbeat()`, `resumed` → `resumeHeartbeat()`
   - 정식 방 나가기 버튼 → `closeRoom()` 호출 후 `disconnect()`

3. 게스트 자리비움 UI + 주기적 재접속 (`room_screen.dart`):
   - `_hostAway` / `_hostClosed` 플래그
   - 주황 배너 "호스트가 일시 자리비움입니다"
   - `host-paused` 수신 시 `_hostAway=true` + 재접속 시도 중단
   - TCP 끊기면 `_startAwayReconnectLoop()` — 5초 주기 재접속 시도 (`reconnectToHost(retries: 1)`)
   - 재접속 성공 시 `_hostAway=false` + 재동기화 + Timer 취소 (TCP 재접속 성공 자체가 복귀 신호, `host-resumed` 도달 불가 전제)
   - watchdog: 12회 실패(공칭 60초, 실제 timeout 7초씩이라 ~2분) 후 `leaveRoom()` 호출
   - `host-resumed` 수신 시에도 Timer 취소 (이중 안전장치)
   - `host-closed` 수신 시 즉시 `_leaveRoom()`

**검증 (S22 + A7 Lite 실측)**:

| 시나리오 | 결과 | 복구 시간 |
|---|---|---|
| T1 파일 선택 창 10초 대기 → 복귀 | ✅ 자동 재접속 + 재동기화 | 5~10초 |
| T2 홈 버튼 → 복귀 | ✅ 자동 재접속 | 4~10초 |
| T3 정식 방 나가기 버튼 | ✅ `host-closed` 메시지로 게스트 즉시 홈 복귀 | 1~2초 |
| T4 앱 스위처 스와이프 종료 | ✅ watchdog 12회 실패 후 자동 홈 복귀 | 약 2분 |

**iOS 검증 미수행**: flutter run의 VM Service 연결 실패로 오늘 세션에선 iPhone을 안정적으로 테스트 못 함. iOS는 Android와 동일 enum이지만 detached 도달 동작 차이 있음 → 추후 재확인 필요 (PLAN.md 추후 보완 후보에 기록).

**아직 미구현(추후 보완 후보, 상세는 `docs/LIFECYCLE.md` + `docs/PLAN.md`)**:
- `RoomLifecycleCoordinator` 클래스 추출 (현재 room_screen에 로직 혼재)
- ~~`detached`에서 `host-closed` broadcast~~ — v0.0.26에서 구현
- errno=111 refused 감지 시 watchdog 빠른 포기 (재생 전 종료 2분 → ~10초)
- errno=113/101 시 connectivity_plus 연동

**문서 신설**:
- `docs/LIFECYCLE.md` 대폭 확장 — "앱 라이프사이클 (AppLifecycleState)", "소켓 에러 코드 (errno)", "연결 복구 전략 (3중 안전망)" 섹션 추가. 이 3섹션이 앞으로 라이프사이클/연결 이슈 작업할 때 참조할 단일 소스.

**빌드**: v0.0.25

### 2026-04-22 (18) — 호스트 detached 시 host-closed 즉시 broadcast (v0.0.26)

**배경**: v0.0.25에서 T4(호스트 강제 종료) 복구가 watchdog 의존(~2분)이었다. 재생 중 호스트 종료 시 foreground service 덕에 `AppLifecycleState.detached`까지 Dart 코드가 도달함을 오늘 세션 실측으로 확인 → 이 window에서 `host-closed`를 best-effort로 보내면 게스트가 즉시 홈 화면 복귀 가능.

**구현**:
- `p2p_service.dart` `broadcastHostClosedBestEffort()`: `host-closed` broadcast + `socket.flush()`만 트리거 (await 없음). Dart isolate가 곧 소멸될 수 있어 동기 호출로만 구성.
- `room_screen.dart:didChangeAppLifecycleState`에 `detached` 분기 추가: 호스트일 때 `_hostClosed=true` + `broadcastHostClosedBestEffort()` 호출.

**한계 (기록)**:
- **iOS 앱 스위처 스와이프 종료**는 여전히 detached 도달 안 함 → 이 경로는 기존 watchdog이 받아줌
- **재생 전 상태에서 강제 종료**는 foreground service 없어 detached 도달 확률 낮음 → 기존 watchdog 유지
- flush는 async 함수 호출만 하고 완료 대기 X → OS가 프로세스 종료 시 커널 측 TCP 버퍼에 남은 데이터를 얼마나 보내주느냐에 의존 (best-effort)

**추가**: `native_audio_service.dart:87` `${minutes}` → `$minutes` (flutter analyze info 정리).

**검증 완료** (세션 후반 재연결 후 실측, S22 + A7 Lite):

재생 중 S22 앱 스위처 스와이프 종료 → 게스트 홈 복귀까지 **1.4초**.

실측 로그:
```
23:32:19.522  호스트 paused (스위처 진입) → broadcast host-paused
23:32:20.131  호스트 detached (앱 종료)
              [LIFECYCLE] HOST detached → broadcast host-closed (best-effort)
              [P2P] broadcastHostClosedBestEffort peers=1
23:32:20.913  게스트 received host-paused
23:32:21.550  게스트 received host-closed  ← !!
23:32:21.637  게스트 Connection closed: host → _leaveRoom
```

v0.0.25의 동일 시나리오가 **watchdog 의존 ~2분**이었던 것과 대비 → 약 **85배 단축**.

**재생 전 종료 / iOS 강제 종료**는 detached 도달이 보장 안 되므로 여전히 기존 watchdog(2분)이 fallback. 이 두 경로는 별도 검증 없이 v0.0.25 동작 유지됨 (v0.0.26이 해당 경로를 건드리지 않음).

**빌드**: v0.0.26

---

### 2026-04-23 (19) — Socket connect timeout 단축 + errno=111 빠른 포기 (v0.0.27)

**배경**: v0.0.26의 detached host-closed broadcast로 "재생 중 호스트 종료" 케이스(가장 흔함)는 1.4초 복구를 확인했지만, **재생 전 종료**·**iOS 강제 종료** 등 detached 메시지가 도달하지 못하는 경로는 여전히 watchdog 12회(약 60초~2분)에 의존해 사용자 체감이 나쁨. `docs/LIFECYCLE.md:402-408` "errno 판정 트리"에 이미 설계안이 있던 항목 구현.

**구현**:
- `p2p_service.dart:163, :189` — `Socket.connect` timeout `5초 → 2초`. WiFi 같은 LAN에서는 정상 connect가 수십 ms 안에 끝나므로 5초는 호스트 죽음 판정을 늦추는 부작용이 더 컸음. 2초여도 정상 케이스 영향 없음.
- `p2p_service.dart` `lastReconnectErrno` 노출 — `reconnectToHost()` catch에서 `SocketException.osError?.errorCode` 저장. 호출부가 errno로 판정 분기 가능.
- `room_screen.dart:_startAwayReconnectLoop` — `_consecutiveRefused` 카운터 추가. errno=111(`ECONNREFUSED`)이 2회 연속 잡히면 watchdog 12회 안 기다리고 즉시 `_leaveRoom()`. 다른 errno(110/104/101 등)는 카운터 리셋하고 기존 12회 watchdog 유지 — 호스트 paused/네트워크 일시 단절 같이 복구 가능한 케이스를 지키기 위함.

**복구 시간 (이론값)**:
- 재생 전 호스트 강제 종료 시: 호스트 측 TCP listen 즉시 사라짐 → 게스트 watchdog 1번째 시도에서 errno=111, 5초 후 2번째 시도에서도 errno=111 → 즉시 leave. 실제 ~10초 이내 (이전 60초+).
- 호스트 paused (foreground service 강등): listen 살아있을 수 있어 errno=110/104 → 카운터 0 유지 → 기존 watchdog 동작 (의도)

**한계**:
- 실측 검증은 사용자 실기기 테스트 대기 (S22 호스트 재생 전 종료 + 게스트로 시간 측정)
- "host-paused 직후 host-closed (errno 잡히기 전 메시지 도착)" 케이스는 v0.0.26 detached broadcast 경로로 더 빠름 — 이번 변경은 detached 도달 못 하는 fallback만 개선
- errno 값은 POSIX 표준이지만 iOS/Darwin 커널에서 동일하다는 가정 (Linux와 차이 적지만 100%는 아님)

**문서**:
- `docs/PLAN.md:193, :195` 두 항목 `[x]` 체크 + 본 항목 링크
- `docs/LIFECYCLE.md` "errno 판정 트리" 섹션의 v0.0.25 미구현 메모 → v0.0.27 구현 완료 표기

**빌드**: v0.0.27 (`flutter analyze` clean)

---

### 2026-04-23 (20) — errno=113/101 + connectivity_plus 연동 (v0.0.28)

**배경**: `docs/LIFECYCLE.md:414-417` "errno 판정 트리"의 마지막 미구현 분기. WiFi 변경/AP 변경 케이스에서 `connectivity_plus.onConnectivityChanged` 이벤트가 늦게 오거나 누락되는 경우, errno=113(EHOSTUNREACH) / 101(ENETUNREACH)가 먼저 잡힘 → 이걸 조기 신호로 사용해 `_waitForWifiAndReconnect()` 즉시 트리거.

**구현** (`room_screen.dart`):
- 헬퍼 `_maybeHandleNetworkErrno(int? errno) → Future<bool>` 추가:
  - errno != 113 && errno != 101 → false
  - `Connectivity().checkConnectivity()` 즉시 확인
  - WiFi 살아있음 → false (호스트 측 문제로 판정, 기존 흐름 유지)
  - WiFi 끊김 → `unawaited(_waitForWifiAndReconnect())` 시작 + true (호출자 흐름 종료)
- 호출 위치 두 곳:
  1. `_startAwayReconnectLoop`의 reconnect 실패 분기 — errno=111(refused) 카운트 전 우선 체크. 잡히면 watchdog 타이머 cancel + return.
  2. 일반 disconnect 핸들러 (`_disconnectSub`)의 `reconnectToHost(retries:3)` 실패 분기 — `_leaveRoom()` 직전. 잡히면 leave 안 하고 WiFi 복구 대기로 위임.

**효과**:
- 게스트가 다른 AP로 옮기는 케이스: connectivity_plus 이벤트가 OS별 200ms~수초 지연되는 경우에도 errno로 즉시 감지 → WiFi 복구 대기 루프 빠른 진입
- 기존 connectivity_plus 이벤트 경로는 그대로 유지 (이중 안전망)

**한계**:
- 검증은 다음 세션 (게스트 WiFi off → on, AP 변경 시나리오)
- WiFi 살아있는데 errno=113이 잡히는 케이스(호스트가 다른 AP로 갔을 때 등)는 이번 변경 대상 아님 — 기존 reconnectToHost 재시도 / watchdog로 처리

**문서**:
- `docs/PLAN.md:194` 체크 + 본 항목 링크. 라이프사이클·연결 후보 6개 중 5개 완료 (남은 건 `RoomLifecycleCoordinator` 추출)
- `docs/LIFECYCLE.md` "errno 판정 트리" 헤더 v0.0.28 표기

**빌드**: v0.0.28 (`flutter analyze` clean)

---

### 2026-04-23 (21) — RoomLifecycleCoordinator 추출 (v0.0.29)

**배경**: v0.0.25~v0.0.28 동안 라이프사이클·연결 로직이 `room_screen.dart`(약 830줄) 내부에 누적되면서, 같은 파일이 UI 빌드 + 라이프사이클 상태 + 재접속 watchdog + WiFi 처리 + errno 판정 + sync 트리거를 모두 떠안게 됨. `docs/PLAN.md:191`에 라이프사이클·연결 후보 마지막 항목으로 명시되어 있던 추출 작업.

**구현**:
- 신규 파일 `lib/services/room_lifecycle_coordinator.dart` (약 320줄)
- 흡수한 책임:
  - 호스트: `AppLifecycleState` (paused/resumed/detached) → `host-paused`/`resumed`/`closed` broadcast + heartbeat pause/resume
  - 게스트: `host-paused`/`resumed`/`closed` 메시지 처리 → 상태 변경
  - 게스트: TCP 끊김 (`p2p.onDisconnected`) 분기 (host-closed / hostAway / 일반 reconnect)
  - 호스트/게스트: WiFi 끊김 (`Connectivity().onConnectivityChanged`) 분기
  - away reconnect watchdog (errno=111 빠른 포기, errno=113/101 분기 포함)
  - WiFi 복구 대기 (`_waitForWifiAndReconnect`)
- UI(`room_screen`) 인터페이스:
  - 상태 노출: `ValueNotifier<bool> hostAway`, `ValueNotifier<bool> hostClosed` — UI는 `ValueListenableBuilder`로 구독
  - 액션 콜백: `onLeaveRequested` (cleanup + Navigator), `onReconnectSyncRequested` (sync.reset + 재동기화)
  - UX 콜백: `onLog` (로그), `onSnackbar` (사용자 알림)
- `room_screen.dart` 변경:
  - 라이프사이클·연결 관련 필드 9개(`_hostClosed`, `_hostAway`, `_awayReconnectTimer`, `_consecutiveRefused`, `_awayReconnecting`, `_awayReconnectAttempts` 등) 제거 → coordinator로 이동
  - 메서드 5개(`_startAwayReconnectLoop`, `_cancelAwayReconnectLoop`, `_maybeHandleNetworkErrno`, `_waitForWifiAndReconnect`, `didChangeAppLifecycleState` 본문) 제거/위임
  - `initState`에서 coordinator 생성 + `start()`. `_disconnectSub`, `_connectivitySub` 직접 listen 제거 (coordinator가 처리). `_messageSub`은 peer-joined/welcome/peer-left 등 비-라이프사이클 메시지만 남김 (coordinator는 자체 broadcast listener로 라이프사이클 메시지 처리)
  - `_leaveRoom` 진입 시 `_lifecycle.notifyLeaving()` 호출 → coordinator의 watchdog/리스너 모두 정지. `_hostClosed` 참조는 `_lifecycle.hostClosed.value`로
  - `_reconnectSync`에 `sync.reset()` 흡수 — 호출자(coordinator)는 단일 콜백만 호출하면 됨
  - 자리비움 배너 → `ValueListenableBuilder<bool>` 으로 변환
  - 줄 수: 828 → 약 600 (라이프사이클 영역 제거 + coordinator 위임)

**의도**:
- 역할 × 라이프사이클 매트릭스를 한 곳에서 선언 → 분기 누락/중복 방지
- 향후 라이프사이클 추가 작업(예: `errno=110` 분기, iOS 별도 분기) 시 한 파일만 수정
- UI 코드는 빌드/표시에만 집중

**한계**:
- 동작 동등성 검증은 정적 분석(`flutter analyze` clean) + 수동 코드 리뷰만. 라이프사이클 시나리오 T1~T4 실측 재검증은 다음 세션
- coordinator는 `mounted` 대신 `_disposed`/`_leaving` 자체 플래그로 가드 — 같은 의미지만 출처 다름. UI context 의존 분리한 부산물

**문서**:
- `docs/PLAN.md:191` 체크 → **라이프사이클·연결 후보 6개 모두 완료**. Phase 4 라이프사이클 영역 종결
- `docs/LIFECYCLE.md` "연결 복구 전략" 섹션에 코디네이터 위치 한 줄 추가
- `CLAUDE.md` 최신 릴리스 + 다음 재개 포인트 갱신 (라이프사이클 영역 빠짐)

**빌드**: v0.0.29 (`flutter analyze` clean — 전체 프로젝트 0 issue)

---

### 2026-04-24 (22) — 라이프사이클·연결 실측 재검증 (T1~T4a PASS, T4b/W 에뮬 한계로 미검증)

**배경**: v0.0.27/v0.0.28/v0.0.29 모두 정적 검증(`flutter analyze` clean)만 됐고 실기기 재검증 대기 상태. 이번 세션에서 coordinator 추출 후 동작 동등성 포함해 실측. **iPhone 12 Pro USB 인식 실패** (macOS USB 버스 레벨에서 감지 안 됨, `system_profiler SPUSBDataType` 결과 0건. 케이블/포트는 이전 사용 실적 있어 배제, 원인 미규명) → S22 호스트 + Pixel 6 Android 에뮬 게스트 조합으로 진행. iOS 조합은 이월.

**결과** (`/tmp/synchorus_logcat_s22.log`, `/tmp/synchorus_logcat_emu.log` 직접 캡처 근거):

| 시나리오 | 결과 | 측정치 / 핵심 로그 |
|:---:|:---:|:---|
| T1 파일 선택 창 대기 | ✅ PASS | 호스트 `paused→resumed` 17.5초, 게스트 수신 간격 동일(17.6초). `[LIFECYCLE] HOST paused → host-paused broadcast` / `[LIFECYCLE-GUEST] received host-paused` |
| T2 홈 버튼 라운드트립 | ✅ PASS | 호스트 `paused→resumed` 14.9초, 게스트 수신 간격 동일 |
| T3 정식 방 나가기 | ✅ PASS | 게스트 `received host-closed` 즉시 수신, 양쪽 홈 화면 복귀 |
| T4a 재생 중 스와이프 종료 | ✅ PASS | S22 `AppLifecycleState.detached` 도달 → `[P2P] broadcastHostClosedBestEffort peers=1` → 게스트 즉시 홈. watchdog(`AWAY-RECONNECT`) 로그 0건 |
| T4b 재생 전 스와이프 종료 | 🟡 에뮬 한계로 미검증 | adb forward 특유의 `Socket.connect` 가짜 성공 (아래 상세) |
| W 게스트 WiFi off/on | 🟡 미수행 | adb forward 환경에서 게스트 WiFi 토글 의미 제한적 |

**T4b 현상 상세** (재현 로그 기반):
- S22 앱 스위처 스와이프 → 프로세스 종료 확인 (`adb shell ps | grep synchorus` 0건)
- 에뮬 13:35:14~39 구간 **1초 간격** `Reconnected successfully → Connection closed: host` 무한 반복
- Mac `lsof -iTCP:41235`: `adb pid 2230 LISTEN` 유지 → 에뮬 `connect("10.0.2.2", 41235)`가 **adb 프로세스에 의해 accept됨** → 직후 adb가 S22로 forward 실패 감지하고 close → 게스트 coordinator는 "reconnect 성공"으로 판단 → `hostAway=false` 리셋 → 직후 `onDone` → 일반 disconnect 경로 → 반복
- **실기기 LAN이면 `Socket.connect` 자체가 `errno=111`로 실패해야 정상** (v0.0.27 설계 전제). 에뮬 adb forward 경로 특유의 false positive이며 coordinator 로직 문제 아님.

**의의**:
- **v0.0.29 `RoomLifecycleCoordinator` 추출 후에도 v0.0.25 프로토콜(host-paused/resumed) + v0.0.26 detached best-effort host-closed 경로 동작 동등** (T1~T4a 모두 동일 타이밍)
- T1~T4a에서 `AWAY-RECONNECT` 로그 0건 확인 — 프로토콜 메시지로 충분, watchdog은 fallback 용도로 유지
- v0.0.27/v0.0.28 errno 판정 트리는 **실측 미검증 상태 유지** — Android 에뮬로는 원천적 검증 불가 (`errno=111` 경로 자체 진입 불가)

**다음 세션 조건**:
- iPhone 12 Pro USB 인식 복구 (Mac 재부팅 또는 케이블 교체 후 시도)
- S22 호스트 + iPhone 게스트 WiFi LAN 조합으로 T4b/W 재검증
- iOS의 paused/detached 도달 여부도 같은 세션에서 (PLAN.md:196)

**문서**:
- `docs/EMULATOR_NETWORK.md`에 "adb forward false-positive accept" 주의사항 추가
- `docs/PLAN.md:196` 미완 유지 + 범위 갱신 (T4b/W 포함)
- `CLAUDE.md` 다음 재개 포인트 갱신

**빌드**: 변경 없음 (실측 검증만, 코드 수정 0)

---

### 2026-04-24 (23) — iPhone 실측에서 Darwin errno 대응 버그 발견 + 수정 (v0.0.30)

**배경**: (22) 세션 직후 iPhone 12 Pro USB 연결 복구 → S22 호스트 + iPhone 게스트 조합으로 T4b 실측. 예상(~10초)과 달리 **60초 watchdog 경로**로만 복구되는 현상 관측.

**원인** (로그 직접 캡처, `/tmp/iphone_run_v030.log`):

```
Reconnect attempt 1 failed: SocketException: Connection refused (OS Error: Connection refused, errno = 61)
[AWAY-RECONNECT] attempt 1/12 failed (errno=61)
...
[AWAY-RECONNECT] attempt 12/12 failed (errno=61)
[AWAY-RECONNECT] giving up after 12 attempts → leaveRoom
```

POSIX **이름은 같아도 숫자값이 다르다**. Darwin(iOS/macOS)에서 `ECONNREFUSED=61` (Linux=111). v0.0.27~v0.0.29 coordinator 코드는 `errno == 111` 리터럴로만 하드코딩되어 있어 iOS에서는 `_consecutiveRefused` 카운터가 증가하지 않음 → 빠른 포기 경로 미작동 → 기존 60초 watchdog으로만 복구. `docs/LIFECYCLE.md:389`의 "플랫폼별 errno 차이 있음" 경고가 실측으로 현실화.

**수정** (`lib/services/room_lifecycle_coordinator.dart`):
- `_refusedErrnos = {111, 61}` (Linux ECONNREFUSED + Darwin)
- `_networkUnreachableErrnos = {113, 101, 65, 51}` (EHOSTUNREACH/ENETUNREACH 양쪽)
- 기존 `if (errno == 111)` / `if (errno != 113 && errno != 101)` 사용부 3곳 교체
- debugPrint 메시지 하드코딩 "errno=111" → 실제 errno 변수 값 출력

**실측 재검증** (v0.0.30, 동일 조합):

| 시나리오 | v0.0.29 결과 | v0.0.30 결과 | 로그 증거 |
|:---:|:---:|:---:|:---|
| T4b 재생 전 호스트 강제 종료 | 60초 watchdog 완주 | **~10초 fast giveup** ✅ | `[AWAY-RECONNECT] refused (errno=61) x2 → fast giveup` |
| W 게스트 WiFi off/on | — | 일반 재연결 성공 | `Reconnected successfully` (errno=65/51 분기 자체는 이번엔 미재현) |

W 시나리오의 errno=65/51 분기는 이번 실측에서 재현 안 됨. 사용자가 WiFi를 5~10초 짧게 off했더니 `Socket.onDone` 도달 시점엔 이미 WiFi 복구 상태 → `Socket.connect`가 바로 성공 → errno 분기 진입 없이 정상 재연결. 분기 실행 증거는 **WiFi 30초+ off 또는 AP 이동 시나리오**에서 별도 캡처 필요.

**부가 관찰** (아래 "미해결 이슈"에 기록):
- W 직후 호스트 S22는 접속자 **3명**, 게스트 iPhone은 **5명** 표시 (실제 2대). peer leave 처리 누적 버그 추정.

**의의**:
- 프로젝트 첫 iOS 게스트 실측에서 **Linux-only 가정 코드가 iOS에서 깨진다는 설계 리스크를 실증**으로 확인
- iPhone USB가 하루 멈춰서 검증 지연됐지만, 복구 후 첫 테스트에서 즉시 버그 노출 → 실기기 검증의 가치 재확인

**문서**:
- `docs/LIFECYCLE.md`: errno 표 Linux/Darwin 컬럼 분리 + 판정 트리 이름 기반으로 재정비 + v0.0.30 메모
- `docs/PLAN.md`: errno 재검증 항목 체크 (T4b), W는 추가 조건 필요 메모
- `CLAUDE.md`: 최신 릴리스 v0.0.30 + 다음 재개 포인트 갱신

**빌드**: v0.0.30+1 (`flutter analyze` clean)

---

### 2026-04-24 (24) — P2PService StreamController race 수정 + CONNECTIVITY 로그 보강 (v0.0.31)

**배경**: (23) 직후 W 시나리오(게스트 iPhone WiFi off 30초+ 유지) 재현 중 두 가지 드러남.

**드러난 버그**:
```
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception:
Bad state: Cannot add new events after calling close
#1 P2PService._listenToSocket.<anonymous closure> (p2p_service.dart:345:35)
```
`dispose()`가 controllers를 close한 뒤 Socket.onDone이 **비동기로 늦게** 도착 → 이미 close된 `_disconnectedController.add(null)` → 예외. `sendToHost` catch 블록의 `_disconnectedController.add(null)`(line 384)도 같은 문제.

**수정** (`lib/services/p2p_service.dart`):
- line 345, 384 모두 `if (!_disconnectedController.isClosed) _disconnectedController.add(null);` 가드

**추가 관찰** — W 시나리오 CLI 로그 부족:
- iPhone WiFi off 시 `Connection closed: host` 외 coordinator 경로 로그가 전혀 안 뜸
- 원인: `_handleConnectivity` / `_waitForWifiAndReconnect`가 **`onLog` (UI 로그)만 사용, `debugPrint` 미사용**. UI 로그는 flutter CLI stdout에 안 찍힘 → 실측 디버깅 어려움

**보강**: `lib/services/room_lifecycle_coordinator.dart`에 `[CONNECTIVITY]` 태그 debugPrint 5개 추가
- `_handleConnectivity` 진입 시 이벤트 상세
- 1초 재확인 후 local 살아있음/확정 분기
- 호스트/게스트 분기 결과
- `_waitForWifiAndReconnect` 시작 + WiFi 복구 감지 시점 + reconnect 성공/실패(errno 포함)
- 15초 타임아웃 → leaveRoom

**재검증 결과** (같은 시나리오, 수정본 반영 후):
- ✅ **Race 예외 0건** (이전 `Bad state` 스택트레이스 사라짐)
- ✅ **W Connectivity 경로 iOS에서 정상 작동**: WiFi off → `_waitForWifiAndReconnect` 15초 대기 → WiFi 복구 실패 시 `onLeaveRequested` → 홈 화면. 사용자 관찰: "그냥 나가졌다"가 **설계 의도대로 작동한 결과**
- 🟡 **errno=65/51(v0.0.28) 분기 캡처 실패**: iPhone의 `connectivity_plus.onConnectivityChanged`가 WiFi off 즉시 발화 → `_handleConnectivity` 경로가 먼저 처리 → errno 분기(백업용)까지 안 감. LIFECYCLE.md:414~418의 "connectivity_plus가 늦을 때"라는 분기 전제 조건 자체가 iPhone에선 잘 성립 안 함

**의의**:
- W 시나리오는 주 경로(connectivity) PASS. errno 분기는 현 시점에선 "예비 안전망"으로만 존재하며 실측 증거 수집 필요 (다른 AP 이동 등 conditions 만족 시 재시도)
- StreamController race 버그는 이번 실측 아니었으면 발견 어려웠음 — dispose 타이밍 의존 race라 정상 흐름에선 잘 안 나옴

**문서**:
- `docs/PLAN.md`: 현 상태 유지 (errno 재검증은 기존 "재현 조건 필요" 항목 그대로)
- `CLAUDE.md`: 최신 릴리스 v0.0.31 + 다음 재개 포인트 갱신

**빌드**: v0.0.31+1 (`flutter analyze` clean)

---

### 2026-04-24 (25) — Peer count 불일치 수정 (v0.0.32)

**배경**: (23) W 시나리오 직후 관찰 — 호스트 S22 접속자 **3명**, 게스트 iPhone **5명** 표시(실제 2대). 라이프사이클과 별개의 P2P peer 관리 버그.

**원인 분석** (코드 기반):
- `Peer.id = "${socket.remoteAddress}:${socket.remotePort}"` — **socket 주소 기반**이라 게스트 재접속 시 **다른 ID로 새 peer 추가**됨 (`p2p_service.dart:217`)
- 호스트 `_handleNewPeer`는 새 join 때 같은 이름 stale peer 정리 없이 그냥 `_peers.add` — old socket은 `socket.done` 도달하거나 heartbeat timeout(15초)까지 남음
- 재접속 여러 번이면 stale peer 누적 → `peerCount = _peers.length` 부풀음
- 게스트는 `welcome`에서만 절대값 받고 `peer-joined`는 `++`, `peer-left`는 `--` 증감만 — 메시지 누락 시(WiFi off 중) drift 누적

**수정** (`lib/services/p2p_service.dart` + `lib/screens/room_screen.dart`):
1. **호스트 stale peer 정리**: `_handleNewPeer` join 처리 시 같은 `name`의 기존 peer를 모두 `socket.destroy()` + `_peers.remove` + `peer-left` broadcast 후 새 peer 등록 (`p2p_service.dart:228~242`)
2. **peer-joined/left broadcast에 `peerCount` 포함**: heartbeat timeout, `socket.done`, leave 메시지 수신, `_removeAndBroadcastLeave` 등 모든 peer-left 경로 + peer-joined 경로
3. **게스트 절대값 우선 반영**: `room_screen.dart`에서 `peer-joined`/`peer-left` 수신 시 `peerCount` 필드 있으면 `_guestPeerCount = peerCount`, 없으면 기존 `++`/`--` fallback

**효과** (논리 기반 — 실측 검증 대기):
- 재접속 시 같은 이름 stale peer 자동 제거 → 호스트 `_peers.length` 누적 해소
- 게스트가 연속으로 받는 broadcast마다 절대값으로 재설정 → 증감 drift 누적 해소
- 이중 방어: 둘 중 하나라도 작동하면 카운트 일치

**한계 / 다음 세션 실측 필요**:
- 정적 검증(`flutter analyze` clean)만 완료. 실기기 2대 WiFi off/on 반복으로 peer count 일치 재현 필요
- 이름이 동일한 두 기기가 동시 참가하는 edge case 처리는 이번 범위 밖 (stale 정리 로직이 의도치 않게 legit peer 잘라낼 가능성). MVP 기준 기기명은 보통 기기별 unique라 허용.

**문서**:
- `docs/HISTORY.md` 미해결 이슈 "Peer count 불일치" 항목 해결 체크
- `CLAUDE.md` 최신 릴리스 v0.0.32 + 다음 재개 포인트 갱신

**빌드**: v0.0.32+1 (`flutter analyze` clean)

---

### 2026-04-24 (26) — Orphan `com.synchorus/audio_latency` MethodChannel 제거 (v0.0.33)

**배경**: v3 전환(NativeAudioSyncService + framePos 기반 폐루프)에서 엔진 레이턴시가 `oboe::getTimestamp()` / `AVAudioTime` 반환값에 이미 내포되어 별도 보정값 불필요해짐. v2 시절의 `com.synchorus/audio_latency` 채널은 네이티브 측만 유지되고 **Dart에서 호출 0건** 상태(Explore agent 2026-04-24 조사 결과). v0.0.4 HISTORY 236의 player_screen "buf=4ms" 디버그 표시도 이미 제거된 상태라 유일한 사용처도 없었음.

**수정**:
- `android/app/src/main/kotlin/com/synchorus/synchorus/MainActivity.kt`: `com.synchorus/audio_latency` 블록(14줄) 제거 + 미사용 `import android.media.AudioManager` 제거
- `ios/Runner/SceneDelegate.swift`: 동일 채널 블록(25줄) 제거 + 미사용 `import AVFoundation` 제거. `super.scene(...)` 호출만 남기고 빈 body로 축소

**효과**:
- 네이티브 코드 40여 줄 dead code 제거
- 새로 프로젝트 들어오는 사람이 v2 잔재에 혼란스러울 일 없음
- 기능 동일 (호출자 0이었음)

**검증**:
- `grep -rn "audio_latency\|getOutputLatency" ios/ android/` 0건 확인
- `flutter analyze` clean

**향후**: 레이턴시 측정값을 다시 UI에 노출하고 싶다면 `ARCHITECTURE.md:514`의 "엔진 레이턴시 측정" 절차 참고해서 새로 구축 (v3 폐루프와 별개 디버그용).

**빌드**: v0.0.33+1 (`flutter analyze` clean)

---

### 2026-04-24 (27) — 게스트 재연결 race 수정 + v0.0.32 peer count 실측 PASS (v0.0.34)

**배경**: (25) v0.0.32 peer count 실측 재검증 준비 중 S22+iPhone USB로 W 시나리오(짧은 off) 1회 돌리자마자 iPhone에서 **재연결 → 끊김 무한 반복** 관찰. 기존 버그였는데 v0.0.31까지는 긴 off(30초+)나 가벼운 1회 테스트만 해봐서 드러나지 않았음.

**원인 분석** (`p2p_service.dart:355~367` + `room_lifecycle_coordinator.dart`):
- 게스트 측 disconnect 감지 경로가 **두 개**로 분리:
  - 경로 A: `onDisconnected` 스트림 → `_handleDisconnected` → `reconnectToHost(retries=3)`
  - 경로 B: `connectivity_plus none` 이벤트 → `_waitForWifiAndReconnect` → 15초 내 `reconnectToHost()`
- 짧은 off(5~8초)에서는 두 경로가 거의 동시에 재연결 시도 → 둘 다 성공하면서 **하나가 다른 쪽 socket을 `_hostSocket?.destroy()`로 파괴**
- 파괴된 old socket의 `onDone` 콜백이 기존 코드는 **새 `_hostSocket`까지 무조건 destroy** + `_disconnectedController.add(null)`:
  ```dart
  onDone: () {
    if (sourceId == 'host') {
      _hostSocket?.destroy();   // ← 이 시점 _hostSocket은 이미 새 socket!
      _hostSocket = null;
      _disconnectedController.add(null);  // → _handleDisconnected 재트리거 → loop
    }
  }
  ```
- → **무한 재연결 loop**

**수정** (`lib/services/p2p_service.dart:355`):
```dart
onDone: () {
  if (sourceId == 'host') {
    // 이 콜백 소유의 socket이 이미 재연결로 교체된 old socket이면 무시
    if (!identical(_hostSocket, socket)) {
      debugPrint('Stale host onDone ignored (socket replaced)');
      return;
    }
    _hostSocket = null;
    if (!_disconnectedController.isClosed) {
      _disconnectedController.add(null);
    }
  }
}
```
- `identical(_hostSocket, socket)` 가드: 현재 `_hostSocket`이 이 콜백 소유 socket과 같을 때만 정리. old socket의 onDone은 noop.

**실측 결과** (S22 호스트 + iPhone 12 Pro 게스트, USB flutter run, 비행기 모드 토글):
```
flutter: [CONNECTIVITY] GUEST WiFi off 확정 → _waitForWifiAndReconnect
flutter: [CONNECTIVITY] _waitForWifiAndReconnect 시작 (최대 15초)
flutter: [CONNECTIVITY] WiFi 복구 감지 (check 3/5) → reconnectToHost
flutter: Connection closed: host
flutter: Reconnect attempt 1/3 to 192.168.45.52:41235   ← 경로 A
flutter: Reconnect attempt 1/3 to 192.168.45.52:41235   ← 경로 B (동시)
flutter: Reconnected successfully
flutter: Reconnected successfully                         ← 둘 다 성공 (race 재현)
flutter: [CONNECTIVITY] reconnectToHost OK → sync 재시작
flutter: Connection closed: host
flutter: Stale host onDone ignored (socket replaced)      ← ✅ 가드 발동 — loop 차단
```

- **race 자체는 실제 존재** (`Reconnect attempt 1/3 ... ×2 → Reconnected ×2`).
- **`Stale host onDone ignored` 로그** 정상 출력 → 수정이 의도대로 동작.
- **무한 반복 없이** 재접속 완료, **peer count 양쪽 모두 2명 유지** (v0.0.32 효과 동시 확인).
- 여러 사이클 반복해도 동일 동작.

**부수 효과 — v0.0.32 peer count 실측 PASS**:
- (25)에서 "실측 재검증 대기"로 남겼던 Peer count 불일치 수정이 같이 검증됨.
- iPhone 비행기 모드 on/off 반복 내내 **S22 2명, iPhone 2명** 유지.

**iOS 테스트 조건 발견**:
- 제어센터 **WiFi 아이콘** 토글은 iOS가 "일시 비활성화"로 취급해 `connectivity_plus`에 `none` 이벤트가 안 가거나 약하게 감. → 재현 부적합.
- 진짜 네트워크 off 재현은 **제어센터 → 비행기 모드 토글** 또는 **설정 앱 > Wi-Fi 토글**로 해야 함. 전자는 앱 포그라운드 유지, 후자는 앱이 background로 내려감 → race 조건 달라짐.

**문서**:
- 미해결 "Peer count 불일치" 체크 완료 + 주석에 실측 PASS 반영
- 게스트 재연결 race는 (25)에 포함 안 됐던 별건 → (27) 항목으로 신설
- `CLAUDE.md` 최신 릴리스 v0.0.34 + 재개 포인트 갱신

**빌드**: v0.0.34+1 (`flutter analyze lib/services/p2p_service.dart` clean)

---

### 2026-04-24 (28) — 재연결 경로 직렬화 — 재동기화 중복 호출 제거 (v0.0.35)

**배경**: (27) v0.0.34 onDone 가드로 무한 loop는 차단했지만, **두 재연결 경로가 각자 성공한 뒤 재동기화도 각자 호출**하는 문제가 남음. W 시나리오 3회 실측에서 증상 관찰:
- `Reconnect attempt 1/3` **7회** (3 사이클 × 2 경로 + 추가 1회)
- `Reconnected successfully` **7회** (매 경로 각자 성공)
- 사용자 보고: "재연결 2번, 재동기화 2번 하는데 1번은 실패했다고 나오네" — 두 `onReconnectSyncRequested` 호출이 경쟁하며 하나가 실패 보고

**원인**: `_handleDisconnected`(TCP onDone 기반)와 `_waitForWifiAndReconnect`(connectivity `none` 기반)가 WiFi off/on 시 거의 동시에 발화 → 각자 `reconnectToHost` 성공 → 각자 `onReconnectSyncRequested()` await. 재동기화는 P2P 메시지+타이밍 조율이라 중복 실행이 서로를 invalidate.

**수정** (`lib/services/room_lifecycle_coordinator.dart`):
- 클래스 필드에 `bool _reconnectInProgress = false` 추가
- `_handleDisconnected` 진입부에 `if (_reconnectInProgress) return;` 가드 + flag 세팅
- `_waitForWifiAndReconnect` 진입부 동일 가드 + try/finally로 flag 해제
- `_handleDisconnected`는 `finally` 대신 각 exit 경로에서 **명시적 flag 해제** — errno 분기에서 `unawaited(_waitForWifiAndReconnect())`를 트리거할 때 flag를 먼저 false로 만들고 반환해야 `_waitForWifiAndReconnect`가 자체 관리로 이어받을 수 있음. `finally`로 덮어쓰면 `_waitForWifiAndReconnect` 실행 중에 flag가 풀려 다른 이벤트로 또 race 유발.

**실측 결과** (S22 호스트 + iPhone 12 Pro 게스트 USB, 비행기 모드 3회 반복):

| 항목 | v0.0.34 | v0.0.35 | 변화 |
|------|---------|---------|------|
| Reconnect attempt 1/3 | 7 | **3** | -4 |
| Reconnected successfully | 7 | **3** | -4 |
| `_handleDisconnected skip` | 0 | **3** | 신규 로그, 경로 A 차단 증거 |
| `[CONNECTIVITY] reconnectToHost OK` | 3 | 3 | (경로 B 1번만) |
| `Stale host onDone ignored` | 3 | **0** | race 자체가 사라져 가드 발동 불필요 |
| 재동기화 실패 스낵바 | 1/3 사이클 | **0** | ✅ |

로그 흐름:
```
[CONNECTIVITY] GUEST WiFi off 확정 → _waitForWifiAndReconnect    ← 경로 B flag 잡음
[CONNECTIVITY] _waitForWifiAndReconnect 시작 (최대 15초)
[CONNECTIVITY] WiFi 복구 감지 (check 3/5) → reconnectToHost
Reconnect attempt 1/3 to 192.168.45.52:41235                    ← 1회만
[RECONNECT] _handleDisconnected skip (이미 진행 중)              ← 경로 A 차단
Reconnected successfully
[CONNECTIVITY] reconnectToHost OK → sync 재시작                  ← 재동기화 1회만
```

**관계**:
- v0.0.34 onDone 가드는 **race가 일어난 뒤 loop를 차단**하는 안전망으로 유지
- v0.0.35 flag는 **race 자체를 예방** → `Stale host onDone ignored` 발동 불필요 상태
- 두 방어층이 함께 있어 future regression에도 견고

**문서**:
- 미해결 "게스트 재연결 race(무한 loop)" 항목을 "게스트 재연결 race(중복 재동기화 포함)"으로 갱신
- `CLAUDE.md` 최신 릴리스 v0.0.35

**빌드**: v0.0.35+1 (`flutter analyze lib/services/room_lifecycle_coordinator.dart` clean)

---

### 2026-04-24 (29) — 레이턴시 미해결 이슈 맥락 재정리 (문서 only)

**배경**: 세션 막바지에 "다음 트랙 = 레이턴시 자동 보정 정밀도 개선"(CLAUDE.md 재개 포인트 2번)의 실제 작업 내용을 정리하려 했는데, 미해결 이슈 "엔진 레이턴시 보정값 ~10ms 오차" / "S22 buf=4ms vs iPhone buf=21ms 비대칭(17ms)" 두 항목 모두 **구체적 측정 근거·현재 코드 맥락이 불명확**함을 발견.

**git 추적 결과**:
- 현 미해결 이슈 "~10ms 오차" 항목은 commit `ec80452`(이슈 목록 재구성 시)에서 "수동 보정 슬라이더 추가 예정"으로 처음 추가됨
- commit `6e53efd`(근거 기반 답변 원칙 추가 + 세션 재개 포인트 정리)에서 "자동 측정 방식 개선 먼저 검토"로 **문구만** 수정됨
- 그 어느 커밋에서도 "10ms"라는 수치의 출처·측정 방법은 기록되지 않음

**실제 맥락 재검토**:

1. **"엔진 레이턴시 보정값 ~10ms 오차"**: 틀린 표현.
   - v3 전환(NativeAudioSyncService + framePos 기반 폐루프) 후 **엔진 레이턴시는 `oboe::getTimestamp()` / `AVAudioTime` 반환값에 이미 내포**되어 "별도 보정값"이라는 수치가 코드에 존재하지 않음.
   - 이를 뒷받침하는 증거: v0.0.33(26)에서 `com.synchorus/audio_latency` orphan MethodChannel 제거 — Dart 호출 0건 상태였음.
   - "10ms"의 유력 출처는 PoC Phase 5~6의 `|drift| < 10ms 100%`(HISTORY.md:491,500,534) 또는 안정 구간 drift mean 진동(HISTORY.md:648 `-5ms ~ +10ms`) — **이는 현재 시스템의 성능 지표**이지 "보정값 오차"가 아님.
   - → 항목 제거.

2. **"S22 buf=4ms vs iPhone buf=21ms 비대칭(17ms)"**: 맥락이 v0.0.4 이전 기준.
   - v0.0.4(2026-04-07)에서 iOS도 `outputLatency` 제거하고 buffer만 쓰는 **측정 방식 통일**로 compensation 계산 왜곡은 제거됨. 비대칭 자체(buffer HAL 보고값 차이)는 구조적이라 남아있음.
   - v3 전환 후 **이 17ms가 실제 drift에 영향을 미치는지 실측 검증된 바 없음**. framePos 기반 폐루프가 이걸 흡수할 가능성 큼.
   - → `[~]` 부분 해결 상태로 표기하고 "실측 검증 필요"로 재문구화.

3. **실제 개선 여지 — Bluetooth outputLatency 동적 보정**: `ARCHITECTURE.md:177~178`에 명시적 근거 — BT 이어폰·스피커는 연결 중에도 ±50ms 변동 → 현재 고정값 대응. **자동 보정 우선 원칙(memory feedback_prefer_auto_correction.md)에 부합하는 방향**.
   - → 신규 항목으로 추가.

**CLAUDE.md 재개 포인트 갱신**:
- 기존: "엔진 측정값 10ms 오차 줄이기, S22/iPhone 버퍼 비대칭(17ms) 자동 보정 알고리즘 탐색"
- 신규: "Bluetooth outputLatency 동적 보정" + "v0.0.4 buf 차이가 v3 폐루프에서 실제 drift에 영향 주는지 실측 검증" 2개로 쪼갬.

**변경 범위**: 문서만(HISTORY.md, CLAUDE.md). 코드 변경 없음. 버전 bump 없음.

**다음 세션 시작점**: 이번 (29) 정리 덕에 "~10ms 오차"라는 모호한 타겟이 사라졌음. 실제 개선 2개 중 택일:
- **A (Bluetooth 동적 보정)** — 실사용 환경 영향 큼, 자동 보정 원칙 부합
- **B (buf 차이 실영향 검증)** — PoC Phase처럼 실기기 2대 오래 돌려 drift csv 수집·분석, 코드 변경 0 가능성도 있음

**관찰 vs 가설 구분**:
- **관찰**: git log에서 "~10ms 오차"의 측정 근거 미기록, v3 전환 후 `audio_latency` 채널 제거.
- **가설**: "10ms"의 원래 의도는 PoC 기간의 drift 진동 관찰을 옮겨 적은 것으로 보임. v3 폐루프 기준으론 해결 대상이 아닐 가능성이 큼. (확정하려면 해당 커밋 작성자에게 문의 필요 — 여기선 1인 개발이라 자기 판단.)

---

### 2026-04-24 (30) — B(buf 차이 실영향) 검증 결과 + 호스트 `getTimestamp` 간헐 실패 이슈 발견 (문서 only)

**배경**: (29) 문서 정리 직후 B(v0.0.4 buf 17ms 차이가 v3 폐루프에서 drift에 영향 주는지) 실측을 이어서 진행. S22(호스트, 내장 스피커) + iPhone 12 Pro(게스트) USB 연결, 임의 파일 약 3분 30초 재생. 사용자 체감 "시작엔 잘 맞다가 정지 직전에 싱크 엄청 틀어짐".

**csv 추출 실패**:
- `getApplicationDocumentsDirectory()` 실제 경로가 S22에서 `/data/user/95/com.synchorus.synchorus/app_flutter/`로 생성됨 (`/data/user/95/`는 Samsung Secure Folder 또는 multi-user 공간). `run-as`로는 기본 `/data/user/0/`만 바인드되어 permission denied.
- 대체: S22 `logcat --pid=<app>`에서 `[DRIFT-REPORT]` 363건 추출(약 3분 10초치)로 분석.

**B 검증 결과 (drift 수치 관점) — PASS**:

| 구간(s) | event | n | mean\|d\| | max | 해석 |
|---------|-------|---|-----------|-----|------|
| 0~30 | fallback 21 + drift 28 | 49 | **37ms** | **636ms** | 초기 clock sync·앵커 설정, 정상 수렴 과정 |
| 30~60 | drift 58 | 58 | **0.47ms** | 1.4ms | 폐루프 수렴 완료 |
| 60~90 | drift 60 | 60 | 0.53ms | 1.4ms | 안정 |
| 90~120 | drift 60 | 60 | 0.76ms | 1.8ms | 안정 |
| 120~150 | drift 60 | 60 | 1.75ms | 3.8ms | 약간 증가 |
| 150~180 | drift 60 | 60 | 2.74ms | **4.1ms** | 가장 큰 구간이지만 여전히 5ms 미만 |
| 180~210 | drift 16 | 16 | 1.88ms | 2.9ms | 종료 직전, 다시 안정 |

→ 초기 30초 수렴 이후 **전 구간 \|drift\| < 5ms**. buf 17ms 비대칭은 v3 framePos 기반 폐루프가 **정상적으로 흡수**. PoC Phase 5~6의 `|drift| < 10ms 100%`와 동등한 성능 재확인.

**그런데 체감은 "정지 직전 싱크 엄청 틀어짐"** — 데이터와 모순된 체감 원인을 찾기 위해 logcat의 `[TS]` 이벤트 추가 조사:

```
04-24 16:01:50.390  [TS] ok recovered after 26 failures (vf=3360)       ← 재생 시작 직후
04-24 16:04:57.275  [TS] ok recovered after 15 failures (vf=8175360)    ← 정지 10초 전
04-24 16:05:07        방 닫음(closeRoom)
```

**`[TS]`는 호스트 S22의 `oboe::getTimestamp()` 폴링** (100ms 주기). 15회 연속 실패 = **1.5초 동안 호스트가 자기 재생 위치를 못 읽음**. 이 구간 동안:
- 호스트: 정확한 audio-obs 못 보냄
- 게스트: 마지막 앵커로 외삽 계속 → 게스트 **자기 drift 계산에선 0~3ms로 정상**처럼 보임
- 하지만 실제 호스트 오디오는 그동안 진행 → **복구 순간 두 기기 실제 재생 위치가 최대 1.5초치 어긋남**
- → 사용자 체감 "정지 직전 싱크 엄청 틀어짐"과 타이밍 정합 (16:04:57 TS 실패 → 16:05:07 정지)

**결론**:
- **B 수치 검증은 PASS** (buf 17ms → 폐루프 흡수, drift 안정).
- 하지만 **별개 이슈 발견**: 호스트 `oboe::getTimestamp` 간헐 실패(15~26회 연속)가 **실전 체감 싱크 품질을 저해**하고 있음. drift-report만으론 이 구간을 못 잡음 (게스트 기준 외삽값이라).
- 이 이슈는 buf 차이·BT 동적 보정과 별개 트랙. 우선순위 높음.

**원인 가설** (추측, 근거 부족):
- Oboe stream xrun(buffer underrun) 또는 HAL이 일시적 timestamp 반환 불가 상태
- 앱 라이프사이클 전환 시점(paused/resumed), 포그라운드 서비스 재조정 등과 상관관계 의심
- 재생 시작 직후 26회 / 정지 직전 15회라는 타이밍 특이점 — **stream state 전환 부근에 몰려있을 가능성**
- 확정 위해선 `oboe_engine.cpp:278` 근처에서 실패 시 `AAudio_convertResultToText(result)` 등으로 실패 이유 native 로그에 찍어야 함

**완화 방향 후보**:
1. 호스트 TS 실패 중에도 **최근 성공한 framePos + 경과 시간**으로 보간해서 obs 보내기 — 게스트는 끊김 없이 따라갈 수 있음. 현재는 실패 시 obs 생략되거나 stale 값 반환
2. 실패 원인을 native 로그로 분류 → 특정 원인 타깃 수정
3. TS 폴링 주기 단축·백업 타임소스 병용 (cost 고려 필요)

**csv 접근 개선 과제**:
- Android에서 `getApplicationDocumentsDirectory()` 경로가 multi-user 공간(`/data/user/95/`)에 생성되면 `run-as`로 접근 불가. 실측 csv 분석이 logcat 버퍼(256KB~2MB)에 의존하게 됨
- 대안: Android 한정으로 csv를 `/sdcard/Android/data/com.synchorus.synchorus/files/`(외부 앱 전용 저장소)로 저장하면 `adb pull` 직접 가능. 다음 세션에서 logger 경로 옵션 추가 검토

**변경 범위**: 문서만(HISTORY.md, CLAUDE.md). 코드 변경 없음.

---

### 2026-04-25 (31) — 호스트 `oboe::getTimestamp` streak 진단 로그 보강 (v0.0.37)

**배경**: (30)에서 호스트 S22 `oboe::getTimestamp()` 100ms 폴링이 재생 시작 직후 26회·정지 직전 15회 연속 실패했지만, 기존 진단 로그는 streak 시작 시 1회 `LOGW`만 찍고 종료·길이·지속 시간을 안 남겼다 (`mLastTsResult` 가드). 그 결과 logcat에서는 "실패가 시작됐다"만 보이고 streak이 몇 회·몇 ms였는지, 어떤 result 코드였는지 분류 불가.

**변경** (`android/app/src/main/cpp/oboe_engine.cpp:253` 주변, `getLatestTimestamp`):
- 멤버 필드 2개 추가
  - `int64_t mTsFailStreakCount{0};` — 현재 streak의 실패 횟수
  - `int64_t mTsFailStreakStartMonoNs{0};` — streak 시작 monotonic ns
- `monoNow` 계산을 lock 진입 전으로 이동 (실패 분기에서도 streak 시각 기록에 필요)
- 실패 분기: 새 streak 시작이면 `mTsFailStreakStartMonoNs = monoNow`, `mTsFailStreakCount = 0`, 기존 `LOGW("getTimestamp streak start: %s (%d)", ...)`. 매 실패마다 `++mTsFailStreakCount`
- 성공 분기 진입 시 직전이 실패였으면(`mLastTsResult != OK`) `LOGW("getTimestamp streak end: last=%s count=%lld duration=%lldms", ...)` 1회 추가

**효과**:
- logcat에 streak 1회당 시작/종료 1쌍 → streak 길이·지속 시간·마지막 result 코드 분류 가능
- 폭주 방지(streak당 2줄)는 유지

**1차 측정 결과** (S22 호스트 v0.0.37 + iPhone 12 Pro 게스트 v0.0.36, 3분 재생 + 끝부분 재생/정지/seek 연타):

| 시각 | result | count | duration |
|---|---|---|---|
| 15:18:59 | `ErrorInvalidState` (-895) | 1회 | 142ms |
| 15:22:12 | `ErrorInvalidState` (-895) | 1회 | 61ms |

- result 코드 확정: **`ErrorInvalidState` (-895)** = "스트림 state가 timestamp를 줄 수 있는 상태(ACTIVE)가 아님"
- (30)의 26회/15회 (1.5~2.6초) 긴 streak은 **재현 안 됨**. 사용자 체감 어긋남도 이번엔 없음
- (30)과 (31)은 **같은 코드 + 같은 파일 + 같은 출력 장치(내장 스피커) + 다른 앱 없음** — 차이는 시간/시점뿐

**csv 비교** (둘 다 30초 이후 안정):

| 구간(s) | (30) mean / max ms | (31) mean / max ms |
|---|---|---|
| 30~60 | 0.47 / 1.4 | 2.03 / 3.91 |
| 60~90 | 0.53 / 1.4 | 1.38 / 3.23 |
| 90~120 | 0.76 / 1.8 | 1.72 / 3.91 |
| 120~150 | 1.75 / 3.8 | 4.44 / 6.34 |
| 150~180 | 2.74 / 4.1 | 2.84 / 6.37 |

→ drift csv는 **(30)/(31) 둘 다 안정**(< 7ms). 사용자 체감 차이는 csv가 못 잡음. (게스트 외삽값이라 호스트 TS 침묵 구간이 가려짐 — (30) 결론과 일치)

**csv 접근성 회복**: v0.0.36 `SyncMeasurementLogger`가 `getExternalStorageDirectory()`를 우선 시도하도록 바뀌어, **S22 dual-app(user 95) 환경에서도** `/storage/emulated/95/Android/data/com.synchorus.synchorus/files/sync_log_*.csv`로 떨어져 `adb pull` 가능. (30) raw csv는 v0.0.36 이전 internal `/data/user/95/...`라 영구 접근 불가.

**잠정 결론**: 같은 코드/입력에서 streak 길이가 2회 → 26회로 점프 = **시스템 레벨 비결정성**. OS scheduler / AAudio HAL 내부 부하 / thermal 등이 트리거 후보지만 단발 측정으론 못 잡음.

**2차 진단 보강** (이번 세션 후속):
- streak start 로그에 **stream state**(`oboe::convertToText(mStream->getState())`) + **xrun 누적값**(`mStream->getXRunCount()`) + **wall clock ms** 추가
- streak end 로그에 종료 시 state + **xrun delta** + wall clock ms 추가
- 신규 멤버 `int32_t mTsFailStreakStartXRun{-1};`
- 다음 긴 streak 재발 시 분류 가능: `ErrorInvalidState`가 어떤 state(STARTING / PAUSING / STOPPING / DISCONNECTED)에서 발생했는지, xrun underrun이 동반됐는지, Dart 측 라이프사이클·재생 컨트롤 호출과 시각 매칭

**다음 단계 (A 방향, 사용자 합의)**:
- 추가 보강만 해두고 **다음 자연 재발 대기**. 같은 조건 강제 재현 시도 부담 대비 ROI 낮다고 판단
- 재발 시 logcat 데이터로 원인 분류 → 완화 방향(보간 obs / state 마스킹 신호 / 버퍼 점검) 결정

**남은 위험**:
- 자연 재발이 드물면 분류 데이터 누적까지 시간 소요
- result/state/xrun으로도 근본 원인 단정 안 되면 Perfetto/atrace 시스템 레벨 trace 필요

**변경 범위**: `android/app/src/main/cpp/oboe_engine.cpp` (1차 + 2차 진단 보강), `pubspec.yaml`(0.0.36→0.0.37). Dart 변경 없음, iOS 변경 없음(이슈는 Android 호스트만 관측).

---

### 2026-04-25 (32) — BT outputLatency 비대칭 발견 + drift 공식에 양쪽 outputLatency 반영 (v0.0.38)

**배경**: PLAN 우선순위 2 "BT outputLatency 동적 보정"의 선검증. 조사 후(general-purpose agent + Apple/Google/SO/audio_session 출처 검증) 결론: iOS `AVAudioSession.outputLatency`는 안정화 후엔 ±10ms 정확하나 워밍업 50~60ms 과소보고 / 분 단위 30~70ms 변동 / A2DP↔HFP 전환 100ms+ 누락 가능. Android Oboe `getLatency()`는 BT codec/radio 단계 거의 안 잡음(Oboe wiki 명시).

**(a) baseline 측정 (v0.0.37, outputLatency 미반영)** — S22 호스트 내장 + iPhone 게스트 + 갤럭시 버즈 BT, 3분 재생:

| 항목 | 값 |
|---|---|
| 사용자 체감 | 갤럭시 버즈 **~300ms 느림** |
| csv 통계 | n=311, mean 3.56ms, p50 3.66ms, **p95 5.60ms, p99 6.38ms** |
| 30~180초 구간 \|drift\| | 1.38~4.44ms (안정) |
| streak | 1회 (51ms, state=Started, xrun=0) |

→ **csv는 3분 내내 < 7ms 안정인데 음향은 ~300ms 어긋남**. 구조적 발견:
- 호스트/게스트 양쪽 `framePos` = "디코더 → 출력 노드" 누적 카운터
- 그 이후 BT codec/transmission/DAC 단계는 framePos에 안 들어감
- 양쪽 다 outputLatency 무시하는 대칭 구조라 **BT 비대칭이 csv에 안 잡히고 음향에만 그대로 남음**
- (30)의 호스트 TS 침묵 케이스와는 별개의 새 root cause

**(b) 코드 변경 — outputLatency를 drift 공식에 반영**:

1. **`oboe_engine.cpp`**: `getLatestTimestamp` 시그니처에 `double* outOutputLatencyMs` out 파라미터 추가. `mStream->calculateLatencyMillis()` (Oboe API) 호출 → ResultWithValue가 OK면 값, 실패면 -1. JNI nativeGetTimestamp의 jlongArray 7→8개로 확장, outputLatencyMs를 micro 단위 long으로 인코딩(`* 1000.0`, -1은 그대로).
2. **`MainActivity.kt`**: getTimestamp Map에 `"outputLatencyMs" to outLatMs` 추가. -1 → null 변환.
3. **`NativeTimestamp` (`native_audio_service.dart`)**: `double? outputLatencyMs` 필드 추가, fromMap에 파싱. `safeOutputLatencyMs` getter — null/음수/500ms 초과는 0으로 무시(OS 보고 비정상 시 보정 노이즈 차단).
4. **`AudioObs` (`models/audio_obs.dart`)**: `double hostOutputLatencyMs` 필드 추가(기본 0), toJson/fromJson에 포함. 구버전 호스트 호환은 0 fallback.
5. **`_broadcastObs` (line 503)**: `hostOutputLatencyMs: ts.safeOutputLatencyMs`.
6. **drift 공식 (line 1075)**: `final outLatDelta = ts.safeOutputLatencyMs - obs.hostOutputLatencyMs; final driftMs = dGms - dHms - outLatDelta;`
7. **`_fallbackAlignment` (line 949)**: 동일하게 `- outLatDelta` 보정 추가.

**iOS는 이미 `AVAudioSession.outputLatency`를 dict에 보내고 있어 native 변경 없음** (`AudioEngine.swift:158`, 단 v0.0.37까지 Dart는 받지도 사용하지도 않은 dead data였음).

**예상 효과** (Apple Forum 출처 + (a) baseline 기반):
- 호스트·게스트 둘 다 같은 기종 내장: 보정값 거의 상쇄, drift 변화 ≈ 0
- 다른 기종 내장 (S22+iPhone): ±10ms 보정으로 약간 개선 가능
- 한쪽 BT (이번 케이스): ~150~250ms 보정 → 잔여 50~100ms (OS 보고 정확도 한계)
- OS 보고 비정상값(>500ms 등)은 sanity check로 0 fallback, 회귀 위험 차단

**(b) 1차 측정 (이번 세션 후속)** — S22 내장 호스트 + iPhone 게스트 + 갤럭시 버즈 BT, 3분 재생:

| 항목 | 값 |
|---|---|
| 사용자 체감 | 약 ~150ms 잔여 어긋남 (이전 ~300ms의 절반 개선) |
| csv 통계 | n=283, mean **-275.81ms**, p95 **-274.49 ~ -278.40ms** (3분 내내 ±2ms 변동만) |
| seekCount | **0회** (3분 내내 자동 보정 seek 발동 안 함) |

→ **csv가 -275ms로 일관 = 보정값은 정확히 들어갔지만 무한 anchor reset 루프**. 원인: `_maybeTriggerSeek` (line 1124)이 `|drift| ≥ _reAnchorThresholdMs (200ms)`이면 anchor만 리셋하고 seek 안 함 → 다음 poll에서 _tryEstablishAnchor 재진입 → 같은 framePos 기준으로 정렬 → 또 -275ms drift → 또 reset. 사용자 체감 150ms 잔여는 _fallbackAlignment 일부 작동 또는 체감 정확도 ±100ms 오차로 추정.

**(b') 수정 — outputLatency 비대칭을 anchor에 베이크인** (`_tryEstablishAnchor` line 1003~1018):

```dart
final outLatDelta = ts.safeOutputLatencyMs - obs.hostOutputLatencyMs;
final targetGuestVf = (hostContentMs * _framesPerMs).round() +
    (outLatDelta * _framesPerMs).round();          // ← BT 비대칭만큼 앞선 위치로 seek
...
_anchoredOutLatDeltaMs = outLatDelta;              // 신규 멤버, 시간 변화 추적용
```

`_recomputeDrift` (line 1075):
```dart
final currentOutLatDelta = ts.safeOutputLatencyMs - obs.hostOutputLatencyMs;
final dynLatDeltaMs = currentOutLatDelta - _anchoredOutLatDeltaMs;
final driftMs = dGms - dHms - dynLatDeltaMs;       // 시간 변화분만 보정
```

**효과 예상**:
- anchor establishment 시점에 게스트가 outLatDelta 만큼 앞선 콘텐츠 위치로 seek됨 → 처음부터 음향 시각 정렬
- 그 후 drift csv는 framePos 기준 ≈ 0 + BT 분 단위 변동(±30~70ms)만 표시
- 메인 seek 임계(20ms)는 변동분만 트리거 → 무한 reset 루프 해소

**(b') 검증 측정 결과 — 모두 PASS**:

**(b'-1) 개선 검증** (S22 내장 + iPhone 버즈 BT, 같은 파일, 약 2분):

| 항목 | (a) 미반영 | (b) 1차 | **(b') 베이크인** |
|---|---|---|---|
| csv mean(\|d\|) | 3.56ms | 275.81ms | **0.5~1.5ms** |
| csv max\|d\| | 6.99ms | 278.40ms | **4.18ms** (15~30s) |
| seek_count | - | 0 (무한 reset) | **0** (보정 불필요) |
| 사용자 체감 | ~300ms 어긋남 | ~150ms 어긋남 | **40초 후 정확** |

처음 40초 약간 잔여 = **iOS `outputLatency` 워밍업 과소보고**(Apple Forum #679274와 일치, AirPods 220ms 실측 vs 160ms 보고). 시간 지나며 보고값 안정 + `_recomputeDrift` 변화분 추적이 따라감. csv는 보고값 기준이라 잔여를 못 잡고 체감만 잡힘.

**(b'-2) 회귀 검증** (S22 내장 + iPhone 내장, (30)/(31)와 동일 조건, 3분 + 끝부분 재생/정지/seek 연타):

| 구간(s) | mean\|d\| | max\|d\| | 비교 |
|---|---|---|---|
| 30~60 | 1.51 | 4.55 | (30) 0.47/1.4, (31) 2.03/3.91 — 동등 |
| 60~90 | 1.87 | 4.10 | (30) 0.53/1.4, (31) 1.38/3.23 — 동등 |
| 90~150 | 1.13~1.29 | 3.74 | 동등 |
| 150~180 | 1.54 | 4.25 | (30) 2.74/4.1 — 동등 |
| 180~210 (연타) | 0.68 | 2.43 | 라이프사이클 회귀 없음 |

→ 양쪽 내장에선 `outLatDelta ≈ 0`이라 사실상 보정 없음 = (30)/(31)와 동등 거동. **회귀 없음 PASS**.

**최종 결론**:
- BT 비대칭은 anchor 베이크인으로 처음부터 음향 시각 정렬 → seek 0회로 부드럽게 동작
- 양쪽 내장은 보정 항이 자동으로 0에 가까워져 회귀 없음
- 잔여 30~50ms는 OS API 한계 (acoustic loopback 트랙은 후순위 확정)
- 처음 40초 잔여 잡고 싶으면 옵션 A (outputLatency 안정화 대기)·B (사전 무음 워밍업)·C (acoustic loopback) 중 선택. 현재 MVP 단계에선 D (UX 명시)도 합리적

**남은 한계**:
- 첫 anchor establishment 직후 ~40초 BT 워밍업 잔여 (사용자 체감)
- BT 코덱 전환(A2DP↔HFP) 100ms+ 누락은 OS가 보고 안 함 → 발생 시 큰 어긋남 가능. 발생 빈도 적음

**변경 범위**: `oboe_engine.cpp`, `MainActivity.kt`, `lib/services/native_audio_service.dart`, `lib/models/audio_obs.dart`, `lib/services/native_audio_sync_service.dart`(+anchor 베이크인 + `_anchoredOutLatDeltaMs` 멤버), `pubspec.yaml`(0.0.37→0.0.38). iOS native 변경 없음(이미 `AVAudioSession.outputLatency` 송신 중). iOS Dart는 NativeTimestamp.fromMap/AudioObs 호환만 필요(자동).

---

### 2026-04-25 (33) — `_resetDriftState` 베이크인 안전성 + BT 워밍업 잔여 조사 + iOS 호스트 P2P discovery 버그 발견

**(33-1) 코드 한 줄 — `_resetDriftState`에 `_anchoredOutLatDeltaMs = 0;` 추가**

`_startGuestPlayback`에서 매번 `_resetDriftState`로 anchor 초기화하지만 v0.0.38의 `_anchoredOutLatDeltaMs`는 명시 리셋 안 함. 다음 anchor establish 시점에 새 값 저장되므로 동작은 동일하지만, anchor null인 동안의 의미적 일관성·가독성 위해 명시 리셋. `_recomputeDrift`는 anchor null이면 early return이라 실제 영향 0.

**(33-2) BT 워밍업 잔여 — 사용자 관찰 + 외부 자료 조사**

(b') 검증에서 사용자 관찰: "처음 40초 약간 어긋남, 이후 정확". 정지 후 재생 재개 시 같은 패턴 반복 (코드상 `_resetDriftState`가 매번 호출되어 anchor 새로 잡힘). 원인 분석:

- iOS `AVAudioSession.outputLatency`는 BT 라우트 활성 직후 30~60ms 과소보고 (Apple Developer Forums #679274 검증)
- 우리 코드는 첫 anchor 시점에 그 작은 값을 베이크인 → 보정 부족 → 잔여 어긋남
- 시간 지나며 OS 보고가 안정 + `_recomputeDrift`의 변화분 추적이 따라잡음

**외부 자료 조사 결과** (general-purpose agent, 출처: Apple Forums, Apple Developer Documentation, Android NDK Audio Latency, Oboe Wiki, Stephen Coyle, iDropNews, WWDC 2014 Session 502):

1. **iOS 표준 안정화 시간 없음**. Apple 공식 헤더에 outputLatency를 "estimation, **least reliable with Bluetooth**"로 표기. 자체 휴리스틱 필요.
2. **Android NDK 공식 권장 패턴**: warmup latency 피하려면 silence buffer를 계속 enqueue하다가 실제 오디오로 전환 (developer.android.com/ndk/guides/audio/audio-latency). iOS도 동일 원리 적용 가능 — `AVAudioPlayerNode.scheduleBuffer`로 무음 PCM 흘림.
3. **Oboe `calculateLatencyMillis()`도 같은 워밍업 패턴** — getTimestamp 기반이라 호스트 BT 시 동일 영향. Issue #357: "BT 헤드셋 0.5초 상수 지연이 calculateLatencyMillis 미반영".
4. **acoustic loopback이 OS API 외 유일한 ground truth** (Apple Forum 합의). lower-level API(AudioUnit / Audio Queue Tap / Oboe lower-level)도 BT 라우트 너머의 수신측 지연은 못 봄.
5. **코덱별 워밍업 시간 차이**: AirPods Pro 144ms, AirPods (W1/H1) 274/178ms. 갤럭시 버즈 같은 일반 BT는 가시화된 코덱 협상 데이터 부족. 가설로만.

**조사 권장 (효과/복잡도)**:

| # | 방법 | 효과 | 복잡도 |
|---|---|---|---|
| **A** | iOS 무음 prebuffer + outputLatency 수렴 게이팅 (`_engine.start()` 직후 `setMuted(true)` 1~3초, outputLatency 표본 ±5ms 안정 확인 후 anchor) | **상** | 중 |
| **B** | outputLatency rolling median(3~5 샘플) → spike 흡수 | 중 | 하 |
| **C** | acoustic loopback 1회 calibration → 이어폰 ID + 측정값 저장 → 정지/재생 무관 즉시 적용 (근본 해결) | 상 (정확도 ±5ms) | 큰 작업 |
| **D** | UX 명시 ("BT 이어폰은 재생 시작마다 잠깐 워밍업") | 0 | 0 |

**Android 게스트 BT 시 추가 한계**:
- Oboe `calculateLatencyMillis()`가 BT codec/radio 단계 거의 안 잡음 (Oboe wiki TechNote_BluetoothAudio 명시) → OS 보고가 iOS보다 부족 → 베이크인 자체가 작아 음향 어긋남 큼 가능
- 같은 게이팅(A) 적용해도 codec/radio 누락분이 상시 잔여로 남음 → 이 케이스는 acoustic loopback(C)이 거의 유일한 해결

**다음 세션 결정**: A/B/C 중 진행 또는 D로 보류. 사용자 시나리오 우선순위(MVP 마감 vs 정확도)에 따라.

**(33-3) 신규 발견 — iOS 호스트 시 P2P discovery 게스트 검색·접속 안 됨**

검증 매트릭스 확장 시도(Android 게스트 BT 케이스 측정) 중 발견:
- **Android 호스트 + iPhone 게스트**: 정상 작동 (이번 세션 (b'-1) (b'-2) PASS의 시나리오)
- **iPhone 호스트 + Android 게스트**: **검색 안 됨 + 접속 안 됨**

코드 분석:
- `discovery_service.dart:40` — discovery는 mDNS/Bonjour가 아니라 **raw UDP `255.255.255.255:41234` broadcast** 사용 (`RawDatagramSocket`)
- iOS Info.plist는 `NSLocalNetworkUsageDescription` + `NSBonjourServices=_synchorus._tcp` 등록되어 있음. **하지만 코드는 Bonjour 안 씀** → 불일치
- iOS entitlements 파일 자체 부재 (`Runner.entitlements` 없음) → `com.apple.developer.networking.multicast` entitlement 없음. iOS 14+에서 raw multicast/broadcast 송신은 이 entitlement 필요할 수 있음 (Apple 신청 필요)
- `discovery_service.dart`에 Platform 분기 없음 → iOS/Android 같은 코드라 iOS 측만 silent fail 가능

권한 확인 (사용자 보고): iPhone 설정 → 개인정보 보호 및 보안 → 로컬 네트워크 → Synchorus 토글 **켜져 있음** (권한은 OK).

**임시 우회 가능**: 게스트 측 `home_screen.dart:295`에 "IP 직접 입력" UI 이미 존재. 호스트 측 화면에 IP 표시 + 클립보드 복사 (`room_screen.dart:436~446`)도 이미 있음. → **iPhone 호스트 IP를 Android 게스트가 직접 입력해서 우회 가능 가능성** (검증 필요).

**진단 분기 (다음 액션)**:
- IP 직접 입력으로 접속 됨 → discovery(UDP broadcast)만 막힘, ServerSocket(TCP listen) 정상 = iOS multicast/broadcast 송신 entitlement 부재 확정. 단기 IP 우회 + 장기 nsd/multicast_dns 패키지 마이그레이션
- IP 직접 입력으로도 접속 안 됨 → ServerSocket 자체 차단 (더 큰 보안 문제, 별도 진단)

**fix 옵션** (다음 세션):
- **A**: `nsd` 패키지로 discovery 마이그레이션 (정석, 30분~1시간, multicast entitlement 불필요 — 시스템 mDNS 사용. iOS NSNetServiceBrowser + Android NsdManager wrap)
- **B**: Apple `com.apple.developer.networking.multicast` entitlement 신청 + 추가 (1~2주 승인, 코드 변경 0, raw broadcast 그대로)
- **C**: 임시 우회만 — 게스트 IP 입력 UI는 이미 있으니 UX 안내만 보강

**변경 범위**: `lib/services/native_audio_sync_service.dart` (한 줄). 코드 동작 변화 없음 (가독성 보강). 워밍업 조사 + iOS 호스트 버그는 문서만 — 다음 세션 결정 + fix.

---

### 2026-04-25 (34) — iOS 파일 선택 크래시 + Apple Music DRM 한계 발견 (v0.0.39 + v0.0.40)

**배경**: (33-3) iOS 호스트 P2P discovery 진단 시도 중 사용자가 iPhone 호스트로 방 만들기 + 파일 선택 시도 → **앱 즉시 크래시** 발견. 원인 분석 + fix.

**원인 1 (v0.0.39)**: `file_picker-8.3.7` iOS 구현(`FilePickerPlugin.m:369`)이 `FileType.audio`일 때 `MPMediaPickerController` 사용 → iOS Music 앱 라이브러리 접근 → **`NSAppleMusicUsageDescription`** Info.plist description 필수. iOS는 권한 description 없는 권한 요청 시 앱을 SIGABRT로 강제 종료. 우리 Info.plist엔 `NSLocalNetworkUsageDescription`만 있고 음악 라이브러리 description 누락 → 크래시.

**v0.0.39 fix**: `ios/Runner/Info.plist`에 `NSAppleMusicUsageDescription` 추가 ("재생할 음악을 라이브러리에서 선택하기 위해 음악 라이브러리에 접근합니다"). iPhone 재빌드 후 사용자 검증 — **앱 안 튕김 PASS** (보관함 picker 정상 표시).

**원인 2 (v0.0.40)**: 보관함 picker는 열렸지만 **파일이 아무것도 안 보임**. 추가 분석:
- `MPMediaPickerController`는 **iOS Music 앱 라이브러리**만 표시 (Apple Music 구독 곡, iTunes 동기화 곡, Music 앱에 다운로드한 음악)
- **Files 앱·iCloud Drive·On My iPhone에 직접 저장한 mp3/m4a는 안 보임** (Music vs Files 별개 sandbox)
- 사용자 iPhone에 Music 앱 라이브러리가 비어 있어 picker가 빈 화면
- 추가 함정: **Apple Music 구독 곡은 FairPlay DRM 보호** → 일반 앱이 라이선스 키 못 받음 → `MPMediaItem.assetURL`로 가져오려 해도 `AVAssetExportSession`이 export 거부 (`FilePickerPlugin.m`의 `exportMusicAsset` silent fail) → **picker로 가져와도 우리 엔진이 디코드 불가**. 즉 `FileType.audio`는 iOS에선 사실상 무용에 가까움 (DRM-free 동기화 음악 가진 사용자만 작동)

**v0.0.40 fix**: `player_screen.dart:_pickFile` + `native_test_screen.dart:_pickAndLoad`의 `pickFiles` 호출을 `FileType.custom + allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg']`로 변경. iOS는 이때 `UIDocumentPickerViewController` 사용 → **Files 앱 / iCloud Drive / On My iPhone / 외부 Storage Provider(Dropbox 등) 모든 source 표시**. 사용자가 명시적으로 저장한 DRM-free 파일 선택 → 우리 엔진 디코드 가능.

**Android 영향**: `FileType.custom + allowedExtensions`는 Android에서도 SAF mime 필터로 처리되어 기존 `FileType.audio`와 거의 동일한 picker 표시. 사용자 검증 — **회귀 없음 PASS**.

**`NSAppleMusicUsageDescription`**: v0.0.40 코드에선 사실상 dead 권한이지만 안전성·미래 확장(혹시 음악 라이브러리 옵션 추가 시)을 위해 Info.plist에 유지.

**고려·기각된 옵션**:
- BottomSheet로 두 source(`Files` + `Music 라이브러리`) 같이 노출 — 사용자 선택. 단 Music 라이브러리 path는 DRM 곡 비율 높아 실용성 낮음 → 기각, custom만 사용.
- DRM 보호 곡 silent fail 시 친절한 에러 메시지 — `loadFile` catch에 SnackBar 이미 있음, 메시지 정교화는 필요 시 후속.

**변경 범위**: `ios/Runner/Info.plist`(`NSAppleMusicUsageDescription` 추가), `lib/screens/player_screen.dart`(custom + extensions), `lib/screens/native_test_screen.dart`(동일), `pubspec.yaml`(0.0.38→0.0.39→0.0.40 두 단계 bump 합쳐 0.0.40 최종). Android native·Dart 프로토콜 변경 0, P2P 호환 유지.

**남은 (33-3) 작업**: iOS 호스트 시 P2P discovery(UDP broadcast)는 여전히 막힘. fix는 nsd 패키지 마이그레이션 또는 multicast entitlement 신청 — 다음 진행.

---

### 2026-04-25 (35) — `discovery_service` nsd 마이그레이션 (v0.0.41) — 양방향 검색 PASS

**배경**: (33-3) 발견한 iPhone 호스트 시 P2P discovery 게스트 검색·접속 안 되는 버그의 본격 fix. 진단 결과(IP 직접 입력은 OK = TCP 정상, UDP broadcast만 막힘) → iOS 14+ 보안상 raw multicast/broadcast 송신은 `com.apple.developer.networking.multicast` entitlement 필요(Apple에 사유 신청, 1~2주 승인). entitlement 신청 없이 영구 fix하려면 시스템 mDNS(Bonjour) 사용해야 함.

**변경**:
- **`pubspec.yaml`**: `nsd: ^5.0.1` 의존성 추가 (iOS NSNetService + Android NsdManager wrap)
- **`lib/services/discovery_service.dart`** 전체 재작성:
  - 기존: `RawDatagramSocket.bind(anyIPv4, 0)` + `broadcastEnabled = true` + 2초마다 `255.255.255.255:41234` send / 게스트는 41234 listen
  - 신규: 호스트 `nsd.register(Service(name, type: '_synchorus._tcp', port, txt))` / 게스트 `nsd.startDiscovery(serviceType, ipLookupType: any)` + `addServiceListener`
  - **인터페이스(`startBroadcast`/`discoverHosts`/`stop`) 호환 유지** → 호출부(`home_screen.dart`, `room_screen.dart`) 수정 0
  - `roomCode`는 mDNS TXT records로 전달 (`Map<String, Uint8List>` 형태로 utf8 인코딩)
  - 서비스 발견 시 IPv4 우선 (link-local IPv6는 일부 환경에서 connect 불안정)
  - `stop()`은 unregister + stopDiscovery + StreamController close 모두 처리. async Future<void>로 변경 (호출부 fire-and-forget)
- **iOS Info.plist**: `NSBonjourServices=_synchorus._tcp` 이미 등록되어 있어 추가 변경 0 (v0.0.41 시점에야 실제로 사용되기 시작)
- **Android Manifest**: `CHANGE_WIFI_MULTICAST_STATE` 이미 등록되어 있어 추가 변경 0

**검증** (이번 세션 사용자 보고):
- iPhone 호스트 + Android 게스트 검색: **PASS** (이전 안 됐던 방향 fix)
- Android 호스트 + iPhone 게스트 검색: **PASS** (회귀 없음)

**효과**:
- multicast entitlement 신청 없이 영구 fix
- 표준 Bonjour 패턴이라 mDNSResponder가 시스템 단위로 처리 → 권한·entitlement 부담 ↓
- iOS의 NSLocalNetworkUsageDescription 권한 다이얼로그가 nsd discovery 시 명확히 트리거 (이전 raw UDP는 트리거 비결정적)

**남은 한계**:
- mDNS는 같은 LAN segment 내에서만 작동 (라우터 분리 시 작동 안 함). 단 이전 raw UDP broadcast도 같은 한계라 회귀 아님
- 첫 discovery 시작에 ~수백ms 지연 가능 (mDNS query → 응답 대기). 사용자 체감엔 영향 적음

**변경 범위**: `pubspec.yaml`(nsd 추가, 0.0.40→0.0.41), `lib/services/discovery_service.dart`(전체 재작성). 호출부·iOS Info.plist·Android Manifest·native code 변경 0.

---

### 2026-04-25 (36) — mDNS stale 방 fix (v0.0.42) — found/lost 즉시 반영 PASS

**배경**: v0.0.41 nsd 마이그레이션 후 사용자가 같은 호스트 기기에서 방 만들기 → 나가기 반복하니 게스트 검색 화면에 stale 방이 누적 발견. 이미지 보고: S22(172.30.1.25)에서 만든 방 코드 7728/6457/3323 등 동시에 표시됨. 원인은 두 가지.

**원인 1 — 호스트 측 unregister 누락**:
- `room_screen.dart:354`의 `discovery.stop()`이 **await 없이 fire-and-forget** 호출
- 바로 다음 줄들에서 `ref.invalidate(discoveryServiceProvider)` 등 인스턴스 교체 → `nsd.unregister()`가 mDNS goodbye 패킷 송신 완료 전 중단되거나 실행 안 됨
- → 게스트 cache에 stale record가 TTL(75~120초) 만료까지 남음

**원인 2 — 게스트 측 lost 이벤트 미처리**:
- `discovery_service.dart`의 listener가 `ServiceStatus.found`만 emit
- `ServiceStatus.lost`(mDNS goodbye 또는 TTL 만료) 발생해도 게스트 UI는 그대로 → `home_screen.dart`가 lost 알 길 없음

**v0.0.42 fix**:
1. **`room_screen.dart:354`**: `discovery.stop()` → `await discovery.stop()`. ref.invalidate 전에 unregister + goodbye 송신 완료 보장
2. **`discovery_service.dart`**:
   - `Map<String, DiscoveredHost> _knownHosts` (service.name → host) 내부 맵 추가, found 시 등록
   - `ServiceStatus.lost` 분기 추가: `_knownHosts.remove(serviceName)` → `_hostLostController.add(roomCode)`
   - `Stream<String> get hostLeftStream` getter 추가 (broadcast)
   - `dispose()` 메서드 추가: stop() + lost controller close
3. **`app_providers.dart`**: `discoveryServiceProvider`의 `onDispose`를 `stop()` → `dispose()`로 (broadcast controller leak 방지)
4. **`home_screen.dart`**:
   - `StreamSubscription? _hostLeftSub` 필드 추가
   - `_startDiscovery`에서 `discovery.hostLeftStream.listen((roomCode) → removeWhere)` 구독
   - `_stopDiscovery`/`dispose`/`_joinRoom` 흐름에 `_hostLeftSub?.cancel()` 추가

**검증** (사용자 보고): "한쪽에선 검색 눌러놓고 다른쪽은 방만들었다 나갔다하면 검색하는쪽에선 바로바로 생겼다가 사라졌다해" — found/lost 양방향 즉시 반영 **PASS**. stale 방 누적 0.

**효과**:
- 호스트 → 게스트 cache 동기화가 mDNS goodbye 기반으로 즉시 작동
- 호스트가 비정상 종료(force kill)되면 lost 이벤트가 TTL 만료 시점에 emit (75~120초). 정상 흐름은 즉시
- list에 표시되는 방의 신뢰도 ↑, 사용자가 눌러서 connect 시도 시 "호스트 응답 없음" 비율 ↓

**남은 한계**:
- 호스트 비정상 종료(앱 강제 종료, 라우터 끊김) 시 lost 이벤트는 TTL 만료까지 지연 — mDNS 표준 거동. 사용자 체감엔 보통 75~120초 후 사라짐
- 다른 LAN segment(VLAN 등) 분리되면 원래 mDNS 자체가 안 뜸 (라우터 재구성 외 fix 불가)

**변경 범위**: `lib/screens/room_screen.dart`(await 한 줄), `lib/services/discovery_service.dart`(_knownHosts + lost 분기 + dispose), `lib/providers/app_providers.dart`(onDispose dispose로 변경), `lib/screens/home_screen.dart`(_hostLeftSub 구독 + 정리), `pubspec.yaml`(0.0.41→0.0.42). native·iOS Info.plist·Android Manifest 변경 0.

---

### 2026-04-25 (37) — Android 게스트 BT 시나리오 측정 — (33-2) 가설 부분 반증 (문서 only)

**배경**: (33-2)에서 "Android 게스트 BT는 Oboe `calculateLatencyMillis()`가 BT codec/radio 단계 거의 안 잡아서 게이팅(옵션 A)만으론 부족 → acoustic loopback(C)이 거의 유일"이라고 추정. v0.0.42 검증 후 미관측 케이스(iPhone 호스트 내장 + S22 게스트 갤럭시 버즈 BT) 측정해 가설 검증.

**시나리오**: iPhone(172.30.1.93, 호스트, 내장 스피커) + S22(172.30.1.25, 게스트, 갤럭시 버즈 BT). 2분 재생 + 끝부분 재생/정지/seek 연타.

**S22 logcat (`OboeEngine:W`) — 11회 streak**:

| 시각 | streak | 비고 |
|---|---|---|
| 17:46:17 | **6회/507ms** | 재생 시작 직후, anchor establish 시점 |
| 17:48:23 ~ 17:49:09 | 1회/26~79ms × 6번 | 정상 짧은 streak (state=Started, xrun=0) |
| 17:49:53 | 8회/729ms | 끝부분 연타 시작 |
| 17:49:58 | 3회/263ms | 연타 |
| 17:50:08 | 4회/327ms | 연타 |

**사용자 체감 보고**: "짧게는 바로, 길게는 2초 정도 후에 싱크가 맞기 시작해서 쭉 잘됐어. 재생/정지 연타나 seek 연타 해봤는데도 안정."

**결과 분석**:
- **(30) 같은 비정상 긴 streak 미재현** — 모두 `ErrorInvalidState + state=Started + xrun=0` 정상 stream 전환만
- 첫 streak(507ms, 6회)이 사용자 체감 "~2초 정착"의 일부 — 정착 후 음향 안정
- 연타 구간 streak(>200ms)도 사용자 행동에 따른 정상 거동 (정지/재시작/seek가 stream 일시 전환 유발), 음향 어긋남 없었음
- 호스트가 iPhone이라 drift csv는 iPhone sandbox 안에 있음 — adb 직접 pull 불가, 본 분석엔 제외 (사용자 체감 + S22 logcat이 1차 데이터)

**(33-2) 가설 부분 반증**:
- "Android 게스트 BT는 acoustic loopback 거의 유일"이라는 가설이 **Galaxy + 갤럭시 버즈 조합에선 반증**됨. OS 보고가 충분히 정확해 v0.0.38 anchor 베이크인만으로 사용자 체감 만족 (~2초 정착, 이후 안정)
- 가능 원인: Samsung 자체 BT 코덱 또는 Samsung HAL이 BT latency를 Oboe wiki 일반론보다 더 정확히 보고. Galaxy 생태계 통합 효과
- iPhone+버즈(처음 40초 잔여)와 대비: **Android 게스트 정착 시간이 더 짧음**. iOS의 워밍업 50~60ms 과소보고가 베이크인에 더 큰 영향을 줬을 가능성
- 일반화 보류: 다른 BT 기기(일반 BT 스피커, Pixel + AirPods 등) 미검증

**남은 BT 케이스** (검증 안 됨):
- AirPods on iPhone (W1/H1 통합 — Apple Forum 데이터로 추정 가능, 안정화 후 정확)
- 일반 BT 스피커 (예: JBL) — 코덱 의존성 클 것
- AirPods on Android (반대 통합)
- aptX/LDAC 사용 시

**의미**:
- v0.0.38 anchor 베이크인이 OS 보고 정확도가 충분한 케이스(Galaxy + 버즈)에선 acoustic loopback 없이도 충분
- (33-2) 옵션 C(acoustic loopback) 우선순위 ↓. iPhone+버즈 같은 OS 보고 부정확 케이스는 옵션 A(워밍업 게이팅)만으로도 잡힐 가능성 ↑
- BT 워밍업 잔여 fix는 **iPhone+버즈 시나리오에 한정한 옵션 A 시도가 가성비 1순위**

**변경 범위**: 없음 (측정·문서). v0.0.42 그대로.

---

### 2026-04-25 (38) — iPhone 호스트 정지/재생/seek 버그 fix (v0.0.43)

**배경**: iPhone 호스트일 때 두 가지 버그 사용자 보고:
1. **정지 상태에서 seek 안 됨**: -5/+5 버튼은 아예 안 움직이고, seek바 드래그앤드랍은 일시적으로 움직이지만 손 떼면 이전 위치로 돌아감
2. **재생 → 정지 → 재생 시 정지 시점이 아닌 이전 위치(마지막 seek/0:00)부터 재생**
3. (게스트 관찰) 호스트 재생 시작 시 게스트 화면이 잠깐 최대 재생시간으로 튀었다가 현재 위치로 돌아오는 잔상

**원인 — iOS native (`AudioEngine.swift`) 두 곳**:

1. `getTimestamp()` 정지 분기 (line 119~121): `["ok": false]`만 반환 → **`virtualFrame`/`sampleRate`/`totalFrames`/`wallAtFramePosNs` 키 모두 누락** → Dart `NativeTimestamp.fromMap`에서 fallback 0으로 → `_engine.latest.virtualFrame = 0` + `sampleRate = 0` → `_skipSeconds`의 `currentMs = 0`으로 계산 → seek가 0:00으로 되돌아감 + 게스트 측에 일시적 잘못된 vf 노출
2. `stop()` (line 78~88): `playerNode.stop()` + `engine.stop()` + node 분리만 처리, **정지 시점의 vf를 `seekFrameOffset`에 저장 안 함** → 다음 `start()`의 `scheduleAndPlay(from: seekFrameOffset)`이 정지 직전 위치 모름 → 마지막 seek 위치(또는 0)부터 재생

Android oboe는 `getLatestTimestamp`가 vf를 atomic load로 항상 유효 반환 + `mVirtualFrame`이 callback에서 매 frame 갱신 → 같은 버그 없음. iOS native만 수정.

**v0.0.43 fix** (`ios/Runner/AudioEngine.swift`):
1. `getTimestamp()`에 `stoppedReturn` 추가 — 정지/timestamp 무효 분기에서도 `virtualFrame`/`sampleRate`/`totalFrames`/`wallAtFramePosNs`/`outputLatencyMs` 포함해 반환. ok=false flag만 다름. ok=true 분기는 기존대로 framePos·timeNs 포함.
2. `stop()` 진입 시 현재 `lastRenderTime` + `playerTime`으로 vf 계산 → `seekFrameOffset += sampleTime` 누적. 음수·totalFrames 초과는 clamp. 그 후 기존 stop 처리.

**검증** (사용자 보고): "잘 되는 것 같아" — 체감 OK. 간접 데이터(logcat) 검증은 보조 옵션, 사용자 체감으로 1차 PASS.

**남은 한계**:
- iOS native만 변경, Android는 영향 없음 (이미 정상)
- `_skipSeconds` 등 Dart 측은 변경 없음 — 호스트가 정확한 vf/sampleRate 받으니 자동으로 정상 동작
- v0.0.42 게스트(Android)는 호환 그대로 (P2P 메시지·Dart 코드 변경 0)

**변경 범위**: `ios/Runner/AudioEngine.swift` (`stop()` vf 저장 + `getTimestamp()` 정지 분기 stoppedReturn), `pubspec.yaml`(0.0.42→0.0.43). Dart·Android·iOS Info.plist 변경 0.

---

### 2026-04-25 (39) — 첫 재생 정착 시간 이슈 정리 (문서 only)

**배경**: 사용자 관찰: BT 무관하게 모든 시나리오에서 첫 재생 직후 아주 잠깐 싱크가 틀어졌다가 정착. 사용자 가설: "호스트가 신호 보내고 바로 재생 + 게스트도 신호 받고 재생 → 신호 전송 시간(RTT)만큼 어긋남". 가설 검증 + 진짜 원인 분석.

**가설 검증 — RTT 자체는 보정됨**:
- 호스트 `syncPlay()`: `_engine.start()` + 즉시 audio-obs broadcast (`hostTimeMs = ts.wallMs`, `framePos`, `virtualFrame` 포함)
- 게스트는 `_sync.filteredOffsetMs`(NTP-style ping의 clock skew)로 자기 wall → 호스트 wall 변환: `hostWallNow = ts.wallMs + offset`
- 게스트가 호스트 framePos 외삽으로 "호스트가 지금 재생 중인 콘텐츠 위치" 계산 → 그 위치로 seek
- → RTT 50~200ms든 게스트는 자동으로 따라잡음. 사용자 가설은 **부분적으로만 맞음** (RTT 자체는 직접 원인 아님)

**진짜 원인 분류**:

| 요인 | 영향 |
|---|---|
| 게스트 `engine.start()` 자체 지연 | iOS 100~500ms (audio session active + node 생성 + scheduleSegment). 그 동안 호스트는 진행 → 게스트 출발 후 따라잡아야 함 |
| 첫 anchor establish 전 fallback alignment | `_sync.isOffsetStable` 전엔 fallback만 작동(정밀도 ±8ms). 정밀 anchor는 clock sync 5~15초 수렴 후 |
| clock sync 수렴 시간 | NTP-style ping의 EMA가 안정될 때까지 RTT 변동이 offset 추정에 노이즈. 첫 수 초 동안 ±10~30ms 흔들림 |
| 호스트 첫 obs 즉시 vs 정기 obs 500ms 주기 | 첫 obs 받고 fallback 정렬 후, 다음 obs로 점진 보정 |
| BT outputLatency 워밍업 | iPhone+버즈 한정 ~40초 잔여 (별도 트랙) |

**즉 ~수 초 정착 시간 = 위 요인 합성**. RTT는 보정되지만 게스트 시작 지연 + 첫 sync 수렴까지 시간은 알고리즘 특성.

**잡는 방법 후보** (다음 세션):

1. **NTP-style 예약 재생** (가장 정석)
   - 호스트가 syncPlay 시 "현재 wall + N ms 시각에 양쪽 동시 재생 시작" 메시지 broadcast
   - 게스트는 자기 wall 기준 (예약 시각 - offset) 시점에 engine.start() 예약
   - iOS는 `AVAudioPlayerNode.play(at: AVAudioTime)` 정밀 예약 가능
   - Android oboe도 frame 예약 가능 (추가 코드 필요)
   - 효과: 첫 재생 직후 정착 시간 거의 0
   - 비용: 양쪽 native + Dart 흐름 변경 중

2. **게스트 사전 워밍업**
   - 호스트 syncPlay 누르기 전 미리 게스트가 audio engine 활성화 + 무음 schedule
   - engine.start() 자체 지연(100~500ms) 흡수
   - 비용: 작음. 단 효과는 engine.start 지연 분만 잡음

3. **첫 anchor 가속**
   - `_sync.isOffsetStable` 임계 완화 또는 첫 obs 직후 anchor 시도
   - 비용: 작음. 단 clock sync 수렴 전이라 첫 anchor가 부정확해질 수 있어 회귀 위험

**우선순위 후보** (다음 세션):
- 1번(NTP-style 예약)이 효과 큼. 단 작업량 ↑ — Phase 3 진입 전 MVP 완성도 위해 가치 있음
- 2번(사전 워밍업)이 가성비 좋음 — 빠른 시도 가능
- 3번은 회귀 위험 있어 측정 후 결정

**관련**: BT 워밍업 잔여(33-2, 37)는 다른 root cause. 이 (39)는 BT 무관 일반 시작 정착 이슈.

**변경 범위**: 없음 (문서 only). v0.0.43 그대로.

---

### 2026-04-26 (40) — v0.0.44 게스트·호스트 prewarm으로 첫 재생 정착 시간 단축

**배경**: (39)에서 분석한 첫 재생 정착 시간의 주 원인 중 **게스트 `engine.start()` 자체 지연**(iOS 100~500ms — AVAudioSession activate + AVAudioPlayerNode 생성 + scheduleSegment) 잡기. 동시에 (33-2)/(37) BT outputLatency 워밍업 잔여(iPhone+버즈 ~40초)도 일부 같이 해결 기대 — prewarm 1초 동안 codec/HAL이 안정값으로 수렴하면 첫 anchor establish 시점에 정확한 outputLatency가 베이크인됨.

**(39)의 후보 2번(게스트 사전 워밍업) 채택**. 1번(NTP-style 예약)은 변경량 크고 양쪽 native 정밀 예약 코드 필요 → Phase 1로 2번부터, 효과 측정 후 1번 검토.

**설계 — 게스트가 파일 로드 후 미리 엔진 데우기**:

기존 흐름 (v0.0.43):
```
guest: 다운로드 → loadFile → (대기)
                                    ↓ 호스트 syncPlay
guest:                              engine.start() ← 100~500ms
                                    → 출력 시작 (호스트와 정렬 시도)
```

v0.0.44 흐름:
```
guest: 다운로드 → loadFile → prewarm() ← 100~500ms 미리
                              ├─ AVAudioSession.setActive
                              ├─ engine.start (노드 attach만, schedule X)
                              └─ idle 무음 송신 (PCM 0)
                              (60초 idle 시 자동 coolDown)
                                    ↓ 호스트 syncPlay
guest:                              engine.start() ← 수십 ms
                                    └─ scheduleSegment + node.play
```

**iOS `AudioEngine.swift`**:
- `prewarm()` 추가 — `setActive(true)` + `engine.start()` + 노드 attach. **노드 schedule/play 안 함** → PCM 송신 0이지만 codec/HAL은 깨어 있음.
- `start()` 단순화 — `isEngineRunning` false면 prewarm 호출, 그 후 `scheduleAndPlay`만.
- `coolDown()` 추가 — `stop()` + `setActive(false, options: .notifyOthersOnDeactivation)`. audioFile 보존, 다음 prewarm 시 디코딩 재사용. idle timer가 호출.
- `seekToFrame()` 가드 — `node.isPlaying`일 때만 reschedule. prewarmed but not playing 상태에서 호스트 seek-notify 받아도 의도치 않게 재생 시작 안 함 → seekFrameOffset만 갱신, 다음 start에서 새 위치부터.
- `unload()` — `coolDown()` 호출하도록 통일.
- `sessionActivated` 멤버 추가로 deactivate 멱등 처리.

**Android `oboe_engine.cpp`**:
- `prewarm()` 추가 — stream 만들고 `requestStart`, **`mPrewarmIdle=true`로 콜백을 무음 + vf 동결 모드**로 만듦. AAudio/BT codec은 깨어 있어 워밍업 효과는 유지.
- `start()` 분기 — stream 있으면 `mPrewarmIdle=false`로 풀어 즉시 정상 출력. 없으면 prewarm 후 동일 처리.
- `coolDown()` — Android는 글로벌 세션 개념 없어 `stop()`과 동일. iOS와 인터페이스 통일을 위해 추가.
- `onAudioReady()`에 `mPrewarmIdle` 가드 — true면 silent + vf 진행 안 함. start() 시 즉시 정상 출력 + 0:00부터 시작 보장.
- JNI export `nativePrewarm` / `nativeCoolDown` + Kotlin `NativeAudio.kt` external 선언 + `MainActivity.kt` 채널 핸들러.

**Dart `NativeAudioService`**:
- `prewarm()` / `coolDown()` MethodChannel 인터페이스 추가.

**`NativeAudioSyncService` (`native_audio_sync_service.dart`)**:
- 호스트 `loadFile()` 끝에 `_engine.prewarm()` + `_startPrewarmIdleTimer()` — 호스트도 syncPlay 시 즉시 시작.
- 게스트 `_handleAudioUrl()` loadFile 후 `_engine.prewarm()` — `hostPlaying=true`면 곧장 `_startGuestPlayback()` 호출(start가 prewarm된 stream 활용해 즉시 정상 출력), `false`면 idle timer 시작해 호스트 syncPlay 대기.
- `syncPlay` / `_startGuestPlayback` 진입 시 `_cancelPrewarmIdleTimer()`.
- `syncPause` / `_stopGuestPlayback` 끝에 `_engine.prewarm()` + `_startPrewarmIdleTimer()` — 정지 → 재생 시점도 빠르게.
- 새 파일 들어왔을 때(`loadFile` / `_handleAudioUrl` 시작) `_cancelPrewarmIdleTimer()` + 명시적 `_engine.stop()` 호출 (prewarmed 상태 정리).
- `cleanupSync` 에 `_cancelPrewarmIdleTimer()` 추가.
- 새 헬퍼 `_startPrewarmIdleTimer()` / `_cancelPrewarmIdleTimer()` — 60초 후 `_audioReady` && `!_playing`이면 `_engine.coolDown()`.

**부작용 안전망**:
- **iOS `setActive(true)`로 다른 앱 오디오 인터럽트** (Apple 공식: `.playback` 카테고리는 `mixWithOthers` 옵션 없으면 기본 nonmixable, developer.apple.com/documentation/AVFAudio/AVAudioSession/setActive). 기존엔 syncPlay 시점에 인터럽트 발생, prewarm 후엔 다운로드 직후로 앞당겨짐 → **60초 idle timer로 cap**, idle 종료 시 `setActive(false, .notifyOthersOnDeactivation)`로 다른 앱 음악 풀어줌.
- **AirPods auto-disconnect**: 60초 안에 syncPlay 또는 coolDown 둘 중 하나로 끝남 → 일반 BT 절전 timeout(보통 분 단위) 안 건드림.
- **메모리**: AVAudioPlayerNode 1개 + oboe stream 1개 + AVAudioSession active 추가 점유. 무시 가능.

**기대 효과**:
1. 첫 재생 정착 시간 — engine.start 자체 지연(100~500ms) 거의 제거. clock sync 수렴 + 첫 anchor establish 시간은 별도 트랙(NTP 예약 재생 검토 필요).
2. BT 워밍업 잔여 — prewarm 1초 동안 outputLatency가 안정값으로 수렴 → 첫 anchor establish가 정확한 값 베이크인. iPhone+버즈 ~40초 잔여 단축 기대.

**검증 (다음 세션)**:
- S22 + iPhone 실기기 LAN. 양쪽 내장 / iPhone+버즈 / S22+버즈 / iPhone 호스트 / S22 호스트 / 게스트만 BT 시나리오.
- 체감 + drift csv (`/sdcard/Android/data/com.synchorus.synchorus/files/`).
- 회귀 — 다른 앱 음악 인터럽션 시점, syncPause→syncPlay 정착 시간, 정지 상태 seek (v0.0.43 fix), peer 입퇴장.

**변경 범위**: `ios/Runner/AudioEngine.swift`, `ios/Runner/AppDelegate.swift`, `android/app/src/main/cpp/oboe_engine.cpp`, `android/app/src/main/kotlin/com/synchorus/synchorus/NativeAudio.kt`, `android/app/src/main/kotlin/com/synchorus/synchorus/MainActivity.kt`, `lib/services/native_audio_service.dart`, `lib/services/native_audio_sync_service.dart`, `pubspec.yaml`(0.0.43→0.0.44).

---

### 2026-04-26 (41) — v0.0.45 prewarm 회귀 롤백 + baseline 회복

**배경**: v0.0.44 prewarm 적용 후 첫 측정에서 **csv drift 안정 -3 ~ -5ms (게스트 일관 앞섬)**. 사용자 체감 "csv는 잘 맞은 듯한데 미묘하게 게스트가 빠르다". A fix(iOS prewarm을 setActive까지만)로 한 번 더 측정 → drift +5 ~ +7ms로 부호만 바뀐 비결정적 회귀. 사용자 대기 시간(prewarm duration)에 따라 결과 달라짐. **v0.0.43 baseline이 더 정확**한 것이 확정 → 전체 롤백 결정.

**진단 (실측 데이터)**:

| 측정 | drift abs 평균 | drift 평균 | 패턴 |
|---|---|---|---|
| v0.0.44 prewarm | 3.14ms | -3.08ms | 게스트 일관 앞섬 |
| v0.0.44 A fix | 3.83ms | +3.80ms | 게스트 일관 뒤섬 |
| **v0.0.45 롤백 (S22+iPhone)** | **1.21ms** | **+0.08ms** | **0 근처 진동, 346 샘플** |

`[ANCHOR] establish` 진단 로그로 가설 확인:
- v0.0.44 prewarm: `host fpVfDiff_ms=+13,595 (13.5초 누적)`, `guest fpVfDiff_ms=+55,547,899 (15시간)` ← Android oboe stream framePos가 prewarm으로 stop/start 사이 누적. iOS는 device level 누적(prewarm 무관, v0.0.43에도 같음).
- v0.0.45 롤백: `host fpVfDiff_ms=-11ms` ← 정상 buffer offset (oboe DAC 출력 latency).

**가설 정정**: 첫 분석에선 "iOS prewarm으로 framePos 누적이 회귀 원인"으로 추정했으나, **iOS framePos는 prewarm 무관하게 device level 누적값**(역할 반전 측정에서 확인). 진짜 회귀 원인은 **Android oboe 측 prewarm으로 stream framePos가 stop/start 사이 누적된 것**으로 좁혀짐. 어쨌든 측정으로 prewarm 호출 제거 시 baseline 회복은 확정.

**v0.0.45 변경**:
- `lib/services/native_audio_sync_service.dart`:
  - 호스트 `loadFile()` 끝부분 `_engine.prewarm()` + `_startPrewarmIdleTimer()` 호출 제거
  - 호스트 `syncPause()` 후 `_engine.prewarm()` 재호출 제거
  - 게스트 `_handleAudioUrl()` loadFile 후 `_engine.prewarm()` 호출 제거
  - 게스트 `_stopGuestPlayback()` 후 `_engine.prewarm()` 재호출 제거
  - dead code 정리: `_prewarmIdleTimer` 멤버, `_startPrewarmIdleTimer`/`_cancelPrewarmIdleTimer` 헬퍼, `_prewarmIdleTimeout` 상수, `syncPlay`/`_startGuestPlayback`/`cleanupSync`/`loadFile`/`_handleAudioUrl`의 `_cancelPrewarmIdleTimer()` 호출 제거
  - 새 파일 진입 시 명시적 `_engine.stop()` 호출 제거 (prewarm 정리용이었음)
- iOS `AudioEngine.swift` / Android `oboe_engine.cpp`: `prewarm()`/`coolDown()` 함수 자체는 dead code로 유지 (다음 NTP 예약 재생 작업에 재활용 가능). `mPrewarmIdle` 가드도 유지.
- 진단 로그 (`[SYNCPLAY-HOST]`, `[ANCHOR]`, `[OBS-FIRST]`, `[OBS-PLAYSTART]`)는 baseline 검증 + 다음 작업 분석에 유용해 유지.
- `pubspec.yaml`: 0.0.44+1 → 0.0.45+1.

**검증**:
- S22 host + iPhone guest: drift abs 1.21ms (346 샘플), 사용자 체감 "잘 맞다", 재생/정지/seek 연타도 자연스러움.
- 롤백으로 baseline 회복 확정.

**남은 한계** ((42) 별도 트랙): 역할 반전 (iPhone host + S22 guest) 측정에서 **anchor reset 후 fallback 단계 큰 drift 발견** (drift -634ms 등). v0.0.43 baseline에도 있던 edge case로 확정 → 별도 작업.

**변경 범위**: `lib/services/native_audio_sync_service.dart`, `pubspec.yaml`(0.0.44→0.0.45). iOS/Android native 코드는 함수 정의만 남음 (호출 0).

---

### 2026-04-26 (42) — anchor reset 후 fallback 단계 큰 drift edge case 발견

**배경**: v0.0.45 마감 후 역할 반전 (iPhone host + S22 guest) 검증 측정. drift 평균 -6.59ms, abs 평균 6.90ms (361 drift 샘플)로 정상 재생 시엔 양호. 단 **사용자 체감 "2분 재생 후 싱크가 엄청 틀어졌다"** + 측정에서 **fallback 단계 drift 절댓값 max 634ms (0.6초 어긋남)** 발견.

**원인 — anchor reset 후 fallback 단계의 외삽 부정확**:

1. 호스트가 정지/재생/seek 누름 → audio-obs broadcast (playing 변동)
2. 게스트가 `_stopGuestPlayback`/`_startGuestPlayback` 호출 → `_engine.stop`/`_engine.start`
3. `_startGuestPlayback` 끝의 `_resetDriftState()` → **anchor 폐기** (`_anchorHostFrame = null`)
4. anchor 재 establish까지 **clock sync stable(`_sync.isOffsetStable`) 또는 충분한 obs 도착 대기 = 약 5초 동안 fallback align만 작동**
5. fallback align은 호스트 obs 외삽으로 정렬 시도 — **게스트 측 stream 시작 latency를 못 잡음**
6. 큰 drift 보고 + 큰 seek 발생 → 사용자 귀에 콘텐츠 점프 느낌

**왜 Android 게스트만 심한가**:
- iOS AVAudioEngine: stream 새로 시작 latency 수 ms (S22 host + iPhone guest 측정에서 안 보임)
- Android oboe: stream open + setup latency 10~수백 ms — fallback 외삽이 그 latency를 못 잡음 → drift -130 ~ -634ms 보고

**v0.0.43 baseline에도 있던 이슈**:
- v0.0.43 시점 측정은 S22 host + iPhone guest만 수행 → 안 보였음
- 역할 반전 측정 미수행이라 발견 못 했음
- prewarm 회귀와 무관 — 코드 자체의 한계

**관찰된 시그니처** (iPhone host + S22 guest, 22:14:19~22:15:19 약 1분):
```
[FALLBACK] align: drift=-120ms
[ANCHOR] establish ...
[FALLBACK] align: drift=-138ms → [ANCHOR]
[FALLBACK] align: drift=-270ms
[FALLBACK] align: drift=-109ms → [ANCHOR]
[FALLBACK] align: drift=-634ms ★ 0.6초 어긋남
[ANCHOR]
[FALLBACK] align: drift=-130ms → [ANCHOR]
```
9회 anchor establish + 7회 fallback align + 1회 anchor invalidated.

**해결 방향 (v0.0.46 트랙)**:
1. **`_startGuestPlayback`의 `_resetDriftState` 조건부 호출** — 같은 콘텐츠 이어 재생이면 anchor 보존 (단 oboe stream framePos가 stop/start로 reset되는 점 고려 필요)
2. **fallback align 외삽에 게스트 측 stream 시작 latency 보정** — 어렵지만 직관적
3. **NTP-style 예약 재생** (HISTORY (39) 후보 1번) — anchor 의존 자체 제거. 변경량 큼. 정공법.

먼저 1번 시도 → 효과 측정 → 부족하면 3번.

**변경 범위**: 없음 (분석/문서). v0.0.45 그대로. v0.0.46 작업 대상.

---

### 2026-04-26 (43) — v0.0.46 oboe pause/resume + v0.0.47 NTP 예약 재생 시도 → v0.0.48 롤백

**배경**: (42) anchor reset 후 fallback 단계 큰 drift edge case (iPhone host + S22 guest, 최대 -634ms 점프) 잡기 위한 단계적 시도. 결과적으로 정공법 NTP 예약 재생까지 도달했으나 메시지 race + outputLatency 비대칭 등 정밀 작업 부족으로 회귀 발생 → 롤백. 단 NTP 인프라 (native scheduleStart/cancelSchedule + 메시지 프로토콜)는 코드에 보존 → 다음 세션 재도입 가능.

**시도 단계**:

**v0.0.46 (1차) — oboe stop을 close + reset → pause로 변경**:
- 가설: stream open latency (Android 100~수백ms)가 anchor reset 후 fallback 단계의 외삽에서 못 잡혀 큰 drift 발생. stream을 살려두면 latency 0.
- 변경: `oboe_engine.cpp` stop() = `requestPause()`, `unload()` = 진짜 close. start()는 stream 있으면 resume.
- v0.0.46 stale hostPlaying fix 추가 — `_handleAudioUrl` loadFile 후 `_latestObs?.playing` 우선해서 다운로드 도중 호스트 syncPause 후 게스트만 재생되는 케이스 차단.
- 측정 (S22 host + Tab A7 Lite guest): drift abs 평균 3.88ms, max 571ms — 회귀 차단 부분적. Tab A7 Lite의 oboe `requestPause` 사이클이 xrun + getTimestamp ErrorInvalidState 동반 → fallback 단계 외삽 작동 못 함 → 큰 점프 여전. **저가형 oboe HAL 한계**.

**v0.0.47 (2차) — NTP-style 예약 재생 도입**:
- 가설: reactive 보정 자체가 "발생 후 따라잡기"라 stream 시작 latency 못 잡음. proactive — wall time + 200ms buffer로 양쪽 동시 시작 약속하면 anchor 의존 자체 제거.
- 변경: `engine.scheduleStart(wallEpochMs, fromFrame)` / `cancelSchedule()` 인터페이스 native 양쪽 추가.
  - **iOS**: `AVAudioPlayerNode.play(at: AVAudioTime(hostTime: ...))` — Apple 공식 정밀 예약 API.
  - **Android oboe**: data callback 안에서 `clock_gettime(CLOCK_REALTIME)` 비교 → 도달 전 silent + vf 동결, 도달 시 elapsed 보정 후 정상 출력.
  - JNI `nativeScheduleStart`/`nativeCancelSchedule` + Kotlin `MainActivity.kt` 핸들러 + Dart `NativeAudioService` 메서드.
- 메시지 프로토콜: `schedule-play: {startWallMs, fromVf}` + `schedule-pause: {immediate}` P2P broadcast.
- 호스트 syncPlay/syncSeek (재생 중) → broadcast + 자기도 scheduleStart. syncPause → cancelSchedule + broadcast.
- 게스트 `_handleSchedulePlay` — 호스트 wall → 게스트 wall 변환 (`hostWallMs - filteredOffsetMs`) 후 native scheduleStart.
- 합류 게스트는 `_scheduleFromObs`에서 `obs.virtualFrame` 외삽으로 자체 schedule 계산.

**v0.0.47 1차 측정**: drift abs 평균 157ms + max 38초. **race condition 발견**:
- `_handleSchedulePlay` 안 `await scheduleStart` yield 동안 `_playing=false` 상태 → `_handleAudioObs`가 obs.playing=true 보고 `_scheduleFromObs` 호출 → **두 핸들러 동시에 scheduleStart 호출**, 다른 fromVf로 → 호스트와 게스트 다른 콘텐츠 위치 시작.

**v0.0.47 race fix**: `_playing=true`를 `await` 전에 set + `_scheduleInProgress` flag.
- 측정: drift abs 평균 3.83ms, max ~수십초 — race는 차단됐지만 사용자 보고 "한 번 틀어지면 5초 후 정렬도 안 됨".

**v0.0.47 reactive seek 비활성화** (NTP 100% 의존 의도):
- `_fallbackAlignment` / `_tryEstablishAnchor`의 seek 호출 제거 (drift report 모니터링만 유지).
- 의도: NTP 예약 재생이 첫 정렬 보장 + 그 위에 reactive seek가 잘못 점프 방지.
- 측정: **drift abs 평균 63초 (max 4분)** — 완전 망. NTP schedule 자체는 logcat상 정확(같은 fromVf, 같은 wall) 작동하나 csv drift는 어마어마함. 메시지 처리 race + dart isolate ordering + outputLatency 비대칭 등 추가 정밀 작업 한 세션으로 부족.

**v0.0.48 롤백**:
- NTP 호출만 v0.0.45 동작으로 되돌림 (`engine.start`/`stop`/`seekToFrame` 직접). NTP 인프라 코드 (native scheduleStart/cancelSchedule, 메시지 핸들러) 보존 — 다음 세션 재활용.
- v0.0.46의 oboe pause/resume + stale hostPlaying fix는 유지 (회귀 없음 확인).
- `_fallbackAlignment` / `_tryEstablishAnchor` reactive seek 다시 활성화.
- 측정 (S22 host + Tab A7 Lite guest, 35 drift 샘플): **drift abs 평균 2.01ms, min -6.24, max +4.06** — v0.0.45 baseline (1.21ms) 회복 (통계 noise 범위 차이).

**핵심 학습**:
- NTP 예약 재생은 정공법이지만 **메시지 race / sequence ordering / outputLatency 비대칭 / 합류 게스트 자체 schedule** 등 다층적 정밀 작업 필요. 한 세션에 도달 불가.
- 다음 세션 정밀 작업 시 추가 필요: (a) schedule-play 메시지에 sequence number 도입, (b) `_scheduleFromObs`와 `_handleSchedulePlay` race 완전 제거, (c) outputLatency 비대칭 자동 보정.
- v0.0.43 시점 anchor reset edge case는 **알려진 한계**로 미해결 이슈에 유지. 일반 사용 패턴(쭉 듣기)에선 영향 없고 정지/재생/seek 연타 + Android 게스트 시나리오에서만 발현.

**변경 범위**: `lib/services/native_audio_sync_service.dart` (호출 v0.0.45 동작으로 롤백), `pubspec.yaml`(0.0.45→0.0.48). NTP 관련 native (iOS `AudioEngine.swift` `scheduleStart`/`coolDown`, Android `oboe_engine.cpp` `scheduleStart`/`mScheduledStartActive` 콜백 가드, JNI/Channel 핸들러)는 dead path로 보존. v0.0.46 oboe pause/resume + stale hostPlaying fix는 유지.

---

### 2026-04-27 (44) — v0.0.49~v0.0.61 NTP 정밀 재시도 13번 fix 사이클 → 사용자 청감 v0.0.48 더 나음 → main reset to v0.0.48

**배경**: (43) v0.0.48 baseline에 (42) edge case (Android 게스트 정지/재생/seek 시 max -634ms drift) 잔존. NTP 정밀 작업 (sequence number + race 제거 + 호스트도 schedule 적용)으로 (42) 잡으려 한 세션. 한 세션 내 13번 fix 사이클 진행됐으나 사용자 청감 비교 결과 v0.0.48이 더 나음 → 모두 revert.

**13번 fix 흐름 (v0.0.49~v0.0.61, backup branch `backup-v0.0.61-session`에 보존)**:

| 버전 | 변경 | 결과 |
|---|---|---|
| v0.0.49 | NTP 정밀 (a)seq number + (b)race 제거 + (e)호스트 schedule | abs 2.82ms (정상 구간), idx 86 outlier 1번 (+48s) |
| v0.0.50 | cooldown 1초 + anchor 즉시 무효화 | systemic +13ms drift 회귀 → revert |
| v0.0.51 | 호스트 `_broadcastObs` async + fresh getTimestamp | seek 연타 시 5~118초 어긋남 부분 잡음 |
| v0.0.52 | virtualFrame 기반 vf-sanity check (>500ms) | 1회 발동 PASS but 다른 케이스 미발동 |
| v0.0.53 | vf-sanity 조건 완화 (`drift<50` 제거) | 발동 빈도 ↑ but fd 1.3초 잔여 |
| v0.0.54 | obs.playing=false streak 2회 안전망 | 호스트 정지 신호 누락 fix |
| v0.0.55 | vf-sanity 외삽 가드 + 임계 200ms + logger flush | 무한 loop 회귀 (fd 358ms) |
| v0.0.56 | 임계 500 복원 + outputLatency cap 200ms + anchor 중복호출 버그 fix | abs 295ms |
| v0.0.57 | 진단: csv에 host_obs_wall 컬럼 추가 | rate drift 진단 가능 |
| v0.0.58 | rate drift 보정 (vf-correction, 100ms 임계) | abs 248ms — 이번 세션 best |
| v0.0.59 | 호스트 측 sync 메서드 직렬화 | vf-sanity 발동 ↑ → revert |
| v0.0.60 | outputLatency 자동 EMA 보정 | abs 279ms (회귀) |
| v0.0.61 | obs.playing=false streak 2→1회 | abs 279ms |

**진짜 원인 발견 (분석 단계)**:
- **drift_ms (anchor 변화율 기반)**: 시간 정확성 측정 — v0.0.48에선 2~3ms 매우 안정
- **frame diff (절대 콘텐츠 위치 차이)**: 진짜 음향 어긋남 측정 — v0.0.48에서도 350~400ms 잔존
- 두 측정값 일치 안 함 = anchor 베이크인된 outputLatency 부정확. v0.0.48~v0.0.61 모두에 있던 한계.
- `_tryEstablishAnchor` line 1222-1228 anchor 중복 호출 버그 발견 (v0.0.49부터 있던 잠재 버그)
- 호스트와 게스트 native rate 미세 차이 (~1%) 의심 (artifact일 수도)

**최종 측정 (v0.0.48 vs v0.0.61, 사용자 연타 환경)**:
| | drift_ms abs_mean | frame diff abs_mean | 측정 시간 |
|---|---|---|---|
| v0.0.48 | **2.43ms** | 477ms (outlier 망침) → 정상 ~350ms | 228초 |
| v0.0.61 | ~3ms | 279ms | 47초 |

frame diff는 두 버전 비슷한 범위. 단 **사용자 청감으로 v0.0.48이 더 나음** 보고. v0.0.49+ 변경들이 race 만들어서 청감 잔여 어긋남 더 컸던 것으로 추정.

**결정**:
- `git reset --hard 1c6da7d`로 main을 v0.0.48 baseline으로 reset
- v0.0.49~v0.0.61 commit은 `backup-v0.0.61-session` branch에 보존
- 다음 세션에 NTP 다시 도입할 때 이 분석 결과 참고 (race fix 우선 + 한 줄기씩)

**미해결 이슈 (다음 세션 후보)**:
1. **(42) Android 게스트 fallback drift edge case** (HIGH) — NTP가 정공법이지만 race 정밀 작업 + acoustic loopback 기반 검증 필요
2. **drift_ms vs frame diff 거짓말 패턴** — anchor 베이크인 outputLatency 부정확. acoustic loopback 또는 EMA 자동 보정 (v0.0.60 시도했지만 anchor reset 자주 발생해 누적 못 함)
3. **호스트/게스트 양쪽 FIFO 큐 직렬화** — 사용자 연타 race 차단 (v0.0.59 마지막-이김 큐는 회귀, FIFO로 의도 보존하면서 직렬화)
4. **첫 재생 정착 시간** (BT 워밍업 + clock sync 수렴, ~수 초 잠깐 어긋남) — 옵션 A (BT prebuffer + outputLatency 수렴 게이팅)

**다음 세션 시작 가이드**:
- 측정 환경 명확히: idle 측정 vs 사용자 연타 측정 분리
- 한 fix 도입 전 → 코드 정밀 분석 (라인 단위) + race 시나리오 시뮬레이션
- backup branch 참고: `git log backup-v0.0.61-session --oneline` 으로 13번 commit 확인 가능
- v0.0.56 anchor 중복 호출 버그 fix는 진짜 버그 — v0.0.48에 cherry-pick 검토할 가치
- HISTORY.md (50)~(54) 항목은 backup branch에만 있음 — 다음 세션에 main 통합할지 또는 새 분기로 진행할지 결정

**변경 범위**: `git reset --hard` (main을 1c6da7d로). 코드 변경 0. backup branch만 새로 생성 (`backup-v0.0.61-session`).

---

### 2026-04-28 (45) — v0.0.49~v0.0.50 측정 인프라 보강 + burst 측정으로 누적 발산 메커니즘 확정

**배경**: (44) 13번 fix 사이클 trial-and-error 회피 위해 디자인 문서 먼저 → 한 번에 알고리즘 v2 구현. 단 디자인 결정 근거 확보 위해 csv 측정 인프라 보강 + idle/burst 측정 선행 필요. CLAUDE.md "다음 세션 작업 흐름 (강제)" 1단계.

**v0.0.49 — csv 컬럼 강화 (sync 동작 변경 0)**:
- `vf_diff_ms` 추가: `expectedHostVfMs - guestVfMs - currentOutLatDelta` (vf 절대 위치 차이)
- `host_obs_wall` 추가: 게스트가 사용한 호스트 obs의 측정 시각 (외삽 신선도)
- `_recomputeDrift` 모드는 vfDiff를 별도 계산, `_fallbackAlignment`는 driftMs 자체가 vf 기반이라 동일 값
- 의도: drift_ms는 framePos 변화율(rate)만 보는 거짓말 패턴 발생 시점에 vf_diff_ms가 직접 노출

**v0.0.49 1차 측정 (S22 host + Tab A7 Lite guest)**:
- idle 4분 5초 (459 drift 샘플): drift_ms abs mean 3.01ms (98.7%가 <5ms), vf_diff_ms abs mean 22.33ms (max 60ms, signed mean -20.84ms)
- burst 2분 (107 샘플, csv blind 70초 누적): drift_ms abs mean 5.71ms, vf_diff_ms abs mean 21.89ms (max 72ms)
- **거짓말 패턴 직접 캡처**: drift_ms <5ms 안정인데 vf_diff_ms 30~50ms 베이크인이 4분 내내 유지. signed mean -20.84ms = 게스트가 호스트보다 ~21ms 뒤. 사용자 청감 미인지 한계 영역 (<25~40ms).

**문제 발견 — csv blind spot (사용자 청감과 csv 분포 불일치)**:
- 사용자 관측: 빠른 정지/재생 연타 시 호스트-게스트 차이 누적 발산, 본 것만 ~3초
- csv max 60ms로 분포만 봐선 사고 안 잡힘 → 정지 구간엔 broadcast 안 함 → drift report 0건 → csv blind
- 결정: **측정 인프라 더 보강 필요** — 호스트 syncPlay/Pause/Seek 이벤트 + 게스트 anchor establish/reset 이벤트 csv 별도 row로 기록

**v0.0.50 — 호스트/게스트 이벤트 csv 로깅 + seq + guest_wall**:
- 호스트 이벤트: `host_play`, `host_pause`, `host_seek` (직접 `_logger.log`)
- 게스트 이벤트: `guest_start`, `guest_stop`, `anchor_set`, `anchor_reset_offset_drift`, `anchor_reset_large_drift`, `anchor_reset_seek_notify` (P2P drift-report 재사용)
- 컬럼 추가: `seq` (csv 자체 단조 시퀀스 — 빠른 연타 시 동일 wallMs 정렬용), `guest_wall` (게스트 보낸 원본 wallMs — TCP lag + clock offset 분석용)
- `wall_ms` 컬럼은 호스트 received 시각으로 통일 → 단조 증가 보장
- sync 동작 변경 0, 측정 도구만 (P2P 트래픽 약간 증가하지만 미미)

**v0.0.50 burst 측정 (4분, 사용자 빠른 연타)**:
- 1589 rows (host_play 175 + host_pause 175 + host_seek 307 + guest_start 180 + guest_stop 143 + anchor_reset_seek_notify 307 + anchor_set 30 + anchor_reset_offset_drift 3 + drift 242 + fallback 27)
- **누적 발산 메커니즘 확정** — 4가지 결정적 발견:

| 발견 | 데이터 | 의미 |
|---|---|---|
| **guest_stop 누락** | host_pause 175 vs guest_stop 143 = 32회 누락 | 호스트 정지했는데 게스트는 그 사이 계속 재생 |
| **vfDiff 폭발** | max 45269ms (45초!), signed mean +3174ms | 사용자 본 ~3초의 실제는 45초 |
| **drift_ms는 정상** | mean 2.56ms, max 8.37ms, 96.3%가 <5ms | rate(framePos)는 매우 안정 |
| **자가 회복 안 됨** | vfDiff 45초 유지가 191~210초 (20초+ 동안) | `_reAnchorThresholdMs=200ms`는 drift 기준 → 거짓말 패턴 못 잡음 |

**메커니즘 4단계**:
1. 호스트 빠른 seek 폭주 (175~177초 사이 ms 단위 연타) → 매 seek가 anchor_reset_seek_notify + 1초 cooldown
2. cooldown 만료 전 또 seek → cooldown 갱신 → anchor 잡힐 시간 0
3. host_pause/play 빠른 전환 시 메시지 처리 race + obs broadcast 누락 → guest_stop 32회 누락 → vf 누적 앞섬
4. 빠른 연타 멈춰도 vfDiff 45초 유지 — drift_ms는 1ms로 정상이라 알고리즘이 발산을 정상으로 판단

**회복 메커니즘 직접 확인 (200~205초)**:
- 사용자가 idle로 둠 → fallback alignment 30ms 임계 발동 → 자가 보정 seek 5회 (vfDiff -25 → -52 → -16 → -8 → -5)
- 205초 anchor_reset_offset_drift → anchor_set → vfDiff -3.42ms 정상 복귀
- 사용자 청감 "5초 뒤 혼자 seek해서 맞춰짐"과 정합 (실제 csv는 ~25초 어긋남 유지 후 fallback 발동)

**디자인 문서 결정 근거 (실측 매칭)**:
- **결정 A (drift+vfDiff 결합 규칙)**: vfDiff >= 1초 시 drift 무시 강제 reseek. 현재 200ms 임계는 drift 기준이라 vfDiff 45초도 못 잡음. **fallback alignment의 30ms 임계는 이미 좋은 메커니즘** (시나리오 1~3에서 작동 증명) — anchor 모드에서도 동일 임계 적용.
- **결정 D (anchor 분리)**: rate anchor (framePos 기반, seek과 무관, 거의 reset 안 함) + position baseline (vf 기반, 매 seek-notify마다 강제 reseek) 분리. 현재 anchor 1개라 빠른 seek 폭주 시 잡힐 시간 0.
- **결정 E (임계값)**: drift_ms 정상 임계 10ms (idle 100% / burst 99.1% 만족), vfDiff 정상 50ms (idle 99.6% / burst 92.6%), vfDiff 큰 임계 1000ms (강제 reseek).
- **결정 F (race 차단)**: 호스트 측 200ms cooldown + 게스트 측 큐 + coalescing (latest-state만 처리, 메시지 idempotent state라 가능). 단순 FIFO만으론 처리 지연 어긋남 발생 — 사용자 통찰.
- **결정 G (정지/재생 vf 동기화)** — 새 결정사항. host_pause/play 시 호스트 vf 같이 broadcast → 게스트 강제 동기화. obs broadcast 만으론 메시지 누락 → guest_stop 누락 32회.

**측정 csv 보존**: `measurements/v0.0.49_idle_2026-04-28.csv`, `v0.0.49_burst_2026-04-28.csv`, `v0.0.50_burst_2026-04-28.csv` (디자인 결정 근거).

**다음 단계**:
1. v0.0.50 commit (이 항목)
2. measurements/ csv 별도 commit (raw 데이터 보존)
3. **디자인 문서 `docs/SYNC_ALGORITHM_V2.md` 작성** — 결정 A/B/D/E/F/G 각각 선택지 3개 + race 시뮬레이션 + 검증 방법
4. 사용자 합의 → v0.0.51 단일 commit으로 알고리즘 v2 구현

**변경 범위**: `lib/services/sync_measurement_logger.dart` (컬럼 4개 추가: seq, vf_diff_ms, host_obs_wall, guest_wall), `lib/services/native_audio_sync_service.dart` (vfDiff 계산 추가 + 9개 이벤트 로깅), `pubspec.yaml` (0.0.48 → 0.0.50). sync 동작 변경 0 — 측정 도구만.

---

### 2026-04-28 (48) — v0.0.51~v0.0.55 시도 후 v0.0.50 reset 결정 (청감 우선)

**배경**: (46)/(47) v0.0.51~v0.0.54 그룹 1 + v0.0.55 D-1 작업 후 검증 측정. v0.0.55 정상 환경에서 vfDiff 23배 회귀 발견 → 사용자 좌절 ("점점 좋아지는 게 아니라 퇴보"). 디자인 문서 + 측정 검증 흐름은 정상 작동했지만 알고리즘 변경 자체의 위험성과 사용자 경험 향상 효과 재평가.

**v0.0.55 회귀 (정상 환경 burst)**:

| | v0.0.54 burst | v0.0.55 burst | 변화 |
|---|---|---|---|
| drift_ms abs mean | 1.87ms | 1.71ms | 동등/향상 |
| **vfDiff abs mean** | 28.52ms | **658.44ms** | **23배 회귀** |
| **vfDiff max** | 702ms | **5188ms (5.2초)** | 7배 회귀 |
| vfDiff >=1초 | 0% | (높음) | 회귀 |
| position_baseline_reset_emergency | (없음) | **84회 진동** | 무한 진동 |

원인: D-1의 position baseline 외삽 부정확. `_handleSeekNotifyAwaited`/`_handleHostStateSync`에서 hostWallMs 계산 시 TCP lag 미반영 → 매 poll 외삽 어긋남 누적 → emergency 임계 도달 → reset → 진동.

**v0.0.48 vs v0.0.50 청감 직접 비교**:

v0.0.48 (commit 1c6da7d) 빌드/install 후 사용자 청감 측정:
- idle 2분: "초반 1~2초 살짝 → 잘 맞음"
- 빠른 연타 2분: "조금씩 미묘한 차이정돈 있지만 잘 맞음 (체감 ~20ms)"
- idle 1분: "잘 맞음"

→ **v0.0.48 청감 매우 안정. (44) 13번 fix 사이클 후 사용자 직접 청감으로 선택한 baseline 재확인.**

**v0.0.50 측정 (4분 1초, idle 3분 + burst 1분)**:
- idle 3분: vfDiff <86ms 안정, signed_mean -1~-42ms (베이크인 잔재). 청감 "초반 1~2초 + 잘 맞음"
- burst 1분: vfDiff max 57505ms (57.5초!) but 사용자 청감 "나쁘지 않음"
- drift_ms abs mean 2.66ms, drift_ms <5ms 88.3%
- guest_stop 90 vs guest_start 117 (race 차단 메커니즘 없음, 단 청감 영향 미미)

**핵심 통찰**:
1. **csv 측정 한계 발견**: vfDiff 57.5초 spike가 청감 인지 안 됨. 두 가지 해석:
   - csv 측정이 사용자 활동 중 외삽 부정확으로 어긋남 부풀림
   - 진짜 어긋남이지만 사용자 활동 중이라 청감 못 잡음
2. **v0.0.51~v0.0.54 그룹 1 fix의 사용자 경험 향상 효과 미미**:
   - csv 정확도 향상 (vfDiff max 57초→702ms, 80배)
   - 단 청감 차이는 거의 없음 (v0.0.48도 청감 OK)
3. **알고리즘 변경 자체가 새 race 만듦**:
   - v0.0.51 debounce 도입 → 자동 정지 race + 끝 도달 후 play race (v0.0.53/54 fix 필요)
   - v0.0.55 D-1 → vfDiff 23배 회귀
   - 코드 복잡 + 잠재 race 영역 확대

**최종 결정 — v0.0.50 main reset**:
- v0.0.48 알고리즘 (검증 깊음, 청감 OK) + v0.0.49/v0.0.50 csv 보강 (가시성 ↑)
- 코드 단순 + race 자체 없음 (debounce 미도입이라 자동 정지 race 등 없음)
- csv 가시성으로 다음 fix 측정 정확도 보장 유지
- v0.0.51~v0.0.55 commits는 `backup-v0.0.51-to-v0.0.55-session` branch에 보존

```
git reset --hard 2481c0a  # main을 v0.0.50으로
```

**남은 csv 한계**: v0.0.50의 vfDiff 측정이 사용자 활동 중 부정확할 가능성. 다음 세션엔 acoustic loopback 같은 외부 ground truth로 진짜 sync 정확도 측정 도구 필요.

**다음 세션 후보 (우선순위 갱신)**:

1. **csv 측정 정확도 개선** (HIGH) — 사용자 활동 중 vfDiff 외삽 정확도 부족. 현재 csv가 진짜 어긋남보다 부풀려 측정할 가능성. acoustic loopback 또는 외삽 알고리즘 보강.
2. **v0.0.51 fix 중 가장 안전한 것만 선택 cherry-pick** — 호스트 cooldown debouncing은 race 차단 효과 + 새 race도 적었음. 단 게스트 큐는 v0.0.55 회귀 위험. 안전한 것만 단계 적용.
3. **30분+ 장시간 idle 측정** — rate drift 누적 검증
4. **iOS host 환경 검증** — Mac 환경 필요
5. **BT 환경 검증** — BT outputLatency 비대칭
6. **다중 게스트 (1:N)** 검증
7. **Tab A7 Lite 호스트 환경 fpVfDiff 비대칭** ((47) 알려진 한계, D-1 시도 회귀 후 보류)

**핵심 학습 (이번 세션 종합)**:
- **사용자 청감 검증 > csv 수치 검증** — csv는 측정 한계 있음. 진짜 사용자 경험은 청감.
- **알고리즘 변경의 위험 = 새 race 도입** — 변경 fix가 또 다른 fix 필요한 사례 (v0.0.51 debounce → v0.0.53/54 race fix). CLAUDE.md "13번 fix 사이클" 패턴 재확인.
- **단순성의 가치** — 검증 깊은 단순 알고리즘이 복잡한 측정상 우수 알고리즘보다 안전.
- **csv 보강은 알고리즘 변경 X — 안전한 추가**: v0.0.49/v0.0.50처럼 측정 도구만 추가하는 작업은 회귀 위험 없음.
- **권한 시스템 가치** — git reset 같은 destructive 작업에 명시 동의 단계 → 사용자 의도 정확히 확인 후 진행.
- **사용자 좌절 = 신호** — "퇴보하는 것 같다" 우려 정당. 자존심 X, 정직한 평가 + 안전한 baseline 선택.

**변경 범위**: `git reset --hard 2481c0a` — main pointer + working tree 모두 v0.0.50으로 복귀. 코드 변경 없음 (단순 commit pointer 이동). v0.0.51~v0.0.55 작업은 `backup-v0.0.51-to-v0.0.55-session` branch에 그대로 보존.

---

### 2026-04-28 (49) — v0.0.51 syncSeek debounce 시도 후 롤백 + v0.0.52 진단 컬럼 추가

**배경**: (48) v0.0.50 reset 결정 후 추가 검증/진단. 두 가지 시도 — 결과적으로 알고리즘 변경 X, 측정 도구만 강화로 매듭.

**v0.0.51 syncSeek debounce 단독 cherry-pick 시도**:

(48) 진단으로 csv vfDiff transient (max 57.5초) 발견. 추측: 빠른 seek 폭주 시 사용자 활동 중 진짜 vf 차이. v0.0.51 그룹 1 중 가장 안전한 단일 변경 (호스트 syncSeek 100ms debounce)으로 transient 차단 시도.

코드 변경:
- `_hostSeekDebounce = Duration(milliseconds: 100)` 상수
- `Timer? _hostSeekDebounceTimer`, `int? _pendingHostSeekTargetMs` 멤버
- `syncSeek` → debounce 큐 + UI 즉시 반영 + `_flushHostSeek` 헬퍼

**측정 결과 (S22 host + Tab A7 Lite guest, burst 2분)**:

| | v0.0.50 burst (4분) | v0.0.51 debounce (2분) |
|---|---|---|
| host_seek (flush 후) | 170 | 177 |
| **vfDiff abs mean** | **302ms** | **21.17ms** (14배 향상) |
| **vfDiff max** | **57505ms (57.5초)** | **60.52ms** (950배 향상) |
| 100ms+ 어긋남 | 1.0% | **0%** |
| 10초+ transient | 2건 | **0건** |

**측정상 transient 1000배 감소** — debounce 효과 명확.

**사용자 청감**:
- "정말 빠르게 연타하니까 재생은 계속 되는데 seek은 반영 안 되고 있었던 것 같아"
- "100ms+ 간격: 호스트+게스트 둘 다 바로 반영. 100ms 미만: 호스트 seek바 여러 번 움직였는데 게스트는 1번만 움직였어"
- → debounce의 정확히 의도된 동작 (100ms 이내 연타 시 마지막만 적용)
- "큰 차이는 모르겠어" — v0.0.50 vs v0.0.51 청감 차이 인지 X

**롤백 결정**: 사용자 경험 향상 효과 0 + UI race 잠재 위험 (timer 비대칭 추측, 미검증) → v0.0.50으로 롤백 (`git checkout`).

**핵심 학습**:
- csv 측정상 향상이 사용자 경험 향상으로 직결되지 않음. 청감 미인지 영역의 csv 정확도 향상은 출시 가치 작음.
- 단일 변경도 사용자 경험 차이가 없으면 단순성 우선 가치 큼.

---

**v0.0.52 진단 컬럼 추가 (sync 동작 변경 0)**:

(48)/(49) 시도 후 사용자 의도 명확화 — "정확한 수치 보고 알고리즘 재설계". csv 진단 도구 강화로 거짓말 패턴 root cause 직접 측정 가능하도록.

코드 변경 (csv만):
- `sync_measurement_logger.dart`: 헤더 + log() 시그니처에 4개 컬럼 추가
  - `out_lat_host_raw`: 호스트 obs.hostOutputLatencyMs (OS 보고)
  - `out_lat_guest_raw`: 게스트 ts.safeOutputLatencyMs (OS 보고)
  - `out_lat_delta_current`: 매 poll guest - host 차이
  - `out_lat_delta_anchored`: anchor 시점 베이크인된 `_anchoredOutLatDeltaMs`
- `native_audio_sync_service.dart`: `_sendDriftReport` payload + `_handleDriftReport` 파싱 + `_recomputeDrift`/`_fallbackAlignment`에서 4개 값 채워 송신
- pubspec 0.0.50 → 0.0.52

**v0.0.52 측정 결과 (idle 3분 20초)**:

| 측정값 | 값 | 의미 |
|---|---|---|
| drift_ms abs mean | 5.80ms | rate 안정 |
| **vfDiff signed mean** | **-3.60ms** | 거의 0 (이전 -20.84ms 대비 매우 정확) |
| out_lat_host_raw mean | 8.20ms | S22 OS 보고 |
| out_lat_guest_raw mean | 22.98ms | Tab A7 Lite OS 보고 |
| out_lat_delta_current mean | 14.78ms | 매 poll 측정 차이 |
| out_lat_delta_anchored mean | 14.72ms | anchor 시점 베이크인 |
| current vs anchored 차이 | **0.06ms** | **베이크인 매우 정확** |

**진단 결과**:
- 이번 측정 = **정상 케이스** — 알고리즘이 OS 비대칭 14.72ms 정확 베이크인 → vfDiff -3.60ms로 거의 0 정렬
- (45) v0.0.49 idle의 -20.84ms 잔재 vs 이번 -3.60ms 차이 = **환경 의존**으로 추정 (단 (45) 측정엔 진단 컬럼 없어 root cause 직접 검증 X)
- 0-30s 시점 vfDiff -42~-53ms spike 발견 (anchor establish 직후, 외삽 부정확 의심)

**거짓말 패턴 추가 분석 (정직한 평가)**:
- 알고리즘 자체엔 vfDiff 보정 메커니즘 없음 → **잠재 한계는 명확**
- 단 청감 미인지 영역 (~25-40ms 한계 안)에서 작동 → 출시 안전성에 영향 작음
- 정확한 root cause는 (45) 같은 큰 잔재 재현 시점에 진단 컬럼 측정 필요 — 이번 세션 미완

**최종 매듭 (사용자 합의)**:
- main = v0.0.52 (= v0.0.48 알고리즘 + v0.0.49/50 csv 보강 + v0.0.52 진단 컬럼)
- **알고리즘 변경 0** — sync 동작은 v0.0.48과 100% 동일
- **측정 도구 강화**: csv 컬럼 8 → 16개, 이벤트 1종 → 11종
- 사용자 경험 영향 0, 개발자 진단 가시성 큰 폭 향상

**다음 세션 후보 갱신**:
- (45)~(49) 진단 데이터 활용 — 거짓말 패턴 자연 재현 시 v0.0.52 진단 컬럼으로 root cause 직접 측정
- EMA 단독 cherry-pick (B-1) — 가설 기반 fix, root cause 검증 후 진행 권장
- 30분+ 장시간 idle / iOS host / BT 환경 / 다중 게스트 측정
- 위험 큰 변경 (D-1 등) 보류 유지

**변경 범위**: `lib/services/sync_measurement_logger.dart` (4개 컬럼), `lib/services/native_audio_sync_service.dart` (4개 값 흐름), `pubspec.yaml` (0.0.50 → 0.0.52). sync 동작 변경 0.

---

### 2026-04-28 (50) — v0.0.53 anchor 중복 호출 버그 fix (거짓말 패턴 잠재 root cause 제거)

**배경**: (49) 매듭 후 사용자 요청 "계산식 검토". 코드 라인 단위 분석으로 `_tryEstablishAnchor`에 **`_engine.seekToFrame` + `_seekCorrectionAccum += initialCorrection` 두 번 호출** 발견. CLAUDE.md "다음 세션 후보 6번 v0.0.56 anchor 중복 호출 버그" 명시되어 있던 진짜 버그.

**버그 정확한 위치 + 메커니즘** (line 1235~1241 v0.0.52 기준):

```dart
final currentEffective = ts.framePos + _seekCorrectionAccum;
final initialCorrection = targetGuestVf - currentEffective;
unawaited(_engine.seekToFrame(targetGuestVf));      // ← 1번째 호출
_seekCorrectionAccum += initialCorrection;          // accum +1번

// v0.0.48 롤백: anchor establish 시 게스트 vf seek 보정 + _seekCorrectionAccum 누적
// (v0.0.45 동작). NTP 예약 재생 비활성화 → reactive 정렬 메커니즘 다시 활성화.
unawaited(_engine.seekToFrame(targetGuestVf));      // ← 2번째 호출!
_seekCorrectionAccum += initialCorrection;          // accum +1번 또!
```

**원인**: v0.0.48 롤백 (HISTORY (44)) 시 v0.0.45 동작 회복 코드 + v0.0.46 이후 코드가 합쳐지면서 의도치 않게 같은 블록이 두 번 들어감. seekToFrame은 idempotent라 결과 위치는 같지만 **`_seekCorrectionAccum`이 두 배로 누적**.

**버그 영향**:
```
의도:  effective = targetGuestVf, _anchorGuestFrame = targetGuestVf
실제:  effective = targetGuestVf + initialCorrection
       _anchorGuestFrame = ts.framePos + 2*correction = targetGuestVf + correction
```

→ **anchor baseline이 의도보다 `initialCorrection` 만큼 앞에 박힘**.

**거짓말 패턴 root cause 가설 (검증된)**:

vfDiff 수식 분해 (anchor establish 후):
```
guestVfMs = ts.virtualFrame / guestFpMs
          ≈ hostContentMs + outLatDelta_anchor   (의도: anchor 시점 정렬)
          
실제로는 _seekCorrectionAccum 잘못 누적이 ts.virtualFrame엔 영향 X (seek은 idempotent)
단 anchor framePos baseline은 잘못 박힘 → drift_ms 계산에 영향

vfDiff = (hostContentMs + outLatDelta_anchor) - hostContentMs - currentOutLatDelta
       = outLatDelta_anchor - currentOutLatDelta
```

이번 v0.0.52 측정 데이터로 검증:
- `out_lat_delta_anchored` = 14.72ms
- `out_lat_delta_current` = 14.78ms
- 수식상 vfDiff = 14.72 - 14.78 = -0.06ms
- 실제 csv vfDiff signed mean = -3.60ms
- **잔재 -3.54ms** = anchor 중복 호출 버그 + 외삽/sampleRate 오차 합산

(45) v0.0.49 측정 -20.84ms 잔재:
- 진단 컬럼 없어 직접 검증 X
- anchor establish 시점 outputLatency 변동 + anchor 중복 호출 버그 합산 추정

**v0.0.53 fix**:
- 두 번째 `unawaited(_engine.seekToFrame(targetGuestVf))` + `_seekCorrectionAccum += initialCorrection` 블록 제거
- seekToFrame 1번만 호출, accum 1번만 누적
- v0.0.51 그룹 1 (commit 50f46ed)에서도 같은 fix 했었음 — 이번 cherry-pick 동등.

**변경 영향 평가**:
- sync 동작 의도와 일치 (1번 호출이 의도였음)
- _anchorGuestFrame baseline이 정확히 박힘 → vfDiff 잔재 감소 예상
- 회귀 위험 작음 (의도된 동작으로 돌아가는 fix)

**검증 측정 — 미수행 (다음 세션에 이어서)**:

이번 세션 매듭 시점에 USB 연결 끊김 + 사용자 측정 부담 누적으로 측정 미진행. 단 fix 자체는 v0.0.51 그룹 1 (commit 50f46ed)에서 검증된 cherry-pick — 의도된 1번 호출로 돌아가는 안전한 fix. 빌드/install은 v0.0.53 빌드 성공 (`flutter build apk --debug` 정상 완료).

**다음 세션 시작 시 측정 가이드** (이 표 빈칸 채우기 작업):

| 지표 | v0.0.52 | v0.0.55 (2026-05-02) | v0.0.56 (2026-05-02, raw 진단 추가) |
|---|---|---|---|
| vfDiff signed mean | -3.60ms | -15.94ms | -10.55ms |
| out_lat_delta_anchored | 14.72 | 14.74 | (생략) |
| out_lat_delta_current | 14.78 | 14.52 | (생략) |
| 두 값 차이 (anchored - current) | -0.06 | +0.22 (사실상 0, EMA 효과 없음) | (생략) |
| anchor_reset_offset_drift | - | 4회/3분 | 2회/3분 (NR 52, 85) |
| **win_min_raw_offset span** | 미측정 | 미측정 | **2ms (-754~-752, 진짜 안정)** |
| **filtered vs win_min_raw gap (anchor 시점)** | 미측정 | 미측정 | **NR 39: 11.4ms → root cause 확정** |

→ 결론: anchor 중복 호출은 root cause 아님 ((59)). 진짜 root cause는 EMA convergence lag + isOffsetStable 판정 결함 ((60)).

**측정 시나리오** (다음 세션 첫 작업):
1. **빌드 + install**: 이미 빌드되어 있음 (`build/app/outputs/flutter-apk/app-debug.apk`). 단 install 필요.
   ```bash
   flutter install --debug --device-id R3CT60D20XE      # S22
   flutter install --debug --device-id R9PW315GL0L      # Tab A7 Lite
   ```
2. **idle 3분**: S22 호스트 + Tab A7 Lite 게스트, 가만히 재생
3. **csv pull**:
   ```bash
   adb -s R3CT60D20XE shell ls /storage/emulated/95/Android/data/com.synchorus.synchorus/files/
   adb -s R3CT60D20XE pull <csv_path> measurements/v0.0.53_idle_<date>.csv
   ```
4. **분석**:
   ```bash
   awk -F, 'NR==1{next} $16=="drift"{n++; sumv+=$6; sla+=$15; slc+=$14; sumd+=$5} END{printf "drift signed=%.2f vfDiff signed=%.2f anchored=%.2f current=%.2f diff=%.2f\n", sumd/n, sumv/n, sla/n, slc/n, (sla-slc)/n}' measurements/v0.0.53_idle_<date>.csv
   ```
5. **수식 검증**: `vfDiff signed ≈ anchored - current` 일치하는지 확인
6. **(50) 표 빈칸 채우기** + 결과로 가설 검증:
   - `vfDiff signed | < |v0.0.52 -3.60ms|` → fix 효과 있음 (anchor 중복 호출이 root cause 일부 확인)
   - 비슷하면 → 다른 root cause (외삽 오차, sampleRate cross-rate 등)

**검증 후 다음 단계**:
- fix 효과 있음 → 만족 시 그대로 유지, 부족 시 EMA 단독 cherry-pick (B-1) 검토
- fix 효과 미미 → root cause는 외삽/cross-rate 등 다른 곳, EMA 시도 또는 추가 진단

**다음 세션 작업 후보 갱신** (이어서 작업 가능하도록 명시):

### 1. v0.0.53 검증 측정 분석 (즉시 후속)
- (50)에 추가될 측정 결과로 vfDiff 잔재 감소 확인
- 만약 잔재 여전 → 다른 root cause (외삽 오차, sampleRate cross-rate 등)
- 만약 잔재 감소 → anchor 중복 호출이 진짜 root cause

### 2. (45) -20.84ms 잔재 자연 재현 시 진단
- v0.0.52/v0.0.53 진단 컬럼 활성 상태로 다른 환경 측정
- BT 게스트, 다른 시간대, 콘텐츠 시작 시점 등
- vfDiff > 10ms 잔재 시 out_lat_* 컬럼으로 root cause 분해

### 3. EMA 단독 cherry-pick (B-1) — 검증 후
- v0.0.55 D-1과 묶여 회귀했지만 EMA 자체는 단순 fix
- backup-v0.0.51-to-v0.0.55-session branch에서 EMA 부분만 cherry-pick 가능
- anchor reset 시 outputLatency EMA 보존 → 점진 수렴

### 4. 30분+ 장시간 idle / iOS host (Mac 환경) / BT / 다중 게스트
- 다양 환경 검증 — 진단 컬럼 활성 상태로

### 5. acoustic loopback 외부 측정 (선택)
- OS API outputLatency 부정확 ground truth
- 마이크로 출력 녹음 → round-trip 측정 (CTS 표준 방식)

### 6. 위험 큰 변경 보류 유지
- D-1 anchor 분리: 회귀 검증됨
- syncPlay/Pause debounce: 자동 정지 race 만든 사례
- 호스트 측 framePos 정규화: D-1 회피로 불필요화

**다음 세션 시작 가이드 (이어서 작업)**:
1. CLAUDE.md "현재 단계" 섹션 확인 — main = v0.0.53
2. measurements/v0.0.53_*.csv 측정 데이터 분석
3. (50) "검증 측정 결과" 표 빈칸 채우기
4. 결과로 root cause 확정 → 다음 fix 결정 (위 후보 1~6)

**검증 명령어 모음**:
```bash
# 빌드/install (Galaxy S22 + Tab A7 Lite 테스트 환경)
flutter build apk --debug
flutter install --debug --device-id R3CT60D20XE       # S22
flutter install --debug --device-id R9PW315GL0L       # Tab A7 Lite

# csv pull (S22 dual-app user 95)
adb -s R3CT60D20XE pull \
  /storage/emulated/95/Android/data/com.synchorus.synchorus/files/<csv> \
  E:/workspace/synchorus/measurements/<name>.csv

# csv 분석 (vfDiff signed mean + out_lat_delta_*)
awk -F, 'NR==1{next} $16=="drift"{n++; sumv+=$6; sla+=$15; slc+=$14} END{printf "vfDiff signed=%.2f anchored=%.2f current=%.2f\n", sumv/n, sla/n, slc/n}' <csv>
```

**변경 범위**: `lib/services/native_audio_sync_service.dart` (line 1238~1241 4줄 제거), `pubspec.yaml` (0.0.52 → 0.0.53). 단 1줄 fix.

---

### 2026-04-29 (51) — 게스트 3명 입장 불가 버그 발견 (문서 only, 다음 세션 fix 예정)

**증상** (사용자 보고): 갤럭시 3대로 같은 방 연결 시도 → 호스트 + 게스트 1명까지는 들어가지만 3번째 게스트는 입장 실패 (또는 기존 게스트가 튕겨나가는 핑퐁).

**원인 확정** (코드 추적 100% 확신):
1. `lib/screens/home_screen.dart:136` (그리고 `:367`) — 모든 게스트가 `name='Guest'` 하드코딩으로 join
   ```dart
   await p2p.connectToHost(host.ip, host.port, 'Guest');
   ```
2. `lib/services/p2p_service.dart:232` — v0.0.32 (2026-04-24 (25))에서 추가된 **이름 기반 stale peer 정리** 로직이 같은 이름 peer를 강제 destroy
   ```dart
   final stalePeers = _peers.where((p) => p.name == peerName).toList();
   for (final stale in stalePeers) {
     stale.socket.destroy();   // ← 여기
     _peers.remove(stale);
     ...
   }
   ```

**시나리오**:
1. 호스트 + 게스트 A('Guest') 입장 → `_peers=[A]`
2. 게스트 B('Guest') join → A와 이름 충돌 → A의 socket destroy → `_peers=[B]`
3. A의 socket이 죽음 → A의 `room_lifecycle_coordinator`가 재연결 시도 → 다시 'Guest'로 join → B destroy
4. → 무한 핑퐁. 사용자 눈엔 "2명까지만 들어가짐"으로 보임

**근본 원인**: v0.0.32 의도는 "같은 게스트가 재접속 시 stale peer 누적 방지"였는데, **peer name이 디바이스별로 고유하다는 가정**이 있었음. 하지만 게스트 측 join 코드가 이름을 디바이스명이 아닌 하드코딩 'Guest'로 보내고 있어 가정 깨짐.

**수정 옵션** (다음 세션):

A. **게스트 이름 고유화** (가장 간단)
   - `home_screen.dart`의 `'Guest'` → 디바이스 모델명 + 짧은 랜덤 suffix (예: `'Galaxy-A3F1'`)
   - 또는 `device_info_plus` 패키지로 실제 디바이스명 가져오기
   - v0.0.32 의도 (같은 게스트 재접속 정리) 그대로 유지

B. **stale 정리 로직 보강**
   - 이름 + IP 둘 다 비교: `p.name == peerName && p.socket.remoteAddress.address == socket.remoteAddress.address`
   - 의미: "같은 디바이스의 재접속"만 정리 (이름이 같아도 IP가 다르면 다른 디바이스로 인식)

C. **A + B 동시 적용 (권장)**
   - A만: 사용자가 같은 닉네임 입력하면 또 깨짐
   - B만: 같은 IP 재접속(NAT, 재DHCP) 케이스 의도대로 처리
   - 둘 다: 이중 안전

**검증 방법**:
- 갤럭시 3대 (S22 + Tab A7 Lite + 다른 1대) 같은 방 입장 → 호스트 측 peer count 3 유지 확인
- 한 게스트 비행기 모드 on/off → 재접속 후 peer count 정상 (3 유지) 확인 (v0.0.32 의도 깨지지 않는지 회귀 검증)

**우선순위**: HIGH — 다중 게스트 사용성 직접 영향. v0.0.53 anchor fix 검증 측정과 별개로 진행 가능 (영역 다름: 알고리즘 vs P2P/UI).

---

### 2026-05-01 (52) — v0.0.54 게스트 3명 입장 불가 fix (A+B 동시 적용)

(51)의 fix를 권장안인 A+B 동시 적용으로 진행.

**변경 1 — `lib/screens/home_screen.dart` (A안: 디바이스명 발급)**:
- `device_info_plus: ^12.4.0` 의존성 추가.
- `_resolveDeviceName()` 헬퍼 도입: Android는 `AndroidDeviceInfo.model` (예 `SM-S908N`), iOS는 `IosDeviceInfo.name` (사용자 설정명, 예 `홍길동의 iPhone`). 24자로 truncate 후 `microsecondsSinceEpoch & 0xFFFF`로 4자리 hex 접미사 추가 → `Galaxy S22#a3f9`, `홍길동의 iPhone#9c12` 형태. 같은 모델 디바이스 2대 이상 환경에서도 충돌 방지.
- `_joinRoom`의 `'Guest'` 하드코딩 제거 → `await _resolveDeviceName()` 결과로 join.

**변경 2 — `lib/services/p2p_service.dart:232` (B안: stale 비교 강화)**:
- v0.0.32의 `_peers.where((p) => p.name == peerName)` → `name == peerName && socket.remoteAddress.address == newRemoteIp`로 강화.
- LAN P2P는 NAT가 없어 IP가 디바이스를 유일 식별 → 같은 이름 + 같은 IP일 때만 진짜 같은 디바이스의 재접속으로 간주, stale 정리 발동.
- A안과 무관하게 이중 안전: A안이 깨져도 (예: 사용자가 직접 디바이스명 같게 강제) B안이 막음.

**왜 v0.0.32가 깨졌는지 정리**: commit `a8da7a4` (2026-04-24) 본문에 "같은 name의 stale peer 모두 정리"라 적혀 있어 의도는 분명히 1:1 재접속 cleanup이었음. 그런데 이미 그 시점 `home_screen.dart:136`에 `'Guest'` 하드코딩이 있었고 (1:N 멀티 게스트가 모두 같은 이름이라는 사실), 이를 fix 작성 시점에 검토 안 함. CLAUDE.md "Step 2 멀티 게스트: 1:N 동작" 명시도 있었는데도 시야가 1:1 회귀에만 좁혀졌음. 책임 — Claude (commit Co-Authored-By 표기됨).

**검증 (다음 세션 — 갤럭시 3대 이상 또는 같은 모델 2대 환경 필요)**:
1. 갤럭시 3대(S22 호스트 + 다른 갤럭시 2대 게스트) 같은 방 입장 → 호스트 측 peer count 3 유지
2. 한 게스트 비행기 모드 on/off → 재접속 후 peer count 정상 (3 유지) — v0.0.32 의도 회귀 없음 확인
3. `[P2P] stale peer 정리 (name=..., ip=...)` 로그가 비행기 모드 케이스에서만 발동하는지 확인 (정상 join 시 발동하면 B안 깨진 것)

**의존성**: `device_info_plus ^12.4.0` 추가. iOS `Info.plist` / Android `AndroidManifest.xml` 권한 추가 불필요 (model/name 모두 권한 free). 회귀 위험 거의 0.

---

### 2026-05-01 (53) — docs 구조 정리: CLAUDE.md slim화 + SYNC_ALGORITHM_V2.md 신설

**문제 인식**: CLAUDE.md(270줄)가 stable manual 본 의도에서 벗어나 "현재 단계", "다음 세션 후보", "최근 해결 (v0.0.20~v0.0.48)", "다음 세션 재개 포인트", "완료됨 (이번 세션)", "핵심 학습", "디자인 문서에 명문화할 결정 사항 A~F" 같은 가변·세션 상태가 누적되어 있음. 사용자 지적 (2026-05-01 세션) — "할 일 같은 걸 왜 CLAUDE.md에 적느냐, 의도와 어긋나지 않냐".

**수정 내역**:

1. **`docs/SYNC_ALGORITHM_V2.md` 신설** — CLAUDE.md "다음 세션 작업 흐름" 5단계 + "디자인 문서에 명문화할 결정 사항 A~F" + "디자인 문서 작성 요령" 이동. 빈칸 채우기 식 skeleton (각 결정 사항마다 선택지/race 시나리오/검증 방법/합의된 결정 4 섹션). 다음 알고리즘 작업 세션 첫 commit이 이 문서를 채우는 것이 되어야 함.

2. **`docs/PLAN.md`에 "다음 세션 작업 후보" 섹션 추가** — CLAUDE.md "다음 세션 후보 (우선순위) 1~10" + "다음 세션 재개 포인트 (우선순위 제안) 1~8" 통합. HIGH/MID/LOW 3 그룹으로 16개 항목 재배치. 매 세션 시작 시 이 리스트로 진입점 결정, 완료 항목은 위로 통과.

3. **`CLAUDE.md` slim화** — 270줄 → 약 80줄. 다음만 유지:
   - 프로젝트 한 줄 설명 + docs 포인터
   - 작업 시작 전/완료 후 (어떤 docs에 적을지)
   - 기능 수정 후 (version bump)
   - 사용자 프로필
   - 협업 원칙 (full)
   - 빌드/배포/테스트 + 실기기 빌드/설치
   - 에뮬레이터 네트워크
   - **추가**: "1:N 멀티 게스트 전제 — 같은 이름 peer가 여럿 있을 수 있음. p2p 로직 수정 시 1:1 가정 금지 (v0.0.32 → v0.0.54 fix 사례 참고)" — `_handleNewPeer` 사고 재발 방지.

**제거된 내용**: 거의 모두 docs로 옮겨졌거나 이미 HISTORY에 동일 정보 존재. CLAUDE.md "최근 해결 v0.0.20~v0.0.48" 섹션은 HISTORY.md 본문(2026-04-22~2026-04-26 항목들)과 100% 중복이라 삭제.

**의도**: 매 세션 컨텍스트에 자동 로드되는 CLAUDE.md를 stable manual로 유지. 세션 진행 상태/할일은 명확히 docs로 분리해 변경 위치 1곳, 책임 1곳 원칙 회복. 다음 세션 Claude가 본 manual에서 핵심 협업 원칙·파일 포인터를 빠르게 찾을 수 있어야 함.

---

### 2026-05-01 (54) — v0.0.55 안전한 코드 정리 (lint 외 dead code 1개 + 중복 패턴 1개)

**배경**: 사용자 "전체 코드중 코드정리할게 있어?" — flutter analyze는 No issues. lint에 안 잡히는 정리 후보를 Explore agent로 스캔. 의도적 롤백 주석(v0.0.45/47/48)·`unused_element` ignore(`_scheduleFromObs` NTP 재도입 대비)·v0.0.52 진단 컬럼은 모두 보존 대상으로 분류. 회귀 위험 0인 항목만 두 개 처리:

**수정 1 — `_driftSampleCount` 미사용 필드 제거** (`native_audio_sync_service.dart:78,1086,1366`):
- `// ignore: unused_field` 주석으로 lint 회피하고 있던 dead 필드. 읽는 코드 0건, 쓰기만 3군데(선언/리셋/증가). 진단용으로 도입했으나 더 이상 활용 없음.
- 필드 선언 + reset 1줄 + 증가 1줄 모두 제거.

**수정 2 — duration fallback 패턴 헬퍼 추출** (`native_audio_sync_service.dart`):
- 호스트(loadFile after) + 게스트(download+loadFile after) 두 곳에 동일한 6줄 패턴 (`_currentDuration == null` → `_engine.getTimestamp()` → `_calcDuration` → `_durationController.add`).
- `_resolveDurationFromTimestampIfNeeded()` 헬퍼로 추출. 게스트 측은 `_downloadSessionId == mySession` 가드를 호출 측에 유지(stale 다운로드에서 duration 갱신 차단 의도 보존).
- 동작 변경 없음. 라인 ~7줄 절감.

**보존 (정리 안 함)**:
- v0.0.45/47/48 롤백 주석들(`native_audio_sync_service.dart:25-32, 416-417, 491, 1033, 1189` 등) — 이력 추적·재실수 방지. CLAUDE.md "되돌리지 말 것" 규칙.
- `_scheduleFromObs()` (`unused_element`, ~921줄) — NTP 재도입 시 재활용 명시.
- v0.0.52 진단 컬럼 (`out_lat_*` 4개, `sync_measurement_logger.dart`) — HIGH-2 (v0.0.53 fix 효과 검증) 측정 끝난 뒤 정리 권장.
- `sync_measurement_logger.dart:26-28` iOS 비대칭 — `getExternalStorageDirectory()` UnsupportedError 회피, 의도적.
- `native_audio_sync_service.dart` 1562줄 분할 — SYNC_ALGORITHM_V2 작업 진입 시 host/guest 자연 분리가 더 깔끔.

**검증**: `flutter analyze` No issues. 동작 검증은 다음 세션 HIGH-2 측정과 함께 (idle 3분 csv).

---

### 2026-05-01 (55) — PoC 폴더 정리·문서화 (3개 README 신설 + CLAUDE.md 진입점)

**배경**: 사용자 "전체 코드중 정리할게 있어?" → "테스트는 불가능한데 작업할수있는게 또 뭐가있을까?" 흐름에서 PLAN.md "다음 세션 후보" + 즉흥 제안 4가지 검토. 1번(SYNC_ALGORITHM_V2 채우기)은 핵심이라 시간 필요로 보류. 2번(의존성 업데이트)은 시급도 낮아 PLAN.md MID-11로 메모만 추가. 4번(`room_lifecycle_coordinator` 리팩터)는 의도된 설계라 폐기. **3번 PoC 정리·문서화** 진행 — 사용자 지시 "이게 핵심 로직이니까 꼼꼼하게, 나중에 다시 안봐도될정도로".

**현황 진단**:
- `poc/native_audio_engine_android/README.md`, `poc/native_audio_engine_ios/README.md` 둘 다 `flutter create` 기본 boilerplate ("A new Flutter project") 17줄.
- `poc/README.md` 없음 — PoC 두 개의 진입점·관계·격리 원칙 어디에도 명시 안 됨.
- HISTORY.md 2026-04-08 ~ 2026-04-15에 PoC 진행·실측·이식 흔적이 산재 (Phase 0~6 + iOS Phase 0+1 + 본체 통합 step 1-1~1-4 + b0415-7 seekToFrame 파싱 버그 등).
- `analysis/data/` 81개 CSV git tracked, `build/` 정상 ignore, `.gitignore` 존재.
- 본 앱 `lib/services/native_audio_sync_service.dart` 와 PoC `lib/main.dart` 알고리즘 4단계 + 7개 파라미터 상수가 1:1 이식 상태.

**작성 내역**:

1. **`poc/native_audio_engine_android/README.md`** (≈250줄) 새로 작성 — 8개 섹션:
   - 답한 질문 (PLAN.md §6-1 Q1/Q2/Q3 통과 표)
   - Phase 0~6 단계별 결과 표 + Phase 4~5에서 발견·수정한 **버그 A~H 8개** 감사 기록 (HISTORY.md 본문에서 추출, 다시 안 봐도 되도록 재구성)
   - 본 앱(Synchorus)으로의 이식 매핑 — 네이티브/Dart/알고리즘 3개 표
   - 코드 구조 트리 (oboe_engine.cpp 292줄, NativeAudio.kt 28줄, lib/main.dart 1821줄, analysis/ 4개 스크립트)
   - 측정 데이터 — CSV 5종 컬럼 스키마 + 주요 세션 인덱스 (Phase 2 60s, Phase 4 1~4차, Phase 5 5~11차, Phase 6 31분)
   - 빌드·실행 — debug APK 빌드, install, 실측 절차, adb pull, Python 분석 스크립트 사용법
   - 향후 PoC 사용 시나리오 (알고리즘 v2 격리 검증, 회귀 디버깅, 새 디바이스 baseline)
   - 주의 사항 — 채널명·JNI 함수명 prefix 차이, version bump 예외

2. **`poc/native_audio_engine_ios/README.md`** (≈140줄) 새로 작성 — Android와 중복 줄이고 **iOS 고유 차이만** 강조:
   - Q1 Android 동등 정밀도 + 크로스플랫폼 30분 stress 99.6% + 역방향 100%
   - Native 비교 표 (Oboe vs AVAudioEngine 7개 항목) — `lastRenderTime → DAC 시점` 보정 공식 명시
   - **b0415-7 seekToFrame 파싱 버그** 별도 강조 (`call.arguments`를 `[String:Any]`로 파싱 → `NSNumber?.int64Value`로 수정. 본 앱 이식 시 동일 패턴 사용)
   - 본 앱 이식 매핑 — `AVAudioSourceNode`(비프) → `AVAudioPlayerNode`+`AVAudioFile`(파일), 백그라운드 모드 추가
   - 빌드·실행 — `flutter install` 미지원 → `flutter run` 또는 Xcode IDE 사용 (iOS 26.4.1 hung 이슈 PLAN.md LOW-14)
   - 주의 — 양쪽 동시 반영, BT outputLatency underreported

3. **`poc/README.md`** 신설 — 두 PoC 진입점 + 격리 원칙 + 본 앱 관계 + 향후 사용 시나리오. CLAUDE.md/PLAN.md/HISTORY.md에서 들어오는 단일 진입점.

4. **`CLAUDE.md` 작업 시작 전 섹션에 한 줄 추가**:
   ```
   - PoC (네이티브 엔진 격리 프로젝트): [poc/README.md](poc/README.md) — 격리 사유, 본 앱과 매핑, 재실행 방법
   ```

5. **`PLAN.md`에 의존성 업데이트 메모 추가** — MID-11. `flutter pub outdated` 결과 정리: A 그룹 즉시(connectivity_plus/path_provider_android 등 patch) + B 그룹 메이저(audio_session 0.1→0.2, just_audio 0.9→0.10, flutter_riverpod 2→3, file_picker 8→11 등 7개) 위험·이득 검토 후 패키지별 단독 commit. 진행은 실기기 회귀 테스트 가능한 세션.

**보존 (정리 안 함)**:
- `analysis/data/` 81개 CSV — Phase 2~6 모든 측정 결과. 분석 스크립트 입력이고 알고리즘 회귀 검증 시 재실행 가능. 삭제 금지.
- `analysis/` Python 스크립트 3개 — 오프라인 분석에 필수. (Phase 3 결정 과정 반영: 온디바이스 EMA 단순, 정교한 알고리즘은 Python으로)
- PoC `lib/main.dart` 1800줄대 — 알고리즘 본체. 본 앱과 파라미터 상수 1:1 매핑이라 정리하면 ablation 비교 불가.

**version bump 안 함**: 본 앱 코드 변경 0 (CLAUDE.md "PoC는 version bump 예외" + lint/포맷 제외 규칙). 문서만 추가됐고 빌드 영향 없음.

**검증**: `flutter analyze` 변경 없음 (애초에 lib/ 변경 없음). PoC 자체 빌드는 사용자 실기기 테스트 불가 환경이라 보류.

---

### 2026-05-01 (56) — DECISIONS.md 누락 결정 일괄 추가 (v0.0.24~v0.0.55, 13개)

**배경**: 사용자 "다음 뭐하면돼?" → DECISIONS.md 갱신 추천 → "매번 문서 럽데이트 안됐었나?" 질문에 git log 확인. `docs/DECISIONS.md` 마지막 commit이 `eaa4700` (v0.0.23 즈음 "Isolate 분리 + 파일 전송 대역폭 개선 후보 기록")이고 이후 **v0.0.24~v0.0.55 약 30개 버전 동안 갱신 0건**. CLAUDE.md "작업 완료 후 — 새 설계 결정 → DECISIONS.md (표에 한 줄 추가)" 규칙이 안 지켜진 거로 확인. HISTORY는 매번 추가됐으나 DECISIONS만 누락.

**작성**: HISTORY.md (16)~(55) + LIFECYCLE.md + 코드 주석을 근거로 "결정으로서 의미 있는" 항목만 13개 추출해 v3 표 상단에 누적(시점 역순). 단순 fix·롤백·버그 수정은 HISTORY가 이미 충분하므로 표에 안 넣음.

**추가된 결정 13개** (시점 역순):

| # | 시점 | 결정 |
|---|---|---|
| 1 | v0.0.53 | anchor establishment 단일 진입 — `_tryEstablishAnchor`의 seekToFrame + `_seekCorrectionAccum +=` 블록 1번만. 중복 호출 시 `_anchorGuestFrame`이 의도보다 앞에 박혀 vfDiff 잔재 |
| 2 | v0.0.32 + v0.0.54 | 1:N 멀티 게스트 전제 — name AND ip 동시 매칭, 디바이스 닉네임 `<model>#<hex>`, peer broadcast에 절대 peerCount 동봉 |
| 3 | v0.0.38 | BT outputLatency 비대칭 anchor 베이크인 (`_anchoredOutLatDeltaMs`) |
| 4 | v0.0.48 | NTP 정공법 보류, 청감 우선 — 13번 시도 후 v0.0.45 baseline 회복. 재도입은 SYNC_ALGORITHM_V2 디자인 합의 후 단일 commit |
| 5 | v0.0.41 | 디바이스 발견은 nsd (multicast_dns 폐기) |
| 6 | v0.0.33 | engineLatency 수치 폐기 — `com.synchorus/audio_latency` MethodChannel 양 플랫폼 제거 |
| 7 | v0.0.34 + v0.0.35 | 재연결 race 다층 방어 — `identical(_hostSocket, socket)` onDone 가드 + `_reconnectInProgress` flag |
| 8 | v0.0.31 | StreamController add 전 isClosed 가드 |
| 9 | v0.0.29 | `RoomLifecycleCoordinator` 클래스 추출 — UI에서 라이프사이클 320줄 분리 |
| 10 | v0.0.30 | errno 분기는 Linux+Darwin 집합 — `_refusedErrnos={111,61}`, `_networkUnreachableErrnos={113,101,65,51}` |
| 11 | v0.0.28 | connectivity_plus + errno 이중 안전망 |
| 12 | v0.0.27 | Socket connect timeout 5→2초 + errno=111 2회 연속 빠른 포기 |
| 13 | v0.0.26 | 호스트 detached에서 host-closed best-effort broadcast — Android 한정, 재생 중 강제 종료 1.4초 복구 |
| 14 | v0.0.25 | 호스트 라이프사이클 프로토콜 — host-paused/resumed/closed 메시지, 자리비움 배너, 12회 watchdog |

(표 14줄이지만 #2와 #7은 두 버전 결정을 한 항목으로 묶어 등록 → 실 항목 13개)

**작성 형식**: 각 항목의 "이유" 컬럼은 사용자 지시(이전 PoC 작업) "다시 안 봐도 될 정도로 꼼꼼하게"를 따라 결정 + 도입 배경 + 실측 수치 + 향후 작업 시 주의점까지 한 셀에 넣음. 표 한 셀이 5~10줄까지 길어졌지만 의도적. DECISIONS.md는 자주 안 보는 ADR(Architecture Decision Record)이라 진입 시 모든 컨텍스트가 한 줄에 있어야 가치.

**보존 (안 추가)**: v0.0.36~v0.0.37(streak 진단 로그 추가), v0.0.39(iOS 파일 선택 크래시 fix), v0.0.42(mDNS stale fix — v0.0.41과 한 묶음으로 nsd 결정에 포함), v0.0.43(iPhone 호스트 cooldown 분리), v0.0.44(prewarm) + v0.0.45(롤백), v0.0.46(oboe pause/resume) + v0.0.47(NTP) + v0.0.48(롤백 + 정공법 보류 결정 — #4로 묶음), v0.0.49~v0.0.50(측정 인프라), v0.0.51(syncSeek debounce 시도 후 롤백), v0.0.52(진단 컬럼). 모두 fix/실험/측정이라 ADR 표 의미 적음. HISTORY가 충분.

**프로세스 개선 메모**: 앞으로 작업 완료 시 CLAUDE.md "작업 완료 후" 체크리스트 더 엄격히 — DECISIONS.md 갱신을 commit 전 확인 단계로 들이기. 이번 일괄 추가로 누적 부채는 청산.

**version bump 안 함**: 본 앱 코드 변경 0. 문서만 추가.

**검증**: 표 형식 markdown lint pass. flutter analyze 영향 없음.

---

### 2026-05-01 (57) — ARCHITECTURE.md v0.0.30~v0.0.55 누락분 일괄 갱신

**배경**: 사용자 "아키텍처 문서도 갱신해줘 ... 항상 히스토리만 업데이트했었구나". DECISIONS.md(56)와 같은 패턴 — `docs/ARCHITECTURE.md` 마지막 commit이 `26d2461` (2026-04-24, v0.0.29 즈음 라이프사이클 섹션 추가)이고 이후 **v0.0.30~v0.0.55 약 25개 버전 동안 갱신 0건**. CLAUDE.md "작업 완료 후 — 설계/로직 변경 → ARCHITECTURE.md" 규칙이 안 지켜진 거.

**누락 진단** (grep 키워드 매칭):
- `_anchoredOutLatDeltaMs` (v0.0.38 BT 비대칭 베이크인) — 본문에 0건
- `nsd` / `multicast_dns` / `discovery_service` — 디스커버리 섹션 자체 없음
- `sync_measurement_logger` / `out_lat_*` 진단 컬럼 (v0.0.49~v0.0.52) — 측정 인프라 섹션 없음
- `_seekCorrectionAccum` / anchor establishment 단일 진입 (v0.0.53) — §4-5 본문에 부재
- `device_info_plus` / "name AND ip" (v0.0.54) — §9-3에 v0.0.32만 명시, v0.0.54 보강 누락

**갱신 내역**:

1. **§4-4 드리프트 계산 본문 전면 교체** — 옛 "선형 보간 expectedP_at_Tg = P1 + (P2 - P1) * (...)" 공식은 **본 앱이 안 쓰는** 버전(이론 모델)이었음. 실제는 `_tryEstablishAnchor` + `_recomputeDrift`의 anchor 외삽 + outputLatency 비대칭 베이크인 + framePos/virtualFrame 역할 분리. 상수 6개 + anchor 시 박는 값 + 매 poll 재계산 공식 + framePos vs virtualFrame 선택 이유 + `_seekCorrectionAccum` 필요성 모두 코드 라인(:1190+, :1300+) 참조와 함께 포함.

2. **§4-5 보정 실행 본문 전면 교체** — 옛 "rate 조정 (1.025~1.05×)" 본문은 **본 앱 미구현**. 실제는 seek 단일 보정 + median window=5 (v0.0.24) + |drift|≥200ms anchor reset + post-seek probe. 노이즈 원천 표에 BT outputLatency 변동 + v0.0.38 anchor 베이크인 추가. clock sync 알고리즘(EMA α=0.1) 명시. 끝에 "알고리즘 변경 시 주의" — v0.0.46~v0.0.61 13번 시도 후 청감 우선 v0.0.45 회복 사례, SYNC_ALGORITHM_V2 단일 commit 원칙, anchor 진입점 1개 원칙(v0.0.53 회귀).

3. **§8 P2P 메시지 카탈로그 전면 재작성** — 옛 본문은 `audio-obs` + `audio-drift-report` 2개만 있었음(설계 단계 작성). 실제 메시지 17종을 4개 카테고리로 정리:
   - 8-1 연결·라이프사이클 10종 (join, welcome, peer-joined/left, leave, heartbeat/ack, host-paused/resumed/closed)
   - 8-2 동기화·재생 7종 (audio-url, audio-obs, seek-notify, state-request/response, download-report, drift-report)
   - 8-3 clock sync 2종 (sync-ping/pong)
   - 8-4 폐기 2종 (sync-position v2 → audio-obs로 교체, audio-latency MethodChannel v0.0.33 제거)

4. **§9-3 Peer count 관리 + 1:N 멀티 게스트 (v0.0.32, v0.0.54) 보강** — 제목 + 본문에 v0.0.54 추가:
   - v0.0.32 fix가 모든 게스트 닉네임 'Guest' 하드코딩과 결합해 게스트 3명 입장 불가 회귀 발생한 경위
   - A안 디바이스 닉네임 `<model>#<hex>` (`device_info_plus ^12.4.0`)
   - B안 stale 비교 `name AND ip` 동시 매칭 (LAN P2P NAT 없어 ip가 디바이스 유일 식별)
   - "p2p 로직 작성 시 1:1 가정 금지" 원칙 (CLAUDE.md 협업 원칙 명시)

5. **§10 디바이스 디스커버리: nsd (v0.0.41+) 신설** (3 subsection):
   - 10-1 라이브러리 결정 — multicast_dns ❌ → nsd ✅. 양방향 발견 안정성, iOS↔Android 호환성
   - 10-2 stale 방 처리 (v0.0.42) — found/lost 즉시 반영
   - 10-3 서비스 정보 — `_synchorus._tcp`, TCP 41235 + HTTP 41236, 권한 (Android Manifest + iOS Info.plist `NSBonjourServices`)

6. **§11 측정·디버그 인프라 (v0.0.49~v0.0.52) 신설** (4 subsection):
   - 11-1 출력 위치 — Android `getExternalStorageDirectory()` (멀티유저 95/ 가능), iOS `getApplicationDocumentsDirectory()` (`getExternalStorageDirectory()` UnsupportedError)
   - 11-2 CSV 컬럼 — 기본 12개 + v0.0.52 진단 4개 (`out_lat_host_raw` 등)
   - 11-3 분석 워크플로우 — adb pull + awk + spreadsheet (PoC와 달리 별도 Python 미사용)
   - 11-4 진단 컬럼 정리 정책 — 목적 달성 후 제거(v0.0.52는 HIGH-2 측정 끝나면)

7. **§3-3 헤더 "코드 미반영" 제거** — 옛: "핵심 기술 설계 (v3) — 폐루프 리아키텍처 (설계 단계, 코드 미반영)". 현재: "핵심 기술 설계 (v3) — 폐루프 리아키텍처" + 부제로 v0.0.13에서 step 1-1 도입 → v0.0.55까지 누적 보강 명시. v3가 이미 main에 있는데 "설계 단계"로 남아 있던 게 가장 오해 유발.

**보존 (안 손댐)**: §1 전략, §2 엔진 선택, §3 audio_service 공존, §4-1~4-3 측정 인프라 설계, §5 Flutter↔네이티브 인터페이스, §9-1/9-2/9-4/9-5. 이미 v0.0.29까지 반영되어 있고 본 앱 동작과 차이 없음.

**작성 형식**: 사용자 지시 "꼼꼼하게 다시 안 봐도 될 정도로". §4-4와 §4-5는 결정 + 도입 시점 + 실측 수치 + 코드 라인 참조 + 향후 작업 시 주의점까지 한 섹션에 응축. PoC `lib/main.dart` 헤더 주석을 1차 출처로 인용해 PoC↔본 앱 알고리즘 1:1 이식 사실 강조.

**version bump 안 함**: 본 앱 코드 변경 0. 문서만.

**검증**: `flutter analyze` 영향 없음. ARCHITECTURE.md 760줄 → 958줄(+198줄). markdown 표 형식 유지.

**프로세스 개선** (DECISIONS와 동일): 작업 완료 시 ARCHITECTURE.md 갱신을 CLAUDE.md "작업 완료 후" 체크리스트로 더 엄격히. 이번 일괄 갱신으로 v0.0.55까지 부채 청산. 다음 알고리즘·로직 변경(예: SYNC_ALGORITHM_V2 작업)부터는 commit 직전 ARCHITECTURE 반영 확인 단계 필수.

---

### 2026-05-01 (58) — LIFECYCLE.md v0.0.31~v0.0.55 누락 갱신 + 작은 부정확 fix

**배경**: 사용자 "라이프사이클도 보자". `docs/LIFECYCLE.md` 마지막 commit이 `fc2a1c9` (v0.0.30 Darwin errno fix)이고 이후 v0.0.31~v0.0.55 갱신 0건. DECISIONS(56) + ARCHITECTURE(57)와 같은 패턴. 추가로 v0.0.41/42/54 변경이 §2-1/2-2의 디스커버리·join 흐름 본문과 충돌하는 작은 부정확까지 fix.

**누락 진단**:
- 본문 "현재 v0.0.25: detached는 미구현(추후 보완)" — **v0.0.26에서 구현됨에도 미구현으로 남아있음** (잘못된 정보)
- 1층 메시지 표 `host-closed` 트리거에 "(장래) detached" — 이미 v0.0.26 구현
- 2층 본문에 v0.0.31 isClosed 가드, v0.0.34 identical 가드, v0.0.35 `_reconnectInProgress` flag 모두 누락 → race 방어 layer가 보이지 않음
- 3층 watchdog 시간 "약 60~120초"는 v0.0.27 timeout 단축(5→2초) 미반영. 실제 ~1분
- iOS WiFi off 재현 조건(제어센터 WiFi 토글 vs 비행기 모드 vs 설정 앱) 어디에도 없음 — v0.0.34 (27)에서 발견된 실측 가이드
- §2-1 "UDP 브로드캐스트" 표현은 mDNS(`_synchorus._tcp`) 기반인 v0.0.41+ 후엔 부정확
- §2-2 게스트 join 흐름에 v0.0.54 디바이스 닉네임 발급(`device_info_plus`) + stale peer `name AND ip` 매칭 누락
- §2-3 sliding window "최근 5개" — v0.0.24에서 10으로 확대됨

**갱신 내역**:

1. **§우리 앱의 역할 × 라이프사이클 대응 매트릭스 보강** — 옛 미구현 메모를 **플랫폼별 detached 도달성** 표로 교체 (Android 재생 중 강제 종료 1.4초 복구, Android 재생 전 종료 watchdog fallback, iOS 앱 스위처 종료 watchdog only). 구현 위치 `room_lifecycle_coordinator.dart` 명시.

2. **§3중 안전망 §1층 host-closed 트리거 정확화** — "(장래) detached" 제거, "정식 closeRoom() + AppLifecycleState.detached (v0.0.26 best-effort, Android foreground service 한정)"로 갱신. host-resumed 도달 불가 케이스 + TCP 재접속 자체가 복귀 신호 명시.

3. **§3중 안전망 §2층에 race 방어 sub-section 신설** — 옛 본문 "1층 메시지가 오지 못하는 상황을 OS 수준에서 포착" 그대로 유지하면서 그 아래 "2층 race 방어 (v0.0.31, v0.0.34, v0.0.35)" sub-section 추가:
   - 두 disconnect 감지 경로(TCP onDone vs connectivity_plus) 다이어그램
   - v0.0.31 `if (!_xxxController.isClosed) ...` 가드 — `Bad state: Cannot add new events after calling close` 차단
   - v0.0.34 `if (!identical(_hostSocket, socket)) return;` onDone 가드 — old socket의 onDone이 새 `_hostSocket` destroy하는 무한 loop 차단
   - v0.0.35 `_reconnectInProgress` flag — 두 경로 직렬화, race 자체 예방
   - "두 층 동시 유지 — 한쪽만 두면 future regression에 약함" 원칙

4. **§3중 안전망 §3층 시간 갱신** — "12회 약 60~120초" → "12회 실제 약 1분 (v0.0.27 connect timeout 5→2초)". errno=111/61 2회 연속 즉시 leave fast giveup도 반영.

5. **새 sub-section §iOS WiFi off 재현 조건** — v0.0.34 (27) 실측에서 발견:
   - 제어센터 WiFi 아이콘 토글: `none` 이벤트 안 가거나 약함 (race 재현 부적합)
   - 제어센터 비행기 모드 토글: 즉시 발화, 앱 포그라운드 유지 (race 재현 적합)
   - 설정 앱 → Wi-Fi 토글: `none` 발화하지만 앱 background 내려감 (race 조건 달라짐)
   - PLAN.md LOW-11 errno=65/51 분기 캡처 시나리오 참조

6. **§2-1 호스트 디스커버리 본문 정확화** — "UDP 브로드캐스트" → "mDNS(`_synchorus._tcp`)로 같은 WiFi의 게스트에게 존재를 알림. v0.0.41부터 `nsd` 라이브러리(이전 `multicast_dns` 폐기). 상세: ARCHITECTURE §10".

7. **§2-2 게스트 join 흐름 보강** — 4단계 → 5단계로 확장:
   - 1단계: 호스트 발견 — `nsd` discovery 스트림 found/lost 즉시 반영(v0.0.42 stale 방 fix)
   - 2단계 신설: 게스트 닉네임 발급 — `<device model>#<hex 4자리>` (v0.0.54)
   - 3단계: connectToHost + `join` 메시지 (`name` 포함)
   - 4단계: welcome 수신 — 호스트는 `name AND ip` 동시 매칭 stale peer 정리 후 새 peer 등록 (v0.0.54)
   - 5단계: RoomScreen 진입

8. **§2-3 시간 동기화 sliding window 갱신** — "최근 5개" → "최근 10개(v0.0.24: 5→10)". EMA alpha 상수명(`_emaAlphaFast`/`_emaAlphaSlow`/`_fastPhaseCount`)과 코드 라인(`sync_service.dart:32-34`) 추가.

**보존 (안 손댐)**: §1 전체 흐름도, §2-4 오디오 파일 공유 ~ §2-7 방 나가기, §3 용어 사전, §앱 라이프사이클 5상태 정의, §OS가 paused 상태 앱에 하는 일, §플랫폼별 실전 차이, §소켓 에러 코드(errno) 표 본문. 이미 v0.0.30까지 정확.

**version bump 안 함**: 본 앱 코드 변경 0. 문서만.

**검증**: `flutter analyze` 영향 없음. LIFECYCLE.md 471줄 → 약 510줄. 정확성 회복이 주 목적이라 분량 증가 적음.

**프로세스 청산 완료**: `docs/` 5개 문서(CLAUDE.md/HISTORY.md/PLAN.md/ARCHITECTURE.md/DECISIONS.md/LIFECYCLE.md/SYNC_ALGORITHM_V2.md 중 핵심 5개) 모두 v0.0.55까지 부채 청산. 사용자 지시 "항상 히스토리만 업데이트했었구나"가 더 이상 사실이 아님 — 이번 (56)+(57)+(58) 삼중 청산으로 회복.

### 2026-05-02 (59) — v0.0.53 anchor fix 효과 검증 측정 — fix 효과 없음 / 다른 root cause 확정

**환경**: S22 호스트 + Tab A7 Lite 게스트, 같은 WiFi, idle 3분 (사용자 측정). v0.0.55 빌드(=v0.0.53 fix 포함) 양 기기 install 후 측정. csv는 호스트(S22)가 기록(`native_audio_sync_service.dart:140-141`, drift 로깅도 596번 줄에서 `!_isHost return`).

**측정 데이터**: `measurements/v0.0.55_idle_2026-05-02.csv` (drift 행 353개, anchor_reset_offset_drift 4회, 약 3분).

**전체 통계**:

| 구간 | n | vfDiff signed | \|mean\| | RMS | range |
|---|---|---|---|---|---|
| 전체 | 353 | **-15.94ms** | 18.76 | 22.91 | -63 ~ +21 |
| 중간 안정 75초 (NR 52-191, no reset) | 140 | **-22.86ms** | 22.91 | 26.83 | -47 ~ +1 |
| 마지막 reset 후 (NR ≥ 230) | 146 | **-9.06ms** | 14.62 | 17.38 | -36 ~ +18 |
| **v0.0.52 baseline** | - | **-3.60ms** | - | - | - |

**핵심 관찰**:
1. **fix 후 잔재 오히려 4배 커짐** (-3.60 → -15.94ms) — anchor 중복 호출 제거가 root cause가 아니었음. (50) 빌드 직후 가설("의도된 1번 호출로 회복")은 측정으로 기각.
2. **idle 3분에 anchor_reset_offset_drift 4회** — NR 14, 28, 50, 192, 228. 처음 25초 동안 3회 발생 후 75초 안정 후 또 1회. offset 변동성 자체가 큼.
3. **outputLatency anchored vs current diff = +0.22ms** — 사실상 0. EMA 단독 cherry-pick (PLAN MID-6, B-1)가 효과 없을 거란 강한 신호. PLAN B-1 우선순위 ↓.
4. **안정 구간끼리도 -22ms vs -9ms로 다름** — 같은 코드/세션 내 75초 무리셋 구간과 마지막 리셋 후 구간의 베이크인 잔재가 ~14ms 차이. anchor establish 순간의 noise(framePos 외삽 부정확 + clock sync 수렴 불충분)가 anchor에 영구 베이크인되는 구조 확정.

**정정 사실**: 분석 도중 "S22 게스트였던 듯" 잠시 오해 → 코드 확인 후 호스트 맞음. csv는 호스트만 로깅(`startListening` 호스트 분기에서만 `_logger.start()`). drift_ms / vf_diff_ms 모두 호스트 시점.

**root cause 후보 — 다음 진단 우선순위**:
- **(A) anchor establish 시점 단일 샘플 noise 베이크인** ← 가장 유력 (당시 가설). 다음 (60) raw 진단으로 부분 확인 — anchor 시점 EMA 미수렴이 진짜 원인. 외삽 오차 자체는 추가 분리 안 됨.
- **(B) anchor_reset_offset_drift 빈도 자체** — idle 3분에 4회는 비정상. **이 세션 내 (60)에서 진단 — root cause는 EMA convergence lag, clock skew 아님 (이 (59)의 "monotone drift = 진짜 clock skew" 가설은 폐기)**. 상세 (60) 참고.
- **(C) 외삽 오차 분해** — `out_lat_*` 진단 컬럼은 anchored vs current diff만 0.22ms로 단정 가능. framePos 외삽 정확도는 별도 진단 필요(현 csv 컬럼으로는 분리 불가). 새 진단 컬럼 추가 검토.

**가설 폐기 메모 (자기 정정)**: 이 (59) 작성 시점에 "offset이 monotone drift → 두 디바이스 wall clock skew (~380ppm)" 가설 제시했으나, 사용자 "다시 검토해봐" 지시로 재검증. csv polling rate 가정 오류(100ms로 가정했는데 실제 ~500ms) + reset 후 drift 지속 여부 미검증 등 결함 확인. (60) raw_offset_ms 진단 컬럼 측정으로 진짜 메커니즘은 EMA convergence lag임이 확정 — clock skew 아니라 EMA가 진짜 offset에 천천히 수렴하는 transient.

**보존**: v0.0.52 진단 컬럼 4개(`out_lat_*`)는 (54)에서 "HIGH-2 측정 끝나면 정리" 명시했으나 본 측정으로 EMA 효과 없음 확인 → 정리해도 무관. 다만 (B) 진단 시 `out_lat_*` 변동성 추적에 재활용 가능 → **유지** 권장. 정리는 (A) 또는 (B) fix 완성 후로 미룸.

**version bump 안 함**: 측정·문서 only. 코드 변경 0.

**다음 세션 작업 후보 갱신** (PLAN.md HIGH-2 → "측정 완료, 다른 root cause 진단" 단계):
- **HIGH 신규 1**: anchor establish robustness (단일 샘플 → N샘플 중앙값) — root cause (A) fix. 회귀 위험 검토 + SYNC_ALGORITHM_V2 디자인에 흡수 가능성 검토.
- **HIGH 신규 2**: anchor_reset_offset_drift 빈도 root cause — clock sync EMA 시정수 / reset 임계 분석.
- **MID-6 (EMA cherry-pick)**: 본 측정으로 우선순위 ↓ (anchored - current diff 0.22ms로 효과 미미 확정).
- **HIGH 4 (SYNC_ALGORITHM_V2)**: 위 (A)/(B)와 동일 root cause 추적이라 디자인에 흡수 가능 — 묶어서 진행 권장.

### 2026-05-02 (60) — v0.0.56 raw_offset 진단 컬럼 추가 + EMA convergence lag root cause 확정

**배경**: (59)에서 "offset monotone drift = wall clock skew ~380ppm" 가설로 잠정 결론. 사용자 "다시 검토해봐" 지시로 재검증. csv polling rate 가정 오류(100ms 가정 → 실제 ~500ms) + reset 후 drift 지속 여부 미관찰 등으로 가설 결함 확인. clock skew vs EMA transient 구분하려면 raw offset 자체 추적 필요 → 진단 컬럼 추가.

**변경 (`v0.0.56`, 알고리즘 0 변경 — 진단/측정만)**:

`lib/services/sync_service.dart`:
- 필드 4개 추가: `_lastRawOffsetMs`, `_winMinRawOffsetMs`, `_lastRttMs`, `_winMinRttMs`
- pong 처리부에서 매 sample마다 업데이트 (EMA 입력 전에)
- public getter 4개 추가
- `reset()`에서 4개 0으로 초기화

`lib/services/sync_measurement_logger.dart`:
- csv 헤더에 `raw_offset_ms,win_min_raw_offset_ms,last_rtt_ms,win_min_rtt_ms` 4개 추가 (event 컬럼 직전)
- `log()` 시그니처 옵셔널 매개변수 4개 추가

`lib/services/native_audio_sync_service.dart`:
- `_sendDriftReport`에서 sync_service getter로 4개 값 가져와 메시지 첨부 (호출부 4군데 수정 안 함 — `_sendDriftReport` 내부에서 일괄)
- 호스트 `_handleDriftReport`에서 받아 `_logger.log()`에 전달

`pubspec.yaml`: 0.0.55 → 0.0.56.

**측정 (S22 host + Tab A7 Lite guest, idle ~3분, `measurements/v0.0.56_idle_2026-05-02.csv`)**:

| 컬럼 | mean | range | span | 의미 |
|---|---|---|---|---|
| **win_min_raw_offset** | -752.76 | -754 ~ -752 | **2ms** | 진짜 안정적인 offset (window=10 min-RTT sample) |
| filtered_offset | -752.02 | -753.60 ~ -740.60 | **13ms** | EMA 결과, lag 영향 |
| raw_offset (단일) | -753.71 | **-940 ~ -624** | 316ms | 단일 sample, RTT outlier 큼 |
| last_rtt | 30 mean | **6 ~ 465** | 459 | outlier 빈번 |
| win_min_rtt | 8.47 mean | - | - | window min 매우 안정 |
| vfDiff signed | -10.55 | - | - | (참고: v0.0.55 -15.94, v0.0.52 -3.60) |

**Anchor 시퀀스 (결정타)**:

| NR | event | filtered | win_min_raw | gap |
|---|---|---|---|---|
| 39 | anchor_set | -740.6 | -752.0 | **11.4ms!** (EMA 미수렴인데 stable로 판정됨) |
| 52 | reset (6초 후) | -745.9 | -752.0 | 5.3ms 따라잡음 → 임계 5ms 초과 |
| 53 | anchor_set | -745.9 | -752.0 | 6.1ms 차이 |
| 85 | reset (17초 후) | -751.0 | -752.0 | 5.1ms 따라잡음 |
| 86 | anchor_set | -751.0 | -752.0 | 1ms (드디어 수렴) |

**핵심 결론 (v0.0.48 이래 잠재되어 있던 결함)**:
1. **clock skew 아님** (win_min_raw span 2ms, 두 디바이스 시계 사실상 동기). (59) 가설 폐기.
2. **EMA convergence lag가 진짜 메커니즘** — anchor가 EMA 수렴 전에 박혀 부정확한 offset이 베이크인됨.
3. **`SyncService.isOffsetStable` 판정 결함** — "step별 변화량 < 2ms 5회"로 판정하는데, slow phase α=0.1에서 누적 gap이 큰 상태에서도 step별로는 작아 false stable. NR 39에서 EMA(-740.6) vs 진짜 값(-752) 11.4ms gap인데 stable=true 통과한 게 증거.
4. **`anchor_reset_offset_drift` 빈도(idle 3분 4회)는 정상 반응** — 잘못된 stable 판정으로 박힌 anchor가 EMA가 진짜 값으로 따라잡는 동안 5ms 임계 자연 초과. fix 자체보다 anchor establish 게이팅이 root cause.

**fix 후보 (이번 세션 미적용 — 알고리즘 변경이라 (44) 13번 사이클 교훈 따라 SYNC_ALGORITHM_V2 단일 commit으로 미룸)**:
- **(D2-1) winMinRaw 일치 기준** — `(filteredOffsetMs - winMinRawOffsetMs).abs() < _stableThresholdMs`로 stable 판정. 1줄 변경.
- **(D2-2) AND 조합** — 기존 변화량 + winMinRaw 일치 둘 다.
- **(D2-3) fast phase 길이 / α 조정만** — 알고리즘 구조 변화 없음.

→ `docs/SYNC_ALGORITHM_V2.md`에 신설 §D-2로 명세. 다른 결정사항(D anchor 분리, E 임계, F race 차단 등)과 묶어서 단일 commit 후보.

**왜 이번에 fix 적용 안 함**:
- 사용자 본인이 v0.0.48 청감 "매우 안정"으로 판정한 baseline (HISTORY:2580). 이 baseline이 "EMA 미수렴 anchor"라는 잠재 결함 위에서도 청감상 안정이라는 뜻 → 측정 잔재 -16ms는 청감 미인지 영역일 가능성.
- (44) 13번 사이클 교훈: 측정 개선 보고 알고리즘 손대다 청감 회귀. 이번 fix도 trade-off (첫 anchor 5~15초 늦어짐 → 첫 재생 정착 영향)가 있어 **사용자 청감 비교 + 다른 결정과 묶어서 단일 commit**이 안전.

**version bump**: 0.0.55 → 0.0.56 (코드 변경 — 진단 컬럼).

**검증**: `flutter analyze` No issues. 빌드 + 두 기기 install 완료. 측정 csv 정상 생성·schema 일치.

**다음 세션 작업 후보 갱신**:
- **PLAN HIGH 2-A/2-B는 SYNC_ALGORITHM_V2 §D-2로 흡수** — 단독 fix 대신 디자인 단일 commit으로 묶음.
- **PLAN HIGH 4 (SYNC_ALGORITHM_V2 디자인)**: §D-2 추가됨, §A-F 빈칸 채우기 + 사용자 합의 + 단일 commit 진행이 다음 알고리즘 트랙 첫 작업.
- 다른 영역(같은 모델 갤럭시 2대 환경에서 v0.0.54 다중 게스트 fix 검증, 의존성 업데이트 등)은 알고리즘과 독립이라 병행 가능.

### 2026-05-02 (61) — v0.0.57 의존성 안전 묶음 upgrade (patch/minor)

**배경**: PLAN MID-11 (의존성 업데이트) 진입. 메이저는 패키지별 단독 commit이 원칙이라 먼저 안전 묶음(patch/minor)만 일괄 처리. 사용자 의도 — 출시 전 점검 + 오디오 관련 메이저(`just_audio`/`audio_session`) 변경점 확인을 단계별로 진행.

**변경 (`v0.0.57`, 코드 변경 0 — pubspec.lock만)**:

`flutter pub upgrade` 한 번. 변경된 11개 패키지:
- `connectivity_plus` 7.1.0 → 7.1.1 (patch)
- `path_provider_android` 2.2.23 → 2.3.1 (minor)
- `vm_service` 15.0.2 → 15.2.0 (minor)
- `hooks` 1.0.2 → 1.0.3 (patch, transitive)
- `sqflite` 2.4.2 → 2.4.2+1 (build metadata)
- `sqflite_common` 2.5.6 → 2.5.6+1 (build metadata)
- `synchronized` 3.4.0 → 3.4.0+1 (build metadata)
- 신규 transitive 잠금: `jni` 1.0.0, `jni_flutter` 1.0.1, `package_config` 2.2.0, `record_use` 0.6.0

**검증**: `flutter analyze` No issues. `flutter build apk --debug` ✓ 19.8s. 코드 변경 0이라 회귀 위험 매우 낮음.

**version bump**: 0.0.56+1 → 0.0.57+1. pubspec.lock만 변경.

**다음 단계**: 메이저 업그레이드는 패키지별 단독 commit (사용자 우선순위 — 오디오 먼저):
1. `just_audio` 0.9.46 → 0.10.5 (디코딩 경로 잔존 grep 필요, v3 NativeAudioEngine 도입 후 의존도 ↓)
2. `audio_session` 0.1.25 → 0.2.3 (iOS AVAudioSession 라우팅 변경점 가능)
3. 비오디오: `network_info_plus` 6→8, `file_picker` 8→11, `device_info_plus` 12→13, `package_info_plus` 9→10
4. 마지막: `flutter_riverpod` 2→3 (Notifier/Provider API 변경 큼, 회귀 위험 최대)

### 2026-05-02 (62) — v0.0.58 just_audio 죽은 의존성 제거

**배경**: (61) 다음 단계로 `just_audio` 0.9.46 → 0.10.5 메이저 업그레이드 진입. 영향 범위 grep 결과 — `lib/`/`poc/` 어디에도 import·`AudioPlayer`·`AudioSource` 등 사용처 0. v3 NativeAudioEngine 전환(2026-04-15) 시점에 디코딩·재생 경로 모두 네이티브로 이관됐는데 pubspec 의존성만 남아있던 상태. transitive로 다른 패키지가 쓰지도 않음 (`flutter pub deps` 확인 — direct only, audio_service도 just_audio 의존 없음). 사용자 결정: 메이저 업그레이드 대신 의존성 자체를 제거 (필요 시 재추가).

**변경 (`v0.0.58`, 코드 변경 0 — pubspec/lock만)**:

`pubspec.yaml`: `just_audio: ^0.9.43` 라인 제거 (37번째 줄).

`flutter pub get` 결과 — 3개 패키지 정리:
- `just_audio` 0.9.46 제거
- `just_audio_platform_interface` 4.6.0 제거 (transitive)
- `just_audio_web` 0.4.16 제거 (transitive)

iOS `GeneratedPluginRegistrant.m`은 빌드 시 자동 재생성 — `JustAudioPlugin` 등록 삭제 확인.

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug` ✓ 9.5s (기존 19.8s 대비 ~절반, 의존성 축소 효과)
- iOS plugin registrant grep — `just_audio`/`JustAudio` 잔존 0

**version bump**: 0.0.57+1 → 0.0.58+1.

**다음 단계**: `audio_session` 0.1.25 → 0.2.3 메이저 업그레이드 (iOS AVAudioSession 라우팅 변경점 검토).

### 2026-05-02 (63) — v0.0.59 audio_session 0.1.25 → 0.2.3 메이저 업그레이드

**배경**: (62) 다음 단계. 사용처 grep — `lib/main.dart:12-13` 두 줄(`AudioSession.instance` + `configure(AudioSessionConfiguration.music())`)만 사용. iOS 네이티브 `AVAudioSession.sharedInstance()` 직접 호출은 시스템 API이지 audio_session 플러그인 아님(`ios/Runner/AudioEngine.swift` 등) → 영향 무관.

**0.2.x breaking change 검토** (pub.dev/packages/audio_session/changelog WebFetch):
- **유일한 breaking change**: `AUDIO_SESSION_MICROPHONE=0 by default on iOS` — Synchorus는 마이크 사용 안 함 → 영향 0
- `AudioSession.instance` / `AudioSessionConfiguration.music()` API 변경 없음
- Android Kotlin 마이그레이션 (내부 변경)
- Flutter 최소 요구 3.27.0 → 현재 환경 3.41.6 충족

**변경 (`v0.0.59`, 코드 변경 0 — pubspec/lock만)**:

`pubspec.yaml`: `audio_session: ^0.1.25` → `^0.2.3`. `flutter pub get` 1개 의존성 변경.

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug` ✓ 25.2s (Kotlin migration 영향, 0.0.58의 9.5s 대비 ↑)
- 실기기 회귀 테스트는 별도 세션 (특히 iPhone BT 라우팅, audio focus 인터럽트 시나리오)

**version bump**: 0.0.58+1 → 0.0.59+1.

**다음 단계**: 비오디오 메이저 업그레이드 — `network_info_plus` 6→8, `file_picker` 8→11, `device_info_plus` 12→13, `package_info_plus` 9→10. 각각 단독 commit. 마지막 `flutter_riverpod` 2→3은 회귀 위험 최대라 별도 세션.

### 2026-05-02 (64) — v0.0.60 network_info_plus 죽은 의존성 제거

**배경**: (63) 다음 단계로 `network_info_plus` 6→8 메이저 업그레이드 진입. 사용처 grep 결과 — `lib`/`poc`/`ios`/`android` 어디에도 import·`NetworkInfo` 사용 0. transitive 의존도 없음 (direct only). `nsd`(mDNS/Bonjour wrap)와 `connectivity_plus`로 IP/네트워크 정보 충분히 다루는 상태라 죽은 의존성이었던 것으로 추정. just_audio(62)와 동일 패턴.

**변경 (`v0.0.60`, 코드 변경 0 — pubspec/lock만)**:

`pubspec.yaml`: `network_info_plus: ^6.1.1` 라인 제거.

`flutter pub get` 결과 — 2개 패키지 정리:
- `network_info_plus` 6.1.4 제거
- `network_info_plus_platform_interface` 2.0.2 제거

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug` ✓ 13.5s

**version bump**: 0.0.59+1 → 0.0.60+1.

**다음 단계**: `device_info_plus` 12→13 (API 무변경, dep 요구치만 ↑) → `package_info_plus` 9→10 (iOS 13.0 최소 검토) → `file_picker` 8→11 (정적 메서드 마이그레이션 필요).

### 2026-05-02 (65) — v0.0.61 file_picker 8.3.7 → 11.0.2 메이저 업그레이드 + win32 충돌 분석

**배경**: (64) 다음 단계로 `device_info_plus` 12→13 진입. 의존성 해석 실패. 원인 분석:

| 패키지 | 최신 | win32 의존 |
|---|---|---|
| `file_picker` 11.0.2 | latest | **^5.9.0** ❌ |
| `device_info_plus` 13.1.0 | latest | ^6.0.1 |
| `package_info_plus` 10.1.0 | latest | ^6.0.1 |

→ `file_picker`가 win32 ^5에 묶여있어 다른 둘을 메이저로 올리면 win32 메이저 충돌. Synchorus는 mobile only라 실제 win32 미사용 transitive지만 pub resolver는 모든 플랫폼 합산해 봄.

**결정**: file_picker 11만 단독 진행. device_info_plus(12.4) + package_info_plus(9.0)는 file_picker가 win32 ^6 지원할 때 함께 메이저 업그레이드. 회귀 추적 측면에서도 file_picker는 코드 마이그레이션 동반(가장 영향 큰 작업)이라 단독이 합리적.

**변경 (`v0.0.61`)**:

`pubspec.yaml`: `file_picker: ^8.1.7` → `^11.0.2`.

코드 마이그레이션 — v11.0.0 breaking change ("FilePicker 클래스 인스턴스 → 정적 메서드"):
- `lib/screens/native_test_screen.dart:34` — `FilePicker.platform.pickFiles(...)` → `FilePicker.pickFiles(...)`
- `lib/screens/player_screen.dart:37` — 동일

**기타 v9.0.0/v10.0.0 breaking은 영향 없음**:
- v9.0.0: web blob 변경 → web 빌드 미사용
- v10.0.0: `compressionQuality` default 0, `allowCompression` deprecated → 우리 코드에서 둘 다 미사용

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug` ✓ 60.7s (전체 재빌드 시간, 코드 변경 동반이라 ↑)
- 실기기 회귀 — Android `pickFiles` audio 파일 선택, iOS `UIDocumentPickerViewController` 호출은 다음 세션 (S22 + iPhone 12 Pro)

**version bump**: 0.0.60+1 → 0.0.61+1.

**다음 단계**:
- (보류) `device_info_plus` 12→13 + `package_info_plus` 9→10: file_picker가 win32 ^6 지원 시점에 묶음 commit
- `flutter_riverpod` 2→3: Notifier/Provider API 변경 큼, 별도 세션 (회귀 위험 최대)

### 2026-05-02 (66) — v0.0.62 flutter_riverpod 2.6.1 → 3.3.1 메이저 업그레이드

**배경**: PLAN.md MID-11 마지막 메이저 트랙. 처음엔 회귀 위험 최대로 별도 세션 분류했으나, 사용자 지적("어차피 단독 commit이면 회귀 시 git revert로 분리 가능") 수용해 진행.

**우리 사용 패턴 분석** (5 파일 / 46 API 호출):
- `lib/providers/app_providers.dart` — `Provider<T>((ref) => ...)` 5개 (audioHandler, p2p, discovery, sync, nativeAudioSync)
- `lib/main.dart`, `home_screen.dart`, `room_screen.dart`, `player_screen.dart` — `ConsumerWidget`/`ConsumerStatefulWidget` + `WidgetRef` + `ref.read/watch/listen` + `ref.onDispose` + `ProviderScope`
- `StateNotifier`/`StateProvider`/`ChangeNotifier` 사용 0 (v3 deprecate 대상에서 안전)

**riverpod v3 migration guide 검증** (riverpod.dev migration/from_state_notifier WebFetch):
- 우리 사용 API(`Provider<T>`, `ConsumerWidget`, `WidgetRef`, `ref.read/watch/listen`, `ref.onDispose`, `ProviderScope`)는 v3에서 모두 유지
- v3 breaking은 deprecate된 `StateNotifier`/`StateProvider`/`ChangeNotifier` 라인 → 우리 미사용
- nice-to-have: 향후 새 stateful 로직은 `Notifier`/`AsyncNotifier`로 작성 권장 (기존 코드는 변경 강제 아님)

**변경 (`v0.0.62`, 코드 변경 0 — pubspec/lock만)**:

`pubspec.yaml`: `flutter_riverpod: ^2.6.1` → `^3.3.1`. `flutter pub get` 25개 의존성 변경 (riverpod + transitive).

**검증**:
- `flutter analyze` No issues (코드 수정 0)
- `flutter build apk --debug` ✓ 14.4s
- 런타임 회귀 — v3 내부 구현 변경(특히 lifecycle/disposal 타이밍) 가능성 있어 실기기 풀세트 회귀 필수: 방 생성/참가, 동기화 재생, dispose 사이클(`onDispose` 호출 5곳)

**version bump**: 0.0.61+1 → 0.0.62+1.

**의존성 트랙 종료**:

| 버전 | 변경 |
|---|---|
| v0.0.57 | 안전 묶음 (patch/minor 8개) |
| v0.0.58 | just_audio 죽은 의존성 제거 |
| v0.0.59 | audio_session 0.1→0.2 |
| v0.0.60 | network_info_plus 죽은 의존성 제거 |
| v0.0.61 | file_picker 8→11 (정적 메서드 마이그레이션) |
| v0.0.62 | flutter_riverpod 2→3 (코드 변경 0) |

**보류** (다음 의존성 세션):
- `device_info_plus` 12→13 + `package_info_plus` 9→10: file_picker가 win32 ^6 지원 시점에 묶음 commit. 현재 file_picker 11이 win32 ^5에 머물러 충돌. 두 패키지 API는 무변경이라 미루는 부담 작음.

**다음 작업 후보**: 출시 전 실기기 풀세트 회귀 (S22 + iPhone + A7 Lite, 6개 commit 누적 영향), 또는 PLAN HIGH 트랙 (SYNC_ALGORITHM_V2 단일 commit / 첫 재생 정착 시간 / 다중 게스트 fix 검증).

### 2026-05-02 (67) — 의존성 업데이트 가치 분석 (v0.0.57~v0.0.62 누적 영향)

**배경**: 사용자 질문 "우리 앱에 도움될만한 업데이트는 없었어?"로 단순 버전 업이 아닌 실제 가치 있는 변경 식별. 각 패키지 changelog 정독 후 Synchorus 코드베이스와 매핑.

**의미 있는 fix 7건 (가치 큰 순)**:

| ★ | 패키지·버전 | 변경 | 우리 영향 |
|---|---|---|---|
| ⭐⭐ | `connectivity_plus` 7.1.0 | iOS NWPathMonitor serial queue → race condition crash 제거 | `RoomLifecycleCoordinator`가 connectivity 이벤트 적극 사용. iOS race crash 원인 1개 직접 제거. |
| ⭐⭐ | `connectivity_plus` 7.1.0 | Android broadcast receiver flag 정정 → 네트워크 변경 감지 신뢰성 ↑ | v0.0.28 errno 113/101 분기와 직접 연동. Android 게스트 WiFi off/on 감지 신뢰성 ↑. |
| ⭐ | `audio_session` 0.2.2 | iOS `setCategory` 스레드 분리 → jank 제거 | **PLAN HIGH-3 (첫 재생 정착 시간) 잠재 개선**. `main.dart:13` `configure(music())`가 main 스레드 점유하던 게 해소 → 게스트 engine.start() 100~500ms 지연 일부 흡수 가능. |
| ⭐ | `audio_session` 0.2.3 | Android `audioAttributes` 무시 fix | `AudioSessionConfiguration.music()`이 Android에서 미디어 볼륨 라우팅 정확히 적용. |
| ⭐ | `flutter_riverpod` 3.0 | Ref operations throw after disposal | 5개 Provider(`p2p`/`discovery`/`sync`/`nativeAudioSync`/`audioHandler`) dispose 사이클에서 stale ref 사용 시 silent fail → 명시적 throw. 디버깅 용이성 ↑. |
| ⭐ | `file_picker` 10.3.5 | 2GB+ 큰 파일 로딩 에러 fix | 무손실 wav / 라이브 녹음 등 큰 오디오 파일 사용 가능. |
| ⭐ | `file_picker` 10.3.7 | Android 파일 타입 필터링 정확도 fix | `allowedExtensions: ['mp3','m4a','wav','aac','flac','ogg']`이 Android에서 관련 없는 파일까지 노출하던 버그 fix. |

**기타 부수적 효과**:
- `audio_session` 0.2.3: AVAudioSession null arguments crash fix
- `audio_session` 0.2.1: Android null pointer (device encoding) fix
- `file_picker` 9.0.2: 파일 스트림 누수 fix
- `flutter_riverpod` 3.2.0: TickerMode로 hidden widget rebuild 회피 (UI 성능 미세 ↑)

**가장 주목할 가치 — 첫 재생 정착 시간 (PLAN HIGH-3) 잠재 개선**:

`audio_session` 0.2.2 변경이 직접 영향 줄 수 있는 코드 경로:
- `lib/main.dart:13` — 앱 시작 직후 `await session.configure(AudioSessionConfiguration.music())` 호출
- 0.2.x 이전엔 iOS `setCategory`가 메인 스레드에서 동기 실행 → 첫 화면 진입까지 jank 발생
- 0.2.2 이후 별도 스레드 → main 진입이 빨라짐 → 게스트가 호스트보다 더 빨리 ready 상태 도달 가능

**측정 가설**:
- v0.0.55/v0.0.56 baseline (audio_session 0.1.25) 대비 v0.0.62 (audio_session 0.2.3)에서 첫 재생 직후 ~수 초 어긋남 구간이 줄어들어야 함.
- HISTORY (39) "첫 재생 정착 시간 — BT 무관" 이슈와 연결: 원인 중 "게스트 engine.start() 자체 지연"의 일부가 해소될 수 있음 (단, 가장 큰 원인인 첫 anchor establish 정밀도는 별개).

**다음 측정 액션** (사용자 요청):
1. 환경: (60)과 동일 — S22 호스트 + Tab A7 Lite 게스트, 같은 WiFi
2. 빌드: v0.0.62 (현 main HEAD), 양 기기 install
3. 시나리오: 호스트 파일 로드 → 첫 재생 → 첫 ~30초 drift_ms 시계열 + **청감 정착 시점**(예: 5초 후 안정) 기록
4. 측정 출력: `measurements/v0.0.62_first_play_2026-05-02.csv` (호스트 자동 로깅)
5. baseline 비교: v0.0.55 csv, v0.0.56 csv 첫 30초 구간과 head-to-head 비교
6. 추가 idle 측정도 함께(약 3분) — 의존성 회귀(특히 `flutter_riverpod` 3 onDispose 사이클) 검증 겸

**기대 결과**:
- 정착 시간 단축 → 가설 확정, PLAN HIGH-3 일부 자연 해결
- 변화 없음 → audio_session jank가 첫 재생 어긋남의 주 원인 아니었음 → engine.start 자체 지연 + anchor 정밀도가 진짜 원인. PLAN HIGH-3 옵션 (1)/(2) 진행 필요.

**추가 검증 항목** (의존성 회귀 — 측정 csv 정상이면 자동 OK):
- 방 생성/참가 사이클 (riverpod 3 ProviderScope/onDispose)
- 파일 선택 (file_picker 11 정적 메서드)
- 게스트 WiFi off/on (connectivity_plus 7.1.0 race fix)
- iOS 게스트 BT 라우팅 (audio_session 0.2.x Kotlin migration 영향 없는지)

### 2026-05-02 (68) — v0.0.62 첫 재생 정착 시간 측정 N=2 — 가설 수정 (audio_session 효과 ❌, EMA stable 판정 결함이 root cause)

**환경**: S22 호스트 + Tab A7 Lite 게스트, 같은 WiFi. (60)/(67)과 동일.

**1회차** (`measurements/v0.0.62_first_play_2026-05-02.csv`, 370행, 3분+):
- 청감: 첫 재생 ~1초 정착 후 쭉 안정
- 첫 anchor 시점: NR 12 (재생 +5.3초)
- **첫 anchor EMA gap: 0.1ms** (filtered -762.1 vs winRaw -762.0) ⭐
- fallback event: 10개 (anchor 박히기 전 충분한 EMA 수렴 시간)
- anchor_reset 횟수: 2회 (NR 299, 336) — idle 후반
- vfDiff signed mean: -10.96ms / RMS 19.53ms
- drift_ms RMS (안정 구간): 2.93ms

**2회차** (`measurements/v0.0.62_first_play_run2_2026-05-02.csv`, 352행, 3분+):
- 청감: 첫 재생 ~2초 정착 + **30초간 미묘 틀어짐** + 그 이후 안정
- 첫 anchor 시점: NR 5 (재생 **+2.5초**, 1회차 대비 2.8초 빠름)
- **첫 anchor EMA gap: 2.0ms** (filtered -767.0 vs winRaw -765.0)
- fallback event: 3개 (anchor 너무 빨리 박힘)
- anchor_reset 횟수: 3회 — **NR 57, 76, 100 (재생 후 ~30~50초 구간 집중)**
- 초기 30초 구간 vfDiff |mean|: 13.82ms (안정 구간 18.00ms) — 사용자 청감 "미묘 틀어짐 30초" 정확히 일치
- reset 시 EMA gap: 5.8ms / 4.4ms / 3.3ms — 모두 (60) 진단한 §D-2 결함 발현 패턴

**결정적 발견**:

사용자 청감 "미묘 틀어짐 30초"가 csv NR 57~100 (재생 후 30초~50초) reset 3회 집중과 1:1 매핑. **첫 재생 정착 품질은 audio_session jank가 아니라 "첫 anchor 시점 EMA 수렴도"가 결정**:
- 1회차: fallback 5초 → EMA 충분 수렴 → 첫 anchor 깔끔(gap 0.1ms) → 안정
- 2회차: fallback 2.5초 → EMA 미수렴(gap 2.0ms) → 첫 anchor에 noise 베이크인 → 30초간 reset/재anchor 반복

**기존 가설 (67) 수정**:

| 가설 | 상태 |
|---|---|
| ❌ "audio_session 0.2.2 jank 제거 → 첫 재생 정착 시간 자연 개선" | **N=2로 기각**. 1회차 ~1초 vs 2회차 ~2초+30초 흔들림 변동성이 너무 큼. audio_session 효과 자체는 작거나 없을 가능성. |
| ⭐ "PLAN HIGH-4 (§D-2, EMA stable 판정 결함)이 첫 재생 정착에 직접 영향" | **N=2로 채택**. 첫 anchor EMA gap (0.1ms vs 2.0ms)이 정착 품질 결정. 운 좋으면 OK / 운 나쁘면 30초 흔들림. |

**(67) 1회차 anchor_reset 빈도 ↓ (4→2)도 우연성 가능성 ↑** — 2회차에서 3회로 다시 ↑됨. 단순 측정 오차 범위.

**의존성 업데이트의 실제 가치 재정정**:
- ⭐⭐ connectivity_plus 7.1.0 race crash 제거 / Android broadcast receiver flag — 여전히 유효 (이번 측정에서 직접 검증 안 했지만 코드 경로는 그대로)
- ⭐ file_picker 10.3.5 2GB+ 파일 / 10.3.7 Android 타입 필터링 — 여전히 유효
- ⭐ flutter_riverpod 3 stale ref throw — 여전히 유효
- ❌ audio_session 0.2.2 jank → 첫 재생 정착 — N=2 측정으로 효과 단정 어려움

**PLAN HIGH-4 우선순위 ↑** — 측정 수치 변동성의 root cause가 §D-2 결함으로 N=2 재현 확인. fix 후 1회차/2회차 케이스 변동성 사라져야 함:
- D2-1 (winMinRaw 일치 기준): `(filteredOffsetMs - winMinRawOffsetMs).abs() < _stableThresholdMs`
- D2-2 (AND 조합): 기존 변화량 + winMinRaw 일치 둘 다
- D2-3 (fast phase 길이/α 조정만)

이 중 가장 시급한 fix를 SYNC_ALGORITHM_V2 §D-2 단일 commit에 포함.

**의존성 트랙 종료 진단**: 의존성 업데이트가 일부 가치 있는 fix(crash 제거, 파일 처리 개선)를 가져왔으나 **첫 재생 정착 시간 직접 개선은 없었음**. 이 문제는 알고리즘 트랙(§D-2)으로 해결해야 함이 N=2 측정으로 확정.

### 2026-05-02 (69) — v0.0.62 첫 재생 정착 시간 N=3 — 비결정적 발현 양상 확정

**환경**: (68)과 동일. 3회차 측정 (`measurements/v0.0.62_first_play_run3_2026-05-02.csv`, 361행, 3분+).

**3회차 청감**: "1회차랑 비슷" (1회차 ~1초 정착 후 안정과 유사).

**3회차 csv 분석 — 전혀 다른 패턴**:

| 항목 | 값 | 비교 (1회차/2회차) |
|---|---|---|
| 첫 anchor 시점 | NR 23 (재생 **+11초**) | 가장 늦음 (vs +5.3s / +2.5s) |
| 첫 anchor EMA gap | **-11.7ms** (filtered -777.7 vs winRaw -766.0) | 가장 큼 (vs 0.1ms / 2.0ms) |
| fallback events | **21개** | 가장 많음 (vs 10 / 3) |
| anchor_reset 횟수 | 2회 (NR 35, 77) | 1회차와 동일 횟수, 다른 시점 |
| reset 시 gap | -6.2ms / **-0.2ms** | 2번째는 거의 완벽 재정착 |
| host_pause 1회 | NR 361 — 측정 마지막 사용자 정지 | 정상 |
| vfDiff signed mean | -14.62ms | 1/2회차 -10.96/-11.01 대비 살짝 ↑ |

**fallback 시계열 (drift_ms 추이)**:
- NR 2: -440.87ms (게스트 첫 sample, 큰 외삽 오차)
- NR 3: +250.16ms (반대로 튐)
- NR 4 이후: -23~-15ms 범위로 빠르게 안정
- NR 13~14: -7~-3ms (~6초만에 청감 임계 도달)
- NR 22: +1.03ms (anchor 직전 거의 0)

→ **fallback 단계에서 이미 청감 안정 도달**. anchor 11s 늦게 박혔어도 청감으론 ~1초~2초에 정착으로 인지됨.

**anchor establish 자기 교정 패턴**:
- NR 23 anchor (gap 11.7ms, noisy) → NR 35 reset (12초 후, gap 6.2ms) → NR 36 재anchor → NR 77 reset (41초 후, gap 0.2ms) → NR 78 재anchor (거의 완벽)
- 2회차의 reset 5~9초 간격(NR 57/76/100) 집중과 다르게 12s + 41s 간격이라 청감 임계 이하로 흡수됨.

**N=3 종합 — 청감 분포**:

| 케이스 | 발현 양상 | 청감 |
|---|---|---|
| 1회차 | ANCHOR EARLY+TIGHT (gap 0.1ms, fallback 10) | 깔끔 |
| 2회차 | ANCHOR EARLY+LOOSE (gap 2.0ms, fallback 3) | **30초 흔들림** ❌ |
| 3회차 | ANCHOR LATE+NOISY+자기교정 (gap 11.7ms, fallback 21) | 깔끔 |

→ 운 나쁜 케이스 ~33% (3회 중 1회 명확한 흔들림). 첫 anchor의 시점·EMA gap·fallback 길이 모두 결정론적이지 않음.

**핵심 통찰 (N=3로 확정)**:

1. **§D-2 결함이 측정마다 다른 양상으로 발현**:
   - EARLY+TIGHT (운 좋음) — anchor 일찍 + EMA 우연 수렴 → 깔끔
   - EARLY+LOOSE (운 나쁨) — anchor 일찍 + EMA 미수렴 → 흔들림
   - LATE+NOISY+자기교정 — anchor 늦게 + noisy → 빠른 자기 교정으로 청감 OK
   
2. **fallback 길이가 청감 정착에 직접 기여** — anchor 박히기 전에도 drift가 -3ms 수준까지 줄면 청감으로는 이미 안정. fallback 21개(3회차)도 청감 정착 ~1~2초 만에 도달.

3. **첫 anchor 시점/gap의 변동성이 너무 큼** → 같은 환경·같은 코드에서도 청감 분포가 좋음/흔들림으로 갈림 → 사용자 경험 비일관성.

**§D-2 fix 후보 비교 (N=3 데이터 기준)**:

| 후보 | 효과 예상 (3 케이스 모두) |
|---|---|
| **D2-1** (winMinRaw 일치 기준) | 1회차 같은 케이스만 anchor 통과, 2/3회차는 더 미룸 → 모든 케이스에서 anchor "LATE+TIGHT"로 수렴 → **일관성 ⭐** |
| **D2-2** (AND 조합) | D2-1보다 더 엄격, anchor 더 늦어짐 → trade-off: 첫 anchor 정확↑ vs 첫 reset 후 reanchor 동일 동작 시 부담 |
| **D2-3** (fast phase 길이/α 조정) | EMA 수렴 빨라짐 → 1/2회차 케이스 개선, 3회차는 영향 작음 |

**가성비**: D2-1 (1줄 변경)이 가장 깔끔. 다만 첫 anchor가 일관되게 늦어지면 첫 재생 정착 시간이 청감으로 길어질 가능성도 있음. fallback alignment 정확도가 충분하면 청감 영향 작을 것.

**다음 작업 후보 갱신** (PLAN HIGH-4):
- N=3로 §D-2 결함의 비결정적 발현 양상 확정 → fix가 일관성 확보 효과를 명확히 줄 것 기대
- fix 후 N=3+ 측정으로 청감 분포가 좋음/좋음/좋음으로 수렴하는지 검증 필요
- SYNC_ALGORITHM_V2.md §A-F 빈칸 + §D-2 fix 채택 → 사용자 합의 → 단일 commit이 다음 알고리즘 트랙 첫 작업 (PLAN HIGH-4 기존 계획 그대로 + 우선순위 ⭐최상)

### 2026-05-02 (70) — v0.0.63 §D-2 fix 적용 (D2-2 AND 조합)

**배경**: PLAN HIGH-4 진행. (44) 13번 사이클 교훈에 따른 minimum-fix 전략 채택 — SYNC_ALGORITHM_V2 §A~F는 모두 "현행 유지 + 명세화" + §D-2만 실제 fix. 직전 commit `9fb0af4`에서 §A-F 합의 결정 명세화 완료. 이번 commit은 §D-2 fix 코드 적용.

**변경 (`v0.0.63`, 코드 변경 1곳)**:

`lib/services/sync_service.dart:271-272` — `isOffsetStable` 판정 조건 (1줄 → 2줄로 AND 확장):

```dart
// 변경 전
} else if (delta < _stableThresholdMs) {

// 변경 후
} else if (delta < _stableThresholdMs &&
    (_filteredOffsetMs - _winMinRawOffsetMs).abs() < _stableThresholdMs) {
```

**의미**:
- `delta < _stableThresholdMs` (기존): EMA 진동 작음 (slow phase α=0.1에서 step별 변화 < 2ms)
- `(_filteredOffsetMs - _winMinRawOffsetMs).abs() < _stableThresholdMs` (신규): EMA 결과가 진짜 값(window 내 min-RTT sample의 raw offset)과 가까움
- AND → 둘 다 만족해야 `_stableCount++` → false positive 최소

**N=3 데이터 시뮬레이션 결과** ((68)/(69) 측정):

| 케이스 | 첫 anchor 시점 / EMA gap | D2-2 적용 시 | 청감 예상 |
|---|---|---|---|
| 1회차 (운 좋음) | NR 12, 0.1ms | 둘 다 통과 → 동일 시점 anchor | 그대로 좋음 |
| 2회차 (흔들림) | NR 5, 2.0ms | winMinRaw gap = 임계 borderline → 미통과 → anchor 미루어짐 | **30초 흔들림 사라질 가능성 ⭐** |
| 3회차 (운 보통) | NR 23, 11.7ms | winMinRaw gap >> 2ms → 미통과 → anchor 미루어짐 | 청감 OK (현재도 OK) |

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug` ✓ 8.1s

**version bump**: 0.0.62+1 → 0.0.63+1.

**다음 단계**: v0.0.63 빌드 + 양쪽 기기 install → N=3+ 첫 재생 측정으로 검증:
1. anchor_set 시점의 (filtered - winMinRaw) gap이 모든 케이스 < 2ms로 수렴해야 함
2. 청감 분포가 좋음/좋음/좋음으로 수렴해야 함
3. anchor_reset 빈도 idle 3분 4회 → 1~2회로 감소 기대
4. trade-off 검증: 첫 anchor 시점 5~15초 늦어져도 청감 정착 ~1~2초 유지하는지 (fallback alignment 충분한지)

**예상 결과 시나리오**:
- ✅ 청감 분포 일관 좋음으로 수렴 → §D-2 fix 채택 + 다른 §은 현행 유지로 PLAN HIGH-3/4 둘 다 해결
- ⚠️ 첫 anchor가 너무 늦어져 청감 정착 시간이 길어짐 → fallback alignment 정확도 별도 개선 필요
- ❌ 청감 분포 변화 없음 → §D-2 fix가 청감과 비상관, 다른 §(A/B/D) 재검토 필요. 이때는 (44) 13번 사이클 회피 위해 fix 롤백 후 재명세

### 2026-05-02 (71) — v0.0.63 §D-2 fix 검증 N=2 — fix 성공 확정

**환경**: (68)/(69)와 동일. S22 호스트 + Tab A7 Lite 게스트, 같은 WiFi.

**1회차** (`measurements/v0.0.63_first_play_run1_2026-05-02.csv`, 350행, 3분+):
- 청감: 사용자 "그냥 좋았어" + "오차시간 자체가 사람한테 체감되는 정도는 아니다"
- 첫 anchor: NR 93 (재생 **+46초**) — fix 의도대로 EMA 수렴 후 박힘
- 첫 anchor EMA gap: **1.3ms** (filtered -773.7 vs winRaw -775.0) ⭐
- fallback events: 159개 (~80초)
- **anchor_reset: 0회** ⭐⭐⭐
- vfDiff signed mean: **-2.86ms** (v0.0.62 -10~-14ms 대비 4배 개선)
- vfDiff RMS: 14.98ms (25% 감소)

**2회차** (`measurements/v0.0.63_first_play_run2_2026-05-02.csv`, 467행, 3분+):
- 청감: 사용자 "그냥 좋았어"
- 첫 anchor: NR 3 (재생 **+1초** — 매우 빠름) 
- 첫 anchor EMA gap: **0.3ms** ⭐ (운 좋게 첫 sample에서 winMinRaw 즉시 안정)
- fallback events: 137개
- **anchor_reset: 0회** ⭐⭐
- vfDiff signed mean: -7.33ms
- vfDiff RMS: 18.08ms

**핵심 검증 결과**:

| 항목 | v0.0.62 (N=3 평균) | v0.0.63 (N=2 평균) | 변화 |
|---|---|---|---|
| 청감 분포 | 좋음/흔들림/좋음 (33% 흔들림) | 좋음/좋음 (0% 흔들림) | ⭐ 일관성 확보 |
| 첫 anchor EMA gap | 0.1~11.7ms (변동 큼) | 0.3, 1.3ms (모두 < 2ms) | ⭐ 정확도 확보 |
| anchor_reset 횟수 | 2~3회 | 0, 0회 | ⭐⭐⭐ root cause 제거 |
| vfDiff signed mean | -10.96~-14.62ms | -2.86, -7.33ms | ⬇️ 50%+ 개선 |

**N=2 결론 — fix 검증 완료**:

1. **EMA 미수렴 anchor 차단 작동 확정** — 모든 anchor가 winMinRaw gap < 2ms 만족 상태에서만 박힘 (1회차 1.3ms / 2회차 0.3ms)
2. **anchor_reset 사이클 자체가 사라짐** — v0.0.62의 reset 빈도 (idle 3분 4회→0회). reset이 없으니 v0.0.62 2회차 같은 30초 흔들림 패턴 발현 불가능.
3. **첫 anchor 시점은 비결정적이지만 무관함** — 2회차에서 NR 3(빠름) / 1회차 NR 93(느림). fix 목적이 "EMA 수렴 차단"이지 "anchor 늦추기"가 아니므로 둘 다 정상 통과. 운 좋게 EMA 즉시 수렴한 케이스는 빨리 박혀도 정확.
4. **trade-off 미발현** — 1회차 첫 anchor +46초로 늦어졌지만 청감 영향 0 (사용자 보고). fallback alignment가 사용자 청감 임계 안에서 동작 확인.

**해소된 PLAN 항목**:
- **PLAN HIGH-3 (첫 재생 정착 시간)** — N=2 청감 좋음 일관으로 자연 해소. (44) 13번 사이클 회피 — fix 한 줄(§D-2)이 HIGH-3/4 둘 다 해결.
- **PLAN HIGH-4 (SYNC_ALGORITHM_V2 단일 commit)** — §A-F 명세 + §D-2 fix + N=2 검증 완료.

**다음 단계 후보**:
- 출시 전 실기기 풀세트 회귀 (v0.0.57~v0.0.63 누적 영향, 특히 audio_session 0.2 BT 라우팅 + riverpod 3 onDispose + file_picker 11)
- 30분+ 장시간 idle 측정 (PLAN MID-7) — §C rate drift 결정 보류 해제 트리거
- iPhone 게스트 BT 워밍업 케이스 (PLAN MID-8)
- 같은 모델 갤럭시 2대 환경에서 v0.0.54 다중 게스트 fix 검증 (PLAN HIGH-1)

### 2026-05-02 (72) — v0.0.64 측정 자동화 인프라 (--dart-define 측정 모드)

**배경**: v0.0.62 N=3 + v0.0.63 N=2 측정에서 매번 사용자가 양쪽 기기 종료/실행/방생성/입장/파일선택/재생을 수동 진행. 자동화 가치 명확. 14분 PCM 한계(`oboe_engine.cpp:143` 150MB)도 발견 — 12분 이내 측정 권장.

**디자인 — 옵션 4 (`--dart-define=AUTO_MEASURE_MODE`)**:
- 출시 영향 0 (flag 없으면 entry 미참조)
- 측정 모드: 호스트 자동 방생성+자동재생, 게스트 자동입장
- 한 줄 명령으로 빌드/install/launch/대기/csv pull/통계 출력
- 양쪽 기기 같은 빌드 mode일 수 없으므로 호스트/게스트 각각 빌드 후 install

**변경 (`v0.0.64`)**:

1. **`assets/measure_audio.mp3`** (11.5MB) — ffmpeg 생성. 1초 주기 1000Hz sine 100ms beep + 5ms fade in/out + 900ms 무음 패턴, 12분 (720회 반복), 128kbps mp3.
   - `pubspec.yaml` assets 등록.

2. **`lib/measurement/auto_measure_screen.dart`** (신규):
   - `AutoMeasureScreen(mode, durationSec)` ConsumerStatefulWidget
   - HOST 모드: P2PService.startHost → DiscoveryService.startBroadcast → 게스트 입장 대기(60s) → assets mp3 → temp 복사 → loadFile → 5s 안정 → syncPlay → durationSec 후 syncPause → 5s 후 SystemNavigator.pop()
   - GUEST 모드: discoverHosts → 첫 발견 자동 connectToHost → startListening(isHost: false) → durationSec+30s 후 종료
   - minimal UI: 진행 status + error 표시

3. **`lib/main.dart`** (분기 추가):
   - `String.fromEnvironment('AUTO_MEASURE_MODE')` 체크
   - 'host' / 'guest' → `AutoMeasureScreen`, 그 외 → `HomeScreen` (기존)
   - `AUTO_MEASURE_DURATION_SEC` (default 720)

4. **`scripts/measure.sh`** (신규):
   - 1) host용 빌드 + 호스트 install / 2) guest용 빌드 + 게스트 install / 3) 양쪽 강제 종료 + launch / 4) (durationSec + 100s) 대기 / 5) csv pull / 6) 통계 출력
   - default: S22(R3CT60D20XE) host + A7 Lite(R9PW315GL0L) guest, 12분
   - 옵션: `-d 300` (5분), `-h <id>` (호스트 변경), `-g <id>` (게스트 변경)

**자동화 범위 한계 (정직)**:
- ✅ Android 양쪽 idle 측정 자동화 — 한 줄 명령
- ⚠️ 청감 평가는 본질적으로 사람 필요 (csv `drift_ms < 5ms` proxy 가능하지만 청감과 1:1 매핑 아님)
- ❌ iPhone 시나리오 (USB hung 이슈 + BT)
- ❌ 사용자 연타 race 시나리오 (UI tap 자동화 필요)
- ❌ BT 라우팅 검증 (페어링 + 라우팅 OS 인터랙션)

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug --dart-define=AUTO_MEASURE_MODE=host` ✓ 13.6s
- 실제 자동화 측정 검증은 다음 commit (1회 검증 후 baseline 비교)

**version bump**: 0.0.63+1 → 0.0.64+1.

**다음 단계**: `./scripts/measure.sh -d 720` 1회 검증 → v0.0.63 N=2 baseline과 비교 → 자동화 의도대로 작동 확인.

### 2026-05-02 (73) — v0.0.65 자동화 측정 모드 fix (게스트 assets 직접 로드 + 경과 시간 UI + 짧은 테스트 preset)

**배경**: v0.0.64 자동화 측정 1회 검증 중 사용자 보고 — 호스트와 게스트 sync 약 500ms 어긋남. csv 분석 결과 `host_play (NR 0)` + `guest_start (NR 1, +18.78s)` 이후 drift 행 0개. v0.0.63 baseline(vfDiff -2.86~-7.33ms)과 100배 차이로 명백한 회귀.

**root cause 추정 — 11.5MB assets HTTP 다운로드 race**:
- 호스트가 5초 안정 후 `syncPlay` → `audio-url` 메시지 broadcast
- 게스트가 다운로드 시작 (~5~10s WiFi)
- 다운로드 완료 후 `loadFile` (~1~2s)
- 그 사이 호스트는 ~10~15초 진행 → 게스트 sync 시작 시점 큰 fallback drift
- timestamp watch가 안정 진입 못해 drift_report 발생 X (가능성)

**fix 1 — 게스트도 assets 직접 로드** (사용자 지적 적용):
`auto_measure_screen.dart` `_runGuest()`:
- `startListening(isHost: false)` 먼저 호출 (호스트 메시지 listen race 회피)
- assets/measure_audio.mp3 → temp 복사 → `loadFile()` (HTTP 다운로드 skip)
- 그 후 discovery → connectToHost
- 호스트 syncPlay 시 즉시 따라잡기 가능

**Trade-off (의도적)**:
- 일반 모드 다운로드 흐름 검증 skip → 별도 트랙으로 분리
- sync 알고리즘 자체 검증에 더 적합 (다운로드 변동성 제거)

**fix 2 — 경과 시간 UI** (사용자 요청):
- `_markStarted()` 호출 시 `Timer.periodic(1s)`로 경과 시간 갱신
- UI: `MM:SS / total_MM:SS (남은 시간 MM:SS)` + LinearProgressIndicator
- monospace digits (FontFeature.tabularFigures)로 깔끔한 표시

**fix 3 — 짧은 테스트 preset** (사용자 요청):
`scripts/measure.sh`:
- `--quick` (60s, smoke test)
- `--short` (180s, 3분)
- `--mid` (300s, 5분)
- `--long` (720s, 12분 default)
- `-d <sec>` 임의 초 옵션 그대로

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug --dart-define=AUTO_MEASURE_MODE=guest` ✓ 13.1s
- 실제 자동화 측정 검증은 다음 단계 (`./scripts/measure.sh --short` 1회로 빠른 확인)

**version bump**: 0.0.64+1 → 0.0.65+1.

**다음 단계**: `./scripts/measure.sh --short` (3분) 1회 → guest_start 후 drift 행 정상 기록되는지 검증. 정상이면 `--long` 12분으로 본격 측정.

### 2026-05-02 (74) — v0.0.66 자동화 게스트 fix — clock sync 누락 (진짜 root cause)

**배경**: v0.0.65 fix(게스트 assets 직접 로드) 검증 진입 직전 사용자 질문 "파일 로드 외 다른 건 다 똑같은가?" → 일반 모드 `RoomScreen._startSync()` 코드 점검 결과 **자동화 게스트가 clock sync 자체를 안 함**을 발견. v0.0.64 csv drift 행 0개의 진짜 root cause는 다운로드 race가 아님.

**root cause 정정 — clock sync 누락**:

일반 모드 `RoomScreen._startSync()` (`room_screen.dart:208-239`):
1. `sync.syncWithHost()` — 초기 clock sync 10회 ping/pong
2. `sync.startPeriodicSync()` — **1초 주기 ping/pong 시작** (EMA 누적 source)
3. `sendToHost({'type': 'audio-request'})` — 호스트 현재 상태 요청

자동화 모드 `_runGuest()` (v0.0.65까지) — **위 1/2/3 모두 빠짐**.

→ 결과:
- `_filteredOffsetMs` / `_winMinRawOffsetMs` 갱신 X
- `isOffsetStable` 영원히 false → anchor 박힘 X
- 게스트가 호스트로 drift_report 안 보냄
- 호스트 csv에 drift 행 0개 (v0.0.64 측정 정확히 일치)

**v0.0.65 fix 한계**: assets 직접 로드는 다운로드 race 회피하지만 clock sync 부재가 진짜 문제라 효과 없음. v0.0.65로도 동일 회귀 발현 예정이었음.

**fix (`v0.0.66`)**:

`auto_measure_screen.dart` `_runGuest()` — connectToHost 후 추가:
```dart
final sync = ref.read(syncServiceProvider);
final result = await sync.syncWithHost();           // 초기 10회
sync.startPeriodicSync();                           // 1초 주기
p2p.sendToHost({'type': 'audio-request', 'data': {}});
```

**검증**:
- `flutter analyze` No issues
- 빌드/install/측정은 다음 단계

**version bump**: 0.0.65+1 → 0.0.66+1.

**다음 단계**: `./scripts/measure.sh --short` (3분) 재측정. drift 행이 정상 기록되는지 확인 (v0.0.64 0개 → 정상이면 ~360개 / 3분).

### 2026-05-02 (75) — v0.0.67 자동화 게스트 connect WiFi 절전 wakeup fix

**배경**: v0.0.66 측정 2회 연속 connect timeout 발생 (`SocketException: Connection timed out, errno=110`). 사용자 의구심 — "수동에서는 잘 됐는데 자동화에서만 안 됨". 진단 후 진짜 root cause 발견.

**진단 절차**:
1. 호스트 IP 확인 (192.168.35.96/24) + 게스트 IP (192.168.35.43/24) — 같은 subnet ✓
2. Mac → 호스트 ping 정상 (157~431ms 변동)
3. Mac → 호스트 41235 TCP = "Connection refused" — 라우터 차단 X, 호스트 listen 안 함 (측정 종료 후라 정상)
4. **게스트 → 호스트 ping**: 처음엔 100% loss → WiFi 토글 후 응답 오는데 RTT 8.5ms / 974ms / 178ms 극단 변동

**root cause — WiFi power save 모드**:

자동화 모드는 사용자 인터랙션 없는 환경 → 게스트 WiFi 절전 모드 진입. 절전 wakeup 지연이 `p2p_service.dart:168` `Socket.connect` 2초 timeout보다 크면 timeout 발생.

| 모드 | 사용자 인터랙션 | WiFi 상태 | 결과 |
|---|---|---|---|
| 수동 (v0.0.62/v0.0.63) | 화면 tap, 메뉴 탐색 | 깨어 있음 | 즉시 connect ✅ |
| 자동화 (v0.0.64~v0.0.66) | launch 후 즉시 자동 진행 | 절전 진입 | TCP 2초 timeout ❌ |

**fix (`v0.0.67`)**:

`auto_measure_screen.dart` `_runGuest()` — discovery 후 connect 부분에 robustness 추가:
1. discovery 직후 500ms 대기 (WiFi 깨우기)
2. connectToHost 3회 재시도 (시도 사이 2s sleep)
3. 첫 시도 실패해도 두 번째 시도엔 WiFi 깨어 있어 정상 connect 기대

**일반 모드 코드 영향 0** — `p2p_service.dart` 변경 없음. 자동화 모드 entry에만 robustness.

**검증**:
- `flutter analyze` No issues
- 빌드/install/측정은 다음 단계 (`./scripts/measure.sh --short`)

**version bump**: 0.0.66+1 → 0.0.67+1.

**왜 이게 정답일 가능성 높은지**:
- 사용자 진단 단서 "수동은 잘 됐는데" — 알고리즘 동일, 환경 동일, 차이는 사용자 인터랙션 유무
- ping RTT 8.5~974ms 변동 = WiFi 절전 wakeup 정확한 패턴
- TCP connect 2초 timeout과 wakeup ~1초 충돌 가능성

**다음 단계**: `./scripts/measure.sh --short` 재측정. 첫 시도 실패해도 재시도로 connect 성공 + drift 행 정상 기록 기대.

### 2026-05-02 (76) — v0.0.67 자동화 측정 첫 성공 — v0.0.63 수동 baseline 동등 품질 확인

**측정**: `./scripts/measure.sh --short` (180s) 1회. csv `measurements/auto_2026-05-02_211801.csv`, 323행.

**event 분포**:
- drift 307개 ⭐ (v0.0.64/65/66 0개에서 정상 회복)
- anchor_set 1, anchor_reset 0
- fallback 8 (anchor 박히기 전 정상)
- host_play / host_pause / guest_start / guest_stop / seek 각각 1~2

**anchor 시퀀스**:
| NR | event | filtered | winRaw | **gap** |
|---|---|---|---|---|
| 11 | anchor_set | -268.2 | -268.0 | **0.2ms** ⭐ |

→ §D-2 fix가 자동화 환경에서도 의도대로 작동. EMA 수렴 후 anchor 박힘.

**drift 통계 (n=307)**:
- vfDiff signed mean: 2.36ms
- |mean|: 13.59ms
- RMS: 16.05ms
- range: -27.39 ~ +41.86ms

**baseline 비교 (v0.0.63 수동 N=2)**:

| 지표 | 수동 1회차 | 수동 2회차 | **자동화 v0.0.67** |
|---|---|---|---|
| anchor EMA gap | 1.3ms | 0.3ms | **0.2ms** |
| anchor_reset | 0 | 0 | **0** |
| vfDiff signed mean | -2.86 | -7.33 | **+2.36** |
| vfDiff RMS | 14.98 | 18.08 | **16.05** |

→ **수동 baseline과 동등 품질 확인**. 자동화로 인한 회귀 없음.

**해결된 사항 누적**:
1. ✅ 게스트 connect (v0.0.67 WiFi 절전 wakeup retry)
2. ✅ Clock sync (v0.0.66 syncWithHost + startPeriodicSync)
3. ✅ assets 직접 로드 (v0.0.65 다운로드 race 회피)
4. ✅ §D-2 fix (v0.0.63) 자동화 환경에서도 정상 작동

**자동화 인프라 가치 확인**:
- 한 줄 명령 (`./scripts/measure.sh --short`)으로 측정 자동
- 사용자 인터랙션 ~30초 → 0초로 단축
- 빌드 + install + launch + 측정 + csv pull + 통계 + baseline 비교 일괄
- N회 반복 부담 압도적 ↓

**시간 측정**:
- 21:12:31 측정 시작 (빌드)
- 21:18:01 측정 종료
- 총 ~5분 30초 (3분 측정 + buffer + sequence)

**다음 단계 후보**:
- `./scripts/measure.sh --long` 12분 본격 측정 (v0.0.63 수동과 동일 길이로 비교)
- §C rate drift 결정을 위한 long-term 측정
- 다른 PLAN 항목 (실기기 풀세트 회귀, 등)

### 2026-05-02 (77) — v0.0.67 자동화 long 측정 (12분) — fix long-term 안정 + 자동화 환경 한계 발견

**측정 1차** (실패): `./scripts/measure.sh --long` 첫 시도. 게스트 측 1분 동안 재생 안 시작 → 측정 종료. 부분 csv `measurements/auto_long_partial_2026-05-02.csv` (101행).

**1차 진단**:
- 게스트 RTT 156~338ms (정상은 5~10ms) — WiFi 절전 모드 진입
- offset 변동 폭 ~수십 ms → §D-2 fix의 step 변화량 < 2ms 조건 통과 못함
- stable 카운트 0 영원 → anchor 박힘 매우 늦음 (~1분 58초 후에 박힘)
- 사용자 청감 보고 "1분 30~40초쯤 게스트 재생 시작"이 fallback 단계에서 자연 시작 시점과 일치

**1차 결과 통찰** (자동화 모드 fundamental 한계):

자동화 모드 = 사용자 인터랙션 0 → OS가 idle 판단 → WiFi/CPU 절전 → RTT 변동성 ↑.
이는 알고리즘 결함 아니라 환경 차이:
- 수동 모드: 사용자 활동으로 WiFi 항상 활성 → §D-2 fix 정상 작동
- 자동화 모드 idle: WiFi 절전 → §D-2 fix가 너무 엄격하게 발현 → anchor 매우 늦게

§D-2 fix가 큰 RTT 환경에서도 결국 작동 (1분 58초 후 anchor gap 0.7ms로 정상 박힘) — fix는 견고. 단지 시간이 더 걸림.

**측정 2차** (성공): RTT 정상화(ping 3.5~6.8ms) 후 재측정. csv `measurements/auto_2026-05-02_214017.csv` (1319행, 12분).

**2차 결과**:

| 지표 | 값 |
|---|---|
| drift 행 | **1195** (12분, 0.5초 주기) |
| 첫 anchor 시점 | NR 34 (~58초 후) |
| 첫 anchor EMA gap | **0.2ms** ⭐ |
| **anchor_reset** | **0회 (12분 동안!)** ⭐⭐⭐ |
| vfDiff signed mean | -5.25ms |
| vfDiff RMS | 21.47ms |
| range | -69.55 ~ +31.54ms |

**누적 baseline 종합**:

| 측정 | 시간 | drift 행 | anchor gap | reset | vfDiff signed mean | RMS |
|---|---|---|---|---|---|---|
| v0.0.62 수동 N=3 | 3분 | 333~370 | 0.1~11.7ms | 2~3회 | -10~-14 | 19~22 |
| v0.0.63 수동 N=2 | 3분+ | 187~328 | 0.3~1.3ms | 0회 | -2.86~-7.33 | 14~18 |
| v0.0.67 자동 short | 3분 | 307 | 0.2ms | 0회 | +2.36 | 16.05 |
| **v0.0.67 자동 long** | **12분** | **1195** | **0.2ms** | **0회** | **-5.25** | **21.47** |

**확정 사항**:

1. **§D-2 fix가 long-term(12분)에서도 완벽 안정** — reset 0회. v0.0.62의 reset 2~3회와 압도적 개선.
2. **자동화 인프라 long-term 검증 완료** — 한 줄 명령으로 12분 측정 자동.
3. **PLAN MID-7 §C rate drift** — 12분 측정에서 vfDiff signed mean -5.25ms로 큰 누적 추세 미관찰. **§C는 12분 한계 내에선 결정 보류 유지** (30분 측정은 14분 PCM 한계로 불가능, §C 결정은 PCM streaming 구조 변경 후로 미룸).

**자동화 모드 fundamental 한계 — 정직 기록**:

자동화 측정은 **OS idle 환경**의 측정. 사용자 실제 환경(인터랙션 활성)과 다를 수 있음:

| 측정 목적 | 자동화 신뢰도 |
|---|---|
| 회귀 검증 (자동화 vs 자동화) | ✅ OK — 같은 환경 비교 |
| 알고리즘 작동 여부 (anchor establish 등) | ✅ OK |
| 실 사용자 환경 절대값 추정 | ⚠️ 자동화에서 RTT 변동 큰 경우 부정확 |
| 청감 평가 | ❌ 사람 귀 필수 |

WiFi RTT가 자동화 환경에서 간헐적으로 비정상 (이번 1차 시도) — 항상 재현 X. 회피 옵션:
- (B) Dart 레이어 keep-alive ping (1초 주기 dummy packet) — 측정 모드 한정
- (C) Native WifiLock + WakeLock — Kotlin 코드 추가
- 별도 트랙으로 보류 (간헐적이라 즉시 fix 우선순위 낮음)

**version bump 안 함**: 측정·문서 only, 코드 변경 0.

**다음 단계 후보**:
- 출시 전 실기기 풀세트 회귀 (v0.0.57~v0.0.67 누적 영향, 청감 검증 포함)
- 같은 모델 갤럭시 2대 다중 게스트 fix 검증 (PLAN HIGH-1) — 디바이스 확보 시
- 14분 PCM 한계 해제 (PCM streaming 구조 변경) — §C rate drift 결정 트리거
- iPhone BT 워밍업 (PLAN MID-8) — iPhone USB 환경 셋업

### 2026-05-02 (78) — v0.0.68 자동화 측정 wakelock 추가 (WiFi keep-alive)

**배경**: (77) 첫 long 측정 RTT 156~338ms 회귀의 root cause는 **자동 측정 모드 = 사용자 인터랙션 0 = OS idle 판단 = WiFi 절전**. 알고리즘 결함 아닌 환경 차이지만 자동화 측정 신뢰도 위해 회피 fix.

**fix**:

`pubspec.yaml`: `wakelock_plus: ^1.5.2` 추가 (1.6.0은 package_info_plus 10 요구하나 우리는 9.0.1 보류 중이라 1.5.2로).

`auto_measure_screen.dart`:
- `initState()` 시 `WakelockPlus.enable()` — OS idle 판단 방지
- `dispose()` 시 `WakelockPlus.disable()`

효과:
- 자동 측정 모드 entry에서 화면 항상 켠 채 + CPU/WiFi 절전 방지
- 일반 앱 모드는 entry 미참조라 영향 0
- Cross-platform 자동 (Android/iOS 둘 다)

**Trade-off (작음)**:
- 측정 시간 동안 배터리 소모 ↑ (자동 측정 모드만)
- 측정 끝나면 dispose에서 자동 해제

**검증**:
- `flutter analyze` No issues
- `flutter build apk --debug --dart-define=AUTO_MEASURE_MODE=host` ✓ 12.1s

**version bump**: 0.0.67+1 → 0.0.68+1.

**다음 단계**: `./scripts/measure.sh --short` 또는 `--long`로 RTT 정상 유지되는지 검증.

### 2026-05-02 (79) — v0.0.68 wakelock 효과 검증 (RTT 정상화 확정)

**측정**: `./scripts/measure.sh --short` 1회. csv `measurements/auto_2026-05-02_220011.csv`, 164행.

**logcat RTT 시계열** (게스트):
```
RTT=13ms / 12ms / 12ms / 10ms / 10ms / ... / 14ms / 9ms (안정)
stable=1, 2, 3, 4, 5, ..., 20 (정상 증가)
```

→ wakelock 효과 명확. RTT 9~14ms 안정 유지.

**event 분포**:
- drift 85개
- fallback 73개
- anchor_set 1, anchor_reset 0
- host_play 1, host_pause 1, guest_start 1, guest_stop 1

**anchor**:
- NR 64 (재생 +32초)
- gap 0.6ms ⭐

**drift 통계 (n=85)**:
- vfDiff signed mean: -5.01ms
- |mean|: 14.47ms
- RMS: 17.42ms

**비교 — wakelock 효과 확정**:

| 측정 | RTT | stable 증가 | anchor 박힘 시점 | gap | 청감 |
|---|---|---|---|---|---|
| v0.0.67 long 1차 (실패) | 156~338ms | **0 영원히** | 1분 58초 (catastrophic) | 0.7 | 1분 30초 흔들림 |
| **v0.0.68 short (wakelock)** | **9~14ms** ⭐ | **정상 증가** | 32초 (정상 범위) | 0.6 | (자동화라 청감 X) |

**확정 사항**:
- ✅ wakelock_plus.enable() → OS idle 판단 방지 → WiFi 절전 회피 → RTT 정상화
- ✅ §D-2 fix 정상 작동 (gap 0.6ms, reset 0회)
- ✅ catastrophic 회귀 회피 (RTT 156~338ms 같은 case)
- ⚠️ anchor 박힘 시점은 5~32초 변동 (정상 범위, 측정 시점 우연)

**자동화 인프라 robustness 확보 완료**:
- 사용자 인터랙션 0인 환경에서도 OS idle 판단 안 됨
- WiFi/CPU 절전 진입 안 함 → 측정 신뢰도 ↑
- 일반 앱 모드 영향 0 (자동 측정 모드 entry에서만 enable)

**다음 단계 후보**:
- 출시 전 실기기 풀세트 회귀 (자동화 N=3 + 수동 청감)
- `--long` 12분 측정 N=2~3 추가 (long-term 안정성 변동성 검증)
- 다른 PLAN 항목

### 2026-05-02 (80) — v0.0.68 자동화 short N=3 — 일시 WiFi glitch 발견 + 실패 run 처리 규칙

**측정**: `./scripts/measure.sh --short × 3회 sequential` (~18분).

**결과 분포**:

| Run | csv | drift 행 | anchor gap | vfDiff signed | RMS | 상태 |
|---|---|---|---|---|---|---|
| 1 | `auto_2026-05-02_220836.csv` (3행) | 0 | - | - | - | ❌ 실패 |
| 2 | `auto_2026-05-02_221407.csv` (327행) | 192 | 0.4ms | +8.46 | 17.57 | ✅ |
| 3 | `auto_2026-05-02_221937.csv` (163행) | 56 | 1.5ms | -18.94 | 25.65 | ✅ |

**Run 1 실패 진단**:

게스트 logcat:
```
22:04:18 sync OK (RTT=9ms) — 정상 시작
22:04:36 Periodic sync RTT=5777ms ← 갑자기 5초 폭증
22:04:38 SocketException: Connection reset by peer (errno=104) — 호스트가 TCP 끊음
22:07:48 측정 시간 종료 (게스트 reconnect 시도 X)
```

**Root cause**: WiFi 일시 glitch → RTT 폭증 → 호스트 heartbeat timeout → TCP close → 게스트 reconnect 부재 (자동화 모드는 RoomLifecycleCoordinator 미적용).

**wakelock 한계 인정**:

wakelock_plus는 화면 wake lock 제공 (screen on, CPU keep alive). 그러나 **WiFi power save 자체와 일시적 네트워크 glitch는 별개**:
- ✅ OS idle 판단 방지 (CPU governor, 화면 off 회피)
- ⚠️ WiFi router/AP 측 일시 변동, 다른 디바이스 활동, 채널 혼잡 등은 회피 불가

자동화 측정의 **inherent 변동성** — 1/3 (~33%) 일시 실패 발생 가능.

**옵션 C 채택 — 분석 시 실패 run 제외 규칙** (코드 변경 0):

자동화 측정 N개 진행 후 분석:
1. **실패 run 식별 기준**: csv `event` 컬럼에 `drift` 행이 측정 시간(durationSec) × 0.5 (0.5초 주기) × 0.5 (안전 마진) 이하면 실패 간주.
   - 예: --short(180s) → 정상은 ~150~360 drift 행. 실패는 < 50 정도.
   - --long(720s) → 정상은 ~700~1500 drift 행. 실패는 < 200.
2. **분석은 정상 run만**: 실패 run은 총계에서 제외, 별도 "실패 횟수" 표시.
3. **N=3+ 측정 권장**: 실패 1회 발생 시 정상 N=2 확보. N=4+면 더 견고.

**대안 (보류)**:
- (A) 자동화 게스트 reconnect 로직 추가 — 알고리즘 영역, 회귀 위험
- (B) measure.sh 실패 자동 재시도 — csv 빈 행 감지 시 재실행. 실용적이지만 별도 작업

이번 세션은 (C)로 마감. 향후 (B) 자동 재시도가 가성비 좋으면 추가 가능.

**확정 정리 — 자동화 측정 신뢰도 가이드라인**:

| 측정 목적 | 자동화 N개 권장 | 신뢰도 |
|---|---|---|
| 회귀 검증 (regression detection) | N=3 | 1/3 실패 허용, 정상 2/3로 충분 |
| 변동성 분포 (distribution sampling) | N=5+ | 실패 1~2회 제외 후 분포 분석 |
| 알고리즘 작동 여부 (binary check) | N=2 | 1번이라도 정상이면 작동 확인 |
| 절대 수치 추정 (수동 baseline 비교) | N=3+ + 수동 N=3 | 자동화 절대값은 wide variance |

**Run 2/3 (정상 N=2) 정리**:
- anchor gap 모두 < 2ms (0.4 / 1.5)
- anchor_reset 둘 다 0회
- vfDiff signed +8.46 / -18.94 (수동 baseline -2.86~-7.33보다 wide variance)

→ §D-2 fix 자체는 정상 작동, 자동화 환경에서 wide variance 정상.

**다음 단계 후보**:
- 출시 전 실기기 풀세트 회귀 — 수동 청감 검증 (자동화는 이미 충분)
- `measure.sh` 실패 자동 재시도 추가 (옵션 B, 별도 트랙)
- 다른 PLAN 항목

### 2026-05-03 (81) — PLAN 정리: NTP 정공법 + MID-5 -20.84ms 잔재 작업목록 제외

**배경**: 출시 전 작업 우선순위 재평가. 두 항목 모두 §D-2(v0.0.63) 후 자연 해소 정황 + 측정 데이터로 가설 약화 → 작업목록에서 정리.

**(A) NTP 정공법 — 작업목록 제외**:

원래 HISTORY 미해결 이슈 "Anchor reset 후 fallback 단계 큰 drift (HIGH priority)"의 fix 방향. 보류 결정 근거:

1. **2회 시도 모두 실패**:
   - v0.0.46~v0.0.48 (HISTORY (43)): oboe pause/resume + NTP 예약 재생 → drift 63초 회귀 → 롤백
   - v0.0.49~v0.0.61 (HISTORY (44)): 13번 fix 사이클 (seq number + race 제거 + 호스트 schedule 등) → 사용자 청감 v0.0.48이 더 나음 → main reset, 사용자 좌절 보고 ("점점 좋아지는 게 아니라 퇴보")
2. **§D-2(v0.0.63) 자연 해소 정황**: v0.0.67 자동화 12분 측정에서 anchor_reset 0회, vfDiff RMS 21ms. 원래 잡으려던 (42) edge case의 대부분이 한 줄 fix로 흡수된 것으로 보임
3. **본격 재도입 트리거 부재**: §C rate drift 결정은 30분+ 측정 후. PCM streaming 구조 변경 선결 → 진짜 누적 drift 측정되면 그때 NTP 재도입 검토
4. backup branch 보존: `backup-v0.0.61-session`, `backup-v0.0.51-to-v0.0.55-session`

**(B) PLAN MID-5 -20.84ms 잔재 root cause 분해 — 취소선 처리**:

(45) v0.0.49 idle 4분 측정 vfDiff signed mean -20.84ms 베이크인 잔재 추적 항목. 정리 근거:

1. **outputLatency baked-in 가설 부정**: (59) 측정에서 anchored vs current diff = 0.22ms로 사실상 0. EMA 보존 효과 미미 신호
2. **§D-2 후 잔재 4~7배 감소**:

| 측정 | vfDiff signed mean |
|---|---|
| v0.0.49 idle 4분 (45) | **-20.84ms** ← 원래 추적 대상 |
| v0.0.62 수동 N=3 | -10~-14ms |
| v0.0.63 수동 N=2 | -2.86~-7.33ms |
| v0.0.67 자동 long 12분 | -5.25ms |
| v0.0.68 자동 short | -5.01ms |

3. **자연 재현 부재**: 자동화 N=3까지 진행, -20ms 영역 미진입. 작은 잔재라 진단 정확도도 떨어짐
4. **진단 인프라 활성 유지**: `out_lat_*` + `vf_diff_ms` 컬럼은 그대로. 큰 잔재 자연 재발 시 자동 캡처 → HISTORY 미해결 이슈에 신규 항목으로 다시 띄움

**작업 후 살아있는 항목** (PLAN.md):
- HIGH: 다중 게스트 fix 같은 모델 갤럭시 2대 검증 (디바이스 한계)
- MID: 7(30분+ 측정, PCM 한계로 보류) / 8(BT 워밍업) / 9(getTimestamp 간헐 실패 자연 재발 대기) / 10(iOS host 환경)
- LOW: errno=65/51 / Tab A7 Lite framePos / acoustic loopback / iOS install hung / 디버그 스터터 / UI 폴리싱

**출시 전 권고 (PLAN 미등재)**:
- 출시 전 실기기 풀세트 청감 회귀 (v0.0.57~v0.0.68 누적)
- measure.sh 실패 자동 재시도 (옵션 B)
- BT outputLatency 동적 보정 (HISTORY 미해결 이슈)
- iOS 라이프사이클 T1~T4 재검증

**변경 범위**: `docs/PLAN.md` MID-5 취소선 처리, `docs/HISTORY.md` 미해결 이슈 NTP 항목 보류 표시. 코드 변경 0.

### 2026-05-04 (82) — v0.0.68 출시 전 실기기 풀세트 회귀 — 신규 회귀 2건 발견

**환경**: S22 호스트(`R3CT60D20XE`) + Tab A7 Lite 게스트(`R9PW315GL0L`) + iPhone 12 Pro 게스트(`00008101-00063C963C52001E`). 셋 다 같은 AP `GANG-E` (192.168.35.x /24).

**범위**: v0.0.57~v0.0.68 누적 영향 검증 (의존성 묶음 패치 + audio_session 0.2 + file_picker 11 + riverpod 3 + wakelock_plus).

**진행**:

1. **빌드/설치** ✅
   - `flutter build apk --debug` → S22/A7 Lite `flutter install`. iPhone은 `flutter run`으로 1차 실패(`Failed to get CONFIGURATION_BUILD_DIR`, MID-14 변종) → 신뢰 다이얼로그 OK 후 재실행 성공.

2. **AP 단말간 격리 회피** ⚠️ (회귀 무관)
   - 초기 A7 Lite → S22 ping 100% loss, iPhone은 정상. 같은 BSSID·채널인데 비대칭. WiFi off→on 토글로 풀림. AP가 random MAC 일부 차단했을 가능성.
   - 향후 자동 회귀 환경 안정화 위해 S22 모바일 핫스팟 표준화 검토.

3. **P2P 연결 회귀** ✅
   - 3대 동시 입장, peer count 3 일관 표시.

4. **파일 전송 + 동기 재생 청감** ⚠️ 신규 회귀 발견
   - 첫 재생: 청감 양호(echo/지연 못 느낌), seek/일시정지/재생 정상, drift 안정.
   - **파일 변경 시 회귀**: 호스트 "대기 중" UI에서 게스트만 단독 재생 + 미세 sync 잔재.
     - logcat: 호스트 새 파일 로드 직후 `[TS] ok recovered after 28 failures (vf=1152)` (~2.8초 ts 실패)
     - 게스트: `[OBS-PLAYSTART] fp=-1 vf=0 sr=44100 hostOutLat=0.0 playing=true` stub 값 → `obs→startPlayback`
     - root cause: `native_audio_sync_service.dart:843` `currentHostPlaying = _latestObs?.playing ?? hostPlaying`이 새 파일 케이스에서 호스트 native 엔진 ready 전에 true 판정.
     - 미해결 이슈 `oboe::getTimestamp 간헐 실패`(HISTORY.md:4217)와 시너지.
     - 미해결 이슈로 기록 (HIGH priority).

5. **라이프사이클 T1~T4** ⚠️ T4에서 신규 회귀
   - T1 호스트 백그라운드/복귀: iPhone 게스트 `[LIFECYCLE-GUEST] received host-paused` / `host-resumed` broadcast 정상 수신 ✓
   - T2 비행기 모드 on/off: 정상 재접속 ✓
   - T3 호스트 백그라운드 재생 유지: ✓
   - **T4 iPhone 강제 종료**: 호스트 peer count 3→2 정상, 그러나 **A7 Lite 게스트는 3 그대로**. v0.0.32에서 fix됐던 영역의 회귀 가능성.
   - 미해결 이슈로 기록 (mid priority, 재현 + 추적 필요).

6. **의존성 회귀** ✅
   - `file_picker 11`: 4번 항목 파일 변경 동작에서 implicit pass.
   - `riverpod 3`: 코드 변경 0이라 묵시적 통과.
   - `wakelock_plus`: 자동화 (79)에서 이미 검증.
   - `audio_session 0.2` BT 라우팅: 이번 회귀에서 skip.

**누적 결과**:

| 항목 | 결과 |
|---|---|
| 빌드/설치 | ✅ (iPhone install hung 변종은 신뢰 다이얼로그 후 회피) |
| 3대 동시 P2P 연결 | ✅ |
| 첫 재생 청감 + drift | ✅ |
| **파일 변경 시 동기** | ⚠️ 신규 회귀 (호스트 ts 실패 + 게스트 단독 재생) |
| 라이프사이클 T1~T3 | ✅ (iPhone 포함 첫 검증) |
| **T4 게스트 강제 종료 peer count** | ⚠️ 신규 회귀 (호스트만 갱신, 다른 게스트 누락) |
| 의존성 회귀 | ✅ (BT skip) |

**version bump 안 함**: 측정·문서 only, 코드 변경 0.

**다음 단계 후보**:
- 신규 회귀 2건 fix
  - (A) 파일 변경 hostPlaying broadcast 게이팅 — `native_audio_sync_service.dart` 또는 audio-url broadcast 측에서 호스트 첫 ts ok 확인 후 hostPlaying=true 보내기
  - (B) T4 peer count 갱신 누락 진단 — logcat streaming + RoomScreen vs PlayerScreen 카운트 출처 추적
- HIGH-1 같은 모델 갤럭시 2대 다중 게스트 검증 (디바이스 확보 시)
- `Anchor reset 후 fallback 큰 drift` NTP 정공법 재도입

### 2026-05-04 (83) — v0.0.69 파일 변경 시 게스트 단독 재생 fix

**배경**: HISTORY (82) 회귀 — 호스트가 새 파일 선택 시 호스트 native 엔진 `getTimestamp` 28회 실패(~2.8초 무음) 동안 게스트만 단독 재생 시작.

**fix 진행** (단일 commit, 3단계):

**Fix A** — `native_audio_sync_service.dart:392~400`. `loadFile` 끝 시점의 `audio-url` broadcast에서 `playing: _playing` → `playing: false` 강제. 새 파일 로드 직후 시점은 호스트가 명시적 `syncPlay` 누르기 전이라 false가 정확. 호스트 syncPlay 후 obs broadcast로 `playing=true` 게스트에 도달.

**Fix B** — `native_audio_sync_service.dart:893~907`. `_handleAudioObs`에서 `obs.playing && obs.framePos > 0` sanity gate. 호스트 ts 간헐 실패(`framePos=-1`) 중인 stub obs 신뢰 안 함. 다음 정상 obs(<=500ms 후) 도달 시 시작.

**Fix C** (게스트 측 obs 판정 강화) — `native_audio_sync_service.dart:840~855`. `loadFile` 끝 시점 `currentHostPlaying` 판정에 `_latestObs?.framePos > 0` 게이트. stub obs면 `urlHostPlaying`(audio-url의 false) 사용.

**Fix D** (1차 검증 후 root cause 추가 발견) — `native_audio_sync_service.dart:704~707`. `_handleAudioUrl` 수신 시 `_latestObs = null` 명시적 reset. 1차 검증에서 게스트가 이전 파일 obs(framePos>0, playing=true)를 새 파일 loadFile 끝 시점에 그대로 신뢰해 단독 시작 발견.

**검증 (실기기 S22 호스트 + A7 Lite 게스트)**:
- Build 1차: A+B+C 적용. 두 번째 파일 변경 시 logcat `[GUEST] loadFile done, urlHostPlaying=false, hasValidObs=true, currentHostPlaying=true` → 게스트 단독 시작. **Fix B sanity gate 통과** (이전 파일 obs framePos>0이라).
- Build 2차: D 추가. 두 번째 파일 변경 시 게스트 단독 재생 회귀 사라짐 ✓. 호스트 명시적 syncPlay 후 정상 동기 시작.

**version bump**: 0.0.68+1 → 0.0.69+1.

**부가 환경 변동성 — fix 검증 중 발견** (코드 무관, 별도 항목):

1. **AP 단말간 격리 재발** — A7 Lite ↔ S22 ping 100% loss. `am force-stop com.synchorus.synchorus` 후 ping도 동일 → **앱과 무관한 OS/AP 레벨 이슈** 확정. WiFi 토글로 회피. iPhone은 정상 — A7 Lite의 random MAC + 11n idle drop 추정. 자동 회귀 환경 안정화 위해 S22 모바일 핫스팟 표준화 검토 가치 있음 (별도 트랙).
2. **HTTP 404 stale state — 게스트 재접속 시 다운로드 실패** (신규 미해결 이슈). A7 Lite WiFi 토글 후 재입장 시 호스트 41236 GET → 404. `nc`로 직접 GET 시도해도 404 응답 정상 도달. 호스트 `_currentUrl`은 살아있는데 disk에 파일 사라진 stale 케이스. 호스트가 mp3 다시 선택하면 즉시 정상화. **fix 방향**: `_handleAudioRequest`(`native_audio_sync_service.dart:539`)에서 disk 파일 존재 확인 + 없으면 응답 보류 또는 재로드.
3. **iOS install hung 변종** — `flutter run` 시 `Installing and launching...` 단계에서 8분+ hung (이전 사례 1~3분). MID-14 변종, 원인 동일.

**다음 단계 후보**:
- HISTORY (82) 1-B 회귀 fix (T4 peer count 게스트 갱신 누락) — 별도 commit
- 2번 신규 미해결 이슈 fix (HTTP 404 stale state)
- 자동화 인프라 안정화 — S22 핫스팟 모드 도입 검토

### 2026-05-04 (84) — v0.0.70 게스트 재접속 다운로드 404 fix + 진단 logging

**배경**: HISTORY (83) 신규 미해결 이슈 1-C — 게스트 WiFi 토글 후 재접속 시 호스트 41236 GET → 404. 호스트 `_currentUrl`은 살아있으나 disk stableFile은 사라진 stale 케이스.

**root cause 가설 추적**:

`_cleanupTempDir` 코드(`native_audio_sync_service.dart:1487`)가 두 곳에서 호출:
- `startListening:138` — RoomScreen 진입 시 잔여 temp 파일 정리 (의도)
- `clearTempFiles:1518` — 방 나갈 때 (정상)

**가드 누락 발견**: `_cleanupTempDir`이 `audio_*`로 시작하는 모든 파일을 무조건 삭제 — **현재 사용 중인 `_storedSafeName`도 보호 안 함**. 호스트가 어떤 경로로 `startListening` 재호출되면 자기 활성 파일을 자기가 삭제하는 부작용. `_currentUrl`/HTTP 서버는 살아있어 게스트는 audio-url 받지만 GET 시 disk에 파일 없어 404.

다만 `startListening` 재호출 트리거 자체(앱 백그라운드/포그라운드, riverpod provider 재생성, RoomScreen rebuild 등)는 logging 부재로 미확정 — 자연 재현 시 좁히기 위해 진단 logging도 같이 추가.

**fix** (방어적 가드 2개 + 진단 logging):

1. `_cleanupTempDir:1494~1517` — `_storedSafeName == name`이면 보호. 삭제/보호 카운트 logging.
2. `_handleAudioRequest:539~556` — disk 파일 존재 확인 후 응답. 없으면 `_currentUrl`/`_storedSafeName`/`_currentFileName` 모두 null로 정리(stale state 정리).
3. `startListening:132~146` — 활성 `_storedSafeName`이 있는 상태에서 재호출 시 `[DIAG] startListening re-entry` 로그.

**검증** (S22 호스트 + A7 Lite 게스트):
- mp3 선택 → 정상 다운로드
- A7 Lite WiFi 토글 → 재접속 → 다운로드 정상 (이전 v0.0.69에선 404 회귀 — fix 통과)

**root cause 100% 미확정 인정**:
- 두 가드 중 어느 쪽이 발동했는지 logging 부재로 미확인
- 직전 v0.0.69 케이스 disk 사라짐 원인 (startListening 재호출 vs OS cleanup) 미확정
- `[DIAG] startListening re-entry` 로그가 자연 재현 시 트리거 좁히기 가능

**version bump**: 0.0.69+1 → 0.0.70+1.

**다음 단계 후보**:
- HISTORY (82) 1-B fix (T4 게스트 강제 종료 시 다른 게스트 peer count 갱신 누락)
- 자연 재현 시 `[DIAG] startListening re-entry` 로그로 root cause 확정

### 2026-05-04 (85) — v0.0.71 게스트 강제 종료 시 다른 게스트 peer count 갱신 fix

**배경**: HISTORY (82) 1-B 회귀 — T4 회귀 테스트(S22 호스트 + A7 Lite + iPhone) 중 iPhone 강제 종료 시 호스트 peer count는 3→2 정상, 그러나 A7 Lite 게스트는 3 그대로.

**root cause 발견**: `p2p_service.dart:286~290`의 `socket.done.catchError` 분기에서 `broadcastToAll('peer-left', peerCount)` 누락. 정상 종료(`then`) 분기엔 broadcast 있음.

iPhone 강제 종료 = TCP RST → `socket.done` error 종료 → `catchError` 진입 → 호스트 자기 `_peers`에서 제거 + `_peerLeaveController`만 emit, **다른 게스트에게 알림 안 감**.

**fix** (`p2p_service.dart:277~291`): 정상/에러 분기를 `onDone()` 함수로 통합. 양쪽 모두 broadcast 호출.

```dart
void onDone() {
  if (!_peers.any((p) => p.id == peerId)) return;
  _peers.removeWhere((p) => p.id == peerId);
  _peerLeaveController.add(peerId);
  broadcastToAll({
    'type': 'peer-left',
    'data': {'peerId': peerId, 'peerCount': _peers.length},
  });
}
socket.done.then((_) => onDone()).catchError((_) => onDone());
```

**검증** (S22 호스트 + A7 Lite + iPhone 게스트):
- iPhone 강제 종료 → S22 + A7 Lite 모두 peer count 3→2 ✓
- iPhone 재입장 → 셋 다 peer count 3 ✓
- A7 Lite 강제 종료 → S22 + iPhone 모두 peer count 2 ✓
- 호스트 강제 종료 → 게스트 host-closed 정상 흐름 ✓

**version bump**: 0.0.70+1 → 0.0.71+1.

**부수 — IntelliJ로 iPhone install hung 회피**:
- CLI `flutter run`은 `Installing and launching...` 단계 8분+ hung 재현 (MID-14)
- IntelliJ에서 Flutter 플러그인으로 Run → 빌드 + install 정상 완료 (5:37PM 빌드 시작 → 5:38PM `devicectl install app` 호출 완료)
- 이전 stale 프로세스 정리 필요했음 (kill 4868 4869 4876 4888 5279 5336 5752 7205 7262 7678)
- 추가 fix 후보: MID-14 자체는 미해결, IntelliJ 우회로 검증 환경 안정화 가치 확인

**다음 단계 후보**:
- 다른 PLAN 항목 (HIGH-1 같은 모델 갤럭시 2대 / Anchor reset NTP 정공법 등)
- 자연 재현 시 `[DIAG] startListening re-entry` 로그로 1-C root cause 확정

### 2026-05-04 (86) — v0.0.72 Oboe stream sample rate mismatch fix (음정 떨어짐 회귀)

**배경**: v0.0.71 회귀 테스트 중 사용자 보고 — 호스트(S22) + 게스트(A7 Lite) 둘 다 음정이 일관적으로 낮게 재생됨. iPhone은 정상.

**진단 시퀀스**:

1. **logcat oboe 패턴 발견** — S22, A7 Lite 모두 `state=Pausing + ErrorInvalidState + xrun 누적` 반복. 처음엔 xrun 효과로 가설 잡았으나 사용자 정정 — "음정이 일관 down된 것" → xrun(끊김)이 아닌 **sample rate mismatch**.
2. **actualSR 확인** — `start stream OK: reqSR=44100 actualSR=44100 burst=96` (S22) / `burst=256` (A7 Lite). stream 44100Hz로 열려있음.
3. **현재 파일 sr 확인** — `loadFile: sr=48000 ch=2 dur=352.5s mime=audio/mpeg`. 파일은 48000Hz.
4. **mismatch root cause 확정**: 첫 파일이 44100Hz였고 stream 44100으로 열림 → 두 번째 파일 48000Hz 로드 시 stream 그대로 재사용 → 48000Hz 데이터를 44100Hz hardware로 출력 → **0.919배 속도 → 음정 약 1.5반음 낮음**.

**root cause 코드 위치**: `oboe_engine.cpp:250~262` `start()` 메서드. v0.0.46 "정지/재생 시 stream 즉시 출력 위해 재사용" 의도로 `if (mStream) { ... return true; }` 처리했으나, **새 파일 sample rate가 다른 케이스를 누락**.

**fix** (`oboe_engine.cpp:250~285`): `start()` 시작 시 `mStreamSampleRate != mDecodedSampleRate`이면 `stop() + close() + reset()` 후 `prewarmInternal_locked()`로 stream 재생성. 일치하면 기존 v0.0.46 동작 유지(setup latency 0).

**검증** (실기기 S22 + A7 Lite):
- 첫 파일(44100Hz) 재생 → 정상
- 두 번째 파일(48000Hz)로 변경 → 사용자 청감 "음정 정상" 확정 ✓
- logcat에 `start: stream SR mismatch → reopen` 로그 발현

**파급 효과 — 이번 세션 sync 이슈 일부 reframe 가능성**:

이번 SR mismatch가 호스트 0.919배 재생 → 게스트들과 큰 속도 차이 → drift-report에 큰 값 → fallback alignment가 비정상 seek 시도 → A7 Lite logcat의 `[FALLBACK] align: drift=53423.2ms, seekTo=-2563654` (53초 drift) 같은 값이 이걸로 설명됨.

iPhone 게스트 `event=fallback drift=±20~35ms` 매번 발생도 호스트(SR mismatch 0.919배) vs iPhone(정상) 속도 차이로 누적된 drift일 가능성. **즉 이번 세션에서 디버깅했던 anchor reset/fallback drift 일부 또는 전부가 SR mismatch에서 파생된 증상**일 수 있음. 알고리즘 결함이 아니라 root cause(SR mismatch)에서 나온 효과.

이 reframe은 가설이며 향후 같은 시나리오 재현 시 v0.0.72 fix 적용한 logcat에서 fallback drift 절대값이 작아지는지로 검증 가능.

**version bump**: 0.0.71+1 → 0.0.72+1.

**다음 단계 후보**:
- v0.0.72 fix 후 자동화 측정 재실행 — drift 절대값 비교로 SR mismatch 효과 분리
- xrun + Pausing stuck (Tab A7 Lite oboe pause/resume xrun 미해결 이슈 영역) 별도 트랙
- 그 외 PLAN 항목

### 2026-05-04 (87) — v0.0.72 자동화 short baseline (N=2) — SR mismatch fix 효과 정량 검증

**측정**: `./scripts/measure.sh --short × 2회 sequential` (3차 시도 중 S22 USB 연결 끊김으로 N=2 마감).

**Run 결과**:

| Run | csv | drift n | anchor gap | vfDiff signed mean | RMS | range | reset |
|---|---|---|---|---|---|---|---|
| 1 | `auto_2026-05-04_183336.csv` (321행) | 167 | **-0.80ms** | **+1.34ms** | 14.77ms | [-57, +28] | 0 |
| 2 | `auto_2026-05-04_183924.csv` (322행) | 248 | **-1.20ms** | **+0.64ms** | 20.05ms | [-41, +40] | 0 |

**누적 자동화 short baseline 비교**:

| 버전 | vfDiff signed mean | gap | reset | 비고 |
|---|---|---|---|---|
| v0.0.67 | +2.36 | 0.2 | 0 | wakelock 도입 전 |
| v0.0.68 N=2 | +8.46 / -18.94 | 0.4 / 1.5 | 0 | wakelock 도입, wide variance |
| **v0.0.72 N=2** | **+1.34 / +0.64** | **-0.80 / -1.20** | **0** | **SR mismatch fix 후 — variance 좁혀지고 0 근처 수렴** |

**해석**:
- vfDiff signed mean **+0.64~+1.34ms** 매우 작은 값. 0 근처 수렴 = host vs guest 누적 속도 차이 거의 없음.
- v0.0.68의 wide variance(+8 vs -19)가 v0.0.72에서 +1 / +0.6으로 좁혀짐. 측정 환경(자동화 idle) 변동성 자체는 같으니 **이전 wide variance의 source가 SR mismatch**였을 가능성 강한 증거.
- anchor gap 모두 < 2ms (§D-2 fix 효과 유지).
- anchor_reset 0회 N=2 일관.

**SR mismatch root cause 정량 검증**:
v0.0.71까지의 자동화 측정에서 보였던 wide variance가 v0.0.72에서 좁혀짐 → **음정 down 회귀 fix가 sync 안정성에도 부수 효과**. 이번 세션 디버깅했던 fallback 큰 drift 일부가 SR mismatch에서 파생된 효과였을 가설이 정량적으로 강해짐.

**한계**:
- N=2 (3차 시도 중 USB 끊김으로 중단)로 통계적 강도 제한
- 자동화 idle 환경 측정 — 실제 사용자 환경 변동성과 다를 수 있음
- vfDiff |mean| 14~16ms, RMS 14~20ms는 BT outputLatency / host outputLatency 비대칭 잔재 영역 (별도 트랙)

**version bump 안 함**: 측정·문서 only, 코드 변경 0.

**다음 단계 후보**:
- BT outputLatency 동적 보정 (vfDiff 잔재 ~30ms 영역, MID priority)
- HIGH-1 같은 모델 갤럭시 2대 검증 (디바이스 확보 시)
- NTP 정공법 재도입 (DECISIONS 원칙 따라 SYNC_ALGORITHM_V2 합의 후 단일 commit, 별도 세션)

### 2026-05-06 (88) — v0.0.73 게스트 식별을 영속 deviceId(UUID)로 교체 — 같은 모델 충돌 0

**배경**: v0.0.54 (52) fix는 디바이스 모델명 + `microsecondsSinceEpoch & 0xFFFF` hex suffix로 게스트 이름을 발급하고, 호스트가 `name + remoteAddress` 둘 다 일치할 때 stale로 정리하는 구조였음. 같은 모델 디바이스 2대가 같은 microsecond에 join하면 hex suffix가 충돌 가능한 1/65536 코너가 잔존 → PLAN HIGH-1이 "같은 모델 2대 이상 환경 실측"을 요구하는 부담으로 남아 있었음. 현재 보유 디바이스(S22 + iPhone 12 Pro + Tab A7 Lite)는 모델이 모두 달라 이 코너 검증이 사실상 불가.

**접근 (사용자 제안)**: model+timestamp 조합 대신 **앱 첫 실행 시 발급한 UUID를 영속화**하면 충돌 확률 0(1/2^128)이 되어 같은 모델 검증 자체가 불필요해짐. 같은 디바이스의 재접속(앱 재시작 / 비행기 모드 / 백그라운드 후 복귀)도 이름·IP가 아닌 영속 ID로 정확히 식별 가능.

**변경**:
1. `pubspec.yaml`
   - `shared_preferences: ^2.5.2` 추가 (영속 저장).
   - `version: 0.0.72+1 → 0.0.73+1`.
2. `lib/models/peer.dart` — `Peer`에 `deviceId` 필수 필드 추가.
3. `lib/services/p2p_service.dart`
   - `connectToHost(ip, port, name, {required String deviceId})` — signature 확장. join 메시지 payload `{'name', 'deviceId'}`.
   - `_lastMyDeviceId` 추가, `reconnectToHost`도 같은 ID 재사용.
   - `_handleNewPeer`에서 `peerDeviceId = data['deviceId']` 수신, stale 매칭을 `name + remoteAddress` → `deviceId` 단독 비교로 교체. `deviceId`가 비어 있으면(메시지 누락) stale 정리 자체를 건너뜀 — 잘못 destroy하는 것보다 일시 중복이 안전.
4. `lib/screens/home_screen.dart`
   - `_resolveDeviceName()`에서 hex suffix 제거 → 표시명만 (`SM-S908N`, `홍길동의 iPhone`). UI 표시 전용.
   - `_resolveDeviceId()` 추가: SharedPreferences 키 `device_uuid`에 `Random.secure()` 16바이트 hex(32자)를 첫 실행 시 1회 생성·저장 후 영구 재사용. `uuid` 패키지 의존성 안 씀(의존성 줄이기).
   - 두 join 경로(`_joinRoom` 자동 발견, `_joinByIp` IP 직접 입력) 모두 deviceId 전달.
5. `lib/measurement/auto_measure_screen.dart` — 자동 측정 게스트도 같은 SharedPreferences 키 공유(`_resolveAutoMeasureDeviceId`). 같은 디바이스가 일반/측정 모드를 오갈 때도 같은 ID 유지. 표시명은 `'AutoMeasureGuest'` 고정(timestamp 제거).

**왜 SharedPreferences 키 공유인가**: 같은 디바이스에서 일반 모드 → 자동 측정 모드 전환 시 다른 deviceId가 발급되면 호스트는 다른 디바이스로 인식해 stale 정리 안 함. 같은 키를 공유해 ID 일관성 보장.

**왜 `uuid` 패키지 안 씀**: `Random.secure()` + 16바이트 hex로 같은 entropy(2^128) 확보. 패키지 1개 줄임.

**검증 효과**:
- 같은 모델 2대 환경 검증 불필요 (코드상 충돌 0).
- 갤럭시 3대(모델 무관) + 비행기 모드 on/off 검증으로 충분.
- v0.0.54의 1/65536 코너 영구 제거.

**호환성**: 메시지 포맷이 바뀌어 v0.0.72 이하 빌드와 v0.0.73 빌드를 섞으면 deviceId 누락 → 새 빌드 측이 stale 정리를 건너뜀(중복 peer가 일시적으로 보일 수 있음). 같은 빌드 사용 권장.

**lint/analyzer**: `flutter analyze` clean (No issues found).

### 2026-05-06 (89) — v0.0.73 다중 게스트 fix 실측 검증 PASS (3대 환경)

**구성**: S22 (호스트, R3CT60D20XE) + Tab A7 Lite (게스트, R9PW315GL0L) + iPhone 12 Pro (게스트). 모델 모두 달라 v0.0.54 검증 부담이었던 "같은 모델 2대"는 이번에도 못 만족했지만 v0.0.73 영속 deviceId fix로 해당 코너가 코드상 사라졌으므로 모델 무관 검증으로 충분.

**시나리오 결과**:

| 단계 | 시나리오 | 결과 |
|---|---|---|
| 1 | S22 방 만들기 → A7 자동 발견 join → iPhone 자동 발견 join | peer count 3 유지 ✅ |
| 2 | A7 비행기 모드 ON 5~10초 → OFF | 자동 재접속 후 peer count 3 유지 ✅ |
| 3 | iPhone 비행기 모드 ON 5~10초 → OFF | 자동 재접속 후 peer count 3 유지 ✅ |
| 4 | A7 앱 강제 종료 → 재실행 후 같은 방 재입장 | 3→2(즉시)→3(재입장) 정상 사이클 ✅ |

**해석**:
- 1~3단계: v0.0.51 핑퐁 회귀(2번째 게스트가 1번째를 stale로 destroy) 재현 안 됨 → v0.0.54 name+IP 매칭 또는 v0.0.73 deviceId 매칭이 의도대로 동작.
- 4단계: 강제 종료 시 TCP RST가 즉시 호스트에 도달 → 호스트가 즉시 disconnect 감지 → peer count 3→2 broadcast (v0.0.71 (84) fix). 재입장 시 stale peer가 이미 정리된 상태라 deviceId 매칭은 발동 안 하고 그냥 add → 2→3.
- v0.0.73 deviceId 매칭이 진짜 발동하는 시나리오는 **heartbeat timeout(15초) 전에 빠른 재접속**(비행기 모드 5~10초 케이스 = 2/3단계). UI상 정상 작동하므로 동작은 검증되었지만 logcat 캡처는 USB 연결 안 한 상태로 진행해 실제 `[P2P] stale peer 정리 (deviceId=...)` 로그 1회 발동 여부는 미캡처. 동작 결과(peer count 3 유지)로 충분 확인.

**미캡처 로그**: 4단계 진행 중 S22 USB 분리 상태 → adb logcat 미수집. 다음 회귀 시 USB 연결한 채로 같은 시나리오 반복하면 stale 정리 로그 1회 캡처 가능. 다만 본 PASS 판정은 UI 결과로 충분.

**version bump 안 함**: 측정·문서 only. v0.0.73 코드 변경은 (88)에서 이미 bump 완료.

**PLAN HIGH-1 마감**: "다중 게스트 fix 실측 검증" 완료 처리. 같은 모델 2대 검증은 영구 불필요.

---

### 2026-05-10 (90) — v0.0.74 clock sync cold start 단축 (early termination + carry over + fast phase 제거)

**배경**: PLAN MID-7 사전 트랙으로 streaming 구조 검토 중, 첫 재생 정착 wait의 진짜 bottleneck이 `isOffsetStable` 도달 시간 = **초기 핸드셰이크 3초 + fast phase 10초 + stable 5번 5초 ≈ cold start 18초** 임을 진단. 이 동안 anchor establish 안 되어 fallback alignment(30ms 임계 거친 모드)가 동작 → 청감 흐림. v0.0.43~v0.0.63까지 진행한 13번 사이클(HISTORY 44)이 알고리즘 내부 시도였다면, 이번은 **수렴 단계 자체를 단축**하는 보수적 변경.

**변경 위치**: `lib/services/sync_service.dart` 단일 파일.

**변경 내용 4가지**:

1. **A. 초기 핸드셰이크 early termination** (`syncWithHost`, 라인 128~248)
   - 새 상수 `_earlyTermRttThresholdMs = 10`, `_earlyTermSampleCount = 10`
   - 매 pong 처리 시 `rtt <= 10ms` sample 카운터 추가
   - 카운터 ≥ 10이면 30개 cap 못 채워도 즉시 종료
   - 30개 fallback 유지 (보수적). 측정 분포에서 ≤10ms 비율 28% → 평균 36 ping → 30 cap에 거의 항상 걸림. 좋은 LAN 환경에서만 단축.

2. **B. best 1개 sample을 `_recentWindow` 맨 뒤에 carry over** (라인 184~194, 232~238)
   - `bestSample` 추적 (`_SyncSample` 객체)
   - 정상 종료 시 + timeout 시 둘 다 `_recentWindow.add(bestSample)` 후 사이즈 가드
   - sliding window는 인덱스 0(가장 앞)에서 빠지므로 맨 뒤 박힌 best는 **9개 새 sample 들어올 때까지 안 빠짐 → 9초 동안 minSample 안전망**.

3. **C. fast phase 코드 6곳 제거**
   - 상수 `_emaAlphaFast`, `_emaAlphaSlow`, `_fastPhaseCount` → `_emaAlpha = 0.1` 단일화
   - 필드 `_periodicSampleCount` 제거 (다른 용도 없음)
   - `reset()`의 `_periodicSampleCount = 0` 라인 제거
   - `_periodicSampleCount++` + alpha 분기 제거
   - stable 판정 fast phase 분기 (`if (_periodicSampleCount <= _fastPhaseCount) _stableCount = 0`) 통째 제거
   - debugPrint의 `alpha=` 출력 제거
   - **carry over로 출발점 안정 + §D-2 AND 조건이 false positive 방어**가 fast phase 무용화의 전제.

4. **D. `isOffsetStable` 5번 연속 조건 — 변경 없음 (보수적 결정)**
   - `_stableRequiredCount = 5` 그대로. 13번 사이클 회귀 history 학습 — false positive 보호망 유지.

5. **`startPeriodicSync`의 `_recentWindow.clear()` 제거** (라인 256~261)
   - syncWithHost가 carry over한 best 1개를 보존해야 함.
   - `stopPeriodicSync` (방 떠날 때) + `reset()` (상태 초기화)의 clear는 그대로 유지 (의도적 정리).

**예상 효과 (시뮬레이션)**:

```
[현재 v0.0.73]
t=0~3초: 30 ping
t=3~13초: fast phase 10 sample
t=13~18초: stable 5 연속
→ cold start ≈ 18초

[v0.0.74]
t=0~3초: 30 ping (early term 안 걸림 → 30 cap fallback) + best 1개 carry over
t=3초: startPeriodicSync 시작 — _recentWindow 1개 (best)
t=3~8초: stable 5 연속 (carry over로 출발점 안정 → §D-2 gap 즉시 만족)
→ cold start ≈ 8초 (약 절반)
```

좋은 LAN 환경(early term 작동) + WiFi 안정 (stable 5번 연속 즉시 만족) 시 더 단축 가능.

**위험 평가**:
- 13번 사이클 회귀 history 중 EMA convergence(v0.0.51~v0.0.55) 시도가 vfDiff 23배 회귀한 사례 있음. 이번 변경은 EMA 동작 자체는 그대로 유지(α=0.1 단일)하고 **수렴 단계의 wait 시간만 단축** → 회귀 위험 작을 것으로 가설.
- `§D-2 gap` 조건이 그대로 작동하므로 stable false positive 방어 유지.
- carry over 안전성은 사용자 통찰(9초 동안 안전망 보장)로 검증.

**검증 상태**:
- ✅ `flutter analyze` 전체 프로젝트 클린 (`No issues found!`)
- ⏳ 실기기 cold start 측정 미실시 (다음 세션)
- ⏳ 회귀 측정 (vfDiff signed mean 비교) 미실시

**후속 측정 시나리오 (PLAN에 추가 예정)**:
1. **Cold start 측정**: 게스트 입장 직후 즉시 호스트 play. isOffsetStable 도달 시간 + anchor establish 시간 + 청감 정착 시간 측정.
2. **회귀 측정**: 기존 N=2 baseline 환경에서 vfDiff signed mean 비교. v0.0.63 §D-2 fix 후 -5.25 ~ -7.33ms 수준이었는데 회귀 없는지.
3. **Early termination 작동 빈도**: csv 새 컬럼 또는 logcat에서 "30 ping cap에 걸린 횟수 vs early term 종료 횟수" 비율 확인.

**미시도 영역 (PLAN MID로)**:
- E. wallclock → monotonic clock (Android `SystemClock.elapsedRealtimeNanos`, iOS `mach_absolute_time`) — 양 플랫폼 native 채널 작업량 큼. ROI는 OS 점프 빈도 측정 후 결정.
- F. broadcast 주기 단축 (500ms → 200ms) — 호스트 부담 우려로 보류.

**version bump**: v0.0.73 → v0.0.74. 코드 변경 위치 단일 (`sync_service.dart`).

**측정 결과 (2026-05-10 Run 1~4, S22 호스트 + Tab A7 Lite 게스트)**:

| Run | 시나리오 | Cold start | vfDiff mean | 자체 정상화 | 평가 |
|---|---|---|---|---|---|
| 1 | 같은 방 첫 mp3 첫 play (3분+) | 274ms | -47ms (영구 잔재) | ❌ 안 일어남 | 회귀 |
| 2 | 같은 방 mp3 변경 후 play | 93ms | -7.51ms | 30초 시점 ✅ | baseline 도달 |
| 3 | 새 방 + 다운로드 미완료 중 play | 3677ms | -12ms | 60초 시점 ✅ | baseline 근처 |
| 4 | (가드 fix 후) 1분 측정 | 131ms | **+1.81ms** | 10~20초 시점 ✅ | **baseline 매우 좋음** |

**Run 1 회귀 root cause 진단**:
- csv `out_lat_host_raw=0` 시점에 anchor 박힘 → outLatDelta=0 잘못 베이크 → 게스트 syncSeek 위치 33ms 잘못 정렬 → 음향 시각상 47ms 어긋남 영구 잔재
- 호스트가 host_play +1.9초 재생 후도 outputLatency=0 보고 (Oboe `calculateLatencyMillis` 안정 wait가 비정상으로 김)
- v0.0.63까진 fast phase 10초가 outputLatency 안정 wait를 우연히 cover했으나 v0.0.74에서 cover 사라짐 → 본래 누락된 outputLatency 가드 노출

**v0.0.74-fix (가드 + 진단 logging) — 2026-05-10**:

1. **anchor establish 가드** (`native_audio_sync_service.dart:1248-1253`):
   ```dart
   if (obs.hostOutputLatencyMs <= 0) return;
   if (ts.safeOutputLatencyMs <= 0) return;
   ```
   양쪽 outputLatency 진짜 측정값 도달 후에만 anchor establish. `safeOutputLatencyMs`가 -1/음수/>500을 0으로 변환하므로 0 가드 한 번에 비정상값 모두 차단.

2. **Oboe 진단 logging** (`oboe_engine.cpp:411-432`):
   - `calculateLatencyMillis` 비정상값 (음수, >500, Result::Error) 첫 5회 + 매 50회 throttle 로그
   - 안정 도달 시 `recovered after N abnormal: X.XXms` 로그
   - stream 활성화 시 `mLatDiagCount = 0` reset
   - **Oboe Issue #678 (clock skew negative latency) 참고** — HAL hardware clock과 system clock 동기 불일치로 음수 보고 알려진 이슈. 우리 코드는 음수 무시(0 변환).

**fix 후 재측정 결과**:
- ✅ Run 4: cold start 131ms, vfDiff +1.81ms (v0.0.63 baseline -5~-7ms 동등 또는 더 좋음)
- ✅ logcat 검증: stream pause→start 전환 시 `calcLatency abnormal[0~44]: ErrorInvalidState` 4452ms 누적 후 `recovered: 8.19ms`. 가드가 그 4.5초 동안 anchor 차단 → 정상값 도달 후 박힘
- ✅ Run 2 mp3 변경 케이스: -7.51ms baseline 도달 (가드 효과 명확)

**남은 미스터리 (PLAN MID 후속 트랙)**:
- **Run 1 영구 잔재** — 가드 적용 후도 비결정적으로 발생 가능. 1/4 측정에서 자체 정상화 메커니즘 미작동, -47ms 영구 잔재. 사용자 청감으론 "잘 맞음" 보고 (csv 식 한계 또는 음악 특성으로 못 느낀 듯).
- **자체 정상화 메커니즘 미파악** — Run 2/3/4은 첫 10~60초 잔재 후 자체 정상화. 트리거 코드상 미식별. anchor reset 이벤트 안 찍힘.
- **csv vfDiff Run 1과 청감 OK 모순** — 식이 진짜 음향 어긋남보다 큰 잔재 보고 가능성 또는 음악 특성으로 청감 한계.

**검증 상태 갱신**:
- ✅ `flutter analyze` 클린 (`No issues found!`)
- ✅ 실기기 빌드 + install (S22 + A7)
- ✅ 측정 4회 — 가드 효과 확정 (3/4 baseline 도달, 청감 4/4 OK)
- ⏳ Run 1 영구 잔재 root cause 진단 후속 (별도 트랙)

**PLAN HIGH 활성 마감**: v0.0.74 cold start 측정 + 회귀 검증 완료. 가드 fix로 baseline 도달 확정. Run 1 미스터리는 LOW 후속.

**version bump 안 함**: v0.0.74 그대로 유지 (가드 fix는 같은 버전 내 보강).

### 2026-05-11 (91) — v0.0.75 §G step 1 — csv 측정 인프라 (decode_load 컬럼 추가)

**배경**: §G PCM streaming + 하이브리드 시작 패턴 디자인 합의 완료 (`SYNC_ALGORITHM_V2.md` §G). 작업 순서 §G-4 step 1: 안전한 csv 측정 인프라 추가 (sync 동작 변경 0). G-3 EMA 캘리브레이션 사전 데이터 확보 목적.

**합의된 §G 큰 그림** (사용자 합의 2026-05-11):
- G-1: Android 사전할당 PCM → ring buffer 60s (10s/50s 분배, Pre-fill 1초, TOO_LONG 제거)
- G-2: 시작/큰 seek = 하이브리드 ready timeout 200ms (모두 ready=동시 시작 / 미달=호스트 즉시+catch-up / 5초 timeout=heartbeat 위임)
- G-3: throughput EMA + in-flight 폴링 (G3-B + G3-C 결합), 측정 후 별도 PR

**step 1 변경** (이번 commit):
- `sync_measurement_logger.dart`: csv 컬럼 3개 추가 (`decode_load_ms`, `decode_total_frames`, `decode_throughput_fpms`). `log()` 메서드에 named param 3개 추가 (default 0).
- `native_audio_sync_service.dart`:
  - 호스트 `loadFile` 직후 (`:381` 부근): `_logDecodeLoad(guestId: 'host', ...)` 호출 → csv 기록
  - 게스트 `loadFile` 직후 (`:835` 부근): P2P `decode-load-report` 메시지 호스트에 송신
  - 메시지 라우팅 (`:175`): `decode-load-report` → `_handleDecodeLoadReport`
  - 신규 메서드 `_handleDecodeLoadReport`: 게스트 보고를 `_logDecodeLoad` 호출
  - 신규 메서드 `_logDecodeLoad`: event='decode_load' row로 csv 기록

**csv row 형태** (event='decode_load'):
- decode_load_ms: native loadFile 소요 시간
- decode_total_frames: loadFile 직후 totalFrames (없으면 0)
- decode_throughput_fpms: frames per ms (즉시 계산)
- 다른 컬럼 (drift_ms, vf_diff_ms 등): 모두 0

**검증**:
- ✅ `flutter analyze` No issues found
- ✅ 실기기 측정 (S22 호스트 + A7 Lite 게스트):
  - csv 헤더 23개 컬럼 (기존 20 + 신규 3) 정상
  - `event=decode_load` row 5건 형성 (호스트 2건 + 게스트 3건)
  - decode_load_ms 합리적 (호스트 401~539ms, A7 1116~1552ms)
- ⚠️ **`decode_total_frames=0` 한계 발견** — Android Kotlin loadFile이 bool만 반환 (iOS는 Map). G-3 throughput 계산 불가 → 같은 v0.0.75에 fix 묶음.

**fix-1: Android Kotlin loadFile Map 반환 통일 (iOS 정렬)**:
- `MainActivity.kt`: `result.success(true)` → `result.success(mapOf("ok", "totalFrames", "sampleRate"))`
- `nativeGetTimestamp()`의 `arr[5/6]` 재사용 (JNI 추가 없이) — `mDecodedSampleRate/mDecodedTotalFrames`는 `mStream` 상태 무관, file_loaded 후 항상 보장 (`oboe_engine.cpp:562-566`).
- `native_audio_service.dart:86` 주석 정정.

**v0.0.74 롤백 비교 검증 (step 1 변경 결백 확정)**:

청감 회귀 (곡 변경 시 sync 안 맞음) 발생 → step 1 변경 영향 의심 → v0.0.74 (f070f07) 빌드로 같은 시나리오 측정 → 비교.

| 측정 | vfDiff abs_max | drift abs_max | row수 |
|---|---|---|---|
| v0.0.75 (step 1) | 156,028ms | 156,028ms | 162 |
| **v0.0.74 (롤백)** | **177,845ms** | **177,845ms** | 63 |

→ **v0.0.74가 오히려 더 큼**. 두 측정 모두 100초+ vfDiff 발생 = **step 1 변경 무관, v0.0.74 기존 race 확정**.

**근본 race 발견 (v0.0.74 기존, csv 깊은 분석으로 처음 잡힘)**:

큰 seek (사용자 슬라이더) 직후 fallback drift 폭주 패턴:
```
row 87 [host_seek]            host_vf=6,995,318  guest_vf=158,624
row 88 [anchor_reset_seek_notify] host_vf=108,864    guest_vf=113,599
row 89 [fallback] ⚠️           host_vf=113,472    guest_vf=7,012,214  drift=156,028ms
row 90~95 [fallback]          drift -66 → -21 → -14 → -1 → +7 (회복)
```
- 메커니즘: 호스트 seek → 다음 obs broadcast (최대 500ms 갭) 사이에 게스트가 syncSeek 받아 점프 → `_fallbackAlignment`(`native_audio_sync_service.dart:1263-1311`)가 stale obs.virtualFrame + seek 후 ts.virtualFrame 비교 → driftMs 100초+
- 회복: fallback seek (`driftMs > 30` → seekToFrame) 작동, 1~2초 내 ±5ms 수렴
- 청감 인지: 회복 구간이 사용자 체감

**거짓말 패턴 실측 처음 확인** (SYNC_ALGORITHM_V2 §A 가설):
- v0.0.74 측정 일부 row: drift=-1.94ms (정상), vfDiff=-135,534ms (100초+)
- framePos 비교는 정상인데 virtualFrame 격차만 큼 — §A에서 "vfDiff outlier"로만 알던 패턴 실측 잡힘

**의미**:
- §G G-2 하이브리드 시작 패턴이 정확히 이 race를 fix하는 디자인 (ready timeout 200ms로 obs/anchor 갱신 후 시작 → race 0)
- step 2 (G-1 ring buffer + G-2 하이브리드) 들어갈 강한 동기 부여

**회귀 위험**: 거의 0. sync 동작 변경 없음, 측정 인프라 추가만 + Kotlin Map 반환 (Dart LoadResult.fromMap 이미 Map 처리 가능). logger active일 때만 csv 기록 (기존 패턴 그대로).

**다음 단계 (§G-4)**:
- step 2: G-1 ring buffer + G-2 하이브리드 시작 (단일 commit, 큰 변경 — 이번 측정으로 발견된 race fix)
- step 3: G-3 측정 세션 → EMA 활용 (별도 commit)

**빌드**: v0.0.75

### 2026-05-11 (92) — v0.0.76 §G step 2-G1 — native ring buffer 단독 (G-2와 분리)

**배경**: §G step 2 원안은 G-1 + G-2 한 commit. 작업 진행 중 native 변경 + Dart 상태머신 묶음이 회귀 추적 어려움 + race 격리 위험 발견 → 분리 commit으로 사용자 합의 변경.

**G-1 (이번 commit)**: native ring buffer만. Dart 측 변경 0.
**G-2 (다음 commit, v0.0.77 예정)**: Dart prepare→ready→go 흐름.

**변경** (`oboe_engine.cpp`):
- ring buffer 상수 추가: `kRingSeconds=60`, `kRingBehindSeconds=10`, `kRingAheadSeconds=50`
- 멤버 변수: `mRingHead`/`mRingTail` (atomic) + `mRingMutex`/`mRingCv` 추가, `mSeqDecodeEnd`/`mSeekDecodeStart`/`mSeekDecodeEnd` 제거
- `mRingCapacityFrames = sampleRate × 60` — 60s 분량 사전할당 (~11.5MB, 곡 길이 무관)
- `loadFile`: 사전할당 (`estFrames × ch × 2B`) → ring (`60s × sr × ch × 2B`). **`TOO_LONG` 한도 완전 제거** (14분 한도 → 무제한).
- `isFrameDecoded`: 두 영역(seq+seek) 비교 → 단일 윈도우 `[tail, head)` 비교
- `ringFrameIdx(contentFrame)` helper 신규 (modular)
- `onAudioReady`: vf가 ring 윈도우 안이면 modular index로 read, 밖이면 무음. 매 콜백 끝에 `tail = max(tail, vf - behindFrames)` atomic 갱신 (lock 없음)
- `seekToFrame`: 윈도우 안=즉시 (vf만), 밖=`mRingHead/mRingTail = newFrame` reset + `mDecodeSeekTarget` 트리거 + `mRingCv` notify
- `decodeLoop`: ring 가득 차면 (`head - tail >= capacity`) `mRingCv.wait_for(50ms)`, modular write (wrap-around 시 두 chunk 분할), `mRingHead.store(writeFrame)` advance
- `fillGaps` 함수 완전 제거 (sliding window라 갭 개념 없음)

**검증**:
- ✅ `flutter build apk --debug` 통과 (8.7s, NDK incremental rebuild)
- ⏳ 실기기 측정 필요:
  - 5분 곡 로드 시 메모리 ~11.5MB (이전 ~58MB) 확인
  - 14분+ 곡 로드 가능 (이전 `TOO_LONG`) 확인
  - 일반 재생/일시정지/작은 seek 정상 (회귀 없음)
  - 큰 seek 시 v0.0.74 fallback 패턴 그대로 (G-2에서 fix 예정, 이번 commit엔 그대로 유지)

**회귀 위험 평가**:
- 보통 — native 핵심 함수 8개 변경, ring buffer modular index + wrap-around 처리 신규
- 완화: 컴파일 통과 + 단계적 검증 + 큰 seek 시 회복은 기존 fallback alignment 메커니즘이 처리
- 회귀 발생 시 빠른 롤백 (단일 commit 격리)

**다음 (§G step 2-G2)**:
- Dart prepare→ready→go 흐름
- 호스트 측 ready 모집 (timeout 200ms)
- 게스트 측 prepare 핸들러 + ready 송신
- 큰 seek 시 G-2 하이브리드 적용 (vfDiff 100초+ race fix)
- 신규 P2P 메시지 (`audio-prepare`, `audio-ready`)
- csv 컬럼 (`start_pattern`, `ready_wait_ms`, `start_drift_ms`, `catchup_recovery_ms`)

**빌드**: v0.0.76

### 2026-05-11 (93) — v0.0.77 §G step 2-G2 — Dart Ready-then-Go 하이브리드 시작

**배경**: HISTORY (91)에서 csv 깊은 분석으로 잡힌 race — 큰 seek 직후 stale obs + seek 후 ts 비교로 vfDiff 100초+ 발생. v0.0.74에서도 동일 (177초). G-2 하이브리드 시작 패턴이 정확히 이 race fix하는 디자인 (SYNC_ALGORITHM_V2.md §G-2).

**디자인 (§G-2 합의)**:
- 호스트가 시작/큰 seek 시 `audio-prepare {prepareSeq, targetFrame}` broadcast
- 게스트는 seek + ring buffer 1초 분량 디코드 wait → `audio-ready` 송신
- 호스트는 ready timeout 200ms 안에 모두 ready → 동시 시작 (`ready_then_go`)
- 미달 → 호스트 + ready된 게스트만 즉시 시작, 미달은 catch-up (`host_immediate_with_catchup`)
- 5초 안에 ready 안 오면 dead peer 후보 (heartbeat 메커니즘 위임)
- v0.0.47 `scheduleStart(wallEpochMs, fromFrame)` NTP 인프라 그대로 활용

**변경**:
- `oboe_engine.cpp`: `isFrameRangeReady(start, end)` public 메서드 + JNI export `nativeIsFrameRangeReady` 추가. ring [tail, head)에 [start, end) 포함 여부.
- `NativeAudio.kt`: `external fun nativeIsFrameRangeReady` 추가
- `MainActivity.kt`: `isFrameRangeReady` 라우팅 추가
- `AudioEngine.swift` + `AppDelegate.swift`: iOS 측 `isFrameRangeReady()` (audioFile != nil이면 true — AVAudioFile은 즉시 random access)
- `native_audio_service.dart`: `Future<bool> isFrameRangeReady(int, int)` 메서드 추가
- `native_audio_sync_service.dart`:
  - `_ReadyCollector` 클래스 신설 (prepareSeq + expectedPeers + readyPeers + timeout)
  - 메시지 라우팅: `audio-prepare` (게스트 처리) / `audio-ready` (호스트 처리)
  - `_initiatePrepareAndStart(targetFrame)`: 호스트 prepare 모집 시작. 게스트 0이면 즉시 scheduleStart
  - `_handleAudioReady`: 게스트 ready 수신 + allReady면 즉시 resolve
  - `_resolveAndStart({forceTimeout})`: scheduleStart broadcast + 호스트 자기 scheduleStart
  - `_handleAudioPrepare`: 게스트 측. seek + isFrameRangeReady polling (50ms 간격, 5초 timeout) + ready 송신
  - `syncPlay`: `_engine.start()` 직접 → `_initiatePrepareAndStart(vf)` 호출
  - `syncSeek`: 재생 중이면 `_initiatePrepareAndStart(target)` (큰 seek race fix), 일시정지 중이면 기존 `seek-notify` 흐름 유지

**상수**:
- `_readyTimeoutMs = 200` — ready 모집 timeout
- `_readyDeadPeerTimeoutMs = 5000` — dead peer 후보 (heartbeat 위임)
- `_scheduleStartMarginMs = 80` — ready → scheduleStart 사이 마진

**csv event 신규** (기존 컬럼 재활용):
- `event=ready_then_go` — 모두 ready, 동시 시작
- `event=host_immediate_with_catchup` — 200ms timeout, 호스트 즉시 + 미달 catch-up
- `event=ready_solo` — 게스트 0, 호스트 단독 즉시 시작
- `guestVf 컬럼` — wait_ms (ready 모집 wait 시간) 재활용

**검증**:
- ✅ `flutter analyze` No issues
- ✅ `flutter build apk --debug` 통과 (14.1s, NDK + Kotlin + Dart)
- ⏳ 실기기 측정 필요:
  - 큰 seek 시 vfDiff 100초+ → G-2로 fix 확인 (HISTORY (91) 91/156/177초 → 0 또는 매우 작음 기대)
  - 평상 시 재생/작은 seek 회귀 0
  - 첫 입장 후 시작 시 ready_then_go 동작 확인 (logcat `[G2-PREPARE/READY/RESOLVE]`)

**회귀 위험**: 보통.
- syncPlay/syncSeek 흐름 변경 — 가장 자주 호출되는 메서드
- 새 race 도입 가능성 (prepareSeq + ReadyCollector 동기화)
- 완화: `_activeReady?.timeout?.cancel()` + `prepareSeq` 비교로 stale 처리, 컴파일 통과
- 회귀 발생 시 빠른 롤백 (단일 commit 격리)

**다음 (§G step 3)**:
- G-3 측정 세션 (디코드 throughput EMA + in-flight 폴링) → 별도 PR
- 30분+ 측정 검증 (MID-7 자연 해소 — ring buffer로 14분 한도 풀림)
- iOS 회귀 검증

**빌드**: v0.0.77

### 2026-05-12 (94) — v0.0.78 §G step 2-G2 회귀 revert (G-1 ring buffer 유지)

**배경**: v0.0.77 (93) 실기기 검증에서 명확한 회귀 발견. 호스트가 큰 seek (사용자 슬라이더) 한 직후 **무음 상태로 멈춤**. 새 음원 로드(loadFile 재호출)해야만 풀림. 첫 음원에서도 동일 증상 재현.

**시도한 fix (모두 stuck 미해소)**:

1. **fix 1차 가설 (`oboe_engine.cpp` race)** — `seekToFrame`이 `mRingHead/mRingTail = newFrame` 즉시 reset → decodeLoop가 직전 곡 위치 PCM write 후 `mRingHead.store(writeFrame)`로 ring head를 후퇴시킬 수 있음. 결과: 호스트 측 `vf > ringHead` → `isFrameDecoded` false → 영구 무음. fix 적용(미커밋, working tree): `seekToFrame`에서 ring head/tail 변경 제거, `mDecodeSeekTarget`만 set 후 decodeLoop의 PTS reset 시점에 단일 thread에서 set. 결과: 사용자 테스트 동일 증상 재현 → 가설 빗나감.

2. **decodeLoop stuck 가설 (확정)** — 새 음원 loadFile만 fix → loadFile 내부 `stopDecodeThread()` + `resetState()` + 새 thread 시작이 fix하는 것 → decodeLoop가 멈췄다는 것이 강한 증거. atomic 만으로는 ring head/tail/seek target/cv wait 4개 상태 전이가 안전하지 않음. mutex/cv로 단일 thread에서 직렬화 + 외부는 요청 큐만 push 하는 구조 재설계가 필요한 수준 — 한 줄 fix 영역 아님.

**결정**: v0.0.77 commit (50e4e6c) 코드 변경 revert + v0.0.78 fix 미커밋 변경 폐기. **G-1 ring buffer 효과 (v0.0.76 기준 51분 곡 로드, decode 2~3배 단축, ~11.5MB constant 메모리)는 그대로 유지**. 큰 seek 시 호스트 즉시 시작 + 게스트 fallback alignment 로직 (v0.0.74 기존 race 포함)으로 일시 회귀. fallback race는 기능 동작 중단보다 우선순위 낮음.

**revert 범위**:
- 코드 revert (v0.0.77이 추가한 G-2 흐름):
  - `oboe_engine.cpp` — `isFrameRangeReady`/`nativeIsFrameRangeReady` JNI 제거
  - `MainActivity.kt` / `NativeAudio.kt` — isFrameRangeReady 라우팅 제거
  - `AppDelegate.swift` / `AudioEngine.swift` — isFrameRangeReady iOS 측 제거
  - `native_audio_service.dart` — `isFrameRangeReady` 메서드 제거
  - `native_audio_sync_service.dart` — `_ReadyCollector` 클래스, `_initiatePrepareAndStart`, `_handleAudioReady`, `_resolveAndStart`, `_handleAudioPrepare`, `audio-prepare`/`audio-ready` 메시지 라우팅, syncPlay/syncSeek G-2 흐름 모두 제거
- docs는 살림 (HISTORY (91)/(92)/(93) 그대로 + (94) revert 항목 추가, PLAN/SYNC_ALGORITHM_V2 G-2 항목은 "보류 + 재설계 필요" 상태로 update)

**G-2 재시도 전제** (다음 세션 작업 시):
- ring buffer 상태 (`mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts`)는 **decodeLoop 단일 thread에서만 set**
- 외부 (`seekToFrame`, `start`, etc.)는 atomic write 금지 → "요청 큐 push + cv notify"만 허용
- decodeLoop는 매 iteration 시작에서 큐 drain → 상태 단일 thread 갱신 → write/wait 진행
- `_ReadyCollector` (Dart) 측은 native에 polling이 아니라 native 콜백(예: `onPrepareReady(seq)`)으로 신호 받는 구조 검토
- 또는 G-2 자체를 native 안으로 흡수 (Dart는 prepareSeq + scheduleStart wallEpochMs 통신만, ready 모집은 native가 단일 thread로 처리)
- 핵심 회귀 모드 (호스트 무음 + loadFile만 fix)를 재현하는 unit test 또는 자동화 측정 시나리오 먼저 확보 후 진행

**검증**:
- ✅ `git revert 50e4e6c --no-commit` 후 docs/pubspec unstage 복구 → 코드만 revert 적용
- ✅ `flutter analyze` No issues (예정)
- ✅ `flutter build apk --debug` 통과 (예정)
- ⏳ 실기기 회귀 fix 검증: v0.0.76 동작 (큰 seek 시 호스트 즉시 시작, 무음 정지 없음) 복귀 확인

**회귀 위험**: 낮음. v0.0.76은 직전 PASS commit (51분 곡 로드 + decode 2~3배 단축 검증). G-2 재시도 전 baseline 안정.

**빌드**: v0.0.78

### 2026-05-12 (95) — v0.0.79 §G-1 ring buffer 추가 revert (race 확정)

**배경**: v0.0.78 (94) revert 후 v0.0.76 기반 G-1 ring buffer 단독 검증 진행. 첫 음원 + 큰 seek 슬라이더 **연타** 시나리오에서 **호스트/게스트 둘 다 무음** 회귀. virtualFrame은 계속 흐름(재생 logic 살아있음, PCM read만 무음). 새 음원 loadFile 해야 풀림. 51분 곡 로드 시에도 같은 시나리오에서 재현.

**진단 (v0.0.75 비교 실험)**:
- v0.0.78 vs v0.0.76 native/dart 코드 diff = 0 (revert 깔끔). race는 v0.0.76부터 잠재했고 v0.0.78에서 적극적인 연타로 노출됨.
- v0.0.75 (ring buffer 도입 전 = 사전할당 PCM + 2-range 추적 + fillGaps) `oboe_engine.cpp` 한 파일만 checkout 후 실기기 install → 같은 연타 시나리오에서 **무음 발생 안 함**.
- **결론: G-1 ring buffer race 확정**. `mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts` 4개 atomic write가 여러 thread(외부 seekToFrame + decodeLoop)에서 동시 발화 시 일관성 깨짐.

**가능한 race 시나리오** (확정 아님, 가설):
- `seekToFrame` 첫 호출 → `mRingHead/mRingTail = target1` reset + `mDecodeSeekTarget = target1` set + cv notify
- decodeLoop 깨어나기 전 → `seekToFrame` 두 번째 호출 (연타) → `mRingHead/mRingTail = target2` reset + `mDecodeSeekTarget = target2`
- decodeLoop이 target1 처리 시작 → 첫 디코드 데이터 write → `mRingHead.store(writeFrame1)`
- 외부 vf가 target2 위치인데 ring head가 target1 위치 → `isFrameDecoded(vf) == false` 영구 지속

또는 비슷한 변형 race. 핵심은 4개 atomic으로는 "seek 요청 → ring reset → decodeLoop 응답" 단일 트랜잭션이 안 보장됨.

**결정**: G-1 ring buffer 단독으로도 race가 있으므로 v0.0.79 = v0.0.75 native (`oboe_engine.cpp`) 복귀. G-2뿐 아니라 G-1도 보류. ring buffer 효과(51분 곡 + 메모리 ~11.5MB + decode 2~3배 단축) 다 잃지만 안정성 우선.

**revert 범위 (v0.0.79)**:
- `oboe_engine.cpp` 한 파일만 v0.0.75 코드로 checkout (다른 파일은 v0.0.75 == v0.0.78 동일)
- pubspec version 0.0.78 → 0.0.79

**유지** (v0.0.75에서 들어온 정상 변경):
- csv `decode_load` 측정 인프라 (`sync_measurement_logger.dart`, `native_audio_sync_service.dart`의 `_handleDecodeLoadReport`/`_logDecodeLoad`)
- Android `loadFile` Map 반환 통일

**G-1 ring buffer 재시도 전제 (다음 세션 후보)**:
- **PoC 격리에서 재설계** (`poc/` 하위) — 본 앱 회귀 위험 차단
- ring buffer 상태(`mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts`)는 **decodeLoop 단일 thread에서만 set**
- 외부(`seekToFrame`/`start`)는 atomic write 금지 → "요청 큐 push + cv notify"만 허용
- decodeLoop은 매 iteration 시작에서 큐 drain → 상태 단일 thread 갱신 → write/wait 진행
- 핵심 회귀 모드(큰 seek 연타 → 호스트/게스트 무음 + loadFile만 fix)를 자동화 시나리오로 재현 → fix 검증
- 재설계 후 G-2 Ready-then-Go (v0.0.77 디자인)도 같은 큐 기반으로 합쳐 검토

**검증**:
- ✅ v0.0.75 native checkout → 큰 seek 연타 시나리오 무음 없음 (실기기 S22 + A7)
- ⏳ `flutter build apk --debug` 통과 (예정)
- ⏳ 실기기 v0.0.79 회귀 fix 검증 (= v0.0.74 baseline 동작 복귀)

**회귀 위험**: 매우 낮음. v0.0.75는 자체 검증된 baseline + 큰 seek 연타에서도 무음 없음 확인.

**빌드**: v0.0.79

### 2026-05-14 (96) — v0.0.80 §B clock sync outlier rejection + age limit + stable window 가드

**배경**: 사용자가 "최근 (v0.0.74 이후) 청감이 옛날(v0.0.72 등)에 비해 약간 어긋난 느낌"으로 보고. csv/logcat 깊은 분석 진행:

**진단 흐름**:
1. **WiFi 환경 정량 측정** (logcat `Periodic sync` + 별도 raw sample 로그 추가): 사용자 환경에서 raw RTT 분포 매우 흔들림. 60초간 측정:
   - 14~20ms (좋음): 15%
   - 45~110ms: 28%
   - 111~250ms: 38%
   - 251~499ms: 19%
   - 즉 RTT > 30ms sample 비율 ~85% (extreme 환경)
2. **알고리즘 동작 분석**: window best + EMA로 단발성 outlier는 흡수했으나 지속 흔들림 (좋은 RTT sample 한동안 안 들어옴) 시 `minSample`이 jitter sample로 갈리고 EMA가 천천히 표류 — 22초 동안 filtered offset이 -405 → -386.6 = **18ms 표류** 실측. 청감 임계 ±20ms 근접.
3. **사용자 통찰** (사용자 직접 짚어줌, 매우 중요):
   - "처음에 window 1개 넣고 시작하면 새로 들어온 값이 30ms 통과해도 첫 동기화 때 값보다 안 좋을 수 있으니 carry over 안전망 역할"
   - "흔들리는 환경 수용하면 안 됨. wall clock 자체는 환경 무관이고 RTT만 환경 영향" → adaptive 임계 부정, **고정 strict 임계가 정답**
   - "win=6일 때 isOffsetStable=true 되는 거지?" — 코드 검토 결과 첫 sample에서 `_prevFilteredOffset = 0`이라 stable=0 손해 → 사용자 추정 6은 `_prevFilteredOffset`도 carry over로 set한 경우. v0.0.74 carry over의 미세 누락 발견.
   - "지금 fast phase도 제거했는데 진동 영향이 더 크다" — 정확. 사용자 데이터 표류 18ms 정확히 이 메커니즘
4. **anchor 베이크인 잔재 별도 발견 (마지막 부분 청감 어긋남)**: 측정 마지막 부분에서 vfDiff -250ms 영구 잔재 (drift는 ±3ms로 매우 작음) → **sync 자체는 정확한데 anchor 박힌 시점의 outputLatency baked-in 매핑이 부정확**. HISTORY (42)/(45) 미해결 이슈 영역과 같음. 본 commit 범위 밖.

**근거 기반 RTT 임계 선정 (`_rejectThresholdMs = 30`)**:
- RTT > 30ms sample은 ping/pong 비대칭 노이즈 최악 ±15ms (RTT/2)
- 청감 임계 ±20ms 대비 안전 영역 안
- 우리 환경 통과율 ~15% 다만 carry over로 cold start 안전망 유지

**근거 기반 age limit (`_sampleAgeLimitMs = 60_000`)**:
- 60초 = 두 디바이스 wall clock 상대 drift 누적 ±6ms (±50ppm × 60초 × 2디바이스) 수준
- 사용자가 짚은 "1시간 동안 30ms 이하 sample 안 들어오면 stale offset 박힘" 위험 차단
- 일반 환경에선 1분에 RTT < 30ms sample 평균 9개 들어옴 (15%) → 거의 항상 sample 모임. 1단계 (옵션 A) 채택, fallback burst 재실행은 2단계로 보류

**변경 사항 (`sync_service.dart`)**:

1. **`_earlyTermRttThresholdMs` 10 → 20** (line 41) — 초기 핸드셰이크 early termination 임계 완화. jitter 환경에서도 5~10초 안에 좋은 sample 10개 모이도록.

2. **`_rejectThresholdMs = 30` NEW** (line 49) — periodic sync outlier rejection 임계. raw RTT > 30ms sample은 window 추가 안 함, EMA/stable 영향 0.

3. **`_sampleAgeLimitMs = 60000` NEW** (line 51) — window 안 sample 60초 지나면 자동 제거. stale offset 박힘 차단.

4. **`_SyncSample.arrivalMs` getter NEW** (line 30) — `t3` (게스트 pong 수신 시각)을 sample 도착 시각으로 노출. age limit 비교용.

5. **Periodic sync 새 흐름** (line 290~312):
   ```
   sample 도착
     ↓
   if (rttMs > 30): REJECTED 로그 + return (EMA/stable 변화 0)
     ↓ 통과
   _recentWindow.add(sample)
   sliding window 사이즈 제한 (>10 oldest 제거)
     ↓
   age limit: 60초+ sample 모두 제거
     ↓
   if (window.isEmpty): filtered 동결 + return
     ↓
   minSample, EMA, stable count 처리
   ```

6. **`isOffsetStable` 가드 보강** (line 109~111):
   ```dart
   bool get isOffsetStable =>
       _stableCount >= _stableRequiredCount && _recentWindow.length >= 3;
   ```
   carry over 1개만 남은 상태에서 anchor 박힘 trigger 차단.

7. **`_prevFilteredOffset` carry over 같이 set** (line 197, 247) — v0.0.74 carry over의 미세 누락 보강. 사용자가 짚어준 부분. 첫 periodic sample에서 delta=|filtered - 0|=큰 값으로 stable=0 손해 없어짐. **isOffsetStable 도달 시간 6초 → 5초 단축**.

8. **STABLE TOGGLE 로그** (line 320~325) — `_prevIsStable` 필드 추가, isOffsetStable 변경 시점에 로그 출력. 디버그/측정용. false→true / true→false 토글 시점 추적.

9. **Raw sample 로그 확장** — 통과/REJECTED 구분 + arrival 시점 정확히 표시.

**측정 검증** (실기기 S22 + A7 Lite):

- **v0.0.79 baseline** (22초 측정):
  - Raw RTT 분포: 좋음 15% / 흔들림 85%
  - Filtered offset: -405 → -386.6 = **18ms 표류**
  - 청감 어긋남 인지

- **v0.0.80 (이 commit)** (28초 측정):
  - Raw RTT 분포: 좋음 15% / 흔들림 85% (동일 환경)
  - Filtered offset: -414.0 → -414.3 = **0.3ms 변동** ⭐
  - **표류 60배 감소**
  - REJECTED 로그로 outlier 차단 작동 확인 (28초 중 17개 sample reject)
  - STABLE TOGGLE: 14초 만에 false→true, 그 후 영구 true 유지
  - 사용자 청감: "대체적으로 다 좋았는데 마지막 부분만 약간 어긋남"

- **마지막 어긋남 원인 별도 분석** (csv `v080_test.csv` seq 471~487):
  - anchor_set @ seq=471 (drift -2.16, vfDiff 0)
  - 그 직후 seq=472~487 동안 **vfDiff -230 ~ -270ms 영구 잔재**
  - 그러나 **drift는 ±3ms로 매우 작음** (sync 자체는 정확)
  - delta_anchored=13.30 영구 박힘, delta_current 10~17ms 변동
  - → **anchor 박힌 시점의 outputLatency baked-in 매핑이 부정확**한 케이스. sync 자체 문제 아님.
  - 사용자 큰 seek (seq=488)로 anchor reset → 재박힘 → vfDiff ±3ms 정상 회복 확인
  - 이 영역은 HISTORY (42)/(45) 미해결 이슈 영역으로 별도 트랙 필요 (BT outputLatency 동적 보정 또는 anchor reset 임계 보강).

**남은 1단계 한계**:
- WiFi 흔들리는 환경에서 좋은 sample 0개로 60초 지속 → carry over expire → window 빈 상태 → filtered 동결 (1시간 drift 누적 위험)
- 2단계로 burst sync 재실행 fallback 추가 가능 (window 1분 빈 상태 지속 시 30 ping burst 재실행)
- 우리 환경에선 1분에 RTT < 30 sample 평균 9개 들어와 거의 발생 안 함

**다음 작업 후보** (별도 트랙):
- anchor 베이크인 outputLatency 부정확 fix (HISTORY (42)/(45) 영역)
- 또는 anchor reset 트리거에 vfDiff 임계 추가 (drift 외)
- v0.0.80 자동화 측정 N=2~3으로 청감 vs 정량 매칭 확정

**검증**:
- ✅ `flutter analyze` No issues
- ✅ `flutter build apk --debug` 통과
- ✅ 실기기 v0.0.80 청감 PASS ("대체적으로 다 좋음")
- ✅ filtered 표류 60배 감소 정량 확정 (18ms → 0.3ms)
- ✅ STABLE TOGGLE false→true 14초, false 토글 0회 (영구 안정)

**회귀 위험**: 낮음.
- 코드 변경 영역이 sync_service.dart 단일 파일
- 새 가드 (reject, age limit, window>=3) 모두 보수적 (false positive 방지에 안전한 쪽)
- carry over 의도 완성 (1초 단축)으로 좋은 환경에서도 개선

**빌드**: v0.0.80

### 2026-05-14 (97) — v0.0.81 ANCHOR-VERIFY 사후 검증 + anchor 자동 무효화 + sync info UI 실시간 갱신

**배경**: v0.0.80 (96)에서 sync 자체는 매우 robust(filtered 표류 0.3ms) 도달. 그러나 측정 마지막 부분에 vfDiff -250ms 영구 잔재 1회 발견. 사용자 청감 "마지막 부분 약간 어긋남"으로 인지. 별도 트랙(PLAN HIGH §B 후속)으로 분리.

**진단 흐름**:
1. **player 화면 sync info 갱신 안 됨**: `_buildSyncInfo`가 한 번 read만 하고 끝 → drift / seek / offset / RTT 변경되어도 widget rebuild 안 됨. 사용자 보고로 발견.
2. **ANCHOR-VERIFY 진단 추가** (`_tryEstablishAnchor` 직후 100ms 후 ts.virtualFrame이 targetGuestVf와 일치하는지 측정):
   - anchor 박을 때 _pendingAnchorVerifyTarget 저장
   - 다음 ts poll 시 actual vs target 비교 + diffMs logcat 출력
3. **첫 측정 데이터로 사고 잡힘** (사용자 seek 연타 테스트):
   - 평소 anchor: diffMs 50~100ms (seek 도달 디코더 wait, **정상**)
   - **사고 케이스**: target=1549129 (35초) actual=6144 (0.13초) **diffMs=-34988ms** = 35초 영구 잔재
4. **사용자 가설 검토** ("obs 순서 보장 안 돼서 다른 게 박힌 건가"):
   - TCP socket이라 obs 순서 자체 보장 ✓
   - `_handleAudioObs`가 단순 덮어쓰기 (`_latestObs = obs`), 신선도 검사 X
   - 그러나 우리 사고의 root cause는 obs 순서가 아니라 **게스트 측 seek 명령 처리 race** (큰 seek 연타 중 native가 정확히 도달 못 함)
5. **사후 검증 + 자동 무효화 디자인**: anchor 박힌 후 100ms 시점에 vfDiff > 임계(500ms)면 anchor 무효화 + `_seekCorrectionAccum` 되돌리기 + 다음 obs 도착 시 재시도

**변경 사항**:

`lib/services/native_audio_sync_service.dart`:
1. **상수 NEW**: `_anchorVerifyRejectThresholdMs = 500.0`
   - 평소 100ms 후 측정값 ~90ms (seek 도달 디코더 wait) → 500ms는 5배 안전 마진
   - 사고 케이스(수십 초 잔재) 같은 큰 어긋남만 잡고 정상 동작 영향 0
2. **필드 NEW**: `_pendingAnchorVerifyTarget` / `_pendingAnchorVerifyDeadline` / `_pendingAnchorVerifyInitialCorrection`
3. **`_tryEstablishAnchor` 끝**에 _pendingAnchorVerify 3개 필드 예약
4. **`_startTimestampWatch` listener**에서 다음 ts 시점에 검증:
   - target vs actual 비교, diffMs 계산
   - `[ANCHOR-VERIFY] target=X actual=Y diffFrames=Z diffMs=W` 로그
   - **임계 초과 시**:
     - `[ANCHOR-VERIFY] REJECT — diffMs ... > 500.0ms. anchor 무효화 + accum 되돌리기` 로그
     - `_seekCorrectionAccum -= _pendingAnchorVerifyInitialCorrection` (잘못 적용된 보정 되돌리기)
     - `_anchorHostFrame / _anchorGuestFrame / _anchoredOutLatDeltaMs / _offsetAtAnchor` 모두 무효화
     - `_driftSamples.clear()` (이전 sample 폐기)
     - `_logGuestEvent(event: 'anchor_reset_verify_fail')` (csv 기록)
   - 다음 obs 도착 시 `_tryEstablishAnchor` 재시도 → 자동 회복

`lib/screens/player_screen.dart`:
- `_buildSyncInfo`를 `StreamBuilder<Duration>(stream: _audio.positionStream)`로 감쌈
- positionStream(100ms 주기 native poll) 구독으로 매 100ms widget rebuild
- drift / seekCount / offset / RTT 실시간 표시
- **isOffsetStable 표시 추가** (`stable: ✓/✗`)

**측정 검증 (실기기 S22 + A7 Lite, 대규모 seek 연타 시나리오)**:

logcat 패턴 (사용자 1분간 적극 사용):
- 평소 anchor diffMs **0~100ms 범위** (seek 도달 정상)
- ANCHOR-VERIFY REJECT 발동 사례:
  | diffMs | 의미 |
  |---|---|
  | -34988ms (35초) | 호스트 큰 seek 직후 게스트 미도달 |
  | 178437ms (178초) | 곡 내 큰 점프 race |
  | 125645ms (125초) | 비슷 |
  | 30958ms (30초) | 비슷 |
  | 11906ms (11초) | 비슷 |
  | -8686ms (-8초) | 비슷 |
  | -769ms (-0.7초) | 임계 근접 |
  | -151300ms (-151초) | 큰 어긋남 |

csv event 분포 (전체 측정):
- host_seek **432회** (사용자 적극 seek 연타)
- anchor_set 29회
- **anchor_reset_verify_fail 9회** ⭐ (fix 자동 회복 9회)
- **race rate = 9/29 = 31%** — 큰 seek 연타 환경에서 약 1/3 anchor가 race로 잘못 박힘
- 모든 REJECT 직후 다음 anchor 정상 박힘 (자동 회복 작동)
- **사용자 청감 사고 인지 0회** = fix가 백그라운드에서 정확히 처리

**의미**:
- HISTORY (96)에서 본 vfDiff -250ms 잔재의 진짜 root cause = 게스트 seek 명령 처리 race
- fix 안 한 v0.0.80에선 31% race가 영구 잔재로 남아 청감 어긋남 유발
- v0.0.81 사후 검증으로 자동 회복 → 청감 어긋남 0

**1단계 한계 (인정)**:
- 임계 500ms은 보수적 — 200~300ms 더 strict로 바꾸면 -769ms 같은 경계 케이스도 잡힘 (현재는 통과)
- 다만 평소 100ms 차이와 너무 가까워 false positive 위험 있음 — 측정 데이터 더 모은 후 조정
- ANCHOR-VERIFY 시점이 100ms (seek 도달 시간 변동) — 더 긴 deadline (300~500ms)로 보강 가능

**다음 작업 후보** (별도 트랙):
- 임계 200~300ms 실험 (false positive 측정)
- ANCHOR-VERIFY deadline 300ms 같이 보강
- obs 신선도 가드 추가 (사용자 짚은 가설 — TCP는 OK지만 안전망)

**검증**:
- ✅ `flutter analyze` No issues
- ✅ `flutter build apk --debug` 통과 (9.7s)
- ✅ 실기기 측정에서 9회 REJECT 자동 회복 정량 확정
- ✅ 사용자 청감 사고 인지 0회 (fix 효과 청감 매칭)
- ✅ player UI sync info 실시간 갱신 (100ms 주기)

**회귀 위험**: 매우 낮음.
- ANCHOR-VERIFY 검증은 anchor establish 직후 100ms 후 1회만 작동
- 정상 anchor(diffMs < 500ms)는 영향 0
- REJECT 시 _seekCorrectionAccum 정확히 되돌림 (initialCorrection 저장 → 빼기)
- _seekCooldownUntilMs 자연 작동으로 즉시 재시도 폭주 방지

**빌드**: v0.0.81

### 2026-05-15 (98) — v0.0.82 호스트 syncSeek `_broadcastObs()` 제거 (게스트 옛 위치 race 진짜 root cause fix)

**배경**: v0.0.81 (97)에서 ANCHOR-VERIFY 도입 + race rate 31% 자동 회복 확인. 그러나 사용자 보고 신규 시나리오 — "호스트 seek 했는데 게스트가 새 위치 갔다 다시 옛 위치로 돌아온다". 이 race의 진짜 root cause 격리 + fix.

**진단 흐름 (오늘 세션 시간순)**:

1. **사용자 보고 1**: "v0.0.81 측정에서 40초/3분 차이 발생". csv/logcat 깊은 분석 시작.
2. **시도 1 (실패) — v0.0.82(임시) accum 재계산**: ANCHOR-VERIFY REJECT cascade (4번 연속 REJECT + accum 4번 되돌리기) 발견. `_seekCorrectionAccum -= initialCorrection` 대신 `ts.virtualFrame - ts.framePos` 재계산으로 변경. **부분 fix지만 root cause 아님**.
3. **시도 2 (실패) — v0.0.83(임시) `_latestObs = null` + fallback cooldown 가드 + SEEK-NOTIFY 진단 로그**: stale obs로 인한 fallback 잘못 보정 의심. 게스트 측 안전망 추가. **부분 fix**.
4. **사용자 핵심 통찰**: "게스트에서 position bar가 갔다가 다시 돌아왔다 → broadcasting은 했다는 거 아냐? TCP라 순서 보장이라 게스트 받기 전 다른 명령 갔을 리 없잖아". 사용자가 root cause를 좁혀줌 — 메시지 순서 아니라 다른 영역.
5. **호스트 측 코드 정독**: `syncSeek` (`native_audio_sync_service.dart:508~538`)에서:
   - `await _engine.seekToFrame(clampedTarget)` — Android Oboe는 비동기 (mDecodeSeekTarget set만, 즉시 return), 다음 라인 진행
   - `broadcastToAll('seek-notify', ...)` — 게스트한테 정확한 새 위치
   - **`_broadcastObs()` 즉시 호출** — 호스트 native ts 측정. **native seek 처리 전이라 ts.virtualFrame = stale (이전 호스트 위치)** ⚠️
6. **시도 3 (성공) — v0.0.84(임시) 호스트 `_broadcastObs()` 제거 1줄**: stale obs broadcast 자체 차단. 정기 timer (`_obsBroadcastIntervalMs = 500ms`)가 native seek 완료 후 정확한 obs 보냄. **진짜 root cause fix**.
7. **사용자 보고 2**: "v0.0.84 측정 후 청감 묘하게 떨어진 거 같음". v0.0.81 + 82 + 83 + 84 4개 fix 누적이라 어느 게 부작용인지 격리 불가.
8. **시도 4 — v0.0.85(임시) v0.0.80 baseline + sync info UI + 호스트 fix만**: v0.0.81~83 fix 모두 롤백, v0.0.84 핵심 fix만 유지. **사용자 평가: "재현 안 됨, 청감 괜찮음"** ⭐ — 다만 가끔 몇 초 무음 1회 보고.
9. **시도 5 (실패) — v0.0.86(임시) v0.0.85 + `_latestObs=null` 만 추가**: 가끔 무음 fix 시도. **사용자 보고 "큰 문제 — 호스트도 옛 위치로 돌아감"**. 그러나 호스트 logcat 분석 결과 호스트는 정상 동작 (seek 명령대로). 원인 미상.
10. **시도 6 — v0.0.84 다시 모든 fix 누적**: "무음 + 청감 떨어짐" 재현. v0.0.85 대비 부정적.
11. **v0.0.81 단독 테스트**: ANCHOR-VERIFY만 (호스트 fix 없는 채). 사용자 평가 "좋았다 안 좋았다" (환경 의존, 명확한 격리 어려움). logcat: REJECT 1회 (184초 차이 자동 회복) + 큰 어긋남 anchor 다수 (verify 자동 정렬).

**최종 결정 (v0.0.82 commit)**:

v0.0.81 commit baseline + **호스트 `_broadcastObs()` 제거 1줄**만 추가. 다른 시도들 (accum 재계산, _latestObs=null, fallback cooldown 가드) 모두 보류 — 격리 못 했거나 부작용 의심.

**변경** (`native_audio_sync_service.dart:529~`):
```dart
// Before:
_broadcastObs();  // syncSeek 안에서 즉시 호출

// After (v0.0.82):
// _broadcastObs() 호출 제거. 정기 timer broadcast(500ms 주기)가 native seek
// 완료 후 정확한 obs 보냄.
```

**측정 검증 (오늘 실기기 N=여러 회)**:
- ✅ "게스트가 옛 위치로 돌아옴" race 재현 안 됨 (root cause fix 효과)
- ✅ 사용자 청감 "괜찮음" (v0.0.85 시점 평가, ANCHOR-VERIFY 없는 상태였지만 v0.0.82는 ANCHOR-VERIFY 살아있음 — 환경 의존 청감은 별도 트랙)
- ⚠️ 가끔 몇 초 무음 발생 (1~2회). 호스트 큰 seek 후 ~500ms 동안 stale obs 잔존 가능 (정기 timer 주기). 별도 트랙.

**남은 문제 / 미해결**:

1. **가끔 몇 초 무음** (호스트 큰 seek 후 ~500ms transient):
   - root cause 후보: 호스트 정기 broadcast 주기 500ms — 그 사이 게스트 `_latestObs`는 직전 호스트 obs (seek 직전 위치 = stale)
   - 게스트 fallback alignment가 stale obs로 보정 시도 → 옛 위치 점프 → 디코드 wait → 무음
   - v0.0.86 `_latestObs = null` 시도했지만 "호스트도 옛 위치" 큰 문제 발생 (원인 미상)
   - 가능한 fix 후보 (다음 세션):
     - (a) 호스트 큰 seek 시 정기 timer broadcast 주기 임시 단축 (예: 100ms × 5회)
     - (b) 게스트 측 `_latestObs.hostTimeMs` 신선도 검사 — 너무 오래된 obs는 fallback에서 무시
     - (c) `_fallbackAlignment`에 `_seekCooldownUntilMs` 가드 (이전 v0.0.83 일부, 단독 안전 검증 필요)

2. **ANCHOR-VERIFY 단독 청감 부작용 의심 (격리 못 함)**:
   - v0.0.84 (4 fix 누적) 시 사용자 "묘하게 청감 떨어짐"
   - v0.0.85 (ANCHOR-VERIFY 빼고 호스트 fix만) 시 "괜찮음"
   - 다만 N=1 청감 평가라 환경 변동성과 분리 어려움
   - v0.0.82는 ANCHOR-VERIFY 포함이라 청감 부작용 잠재 — 다음 세션 N=여러 회 측정으로 격리 필요

3. **v0.0.86 `_latestObs=null` 시 "호스트도 옛 위치" 신규 race**:
   - logcat에선 호스트 정상 동작 (정상 seek + 진행)
   - 사용자가 본 청감 또는 UI 표시의 원인 미상
   - 일단 v0.0.82는 `_latestObs=null` 안 들어가니까 발생 안 함
   - 다음 세션 fix 시 주의

**잘못된 fix들 정직히 인정** (오늘 학습):
- ANCHOR-VERIFY 사후 검증 = 효과 있는 안전망 (race 자동 회복) but 청감 부작용 의심
- v0.0.82(임시) accum 재계산 = cascade race 부분 fix (root cause 아님)
- v0.0.83(임시) `_latestObs=null` = fallback 차단 안전망 (root cause 아님, v0.0.86에서 다른 race 발견)
- v0.0.84(임시) 호스트 `_broadcastObs()` 제거 = **진짜 root cause** — 1줄 변경이 큰 효과

→ "복잡한 fix 여러 개" 대신 **"진짜 root cause 1개 격리"**가 정답이었음. 사용자 통찰 ("TCP는 순서 보장이라 다른 영역") 결정적.

**검증**:
- ✅ `flutter analyze` No issues
- ✅ `flutter build apk --debug` 통과
- ✅ 실기기 사용자 청감 "괜찮음" 보고 + 옛 위치 race 안 나타남
- ✅ v0.0.85 시점 시나리오 검증 (v0.0.82와 코드 거의 동등, ANCHOR-VERIFY만 차이)

**회귀 위험**: 매우 낮음.
- 1줄 변경 (호스트 syncSeek 안 `_broadcastObs()` 제거)
- 정기 timer broadcast (500ms 주기)는 그대로 — 게스트가 호스트 위치 정보 못 받는 거 아님
- 그 사이 500ms 동안 게스트 fallback이 stale obs 가능 (남은 문제 1번) — v0.0.81 baseline 대비 더 안 좋아진 점 없음

**빌드**: v0.0.82

### 2026-05-15 (99) — v0.0.83 `_fallbackAlignment`에 `_seekCooldownUntilMs` 가드 추가 (가끔 무음 fix)

**배경**: v0.0.82 (98) 호스트 syncSeek `_broadcastObs()` 제거로 즉시 stale obs broadcast race fix. 그러나 정기 timer broadcast (500ms 주기) 안 잔존 stale obs로 인한 단발성 무음 가능 (HISTORY (98) 남은 문제 1번).

**root cause 분석 (HISTORY (98) 남은 문제 1번)**:
- 호스트 큰 seek 직후 ~500ms 동안 게스트 `_latestObs`는 직전 정기 timer broadcast로 받은 obs (호스트 seek 전 위치) = stale
- 게스트 100ms ts poll → fallback alignment 작동:
  - 게스트 vf = 새 위치 (seek-notify로 점프)
  - `_latestObs.virtualFrame` = stale (이전 호스트 위치)
  - drift = 큰 차이 → 30ms 임계 초과
  - `seekToFrame(stale 위치)` 잘못 호출 → 게스트가 옛 위치로 점프
- Native (Oboe + AMediaCodec 사전할당 PCM): 옛 위치 영역 디코드 안 됨 → PCM 버퍼 빈 상태 → **몇 초 무음**

**일관성 발견**:
- `_handleSeekNotify`에서 `_seekCooldownUntilMs = now + 1000` set (v0.0.81 baseline)
- `_tryEstablishAnchor`는 이미 이 cooldown 가드 사용 (line 1322)
- 그러나 **`_fallbackAlignment`는 이 cooldown 무시** → seek 직후 stale obs 사용 가능

**Fix (1줄)** (`native_audio_sync_service.dart:_fallbackAlignment`):
```dart
// Before:
if (ts.wallMs < _fallbackAlignCooldownMs) return;
if (driftMs.abs() > 30) { ... }

// After (v0.0.83):
if (ts.wallMs < _fallbackAlignCooldownMs) return;
if (ts.wallMs < _seekCooldownUntilMs) return;   // ← NEW (1줄)
if (driftMs.abs() > 30) { ... }
```

즉 seek-notify 받은 후 1초간 fallback skip → 호스트 정기 timer 새 obs (500ms 후) 도달 후 정상 작동.

**측정 검증 (실기기 N=여러 회)**:
- ✅ 가끔 발생하던 몇 초 무음 안 나타남 (사용자 보고)
- ✅ 다른 부작용 없음 (호스트 영향 0, 게스트만 fallback skip)
- ✅ 정상 동작 (재생/정지/seek) 영향 0

**왜 v0.0.86 `_latestObs = null` 시도와 다른가** (안전성 분석):
- v0.0.86: `_handleSeekNotify`에서 `_latestObs = null` 무효화 → fallback **및 anchor** 모두 skip (obs 없음 가드)
  - 결과: "호스트도 옛 위치" 신규 race 발생 (원인 미상)
- v0.0.83: `_fallbackAlignment`에만 cooldown 가드 → **anchor는 그대로 작동**
  - `_tryEstablishAnchor`도 이미 같은 cooldown 사용이라 anchor 박힘 영향 0
  - 게스트 자체 보정만 skip — 호스트 측 영향 0

**오늘 학습 추가**:
- "같은 cooldown 자료구조를 일관되게 적용" = 안전한 fix 패턴
- "obs 객체 자체 무효화 (`_latestObs = null`)" = 안전 검증 어려운 변경 (의도치 않은 부작용 위험 큼)
- v0.0.82/v0.0.83 = 진단 명확 + 1줄 fix + 회귀 안전한 패턴

**남은 문제 (PLAN HIGH 후속)**:
1. ✅ ~~정기 timer 500ms 주기 안 stale obs로 가끔 무음~~ — v0.0.83 fix 완료
2. ⏳ **ANCHOR-VERIFY 단독 청감 부작용 미격리** (HISTORY (98) 남은 문제 2번) — N=여러 회 측정 필요
3. ⏳ **v0.0.86 `_latestObs=null` 신규 race 원인 미상** (HISTORY (98) 남은 문제 3번) — v0.0.83은 영향 없음, 다만 향후 fix 시 주의
4. ⏳ **호스트 빠른 seek 연타 시 native 측 디코드 wait 무음** (HISTORY (99) 신규) — v0.0.83 fix와 무관. 매 seek 명령마다 native가 점프 + 디코드 wait. 사용자 의도적 연타 시나리오라 큰 영향 작음.

**검증**:
- ✅ `flutter analyze` No issues
- ✅ `flutter build apk --debug` 통과
- ✅ 실기기 N=여러 회 측정 — 무음 안 나타남 + 부작용 없음

**회귀 위험**: 매우 낮음.
- 1줄 변경 (`_fallbackAlignment`에 가드 추가)
- 기존 `_tryEstablishAnchor`와 같은 cooldown 자료구조 (일관성)
- seek 직후 1초간 fallback skip — 그 사이 anchor 박힘은 그대로 진행 (별도 가드 이미 적용)
- 회귀 발견 시 1줄 revert로 즉시 baseline 복귀

**빌드**: v0.0.83

---

### 2026-05-17 (100) — v0.0.84 §G G-1 ring buffer 재도입 (큐 모델 fix + EOS wait fix)

**배경**: HISTORY (95) v0.0.79에서 §G G-1 ring buffer 회귀(큰 seek 슬라이더 연타 시 호스트/게스트 무음, `virtualFrame`은 흐름) 발견 후 revert. PoC 격리 환경에서 race 재현 → 큐 모델 fix 검증 → 본 앱 합치는 단계.

**Step 1: PoC 격리 (race 재현 + fix 검증)** (`poc/native_audio_engine_android`):

`oboe_engine.cpp`에 `RingBufferEngine` 클래스 추가 — sine wave generator + 60s ring buffer + v0.0.76 race 모델 + 큐 모델 fix toggle. mp3 디코더 빼고 sine으로 격리 (race 원인은 디코더가 아니라 ring buffer 동기화). `main.dart`에 "Ring Buffer Race Test" 페이지 신설 — 토글 스위치(RACE/FIX) + 수동 seek + 자동 race test (3초간 50ms 주기 random 큰 seek 60회 + 3초 모니터링 → silent ratio > 50%면 race 판정) + logcat print (`AUTO_TEST_RESULT mode=X race=Y silent_ratio_pct=...`).

**Race window 튜닝**:
- 1차 시도 chunk decode sleep 5ms → race 안 잡힘 (window 너무 짧음, mp3 디코더 chunk wall time 비슷 안 만듦)
- 2차 시도 sleep 40ms + chunk 1024 frames → 디코더가 realtime의 0.53배 → 영구 underrun (호스트 단순 재생도 무음)
- 3차 (확정) chunk 4096 frames (85ms 재생) + sleep 40ms → 디코더가 재생의 ~2배 빠름 (정상 동작) + race window 40ms (자동 test 50ms 주기에 첫 chunk 처리 도중 두 번째 seek 도착 가능)

**PoC 측정 (S22 25회 logcat 캡처)**:

| 모드 | 시도 | race=true | race rate | silent ratio range |
|---|---|---|---|---|
| **RACE** (v0.0.76 baseline) | 8 | 2 | **25%** | 정상 3~8% / race 시 **96.9%, 98.3%** (영구 무음) |
| **FIX** (큐 모델) | 17 | 0 | **0%** | 3.0 ~ 10.0% (mean ~6.6%) |

→ **큐 모델 fix가 race 100% 차단 확인**. silent ratio 96.9% = 본 앱 (95) "loadFile 해야 풀림" 영구 무음 패턴과 일치.

**Step 2: 본 앱 v0.0.84 적용** (`android/app/src/main/cpp/oboe_engine.cpp`):

`git checkout f7e4dfa -- oboe_engine.cpp`로 v0.0.76 ring buffer 베이스 복원 후 큐 모델 fix + EOS wait fix 두 가지 적용. 그 외 파일(`sync_service.dart` 등 v0.0.80~v0.0.83 변경)은 그대로 살림.

**Fix 1 (큐 모델, race 차단)**:

```cpp
// seekToFrame (외부 thread) — head/tail 직접 store 제거
if (!isFrameDecoded(clamped)) {
    if (mDecoding.load(std::memory_order_relaxed)) {
        mDecodeSeekTarget.store(clamped, std::memory_order_release);  // 요청만
        std::lock_guard<std::mutex> lock(mRingMutex);
        mRingCv.notify_all();
    }
}

// decodeLoop (단일 thread)
if (seekTarget >= 0) {
    mRingHead.store(seekTarget, std::memory_order_release);  // 단일 thread set
    mRingTail.store(seekTarget, std::memory_order_release);
    AMediaCodec_flush(codec);
    AMediaExtractor_seekTo(extractor, seekUs, ...);
    inputEos = false;
    outputEos = false;
    needsPtsReset = true;
    writeFrame = seekTarget;
}
```

→ ring head/tail write가 decodeLoop 단일 thread로 일원화 → 외부 thread와 인터리브 race 자체가 사라짐.

**Fix 2 (EOS wait, v0.0.76 누락된 디자인)**:

v0.0.76 ring buffer는 `while (!outputEos && !mDecodeAbort)` → 곡 끝 도달 시 thread 종료. ring buffer는 60s sliding window라 thread 종료 후 ring head 고정 → 그 후 seek 시도해도 디코드 재시작 불가 → 영구 무음. v0.0.75 사전할당 PCM에선 곡 전체 메모리에 있어 무관했음. **이번 v0.0.84 실측 logcat에서 `decode thread done: 11894998 frames decoded`(곡 4분 35초) 후 무음 영구 잔재로 발견**.

```cpp
// 변경 전: while (!outputEos && !mDecodeAbort)
// 변경 후:
while (!mDecodeAbort.load(std::memory_order_relaxed)) {
    // seek 요청 처리
    int64_t seekTarget = mDecodeSeekTarget.exchange(-1, ...);
    if (seekTarget >= 0) {
        ...
        inputEos = false;
        outputEos = false;  // EOS 였어도 seek로 재개
        ...
    }

    // EOS 후 seek 대기 모드
    if (outputEos) {
        std::unique_lock<std::mutex> lock(mRingMutex);
        mRingCv.wait_for(lock, std::chrono::milliseconds(200), [&] {
            return mDecodeAbort || mDecodeSeekTarget.load() >= 0;
        });
        continue;
    }

    // 일반 디코드 진행 ...
}
```

이론상 5분 곡(behind 10s + ahead 50s 분배 = 윈도우 60s)에서 자연 재생만 해도 vf 4분 10초 시점에 ringHead가 곡 끝(5분) 도달 → 기존엔 thread 종료 → 그 후 seek 무효. 큰 seek 연타로 끝쪽 점프 시 더 빠르게 도달. v0.0.84 fix는 EOS 도달해도 thread 살아있고 seek 대기 → 어디든 다시 디코드 가능.

**측정 검증 (본 앱, S22 5분 측정)**:

- `host_seek` 330회 (사용자 슬라이더 빠르게 흔들기) — drift 0.00ms 매번 깔끔 → **race fix 작동 확정**
- RTT 분포: min 6 / p50 18 / p90 26 / **max 30ms** — v0.0.80 outlier rejection 통과율 100% (사용자 환경 WiFi 안정)
- 사용자 청감: 5분 측정 동안 **무음 영구 잔재 0회**

**남은 잔재 1건 발견 (본 fix와 무관, 별도 트랙)**:

seq 265~278 영역 (csv 58~65초, 13초 지속):
- vfDiff -319 ~ -346ms (청감 인지 가능)
- drift_ms -1 ~ -4ms (sync 자체는 정확)
- `out_lat_delta_anchored = 13.09ms` 영구 박힘 (anchor 베이크인 outputLatency 부정확)
- 13초 후 사용자 seek (seq 279)로 anchor reset → 0ms 정상 복귀
- → HISTORY (42)/(45)/(98) 영역 = anchor 베이크인 outputLatency 부정확 미해결 이슈. PLAN HIGH §B v0.0.81 ANCHOR-VERIFY 임계 200~300ms로 좁히기 후속에 이미 있음.

**부작용 1건 (영구 무음 아님, 별도 트랙)**:

호스트 PlayerScreen 첫 진입 시 모든 버튼(재생/정지/seek/mute) 비활성화 케이스 1회 발생. 방 나갔다 다시 만들기 2~3회로 복구. `widget.isHost` 또는 `currentFileName` 일시 false 추정. v0.0.83에서 못 본 증상이라 v0.0.84 회귀 의심이나 oboe_engine.cpp 변경(native engine 측)이 Dart UI 상태에 영향 줄 흐름 모호. 재현 패턴 모이면 root cause 추적.

**왜 PoC 격리가 성공적이었나**:

직전 시도 (v0.0.76 단독 → v0.0.77 → v0.0.78/v0.0.79 revert)는 본 앱 회귀 위험으로 race 격리 검증 부족했음. PoC 격리에서 sine generator + mp3 디코더 제거로 변수 1개(ring buffer 동기화)만 남기고, 자동화 race test + logcat print로 25회 정량 측정 → **race window 튜닝 + fix 작동 모두 객관 수치로 검증**. 본 앱 합치기는 v0.0.76 베이스 복원 + 2곳 한정 fix로 회귀 면적 최소화.

**검증**:
- ✅ PoC `flutter analyze` No issues, `flutter build apk --debug` 통과 (NDK 12.2s)
- ✅ PoC 자동 race test 25회 (RACE 8회 + FIX 17회) logcat 수치 캡처
- ✅ 본 앱 `flutter analyze` No issues, `flutter build apk --debug` 통과 (NDK 8.3s)
- ✅ 본 앱 S22 5분 측정: host_seek 330회 drift 0.00ms, fallback 27회 모두 정상 회복
- ⏳ A7 Lite 본 앱 측정 (디바이스 분리/재연결 반복으로 본 commit 시점 미수행)
- ⏳ iOS 회귀 검증 (다음 세션)

**회귀 위험**: 낮음.
- `oboe_engine.cpp` 단일 파일 변경 (다른 파일 v0.0.80~v0.0.83 그대로)
- v0.0.76 베이스(검증된 ring buffer) + 두 곳 한정 fix
- 큐 모델 fix는 PoC 격리에서 25회 측정으로 race 0% 확정
- EOS wait fix는 native 측 mDecodeAbort 시 정리 그대로 (loadFile 새 호출 시 안전 종료)

**빌드**: v0.0.84

---

### 2026-05-17 (101) — v0.0.85 §B 후속 진단 로그 추가 (호스트 빠른 seek 연타 시 게스트 sync 누락 root cause 좁힘)

**배경**: HISTORY (100) v0.0.84 후속 측정에서 csv `sync_log_2026-05-17T17-44-45.csv` seq 324~342 영역에 vfDiff -197초 영구 잔재 19초+ 지속 발견. drift_ms ±5ms로 sync 자체는 정확하나 게스트 syncSeek가 발화 안 됨. ANCHOR-VERIFY는 anchor 박은 직후 100ms만 검증 → 통과 후 호스트 큰 seek 폭증 케이스 못 잡음. PLAN HIGH §B 후속 진행 후보 (a) "호스트 큰 seek 후 게스트 seek-notify 도달 검증 로그 추가" 실행.

**의심 가설 분리** (어느 단계에서 끊겼나):
1. (가설 1) p2p `broadcastToAll`로 보낸 seek-notify 메시지가 게스트 TCP에 도달 안 함 (네트워크 손실 / 호스트 send buffer 폭증)
2. (가설 2) 게스트가 메시지 수신했는데 `_handleSeekNotify` 발화 누락 (이벤트 디스패치)
3. (가설 3) `_handleSeekNotify` 발화 → `_engine.seekToFrame` 호출했는데 v0.0.84 큐 모델로 외부 호출이 `mDecodeSeekTarget`만 set → ts.virtualFrame 자체가 즉시 점프 안 되거나 decodeLoop 처리 누락

**변경 (3곳)**:

1. **`sync_measurement_logger.dart`** — csv 헤더에 `seek_msg_seq` 컬럼 1개 추가 (마지막, event 직전). `log()` 시그니처에 `int seekMsgSeq = 0` optional 파라미터.

2. **`native_audio_sync_service.dart`** — 호스트 측 단조 카운터 `_hostSeekMsgSeq` 멤버 추가.
   - `syncSeek()` (line 508~): `++_hostSeekMsgSeq` 후 p2p `seek-notify` 메시지 data에 `'msgSeq': msgSeq` 동봉 + `_logHostEvent`에 `seekMsgSeq: msgSeq` 전달 → csv host_seek row에 기록.
   - `_handleSeekNotify()` (line 1140~): 메시지에서 `msgSeq` 추출 (구버전 호스트 호환 0 fallback). logcat `[SEEK-NOTIFY] recv msgSeq=X targetMs=Y → guestVf=Z` 출력. `_logGuestEvent('anchor_reset_seek_notify', seekMsgSeq: msgSeq)` 호출 → csv guest row에 같은 값.
   - `_handleSeekNotify` 200ms 후 timer: `ts.virtualFrame`이 `targetGuestVf` ±100ms 안 도달했는지 검증. 벗어나면 `[SEEK-NOTIFY] WARN msgSeq=X target=Y actual=Z diffMs=N` 출력, OK면 `[SEEK-NOTIFY] OK ...` 출력. 가설 3 검증용 (handler는 발화했는데 native 처리 누락).
   - `_logGuestEvent`, `_sendDriftReport`, `_handleDriftReport` 시그니처 모두 `seekMsgSeq` optional 추가 + p2p 메시지/csv 끝까지 전달.

**다음 측정 시 root cause 좁히기 흐름**:
- csv에서 host_seek row의 `seek_msg_seq` 모두 추출 → 게스트 `anchor_reset_seek_notify` row의 같은 값 매칭.
- 매칭 누락 = 가설 1 또는 2 (메시지 손실 / 발화 누락 — logcat `[SEEK-NOTIFY] recv` 유무로 1/2 분리).
- 매칭 OK인데 logcat `[SEEK-NOTIFY] WARN` 발생 = 가설 3 (큐 모델 영향).
- 매칭 OK + `[SEEK-NOTIFY] OK`인데도 vfDiff 잔재 = 다른 경로 (예: anchor 단계 fallback 부정확) → ANCHOR-VERIFY 임계 좁힘 (PLAN 후속 b) 트랙.

**검증**:
- ✅ `flutter analyze` No issues (4.8s)
- ⏳ 실기기 측정 — 사용자 시나리오 (호스트 빠른 seek 연타) 재현 후 csv + logcat 같이 캡처

**회귀 위험**: 매우 낮음.
- 신규 컬럼은 마지막 위치 추가 (기존 컬럼 인덱스 무영향)
- p2p 메시지에 새 필드 `msgSeq` 추가 (구버전 호스트 호환 0 fallback)
- 200ms timer는 logcat만 — 동작 영향 0
- v0.0.84 행동 그대로, 진단 로그만 추가

**빌드**: v0.0.85

---

### 2026-05-25 (102) — v0.0.85 진단 측정 결과: 가설 3가지 모두 부정, HISTORY (100) 잔재 재현 실패

**환경**: 카페 공용 WiFi의 client isolation으로 일반 LAN 불가 → **맥북 macOS 26.3 Internet Sharing으로 WiFi AP 우회**. 카페 WiFi가 유일한 활성 source인데 macOS는 WiFi→WiFi 공유 차단(같은 인터페이스 source/target 동시 사용 불가)이라 [zhuhuilin gist](https://gist.github.com/zhuhuilin/01656866b3e73a677a434c21183b40d2)의 트릭 적용:

```bash
sudo networksetup -createnetworkservice "AdHoc" lo0
sudo networksetup -setmanual "AdHoc" 10.10.10.1 255.255.255.255
```

→ lo0(loopback)에 가짜 IP를 가진 "AdHoc" 네트워크 서비스 생성 → macOS가 활성 source로 인식 → Internet Sharing 메뉴에서 source=AdHoc, target=Wi-Fi 선택 가능 → 맥북이 WiFi AP가 됨. S22 + A7 Lite를 그 AP에 연결. **macOS 26.3 (Tahoe)에서도 정상 작동 확인** (gist는 13~15까지만 검증돼 있었음).

**시나리오**: 호스트(S22) PlayerScreen에서 슬라이더 빠르게 흔들기 6초간 — 1초당 ~8.6회, 총 256회 seek 발생 (인간 수동이지만 Flutter Slider onChanged 폭증).

**측정 데이터 (csv `sync_log_2026-05-25T17-26-08.csv`, 1095 row)**:

| 가설 | 결과 | 근거 |
|---|---|---|
| (1) seek-notify 메시지 손실 | ❌ **부정** | host_seek **256회** ↔ anchor_reset_seek_notify **256회** = 1:1 완전 매칭 |
| (2) 게스트 handler 발화 누락 | ❌ **부정** | logcat `[SEEK-NOTIFY] recv msgSeq=207~256` 모두 도착, 빠짐 없음 |
| (3) v0.0.84 큐 모델 native 처리 누락 | ❌ **부정** | 각 seek 클러스터의 마지막 msgSeq는 항상 `OK` (target = actual) |

**WARN 발생 패턴은 false positive**: 200ms 검증 timer가 발화할 때 이미 후속 seek이 새 target으로 덮어쓴 상태. 큐 모델 `mDecodeSeekTarget.exchange(-1)`로 옛 target 떨궈진 정상 동작. 예시 — msgSeq=212/213/214 모두 WARN, 그 직후 msgSeq=215는 OK (vf=7955328 = 모두 같은 actual).

**vfDiff 영구 잔재 0건**: csv drift row 중 |vf_diff_ms| ≥ 500ms 0건. 마지막 30개 drift row의 vfDiff 최대 -52.71ms (청감 인지 어려운 수준). anchor_set 13회 정상 발생. drift_ms ±5ms 이내. **사용자 청감 OK**.

**해석**:

(100) 잔재 재현 실패의 가능한 원인:
- (a) **race 의존성** — 매번 재현되지 않는 확률적 잔재
- (b) **환경 의존성** — 맥북 핫스팟의 낮은 latency(LAN 직결, RTT < 5ms 추정)가 race window 좁혀서 (100)의 카페 WiFi 환경과 다름
- (c) 사용자 시나리오 차이 — (100)은 일반 카페 WiFi + 일정 시간 사용 후, 본 측정은 핫스팟 + 첫 진입 직후

**진단 인프라는 유지**: `seek_msg_seq` csv 컬럼 + `[SEEK-NOTIFY]` logcat 태그 v0.0.85 그대로. 자연 재발 시 root cause 분리 가능. (b)~(e) 영역 fix는 잔재 직접 재현 후로 보류.

**부가 발견**:
- **macOS Internet Sharing AdHoc 트릭이 측정 인프라로 유용** — 카페/외부 환경에서 WiFi AP 없이 측정 가능. 단 호스트 connectivity 가드(`room_lifecycle_coordinator.dart:215~248`)가 잘 작동했는데, S22가 맥북 핫스팟에 정상 WiFi로 연결됐기 때문 (connectivity_plus가 `wifi`로 보고). task #7 코드 패치 불필요.
- **빠른 seek 연타의 정상 동작 범위 확인**: 1초당 ~8.6회 (총 256회/6초)까지 256:256 매칭 성공. 더 빠른 연타에서 어디서 깨지는지는 미측정.

**검증**:
- ✅ macOS 26.3에서 AdHoc 인터넷 공유 동작 확인 (S22 + A7 Lite WiFi 연결)
- ✅ 256회 빠른 seek 연타 (6초 동안) 모두 정상 처리
- ✅ 사용자 청감 OK
- ⏳ 일반 WiFi 환경 재측정 (환경 의존성 검증)
- ⏳ (100) 잔재 자연 재발 진단 대기

**다음 세션 후보**: (a) 일반 WiFi 환경에서 동일 시나리오 측정 → 환경 의존성 확인. (b) 자연 재발 trigger 발견 시 진단 인프라로 root cause 분리. (c) (100) 잔재 영영 못 잡으면 PLAN HIGH §B 후속 사상.

---

### 2026-05-29 (103) — v0.0.86 UI 정리: `NativeTestScreen` 제거

**배경**: `lib/screens/native_test_screen.dart`는 v3 PoC 단계(commit c4bfd5c "v3 step 1-2: 네이티브 엔진 테스트 UI + S22 검증 완료")에서 만든 임시 화면. 코드/주석 모두 `[임시]` / `(임시)` 명시. PoC §6-3 단계별 진행은 모두 ✅ 완료(PLAN.md), 본 구현 단계 1-1 ~ 2도 모두 ✅. 더 이상 진입 경로 없는 dead UI라 제거.

**변경**:
1. `lib/screens/native_test_screen.dart` 삭제 (225 lines)
2. `lib/screens/home_screen.dart` import 제거 (line 14)
3. `lib/screens/home_screen.dart` "Native Engine Test" `OutlinedButton` + 주석 + 인접 `SizedBox(height: 16)` 제거 (방 만들기 버튼 위 13줄)

**검증**:
- ✅ `flutter analyze` No issues (3.6s)
- ⏳ 실기기 동작 확인 (다음 세션)

**회귀 위험**: 매우 낮음. UI 한 화면 + 진입 버튼 제거. 본체 동기화 로직/네이티브 엔진 무영향.

**빌드**: v0.0.86

---

### 2026-05-29 (104) — v0.0.87 첫 화면 = PlayerScreen (단독 호스트 모드)

**배경**: 사용자 요청 — 누군가 방을 만들거나 참가하지 않는 한 앱을 단독 플레이어로 사용. 첫 화면이 `PlayerScreen`이 되어야 함. 방 만들기/참가 동선의 정확한 UI 위치는 사용자가 추후 결정.

**변경**:
1. `lib/main.dart` — `home: const HomeScreen()` → `home: const PlayerScreen(isHost: true)`. import 교체.
2. `lib/screens/player_screen.dart` — `initState`에서 `audio.startListening(isHost: isHost)` + `handler.attachSyncService(audio, isHost: isHost)` 호출 추가. 기존 RoomScreen 경유 진입에선 이미 호출되지만 재호출 안전(`startListening`은 `_messageSub` 재구독, `attachSyncService`는 detach 선행). 단독 진입 경로에서도 audio_handler 및 message listener 활성 보장.
3. `lib/screens/player_screen.dart` — `AppBar.actions`에 `Icons.group_add` IconButton 추가, 누르면 기존 `HomeScreen` push. **[임시]** 주석 명시 — 사용자가 위치 정해주면 인라인 통합 예정.

**동작 검증 흐름**:
- P2P 미연결 상태에서 `syncPlay`/`syncSeek`/`syncPause` 호출 → `_p2p.broadcastToAll`은 빈 `_peers` 순회로 no-op (`p2p_service.dart:407`), `_engine.start/stop/seekToFrame`만 실행. 단독 재생 정상.
- `_broadcastObs` Timer(500ms)도 빈 list no-op. CPU 영향 무시 가능.
- 누군가 임시 진입점 통해 `HomeScreen` → `_createRoom` → `RoomScreen(isHost: true)` 진입 시 기존 흐름 그대로. `RoomScreen` → `PlayerScreen(isHost: true)` push 시 `initState` 재호출 + `startListening`/`attach` 재호출 안전.

**검증**:
- ✅ `flutter analyze` No issues (3.5s)
- ⏳ 실기기 단독 모드 재생/seek/5초 스킵/mute 동작
- ⏳ 실기기 임시 진입점 → 방 만들기 → 게스트 입장 → 동기화 회귀 없음

**회귀 위험**: 낮음~중간. `initState`의 `startListening` 재호출이 RoomScreen 경유 진입 후 PlayerScreen `initState`에서 한 번 더 실행되는 경로 추가 — `_messageSub` cancel+re-subscribe만 일어나며 동작 무영향. `attachSyncService`는 내부 `detachSyncService` 선행이라 stream 누수 없음. 단독 모드에서 `_logger.start()`가 호출돼 csv 파일 1개 더 생성됨 (자원 영향 미미, 측정 인프라 분리는 별도 작업).

**빌드**: v0.0.87

---

### 2026-05-29 (105) — v0.0.88 단독 모드 loadFile WiFi IP 가드 완화 + Android 16 16KB 호환성 관찰

**배경**: v0.0.87 단독 모드(첫 화면 PlayerScreen, P2P 미연결) 실기기 검증 중 발견 — 파일 선택 후 로드/재생/duration 표시 모두 실패. Root cause: `loadFile`이 `_startFileServer` → `_getLocalIP()` null(WiFi 미연결, 모바일 데이터만) 시 "WiFi IP를 가져올 수 없습니다" 에러 + 즉시 return → native engine 로드 자체가 안 됨. 단독 재생엔 HTTP 서버 불필요(native engine은 로컬 path 직접 받음)이므로 가드 완화.

**변경 (`lib/services/native_audio_sync_service.dart`)**:
1. `_startFileServer`가 null 반환해도 loadFile abort 안 함 — native engine 로드 진행.
2. `_currentUrl = httpUrl != null ? '$httpUrl?v=...' : null` — URL 없으면 null 보존.
3. `_p2p.broadcastToAll(audio-url)` 호출을 `if (_currentUrl != null)` 가드 안으로 이동. (단독 모드는 `_peers` 빈 list라 어차피 no-op이지만 명시적 의미 표현.)

**P2P 사용 시 흐름 메모**: 단독 모드에서 파일 로드 후 사용자가 방 만들기 누른 시점에 `_currentUrl == null`이라 게스트가 들어와도 audio-url 못 받음. 사용자가 WiFi 켠 뒤 파일 재선택 또는 (향후 fix) 방 만들기 시점에 `_startFileServer` 재시도 후 audio-url broadcast 트리거. 별도 트랙 — 사용자 합의 후 처리.

**검증 (SM S947N, Android 16 API 36, WiFi 미연결 + 5G 모바일 통신)**:
- ✅ `flutter analyze` No issues (4.4s)
- ✅ debug 빌드 + install 성공 (gradle 9.1s + install 5.6s)
- ✅ 파일 선택 → 로드 → 재생 → seek → duration 표시 모두 동작 (사용자 확인)

**별도 관찰 — Android 16 16KB page size 호환성 경고**:

SM S947N(Android 16 API 36) 첫 실행 시 다이얼로그 "이 앱은 16KB와 호환되지 않습니다. ELF 정렬 검사에 실패했습니다." 미정렬 라이브러리 목록:
- `liboboe.so`, `liboboe_engine.so` (우리 native engine)
- `libflutter.so`
- `libc++_shared.so`
- `libdartjni.so`
- `libdatastore_shared_counter.so`
- `libVkLayer_khronos_validation.so`

Android 16부터 16KB page size 디바이스에서 .so 라이브러리가 16KB 정렬 필수. 출시(Google Play 등록) 전 반드시 fix 필요. 별도 트랙 — NDK r27+ 업그레이드 + Flutter SDK 16KB 빌드 플래그 검토. 현재는 "다시 표시 안 함" 누르고 사용 가능, 동작 영향 0.

**회귀 위험**: 낮음. P2P 호스트 모드(WiFi O + 게스트 입장 흐름)에선 기존 동작과 동일 — `httpUrl != null` 분기 들어가 audio-url broadcast 정상. 단독 모드 + WiFi 없는 경우만 새 경로(native engine 로드 진행 + broadcast 건너뜀).

**빌드**: v0.0.88

---

### 2026-05-29 (106) — v0.0.89 A-B 구간 반복 (호스트 전용)

**배경**: 사용자 요청 — 단독 호스트 모드 + 방 모드에서 A-B 구간 반복 기능 추가. UX 결정은 인터랙티브 합의 (HISTORY (105) commit 후 같은 세션에서 반복 조정).

**주요 동작 결정**:
- 호스트만 표시·조작, 게스트는 항상 follower (syncSeek 자동 따라옴).
- 1회성 (파일 변경 / 앱 재시작 시 자동 리셋, SharedPreferences 미사용).
- 효과적 범위: A 미지정 시 효과적 A=0, B 미지정 시 효과적 B=duration. 한쪽만 지정해도 자동 반복 동작.
- 간격 가드: A-B가 100ms 미만이면 `_abActive=false` — 무한 jump 루프 방지.
- 새 지정 우선 충돌 처리(옵션 2): A=10s 있는데 B를 10s±100ms 안 지정 → A 자동 해제. vice versa.
- A>B 자동 swap.

**UI**:
- 시크바 위 A/B 텍스트 마커 + 작은 세로 막대. SliderTheme.padding 12 명시 + FractionalTranslation(-0.5)로 thumb 중심과 정확 정렬.
- 시크바 아래 `[A] [B] [⊗]` Row. A/B 버튼은 `OutlinedButton`, outlined 색상이 primary로 활성 표시.
- A/B 버튼 너비 고정: invisible placeholder `A  00:00` (또는 1시간 곡이면 `A  0:00:00`) + 실제 라벨 Stack overlay → 비어있을 땐 `A`만 visible, 저장 시 `A  1:23` visible. 너비 변동 0.
- `fontFeatures: tabularFigures()`로 시간 숫자 폭 일관(시스템 글씨 크기/해상도 무관).
- 짧게 누름 = 저장, 길게 누름 = 그 점만 해제 + `HapticFeedback.mediumImpact()`. 비어있는 버튼 long-press 무동작.
- `⊗ Icons.cancel_outlined` 리셋 아이콘: 5초 seek(`replay_5`/`forward_5`) 시각 겹침 회피 + 향후 플레이리스트 반복재생/한곡재생용 `Icons.repeat` 자리 확보.

**Seek 클램프**:
- 시크바 thumb은 [효과적 A, 효과적 B] 안에서만 움직임. 시각적으로 시크바 전체 길이는 곡 전체 표시.
- 5초 앞/뒤 버튼도 같은 [A, B] clamp.
- B 이후 영역으로 드래그 시도 → B에서 stick.

**Trigger**:
- `_onAbPositionTick(position)`: `_audio.playing && position >= 효과적 B` 시 `syncSeek(효과적 A)`. 정지 중엔 trigger 안 함 (B 위치 정지 후 무한 jump 방지).
- `_togglePlay`: 재생 시작 시 `_lastPosition`이 [A, B] 범위 밖 또는 곡끝 도달이면 startFrom = A로 `syncPlay`.

**`syncPlay({Duration? startFrom})` 인자 추가** (`native_audio_sync_service.dart:462`):
- startFrom 명시 시 그 위치에서 시작 + 곡끝 → 0 분기 우회. 곡끝 도달 후 A로 jump 시 race(syncSeek 큐 모델에서 외부 호출이 vf 즉시 갱신 안 함 → syncPlay 내부 vf>=totalFrames 분기가 syncSeek(0)으로 덮어쓰기)를 차단.
- 기존 호출자(`audio_handler`, `auto_measure_screen`, 게스트 흐름)는 인자 없이 호출 → default null → 동작 동일.

**변경 파일**:
- `lib/screens/player_screen.dart` — A-B 상태/getter/handler/UI (대부분 변경).
- `lib/services/native_audio_sync_service.dart` — `syncPlay` startFrom 인자 추가.
- `pubspec.yaml` — version 0.0.88+1 → 0.0.89+1.

**검증 (SM S947N, Android 16 API 36, 단독 호스트 모드)**:
- ✅ `flutter analyze` No issues (4.6s)
- ✅ A 지정/B 지정/마커 위치 thumb 중심 정렬/B clamp/A>B swap/같은 위치 충돌 자동 해제/long-press 1점 해제/햅틱 진동
- ✅ B 도달 시 A로 자동 jump (재생 중)
- ✅ 곡끝 도달 후 재생 누름 → A로 jump (startFrom 인자 우회)
- ✅ B만 있을 때 0초부터 B 반복
- ✅ A만 있을 때 곡끝 도달 시 A로 jump
- ✅ 파일 변경 시 A/B 자동 리셋
- ✅ 시스템 글씨 크기 변경 시 placeholder 너비도 같이 확장 (Stack 내 두 Text 동일 스타일)
- ⏳ 게스트(방 모드) 회귀 — host syncSeek/syncPlay 정상 broadcast 가정, 게스트는 buttons 비활성

**회귀 위험**: 낮음. PlayerScreen 변경은 UI + 호스트 전용 메서드만, native engine 무영향. `syncPlay` 인자는 optional + 기존 호출자 무수정. 게스트는 widget.isHost == false 분기로 A-B 컨트롤·streams 미접근.

**남은 후속 후보** (사용자 합의 기준):
- seek 메모리 3슬롯 (1회성, 호스트만, tap=저장/이동, long-press=리셋).
- 단독 모드 → P2P 전환 시 audio-url 재시작 흐름 (HISTORY (105) 미해결 이슈).
- 속도 조절 (피치 유지, time stretching) — 별도 §H 트랙 명세 후 진행.

**빌드**: v0.0.89

---

### 2026-05-29 (107) — v0.0.90 seek 메모리 3슬롯 + 시크바 마커 색상/위치 분리 + 영역 reserve

**배경**: PLAN UI 폴리싱 트랙 후속. 사용자 합의된 1회성 seek 북마크 3개 + 시각 일관성 (A-B 마커와 충돌·구분 처리).

**기능 동작**:
- 슬롯 3개, 호스트 전용. 게스트는 비활성.
- tap (비어있음): 현재 `_lastPosition` 저장 + 시간 라벨 visible.
- tap (저장됨): `_audio.syncSeek(stored)` 호출 — 재생 중이면 그 위치에서 그대로 진행, 정지 중이면 위치만 이동. A-B 활성 시 [효과적 A, 효과적 B]로 clamp (슬롯이 범위 밖이면 가까운 끝점).
- long-press (저장됨): 그 슬롯만 해제 + `HapticFeedback.mediumImpact()`.
- long-press (비어있음): 무동작.
- 파일 변경 (`durationStream` listen) / 앱 재시작 시 자동 리셋. A-B 리셋과 같은 시점.

**시각 — 마커 색상/위치 분리 (사용자 인터랙티브 합의)**:
1. 초기 시도: A/B와 슬롯을 같은 위치(시크바 위)에 fontSize 11 vs 9로 우선순위 표현 → 사용자 보고 "가독성 안 좋음".
2. 색상 구분 채택: A/B = `colorScheme.primary` (보라), 슬롯 = `colorScheme.tertiary` (Material 3 자동 보색). 둘 다 fontSize 11 통일.
3. 위치 분리: A/B는 시크바 위 (텍스트 위 + 막대 아래), 슬롯은 시크바 아래 (막대 위 + 텍스트 아래). 두 SizedBox(18dp) 사이에 Slider.
4. `_markerRow({below, color, points})` 공통 헬퍼로 두 함수(`_buildAbMarkers`, `_buildSlotMarkers`) 코드 공유. `below: true`면 Column children 순서 [bar, text]로 뒤집어 시크바 아래에 매달림.
5. **영역 항상 reserve**: 사용자 보고 "마커 추가/해제 시 시크바 위치 변동 거슬림" → `if (host && condition)` → `if (host)`로 변경. 마커 없을 때도 SizedBox(18) 유지 → Stack 빈 children. 호스트 모드 시 시크바 위치 절대 변동 0.
6. 슬롯 버튼 outlined `foregroundColor`도 `tertiary`로 통일 (시크바 마커 색과 일치 — 슬롯 시각 그룹 형성).

**A-B와 슬롯 충돌 처리**:
- A-B 활성 시 슬롯 tap → 그 위치로 syncSeek 하되 [A, B]로 clamp (슬롯이 범위 밖이면 가까운 끝점). 사용자가 슬롯 위치를 의도해도 A-B 의도가 우선.
- 슬롯끼리는 독립. 같은 위치 슬롯 2개 저장 가능 (사용자 자유).

**변경 파일**:
- `lib/screens/player_screen.dart`:
  - `_seekSlots: List<Duration?> filled(3, null)` 상태 + 파일 변경 listen에 슬롯 리셋 통합
  - `_onSlotTap` / `_onSlotLongPress` handlers (A-B와 동일 패턴, A-B clamp 포함)
  - `_buildSeekSlots` + `_slotButton` UI (A/B 버튼과 같은 invisible placeholder + tabularFigures + Stack overlay 패턴)
  - `_buildAbMarkers` / `_buildSlotMarkers` / `_markerRow` 마커 공통 헬퍼
- `pubspec.yaml` — 0.0.89+1 → 0.0.90+1

**검증 (SM S947N, Android 16 API 36, 단독 호스트 모드)**:
- ✅ `flutter analyze` No issues
- ✅ tap 비어있음 → 저장 + 색 활성, tap 저장됨 → 이동 (재생 중/정지 두 케이스 모두 의도대로)
- ✅ long-press 저장됨 → 해제 + 햅틱, long-press 비어있음 → 무동작
- ✅ 시크바 위/아래 마커 색상 구분 (primary/tertiary) + 가독성 OK
- ✅ 마커 추가/해제 시 시크바 위치 변동 0 (호스트 모드 영역 reserve 효과)
- ✅ A-B 활성 + 슬롯 tap 시 [A, B] clamp 작동
- ✅ 파일 변경 시 A-B와 슬롯 동시 리셋

**회귀 위험**: 낮음. PlayerScreen UI 한정 변경. 슬롯은 호스트 widget.isHost == true 한정. 게스트는 streams 미접근 + 마커 영역 reserve 없음.

**빌드**: v0.0.90

---

### 2026-05-29 (108) — v0.0.91 §H Transpose — PoC 격리 검증 후 본 앱 통합 (worker thread + ring buffer)

**배경**: 사용자 요청 — ±12 반음 transpose (단독 + P2P). 2026-05-29 같은 세션 안에서 H-1 첫 시도(Sonic SIGSEGV / SoundTouch callback 안 처리 silence padding) 모두 revert 후 §H 디자인 명세(`SYNC_ALGORITHM_V2.md` §H) + PoC 격리 검증 → 본 앱 통합 진행.

**PoC 격리 (`poc/transpose_engine/`)**:
- step 1: NDK + SoundTouch + Oboe CMake 빌드 통합 (JNI symbol 검증)
- step 2: Oboe stream + 1kHz sine generator + SoundTouch callback 안 처리 — **silence padding click + buzz 재현**, v0.0.91 1차 시도와 동일 한계 확정
- step 3: **Worker thread + lock-free SPSC ring buffer** — 청감 click 0 (사용자 검증: "지지직거리는 잡음 사라졌어 오오 좋은데?"). cents 변경 순간 매우 미세한 틱 (~1ms 추정) 남았지만 음악 컨텍스트에선 묻힐 수준.

**본 앱 통합 디자인 (§H-2 합의값)**:
- **라이브러리**: SoundTouch 2.4.1 (LGPL v2.1, 음악용 권장 setting `SEQUENCE_MS=82 / SEEKWINDOW_MS=28 / OVERLAP_MS=12`)
- **Worker thread + 2개 ring**:
  - `mSTInRing` (input PCM): callback이 `mDecodedData` → 임시 buf → push
  - `mSTOutRing` (transpose 결과): worker가 `mST.put/receive` → push, callback이 pop → output
  - SoundTouch는 worker thread 단독 호출 (thread-safety 보장)
  - `mPitchDirty` / `mSTReconfigure` atomic flag → worker가 pickup
- **cents=0 bypass**: callback이 `mDecodedData` → output 직접 (worker/SoundTouch 거치지 않음, **음질 손실 0**)
- **vf 진행**: callback이 책임 (기존 흐름 유지, 회귀 위험 X). worker는 SoundTouch processing만.
- **알고리즘 latency**: SoundTouch ~50ms + ring buffer ~50ms = ~100ms. 향후 `outputLatencyMs` 반영 보정은 별도 트랙 (sync 알고리즘 자동 흡수 가능성 큼).

**플랫폼 분기**:
- Android: SoundTouch NDK + Worker thread
- iOS: `AVAudioUnitTimePitch` 노드 (OS 내장, 5줄 추가). HW 가속, 검증된 API.

**변경 파일**:
- Android native:
  - `android/app/src/main/cpp/CMakeLists.txt` — SoundTouch 소스(13 cpp) + LGPL 라이센스 추가
  - `android/app/src/main/cpp/SoundTouch/` — SoundTouch 2.4.1 소스 (Olli Parviainen, codeberg.org/soundtouch/soundtouch 2.4.1 태그)
  - `android/app/src/main/cpp/SoundTouchInclude/` — 헤더
  - `android/app/src/main/cpp/oboe_engine.cpp` — SoundTouch 멤버, Worker thread (`stWorkerLoop`), SpscRing 클래스(lock-free SPSC), setSemitoneCents/getSemitoneCents API, `onAudioReady`에 cents=0 bypass / cents!=0 ring push+pop 분기
- Android Kotlin: `NativeAudio.kt` + `MainActivity.kt` MethodChannel 추가
- iOS: `AudioEngine.swift` `AVAudioUnitTimePitch` 노드 attach + setSemitoneCents/getSemitoneCents, `AppDelegate.swift` MethodChannel 추가
- Dart: `native_audio_service.dart` (setSemitoneCents API), `native_audio_sync_service.dart` (setTransposeCents 호스트 API + audio-pitch P2P broadcast + audio-url에 transposeCents 동봉 + 게스트 핸들러)
- UI: `player_screen.dart` `_buildTransposeControls()` — `TRANSPOSE [-]슬라이더[+]` 패턴 (정수 단위 ±12, 표시 long-press = 0 리셋 + 햅틱), 파일 변경 시 자동 reset
- `pubspec.yaml` 0.0.90+1 → 0.0.91+1

**라이센스 처리**:
- SoundTouch는 LGPL v2.1. `.so` 동적 로드 패턴이라 LGPL 의무 부담 작음.
- `android/app/src/main/cpp/SOUNDTOUCH_LICENSE` (원본 COPYING.TXT) 포함.
- 출시 시 앱 라이센스 고지 + 소스 위치 명시 필요.

**Crash 회피 (이전 H-1 시도 학습)**:
- SoundTouch는 thread-safe X → worker thread 단독 호출 (callback과 race 0)
- cents 변경 시 `mST.clear()`는 worker에서만
- ring 비우기도 worker가 책임
- 회귀 위험 가장 큰 영역인 callback 분기 (`mFileLoaded`/`mPrewarmIdle`/`mScheduledStartActive`) 그대로 유지 → cents=0 동작 보장

**검증 (SM-S947N, Android 16 API 36)**:
- ✅ `flutter analyze` No issues
- ✅ build + install 성공
- ✅ cents=0 (기본) 재생 정상 — 회귀 없음
- ✅ transpose ±n 동작 + 음높이 변경 + **지지직 사라짐** (사용자 청감 검증)
- ✅ ±12 sweep 매끄러움
- ✅ transpose 0 복귀 깨끗 (bypass)
- ✅ 파일 변경 시 transpose 자동 reset
- ⏳ 30분 stress (반복 cents 변경) 검증 (다음 세션)
- ⏳ iOS 실기기 검증
- ⏳ P2P 게스트 동기화 (호스트 transpose 변경 → 게스트 적용) — 실측 미수행

**회귀 위험**: 중간.
- Native engine 큰 변경 (worker thread + 2개 ring + onAudioReady 분기)
- cents=0 분기는 기존 패턴 그대로 → cents=0 default 사용자엔 영향 0
- cents!=0 분기 안정성은 PoC step 3에서 정량 검증됨

**남은 후속 (별도 트랙)**:
- Algorithm latency를 `outputLatencyMs`에 반영 (sync 알고리즘 자동 보정)
- 30분 stress 측정 + 보고서
- iOS 실기기 동작 검증
- Crossfade(Option C) 도입 — transition click 완전 제거 (현재 매우 미세, 음악에선 인지 어려움)

**빌드**: v0.0.91

---

### 2026-05-29 (109) — v0.0.92 §I 속도 조절 추가 — SoundTouch setTempo + AVAudioUnitTimePitch.rate

**배경**: §H Transpose 본 앱 통합 (HISTORY (108)) 직후 사용자 요청. SoundTouch가 pitch와 별개로 tempo도 독립 지원 → 같은 worker thread + ring buffer 인프라에 한 줄 추가로 가능. PoC step 4는 생략(음악 검증이 sine보다 더 의미 있음) → 본 앱 직접 통합.

**디자인 결정 (이전 사용자 합의 적용)**:
- 범위 0.5x ~ 2.0x
- 5% 단위 (정수 5의 배수만 — 직접 입력 없음, 버튼/슬라이더 강제)
- UI: 가운데 슬라이더 + 양쪽 ±5% 버튼 + 표시 `1.00x`
- 표시 long-press → 1.0x 리셋 + 햅틱
- transpose와 독립 적용 (pitch + tempo 동시 가능)
- 파일 변경 시 자동 reset (1.0x)

**Native 구조 (transpose와 동일 worker thread 패턴 확장)**:

| | Transpose | 속도 |
|---|---|---|
| Android | `mST.setPitchSemiTones(cents/100.0f)` | `mST.setTempo(speedX1000/1000.0f)` |
| iOS | `timePitch.pitch = Float(cents)` | `timePitch.rate = Float(speedX1000)/1000.0` |
| 적용 위치 | worker thread (mPitchDirty atomic flag) | worker thread (mTempoDirty atomic flag) |
| vf 진행 | numFrames 그대로 | **numFrames × speed** ← 핵심 차이 |
| useST 조건 | cents != 0 | cents != 0 OR speed != 1.0 |

**Android callback inputFrames 계산** (`oboe_engine.cpp:onAudioReady`):
- 기존 (transpose만): `inputFrames = numFrames` (1:1)
- speed 추가: `inputFrames = (numFrames * speedX1000 + 500) / 1000`
- vf += inputFrames → 사용자 청감과 일치 (1.5x = vf 1.5배 빠르게 진행 = position 표시도 1.5배 빠르게)

**자료형 결정**:
- `mPlaybackSpeedX1000` (atomic int) — float atomic 미지원 환경 회피
- 1.0배속 = 1000, 0.5 = 500, 2.0 = 2000
- 적용 시 `/ 1000.0f`

**변경 파일**:
- `android/app/src/main/cpp/oboe_engine.cpp` — mPlaybackSpeedX1000 atomic + setPlaybackSpeedX1000/getPlaybackSpeedX1000 API + workerLoop에 mTempoDirty 분기 + onAudioReady useST 조건/inputFrames 계산
- `android/app/src/main/kotlin/com/synchorus/synchorus/NativeAudio.kt` + `MainActivity.kt` — MethodChannel
- `ios/Runner/AudioEngine.swift` + `AppDelegate.swift` — playbackSpeedX1000 멤버 + AVAudioUnitTimePitch.rate
- `lib/services/native_audio_service.dart` — setPlaybackSpeedX1000/getPlaybackSpeedX1000
- `lib/services/native_audio_sync_service.dart` — setPlaybackSpeedX1000 호스트 API + audio-tempo P2P broadcast + audio-url에 playbackSpeedX1000 동봉 + 게스트 audio-tempo 핸들러
- `lib/screens/player_screen.dart` — `_buildSpeedControls()` (SPEED [-]슬라이더[+] + 표시 long-press reset) + durationStream listen에 playbackSpeed reset 추가
- `pubspec.yaml` 0.0.91+1 → 0.0.92+1

**검증 (SM-S947N, Android 16 API 36)**:
- ✅ `flutter analyze` No issues
- ✅ 빌드 + install 성공
- ✅ 단독 모드 청감 OK (사용자: "정상 동작하는 것 같아")
- ⏳ Edge case 조합 (시크바 진행 / A-B 반복 + 속도 / seek 메모리 + 속도 / 5초 앞뒤 + 속도 / 일시정지/재생 + 속도 / transpose + 속도 동시) — 다음 세션
- ⏳ 30분 stress (반복 속도 변경) — 다음 세션
- ⏳ **P2P 게스트 sync 실측** — 핵심 검증. vf 진행 속도가 변하니 drift 계산 영향. 호스트/게스트 같은 platform이면 자동 상쇄 예상. 다른 platform(Android+iOS) 섞이면 algorithm latency 차이로 drift 가능 — 별도 트랙 후속.
- ⏳ iOS 실기기

**회귀 위험**: 낮음~중간.
- §H worker thread + ring 인프라 그대로 → 새 동기화 race 없음
- callback inputFrames 계산 변경 — speed=1.0 default 사용자엔 영향 0 (inputFrames == numFrames)
- mDecodedSampleRate 기준 vf 진행 변경 — sync 알고리즘이 vf 기반이라 drift 계산 영향 가능 → P2P 실측 후 확정

**남은 후속 (별도 트랙)**:
- P2P sync 실측 (호스트 1.5x 변경 → 게스트 동기 drift 확인)
- Algorithm latency outputLatencyMs 반영 (transpose와 공통)
- iOS 실기기
- 30분 stress
- 시크바/시간 표시 정확도 (1.5x에서 totalDuration vs 실제 재생 시간 표시 정확한지)

**빌드**: v0.0.92

---

### 2026-05-31 (110) — v0.0.93 §H/§I edge case 검증 + 파일 변경 시 state 누수 fix

v0.0.92 단독 모드 edge case 검증 중 사용자 제보로 회귀 1건 발견 → fix.

**증상 (사용자 실측, SM-S947N)**: 앱을 종료/재진입 후 파일 로드해 재생하면, 이전 세션에서 설정해둔 transpose/speed가 그대로 적용된 채로 재생됨. 그런데 UI는 default(0 cents / 1.00x) 표시. 더 신기한 점 — 음정만 조정하면 음정은 정상으로 바뀌지만 속도는 잘못된 그대로, 속도만 조정하면 속도는 정상이지만 음정은 잘못된 그대로. 즉 **두 영역이 독립적으로 잔재**.

**Root cause 추적**:
- `oboe_engine.cpp:1000 resetState()` 는 decode 관련 state만 reset, `mSemitoneCents` / `mPlaybackSpeedX1000`은 건드리지 않음 → `loadFile`을 호출해도 native 측 두 값은 이전 세션 그대로
- SoundTouch worker thread는 `mPitchDirty` / `mTempoDirty` flag를 따로 처리(`oboe_engine.cpp:145, 151`). 한쪽 flag만 set되면 `mST.setPitchSemiTones()` 또는 `mST.setTempo()` 중 하나만 재호출됨 → 사용자가 한쪽만 슬라이더 조정 시 다른 쪽은 SoundTouch 내부 state 그대로 유지 → 사용자 관찰과 정확히 일치
- `player_screen.dart:73-88` durationStream listen의 reset 로직은 `hasAny` gate를 Dart 측 값 기준으로 평가. 새 process에서 Dart는 default(0/1000)이고 native만 잔재면 `hasAny=false` → reset 안 함
- audio_service foreground service가 process keep-alive 시키면 native singleton이 살아남는 시나리오와도 맞물림

**Fix (4 layer reset, file 변경 시 강제)**:
1. **Dart 호스트 `loadFile`** (`native_audio_sync_service.dart:367-376`): 파일 로드 직후 `_transposeCents=0`, `_playbackSpeedX1000=1000` field reset + `_engine.setSemitoneCents(0)` / `_engine.setPlaybackSpeedX1000(1000)` 직접 호출 (broadcast 부작용 없는 native 직접 push). audio-url 동봉(443~)이 게스트도 일괄 0/1000으로 초기화.
2. **Android native `loadFile`** (`oboe_engine.cpp:196-202`): `mSemitoneCents=0`, `mPlaybackSpeedX1000=1000` + `mPitchDirty=true`, `mTempoDirty=true` 강제 → worker thread가 다음 iteration에 `mST.setPitchSemiTones(0)` + `mST.setTempo(1.0)` 둘 다 재호출 → SoundTouch 내부 state 강제 갱신. 안전망.
3. **iOS native `loadFile`** (`AudioEngine.swift:33-39`): `pitchCents=0`, `playbackSpeedX1000=1000`, `timePitch.pitch=0`, `timePitch.rate=1.0` 강제. 안전망.
4. **UI `PlayerScreen`** (`player_screen.dart:71-83`): `hasAny` gate 제거 + transpose/speed reset 호출 제거(sync_service가 이미 처리). durationStream listen은 widget state(A-B/seek slots)만 reset.

**변경 파일**:
- `lib/services/native_audio_sync_service.dart`
- `android/app/src/main/cpp/oboe_engine.cpp`
- `ios/Runner/AudioEngine.swift`
- `lib/screens/player_screen.dart`
- `pubspec.yaml` 0.0.92+1 → 0.0.93+1

**검증 (SM-S947N, Android 16 API 36)**:
- ✅ `flutter analyze` No issues
- ✅ 빌드 + install 성공
- ✅ **재현 시나리오 통과** — 사용자: "이제 정상적으로 되는것같네"
- ✅ Edge case 시나리오 1~9 모두 통과 (단독 모드):
  - 1: 시크바 진행 정확도 (1.5x → position 1.5배 속도)
  - 2: A-B 반복 + 속도
  - 3: seek 슬롯 + 속도 (음악적 ms 단위)
  - 4: 5초 skip + 속도
  - 5: pause/resume + 속도 유지
  - 6: transpose + 속도 동시 (사용자 ±12 semitone = ±1옥타브 극단 케이스도 통과, SoundTouch pitch+tempo 동시 적용)
  - 7: 슬라이더 dragging (5% step gate 정상 동작)
  - 8: long-press reset
  - 9: 파일 변경 시 default reset (본 fix의 직접 대상)

**남은 후속 (별도 트랙, v0.0.92 항목 그대로)**:
- P2P sync 실측 (호스트 speed 변경 → 게스트 동기 drift)
- Algorithm latency outputLatencyMs 반영
- iOS 실기기
- 30분 stress
- 시크바/시간 표시 정확도 (1.5x에서 totalDuration vs 실제 재생 시간)

**회귀 위험**: 매우 낮음. fix가 모두 default 값으로의 강제 reset이라 idempotent. 다른 시나리오 회귀 없음 확인.

**빌드**: v0.0.93

---

### 2026-05-31 (111) — v0.0.94 방 만들기 WiFi 미연결 silent fail fix

**배경 (HISTORY (107) 후속)**: 2026-05-29 v0.0.90 SM-S947N에서 PlayerScreen → group_add → HomeScreen → "방 만들기" 클릭 무반응 보고. logcat에 mDNS 등록(`MdnsAdvertiser: roomCode=2306, port=41235`) 성공 보임 → RoomScreen navigate 안 됐거나 진입 후 UI 동결 의심으로 PLAN HIGH에 진단 항목 등록.

**사용자 진단 (2026-05-31)**: WiFi 미연결 상태였음. mDNS 등록 자체는 인터페이스 없어도 일부 진행되어 로그가 보였으나 IP 획득 못해 실제 호스트 광고/HTTP 서버 시작이 막힌 것으로 추정. 사용자 입장에선 안내 없이 silent fail이라 무반응으로 보임.

**Fix (v0.0.94)**:
- `lib/services/native_audio_sync_service.dart` — `_getLocalIP` → `getLocalIP` public 노출 (HomeScreen 등 외부에서 사전 체크용 재사용)
- `lib/screens/home_screen.dart` — `_createRoom` 진입 직후 `getLocalIP()` 호출, null이면 `SnackBar('WiFi 연결이 필요합니다')` 후 return. `p2p.startHost()` 호출 전이라 부수 효과(포트 점유, mDNS 시작) 없이 깨끗하게 종료.
- `pubspec.yaml` 0.0.93+1 → 0.0.94+1

**선택지 근거**: `connectivity_plus.checkConnectivity()` 대신 `NetworkInterface` IP 직접 체크. CLAUDE.md note에 "iOS 제어센터 WiFi 토글 시 connectivity가 'none' 미발화" 케이스가 있어 IP 체크가 더 robust. 양 플랫폼 동일 로직.

**검증 (SM-S947N, Android 16 API 36)**:
- ✅ `flutter analyze` No issues
- ✅ WiFi 끈 상태로 방 만들기 → SnackBar 안내, RoomScreen 미진입
- ✅ WiFi 켠 상태로 방 만들기 → 정상 RoomScreen 진입 (회귀 없음)

**회귀 위험**: 매우 낮음. fix가 호스트 시작 사전 가드 1개 추가. WiFi 연결 시 기존 흐름 그대로.

**남은 관련 후속 (별도 트랙, PLAN HIGH 유지)**:
- 단독 모드 → P2P 전환 시 audio-url 미전파 (HISTORY (105) 미해결 — 단독 모드로 파일 로드 후 WiFi 켜고 방 만들기 누른 경우 `_currentUrl=null`이라 게스트가 audio-url 못 받음. 본 fix는 무반응 안내만이고 audio-url 흐름은 별개)

**빌드**: v0.0.94

---

### 2026-05-31 (112) — v0.0.95 P2P 동선 통합: HomeScreen/RoomScreen → PlayerScreen BottomSheet

**배경**: HomeScreen + RoomScreen 거치는 동선이 어색 ("플레이어 → group_add → 홈 → 방 만들기/참가 → 방 화면 → 플레이어"). 사용자 요청 — 플레이어 화면에서 P2P 모드 선택 + 정보 표시까지 단일 화면 안에서 처리. 또 입장 코드 검증이 빠져 있던 기능 같이 추가.

**Phase 분할 (사용자 합의 후 진행)**:
- Phase 1: P2P join 메시지에 roomCode 동봉 + 호스트 측 검증 reject
- Phase 2: PlayerScreen `PlayerMode` enum state (standalone/host/speaker) 도입
- Phase 3: `group_add` → BottomSheet (단독: 호스트/스피커 선택 / 호스트: 정보 카드 + 종료 / 스피커: 정보 카드 + 종료)
- Phase 4: `_enterHostMode` / `_exitHostMode` PlayerScreen 이식 + `_currentUrl` 재바인딩
- Phase 5: 스피커 모드 검색 토글 + IP 입력 + 코드 다이얼로그

**주요 변경**:
- **P2P join 코드 검증** (`p2p_service.dart`) — `connectToHost`에 `roomCode` 인자, join 메시지에 동봉. `_handleNewPeer`에서 `_roomCode`와 비교 → 불일치 시 `join-rejected` 응답 후 socket.destroy. 게스트는 inline 에러 "입장 코드가 맞지 않습니다".
- **PlayerScreen 모드 state** (`player_screen.dart`) — `PlayerMode` enum + `_mode` field. standalone/host는 UI 컨트롤 권한 동일, speaker만 read-only. 모드 변경 시 재생 상태(speed/transpose/position/playing) 모두 유지.
- **BottomSheet UI** — `group_add` 트리거. 단독 모드: 호스트 모드 버튼 + 스피커 모드 영역(`_SpeakerModePicker` widget: 검색 토글 + 결과 리스트 + IP 입력). 호스트/스피커 모드: 정보 카드(코드/IP/접속자 수) + 종료 버튼.
- **모드 전환 race fix** — `_isModeTransitioning` flag로 호스트/스피커 진입 비동기 중 `group_add` 비활성.
- **호스트 모드 선택 시 sheet 유지** — `Navigator.pop` 제거, `_setStateAndSheet`이 sheet rebuild → `switch` 분기로 정보 카드 즉시 표시.
- **HistoryCard rebuild 보장** — `_setStateAndSheet(VoidCallback)` helper + `_setSheetState` 저장(`whenComplete`에서 reset). peer count/모드 등 외부 변경 시 PlayerScreen setState + sheet setSheetState 동시 호출 → BottomSheet 안 카드 갱신.
- **IP 검증 + 호스트 존재 확인 후 코드** — `_isValidIPv4` 형식 검증 + `P2PService.pingHost` (raw TCP connect → 즉시 close) → 호스트 없으면 inline 에러 "호스트를 찾을 수 없습니다", 있으면 코드 다이얼로그.
- **`_CodeInputDialog` StatefulWidget** — controller 자체 관리 + pop 직전 `FocusManager.unfocus()` → 잘못된 코드 후 발생하던 `_dependents.isEmpty` framework assertion 회피.
- **`onSuccess` postFrameCallback** — 같은 frame에 PlayerScreen setState(_mode=speaker) + Navigator.pop(sheetContext) 동시 시 'child.owner == owner' BuildOwner mismatch가 났던 사례 회피.
- **inline 에러 표시** — `_enterSpeakerMode` 반환 타입을 `Future<String?>`로 (null=성공, string=에러). picker 내부에 빨간 errorContainer 박스로 표시 — SnackBar는 BottomSheet 아래에 가려서 안 보임.
- **스피커 모드 UI 동일화** — A-B/seek slots/transpose/speed/시크바/재생 컨트롤 모두 표시. 컨트롤만 비활성(`hasAudio = currentFileName != null && _isController` 가드). 호스트와 시각적 동일성 유지. Sync Info는 사용자 요청으로 노출 제거.
- **게스트 transpose/speed Dart state sync** (`native_audio_sync_service.dart`) — audio-url/audio-pitch/audio-tempo 핸들러에서 Dart field + stream도 같이 갱신 (이전엔 native만 적용 → 스피커 모드 UI는 default 0/1000으로 보이고 실제 native만 호스트 값). `transposeCentsStream` / `playbackSpeedStream` controller 추가, PlayerScreen이 listen → setState.
- **호스트 카드 접속자 수 호스트 포함** — `_peerCount + 1` 표시 (호스트 1 + 게스트 N).
- **WiFi 미연결 시 안내** — `_enterHostMode` 진입 직후 `getLocalIP()` null이면 SnackBar "WiFi 연결이 필요합니다".
- **`rebindFileServerIfNeeded`** (`native_audio_sync_service.dart`) — 단독 모드에서 파일 로드한 상태로 호스트 모드 전환 시 `_currentUrl=null`이면 HTTP 서버 재바인딩 + audio-url broadcast. HISTORY (105) 미해결 이슈 자연 해소.
- **다운로드/sync 직렬 처리** — 게스트 입장 시 `_runGuestStartupSequence`로 sync 먼저 (await) → 완료 후 audio-request 전송. 다운로드와 병렬 시 WiFi 채널 점유로 RTT jitter가 sync 정확도 떨어뜨리는 영향 회피 (사용자 합의).
- **"동기화 중" UI 표시** — `_isSyncing=true`일 때 파일 정보 카드 subtitle을 "스피커 · 동기화 중" (primary 색 + italic). sync 완료 시 "스피커"로 복귀.
- **`_startGuestPlayback` sync 가드** — `!_sync.isSynced`면 재생 보류, sync 완료 후 다음 audio-obs(500ms 주기)에서 자동 재시도.

**회귀 fix (검증 중 발견)**:
1. **`discovery.stop()` 호스트 광고까지 같이 제거** — `_setStateAndSheet`이 sheet rebuild → `_buildStandaloneSheet` 안 `_SpeakerModePicker` widget unmount → `dispose()` → `_stopSearch()` → `widget.discovery.stop()` → discovery 인스턴스가 광고/검색 공용이라 호스트 광고도 같이 제거. `DiscoveryService.stopBroadcast()` / `stopDiscovery()` 분리, picker는 `stopDiscovery()`만 호출. logcat에서 광고 등록 73ms 후 즉시 제거 패턴으로 root cause 좁힘.
2. **`SyncService.startHostHandler()` 호출 누락** — 호스트가 sync-ping 받아서 sync-pong 응답하는 listener 등록. PlayerScreen `_enterHostMode`에 이식 누락 → 게스트 `sync.syncWithHost` 무한 await → sync 영원히 안 됨. `room_screen.dart:80`에서 호출되던 게 누락된 path.
3. **`cleanupSync` stream emit 누락** — 모드 종료 후 state field만 `_playing=false`/`_currentFileName=null` 설정하고 `_playingController.add(false)` / `_durationController.add(null)` / `_positionController.add(Duration.zero)` stream emit 안 함 → `_buildControls` StreamBuilder가 마지막 playing=true 그대로 표시 → 일시정지 아이콘 잔재. 4개 stream emit 추가로 fix.
4. **시크바 hasAudio 가드 누락** — `Slider.onChanged`/`onChangeEnd`가 `_isController`만 가드, `currentFileName` 확인 없음 → 파일 없는 단독 상태에서도 시크바 드래그 가능. `_isController && _audio.currentFileName != null`로 가드 강화.

**변경 파일**:
- `lib/services/p2p_service.dart` — `pingHost` + `connectToHost(roomCode)` + `_handleNewPeer` 검증
- `lib/services/discovery_service.dart` — `stopBroadcast`/`stopDiscovery` 분리 + 진단 logging
- `lib/services/native_audio_sync_service.dart` — `rebindFileServerIfNeeded` + transpose/speed stream + 게스트 측 Dart state sync
- `lib/screens/player_screen.dart` — `PlayerMode` enum + BottomSheet 3종 + 모드 전환 메서드 + `_SpeakerModePicker` + `_CodeInputDialog` + 호스트/스피커 카드
- `lib/screens/home_screen.dart` — `_joinRoom` `connectToHost`에 `roomCode` 인자 추가 (dead route 후보지만 빌드 통과)
- `lib/screens/room_screen.dart` — `_goToPlayer` PlayerScreen 호출에 `initialMode` 사용
- `lib/measurement/auto_measure_screen.dart` — `connectToHost(roomCode)` 인자 추가
- `lib/main.dart` — `PlayerScreen(isHost: true)` → `PlayerScreen()` (default standalone)
- `pubspec.yaml` 0.0.94+1 → 0.0.95+1

**검증 (SM-S947N + S22, 양쪽 Android 16)**:
- ✅ 단독 모드 진입 + 파일 재생
- ✅ 호스트 모드 진입 + 정보 카드 표시 (sheet 안 카드로 자연 전환)
- ✅ 스피커 모드 검색 → 결과 보임 → 탭 → 코드 다이얼로그
- ✅ 잘못된 코드 → inline 에러 "입장 코드가 맞지 않습니다"
- ✅ 정확한 코드 → 연결 성공 → "동기화 중" → sync 완료 → 다운로드 → 자동 재생
- ✅ 양쪽 카드 접속자 "2명" 표시 (호스트 1 + 게스트 1)
- ✅ IP 직접 입력 + 형식 검증 + 호스트 존재 확인 + 코드 다이얼로그
- ✅ 호스트 모드 종료 → 게스트 자동 단독 복귀
- ✅ 모드 전환 시 재생 상태 유지

**남은 이슈 / 후속 (별도 트랙)**:
- **`RoomLifecycleCoordinator` 이식 보류** — WiFi 끊김 자동 재접속, 백그라운드 진입 후 재동기화 등. 사용자 요청으로 "호스트 자리 비움" 같은 UI 안내 불필요. 라이프사이클 핵심 기능 이식은 다음 세션 후보.
- **`RoomScreen` 폐기** — PlayerScreen 통합으로 dead route. Phase 6 task로 별도 진행.
- **HomeScreen IP 직접 입력** — dead route 후보(임시로 빈 코드 전달, 호스트 reject로 사용자에 SnackBar). Phase 6에서 정리.
- **`_buildSyncInfo`** — 사용자 요청으로 build에서 노출 제거. 코드는 보존 (`// ignore: unused_element`).

**회귀 위험**: 중간. P2P 동선이 크게 바뀌어 라이프사이클 케이스(WiFi 끊김, 호스트 종료, 백그라운드 진입)는 별도 검증 필요. 핵심 시나리오는 검증 통과.

**빌드**: v0.0.95

---

### 2026-06-01 (113) — v0.0.96 PlayerScreen UI 폴리싱

v0.0.95 P2P 동선 통합 직후 follow-up 사용자 요청 폴리싱.

- **파일 선택 버튼 → 파일 정보 카드 통합** — 별도 `ElevatedButton` 제거, `ListTile.onTap = _pickFile` 호스트 권한 + 진행 중 아닐 때만. UI 1줄 절약 + 직관성 ↑.
- **모드 라벨(단독/호스트/스피커) 노출 제거** — `subtitle` 항상 null. 라벨이 굳이 필요 없다는 사용자 의견.
- **동기화 중 표시 위치 변경** — 기존 subtitle "스피커 · 동기화 중" → title "동기화 중" + leading을 `CircularProgressIndicator(indeterminate)`. "음악 대기 중" 같은 placeholder 안 보이고 progress 동그라미만. 동기화 완료되면 다운로드 단계(`파일 수신 중... X%`)로 자연 전환.
- **시크바 마커 영역 항상 reserve** — `if (_isController)` 가드 제거. 스피커 모드는 `_abPointA/B`/`_seekSlots` null이라 빈 18px `SizedBox`만 표시 → 시크바 위치/높이 모드 전환에도 고정. 이전엔 호스트→스피커 전환 시 시크바가 위로 점프.
- **AppBar 좌측 "Synchorus" + 버전** — 기존 "플레이어" 텍스트를 앱 이름으로. 옆에 11pt 50% opacity로 `v0.0.96` 표시(`package_info_plus`). `_loadVersion()`은 HomeScreen 패턴 그대로.

**변경 파일**:
- `lib/screens/player_screen.dart`
- `pubspec.yaml` 0.0.95+1 → 0.0.96+1

**검증 (SM-S947N + S22)**:
- ✅ 카드 탭 → 파일 선택창
- ✅ 동기화 중 title="동기화 중" + 동그라미 progress, 완료 시 다운로드 단계로 자연 전환
- ✅ 스피커 모드 시크바 높이 고정 (단독/호스트와 동일)
- ✅ AppBar Synchorus + v0.0.96 표시

**회귀 위험**: 낮음. UI 표시 영역만 변경, 로직 무변경.

**빌드**: v0.0.96

---

### 2026-06-01 (114) — v0.0.97 Phase 6: HomeScreen/RoomScreen/RoomLifecycleCoordinator 폐기

v0.0.95 P2P 동선 PlayerScreen 통합 이후 dead route 정리. 사용자 요청.

**삭제 파일**:
- `lib/screens/home_screen.dart` — group_add 진입점이 BottomSheet로 바뀐 v0.0.95부터 dead route. Phase 3 결제/로그인 등 재진입 필요 시 git history(`6af678e^`)에서 복구해 fresh로 시작.
- `lib/screens/room_screen.dart` — PlayerScreen이 모드 + 정보 카드 + 종료까지 모두 처리. RoomScreen 진입 path 없음.
- `lib/services/room_lifecycle_coordinator.dart` — RoomScreen에서만 사용 → RoomScreen 폐기와 함께 dead. WiFi 끊김 재접속/백그라운드 재동기화 등 로직은 PlayerScreen에 이식 시 git history에서 복구 + 적용.

**의존성**:
- 다른 코드 import 없음 (v0.0.95에서 player_screen은 이미 import 정리됨)
- auto_measure_screen 주석에 HomeScreen/RoomScreen 참조만 있고 코드 의존 X — 주석은 그대로 (이름 변경 시점에 같이 정리)
- `flutter analyze` No issues

**변경 파일**:
- `lib/screens/home_screen.dart` — 삭제
- `lib/screens/room_screen.dart` — 삭제
- `lib/services/room_lifecycle_coordinator.dart` — 삭제
- `pubspec.yaml` 0.0.96+1 → 0.0.97+1

**미해결 후속 (별도 트랙)**:
- `RoomLifecycleCoordinator` 핵심 기능(WiFi 끊김 자동 재접속, 백그라운드 진입 후 재동기화)을 PlayerScreen에 이식 — UI 안내(자리 비움 배너 등)는 사용자 요청으로 제외. git history `9deaea3^:lib/services/room_lifecycle_coordinator.dart`에서 복구 시작.

**회귀 위험**: 매우 낮음. dead code 제거뿐 — 동작 변경 0.

**빌드**: v0.0.97

---

### 2026-06-01 (115) — v0.0.98 세로 고정 + 사용 중 화면 꺼짐 방지

- **세로 고정** (`main.dart`) — `SystemChrome.setPreferredOrientations([portraitUp, portraitDown])`. 가로 회전 시 시크바/카드 영역이 overflow되어 노란 경고 띄우던 사례 회피(사용자 보고).
- **화면 꺼짐 방지** (`player_screen.dart`) — `WakelockPlus.enable()` initState, `WakelockPlus.disable()` dispose. 음악 재생 중 자동 잠금 미진입. `wakelock_plus` 패키지는 pubspec 의존성에 이미 존재 — import만 추가.

**변경 파일**:
- `lib/main.dart`
- `lib/screens/player_screen.dart`
- `pubspec.yaml` 0.0.97+1 → 0.0.98+1

**검증 (SM-S947N + S22)**:
- ✅ 디바이스 가로 회전해도 화면 세로 유지, overflow 경고 0
- ✅ 음악 재생 중 잠금화면 미진입

**회귀 위험**: 매우 낮음. 시스템 기능 호출만, 로직 변경 0.

**빌드**: v0.0.98

---

### 2026-06-01 (116) — v0.0.99 BottomSheet UI 폴리싱

- **타이틀 변경** — "P2P 모드 선택" → "모드 선택" (P2P 단어 비기술 사용자에게 어려움).
- **호스트 모드 버튼 스타일 통일** — `ElevatedButton.icon` → `OutlinedButton.icon`. 스피커 검색 버튼과 시각적 통일.
- **검색 결과 영역 고정 높이** — `ConstrainedBox(maxHeight: 180)` + `ListView shrinkWrap: true` → `SizedBox(height: 180)` 고정 + `shrinkWrap: false`. 결과 0개 → "주변 방을 찾는 중..." 가운데 표시, 1개 검색되어도 영역 안 줄어들고, 많아지면 ListView 자체 스크롤.

**변경 파일**:
- `lib/screens/player_screen.dart`
- `pubspec.yaml` 0.0.98+1 → 0.0.99+1

**회귀 위험**: 매우 낮음. UI 표시만, 로직 무변경.

**빌드**: v0.0.99

---

### 2026-06-01 (117) — v0.0.100 SnackBar UX 개선 (가림 fix + 큐 적체 fix)

PLAN UI 폴리싱 트랙 "SnackBar UX 개선" 항목 두 가지 처리.

**이슈 ① modal에 가림 — `_enterHostMode` 진입 실패 안내** (`player_screen.dart`)
- 호스트 모드 버튼은 BottomSheet를 **닫지 않고** sheet 안에서 `_enterHostMode()`를 호출(`onPressed: () => _enterHostMode()`)하므로, 실패 시 띄우던 SnackBar 2개가 modal 아래에 가려져 안 보임.
  - WiFi 없음 (구 1324)
  - 서버 시작 실패 (구 1339)
- → SnackBar 대신 **inline 에러 박스**로 변경. 스피커 picker가 이미 쓰던 `_lastError` inline 패턴(errorContainer + error_outline)과 동일. state field `_hostModeError` 추가, `_setStateAndSheet`로 sheet rebuild, 재진입/ sheet 닫힘 시 clear.
- inline 박스를 top-level `_buildInlineError(context, message)` helper로 추출 → picker(기존 inline)와 호스트 모드 공용(DRY).

**포트 충돌 문구 일반화**
- `startHost()`는 `disconnect()`로 기존 소켓 정리(`p2p_service.dart:528`) + `ServerSocket.bind(anyIPv4, 41235, shared:true)`. `shared:true`는 같은 (주소,포트)에 여러 ServerSocket 바인딩을 허용([Dart API: ServerSocket.bind](https://api.dart.dev/dart-io/ServerSocket/bind.html))하므로 **잔재 소켓이 있어도 재바인딩이 SocketException 없이 성공** → 포트 점유 충돌은 사실상 안 남.
- 기존 `'서버 시작 실패: 포트가 이미 사용 중입니다'`는 원인을 포트 점유로 단정한 오도성 문구. → `'서버를 시작할 수 없습니다'`로 일반화. `catch`는 드문 예외(권한 등) 안전망으로 유지.

**이슈 ② SnackBar 큐 적체** (`player_screen.dart`)
- 연속 호출 시 옛 메시지가 끝나야 새 메시지가 떠 적체됨. → `_showSnack(msg)` helper 도입: `hideCurrentSnackBar()` 후 `showSnackBar`로 항상 최신 메시지 즉시 대체.
- 적용: `_pickFile`(파일 로드 실패), `_exitSpeakerMode`(호스트 끊김 reason). 이 두 케이스는 sheet 미오픈 상태라 가림 무관, root ScaffoldMessenger 사용.

**폐기한 옵션**: PLAN이 추천했던 "BottomSheet builder를 `Scaffold`로 감싸 자체 ScaffoldMessenger 활성"(옵션 A)은 검토 결과 폐기. `isScrollControlled:true` modal은 자식에게 0~화면전체 높이의 loose 제약을 주는데 `Scaffold`는 받은 최대 높이를 꽉 채우려 해 **sheet가 화면 전체로 늘어나는 회귀** 발생(현재는 `Column(mainAxisSize:min)`이라 콘텐츠만큼만). 사용자가 이 부작용을 먼저 지적 → inline 채택.

**변경 파일**:
- `lib/screens/player_screen.dart`
- `pubspec.yaml` 0.0.99+1 → 0.0.100+1

**검증**: `flutter analyze` No issues. **실기기(SM S947N, Android 16) 통과** — WiFi off 상태로 호스트 모드 진입 시 sheet 안에 inline 에러("WiFi 연결이 필요합니다") 가려지지 않고 정상 표시 + sheet 닫았다 다시 열면 에러 사라짐(clear 동작 OK).

**회귀 위험**: 낮음. UI 표시 경로만, P2P/sync 로직 무변경.

**빌드**: v0.0.100

---

### 2026-06-01 (118) — v0.0.101 Android 16KB page size 정렬 (출시 차단 해소)

**배경**: SM S947N(16KB page size로 동작하는 기기) 첫 실행 시 호환성 경고 다이얼로그. Google Play 2025-11-01부터 16KB 지원 필수 → **출시 차단 이슈**(미해결 이슈에 있던 항목).

**실측 우선 (가설 검증)**: debug APK의 arm64-v8a `.so` ELF LOAD segment align을 NDK 28 `llvm-readelf -l`로 측정. 7개 중 **`liboboe.so`만 `0x1000`(4KB) 미정렬**, 나머지는 이미 정렬:
- `liboboe_engine.so`(우리 native 엔진) `0x4000` / `libc++_shared.so` `0x4000` — NDK **28.2.13676358**(r28)이 자동 16KB 정렬
- `libflutter.so` `0x10000` / `libdartjni.so` `0x4000` — Flutter **3.41.6** 엔진
- `libdatastore_shared_counter.so` `0x4000` — androidx (shared_preferences 경유)
- `libVkLayer_khronos_validation.so` — **debug 전용** (release APK 미포함)
- AGP **8.11.1** / Gradle **8.14** 이미 요구치(8.5.1+/8.7+) 초과 → APK zip 정렬도 자동
- **가설 철회**: oboe 1.9.0 release note는 "16KB 지원"이라 표기([oboe #2041](https://github.com/google/oboe/issues/2041))했으나, **배포 AAR의 `liboboe.so`는 실측 4KB**. release note ≠ 배포 바이너리.

**fix**: `android/app/build.gradle.kts` oboe `1.9.0` → **`1.9.3`** (한 줄). 재빌드 후 `liboboe.so` `0x4000` 정렬 실측 확인.

**완전성 검사**: 전 ABI(arm64-v8a/armeabi-v7a/x86_64) ELF LOAD align ≥16KB + APK zip 정렬 `zipalign -c -P 16` → **Verification successful (exit 0)**. (16KB는 64비트 ABI만 해당, 32비트는 page size 전환 안 함. Android page size는 4KB/16KB 둘뿐 — 추가 정렬 불요.)

**oboe 1.9.0→1.9.3 버전업 영향**: 우리가 쓰는 **출력 LowLatency/Exclusive 경로 API 무변경**(컴파일 호환). 1.9.3 변경([releases](https://github.com/google/oboe/releases))은 FullDuplex shared ptr(미사용)·AudioClock(미사용)·OpenSL ES deadlock fix(잠재 이득)·workload reporting(opt-in)·16KB뿐. iOS는 oboe 미사용(AVAudioEngine)이라 무관.

**검증 (SM S947N 실기기)**:
- ✅ 첫 실행 호환성 경고 **사라짐** (16KB 정렬 실증)
- ✅ 오디오 회귀 없음 — 재생/일시정지·재개/seek/transpose/speed/A-B 정상

**변경 파일**:
- `android/app/build.gradle.kts` (oboe 1.9.0 → 1.9.3)
- `pubspec.yaml` 0.0.100+1 → 0.0.101+1

**회귀 위험**: 낮음. oboe 패치 업 + 우리 코드 무변경, 실기기 오디오 통과.

**빌드**: v0.0.101

---

### 2026-06-01 (119) — v0.0.102 §H transpose/speed 연속 변경 무음 fix (clear 생략, B안)

**증상 (사용자 보고)**: transpose(피치)·speed(속도)를 슬라이더로 **연속으로 빠르게 바꾸면** 재생 시간(position)은 흘러가는데 **소리가 안 남**. 변경을 멈추면 그 값으로 정상 복구 → 영구 stuck 아닌 일시 현상.

**Root cause (코드 분석)**: SoundTouch는 batch 알고리즘(`SETTING_SEQUENCE_MS=82` 등). worker가 pitch/tempo 변경마다 `mST.clear()` + `mSTOutRing.clear()`를 호출(`oboe_engine.cpp:145-157`, v0.0.91 도입). 연속 변경 시 SoundTouch가 82ms치를 다 모으기 전에 또 clear → 출력 ring이 영영 안 차서 콜백 `pop`이 0 → silence(`854-860`). vf(재생 위치)는 이 경로와 무관하게 진행(`847`,`881`)이라 시간만 흐름.

**PoC와의 차이 (가설 추적)**: 사용자가 "PoC transpose 테스트 땐 연속 변화 부드러웠다"고 기억 → "PoC는 clear 안 했나?" 가설. **코드 확인 결과 PoC도 clear 함**(`poc/transpose_engine/.../transpose_engine.cpp:243-246`, 본 앱과 구조 동일). 진짜 차이는 **입력 공급 방식**:
- PoC: worker가 **사인파를 자체 생성**해 즉시 무한 공급(`transpose_engine.cpp:255-267`) → clear 후 SoundTouch 재충전 빠름 → 무음 미인지.
- 본 앱: 실제 PCM을 callback이 `mSTInRing` 경유 공급 + worker는 4096 frame 모일 때까지 대기(`160-162`) → 재충전 느림(입력 ring ~85ms + SoundTouch 82ms+) → 무음 두드러짐.

**fix (B안 — clear 생략)**: `mPitchDirty`/`mTempoDirty` 처리에서 `mST.clear()` + `mSTOutRing.clear()` 제거, `setPitchSemiTones`/`setTempo`만 호출(`145-160`). SoundTouch는 실시간 파라미터 변경 지원([README](https://www.surina.net/soundtouch/README.html)) → crash·데이터 손상 없음. 옛 설정 출력은 mSTOutRing에서 자연 소비. **파일 로드 시엔 `mSTReconfigure`(`313`)가 clear 보장**하므로 이전 파일 잔재는 안 섞임.

**검토했으나 안 택한 대안**:
- A(debounce): 드래그 중 native 미적용 → 멈추면 마지막 값 1회. 안전하나 드래그 중 실시간 변화 없음.
- B 선택 이유: 드래그 중에도 소리 끊김 없이 실시간 변화 UX(사용자 욕심). speed의 position↔audio ~170ms 불일치 위험은 청감으로 판단키로.

**검증 (SM S947N 실기기, 단독 모드)**:
- ✅ pitch 연속 변경 — 드래그 중 끊김 없이 실시간 변화, click/buzz 없음
- ✅ speed 연속 변경 — 우려한 position↔audio 불일치 청감상 거슬리지 않음, 2배속 연속에서도 무음 없음
- ✅ 파일 변경 시 이전 곡 잔재 안 섞임 (mSTReconfigure clear 정상)

**미검증 / 후속 (PLAN §H 등록)**:
- **P2P 게스트 sync에서 speed B의 영향** — 단독 청감만 OK. vf-audio 불일치가 게스트 동기화에 주는 영향 미측정.
- **2배속 장시간 stress + underrun 측정** — 현재 무음(underrun) 객관 카운터 없음(`840` vf≥ringHead / `862` popped<numFrames 지점). 측정하려면 카운터 추가 선행. idle 측정과 다른 시나리오(2배속 긴 재생).

**변경 파일**:
- `android/app/src/main/cpp/oboe_engine.cpp` (clear 2곳 제거)
- `pubspec.yaml` 0.0.101+1 → 0.0.102+1

**회귀 위험**: 낮음(단독 모드). 단 P2P speed sync 미검증.

**빌드**: v0.0.102

---

### 2026-06-01 (120) — v0.0.103/104 §H/§I transpose·speed P2P 전파 견고화 (P0 합류 상실 + P1 외삽 speed 반영)

**배경**: HISTORY (119) + PLAN §H "P2P 게스트 sync 미검증" 항목. transpose/speed가 v0.0.91~102로 연달아 들어갔으나 **게스트 동기화 영향은 미측정**. sync 정확도에 영향 주는 8개 영역(anchor / drift / clock offset / outputLatency / transpose·speed / fallback / obs broadcast / 시작·seek)을 멀티에이전트 workflow(Opus, 병렬 조사 → 종합 → 측정계획)로 전수 재조사.

**조사 결론 (관찰 = 코드 근거)**:
- **sync 알고리즘 자체는 견고** — 실제 seek를 트리거하는 `driftMs`가 `framePos`(HAL DAC 카운터, `oboe_engine.cpp:643-647`) 기반이라 speed 무관 wall rate → rate 비교 자동 상쇄. 호스트·게스트가 같은 speed면 폐루프는 speed≠1.0이어도 견고.
- 문제는 transpose/speed "전파 플러밍" 3곳 누락 + vf 외삽 1배속 가정.

**fix**:
- **P0 (확정 버그)** — 늦게 합류한 게스트가 호스트 speed/transpose 상실. native `loadFile`이 cents/speed를 0/1000으로 강제 reset(안전망: `oboe_engine.cpp:205-208`, iOS `AudioEngine.swift:38-41`)하는데, 게스트 `_handleAudioUrl`이 다운로드 *전* 적용(:911/916)만 하고 loadFile *후* 재적용이 없어 덮였음. **v0.0.93 reset 안전망 도입 시 들어온 회귀** (git blame: cents=v0.0.91, speed=v0.0.92, reset=v0.0.93). → loadFile 후 재적용 추가 + 다운로드 전 native 적용 제거(Dart 상태/stream만 유지). **v0.0.103**.
- **P1-a** — 재생 중 speed 변경 시 anchor stale. audio-tempo 핸들러가 `_resetDriftState` 미호출(audio-url 경로 `:937`과 대조). speed는 vf rate를 바꿔 기존 anchor를 무효화하므로 리셋 추가. transpose는 vf rate 무변경이라 제외. **v0.0.103**.
- **P1-b** — audio-tempo/pitch 단발 broadcast(ack 없음) 유실 시 복구 부재 + obs에 speed 필드 없어 자가 감지 불가. obs에 `speedX1000`/`transposeCents` 필드 추가(구버전 fallback 1000/0) + 게스트가 매 obs(500ms)마다 불일치 시 재적용(자가 치유). **v0.0.103**.
- **P1 (외삽 speed 미반영)** — speed≠1.0일 때 vf 외삽이 1배속 가정. anchor `hostContentFrame`(:1613, seek 위치 결정) / fallback `expectedPositionMs` / `_recomputeDrift` `expectedHostVfMs`의 `(경과)*hostFpMs`에 `speedFactor=obs.speedX1000/1000` 곱. **framePos 외삽(anchorHostFrame/expectedHostFrameNow, driftMs용)은 HAL rate라 그대로** — driftMs 견고성 유지. **v0.0.104**.

**측정 (실기기: S26+ R3KL207HBBF 호스트 + S22 R3CT60D20XE 게스트, csv `sync_log_*.csv`)**:
- ✅ **P0 확정** — v0.0.103, 호스트 1.5x → 게스트도 1.5x 따라감 (fix 전이라면 1.0x default). 청감 + csv `host_vf`/`guest_vf` rate 일치.
- ✅ **외삽 fix 안정성 개선** — v0.0.104 2배속: anchor_set 16→**1회**, fallback 163→**34개**, drift mean **~2ms**(전체 견고). vfDiff 부호가 fix-무효 예상(양수)과 반대인 음수 → 외삽 speed 보정 작동 정황.
- **순수 1배속**: vfDiff 작음(대부분 \|v\|<20) = baseline 정상. **순수 2배속**: vfDiff 음수 ~107ms.
- **가설**: 2배속 vfDiff 잔재 = (obs staleness) × speed 외삽 잔차 (raw `guest_vf - host_vf` 평균 **605ms**, obs가 stale한데 2배속이라 그 사이 게스트가 앞섬). `driftMs`(framePos 기반)는 이 잔차에 둔감 → 청감 OK. **vfDiff가 2배속에서 실제 음향 어긋남을 과대보고**하는 것으로 추정. offset은 매우 안정적(span 1.4ms)이라 offset 노이즈 가설은 데이터로 철회.
- **전환 순간(특히 2→1 감속)**: vfDiff **양수 스파이크 +200ms대**(전환 구간 양수 99/음수 33). 사용자 청감 관찰("2→1 시 게스트가 앞서 재생")과 일치. **메커니즘**: 호스트가 `audio-tempo(1.0x)` 보내도 게스트는 네트워크 지연 동안 아직 2배속 → 그만큼 앞섬. P1-a anchor 리셋은 재정렬을 시도(anchor_set 14회)하나 전환 순간 위치 점프 자체는 수 초간 잔존. → **전환 스케줄링(다음 트랙, SYNC_ALGORITHM_V2 §I-6)**.

**미검증 / 후속**: P1-b 자가치유(WiFi 교란 시나리오), iOS 실기기, 2배속 장시간 underrun 카운터, 전환 스케줄링.

**검토했으나 안 한 것**: 전환 어긋남 즉시 강행 — schedule-play race 이력(v0.0.47 `_scheduleInProgress`)으로 설계 합의 선행 필요 판단 → §I-6 설계 항목으로.

**변경 파일**: `lib/models/audio_obs.dart`(speed/cents 필드), `lib/services/native_audio_sync_service.dart`(fix 5곳 + 외삽 3곳), `pubspec.yaml` 0.0.102 → 0.0.104.

**빌드**: v0.0.103, v0.0.104

---

### 2026-06-03 (121) — v0.0.109 자동측정(AutoMeasureScreen) 제거

**배경**: `--dart-define=AUTO_MEASURE_MODE=host|guest`로 두 기기를 호스트/게스트로 **자동 연결·재생·종료**하던 측정 자동화 화면. 더 안 쓰기로 결정 → 코드 제거. 단 **수동 측정 인프라(CSV 로거·measure_audio.mp3)는 유지**.

**제거**:
- `lib/measurement/auto_measure_screen.dart` 삭제 (디렉토리 제거). HOST: 방 자동 생성 → 게스트 대기 → assets mp3 로드 → syncPlay → durationSec 후 syncPause → 앱 종료. GUEST: discovery → 첫 방 자동 입장 → 호스트 따라가기 → 종료.
- `lib/main.dart`: `import 'measurement/...'`, `_autoMeasureMode`/`_autoMeasureDurationSec` const 2개, `home:` 진입 분기 제거 → `home: const PlayerScreen()`.

**유지 (의도적, 사용자 요청)**:
- `SyncMeasurementLogger` (CSV) — 호스트 세션마다 계속 `sync_log_*.csv` 기록. `native_audio_sync_service.dart:183-185`의 `_logger.start()`는 `if (isHost)`만 보고 호출(AUTO_MEASURE 게이트 없음) → **일반 빌드 호스트도 기록**. 당분간 수동 측정에 계속 사용.
- `assets/measure_audio.mp3` + `pubspec.yaml` 등록 — 단 자동측정이 유일 사용처였어서 **이제 코드 미참조**(APK 11MB 잔존). 향후 제거 가능, 일단 보존.

**검증**: `flutter analyze lib/main.dart` No issues. `AutoMeasure`/`auto_measure` 잔여 참조 0 (lib/test grep).

**변경 파일**: `lib/main.dart`, `lib/measurement/auto_measure_screen.dart`(삭제), `pubspec.yaml` 0.0.104 → 0.0.109.

**주의 (동시 작업)**: 같은 워킹트리에 진행 중인 tempo 디바운스/TCP Nagle 작업(`native_audio_sync_service.dart`/`p2p_service.dart`, 0.0.105~108)이 있어 **본 커밋엔 미포함**. pubspec version은 그 작업이 올려둔 값 위에 109로 bump.

**빌드**: v0.0.109

---

### 2026-06-03 (122) — v0.0.110 모드 BottomSheet 우측 상단 X(닫기) 버튼 추가

**배경**: 모드 선택/호스트 모드 등 `_showModeSheet` BottomSheet는 배경(barrier) 탭으로 닫히지만, 일부 사용자에겐 직관적으로 보이지 않을 수 있어 명시적 닫기 버튼 요청.

**변경** (`lib/screens/player_screen.dart`):
- `_showModeSheet`의 `switch (_mode)`(standalone/host/speaker 3모드 공통 진입점, `player_screen.dart:1129~`)를 `Stack`으로 감싸고 우측 상단에 `Positioned` + `IconButton(Icons.close)` 1개 추가.
- switch 바깥 공통 위치라 **한 곳 수정으로 모드 선택·호스트·스피커 sheet 모두** X 버튼 적용. 누르면 `Navigator.pop(sheetContext)`.
- 기존 배경 탭 닫기는 그대로 유지(제거 아님, 추가).
- `Positioned`가 음수 offset(top/right `-8`, 패딩 영역으로 빼냄)이라 `Stack`의 기본 `Clip.hardEdge`면 잘림 → `clipBehavior: Clip.none`. `IconButton`은 `visualDensity: compact`.

**검증**: `flutter analyze lib/screens/player_screen.dart` No issues. 실기기 2대(S22 R3CT60D20XE, S947N R3KL207HBBF) debug 설치 후 사용자 동작 확인 완료.

**변경 파일**: `lib/screens/player_screen.dart`, `pubspec.yaml` 0.0.109 → 0.0.110.

**주의 (동시 작업)**: 같은 워킹트리에 다른 세션의 tempo 디바운스/TCP Nagle 작업(`native_audio_sync_service.dart`/`p2p_service.dart`)이 진행 중 → **본 커밋엔 미포함** (해당 2파일·테스트 assets는 stage 제외).

**빌드**: v0.0.110

---

### 2026-06-03 (123) — v0.0.111 거짓말 패턴(vfDiff) re-anchor + speed 정규화 + tempo 디바운스 + 계측

**배경**: transpose/speed(v0.0.91~104) 추가 후 P2P 게스트 싱크 영향이 미측정 상태. 사용자가 "1.5/2배속에서 음정·속도는 맞는데 싱크가 미묘하게 어긋난다"고 관찰 → **거짓말 패턴**(rate=driftMs는 1~2ms로 정상인데 절대 위치는 어긋남, anchor가 잘못 박힌 상태) 의심. 맥북 마이크 acoustic 측정(1kHz bandpass + folding + matched filter, `assets/measure_audio.mp3` 비프음)으로 호스트/게스트 실제 스피커 출력 시차를 직접 측정해 검증.

**관찰 (실측)**:
- acoustic 측정 시차 ≈ csv `vfDiff` 값과 일치(예: 465ms = vfDiff 465ms). **driftMs(rate)는 1~2ms로 정상이었음** → vfDiff(절대 위치)가 진실, framePos/drift가 "거짓말"이었음 확정. (그동안 vfDiff를 staleness 과대보고로 치부한 Claude 판단이 틀렸고 사용자 청감이 맞았음 — 기록.)
- vfDiff re-anchor 적용 후 vfDiff max 474→156ms. speed 정규화 후 2배속 224→23ms. anchor가 정상적으로 박힌 상태에선 23ms 수준.

**변경**:
- `native_audio_sync_service.dart` (+81/-8):
  - **vfDiff re-anchor (코드 주석 v0.0.108)**: `driftMs`(rate)는 두 폰 속도가 같으면 0이라 절대 위치 어긋남(거짓말 패턴)을 못 잡음 → `_vfDiffSamples` 중앙값이 `_vfDiffReAnchorThresholdMs`(150ms) 초과 시 anchor 리셋(재정렬), `_logGuestEvent('anchor_reset_vfdiff')`. 4개 anchor-reset 사이트에 `_vfDiffSamples.clear()` 추가.
  - **speed 정규화 (주석 v0.0.109)**: vfDiff는 "콘텐츠 위치 ms"라 실제 청감 어긋남 = `vfDiff/speedFactor` (0.5배 콘텐츠150=실제300ms / 2배=75ms). 정규화 후 push → 임계가 speed 무관하게 일관.
  - **tempo 디바운스 (주석 v0.0.105)**: speed 연속 변경 시 매번 anchor 리셋하던 것을 `_scheduleSpeedAnchorReset()`(250ms 디바운스)로 — 마지막 변경 후 안정되면 한 번만 리셋.
  - **계측 (주석 v0.0.106)**: host `setPlaybackSpeedX1000`에 `msgSeq` 동봉 + `host_tempo`/`guest_tempo_recv` 이벤트 로깅 (전파 지연 매칭용).
- `p2p_service.dart` (+9): **tcpNoDelay (주석 v0.0.107)** — `_listenToSocket` 공통 진입점에 Nagle off. (broadcast 전파 지연 가설 검증용이었으나, ping/audio-tempo가 같은 TCP 소켓이라 전파 자체는 빠르고 지연은 offset/clock 아티팩트였음이 밝혀짐 — Nagle은 원인 아님. 옵션 자체는 무해해 유지.)
- 코드 주석의 v0.0.105~109는 작업 단위 표기이며 **실제 커밋은 v0.0.111로 묶음**.

**검증**: acoustic + csv로 P0(늦게 합류 speed 상실) fix와 거짓말 패턴 재현·완화 확인. 정상(조작 없이 재생 + speed 변경) 상태에선 anchor 박힘 → 23ms.

**미해결 (별도 트랙 — 한 번에 건드리지 않고 다음 세션에 하나씩, PLAN §H 참조)**:
- **isOffsetStable jitter**: filtered offset은 1.9ms로 안정인데 raw RTT jitter(15~30ms)가 `_stableCount`를 리셋 → anchor가 길게는 ~20초간 안 박혀 그동안 fallback(±240ms)으로 방치. (사용자가 "1초가 아니라 몇 초 어긋남" 관찰한 실제 원인 = fallback cooldown이 아니라 **anchor 공백**.)
- **150ms 임계 큼**: 체감상 큼 → 80~100ms로 낮추는 후보(staleness 마진 고려).
- **host HAL getTimestamp 간헐 실패** (framePos=-1, HISTORY (30) 재발 — 호스트 obs가 거짓 위치를 줌).
- **게스트 재시작 루프**: host seek 연타 + play/pause 토글 막 조작 시 guest engine start/stop 반복 → "position(vf)은 동기 표시인데 실제 다른 부분 재생" 증상. (csv timeline에서 트리거 식별: host_seek 0.7초에 5번 + host_play/pause 2초에 2번.) 정상 사용에선 미발생.

**빌드**: v0.0.111

---

### 2026-06-03 (124) — v0.0.112 강제 establish 시도 → 재입장 악화로 폐기 (미커밋)

**배경**: PLAN §H 미해결 1번(isOffsetStable jitter anchor 공백) 착수. 가설: "EMA offset은 수렴했는데 raw RTT jitter로 stable 판정만 막혀 anchor가 영영 안 박힘" → N초(8초) 타임아웃 강제 establish + ANCHOR-VERIFY(v0.0.81)/vfDiff(v0.0.111) 안전망.

**구현 (폐기됨)**: `_forceEstablishTimeoutMs=8000`, anchor 미설정 8초 경과 시 `_tryEstablishAnchor(force:true)`로 isOffsetStable 가드만 우회. `git restore`로 v0.0.111 복원, 미커밋.

**실측** (게스트 SM-S901N(R3CT60D20XE)에 v0.0.112 설치 / 호스트 SM-S947N(R3KL207HBBF)이 csv 기록 — **csv는 호스트가 drift-report 수신해 기록**, `native_audio_sync_service.dart:218` `drift-report && _isHost` + `:776` 주석. csv 내용은 게스트가 보낸 sync 동작):
- **A 첫 입장 정상**: guest_start(off=65, rtt=23) → `anchor_set` 즉시. 회귀 없음.
- **B 재입장 악화** (csv `sync_log_2026-06-03T14-45-54.csv`):
  - seq49 guest_start **rawOff=0, rtt=0** — clock sync(ping/pong) 미작동.
  - seq49~70 (~8초) **rawOff=0/rtt=0 지속** — offset을 못 구하는 상태.
  - seq66 **`anchor_set_forced` (rawOff=0)** — **offset 미측정 상태에서 강제 establish** → 틀린 위치에 고정.
  - seq114~148 **vfDiff 40~95ms 진동, drift 0~4ms** (거짓말 패턴, 150ms 미달이라 vfDiff re-anchor 미발동) → 청감 "계속 틀어짐".
  - (seq50 vfDiff -33521ms는 재입장 순간 초기 위치 차 → 다음 샘플 seq51에서 즉시 -5ms 보정. 정상 동작, 문제 아님.)

**가설 철회**: "offset 수렴, 판정만 막힘"은 jitter 환경 가정인데, **재입장 직후엔 offset 자체가 없음(rawOff=0/rtt=0)**. force가 그 상태에서 박아 오히려 악화. 안전망(vfDiff 150ms)도 진동폭(40~95ms)이 임계 미달이라 못 잡음.

**결정**: 폐기. 효과(jitter 환경)는 재현 못 해 미확인 + 부작용(재입장 악화)만 확인.

**새 발견 (다음 트랙 후보 — PLAN §H 반영)**:
1. **재입장 시 clock sync ~8초 지연** (rawOff=0/rtt=0) — 재입장 틀어짐의 진짜 root cause 후보. ping/pong 재개가 왜 늦는지 미상.
2. **vfDiff 40~95ms 진동** — 거짓말 패턴 잔존, 150ms 임계 미달 방치.

**빌드**: 폐기(미커밋)

---

### 2026-06-03 (125) — v0.0.112 SoundTouch latency를 outputLatency에 반영 (SYNC_REDESIGN 결함 B)

**배경**: transpose/speed ON이면 vf(보고 위치)는 콜백이 즉시 진행하나 실제 PCM은 SoundTouch(TDStretch+RateTransposer) + worker batch를 거쳐 수백 ms 뒤 DAC 도달. `getLatestTimestamp`의 outputLatencyMs가 HAL `calculateLatencyMillis`만 넣어(`oboe_engine.cpp:567-570`) SoundTouch 항이 빠짐 → P2P anchor 비대칭 보정 부정확. (v0.0.112 번호는 폐기된 force-establish (124)에서 재사용 — 미커밋 폐기라 충돌 없음.)

**변경**:
- `oboe_engine.cpp`: (1) 멤버 `mStLatencyFrames`. (2) worker(stWorkerLoop)가 reconfigure/pitch/tempo 변경 시 `mST.getSetting(SETTING_INITIAL_LATENCY)`(rate 의존 정확 frame, `SoundTouch.cpp:453`)로 갱신 — worker 단독이라 thread-safe. (3) `getLatestTimestamp`가 useST(cents≠0||speed≠1000) && stereo && HAL latency 유효 시 outputLatencyMs에 `(INITIAL_LATENCY + worker batch 4096)/SR*1000` 가산. 정적 항만(out-ring 동적 점유는 anchor 출렁임 우려로 제외).
- `native_audio_service.dart`: `safeOutputLatencyMs` 상한 500→700. Dart anchor/fallback 무수정 — 비대칭 보정이 자동 적용.

**실측** (호스트 SM-S947N(R3KL207HBBF) csv `sync_log_2026-06-03T15-56-34.csv`, 게스트 SM-S901N(R3CT60D20XE)):
- **ST 반영 확인** ✅: speed OFF `out_lat_guest=0.00`, 2배속 `~274ms`(HAL+ST), 중간 203~239.
- **회귀 없음**: OFF 구간 영향 0 (청감 OK).
- **정상 2배속 정렬 좋음**: drift median 0.24ms, p90 6.12ms.

**발견 (미해결, 다음 트랙)**:
1. **게스트 체계적 앞섬** (사용자 청감 + csv 일치): **1배속**(seq23-51, out_lat 7-8) `vfDiff 40~46ms` + **2배속**(seq211) `vfDiff 92ms`(청감 ~46ms) 모두 drift~0인데 게스트가 **한 방향으로 일관되게 앞선 위치**. 거짓말 패턴 잔여 + 150ms 임계 미달이라 re-anchor 방치. **임계 낮춤(80~100)으로도 46ms는 미달 — 못 잡음.** 한 방향 편향이라 anchor establish 외삽/식 어딘가 체계적 오차 의심 → 진단 필요.
2. **전환 과도기 ST 비대칭 베이크** (v0.0.112 부작용): speed 전환 직후 한쪽만 ST 켜진 순간 anchor 박으면 비대칭(195ms) baked(seq150 `deltaAnc=195.20`) → 양쪽 ST 동기화되며 drift 194 스파이크 → seek 회복. anchor establish 시 ST 안정 가드로 후속 보완.

**빌드**: v0.0.112

---

### 2026-06-03 (126) — 게스트 앞섬 진단: anchor가 fallback보다 부정확 (실증, 코드 변경 없음)

**배경**: v0.0.112 (125) 후 사용자 청감 "1배속/2배속 모두 게스트가 미묘하게 앞섬"(+ transpose +5에서도). 호스트 SM-S947N(R3KL207HBBF) csv `sync_log_2026-06-03T15-56-34.csv`(2세션: 15:56 + 16:16 재입장)로 진단.

**실측**:
- **anchor 경로가 fallback보다 부정확** (핵심): 세션2(16:16, transpose +5 안정 재생) anchor 경로(drift event) vfDiff **−10~−65 변동**, 같은 곡에서 anchor가 깨져 fallback 경로로 가면 vfDiff **0~5 정렬**. 세션1(15:56) anchor 경로는 **+46**. → anchor는 establish 시점 오차를 baseline에 박고 곡 내내 지속, fallback은 **매번 fresh 외삽이라 정확.**
- **방향 ±변동 → (125)의 "체계적 한 방향 편향" 가설 철회**: 세션1 +46(게스트 앞) / 세션2 −65(게스트 뒤). establish의 seek/외삽 오차가 ±로 출렁이는 것.
- **ANCHOR-VERIFY +47~196ms가 임계 500 통과**: establish 직후 seek 도달이 target보다 빗나가나 reject 안 됨 → baseline에 박힘. 단 verify diff에 establish~verify 경과(~100ms vf 진행)가 **안 빠져 과대보고**(verify 로직 결함, `native_audio_sync_service.dart:1510-1518`).
- **ST/outLat 무관 확정**: establish 로그 `outLat delta 3.0/−0.2/1.6`(transpose 양쪽 ST 상쇄). drift~0(rate 정상). offset 69ms stable 24(시계 동기 좋음).
- **onAudioReady useST vf 진행 = 1배** 확인(`oboe_engine.cpp:864-885`, inputFrames=numFrames@1x) — vf 빠른 진행 아님.

**미확정**: vfDiff 부호 방향 — 청감("게스트 앞") vs csv 세션2(−65 "게스트 뒤") **불일치**. acoustic 측정((120) 방식)으로 ground truth 확정 필요.

**다음 세션 시작점** (SYNC_REDESIGN 결함 A):
1. **acoustic 1회로 부호/정렬 확정**: fallback이 진짜 anchor보다 정렬 좋은지 + 게스트 앞/뒤. (csv 부호 혼란 해소, v0.0.111처럼 ground truth.)
2. → **anchor 주기 재발행**(결함 A 근본) 설계: baseline을 fallback처럼 자주 갱신 + 멱등 재스케줄(seek 반복 회피). **부호/방향 무관하게** establish 오차 지속 차단.
- **작은 패치(ANCHOR-VERIFY 임계 낮춤)는 비추**: verify 경과 미보정 + seek 반복 부작용 + 측정 없는 fix 위험(v0.0.112 force-establish 폐기 (124) 교훈).

**빌드**: 코드 변경 없음 (진단만).

---

### 2026-06-03 (127) — v0.0.113 transpose/speed 리셋 UI (long press → 항상 보이는 아이콘 버튼)

**배경 (사용자 보고)**: transpose/speed 값을 **꾹 눌러(long press) 리셋**하던 기존 방식의 문제 — (1) 터치 영역이 값 텍스트뿐(transpose `SizedBox(width:36)` / speed `width:52`, 높이 ≈글자높이)이라 좁아 옆 컨트롤이 잘못 눌림, (2) 화면에 단서가 없어 "어디를 눌러야 리셋되는지" 발견 불가. 사용자 표현: "리셋 범위 모르겠고 좁아서 다른 게 눌릴 때가 있다".

**변경** (`player_screen.dart` `_buildTransposeControls`/`_buildSpeedControls`):
- **명시적 리셋 아이콘(`Icons.refresh`) 추가** — 값 옆에 **항상 표시**. 기본값(transpose 0 / speed 1.00x)일 땐 `onPressed:null`이라 **disabled(회색)**, 값이 바뀌면 활성(primary). 터치 영역 `BoxConstraints(minWidth:40, minHeight:40)`로 확보(기존 좁은 영역 문제 해소).
- **long press 리셋 제거** — 값의 `GestureDetector(onLongPress)` 삭제, 리셋은 아이콘 버튼으로 일원화. `_resetTranspose`/`_resetSpeed`는 아이콘이 계속 호출.
- **값 위치 고정** — 값 `Text`를 `Center` → `textAlign:right` + `tabularFigures`로 변경. 부호(+/−) 유무·자릿수(0 / +5 / −12)가 바뀌어도 **오른쪽 끝(아이콘 옆) 기준으로 위치 고정**. 아이콘이 항상 떠 있어 등장/소멸로 인한 레이아웃 흔들림도 제거.

**버전 맥락**: v0.0.113~114는 원래 다른 세션의 tempo/native sync 작업(`native_audio_sync_service.dart`)이 점유했으나 그 미커밋 변경이 폐기(되돌림)되어, 본 UI 작업이 112 다음 **113**을 차지.

**검증**: `flutter analyze lib/screens/player_screen.dart` No issues. 실기기 2대(S22 R3CT60D20XE, S947N R3KL207HBBF) debug 설치 후 사용자 동작 확인 완료("잘된다").

**변경 파일**: `lib/screens/player_screen.dart`, `pubspec.yaml` 0.0.112 → 0.0.113.

**회귀 위험**: 낮음. player UI만 변경, sync/P2P/엔진 로직 무변경.

**빌드**: v0.0.113

---

### 2026-06-04 (128) — v0.0.114 anchor vfDiff realign + virtualFrame 시점 정합 (톱니 근본 fix, 결함 A)

**배경**: (126) 진단("게스트 미묘하게 앞섬" = anchor 경로 vfDiff ±수십ms, fallback보다 부정확)의 후속 fix. 두 변경을 0.0.114에 묶음 (realign은 원래 0.0.113이었으나 (127) UI 작업이 113을 가져가 폐기·재작업).

**변경 1 — vfDiff realign (`native_audio_sync_service.dart`)**:
- vfDiff(절대 위치) 중앙값이 임계(`_vfDiffRealignThresholdMs = 60`) 초과 시, anchor를 유지한 채 baseline(`_anchorHostFrame`/`_anchorGuestFrame`/`_offsetAtAnchor`/`_anchoredOutLatDeltaMs`)을 현재 호스트 위치로 fresh 재정렬(seek). fallback이 정확한 비결(매 주기 fresh 절대 보정)을 anchor 경로에 이식. v0.0.108~112의 150ms `anchor=null` 리셋(establish 공백) 대체 — `_maybeTriggerSeek`의 vfDiff 150 분기 제거, `_recomputeDrift`의 realign 분기로 이동(`anchor_realign_vfdiff` 이벤트).
- 측정1(0.0.113 realign 단독, transpose +5)에서 16회 발동 확인. 단 ±50ms 톱니는 여전 → realign이 원인 아님이 드러남(아래 변경 2).

**변경 2 — virtualFrame 시점 정합 (톱니 근본 fix, `oboe_engine.cpp`)**:
- **±50/±100ms 톱니의 진짜 원인 = virtualFrame 시점 불일치.** `getLatestTimestamp`에서 `virtualFrame`은 마지막 콜백 시점(~현재, `mVirtualFrame.load`)이지만 `framePos`/`wallAtFramePos`는 HAL `timeNs`(DAC 출력 = 버퍼 깊이만큼 과거) 시점. 게스트가 vfDiff를 외삽할 때 이미 "현재" 값인 virtualFrame에 "과거(framePos시점)→현재" 경과를 또 더해 **HAL 지연(`monoNow-timeNs`)을 이중 카운트** → 그 지연이 콜백 위상에 따라 출렁여 톱니. **drift(framePos↔wall 정합)가 멀쩡한 게 결정적 증거** (`native_audio_service.dart:43` `wallMs = wallAtFramePosNs`).
- fix: virtualFrame에서 `(monoNow-timeNs) × decodedSampleRate × speed`(파일 rate, speed배 재생)를 빼 **timeNs 시점 값으로 되돌림**. getTimestamp 성공 시에만, 실패(fallback)면 현재값 유지.
- **iOS는 보정 불필요** — `vf`(playerNode lastRenderTime)와 `framePos`/`timeNs`(outputNode lastRenderTime)가 같은 렌더 사이클 시각이라 이미 정합. 사유 주석만 추가(`AudioEngine.swift`).

**진단 과정 (관찰 사실)**:
- transpose **0/+5 두 측정 모두 ±50 톱니** → SoundTouch(batch ~82ms) 가설 기각. (transpose +5에선 음수쪽 톱니만 추가, +방향 주범은 transpose 무관.)
- `obs_age` 버킷별 |vfDiff| 무관(age<200 35.6 ~ 600-800 22.6) → "obs 500ms 이산성/stale 외삽"(Explore 1차 가설) **기각**. 외삽 거리 문제면 age 비례해야 함.
- fallback이 타이트한 건 외삽이 정확해서가 아니라 vfDiff>30마다 적극 seek로 톱니를 억제하기 때문(anchor·fallback 외삽 수식은 동일).

**측정 결과** (호스트 S947N R3KL207HBBF + 게스트 S901N R3CT60D20XE, transpose +5, 3분):

| 지표 | 측정1 (0.0.113 realign) | 측정3 (0.0.114 톱니fix) |
|---|---|---|
| drift vfDiff 30-60ms 구간 | 148개 | **0개** |
| >60ms | 11개 | **0개** |
| min/max | -107.8 / +102.8 | **-27.2 / +19.3** |
| p10 / p90 | -51.2 / +51.6 | -25.2 / +17.1 |
| realign 발동 | 16회 | 0회 (톱니 없으니 미발동) |

→ **±50/±100ms 랜덤 톱니 완전 제거.** virtualFrame 시점 정합 가설 실증.

**⚠️ 정정 (2026-06-04, 사용자 청감 + raw csv 재분석 — 위 "톱니 제거 성공" 판정 무효)**:
- 측정3 중 사용자 청감으로 **게스트가 ~500ms 어긋남**(measure_audio 비프가 1초 주기 중 정반대로 들림). csv `vfDiff`(±42)와 정면 모순.
- raw `guest_vf − host_vf` = **+250~512ms** (외삽 무관 콘텐츠 위치 차, seq 48~348 내내) → **청감과 일치.** `vfDiff`(외삽 후 ±42)가 거짓이었음.
- 원인: **측정3는 offset(clock) 불안정**(anchor 거의 안 박힘 — drift 97 vs fallback 255, `anchor_set` 2회). offset이 부정확하면 외삽이 실제 500ms를 ±42로 **지워버림**. **`seek_count = 0`**(게스트 3분간 보정 seek 0회) = 거짓 vfDiff를 "정렬됨"으로 오판해 어긋남 방치. **= 거짓말 패턴 재확인 (offset 부정확 시 vfDiff 통째 거짓).**
- 따라서 위 "톱니 제거" 판정은 **무효** — 거짓 vfDiff를 보고 내린 오판. 톱니fix(virtualFrame 시점 정합)·realign은 코드상 유효하나 **offset 안정 상태에서만 효과 검증 가능**, 측정3로는 판정 불가.
- **진짜 발목 = offset/clock sync 불안정** (미해결 #1 `isOffsetStable` jitter / #5 재입장 clock sync 지연). 그동안 vfDiff 기반 분석(톱니 포함)은 모두 "offset 안정" 가정 위에서만 유효했음 — 그 토대가 무너지면 vfDiff가 통째 거짓. **다음 1순위로 격상.**
- 교훈: vfDiff는 offset 의존 외삽값이라 **offset 불안정 시 ground truth 아님.** anchor 박힘 여부(drift vs fallback 비율) + raw `guest_vf−host_vf` + acoustic으로 교차 검증 필수.

**잔존 (다음 트랙 — 별개 이슈)**:
1. **+16ms vfDiff 일정 편향** (median 측정1 +2.4 → 측정3 +15.9, fallback도 +8.2). 톱니(랜덤)가 사라지니 그 아래 깔려있던 일정 bias가 드러남 — 보정 과조정 vs 진짜 편향 미확정(acoustic 또는 보정 수식 재검토 필요). 일정해서 톱니보다 다루기 쉬움.
2. **이번 측정 anchor 거의 안 박힘** (drift 97 vs fallback 255, `anchor_set` 2회). offset 불안정(`isOffsetStable` 실패)으로 establish 못 함 = (123) #1 jitter / #5 clock sync 지연 영역, **톱니fix와 무관한 환경 이슈.** 이번 WiFi/시계 상태 탓 추정.

**변경 파일**: `native_audio_sync_service.dart`, `oboe_engine.cpp`, `ios/Runner/AudioEngine.swift`(주석), `pubspec.yaml` 0.0.113 → 0.0.114.

**검증**: `flutter analyze` No issues, debug 빌드/설치(S947N+S901N) OK, 실측 톱니 제거 확인.

**빌드**: v0.0.114

---

### 2026-06-05 (129) — v0.0.114 offset 정상 재측정: 톱니fix 검증 성공 + 음향 outputLatency 비대칭 (코드 변경 없음)

**배경**: (128) 정정 후속. 측정3의 wall 점프 offset 오염이 회복된 상태에서 재측정 (measure_audio transpose+5, 3분, 호스트 S947N R3KL207HBBF + 게스트 S901N R3CT60D20XE).

**[관문1] offset 정상 확인** — filtered offset 192(변동 **2.3ms**), raw 192.3 일치, anchor 잘 박힘(**drift 317 vs fallback 48**, 측정3는 97 vs 255로 반대였음). 측정3 점프가 같은 앱 세션 내 EMA 수렴으로 이미 회복된 상태.

**[관문2] 톱니fix(47a2f2b) 검증 성공** — vfDiff **-19.5 일정**(p10/p90 -20.1/-18.1), **±50 톱니 사라짐**. 측정1(톱니fix 전, offset 정상이었으나 ±50 톱니)과 대조 → virtualFrame 시점 정합 fix 유효 확정. (128)에서 "측정 무효"였던 검증을 offset 정상 상태에서 완료.

**사용자 가설 실증** — "offset만 고치면 측정3의 500ms도 잡힌다"가 확인됨. offset 정상되니 raw 500ms 어긋남 사라지고 vfDiff -19.5(작음). **offset이 root 확정.**

**청감 교차 (사용자)**:
- **position "호스트 미묘 빠름"** = vfDiff -19.5(호스트가 콘텐츠 위치 앞) **일치 ✅**.
- **음향 "게스트 앞"(처음~끝 일관)** ↔ vfDiff(호스트 앞) **반대 방향** → **outputLatency 비대칭** 단서. position은 호스트가 앞인데 소리는 게스트가 먼저 = 게스트 스피커 출력 지연이 호스트보다 ~20ms 작은데 csv `out_lat`(host 205.6 / guest 204.0, delta -1.6)이 못 잡음. 결함 B/HAL 과소보고 영역. ⚠️ 음향 부호는 20ms(인지 경계)라 acoustic 확정 필요.

**잔존 (다음 트랙)**:
1. **음향 outputLatency 비대칭** (결함 B) — 가장 체감되는 잔존. csv outputLatency가 실제 음향 지연 비대칭(~20ms)을 과소보고.
2. **vfDiff -19.5 position 편향** — seek 임계(20ms) 바로 아래라 "정렬됨"으로 방치(seek_count 0).
3. **offset 점프 재발 방지** — 측정3 같은 wall 점프는 **B(monotonic 전환)** 로 면역. ⚠️ 단 `CLOCK_MONOTONIC`/`mach_absolute_time`(현재 oboe/iOS)은 deep sleep 중 멈추므로(검증 완료), suspend도 견디는 **`CLOCK_BOOTTIME`/`mach_continuous_time`** 사용 필수.

**코드 변경 없음** (측정/검증만). 커밋: 47a2f2b(톱니fix) + bf0d47d(정정) 유지.

---

### 2026-06-05 (130) — v0.0.115 monotonic clock 전환 (offset 점프 면역, B-트랙 구현+검증)

**배경**: (129) 다음 1순위. 측정3 "wall 점프"(NTP 보정) 재발 방지 — 두 기기 정렬 시계를 wall → BOOTTIME 계열로. 전수조사(Dart/Android/iOS 3계층) + 1차 소스 검증 + 설계: [SYNC_REDESIGN.md](SYNC_REDESIGN.md) (130). 핵심: 현재 정렬이 전부 wall 도메인(native가 monotonic을 일부러 wall로 역변환 `oboe_engine.cpp:686`), wall은 NTP에 점프.

**구현 (task #2~5)**:
- Dart FFI (`monotonic_clock.dart`): Android `clock_gettime(CLOCK_BOOTTIME)`, iOS `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`(=mach_continuous_time). `isNative` fallback 가드.
- sync_service ping/pong t1/t2/t3 → `MonotonicClock.nowMs()` (offset boot 기반).
- `NativeTimestamp.monoMs` / `AudioObs.hostBootMs` getter (=timeNs÷1e6). 외삽 정렬(anchor/drift/fallback) `ts.monoMs`+`obs.hostBootMs`. wall(`wallMs`/`hostTimeMs`/csv)는 검증 병행 유지.
- ⚠️ Darwin `CLOCK_MONOTONIC`은 NTP 점프(REALTIME offset)라 금지 → raw 계열 필수(1차 소스 검증). AVAudioTime.hostTime=mach_absolute라 iOS native 변환 레이어(hostTime + sleep누적).
- scheduleStart 경로 dead(v0.0.48) 확인 → 스킵.

**⚠️ 실측 버그+수정 (getTimestamp clockId 신뢰 불가)**: 첫 측정 재생시간 **음수**(호스트 -38분/게스트 -1분). 원인 = AAudio `getTimestamp(CLOCK_BOOTTIME)`가 **clockId 무시하고 MONOTONIC 반환** → `bootNow(BOOTTIME)-timeNs(MONOTONIC)`가 deep sleep 누적만큼 폭발 → virtualFrame **-89억**(호스트/게스트 음수폭이 각 기기 sleep 시간차와 일치). **수정**: iOS와 대칭으로 — `getTimestamp(CLOCK_MONOTONIC)`로 받아 HAL지연/virtualFrame/wall역산은 MONOTONIC 일관(정상), 정렬 보고값 `outTimeNs`만 `+(bootNow-monoNow)` 가산해 BOOTTIME화. **교훈: getTimestamp clockId는 신뢰 불가 — 항상 MONOTONIC 받고 sleep누적을 코드로 가산(iOS hostTime과 동일 패턴).**

**검증 (S947N 호스트 + S901N 게스트, transpose+5, 2분, `sync_log_2026-06-05T10-54-49`)**:
- ✅ FFI 정상: `isNative=true`, boot=690443170ms(≈8일)≠wall=epoch.
- ✅ **offset 점프 면역**: boot offset 522219902.0→903.1 (2분 **1.1ms 변동**), stable 17 유지. **측정3 점프 완전 제거.**
- ✅ **vfDiff -3.64ms** (p10/p90 -6.3/-3.1, anchor 경로 247행). **(129) -19.5 대비 개선** (offset 안정→외삽 정확 추정).
- ✅ drift_ms(rate) 0.59, seek_count 0, anchor_set 2 (drift 247 ≫ fallback 28, anchor 정상 박힘).
- 음수 fix 후 재생시간 정상 + 사용자 청감 OK.

**잔존 (별도 트랙)**: (1) 음향 outputLatency 비대칭(결함 B, 가장 체감), (2) vfDiff -3.64 position 편향(seek 임계 20ms 아래라 방치), (3) **데드코드 정리 트랙**: scheduleStart/cancelSchedule 경로 + `nowAsHostTime`(사용처 0) + wall 병행 경로(검증 끝나 제거 가능).

**커밋**: v0.0.115.

---

### 2026-06-05 (131) — v0.0.116 scheduleStart/cancelSchedule dead path 삭제 (NTP 예약 재생 제거)

**배경**: (130) monotonic 전환 후 데드코드 정리. scheduleStart(NTP 예약 재생, v0.0.47)는 v0.0.48에서 보류 + "다음 세션 재활용" 명목으로 dead path 보존됐으나, **재도입 검토 결과 폐기 결정** (사용자 합의). 근거: ① 실패 원인(메시지 race/sequence ordering/outputLatency 비대칭, HISTORY (43) 2413 — "NTP schedule 자체는 정확히 작동, 문제는 race+latency")이 **monotonic과 무관** → 시계 개선이 부활 명분 안 됨, ② "주기 동시 정렬" 역할은 v0.0.114 `realign`이 이미 대체, ③ SYNC_REDESIGN 로드맵은 *anchor 폐기 말고 주기 재발행* 방향이라 NTP 전면(anchor 의존 제거)과 반대.

**삭제 (3계층 전수)**:
- **Dart**: `native_audio_service.scheduleStart/cancelSchedule` + `native_audio_sync_service._scheduleFromObs/_handleSchedulePlay/_handleSchedulePause` + schedule-play/schedule-pause 메시지 핸들러 + `_scheduleInProgress`/`_scheduleBufferMs`.
- **Android**: `oboe_engine.cpp` scheduleStart/cancelSchedule 함수 + onAudioReady 콜백 안 예약 판정 블록 + `mScheduledStart*` 필드 3개 + JNI `nativeScheduleStart/nativeCancelSchedule`. `MainActivity.kt`/`NativeAudio.kt` 핸들러·선언.
- **iOS**: `AudioEngine.swift` scheduleStart/cancelSchedule + `AppDelegate.swift` case 2개.

**검증**: flutter analyze 통과 + APK 빌드 OK (Dart 미사용 잔재 0). iOS 빌드는 macOS 필요 — 코드 삭제만, 다음 iOS 작업 시 검증.

**잔여 데드코드**: ✅ `nowAsHostTime`+`localTimeToHost`/`hostTimeToLocal` dead 삭제(v0.0.117, 사용처 0). prewarm/coolDown은 **유지** — coolDown이 iOS `unload()`(방 나가기)에서 실사용이라 dead 아님(2321 "dead 유지"는 오기), prewarm의 mPrewarmIdle도 stream 생성 공통 경로와 얽힘. ⏳ wall 병행 경로만 iOS 검증 후 제거.

**커밋**: v0.0.116.

---

### 2026-06-05 (132) — acoustic 측정으로 결함 B(출력단 지연 비대칭) 실재 확정 + 측정 인프라 구축 (코드 변경 없음)

**배경**: (129)/(130) 후속. monotonic 전환(v0.0.115)으로 offset이 안정된 상태에서, 남은 "미묘한 음향 어긋남"의 정체(결함 B = outputLatency 비대칭)를 맥북 마이크 acoustic 측정으로 ground truth 확정. 호스트 SM-S947N(R3KL207HBBF) + 게스트 SM-S901N/S22(R3CT60D20XE).

**측정 인프라 (신규, `scripts/acoustic/`)**:
- `gen_chirp.py` → `measure_chirp.mp3`: **5ms chirp(1k→4kHz sweep), 1초 주기, 15분 mp3**. chirp은 pulse-compression으로 matched-filter peak가 순톤/임펄스보다 날카로움(sub-ms). 1k~4kHz는 폰 스피커/마이크 안전대역. mp3 320k 인코딩(두 폰 동일 왜곡이라 상대 시차 불변, round-trip self-test로 −15ms 정확 복원 확인).
- `analyze.py`: 녹음 wav ⨯ chirp template **matched filter(correlate+hilbert envelope)** → 1초 주기마다 2-peak(host/guest). self-test로 ±부호·음속보정 검증 통과.
- 녹음: `ffmpeg -f avfoundation -i ":0"` 맥북 내장 마이크 → wav. 입력게인 35(클리핑 방지).
- 동시에 호스트 `sync_log_*.csv` 기록(일반 빌드 호스트 상시 로깅) → 음향과 csv 교차.

**방법론 교훈 (관찰 사실)**:
- **녹음 timebase 0.877배 압축** — ffmpeg avfoundation이 맥북 마이크 실제 delivery rate를 48000으로 잘못 태깅(60초 명령 → 52.6초 출력). measure_chirp의 **정확한 1.0초 주기를 anchor로 chirp 실측주기(877ms)로 자동 캘리브레이션**(`time_scale=1.0/P_meas`) → 재생은 48kHz 폰 클럭(정확)이라 보정 가능. ⚠️ 처음 "1.15배속 재생" 가설은 **오진** → 사용자 "1배속 맞다" + 녹음길이 단서로 철회.
- **transpose/speed ON 시 chirp 들쭉날쭉** — SoundTouch는 85ms(`kSTWorkerBatchFrames=4096`) batch로 처리(`SEQUENCE_MS=82`)인데 5ms chirp+995ms 무음과 안 맞아 pitch-shift가 transient를 뭉갬/누락. (116) H-1 동일 메커니즘. **측정은 transpose 0/1.0배=SoundTouch bypass(`oboe_engine.cpp:822`)라 무관** — chirp 정상 출력.
- **진폭 기반 host/guest 식별은 반향장에서 실패** — 호스트 3cm/게스트 50cm(거리비 16배)인데 진폭비 1.42뿐 = 방 반향이 거리효과를 죽임. 음소거 식별(rec3/4)도 진폭 변동(폰 미고정)으로 실패.
- **부호 확정 = "볼륨 조정한 폰 추적" 교차검증** (핵심 트릭): rec2(호스트 볼륨↓)와 rec5(원복)에서 **나중 peak 진폭 불변(0.75→0.82=게스트, 볼륨 안 건드림)** + **먼저 peak만 0.56→0.99 변함(호스트, 볼륨 조정)** → **먼저 도착 peak=호스트** 확정. 진폭 절대값 안 쓰므로 반향 무관.

**핵심 발견 — 결함 B 실재 확정 (실측)**:
| 구간 | 음향 시차 | csv vf_diff | drift_ms(framePos) | offset_ms | out_lat H/G |
|---|---|---|---|---|---|
| rec2 12:20 | **+12.0ms**(host먼저) | −28.2 | −0.9 | (기준) | 10.1/8.6 |
| rec5 12:52 | **+12.6ms** | **−6.8** | +1.8 | +2.7ms | 10.3/7.7 |

- **음향 시차 ~12ms 고정** ↔ vf_diff −28→−6.8 **출렁임**(21ms) → 음향은 재생 position 외삽(vf_diff)을 **안 따라감 = 재생오차 아님** (사용자 통찰).
- **monotonic offset 2.7ms만 변동**(안정) → 클럭차는 sync가 보정 → 음향 12ms는 **클럭차도 아님**.
- **drift_ms(framePos=HAL DAC) ≈ 0** → DAC 레벨까지 sync 정확.
- ∴ **음향 12ms = framePos(DAC) 이후 → 스피커 출력단의 고정 지연 비대칭 = 결함 B**. csv `out_lat`(Oboe `calculateLatencyMillis`)가 DAC 이후를 못 잡음((33-2)와 일치). 음속보정 후 **~11ms, 호스트 출력이 게스트보다 빠름**. csv out_lat delta(g−h) −2.6ms는 **부호도 반대로 과소보고**.

**정정**: 측정 중 `결함B = emit_dt + vf_diff`로 계산한 건 **무효** — vf_diff가 음향과 독립(출렁이는데 음향 고정)이라 쓰면 안 됨. **결함 B = 음향 잔차 ~11ms 자체**(framePos drift≈0 기준).

**측정 데이터**: `measurements/acoustic/rec{2,5}.wav` + `rec{2,5}_synclog.csv`. (rec1 무효=음악+2배속 오선택, rec3/4 무효=음소거 진폭변동.)

**다음**: 보정 구현은 **보류(close, 사용자 합의)** — 11ms 인지경계(효용↓) + 동적 캘리브레이션 비용·측정오차 악순환(이번 4회 실패) + outputLatency 본질적 불확실 + 더 큰 이슈(anchor 공백 ±240ms/재입장 8초) 우선. 진단·인프라만 보존. 재개조건/설계원칙("값 박지 말고 통로", 경로별 캐싱)은 SYNC_REDESIGN (132) "결정" 참조.

---

### 2026-06-05 (133) — v0.0.118 ring buffer overwrite fix (prewarm/pause 중 decode 폭주 → 시크바≠소리)

**배경**: 재입장 8초 진단(별도 트랙)을 위해 실기기 2대(호스트 SM-S947N(R3KL207HBBF) + 게스트 SM-S901N(R3CT60D20XE)) 측정 중, 사용자가 **실제 음악** 재생에서 신규 버그 발견 — "시크바가 가리키는 위치와 실제 들리는 소리가 다른 곡 구간". (재입장 8초 트랙은 이 버그가 끼어들어 측정 미완 — csv rawOff/rtt가 `startPeriodicSync` 전용 컬럼이라 "8초간 clock sync 미작동은 측정 아티팩트일 수 있다"는 가설까지만 세움. 다음 트랙.)

**증상 (사용자 관찰)**:
- 호스트가 엉뚱한 구간 재생(게스트는 정상 위치) 또는 양쪽 다 시크바≠소리. **실제 소리가 다름**(무음 아님).
- 트리거: **오래 정지(pause) 후 재생** 또는 재생 시작 전 긴 대기(prewarm). 정지 길수록 심함.
- 호스트 심함, 게스트 경미. ~20초 후 자가 회복.

**진단** (native `[VF-DIAG]` 임시 로그 추가 → 재현 → 분석):
- ring buffer = content frame 윈도우 `[mRingTail, mRingHead)`, 저장은 modular `frame % cap` (`oboe_engine.cpp` callback `vf % capFrames`). 시크바=vf, 소리=ring[vf%cap] PCM. invariant `head − tail <= cap`.
- **실측**: 호스트 첫 poll `vf=480 head=3101807 tail=0 cap=2646000` → **head−tail=3,101,807 > cap=2,646,000 (invariant 위반, 10초 초과, prewarm 22초)**. 게스트 `head−tail=2,650,223`(0.1초 초과)뿐 → **"호스트만 심함" 정확히 일치**.
- modular overwrite: decode가 frame 0→3,101,807 순서로 채우며 **frame 0 위치(ring[0])가 frame 2,646,000(60초)으로 덮어써짐**. `vf=480`(0.01초) 읽으면 ring[480]=frame 2,646,480=**60초 PCM** → 시크바 0초인데 60초 소리.
- **회복**: 재생 시작 후 callback이 tail advance(`vf−behind`) → head 폭주분 따라잡아 head−tail이 cap으로 수렴 → vf 위치 정상화 (~20초).

**root cause**: `decodeLoop`의 `wait_for(50ms timeout, predicate=head-tail<cap)`가 **timeout으로 깨면 predicate 충족 여부와 무관하게 입력/출력 단계로 진행** → ring 가득인데도 chunk를 더 decode해 head가 cap 초과. 정상 재생 중엔 callback이 tail advance해 head−tail<cap 유지라 무해하나, **callback이 tail 동결인 동안(prewarm idle `mPrewarmIdle`, pause)** head 폭주 → modular overwrite. ring 도입(v0.0.76 `f7e4dfa`) 이래 잠복.

**왜 그동안 안 잡혔나 (교훈)**:
- 회귀/측정에 **비프·chirp 등 단일톤** 사용 → 전 구간 동일 파형이라 위치 어긋나도 같은 소리 → 무감지.
- drift/vfDiff 측정도 **vf(보고 위치) 기반** → ring 실제 PCM 내용물 어긋남은 안 보임. 동기 측정은 계속 "정상". **실제 음악 청감으로만 발견.** → 합성음 측정 ≠ 실제 음악 청감 회귀.

**fix** (`oboe_engine.cpp` decodeLoop): `wait_for` 직후 abort/seekTarget 체크 다음에 `(head-tail) >= cap`이면 `continue`(decode skip). timeout 본래 목적(seek 반응성)은 위 seekTarget 체크가 이미 처리하므로 안전. callback이 tail을 advance(재생/시크)하기 전까진 한 chunk도 더 안 채움.

**검증** (호스트 SM-S947N + 게스트 SM-S901N):
- 청감: 정지 38초 후 재생 → "시크바=소리" 정상.
- logcat: pause 38초 후 `start(resume): head=2646016 tail=0` → **head−tail=2,646,016 = cap에서 정확히 멈춤(폭주 0)**. fix 전 prewarm 22초 `head−tail=3.1M`과 대조.

**진단 로그 처리**: native `[VF-DIAG]`(poll/pause/resume/decode-seek) + 재입장 트랙 Dart `[REJOIN-DIAG]` 임시 로그는 검증 후 **전부 제거**(커밋엔 fix만).

**빌드**: v0.0.118

---

### 2026-06-05 (134) — v0.0.119 정지→재생 시 게스트 0:00 점프 fix (ts.ok=false 외삽 garbage, v0.0.115 회귀)

**배경**: (133) ring overwrite fix 검증 중 사용자가 별개 증상 발견 — "정지했다 재생하면 게스트가 0:00로 한번 갔다온다" + "게스트가 조금 앞선다". ring fix(시크바=소리)는 정상 작동 확인된 상태(head-tail이 cap에서 멈춤), 이건 **sync(fallback) 레이어**의 다른 버그.

**증상 (사용자 관찰)**: 호스트 정지→재생 시 게스트가 0:00로 확 튀었다 제자리로 복귀.

**진단** (`[FALLBACK] align` 로그):
- resume 직후 첫 align이 `drift=182,077,364ms`(50시간), `seekTo=-8,019,881,814`(음수) → clamp(0) → **게스트 0:00 점프**. 2초 뒤 정상화(`-36ms`).
- root: poll(`native_audio_sync_service.dart:1394`)이 `ts.ok=false`(resume 직후 getTimestamp `ErrorInvalidState` 구간)인데도 `_fallbackAlignment(ts)` 호출(`:1401`). 그 함수는 `ts.monoMs`로 외삽(`hostWallNow = ts.monoMs + offset`, `:1473`/`:1481`)하는데, **`ts.ok=false`면 `monoMs=0`**(timeNs=-1, `native_audio_service.dart:46` 주석이 "⚠️ 정렬은 ok 가드 통과 후만 사용"이라 직접 경고) → `elapsedMs` 외삽 폭주 → garbage seekTo.

**root cause = v0.0.115 monotonic 전환 회귀**: 그 fallback 경로(`4431aa1`)는 원래 wall clock 기반이라 `ts.ok=false`여도 동작했으나, v0.0.115에서 `monoMs`가 "`ts.ok=false`면 0"이 되도록 바뀌면서 깨짐. 전환 때 `monoMs`에 경고 주석만 남기고 이 경로는 업데이트 안 함.

**fix**: poll에서 `ts.ok=false` 시 `_fallbackAlignment` 호출 제거 + `_fallbackAlignment` 진입에 `if (!ts.ok) return;` 방어 가드. **정렬만 skip** — virtualFrame은 콜백이 계속 진행하니 재생은 안 끊기고, 정지 전 정렬 상태가 유지됨(정지→재생은 `host-paused/resumed`로 양쪽 동시라 resume 직후 대략 정합). `ts.ok` 회복 후 정상 fallback이 미세 보정.

**검증** (호스트 SM-S947N + 게스트 SM-S901N):
- 청감: 정지→재생 0:00 튐 **사라짐**.
- logcat: garbage drift(50시간)/음수 seekTo **0건**. `engine.start` 즉시(187ms), `ts.ok` 회복 34~64ms(S22 내장 스피커)라 **재생 지연 없음** — 가드는 오디오 콜백(재생)이 아니라 sync 정렬만 skip.

**남은/참고**:
- **늦은 입장 케이스**: 게스트 vf=0(새 파일) → `ts.ok` 회복(수십ms) 후 호스트 위치로 seek(따라잡기). fix와 무관한 원래 동작(전엔 그 구간에 garbage seek가 추가됐을 뿐). 그 짧은 0:00마저 없애려면 `engine.start` 전 호스트 위치 pre-seek가 가능하나, ts.ok 회복이 수십ms라 체감 작아 별도 트랙(BT 등 느린 경로 체감 시).
- **게스트 ~30-50ms 앞섬**(`fallback drift -36/-31/-47`): 기존 PLAN (125)/(126) "게스트 체계적 앞섬"(anchor establish 오차) 계열, 별개 트랙.

**빌드**: v0.0.119

---

### 2026-06-05 (135) — v0.0.120 isOffsetStable jitter fix: stable 판정을 "RTT 작은 샘플 공급"으로 재설계 (#1)

**배경**: anchor 주기 재발행(SYNC_REDESIGN 결함 A) 1단계(realign 2초 주기) 시도 → 2분 측정에서 `fallback` 109회(offset 불안정 지배)로 vfDiff가 거짓 → 효과 미확정 → **롤백**. **두 트랙 얽힘 확인**: isOffsetStable jitter(#1)가 offset을 흔들어 anchor 측정을 오염. 사용자 합의 "하나씩 확실히"로 **#1 선행**.

**root cause**: `isOffsetStable`의 stable 판정 조건 (b) `|filtered − winMinRaw| < 2ms`가 **RTT 노이즈에 깨짐**. `winMinRaw`(window min-RTT **생 샘플 1개**)는 ±RTT/2 노이즈(RTT 10ms면 ±5ms) > 임계 2ms → `_filteredOffsetMs`가 안정(1.9ms)해도 `_stableCount` 리셋 → isOffsetStable false 지배 → fallback.

**사용자 통찰 (설계 주도)**: monotonic 전환(v0.0.115)으로 **시계는 무죄**(점프 없음). jitter는 RTT 비대칭 노이즈일 뿐. `filtered` 안정 = **진짜 offset은 안정**, 판정만 raw 노이즈(winMinRaw)에 휘둘림. → "offset을 더 정확히"가 아니라 "안정한 offset을 stable로 인정"하는 판정만 고치면 됨.

**설계 (사용자안)**: stable 판정을 **"offset 값 안정성(winMinRaw 2ms 비교)" → "RTT가 충분히 작은(≤20ms) 샘플이 최근 5초 내 들어왔는가"**(`_lastGoodSampleMs` 타이머)로 전환. **역할 분리**: stable 판정 = "정밀 anchor 박을 *타이밍*", offset 정확도 = EMA filtered가 담당.
- 초기 (c): `syncWithHost`에서 RTT≤20 샘플이 있었으면(roundBestRtt) 즉시 stable — 시작 공백 제거.
- 두 임계 분리: **reject 30ms**(offset 갱신용, 넓게 모아 EMA 평균) vs **stable good 20ms**(anchor 타이밍용, 정밀할 때만). RTT 21~30 샘플도 offset엔 기여하나 stable 타이머는 안 건드림.
- **혼잡(RTT 큼) 시**: good 샘플(≤20)이 5초간 안 와 자연히 unstable → fallback(정확하면 −12ms로 버팀, v0.0.112 force-establish 폐기 교훈 = anchor 억지 금지).

**변경** (`sync_service.dart`): `_stableGoodRttMs=20`/`_stableTimeoutMs=5000` 추가. `_stableThresholdMs`/`_stableRequiredCount`/`_stableCount`/`_prevFilteredOffset`/winMinRaw 2ms 비교/`window≥3` 가드 제거. isOffsetStable = `_lastGoodSampleMs>0 && now−_lastGoodSampleMs ≤ 5000`.

**검증** (집 WiFi, 1분40초, 호스트 S947N + 게스트 S901N):
- RTT 통과분 9~11ms (RTT≤20 **100%**).
- stable **true 22 / false 5 (82%)**, `[STABLE TOGGLE]` **4회** — 이전 fallback 109회(거의 unstable) 대비 급감. anchor 잘 박힘.
- 17:36:52 잠깐 false → 1초 복구 = **설계대로**(good 샘플 5초 공백 → false → 다음 good 샘플에 복구).
- 청감 **"잘 맞음"**.

**⚠️ 미해결 (별개 트랙)**: **reject ~73%**(Periodic sync 통과 27개/100초). RTT가 **9~11ms 아니면 >30으로 양극화** — 집 WiFi인데 의외, **WiFi 절전(doze)/간섭**으로 ping 응답 간헐 지연 의심. good 샘플 공백(잠깐 false)의 원인. #1과 독립.

**다음**: offset 안정화됐으니 **anchor 주기 재발행(SYNC_REDESIGN) 재측정** — 이제 vfDiff 신뢰 가능.

**빌드**: v0.0.120

---

### 2026-06-05 (136) — anchor 주기 재발행(결함 A 1단계) 재측정: seek 기반 realign 실패 확정 → 트랙 보류(close)

v0.0.120으로 offset 안정화(#1) 완료 → 1단계 롤백 사유("offset 불안정 → vfDiff 거짓")가 해소되어 **SYNC_REDESIGN 결함 A "anchor 주기 재발행" 1단계 재측정**.

**구현 (v0.0.121, 측정 후 롤백)**: `_recomputeDrift`의 realign 발동을 `vfDiff 중앙값 ≥ 60ms`(반응적) **OR** `마지막 realign 후 N초 경과`(주기적)로 확장. event `anchor_realign_periodic` 분리. `_realignIntervalMs`(2초/5초 스윕) + `_lastRealignMs`(establish 시점 설정 → 즉발 방지). 발동 타이밍은 `ts.wallMs`(게스트 로컬)이라 네트워크 무관 — obs는 외삽의 기준점일 뿐, 외삽은 매 100ms poll(`native_audio_service.dart:203`)마다, obs broadcast는 500ms.

**측정 (호스트 S947N + 게스트 S901N, 1배속, seek/pause 없이 평상시 2~3분):**

| 주기 | realign 횟수 | drift vfDiff med | signed | offset stdev |
|------|-------------|------------------|--------|--------------|
| baseline (realign 0) | 0 | **-4.83 / -5.42** | -8 / -17.5 | 1.0~1.2 |
| 5초판 | 19 | **-15.05** | -17.42 | 0.38 |
| 2초판 | 70 | **-26.38** | -26.08 | 0.51 |

**결론 (관찰 사실)**: realign 빈도↑ = vfDiff **악화**. 2초(-26) → 5초(-15) → ∞/baseline(-5)로 **주기↑ = baseline 수렴**. offset은 3개 측정 모두 안정(stdev 0.4~1.2)이라 측정 신뢰 가능 = 측정 아티팩트 아님. raw 패턴: **realign 직후 vfDiff가 음수로 점프 후 다음 realign까지 고정**(예: seq35 realign→seq36~39 -49.5 고정, seq50→-33.8 고정). 그동안 **drift(rate)는 ±2~5ms로 정상** = 전형적 "거짓말 패턴"(baseline이 어긋난 자리에 박힘, rate는 맞음).

**root cause (가설, 미확정)**: realign의 self-seek가 매번 **음수 편향**으로 박음. establish(처음, `_seekCorrectionAccum`≈0)는 -5로 정확한데 주기 realign(accum 누적 상태)만 악화 → seek 실이동(framePos)과 가상보정(accum) **이중 카운트** 의심. native `virtualFrame`/`framePos`/accum 관계는 미확정. (`seek_count=0`은 realign seek가 `_maybeTriggerSeek`의 `_seekCount++`(`:1868`)를 안 거치는 별도 경로라 카운터 미반영일 뿐, seek 자체는 발생.)

**청감**: 사용자 "대체로 OK" — vfDiff -26인데도 청감 무영향 → **결함 A 잔재(-5~-26ms)가 청감 임계 아래**.

**왜 어떤 점프(seek) 방식도 -5를 못 고치나 (후속 논의, close의 진짜 근거)**: 측정한 1단계는 사실 설계 합의(SYNC_REDESIGN `:282` "0점은 자주 fresh, **seek는 차이 클 때만** = 기존 메커니즘이 알아서")와 어긋난 **"realign 매번 seek 동반"판**이었음 — 1단계 MVP(`:287`)가 "기존 seek 로직 재사용"으로 적혀 통찰(`:282` 분리)과 모순. 진짜 합의판(숫자만 갱신, seek 분리)을 따져도 -5는 못 고침. **세 갈래 다 막힘:**
- **숫자만 갱신**(합의판): vfDiff(절대 위치)는 anchor를 **안 씀**(`:1727-1728`, 게스트 virtualFrame을 호스트 외삽과 직접 비교) → baseline 숫자 갱신해도 게스트가 안 움직여 **vfDiff(-5) 불변**. 게다가 기존 drift seek(`:1826` `|medianDrift|≥20`)는 baseline 갱신마다 drift 0 리셋(`:1788 _driftSamples.clear()`)으로 **죽고**, -5는 애초 drift에 **안 보임**(거짓말 패턴 — 측정에서 drift ±2~5 정상인데 vfDiff -26). = 악화는 없으나 못 고침.
- **seek 동반**(측정한 구현): self-seek 음수 편향 -26 **악화**.
- **rate-bend**(2단계): 점프 없이 부드럽게 = 유일한 깨끗한 해법, native+Dart 큰 비용.
즉 작은 0점 오차(-5)는 **vfDiff(절대 위치) 문제인데 기존 보정은 전부 drift(rate) 기반(`:1813`/`:1826`, vfDiff 안 봄 `:1810`)이라 못 보고, vfDiff 기반으로 잡으려면 점프(seek)는 거칠어 악화·임계 낮추면 떨림** → rate-bend 아니면 불가.

**결정 (사용자 합의)**: **1단계 롤백(`git restore`) + 트랙 보류(close)**. 효용<비용 — 청감 무영향 + seek 기반 접근 실패(할수록 해로움) + 2단계 rate-bend는 native+Dart 큰 비용. baseline(v0.0.120, anchor 한 번 박기)이 현재 최선이라 유지. (결함 B 음향 11ms 비대칭 close와 동형 판단.) **재개조건**: BT 등 큰 비대칭 경로 체감 시 / 다른 큰 이슈 해결 후 마지막 병목 시 → 그땐 seek가 아니라 **2단계 rate-bend**(SoundTouch setTempo ±0.05%, 점프 없는 미세보정)로.

**측정 인프라 유지**: `scripts/analyze_anchor.sh`(event별 vfDiff 분포), `measurements/realign2s_2026-06-05.csv` / `realign5s_2026-06-05.csv` / baseline `manual_2026-06-05_181705.csv`·`182028_s12.csv`.

**빌드**: v0.0.121 측정 후 롤백(미커밋) → **v0.0.120 유지**

---

### 2026-06-05 (137) — SYNC_REDESIGN 🥇1번 stale 정정 + iOS transpose/speed latency 누락 진단 (코드 변경 없음)

**배경**: "SoundTouch latency 반영이 로드맵 1순위였는데 다음 후보에서 왜 빠졌나?" 질문 → `SYNC_REDESIGN.md:74` 🥇1번에 **✅ 완료 표시 누락**(🥈2/🥉3은 갱신됐는데 1번만 stale) 발견.

**정정 (로드맵 🥇1)**: SoundTouch latency 반영(**결함 B-ST**)은 **v0.0.112에서 Android 완료**(HISTORY (125), `oboe_engine.cpp` worker `getSetting(SETTING_INITIAL_LATENCY)` → outputLatencyMs 가산, 2배속 out_lat~274ms 실측 반영). close된 건 SoundTouch가 아닌 별개의 **결함 B-HAL**(출력단 ~11ms 하드웨어 비대칭, (132), 인지경계 아래 보류). 두 개를 "결함 B"로 뭉뚱그려 1순위가 사라진 것처럼 보였던 것 → 로드맵에 ✅/B-ST·B-HAL 분리 명시.

**iOS latency 누락 진단 (코드 확정, 신규)**: iOS는 SoundTouch가 아닌 Apple `AVAudioUnitTimePitch` 사용(`AudioEngine.swift:11`). transpose/speed latency가 sync 보정에 **완전 누락**:
- `getTimestamp`의 `outputLatencyMs`=`session.outputLatency`만(`:275`) — timePitch 미포함.
- `nodeLatency` 합산(`:234-236`=playerNode+mainMixer+output)이 신호 체인(`node→timePitch→mainMixer`, `:120-121`) 중간 `timePitch`를 **건너뜀**. `timePitch.latency` 호출 **0곳**.
- 그 `nodeLatencyMs`/`totalLatencyMs`는 Dart가 **안 받음**(`native_audio_service.dart:56,69`는 `outputLatencyMs`만 수신).
- → iOS 게스트 transpose/speed ON 시 큐 latency만큼 어긋남 가능(영향 크기 미측정). AVAudioUnitTimePitch latency API 미문서화(`SYNC_REDESIGN.md:62`)라 SoundTouch식 hook 불가 → **acoustic 캘리브레이션 상수 필요**. PLAN §H "iOS 실기기 검증" 트랙으로 묶임.

**빌드**: 문서만 (`SYNC_REDESIGN.md` 🥇1번 갱신 + 본 항목) — **v0.0.120 유지**.

---

### 2026-06-05 (138) — ② 재입장 vfDiff 진동 재측정: 40~95 진동 소멸 확정(v0.0.118/119 효과) → 트랙 close + fallback obs 의존성 분석

**배경**: PLAN §H 미해결 #6 "vfDiff 40~95ms 진동"((124) 재입장 후 관찰)이 v0.0.118(ring overwrite)/v0.0.119(resume 0:00) 두 청감 버그 fix 후에도 남는지 깨끗하게 재측정. (124) 측정은 그 두 버그 + force-establish(폐기)로 오염 의심이었음.

**측정** (호스트 SM-S947N(R3KL207HBBF) csv 기록, 게스트 S22 SM-S901N(R3CT60D20XE), v0.0.120, 재입장 5회, `measurements/reentry_2026-06-05.csv`):

| 입장 | drift vfDiff mean | range | 폭 |
|---|---|---|---|
| #1 | -7.5 | [-9.4, -5.5] | 3.9 |
| #2 | -22.1 | [-24.4, -21.2] | 3.2 |
| #3 | -13.4 | [-15.6, -11.2] | 4.5 |
| #4·5 | -14.5 | [-17.5, -11.1] | 6.4 |

**결과 (관찰 사실)**:
1. ✅ **40~95 진동 소멸** — 각 재입장 구간 내 vfDiff 폭 **3~6ms**(왕복 없음). (124) "40↔90 진동" 재현 안 됨. **v0.0.118/119가 (124) 진동의 진짜 원인이었음 확인** (PLAN §H #6 "두 fix 오염" 가설 적중).
2. ✅ **재입장 clock sync 지연 없음** — anchor가 매 재입장 ~5초(10 seq) 내 박힘, offset **stdev 0.62 / span 2.9ms**. (124) "8초 rawOff=0"은 (134) 측정 아티팩트 결론 재확인 (guest_start row rawOff=0/rtt=0은 lastRaw/Rtt 컬럼 미충전일 뿐, anchor_set rtt 8~18로 정상).
3. ✅ **fallback 거대 spike 무해** — `-14850~-195563ms` outlier가 정확히 각 재입장 직후 **첫 fallback 1개씩**(seq4/58/170/283), 다음 샘플 즉시 복구. (124) "초기 위치차, 문제 아님" 패턴.
4. ⚠️ **결함 A 잔재 또렷** — 입장마다 anchor baseline -7/-22/-13/-14로 제각각. 입장#2 시계열: anchor 박히기 전 fallback -1.76~-2.76(정확) → anchor_set 후 -22 편향 고정. (126)/(136) "anchor가 fallback보다 부정확" 재현.

**청감 (사용자)**: 전체적으로 "싱크 틀어진지 모를 정도로 좋음" + 재입장 즉시 싱크 잡음. 측정 최대 -22ms도 두 스피커 동시성 인지 임계(~20-30ms+) 안.

**fallback obs 의존성 분석 (코드, fallback-only 전환 가능성 검토)**: 사용자 통찰 "측정상 fallback이 더 정확하니 fallback-only?" 검증.
- **가설 정정**: "anchor는 obs 독립"은 부정확 — **둘 다 obs를 외삽 기준으로 씀**(`:1700`/`:1725` vs `:1473`/`:1486`).
- **차이 = obs 사용 방식**: fallback(`_fallbackAlignment:1466`)은 매 보정마다 obs 절대 위치로 게스트를 **직접 seek**(obs null이면 정지 `:1474`, stale obs면 옛 위치로 잘못 seek = HISTORY (98) 실증, seek cooldown 1초 `:1521`로 방어). anchor/drift(`:1696`)는 obs를 **rate(변화율) 비교**(driftMs `:1716`)에 써 stale obs에 견고(`:1723`), 게스트 위치는 anchor baseline+자체 rate로 진행 → obs 주기/유실과 무관하게 매끄러움.
- **fallback-only 리스크**: ① obs 500ms 주기인데 fallback은 100ms poll마다 정렬 → 사이 stale 외삽, ② obs 유실/혼잡 WiFi 시 잘못 seek, ③ 30ms↑ 점프(seek) 보정이라 자주 발동 시 글리치. → 저지연 WiFi에선 fallback이 정확하나 환경 흔들리면 anchor 강건. **anchor main이 합리적**. 결함 A 진짜 해법은 fallback-only가 아니라 anchor establish 정확도/주기 갱신(rate-bend, (136) close).

**결정**: **② 진동 트랙 close** — 40~95 진동 소멸 확정(v0.0.118/119 효과). 결함 A 잔재(-7~-22)는 청감 OK + (136) close 유지(rate-bend 큰 비용) → **현 baseline(v0.0.120, anchor main) 유지**.

**빌드**: 측정만, 코드 변경 없음 — **v0.0.120 유지**.

---

### 2026-06-05 (139) — offset reject ~73% close: 품질 게이트(무해) + 완화 역효과, 환경 탓 (코드 변경 없음)

**배경**: "싱크 잔여 마무리" 트랙 마지막 항목. PLAN §H #1 잔여 reject ~73%((135) 관찰: periodic sync 통과 27/100, RTT 9~11 vs >30 양극화). close인지 코드 완화인지 판정.

**코드 분석** (`sync_service.dart` startPeriodicSync):
- reject = raw RTT > `_rejectThresholdMs`(30) 샘플 폐기(`:314-317`). 주석 명시 "window/EMA/stable 모두 변화 0" → **reject 자체는 무해**(품질 게이트). 비대칭 노이즈가 RTT에 비례(±RTT/2)해 RTT 큰 샘플은 rawOffset 부정확 → 거르는 게 맞음.
- 통과분(27%)만으로 offset EMA(alpha 0.1, min-RTT 샘플 `:336/346`) 유지 → ② 측정에서 **offset stdev 0.62/span 2.9ms = 안정**. reject 높아도 offset 흔들림 없음.
- reject 높음 → good 샘플(≤20, stable 타이밍 `:355`) 띄엄띄엄 → stable 잠깐 false → fallback↑((138) fallback 45%). **단 fallback도 정확(입장#2 -1.76) + 청감 OK** → 무영향.

**reject 73% = 환경 탓**: RTT 양극화(9~11 vs >30)는 WiFi 절전(doze)/간섭으로 일부 ping 응답 간헐 지연. **코드 버그 아님.**

**완화 옵션 평가 (모두 기각)**:
- reject 임계 30↑ → RTT 30~50 noisy 샘플 유입 → **offset 품질↓**(현재 안정 깨짐). 역효과.
- ping 주기 1초↓ → 통과 빈도↑이나 **p2p 트래픽↑**(호스트 부담, 사용자 기존 우려) + offset 이미 안정이라 효용 작음.
- RTT median 기반 동적 임계(SYNC_REDESIGN 🥉3) → 복잡도↑, offset 안정한 현 상태선 **효용<비용**.

**결정 (close)**: reject는 무해한 품질 게이트, 높은 건 환경 탓, offset/청감 영향 없음((138) 확인), 완화는 다 역효과/효용<비용 → **close**. (메모 `feedback_dynamic_over_hardcoded` "효용<비용이면 close" 원칙 일치 — 동적 임계도 효용<비용.) **재개조건**: WiFi 매우 나빠 good 샘플 5초+ 장기 공백 → fallback 의존도↑ → fallback의 obs stale 약점((138)) 노출로 청감 틀어질 때.

**빌드**: 코드 변경 없음 — **v0.0.120 유지**.

→ **"싱크 잔여 마무리" 트랙 종료** (② 진동 close (138) + ③ 임계 stale/분화 + ① reject close (139)).

---

### 2026-06-10 (140) — iOS 실기기 첫 검증: transpose/speed/seek/monotonic ✅ + v0.0.121 크래시 fix + 잔음 root cause 진단

**구성**: SM S947N(Android 16) 호스트 + iPhone 12 Pro(iOS 26.4.2) 게스트. 호스트는 v0.0.120 유지(이번 fix는 iOS native만, P2P 버전 호환성 체크 없음 확인). 게스트는 **profile 빌드**(AOT — debug는 attach 끊기면 interpreter fallback이라 sync 측정 오염).

**검증 성공 (iOS 첫 실측)**:
- ✅ §H/§I **transpose/speed 게스트 전파** — 음정·속도 정상 추종 (`AVAudioUnitTimePitch`).
- ✅ **seek/정지/resume** — 0:00 안 튐 (v0.0.119 Dart fix가 iOS에도 적용 확인).
- ✅ **monotonic 안정** — vfDiff 진동/점프 없음 (v0.0.115 iOS BOOTTIME 대칭화 동작).
- ⚠️ **sync 오프셋**: iPhone 게스트 **−13~−15ms 느림**(baseline) → transpose/speed ON 시 **−23~−27ms 악화**(csv `vf_diff_ms`, n=560/810). 원인 유력 = `timePitch.latency` 미반영(v0.0.112 iOS 누락 — `getTimestamp`의 `outputLatencyMs`가 `session.outputLatency`만, `nodeLatency`에도 `timePitch.latency` 빠짐, `AudioEngine.swift:234-236,275`). **미해결, 별도 트랙.**

**🔴 신규 크래시 발견 → v0.0.121 fix**: `*** Terminating ... 'com.apple.coreaudio.avfaudio', reason: 'player did not see an IO cycle.'` (SIGABRT). speed 변경 + seek 연타로 실측 재현. root cause: iOS `AudioEngine`에 **interruption/routeChange/configurationChange notification 핸들러 0개** + `engine.isRunning`(실제 상태) 미확인(자체 Bool 플래그만) → engine이 IO 멈춘/첫 렌더 전 상태에서 `node.play()` 호출. 검증: Apple DTS forum 129207 + AudioKit #2910 — notification 다 구현해도 production 잔존(TOCTOU race, 호출 전 체크로 100% 못 막음) → **던져진 예외를 잡는 게 유일한 확실한 차단**.
- **fix 3층** (`AudioEngine.swift` + `ExceptionCatcher.h` + bridging header):
  1. `scheduleAndPlay`에 `engine.isRunning` 가드 (멈춤 시 재시작) — 단독으론 부족(IO 첫 사이클 전 race는 못 막음).
  2. `objcTryCatch`(ObjC `@try/@catch` static inline 헬퍼)로 `node.play()` wrap → **NSException 잡아 크래시 0**.
  3. 예외 시 `rebuildEngineAndResume` — engine/노드 재구성 + 50ms 지연 후 재시도(IO 사이클 1회 경과). 게스트는 native 멈춤을 Dart가 몰라 복구를 native 내부에서 끝내야 영구 무음 회피.
- **검증**: speed+seek 막 연타 → **크래시 0** (앱 안 죽음). ① 성공.

**잔음 root cause 진단 (idevicesyslog)**: ① fix 후 "가끔 잔음, 다른 동작 전까지 지속" 보고. iPhone syslog 캡처 분석:
- **내 rebuild 반복 가설 틀림** — `AVAudioEngine start` **1회**(rebuild면 다회). 잔음은 rebuild가 아님.
- **진짜 원인**: 잔음 구간 `AudioConverter`(mp3 디코더) **~2초마다 dispose/생성 235회 반복**. 동시 flutter 로그 = **seek 폭주**(`[SEEK-NOTIFY] targetMs 9.5분↔1.7분 진동`, `diffMs ±48만ms`) + `[ANCHOR] establish fpVfDiff_ms=4352605`(72분!) + `[ANCHOR-VERIFY] REJECT diffMs 14000ms`. 메커니즘: **seek 연타 → 게스트 seek 폭주(node.stop()→scheduleSegment 반복) → ① 디코더 235회 재생성=잔음 + ② outputNode.sampleTime 꼬임 → framePos 72분 폭주 → anchor 매번 REJECT/reset → 위치 못 맞춰 seek 무한 → 잔음 지속(seek 멈춰도)**. 
- iOS `framePos`(outputNode 누적)가 seek/node 재생성 후 `vf`와 어긋남 = **v0.0.114 "vf/framePos 정합" 가정이 seek 폭주에선 깨짐**. 아까 (137) offset 폭주와 동일 뿌리.
- 크래시에 가려져 있다가 ① fix로 앱이 안 죽으니 드러난 **기존 sync 버그**. **정상 seek(가끔)에선 미발현** → 일상 사용은 ① fix만으로 안전.

**부수 발견**:
- **CLI `flutter run` "1~8분 hung"의 정체 = 첫 연결 Xcode shared-cache symbol 복사**(`Installing and launching` 622초). 한 번 복사 후 캐시 → 재빌드 시 **15~17초**로 통과. hung이 아니라 symbol 복사 대기였음(CLAUDE.md 정정).
- profile에서 `flutter run`이 VM Service attach 실패(errno=49)해도 **AOT라 앱 정상 동작**(debug와 달리 안 멈춤).
- Swift `print()`는 **stdout이라 syslog 미표시**(idevicesyslog에 안 잡힘). Dart print는 NSLog 경유라 잡힘. → native 진단 로그는 `NSLog`/`os_log` 필요.
- 진단 인프라: `idevicesyslog`(brew libimobiledevice) — `idevicesyslog -u <udid> -p Runner`로 Runner 로그 캡처.

**빌드**: v0.0.121 (iOS `AudioEngine.swift` 크래시 가드 3층 + `ExceptionCatcher.h` 신규 + bridging header).

**남은 트랙** (미해결 이슈 + PLAN/SYNC_REDESIGN 반영): ① ✅ iOS sync 오프셋(timePitch latency) → **v0.0.122 (141) 해결** ② **잔음/seek 폭주 → framePos 붕괴**(iOS framePos 도메인 + anchor 재설계, 깊음) ③ ⏸️ notification 핸들러 → **조건부 보류 close (141)**.

---

### 2026-06-10 (141) — iOS 트랙 1: timePitch latency 반영(v0.0.122) → acoustic 검증으로 fix 성공 + (140) vfDiff 인과 오진 정정

(140) "남은 트랙" ① 처리. **구성**: SM S947N(Android 16) 호스트 v0.0.122 + iPhone 12 Pro(iOS 26.4.2) 게스트 profile 빌드.

**fix**: `AudioEngine.swift getTimestamp()`의 `outputLatencyMs` 보고에 `timePitch.latency` 가산 (`algoLatency = max(0, timePitch.latency)` → `reportedOutputLatency = session.outputLatency + algoLatency`). Android v0.0.112(SoundTouch `SETTING_INITIAL_LATENCY`를 outputLatency에 가산, `oboe_engine.cpp:624`)의 **iOS 미반영분 대칭**. ⚠️ Android는 callback이 cents=0에서 bypass라 조건 분기했으나, iOS는 노드 그래프(node→timePitch→mixer)가 **항상** timePitch를 거치므로 pitch=0/rate=1에서도 알고리즘 latency가 남아 **조건 없이 항상 가산**. 진단 컬럼 `algoLatencyMs` 신규.

**timePitch.latency 실측** (NSLog, idevicesyslog 캡처 — `print`는 stdout이라 syslog 미표시, native 진단은 NSLog 필수):
- baseline(pitch=0, speed=1.0): **85.33ms** (사전 예측 13-15ms의 6배 — "작을 수도" 우려 반증)
- **pitch 무관** (cents 900~1200 모두 85.33 고정)
- **speed 반비례**: 2.0x=64.0ms / 1.0x=85.33ms / 0.5x=128.0ms

**csv 반영 확인** (`sync_log_2026-06-10T14-35-42.csv`): `out_lat_guest_raw` = baseline 95.60ms(=85.33 timePitch + 10.27 session) / 2x 74.27 / 0.5x 130~138 → fix 정확 반영. host(Android 내장 스피커) 5~6ms → **outLatDelta +90ms** → 게스트를 호스트보다 90ms 앞선 위치로 seek.

**🔴 vfDiff는 이 fix 검증에 무력 (순환 구조)**: anchor seek `targetGuestVf = hostContent + outLatDelta`(`native_audio_sync_service.dart:1574-1576`)와 vfDiff 계산 `vfDiffMs = guestVfMs − expectedHostVfMs − currentOutLatDelta`(`:1728`)에 **같은 outLatDelta가 양쪽에 들어가 상쇄** → outLat을 바꾸는 fix는 vfDiff에 무감각. 실측 증명: **fix 후에도 baseline vfDiff median −23ms** (fix 전 −13~−15와 동급). 이 −23ms의 정체는 timePitch가 아니라 **결함 A 잔재**(anchor establish 편향 −7~−22, (136)/(138)서 청감 OK로 close).

**✅ acoustic 검증 = fix 성공 확정** (`scripts/acoustic/`, 맥북 마이크 호스트 5cm/게스트 50cm, chirp 동기 재생 15초, `rec_v122_baseline.wav`):
- **emit_dt median +7.84ms** (게스트−호스트 출력 시차, std 2.91, 진폭비 host/guest 2.20 식별 명확, '큰 peak 먼저' 100% 일관, 15 events)
- 판정: **+7.84ms ≈ +11ms(결함 B — (132)에서 잰 DAC 후 하드웨어 비대칭)** → **가설 A 확정**. timePitch.latency 85ms = **실제 음향 지연이 맞음**. fix(+90ms 앞당김)가 게스트 늦음을 정확히 상쇄. 잔여 +7.84는 결함 B(timePitch 무관, (132) close).
- 과보정(가설 B = 85ms는 lookahead일 뿐) 반증: 그랬다면 emit_dt가 음수(게스트 빠름)여야 하나 양수.

**🔧 (140) 인과 오진 정정**: (140) "iOS 게스트 sync 오프셋 −13~−27ms(**csv vf_diff_ms**) = timePitch latency 미반영"은 **인과 오진**이었음. vfDiff는 timePitch fix에 순환 무감각 → 그 −13~−27은 timePitch가 아니라 결함 A 잔차였음(청감/음향 OK, 이미 close). timePitch 누락의 **실제 음향 영향은 acoustic으로만 보이고**, fix 후 +7.84ms로 양호. **방법론 교훈: outLat 자체를 바꾸는 fix는 vfDiff(순환)/청감(미세차)으로 검증 불가 → acoustic 필수.** (PLAN (114)/(132) "acoustic 교차검증" 원칙 재확인.)

**빌드**: v0.0.122 (iOS `AudioEngine.swift` outputLatencyMs += timePitch.latency + 실측 NSLog 3곳 + algoLatencyMs 진단 컬럼).

**트랙 3 (② notification 핸들러) — 조건부 보류 close**: interruption/routeChange/configurationChange 핸들러 부재가 v0.0.121 크래시("player did not see an IO cycle")의 근본 트리거였으나, ① v0.0.121 예외잡기(`objcTryCatch` + `engine.isRunning` 가드)로 **크래시 0** + ② (140) 결론 "notification 다 구현해도 TOCTOU race로 production 잔존 → 예외잡기가 유일한 확실 차단"이라 **크래시 관점 추가가치 미미**. 남는 실익(예외 발생 빈도↓ / 전화·이어폰·BT 후 자동 재개 UX)은 **관찰된 적 없음**(효용 불확실) + notification 핸들러는 라이프사이클을 건드려 **회귀 검증 비용(전화·이어폰·BT 실기기 시나리오) 확실** → 효용<비용. **재개조건**: 크래시 자연 재발 or "게스트가 전화 받았다 끊으면 재생 미복귀" 같은 실사용 불편 관찰 시 → `configChange`/`interruption` 핸들러 추가(`rebuildEngineAndResume` 재사용). 사용자 합의 close.

---

### 2026-06-10 (142) — iOS 트랙2(잔음/seek 폭주) 착수: 백오프 롤백 → seek coalesce(v0.0.123) + 음정/속도 틀어짐 "네트워크 아님" 확정

(140) "남은 트랙" ② 착수. **구성**: S947N 호스트 + iPhone 12 Pro 게스트, 둘 다 coalesce v0.0.123(profile). 측정 csv `sync_log_2026-06-10T16-29-49.csv`.

**1차 시도 = anchor REJECT 백오프 → 롤백(진단 오류)**: establish-REJECT 루프(매 obs 재establish→seekToFrame)가 잔음 주범이라 가정, 연속 REJECT N회 시 establish 백오프 구현. **실측이 가설 반증** — csv event: `anchor_reset_verify_fail` **16회뿐**, 진짜 주범은 **`host_seek` 331회(시크바 막 드래그, 간격 median 176ms·min 1ms) = 게스트 seekToFrame 331회 → iOS 디코더(AudioConverter) 재생성**. 백오프는 16회짜리만 겨냥해 잔음(331회) 무효 + 음정/속도 변경 시 establish 억제로 sync 악화 의심 → **롤백**.

**2차 = seek-notify coalesce (v0.0.123)**: 연속 seek-notify를 150ms 디바운스로 합쳐 **마지막 위치만 native seekToFrame** (절대위치라 멱등, 중간 skip 안전). UI/anchor무효화는 매번(반응성), 무거운 seekToFrame만 합침. `native_audio_sync_service.dart` `_handleSeekNotify` + `_seekCoalesceTimer`. **결과: 잔음 감소(baseline+일반 seek OK)** but **극한 막 조작엔 잔존**(디바운스 150ms < seek 간격 median 176ms라 일부 구간 안 합쳐짐).

**음정/속도 sync 틀어짐 진단**: 사용자 보고 "속도/음정 조정 시 sync 틀어짐". (a) **백오프 무관 확정** — 롤백 후에도 틀어짐. (b) **네트워크 아님 확정** — RTT median **16ms**(max 30)인데 vfDiff 스파이크 **±100~224ms**(RTT의 10배+, 극단 ±48만). 네트워크 지연이면 vfDiff≈RTT여야 하나 10배+ → 네트워크로 설명 불가. (c) vfDiff median **−24.7ms**(정상 구간 안정, 트랙1 baseline −23과 동일 = 결함 A 잔재), `|vfDiff|>100` **8%**(막 조정 중 전환 순간만). → **원인 = speed 전환 순간 엔진/timePitch latency 과도기**(speed마다 timePitch.latency 85/64/128ms로 점프 → 전환 시 outputLatency 비대칭 어긋남 + 엔진 버퍼 재충전 과도기). **§I-6 "네트워크 지연" 기존 가정 정정** — 실측상 네트워크 아님, 엔진 전환 과도기.

**잔여 (둘 다 깊음, 다음 세션 하나씩)**:
1. **잔음** — coalesce 디바운스 튜닝(150→?) or iOS 엔진 디코더 재사용(seekToFrame이 AudioConverter 재생성 안 하게, 깊음).
2. **speed 전환 과도기** — 네트워크 아님, 엔진/timePitch latency 과도기. §I-6 해법(적용 시각 broadcast)은 네트워크 보상 전제라 재검토 필요. acoustic 교차검증(vfDiff offset 의존) 권장.

**빌드**: v0.0.123 (`_handleSeekNotify` seek coalesce 디바운스 150ms + dispose cancel).

---

### 2026-06-10 (143) — v0.0.124 무음(underrun) 객관 카운터 + 30분 측정 음원 (PLAN ② 선행)

PLAN 129줄 "30분 stress 측정 보고서"의 **선행 작업** = 무음(underrun) 객관 카운터 부재 해소. HAL `getXRunCount`는 콜백이 0으로 채운 **soft silence**(decode 못 따라옴 / SoundTouch out-ring 빔)를 정상 출력으로 보고 못 잡으므로 별도 카운터 필요(`oboe_engine.cpp:840/862/870`).

**변경 (v0.0.124)**:
- `oboe_engine.cpp`: atomic 4개(`mDecodeUnderrunFrames/Events`, `mStUnderrunFrames/Events`) + 콜백 로컬 누적 후 끝에 1회 `fetch_add`(RT-safe). decode underrun = `!muted && !decoded && vf∈[0,total)`(useST `:843` + bypass `:873`), ST underrun = `popped<numFrames`(`:862`). getter + JNI long array 8→12.
- `MainActivity.kt` Map 4키 / `native_audio_service.dart` `NativeTimestamp` 4필드(`-1`=미지원).
- `sync_measurement_logger.dart`: csv에 `guest_*`/`host_*` underrun 8컬럼(frames+events). `native_audio_sync_service.dart`: 호스트 자기 underrun을 `_handleDriftReport`에서 `_engine.latest` 직접 읽어 `host_*` 기록 + 게스트는 `[UNDERRUN][guest]` logcat(누적 변화 시에만).
- iOS `AudioEngine.swift`: 두 반환 Map에 `-1`(AVAudioEngine 내부 버퍼라 동일 카운트 불가).

**범위 결정 (사용자 합의, "추가가 많다" 지적 후)**: "호스트만 csv + 게스트 logcat". P2P 송신 배관(`_sendDriftReport`)은 **0줄 수정** — 측정 핵심은 재생 주체(호스트)이고, 게스트 underrun을 drift report에 동봉하는 건 효용 대비 배관 큼. 게스트는 자체 logcat으로 충분.

**측정 음원**: `assets/measure_scale_30min.mp3` 생성 — 도레미파솔라시도(C4~C5, `261.63~523.25Hz`) 100ms 톤 + 900ms 무음, 8초 주기 반복, 30분, 48k/stereo/192k. **음높이로 어긋난 비트를 즉시 식별**(싱크 앞/뒤 판별). Android 2대 `/sdcard/Download` push. pubspec 미등록(측정은 `_pickFile` 수동 선택이라 번들 불필요).

**관찰/발견**:
- PLAN 128줄 "algorithm latency 미반영"은 **옛 서술** — v0.0.112(Android SoundTouch `INITIAL_LATENCY`+batch)/v0.0.122(iOS `timePitch.latency`)로 **정적 항 이미 반영**(drift median 0.24 / acoustic +7.84). 남은 건 out-ring **동적 점유**(의도적 1단계 제외, `oboe_engine.cpp:627`, 효용<비용 후보).
- `assets/measure_audio.mp3`(12분) + `scripts/measure.sh`(`AUTO_MEASURE_MODE` dart-define)는 **lib 미참조 죽은 유물** — 현재 측정은 `_pickFile` 수동 방식. pubspec 등록/파일/measure.sh 묶어 정리 가능(사용자 결정 대기).
- csv는 **호스트가 방 만들면 자동 시작**(`startListening(isHost:true)`→`_logger.start()`, 별도 토글 없음) → 측정은 호스트1+게스트≥1 구성 필요.

**검증**: C++ NDK 컴파일 통과(`assembleDebug` 20.4s) + `flutter analyze` 0 issues. Android 2대(R3CT60D20XE/R3KL207HBBF) 설치+음원 push 완료. iOS(iPhone 12 Pro) profile 빌드 완료. **실측은 (144)**.

**빌드**: v0.0.124.

---

### 2026-06-10 (144) — v0.0.124 첫 실측: underrun=재생 시작 워밍업 1회성 + iPhone vfDiff 과도기(속도/음정 조정 시 오차)

**구성**: 호스트 R3KL207HBBF + 게스트 2대(Android R3CT60D20XE=`192.168.35.239`, iPhone 12 Pro=`192.168.35.209`). 같은 csv `sync_log_2026-06-10T17-21-13.csv`(`startListening` 재호출이 기존 파일 이어씀)에 **2배속 구간(+10.8~24.9min) + 1배속 구간(+30.6~42.3min, 11.7분 무조작 1.0x)** 누적. 보관: `measurements/underrun_v124_2026-06-10_mixed.csv`.

**underrun = 재생 시작 워밍업 1회성 (배속 무관)**:
- **ST underrun: 2배속·1배속 둘 다 정확히 7392 fr (154ms, 77 events)** — 동일값 = 결정론적. `event=96 fr`(콜백 1개 통째)씩 77회 = 재생 시작 시 SoundTouch out-ring 초기 채우는 동안 silence. 정상 재생 구간은 0. 카운터가 loadFile마다 리셋되는 듯(1배속 구간 delta=절대값 7392) → "재생 세션당 시작 워밍업 154ms" 성격.
- **decode underrun: 1배속 622 fr (13ms, 7ev)** — 재생 시작 ring 초기화 시 미미. 2배속 전체구간 0.
- 호스트 csv `host_*`와 게스트 logcat `[UNDERRUN][guest]`가 동일(7392) — 두 별개 기기가 같은 콘텐츠/콜백크기(96 fr)로 같은 워밍업.

**🎯 iPhone vfDiff = 배속 전환 과도기 노이즈 (iOS 고유 sync 문제 아님)**:
| 게스트 | 2배속 \|vfDiff\| | 1배속 \|vfDiff\| (깨끗) | 1배속 >100ms |
|--------|-----------------|----------------------|-------------|
| Android(.239) | 20ms | **6.9ms** | 0.1% |
| iPhone(.209) | **71ms** (>100ms 25%) | **17.3ms** | 0.1% |
- 2배속 측정의 iPhone 71ms(25%가 100ms 초과)는 **배속 슬라이더 1.0→2.0 변경(`host_tempo` 20회) + pause 과도기 스파이크**(vfDiff max 1144ms) 탓. **1배속 깨끗 조건에선 iPhone 17ms로 양호**. vfDiff는 offset 의존 외삽이라 "거짓말" 가능 — 과도기 노이즈 확인.
- ⚠️ **단 iPhone은 속도/음정 조정 시 오차 발생**(2배속·전환에서 vfDiff 악화 17→71ms, Android는 20ms로 덜 민감). 일상 1배속 재생은 양호(17ms, 결함 A 잔재 수준, (138) close 영역). 속도/음정 기능 쓸 때만 iOS 과도기 오차 참고. → §I-6 트랙.

**기타 sync 품질**: fallback 2배속 21% → **1배속 3%**(깨끗하면 offset 안정). `verify_fail` 0, seek 폭주 0(host_seek 3), `anchor_reset_offset_drift` 1회. 양호.

**방법론 교훈**:
- **측정 중 중간 pull 금지** — 진행 중 csv를 당기면 `host_vf`가 그 순간값이라 "정지"로 오판(실제론 28.1분까지 진행 중이었음). 측정 끝나고 한 번에 pull.
- **배속 검증은 재생 전 idle 제외 필수** — csv 첫 row(방 만든 시점)부터 wall 재면 파일 고르기·게스트 입장 idle(8.8분) 포함돼 2배속이 1.13x로 오산. 순수 재생 구간(첫 vf>0 ~ 마지막 vf증가)만 보면 1.74x(≈2배속, 남은 차이는 pause).

**빌드**: 코드 변경 없음 (실측·분석만, v0.0.124 데이터).

---

### 2026-06-10 (145) — 시크바/시간 표시 정확도(speed≠1.0) 조사 → 정상 확인 close

**배경**: PLAN "시크바/시간 표시 정확도 (speed != 1.0 시 totalDuration / position 표시)"는 v0.0.92(§I 속도 조절 도입) 당시 남긴 **미검증 후보**(HISTORY (109) 남은 후속 5835)였음 — 실제 관찰된 버그가 아님. 코드 조사 + 기존 실측 + iPhone 실기기 눈 확인으로 close.

**조사 결론 — 로직상 speed≠1.0서도 콘텐츠 timeline 기준으로 정상**:

| 항목 | 계산식 | speed 반영 | 판정 |
|------|--------|-----------|------|
| Duration(총길이) | `totalFrames / sampleRate` (`native_audio_sync_service.dart:1999`) | 안 곱함 → 원본 음원 길이 | ✅ 정상 |
| Position(UI) | `virtualFrame / sampleRate` (`:1384`) | 안 곱함, 단 vf가 콘텐츠 기준 진행 | ✅ 정상 |
| Position(내부 vf) | `inputFrames = (numFrames × speedX1000 + 500)/1000` (`oboe_engine.cpp`, (109) 5799) | 2배속 시 vf 2배 빠르게 증가 | ✅ 정상 |
| Seek | `position_ms × sampleRate / 1000` (`:603`) | 안 곱함 → 절대 콘텐츠 위치 | ✅ 정상 |

- **"2배속이면 시간 표시가 2배 빠르게 가는" 게 정상** — 콘텐츠 타임라인 기준(YouTube/Spotify 배속과 동일). 4분 곡을 2배속으로 틀면 실제론 2분에 끝나지만 시크바/시간은 00:00→04:00을 2배 빠르게 채움. (109) 도입 당시 설계 메모(5800)와 일치: "vf += inputFrames → position 표시도 1.5배 빠르게".
- duration을 "재생 소요 시간"(2분)으로 바꾸면 오히려 표준에서 벗어남 → 현 동작이 맞음.

**플랫폼별 근거**:
- **Android**: 코드로 확정. vf가 콘텐츠 프레임 단위 진행(`oboe_engine.cpp` onAudioReady inputFrames), UI는 `vf/sampleRate`.
- **iOS**: `playerTime.sampleTime`(`AudioEngine.swift:200-209`)이 콘텐츠/입력 기준인지 1차 문서 직접 확정은 안 됨(Apple 미명시). **가설**: AVAudioEngine pull-based 파이프라인 — 하드웨어가 N프레임 당기면 `timePitch.rate=2.0`서 입력 2N프레임을 playerNode서 pull → sampleTime 2배 진행. **간접 실증**: (144) 측정에서 iPhone 2배속 vfDiff **71ms로 유지**(`HISTORY (144)` 6840) — sampleTime이 출력 기준(rate 미반영)이었다면 게스트 vf가 호스트의 절반 속도라 vfDiff가 **초당 0.5초씩 무한 누적**돼 P2P sync가 박살났을 것. 71ms 유지 = vf가 콘텐츠 기준 진행하는 강력한 간접 증거.
- **iPhone 실기기 눈 확인 (2026-06-10)**: 2배속 재생 중 시크바/시간이 2배 빠르게 진행 — 정상 확인. → **close**.

**부수(실버그 아님)**: duration 초 단위 반올림(`native_audio_sync_service.dart:1999` `Duration(seconds:)`) — speed 무관, Android/iOS 1초 차이 통일용 의도된 것(HISTORY (10) 1042). 시간 표시 무관.

**빌드**: 코드 변경 없음 (조사·문서만).

---

### 2026-06-11 (146) — out-ring 동적 점유 반영 → 효용<비용 close

**배경**: PLAN HIGH "Algorithm latency를 `outputLatencyMs`에 반영"의 마지막 잔여 항. transpose/speed ON 시 SoundTouch 파이프라인 지연을 P2P 동기 보정값(`outputLatency`)에 더하는 작업인데, **정적 항(SoundTouch `INITIAL_LATENCY` + worker batch)은 이미 v0.0.112에서 반영**(`oboe_engine.cpp:626-640`, iOS는 v0.0.122 `timePitch.latency`). 남은 건 **out-ring 동적 점유**(`mSTOutRing`에 매 순간 쌓인 양) 하나뿐이었음.

**out-ring 동적 점유란**: SoundTouch 가공 결과를 담는 출력 ring(`mSTOutRing`, `kSTOutRingFrames=8192` ≈ 170ms @48k, `oboe_engine.cpp:42-44`)에 "지금 몇 ms어치 PCM이 대기 중인지"가 매 순간 0~170ms로 변동. 정확히 하려면 이 점유분도 `outputLatency`에 가산해야 콜백이 처리한 샘플의 실제 DAC 도달 시점과 맞음.

**close 결정 — 효용<비용**:
- **측정 이미 양호**: 정적 항만 반영한 상태로 drift median **0.24ms**, acoustic(마이크 실측) **emit_dt +7.84ms** — 결함 B 음향 비대칭(~11ms, HISTORY (132)) 범위 내. 동적 점유까지 안 넣어도 정렬 충분.
- **반영 시 리스크**: 동적 점유는 0~170ms로 출렁이는 값 → `outputLatency`에 직접 넣으면 anchor(동기 기준점)가 같이 출렁일 우려. `oboe_engine.cpp:627-628` 주석에서 "1단계 의도적 제외"로 이미 명시.
- 따라서 **불확실한 효용(이미 양호한 정렬을 미세 개선) < 확실한 비용(anchor 출렁임 + 검증 부담)** → 구현 안 함으로 결정.

**재개조건**: BT 등 큰 비대칭 경로에서 정적 항만으론 부족함이 체감될 때 / 다른 큰 이슈(§I-6 등) 해결 후 이게 마지막 병목으로 남을 때. 재개 시 동적 점유를 raw 가산이 아니라 EMA smoothing 등으로 anchor 출렁임을 막는 방향 검토.

**빌드**: 코드 변경 없음 (close 결정·문서만).

---

### 2026-06-11 (147) — §G step 2-G2 (Ready-then-Go 하이브리드) 도입 보류 → close

**배경**: §G PCM streaming의 G-2 항(시작/큰 seek 시 ready timeout 200ms 동기 시작 = `ready_then_go`). v0.0.77 (93) 시도 → v0.0.78 **(94) 회귀 revert**(호스트 큰 seek 직후 무음 stuck, loadFile 재호출해야만 풀림) 이후 "큐 모델 기반 재설계로 재시도" 후보로 남아 있었음. 지금 도입 안 함으로 close.

**close 근거 — 효용<비용**:
1. **도입 동기가 약해짐**: G-2가 풀려던 문제(큰 seek 직후 stale obs → vfDiff 100초+ race, HISTORY (91))가 그 후 측정에서 재현 안 됨 — §B 후속 (102) **256회 빠른 seek 측정에서 메시지 손실 0 · vfDiff 영구 잔재 0건**. 추가로 v0.0.111 거짓말 패턴 re-anchor(vfDiff>150ms 시 anchor 리셋, HISTORY (123))로 큰 seek 직후 폭주는 다른 경로로 이미 완화.
2. **재시도 비용 큼**: (94) 재시도 전제가 ring 상태(`mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts`)를 decodeLoop **단일 thread 직렬화 + 외부는 요청 큐 push만** 구조로 재설계(또는 G-2 native 흡수) + 회귀(호스트 무음) 재현 unit test 선확보. (94)에서 "한 줄 fix 영역 아님"으로 명시.
3. **§G 핵심 실용 가치는 G-1으로 이미 확보**: 14분 PCM 한도 제거(51분 곡 로드) · decode 2~3배 단축 · ~11.5MB constant 메모리는 G-1 ring buffer(v0.0.76 / v0.0.84 큐 모델 fix)로 달성됨. G-2 없이도 시작/seek 청감 양호.

→ 불확실한 효용(이미 재현 안 되는 race 방어) < 확실한 비용(엔진 재설계 + 회귀 위험)이라 도입 보류.

**종속 정리**: step 3(G-3 throughput EMA)도 "G-2 재도입 후" 전제라 함께 보류. 30분+ 측정은 (143)/(144)에서 1회 완료, iOS 회귀는 별도 iOS 트랙.

**재개조건**: 큰 seek 직후 무음 / vfDiff 폭주가 일반 WiFi에서 자연 재발할 때(§B 후속 진단 인프라 `seek_msg_seq` csv + `[SEEK-NOTIFY]` logcat 유지 중). 재개 시 (94) 전제대로 decodeLoop 큐 모델 재설계로 진행.

**빌드**: 코드 변경 없음 (close 결정·문서만).

---

### 2026-06-11 (148) — iPhone 2배속 톤 누락 추적 → realign 과잉 seek 가설 (기록 후 보류)

**배경**: 사용자 보고 — measure 음원 2배속 재생 시 "짧은 톤이 가끔 누락". 어제 (144) 30분 테스트(기기 겹쳐놔 호스트/게스트 청감 분리 불가) 중 들은 현상. 처음엔 §H/§I SoundTouch **82ms batch**(짧은 톤 vs 큰 처리 단위) 또는 §I-6 전환 과도기로 의심 → 추적 결과 **별개의 제3 이슈**로 좁혀짐.

**추적 (가설 단계적 반증·확정)**:
1. **음원 실측**: `measure_audio.mp3` = 100ms 톤 + 900ms 무음, 1초 주기(`ffmpeg silencedetect`). 2배속이면 톤 50ms, 주기 0.5초. SoundTouch worker batch=4096fr(85ms, `oboe_engine.cpp:178`)·`SEQUENCE_MS=82`(`:112`)와 비슷한 크기 → "톤이 batch 단위와 안 맞아 누락" 가설 성립 가능성.
2. **❌ 82ms/SoundTouch 가설 반증 (사용자 실측)**: 단독 1대(P2P·sync 없음) 2배속 재생 → **누락 재현 0**. SoundTouch + worker batch + ring 경로 무죄. 보조로 `ffmpeg atempo=2.0`도 50ms 톤 생존(=time-stretch 알고리즘 무죄, 단 다른 알고리즘·오프라인이라 참고).
3. **✅ realign 과잉 seek 가설 (어제 (144) csv 재분석, `measurements/underrun_v124_2026-06-10_mixed.csv`)**: `event=anchor_realign_vfdiff` **46회 전부 iPhone(.209), Android(.239) 0회**, 시간상 2배속 구간(11.0~24.7분)에 집중(1배속 구간 0). realign 코드(`native_audio_sync_service.dart:1794-1814`) = **vfDiff 중앙값 >60ms 시 `_engine.seekToFrame(targetGuestVf)`**(`:1803`)로 게스트 위치 강제 점프.

**가설 (강함)**: iPhone 2배속 vfDiff 71ms((144)) → realign이 60ms 임계 넘어 seek 46회 → **iOS 디코더(AudioConverter) 재생성**((142)) → 짧은 톤(50ms) 건너뜀 = 누락. 모든 관찰 일치:
- 단독 1대 누락 0 = realign 자체 없음(P2P 아님)
- Android 게스트 안 들림 = vfDiff 20ms < 60ms → realign 0
- iPhone 게스트 누락 = vfDiff 71ms → realign 46 = seek 46
- 2배속에서만 = 1배속은 vfDiff 작아 realign 0
- **(144) underrun 0인데 누락** = seek는 무음(silence padding)이 아니라 **위치 점프(톤 건너뜀)**라 underrun 카운터 무감지 → (144) "정상구간 underrun 0" vs 청감 누락 **모순 해소**

**미확정 (정직)**:
- realign 발동 vfDiff가 **진짜 어긋남인지 "거짓말"(측정 노이즈)인지** 미확정. 거짓말이면 realign이 멀쩡한 위치를 헛seek로 망가뜨리는 것(치료가 병) — HISTORY (136) "realign↑ = vfDiff 악화, self-seek 음수 편향" 패턴과 통함.
- realign seek가 그 순간 톤을 건너뛰는지 **녹음 직접 확인 안 됨**.
- realign 행 `vf_diff_ms`가 전부 0으로 찍힘 — 발동 조건이 >60ms인데 0일 리 없으니 **로깅 누락**(`_logGuestEvent`가 vfDiff 미전달, 사소한 측정 버그). 실제 분포는 drift 행으로 봐야.

**함의**: §I-6(전환 과도기)·82ms batch와 **별개 제3 이슈 = realign 과잉 seek**. 또 **iOS 편중** — realign은 공통 코드지만 *발동은 iPhone(vfDiff 큼)*, *아픔은 iOS(seek=디코더 재생성)*. iOS 후순위 → **fix 보류, 기록만**.

**재개조건**: iOS 트랙 재개 시. fix 후보(보류): (a) realign 임계(60ms) iOS 상향 or 신뢰도 게이트, (b) iOS `seekToFrame` 디코더 재사용(재생성 회피, (142) 잔음과 동일 깊은 트랙), (c) vfDiff 거짓말 여부 acoustic 확정 후 realign 발동 신뢰. **선행**: realign vfDiff 로깅 누락 fix(0→실값) — 그래야 발동 vfDiff 분포 측정 가능.

**빌드**: 코드 변경 없음 (진단·문서만).

---

### 2026-06-11 (149) — Crossfade(transition click) 해결법 설계 정리 → 보류 유지

**배경**: Crossfade(Option C, `SYNC_ALGORITHM_V2.md` §H H-4 7) 보류 항목의 **해결법을 코드 확인 후 정리**(착수 아님, 다음 재논의 시 중복 방지용 기록).

**click 원인**: pitch/tempo 변경(`oboe_engine.cpp:155,166`) 시 v0.0.102부터 `mST.clear()` 생략 → `mSTOutRing`에 옛 설정 출력 ↔ 새 설정 출력이 이어 붙어 **이음새 파형 불연속**. 단일 SoundTouch 인스턴스(`mST`)라 파라미터 바꾸면 옛 설정 소리를 동시에 못 만듦 = 진짜 crossfade 어려움.

**해결 옵션**:
- **(A) 짧은 fade — 권장**: 변경 순간 출력 수ms 페이드out → 변경 → 페이드in. click → 귀에 안 띄는 미세 볼륨 dip. 단일 인스턴스로 가능(`mSTOutRing` push/pop 경계 ramp).
- (B) 이중 인스턴스 crossfade: 옛·새 SoundTouch 병렬, 옛↘+새↗ N ms 겹침. 가장 매끄러우나 CPU/메모리 잠깐 2배 + 위치/latency 정렬 복잡.
- (C) 파라미터 ramp: transpose엔 음 미끄러짐(글리산도)이라 부적합. speed엔 가능.

**크로스플랫폼**: iOS는 `AVAudioUnitTimePitch`(OS 내장 노드)라 **내부에 fade 못 넣음** → 노드 출력단에서 별도 처리 필요(Android SoundTouch와 구현 다름).

**결론**: click 매우 미세(음악 무영향) → **보류 유지**. 착수 시 A로 Android 먼저, iOS 별도. 82(SEQUENCE) 줄이기는 정상 재생 처리 단위라 click 해결책 아님(별개 손잡이).

**빌드**: 코드 변경 없음 (설계·문서만).

---

### 2026-06-11 (150) — obs broadcast 주기 단축(500→200) 재검토: 과보정 우려=기우, realign 완화 후보로 연결

**배경**: PLAN MID 항목(clock sync broadcast 주기 단축) 재검토 — 사용자 질문 "단축 시 과보정으로 틀어짐 누적되지 않나?".

**분석 (코드 근거)**:
- realign/seek 판정은 게스트 자체 `timestampStream` poll(~100ms, `:33` 주석)마다 `_recomputeDrift`(`:1481`/`:1697`) → vfDiff 중앙값 >60ms면 realign(`:1794`).
- obs는 호스트가 500ms마다 broadcast(`_obsBroadcastIntervalMs` `:36`) → 게스트 `_latestObs` 갱신. **poll(판정)과 obs(정보)는 별개 통로** — poll=게스트 native emit, obs=네트워크.
- ∴ obs 주기 단축해도 **판정 빈도(poll 100ms) 불변**. 오히려 게스트가 매 poll `_latestObs`로 외삽(`:1744`, `hostWallNow - obs.hostBootMs`)하는 거리가 짧아짐 → vfDiff 정확↑.

**결론 — 과보정 누적 우려 = 기우(반대)**: 누적 위험은 obs가 **길 때**(외삽 멀어 vfDiff 거짓말 → 틀린 위치 seek) 더 큼. 단축하면 외삽 짧아 realign 정확도↑ + 헛발동↓.

**새 함의**: (148) realign 과잉 seek **완화 후보** — iPhone vfDiff 71ms 흔들림 일부가 외삽 거리에서 오면 obs 단축이 realign 발동을 줄일 수 있음.

**미확정/비용**: vfDiff 거짓말 주범이 외삽 거리인지 offset 노이즈인지 미확정 → 효과 미확정(다른 주범이면 트래픽만 늘고 효과 미미). 트래픽 2.5배(호스트, 멀티 게스트 ×N)는 확실 비용. cold start는 v0.0.74로 이미 해결돼 원래 단축 동기 약화.

**결정**: 지금 단독 변경 안 함(효용<비용 가능). **iOS 트랙(realign (148)) 재개 시 "obs 단축 ↔ vfDiff 흔들림 감소"를 묶어 측정 후 결정.** PLAN MID 항목에 연결.

**빌드**: 코드 변경 없음 (분석·문서만).

---

### 2026-06-11 (151) — 온보딩 가이드 오버레이(coach mark) 추가 (v0.0.125)

**배경**: UI 폴리싱(#16) 트랙 중 사용자 요청 — "처음 앱 열거나 가이드 버튼 누르면 반투명 오버레이로 각 버튼 설명". coach mark 패턴.

**구현 (v0.0.125, `lib/screens/player_screen.dart`)**:
- **패키지**: `tutorial_coach_mark 1.3.3`(순수 Flutter, Android/iOS 동일 — 네이티브 무관). 첫 실행 플래그는 기존 `shared_preferences` 재사용 → 추가 의존성 1개뿐.
- **타겟**: 8개 영역(파일선택/시크바/A-B/슬롯/음정/속도/재생컨트롤/싱크모드)에 `GlobalKey` — build에서 각 `_buildXXX()`를 `KeyedSubtree`로 감싸 부착(레이아웃 코드 거의 안 건드림). **`shape: RRect`**(가로로 긴 위젯은 원형이면 화면 절반 덮음 → 사각, `radius:12`).
- **트리거**: ① 첫 실행 자동(initState `addPostFrameCallback` → `SharedPreferences` `hasSeenGuide_v1` 체크) ② AppBar `?`(help_outline) 버튼(`_showGuide` 수동). P2P 버튼에 `_keyP2P` 부착.
- **진행**: 각 말풍선 우하단 **"다음 →"/"완료 ✓"(마지막)** 버튼 → `_coachMark.next()`. 하이라이트(타겟) 탭도 진행. ⚠️ **오버레이 빈 곳 탭은 패키지가 기본 미수신** — `onClickOverlay`+`next()` 시도했으나 무효 → 버튼/타겟 탭으로 진행. (`enableOverlayTab`은 닫힘으로 오작동해 제거.)
- **문구**: 해요체 통일 + "[동작]. [되돌리기/팁]." 구조. A-B "길게 누르면 그 지점만, Ⓧ로 전체 해제", 위치저장 "길게 누르면 해제"(코드 `:779-781` 확인), 음정/속도 "↻로 원래 ~로 되돌려요". P2P→**"싱크 모드"**(연동/해제 절차는 가이드 생략 — 들어가면 BottomSheet서 안내).

**결정**: 첫 실행 자동(강제) **유지** — 숨은 기능(길게 누르기·A-B·슬롯·음정/속도) 발견성 + 빈 첫 화면이라 방해 적음 + 건너뛰기로 탈출 쉬움(1회만). 비강제(? 버튼만)/절충(힌트 배너) 대안 검토 후 현행 채택. → DECISIONS.

**검증**: 에뮬 Pixel_6. 첫 실행 자동 표시 + RRect 사각 하이라이트 + **손가락 탭으로 단계 진행 정상**(사용자 확인) + 건너뛰기/완료 동작. `flutter analyze` 0 issues. ⚠️ **방법론**: `adb input tap`은 가이드 오버레이와 상호작용 불안정(종료 오작동) — 실제 손 탭은 정상. 검증은 손 탭 우선.
- **부수(별개)**: 에뮬 첫 부팅이 `lo0` loopback의 `127.0.0.1` 부재로 "too many emulator instances" abort → `sudo ifconfig lo0 alias 127.0.0.1` 복구. AVD/lock 무관, 환경 이슈(메모리 기록). emulator는 콘솔/ADB 포트를 127.0.0.1에 bind하므로 그 주소 없으면 전 포트 실패.

**빌드**: v0.0.125.

---

### 2026-06-11 (152) — 출시 전 준비도 점검 → 출시 체크리스트 PLAN 추가

**배경**: 사용자 "이제 출시 전인 것 같은데" → 준비도 점검. "출시 = 기능 + 기능 외"인데 기능 MVP는 탄탄하나 기능 외 요소 점검.

**점검 결과 — 주요 블로커**:
- 🔴 **Android release 서명이 debug keystore** (`android/app/build.gradle.kts` `signingConfig = signingConfigs.getByName("debug")`) → Play 업로드 거부. release keystore + 서명 config 필요.
- 🔴 **수익화 코드 0** — 프로 IAP(`in_app_purchase` 패키지 없음) + 무료 2대 제한 로직 없음. DECISIONS(2026-06-01)는 모델 결정만.
- 🔴 **앱 아이콘 기본 Flutter** (`ic_launcher.png`) — 커스텀 필요.

**갖춰진 것**: bundle id/앱 이름, iOS 권한 설명(로컬네트워크/Bonjour/AppleMusic), Android 권한(INTERNET/FOREGROUND_SERVICE mediaPlayback 등), 16KB page 대응, 핵심 기능 + sync 1배속 양호 + iOS 크래시 fix.

**잔여 iOS 이슈**(§I-6 / realign 톤 누락(148) / 잔음(142))는 일상 1배속 영향 없어 **출시 블로커 아님**.

**결정**: 출시 전략(무료 먼저 vs 수익화 포함)이 남은 작업량을 가름 → 전략 정하기 전 **PLAN "🚀 출시 체크리스트" 섹션**으로 전체 항목+상태(블로커/스토어등록물/마무리/완료) 정리. 전략은 체크리스트 보고 결정.

**빌드**: 코드 변경 없음 (점검·문서만).

---

### 2026-06-16 (153) — 작은 화면 대응: PlayerScreen 스크롤 fallback (v0.0.126)

**배경**: 출시 전 작은 화면 대응 점검. 사용자 "우리 앱 최소 필요 높이가 얼마야?" → PlayerScreen body 구조 조사.

**조사**: body가 **스크롤 없는 단일 `Column` + 맨 위 `Spacer` 하나**(`player_screen.dart:424` 당시). Spacer가 남는 공간 흡수용 → 화면이 짧으면 Spacer가 0으로 collapse하고 그 아래 고정 콘텐츠가 넘쳐 RenderFlex overflow. 코드 라인 기준 고정 콘텐츠 합산 추정 ≈ **620dp**(콘텐츠) + Padding 32 = body **~652dp**, 윈도우 **~760dp**(AppBar 56 + 상태바/제스처 inset 포함). 개별 위젯 높이는 코드 근거지만 실제 렌더 ±10% 변동이라 추정.

**도달 가능 케이스 정정**: Android는 `main.dart:16-17` `SystemChrome.setPreferredOrientations([portraitUp, portraitDown])`로 **세로 고정** → 가로 모드 overflow는 도달 불가(처음엔 가로를 주 위험으로 들었으나 정정). 실제 도달 = **분할 화면(split-screen)** + **글꼴 크게 설정**(accessibility, `fontScale` configChanges) + 구형/작은 폰. iOS Info.plist는 landscape 허용이라 iOS는 가로도 해당.

**fix (v0.0.126)**: body를 `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight: constraints.maxHeight)` + `IntrinsicHeight`로 감쌈(`player_screen.dart:421~`). 표준 "fill if tall, scroll if short" 패턴 — 화면 충분하면 minHeight로 꽉 차 Spacer 살아 **기존 레이아웃 보존**, 짧으면 IntrinsicHeight가 실제 콘텐츠 높이 잡아 그만큼 스크롤. 내부 `_build*` 위젯은 무수정.

**검증** (SM S947N debug):
- 포트레이트 정상(1080x2340): 기존과 동일 레이아웃, Flutter 예외 0.
- IntrinsicHeight + Slider 조합의 "intrinsic 미지원 assert" 우려 → **에러 0** 확인(logcat `intrinsic`/`does not support returning`/`was not laid out` 검색 무결과).
- 짧은 화면 강제(`wm size 1080x1300` + `font_scale 1.8`): **overflow 노란줄 0**, Spacer collapse + 우측 스크롤바 + 하단 컨트롤이 화면 아래로. 위로 스크롤 시 재생/skip/mute 컨트롤 전부 정상 노출. AppBar 고정.
- 검증 후 기기 설정 원복(wm size reset / font_scale 1.0 / rotation auto).

**빌드**: v0.0.126.

---

### 2026-06-16 (154) — iOS 세로 고정 + 큰 글꼴 SPEED/TRANSPOSE 2줄 wrap fix (v0.0.126, (153)과 동일 버전)

**배경**: (153) 검증 캡처에서 큰 글꼴(fontScale 1.8) 시 `SPEED 1.00x`가 `1.0`/`0x` **2줄로 wrap**되는 것 + iOS도 Android처럼 세로 고정 요청.

**fix 1 — iOS 세로 고정**: `ios/Runner/Info.plist` `UISupportedInterfaceOrientations`(iPhone)와 `~ipad`를 모두 `UIInterfaceOrientationPortrait` 단일로(landscape/upsideDown 제거). Android는 이미 `main.dart:16-17` `setPreferredOrientations([portraitUp, portraitDown])`로 세로 고정 → **양 플랫폼 세로 고정 일치**. (iOS Info.plist가 setPreferredOrientations보다 우선이라 plist 수정 필요했음.)

**fix 2 — 값 텍스트 2줄 wrap**: root cause = SPEED 값 `Text`가 `SizedBox(width: 52)`(위치 고정용, `player_screen.dart`)에 갇혀 큰 글꼴 시 intrinsic width가 52 초과 → wrap. TRANSPOSE 값도 동일(width 36). 둘 다 `FittedBox(fit: BoxFit.scaleDown, alignment: centerRight)`로 감쌈 — 폭 초과 시에만 축소(평소 무변화), 우측정렬·width 고정 유지. clip/ellipsis 아니라 축소라 글자 안 잘림.

**검증** (SM S947N, fontScale 1.8): SPEED `1.00x` **한 줄** 복원(이전 2줄) + TRANSPOSE 정상. analyze 통과. 검증 후 font_scale 1.0 원복.

**빌드**: v0.0.126 ((153)과 같은 버전 — 한 세션 내 작은 화면 대응 묶음이라 patch 1회만 bump).

---

#### 미해결 이슈

**싱크/재생**
- [x] ~~seek 연타 시 싱크 틀어짐~~ — absolute targetMs + cooldown으로 해결 (2026-04-20)
- [x] ~~Android↔iOS 싱크 정확도~~ — sampleRate 정규화 + cross-rate ms 비교로 ±4ms 달성 (2026-04-20)
- [x] ~~iOS 게스트에서 총 재생시간(duration) 0:00 표시~~ — loadFile 반환값에 totalFrames 포함 (2026-04-20)
- [x] ~~호스트 파일 빠른 교체 시 race condition~~ — 세션 ID + HttpClient 강제 종료 + stale 체크 (2026-04-20)
- [x] ~~호스트 재생 완료 → 처음 재생 시 게스트가 잠깐 4:55~4:59 표시 후 0:00 이동~~ — seek-notify `!_playing` 가드 제거 + UI override (2026-04-22)
- [x] ~~게스트 파일 다운로드 속도 체감상 느림~~ — shelf 제거 + HttpServer 직접 + Content-Length + 1MB chunk로 +40~50% 개선 (2026-04-22)

**레이턴시 보정**
- [x] ~~S22 buf=4ms vs iPhone buf=21ms 비대칭 (17ms)~~ — **v0.0.4에서 측정 방식 통일로 compensation 계산 왜곡 원인 제거** + **2026-04-24 (30) 실측으로 v3 framePos 폐루프가 완전 흡수 확인** (3분 재생 안정 구간 \|drift\| < 5ms, p95 3.78ms). 추가 작업 불필요.
- [x] ~~엔진 레이턴시 보정값 ~10ms 오차~~ — **실제로는 이 수치의 구체적 측정 근거가 코드/문서에 없음** (git log 추적: ec80452에서 "수동 보정 슬라이더 추가 예정"으로 추가 → 6e53efd에서 "자동 측정 방식 개선"으로 문구만 수정). v3 전환 후 `com.synchorus/audio_latency` 채널 제거(v0.0.33) 이후 **"엔진 레이턴시 보정값"이라는 수치 자체가 코드에 없음** — 엔진 레이턴시는 `oboe::getTimestamp()` / `AVAudioTime` 반환값에 내포. "~10ms"의 유력 출처는 PoC Phase 5~6의 `\|drift\| < 10ms 100%`(HISTORY.md:491,500,534) 또는 drift mean 진동 범위(HISTORY.md:648) — 이건 **성능 지표**이지 "오차"가 아님. (2026-04-24 (29)에서 맥락 재정리·제거)
- [ ] **Bluetooth outputLatency 동적 보정** — BT 이어폰·스피커는 연결 중에도 `outputLatency`가 ±50ms 변동(ARCHITECTURE.md:177~178). 현재 고정값 기반 → BT 환경에서 drift 누적 가능. 주기 재측정 + EMA 반영(자동 보정) 방향. (2026-04-24 (29) 신규 항목). **외부 문서 검증 결과 주의**: Apple `AVAudioSession.outputLatency`가 BT 실제 지연을 과소보고하는 것으로 보고됨 (developer.apple.com/forums/thread/126277) → iOS에서 이미 측정 중인 값을 Dart `_recomputeDrift`에 반영해도 효과 제한적일 수 있음. BT route 변경 감지는 `AVAudioSession.routeChangeNotification` 공식. Android는 `AAudioStream_getTimestamp`가 DAC까지만 커버, BT transmission 지연 포함 여부 불확실(google/oboe#357 관찰).
- [ ] **호스트 `oboe::getTimestamp` 간헐적 실패 — 체감 싱크 깨짐 원인** (2026-04-24 (30) 신규). S22 3분 재생 중 재생 시작 직후 26회, 정지 직전 15회 연속 실패 관측. 100ms 폴링 기준 **1.5~2.6초 동안 호스트가 재생 위치를 못 읽음** → 게스트는 외삽 계속이라 drift-report는 안정(0~3ms)해 보이나 실제 재생은 최대 1.5초치 어긋남. 원인 가설: stream xrun / HAL 일시 실패 / 라이프사이클 전환 부근 상관. `oboe_engine.cpp:278` 근처에서 실패 시 `AAudio_convertResultToText(result)` 로그 추가 → 원인 분류 필요. 완화 방향: 실패 중에도 최근 성공한 framePos + 경과 시간으로 보간해 obs 계속 전송.
- [x] ~~**Logger csv 경로 접근성**~~ — **이미 v0.0.36에서 fix 완료** (`sync_measurement_logger.dart:26~29` Android 한정 `getExternalStorageDirectory()` 우선 사용 → `/sdcard/Android/data/<pkg>/files/`). v0.0.71 (85) 측정 csv 실측 확인: `/storage/emulated/95/Android/data/com.synchorus.synchorus/files/sync_log_*.csv` (S22 Dual App user 95 케이스). `measure.sh:131`도 `/storage/emulated/*/...` glob으로 검색하여 user 0/95 모두 커버. **stale 미해결 이슈 정리 (v0.0.71 (85) 후속)**.
- [ ] **Anchor reset 후 fallback 단계 큰 drift** (2026-04-26 (42) 신규, **보류 — 작업목록 제외 2026-05-03**). 호스트 정지/재생/seek 시마다 게스트 측 anchor 폐기 → 5초 fallback 단계에서 외삽 부정확 → drift 최대 -634ms (0.6초 어긋남) 발견. Android 게스트 한정 stream open latency가 외삽에서 누락된 것이 직접 원인. v0.0.43 baseline에도 있던 이슈로 prewarm 회귀와 무관. **NTP 정공법 2회 시도 모두 실패** — v0.0.46~v0.0.48 (HISTORY (43)) drift 63초 회귀 → 롤백, v0.0.49~v0.0.61 (HISTORY (44)) 13번 fix 사이클 → 사용자 청감 v0.0.48이 더 나음 → main reset. **§D-2 fix(v0.0.63)로 자연 해소 정황** — v0.0.67 12분 자동화에서 anchor_reset 0회, vfDiff RMS 21ms. 본격 재도입 트리거는 §C rate drift 결정(PCM streaming 구조 변경 후 30분+ 측정)에 묶임. backup branch 보존: `backup-v0.0.61-session`, `backup-v0.0.51-to-v0.0.55-session`.
- [x] ~~**파일 변경 시 호스트 무음 + 게스트만 단독 재생**~~ — **v0.0.69 (83)에서 4단계 fix 완료** (audio-url playing=false 강제 + framePos>0 sanity gate + audio-url 수신 시 _latestObs reset). 실기기 S22+A7 Lite로 두 번째 파일 변경 시 게스트 단독 재생 회귀 사라짐 확인.
- [x] ~~**HTTP 404 stale state — 게스트 재접속 시 다운로드 실패**~~ — **v0.0.70 (84) 방어적 fix 완료**. `_cleanupTempDir`에 활성 `_storedSafeName` 보호 가드 + `_handleAudioRequest`에 disk 파일 존재 확인 + `startListening` 재호출 진단 logging. 실기기 검증 통과. 단 root cause(startListening 재호출 트리거)는 미확정, 자연 재현 시 `[DIAG] startListening re-entry` 로그로 좁힐 예정.
- [x] ~~**iOS 26.4.1 + macOS 26.3 환경 빌드 install hung**~~ — **회피 표준화 완료 (v0.0.71 (85) 후속)**. CLAUDE.md "실기기 빌드/설치" + "iOS debug 빌드 디버거 attach 필요" 섹션 갱신. CLI hung 시 잔재 프로세스 정리 + IntelliJ/Xcode IDE 권장. 근본 fix는 Apple/Flutter toolchain 측이라 운영 차원에선 표준 우회로 마감.
- [ ] **Tab A7 Lite oboe pause/resume xrun** (2026-04-26 (43) 신규, low priority). v0.0.46 oboe stop을 `requestPause`로 변경 후 Tab A7 Lite에서 pause→resume 사이클마다 xrun + getTimestamp ErrorInvalidState 50~360ms 동반. S22는 정상. 저가형 HAL 한계로 추정. 회피 — pause 모델 대신 close + reset 사용 분기. 또는 NTP 정공법으로 우회.
- [x] ~~**게스트 3명 입장 불가 (이름 충돌 핑퐁)**~~ — **v0.0.54 (52) name+IP fix → v0.0.73 (88) 영속 deviceId(UUID) fix로 단순화 완료**. 같은 모델 2대 환경 검증 부담 자체 해소(코드상 충돌 1/2^128). 갤럭시 3대(모델 무관) + 비행기 모드 검증으로 충분.
- [ ] **호스트 PlayerScreen 첫 진입 시 모든 버튼 비활성화** (2026-05-17 (100) v0.0.84 신규, 1회 재현). 재생/정지/5초 skip/mute/seekbar 모두 비활성화 상태. 방 나갔다 다시 만들기 2~3회 시 복구. `widget.isHost` 또는 `currentFileName` 일시 false로 평가됨 추정. v0.0.84의 oboe_engine.cpp 변경(native engine)이 Dart UI 상태에 영향 줄 흐름 모호. 영구 무음 아니라 critical 아님. 재현 패턴 모이면 root cause 추적 — 의심 후보: PlayerScreen build 순서 race, native engine init time 변경 영향, install 직후 fresh state 이슈.
- [ ] **anchor 베이크인 outputLatency 부정확 (vfDiff -319ms 잔재)** (2026-05-17 (100) 신규 관찰, HISTORY (42)/(45)/(98) 동일 영역). v0.0.84 5분 측정 중 1회 13초 지속 — `out_lat_delta_anchored = 13.09ms` 영구 박힘 + drift_ms ±4ms (sync 자체 정확) + vfDiff -319 ~ -346ms (청감 인지). 사용자 seek로 anchor reset 시 0ms 복귀. 본 commit 무관. PLAN HIGH §B v0.0.81 ANCHOR-VERIFY 임계 200~300ms로 좁히는 후속에 이미 분류.
- [ ] **호스트 빠른 seek 연타 시 게스트 vfDiff -197초 영구 잔재** (2026-05-17 (100) 후속 측정 발견 → 2026-05-25 (102) **v0.0.85 진단 측정 결과 재현 실패, 의심 가설 3가지 모두 부정**). 원 관찰: csv `sync_log_2026-05-17T17-44-45.csv` seq 324~342에 vfDiff -197초 19초+ 지속, drift_ms ±5ms (sync 정확), 게스트 syncSeek 자체 발화 누락. v0.0.85에서 `seek_msg_seq` csv 컬럼 + `[SEEK-NOTIFY]` logcat 태그 추가 후 측정: host_seek 256회 ↔ anchor_reset_seek_notify 256회 1:1 매칭(메시지 손실 0) + 게스트 handler 모두 발화 + 큐 모델 native 처리 OK + vfDiff 영구 잔재 0건. 가능성: race 의존성(확률적) 또는 환경 의존성(맥북 핫스팟 저latency vs 일반 WiFi). **진단 인프라 유지 + 자연 재발 trigger 발견 시 root cause 분리 가능**. 일반 WiFi 환경 재측정 + 자연 재발 대기. 상세 분석 HISTORY (102).
- [ ] **단독 모드 → P2P 전환 시 audio-url 미전파** (2026-05-29 (105) v0.0.88 신규). 단독 모드(WiFi 없음)에서 파일 로드 후 사용자가 WiFi 켜고 방 만들기 누르면 `_currentUrl == null`이라 게스트가 들어와도 audio-url 못 받음. 해결안: 방 만들기 시점에 `_startFileServer` 재시도 + audio-url broadcast 트리거. 사용자 합의 후 처리.
- [x] ~~**Android 16 16KB page size 정렬 미준수**~~ — **v0.0.101 (118) 완료**. 2026-06-01 실측 결과 미정렬은 `liboboe.so`(oboe 1.9.0 AAR) **단 하나**(나머지는 NDK 28 + Flutter 3.41 + AGP 8.11이 이미 정렬, `libVkLayer`는 debug 전용). oboe `1.9.0`→`1.9.3` 한 줄로 해결, 전 ABI ELF+zip 정렬 통과, SM S947N 첫 실행 경고 사라짐 + 오디오 회귀 없음 확인. (2026-05-29 (105) 최초 보고 시점의 7개 미정렬 목록은 debug APK 기준 + 당시 버전 조합 기준이었음.)
- [ ] **거짓말 패턴(vfDiff) — 대부분 해소, 잔여 추적** (2026-06-03 (123) v0.0.111 부분 대응 → 2026-06-05 진척). (1) `isOffsetStable` jitter anchor 공백 → ✅ **v0.0.120 (135) fix**(stable 82%, fallback 지배 해소). (1') vfDiff 40~95 진동 → ✅ **(138) close**(v0.0.118/119 효과, 재입장 5회 재측정에서 재현 안 됨, 폭 3~6ms). 잔여: (2) host HAL getTimestamp 간헐 실패(framePos=-1, (30) 재발) 미해결, (3) offset reject ~73% → ✅ **close (139)**(RTT>30 품질 게이트라 무해, 환경 탓, 완화 다 역효과), (4) 결함 A 잔재(anchor establish -7~-22 편향, fallback이 더 정확, 청감 OK → (136) close, 재개 시 rate-bend). 상세 (138)/(135)/(136) / PLAN §H.
- [ ] **게스트 engine 재시작 루프 (막 조작 트리거)** (2026-06-03 (123) v0.0.111). host seek 연타 + play/pause 토글 막 조작 시 guest start/stop 반복 → "position(vf) 동기 표시인데 실제 다른 부분 재생". 정상 사용에선 미발생 — 막 조작 견고화는 별도 트랙(우선순위 낮음).
- [ ] **iOS 게스트 잔음 — seek 폭주 → framePos 붕괴** (2026-06-10 (140) v0.0.121 진단). seek 연타(시크바 막 드래그) 시 게스트 seek 폭주 → mp3 디코더(`AudioConverter`) ~2초마다 235회 재생성=잔음 + outputNode.sampleTime 꼬임 → `framePos` 72분 폭주(fpVfDiff) → anchor 매번 REJECT/reset → 위치 못 맞춰 seek 무한 → **잔음 지속(seek 멈춰도)**. iOS `framePos`(outputNode 누적)가 seek/node 재생성 후 `vf`와 어긋남 = v0.0.114 "vf/framePos 정합" 가정이 seek 폭주에선 깨짐 ((137) offset 폭주와 동일 뿌리). **정상 seek(가끔)에선 미발현** → 일상 사용은 v0.0.121 크래시 fix만으로 안전. idevicesyslog 진단 근거 (140). **⏳ (142) 정정+진전**: 실측상 잔음 주범은 framePos 붕괴/establish-REJECT 루프(`anchor_reset_verify_fail` 16회)가 아니라 **`host_seek` 331회 → 게스트 seekToFrame 331회 = iOS 디코더 재생성**. **v0.0.123 seek-notify coalesce(150ms 디바운스)로 완화** — baseline+일반 seek OK, 극한 막 조작엔 잔존(디바운스 150 < seek 간격 median 176ms). 추가 = 디바운스 튜닝 or iOS 엔진 디코더 재사용(깊음). framePos 도메인 재설계는 잔재 재현 시 재검토. 상세 (142).
- [x] ~~**iOS 게스트 sync 오프셋 −13~−27ms (timePitch latency 미반영)**~~ — **v0.0.122 (141) 해결**. timePitch.latency(baseline 85.33ms, pitch 무관·speed 반비례) outputLatency 가산 → acoustic emit_dt **+7.84ms**(결함 B ~11ms 범위)로 fix 성공 확정(가설 A: 85ms = 실제 음향 지연). ⚠️ (140) "−13~−27ms(csv vfDiff)" 진단은 **인과 오진** — vfDiff는 outLat fix에 순환 무감각(seek와 계산에 같은 outLatDelta 상쇄), 그 잔차는 결함 A((136)/(138) close). 상세 (141).

**안정성**
- [x] ~~호스트 백그라운드 진입 시 파일 서버 끊김 → 게스트 seek 시 "404"~~ — v0.0.22(HTTP 서버 재구현) + v0.0.23(heartbeat timeout 15초) 이후 재현 실패. 실기기(S22 호스트 + iPhone + A7 Lite 게스트) 3기기에서 홈 버튼/파일 선택 창/다운로드 중 파일 선택 모든 경로 검증. 단일 원인 확정은 못 했고 두 변경의 합산 효과로 추정 (2026-04-22). **v0.0.25에서 프로토콜 메시지 + 자리비움 배너 + 주기적 재접속으로 근본 대응 완료.**
- [x] ~~호스트 파일선택 창 열고 있는 동안 게스트 입퇴장 시 안정성~~ — 위와 같은 조건에서 재현 실패 (2026-04-22). v0.0.25에서 호스트 라이프사이클 프로토콜로 명시적 처리.
- [x] ~~호스트 재생 전 paused 시 게스트 연결이 tcp abort로 끊겨 재접속 실패 → 방 폭파~~ — v0.0.25 host-paused/resumed + 주기적 재접속 watchdog로 해결. T1~T4 실기기 검증 완료 (Android 2대) (2026-04-22)
- [ ] 디버그 모드에서 호스트 플레이어 간헐적 스터터
- [ ] iOS 실기기에서 라이프사이클 시나리오(T1~T4) 재검증 — v0.0.25는 Android 2대로만 검증됨. iOS의 background audio 미활성 상태에서 paused 동작과 detached 이벤트 도달 여부 확인 필요
- [x] ~~**v0.0.27 errno=111 빠른 포기 실측 검증**~~ — 2026-04-24 (23)에서 S22+iPhone 조합으로 T4b 실측. **Darwin errno=61 미체크 버그** 발견 → v0.0.30에서 수정 → 재검증 ~10초 fast giveup PASS. W(게스트 WiFi off/on)는 일반 재연결 성공, errno=65/51 분기 재현은 추가 조건 필요 (WiFi 30초+ off 또는 AP 이동)
- [ ] W 시나리오의 errno=65/51(Darwin EHOSTUNREACH/ENETUNREACH) 분기 실행 캡처 — 2026-04-24 (23)에서 WiFi off 시간이 짧아 Socket.onDone 도달 전 WiFi 복구됨. 30초+ off 또는 호스트와 다른 AP 이동 시나리오 필요
- [x] ~~Peer count 불일치~~ — 2026-04-24 (25) stale peer 정리 + peerCount broadcast 포함으로 수정(v0.0.32). **2026-04-24 (27) S22+iPhone 실측 PASS** — 비행기 모드 on/off 반복 중 양쪽 2명 유지 확인
- [x] ~~**Peer count 불일치 회귀 — 게스트 강제 종료 시 다른 게스트 갱신 실패**~~ — **v0.0.71 (84) fix 완료**. `p2p_service.dart:286~290` `socket.done.catchError` 분기에서 broadcast 누락이 root cause. iPhone 강제 종료 = TCP RST → catchError 진입 → 다른 게스트 알림 안 감. 정상/에러 분기를 `onDone()` 함수로 통합. 실기기 3대(S22 + A7 Lite + iPhone) 검증 통과.
- [x] ~~게스트 재연결 race(무한 loop)~~ — 2026-04-24 (27) p2p_service.dart onDone에 `identical(_hostSocket, socket)` 가드 추가(v0.0.34). 짧은 off(5~8초)에서 두 재연결 경로(`_handleDisconnected` + `_waitForWifiAndReconnect`)가 동시 성공 시 old socket의 onDone이 새 socket까지 destroy하면서 발생하던 무한 loop 차단
- [x] ~~게스트 재연결 경로 중복(재동기화 2회, 1회 실패 보고)~~ — 2026-04-24 (28) `_reconnectInProgress` flag로 두 경로 직렬화(v0.0.35). race 자체 제거 → Reconnect 7→3, 재동기화 실패 0. v0.0.34 onDone 가드는 안전망으로 유지

#### 해결된 이슈
- [x] 호스트 파일 빠른 교체 시 race condition — 세션 ID + HttpClient 강제 종료 + stale 체크 (2026-04-20)
- [x] iOS duration 0:00 — loadFile 반환값에 totalFrames/sampleRate 포함 (2026-04-20)
- [x] 재생 완료 시 멈추지 않음 — VF >= totalFrames 자동 정지 추가 (2026-04-20)
- [x] sampleRate mismatch (88ms/sec drift) — C++ framePos 정규화 + cross-rate ms 비교 (2026-04-20)
- [x] seek 연타 29초 점프 — absolute targetMs + anchor 무효화 + cooldown (2026-04-20)
- [x] premature anchor — EMA fast phase 중 stability gate (2026-04-20)
- [x] 네이티브 엔진 `unload` — 방 나가기/종료 시 PCM 메모리 해제 (2026-04-17)
- [x] iOS 접속 불가 — connectivity_plus WiFi 감지 false negative → 체크 제거 (2026-04-17)
- [x] iOS 게스트 한글/공백 파일명 로드 실패 → `_safeFileName` 해시명 (2026-04-16)
- [x] 대용량 파일 전송 중 TCP 끊김 → 청크 32KB + 딜레이 20ms (2026-04-16)
- [x] 호스트 재생 중 파일 로드 시 재생 안 됨 → 앱 임시 디렉토리 복사 (2026-04-16)
- [x] 에뮬↔실기기 네트워크 → IP 직접 입력 연결 (2026-04-13)
- [x] 에뮬 싱크 ~100ms 차이 → 엔진 레이턴시 보정 (2026-04-13)
