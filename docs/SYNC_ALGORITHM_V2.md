# Sync Algorithm V2 — Design

v0.0.48 baseline 알고리즘의 한계 ((42) Android 게스트 fallback drift edge case, (45) -20.84ms 잔재, 거짓말 패턴 등)를 정공법으로 풀기 위한 디자인 문서.

**작성 의도**: v0.0.49~v0.0.61 시도 사이클(2026-04-27 (44))처럼 "fix 시도 → 측정 → 회귀 → 또 fix" trial-and-error 반복을 회피한다. 코드 작성 전에 결정 사항을 모두 명문화하고 사용자 합의 후 단일 commit으로 구현.

---

## 작업 흐름 (강제)

순서 — 어긋나면 다시 처음으로:

1. **csv 측정 인프라 강화** (단순 작업, 진단 도구) — sync 동작 변경 0
2. **이 문서 작성** (`docs/SYNC_ALGORITHM_V2.md`) — 코드 X, 결정 사항 A~F 빈칸 채우기
3. **사용자 합의** — 디자인 명세 검토. 합의 안 되면 2번으로 복귀.
4. **한 번에 단일 commit으로 알고리즘 구현** — 명세 따라 단순 변환
5. **측정 검증** (idle + 사용자 연타 환경 분리)

이 문서가 다음 알고리즘 작업 세션의 **첫 commit**이어야 한다. 코드는 그 후.

---

## 작성 요령

각 결정 사항(A~F)마다 다음 4 섹션을 모두 채운다:

- **선택지 (예 3가지)** — 각 옵션의 장단점
- **race 시나리오 시뮬레이션** — 사용자 연타 / 빠른 정지·재생 / 비행기 모드 시 어떻게 동작하는지 예상
- **검증 방법** — 측정 어떤 csv 컬럼/이벤트가 결과로 나올지 미리 명시
- **합의된 결정** — 사용자 검토 후 확정. 미정 시 비워둠.

선택지 비교는 표로. race 시나리오는 시간축 timeline으로.

---

## A. 두 측정값 결합 규칙 (`drift_ms` × `vfDiff`)

`drift_ms`(호스트와 게스트 framePos 비교)와 `vfDiff`(virtualFrame 격차)는 의미가 다르다. 두 값이 어떻게 조합되어 "정상/이상"을 판정하고 어떤 액션을 트리거하는지 결정.

- **선택지**:
  - (A1) drift_ms 단일 기준, vfDiff는 진단만
  - (A2) AND 조합 (둘 다 임계 미만이어야 정상)
  - (A3) OR 조합 (한쪽만 큰 경우 별도 액션 분기)
- **race 시나리오 시뮬레이션**: 사용자 seek 연타 시 vfDiff는 일시 큰 값으로 치솟지만 drift_ms는 cooldown 후 정상 복귀. A2(AND)면 두 값 동시에 임계 미만 도달까지 비정상 판정 길어져 false alarm. A3(OR)는 vfDiff outlier만으로도 액션 트리거 → 회귀 위험. A1은 drift_ms 기준만 보므로 거짓말 패턴(vfDiff 큰데 drift 작음) 발생 시 무시 → 측정상으론 잡혀도 청감 영향 작음.
- **검증 방법**: csv `vf_diff_ms` + `drift_ms` 시계열 → 거짓말 패턴 frequency 측정. v0.0.62 N=3에서 vfDiff -10~14ms / drift -2~5ms로 거짓말 패턴 발현 미관찰 (3분 측정 한계 가능).
- **합의된 결정**: **A1 (drift_ms 단일 기준, vfDiff는 진단만) — 현행 유지**. 근거: N=3 측정에서 거짓말 패턴 미관찰 + A2/A3는 청감 검증 안 된 새 액션 도입(회귀 위험). vfDiff는 csv 진단 + 향후 §D-2 fix 후 N=3+ 측정에서 본격 분석.

거짓말 패턴 — `vfDiff > X` AND `drift_ms < Y`인 경우 액션:
- ~~(옵션) anchor 무효화~~ — 보류
- ~~(옵션) 게스트 강제 reseek~~ — 보류
- **(채택) 무시 (v0.0.48 현재 동작)**

---

## B. outputLatency 보정 메커니즘

