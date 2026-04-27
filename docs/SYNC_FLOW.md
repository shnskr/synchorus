# Sync 알고리즘 흐름도 (v0.0.48 main 기준)

## 핵심 개념 한 줄

> **호스트는 자기 시간 기준으로 그냥 재생만, 게스트는 호스트 obs를 받아 자기 위치를 호스트 추정 위치로 맞춤**

---

## 시간선 (재생 시작부터 정상 동작까지)

```
시간:    0ms    100ms   200ms   300ms   400ms   500ms   600ms   700ms   800ms   900ms  1000ms  1100ms  ...
─────────────────────────────────────────────────────────────────────────────────────────────────────────
호스트:  play
         │ engine.start (즉시 재생 시작)
         │ poll(100ms) ─ poll ─ poll ─ poll ─ poll(500ms) ─ poll ─ poll ─ poll ─ poll ─ poll ─ poll ─ ...
         │                                    │
         │                                    obs broadcast (매 500ms timer)
         │                                    {hostTimeMs=T, virtualFrame=V, framePos=F, sampleRate=SR, playing=true, outLat=oH}
         │                                    │
─ TCP ───┼────────────────────────────────────┼─────────────────────────────[obs]────────────────────────
         │                                    │      ~50ms 네트워크 lag
         │                                    │      │
게스트:  │                                    │      [수신]
         │                                    │       ├ _latestObs = obs
         │                                    │       └ 첫 obs면 → engine.start (게스트도 재생 시작)
         │                                    │       │
         │                                    │       poll(100ms) ─ poll ─ poll ─ poll ─ poll ─ ...
         │                                    │                              │
         │                                    │                              매 poll마다 drift 계산
         │                                    │                              │
         │                                    │                              ↓
         │                                    │                              if (drift > 200ms) anchor reset
         │                                    │                              if (median drift > 20ms) seek 보정
─────────────────────────────────────────────────────────────────────────────────────────────────────────
                                              ↑           ↑                  ↑
                                         호스트 측정 시각   게스트 수신 시각      게스트 보정 시각
                                              T          T+50ms              T+100~500ms 후
```

---

## 각 값의 의미

### 호스트 → 게스트로 가는 메시지 (audio-obs)

| 필드 | 의미 | 예시 |
|---|---|---|
| `hostTimeMs` (T) | 호스트가 framePos/virtualFrame을 측정한 wall clock 시각 (ms epoch) | `1777286713200` |
| `virtualFrame` (V) | T 시점 호스트의 **콘텐츠 frame** (현재 곡 어디 위치 재생 중) | `220500` (= 5초 지점 @ 44.1kHz) |
| `framePos` (F) | T 시점 호스트의 **HAL 하드웨어 sample 카운터** (단조 증가, seek 영향 X) | `220500` |
| `sampleRate` (SR) | 콘텐츠 sample rate | `44100` |
| `playing` | 호스트 재생 상태 | `true` |
| `hostOutputLatencyMs` (oH) | 호스트 OS가 보고하는 디코더→스피커 latency | `30.5` |

### 게스트 측 native timestamp (매 100ms poll)

| 필드 | 의미 |
|---|---|
| `ts.virtualFrame` (G) | **게스트 자기** 콘텐츠 frame (현재 재생 위치) |
| `ts.framePos` | 게스트 HAL 하드웨어 sample 카운터 |
| `ts.wallMs` | 게스트가 framePos 측정한 wall clock 시각 |
| `ts.safeOutputLatencyMs` (oG) | 게스트 OS의 출력 latency 보고 |

### Clock sync (별도 SyncService)

| 필드 | 의미 |
|---|---|
| `_sync.filteredOffsetMs` | 게스트 wall + offset = 호스트 wall (ping/pong으로 추정) |

---

## drift_ms 계산 (게스트 측)

게스트가 받은 obs로부터 "지금 호스트는 어디 위치 재생 중인지" 추정:

```
1. 게스트 wall now = ts.wallMs (자기 시각)
2. 호스트 wall now = ts.wallMs + offset                       ← clock sync로 환산
3. elapsed = 호스트 wall now - obs.hostTimeMs                 ← obs 측정 후 흐른 시간
4. 호스트 추정 위치 H = obs.virtualFrame + elapsed × SR / 1000
5. 게스트 자기 위치 G = ts.virtualFrame
6. 출력 latency 비대칭 = oG - oH
7. drift_ms = (G - H 둘 다 ms로 변환한 차이) - 출력 latency 비대칭
```

**의미**: drift_ms 양수 = 게스트 음향이 호스트보다 앞섬. 음수 = 뒤처짐.

### 좀 더 정밀한 실제 코드 (v0.0.48 `_recomputeDrift`)

