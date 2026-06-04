# Synchorus 구현 계획

제품 기획/구현 계획/PoC 플랜. 설계·이력·결정은 아래 문서 참고.

- 아키텍처·로직: [ARCHITECTURE.md](ARCHITECTURE.md)
- 설계 결정: [DECISIONS.md](DECISIONS.md)
- 작업 이력: [HISTORY.md](HISTORY.md)

## PoC 플랜 (v3)

### 6-1. PoC가 답해야 할 3가지

1. **네이티브 엔진 정밀도**가 정말 sub-ms인가
2. **Wi-Fi clock sync 노이즈**가 어느 수준인가 (5-10ms 가정 검증)
3. **폐루프가 진짜 수렴**하는가 (drift → 보정 → 안정 사이클)

이 3개에 답하면 본 구현 GO. 못 답하면 설계 재검토.

### 6-2. 범위 (격리 원칙)

**PoC = 변수 하나만 실험**. 다른 모든 변수는 의도적으로 제외:

| 포함 | 제외 (본 구현 단계로 미룸) |
|---|---|
| Android Oboe 네이티브 엔진 | UI 폴리싱 |
| getTimestamp 폴링 + 로그 파일 | audio_service 플러그인 통합 |
| 최소 P2P (audio-obs, drift-report) | ~~iOS (별도 task)~~ ✅ |
| Drift 계산 + seek 보정 | rate 조정 |
| 광범위한 로깅 | 백그라운드 모드 |
| 호스트 1 + 게스트 1 | 멀티 게스트 |
| 로컬 파일 직접 재생 | HTTP 파일 전송 |

**왜 격리하는가**: 전부 다 넣으면 drift 원인 추적 불가능 ("sync 알고리즘 탓? 플러그인 충돌? HTTP 지연? 백그라운드?"). 좁게 잡아야 인과 분석 가능.

### 6-3. 단계별 진행

| 단계 | 내용 | 출력/통과 기준 | 상태 |
|---|---|---|---|
| 0 | Oboe 래퍼 + 단순 재생 | "소리 나옴" 확인 | ✅ 2026-04-08 S22 통과 |
| 1 | getTimestamp 폴링 + 파일 로그 | (framePos, ns) 시계열 확보 | ✅ 2026-04-08 S22 통과 |
| 2 | P2P audio-obs 송수신 | 게스트가 호스트 obs 수신 | ✅ 2026-04-09 S22+S10 통과 |
| 3 | drift 계산 (선형 보간) + clock sync | drift 시계열 로그, 네트워크 지연 분리 | ✅ |
| 4 | seek 보정 + drift-report | 보정 전/후 비교 | ✅ |
| 5 | 정적 노이즈 측정 (재생 후 30s) | 실측 noise floor | ✅ |
| 6 | S22 30분 stress + 네트워크 블립 | 누적 drift, 글리칭 검증 | ✅ 2026-04-14 |
| iOS | AVAudioEngine 동일 패턴 | 크로스플랫폼 싱크 ±6ms | ✅ 2026-04-15 (S22↔iPhone) |

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

### 6-4. 성공 기준

| 항목 | 목표 |
|---|---|
| 정적 noise floor | <10ms |
| 30분 보정 없이 누적 drift | <100ms |
| 보정 후 안정 시간 | <1초 |
| S22 글리칭 발생 빈도 | 분당 0회 |
| 글리칭 발생 시 복구 시간 | <2초 |

미달 시 → 어디서 막혔는지 로그로 진단 → 설계 재검토.

### 6-5. 본 구현 단계 흐름 (PoC 통과 후)

| 단계 | 내용 | 상태 |
|---|---|---|
| 1-1 | 네이티브 엔진 본체 앱 이식 (Android Oboe + iOS AVAudioEngine) | ✅ 2026-04-15 |
| 1-2 | Dart 서비스 레이어 (NativeAudioService) + 오디오 파일 디코딩 재생 | ✅ 2026-04-15 |
| 1-3 | P2P + clock sync + drift 보정 통합 | ✅ 2026-04-16 |
| 1-4 | 백그라운드 재생 (audio_service 연동) + 음소거 | ✅ 2026-04-17 |
| 2 | 1:1 → 1:N 멀티 게스트 확장 | ✅ 2026-04-22 (S22 호스트 + iPhone 12 Pro + A7 Lite 동시 실측, 코드 변경 없이 동작) |
| 3 | 로컬 파일 → HTTP 전송 추가 | ✅ (step 1-3에서 구현 완료, v0.0.22에서 shelf 제거·직접 구현으로 재작성) |
| 4 | rate 조정 추가 (UX 개선) | |
| 5 | UI 폴리싱 | |

각 단계 후 회귀 테스트.

## 다음 세션 작업 후보 (우선순위)

매 세션 시작 시 이 리스트로 진입점 결정. 완료된 항목은 체크해서 위로 통과. 새 항목은 우선순위에 끼워 넣기.

세션 마감 시 "지금까지 한 것"은 [HISTORY.md](HISTORY.md)에 기록, 이 리스트는 **앞으로 할 것**만.

### HIGH

**🆕 UI 폴리싱 트랙 (2026-05-29 시작)** — 단독 플레이어 앱 사용성 + 호스트 모드 UX 정리.

