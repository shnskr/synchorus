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

**합의된 결정**: **D2-2 (AND 조합) 채택**. `(filteredOffsetMs - _prevFilteredOffset).abs() < _stableThresholdMs && (_filteredOffsetMs - _winMinRawOffsetMs).abs() < _stableThresholdMs`로 stable 판정. 근거:
- D2-1(winMinRaw 일치만)은 step 조건 제거 — winMinRaw outlier 시 false positive 위험
- D2-2는 step 변화량(EMA 진동 작음) + winMinRaw 일치(EMA가 진짜 값에 가까움) 둘 다 보장 → false positive 최소
- D2-3(상수만)은 root cause 안 고침
- 변경: 기존 1줄 → 2줄로 확장 (AND 조건 추가). `_winMinRawOffsetMs`는 (60) v0.0.56에서 이미 추가된 필드 → 코드 변경 최소

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
