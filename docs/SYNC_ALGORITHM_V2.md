# Sync 알고리즘 v2 디자인 (2026-04-28 작성, 합의 대기)

CLAUDE.md "다음 세션 작업 흐름 (강제)" 2단계. 코드 작성 전 사용자 합의 필수.

---

## 0. 동기 — 왜 v2인가

### v0.0.48 baseline 한계 (실측 캡처됨)

`docs/HISTORY.md` (45)의 v0.0.49~v0.0.50 측정으로 직접 확인:

1. **거짓말 패턴 (idle)**: drift_ms <5ms 안정인데 vf_diff_ms 30~50ms 일관 베이크인. anchor 시점 잘못된 차이가 4분 내내 풀리지 않음. 사용자 청감 미인지(<25~40ms 한계) 영역이라 v0.0.48이 "잘 맞아 보임"이지만 실제론 어긋남.

2. **누적 발산 (burst)**: 사용자 빠른 정지/재생/seek 연타 시 vfDiff **max 45.27초**. drift_ms는 1ms 이하 정상이라 알고리즘이 발산을 "정상"으로 판단 → 자가 회복 안 됨. fallback alignment(30ms 임계)는 좋은 메커니즘이지만 anchor 모드 진입하면 작동 안 함.

3. **메시지 race**: host_pause 175회 vs guest_stop 143회 = **32회 누락**. 호스트 정지했는데 게스트는 그 사이 계속 재생 → vf 누적 앞섬.

### v2 핵심 방향

- **drift_ms (rate) + vfDiff (절대 위치) 둘 다 본다**
- **anchor 분리** — rate anchor는 거의 reset 안 함, position baseline은 자주 강제 정렬
- **메시지 race 차단** — 호스트 cooldown + 게스트 큐 coalescing
- **outputLatency EMA 누적 보존** — anchor reset해도 보정값 유지

---

## 측정 데이터 요약 (디자인 근거)

### v0.0.49 idle (4분 5초, 459 drift 샘플)

| | abs mean | max | signed mean | 분포 |
|---|---|---|---|---|
| drift_ms | 3.01ms | 583ms (fallback 첫 보정) | -1.98ms | <5ms: 98.7% / <10ms: 100% |
| vf_diff_ms | 22.33ms | 60ms | -20.84ms | <5ms: 16.8% / 10-30ms: 40.7% / 30-50ms: 28.8% / >50ms: 0.4% |

### v0.0.50 burst (4분, 사용자 빠른 연타, 1589 rows)

| 이벤트 | 횟수 |
|---|---|
| host_play / host_pause | 175 / 175 |
| guest_start / guest_stop | 180 / 143 (**32회 누락**) |
| host_seek / anchor_reset_seek_notify | 307 / 307 |
| anchor_set | 30 |
| anchor_reset_offset_drift | 3 |
| drift / fallback | 242 / 27 |

drift 샘플 분포:

| | abs mean | max | signed mean | 분포 (vfDiff) |
|---|---|---|---|---|
| drift_ms | 2.56ms | 8.37ms | +0.49ms | <5ms: 96.3% |
| vf_diff_ms | 3194ms | **45269ms (45초)** | +3174ms | <5ms: 21.5% / 5-30ms: 52.5% / 30-100ms: 18.6% / 100-500ms: 0.4% / **>=3초: 7.0%** |

자세한 메커니즘 분석: `docs/HISTORY.md` (45).

---

## 결정 A — drift_ms + vf_diff_ms 결합 규칙

### 현재 (v0.0.48)
- `_recomputeDrift` (anchor 모드): drift_ms만 봄. |drift| ≥ 200ms → anchor reset, |median drift| ≥ 20ms → 작은 보정 seek.
- `_fallbackAlignment` (anchor 잡기 전): driftMs == vfDiffMs (vf 기반). |drift| > 30ms → 강제 reseek.
- 거짓말 패턴 못 잡음 (drift 1ms인데 vfDiff 45초여도 정상 판단).