- ✅ v0.0.86 NativeTestScreen 제거 (PoC 임시 화면, HISTORY (103))
- ✅ v0.0.87 첫 화면 = PlayerScreen (단독 호스트 모드, HISTORY (104))
- ✅ v0.0.88 단독 모드 loadFile WiFi IP 가드 완화 (HISTORY (105))
- ✅ v0.0.89 A-B 구간 반복 (호스트 전용, 효과적 A=0/B=duration, 새 지정 우선 충돌 처리, long-press 1점 해제 + 햅틱, 시크바 위 마커, [A, B] clamp, HISTORY (106))
- ✅ v0.0.90 seek 메모리 3슬롯 + 마커 색상/위치 분리 + 영역 reserve (HISTORY (107))
- ✅ **v0.0.95 P2P 동선 통합 (HISTORY (112))** — group_add → BottomSheet 안에서 호스트/스피커 선택 + 정보 카드 + 종료까지 단일 화면. RoomScreen 거치지 않음. 입장 코드 검증 + IP 검증 + 호스트 ping. 단독↔P2P 전환 시 audio-url 재바인딩(HISTORY (105) 자연 해소). 게스트 transpose/speed UI 정합성 + sync 직렬 처리 + cleanupSync stream emit + 시크바 hasAudio 가드. 검증 통과(SM-S947N + S22).
- ✅ **방 만들기 WiFi 미연결 silent fail fix (v0.0.94, HISTORY (111))** — 2026-05-29 v0.0.90 SM-S947N "방 만들기 클릭 무반응" 보고는 사용자 진단으로 WiFi 미연결이 root cause로 확인. `_createRoom` 진입 시 `NativeAudioSyncService.getLocalIP()` 사전 체크 + SnackBar "WiFi 연결이 필요합니다" 안내로 마감. iOS 제어센터 WiFi 토글 케이스도 IP 직접 체크라 robust.

**🆕 §H Transpose PoC 트랙** (2026-05-29 시작) — `docs/SYNC_ALGORITHM_V2.md` §H 디자인.

H-1 첫 시도(v0.0.91 1차, 2026-05-29 revert) — Sonic 음수 cents SIGSEGV + SoundTouch callback 안 직접 처리 시 silence padding buzz + timing drift. **공통 root cause**: 음악용 transpose 라이브러리 모두 batch processing 알고리즘인데 우리 oboe LowLatency callback burst(~96 frames)이 너무 작음.

진행 상태:
- ✅ §H 디자인 명세 + 합의 권장값 (`SYNC_ALGORITHM_V2.md` §H-2-A~H)
- ✅ PoC scaffold `poc/transpose_engine/` (step 1 NDK 빌드)
- ✅ PoC step 2 (callback 안 처리 = silence padding 한계 객관적 확정)
- ✅ PoC step 3 (Worker thread + lock-free SPSC ring = 청감 click 0 통과)
- ✅ **v0.0.91 본 앱 통합 (HISTORY (108))** — Android worker thread + iOS AVAudioUnitTimePitch + Dart/UI/P2P 모두. cents=0 bypass.
- ✅ **v0.0.92 §I 속도 조절 추가 (HISTORY (109))** — SoundTouch setTempo + AVAudioUnitTimePitch.rate, 0.5~2.0x, 5% step, 동일 worker thread 인프라.
- ✅ **v0.0.93 edge case 검증 + state 누수 fix (HISTORY (110))** — 시나리오 1~9 단독 모드 통과. 검증 중 발견된 회귀(파일 변경/세션 진입 시 native 측 transpose/speed state 잔재) 4 layer reset으로 fix. ±12 semitone 극단 케이스도 통과.
- ✅ **v0.0.102 연속 변경 무음 fix (HISTORY (119))** — transpose/speed 슬라이더 연속 변경 시 위치는 가는데 소리 안 나던 증상. root cause: pitch/tempo 변경마다 `mST.clear()`로 SoundTouch batch(82ms)를 못 채워 출력 ring이 빔. **B안(clear 생략)** — `setPitchSemiTones`/`setTempo`만 호출. 드래그 중에도 끊김 없이 실시간 변화. 파일 로드는 `mSTReconfigure`가 clear 보장. SM S947N 단독 모드 청감 통과(2배속 연속 포함 무음 없음). PoC가 부드러웠던 건 clear 유무가 아니라 입력 공급 방식(PoC sine self-feed vs 본 앱 PCM callback feed) 차이로 확인.
- ✅ **v0.0.103/104 §H/§I P2P 전파 견고화 (HISTORY (120))** — 멀티에이전트 재조사로 transpose/speed의 게스트 sync 영향 전수 분석. **P0**(늦게 합류 게스트 speed/transpose 상실 — loadFile reset 후 재적용 누락 = v0.0.93 회귀) + **P1-a**(speed 변경 시 anchor stale → audio-tempo 핸들러 `_resetDriftState`) + **P1-b**(단발 broadcast 유실 자가치유 — obs에 speedX1000/transposeCents 필드) + **P1 외삽**(vf 외삽 3곳에 speedFactor 곱, framePos 외삽은 HAL rate라 그대로). 실기기(S26+ 호스트 + S22 게스트): P0 ✅, 외삽 안정성 ✅(2배속 anchor_set 16→1, fallback 163→34, drift ~2ms), 1배속/speed고정 청감 OK.
- ⏳ Algorithm latency를 `outputLatencyMs`에 반영 (sync 자동 보정) — SoundTouch 큐(~170ms) latency 미반영. 종합 P2.
- ⏳ 30분 stress + 측정 보고서 — **2배속 장시간 포함**. 현재 underrun(무음) 객관 카운터 없음(`oboe_engine.cpp:840` vf≥ringHead / `862` popped<numFrames) → 측정 전 카운터 추가 선행.
- ⏳ iOS 실기기 검증
- ✅ **P2P 게스트 동기화 실측 — v0.0.103/104 (HISTORY (120)) 핵심 완료**. transpose/속도 게스트 전파 fix(P0/P1-a/P1-b) + 외삽 speed 반영 + 2배속 실측. driftMs(framePos) 견고, 청감 OK. ⚠️ **정정**: 당시 "2배속 vfDiff staleness 잔차는 진단 과대보고로 추정"이라 적었으나, v0.0.111 acoustic 측정으로 **vfDiff가 진실(거짓말 패턴)이고 framePos/drift가 거짓**이었음이 밝혀짐 (아래 v0.0.111 항목). ⏳ **잔여**: P1-b 자가치유(WiFi 교란 직접 재현) / iOS 실기기 / 2배속 underrun 카운터.
- ✅ **v0.0.111 거짓말 패턴(vfDiff) re-anchor + speed 정규화 (HISTORY (123))** — 맥북 마이크 acoustic 측정으로 vfDiff = 실제 스피커 시차임을 확정(465ms 일치). vfDiff 중앙값 >150ms 시 anchor 리셋 + speed 정규화(vfDiff/speedFactor). vfDiff max 474→156ms, 2배속 224→23ms. tempo 디바운스(250ms)·계측(msgSeq)·tcpNoDelay 동반. ⏳ **미해결 (별도 트랙 — 한 번에 안 건드림, 다음 세션 하나씩)**:
  1. **isOffsetStable jitter → anchor 공백** (가장 영향 큼). filtered offset 1.9ms 안정인데 raw RTT jitter(15~30ms)가 `_stableCount` 리셋 → anchor ~20초 안 박힘(그동안 fallback ±240ms). ⚠️ **v0.0.112 타임아웃 강제 establish 시도 → 폐기 (HISTORY (124))**: 재입장 시엔 offset 자체가 없는(rawOff=0/rtt=0) 상태라 force가 틀린 위치에 박아 악화. "offset은 있고 판정만 막힘" 가정이 재입장엔 안 맞았음. 재시도 시 **force 조건에 offset 신선도(rtt>0) 가드 필수**, 또는 아래 5번(clock sync 지연)을 먼저 해결.
  2. **150ms 임계 → 80~100ms 낮춤** (체감상 큼, staleness 마진 고려).
  3. **host HAL getTimestamp 간헐 실패** (framePos=-1, HISTORY (30) 재발).
  4. **게스트 engine 재시작 루프** (host seek 연타 + play/pause 토글 막 조작 트리거, "position 동기 표시인데 다른 부분 재생"). 정상 사용 미발생 — 우선순위 낮음.
  5. **🆕 재입장 시 clock sync ~8초 지연** (2026-06-03 (124) 실측, 재입장 틀어짐의 진짜 root cause 후보). 게스트 재입장 후 ping/pong이 ~8초간 미작동(csv rawOff=0/rtt=0) → offset 못 구함 → anchor 못 박고 fallback만. **다음 세션 1순위 진단**: 재입장 시 SyncService 재시작/핸드셰이크 흐름이 왜 지연되는지 (carry over 안 됨? listener 재등록 지연? 초기 핸드셰이크 미재개?).
  6. **🆕 vfDiff 40~95ms 진동** (2026-06-03 (124) 재입장 후, drift 0~4ms = 거짓말 패턴). 150ms 미달이라 vfDiff re-anchor 미발동 → 방치. 위 2번(임계 80~100 낮춤)으로 일부 잡히나, 진동 자체(40↔90 왕복) 원인은 별도 — obs 신선도/외삽 톱니 의심.
