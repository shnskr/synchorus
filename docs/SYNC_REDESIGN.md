# Synchorus 싱크 + 오디오 엔진 재설계 로드맵

> 2026-06-03 멀티에이전트 조사(2개 workflow, 12 에이전트, ~88만 토큰) 결과 종합.
> 계기: "매번 anchor 방식에서 문제가 터지는 것 아닌가" + "ring/SoundTouch도 더 좋은 방법 없나"라는 사용자 질문.
> 관련: [SYNC_ALGORITHM_V2.md](SYNC_ALGORITHM_V2.md), [HISTORY.md](HISTORY.md) (123)/(124), [DECISIONS.md](DECISIONS.md).

## 핵심 결론 — "구조는 다 옳다, 결함 2개만 메운다"

두 조사(싱크 / 오디오 엔진)가 독립적으로 같은 결론에 수렴:

| | 싱크 조사 | 엔진 조사 |
|---|---|---|
| 결론 | anchor 모델 폐기하지 마라 | ring buffer/SoundTouch 갈아엎지 마라 (구조 모범적) |
| 진짜 문제 | anchor를 **한 번만 박고 믿는 것** | **SoundTouch latency가 sync 보정에 미반영** |
| 전면 교체 | continuous 전면전환 ❌ | Rubber Band 교체 ❌ (GPL/유료 → App Store 부적합) |

기존 자산(클럭 동기 1.9ms, framePos/vf 분리, vfDiff 절대 검증, lock-free ring, worker 분리, cents=0 bypass)은 합리적. **결함 2개만** 외부 기술 방식으로 메우는 하이브리드 보강이 최소 침습·최대 효과.

---

## 결함 A — anchor를 한 번만 박고 신뢰 (싱크)

### 근본 약점 (조사 정리)
1. **단일 기준점 외삽 오차의 곡 전체 지속**: anchor는 최대 500ms 오래된 obs를 한 번 외삽해 박고(`native_audio_sync_service.dart:1651-1664`), 이후 `_recomputeDrift`는 "(현재−anchor) 변화분"만 본다(`:1805-1807`). 외삽 구간의 offset 오차/clock skew가 절대 위치에 베이크인되면 driftMs로 영영 못 잡음 — 코드 주석이 직접 "거짓말 패턴"이라 명시(`:1813-1816`).
2. **self-seek이 검증 무력화**: anchor 박는 동시에 게스트를 target으로 seek시키고 그 seek을 기준선에 포함(`:1681,1685`)해 직후 driftMs가 정의상 0 근처 → driftMs 기반 seek 폐루프(`:1878,1904`)는 잘못 박힌 anchor를 self-detect 불가. 절대 검증은 ANCHOR-VERIFY(임계 500ms)와 vfDiff(임계 150ms)뿐이라 그 사이 40~140ms 오차가 무효화 트리거 없이 잔존(40~95ms 진동 미해결).
3. **outputLatency 비대칭 베이크인**: 그 순간 outLatDelta를 seek에 베이크(`:1669,1687`) 후 변화분만 보정(`:1808-1810`). BT 워밍업 직후 과소보고 시점에 박으면 정상 회복 후에도 영구 오프셋. **(BT가 이 약점의 최악 케이스 — outputLatency가 분 단위 ±30~70ms 변동.)**
4. **isOffsetStable이 raw RTT jitter에 취약**: `_stableCount`는 `delta<2ms AND |filtered−winMinRaw|<2ms`를 5회 연속 만족해야 하는데(`sync_service.dart:341-345`), winMinRaw가 reject(30ms) 통과 샘플의 ±15ms 노이즈로 움직이면 리셋 → anchor가 ~20초 안 박힘(공백). **판정 임계 2ms vs 입력 노이즈 ±15ms의 7.5배 미스매치.**
5. **재입장/공백 자체 회복 수단 부재**: reset이 offset 상태 전부 0으로 비우고 alpha=0.1 EMA가 ~10초 재수렴. 그 사이 fallback만 동작. offset 결핍(rawOff=0) 상태에서 강제 establish하면 틀린 위치 고정(**v0.0.112 폐기 사례 = (124)**).
6. **patch 누적이 구조적 취약성의 방증**: v0.0.53(accum 2배), v0.0.81(ANCHOR-VERIFY), v0.0.108(vfDiff) 모두 "잘못 박힌 anchor의 영구 잔재"를 사후에 메우는 패치.