iOS/Android 양쪽의 `outputLatency`가 BT 환경에서 비대칭(특히 iPhone 게스트 첫 ~40초 워밍업, Apple Forum #679274). 보정 방식 결정.

- **선택지**:
  - (B1) **베이크인** — anchor 시점 1회 측정해 `_anchoredOutLatDeltaMs`로 고정 (v0.0.38 현행)
  - (B2) **EMA 점진 수렴** — 매 obs마다 `latencyEMA = α·current + (1-α)·prev` 보정 (v0.0.51~v0.0.55 시도, v0.0.55에서 vfDiff 23배 회귀)
  - (B3) **cap 상한 제한** — outputLatency 변화량이 임계 초과하면 무시
- **anchor reset 시 EMA 누적값 보존 여부** — v0.0.60 한계 회피. 보존하면 anchor reset 후에도 계속 수렴 진행, 폐기하면 매 reset마다 처음부터.
- **race 시나리오 시뮬레이션**: B2 EMA 시도 시 anchor reset → EMA 누적값 보존하면 reset 직후 outputLatency가 직전 baseline으로 끌려가 큰 jump 발생, 폐기하면 매 reset마다 fast phase 처음부터 → fallback alignment에 jitter. v0.0.55 회귀(vfDiff 23배)가 정확히 이 패턴. B1 베이크인은 reset 시 1회 재측정만 → race 없음.
- **검증 방법**: csv `out_lat_host_raw` / `out_lat_guest_raw` / `out_lat_delta_current` / `out_lat_delta_anchored` 4개 컬럼. v0.0.56 (60) 측정에서 `delta_current - delta_anchored` = +0.22ms (mean) → EMA 효과 사실상 0 확인. iPhone BT 워밍업 케이스만 추가 측정 필요(현재 데이터는 갤럭시+갤럭시).
- **합의된 결정**: **B1 (베이크인) — 현행 유지**. 근거: (60) 측정 anchored vs current diff 0.22ms로 EMA 효과 미미 + v0.0.51~v0.0.55 EMA 시도 vfDiff 23배 회귀 + race 위험. iPhone BT 워밍업 케이스는 별도 항목(PLAN MID-8 BT 워밍업 잔여 개선)으로 분리.

### v0.0.74-fix 후속: outputLatency 안정 가드 (2026-05-10)

**배경**: v0.0.74에서 fast phase 제거로 cold start wait 단축했더니 **호스트 outputLatency 안정 wait가 노출**되어 회귀 발생. 측정에서 호스트가 stream 활성화 후 1.9~4초까지도 `calculateLatencyMillis`가 `Result::Error` 반환 (HAL timestamp 측정 불가) → `safeOutputLatencyMs` 가 0으로 변환 → 그 시점에 anchor 박히면 `outLatDelta = 0` 잘못 베이크 → 게스트 syncSeek 위치 자체가 어긋남 → **vfDiff 영구 잔재** (Run 1 -47ms 케이스, 자체 정상화 안 일어남).

**Oboe API 알려진 이슈 (Issue #678)**:
- `calculateLatencyMillis()` 내부 식: `latency = nextFramePresentationTime - nextFrameWriteTime`
- HAL hardware clock(CLOCK_MONOTONIC, presentationTime)과 system steady_clock(writeTime) 동기 불일치 시 음수 반환 가능
- 디바이스/HAL 의존 — 일부 디바이스에선 `Math.abs()`로 우회 가능, 우리는 0으로 무시(보수적).

**fix 결정 — anchor establish에 outputLatency 안정 가드**:

```dart
// _establishAnchor (라인 1248-1253)
if (obs.hostOutputLatencyMs <= 0) return;       // 호스트 HAL latency 측정 안정 전
if (ts.safeOutputLatencyMs <= 0) return;        // 게스트 HAL latency 측정 안정 전
```

`safeOutputLatencyMs`가 -1/음수/>500을 모두 0으로 변환하므로 **0 가드 한 줄로 모든 비정상 케이스 차단** (Issue #678 음수, Result::Error -1, outlier 모두).

**Oboe 진단 logging 추가** (`oboe_engine.cpp:411-432`):
- 비정상 raw 값 추적용. 첫 5회 + 매 50회 throttle.
- 안정 도달 시 `recovered after N abnormal: X.XXms` 로그.
- stream 활성화 시 `mLatDiagCount = 0` reset.
- 디바이스/Android 버전별 안정 wait 패턴 진단 가능.

**측정 검증 (2026-05-10 (90))**:

| Run | vfDiff mean | 평가 |
|---|---|---|
| Run 1 (이전, 가드 전) | -82ms | 큰 회귀 |
| Run 1 (가드 후, 비결정) | -47ms (영구 잔재) | 1/4 비결정 outlier |
| Run 2 (mp3 변경) | -7.51ms | baseline ✅ |
| Run 3 (새 방) | -12ms | baseline 근처 |
| Run 4 (1분, 대부분 케이스) | **+1.81ms** | **baseline 매우 좋음** |

logcat 검증:
```
13:47:19.453 calcLatency abnormal[0]: ErrorInvalidState   ← stream Pausing
... 4452ms 동안 abnormal 누적
13:47:23.906 calcLatency recovered after 45 abnormal: 8.19ms
```
→ 가드가 4.5초 동안 anchor 차단 → 정상값(8.19ms) 도달 후 박힘. **fix 효과 확정**.

**남은 미스터리**:
- Run 1 영구 잔재 (1/4 케이스)는 가드 적용 후도 비결정적으로 발생. 자체 정상화 메커니즘 (Run 2/3/4은 작동, Run 1만 안 함) 트리거 미파악.
- 사용자 청감으로는 모든 케이스 OK — csv 식 한계 또는 음악 특성으로 47ms 못 느낀 가능성.
- 후속 진단: anchor 시점 진짜 베이크값 csv 컬럼 추가 + 자체 정상화 메커니즘 추적.

---

## C. rate drift 1% 보정

게스트 측 sample rate가 호스트와 미세하게 다르면 (1% 가정) 30분 누적 시 약 18초 drift. 현재 (v0.0.48)는 보정 없음.

- **선택지**:
  - (C1) **주기 강제 reseek** — vf-correction 100ms 임계 초과 시 seek (v0.0.58 시도)
  - (C2) **native sample rate 조정** — `oboe::AudioStream::setSampleRate` (가능한지 확인 필요) / iOS는 `AVAudioEngine`의 reconnect로만 가능
  - (C3) **virtualFrame 진행 속도 보정** — 게스트 측 rate match. Dart 레이어에서 시간 진행률 조정.
- **race 시나리오 시뮬레이션**: C1 주기 강제 reseek는 사용자 정상 seek와 race 가능 — seek cooldown(v0.0.20 도입)과 충돌. C2 native rate 조정은 audio glitch 위험. C3 virtualFrame 보정은 anchor와 진행 속도 사이 일관성 깨질 위험. 모두 race 도입 위험 큼.
- **검증 방법**: 30분+ 장시간 idle 측정 (PLAN MID-7) — vf_diff_ms 누적 추세 + rate slope 추정. 현재 3분 측정은 데이터 부족.
- **합의된 결정**: **결정 보류** — 30분+ 장시간 측정(PLAN MID-7) 후 데이터 기반 결정. 현재 3분 측정에서 vfDiff signed mean ~-11ms 수준이라 rate drift 누적 추세 미관찰. 보류 사유: 결정 못해서가 아니라 측정 인프라 부족.

---

## D. anchor 분리 여부

현재 (v0.0.48): anchor 1개 (framePos + virtualFrame 동시점). 호스트 정지/재생/seek마다 reset → fallback 단계 (5초) 동안 큰 drift 발생 ((42) edge case).

- **선택지**:
  - (D1) **현행 단일 anchor 유지** — 단순, 회귀 위험 낮음
  - (D2) **anchor 2개 분리** — `rate anchor` (framePos 기준, 거의 reset X) + `position baseline` (virtualFrame 기준, 절대 정렬). 둘이 어떻게 상호작용?
  - (D3) **NTP-style 예약 재생** — wall clock 기준 양쪽 동시 시작. v0.0.47 시도 후 race로 롤백, 정밀 작업 필요.
- **race 시나리오 시뮬레이션**: D2 anchor 2개 분리 시 — host pause→play 사이클에서 rate anchor와 position baseline이 다른 시점에 갱신되면 두 값이 일관성 깨질 위험. seek 연타에서 baseline 갱신 race + rate anchor 보존 race 동시 발생 가능. D3 NTP는 v0.0.47 시도에서 호스트 broadcast 직후 게스트 schedule 도달 사이 race로 양쪽 시작 시점 불일치 → 큰 초기 drift. 정밀 race 차단 필요. D1은 race 표면적 최소.
- **검증 방법**: D2/D3 채택 시 — 사용자 연타 시나리오(pause/play 5회 빠르게, seek 연타) csv 시퀀스 점검. event 컬럼 11종 시퀀스 정상성. 청감 — 음성 끊김/지터 발생 빈도. **단일 anchor 유지 시**: §D-2 fix 후 (42) edge case 자연 완화 가능성 (잘못된 anchor 박힘 줄어들면 reset 후 fallback drift도 작아질 것).
- **합의된 결정**: **D1 (현행 단일 anchor 유지)**. 근거: (44) 13번 사이클 교훈 — 알고리즘 변경 = race 도입 위험 + (42) edge case의 root cause가 §D-2 결함과 직결되어 §D-2 fix 후 자연 완화 가능성. D2/D3은 §D-2 fix 측정 결과 부족할 때 후속 검토.

---

## D-2. clock sync 안정 판정 — `isOffsetStable` 결함 (2026-05-02 (60) 신규)

v0.0.56 진단 컬럼(`raw_offset_ms`/`win_min_raw_offset_ms`/`last_rtt_ms`/`win_min_rtt_ms`) 추가 후 측정으로 발견. anchor가 EMA 수렴 전 박혀 부정확한 offset이 베이크인되는 root cause.

**현행 동작 (v0.0.48~v0.0.56 동일)**: `SyncService.isOffsetStable`은 "step별 filtered 변화량 < 2ms 5회 연속"으로 판정 (`sync_service.dart:267-272`). slow phase α=0.1에서 매 step 변화 = (raw - filtered)×0.1이라 큰 gap이 누적된 상태에서도 step별로 작아 false positive 가능.

**증거 (v0.0.56 idle 3분, S22 host + Tab A7 Lite guest, `measurements/v0.0.56_idle_2026-05-02.csv`)**:

| 컬럼 | mean | range | span |
|---|---|---|---|
| **win_min_raw_offset** | -752.76 | -754 ~ -752 | **2ms** (진짜 안정 offset) |
| filtered_offset | -752.02 | -753.60 ~ -740.60 | **13ms** (EMA lag) |
| raw_offset (단일) | -753.71 | -940 ~ -624 | 316ms (RTT outlier) |
| last_rtt | 30 mean | 6 ~ 465 | (outlier 빈번) |
| win_min_rtt | 8.47 mean | - | (window min 매우 안정) |

**Anchor 시퀀스 (결정타)**:

| NR | event | filtered | win_min_raw | gap |
|---|---|---|---|---|
| 39 | anchor_set | -740.6 | -752.0 | **11.4ms!** (EMA 미수렴인데 stable로 판정) |
| 52 | reset (6초 후) | -745.9 | -752.0 | 5.3ms 따라잡음 → 임계 5ms 초과 |
| 53 | anchor_set | -745.9 | -752.0 | 6.1ms 차이 |
| 85 | reset (17초 후) | -751.0 | -752.0 | 5.1ms 따라잡음 |
| 86 | anchor_set | -751.0 | -752.0 | 1ms (드디어 수렴) |

→ **clock skew 아님**. **EMA convergence lag**. 이전 (59) 가설("clock skew") 폐기.

**선택지**:

- **(D2-1) winMinRaw 일치 기준** — `(filteredOffsetMs - winMinRawOffsetMs).abs() < _stableThresholdMs`로 stable 판정. 1줄 변경. v0.0.56 데이터로 winMinRaw가 ±1ms 안정 확인 → 신뢰 가능 기준값. 단점: winMinRaw도 일시 outlier 시 흔들림 가능 (window=10이라 영향 작음).
- **(D2-2) AND 조합** — 기존 변화량 < 2ms AND winMinRaw 일치 둘 다. 보수적. 안정 판정 5~15초 늦어질 수 있음.
- **(D2-3) fast phase 길이 + α 조정만** — `_fastPhaseCount` 10→20 또는 α=0.5→0.3. 알고리즘 구조 변화 없음. 단 저변동 raw 환경에서 더 느림.

**예상 trade-off**: anchor establish가 5~15초 늦어짐 → 첫 재생 정착 시간 (PLAN HIGH 3) 더 길어질 수 있음. 그 동안 fallback alignment(거친 정렬)만 작동. 청감 비교 필수.

**race 시나리오**: stable 판정 늦어지는 동안 사용자 seek/play/pause 연타 시 — fallback alignment 단계에서 어떻게 동작? 현재도 anchor 없으면 fallback이라 동등하지만 시간이 길어질 뿐. v0.0.62 N=3 측정에서 fallback 21개(3회차) 동안 청감 정착 ~1~2초 도달 확인 → fallback 길어져도 청감 영향 작음.

**N=3 데이터 (2026-05-02 (68)/(69)) — fix 효과 시뮬레이션**:

| 케이스 | 첫 anchor 시점 / EMA gap | D2-2 (AND) 적용 시 | 청감 예상 |
|---|---|---|---|
| 1회차 (운 좋음) | NR 12, 0.1ms | 통과 (둘 다 ✓) → 변화 없음 | 그대로 좋음 |
| 2회차 (흔들림) | NR 5, 2.0ms | winMinRaw gap = 임계 borderline → 미통과 → anchor 미루어짐 | **30초 흔들림 사라질 가능성 ⭐** |
| 3회차 (운 보통) | NR 23, 11.7ms | winMinRaw gap >> 2ms → 미통과 → anchor 미루어짐 | 청감 OK (현재도 OK) |

→ 운 나쁜 케이스(2회차 패턴)가 일관되게 좋음으로 수렴 기대.

**검증 방법**:
- v0.0.56 이후 csv 컬럼 `raw_offset_ms` / `win_min_raw_offset_ms` 차이 시계열 → stable 판정 시점에 gap < 2ms 충족하는지
- anchor_set 이벤트 시점의 (filtered - winMinRaw) gap이 임계 미만인지 — **모든 케이스에서 gap < 2ms로 수렴해야 함**
- reset 빈도 (v0.0.55/v0.0.56 idle 3분 4회 → fix 후 1~2회로 감소 기대)
- vfDiff 잔재 변화 (v0.0.55 -16ms → fix 후 변화)
- 청감 (idle 시작 후 첫 ~30초) — 1/2/3회차 같은 패턴이 좋음/좋음/좋음으로 수렴하는지
- N=3+ 재측정 필수 — N=2로는 변동성 단정 어려움

**합의된 결정**: **D2-2 (AND 조합) 채택** (v0.0.63 적용). `(filteredOffsetMs - _prevFilteredOffset).abs() < _stableThresholdMs && (_filteredOffsetMs - _winMinRawOffsetMs).abs() < _stableThresholdMs`로 stable 판정. 근거:
- D2-1(winMinRaw 일치만)은 step 조건 제거 — winMinRaw outlier 시 false positive 위험
- D2-2는 step 변화량(EMA 진동 작음) + winMinRaw 일치(EMA가 진짜 값에 가까움) 둘 다 보장 → false positive 최소
- D2-3(상수만)은 root cause 안 고침
- 변경: 기존 1줄 → 2줄로 확장 (AND 조건 추가). `_winMinRawOffsetMs`는 (60) v0.0.56에서 이미 추가된 필드 → 코드 변경 최소

### v0.0.74 후속: fast phase 제거 (2026-05-10)

§D-2 AND 조합이 false positive 보호망으로 충분히 작동한다는 전제로 v0.0.74에서 cold start wait 단축 작업:

- **변경 1 (early termination)**: 초기 핸드셰이크 30 ping 무조건 받기 → ≤10ms RTT sample 10개 모이면 즉시 종료. 30 cap fallback 유지.
- **변경 2 (carry over)**: 30 ping 중 best 1개를 `_recentWindow` 맨 뒤에 추가. 9초간 minSample 안전망.
- **변경 3 (fast phase 제거)**: `_emaAlphaFast/_emaAlphaSlow/_fastPhaseCount` 3개 상수 → `_emaAlpha = 0.1` 단일. `_periodicSampleCount` 필드 제거. fast phase 분기 6곳 정리. carry over로 출발점 안정 + §D-2 gap 보호 전제로 fast phase 무용화.
- **변경 4 (stable 5번 그대로)**: `_stableRequiredCount = 5` 유지. 보수적 — false positive 보호망 그대로.

**예상 효과**: cold start wait 18초+ → 약 8~10초 (LAN 안정 환경). 좋은 LAN에선 early termination 작동 시 추가 단축.

**위험 분석**:
- 불안정 WiFi에서도 §D-2 gap이 자가 진단으로 작동 — minSample 변동 시 gap 커짐 → stable 안 됨 → 안전 wait. 회귀 위험 없음.
- carry over best가 outlier일 가능성 — 측정 분포에서 ≤5ms 비율 0.1%로 매우 낮음. 첫 주기 sample 들어왔을 때 §D-2 gap이 자동 검증.

**측정 검증 (2026-05-10 (90))**:
- ✅ Cold start 1.9~3.5초 (이전 18초 대비 5~9배 단축, 의도대로)
- ❌ vfDiff 회귀 발생 — Run 1 -82ms, Run 2 -11.7ms (baseline -5~-7ms 대비 2~11배)
- 🔍 Root cause: anchor establish가 outputLatency 안정 wait 도달 전에 박힘. 호스트가 1.9~4초 재생 후도 outputLatency=0 보고. **이전 fast phase 10초가 outputLatency 안정 wait 우연히 cover했음**. v0.0.74에서 그 cover 사라지면서 본래 누락된 outputLatency 가드 노출.
- → fix 방향: anchor establish에 `outputLatency > 0` 가드 추가 (offset 동기화 자체는 정상, 본 §D-2 fix 결정 유지).

**구현 위치**: `lib/services/sync_service.dart:271`

```dart
// 현재
} else if (delta < _stableThresholdMs) {
  _stableCount++;
} else {
  _stableCount = 0;
}

// 변경 후
} else if (delta < _stableThresholdMs &&
           (_filteredOffsetMs - _winMinRawOffsetMs).abs() < _stableThresholdMs) {
  _stableCount++;
} else {
  _stableCount = 0;
}
```

**Trade-off 인정**: 첫 anchor 시점이 5~15초 늦어질 가능성. fallback 단계 길어지지만 N=3 데이터 기준 청감 영향 작음. fix 후 N=3+ 측정으로 청감 분포 검증 필수.

### v0.0.80 후속: outlier rejection + age limit + stable window 가드 (2026-05-14 HISTORY (96))

**배경**: 사용자 청감 "최근 (v0.0.74 이후) 옛날(v0.0.72)에 비해 약간 어긋남". csv/logcat 깊은 분석:

- 사용자 환경 WiFi raw RTT 분포: 14~20ms 15% / 45~110ms 28% / 111~250ms 38% / 251~499ms 19%
- v0.0.79 EMA: 단발 outlier 흡수했지만 지속 흔들림 (좋은 sample 한동안 안 들어옴) 시 minSample이 jitter sample로 갈리고 EMA가 천천히 표류 → **22초 18ms 표류** 실측 (청감 임계 ±20ms 근접)

**사용자 통찰** (매우 중요, 디자인 결정 핵심):
> "흔들리는 환경 수용하면 안 됨. wall clock 자체는 환경 무관이고 RTT만 환경 영향" → adaptive 임계 부정, **고정 strict 30ms 임계** 채택

**변경 사항 (`sync_service.dart`)**:

1. **Periodic sync outlier rejection** (`_rejectThresholdMs = 30`):
   - raw RTT > 30ms sample은 window 추가 안 함 (EMA/stable 변화 0)
   - 30ms 근거: RTT/2 = 15ms 최악 비대칭 노이즈 → 청감 임계 ±20ms 안전 영역
   - 우리 환경 통과율 ~15%
2. **Sample age limit** (`_sampleAgeLimitMs = 60_000`):
   - window 안 sample 60초 지나면 자동 제거
   - 60초 근거: wall clock 상대 drift 누적 ±6ms 수준 (±50ppm × 60s × 2 device)
   - stale offset 박힘 차단 (사용자 우려 "1시간 동안 sample 안 들어오면 stale" 방어)
3. **`isOffsetStable` 가드 보강**: `_stableCount >= 5 && _recentWindow.length >= 3`
   - carry over 1개만 남은 상태에서 false positive 차단
4. **`_prevFilteredOffset` carry over 같이 set**: 첫 periodic sample stable=0 손해 제거
   - v0.0.74 carry over 의도 완성
   - isOffsetStable 도달 6→5초 단축
5. **`_earlyTermRttThresholdMs` 10 → 20**: jitter 환경에서도 초기 핸드셰이크 early termination 도달 가능
6. **진단 로그 추가**: `Raw sample` / `Raw sample REJECTED` / `[STABLE TOGGLE]`

**측정 검증 (실기기 S22 + A7 Lite)**:
- ✅ filtered offset 표류: 18ms (v0.0.79) → **0.3ms (v0.0.80)** = **60배 감소**
- ✅ STABLE TOGGLE: false→true 14초, 그 후 false 토글 0회 (영구 안정)
- ✅ 사용자 청감: "대체적으로 다 좋음"
- ⚠️ 측정 마지막 부분 vfDiff -250ms 영구 잔재 발견 (drift는 ±3ms로 작음) — **sync 자체 정확하나 anchor 베이크인 outputLatency 매핑 부정확**. HISTORY (42)/(45) 미해결 이슈 영역과 같음. 본 commit 범위 밖.

**1단계 한계**:
- 1시간 jitter 환경에서 carry over expire → window 빈 상태 → filtered 동결
- 우리 환경에선 1분에 RTT < 30 sample 평균 9개 들어와 거의 발생 안 함
- 2단계 burst sync 재실행 fallback은 후순위 (PLAN HIGH 후속)

### v0.0.81 후속: ANCHOR-VERIFY 사후 검증 + 자동 무효화 (2026-05-14 HISTORY (97))

**배경**: v0.0.80 (96) 측정 마지막 부분 vfDiff -250ms 영구 잔재 → 사용자 청감 어긋남. sync 자체는 정확하나 anchor 매핑 부정확. 사용자 가설 "obs 순서 보장 안 됨" 코드 검토 결과 TCP 순서 OK이지만 **게스트 측 seek 명령 처리 race**가 진짜 root cause (큰 seek 연타 시 native가 정확히 도달 못 함).

**디자인 — 사후 검증 + 자동 무효화**:

`_tryEstablishAnchor` 직후 100ms 시점에 게스트 ts.virtualFrame이 targetGuestVf와 임계 초과 차이면 anchor 자동 무효화 + 다음 obs 도착 시 재시도. 사고 자동 회복.

```
[anchor establish: target=X, _seekCorrectionAccum += initialCorrection]
   ↓ 100ms 후 (다음 ts poll)
[ANCHOR-VERIFY] target vs ts.virtualFrame 비교
   ↓ diffMs > 500ms?
[REJECT 시]:
  - _seekCorrectionAccum -= initialCorrection (잘못 적용된 보정 되돌리기)
  - _anchorHostFrame / _anchorGuestFrame / _anchoredOutLatDeltaMs 무효화
  - _driftSamples.clear()
  - csv event: anchor_reset_verify_fail
  - 다음 obs 도착 시 _tryEstablishAnchor 재시도
```

**임계 500ms 근거**:
- 평소 100ms 후 측정값 ~90ms (seek 도달 디코더 wait, 정상)
- 500ms = 5배 안전 마진
- 사고 케이스(수십 초~수백 초 잔재)만 잡고 정상 동작 영향 0

**측정 검증 (실기기 큰 seek 연타 시나리오)**:
- ✅ ANCHOR-VERIFY REJECT 9회 발동 (anchor_set 29회 중 31% race rate)
- ✅ REJECT diffMs 사례: -34988 / 178437 / 125645 / 30958 / 11906 / -8686 / -769 / -151300 ms
- ✅ 매 REJECT 직후 다음 anchor 정상 박힘 (자동 회복)
- ✅ 사용자 청감 사고 인지 0회 = fix가 백그라운드 정확 처리
- ✅ 정상 anchor diffMs 0~100ms 영향 0
- player UI sync info도 100ms 주기 실시간 갱신 (`StreamBuilder<Duration>(stream: positionStream)`)

**추가 정직성**:
- 임계 500ms는 보수적 — 200~300ms strict화로 -769ms 같은 경계 케이스 잡을 수 있음. 다만 false positive 위험 → 측정 더 모은 후 조정 (PLAN HIGH 후속).
- ANCHOR-VERIFY deadline 100ms 너무 짧을 수 있음 — 디코더 wait 더 긴 케이스 정확 측정 위해 300~500ms 보강 가능.
- obs 신선도 가드(`obs.hostTimeMs` 검사) 미적용 — TCP 순서는 OK이지만 호스트 측 broadcast 시점 race 안전망으로 추가 가능.

### v0.0.82 후속: 호스트 syncSeek `_broadcastObs()` 제거 (2026-05-15 HISTORY (98))

**배경**: v0.0.81 (97) ANCHOR-VERIFY 자동 회복 작동 확인 후, 사용자 보고 신규 시나리오 "호스트 seek 했는데 게스트가 새 위치 갔다 옛 위치로 돌아옴" + "vfDiff -250ms 영구 잔재". race 자체의 진짜 root cause 격리.

**사용자 핵심 통찰** (진단 결정적):
> "tcp라 모든 명령 순서대로 간다며 그럼 게스트가 받기전 다른 명령이 갔을리가 없잖아"

→ 메시지 순서 race 아니라 **호스트 측 race**. 코드 정독으로 확정.

**진짜 root cause** (`native_audio_sync_service.dart:syncSeek`):
```dart
await _engine.seekToFrame(clampedTarget);  // Android Oboe 비동기 (즉시 return)
_p2p.broadcastToAll({'type': 'seek-notify', ...});
_broadcastObs();  // ⚠️ native seek 처리 전 ts 측정 → stale virtualFrame broadcast
```

호스트가 seek-notify (정확한 새 위치) + audio-obs (stale 이전 위치) 두 메시지 보냄. 게스트:
1. seek-notify 처리 → `seekToFrame(새 위치)` → 게스트 새 위치 점프 ✓
2. audio-obs 처리 → `_latestObs = stale 이전 위치` ⚠️
3. ts poll → fallback alignment: stale obs vs 게스트 새 위치 = 큰 drift → `seekToFrame(옛 위치)` → **게스트 옛 위치로 돌아감** ⚠️

**Fix (v0.0.82, 1줄)**: 호스트 `syncSeek` 안 `_broadcastObs()` 호출 제거. 정기 timer broadcast (`_obsBroadcastIntervalMs = 500ms` 주기)가 native seek 완료 후 정확한 obs 보냄.

**검증 (v0.0.85 임시 시점 실기기)**:
- ✅ 옛 위치 race 재현 안 됨 (사용자 보고)
- ✅ 사용자 청감 "괜찮음" 보고
- ⚠️ 가끔 몇 초 무음 (호스트 큰 seek 후 ~500ms transient — 정기 timer 주기 안 stale obs 잔존)

**오늘 학습 (잘못된 시도 정직히)**:

| 시도 | 효과 | 평가 |
|---|---|---|
| ANCHOR-VERIFY accum 재계산 (v0.0.82 임시) | cascade race 부분 fix | surface symptom, root cause 아님 |
| `_handleSeekNotify`의 `_latestObs = null` (v0.0.83 임시) | fallback 차단 안전망 | surface symptom, v0.0.86 시 호스트 옛 위치 신규 race 유발 |
| `_fallbackAlignment`의 `_seekCooldownUntilMs` 가드 (v0.0.83 임시) | seek 직후 fallback skip | surface symptom |
| **호스트 `_broadcastObs()` 제거 (v0.0.82, 1줄)** | **stale obs broadcast 자체 차단** | **진짜 root cause fix** |

→ "복잡한 fix 여러 개" 대신 "진짜 root cause 1개 격리"가 정답. 사용자 통찰이 결정적.

**남은 문제 (PLAN HIGH 후속)**:
- ✅ ~~정기 timer broadcast 500ms 주기 — 그 사이 stale obs로 가끔 몇 초 무음 가능~~ — v0.0.83 fix 완료
- ⏳ ANCHOR-VERIFY 단독 청감 부작용 미격리 (N=1 평가 한계)
- ⏳ `_latestObs = null` 시도 시 "호스트도 옛 위치" 신규 race (원인 미상)

### v0.0.83 후속: `_fallbackAlignment`에 `_seekCooldownUntilMs` 가드 (2026-05-15 HISTORY (99))

**배경**: v0.0.82 (98) 호스트 syncSeek 즉시 stale obs broadcast 차단 후 남은 문제 — 정기 timer broadcast(500ms 주기) 안 잔존 stale obs로 가끔 몇 초 무음.

**root cause**: 호스트 큰 seek 직후 ~500ms 동안 게스트 `_latestObs` stale → `_fallbackAlignment`가 stale obs로 옛 위치 잘못 seek → native PCM 디코드 wait → 무음.

**일관성 발견**: `_handleSeekNotify`에서 `_seekCooldownUntilMs = now + 1000` set. `_tryEstablishAnchor`는 이미 사용(line 1322), 그러나 `_fallbackAlignment`는 무시.

**Fix (1줄)** (`_fallbackAlignment`):
```dart
if (ts.wallMs < _fallbackAlignCooldownMs) return;
if (ts.wallMs < _seekCooldownUntilMs) return;   // ← NEW
if (driftMs.abs() > 30) { ... }
```

**효과 (실기기 N=여러 회)**:
- ✅ 가끔 발생하던 무음 안 나타남
- ✅ 부작용 없음 (anchor 그대로 작동, 호스트 측 영향 0)

**v0.0.86 `_latestObs = null` 시도와 안전성 비교**:
- v0.0.86: obs 객체 무효화 → fallback **및 anchor** 모두 skip → 호스트 영향 알 수 없는 신규 race
- v0.0.83: fallback만 skip → anchor 그대로 → 안전

**남은 문제**:
- ANCHOR-VERIFY 단독 청감 부작용 격리 (N=여러 회 측정 필요)
- 호스트 빠른 seek 연타 시 native 디코드 wait 무음 (별도 영역, v0.0.83 fix와 무관)

---

## E. 임계 정확 값

각 보정 액션이 발동하는 임계값. 값 자체보다 **왜 그 값인지**가 핵심 (사용자 청감 미인지 한계 + 측정 noise floor 균형).

- **drift_ms 정상 임계** (현행): 5ms — anchor reset 트리거. v0.0.43 baseline 검증 청감 OK.
- **vfDiff 정상 임계** (현행): 30ms — vf-correction seek 트리거. 사용자 청감 미인지 한계 25~40ms 범위에서 채택.
- **clock sync stable 임계** (현행): `_stableThresholdMs = 2.0ms` — `sync_service.dart:36`.
- **비정상 시 액션 단계**:
  - (작은 보정) seek by Δ — vfDiff > 30ms 시 발동
  - (중간) anchor reset — drift_ms > 5ms 또는 offset 변동 시 발동 (§D-2 fix 후 빈도 감소 예상)
  - (강한) 강제 seek to host position — 미사용 (fallback alignment로 충분)
- **race 시나리오 시뮬레이션**: 임계값 변경 시 — 작게(예: drift 3ms) 잡으면 anchor reset 빈도 ↑ → fallback drift 빈발 → 청감 회귀. 크게(예: drift 10ms) 잡으면 진짜 drift 누적 미감지 → 장시간 재생 누적 어긋남. 현행 5ms는 v0.0.43 baseline 청감 검증된 값.
- **검증 방법**: §D-2 fix 후 N=3+ 측정에서 anchor_reset 빈도가 idle 3분 4회 → 1~2회로 감소하면 임계값 자체는 그대로 두고 root cause(EMA stable 판정)가 해소된 것. fix 후에도 reset 빈도 높으면 임계값 재검토.
- **합의된 결정**: **현행 임계 모두 유지** (drift 5ms / vfDiff 30ms / stable 2ms). 근거: 청감 검증된 baseline + §D-2 fix가 임계 변경 없이 root cause 해결 가능 + 임계 변경은 새로운 측정 사이클 트리거. fix 후 측정 결과 부족할 때 재검토.

---

## F. race 차단 메커니즘

v0.0.51 debounce / v0.0.59 마지막-이김 / v0.0.47 NTP 모두 race로 회귀. 명확한 직렬화 필요.

- **호스트 측 syncPlay/Pause/Seek**:
  - (F1) FIFO 큐 (모든 호출 순서대로)
  - (F2) 마지막-이김 (debounce, v0.0.59에서 회귀)
  - (F3) 미들웨어 lock (한 번에 하나만)
- **게스트 측 메시지 처리**: `_handleSchedulePlay` / `_handleSchedulePause` / `_handleAudioObs` 동시 진행 차단 — async lock or message queue.
- **race 시나리오 시뮬레이션**: F1 FIFO는 사용자 5번 빠른 seek 시 5번 모두 처리 → 마지막 위치 도달까지 ~수 초 lag. F2 debounce는 마지막 1번만 처리 → 빠르지만 v0.0.59에서 자동 정지 race + 끝 도달 race 회귀. F3 lock은 처리 중인 호출 종료 대기 → 사용자 체감 응답 지연. 현행 v0.0.48은 absolute targetMs + cooldown(v0.0.20) + 세션 ID(v0.0.20)로 가장 흔한 race(seek 연타) 차단 — 실용적 lock 형태.
- **검증 방법**: 사용자 연타 시나리오 — pause/play 5회 빠르게(0.2초 간격), seek 연타 10회. csv `event` 컬럼(11종) 시퀀스 정상성 + 청감 음성 끊김/지터.
- **합의된 결정**: **현행 v0.0.48 race 차단 메커니즘 유지** (absolute targetMs + cooldown + 세션 ID + 동기화 메시지 직렬 처리). 근거: v0.0.51 debounce / v0.0.59 마지막-이김 / v0.0.47 NTP 모두 race로 회귀 → 현행이 검증된 baseline + §D-2 fix가 race 차단과 무관 (clock sync 안정 판정만 변경). race 메커니즘 변경은 별도 트랙으로 분리.

---

## G. PCM streaming + 하이브리드 시작 패턴 (2026-05-11 신규)

**배경**:
- Android 현행 `oboe_engine.cpp:155` `mDecodedData.assign(estFrames × ch × sizeof(int16_t))` 사전할당 패턴 → 곡 길이 비례 메모리 (5분 ≈ 58MB), 14분 한도 (`:143` 150MB cap). PLAN MID-7 30분+ 측정 막힘.
- iOS는 `AVAudioFile + scheduleSegment`가 OS 레벨 streaming이라 이미 무관 → 이번 변경은 **Android를 iOS 동작 모델로 정렬**.
- 부수적으로 시작 / 큰 seek 시점의 sync 잔재 처리 패턴도 같이 명세.

### G-1. PCM 메모리 모델 — 사전할당 → Ring buffer

- **선택지**:

  | 옵션 | 메모리 | 곡 길이 한도 | 구현 비용 | seek 비용 |
  |---|---|---|---|---|
  | (현행) 전체 사전할당 | 곡 비례 (5분=58MB) | 14분 | 0 (현행) | 항상 즉시 |
  | (G1-A) Ring buffer 고정 60s | 일정 (~11.5MB) | 무제한 | 중간~큼 | 버퍼 안=즉시, 밖=재디코드 |
  | (G1-B) 청크 LRU 캐시 | 조절 가능 | 무제한 | 큼 | 캐시 hit=0, miss=재디코드 |
  | (G1-C) 디스크 PCM + mmap | ~0 RAM | 디스크 한도 | 중간 | 디스크 seek (SSD ms) |

- **race 시나리오 시뮬레이션**:
  - **사용자 큰 seek 연타** (10분 → 30분 → 5분 → 25분, 0.3초 간격): 디코드 head가 매번 점프 + 직전 디코드 abort. abort 안전성 (디코드 스레드 mid-frame 종료) 확인 필요. 현행 `mDecodeAbort` (`oboe_engine.cpp:166`) 패턴 재사용 가능.
  - **재생 중 OS swap-out** (백그라운드 진입 → 메모리 회수): ring buffer는 일정 크기라 swap-out 영향 작음. 사전할당은 큰 영역 swap → 복귀 시 page fault 폭증.
  - **디코드 underrun** (디코드 스레드가 재생보다 늦음): 재생 head가 디코드 head를 따라잡으면 무음 발생. 안전 마진 (Pre-fill) 필수.

- **검증 방법**: csv 신규 컬럼:
  - `pcm_buf_used_ms`: ring buffer 점유 분량 (ms)
  - `pcm_buf_underrun_count`: 재생 head가 디코드 head 따라잡은 횟수
  - `decode_throughput_frames_per_ms`: 매 디코드 cycle throughput EMA
  - 30분+ 측정 (PLAN MID-7) 자연 해소: 이전 14분 한도 → 무제한.

- **합의된 결정** (2026-05-11 확정):
  - ✅ **G1-A Ring buffer 채택** (단일성, iOS 정렬, race 안전성)
  - ✅ **버퍼 크기 60초** (~11.5MB) — 음악 앱 사용 패턴에 충분
  - ✅ **behind/ahead 분배 = 10s / 50s** — 짧은 rewind 흡수 + 디코드 여유 충분
  - ✅ **Pre-fill (재생 시작 임계) = 1초 분량** — mp3 디코드 빠르니 안전 마진 1초
  - ✅ **`TOO_LONG` 한도 완전 제거** (`oboe_engine.cpp:143-148` 삭제) — streaming이라 의미 없음
  - ✅ **G-1과 G-2 분리 commit (2026-05-11)** — 원안 단일 commit에서 변경. 이유: native 변경 + Dart 상태머신 묶음이 회귀 추적 어려움. G-1 단독 검증으로 ring buffer 정상 동작 격리 검증 후 G-2 별도 commit (race 격리). G-1 단독은 큰 seek 시 v0.0.74 fallback 패턴 그대로 유지.
  - ⚠️ **G-1 v0.0.76 도입 후 race 발견 → v0.0.79 revert (2026-05-12 HISTORY (95))**. 큰 seek 슬라이더 연타 시나리오에서 호스트/게스트 둘 다 무음 (`virtualFrame`은 계속 흐름). v0.0.75 비교 실험 PASS로 ring buffer race 확정. 4개 atomic (`mRingHead`/`mRingTail`/`mDecodeSeekTarget`/`mDecodePts`)으로는 "seek 요청 → ring reset → decodeLoop 응답" 단일 트랜잭션이 안 보장.
  - ✅ **G-1 v0.0.84 재도입 — 큐 모델 fix + EOS wait fix (2026-05-17 HISTORY (100))**. PoC 격리(`poc/native_audio_engine_android`)에서 sine generator + ring buffer로 race 재현 + fix 검증 25회(RACE 25% 발현, FIX 0% 차단) 후 본 앱 합치기. 핵심:
    - **큐 모델 fix**: 외부 `seekToFrame`은 `mDecodeSeekTarget`만 store + cv notify, ring head/tail은 안 건드림. `decodeLoop`이 단일 thread로 ring head/tail 갱신 + codec flush + extractor seekTo 처리. → 외부 thread와 인터리브 race 자체 차단.
    - **EOS wait fix**: v0.0.76 누락 — `while (!outputEos && !mDecodeAbort)` 조건은 곡 끝 도달 시 decode thread 종료. ring buffer 60s sliding window라 thread 종료 후 seek 불가 → 영구 무음 (5분 곡에선 vf 4분 10초 도달 시 자연 발화, behind 10s + ahead 50s 분배 산식). 변경: `while (!mDecodeAbort)` + EOS 시 cv wait → seek 도착 시 `outputEos=false` 재개.

### G-2. 시작 / 큰 seek 패턴 — Ready-then-Go 하이브리드

기존 v3 폐루프(평상 시 ±5~7ms, HISTORY HIGH 4 §D-2 검증)는 **시작 후 1~2초 내 수렴**. 잔재는 시작 직후만 청각 인지 가능 → 시작 시점 처리만 신규 결정.

**실측으로 잡힌 회귀 (2026-05-11 HISTORY (91))**:
- 큰 seek (사용자 슬라이더) 직후 호스트 obs broadcast 갭 (최대 500ms) 안에 게스트 syncSeek 처리 → `_fallbackAlignment`가 stale obs + seek 후 ts 비교 → driftMs 100초+ 발생
- v0.0.74 측정 vfDiff abs_max 177,845ms / v0.0.75 156,028ms — step 1 변경 무관 확정 (v0.0.74 기존 race)
- 회복: fallback seek (driftMs>30 → seekToFrame) 1~2초 내 ±5ms 수렴, 청감은 회복 구간 인지
- **G-2 하이브리드가 이 race를 정확히 fix** (ready timeout 200ms로 양측 obs/anchor 동기화 후 시작 → race 0)

- **선택지**:

  | 옵션 | 호스트 응답성 | 시작 시점 잔재 (정상/BT) | 청각 인지 |
  |---|---|---|---|
  | (G2-i) Ready-then-Go (모든 게스트 ready 대기) | 0.3~0.5초 대기 | ±10ms / ±20ms | 거의 없음 |
  | (G2-ii) 호스트 즉시 + 게스트 catch-up (예측 점프) | 즉시 | ±70~150ms / ±200ms+ | 명확 |
  | (G2-iii) 하이브리드 (ready timeout 200ms) | 정상=동시 / 느린 게스트 있을 때만 즉시 | ±10ms / ±50ms | 정상=없음, BT=살짝 |

- **race 시나리오 시뮬레이션**:
  - **사용자 seek 후 빠른 재seek** (T0: 30분 broadcast → T0+150ms: 5분 broadcast): 게스트가 첫 prepare 디코드 중 두 번째 도착. `_downloadSessionId` 패턴 (`native_audio_sync_service.dart:710`) 응용 → `_seekSessionId` 도입, 첫 디코드 abort + 두 번째로 진행.
  - **느린 게스트 ready 200ms 미달** (디코드 슬로우 디바이스): 호스트 + ready된 게스트는 즉시 시작, 느린 게스트는 예측 점프로 catch-up. 시작 후 폐루프(audio-obs)가 1~2초 내 ±5ms 수렴.
  - **게스트 ready 신호 dropped (네트워크 jitter)**: 5초 timeout → 해당 게스트 dead peer 후보 (P2P heartbeat 기존 메커니즘 재사용).

- **검증 방법**: csv 신규 컬럼:
  - `start_pattern`: `ready_then_go` / `host_immediate_with_catchup` / `single_guest_only`
  - `ready_wait_ms`: 호스트가 ready 신호 대기한 시간 (0 = 즉시 시작)
  - `start_drift_ms`: 시작 직후 첫 audio-obs 측정 drift (ready-then-go 검증)
  - `catchup_recovery_ms`: 시작 후 ±5ms 도달까지 시간 (하이브리드 효과 검증)
  - 청감 테스트: 같은 공간 호스트+게스트 청취 시 시작 시점 인지 가능성.

- **합의된 결정** (2026-05-11 확정):
  - ✅ **G2-iii 하이브리드 채택**
  - ✅ **Ready timeout = 200ms**
  - ✅ **Seek 즉시/대기 분기**: 재생 중 큰 seek = G-2 하이브리드 (`syncSeek`이 `_initiatePrepareAndStart` 호출), 일시정지 중 seek = 기존 `seek-notify` 흐름, 작은 drift 보정 seek = `_engine.seekToFrame` 직접 호출 (변경 없음)
  - ✅ **Ready timeout 후 동작**:
    - (a) 200ms 내 모두 ready → 동시 시작 (`ready_then_go`)
    - (b) 미달 있음 → 호스트 + ready된 게스트 즉시 시작 (`host_immediate_with_catchup`), 미달 게스트는 schedule-play 받아 wallEpochMs에 시작 (디코드 못 따라가면 잠시 무음 후 polling으로 회복)
    - (c) 5초 내 ready 안 됨 → 해당 게스트 dead peer 처리 후보 (기존 heartbeat 메커니즘과 통합, 별도 race 메커니즘 도입 X)
  - ✅ **v0.0.47 `scheduleStart` 인프라 그대로 활용** (`native_audio_service.dart:149-154`) — 추가 native 코드 거의 없음
  - ⚠️ **v0.0.77 구현 후 회귀 → v0.0.78 revert (2026-05-12 HISTORY (94))**. 실기기에서 "호스트 큰 seek 직후 무음, 새 음원 로드해야 풀림" 증상. 두 차례 fix 시도(원래 + seekToFrame이 ring head/tail 미수정) 모두 stuck 미해소 → decodeLoop가 멈춘다는 강한 신호. G-1 ring buffer baseline (v0.0.76)으로 복귀. **재시도 전제**: `_ReadyCollector` (Dart 측) ↔ `decodeLoop` (native) ↔ `seekToFrame` (native) 셋의 상태 전이를 atomic만이 아니라 native 측에서 단일 mutex/cv로 직렬화하는 동기화 재설계 필요. ring head/tail/seek target은 decodeLoop 단일 thread에서만 set, 외부는 "요청 큐"로만 영향.

### G-3. 디코드 throughput 동적 캘리브레이션

G-2 하이브리드의 "예측 점프" (catch-up 게스트가 미래 호스트 위치로 seek) 정확도를 위해 디코드 throughput 학습 필요.

- **선택지**:

  | 옵션 | 정확도 | 구현 비용 | 적용 시점 |
  |---|---|---|---|
  | (G3-A) 정적 평균값 (기기별 hardcoded) | ±50~100ms 잔재 | 0 | 즉시 |
  | (G3-B) 디코드 throughput EMA 학습 | ±10~30ms 잔재 | 작음 | 첫 N회 부정확 후 수렴 |
  | (G3-C) in-flight 폴링 (CPU spike 감지) | ±20~50ms 잔재 (spike 발생 시) | 중간 | 실시간 |
  | (G3-D) 누적 잔재 학습 (장기 보정) | 환경별 fine-tune | 큼 | 첫 점프 부정확 후 수렴 |

- **race 시나리오 시뮬레이션**:
  - **첫 점프 (학습 데이터 0)**: G3-A 정적 평균값으로 fallback. EMA는 첫 디코드 후 갱신.
  - **CPU spike 발생 중 점프**: G3-B EMA만으론 부정확 (평균값 < 실제). G3-C in-flight 폴링이 디코드 시작 후 throughput 실측 → `cancelSchedule` + 재등록 (다만 잦은 갱신은 sync 흔들림, threshold 필요).
  - **BT 라우팅 변동 중**: throughput 자체는 무관, `outputLatency` 변동으로 잔재 발생. 사후 폐루프(기존)에 위임.

- **검증 방법**: csv 신규 컬럼:
  - `decode_throughput_ema`: EMA 학습값 (frames/ms)
  - `predicted_decode_ms`: 예측 디코드 시간
  - `actual_decode_ms`: 실측 디코드 시간
  - `prediction_error_ms`: |예측 - 실측|
  - 측정 세션: 정상 환경 + CPU 부하 환경 + BT 환경 분리.

- **합의된 결정** (2026-05-11 확정):
  - ✅ **G3-B + G3-C 결합** — EMA 학습 (안정 시) + in-flight 폴링 (spike 대응)
  - ✅ **G3-D는 후속 작업** — 첫 출시 후 데이터 누적 시 검토
  - ✅ **측정 → 활용 분리**: 캘리브레이션 csv 컬럼은 **G-1 ring buffer PR과 같이 추가**해 데이터 먼저 확보, EMA 활용은 데이터 검토 후 별도 PR

### G-4. 작업 순서

`## 작업 흐름 (강제)` 형식 따라:

1. **csv 측정 인프라 추가** (G-1, G-2, G-3 컬럼 모두) — sync 동작 변경 0
2. **이 §G 섹션 사용자 합의** (위 confirm 대기 항목 모두 결정)
3. **단일 commit으로 G-1 ring buffer 구현** (`oboe_engine.cpp` 리팩터 + `TOO_LONG` 제거)
4. **단일 commit으로 G-2 하이브리드 시작 구현** (Dart `native_audio_sync_service.dart` ready 흐름 + iOS native scheduleSegment ready 콜백)
5. **G-3 캘리브레이션 측정 세션** (정상/CPU 부하/BT 환경 분리, 1일)
6. **G-3 EMA 활용 commit** (예측 점프 정확도 ↑)
7. **30분+ 측정 검증** (PLAN MID-7 자연 해소 확인)
8. **iOS 회귀 검증** (변경 작지만 ready 흐름 추가, 기존 단순 시작 시나리오 회귀 없음 확인)

각 commit 후 청감 검증 + csv 분석. 회귀 시 즉시 롤백.

### G-5. iOS 영향 정리

| # | 항목 | iOS 영향 |
|---|---|---|
| G-1 | Ring buffer | 없음 (이미 streaming) |
| G-2 | 하이브리드 시작 | **있음** — Dart 측 ready 흐름 + iOS native `scheduleSegment` 후 ready 콜백 추가 |
| G-3 | 디코드 throughput | iOS는 `loadFile` 시간 거의 0 → throughput 의미 작음. 대신 `scheduleSegment → 첫 frame 출력까지 시간` 측정 필요 (별도 지표) |

iOS native 코드 변경: `AudioEngine.swift`에 ready 콜백 메서드 추가 정도. 작음.

---

## H. Transpose (pitch shift, 시간 무변경) — 2026-05-29 신규

사용자 요구: 단독 모드 + P2P 양쪽에서 ±12 반음 transpose. UI는 슬라이더 + ± 버튼. cents=0이면 bypass(원음).

### H-1 첫 시도 실패 분석 (v0.0.91, 2026-05-29 revert)

세 번 시도, 세 번 모두 미달:

1. **Sonic (Bill Cox, Apache 2.0)** — `sonicWriteFloatToStream`에서 음수 cents 진입 시 SIGSEGV. 매 setPitch마다 stream destroy/create로 hack 우회했지만 RT-safety 위반 + 음악용 알고리즘 아님(speech 최적화).
2. **SoundTouch (Olli Parviainen, LGPL) 2.4.1 + 음악용 setting** — crash는 없지만:
   - **지지직(buzz)**: 매 callback (96 frames@48kHz=2ms)마다 `receiveSamples` 반환량 < numFrames → silence padding → 매 콜백마다 click → 빠르게 반복되면 buzz로 들림
   - **속도 저하**: while 루프로 SoundTouch 안정화 동안 input N회 부어 넣음 → 첫 콜백들에서 vf 너무 빠르게 진행 → 사용자 청감 "느려진 후 누적"
   - **단일 process per callback** 변경해도 안정화 동안 짧은 silence 지속 → 음질 불만
3. **공통 근본 문제**: 음악용 transpose 라이브러리(Sonic/SoundTouch/Rubberband 모두) = **batch processing** 알고리즘. 우리 LowLatency 콜백 burst (~96 frames) 너무 작음. callback 안에서 직접 process하는 패턴 자체가 mismatch.

### H-2 다음 시도 디자인 합의 항목

**아키텍처 결정 (PoC에서 검증):**

| # | 항목 | 결정 후보 |
|---|---|---|
| H-2-A | 라이브러리 | (a) SoundTouch (LGPL) (b) Rubberband (GPL, 음질 ↑ but 라이센스 부담) (c) ExoPlayer SonicAudioProcessor (Kotlin layer 통합) |
| H-2-B | 처리 위치 | (a) Worker thread + lock-free ring (b) Callback 안 batch 누적 후 process |
| H-2-C | Batch size | 4096+ frame (~85ms@48kHz) — 알고리즘 안정 처리량 |
| H-2-D | Output buffering | 자체 ring buffer (input 양 == output 양 보장, callback은 pop만) |
| H-2-E | Latency 보정 | `mST.numUnprocessedSamples()` 또는 input/output count로 algorithm latency 측정 → `outputLatencyMs`에 반영 → sync 알고리즘 자동 보정 |
| H-2-F | Bypass 분기 | `cents == 0` 시 ring → output 직접 (현 v0.0.91 패턴 유지, 음질 손실 0) |
| H-2-G | iOS | AVAudioUnitTimePitch 노드 (OS 내장) — Android worker 패턴과 별개 (iOS는 OS가 내부 처리) |
| H-2-H | P2P sync | (a) audio-pitch broadcast (v0.0.91 패턴) + outputLatency가 algorithm latency 흡수 (b) cents 변경 시 sync 알고리즘 일시 re-anchor |

**합의 권장값** (디자인 회의에서 확정):
- H-2-A: **SoundTouch 재시도** — LGPL 부담 작음, production 검증 (Music Speed Changer). Rubberband는 H-2 실패 시 fallback
- H-2-B: **Worker thread** — RT-safety + 음질 양쪽 만족하는 표준 패턴
- H-2-C: **4096 frames** — SoundTouch 음악 setting (SEQUENCE_MS=82, ~3936 samples)에 맞춤
- H-2-D: **Output ring** (mSTOutBuf로 v0.0.91 시도했지만 callback 안 처리라 실패. worker thread로 분리)
- H-2-E: **input/output count 차이로 latency 자동 측정** — outputLatency에 반영
- H-2-F: 채택
- H-2-G: 채택
- H-2-H: (a) — v0.0.91 broadcast 패턴 그대로 + outputLatency가 sync 자동 보정

### H-3 PoC 트랙 (poc/transpose_engine/)

**격리 원칙** (기존 §G PoC 패턴 따라):

| 포함 | 제외 (본 구현으로 미룸) |
|---|---|
| SoundTouch NDK 통합 | UI 통합 |
| Worker thread + ring buffer 패턴 | P2P broadcast |
| Algorithm latency 측정 + outputLatency 반영 | sync 알고리즘 |
| Bypass 분기 (cents=0) | 다중 audio source |
| 청감 검증 (반음 ±12 sweep) | iOS (별도 트랙) |

**측정 지표:**
- 청감: ±1~±12 반음 sweep, ±5 반음 즉시 변경 × 10회 — click/buzz 0 목표
- Timing: 1분 재생 후 input vf == output frame 차이 ±10ms 이내
- Algorithm latency: 측정된 값이 안정 (분 단위 변동 < 5ms)
- Underrun/glitch: 분당 0회
- CPU: 콜백 CPU usage 디폴트 대비 변화 < 10% (worker thread는 별개)

**통과 기준 (전부 만족 시 본 앱 통합):**
- ✅ 청감: ±12 sweep 동안 click/buzz/속도 변화 0
- ✅ Timing: ±10ms
- ✅ Algorithm latency 안정 + outputLatency 반영 동작 확인
- ✅ 30분 stress (반복 cents 변경) 안 crash

미달 시: SoundTouch 한계 확정 → Rubberband 또는 ExoPlayer SonicAudioProcessor 시도.

### H-4 작업 순서 (2026-05-29 진행 완료)

1. ✅ **사용자 합의** — H-2 항목 권장값 채택 (SoundTouch + worker thread + cents=0 bypass)
2. ✅ **PoC 디렉토리** `poc/transpose_engine/` — step 1 NDK build, step 2 callback 안 처리(silence padding 한계 객관적 재현), step 3 worker thread + ring(청감 click 0 통과)
3. ✅ **본 앱 통합 v0.0.91** (HISTORY (108)) — Android worker thread + 2개 ring(in/out), iOS AVAudioUnitTimePitch, Dart/UI/P2P
4. ⏳ Algorithm latency `outputLatencyMs` 반영 — sync 알고리즘 자동 보정 검증
5. ⏳ 30분 stress + 측정 보고서
6. ⏳ iOS 실기기 + P2P 게스트 동기화 실측
7. ⏳ Crossfade(Option C) — 필요 시 (현재 transition click 매우 미세)

### H-5 iOS 영향

| # | 항목 | iOS 영향 |
|---|---|---|
| H-2-A~F | Android worker pattern | 없음 (iOS는 AVAudioUnitTimePitch 단일 노드로 OS 내부 처리) |
| H-2-G | iOS 통합 | AVAudioEngine graph에 timePitch 노드 1개 추가 (5~10줄). H-1에서 검증 완료. |
| H-2-H | P2P sync | 같음 (양 platform broadcast 동일) |

iOS는 OS 알고리즘이라 PoC 격리 검증 불필요. AVAudioUnitTimePitch 내부 latency가 outputLatency에 반영되는지만 확인 (별도 측정 1회).

---

## I. 속도 조절 (tempo, pitch 유지) — 2026-05-29 신규

§H Transpose 통합 직후 추가. SoundTouch가 setTempo도 setPitch와 독립 지원 → 같은 worker thread + ring 인프라에 한 줄 추가. PoC step 4 생략, 본 앱 직접 통합.

### I-1 디자인 (사용자 합의)

- 범위 0.5x ~ 2.0x
- 5% 단위 (정수 5의 배수, 직접 입력 없음)
- UI: 가운데 슬라이더 + ±5% 버튼 + 표시 `1.00x` long-press reset
- transpose와 독립 (동시 사용 가능)
- 파일 변경 시 자동 reset (1.0x)

### I-2 Native 구조 (transpose와 차이)

| | Transpose (§H) | 속도 (§I) |
|---|---|---|
| Android API | `mST.setPitchSemiTones(cents/100.0f)` | `mST.setTempo(speedX1000/1000.0f)` |
| iOS API | `timePitch.pitch = Float(cents)` | `timePitch.rate = Float(speedX1000)/1000.0` |
| vf 진행 | numFrames 그대로 | **numFrames × speed** ← 핵심 |
| useST 조건 | cents != 0 | cents != 0 OR speed != 1.0 |

### I-3 sync 알고리즘 영향 (핵심 차이)

Transpose는 vf 진행 속도 무변경 → drift 계산 영향 0. 속도는 vf 진행이 N배라 drift 식 영향 가능:

- 기존 외삽: `expectedFrames = (hostWallNow - obs.hostTimeMs) * hostFpMs`
- 속도 적용 시: 같은 식 OK (vf 자체가 speed만큼 진행했으니 호스트/게스트 양쪽 동일 → 자동 상쇄)
- 다만 호스트/게스트가 같은 속도여야 — `audio-tempo` broadcast로 보장
- 다른 platform(Android worker thread + iOS AVAudioUnitTimePitch) 섞이면 algorithm latency 차이로 미세 drift 가능 → outputLatencyMs 보정으로 흡수 예상 (실측 후 확정)

### I-4 P2P 동기화

- 호스트 setPlaybackSpeed → `audio-tempo {speedX1000}` broadcast
- 게스트 _handleMessage → engine.setPlaybackSpeedX1000(...)
- audio-url에 `playbackSpeedX1000` 동봉 → 늦게 들어온 게스트도 호스트 현재 속도 적용

### I-5 미검증 (다음 세션)

- Edge case (시크바, A-B, 메모리, 5초 앞뒤, 일시정지, transpose+속도 조합)
- 30분 stress
- P2P 게스트 sync 실측 (핵심 — vf 진행 속도 변경 영향)
- iOS 실기기
- 시크바/시간 표시 정확도

---

## 핵심 학습 (2026-04-28 세션 종합)

이 문서를 채울 때 잊지 말 것:

- **사용자 청감 검증 > csv 수치 검증** — csv는 측정 한계 있음 (사용자 활동 중 외삽 부정확 가능성). 진짜 사용자 경험은 청감.
- **알고리즘 변경의 위험 = 새 race 도입** — v0.0.51 debounce 도입 → 자동 정지 race + 끝 도달 race, v0.0.55 D-1 → vfDiff 23배 회귀. 단순한 알고리즘이 안전.
- **csv 보강은 안전한 추가** — v0.0.49/v0.0.50처럼 측정 도구만 추가하는 작업은 회귀 위험 0.
- **단순성의 가치** — 검증 깊은 단순 알고리즘이 복잡한 측정상 우수 알고리즘보다 출시 안전.
- **사용자 좌절 = 신호** — "퇴보하는 것 같다" 우려 정당. 자존심 X, 정직한 평가 + 안전한 baseline 선택.
- **(44) v0.0.48 reset과 동일한 결말 위험** — 알고리즘 재설계 → race → 좌절 → 단순 baseline 복귀. **알고리즘 변경 시 청감 검증 깊이가 결정 척도**.

---

## 관련 문서

- 이력: [HISTORY.md](HISTORY.md) — (42) edge case, (43) v0.0.46~v0.0.48 시도, (44) v0.0.49~v0.0.61 reset, (45)~(50) v0.0.51~v0.0.53 진단 강화
- 아키텍처: [ARCHITECTURE.md](ARCHITECTURE.md) — 현재 (v0.0.48) sync 알고리즘 본문
- 결정: [DECISIONS.md](DECISIONS.md)
- backup branch: `backup-v0.0.61-session` — v0.0.49~v0.0.61 commit 13번 보존, `git log backup-v0.0.61-session --oneline`로 시도 흐름 확인 가능