- ✅ **v0.0.112 SoundTouch latency 반영 (HISTORY (125))** — `SETTING_INITIAL_LATENCY`를 outputLatency에 가산(transpose/speed ON 시). ST 반영 확인 + 정상 2배속 정렬 좋음(drift median 0.24). ⏳ **미해결**: (가) **anchor < fallback 실증 (HISTORY (126))** — anchor 경로 vfDiff ±수십ms 변동(세션1 +46/세션2 −65), 같은 곡 fallback 경로는 0~5 정렬 → anchor가 establish 오차를 baseline에 박고 지속, fallback은 fresh라 정확. "한 방향 편향" 가설 철회(±변동). ST/outLat 무관 확정. **다음 1순위 = acoustic 부호 확정 → anchor 주기 재발행(결함 A, SYNC_REDESIGN).** (나) 전환 과도기 ST 비대칭 베이크 스파이크(195ms → seek 회복).
- ✅ **v0.0.114 realign + virtualFrame 시점 정합 — 톱니 근본 fix (HISTORY (128))** — (126) "±수십ms 변동(톱니)"의 진짜 원인 = `virtualFrame`(마지막 콜백 ~현재) vs `wallMs`(=framePos의 HAL timeNs 과거 시점) **시점 불일치** → 게스트 vfDiff 외삽이 HAL 지연 이중 카운트. `oboe_engine.cpp`에서 virtualFrame을 timeNs 시점으로 정렬 + realign(vfDiff 60ms 시 baseline fresh 재정렬, 150ms anchor=null 리셋 대체). 측정(transpose +5, 3분): drift vfDiff 30-60ms **148→0**, >60 **11→0**, min/max ∓108→∓27. **±50/±100 톱니 제거.** drift(framePos↔wall 정합)가 멀쩡했던 게 증거. iOS는 vf/framePos 둘 다 lastRenderTime이라 정합(보정 불필요). 진단: transpose 0/+5 둘 다 톱니(SoundTouch 무관) + obs_age 무관(외삽 거리 무관). ⏳ **잔여 (다음 세션, 하나씩)**:
  1. **+16ms vfDiff 일정 편향** (median +2.4→+15.9, fallback +8.2). 톱니(랜덤) 사라지니 드러난 일정 bias. 보정 과조정 vs 진짜 편향 미확정 → virtualFrame 보정 수식 재검토 또는 acoustic. **1순위.**
  2. **anchor establish 공백** (이번 측정 drift 97 vs fallback 255, anchor_set 2회). offset 불안정(isOffsetStable raw RTT jitter) = 위 v0.0.111 #1 / #5 clock sync 영역. 톱니fix 무관 환경/jitter 트랙.