### 외부 기술 비교
- **Snapcast**: anchor를 **매 청크 재발행** + shortMedian>100µs에서 ±0.05% 리샘플 + 단일 샘플 drop/dup, 큰 오차(2~500ms)만 hard resync. 통상 <0.2ms.
- **AirPlay 2 / Sonos**: 같은 "play sample N at clock time T" anchor 모델이지만 host가 anchor를 **주기적 refresh** + frame stuffing(silent/duplicate/interpolate 샘플 점진 삽입)을 연속 보정층으로 깖. **anchor=거친 정렬, stuffing=미세 정렬 역할 분리.**
- **PTP(IEEE 1588)**: 일반 WiFi + 소프트웨어 타임스탬프에선 NTP와 사실상 동급(수십~수백µs jitter) + 데몬 부담 → **비채택**.

### 해결: 하이브리드 3층
1. **시계 동기층** — 현 NTP류 유지(PTP 비채택), median 필터 강화 + skew(주파수 차) 추정(PI/Kalman)으로 외삽 정확도↑.
2. **거친 정렬층** — 주기적 `(콘텐츠위치 P, 호스트 wall T, rate)` anchor 재발행. 게스트는 establish 1회가 아니라 매 수신마다 멱등 재스케줄 → 외삽 staleness·재입장·합류 동시 완화 (멱등/상태 무의존이라 1:N 멀티게스트 친화).
3. **미세 정렬층** — Snapcast/AirPlay식 연속 보정: 1단계 정수 샘플 add/drop(클릭/무음 없는 ~0.02ms 단위), 2단계 기존 **SoundTouch setTempo(Android) / AVAudioUnitTimePitch.rate(iOS)**를 ±0.05% 폭으로 폐루프에 묶는 rate-bend. driftMs 단독 폐루프 대신 **vfDiff(절대 위치)를 미세 보정 입력으로** 쓰는 폐루프로 대체.

---

## 결함 B — SoundTouch latency가 sync에 미반영 (엔진)

### ring buffer 평가: 모범적 (갈아엎을 이유 없음)
- LowLatency+Exclusive+Float+48k 스트림, 곡 길이 무관 **60s 고정 ring ~11.5MB**(`oboe_engine.cpp:96-104,300-307`) — **질문이 우려한 14분/150MB 사전할당 한계는 과거 동작, 현재 없음**. behind 10s + ahead 50s 윈도우.
- 콜백↔producer lock-free SPSC, decode 단일 thread, seek race를 큐(`mDecodeSeekTarget`)로 차단(`:727-750`, v0.0.76 fix). oboe best practice 충족.
- 남은 약점(우선순위순): ① 무음(underrun) 경로가 여러 곳에 분산되고 **경로별 카운터/로그 없음**(관측 불가), ② `mSTInRing.push` 반환값 미검사(`:854`) → speed=2.0에서 worker 못 따라오면 입력 PCM 조용히 유실 → position↔audio 어긋남, ③ lock-free tail 가시성 비대칭(polling 50ms 의존), ④ polling sleep 혼합(wakeup 지연이 underrun 마진 깎음).

### SoundTouch 평가: 통합은 정석, 치명 결함은 latency 미반영
- RT-safe(콜백은 ring read/push만, setPitch/setTempo·process는 worker 단독), cents=0 && speed=1000이면 완전 bypass(음질 손실 0). WSOLA 시간영역이라 모바일 CPU 부담 낮음.
- **치명 결함**: `getLatestTimestamp`의 outputLatencyMs는 HAL `calculateLatencyMillis`만 넣고(`oboe_engine.cpp:567-570`), SoundTouch 단계(TDStretch ~110ms + worker batch ~85ms + out-ring ~170ms)를 **안 더함**. 콜백은 vf를 매 frame 즉시 진행(`:885`)하므로 speed/pitch ON이면 vf(보고 위치)는 앞서고 실제 PCM은 수백 ms 뒤 DAC 도달. Dart anchor 공식(`native_audio_sync_service.dart:1669-1671`)은 HAL 비대칭만 베이크인 → **transpose/speed 켠 기기 vs 끈 기기 구조적 정렬 오차.**

### 라이브러리: SoundTouch 2.4.1 유지 (Rubber Band 탈락)
- **라이선스**: Rubber Band = GPL/유료 → App Store(iOS) 배포 시 사실상 유료. SoundTouch는 LGPL-2.1 상용 무료. → Rubber Band 탈락.
- **본질 미스매치**: 청감 문제 원인은 "SoundTouch 음질"이 아니라 "latency 미반영" → 어떤 라이브러리로 바꿔도 그 latency를 sync에 안 넣으면 재발. 교체는 근본 해결 아님.
- Signalsmith Stretch(MIT, single-header)는 라이선스·이식성 매력적이나 권장 구간 0.75~1.5x(우리는 0.5~2.0x) + spectral이라 예측 가능 latency가 중요한 P2P엔 불리. → latency 반영 끝낸 뒤에도 큰 pitch shift 아티팩트가 **실측 청감 회귀**로 확인될 때만 `poc/`로 격리 평가.

