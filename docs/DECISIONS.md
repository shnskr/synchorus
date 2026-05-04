# Synchorus 설계 결정 기록 (ADR)

v2/v3 주요 설계 결정과 그 이유. 신규 결정은 상단에 누적.

## v3 설계 결정

신규 결정은 표 상단에 누적. 시점은 결정 컬럼 끝 (vX.X.X)로 표기 — 같은 영역에 후속 결정이 더 들어왔으면 같이 묶음.

| 결정 | 이유 |
|---|---|
| Oboe stream sample rate mismatch 시 재생성 (v0.0.72) | v0.0.46 "정지/재생 시 stream 재사용으로 setup latency 0" 의도가 새 파일 sr이 다른 케이스를 누락. 첫 파일 44100Hz로 stream 열린 후 두 번째 파일 48000Hz 로드 시 stream 그대로 → 48000Hz 데이터를 44100Hz hw로 → **0.919배 속도 + 음정 1.5반음 down**. `start()`에서 `mStreamSampleRate != mDecodedSampleRate`이면 stop+close+reset 후 prewarmInternal_locked로 재생성. 양방향 mismatch(느려짐/빨라짐) 모두 처리. |
| anchor establishment 단일 진입 (v0.0.53) | `_tryEstablishAnchor`의 `seekToFrame(targetGuestVf)` + `_seekCorrectionAccum += initialCorrection` 블록은 1번만 호출. v0.0.48 롤백 시 v0.0.45 회복 코드 + v0.0.46 이후 코드가 합쳐지며 중복 발생 → `seekToFrame`은 idempotent라 위치는 같지만 accum이 두 배로 누적 → `_anchorGuestFrame`이 의도(`targetGuestVf`)보다 `+initialCorrection` 앞에 박힘 → vfDiff 베이크인 잔재(-3.6ms 등). 향후 anchor 로직 수정 시 **진입점 1개 원칙** 유지 |
| 1:N 멀티 게스트 전제 (v0.0.32, v0.0.54) | 같은 이름 peer가 다수 존재 가능. p2p 로직 작성 시 1:1 가정 금지. 호스트 stale peer 정리는 `name AND ip` 동시 매칭(LAN P2P는 NAT 없어 ip가 디바이스 유일 식별), 게스트 닉네임은 `<device model>#<hex 4자리>`(같은 모델 2대 이상 충돌 방지, `device_info_plus`). peer-joined/left broadcast는 절대 peerCount 동봉(메시지 누락 시 증감 drift 누적 방지). v0.0.32 도입 → v0.0.54 다중 게스트 입장 불가 버그 fix로 확장 |
| BT outputLatency 비대칭 anchor 베이크인 (v0.0.38) | 게스트와 호스트의 `outputLatency` 차이(BT 환경 ±50ms 가능)를 anchor 시 콘텐츠 정렬 seek에 베이크인 → framePos 기준 drift = 0으로 시작. 이후 `_recomputeDrift`는 (현재 outLatDelta − 앵커 outLatDelta) 변화분만 보정. `_anchoredOutLatDeltaMs` 필드. v3 폐루프 BT 안정성 핵심 |
| NTP 정공법 보류, 청감 우선 (v0.0.48) | v0.0.46(oboe pause/resume) + v0.0.47(NTP 예약 재생) + v0.0.49~v0.0.61 총 13번 시도 모두 청감 v0.0.45 baseline 미달 → main을 v0.0.48로 reset. 정공법 재도입은 `docs/SYNC_ALGORITHM_V2.md` 디자인 문서 합의 후 **단일 commit** 원칙(sequence number + race 제거 + outputLatency 자동 보정 통합). 즉흥 시도 금지 |
| 디바이스 발견은 nsd 라이브러리 (v0.0.41) | `multicast_dns` 폐기. 양방향 발견(호스트 자기 광고 + 게스트 호스트 발견 동시) 안정성 문제. iOS↔Android 호환성도 nsd 우수. mDNS stale 방 처리는 v0.0.42에서 found/lost 즉시 반영으로 fix |
| engineLatency 수치 폐기 (v0.0.33) | v3 `NativeAudioSyncService` + framePos 기반 폐루프에서 엔진 latency는 `oboe::getTimestamp()` / `AVAudioTime` 반환값에 이미 내포. 별도 보정값이 코드에 존재하지 않음. v2 잔재 `com.synchorus/audio_latency` MethodChannel을 양 플랫폼에서 제거 (Dart 호출 0건이었음). 새로 도입할 일 있어도 v3 폐루프와 별개 디버그용으로만 |
| 재연결 race 다층 방어 (v0.0.34 + v0.0.35) | onDisconnected(TCP) + connectivity_plus(WiFi) 두 경로가 거의 동시 발화 가능. v0.0.34 `if (!identical(_hostSocket, socket)) return;` onDone 가드(old socket의 onDone이 새 socket을 destroy하는 무한 loop 차단) + v0.0.35 `_reconnectInProgress` flag(`_handleDisconnected`/`_waitForWifiAndReconnect` 진입부 가드 — race 자체 예방). 두 층 동시 유지 — race 예방 실패해도 loop 차단이 받아줌 |
| StreamController add 전 isClosed 가드 (v0.0.31) | `dispose()`가 controller close 후 socket.onDone이 비동기로 늦게 도달 → 이미 close된 `_disconnectedController.add(null)` → `Bad state: Cannot add new events after calling close`. 모든 add 호출 위치에 `if (!_xxxController.isClosed) ...` 가드 필수 |
| `RoomLifecycleCoordinator` 클래스 추출 (v0.0.29) | `room_screen.dart`(830줄)에서 라이프사이클·재접속 watchdog·errno 분기·WiFi 처리·sync 트리거 분리 → `lib/services/room_lifecycle_coordinator.dart`(약 320줄). UI는 `ValueListenableBuilder<bool>(hostAway/hostClosed)` + 콜백 4개(`onLeaveRequested`, `onReconnectSyncRequested`, `onLog`, `onSnackbar`). 향후 라이프사이클 변경 시 한 파일만 수정. 추출 시 `mounted` 대신 `_disposed`/`_leaving` 자체 플래그로 가드 |
| errno 분기는 Linux+Darwin 집합 (v0.0.30) | POSIX errno 같은 의미라도 OS별 번호 다름. `ECONNREFUSED` Linux=111 Darwin=61, `EHOSTUNREACH` 113/65, `ENETUNREACH` 101/51. **단일값 하드코딩 금지** (v0.0.27이 Linux 111만 박아 iOS에서 fast giveup 동작 안 함 → v0.0.30 fix). 정의 위치: `room_lifecycle_coordinator._refusedErrnos = {111, 61}` / `_networkUnreachableErrnos = {113, 101, 65, 51}` |
| connectivity_plus + errno 이중 안전망 (v0.0.28) | iOS `connectivity_plus.onConnectivityChanged`가 200ms~수초 지연되거나 (제어센터 WiFi 토글 같은 일시 비활성화에서) 미발화. errno=113/101 잡히면 즉시 `Connectivity().checkConnectivity()` 확인 → WiFi 끊김이면 `_waitForWifiAndReconnect()` 조기 트리거. 기존 connectivity 이벤트 경로는 그대로 유지 (이중 안전망) |
| Socket connect timeout 5→2초 + errno=111 2회 연속 빠른 포기 (v0.0.27) | LAN 정상 connect는 수십 ms. 5초는 호스트 죽음 판정만 늦춤. 재생 전 호스트 강제 종료 시(detached 미도달) 60s+ watchdog → **~10초**로 단축. 카운터는 다른 errno(110/104/101)에선 reset(호스트 paused/일시 단절 같이 복구 가능 케이스 보호) |
| 호스트 detached에서 host-closed best-effort broadcast (v0.0.26) | Android foreground service가 detached 이벤트까지 Dart에 전달 → `broadcastHostClosedBestEffort()` (await 없이 broadcast + flush만). 재생 중 강제 종료 시 watchdog 2분 → **1.4초** 복구(실측 S22+A7 Lite). iOS 앱 스위처 종료는 detached 미도달 — 기존 watchdog가 fallback. 재생 전 종료(foreground service 없음)도 도달 확률 낮음 — watchdog 유지 |
| 호스트 라이프사이클 프로토콜 (v0.0.25) | 무한 재시도가 아닌 **명시적 종료 신호**. 메시지 3종 `host-paused`/`host-resumed`/`host-closed`. 게스트 측 자리비움 배너 + 5초 주기 재접속 watchdog (12회 ~2분 후 leave). 호스트 `AppLifecycleState.paused`가 실제 TCP abort보다 약 5초 먼저 도달 사실에 의존(실측). T1~T4 시나리오 5~10초 복구. 사용자 체감 "잠깐 뒤로 가기만 했는데 방 터짐" 해소 |
| v2 AudioSyncService 교체 (병행 X) | just_audio에 깊이 결합(780줄), 병행은 P2P/HTTP/파일 로직 중복, PoC 30분 ±20ms 검증으로 fallback 불필요 |
| SyncService in-place 업그레이드 (교체 X) | clock sync는 v2에서도 별도 서비스, v3 알고리즘은 상위 호환 (EMA 추가) |
| 게스트 파일 다운로드: dart:io HttpClient | 네이티브 엔진은 로컬 파일 경로 필요, http/dio 패키지 불필요, 새 의존성 없음 |
| 호스트 파일 서버: dart:io HttpServer 직접 (shelf 제거) | shelf_static 기본 동작이 작은 chunk 스트림 → throughput 저하. Content-Length + 1MB chunk 직접 구현으로 40~50% 개선, 의존성도 줄어듦 |
| 게스트 HTTP 다운로드는 main isolate 유지 (Isolate 분리 유보) | Dart single event loop 특성상 다운로드 CPU 작업이 heartbeat-ack 처리 지연시키지만, timeout 15초 완화만으로 체감 해결. Isolate 분리는 SendPort 직렬화/소켓 이동 불가 등 구조 변경 크고 현재 규모에선 수확 체감. 동시 게스트 수 증가 또는 다운로드 페이로드 더 커지면 재검토 |
| Android 파일 디코딩: NDK AMediaCodec 전체 메모리 디코딩 | 스트리밍보다 단순, 150MB 제한으로 ~5분 곡 커버. iOS는 AVAudioPlayerNode가 자체 스트리밍 |
| iOS 파일 재생: AVAudioPlayerNode + scheduleSegment | AVAudioSourceNode 수동 렌더링 대비 메모리/코드 최소, seek = stop→scheduleSegment→play |
| framePos는 네이티브에서 파일 rate로 정규화 | HAL은 hw rate(48kHz)로 카운트하지만 VF/sampleRate는 파일 rate(44.1kHz). Dart에서 하면 양쪽 rate를 알아야 하므로 C++/Swift에서 변환 |
| cross-rate 비교는 항상 ms 단위로 통일 | frame 직접 비교는 rate가 다르면 틀림. `frames / (sampleRate/1000)` → ms 변환 후 비교 |
| seek-notify는 absolute targetMs (deltaFrames 아님) | delta 기반은 비동기 seek 중첩 시 누적 오차 발생. absolute는 멱등(idempotent) |
| fallback은 isOffsetStable gate 없이 즉시 동작 | 초기 offset이 부정확해도 ±30ms 이상 차이만 보정하므로 대략 정렬에 충분 |
| virtualFrame/sampleRate는 파일 네이티브 레이트 기준 | 양 플랫폼 동일 단위로 Dart 서비스 레이어 단일화. 시간 변환: `ms = vf * 1000 / sampleRate` |
| 본체 앱 MethodChannel명 `com.synchorus/native_audio` | PoC(`com.synchorus.poc/native_audio`)와 구분. Android/iOS 동일 채널명으로 Dart 서비스 레이어 단일화 |
| iOS MethodChannel 인자는 Dart 원시값 직접 전달 | Android Kotlin(`call.arguments as Number`)과 동일 패턴. 딕셔너리 래핑 시 silent fail 위험 (b0415-7 버그) |
| iOS 출력 지연 = outputLatency + ioBufferDuration | Apple 포럼 합의. `outputPresentationLatency`는 ioBuffer 미포함. 노드 latency도 합산하되 보통 0 |
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


## v2 설계 결정

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
