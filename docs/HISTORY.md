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

### 2026-04-27 (44) — v0.0.49 NTP 예약 재생 정밀 재도입 (B 단계: NTP only, prewarm 제외)

**배경**: (43) v0.0.47 NTP 시도가 메시지 race + sequence ordering 부재 + 호스트 측 schedule 미적용 등 정밀 작업 부족으로 drift 60초 회귀 후 v0.0.48 롤백. 이번 세션은 한 줄기씩 (a)~(e) 항목 도입해 정공법 재진입. BT 워밍업 옵션 A는 분리해서 별도 측정 후 결정 (사용자 합의: B 먼저 → 측정 → 잔여 보고 A로).

**변경 내역**:

**(a) Sequence number 도입**:
- `_hostSchedSeq`(호스트, 단조 증가) / `_lastSeenSchedSeq`(게스트, 마지막 처리한 seq) 멤버 추가.
- `schedule-play` / `schedule-pause` 메시지 본문에 `seq: <int>` 필드.
- 게스트 `_isStaleSeq` 헬퍼 — 작은 seq는 stale로 무시, 큰 seq만 처리. 새 곡(`_handleAudioUrl`) 진입 시 `_lastSeenSchedSeq=null`로 리셋해 새 곡 첫 schedule 받기.
- 호스트는 새 곡에서도 `_hostSchedSeq` 그대로 유지(단조 증가 보장).

**(b) Race 완전 제거**:
- `_handleSchedulePlay`가 `_playing=true` + `_scheduleInProgress=true`를 `await scheduleStart` 전에 set. → 그 사이 `_handleAudioObs`가 `_scheduleFromObs` 호출 못 함.
- `_scheduleFromObs`도 `_lastSeenSchedSeq != null` 체크 → 호스트 schedule 받은 적 있으면 자체 외삽 호출 안 함 (호스트 권위 우선).
- `_handleAudioObs`에서 obs 기반 자동 start/stop 분기 완전 제거 — schedule 받은 게스트는 `obs.playing`으로 자동 전환 안 함. 합류 게스트(`_lastSeenSchedSeq==null`)만 `_scheduleFromObs` catch-up.

**(e) 호스트도 schedule 적용 (대칭)**:
- `syncPlay`: `_scheduleHostPlay` 헬퍼로 호스트 자기 `engine.scheduleStart(hostStartWallMs, fromVf)` 호출 + `schedule-play` broadcast. lead time 200ms 후 양쪽 동시 출력.
- `syncSeek`(재생 중): `cancelSchedule` + `_scheduleHostPlay(fromVf=clampedTarget)` — 양쪽 동시 점프. anchor reset 후 fallback drift edge case((42), 최대 -634ms) 근본 제거.
- `syncSeek`(정지 중): 기존대로 `engine.seekToFrame` + `seek-notify` broadcast (schedule 안 함).
- `syncPause`: `engine.cancelSchedule` + `schedule-pause` broadcast.
- 호스트 새 파일 로드 시(`loadFile`)도 `engine.cancelSchedule()`로 진행 중 schedule 정리.

**합류 게스트 catch-up 활성화**:
- `_handleAudioUrl` 마지막 (currentHostPlaying=true)에 `unawaited(_scheduleFromObs())` 호출. 이전 v0.0.48의 `_startGuestPlayback`(즉시 engine.start) 대체.
- `_scheduleFromObs`는 `obs.playing=true` + `_sync.isSynced` + `_lastSeenSchedSeq==null` 모두 만족 시 호스트 obs로 콘텐츠 위치 외삽 → 200ms lead로 자체 schedule. 다음 호스트 syncPlay/Seek 호출 시 더 정확한 fromVf로 보정.

**Reactive seek 정책**:
- v0.0.47에서 비활성화 후 v0.0.48 롤백 시 다시 활성화한 `_fallbackAlignment` / `_recomputeDrift` / `_maybeTriggerSeek` 그대로 유지. NTP는 첫 정렬, reactive는 잔여 drift 누적 보정. NTP 정확도 보면 reactive seek 발동 줄어들 것 (드물게 발동 시에도 청감 영향 미미).

**Dead code 제거**:
- `_startGuestPlayback` / `_stopGuestPlayback` 제거 — schedule 경로로 일원화. `_handleAudioObs`에서 obs 기반 자동 stop 분기도 제거됨.