### 선택지

**A-1. vfDiff 임계만 추가 (최소 변경)**
- `_recomputeDrift`에 `if (vfDiff.abs() > X) anchor 무효화 + 강제 reseek` 추가
- 장점: 변경 최소. driftMs 기반 기존 보정 로직 유지
- 단점: anchor 잡힌 후 세밀한 vfDiff 보정 안 됨 (큰 임계만)

**A-2. drift+vfDiff 2단 액션 (중간 변경)**
- 정상: drift <10ms AND vfDiff <50ms
- 작은 보정: drift 10-50ms OR vfDiff 50-500ms → 작은 보정 seek (correctionGain 0.8)
- 강제 reseek: drift >200ms OR vfDiff >500ms → anchor 무효화 + position 강제 정렬
- 장점: 두 측정값 같이 봄, 단계별 액션
- 단점: 임계 4개 튜닝 필요, 복합 조건 복잡

**A-3. fallback 모델로 통일 (큰 변경)**
- anchor 모드 폐지 또는 단순화 → 항상 fallback alignment 같은 단순 정렬 (vfDiff 30ms 임계 보정)
- drift_ms는 진단용 csv에만, 보정 로직엔 안 씀
- 장점: 단순. fallback이 burst에서 자가 회복 잘 작동 검증됨
- 단점: rate drift 측정·보정 메커니즘 없어짐 → 분 단위 1% drift 누적 못 잡음 (BT 비대칭 등)

### Race 시나리오 시뮬레이션

| 시나리오 | A-1 결과 | A-2 결과 | A-3 결과 |
|---|---|---|---|
| idle vfDiff 30~50ms 베이크인 | 임계 미만이면 미보정 (현 상태) | 50ms 임계로 작은 보정 → 정상 회복 | 30ms 임계로 작은 보정 → 정상 회복 |
| burst vfDiff 45초 | 임계 1초 → 강제 reseek 1번 | 임계 500ms → 강제 reseek 1번 | 30ms 임계마다 보정 (느림) |
| 빠른 seek 폭주 | anchor 자주 무효화 | 작은 보정 자주 + 강제 reseek 가끔 | 매 poll마다 보정 (과도?) |

### 검증 방법

새 csv 컬럼 추가 또는 event 활용:
- `corrective_seek_small` event (작은 보정 시) — 빈도가 너무 높으면 noise 보정 과다
- `corrective_seek_large` event (강제 reseek 시) — 사용자 연타 사고 시 발동 빈도

idle baseline에서 vfDiff <30ms 비율 측정 — 96% 이상이면 OK.

### 추천: **A-2**

이유: idle에서도 vfDiff 30~50ms는 자주 발생 (idle 28.8%) → A-1처럼 큰 임계만 두면 베이크인 영구 유지. A-3는 anchor 폐지로 rate drift 측정 잃음. A-2가 단계별 액션으로 세밀.

---

## 결정 B — outputLatency 보정 메커니즘

### 현재 (v0.0.48)
- anchor 시점에 outputLatency 비대칭(`_anchoredOutLatDeltaMs`) 1회 베이크인
- `_recomputeDrift`에서 변화분(`dynLatDeltaMs`)만 보정 → BT 분 단위 ±50ms 변동만 잡힘
- anchor reset 시 베이크인 값도 0으로 → **누적 학습 없음**

### 선택지

**B-1. 베이크인 유지 + reset 시 EMA 보존 (최소 변경)**
- anchor reset 시 `_anchoredOutLatDeltaMs`를 0이 아니라 마지막 EMA 값으로 보존
- 다음 anchor establish 시 EMA × α + 새 측정 × (1-α)로 점진 갱신
- 장점: 기존 구조 거의 유지. 누적 학습 추가만.
- 단점: 잘못된 EMA 값이 누적 오류 만들 가능성