- 📋 **전체 로드맵: [SYNC_REDESIGN.md](SYNC_REDESIGN.md)** — anchor 주기 재발행 / 미세 보정층 / 시계동기 강화 우선순위.
- ⏳ **전환 스케줄링 (SYNC_ALGORITHM_V2 §I-6, 다음 트랙)** — speed 전환 순간(특히 2→1 감속) 네트워크 지연 동안 게스트가 옛 speed 유지 → vfDiff +200ms 스파이크(실측, 사용자 청감 일치). 호스트 "wall T에 speed S 적용" broadcast로 양쪽 동시 전환. schedule-play race 이력 있어 **설계 합의 선행**.
- ⏳ 시크바/시간 표시 정확도 (speed != 1.0 시 totalDuration / position 표시)
- ⏳ Crossfade(Option C) — 현재 transition click 매우 미세 (음악에선 묻힘), 필요 시 추가
- ✅ **방 만들기/참가 동선 — v0.0.95에서 BottomSheet 통합 + v0.0.97에서 dead route 정리 완료 (HISTORY (112)/(114))**. PlayerScreen AppBar `group_add` → BottomSheet. HomeScreen/RoomScreen/RoomLifecycleCoordinator 3개 삭제. RoomLifecycleCoordinator 핵심 기능 이식은 별도 트랙.
- ✅ **SnackBar UX 개선 — v0.0.100 (HISTORY (117)) 완료**:
  1. modal 가림 → 호스트 모드 진입 실패(WiFi 없음/서버 시작 실패)를 inline 에러 박스로 변경(스피커 picker `_lastError`와 동일 패턴, `_buildInlineError` helper 공용). **옵션 A(Scaffold full-wrap)는 폐기** — `isScrollControlled:true` modal에서 Scaffold가 화면 전체 높이로 늘어나는 회귀 때문(사용자 지적). 가림 케이스는 `_enterHostMode` 2곳뿐(스피커 IP/코드 오류는 이미 inline). 포트 충돌 문구는 `shared:true`라 사실상 안 나므로 일반화.
  2. 큐 적체 → `_showSnack` helper(`hideCurrentSnackBar()` 후 표시)로 해결. `_pickFile`/`_exitSpeakerMode`에 적용.
  - ✅ 실기기(SM S947N) 검증 통과 — WiFi off 호스트 모드 inline 표시 + sheet 닫힘 시 clear 정상.
- ⏳ **별도 §H 트랙: 속도 조절** (피치 유지, time stretching). native engine + 동기화 알고리즘 큰 변경. §G G-2/G-3 완료 + 측정 후 진행.

**§G PCM streaming + 하이브리드 시작 패턴** — `docs/SYNC_ALGORITHM_V2.md` §G 명세 + 사용자 합의 완료 (2026-05-11). 결정: Android 사전할당 PCM → ring buffer 60s (10s/50s 분배, Pre-fill 1초, TOO_LONG 제거), 시작/큰 seek = G-2 하이브리드 ready timeout 200ms, G-3 throughput EMA+in-flight 폴링은 측정 선행 후 별도 PR.

진행 상태:
- ✅ step 1 (v0.0.75) — csv decode_load 측정 인프라 + Android loadFile Map 통일 완료 (2026-05-11)
- ✅ **step 2-G1 재도입 (v0.0.84, 2026-05-17)** — PoC 격리에서 race 재현(8회 중 2회=25%) + 큐 모델 fix 검증(17회 중 0회=0%) 후 본 앱 합치기. 큐 모델: 외부는 `mDecodeSeekTarget`만 set, ring head/tail은 decodeLoop 단일 thread에서만 갱신. 추가로 EOS wait fix(v0.0.76 누락) — 곡 끝 도달해도 decode thread 살아있게 seek 대기. HISTORY (100) 참조.
- ⏳ **step 2-G2 (Dart Ready-then-Go 하이브리드)** — v0.0.77 시도 후 revert (HISTORY (94)). G-1 race가 fix됐으니 G-2 재시도 가능. 다음 작업 후보 (큐 모델 기반 재설계).
- ⏳ step 3 — G-3 측정 → EMA 활용 (G-2 재도입 후)
- ⏳ 30분+ 측정 검증 (MID-7 자연 해소 가능 — ring buffer 14분 한도 제거됨)
- ⏳ iOS 회귀 검증

~~**§B clock sync 추가 보강 (v0.0.80~v0.0.83)**~~ — **2026-05-15 (99) 완료, 사상**. v0.0.80 outlier rejection + v0.0.81 ANCHOR-VERIFY + v0.0.82 호스트 `_broadcastObs()` 제거 + v0.0.83 fallback cooldown 가드. 청감 "괜찮음" 확정, 무음 0회. 잠재 후보(임계 보강 / deadline 보강 / obs 신선도 가드 / 호스트 빠른 seek 연타 무음 / 2단계 burst sync 재실행 / ANCHOR-VERIFY 단독 청감 부작용 측정 / v0.0.86 `_latestObs=null` race 메모) 모두 잔재 발견 시 HISTORY (96)~(99) 참고해 재기.

**§B 후속 — 호스트 빠른 seek 연타 시 게스트 sync 누락** (2026-05-17 (100) 후속 측정 신규 → 2026-05-25 (102) **진단 측정 결과 가설 3가지 모두 부정, 재현 실패**) — v0.0.84 측정에서 vfDiff -197초 영구 잔재 19초+ 지속 발견. v0.0.85에서 진단 로그 추가 후 256회 빠른 seek 측정 결과 메시지 손실 0 + handler 발화 OK + 큐 모델 native 처리 OK + vfDiff 영구 잔재 0건. **잔재가 race 의존(확률적) 또는 환경 의존(맥북 핫스팟 저latency)** 가능성. 진단 인프라(`seek_msg_seq` csv + `[SEEK-NOTIFY]` logcat)는 v0.0.85 그대로 유지 — 자연 재발 시 즉시 root cause 분리 가능.