**미적용 항목 (다음 세션 후보)**:
- (c) outputLatency 비대칭 자동 보정 — anchor에 베이크인된 outLatDelta는 v0.0.38 그대로. NTP 정확 시 잔여 outLat은 reactive seek가 잡아줄 것으로 기대.
- (d) Tab A7 Lite oboe pause/resume xrun 회피 — 변경 없음. NTP가 stream 시작 latency 자체를 lead time으로 흡수하므로 xrun 영향 줄어들 것 기대.
- BT 워밍업 옵션 A (사용자 합의로 분리).

**예상 효과**:
- 첫 재생 정착 시간 ~수 초 → 200ms lead 후 즉시 정렬 (engine.start 지연 + clock sync 수렴 흡수).
- 정지/재생/seek 매번 schedule → anchor reset 후 fallback drift edge case 근본 제거.
- BT 게스트도 호스트 schedule 시점에 출력 시작 (단 outputLatency 비대칭은 anchor 베이크인에 의존, 처음 ~40초 잔여 가능).

**미검증 / 측정 필요**:
- drift csv (S22 host + iPhone guest 또는 + Tab A7 Lite guest): v0.0.45/v0.0.48 baseline (1.21ms / 2.01ms) 동등 또는 개선?
- 첫 재생 정착 시간: 수 초 → 수백 ms?
- 정지/재생/seek 반복 시 (42) edge case 재현 여부.
- BT 게스트 (iPhone+버즈) 처음 40초 잔여 패턴 변화.
- Tab A7 Lite oboe `requestPause` xrun 영향 (v0.0.46 (43) 발견 항목).
- v0.0.47 1차 race(drift 38초) / 2차 race fix 후(63초) 회귀 재발 안 함 — 이번 세션에서 a/b/e 한꺼번에 적용했으니 다음 측정에서 회귀 시 bisect 어려움 위험.

**롤백 기준**: 측정 drift abs 평균이 v0.0.48 baseline (2.01ms) 대비 2배 이상 증가, 또는 60초 이상 max drift 발생 시 즉시 v0.0.48 동작으로 롤백.

**변경 범위**: `lib/services/native_audio_sync_service.dart` (NTP 호출 재활성화 + seq 가드 + 합류 catch-up), `pubspec.yaml` (0.0.48→0.0.49). native 파일(iOS/Android scheduleStart/cancelSchedule + JNI/Channel 핸들러)는 v0.0.47 인프라 그대로 유지.

---

### 2026-04-27 (45) — v0.0.50 시도 → v0.0.49 revert + v0.0.51 호스트 obs fresh fetch

**v0.0.50 시도 + revert**:
- (44) v0.0.49 측정에서 idx 86 (+55.7s) drift +48,449ms 단발 outlier 발견. 사용자 청감 인지 못 함.
- v0.0.50: `_handleSchedulePlay`에서 anchor 무효화 + `_latestObs=null` + 1초 cooldown으로 await yield window 차단 시도.
- 측정 (S22 host + Tab A7 Lite guest, 71 row, 48s): outlier max 48,449→156ms로 줄였으나 **+11~13ms systemic offset 회귀** + 사용자 청감 보고 "seek 연타 시 5초+ 어긋난 채 재생" 발생. csv에는 안 잡힘 (cooldown이 drift 계산 자체를 보류).
- v0.0.49 csv 재분석으로 같은 5초+ 어긋남 증상이 **이미 v0.0.49에도 있었음** 확인. drift_ms 공식이 anchor 기준 변화분만 보여 거짓말. 절대 frame diff (host_vf - guest_vf):
  - idx 53 +37.2s: **+5,036ms**
  - idx 87 +56.3s: **-55,686ms** (55초)
  - idx 89 +57.6s: +18,251ms (18초)
  - idx 111 +69.4s: **+117,963ms** (118초!)
- 결론: v0.0.50의 새 회귀 아니라 **v0.0.49(이전 모든 버전)부터 있던 본질 race**. v0.0.50의 cooldown이 오히려 fallback 보류로 csv 거짓말 + +13ms systemic offset 만들어 더 나쁨 → v0.0.50 revert.

**진짜 원인**:
- 호스트 syncPlay/syncSeek/syncPause 끝의 `_broadcastObs()`가 `_engine.latest`(100ms poll 캐시) 사용 → 캐시는 syncSeek 직후 새 vf 반영 안 된 stale 값일 수 있음.
- 게스트가 그 stale obs로 `_tryEstablishAnchor` 호출 → 게스트를 옛 host_vf 위치로 seek → anchor 베이크인. 이후 호스트 obs 새 vf로 갱신해도 anchor 기준이라 drift_ms는 작게 보임. **실제 음향은 옛/새 위치로 어긋난 채 유지**.

