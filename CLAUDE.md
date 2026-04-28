# Synchorus

여러 핸드폰을 동기화된 스피커로 만드는 Flutter 앱 (P2P).

## 현재 단계
v3 본 구현 진행 중. **현재 main = v0.0.52 (v0.0.48 알고리즘 + csv 보강 + 진단 컬럼)** — 2026-04-28 세션에 v0.0.51~v0.0.55 그룹 1 + D-1 시도 후 v0.0.55 회귀 → v0.0.50 reset. 그 후 syncSeek debounce 단독 시도 → 사용자 청감 차이 X → 롤백. 마지막으로 v0.0.52 진단 컬럼 4개 추가 (sync 동작 변경 0). 상세: `docs/HISTORY.md` (45)/(46)/(47)/(48)/(49).

**v0.0.52 = v0.0.48 알고리즘 + 측정 도구 강화** (sync 동작 변경 0):
- v0.0.49: `vf_diff_ms`, `host_obs_wall` 컬럼
- v0.0.50: `seq`, `guest_wall`, 호스트/게스트 이벤트 로깅 (11종)
- v0.0.52: `out_lat_host_raw`, `out_lat_guest_raw`, `out_lat_delta_current`, `out_lat_delta_anchored` 컬럼

**v0.0.52 측정값** (S22 host + Tab A7 Lite guest):
- **idle 3분 20초**: drift abs mean 5.80ms, **vfDiff signed -3.60ms** (매우 정확)
- 호스트 outputLatency 8.20ms / 게스트 22.98ms / 차이 14.78ms 정확 베이크인 (베이크인-current 차이 0.06ms)
- **사용자 청감**: idle "초반 1~2초 + 잘 맞음", burst "나쁘지 않음" (v0.0.48과 동일)
- 알려진 잠재 한계 (알고리즘 자체):
  - 거짓말 패턴 — vfDiff 보정 메커니즘 없음, 환경 따라 -20ms+ 잔재 가능 (단 청감 미인지 영역)
  - (42) Android 게스트 fallback drift edge case
  - (47) Tab A7 Lite 호스트 framePos vs vf 비대칭 (정상 사용 패턴엔 영향 작음)

**다음 세션 후보 (우선순위)**:

1. **csv 측정 정확도 개선** (HIGH) — 사용자 활동 중 vfDiff 외삽이 진짜 어긋남보다 부풀려 측정할 가능성 ((48)에서 발견). 외삽 알고리즘 보강 또는 acoustic loopback ground truth 도입. 알고리즘 변경 없이 측정 도구만.

2. **v0.0.51 그룹 1 fix 중 가장 안전한 것만 선택 cherry-pick** — 호스트 cooldown debouncing은 race 차단 효과 + 새 race도 적었음. 단 게스트 큐 + EMA + D-1 등은 위험성 노출됨. 단순 호스트 cooldown만 단계 적용 검토.

3. **30분+ 장시간 idle 측정** — rate drift 누적 검증 (4분만 측정).

4. **iOS host 환경 검증** — Mac 환경 필요. v2 그룹 1 핵심 fix는 OS 무관이지만 미세 차이 검증.

5. **BT 환경 검증** — BT outputLatency 비대칭 + EMA 학습 상호작용.

6. **다중 게스트 (1:N)** 검증 — 1대1만 검증.

7. **(47) Tab A7 Lite 호스트 framePos 비대칭** — D-1으로 시도했으나 회귀 발생, 보류. 호스트 측 framePos 정규화 (네이티브) 또는 다른 방향.

8. **acoustic loopback 외부 측정** (선택, 검증 도구) — OS outputLatency 부정확 ground truth. 정확도 검증 + 알고리즘 재설계의 진짜 척도.

9. **환경 이슈** — iOS 26.4.1 + macOS 26.3 Tahoe `flutter run` install hung (이전 환경). IntelliJ Run 또는 Xcode IDE 권장.

**핵심 학습 (2026-04-28 세션 종합)**:
- **사용자 청감 검증 > csv 수치 검증** — csv는 측정 한계 있음 (사용자 활동 중 외삽 부정확 가능성). 진짜 사용자 경험은 청감.
- **알고리즘 변경의 위험 = 새 race 도입** — v0.0.51 debounce 도입 → 자동 정지 race + 끝 도달 race (v0.0.53/54 fix 필요), v0.0.55 D-1 → vfDiff 23배 회귀. 단순한 알고리즘이 안전.
- **csv 보강은 안전한 추가** — v0.0.49/v0.0.50처럼 측정 도구만 추가하는 작업은 회귀 위험 0.
- **단순성의 가치** — 검증 깊은 단순 알고리즘이 복잡한 측정상 우수 알고리즘보다 출시 안전.
- **권한 시스템 + git Safety Protocol 가치** — destructive 작업에 명시 동의 단계가 사용자 의도 정확히 확인 + 데이터 손실 방지.
- **사용자 좌절 = 신호** — "퇴보하는 것 같다" 우려 정당. 자존심 X, 정직한 평가 + 안전한 baseline 선택.
- **이전 (44)와 같은 패턴** — 알고리즘 재설계 → race → 좌절 → 단순 baseline 복귀. (44) v0.0.48 reset과 동일한 결말. **알고리즘 변경 시 청감 검증 깊이가 결정 척도**.