**B-2. 매 poll EMA 갱신 (중간 변경)**
- anchor 모드에서 매 poll마다 outLatDelta 측정 → EMA 갱신
- 보정에 EMA 사용 (현재 변화분 보정 대신)
- 장점: 점진 수렴. BT 비대칭 자동 학습.
- 단점: outputLatency 노이즈가 EMA에 들어감. 안정화 시간 필요.

**B-3. cap + EMA 결합 (큰 변경)**
- EMA 갱신은 매 poll, 단 갑작스런 큰 변동(>200ms)은 cap으로 제한
- anchor reset 시도 EMA 보존
- 장점: 노이즈 강건성 + 누적 학습 + cap으로 outlier 차단
- 단점: 파라미터 3개 (α, cap, anchor reset 보존 정책) 튜닝

### 측정 근거

idle 4분간 vfDiff signed mean -20.84ms 일관 — outputLatency 비대칭이 ~21ms 베이크인됨. anchor reset이 거의 없는 idle 환경에서도 자가 보정 안 됨 = 현재 메커니즘 정적.

### 추천: **B-1**

이유: idle vfDiff 30~50ms 잔여는 단순 누적 학습으로 점진 수렴 가능. B-2/B-3는 추가 복잡성 — anchor 모드에서 outputLatency 매 poll 측정의 노이즈 영향 검증 필요. 단순 fix부터 시도 후 부족하면 단계 상승.

---

## 결정 C — rate drift 1% 보정

### 현재 (v0.0.48)
- 호스트와 게스트 native sample rate 미세 차이(~1%) 의심 (HISTORY (44))
- 보정 메커니즘 없음. drift_ms가 천천히 누적될 수 있음

### 측정 근거

idle 4분에서 drift_ms signed mean -1.98ms — rate drift 자체는 매우 작음. burst에서도 평균 +0.49ms. 사용자 청감으로 4분 내 인지 안 됨.

→ **rate drift 1%는 가설 단계. 실측에서 거의 안 보임.**

### 선택지

**C-1. 무시 (작업 안 함)**
- 4분 측정에서 보이지 않는 수준. 분 단위 누적은 anchor 자주 reset되며 자연 회복.
- 장점: 작업 0
- 단점: 한 시간+ 재생 시 누적 가능성 (검증 안 됨)

**C-2. 주기적 reseek 방어**
- 5분마다 vfDiff 검사 → 100ms+ 어긋나 있으면 강제 reseek
- 장점: rate drift 누적도 잡힘 (메커니즘 자체는 vfDiff 기반이라 rate 무관)
- 단점: A-2의 큰 임계와 중복 가능

**C-3. native sample rate 조정 (oboe setSampleRate / iOS rate)**
- 게스트가 호스트와 동일 rate 강제
- 장점: 근본 해결
- 단점: 코드 변경 큼. 플랫폼별 API 차이. 검증 인프라 필요.

### 추천: **C-1 (무시) + 결정 A-2가 사실상 C-2 역할**

이유: A-2의 vfDiff 큰 임계(500ms)가 rate drift 누적도 자동으로 잡음. 별도 메커니즘 불필요. 1시간+ 사용 시나리오에서 재검증 후 부족하면 C-3 검토.

---

## 결정 D — anchor 분리

### 현재 (v0.0.48)
- anchor 1개: `_anchorHostFrame` + `_anchorGuestFrame` (framePos pair)
- 호스트 seek 시 무효화 + 1초 cooldown → 새 anchor 잡기 시도

### 측정 근거

burst 4분 중 anchor_set 30회 / anchor_reset_seek_notify 307회 — **anchor 한 번 잡힐 때마다 평균 10번 reset**. 빠른 seek 폭주 시 cooldown 만료 전 또 reset → anchor 영원히 못 잡힘 → fallback만 작동 또는 최악의 경우 둘 다 작동 안 함.