**v0.0.51 fix**: `_broadcastObs`를 `Future<void> async`로 변경, `_engine.latest` 캐시 대신 `await _engine.getTimestamp()`로 매번 native fetch. 호출처 3곳(syncPlay/syncPause/syncSeek 끝) `await _broadcastObs()`로 변경, `_startObsBroadcast` timer callback은 `unawaited(_broadcastObs())`. 매 호출 native 호출이지만 500ms 주기 + sync 이벤트 시 추가 — 부담 무시 수준.

**최소 변경 원칙**: 한 번에 한 가설만 검증. 다른 옵션(게스트 anchor sanity check, 호스트 syncSeek 직렬화)은 보류 — 측정 후 효과 부족하면 추가.

**예상 효과**: seek 연타 시 호스트가 항상 fresh host_vf로 broadcast → 게스트 anchor가 정확한 위치에 잡힘 → 어긋남 자동 회복. csv `host_vf - guest_vf` 절대 차이가 5~118초에서 100ms 이내로 줄어들 것 기대.

**미검증**: 다음 측정에서 seek 연타 패턴으로 frame diff 큰 어긋남 재현 안 됨 확인 필요.

**변경 범위**: `lib/services/native_audio_sync_service.dart` `_broadcastObs` async + 4 호출처 변경. `pubspec.yaml` (0.0.49→0.0.51, 0.0.50 skip — revert됨). 다른 코드 변경 없음.

---

### 2026-04-27 (46) — v0.0.52 virtualFrame 기반 sanity check 추가

**배경**: (45) v0.0.51 호스트 fresh `_broadcastObs` 측정 결과 idx 70~71 (1000~1001s, seek 연타 시점)에서 frame diff -146초→-144초→+48ms로 **2초 안 회복**되었으나 사용자 청감 "조금 틀어짐" 보고. csv `drift_ms`는 -3.8ms로 안정 보고했지만 frame diff(절대 콘텐츠 위치 차이)는 146초 어긋남 — `drift_ms` 공식이 framePos(HAL 단조 카운터) 변화율만 봐서 호스트 콘텐츠 점프 자체를 못 보는 구조적 한계. anchor가 잘못된 obs로 잡히면 이후 drift_ms는 작게 보이지만 실제 음향은 어긋난 채 유지.

**Fix (`_recomputeDrift`)**:
- driftMs 계산 후 virtualFrame 기반 `vfDiffMs` 별도 계산 (`guestVfMs - hostVfExpectedMs - currentOutLatDelta`)
- `vfDiffMs > 500ms` AND `driftMs < 50ms` (driftMs 거짓말 패턴) 시 anchor 강제 reset → 다음 poll에서 fresh obs 기반 `_tryEstablishAnchor`로 정확히 재정렬
- 무한 loop 방지: sanity fail 후 300ms 짧은 cooldown (다음 obs broadcast 도달 시간)
- sanity 발동 분석용 csv `event=vf-sanity` 기록 (`vfDiffMs`를 `driftMs` 자리에)

**미적용**:
- `_tryEstablishAnchor` 진입 sanity 보류 — 첫 anchor establish도 막을 위험. v0.0.51 호스트 fresh broadcast로 schedule 직후 fresh obs 도달이 빠른 것으로 기대.
- 호스트 측 `syncSeek/syncPlay/syncPause` 직렬화(B 옵션) 보류 — 이 fix(A)로 발생한 어긋남 자동 회복되면 충분. 측정 후 잔여 발생 빈도 보고 추가 결정.

**예상 효과**:
- frame diff 5~118초 어긋남 발생해도 **다음 obs(500ms) + 1 poll(100ms) 안에 자동 회복** (~600ms 이내)
- csv `drift_ms`와 frame diff 일치도 ↑ — `vf-sanity` 이벤트로 잘못된 anchor 케이스 명시 추적
- 사용자 청감 "잠깐 틀어짐"은 1초 안에 정렬되어 인지 부담 ↓

**미검증**: 다음 측정에서 (1) frame diff abs_max 1초 이내 확인 (2) `event=vf-sanity` 발생 빈도 확인 (3) drift_ms 안정 구간 baseline 동등 확인.

**변경 범위**: `lib/services/native_audio_sync_service.dart` `_recomputeDrift` 18줄 추가. `pubspec.yaml` (0.0.51→0.0.52). 다른 코드 변경 없음.

