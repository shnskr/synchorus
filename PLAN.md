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
- [ ] iOS PoC (AVAudioEngine `lastRenderTime` 기반, Android PoC 통과 후)

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

**다음 작업**
- [ ] 네트워크 블립 테스트 (WiFi 일시 끊김 → 복구 후 재동기화)
- [ ] iOS PoC (AVAudioEngine `lastRenderTime` 기반, Android PoC 통과 후)

#### 알려진 이슈 / 다음에 확인할 것
- [ ] **(2026-04-07 실측)** v0.0.4 측정값: S22(호스트) buf=4ms, iPhone(게스트) buf=21ms / rawOut=15ms → `comp = +17ms`
  - iPhone buffer 21ms ≈ 1024 frames @ 48kHz (Apple 표준 IO buffer), S22 192 frames @ 48kHz
  - 측정 통일 후에도 17ms 비대칭 잔존 — 이건 buffer 자체 차이라 "진짜 latency 차이"의 일부
  - Android의 hardware 출력 지연(rawOut)은 여전히 못 잡음 → 진짜 보정값과 우리 보정값 사이 잔여 오차 가능
  - 실측 후 ahead로 들리는 정도/방향에 따라 옵션 (B) 수동 offset 슬라이더 추가 검토
- [ ] 엔진 레이턴시 보정값이 실제와 약간 차이 (에뮬 기준 ~10ms 오차) — 수동 보정 슬라이더 추가 예정
- [ ] 호스트 백그라운드 진입 시 파일 서버 연결 끊김 → 게스트 seek 시 404 (자동 재로드로 대응)
- [ ] 디버그 모드에서 호스트 플레이어 간헐적 스터터 (position이 실시간보다 느리게 진행)
- [ ] 호스트 파일선택 창 열고 있는 동안 게스트 입퇴장 시 안정성 (추가 테스트 필요)
- [ ] Android↔iOS 싱크 정확도 검증 — `_safeFileName` + iOS MethodChannel 적용 후 실측 필요
- [x] iOS 게스트가 한글/공백 파일명 URL 로드 실패 → `_safeFileName` 해시명으로 해결
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

**Play**: 메시지 전송 `{ hostTime, positionMs, engineLatencyMs }` → seek(현재position) → play()
**Pause**: pause() → 메시지 전송 `{ positionMs }`
**Seek**: 메시지 전송 `{ hostTime, positionMs, engineLatencyMs }` → seek(position)

> Play/Seek 모두 **broadcast 먼저, seek/play는 그 다음**. 게스트가 메시지를 받자마자 거의 동시에 seek를 시작하므로, 호스트와 게스트가 seek 비용을 대칭으로 치름. 게스트의 elapsed 계산에 자기 seek 시간이 포함되어 자연 상쇄. 이 순서를 뒤집으면 싱크가 깨진다 (commit c6123b6).
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

  diff < 100ms  → 무시
  diff >= 100ms → seek(expectedPosition)