### 선택지

**D-1. 분리 — rate anchor + position baseline (큰 변경)**
- **rate anchor (`_anchorHostFramePos` / `_anchorGuestFramePos`)**: framePos 기준. seek과 무관하게 유지. 분 단위 reset 안 함. drift_ms 측정 전용.
- **position baseline (`_lastSyncedHostVf` / `_lastSyncedGuestVf`)**: virtualFrame 기준. 매 seek-notify마다 강제 정렬. vfDiff 측정 전용.
- 둘 독립 유지. anchor reset 트리거 분리:
  - rate anchor: drift_ms >200ms (rate 폭발) — 거의 발생 안 함
  - position baseline: 매 seek-notify, vfDiff >500ms
- 장점: 빠른 seek 폭주 중에도 rate 측정 살아있음. 정밀 정렬 유지.
- 단점: 두 anchor 관리 복잡. 둘이 일관성 어떻게 보장하나?

**D-2. 단일 anchor + cooldown 제거 (중간 변경)**
- anchor 1개 유지하되 cooldown 1초 제거 → 매 seek 즉시 새 anchor
- 장점: 빠른 seek에도 anchor 따라감. 코드 변경 작음.
- 단점: stale obs로 잘못 잡힐 수 있음 → 거짓말 패턴 더 자주 발생 가능

**D-3. anchor 폐지 (큰 변경)**
- fallback alignment만 사용 (결정 A-3과 동일)
- 장점: 단순
- 단점: rate 측정 메커니즘 없어짐

### Race 시나리오 시뮬레이션

| 시나리오 | D-1 결과 | D-2 결과 | D-3 결과 |
|---|---|---|---|
| 빠른 seek 폭주 (burst) | rate anchor 유지 + position 매번 갱신 → drift/vfDiff 둘 다 정확 | anchor 매번 갱신, stale obs 자주 → 잘못 잡힐 수 있음 | rate 측정 없음, vfDiff만 |
| idle 4분 | rate anchor 1번 잡고 안정 + position 미세 보정 | anchor 1번 잡힘 (현 상태와 동일) | 매 poll vfDiff 보정 |
| anchor reset_offset_drift (현재 3회) | rate anchor만 reset, position 유지 | anchor 통째 reset | 해당 없음 |

### 검증 방법

새 csv 이벤트 추가:
- `rate_anchor_set` / `rate_anchor_reset` (드물게)
- `position_resync` (자주, 매 seek-notify)

burst에서 rate_anchor_reset 빈도가 anchor_reset_seek_notify의 1/10 이하면 분리 효과 확인.

### 추천: **D-1**

이유: 빠른 seek 폭주가 사용자 실사용 시나리오라 rate 측정 잃으면 안 됨. D-2는 stale obs 위험. D-3는 결정 C와 충돌 (rate drift 측정 없어짐). 단 D-1 구현 복잡성 있어 작업량 큰 편 — 디자인 단계에서 두 anchor 상호작용 정확히 명세 필요.

---

## 결정 E — 임계값

측정 데이터 기반:

| 임계 | 후보 값 | 근거 |
|---|---|---|
| `drift_normal` | **10ms** | idle 100% / burst 99.1% 만족. 여유 있음 |
| `drift_seek_threshold` | **20ms** (기존 유지) | 작은 보정 seek 임계. 노이즈 완화용 medianWindow 5 유지 |
| `drift_re_anchor` | **200ms** (기존 유지) | rate 폭발만 잡음. burst 측정 안 보였음 |
| `vfdiff_normal` | **50ms** | idle 99.6% / burst 92.6% 만족. 사용자 청감 미인지 한계 (~30~40ms) 근처 |
| `vfdiff_small_correction` | **50ms** (= normal 같음) | 50~500ms 사이 작은 보정 |
| `vfdiff_force_reseek` | **500ms** | 큰 어긋남. burst 1건 (0.4%)만 100-500ms 영역 |
| `vfdiff_emergency` | **1000ms** | 누적 발산 사고 (burst 7%가 3초+). anchor 무효 + 강제 reseek + position baseline 재설정 |