진행 후보:
- ✅ **(a) 호스트 큰 seek 후 게스트 seek-notify 도달 검증 로그** — **v0.0.85 (101) 완료, (102) 측정으로 가설 1/2/3 부정**.
- ⏳ **(다음) 일반 WiFi 환경 재측정** — 환경 의존성 확인. 카페 핫스팟 vs 집/사무실 WiFi에서 재현 빈도 비교.
- ⏳ **(다음) 자연 재발 trigger 진단** — 진단 인프라 유지 + 사용자 일상 사용 중 잔재 발견 시 csv/logcat 즉시 캡처.
- (b)~(e)는 **잔재 직접 재현 후로 보류**. 잔재 못 보면 fix 방향 미정.
  - (b) ANCHOR-VERIFY 임계 500ms → 200~300ms 좁힘 (HISTORY (98) 남은 문제와 동일 트랙)
  - (c) obs 안 호스트 vf 점프 감지 시 강제 reseek fallback
  - (d) v0.0.82/v0.0.83 timing race 검토
  - (e) v0.0.84 큐 모델 fix와의 상호작용

순서 권장: ✅(a)/(102) 측정 → **(다음) 일반 WiFi 재측정 + 자연 재발 대기** → 재현 시 root cause 좁힘 → (b)~(e) 중 직접 영향 영역만 fix.

~~**v0.0.74 cold start 측정 + 회귀 검증**~~ — **2026-05-10 (90) 완료, fix 통합 사상**.

진행 결과:
- ✅ Cold start 단축 확정: 18초+ → 100~3000ms 영역 (시나리오별)
- ✅ baseline 도달 (Run 4 +1.81ms, v0.0.63 -5~-7ms 동등 또는 더 좋음)
- ⚠️ 회귀 1건 (Run 1 영구 잔재 -47ms) — outputLatency 안정 wait 도달 전 anchor 박힘이 root cause
- ✅ **v0.0.74-fix (outputLatency 안정 가드 + Oboe 진단 logging) 추가 적용**
- ✅ fix 후 재측정: Run 4 baseline 도달, logcat에서 가드 효과 확정 (`calcLatency recovered after 45 abnormal: 8.19ms`)

**남은 미스터리 (LOW 후속)**:
- Run 1 영구 잔재가 가드 후도 비결정적 발생 가능 (1/4 케이스). 자체 정상화 메커니즘 미파악. 사용자 청감 OK라 실용 영향 작음.
- 후속 진단 후보: anchor 시점 진짜 베이크값 csv 컬럼 추가, 자체 정상화 트리거 추적.

1. ~~**v0.0.73 다중 게스트 fix 실측 검증**~~ — **2026-05-06 (89) PASS**. 3대(S22 호스트 + Tab A7 Lite + iPhone 12 Pro) 환경에서 (1) 기본 입장 peer count 3 유지, (2) A7 비행기 모드 on/off 후 재접속 3 유지, (3) iPhone 비행기 모드 on/off 후 재접속 3 유지, (4) A7 앱 강제 종료 → 즉시 2 → 재실행 후 3으로 복귀 모두 통과. v0.0.51 핑퐁 회귀 없음, 영속 deviceId 정상 작동. 같은 모델 2대 환경 검증 부담은 v0.0.73 fix(코드상 충돌 0)로 자체 해소.

1-A. ~~**(81) 신규 회귀 fix — 파일 변경 시 호스트 무음 + 게스트 단독 재생**~~ — **v0.0.69 (82) 완료**. audio-url playing=false + framePos>0 sanity gate + _latestObs reset. 실기기 검증 통과.

1-B. ~~**(81) 신규 회귀 진단 — T4 peer count 갱신 누락**~~ — **v0.0.71 (84) 완료**. root cause: `socket.done.catchError` 분기 broadcast 누락. 정상/에러 분기 통합 fix. 실기기 3대 검증 통과.

1-C. ~~**(82) 신규 회귀 fix — HTTP 404 stale state**~~ — **v0.0.70 (83) 완료**. `_cleanupTempDir` 활성 파일 보호 가드 + `_handleAudioRequest` disk 확인 + 진단 logging. 실기기 통과. root cause는 자연 재현 시 `[DIAG] startListening re-entry` 로그로 좁힐 예정.

2. ~~**v0.0.53 anchor fix 효과 검증 측정**~~ — **완료 (2026-05-02 (59))**. 결과: vfDiff signed -15.94ms (v0.0.52 -3.60ms 대비 4배↑), anchored vs current diff 0.22ms (EMA 효과 없음 확정). anchor 중복 호출 제거가 root cause 아니었음. 후속 작업은 신규 HIGH 항목 2-A/2-B로 분기.

2-A. ~~**anchor establish robustness**~~ — **SYNC_ALGORITHM_V2 §D-2로 흡수 (2026-05-02 (60))**. (60) raw 진단으로 root cause가 EMA convergence lag로 좁혀짐. 단독 fix 대신 디자인 단일 commit으로 묶음 (HIGH 4 참조).

2-B. ~~**anchor_reset_offset_drift 빈도 root cause**~~ — **(60)에서 진단 완료**. idle 3분 reset 4회는 잘못된 stable 판정으로 박힌 anchor가 EMA가 진짜 값에 따라잡는 동안 5ms 임계 자연 초과한 결과. clock skew 아니라 EMA convergence lag (`SyncService.isOffsetStable` 판정 결함). 단독 fix 대신 SYNC_ALGORITHM_V2 §D-2로 명세 후 단일 commit (HIGH 4 참조).

3. ~~**첫 재생 정착 시간 — BT 무관 (HISTORY (39))**~~ — **2026-05-02 (71) v0.0.63 §D-2 fix N=2 검증으로 자연 해소**. 청감 분포 좋음/좋음 일관, fallback alignment가 사용자 청감 임계 안에서 동작 확인. (44) 13번 사이클 회피 — fix 한 줄(§D-2)로 HIGH-3/4 둘 다 해결.

4. ~~**SYNC_ALGORITHM_V2 디자인 단일 commit**~~ — **2026-05-02 (70)/(71) 완료**. v0.0.63 §D-2 fix(D2-2 AND 조합) 적용 + N=2 검증 통과. anchor EMA gap 모든 케이스 < 2ms, anchor_reset 빈도 4회→0회. §A/B/D/E/F는 현행 유지 명세화, §C는 30분+ 장시간 측정 후 결정 보류.