```

**안전장치**:
- `_syncSeeking`: sync-position 보정 seek 진행 중 다음 sync-position 무시
- `_internalSeeking`: 내부 seek로 인한 buffering 전환을 buffering watch가 무시 (recovery 루프 방지)
- `_awaitingStateResponse`: 버퍼링 복구 시 state-request 중복 방지 (응답 오면 해제)
- `_commandSeq`: 빠른 재생/정지 반복 시 stale async 무효화
- `_reloadInProgress`: 동시 재로드 차단

##### 케이스 7: 재생 중 버퍼링 발생 후 복구 [C-2]

네트워크 지연으로 HTTP 스트리밍 버퍼가 비어서 재생이 멈췄다가 복구된 경우.

```
버퍼링 발생 → 재생 멈춤
버퍼 채워짐 → ready 전환 감지
  state-request → 호스트가 최신 상태 응답 → seek(보정position)
  (_awaitingStateResponse: 응답 대기 중 중복 요청 방지)
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
| 쿨다운 → _awaitingStateResponse | 2초 쿨다운은 정상 복구도 차단 → 응답 대기 플래그로 자연 스로틀링 |
| syncSeek도 broadcast 먼저 | syncPlay와 동일하게 시간 찍고 메시지 먼저 → seek (seek 비용 대칭화) |
| 임계값 100ms | 20→30→100ms로 단계적 상향 — seek 자체가 추가 버퍼링을 유발해서 너무 민감하면 오히려 싱크 흔들림 |
| `_internalSeek` 래퍼 | 내부 seek로 인한 buffering→ready 전환을 buffering watch가 자연 발생으로 오인하여 state-request 루프 도는 것 방지 |
| `_storedSafeName` ↔ `_currentFileName` 분리 | 디스크/HTTP 서빙은 ASCII-safe 해시명(iOS AVPlayer 호환), UI 표시는 원본 파일명 유지 |
| URL `?v=timestamp` | AVPlayer가 같은 URL을 캐시해서 이전 세션 데이터를 재사용하는 문제 방지 |
| `_handlePlay`/`_handleStateResponse`에서 reload 먼저 | 로그 출력 후 reload하면 reload 소요시간이 elapsed 계산에 누락됨. reload 후 elapsed 재계산 |
| sync-position 5초 간격 | 드리프트/지터를 주기적으로 잡되, 너무 잦으면 seek 과다 |
| bestRtt는 로그 전용 | offset 선택 기준으로만 사용, 이후 계산에 미사용 |
| 블루투스 레이턴시 | engineLatency에 미포함, 수동 슬라이더로 대응 예정 |

## 핵심 기술 설계 (v3) — 폐루프 리아키텍처 (설계 단계, 코드 미반영)

> **상태**: 설계 완료, PoC 시작 직전. 현재 코드(v2)는 그대로 유지되며, v3는 PoC 통과 후 단계적 통합. 이 섹션은 PoC와 본 구현의 단일 참조 지점이다 — 같은 토론을 반복하지 않기 위함.

### 배경: 왜 v3로 가는가

v2는 **개방 루프 (open-loop) 보정**:
1. 호스트가 "지금 X 위치에서 재생"을 알림
2. 게스트가 elapsed + engineLatency를 **계산**해서 보정 위치 산출
3. 그 위치로 seek + play

문제:
- **engineLatency 측정 한계**: Android `AudioManager.getProperty(OUTPUT_LATENCY)`가 S22에서 null, buffer duration만 잡혀 4ms 보고. iOS `AVAudioSession.outputLatency`는 실측과 차이 큼 (특히 Bluetooth)
- **계산 vs 실제 불일치**: 디코더 지연, GC, 스레드 스케줄링 등 측정 불가능한 변수 다수
- **결과**: v0.0.4 측정 시 17ms 잔여 비대칭. 일부 디바이스에서 더 큼. 드리프트 누적 위험.

v3는 **폐루프 (closed-loop) 보정**:
1. 게스트가 **자기 엔진의 실제 출력 시점**을 측정 (`getTimestamp` / `lastRenderTime`)
2. 호스트의 동일한 측정값과 비교 → 실측 drift 계산
3. drift를 보정 (seek 또는 rate 조정)

핵심 차이: **계산이 아니라 측정**. 측정 불가능한 변수도 측정값에 자동으로 녹아 있음.

### 1. 전략 선택: D (엔진만 네이티브)

| 전략 | 범위 | 평가 |
|---|---|---|
| A. 전체 네이티브 | 화면/P2P까지 전부 네이티브 | 가장 정밀, 가장 큰 비용. 기존 자산 폐기 |
| B. iOS만 네이티브 | iOS 우선 | 앱스토어 운영 비용 부담 |
| **D. 엔진만 네이티브** | 오디오 엔진만, 나머지 Flutter 유지 | 정밀도 거의 동일, 비용 최소 |

→ **D 채택**. Android 우선 (앱스토어 운영 비용 회피), iOS는 동일 패턴 반복.

### 2. 네이티브 엔진 선택

#### 2-1. Android: Oboe
- AAudio (API 27+) 자동 활용, OpenSL ES fallback
- `AAudioStream_getTimestamp(framePosition, nanoseconds)` 로 출력된 프레임의 정확한 시각 측정
- Google 공식, 활발히 유지, MediaCodec 디코딩과 결합 가능