### 추천 — 위 값 그대로

idle 99% + 사용자 청감 미인지 한계 + burst 100ms+ 빈도 거의 없음 매칭.

---

## 결정 F — race 차단 메커니즘

### 측정 근거 + 사용자 통찰

- guest_stop 32회 누락 (burst 4분)
- 사용자 통찰: "단순 FIFO만으로 게스트 처리 지연 시 호스트와 어긋남"
- 메시지 idempotent state (절대값) 라 coalescing 가능

### 선택지

**F-1. 호스트 측 cooldown만 (최소)**
- syncPlay/Pause 200ms cooldown, syncSeek 100ms cooldown
- cooldown 동안 추가 호출은 마지막만 처리 (debouncing)
- 장점: 변경 작음
- 단점: 게스트 측 처리 지연 어긋남 못 막음 (사용자 우려)

**F-2. 호스트 cooldown + 게스트 coalescing (권장)**
- F-1 + 게스트 측 latest-state 큐:
  - audio-obs 큐: 새 obs 도착 시 기존 덮어쓰기. 처리 끝나면 마지막 obs만 처리.
  - seek-notify 큐: 새 seek-notify 도착 시 기존 덮어쓰기. idempotent라 안전.
- 장점: 두 방향 race 모두 차단
- 단점: 코드 변경 게스트/호스트 양측

**F-3. 모든 메시지 sequence number + idempotent replay (큰 변경)**
- 메시지에 seq 추가. 게스트는 큐에 쌓인 메시지 중 최신 seq만 처리
- 장점: 가장 안전. 메시지 누락도 감지 가능
- 단점: 메시지 페이로드 + 처리 로직 모두 변경

### Race 시나리오 시뮬레이션

| 시나리오 | F-1 | F-2 | F-3 |
|---|---|---|---|
| 호스트 syncPlay 5번/200ms | 마지막 1번만 broadcast | F-1 + 게스트 큐 1개만 처리 | seq로 마지막만 처리 |
| 게스트 처리 지연 (50ms × 5 메시지) | 큐 5개 순차 처리, 호스트 옛 상태 따라감 | 큐 마지막 1개만 처리 → 호스트 최신 상태 | seq로 같은 효과 |
| guest_stop 누락 | 여전히 발생 가능 (cooldown만으론 부족) | 누락 0 (호스트 cooldown 후 한 번만 broadcast, 게스트는 그 한 번 처리) | 누락 0 |

### 추천: **F-2**

이유: F-1로 부족 (사용자 우려대로 게스트 지연 어긋남). F-3는 모든 메시지에 seq 추가 — 큰 변경. F-2가 idempotent state replay 본질을 활용 — 메시지 자체 변경 없이 게스트 큐 정책만 변경.

---

## 결정 G — 정지/재생 시 vf 강제 동기화 (새 결정사항)

### 측정 근거

guest_stop 32회 누락 — host_pause 후 obs broadcast 한 번 가는데 게스트가 못 받거나 처리 지연으로 정지 안 함. 그동안 게스트만 vf 진행 → 누적 발산의 한 원인.

### 선택지

**G-1. obs broadcast 강화 (최소)**
- 호스트 정지 시 broadcast 횟수 1번 → 3번 (50ms 간격)
- 장점: 코드 변경 작음
- 단점: 트래픽 증가. 메시지 누락이 진짜 원인이 아니면 효과 없음

**G-2. play/pause 시 vf 같이 broadcast (권장)**
- 호스트 syncPlay/syncPause 시 vf를 명시적으로 보내는 새 메시지 (`host-state-sync`):
  ```json
  { type: "host-state-sync", playing: false, vf: 12345678, wallMs: 1234567890 }
  ```