### MID

5. ~~**HISTORY (45) -20.84ms 잔재 자연 재현 시 root cause 분해**~~ — **2026-05-03 §D-2로 자연 해소 정황 정리**. (a) outputLatency baked-in 가설은 (59) anchored vs current diff = 0.22ms로 사실상 부정. (b) §D-2(v0.0.63) 후 vfDiff signed mean -20.84ms → -5.25~-7.33ms로 4~7배 감소. (c) 자동화 N=3까지 진행했으나 -20ms 영역 미재진입. 진단 컬럼(`out_lat_*` + vf_diff_ms)은 활성 유지 — 큰 잔재 자연 재발 시 자동 캡처되어 HISTORY 미해결 이슈에 신규 항목으로 다시 띄움.

6. ~~**EMA 단독 cherry-pick (B-1) 검토**~~ — **우선순위 ↓ (2026-05-02 (59))**. 측정 결과 outputLatency anchored vs current diff = 0.22ms로 사실상 0 → EMA 보존 효과 미미할 것으로 강한 신호. 본 항목은 (A)/(B) root cause fix 진행 후에도 잔재가 있을 때만 재고려.

7. **30분+ 장시간 idle 측정** — rate drift 누적 검증. **2026-05-02 (77) v0.0.67 자동화 12분 측정에서 vfDiff signed mean -5.25ms로 큰 추세 미관찰**. 30분 측정은 14분 PCM 한계(`oboe_engine.cpp:143` 150MB)로 직접 불가. §C 결정은 PCM streaming 구조 변경 후로 미룸. 또는 측정 mp3를 여러 번 연속 재생(seek 0 반복)으로 우회 가능 — 다만 첫 anchor reset 발생. **2026-05-11 §G 작업으로 14분 한도 자연 해소 예정** (HIGH 영역 §G PCM streaming 항목 참조).

8. **BT 워밍업 잔여 개선 (HISTORY (33-2), (37))**. iPhone 게스트 BT는 처음 ~40초 잔여 패턴. Galaxy+버즈는 ~2초로 양호 (Samsung HAL 정확 보고 추정). iPhone+버즈 케이스 한정 옵션 A(무음 prebuffer + outputLatency 수렴 게이팅) 시도.

9. **호스트 `oboe::getTimestamp` 간헐 실패 — 자연 재발 대기** (HISTORY (30) → v0.0.36 → v0.0.37). 재발 시 logcat `OboeEngine:W` 태그 `streak start/end` 짝짓기 → state/xrun/wallMs로 분류.
   - **외삽 모델 검토 (가설)**: `_recomputeDrift`(`native_audio_sync_service.dart:1376-1379`)가 wall clock 외삽 — `(hostWallNow - obs.hostTimeMs) * hostFpMs` — 을 쓰므로 obs가 stale이어도 외삽이 정확한 한 streak **그 자체로는 큰 위치 점프를 안 만듦**. (30) 체감 어긋남이 진짜였다면 root cause는 (a) **호스트 오디오 자체가 streak 동안 멈춤**(stream `ACTIVE` 이탈 / xrun → 외삽은 "갔을 거"로 추정하지만 실제 출력 못 감) 또는 (b) **재생 시작 직후 streak이 첫 anchor establish 시점을 늦추거나 잘못된 baseline에 박음** 분기. (31) state + xrunDelta 진단이 이 (a)/(b) 분기 가리는 용도 — 재발 시 해당 컬럼 우선 확인.

10. **iOS host 환경 검증** — Mac 환경 필요.

11. ~~**의존성 업데이트 검토**~~ — **2026-05-02 완료 (v0.0.57~v0.0.62)**. 6개 commit:
    - v0.0.57 안전 묶음 (patch/minor 8개)
    - v0.0.58 just_audio 죽은 의존성 제거
    - v0.0.59 audio_session 0.1→0.2
    - v0.0.60 network_info_plus 죽은 의존성 제거
    - v0.0.61 file_picker 8→11 (정적 메서드 마이그레이션)
    - v0.0.62 flutter_riverpod 2→3 (코드 변경 0)
    - **보류**: `device_info_plus` 12→13 + `package_info_plus` 9→10 (file_picker 11이 win32 ^5에 묶여 충돌. file_picker가 win32 ^6 지원할 때 묶음 commit). API 무변경이라 미루는 부담 작음.
    - **다음**: 실기기 풀세트 회귀 테스트 (특히 audio_session 0.2 BT 라우팅 + file_picker 11 + riverpod 3 onDispose 사이클).

**🆕 [신규, 2026-05-10] clock sync 인프라 정밀화 — wallclock → monotonic clock**
- 변경 영역: `sync_service.dart` 핑퐁 t1/t3 + `audio_obs.dart` broadcast hostTimeMs + 오디오 엔진 native 측 timestamp + `native_audio_sync_service.dart` event timestamp 등 wallclock 사용 모든 위치
- API: Android `SystemClock.elapsedRealtimeNanos()` (Kotlin) / iOS `mach_absolute_time()` + `mach_timebase_info` (Swift)
- 이론적 가치: OS NTP 자동 보정 점프 영향 0 + ms → ns 정밀도. § D-2 gap 임계 2ms → 1ms 좁힘 가능, fallback 임계 30ms → 10~15ms 좁힘 가능
- 우리 환경 ROI: 측정 데이터로 추정 시 winMinRaw range가 매우 좁음 (v0.0.56 idle 3분 2ms span) → OS 점프 거의 없는 듯. **v0.0.74 cold start 측정 결과가 만족스러우면 보류, 부족하면 진행**.
- 작업량: 1~2일 (양 플랫폼 native 채널 + 일관 변경 + 디버깅용 wallclock 병행 출력)
- 위험: 변경 범위 크나 알고리즘 그대로 → 회귀 위험 보통