**S22 Wi-Fi + Oboe glitching 리스크 검증**:
- 과거 Samsung WiFi 드라이버 인터럽트 disable → DSP underflow 이슈 (S10, Oboe issue #1178), Android 11에서 수정
- S22는 Exynos 2200, Android 12+ → 동일 이슈 가능성 낮음. Oboe Samsung Quirks wiki에 S22 항목 없음
- Fallback: MMAP off → PerformanceMode 낮춤 → buffer size 증가 → Oboe quirk 등록

#### 2-2. iOS: AVAudioEngine
- `engine.lastRenderTime` 으로 sample-accurate 출력 시각 측정
- `play(at: AVAudioTime)` 로 정밀 예약 재생
- `AVAudioFile`로 mp3/aac/m4a/alac 단일 API 디코딩

**iOS 주의점**:
- Bluetooth(AirPods 등) latency 부정확: `outputLatency` 보고값과 실측이 다름 (193~260ms 변동, 1분 내 변화 가능) → 수동 보정 슬라이더 필요
- `AVAudioEngineConfigurationChange` notification 처리 필수 (인터럽션 후 노드 재연결)

#### 2-3. FLAC: 미지원 (생략)
- `AVAudioFile`가 FLAC 지원 안 함
- 일반 사용자 거의 사용 안 함 (mp3/aac/m4a/wav로 충분)
- 추후 필요 시 별도 디코더 통합 검토

### 3. audio_service 플러그인과의 공존

`audio_service` (백그라운드 재생 / 잠금화면 컨트롤) + 커스텀 네이티브 엔진을 같이 쓸 수 있는가?

- audio_service 공식 README: `final _player = AudioPlayer(); // e.g. just_audio` — 주석에서 다른 player도 명시적으로 허용
- BaseAudioHandler는 player 추상화에 무관, 네이티브 엔진을 wrap한 커스텀 핸들러 가능
- iOS `AVAudioSession`은 audio_service 플러그인이 카테고리/활성화 관리, 네이티브 엔진은 같은 세션 위에서 동작
- Android는 layer 분리: `audio_session`(AudioFocus) / `audio_service`(ForegroundService) / `Oboe`(PCM stream)

→ **공존 가능, 통합 가능**

### 4. 측정 인프라 설계

폐루프가 동작하기 위한 5개 항목.

#### 4-1. 관측 데이터: `(framePos, deviceTimeNs)` 페어

- **framePos**: 방금 물리 스피커에서 울린 샘플의 인덱스
  - Android: `AAudioStream_getTimestamp(CLOCK_MONOTONIC, &framePos, &nanos)`
  - iOS: `engine.lastRenderTime.sampleTime`
- **deviceTimeNs**: 그 프레임이 출력된 시각 (로컬 CLOCK_MONOTONIC, ns)
  - Android: `getTimestamp`의 두 번째 파라미터
  - iOS: `lastRenderTime.hostTime` → `mach_timebase_info`로 ns 환산

**왜 이 페어가 최소 단위인가**: 시간 축과 샘플 축이 둘 다 있어야 디바이스 간 "같은 프레임이 언제 울렸나"를 비교할 수 있음. 엔진 레이턴시·DAC 지연 등이 페어에 자동 내포됨 (계산 불필요).

**트랙 포지션 변환**:
```
trackPosMs = anchor.trackMs + (framePos - anchor.framePos) * 1000 / sampleRate
```
앵커는 마지막 seek/play 시점에 갱신.

**PoC에서 검증할 잔가지**: framePos 리셋 규칙(stream stop 시 등), 첫 프레임 시각의 정의, 초기 getTimestamp 실패 처리.

#### 4-2. 관측 주기

- **로컬 관측**: 50-100ms (로컬 API는 저렴)
- **P2P 교환 (정상)**: 500ms-1s
- **P2P 교환 (재생 시작 직후)**: 100-200ms (초기 수렴)

근거: 일반 수정 발진기 드리프트 ±20-50 ppm = 1분당 1.2~3ms 누적. 청각 임계 ~20ms (Haas effect 기반) 도달 전 충분히 보정 가능.

#### 4-3. 교환 프로토콜: A + Drift Report 하이브리드

**방향 결정**:
| 옵션 | 장점 | 단점 |
|---|---|---|
| A. Host Push | 단순 (Snapcast/AirPlay 2 PTP 패턴), 지연 최소 | 호스트가 게스트 상태 모름 |
| B. 양방향 | 로깅/모니터링 풍부 | 트래픽 2배, 대부분 낭비 |
| C. Guest Pull | 네트워크 효율 | RTT가 정확도 깎음 (position 같은 동적 값엔 부적합) |

→ **A 기본 + Guest Drift Report 이벤트** 채택. PoC 분석 단계에 가시성 확보 + 운영 시 부하 최소.

**참고 레퍼런스**:
- Snapcast: Server Push (audio + timestamps) + Client 독립 clock sync, <1ms 편차
- AirPlay 2: PTP (IEEE 1588), 마스터 push, 디바이스 간 sub-25ms
- NTP vs PTP: NTP=Client Pull (정적 offset 추정 OK), PTP=Master Push (동적 sync 적합)

**핵심 통찰**: clock sync (정적)에는 Pull, position observation (동적)에는 Push가 자연스럽다. 이게 우연히 Snapcast 패턴과 일치.

**메시지 타입**:
- `audio-obs` (호스트→게스트, 평상시 500ms 주기 broadcast) — 신규
- `audio-drift-report` (게스트→호스트, 드리프트 임계 초과 시에만) — 신규
- `sync-ping`/`sync-pong` 유지 (clock offset용)
- `sync-position` 폐기 (audio-obs로 대체 — sync-position은 시각 축이 없어 정확 drift 계산 불가)

**페이로드 (audio-obs)**:
```json
{
  "type": "audio-obs",
  "seq": 1234,
  "hostTimeMs": 1712567890123,
  "anchor": { "framePos": 0, "trackMs": 30000 },
  "framePos": 88200,
  "playing": true
}
```

**페이로드 (audio-drift-report)**:
```json
{
  "type": "audio-drift-report",
  "seq": 42,
  "hostTimeMs": 1712567890123,
  "observedTrackMs": 30050,
  "expectedTrackMs": 30105,
  "driftMs": -55
}
```

**계층 정리**:
```
[Layer 1] sync-ping/pong   → wall clock offset (기존, 유지)
                ↓ 제공
[Layer 2] audio-obs        → 엔진 상태 + 시각 (신규)
                ↓ 소비
[Layer 3] drift 계산 + 보정
```

**앵커 갱신 규칙**: 평상시 같은 앵커, seek/play 직후 즉시 새 앵커 broadcast (늦게 도착하는 옛 측정값과 혼동 방지).

#### 4-4. 드리프트 계산: 호스트 obs 선형 보간

호스트 최근 obs 두 개 `(T1, P1)`, `(T2, P2)`, 게스트 관측 순간 `T_g` (`T1 ≤ T_g ≤ T2`):

```
expectedP_at_Tg = P1 + (P2 - P1) * (T_g - T1) / (T2 - T1)
drift = observedP_g - expectedP_at_Tg
```

재생 속도 일정 시 P는 T에 대해 선형 → 보간이 수학적으로 정확.

**왜 "앵커 + 이론 계산"이 아니라 "실측 보간"인가**:
- 앵커 기반 `expectedP(T) = P_anchor + (T - T_anchor)`는 클락 드리프트를 못 잡음 = **개방 루프 그 자체**
- 호스트 obs는 실측값이라 그 자체에 호스트 측 모든 지연이 녹아 있음
- 게스트가 실측값을 기준선으로 자기 실측과 직접 비교 → 진짜 폐루프

#### 4-5. 보정 실행: 계층적

| drift 크기 | 방법 | 비고 |
|---|---|---|
| **< 15ms** | 무시 (dead zone) | 측정 노이즈 zone |
| **15 ~ 50ms** | rate 조정 (1.025~1.05×) | 매끄럽게 수렴 (본 구현 단계) |
| **> 50ms** | seek | rate로 따라잡기 너무 느림, 갑작스런 점프 대비 |

**노이즈 원천 분해** (왜 임계값이 ms 단위인가):

| 원천 | 크기 | 네이티브가 해결? |
|---|---|---|
| 엔진 타임스탬프 정밀도 | <1ms | ✅ |
| Wi-Fi clock 동기화 오차 | 5-10ms | ❌ (네트워크 본질) |
| 네트워크 전송 지연 | 우회 가능 (obs에 발생 시각 박아 보냄) | - |
| 재생 하드웨어 지연 | ~0 (`getTimestamp`가 빼고 돌려줌) | - |

→ **병목은 Wi-Fi clock 동기화**. 네이티브 가도 이건 안 줄어. 실제 floor는 3-10ms 범위. dead zone 15ms는 보수적 출발값.

**임계값은 PoC 실측 후 확정**: 정적 상태에서 noise floor 측정 → dead zone = floor × 2 (oscillation 방지). 15ms가 빡빡/헐거우면 조정.

**보정 후 쿨다운**: 한 번 보정 후 최소 500ms-1s 대기 (oscillation 방지).

**PoC 단계 (rate 조정 생략)**:
```
< 15ms   → 무시
≥ 15ms   → seek
```

본 구현 단계에서 rate 조정 추가 시 위 3계층 활성화.

**clock sync 개선 기법** (필요 시 PoC 측정 후 적용):
1. Kalman filter — RTT 시계열 필터링, 튀는 값 자동 배제
2. ping 주기 ↑ — 30s → 5-10s
3. 샘플 수 ↑ — 10 → 20-30
4. 이상치 제거 — RTT 분포 기반 outlier 버림

### 5. Flutter ↔ 네이티브 인터페이스 (스켈레톤)

채널 분리:

| 채널 | 용도 |
|---|---|
| MethodChannel | 명령 (play/seek/pause 등 일회성 RPC) |
| EventChannel | 관측값 스트림 (지속 push) |

**왜 분리**: MethodChannel만 쓰면 Flutter가 50-100ms마다 polling 해야 함 → 폴링 자체가 노이즈 원천. 관측은 native 자발적 push가 정답.

**명령 API (예시)**:
```dart
abstract class NativeAudioEngine {
  Future<void> prepareSource({required String url});
  Future<void> play({int? atHostTimeMs});
  Future<void> pause();
  Future<void> seek({required int positionMs});
  Future<void> setRate(double rate);  // 1.0 = normal, 1.05 = 5% faster
  Future<void> dispose();
}
```

**이벤트 API (예시)**:
```dart
abstract class NativeAudioEvents {
  Stream<AudioObservation> get observations;
  Stream<PlaybackState> get stateChanges;
  Stream<AudioError> get errors;
}
```

**데이터 모델 (예시)**:
```dart
class AudioObservation {
  final int framePos;
  final int deviceTimeNs;
  final int anchorFramePos;
  final int anchorTrackMs;
  final int sampleRate;
  final bool playing;
}

enum PlaybackState { idle, preparing, ready, playing, paused, ended }

class AudioError {
  final String code;
  final String message;
  final bool fatal;  // recoverable vs 엔진 재초기화 필요
}
```

**설계 포인트**:
- **앵커는 native가 관리**, Flutter는 받기만 (play/seek 호출 시 native 갱신)
- **observation은 native 자발적 push** (Flutter polling 안 함)
- **`setRate`는 인터페이스에 미리 둠** (PoC에선 호출 안 하지만 본 구현 단계에 native만 구현 추가하면 됨)
- **에러는 fatal/recoverable 구분**

위 코드는 형태 예시. 최종 시그니처는 PoC 구현 중 조정 가능 — 빠진 메서드/필드는 그때 추가.

### 6. PoC 플랜

#### 6-1. PoC가 답해야 할 3가지

1. **네이티브 엔진 정밀도**가 정말 sub-ms인가
2. **Wi-Fi clock sync 노이즈**가 어느 수준인가 (5-10ms 가정 검증)
3. **폐루프가 진짜 수렴**하는가 (drift → 보정 → 안정 사이클)

이 3개에 답하면 본 구현 GO. 못 답하면 설계 재검토.

#### 6-2. 범위 (격리 원칙)

**PoC = 변수 하나만 실험**. 다른 모든 변수는 의도적으로 제외:

| 포함 | 제외 (본 구현 단계로 미룸) |
|---|---|
| Android Oboe 네이티브 엔진 | UI 폴리싱 |
| getTimestamp 폴링 + 로그 파일 | audio_service 플러그인 통합 |
| 최소 P2P (audio-obs, drift-report) | iOS (별도 task) |
| Drift 계산 + seek 보정 | rate 조정 |
| 광범위한 로깅 | 백그라운드 모드 |
| 호스트 1 + 게스트 1 | 멀티 게스트 |
| 로컬 파일 직접 재생 | HTTP 파일 전송 |

**왜 격리하는가**: 전부 다 넣으면 drift 원인 추적 불가능 ("sync 알고리즘 탓? 플러그인 충돌? HTTP 지연? 백그라운드?"). 좁게 잡아야 인과 분석 가능.

#### 6-3. 단계별 진행

| 단계 | 내용 | 출력/통과 기준 | 상태 |
|---|---|---|---|
| 0 | Oboe 래퍼 + 단순 재생 | "소리 나옴" 확인 | ✅ 2026-04-08 S22 통과 |
| 1 | getTimestamp 폴링 + 파일 로그 | (framePos, ns) 시계열 확보 | ✅ 2026-04-08 S22 통과 |
| 2 | P2P audio-obs 송수신 | 게스트가 호스트 obs 수신 | ✅ 2026-04-09 S22+S10 통과 |
| 3 | drift 계산 (선형 보간) + clock sync | drift 시계열 로그, 네트워크 지연 분리 | **다음** |
| 4 | seek 보정 + drift-report | 보정 전/후 비교 | 대기 |
| 5 | 정적 노이즈 측정 (재생 후 30s) | 실측 noise floor | 대기 |
| 6 | S22 30분 stress + 네트워크 블립 | 누적 drift, 글리칭 검증 | 대기 |

각 단계 끝에 로그 분석으로 통과 판정. 다음 단계 가기 전 측정값 확인.

**Phase 0~1 실측 결과 (2026-04-08, S22 SM-S901N, Android 16 API 36 arm64)**
- Oboe 설정: `LowLatency + Exclusive + Float + Stereo` → `sampleRate = 48000 Hz`
- `frames/ms = 48.00` — 48000/1000 정확 일치. HAL이 Flutter 레이어까지 내부 일관된 타임스탬프를 전달함
- `framePos` 단조 ✓ / `timeNs` (CLOCK_MONOTONIC) 단조 ✓
- `Timer.periodic(100ms)` + MethodChannel 폴링, ok 유효율 거의 100%
→ **PoC 6-1의 질문 1번 (네이티브 엔진 정밀도 sub-ms)에 긍정 답**. `(framePos, deviceTimeNs)` pair가 JNI→Kotlin→MethodChannel→Dart 경로를 거쳐 손상 없이 도달 확인.

**Phase 2 실측 결과 (2026-04-09, S22 SM-S901N Android 16 호스트 + S10 SM-G977N Android 12 게스트, 60.4s)**
- TCP 다이렉트(JSON over `\n`), 500ms 주기 broadcast, 총 122개 수신
- **seq 연속성**: gaps = 0 ✅ (유실/재정렬 없음)
- **호스트 송신 주기**: mean 498.8ms, stdev 13.2ms (Timer 매우 정확)
- **게스트 수신 주기**: mean 498.0ms, stdev 67.8ms (평균은 보존, 지터는 크다)
- **frames/ms = 48.0003** — Phase 1과 동일값, 60초 장시간 안정
- **rx-host offset**: mean 507ms, range 473~636 (clock offset + 네트워크 지연 혼재, 분리는 Phase 3에서)
→ **§6-1 질문 1 재확인** (sub-ms 정밀도 장시간 안정).
→ **§6-1 질문 2는 아직 미답** — 수신 지터가 5배 크다는 사실은 확인했으나, 이게 WiFi 노이즈인지 게스트 OS 스케줄링인지 분리 못함. `sync-ping/pong` 구현 필요.

코드: `poc/native_audio_engine_android/` (독립 Flutter 프로젝트, 본 앱과 세션 충돌 방지 위해 격리)

#### 6-4. 성공 기준

| 항목 | 목표 |
|---|---|
| 정적 noise floor | <10ms |
| 30분 보정 없이 누적 drift | <100ms |
| 보정 후 안정 시간 | <1초 |
| S22 글리칭 발생 빈도 | 분당 0회 |
| 글리칭 발생 시 복구 시간 | <2초 |

미달 시 → 어디서 막혔는지 로그로 진단 → 설계 재검토.

#### 6-5. 본 구현 단계 흐름 (PoC 통과 후)

```
1. PoC 코드 → audio_service 안으로 통합 (백그라운드/잠금화면)
2. 1:1 → 1:N 멀티 게스트 확장
3. 로컬 파일 → HTTP 전송 추가
4. rate 조정 추가 (UX 개선)
5. iOS 동일 패턴 반복
6. UI 폴리싱
```

각 단계 후 회귀 테스트.

### 7. v3 설계 결정 기록

| 결정 | 이유 |
|---|---|
| 네이티브 엔진(Oboe/AVAudioEngine) 도입 | just_audio + 플랫폼 채널로는 출력 시각의 sub-ms 측정 불가 |
| 전략 D (엔진만 네이티브) | 정밀도 거의 동일, 비용 최소 (UI/P2P/플러그인 재사용) |
| Android 우선 | 앱스토어 운영 비용 회피, iOS는 동일 패턴 반복 |
| Oboe 채택 (AAudio 직접 X) | AAudio + OpenSL ES fallback + Quirks 자동 처리 + Google 공식 |
| AVAudioEngine 채택 (AVAudioPlayer X) | sample-accurate 측정(`lastRenderTime`) + `play(at:)` 정밀 예약 |
| FLAC 미지원 | AVAudioFile 비지원, 일반 사용자 거의 안 씀 |
| 폐루프 (계산 → 측정) | 측정 불가능한 변수까지 자동 내포됨 |
| `(framePos, deviceTimeNs)` 페어 | 시간/샘플 양 축 모두 있어야 디바이스 간 비교 가능 |
| 호스트 Push + Guest Drift Report 이벤트 | 단순함 + 모니터링 가시성 동시 확보 (PoC 분석에 필수) |
| 선형 보간 (실측 기반) | 앵커 기반 이론 계산은 클락 드리프트 못 잡음 (개방 루프 회귀) |
| dead zone 15ms 출발값 | 측정 노이즈(5-10ms) × 2 + 청각 임계(20ms) 미만, PoC 측정 후 재조정 |
| seek 임계 50ms | 청각 임계와 정합. 갑작스런 점프 시 "긴 에코" 대신 "한 번 클릭"이 나음 |
| 보정 후 500ms-1s 쿨다운 | oscillation 방지 |
| MethodChannel + EventChannel 분리 | 명령 RPC와 관측 스트림은 본질이 다름. 단일 채널이면 polling 발생 |
| 앵커는 native 관리 | seek/play 시점에 native 내부 상태가 가장 정확 |
| sync-position 폐기, audio-obs 신규 | sync-position은 시각 축 없어 정확 drift 계산 불가 |
| sync-ping/pong 유지 | clock offset (정적)에는 Pull (NTP) 패턴이 적합 |
| PoC 격리 원칙 | 한 번에 다 만들면 원인 추적 불가, 한 변수씩 검증 |

### 8. v3 새 P2P 메시지 (요약)

| 타입 | 방향 | 페이로드 | 용도 |
|---|---|---|---|
| `audio-obs` | 호스트→게스트 | `seq`, `hostTimeMs`, `anchor`, `framePos`, `playing` | 호스트 엔진 실측값 broadcast (500ms 주기, 앵커 변경 시 즉시) |
| `audio-drift-report` | 게스트→호스트 | `seq`, `hostTimeMs`, `observedTrackMs`, `expectedTrackMs`, `driftMs` | 게스트가 임계 초과 drift 감지 시 보고 (이벤트성) |

기존 `sync-position`은 v3에서 폐기. `sync-ping`/`sync-pong`은 그대로 유지.

---

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