- 게스트가 받으면:
  1. playing 상태 일치 (정지 → 즉시 stop, 재생 → 즉시 start)
  2. vf 강제 정렬 (현재 vf와 차이 >50ms면 seekToFrame)
- 장점: 메시지 누락이 와도 게스트는 항상 호스트와 같은 vf로 시작
- 단점: 새 메시지 타입 추가

**G-3. obs로 통합 + 처리 강화**
- 기존 audio-obs에 vf 이미 있음. 게스트가 obs.playing 변화 감지 시 vf 강제 정렬
- 장점: 새 메시지 타입 없음
- 단점: obs broadcast 주기적 (500ms) — 정지/재생 직후 즉시 obs 안 옴

### Race 시나리오 시뮬레이션

| 시나리오 | G-1 | G-2 | G-3 |
|---|---|---|---|
| host_pause 직후 obs 누락 | 추가 broadcast로 다음 도달 가능 | host-state-sync 즉시 + 게스트 강제 정렬 | 게스트가 다음 obs(최대 500ms 후) 받을 때 정렬 |
| 빠른 정지/재생 5번 | 트래픽 폭주 | 마지막 상태로 강제 정렬 | obs 다음 cycle에 최신 상태 반영 |
| 게스트 처리 지연 | 처리는 여전히 늦음 | F-2 큐로 마지막만 처리 → 호스트 최신 vf | F-2와 같은 효과 |

### 추천: **G-2**

이유: 메시지 누락 + 처리 지연 둘 다 대응. F-2 큐 정책과 합쳐지면 가장 강건. G-3는 obs 주기 500ms 동안 어긋남 가능 (작긴 함).

---

## 알고리즘 v2 통합 흐름

추천 결정(A-2 / B-1 / C-1 / D-1 / E / F-2 / G-2) 합치면:

```
[호스트 측]
syncPlay/Pause/Seek
  ↓
syncPlay/Pause: 200ms cooldown debouncing → 마지막 의도만 broadcast
syncSeek:        100ms cooldown debouncing
  ↓
broadcast:
  - audio-obs (기존, 500ms 주기 + 이벤트 시)
  - host-state-sync (새, syncPlay/Pause 시 — vf + playing)
  - seek-notify (기존)

[게스트 측]
P2P 수신
  ↓
큐 정책 (F-2):
  - audio-obs 큐: latest 1개만 보존 (새 obs로 덮어쓰기)
  - seek-notify 큐: latest target만 보존
  - host-state-sync 큐: latest 1개만 보존
  ↓
처리 (단일 처리 thread, 큐 마지막만):
  - audio-obs → _latestObs 갱신, playing 상태 변화 감지 시 start/stop
  - host-state-sync → playing 일치 + vf 강제 정렬 (>50ms 차이 시 seekToFrame)
  - seek-notify → 강제 seek + position baseline 재설정 (D-1)
  ↓
매 100ms poll:
  - rate anchor 잡기 (framePos 기반, 거의 reset 안 함)
  - position baseline 갱신 (vf 기반, 매 obs 최신 호스트 vf로 외삽 비교)
  ↓
보정 액션 (A-2):
  drift_ms <10 AND vfDiff <50  → 정상, 보정 없음
  drift_ms 10-200 OR vfDiff 50-500 → 작은 보정 seek (gain 0.8)
  drift_ms >200 OR vfDiff >500 → rate anchor reset (드물게) 또는 position baseline 강제 reseek
  vfDiff >1000 → 비상 강제 reseek + position baseline 재설정
  ↓
outputLatency EMA 갱신 (B-1):
  - anchor 시점에 베이크인
  - reset 시 EMA 값 보존 (다음 anchor에 carry-over)
```

---

## 검증 계획

