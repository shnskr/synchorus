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
- **race 시나리오 시뮬레이션**: _(미작성)_
- **검증 방법**: _(미작성, csv `vf_diff_ms` + `drift` 컬럼 활용 예정)_
- **합의된 결정**: _(미정)_

거짓말 패턴 — `vfDiff > X` AND `drift_ms < Y`인 경우 액션:
- (옵션) anchor 무효화
- (옵션) 게스트 강제 reseek
- (옵션) 무시 (v0.0.48 현재 동작)

---

## B. outputLatency 보정 메커니즘

iOS/Android 양쪽의 `outputLatency`가 BT 환경에서 비대칭(특히 iPhone 게스트 첫 ~40초 워밍업, Apple Forum #679274). 보정 방식 결정.

- **선택지**:
  - (B1) **베이크인** — anchor 시점 1회 측정해 `_anchoredOutLatDeltaMs`로 고정 (v0.0.38 현행)
  - (B2) **EMA 점진 수렴** — 매 obs마다 `latencyEMA = α·current + (1-α)·prev` 보정 (v0.0.51~v0.0.55 시도, v0.0.55에서 vfDiff 23배 회귀)
  - (B3) **cap 상한 제한** — outputLatency 변화량이 임계 초과하면 무시
- **anchor reset 시 EMA 누적값 보존 여부** — v0.0.60 한계 회피. 보존하면 anchor reset 후에도 계속 수렴 진행, 폐기하면 매 reset마다 처음부터.
- **race 시나리오 시뮬레이션**: _(미작성)_
- **검증 방법**: _(미작성, csv `out_lat_*` 4개 컬럼 활용)_
- **합의된 결정**: _(미정)_

---

## C. rate drift 1% 보정

게스트 측 sample rate가 호스트와 미세하게 다르면 (1% 가정) 30분 누적 시 약 18초 drift. 현재 (v0.0.48)는 보정 없음.

- **선택지**:
  - (C1) **주기 강제 reseek** — vf-correction 100ms 임계 초과 시 seek (v0.0.58 시도)
  - (C2) **native sample rate 조정** — `oboe::AudioStream::setSampleRate` (가능한지 확인 필요) / iOS는 `AVAudioEngine`의 reconnect로만 가능
  - (C3) **virtualFrame 진행 속도 보정** — 게스트 측 rate match. Dart 레이어에서 시간 진행률 조정.
- **race 시나리오 시뮬레이션**: _(미작성)_
- **검증 방법**: _(미작성, 30분+ 장시간 idle 측정 필요)_
- **합의된 결정**: _(미정)_

---

## D. anchor 분리 여부

현재 (v0.0.48): anchor 1개 (framePos + virtualFrame 동시점). 호스트 정지/재생/seek마다 reset → fallback 단계 (5초) 동안 큰 drift 발생 ((42) edge case).

- **선택지**:
  - (D1) **현행 단일 anchor 유지** — 단순, 회귀 위험 낮음
  - (D2) **anchor 2개 분리** — `rate anchor` (framePos 기준, 거의 reset X) + `position baseline` (virtualFrame 기준, 절대 정렬). 둘이 어떻게 상호작용?
  - (D3) **NTP-style 예약 재생** — wall clock 기준 양쪽 동시 시작. v0.0.47 시도 후 race로 롤백, 정밀 작업 필요.
- **race 시나리오 시뮬레이션**: _(미작성)_
- **검증 방법**: _(미작성)_
- **합의된 결정**: _(미정)_

---

## E. 임계 정확 값

각 보정 액션이 발동하는 임계값. 값 자체보다 **왜 그 값인지**가 핵심 (사용자 청감 미인지 한계 + 측정 noise floor 균형).

- **drift_ms 정상 임계**: 5ms? 10ms? 20ms?
- **vfDiff 정상 임계**: 30ms? 50ms? 100ms? (사용자 청감 미인지 한계 — 외부 자료 필요)
- **비정상 시 액션 단계**:
  - (작은 보정) seek by Δ
  - (중간) anchor reset
  - (강한) 강제 seek to host position
- **race 시나리오 시뮬레이션**: _(미작성)_
- **검증 방법**: _(미작성)_
- **합의된 결정**: _(미정)_

---

## F. race 차단 메커니즘

v0.0.51 debounce / v0.0.59 마지막-이김 / v0.0.47 NTP 모두 race로 회귀. 명확한 직렬화 필요.

- **호스트 측 syncPlay/Pause/Seek**:
  - (F1) FIFO 큐 (모든 호출 순서대로)
  - (F2) 마지막-이김 (debounce, v0.0.59에서 회귀)
  - (F3) 미들웨어 lock (한 번에 하나만)
- **게스트 측 메시지 처리**: `_handleSchedulePlay` / `_handleSchedulePause` / `_handleAudioObs` 동시 진행 차단 — async lock or message queue.
- **race 시나리오 시뮬레이션**: _(미작성, 사용자 연타 timeline 시뮬)_
- **검증 방법**: _(미작성, csv 이벤트 11종 시퀀스)_
- **합의된 결정**: _(미정)_

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
