# Synchorus 설계 결정 기록 (ADR)

v2/v3 주요 설계 결정과 그 이유. 신규 결정은 상단에 누적.

## v3 설계 결정

신규 결정은 표 상단에 누적. 시점은 결정 컬럼 끝 (vX.X.X)로 표기 — 같은 영역에 후속 결정이 더 들어왔으면 같이 묶음.

| 결정 | 이유 |
|---|---|
| 정렬 시계 도메인 = monotonic(BOOTTIME 계열) + Dart는 dart:ffi (설계 2026-06-05 (130), 구현 v0.0.115~ 예정) | 측정3 "wall 점프"(NTP 보정) root cause 제거. 현재 두 기기 정렬이 전부 wall 도메인(native가 monotonic `timeNs`를 갖고도 `oboe_engine.cpp:686`에서 일부러 wall로 역변환 — 호스트/게스트 monotonic epoch 불일치 회피용 "공통어"였으나 NTP 점프에 취약). **도메인 = BOOTTIME 계열**(deep sleep 면역): Android `CLOCK_BOOTTIME`(=7) / iOS `mach_continuous_time`(=`clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`). ⚠️ Darwin `CLOCK_MONOTONIC`은 sleep 포함이나 **NTP에 점프**(REALTIME offset, monotonic 보장 깨짐) → 금지, raw 계열 필수 — 1차 소스 교차검증(Apple QA1643/kernel docs, xcode man clock_gettime(3), Python bpo-42107). **핵심 제약 = 도메인 일치**: Dart FFI now()와 native getTimestamp timeNs가 같은 clock domain이어야 offset/anchor 외삽 성립. Android는 직접 일치(변환 0), iOS는 AVAudioTime.hostTime이 mach_absolute_time 고정이라 native에서 continuous 변환 + play(at:) 역변환. **Dart 읽기 = dart:ffi**(MethodChannel 비동기 왕복 지연 회피 → ping/pong t1/t3 정밀). 알고리즘(offset 식·anchor 외삽) 불변, clock 소스만 교체. 상세·실측 검증 항목: SYNC_REDESIGN.md (130). |
| 수익화 = 일회성 "프로" IAP, 구독❌·광고❌·자체서버❌ (2026-06-01) | **모델**: 무료 2대(호스트+게스트1 = 1:1 동기화 체험) / 프로 일회성 결제 시 무제한(3대+). **구독 안 함**: 유틸+로컬 동작 앱은 "정적 기능에 월정액" 저항 강함(2026 능동 해지율 31%→47%, 유틸 앱 일회성 회귀 트렌드) — 동기화는 "정해진 일 잘하는 도구"라 일회성이 맞음. **광고 안 함**: 재생 후 화면 안 봄(백그라운드)→배너 노출↓ 수익 미미 + AdMob/iOS ATT/개인정보처리방침 부담만. **자체 서버 안 함**: `in_app_purchase` non-consumable + `restorePurchases`(서버0, 클라 검증) 또는 RevenueCat(MTR $2,500까지 무료, Firebase 불필요 — anonymous App User ID 단독). 구독 갱신/해지 관리 복잡성 0. **시점**: 무료 먼저 출시(수익화 코드 0) → 반응 확보 후 추가. 가격(5,000~9,900원)·검증 방식(in_app_purchase 단독 vs RevenueCat)은 구현 시 결정. PLAN 수익화 전략 참조. |
| §G G-1 ring buffer 큐 모델 + EOS wait fix (v0.0.84) | v0.0.79 revert 후 PoC 격리(`poc/`)에서 재설계 검증 → 본 앱 합치기. **큐 모델 fix**: atomic 4개로는 단일 트랜잭션 안 보장이라 외부 `seekToFrame`은 `mDecodeSeekTarget` set만, ring head/tail은 decodeLoop 단일 thread에서만 갱신. PoC sine generator + 60s ring buffer + 자동 race test(50ms 주기 60회 큰 seek + 3초 모니터링)로 RACE 모드 25회 측정 race rate 25% (silent ratio 96.9~98.3%) → FIX 모드 17회 0% 차단. 본 앱 합치기 후 5분 측정 host_seek 330회 drift 0.00ms. **EOS wait fix**: v0.0.76 누락 — `while (!outputEos && !mDecodeAbort)` 조건은 곡 끝 도달 시 decode thread 종료, ring buffer 60s sliding window라 그 후 seek 불가 → 영구 무음 (5분 곡에선 vf 4분 10초 도달 시 자연 발화, behind 10s + ahead 50s 산식). 변경: `while (!mDecodeAbort)` + EOS 시 cv wait, seek 도착 시 `outputEos=false` 재개. **검증 패턴**: PoC 격리에서 race window 튜닝(chunk 4096 frames + sleep 40ms = 디코더 2배 빠름 + race window 40ms) + 토글 + logcat print로 객관 수치 25회 비교 → 본 앱 단일 파일 변경으로 회귀 면적 최소. HISTORY (95)/(100). |
| `_fallbackAlignment`에 `_seekCooldownUntilMs` 가드 추가 (v0.0.83) | HISTORY (98) 남은 문제 1번 fix. v0.0.82로 호스트 syncSeek 즉시 stale obs broadcast 차단했으나 정기 timer broadcast(500ms 주기) 안 잔존 stale obs로 가끔 몇 초 무음 발생. root cause: 호스트 큰 seek 직후 ~500ms 동안 게스트 `_latestObs`는 stale → fallback alignment가 stale obs로 옛 위치 잘못 seek → native PCM 디코드 wait → 무음. **Fix (1줄)**: `_fallbackAlignment`에 `_seekCooldownUntilMs` 가드 추가. 이미 `_tryEstablishAnchor`가 같은 cooldown 사용(line 1322) — fallback도 일관성. seek-notify 후 1초간 fallback skip, 호스트 정기 timer 새 obs 도달 후 정상. **v0.0.86 `_latestObs=null` 시도와 다른 안전성**: v0.0.86은 obs 객체 자체 무효화로 anchor에도 영향(원인 미상 신규 race 발생). v0.0.83은 fallback만 skip — anchor는 그대로 작동. 게스트 자체 보정만 영향, 호스트 측 영향 0. 실기기 N=여러 회 측정에서 무음 안 나타남 + 부작용 없음 확정. **패턴 학습**: "같은 cooldown 자료구조를 일관되게 적용" = 안전한 fix 패턴. |
| 호스트 syncSeek `_broadcastObs()` 제거 (v0.0.82) | HISTORY (98) 진단. 사용자 보고 "호스트 seek했는데 게스트가 새 위치 갔다 옛 위치로 돌아옴" + "vfDiff -250ms 영구 잔재". 사용자 핵심 통찰 "TCP는 순서 보장이라 게스트 받기 전 다른 명령 갔을 리 없잖아"가 진단 좁힘 — 메시지 race 아니라 호스트 측 race. **진짜 root cause**: `syncSeek` 안 `await _engine.seekToFrame(...)` 후 즉시 `_broadcastObs()` 호출. Android Oboe seek는 비동기(`mDecodeSeekTarget` set만, 즉시 return)라 그 시점 `_engine.latest` ts는 seek 처리 전 stale virtualFrame(이전 호스트 위치). 게스트가 그 stale obs 받으면 fallback alignment가 게스트를 옛 위치로 잘못 seek. **1줄 변경**: 호스트 `syncSeek` 안 `_broadcastObs()` 호출 제거. 정기 timer broadcast(500ms 주기)가 native seek 완료 후 정확한 obs 보냄. 사용자 청감 "괜찮음" + race 재현 안 됨 확정. 잘못된 시도 (accum 재계산 / `_latestObs=null` / fallback cooldown 가드) 모두 surface symptom fix였고 진짜 fix는 호스트 측 1줄. "복잡한 fix 여러 개"보다 "진짜 root cause 1개 격리"가 정답 — 사용자 통찰이 결정적. 남은 문제: 정기 timer 500ms 주기 안 stale obs로 가끔 몇 초 무음 (별도 트랙). |
| ANCHOR-VERIFY 사후 검증 + 자동 무효화 (v0.0.81) | HISTORY (96) v0.0.80 측정 마지막 부분 vfDiff -250ms 영구 잔재 발견. sync 자체는 정확하나 anchor 박힌 시점 매핑 부정확 → 청감 어긋남. 사용자 가설 "obs 순서 보장 안 됨" 코드 검토 결과 TCP 순서 자체는 OK이지만 게스트 측 seek 명령 처리 race가 진짜 root cause(큰 seek 연타 시 native seek 명령 처리 못 함). **사후 검증 디자인** 채택 — anchor 박힌 후 100ms 시점에 ts.virtualFrame이 targetGuestVf와 임계(500ms) 초과면 anchor 무효화 + `_seekCorrectionAccum` 되돌리기 + 다음 obs 도착 시 자동 재시도. 임계 500ms 근거: 평소 100ms 후 측정값 ~90ms (seek 도달 디코더 wait 정상)의 5배 안전 마진 → 정상 동작 영향 0, 사고(수십 초 잔재)만 잡음. 측정 검증: race rate 31% (anchor_set 29 중 9회 REJECT) 자동 회복 확정, 사용자 청감 사고 인지 0회. _seekCooldownUntilMs 자연 작동으로 즉시 재시도 폭주 방지. |
| §B clock sync outlier rejection + age limit + stable window 가드 (v0.0.80) | 사용자 환경 WiFi jitter 측정 결과 raw RTT > 30ms sample 비율 85% 발견. v0.0.79 알고리즘은 단발성 outlier는 흡수했으나 지속 흔들림 시 minSample이 jitter sample로 갈리고 EMA가 천천히 표류 (22초 18ms). 사용자가 "흔들리는 환경 수용하면 안 됨, wall clock 자체는 환경 무관" 지적 → adaptive 임계 부정, 고정 strict 임계 선택. **30ms 임계** = ping/pong 비대칭 노이즈 최악 ±15ms (RTT/2) → 청감 임계 ±20ms 안전 영역. **60초 age limit** = wall clock 상대 drift 누적 ±6ms 수준 (±50ppm × 60초 × 2 디바이스), stale offset 박힘 차단. **`_recentWindow.length >= 3` stable 가드** = carry over 1개만 남은 상태에서 anchor 박힘 false positive 차단. **`_prevFilteredOffset = roundOffset` 같이 carry over** = 첫 periodic sample stable 카운트 손해 (delta=|filtered-0|=큰 값) 제거, isOffsetStable 도달 6→5초 단축. 측정 검증: filtered 표류 18ms → 0.3ms (60배 감소), 사용자 청감 "대체적으로 다 좋음". 1단계 한계: 1시간 jitter 환경에서 carry over expire → window 빈 상태 → filtered 동결 (drift 누적 위험). 2단계 burst 재실행 fallback은 후순위 (우리 환경에선 거의 발생 안 함). |
| §G-2 Ready-then-Go 시도 후 revert + 재시도 전제 (v0.0.78) | v0.0.77에서 Dart `_ReadyCollector` + native `isFrameRangeReady` JNI + `audio-prepare`/`audio-ready` 메시지 흐름으로 G-2 구현. 실기기에서 호스트 큰 seek 직후 무음 정지 → 새 음원 loadFile만 fix. fix 시도 2번(원래 + `seekToFrame`이 ring head/tail 미수정) 모두 stuck 미해소 → decodeLoop 멈춤 강한 신호. atomic 만으로는 ring head/tail/seek target/cv wait 4개 상태 전이 안전 X. **재시도 전제**: ring buffer 상태(`mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts`)는 decodeLoop 단일 thread에서만 set, 외부(`seekToFrame`/`start`)는 atomic write 금지 → 요청 큐 push + cv notify만 허용. 또는 G-2 자체를 native 안으로 흡수(Dart는 prepareSeq + scheduleStart 통신만). 핵심 회귀 모드(호스트 무음 + loadFile만 fix) 재현 unit test 또는 자동화 시나리오 먼저 확보. v0.0.78에서 v0.0.77 코드만 revert(G-1 ring buffer 유지). |
| §G-1 PCM ring buffer 시도 후 revert (v0.0.76 → v0.0.79) | v0.0.76에서 Android 사전할당 PCM 전체 디코딩 → 60s sliding window ring buffer 도입(`mRingHead`/`mRingTail` atomic + `mRingMutex`/`mRingCv`). 큰 seek 슬라이더 **연타** 시나리오에서 호스트/게스트 둘 다 무음 회귀(`virtualFrame`은 흐름, PCM read만 무음). v0.0.75 비교 실험(`oboe_engine.cpp` 한 파일 checkout)에서 ring buffer 없을 땐 무음 없음 → race 확정. 4개 atomic(`mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts`)으로는 "seek 요청 → ring reset → decodeLoop 응답" 단일 트랜잭션이 안 보장. v0.0.79에서 `oboe_engine.cpp` 한 파일만 v0.0.75 코드로 복귀. ring buffer 효과(51분 곡, ~11.5MB constant, 2~3배 디코드)는 잃지만 안정성 우선. **재설계 전제**: ring buffer 상태는 decodeLoop 단일 thread에서만 set, 외부는 요청 큐 push + cv notify. **PoC 격리(`poc/`)로 자동화 연타 시나리오 + 회귀 재현 → fix 검증 → 본 앱 합치기** 패턴 권장 (HISTORY (95) 참고). 기존 row "Android 파일 디코딩: NDK AMediaCodec 전체 메모리 디코딩"은 다시 현행. |
| 게스트 식별은 영속 deviceId(UUID) (v0.0.73) | v0.0.54 `<model>#<microsecond hex 4>` + name+IP stale 매칭은 같은 모델 2대가 같은 microsecond에 join 시 충돌하는 1/65536 코너 잔존 → PLAN HIGH-1 검증을 "같은 모델 2대 환경"으로 제한. `Random.secure()` 16바이트 hex(2^128)를 SharedPreferences `device_uuid`에 영속 → join 메시지 `data.deviceId` 동봉 → 호스트 stale 매칭을 deviceId 단독 비교로 단순화. 같은 모델 충돌 0, 같은 디바이스의 앱 재시작 후 재접속도 정확 식별. 표시명(`name`)은 UI 전용으로 분리(`<device model>` 그대로). 자동 측정 게스트도 같은 SharedPreferences 키 공유. `uuid` 패키지 안 씀(`Random.secure` + hex로 동등 entropy). |
| Oboe stream sample rate mismatch 시 재생성 (v0.0.72) | v0.0.46 "정지/재생 시 stream 재사용으로 setup latency 0" 의도가 새 파일 sr이 다른 케이스를 누락. 첫 파일 44100Hz로 stream 열린 후 두 번째 파일 48000Hz 로드 시 stream 그대로 → 48000Hz 데이터를 44100Hz hw로 → **0.919배 속도 + 음정 1.5반음 down**. `start()`에서 `mStreamSampleRate != mDecodedSampleRate`이면 stop+close+reset 후 prewarmInternal_locked로 재생성. 양방향 mismatch(느려짐/빨라짐) 모두 처리. |
| anchor establishment 단일 진입 (v0.0.53) | `_tryEstablishAnchor`의 `seekToFrame(targetGuestVf)` + `_seekCorrectionAccum += initialCorrection` 블록은 1번만 호출. v0.0.48 롤백 시 v0.0.45 회복 코드 + v0.0.46 이후 코드가 합쳐지며 중복 발생 → `seekToFrame`은 idempotent라 위치는 같지만 accum이 두 배로 누적 → `_anchorGuestFrame`이 의도(`targetGuestVf`)보다 `+initialCorrection` 앞에 박힘 → vfDiff 베이크인 잔재(-3.6ms 등). 향후 anchor 로직 수정 시 **진입점 1개 원칙** 유지 |
| 1:N 멀티 게스트 전제 (v0.0.32, v0.0.54, v0.0.73) | 같은 이름 peer가 다수 존재 가능. p2p 로직 작성 시 1:1 가정 금지. v0.0.73부터 호스트 stale peer 정리는 영속 `deviceId`(UUID) 단독 매칭으로 단순화 — name/IP 비교 폐기. 게스트 표시명은 `<device model>` 또는 iOS 사용자 설정명(UI 전용, 충돌 무관). peer-joined/left broadcast는 절대 peerCount 동봉(메시지 누락 시 증감 drift 누적 방지). v0.0.32 이름 기반 도입 → v0.0.54 name+IP로 보강 → v0.0.73 deviceId 영속화로 같은 모델 코너까지 0. |
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
| Android 파일 디코딩: NDK AMediaCodec 전체 메모리 디코딩 | 스트리밍보다 단순, 150MB 제한으로 ~5분 곡 커버. iOS는 AVAudioPlayerNode가 자체 스트리밍. **v0.0.76 §G-1에서 ring buffer로 시도했으나 race로 v0.0.79 revert 후 본 결정 다시 현행 (표 상단 §G-1 row 참조)**. |
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
| 게스트 loadFile 후 transpose/speed 재적용 (v0.0.103) | native loadFile이 cents/speed를 0/1000으로 강제 reset(안전망, `oboe_engine.cpp:205-208`/iOS `AudioEngine.swift:38-41`)하므로 호출 측이 재적용해야 함. 다운로드 *전* 적용은 reset에 덮임 → 늦게 합류 게스트가 호스트 speed 상실(v0.0.93 reset 안전망 도입 시 회귀). HISTORY (120) |
| vf 외삽엔 speed 반영, framePos 외삽은 그대로 (v0.0.104) | speed≠1.0 시 호스트 vf는 wall당 speed배 진행(`oboe_engine.cpp:834,851`)하나 게스트 외삽이 1배속 가정 → anchor가 뒤처진 위치에 박혀 vfDiff 잔재(2배속 실측 -107ms). vf 외삽 3곳(anchor `hostContentFrame`/fallback/`vfDiffMs`)에 `speedFactor=obs.speedX1000/1000` 곱. **framePos 외삽(driftMs)은 HAL DAC 카운터라 speed 무관 wall rate → 자동 상쇄, 곱하면 오히려 깨짐.** HISTORY (120) |
| vfDiff(절대 위치)로 re-anchor + speed 정규화 (v0.0.111) | driftMs(framePos rate)는 두 폰 속도가 같으면 0이라 **절대 위치 어긋남(거짓말 패턴: anchor가 잘못 박혀 rate는 맞는데 위치는 틀림)을 못 잡음.** 맥북 마이크 acoustic 측정으로 vfDiff가 실제 스피커 시차임을 확정(465ms 일치) → vfDiff가 진실, framePos/drift가 거짓이었음. `_vfDiffSamples` 중앙값 >150ms 시 anchor 리셋. vfDiff는 콘텐츠 위치 ms라 **실제 청감 어긋남 = vfDiff/speedFactor**로 정규화 후 비교(임계가 speed 무관 일관: 0.5배 콘텐츠150=실제300ms). HISTORY (123) |
| SoundTouch latency를 outputLatency에 반영 (v0.0.112) | transpose/speed ON 시 vf(보고 위치)는 콜백이 즉시 진행하나 PCM은 SoundTouch(TDStretch+RateTransposer)+worker batch 거쳐 수백 ms 뒤 DAC 도달 → HAL outputLatency만으론 P2P anchor 정렬 부정확(SYNC_REDESIGN 결함 B). worker가 `SETTING_INITIAL_LATENCY`(SoundTouch.cpp:453, rate 의존 정확 frame)로 갱신, `getLatestTimestamp`가 useST일 때 (INITIAL_LATENCY+batch)를 가산. **양쪽 동일 speed면 outLatDelta에서 상쇄(무해), 비대칭(전환/합류/한쪽만 ON)에서 정렬.** 정적 항만(out-ring 동적 점유는 anchor 출렁임 우려 제외). HISTORY (125) |