### 해결: SETTING_INITIAL_LATENCY 반영 (손수 공식 금지)
- vendored `SoundTouch.cpp:453-465`의 `SETTING_INITIAL_LATENCY`가 TDStretch+RateTransposer rate-dependent 합산을 frame 수로 정확 반환 — **현재 한 번도 호출 안 함**. 가장 깨끗한 hook.
- 방법: worker가 reconfigure/pitch/tempo 적용 직후 `mST.getSetting(SETTING_INITIAL_LATENCY)`로 frame 저장 → `getLatestTimestamp`가 `useST`일 때 outputLatencyMs에 `(frames/SR*1000 + batch/SR*1000)`를 더해 반환(useST=false면 0). `native_audio_service.dart:49`의 500ms 상한을 ~700ms로 상향. **Dart는 무수정** — `safeOutputLatencyMs` 비대칭 보정(`:1669,1585`)이 자동 적용해 한쪽만 ON인 비대칭도 정렬.
- **iOS**: AVAudioUnitTimePitch latency API 미문서화 → 루프백/박수 acoustic 캘리브레이션으로 상수 보정값 확보 후 `AudioEngine.swift` getTimestamp 경로에서 outputLatency에 합산. Android와 보고 의미 대칭화.
- 주의: 동적 out-ring 점유분을 매 poll 반영하면 outputLatency가 출렁여 anchor가 자주 깨질 수 있음 → **정적 항(INITIAL_LATENCY+batch)만 먼저**, 동적 항은 PoC drift 측정 후. v0.0.74-fix 안정 가드(`:1646-1647`)와 일관성.

---

## A ↔ B 연결
미세 정렬층(A-3)에 쓸 도구가 바로 SoundTouch setTempo / AVAudioUnitTimePitch.rate인데, 그 latency를 정확히 알아야(B) 보정이 정확. **B가 A의 전제조건.**

---

## 로드맵 (우선순위)

### 🥇 1. SoundTouch latency 반영 (결함 B, 최우선)
- `SETTING_INITIAL_LATENCY` 정적 항 반영 + 500→700ms 상한. native 한 곳 + Dart 무수정. transpose/speed 정렬 즉시 개선, acoustic 측정 가능. **리스크 최저, ROI 최고, 독립적.**
- 동반(저비용): `mSTInRing.push` 반환값 검사(입력 유실 가시화), underrun 경로별 카운터(관측성), `setBufferSizeInFrames(2*burst)` 명시.

### 🥈 2. anchor 주기 재발행 (결함 A 거친 정렬층)
- 호스트가 `(P, T, rate)` 주기 broadcast + 게스트 멱등 재스케줄. **Dart-only, 리스크 낮음.** 외삽 staleness + 재입장 + 합류 동시 완화.

### 🥉 3. isOffsetStable jitter 강건화 (결함 A 약점 4)
- winMinRaw 비교 임계(2ms) vs reject 노이즈(±15ms) 미스매치 해소: RTT outlier reject를 window median 기반으로, stable "5회 연속 0 리셋"을 누적 감점식으로 완화. **(v0.0.112 force-establish는 offset 결핍 상태에서 박지 말 것 — (124) 폐기 교훈.)**

### 4. vfDiff 임계 80~100ms + 지속 가드 (40~95ms 진동)
- `_vfDiffReAnchorThresholdMs` 150→80~100, 단발 staleness 오발 방지 위해 "연속 N회 초과 시만" 발동.

### 5. 미세 정렬층 (결함 A 미세 정렬, 중장기)
- 정수 샘플 add/drop → SoundTouch/AVAudioUnitTimePitch ±0.05% rate-bend 폐루프. **Android+iOS 동시 구현 필수.**

### 기타
- outputLatency 과소보고 베이크인 방지(BT 워밍업 안정화 후 establish), host getTimestamp framePos=-1 구간 보간 obs((30) 완화), polling→condition_variable 정밀 깨우기.

## 검증 원칙
- 맥북 마이크 **acoustic 측정**((120) 방식)으로 청감 vfDiff를 ground truth로 계속 사용.
- **BT 기기를 검증 매트릭스에 포함** — BT가 outputLatency 변동의 최악 케이스라 1순위 검증 환경. (Android oboe outputLatency가 BT 경로를 정확히 보고하는지는 미확정 — 실측 필요. iOS `AVAudioSession.outputLatency`는 BT 반영 확인.)
- native rate-bend/latency는 **Android+iOS 동시 구현 + 플랫폼별 framePos/vf speed 동작 실측 검증**.
- 목표는 sub-ms 보장이 아니라(일반 WiFi 천장) **거짓말 패턴/공백/재입장/진동의 구조적 제거 + 청감 무인지**.
