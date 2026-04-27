# Sync 알고리즘 흐름도 (v0.0.48 main 기준)

## 핵심 개념

> **호스트는 자기 시간 기준으로 그냥 재생만 한다. 게스트가 호스트의 위치 정보(obs)를 받아 자기 위치를 호스트에 맞춘다.**

- 호스트 = master clock. 어긋남 보정 안 함.
- 게스트 = slave. 매 100ms 자기 위치 측정 + 호스트 obs 비교 + 보정 seek.

---

## 용어 정리 (변수명 대신 풀이)

### 호스트가 게스트로 보내는 정보 (audio-obs 메시지)

| 변수명 | 한국어 풀이 | 비유 |
|---|---|---|
| `hostTimeMs` | "이 정보를 측정한 호스트 측 시각" (벽시계 시각, ms epoch) | "사진 찍은 시각" |
| `virtualFrame` | "측정 시각 호스트가 재생 중이던 콘텐츠 위치" (frame 단위) | "사진 속 노래의 어느 부분" |
| `framePos` | "측정 시각 호스트의 하드웨어 sample 카운터" (단조 증가, seek해도 그대로 진행) | "스피커가 출력한 누적 sample 수" |
| `sampleRate` | "콘텐츠의 샘플레이트" (44100Hz면 1초당 frame 44100개) | "노래의 frame/초 비율" |
| `playing` | "호스트 재생 상태" | true/false |
| `hostOutputLatencyMs` | "호스트 OS가 알려주는 디코더→스피커까지 걸리는 시간" | "출력 지연" |

### 게스트 자기 측정값

| 변수명 | 한국어 풀이 |
|---|---|
| `ts.virtualFrame` | "게스트 자기 콘텐츠 위치" (현재 곡 어디 재생 중) |
| `ts.framePos` | "게스트 하드웨어 sample 카운터" |
| `ts.wallMs` | "게스트가 위치 측정한 시각" |
| `ts.safeOutputLatencyMs` | "게스트 OS의 출력 지연" |

### Clock sync (별도 ping/pong으로 추정)

| 변수명 | 한국어 풀이 |
|---|---|
| `_filteredOffsetMs` | "두 기기 시계 차이 — 게스트 시각 + offset = 호스트 시각" |

### Anchor 시스템 (정확한 정렬 baseline)

| 변수명 | 한국어 풀이 |
|---|---|
| `_anchorHostFrame` | "anchor 잡은 시점의 호스트 framePos" |
| `_anchorGuestFrame` | "anchor 잡은 시점의 게스트 framePos" |
| `_anchoredOutLatDeltaMs` | "anchor 잡은 시점의 출력 지연 비대칭 (게스트 - 호스트)" |
| `_seekCorrectionAccum` | "게스트 보정 seek 누적 — HAL framePos는 seek 영향 없으니 이걸로 콘텐츠 차이 복원" |

---

## 시나리오 1: 호스트 재생 시작 (정지 → 재생)

```
시간:    0ms          10ms         20ms         50ms          550ms        ...
─────────────────────────────────────────────────────────────────────────────────
호스트:  [재생 버튼]
         │ syncPlay() 호출
         │
         ├─ _engine.start()                                                      
         │  └ native 즉시 재생 시작 ───────────────────────────────────────────  ▶♪
         │
         ├─ _playing = true (UI 갱신)
         │
         ├─ _broadcastObs()                       ←── 즉시 1회 broadcast
         │  └ obs = { hostTime=10ms, vf=현재위치, playing=true, ... }
         │
         └─ _startObsBroadcast()                  ←── 500ms 주기 timer 시작
                                                       (이후 매 500ms마다 broadcast)
─ TCP ──────[obs 전송]─────────────────────────────────────────────────[obs]──── ...
                  │       ~30~50ms 네트워크 lag
                  ↓
게스트:           [수신 _handleAudioObs]
                  │
                  ├─ _latestObs = obs                ← 호스트 위치 정보 저장
                  │
                  └─ if (게스트 정지 중 + 호스트 playing=true)
                     └─ _startGuestPlayback()
                        ├─ _engine.start()         ───────────────────────  ▶♪ (게스트도 시작)
                        ├─ _playing = true
                        └─ _resetDriftState()      ← anchor null, accum 0

                                                      이후 매 100ms poll:
                                                      → fallback alignment (clock 미수렴 시)
                                                      → _tryEstablishAnchor (수렴 후)
                                                      → _recomputeDrift (anchor 잡힌 후)
```

**왜 게스트가 호스트보다 ~50ms 늦게 시작?** 네트워크 lag + 메시지 처리 시간. 이게 첫 정착 시간 ~수 초 잠깐 어긋남의 한 원인 (다른 원인: clock sync 수렴 + outputLatency 워밍업).

---