**🆕 [신규, 2026-05-10] clock sync broadcast 주기 단축 (500ms → 200ms)**
- 변경 위치: `native_audio_sync_service.dart` `_obsBroadcastIntervalMs` (라인 518-520)
- 효과: 첫 fresh obs 도착 빨라짐 → anchor establish 자연 wait ↓ (cold start 끝 부분 추가 단축)
- 우려: p2p 트래픽 2.5배 ↑ → 호스트 부담 (사용자가 호스트 부담 우려로 보류 의사 표시)
- v0.0.74 cold start 측정 결과 보고 결정. 만족스러우면 보류, 부족하면 검토.

### LOW

11. **errno=65/51 분기 캡처 (v0.0.28 백업 경로)** — connectivity_plus 즉시 반응으로 우회됨. AP 이동 or 다른 AP 시나리오에서만 캡처 가능. 코드 변경 0, 실기기 2대 + 2개 AP.

12. **HISTORY (47) Tab A7 Lite 호스트 framePos 비대칭** — D-1 시도 회귀 후 보류. 호스트 측 정규화 또는 다른 방향.

13. **acoustic loopback 외부 측정** (선택, 항목 8 검증에서 잔여 100ms+ 시 우선순위 ↑) — OS API 한계(BT codec/radio 단계 미보고) 잡으려면 마이크로 round-trip 측정. AOSP CTS 표준 방식.

14. ~~**iOS 26.4.1 + macOS 26.3 환경 빌드 install hung**~~ — **회피 표준화 완료 (v0.0.71 (84) 후속)**. CLAUDE.md "실기기 빌드/설치" + "iOS debug 빌드 디버거 attach 필요" 섹션 갱신. CLI hung 발생 시 잔재 프로세스 정리 명령어 + IntelliJ/Xcode 권장 명시. 근본 fix(Apple/Flutter toolchain 측 이슈)는 미해결이지만 **운영 측면에선 표준 우회로 마감**.

15. **디버그 모드 호스트 간헐적 스터터** — 릴리스에선 무관.

16. **UI 폴리싱** — Phase 4 확장 전 MVP 마감 다듬기.

17. **v0.0.74 Run 1 영구 잔재 root cause** (HISTORY (90), SYNC_ALGORITHM_V2 §B v0.0.74-fix) — 2026-05-10 측정 4회 중 1회 (Run 1)에서 vfDiff -47ms 영구 잔재 발견, 가드 적용 후도 비결정적 발생 가능. 자체 정상화 메커니즘이 Run 2/3/4은 작동, Run 1만 미작동. 사용자 청감으론 4건 모두 OK라 실용 영향 작음. **진단 후보**: (a) anchor 시점 진짜 outLatDelta 베이크값을 `_logGuestEvent('anchor_set')`이 보내는 csv row 컬럼에 추가 (현재 `_sendDriftReport`에서 outLat 인자 안 넘겨 default 0), (b) 자체 정상화 메커니즘 (Run 2/3/4의 -100→-2 자체 회복) 트리거 코드 추적, (c) csv vfDiff 식이 진짜 음향 어긋남보다 큰 잔재 보고 가능성 검증 (청감 비교 측정).

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

**결정 (2026-06-01): 일회성 "프로" IAP** — 구독 ❌ / 광고 ❌ / 자체 서버 ❌. 근거 상세는 [DECISIONS.md](DECISIONS.md).

### 모델

| 기능 | 무료 | 프로 (일회성 결제) |
|------|------|---------|
| 동기화 재생 | O | O |
| 동시 연결 | 2대 (호스트+게스트1 = 1:1 동기화 체험) | 무제한 (3대+) |
| 광고 | 없음 | 없음 |
| 추후 확장 여지 | | 무손실·EQ·스테레오 분리 등 |

가격은 5,000~9,900원 범위에서 출시 후 결정.

### 왜 일회성인가 (구독·광고 아님)

- **구독 안 함**: 유틸+로컬 동작 앱은 "정적 기능에 월정액" 저항이 큼 (2026 능동 해지율 31%→47%, 유틸 앱 일회성 회귀 트렌드). 동기화는 "정해진 일을 잘하는 도구"라 일회성이 맞음.
- **광고 안 함**: 재생 후 화면을 안 봐서(백그라운드) 배너 노출이 적어 수익 미미. AdMob + iOS ATT 권한 + 개인정보처리방침 부담만 늘어 제거.
- **자체 서버 안 함**: `in_app_purchase` non-consumable + `restorePurchases`(서버 0) 또는 RevenueCat(MTR $2,500까지 무료, Firebase 불필요 — anonymous App User ID 단독). 구독 갱신/해지 관리 복잡성 없음.

### 결제 흐름 (서버리스)

앱 → 스토어 IAP 구매 → `restorePurchases` / RevenueCat entitlement → 로컬 프로 잠금해제. Firebase Functions 영수증 검증 불필요(RevenueCat 쓰면 검증도 대행).

### 구현 시점

무료로 먼저 출시(수익화 코드 0) → 사용자·반응 확보 → 그 후 일회성 IAP 추가(며칠 작업). 아래 출시 전략과 일치.

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

### Phase 3: 수익화 (일회성 프로 IAP — 서버리스)

> **2026-06-01 방향 전환**: 기존 "구독 + Firebase Functions 자작 검증" 설계 **폐기** → **일회성 프로 IAP / 서버리스**. 위 "수익화 전략" + [DECISIONS.md](DECISIONS.md) 참조. 무료 먼저 출시하고 수익화는 출시 후 추가.

#### 3-1. 결정 (확정)

| 항목 | 결정 |
|---|---|
| 모델 | 일회성 "프로" 잠금해제 (구독 ❌) |
| 무료/유료 경계 | 2대(호스트+게스트1) / 무제한(3대+) |
| 광고 | 없음 |
| 계정 | 불필요 (스토어 계정 기반 복원) |
| 백엔드 | 자체 서버 0 — `in_app_purchase` 단독 또는 RevenueCat |
| 가격 | 5,000~9,900원, 출시 후 결정 |