### 다음 세션 작업 흐름 (강제)

이번 세션처럼 "fix 시도 → 측정 → 회귀 → 또 fix" trial-and-error 사이클 반복 회피.
**대신 디자인 문서 먼저 작성 후 합의된 명세대로 한 번에 구현**.

순서:

1. **csv 측정 인프라 강화** (단순 작업, 진단 도구) — sync 동작 변경 0
2. **디자인 문서 작성** (`docs/SYNC_ALGORITHM_V2.md` 신설) — 코드 X
3. **사용자 합의** — 디자인 명세 검토
4. **한 번에 단일 commit으로 알고리즘 구현** — 명세 따라 단순 변환
5. **측정 검증** (idle + 사용자 연타 환경 분리)

#### 디자인 문서에 명문화할 결정 사항 (코드 작성 전 합의 필수)

A. **두 측정값 결합 규칙**
- `drift_ms < ?` AND `vfDiff < ?` 면 정상 (임계 결정)
- `vfDiff > ?` AND `drift_ms < ?` 거짓말 패턴 시 액션: anchor 무효화? 게스트 강제 reseek? 어느 우선?

B. **outputLatency 보정 메커니즘**
- 베이크인 (anchor 시점 1회) vs EMA (점진 수렴) vs cap (상한 제한) 어느 조합?
- anchor reset 시 EMA 누적값 보존 여부 (v0.0.60 한계 회피)

C. **rate drift 1% 보정**
- 주기 강제 reseek (vf-correction 100ms 임계, v0.0.58 시도)
- native sample rate 조정 (oboe setSampleRate?)
- virtualFrame 진행 속도 보정 (게스트 측 rate match)

D. **anchor 분리 여부**
- 현재: anchor 1개 (framePos + virtualFrame 동시점)
- 분리 안: rate anchor (framePos 기준, 거의 reset X) + position baseline (virtualFrame 기준, 절대 정렬)
- 둘이 어떻게 상호작용 (한쪽 reset 시 다른 쪽 영향?)

E. **임계 정확 값**
- drift_ms 정상 임계: 5ms? 10ms? 20ms?
- vfDiff 정상 임계: 30ms? 50ms? 100ms? (사용자 청감 미인지 한계)
- 비정상 시 어느 액션 단계 (작은 보정 / anchor reset / 강제 seek)

F. **race 차단 메커니즘**
- 호스트 측: syncPlay/Pause/Seek FIFO 큐 (마지막-이김 X — v0.0.59 회귀)
- 게스트 측: 메시지 처리 순차화 (`_handleSchedulePlay`/`Pause`/`AudioObs` 동시 진행 차단)

#### 디자인 문서 작성 요령

각 결정 사항마다:
- **선택지 (예 3가지)** — 각 옵션 장단점
- **race 시나리오 시뮬레이션** — 사용자 연타 시 어떻게 동작하는지 예상
- **검증 방법** — 측정 어떤 컬럼/이벤트가 결과로 나올지 미리 명시
- **합의된 결정** — 사용자 검토 후 확정

이 디자인 문서가 다음 세션 첫 commit이어야 함. 코드는 그 후.

**Backup branch**: `backup-v0.0.61-session` — v0.0.49~v0.0.61 commit 13번 모두 보존. 다음 세션에 `git log backup-v0.0.61-session --oneline`으로 시도 흐름 확인 가능.

- **Step 1-1 ~ 1-4**: 완료 (네이티브 엔진 이식 + Dart 서비스 + P2P/clock sync/drift 보정 + 백그라운드 재생)
- **Step 2 멀티 게스트**: 실기기 3대(S22 + iPhone 12 Pro + Galaxy Tab A7 Lite) 동시 테스트로 검증됨. 코드 변경 없이 1:N 동작
- **Step 3 HTTP 전송**: 완료 (v0.0.22에서 shelf 제거, dart:io HttpServer 직접 + 1MB chunk)
- **호스트 라이프사이클 프로토콜**: v0.0.25 추가 — `host-paused`/`host-resumed`/`host-closed` + 게스트 주기적 재접속 + watchdog. T1~T4 Android 검증 완료 (2026-04-22). v0.0.29 coordinator 추출 후 T1~T4a 재검증(S22+Pixel 6 에뮬, 2026-04-24). **v0.0.30에서 Darwin errno 버그 수정 + T4b 실측 PASS (S22+iPhone ~10초 fast giveup)**

v2 AudioSyncService 삭제됨 — NativeAudioSyncService로 교체. audio_handler.dart: NativeAudioHandler.