## 시나리오 2: 호스트 정지 (재생 → 정지)

```
시간:    0ms          10ms         20ms         50ms         ...
─────────────────────────────────────────────────────────────────────────
호스트:  [정지 버튼]                                            ▶♪ ── ▶♪
         │ syncPause() 호출
         │
         ├─ _playing = false (UI 갱신)
         │
         ├─ _engine.stop()                                              ⏸
         │  └ native 즉시 정지
         │
         ├─ _broadcastObs()                       ←── 즉시 1회 broadcast
         │  └ obs = { hostTime=10ms, vf=정지위치, playing=false, ... }
         │
         └─ _stopObsBroadcast()                   ←── 500ms timer 정지
                                                       (이후 broadcast 없음)
─ TCP ──────[obs(playing=false) 전송]──────────────────────
                  │       ~30~50ms lag
                  ↓
게스트:           [수신 _handleAudioObs]                         ▶♪ ── ▶♪
                  │
                  ├─ _latestObs = obs (playing=false)
                  │
                  └─ if (게스트 재생 중 + 호스트 playing=false)
                     └─ _stopGuestPlayback()
                        ├─ _playing = false
                        └─ _engine.stop()                              ⏸ (게스트도 정지)
```

**짧은 시간 어긋남**: 호스트가 ~50ms 먼저 정지되고 게스트가 그 후 정지. 청감으론 거의 인지 안 됨 (50ms는 매우 짧음).

---

## 시나리오 3: 호스트 seek (재생 중 위치 점프)

```
시간:    0ms          10ms         20ms         50ms         150ms       ...
─────────────────────────────────────────────────────────────────────────────
호스트:  [seek bar 드래그 → release at 30초]      ▶♪(현재 5초) ── 점프 → ▶♪(30초)
         │ syncSeek(Duration(30초)) 호출
         │
         ├─ _seekOverridePosition = 30초 (UI 즉시 갱신)
         │
         ├─ targetFrame = 30초 × sampleRate
         │  = 30 × 44100 = 1,323,000
         │
         ├─ _engine.seekToFrame(1323000)
         │  └ native 즉시 점프                                    ▶♪(30초)
         │
         ├─ broadcastToAll('seek-notify', {targetMs=30000})
         │  └ 게스트에게 "30초로 점프" 알림
         │
         └─ _broadcastObs()                                ←── obs도 갱신
─ TCP ──────[seek-notify ─ obs ─]──────
                  │       ~30~50ms lag                  ▶♪(5초) ── 점프 → ▶♪(30초)
                  ↓
게스트:           [수신 _handleSeekNotify]
                  │
                  ├─ targetGuestVf = 30000 × 44.1 = 1,323,000
                  ├─ _engine.seekToFrame(1323000)         ← 게스트도 점프    ▶♪(30초)
                  ├─ _seekOverridePosition = 30초 (UI)
                  │
                  └─ anchor 무효화 + 1초 쿨다운
                     ├─ _anchorHostFrame = null
                     ├─ _anchorGuestFrame = null
                     └─ _seekCooldownUntilMs = now + 1000

                     (1초 동안 새 anchor 안 잡고 fresh obs 기다림)
                     (1초 후 _tryEstablishAnchor 다시 시도)
```

**왜 1초 쿨다운?** seek 직후엔 호스트 obs가 아직 옛 위치 (5초 시점)일 수 있음. 그 stale obs로 anchor 잘못 잡히면 게스트가 옛 위치로 다시 reseek되는 사고 → 1초 기다려서 fresh obs 도착 후 anchor 잡음.

---

## 시나리오 4: 정상 재생 중 drift 보정 (게스트 측 매 100ms)

```
시간:    0ms          100ms        200ms        300ms        500ms        600ms ...
────────────────────────────────────────────────────────────────────────────────
호스트:  ▶♪          ▶♪           ▶♪           ▶♪           ▶♪          ▶♪
                                                  └─obs broadcast (500ms 주기)
─ TCP ─────────────────────────────────────────────────[obs]────────────────────
                                                              ↓
게스트:  ▶♪    │      │      │      │     [수신]│      │      │      │     ...
              poll   poll   poll   poll          poll   poll   poll   poll
              ↓      ↓      ↓      ↓             ↓      ↓      ↓      ↓
              매 poll에서 drift 계산:
              
              ① 게스트 자기 시각 (game wall) + offset = 호스트 시각 추정
              ② 호스트 시각 - 마지막 obs.hostTime = 경과 시간
              ③ 호스트 추정 위치 = obs.virtualFrame + 경과 × sampleRate
              ④ 게스트 자기 위치 = ts.virtualFrame
              ⑤ 차이 = 게스트 위치 - 호스트 추정 위치 - 출력지연 비대칭
              ⑥ 차이가 크면 seek 보정
```