### Phase 1 — 단위 race 시나리오
1. 호스트 cooldown debouncing — syncPlay 5번 빠르게 호출 → broadcast 1번만 확인
2. 게스트 큐 coalescing — obs 5개 빠르게 도착 → 마지막 1개만 처리 확인
3. host-state-sync — host_pause 직후 게스트가 즉시 stop + vf 일치 확인

### Phase 2 — 시나리오별 idle/burst 재측정
1. **idle 4분**: vfDiff 분포 — <30ms 90%+ 만족 (v0.0.49 70.8% 대비 향상)
2. **burst 4분 (사용자 빠른 연타)**:
   - guest_stop 누락 0회 (vs v0.0.50의 32회)
   - vfDiff max <500ms (vs v0.0.50의 45초)
   - 자가 회복 시간 <2초 (vs v0.0.50의 ~25초)
3. **30분+ 장시간 idle**: rate drift 누적 검증

### Phase 3 — 청감 검증
- 사용자 빠른 연타 후 음향 어긋남 인지 가능한지
- "잘 맞다" 청감 v0.0.48 baseline 대비 동등 또는 향상

### 측정 인프라 확장 (v2 구현 시 추가)
- `corrective_seek_small` / `corrective_seek_large` event
- `rate_anchor_set` / `rate_anchor_reset` event
- `position_resync` event
- `host_state_sync_sent` event (호스트 측, broadcast 시각)

---

## 합의 필요 사항 (사용자 검토)

### 핵심 결정
- [ ] **A-2**: drift+vfDiff 2단 액션
- [ ] **B-1**: outputLatency EMA + anchor reset 시 보존
- [ ] **C-1**: rate drift 1% 보정 무시 (A-2가 자동 흡수)
- [ ] **D-1**: anchor 분리 (rate + position)
- [ ] **E**: 임계값 (drift 10/20/200ms, vfDiff 50/500/1000ms)
- [ ] **F-2**: 호스트 cooldown + 게스트 coalescing
- [ ] **G-2**: host-state-sync 메시지 (vf 강제 동기화)

### 작업량 견적
- **F-2 + G-2**: 새 메시지 + 큐 정책 (게스트 측 가장 큰 변경)
- **D-1**: anchor 자료구조 분리 (`_recomputeDrift` / `_tryEstablishAnchor` / `_handleSeekNotify` 모두 변경)
- **A-2**: 임계 + 액션 분기 추가
- **B-1**: EMA 보존 (한 줄 변경)
- **C-1 / E**: 사실상 코드 변경 0 (임계 상수만)

총 5~10시간 작업. 단일 commit (`v0.0.51`)로 묶어서 측정 검증.

### 부분 수용 옵션 (사용자 선택지)
- 모두 받아들임 → 가장 정공법, 시간 큼
- F-2 + G-2 + A-2만 (race 차단 + 결합 규칙) → 누적 발산은 잡지만 D-1 anchor 분리 효과는 다음 차로
- A-2 + B-1만 (결합 규칙 + EMA) → race는 그대로 두지만 거짓말 패턴은 잡음

### 추가 검토 필요한 점
- D-1 두 anchor 상호작용 명세 — 한쪽 reset 시 다른 쪽 영향 정확히 정의 필요
- F-2 게스트 큐 정책 구현 시 기존 _handleAudioObs 비동기 처리와 충돌 검증
- G-2 새 메시지 타입 backward compat — 구버전 호스트는 이 메시지 안 보냄, 게스트가 모르면 obs로만 동기화 fallback

---

## 참고

- 측정 csv: `measurements/v0.0.49_idle_2026-04-28.csv`, `v0.0.49_burst_2026-04-28.csv`, `v0.0.50_burst_2026-04-28.csv`
- 분석 기록: `docs/HISTORY.md` (45)
- v0.0.48 baseline 흐름도: `docs/SYNC_FLOW.md`
- 백업 (v0.0.49~v0.0.61 NTP 시도): `backup-v0.0.61-session` branch