---

### 2026-04-27 (47) — v0.0.53 vf-sanity 조건 완화

**배경**: (46) v0.0.52 측정 결과 vf-sanity 1회 발동(+40s, vfDiff=108초→700ms 회복 PASS) 했으나 idx 60-61(+42.7s, fd=-8.4초) 어긋남은 sanity 조건 `drift < 50` 안 만족(drift_ms=99.8ms)해 미발동. idx 24(+18.9s, drift_ms=14,864ms / fd=-4838ms)도 같은 이유로 미발동 → _maybeTriggerSeek anchor reset 경로로 1.6초 회복. 사용자 청감 "후 …" 어긋남 인지.

**Fix**: `_recomputeDrift`의 vf-sanity 조건에서 `drift < 50` 제거. `vfDiff.abs() > 500ms`만으로 발동.
- 이유: vfDiff는 콘텐츠 위치 직접 차이라 `drift_ms` 값 무관하게 큰 어긋남 직접 진단
- 정상 구간 (vfDiff < 100ms)은 발동 안 함 → false-positive 없음
- _maybeTriggerSeek와 중복 발동 가능하나 둘 다 anchor reset이라 무해

**예상 효과**:
- v0.0.52에서 못 잡은 drift 50~200ms + vfDiff 큰 케이스도 잡힘
- 모든 drift_ms 거짓말 케이스 (anchor 잘못 잡힌 채 정렬 유지) 자동 회복

**미적용**: 호스트 측 syncSeek/syncPlay/syncPause 직렬화 (B 옵션). v0.0.53 측정 후 잔여 발견 시 추가.

**미검증**: 다음 측정에서 frame diff abs_max 1초 이내 + vf-sanity 발동 횟수 확인.

**변경 범위**: `lib/services/native_audio_sync_service.dart` `_recomputeDrift` 1줄 변경 (조건 단순화). `pubspec.yaml` (0.0.52→0.0.53).

---

### 2026-04-27 (48) — v0.0.54 obs.playing=false 안전망

**배경**: (47) v0.0.53 측정에서 사용자 정지/재생 + seek 연타 후 마지막 10초 frame diff 1.3초까지 누적. csv host_vf 분석 결과 idx 135-137 (98.6~99.7s) 호스트 vf=4656079로 **1.6초 정지**, 게스트만 계속 진행 → frame diff 누적. v0.0.49에서 `_handleAudioObs`의 `obs.playing=false` 자동 stop 분기를 stale obs 잘못 정지 우려로 제거한 게 안전망 사라짐.

**가설**: 사용자 연타 중 호스트 syncPause → schedule-pause broadcast했지만 게스트의 `_handleSchedulePlay`/`_handleSchedulePause`가 동시 진행 race로 stale seq 무시 → 게스트가 정지 신호 못 받음. 또는 메시지 처리 순서 비결정. v0.0.51 fresh `_broadcastObs` 도입으로 stale obs 위험은 줄어든 상태라 안전망 다시 추가 가능.

**Fix (`_handleAudioObs`)**: `_obsPlayingFalseStreak` 카운터 추가. obs.playing=false가 **2회 연속(~1초)** 도착하면 게스트 강제 정지 (`_engine.cancelSchedule`). 단발 stale obs로 잘못 정지하는 케이스는 streak 가드로 차단.

**유지**:
- 재생 방향(`obs.playing=true`)은 여전히 schedule-play 권위 — 합류 게스트만 `_scheduleFromObs` catch-up
- v0.0.51 호스트 fresh `_broadcastObs`로 stale 위험 줄어든 환경 가정

**예상 효과**:
- 호스트 정지 후 ~1초 안에 게스트도 정지 (schedule-pause 손실 안전망)
- frame diff 누적 1.3초+ 케이스 차단

**미적용**:
- 호스트 측 syncSeek/syncPlay/syncPause 직렬화 (B 옵션) — 측정 후 잔여 발견 시 추가
- 메시지 처리 큐 직렬화 — 큰 변경, 보류

**미검증**: 다음 측정에서 정지/재생/seek 연타 시 마지막 frame diff 100ms 이내 + `obs.playing=false streak` debug log 발동 빈도 확인.

**변경 범위**: `lib/services/native_audio_sync_service.dart` `_handleAudioObs` 분기 + 멤버 1개 추가 (~15줄). `pubspec.yaml` (0.0.53→0.0.54).

---