#### 3-2. 기술 스택

- **결제**: `in_app_purchase` non-consumable + `restorePurchases()`, 또는 RevenueCat(`purchases_flutter`). 둘 다 자체 서버 0.
- **Firebase 불필요**: 구독 영수증 검증/Firestore 상태저장 불요. RevenueCat은 anonymous App User ID로 단독 동작(Firebase Auth도 불요).
- **기능 gating**: 로컬 구매 상태 → Riverpod provider → 연결 대수 제한(무료 2대).

#### 3-3. 구현 순서 (출시 후)

1. App Store Connect / Google Play Console에 non-consumable 상품 1개 등록(`synchorus_pro`). 샌드박스 테스트 계정 확보.
2. `in_app_purchase`(또는 RevenueCat) 연동 + 구매/복원 UI — `SettingsScreen` "프로 잠금해제" 섹션.
3. 로컬 구매 상태 → Riverpod provider → 연결 대수 게이팅. 미결제 시 3대째 연결 시도에 프로 안내.
4. 심사 필수: IAP **restore** 버튼, 환불 정책, 약관/개인정보 URL.

#### 3-4. 리스크

- **클라 검증 한계**: `in_app_purchase` 단독은 영수증 로컬 검증 빌트인 없음([flutter#52522]) → 크랙 가능성. 소액 앱은 감수, 우려 시 RevenueCat(검증 대행).
- **심사**: 핵심 동기화 재생은 무료라 "핵심 기능 과도 제한" 거절 위험 낮음.

#### 3-5. 비용

- **자체 서버 0** → Firebase 과금 없음.
- **스토어 수수료**: 신규·소규모 **15%** (Apple Small Business Program / Google 구독·SBP). 100만 달러 초과 시 30% 전환(행복한 고민).
- RevenueCat 쓰면 MTR $2,500까지 무료, 초과분 1%.

### Phase 4: 확장
- [ ] WebRTC 전환 (원격 P2P 지원)
- [ ] 볼륨 개별 제어 (디바이스별)
- [ ] 스테레오 분리 (L/R 채널 할당)
- [ ] 재생 목록 (Playlist)
- [ ] QR 코드로 방 참가
- [ ] 이퀄라이저
- [ ] 블루투스 레이턴시 수동 보정 슬라이더
- [ ] 파일 전송 대역폭 개선 후보 (현 TCP over 공유 WiFi 구조에선 소프트웨어로 낼 수 있는 수치 도달, 체감 향상은 링크 계층 변경 필요):
    - [ ] TCP `SO_SNDBUF` 조정 — 저비용, 효과 편차 큼
    - [ ] multi-stream 다운로드 (같은 파일 N개 TCP 병렬) — 중간 비용, AP가 WiFi 6+ 일 때 효과
    - [ ] Wi-Fi Direct / iOS MultipeerConnectivity — 공유기 거치지 않고 기기 간 직접 연결 (AirDrop급 속도). 크로스플랫폼 호환 위해 양 네이티브 플러그인 직접 구현 필요
    - [ ] HTTP 다운로드를 별도 Isolate로 분리 — 속도보다는 heartbeat 처리 안정성 목적 (v0.0.23 노트 참고)
- [ ] 라이프사이클·연결 추가 개선 후보 (v0.0.25 MVP 이후. 상세: `docs/LIFECYCLE.md`의 "앱 라이프사이클", "소켓 에러 코드(errno)", "연결 복구 전략" 섹션):
    - [x] ~~`RoomLifecycleCoordinator` 클래스 추출~~ — v0.0.29에서 구현 (`HISTORY.md` 2026-04-23 (21)). `lib/services/room_lifecycle_coordinator.dart` 신설, 라이프사이클/재접속/상태 로직 약 320줄 흡수. UI는 `ValueListenableBuilder` + 콜백만.
    - [x] ~~`AppLifecycleState.detached`에서 `host-closed` broadcast~~ — v0.0.26에서 구현 (`broadcastHostClosedBestEffort()`). 실측 1.4초 복구 확인(Android, 재생 중 케이스).
    - [x] ~~errno=111 refused 2회 연속 감지 시 watchdog 빠른 포기~~ — v0.0.27에서 구현 (`HISTORY.md` 2026-04-23 (19)). 이론 복구 시간 ~10초.
    - [x] ~~errno=113 EHOSTUNREACH / errno=101 ENETUNREACH 감지 시 `connectivity_plus` 이벤트와 연동~~ — v0.0.28에서 구현 (`HISTORY.md` 2026-04-23 (20)). `_maybeHandleNetworkErrno` 헬퍼 + 두 곳 호출.
    - [x] ~~`_awayReconnectTimer` 주기 조정 여지~~ — v0.0.27에서 `Socket.connect` timeout `5→2초` 적용. 12회 실패 시 실제 시간 ~2분 → ~1분 이내.
    - [ ] iOS 실기기에서 라이프사이클·재접속 시나리오 T1~T4 재검증 — 2026-04-24 (22)에서 S22 + Pixel 6 에뮬 조합으로 T1~T4a PASS 확인했으나 iOS 미검증 유지. iOS의 background audio 미활성 상태에서 paused 동작 특히 확인 필요.
    - [x] ~~errno=111 빠른 포기(v0.0.27) / errno=113·101 연동(v0.0.28) 실측 재검증~~ — 2026-04-24 (23)에서 S22+iPhone 실기기 LAN 조합으로 T4b 실측 PASS (~10초 fast giveup). 과정에서 Linux errno만 체크하던 v0.0.29 버그를 iOS 실측으로 발견 → v0.0.30에서 Darwin errno(61/65/51) 추가해 해결. W의 errno=65/51 분기 자체는 타이밍상 재현 안 됐으나 일반 재연결 성공.