```
expectedHostFrameNow = obs.framePos + elapsed × hostFpMs        ← 호스트 HAL framePos 외삽
dH = expectedHostFrameNow - anchorHostFrame                     ← anchor 잡힌 시점 대비 변화량 (호스트)

effectiveGuestFrame = ts.framePos + _seekCorrectionAccum        ← 게스트 HAL framePos + seek 보정 누적
dG = effectiveGuestFrame - anchorGuestFrame                     ← anchor 잡힌 시점 대비 변화량 (게스트)

drift_ms = (dG / SR_guest - dH / SR_host) × 1000                ← 두 변화율 ms 차이
         - (현재 outLatDelta - anchor 시점 outLatDelta)         ← 비대칭 변동분만 보정
```

**중요**: `anchor` 잡힌 시점 (정확한 정렬) 이후의 **변화율만** 비교.
- anchor 시점에 outputLatency 비대칭이 베이크인되어 있어 그 차이는 0으로 시작
- 이후 시간 지나면서 차이가 생기면 drift_ms 증가 → seek 보정 트리거

---

## Anchor 시스템 (정확한 정렬 baseline)

처음 재생 시작 시 게스트는 fallback alignment (간단 외삽 + 30ms 임계 seek)로 동작.
**clock sync 수렴 + ok timestamp + obs.playing=true 조건 만족하면 anchor establish**:

```
_tryEstablishAnchor:
  hostContentFrame = obs.virtualFrame + elapsed × hostFpMs       ← 호스트 현재 콘텐츠 위치 외삽
  outLatDelta = oG - oH                                          ← 출력 latency 비대칭
  targetGuestVf = (hostContentFrame ms) × SR + outLatDelta × SR  ← 게스트가 가야 할 위치
  engine.seekToFrame(targetGuestVf)                              ← 게스트를 호스트 위치로 강제 정렬
  
  _anchorHostFrame = (외삽한 호스트 framePos)                     ← 이 시점부터 변화율 추적 시작
  _anchorGuestFrame = ts.framePos + _seekCorrectionAccum         ← 게스트 측 baseline
  _anchoredOutLatDeltaMs = outLatDelta                           ← 비대칭 베이크인
```

이후 매 100ms poll마다:
- `_recomputeDrift` 호출 → drift_ms 계산
- **drift > 200ms** → anchor 무효화 (큰 변화 — 호스트 seek 등으로 의심)
- **median drift > 20ms** (5 sample 중앙값) → 작은 보정 seek

---

## 시각적 요약 (한 그림)

```
호스트 timeline:    ──[T1.vf=V1]──[T2.vf=V2]──[T3.vf=V3]──···  (매 500ms broadcast)
                       │             │             │
                       └─ obs ─┐     └─ obs ─┐     └─ obs ─┐
                               ↓             ↓             ↓
게스트 timeline:    ──[poll]──[수신]──[poll]──[수신]──[poll]──[수신]──··· (매 100ms poll)
                                       │
                                       매 poll에서:
                                       ① obs로 호스트 현재 위치 H 외삽
                                       ② 자기 위치 G 측정
                                       ③ drift_ms = G - H - outLat 비대칭
                                       ④ 임계 넘으면 seek 보정
```

---

## 거짓말 패턴 (v0.0.48에도 있는 한계)

drift_ms 공식이 **framePos 변화율만** 보고 **virtualFrame 절대 위치는 안 봄**.

```
정상 시:    drift_ms ≈ 0   AND   |G - H| ≈ 0    ← 둘 다 작음
거짓말 시:  drift_ms ≈ 0   AND   |G - H| = 300ms ← anchor가 잘못 잡힌 채 정렬 유지
```

anchor가 잘못된 obs로 잡히면 (stale obs / outputLatency 부정확 베이크인) 이후 **변화율만 같으면 drift_ms는 0**. 단 **절대 콘텐츠 위치는 어긋난 채로** 유지.

→ 진짜 sync 측정 = drift_ms (rate 정밀) **+** vfDiff (절대 정렬) 둘 다 봐야.
→ 이게 다음 세션 알고리즘 재설계 핵심.

---

## 관련 코드 위치

- `lib/services/native_audio_sync_service.dart`
  - `_broadcastObs` (호스트 측, 줄 560~) — obs 메시지 생성/송신
  - `_handleAudioObs` (게스트 측) — obs 수신
  - `_startTimestampWatch` (줄 1099) — 매 100ms poll
  - `_tryEstablishAnchor` (줄 1170~) — anchor 잡기
  - `_recomputeDrift` (줄 1212~) — drift_ms 계산
  - `_maybeTriggerSeek` (줄 1290) — seek 보정
- `lib/models/audio_obs.dart` — obs 메시지 형식
- `lib/services/sync_service.dart` — clock sync (ping/pong)