### 2026-04-27 (49) — v0.0.55 sanity 임계 강화 + 외삽 가드 + logger flush

**배경**: (48) v0.0.54 측정 결과 frame diff abs_mean **261ms** (사용자 청감 "안 맞음" 매칭). vf-sanity 0회 발동 — 임계 500ms 안 넘는데도 fd 250~948ms 일관 어긋남 발생. csv 분석:
- 첫 5초 fd +374→-16ms 정착 (정상 NTP 패턴)
- 5초 후 fd 다시 +250ms로 점프 후 일관 유지 (anchor establish 시 outputLatency 비대칭 잘못 베이크인 의심)
- vf-sanity 미발동 이유: obs 외삽 보정 후 vfDiffMs는 임계 미만 (1초+ 외삽 거리 부정확)
- v0.0.49 baseline (2.82ms) 대비 92배 회귀 — 사용자 정지/재생/seek 연타로 anchor 자주 reset → 매번 outputLatency 부정확 베이크인

**v0.0.55 fix (3가지)**:

1. **vf-sanity 외삽 시간 가드**: `obsAgeMs > 1000` 시 sanity skip + anchor reset (300ms cooldown). 외삽 거리 1초+면 hostVfExpectedMs 부정확해 vfDiffMs 거짓말 가능.

2. **vf-sanity 임계 500→200ms로 낮춤**: v0.0.54에서 fd 250~948ms 어긋남이 vfDiff 임계 안 넘어 미발동. 200ms는 청감 인지 시작점 + cooldown 300ms로 첫 정착 단계 false-positive 차단.

3. **logger flush 보장**: `clearTempFiles`에 `await _logger.stop()` 추가. 정상 _leaveRoom 흐름에서 cleanupSync 안 호출되니 logger.stop 누락됐던 케이스. 마지막 csv row 손실 방지. `cleanupSync` 자체도 async + await로 변경. `room_screen.dispose` 비정상 경로는 `unawaited(audio.cleanupSync())`.

**예상 효과**:
- 외삽 가드: host_vf 정체 1초+ 케이스에서 stale obs로 anchor 잘못 잡히는 거 차단
- sanity 임계 낮춤: fd 200ms+ 감지 빈도 ↑ → anchor reset → outputLatency 다시 측정 → 누적 정확도 ↑
- logger flush: csv 마지막 측정 row 보존

**잠재 위험**:
- 임계 200ms로 anchor reset 너무 자주 → 매번 같은 outputLatency 베이크인이면 무한 loop 가능 (cooldown 300ms는 막힘 보장). 다음 측정에서 vf-sanity 발동 빈도 + 청감 끊김 확인 필요.
- 만약 baseline outLatDelta 베이크인이 systemic 부정확하면 (양쪽 내장인데 +250ms 베이크 등), 임계 낮춰도 무한 loop. → 다음 fix 후보 (c) outputLatency 자동 보정 EMA 또는 베이크인 상한 cap.

**미적용 (다음 세션 후보)**:
- (c) outputLatency 비대칭 자동 보정 EMA — anchor establish 후 fd 측정으로 _anchoredOutLatDeltaMs 미세 조정
- 호스트 측 syncSeek/syncPlay/syncPause 직렬화 (`_hostOpInProgress` flag)
- 메시지 처리 큐 직렬화 — 큰 변경

**검토 결과 변경 불필요**:
- 호스트 측 `_engine.latest` 사용처 (syncPlay/syncSeek/_handleStateRequest): syncPlay는 이미 `await getVirtualFrame()` fresh, syncSeek는 안정 필드(sampleRate/totalFrames)만 사용, _handleStateRequest는 합류 게스트용으로 catch-up obs가 정밀