### 단계별 세분화 (게스트 측 매 100ms)

```
1. fallback alignment (clock sync 수렴 전)
   ─ 매 poll마다 단순 외삽으로 게스트 위치 보정 (30ms 임계)
   ─ 정밀도 낮음 — 임시 정렬

2. _tryEstablishAnchor (clock sync 수렴 + ok timestamp + obs.playing 만족 시 1회)
   ─ 호스트 측 콘텐츠 위치를 정밀 외삽 (현재 시각 기준)
   ─ 게스트를 그 위치로 강제 seek
   ─ 출력 지연 비대칭(oG - oH)을 baseline에 베이크인
   ─ "이 시점 (호스트 framePos, 게스트 framePos) pair를 anchor로 저장"
   
3. _recomputeDrift (anchor 잡힌 후 매 poll)
   ─ 호스트 framePos 변화량 (anchor 시점 → 현재) — 외삽
   ─ 게스트 framePos 변화량 (anchor 시점 → 현재) — 자기 측정 + seek 보정 누적
   ─ drift_ms = 두 변화량 ms 차이 - 출력지연 비대칭 변동분
   
   ─ |drift| > 200ms → anchor 무효화 (큰 점프 — 호스트 seek 등 의심)
   ─ |median drift| > 20ms (5 sample 중앙값) → 작은 보정 seek
       ↓
       _performSeek:
       correctionFrames = -drift × 0.8 × sampleRate / 1000
       newVf = currentVf + correctionFrames
       engine.seekToFrame(newVf)
       _seekCorrectionAccum += correctionFrames
       (1초 쿨다운)
```

---

## 시각적 한 그림 요약

```
[호스트]  play ────────── 매 500ms broadcast obs ──────── pause ────  
            │              {hostTime, vf, framePos, sampleRate, playing, outLat}
            │              │
            └ TCP ─────────┴────────────── ~50ms lag ──────────────────
                                          │
                                          ↓
[게스트]  start ─ poll(100ms) ─ poll ─ poll ─ poll ─ poll ─ ─ ─ ─ ─ ─
                  ↓
                  매 poll에서:
                  ① 호스트 현재 위치 외삽 (obs + 경과시간 × sampleRate)
                  ② 자기 위치 측정 (ts.virtualFrame)
                  ③ 출력 지연 비대칭 보정
                  ④ 차이 임계 넘으면 보정 seek
```

---

## 거짓말 패턴 (v0.0.48 한계, 다음 세션 fix 필요)

drift_ms 공식은 **하드웨어 카운터(framePos) 변화율**만 비교 — **콘텐츠 절대 위치는 안 봄**.

```
정상:        drift_ms ≈ 0   AND   호스트vs게스트 콘텐츠 위치 차이 ≈ 0    ← 둘 다 작음
거짓말 패턴:  drift_ms ≈ 0   AND   호스트vs게스트 콘텐츠 위치 차이 = 300ms ← 어긋남 유지
```

**거짓말 발생 조건**:
- anchor가 잘못된 시점에 잡힘 (stale obs / 출력 지연 부정확 베이크인)
- 그 후 두 기기 framePos 변화율이 같으면 drift_ms는 0
- 단 **anchor 시점의 잘못된 차이는 그대로 유지됨**

**다음 세션 알고리즘 재설계 핵심**:
- drift_ms (rate 정밀) **+** vfDiff (절대 정렬) **둘 다** 임계 안에 있어야 진짜 sync
- 자세한 결정 사항: `CLAUDE.md` "다음 세션 작업 흐름" 섹션 6가지 (A~F)

---

## 관련 코드 위치 (`lib/services/native_audio_sync_service.dart`)

| 함수 | 역할 | 줄 |
|---|---|---|
| `syncPlay` | 호스트 재생 시작 | 425 |
| `syncPause` | 호스트 정지 | 461 |
| `syncSeek` | 호스트 seek | 471 |
| `_broadcastObs` | obs 메시지 송신 (500ms 주기) | 514 |
| `_handleAudioObs` | 게스트 측 obs 수신 처리 | 816 |
| `_handleSeekNotify` | 게스트 측 seek 알림 수신 | 952 |
| `_startGuestPlayback` | 게스트 재생 시작 | 978 |
| `_stopGuestPlayback` | 게스트 정지 | 992 |
| `_startTimestampWatch` | 게스트 매 100ms poll | 1022 |
| `_fallbackAlignment` | 정밀 anchor 잡기 전 단순 정렬 | 1073 |
| `_tryEstablishAnchor` | 첫 anchor 잡기 | 1121 |
| `_recomputeDrift` | drift 계산 (매 poll) | 1212 |
| `_maybeTriggerSeek` | drift 임계 넘으면 보정 seek | 1290 |