### 최근 해결 (2026-04-22)
- v0.0.20: seek-notify 가드(`!_playing`→`!_audioReady`) + 태블릿 가로모드 UI 스크롤
- v0.0.22: HTTP 서버 재구현 (shelf 제거 + Content-Length + 1MB chunk) + 다운로드 측정 인프라 (`download-report` P2P 메시지)
- v0.0.23: heartbeat timeout 9→15초. 다운로드 중 끊김 해결
- v0.0.25: **호스트 라이프사이클 프로토콜** (host-paused/resumed/closed) + 게스트 자리비움 배너 + 주기적 재접속 Timer + watchdog(12회/~2분). drift 노이즈 완화(C: 중앙값, A: clock sync window 10). 상세: `docs/LIFECYCLE.md`의 "앱 라이프사이클 / errno / 연결 복구 전략" 섹션
- v0.0.26: **detached에서 host-closed best-effort broadcast** — 재생 중 호스트 종료 시 게스트 복구 2분 → **실측 1.4초 확인** (S22 + A7 Lite). 재생 전 종료 / iOS 강제 종료는 detached 미도달 가능성 있어 watchdog fallback 유지
- v0.0.27: **Socket.connect timeout 5→2초** + **errno=111 2연속 → watchdog 빠른 포기** (재생 전 호스트 종료 / iOS 강제 종료 fallback ~2분 → ~10초 이론값). 실측 검증은 다음 세션. 상세: `docs/HISTORY.md` 2026-04-23 (19)
- v0.0.28: **errno=113/101 + connectivity_plus 연동** — WiFi 변경·AP 변경 시 connectivity 이벤트 늦어도 errno로 조기 감지 → `_waitForWifiAndReconnect` 즉시 트리거. 라이프사이클·연결 후보 6개 중 5개 완료. 상세: `docs/HISTORY.md` 2026-04-23 (20)
- v0.0.29: **`RoomLifecycleCoordinator` 추출** — `lib/services/room_lifecycle_coordinator.dart` 신설. `room_screen.dart`(828줄) 라이프사이클·연결 로직 약 320줄을 별도 클래스로 분리. UI는 `ValueListenableBuilder` + 콜백만. 라이프사이클·연결 후보 6개 모두 완료, Phase 4 라이프사이클 영역 종결. 상세: `docs/HISTORY.md` 2026-04-23 (21)
- **2026-04-24 (22)**: 실측 재검증 (S22 + Pixel 6 에뮬). T1~T4a **PASS** (coordinator 동등성). T4b/W는 adb forward의 TCP accept 가짜 성공 때문에 에뮬로는 검증 불가 → 실기기 LAN 필요. 상세: `docs/HISTORY.md` 2026-04-24 (22), `docs/EMULATOR_NETWORK.md`
- **v0.0.30 (2026-04-24 (23))**: iPhone 12 Pro USB 복구 후 S22+iPhone 실기기 LAN으로 T4b 실측 중 **Darwin errno=61 미체크 버그** 발견 (v0.0.27 코드가 Linux `errno=111`만 하드코딩, iOS에서 작동 안 함). `room_lifecycle_coordinator.dart`에 `_refusedErrnos = {111, 61}` + `_networkUnreachableErrnos = {113, 101, 65, 51}` 집합 도입. 재검증 **~10초 fast giveup PASS**. 상세: `docs/HISTORY.md` 2026-04-24 (23)
- **v0.0.31 (2026-04-24 (24))**: W 시나리오(iPhone WiFi 30초+ off) 재현 중 **`P2PService._disconnectedController` race 예외** 발견 → isClosed 가드 추가. `_handleConnectivity` / `_waitForWifiAndReconnect`에 `[CONNECTIVITY]` debugPrint 5개 보강. W connectivity 경로 **PASS**. errno=65/51 분기는 connectivity_plus 즉각 발화로 우회. 상세: `docs/HISTORY.md` 2026-04-24 (24)
- **v0.0.32 (2026-04-24 (25))**: **Peer count 불일치 수정**. `Peer.id`가 socket 주소 기반이라 재접속 시 다른 ID로 새 peer 추가되는 구조 → 호스트 `_handleNewPeer`에 같은 이름 stale peer 정리 추가 + 모든 peer-joined/left broadcast에 `peerCount` 포함 + 게스트 측 `peer-joined`/`peer-left`에서 절대값 우선. 이중 방어. 실측 재검증은 다음 세션. 상세: `docs/HISTORY.md` 2026-04-24 (25)
- **v0.0.33 (2026-04-24 (26))**: Orphan **`com.synchorus/audio_latency` MethodChannel** 제거 (Android MainActivity.kt + iOS SceneDelegate.swift). v2 시절 레이턴시 측정 채널이 v3 전환 후 Dart 호출 0건 상태로 남아있어 dead code 40여 줄 정리. 기능 동일. 상세: `docs/HISTORY.md` 2026-04-24 (26)
- **v0.0.34 (2026-04-24 (27))**: **게스트 재연결 race 수정** — 짧은 off(5~8초) 시 `_handleDisconnected` + `_waitForWifiAndReconnect` 두 경로가 동시에 `reconnectToHost` 성공 → 나중 경로가 `_hostSocket?.destroy()`로 먼저 경로의 새 socket 파괴 → old socket의 onDone이 **교체된 새 `_hostSocket`까지 destroy + `_disconnectedController.add`** → 무한 loop. `p2p_service.dart:355` onDone에 `identical(_hostSocket, socket)` 가드 추가. 실측 PASS — `Stale host onDone ignored` 로그로 가드 발동 확인. **v0.0.32 peer count 수정도 같이 실측 PASS** (비행기 모드 반복 중 양쪽 2명 유지). 상세: `docs/HISTORY.md` 2026-04-24 (27)
- **v0.0.35 (2026-04-24 (28))**: **재연결 경로 직렬화** — v0.0.34는 loop만 차단했지 race 자체는 남아 재연결 2번 + 재동기화 2번 호출 → 1번은 "재동기화 실패" 스낵바. `room_lifecycle_coordinator.dart`에 `_reconnectInProgress` flag 추가해 `_handleDisconnected` + `_waitForWifiAndReconnect` 중 먼저 진입한 쪽이 끝날 때까지 다른 쪽 skip. `_handleDisconnected`는 `finally` 대신 명시적 flag 해제로 errno 분기→`_waitForWifiAndReconnect` 이어받기 지원. 실측(3 사이클): Reconnect 7→3, 재동기화 실패 0, `[RECONNECT] _handleDisconnected skip` 3회 발동 확인. 상세: `docs/HISTORY.md` 2026-04-24 (28)
- **v0.0.36 (2026-04-24, commit 392b1c8)**: 묶음 보강 — (1) `_handleDisconnected` flag leak 방지(try/finally + errno 분기 try 밖 배치), (2) `oboe::getTimestamp` 실패 1차 LOGW 추가(streak 첫 회만), (3) `SyncMeasurementLogger` Android 외부 저장소(`getExternalStorageDirectory()`) 우선 사용 → S22 dual-app(user 95)에서도 csv `adb pull` 가능. HISTORY 별도 항목 없음(commit 본문 참고).
- **v0.0.37 (2026-04-25 (31))**: **호스트 `oboe::getTimestamp` streak 진단 2차 보강 + 1차 측정**. 멤버 `mTsFailStreakCount`, `mTsFailStreakStartMonoNs`, `mTsFailStreakStartXRun` 추가. start 로그에 result + state + xrun + wallMs, end 로그에 last + count + duration + state + xrunDelta + wallMs. **1차 측정 결과**: result 코드 `ErrorInvalidState` (-895) 확정, 단 (30)의 26·15회 긴 streak 미재현 (1·1회, ≤142ms). drift csv는 두 측정 모두 안정(<7ms) → 같은 코드/입력에서 차이 = 시스템 레벨 비결정성. **A 방향**: 자연 재발 대기 + 풍부한 로그로 분류 (사용자 합의). 상세: `docs/HISTORY.md` 2026-04-25 (31)
- **v0.0.38 (2026-04-25 (32))**: **drift 공식에 양쪽 outputLatency 반영 + anchor 베이크인 (BT 비대칭 보정)**. (a) baseline (BT 게스트, 3분)에서 csv <7ms 안정인데 음향 ~300ms 어긋남 = framePos가 BT codec/DAC 안 잡는 구조적 한계 발견. (b) 1차 변경(공식만 보정): csv -275ms 일관 + seek 0회 무한 anchor reset 발견. (b') anchor establishment에 outLatDelta 베이크인 (`_anchoredOutLatDeltaMs` 멤버, `_recomputeDrift`는 변화분만). **검증 PASS** (b'-1) BT: csv |d| <5ms + 사용자 체감 처음 40초 약간 + 이후 정확, (b'-2) 양쪽 내장: (30)/(31)와 동등 거동(<5ms, seek_count 0회). 처음 40초 잔여는 iOS outputLatency 워밍업 과소보고(Apple Forum #679274), 옵션 A(안정화 대기)·B(사전 워밍업)·C(acoustic loopback)·D(UX 명시)로 추가 개선 가능. 상세: `docs/HISTORY.md` 2026-04-25 (32)
- **v0.0.39 + v0.0.40 (2026-04-25 (34))**: **iOS 파일 선택 크래시 + DRM 한계 발견·fix**. (33-3) 진단 중 iPhone 호스트 파일 선택 시 즉시 크래시 발견 → file_picker 8.x가 `FileType.audio`일 때 `MPMediaPickerController` 사용 + `NSAppleMusicUsageDescription` Info.plist 누락이라 SIGABRT. **v0.0.39 fix**: Info.plist에 `NSAppleMusicUsageDescription` 추가. 이후 picker는 열렸지만 Music 라이브러리만 보여줘 비어 보임 + Apple Music 구독곡은 FairPlay DRM이라 어차피 우리 엔진 디코드 불가. **v0.0.40 fix**: `pickFiles`를 `FileType.custom + allowedExtensions: ['mp3','m4a','wav','aac','flac','ogg']`로 변경 → iOS는 `UIDocumentPickerViewController` 사용 → Files/iCloud/On My iPhone 모든 source 표시. Android는 SAF mime 필터로 동일 동작, 회귀 없음. 상세: `docs/HISTORY.md` 2026-04-25 (34)
- **v0.0.41 (2026-04-25 (35))**: **`discovery_service` nsd 마이그레이션 — 양방향 검색 PASS**. (33-3) 본격 fix. raw UDP `255.255.255.255` broadcast(iOS multicast entitlement 필요) → nsd 패키지(시스템 mDNS Bonjour, NSNetService + NsdManager). 인터페이스(`startBroadcast`/`discoverHosts`/`stop`) 호환 유지로 호출부 수정 0. roomCode는 mDNS TXT records로 전달. iOS Info.plist `NSBonjourServices=_synchorus._tcp` 이미 등록되어 추가 변경 0. **검증**: iPhone 호스트 + Android 게스트, Android 호스트 + iPhone 게스트 양방향 PASS. multicast entitlement 신청(1~2주) 우회. 상세: `docs/HISTORY.md` 2026-04-25 (35)
- **v0.0.42 (2026-04-25 (36))**: **mDNS stale 방 fix — found/lost 즉시 반영 PASS**. v0.0.41 후 사용자 발견: 같은 호스트에서 방 만들기 → 나가기 반복 시 게스트 검색 화면에 stale 방 누적. 원인 두 가지 — 호스트 측 `discovery.stop()`이 await 없이 호출되어 ref.invalidate 전에 unregister 미완료 + 게스트 측 `ServiceStatus.lost` 미처리. **fix**: `room_screen.dart` `await discovery.stop()` + `discovery_service.dart`에 `_knownHosts` 맵 + `Stream<String> hostLeftStream` getter + lost 분기 emit + `home_screen.dart`이 구독해서 removeWhere. 검증: 한쪽 검색 켜놓고 다른쪽 방 만들었다 나갔다 반복 → 즉시 생겼다 사라짐 PASS. 상세: `docs/HISTORY.md` 2026-04-25 (36)
- **v0.0.43 (2026-04-25 (38))**: **iPhone 호스트 정지/재생/seek 버그 fix**. (1) 정지 상태 seek 안 됨 (-5/+5 버튼 무반응, seek바 드래그 후 되돌아감), (2) 정지→재생 시 정지 시점이 아닌 마지막 seek 위치/0:00부터 재생, (3) 게스트 측 잠깐 끝 위치 잔상. 원인: iOS `AudioEngine.swift`의 `getTimestamp()` 정지 분기가 ok=false만 반환해 vf/sampleRate 누락 → Dart `_skipSeconds`가 0:00 기준으로 계산 + `stop()`이 vf를 `seekFrameOffset`에 저장 안 함. **fix**: getTimestamp 정지 분기에 stoppedReturn(vf/sampleRate/totalFrames/wallMs/outputLatencyMs 포함) + stop()에서 `seekFrameOffset += sampleTime` 누적. Android oboe는 이미 정상이라 변경 0. 사용자 체감 PASS. 상세: `docs/HISTORY.md` 2026-04-25 (38)
- **v0.0.44 (2026-04-26 (40))**: **게스트·호스트 prewarm으로 첫 재생 정착 시간 단축 시도 — (39) 후속, 회귀 발견 후 v0.0.45에서 롤백**. iOS/Android prewarm 추가했으나 실측에서 **drift abs 평균 3.14ms (게스트 일관 앞섬)** + 사용자 대기 시간에 따라 비결정적 회귀. 자세한 진단 + 가설 검증은 (40)/(41) 참고.
- **v0.0.45 (2026-04-26 (41))**: **prewarm 호출 전체 롤백 → baseline 회복**. iOS framePos는 prewarm 무관하게 device level 누적임을 역할 반전 측정으로 확인. 진짜 회귀 원인은 Android oboe stream framePos가 stop/start 사이 누적된 것. **롤백 후 측정 (S22 host + iPhone guest) drift abs 1.21ms (346 샘플), 평균 +0.08ms** — v0.0.43 baseline 회복. 사용자 체감 "잘 맞다". prewarm/coolDown native 함수는 dead code로 유지(NTP 예약 재생 시 재활용). 상세: `docs/HISTORY.md` 2026-04-26 (41).
- **(42) 2026-04-26**: 역할 반전 (iPhone host + S22 guest) 측정에서 **anchor reset 후 fallback 단계 큰 drift edge case 발견**. 호스트 정지/재생/seek 시마다 게스트 `_resetDriftState()` → 5초 fallback align만 작동 → Android 게스트의 stream open latency를 외삽이 못 잡음 → drift 최대 -634ms (0.6초). v0.0.43 baseline에도 있던 이슈. v0.0.46 작업 대상. 상세: `docs/HISTORY.md` 2026-04-26 (42).
- **v0.0.46 (2026-04-26 (43))**: **oboe stop을 close → pause/resume 모델로 변경** + stale hostPlaying fix. (42) edge case의 stream open latency 자체 제거 의도. 측정 (S22 host + Tab A7 Lite guest) drift abs 3.88ms — 부분 효과. Tab A7 Lite oboe `requestPause` 사이클이 xrun + getTimestamp ErrorInvalidState 동반 → 저가형 HAL 한계로 fallback 외삽 못 잡음. v0.0.48에 그대로 유지.
- **v0.0.47 (2026-04-26 (43))**: **NTP-style 예약 재생 시도**. iOS `AVAudioPlayerNode.play(at:)` + Android oboe 콜백 wall 비교로 호스트·게스트가 wall+200ms 후 양쪽 동시 시작 약속. native `scheduleStart`/`cancelSchedule` 인프라 + `schedule-play`/`schedule-pause` P2P 메시지 추가. 1차: race (drift max 38초) → race fix → reactive seek 비활성화. 결과 drift abs 평균 63초 (max 4분) — 메시지 race + outputLatency 비대칭 등 정밀 작업 한 세션 부족 → 롤백 결정. **NTP 인프라 코드는 보존** — 다음 세션에 (a) sequence number, (b) race 완전 제거, (c) outputLatency 자동 보정 등 추가 후 재도입 가능.
- **v0.0.48 (2026-04-26 (43))**: **NTP 호출 롤백 → v0.0.45 baseline 동작 회복**. 측정 (S22 host + Tab A7 Lite guest, 35 drift 샘플) drift abs 평균 **2.01ms** — v0.0.45 (1.21ms) baseline 동등 (통계 noise). v0.0.46 oboe pause/resume + stale hostPlaying fix는 유지. 사용자 체감 OK. 상세: `docs/HISTORY.md` 2026-04-26 (43).

### 다음 세션 재개 포인트 (우선순위 제안)
1. **첫 재생 정착 시간 — BT 무관 (39)**. 모든 시나리오에서 첫 재생 직후 ~수 초 동안 잠깐 어긋남. 원인 — 게스트 `engine.start()` 자체 지연(iOS 100~500ms) + 첫 anchor establish 전 fallback alignment 정밀도 + clock sync 수렴 시간. RTT 자체는 보정됨(사용자 가설 부분 반증). 옵션: (1) NTP-style 예약 재생(가장 정석, `AVAudioPlayerNode.play(at:)`/oboe frame 예약 활용) / (2) 게스트 사전 워밍업 / (3) 첫 anchor 가속(회귀 위험). 가성비 2번, 효과 1번. 상세: `docs/HISTORY.md` 2026-04-25 (39)
2. **BT 워밍업 잔여 개선 — (32) 후속, (33-2) 조사 + (37) Android 게스트 측정**. iPhone 게스트 BT는 처음 ~40초 잔여 패턴 반복(정지/재생마다 anchor reset). **Android 게스트 BT(Galaxy+버즈)는 ~2초 정착으로 의외로 양호 — (33-2)의 "Android는 acoustic loopback 거의 유일" 가설 부분 반증** (Samsung HAL 정확 보고 추정). 우선순위 1순위는 **iPhone+버즈 케이스 한정 옵션 A(무음 prebuffer + outputLatency 수렴 게이팅)** 시도. C(acoustic loopback)는 우선순위 ↓. D(UX만)도 가능. 상세: `docs/HISTORY.md` 2026-04-25 (33-2), (37)
3. **호스트 `oboe::getTimestamp` 간헐 실패 — 자연 재발 대기 모드** ((30) 발견 → v0.0.36 진단 1차 → v0.0.37 진단 2차 + 1차 측정 재현 X). 같은 코드/같은 파일/같은 출력인데 streak 길이 비결정적 = 시스템 레벨. 재발 시 logcat `OboeEngine:W` 태그 `streak start/end` 짝짓기 → state/xrun/wallMs로 분류 → 완화 방향 결정(보간 obs / state 마스킹 / 버퍼 점검).
4. **errno=65/51 분기 캡처 (v0.0.28 백업 경로)** — iPhone의 connectivity_plus가 즉시 반응해 우회됨. 다른 AP 이동 or 호스트가 네트워크 변경 시나리오에서만 캡처 가능할 것. 코드 변경 0, 실기기 2대 + 2개 AP 필요.
5. **acoustic loopback 1회 calibration 설계** (선택 — 2번 검증에서 잔여 100ms+ 시 우선순위 ↑). OS API 한계(BT codec/radio 단계 미보고) 잡으려면 마이크로 출력 녹음 → round-trip 측정. 마이크 권한 + 정숙 환경 + 사용자 트리거 필요. AOSP CTS 표준 방식.
6. **디버그 모드 호스트 간헐적 스터터** — 릴리스에선 무관, 우선순위 낮음
7. **PLAN Phase 3 (Firebase 인증·결제)** — 수익화 단계 진입
8. **UI 폴리싱** — Phase 4 확장 전 MVP 마감 위한 다듬기

**완료됨 (이번 세션, 2026-04-25)**:
- v0.0.37 호스트 `oboe::getTimestamp` streak 진단 로그 2차 보강 (state + xrun delta + wallMs) + S22 1차 측정 PASS (긴 streak 미재현, 자연 재발 대기로 전환).
- v0.0.38 drift 공식 outputLatency 반영 + anchor 베이크인. **검증 PASS** (BT 게스트 + 양쪽 내장 회귀 모두). seek_count 0회로 부드럽게 동작. 처음 40초 BT 워밍업 잔여만 남음.
- (33) `_resetDriftState`에 `_anchoredOutLatDeltaMs = 0` 한 줄 추가 (안전성). BT 워밍업 잔여 외부 자료 조사 완료(옵션 A/B/C/D 평가).
- v0.0.39 + v0.0.40 iOS 파일 선택 크래시 fix (`NSAppleMusicUsageDescription`) + `FileType.custom + allowedExtensions`로 Files/iCloud 모든 source 표시.
- v0.0.41 `discovery_service` nsd 마이그레이션 — iPhone 호스트 P2P discovery 양방향 검색 **PASS** (multicast entitlement 신청 우회).
- v0.0.42 mDNS stale 방 fix — 호스트 await stop + 게스트 hostLeftStream lost 처리. found/lost 즉시 반영 PASS.
- (37) Android 게스트 BT 시나리오 측정 — Galaxy+버즈는 ~2초 정착, (33-2) 가설 부분 반증.
- v0.0.43 iPhone 호스트 정지/재생/seek 버그 fix — getTimestamp 정지 분기 vf 포함 + stop()에서 vf 저장. 사용자 체감 PASS.
- (39) 첫 재생 정착 시간 이슈 분석·기록 — RTT는 보정되고 진짜 원인은 게스트 engine.start() 지연 + clock sync 수렴. 옵션 1·2·3 정리.
- S22 dual-app(user 95) 환경 발견 + csv 위치 가이드 메모리화.

상세: `docs/HISTORY.md` (최근 섹션 #14~#17), `docs/LIFECYCLE.md`, `docs/PLAN.md`

## 작업 시작 전
- 설계/결정/이력/계획: **docs/** 아래 4개 문서 확인
  - 아키텍처·로직: `docs/ARCHITECTURE.md` (v3 메인, v2는 Appendix)
  - 설계 결정: `docs/DECISIONS.md`
  - 작업 이력: `docs/HISTORY.md`
  - 구현 계획·PoC 플랜: `docs/PLAN.md`
  - 라이프사이클·용어: `docs/LIFECYCLE.md`

## 작업 완료 후
- 작업 내용은 `docs/` 아래 해당 문서에 즉시 반영
  - 일자별 작업·버그·PoC 로그 → `HISTORY.md` (날짜 오름차순, 새 항목은 "알려진 이슈" 바로 위에 추가)
  - 설계/로직 변경 → `ARCHITECTURE.md`
  - 새 설계 결정 → `DECISIONS.md` (표에 한 줄 추가)
  - 계획/일정/기획 변경 → `PLAN.md`
- 기존 4개 분류에 안 맞는 새 유형의 정보면 `docs/` 아래 새 문서 작성 + 본 CLAUDE.md "작업 시작 전" 섹션에 링크 추가해서 관리

## 기능 수정 후
pubspec.yaml version patch bump (예: 0.0.4+1 → 0.0.5+1). lint/포맷 제외.
poc/ 하위 프로젝트는 version bump 예외 (측정/실험용).

## 사용자 프로필
- Spring 백엔드 경험자, Flutter 처음
- IDE: IntelliJ
- 간결한 한국어 소통 선호 ("ㄱㄱ", "응 실행해" 등 짧게 표현)

## 협업 원칙

### 근거 기반 답변 (추측 금지)

**외부 API/라이브러리/플랫폼 SDK에 대한 답변**
- "제 기억으로는..." 금지
- WebSearch/context7 문서 조회로 검증 후 출처(URL) 명시
- 사용자가 다른 곳에서 들은 정보도 반드시 검증 후 동의/반박/보강

**프로젝트 내부 코드/동작에 대한 답변**
- 설명은 반드시 근거와 함께:
  - **코드 라인 번호** (`file.dart:123`)
  - **주석·커밋 메시지·git log/blame** 인용
  - **로그(logcat/flutter 콘솔)** 발췌
  - **실측 수치** (다운로드 속도, drift ms, 타이밍 등)
- 근거 없는 확신형 단정("~해서 이렇게 된다") 금지. 근거가 부족하면 **"가설"/"추측"임을 명시**.
- 설명한 가설이 사용자 관찰(실기기 동작, 로그, 재현 결과)과 어긋나면 즉시 **가설 철회 + 재탐색**. 억지로 기존 설명을 방어하지 말 것.
- 동작이 불확실한 구간은 "확정 못 함"으로 정직하게 기록. HISTORY/DECISIONS 문서에는 **관찰 사실**과 **가설**을 구분해서 적음.
- "~덕분에 해결된 걸로 보임" 같은 추정성 결론은 "재현 실패" 등 실측 기반 표현으로 대체.

### 설명 방식
- **낯선 도메인** (DSP/신호처리/제어이론): 전문 용어는 한 번에 하나씩, 짧은 비유·풀이 곁들이기. Claude가 먼저 쉬운 그림 그리고 사용자 확인.
- **익숙한 도메인**: "사용자가 자기 언어로 정리 → Claude가 검증·보강" 패턴 선호.
- 설명 길어지면 먼저 "여기까지 이해되셨나요?" 체크.

### 코드 수정 전 확인
- git log/blame으로 해당 줄의 도입 의도 확인 후 수정. "이상해 보이는" 패턴이 의도적 수정인 경우 많음.
- 특히 audio_service.dart의 syncPlay/syncSeek 순서(broadcast→seek)는 커밋 c6123b6에서 의도적으로 변경한 것. 되돌리지 말 것.
- 주석에 "대칭화", "의도적", "방지" 같은 단어가 있으면 함부로 되돌리지 말 것.

### 크로스 플랫폼 (Android + iOS) 항상 고려
무언가 구현·수정할 때 **두 플랫폼 모두** 검토해서 진행. 한쪽만 생각하면 상대 플랫폼에서 조용히 동작 안 함.
- **POSIX errno 값 차이**: Linux(Android)와 Darwin(iOS/macOS)은 같은 의미의 errno 번호가 다름.
  - `ECONNREFUSED`: Linux=111, Darwin=61
  - `EHOSTUNREACH`: Linux=113, Darwin=65
  - `ENETUNREACH`: Linux=101, Darwin=51
  - 실제 사고: v0.0.27에서 Linux `errno=111`만 하드코딩해 iOS에서 fast-giveup 작동 안 함 → v0.0.30에서 집합 `{111,61}` / `{113,101,65,51}`로 수정.
  - 플랫폼 errno 집합 정의는 `room_lifecycle_coordinator.dart`의 `_refusedErrnos` / `_networkUnreachableErrnos` 참고.
- **라이프사이클 이벤트 도달성**: detached는 Android foreground service에선 도달 가능, iOS 강제 종료는 미도달 가능. 이런 비대칭은 `docs/LIFECYCLE.md` 매트릭스에 반영.
- **네이티브 채널**: 새 MethodChannel 추가 시 Android(Kotlin) + iOS(Swift) **양쪽 구현** 필수. 한쪽만 하면 반대 플랫폼에서 PlatformException 또는 silent fail.
- **권한·capability**: Info.plist(iOS)와 AndroidManifest.xml 둘 다 확인. 예: 마이크, 로컬 네트워크, 백그라운드 오디오.
- **connectivity / 네트워크 스택**: iOS 제어센터 WiFi 토글은 "일시 비활성화"라 `connectivity_plus`가 `none` 이벤트 안 줄 수 있음. 진짜 off 테스트는 비행기 모드 또는 설정 앱 Wi-Fi 토글로.
- **플랫폼 분기 표기**: `Platform.isIOS` / `Platform.isAndroid` 분기 작성 시 각 분기 아래에 **왜 분기했는지 주석**. 안 그러면 나중에 사유를 알 수 없어 되돌릴 위험.

### 빌드/배포/테스트
- flutter run 백그라운드 실행 후 불필요하게 상태 계속 확인하지 말 것. 빌드 진행 중이면 간단히 알려주고 기다릴 것.
- 에뮬/기기의 앱/프로세스 재시작·종료 전 반드시 사용자 확인.
- **PoC**: 실기기 우선. 에뮬은 알고리즘 로직 verify 목적에서만 선택적 추가.

#### 실기기 빌드/설치 (CLI, Xcode 불필요)
- **Galaxy S22** (R3CT60D20XE): `flutter build apk --debug` → `flutter install --debug --device-id R3CT60D20XE`
- **iPhone 12 Pro** (00008101-00063C963C52001E): `flutter run --device-id 00008101-00063C963C52001E` (iOS는 flutter install 불가, 항상 flutter run)
- 실기기 테스트 시 에뮬레이터는 불필요 — S22(호스트) + iPhone(게스트) 조합으로 진행

### 에뮬레이터 네트워크
에뮬레이터 테스트 시 adb forward 포트포워딩 필수 (에뮬은 192.168.x.x 직접 접근 불가):
```bash
adb -s R3CT60D20XE forward tcp:41235 tcp:41235  # P2P TCP 소켓
adb -s R3CT60D20XE forward tcp:41236 tcp:41236  # HTTP 파일 서버
```
실기기(S22)가 호스트, 에뮬레이터가 게스트, `10.0.2.2`로 접속. 상세: `docs/EMULATOR_NETWORK.md`