**변경 범위**: `lib/services/native_audio_sync_service.dart` (vf-sanity 가드 + 임계 + cleanupSync async + clearTempFiles logger.stop), `lib/screens/room_screen.dart` (unawaited cleanupSync), `pubspec.yaml` (0.0.54→0.0.55).

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
- [ ] **Logger csv 경로 접근성** (2026-04-24 (30) 신규, low priority). Android에서 `getApplicationDocumentsDirectory()`가 `/data/user/95/`처럼 multi-user 공간에 떨어지면 `run-as` 접근 불가. 실측 분석이 logcat buffer에 의존하게 됨. Android 한정 `/sdcard/Android/data/.../files/`로 저장 옵션 추가 검토.
- [ ] **Anchor reset 후 fallback 단계 큰 drift** (2026-04-26 (42) 신규, **HIGH priority**). 호스트 정지/재생/seek 시마다 게스트 측 anchor 폐기 → 5초 fallback 단계에서 외삽 부정확 → drift 최대 -634ms (0.6초 어긋남) 발견. Android 게스트 한정 stream open latency가 외삽에서 누락된 것이 직접 원인. v0.0.43 baseline에도 있던 이슈로 prewarm 회귀와 무관. **v0.0.46 oboe pause/resume + v0.0.47 NTP 예약 재생 둘 다 시도, v0.0.48에서 롤백 (HISTORY (43))**. 정공법 NTP는 다음 세션 정밀 작업 (sequence number + race 제거 + outputLatency 자동 보정)으로 재도입.
- [ ] **iOS 26.4.1 + macOS 26.3 환경 빌드 install hung** (2026-04-26 (43) 신규, mid priority). `flutter run --device-id <iPhone>` USB로 실행 시 "Installing and launching..." 단계에서 1~3분 hung. iPhone 잠금/신뢰 다이얼로그 OK인데도 발생. iOS 26 + Xcode toolchain 호환 이슈 추정. 다음 세션엔 **IntelliJ Run** 또는 **Xcode IDE에서 직접 Run** 권장 (CLI flutter run 대신).
- [ ] **Tab A7 Lite oboe pause/resume xrun** (2026-04-26 (43) 신규, low priority). v0.0.46 oboe stop을 `requestPause`로 변경 후 Tab A7 Lite에서 pause→resume 사이클마다 xrun + getTimestamp ErrorInvalidState 50~360ms 동반. S22는 정상. 저가형 HAL 한계로 추정. 회피 — pause 모델 대신 close + reset 사용 분기. 또는 NTP 정공법으로 우회.

**안정성**
- [x] ~~호스트 백그라운드 진입 시 파일 서버 끊김 → 게스트 seek 시 "404"~~ — v0.0.22(HTTP 서버 재구현) + v0.0.23(heartbeat timeout 15초) 이후 재현 실패. 실기기(S22 호스트 + iPhone + A7 Lite 게스트) 3기기에서 홈 버튼/파일 선택 창/다운로드 중 파일 선택 모든 경로 검증. 단일 원인 확정은 못 했고 두 변경의 합산 효과로 추정 (2026-04-22). **v0.0.25에서 프로토콜 메시지 + 자리비움 배너 + 주기적 재접속으로 근본 대응 완료.**
- [x] ~~호스트 파일선택 창 열고 있는 동안 게스트 입퇴장 시 안정성~~ — 위와 같은 조건에서 재현 실패 (2026-04-22). v0.0.25에서 호스트 라이프사이클 프로토콜로 명시적 처리.
- [x] ~~호스트 재생 전 paused 시 게스트 연결이 tcp abort로 끊겨 재접속 실패 → 방 폭파~~ — v0.0.25 host-paused/resumed + 주기적 재접속 watchdog로 해결. T1~T4 실기기 검증 완료 (Android 2대) (2026-04-22)
- [ ] 디버그 모드에서 호스트 플레이어 간헐적 스터터
- [ ] iOS 실기기에서 라이프사이클 시나리오(T1~T4) 재검증 — v0.0.25는 Android 2대로만 검증됨. iOS의 background audio 미활성 상태에서 paused 동작과 detached 이벤트 도달 여부 확인 필요
- [x] ~~**v0.0.27 errno=111 빠른 포기 실측 검증**~~ — 2026-04-24 (23)에서 S22+iPhone 조합으로 T4b 실측. **Darwin errno=61 미체크 버그** 발견 → v0.0.30에서 수정 → 재검증 ~10초 fast giveup PASS. W(게스트 WiFi off/on)는 일반 재연결 성공, errno=65/51 분기 재현은 추가 조건 필요 (WiFi 30초+ off 또는 AP 이동)
- [ ] W 시나리오의 errno=65/51(Darwin EHOSTUNREACH/ENETUNREACH) 분기 실행 캡처 — 2026-04-24 (23)에서 WiFi off 시간이 짧아 Socket.onDone 도달 전 WiFi 복구됨. 30초+ off 또는 호스트와 다른 AP 이동 시나리오 필요
- [x] ~~Peer count 불일치~~ — 2026-04-24 (25) stale peer 정리 + peerCount broadcast 포함으로 수정(v0.0.32). **2026-04-24 (27) S22+iPhone 실측 PASS** — 비행기 모드 on/off 반복 중 양쪽 2명 유지 확인
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
