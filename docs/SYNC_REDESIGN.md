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

### 🥇 1. SoundTouch latency 반영 (결함 B-ST) — ✅ Android 완료 (v0.0.112, HISTORY (125)) / ⏳ iOS 미반영
- ✅ `SETTING_INITIAL_LATENCY` 정적 항 반영 + 500→700ms 상한. native 한 곳(`oboe_engine.cpp` worker가 `getSetting` → `getLatestTimestamp` outputLatencyMs 가산, useST일 때만) + Dart 무수정(`safeOutputLatencyMs` 자동 적용). 실측: 2배속 `out_lat~274ms` 반영 확인, 정상 2배속 drift median 0.24ms. **리스크 최저·ROI 최고·독립적 (사후 확인).**
- ⚠️ acoustic 측정((132))으로 드러난 잔존은 SoundTouch가 아닌 **결함 B-HAL(출력단 ~11ms 하드웨어 비대칭, SoundTouch 독립)** → 인지경계 아래라 **보류(close)**. 아래 "용어 정리 — 결함 B 두 가지" 참조.
- ⏳ iOS: `AVAudioUnitTimePitch` latency **완전 누락** (v0.0.112는 `oboe_engine.cpp`만 = Android 전용). 코드 확정 (2026-06-05 (137)): ① `getTimestamp`의 `outputLatencyMs`=`session.outputLatency`만(`AudioEngine.swift:275`, timePitch 미포함) ② `nodeLatency` 합산(`:234-236` = playerNode+mainMixer+output)이 신호 체인(`node→timePitch→mainMixer`, `:120-121`) 중간의 `timePitch`를 **건너뜀**(`timePitch.latency` 호출 0곳) ③ 그 `nodeLatencyMs`/`totalLatencyMs`는 Dart가 **안 받음**(`native_audio_service.dart:56,69`는 `outputLatencyMs`만 수신, 나머지 Map에서 버려짐). → iOS 게스트 transpose/speed ON 시 큐 latency만큼 sync 어긋남 가능(영향 크기 미측정). API 미문서화라 SoundTouch식 hook 불가 → acoustic 캘리브레이션 상수 필요(§해결 참조). PLAN §H "iOS 실기기 검증" 트랙.
- ⏳ 동반(저비용, **미완료**): `mSTInRing.push` 반환값 검사(입력 유실 가시화), underrun 경로별 카운터(관측성 — 30분 stress 측정 선행), `setBufferSizeInFrames(2*burst)` 명시.

### 🥈 2. anchor 주기 재발행 (결함 A 거친 정렬층) — ✅ 시도 → **보류(close), 2026-06-05 (136)**
- 호스트가 `(P, T, rate)` 주기 broadcast + 게스트 멱등 재스케줄. **Dart-only, 리스크 낮음.** 외삽 staleness + 재입장 + 합류 동시 완화.
- ⚠️ **1단계(seek 기반 realign) 실측 실패 → close**: realign 빈도↑ = vfDiff 악화(2초 -26 / 5초 -15 / baseline -5), self-seek가 매번 음수 편향으로 박음. 청감 무영향이라 효용<비용. **재개 시 seek 아닌 #5 rate-bend로.** 상세 ↓ "2차 재측정 + 트랙 보류(close)" / HISTORY (136).

### 🥉 3. isOffsetStable jitter 강건화 (결함 A 약점 4)
- winMinRaw 비교 임계(2ms) vs reject 노이즈(±15ms) 미스매치 해소: RTT outlier reject를 window median 기반으로, stable "5회 연속 0 리셋"을 누적 감점식으로 완화. **(v0.0.112 force-establish는 offset 결핍 상태에서 박지 말 것 — (124) 폐기 교훈.)**

### 4. vfDiff 임계 80~100ms + 지속 가드 — ⚠️ 진동 동기 소멸 (2026-06-05 (138))
- 원 동기였던 "40~95ms 진동"((124))은 v0.0.118/119 fix 후 재측정에서 **재현 안 됨 → close** (HISTORY (138), 재입장 5회 폭 3~6ms). 임계 자체는 코드상 이미 realign 60(`_vfDiffRealignThresholdMs`) / reset 200(`_reAnchorThresholdMs`)으로 분화(v0.0.114). 잔존 동기는 (125) "게스트 체계적 앞섬 40~46ms"(결함 A, 임계 낮춰도 미달)뿐 → 결함 A 트랙(🥈2, (136) close)에 흡수.

### 5. 미세 정렬층 (결함 A 미세 정렬, 중장기)
- 정수 샘플 add/drop → SoundTouch/AVAudioUnitTimePitch ±0.05% rate-bend 폐루프. **Android+iOS 동시 구현 필수.**

### 기타
- outputLatency 과소보고 베이크인 방지(BT 워밍업 안정화 후 establish), host getTimestamp framePos=-1 구간 보간 obs((30) 완화), polling→condition_variable 정밀 깨우기.

## 검증 원칙
- 맥북 마이크 **acoustic 측정**((120) 방식)으로 청감 vfDiff를 ground truth로 계속 사용.
- **BT 기기를 검증 매트릭스에 포함** — BT가 outputLatency 변동의 최악 케이스라 1순위 검증 환경. (Android oboe outputLatency가 BT 경로를 정확히 보고하는지는 미확정 — 실측 필요. iOS `AVAudioSession.outputLatency`는 BT 반영 확인.)
- native rate-bend/latency는 **Android+iOS 동시 구현 + 플랫폼별 framePos/vf speed 동작 실측 검증**.
- 목표는 sub-ms 보장이 아니라(일반 WiFi 천장) **거짓말 패턴/공백/재입장/진동의 구조적 제거 + 청감 무인지**.

---

## 2026-06-03 진단 실증 + 다음 세션 시작점 (HISTORY (126))

**결함 A를 csv로 실증함** (게스트 "미묘하게 앞섬" 진단, transpose +5 안정 재생):
- **anchor 경로가 fallback보다 부정확.** anchor 경로 vfDiff −10~−65(변동), 같은 곡에서 fallback 경로는 0~5(정렬). anchor는 establish 시점 오차(seek 도달 빗나감, ANCHOR-VERIFY +47~196)를 baseline에 박고 **곡 내내 지속**, fallback은 **매번 fresh 외삽이라 정확**. = 결함 A "한 번 박기"의 정확한 실증.
- 방향은 **±변동**(세션1 +46 앞 / 세션2 −65 뒤) — "체계적 한 방향" 아님.
- ST/outLat 무관(transpose 양쪽 ST 상쇄, delta ~0), drift~0, 시계 동기 좋음(stable 24). 즉 **위치 정렬(anchor) 단독 문제.**

**다음 세션 진입 순서**:
1. **acoustic 측정 1회** — csv vfDiff 부호가 청감과 어긋나(세션2 −65 vs 청감 "앞") **방향 미확정**. fallback이 진짜 anchor보다 정렬 좋은지 + 게스트 앞/뒤를 ground truth로 확정(v0.0.111 방식). 측정 없는 fix는 v0.0.112 force-establish 폐기 (124)의 재발.
2. **anchor 주기 재발행 설계** (위 로드맵 🥈) — fallback이 정확한 이유(매번 fresh)를 anchor에 이식: baseline 주기 갱신 + 멱등 재스케줄(seek 반복 회피). **부호 무관 효과**라 1번 결과와 독립적으로 방향이 맞음.
3. (참고) ANCHOR-VERIFY는 establish~verify 경과(vf 진행)를 안 빼 과대보고 — 임계 낮춤 단독은 비추.

**현재 코드 상태**: v0.0.112(9af5874)까지 커밋. (126)은 진단만(코드 변경 없음). working tree clean에서 시작.

---

## 2026-06-04 (128) — realign + virtualFrame 시점 정합: 톱니 근본 fix 완료 (v0.0.114)

(126)에서 "진입 순서 1. acoustic 측정 → 2. anchor 주기 재발행"으로 잡았으나, 측정이 어려워 **2(주기 재발행=realign)부터 진행** → 측정 중 (126) "±수십ms 변동"의 진짜 원인을 코드로 규명·해결.

**진행 결과**:
1. **realign (결함 A 거친 정렬층, 로드맵 🥈 구현)** — vfDiff 중앙값 >60ms 시 anchor 유지한 채 baseline을 현재 호스트 위치로 fresh 재정렬. fallback의 "매 주기 fresh 보정" 비결 이식. 150ms `anchor=null` 리셋(establish 공백) 대체.
2. **virtualFrame 시점 정합 (톱니 근본 fix)** — (126)의 ±수십ms 변동(톱니)의 진짜 원인 = `getLatestTimestamp`에서 `virtualFrame`(마지막 콜백 ~현재)과 `wallMs`(=`wallAtFramePos`, framePos의 HAL `timeNs` 과거 시점)의 **시점 불일치**. 게스트 vfDiff 외삽이 HAL 지연(`monoNow-timeNs`)을 이중 카운트 → 톱니. **drift(framePos↔wall 정합)가 멀쩡한 게 증거.** fix: Android `oboe_engine.cpp`에서 virtualFrame을 `(monoNow-timeNs)×decodedRate×speed`만큼 빼 timeNs 시점으로 정렬. iOS는 vf/framePos 둘 다 lastRenderTime 기반이라 이미 정합(보정 불필요).
   - 진단: transpose 0/+5 둘 다 톱니(SoundTouch 무관) + obs_age 무관(외삽 거리 무관)으로 원인 좁힘.
   - 측정(transpose +5, 3분): drift vfDiff 30-60ms **148→0개**, >60 **11→0개**, min/max ∓108→∓27. **±50/±100 톱니 제거.**

**⚠️ 정정 (사용자 청감 + raw csv — 위 "톱니 제거" 무효)**: 측정3는 offset 불안정(anchor 안 박힘, drift 97 vs fallback 255, `anchor_set` 2회)으로 `vfDiff`(±42)가 **거짓**이었음. raw `guest_vf−host_vf` = **+250~512ms**로 게스트 실제 ~500ms 어긋남(청감 일치, measure_audio 비프 정반대, `seek_count=0` = 보정 0회). offset 부정확 시 외삽이 실제 500ms를 ±42로 지움 = **거짓말 패턴 재확인**. 톱니fix·realign은 코드상 유효하나 offset 안정 상태에서만 검증 가능 — 측정3 판정 불가.

**다음 세션 진입 순서 (정정)**:
1. **offset/clock sync 안정화 (진짜 1순위, 격상)** — anchor가 안 박히는 근본(`isOffsetStable` raw RTT jitter = 결함 A 약점 4 / 미해결 #1) + 재입장 clock sync ~8초 지연(#5). **offset이 부정확하면 vfDiff가 통째 거짓이 되어 모든 sync 판단이 무너짐**(측정3 실증). 이게 토대 — 잡혀야 vfDiff를 믿고 톱니fix·realign 효과도 검증 가능.
2. **톱니fix·realign 재검증** — offset 안정 상태에서 ±50 톱니가 실제 줄었는지 재측정.
3. **+16ms vfDiff 편향** — offset 정상에서 재측정 후 판단 (측정3 +16은 offset 거짓 산물이라 무의미).

**측정 방법 교훈**: vfDiff는 offset 의존 외삽값 → offset 불안정 시 ground truth 아님. **anchor 박힘 여부(drift vs fallback 비율) + raw `guest_vf−host_vf` + acoustic 교차 검증 필수.**

**현재 코드 상태**: v0.0.114 커밋(47a2f2b, realign + 톱니fix). 0.0.113은 (127) UI(다른 세션).

---

## 2026-06-05 (129) — offset 정상 재측정: 톱니fix 검증 성공 + 다음 타겟 확정

(128) 정정 후 measure_audio transpose+5 재측정(측정3 점프 회복 상태). **offset 정상**(filtered 192, 변동 2.3ms, anchor drift 317 vs fallback 48) 확보 → 드디어 신뢰 가능한 측정.

**검증 결과**:
- ✅ **톱니fix(virtualFrame 시점 정합) 유효 확정** — vfDiff -19.5 일정(p10/p90 -20.1/-18.1), ±50 톱니 사라짐. (128) "미검증"을 offset 정상 상태에서 완료.
- ✅ **"offset 고치면 500ms 잡힌다" 실증** — offset 정상되니 측정3의 500ms 어긋남 사라지고 vfDiff -19.5(작음). offset이 root 확정.
- 청감 교차: position "호스트 앞" = vfDiff -19.5 일치. **음향 "게스트 앞"(일관)** = vfDiff와 반대 → outputLatency 비대칭(게스트 출력지연 ~20ms 작은데 csv 미반영).

**다음 세션 진입 순서 (확정)**:
1. **B (monotonic 전환, offset 점프 면역)** — 측정3 wall 점프 재발 방지. **`CLOCK_BOOTTIME`/`mach_continuous_time`** 사용(현재 `CLOCK_MONOTONIC`/`mach_absolute_time`은 deep sleep 중 멈춤, 검증 완료). ping/pong + 재생 정렬 전반 monotonic 치환 — wall 사용처 전수조사 + 설계 선행. EMA min-RTT 로직은 점프 없어지면 그대로 둬도 됨.
2. **음향 outputLatency 비대칭 (결함 B)** — 가장 체감되는 잔존. csv `out_lat`가 실제 음향 지연 비대칭(~20ms)을 과소보고. SoundTouch/HAL latency. acoustic로 부호 확정 후 보정.
3. **vfDiff -19.5 position 편향** — seek 임계(20ms) 바로 아래라 방치. 임계/보정 검토.

**현재 코드 상태**: v0.0.114 커밋(47a2f2b + bf0d47d 정정 + 측정4 검증). 톱니fix·realign 검증 완료, offset 점프/outputLatency 비대칭 미해결.

---

## 2026-06-05 (130) — monotonic clock 전환 설계 (offset 점프 면역, 결함 외 B-트랙)

> (129) 다음 1순위. 측정3 "wall 점프"(NTP 보정) 재발 방지. **코드 작성 전** 전수조사(Dart/Android/iOS 3계층) + 1차 소스 검증 완료. 멀티에이전트 전수조사 + WebFetch 1차 소스 교차검증.

### 결정 (사용자 합의)
- **clock 도메인 = BOOTTIME 계열** (deep sleep 면역). Android `CLOCK_BOOTTIME` / iOS `mach_continuous_time`.
- **Dart 시각 읽기 = dart:ffi 직접 호출** (MethodChannel 비동기 왕복 지연 회피 → ping/pong t1/t3 정밀 캡처).

### 근본 문제 (전수조사 결과)
현재 두 기기 정렬이 **전부 wall clock 도메인**. native는 이미 monotonic(`timeNs`)을 손에 쥐고도 `oboe_engine.cpp:686`에서 **일부러 wall로 역변환**(`wallNow-(monoNow-timeNs)`) — 호스트/게스트 monotonic은 epoch가 달라 직접 비교 불가하니 "공통어" wall로 변환한 것. 그러나 wall은 NTP 보정에 점프 → **측정3 root cause**(재생 중이라 deep sleep 아님 = NTP가 범인). obs는 `timeNs`(monotonic)를 이미 싣지만 게스트가 안 씀(`audio_obs.dart:17`) — 인프라 일부는 이미 깔림.

### ✅ 검증된 시계 매핑 (1차 소스 — 절대 헷갈리지 말 것)
| 의미 | Android/Linux | iOS clock_gettime | iOS mach | sleep | NTP점프 | 채택 |
|---|---|---|---|---|---|---|
| **목표: sleep포함+점프면역** | `CLOCK_BOOTTIME` (=7) | `CLOCK_MONOTONIC_RAW` | `mach_continuous_time()` | 포함 | 면역 | ✅ |
| sleep멈춤 (구 MONOTONIC) | `CLOCK_MONOTONIC` | `CLOCK_UPTIME_RAW` | `mach_absolute_time()` | 멈춤 | 면역 | AVAudioTime 전용 |
| ❌ 점프 위험 | — | `CLOCK_MONOTONIC` | — | 포함 | **점프** | 금지 |

- Darwin `CLOCK_MONOTONIC` 함정: man page는 "sleep 포함"이라 하나, 실제론 REALTIME offset이라 **시스템 시간 변경 시 점프**(monotonic 보장 깨짐). → raw 계열 필수.
- 출처: mach_continuous_time="including time the system spent asleep" (Apple kernel/1646199) · CLOCK_UPTIME_RAW=mach_absolute_time/sleep멈춤 (xcode man clock_gettime(3)) · CLOCK_MONOTONIC_RAW≡mach_continuous_time (Python bpo-42107) · **AVAudioTime.hostTime=mach_absolute_time** (Apple QA1643) · oboe가 clockId를 AAudio에 그대로 전달(AudioStreamAAudio.cpp)+AAUDIO_CLOCK_BOOTTIME 지원(NDK Audio) · CLOCK_BOOTTIME=7 (bionic).

### 핵심 제약: 도메인 일치 (설계의 중심)
Dart FFI `now()`와 native `getTimestamp`의 timeNs가 **반드시 같은 clock domain**이어야 offset·anchor 외삽이 성립.
- **Android**: FFI `clock_gettime(CLOCK_BOOTTIME)` ≡ native `getTimestamp(CLOCK_BOOTTIME)` → 직접 일치, 변환 불필요.
- **iOS**: `AVAudioTime.hostTime`은 `mach_absolute_time`(sleep 멈춤) **고정** → native에서 `hostTime + (mach_continuous_time()−mach_absolute_time())`로 continuous 도메인 변환해 보고. `play(at:)` 스케줄은 반대로 continuous→absolute 역변환. FFI `mach_continuous_time`과 일치.

### 영향 위치 (도메인만 교체, 알고리즘 불변)
| 단계 | 위치 | 현재(wall) | 전환 후 |
|---|---|---|---|
| clock offset | `sync_service.dart:173,231,292,365,407` t1/t2/t3 | `DateTime.now()` | FFI monotonic now |
| obs 송신 | `audio_obs.dart:11` `hostTimeMs` | native wallAtFramePos | native mono@framePos (의미 변경) |
| Android 시각 | `oboe_engine.cpp:565,686` | CLOCK_REALTIME 역변환 | `getTimestamp(BOOTTIME)` timeNs 직접 |
| iOS 시각 | `AudioEngine.swift:228,304,331` | Date()+mach_absolute | continuous 변환 |
| 게스트 anchor | `native_audio_sync_service.dart:1652` | `ts.wallMs+offset` | `ts.monoMs+offset` |
| 게스트 drift 외삽 | `native_audio_sync_service.dart:1794,1822` | `ts.wallMs+offset` | `ts.monoMs+offset` |
| native 모델 | `native_audio_service.dart:43` `wallMs` | `wallAtFramePosNs~/1e6` | `monoAtFramePosNs` (ns 양자화 제거 가능) |

**전환 불필요(상대 경과/로그)**: p2p heartbeat `lastSeen`, cache-busting URL, seek cooldown, Stopwatch(이미 monotonic), 로그 파일명. → 사용자 무관, wall 유지 OK.

### 구현 단계 (task #2~#6)
1. **Dart FFI monotonic now** — Android `clock_gettime(BOOTTIME)`, iOS `mach_continuous_time()`.
2. **Android native** — `getTimestamp(CLOCK_BOOTTIME)` + `clock_gettime(BOOTTIME)`, mono@framePos 보고.
3. **iOS native** — hostTime→continuous 변환, scheduleStart 역변환.
4. **Dart 정렬 교체** — sync t1/t2/t3, obs, anchor/drift 외삽, NativeTimestamp 모델.
5. **wall 병행 csv 출력** — monotonic 값과 대조(검증용, 측정 끝나면 제거).
6. **실기기 측정** — 아래 실측 항목.

### ⚠️ 실측 검증 항목 (문헌으로 못 끝냄)
1. **AAudio `getTimestamp(CLOCK_BOOTTIME)`가 실기기에서 정상 framePos/timeNs를 주는가** → ❌ **실측 (2026-06-05, SM S947N): clockId=BOOTTIME을 무시하고 MONOTONIC 값 반환** (vf -89억 폭발, 재생시간 음수). **수정**: iOS(hostTime=absolute + sleep누적) 대칭으로 — `getTimestamp(CLOCK_MONOTONIC)`로 받아 HAL지연/virtualFrame/wall은 MONOTONIC 일관, 정렬 보고값 `outTimeNs`만 `+(bootNow-monoNow)` 가산해 BOOTTIME화. **교훈: getTimestamp clockId는 신뢰 불가 — 항상 MONOTONIC 받고 sleep누적을 코드로 가산.** → ✅ **수정 후 검증 성공** (v0.0.115, HISTORY (130)): offset 1.1ms 변동(점프 제거), vfDiff -3.64, seek 0. (참고: `AudioStreamLegacy::getBestTimestamp` oboe#1489 — native path라 비해당.)
2. **iOS continuous 변환 안정성** — 재생 중(sleep 없음)엔 `continuous−absolute` 차이 일정해야 함. 변환 오차 측정.
→ **wall 값 csv 병행 출력**으로 monotonic과 대조하면 측정 단계에서 자연 검증.

### 리스크/메모
- **ns JSON 전송**: BOOTTIME ns는 부팅 후 경과(작음) → 2^53(=104일) 안전. wall epoch ns보다 안전. 우려 시 세션 baseline 빼서 전송.
- **EMA min-RTT 로직**: 점프 없어지면 그대로 둬도 됨 (PLAN.md:150). isOffsetStable jitter(결함 A 약점 4)는 별개 트랙.
- 이 전환은 **결함 A/B와 독립** — offset 토대를 단단히 해 vfDiff 신뢰성 확보(측정3 거짓말 패턴 재발 방지). 토대 다진 뒤 결함 A(anchor 주기 재발행)·결함 B(음향 outputLatency 비대칭) 진행.

---

## 2026-06-05 (132) — acoustic 측정: 결함 B 정체 확정 = HAL 출력단 비대칭 (SoundTouch 무관)

> (129)가 "음향 outputLatency 비대칭(결함 B)"로 지목한 타겟을, monotonic 안정(v0.0.115) 상태에서 맥북 마이크 acoustic 측정으로 ground truth 확정. **측정 절차/인프라/방법론 교훈 = HISTORY (132). 측정 코드 = `scripts/acoustic/`.**

### 측정 결론 (실측, transpose 0/1.0 = SoundTouch bypass, S947N 호스트 + S22 게스트)
- 음향 시차 **~11ms 고정**(음속보정 후, **호스트 출력이 먼저**) — rec2 12.0 / rec5 12.6.
- vf_diff −28→−6.8 **출렁임**(재생 position 외삽) ↔ 음향 고정 → **음향은 재생오차(position)가 아님**.
- monotonic offset 2.7ms 안정 → **클럭차 아님**(이미 보정됨). drift_ms(framePos=HAL DAC)≈0 → **DAC 레벨까지 sync 정확**.
- ∴ **음향 11ms = framePos(DAC) 이후 → 스피커 출력단의 고정 지연 비대칭.** csv `out_lat_*_raw`(Oboe `calculateLatencyMillis`)가 DAC 이후를 못 잡음(부호도 반대: delta g−h −2.6) → 보정 안 됨. (33-2) "calculateLatencyMillis가 BT codec/radio·DAC 이후 못 잡음"과 일치.

### ⚠️ 용어 정리 — "결함 B" 두 가지를 분리
| | **결함 B-ST** (이 문서 §결함B 원래 정의) | **결함 B-HAL** (이번 측정 확정, 신규) |
|---|---|---|
| 정체 | SoundTouch 단계(TDStretch+batch+ring) latency 미반영 | HAL DAC→스피커 출력단 하드웨어/드라이버 지연 비대칭 |
| 조건 | transpose/speed **ON** | **OFF(bypass)에서도 상존** |
| 처리 | v0.0.112 `SETTING_INITIAL_LATENCY` 부분 반영 | **미처리** |
| 크기 | rate 의존(수백 ms) | ~11ms (이 기기쌍, 음향 실측) |

→ 이번 11ms는 SoundTouch와 **독립**(bypass 측정). PLAN/(129)에서 "결함 B"로 뭉뚱그린 건 **결함 B-HAL**을 가리킴.

### 보정 설계 (초안) — ⚠️ 구현 보류(아래 "결정" 참조), 재개 시 출발점
1. **보정값 성격 (가장 큰 결정)**: acoustic은 두 기기 *상대* 출력지연차만 줌(쌍 11ms). 단일 기기 절대값은 분해 불가(loopback 단독 측정 없이는).
   - **(A) 기기쌍+역할 상수**: "S947N=host일 때 host +11ms" 하드코딩. 단순·즉효. 역할/기기 바뀌면 무효 → 재측정.
   - **(B) 기기별 절대 보정 테이블**: 모델명/식별자 → 출력지연 보정값 DB. 역할 무관 일반화. 단 절대값 분해가 필요(추가 측정 설계) + 기기 커버리지 문제.
   - **(C) 앱 내 자동 acoustic 캘리브레이션**: 한쪽 폰 마이크로 상대방+자기 출력 녹음 → 자동 보정((33-2) 옵션 C). 근본적·범용. 큰 작업.
2. **적용 위치**: ① native `out_lat_*_raw`에 보정 가산(Oboe 값 교정) vs ② Dart anchor 공식 `safeOutputLatencyMs` 비대칭 보정(`native_audio_sync_service.dart:1669` 영역)에 상수 추가. — 결함 B-ST의 `SETTING_INITIAL_LATENCY` hook과 합칠지도 검토.
3. **부호**: 호스트 출력이 ~11ms **빠름** → 호스트 outputLatency를 +11ms **크게** 잡아(=실제 더 늦게 도달하는 것처럼) 호스트 재생을 11ms 늦춰 정렬. (역으로 게스트 −11ms도 동치, 절대 분해 안 되면 상대만.)
4. **캘리브레이션 트리거**: 수동 1회 측정 → 상수 커밋(MVP) vs 앱 내 버튼/자동.

### 미해결/리스크
- **경로 의존성**: 11ms는 유선/내장스피커 기준. BT(codec/radio)·기기마다 다를 것((33-2)/(33-3) BT 케이스 = calculateLatencyMillis 부정확 최악). 보정 상수의 일반성 미검증.
- **측정 정밀도**: 현재 2점(rec2/rec5) + 음속보정(거리 추정) 오차 ±1~2ms. 상수 확정 전 3~5회 반복 + 거리 정밀 측정 권장.
- **절대 분해 불가**: acoustic 쌍 측정은 상대값만 → "어느 기기가 기준(0)인가" 미정. (B)로 가려면 기준 기기 1대 loopback 절대 측정 필요.
- **iOS**: `AVAudioSession.outputLatency`는 BT 반영(문헌) — Android와 보고 의미/정확도 다를 수 있어 iOS 별도 acoustic 필요.

### 결정 (2026-06-05) — 보정 구현 **보류 (close)**. 진단·인프라만 보존.
사용자 합의로 보정 구현 트랙 종료. 사유:
- **효용 작음**: 11ms는 인지 경계(청감 "미묘", 큰 어긋남은 monotonic이 이미 해결).
- **비용 큼 + 산출물 불완전**: 동적 보정엔 앱 내 acoustic 캘리브레이션이 필요한데, 그 측정 자체가 반향·거리·노이즈로 흔들림(이번 4회 실패가 증거) → **"측정해 보정했는데 측정오차로 또 틀어지는" 악순환** 위험.
- **outputLatency 본질적 불확실**: OS 보고든 acoustic이든 경로·코덱·환경에 휘둘림 → 완벽 보정은 환상, 11ms 위해 큰 인프라 떠안는 건 ROI 안 맞음.
- **더 큰 미해결 우선**: isOffsetStable jitter→anchor 공백 ±240ms(#1), 재입장 clock sync ~8초(#5)가 체감 좌우.

**보정 논의에서 확정한 설계 원칙 (재개 시 준수)**:
- **"값" 하드코딩 금지 → "값 받는 통로"만**: sync가 보정값을 저장소/동적 소스에서 읽기. 코드엔 메커니즘만, 값은 측정/설정/원격으로 주입.
- **값은 `(기기 × 출력경로)` 단위로 변동**: 같은 경로(내장스피커끼리)는 안정(rec2 12.0/rec5 12.6 실증), 경로 전환(내장↔BT↔이어폰)에서 크게 변함(BT 코덱/연결마다 수십~수백ms). → 경로별 캐싱 + 경로전환 감지(OS가 알려줌).
- 최종 값 소스 = **앱 내 acoustic 캘리브레이션**(원리·스크립트 이번 검증 완료, native/Dart 이식만 남음).

**재개 트리거**:
1. BT 스피커 등 **비대칭이 수십~수백ms로 커지는 경로**에서 실제 체감될 때.
2. anchor 공백·재입장 등 **큰 이슈를 다 잡고 11ms가 마지막 병목**이 될 때.

---

## 2026-06-05 — 결함 A 거친 정렬층 = anchor 주기 재발행 (1단계 설계 합의)

> 사용자와 개념 합의 완료(이 세션 대화). 결함 A "anchor 한 번 박고 믿기"의 해법. `native_audio_sync_service.dart`.

### 문제 재확인 (실측 근거)
- anchor establish는 게스트를 호스트 위치로 **seek + 그 시점의 환산값(offset/외삽/outLatDelta)을 baseline에 베이크인**(`:1586-1592`). 이후 `_recomputeDrift`는 **"baseline 대비 변화분(driftMs, rate)"만** 봄 → baseline의 절대 오차(0점 오차)는 driftMs로 안 보임("거짓말 패턴", `:1719`).
- **0점 오차의 출처 = 호스트가 아니라 게스트의 환산**: ① offset(clock sync ±오차, 수렴 중이면 더 큼) ② 500ms 묵은 obs 외삽 ③ outputLatency 비대칭(BT 분단위 ±30~70ms 출렁) ④ self-seek 도달 오차. **호스트 obs 데이터는 정확**, 게스트가 그걸 자기 시간축으로 옮기는 한 순간의 환산이 박혀 굳음.
- 환산 오차는 **체계적 편향이 아니라 랜덤**(HISTORY (126): anchor 세션마다 vfDiff +46/−65로 흩어짐, fallback은 0~5로 정확). → **매번 fresh 환산하는 fallback이 한 번 박는 anchor보다 정확**(실측). anchor는 안정성(변화분 보정)을 얻는 대신 0점 오차를 못 잡음.
- **현 v0.0.114 realign의 한계**: vfDiff 중앙값 ≥ **60ms**일 때만 baseline fresh 재정렬(`:1772-1793`). 그런데 결함 A 잔재는 **vfDiff −19.5ms로 일정**(톱니fix 후, PLAN "seek 임계 20 바로 아래라 방치") → 60 임계를 절대 안 넘어 **영구 잔존**. 반응적(틀어진 뒤)이라 "일정한 작은 편향"을 못 잡음.

### 핵심 통찰 (개념 합의)
- 고칠 건 **폴링 빈도(이미 100ms 충분)가 아니라 "0점(baseline)을 다시 박는 빈도"**.
- 현재 "0점 박기 = seek 무조건 동반"(`:1586`, `:1781`)이라 "자주 박기 = 자주 seek = 떨림"으로 묶임. → **분리**: 0점은 자주 fresh, seek(게스트 실제 이동)는 차이 클 때만.
- 단 **seek 없이 baseline 숫자만 갱신하면 실제 어긋남은 안 줄음**(게스트 안 움직이니). 어긋남을 실제로 줄이려면 seek(점프) 또는 rate-bend(속도 미세조정). → 작은 어긋남의 부드러운 흡수 = **rate-bend**(2단계).

### 1단계 MVP (이번 구현, 사용자 선택 — rate-bend 없이 Dart만)
- **realign을 시간 주기로도 발동**: 기존 `vfDiff ≥ 60ms`(반응적) **OR** `마지막 realign 후 N초 경과`(주기적, `_realignIntervalMs` 초기값 측정 후 확정 ~2000ms). 주기 발동이 vfDiff −19.5 같은 **일정 편향을 교정** → anchor 경로 vfDiff를 fallback 수준(0~5)으로.
- realign 동작은 기존 로직 재사용(`:1777-1791`): 현재 호스트 콘텐츠 절대 위치로 fresh 재정렬(seek + baseline fresh) + `_seekCooldown`(1초).
- **진동 방지** (사용자 우려 = 핵심 리스크): (a) `_seekCooldown` 1초로 연속 seek 차단 (b) **establish 오차를 한 번 fresh 정렬로 0 근처로 만들면 이후 주기 realign은 어긋남이 작아 seek 빈도가 자연히 ↓**. seek는 ring 재충전 + `getTimestamp` ErrorInvalidState(ts.ok=false, HISTORY (134))를 동반 → 그 직후 보정 금지가 cooldown의 본 목적.
- **측정**: realign 발동 빈도(주기 vs vfDiff 분리 — event `anchor_realign_periodic`/`anchor_realign_vfdiff`), seek 도달 정확도, vfDiff 분포(주기 realign 전후), 청감 떨림. `_realignIntervalMs`·임계는 측정으로 튜닝.

### 1단계 측정 결과 + 롤백 (2026-06-05) — 두 트랙 얽힘 확인, #1 선행 결정
구현(realign 2초 주기 `_realignIntervalMs=2000` + cooldown 1초) 후 2분 측정(호스트 S947N + 게스트 S901N):
- `anchor_realign_periodic` **31회 발동** — 주기 발동 메커니즘 자체는 작동.
- ⚠️ **offset 불안정이 지배**: `fallback` **109회**(isOffsetStable=false) vs anchor(drift) 126회 — 2분 내내 offset이 자주 unstable = **별도 트랙 #1(isOffsetStable jitter)**.
- realign 직후 vfDiff **−8~−46 톱니**(2초마다: realign event vfDiff=0은 `_logGuestEvent` placeholder, 실제는 다음 drift event가 −8/−33/−38/−46로 제각각). self-seek 오차로 의심되나 — **offset 불안정이라 vfDiff 신뢰 불가**(HISTORY (128) 교훈: vfDiff는 offset 의존 외삽값). → **효과 미확정**. 청감도 사용자가 집중 안 해 불명("대체로 OK").
- anchor mean −27 vs fallback median −9: 이 환경에선 anchor가 더 나빠 보이나 **vfDiff 거짓 가능성으로 단정 불가**.

**결정 (사용자 합의)**: 1단계 **롤백**(미커밋 코드 제거 — `git restore`). 사유: 효과 미확정 + self-seek 역효과 가능성 + **두 트랙 얽힘**(isOffsetStable jitter가 offset을 흔들어 anchor 측정을 오염 → 깨끗한 평가 불가). **"하나씩 확실히"** 원칙으로 #1을 먼저 분리해 풀기로.
- **다음 순서**: ① **#1 isOffsetStable jitter 해결 → offset 안정화** (fallback 지배 해소, vfDiff 신뢰 회복) → ② anchor 주기 재발행 **재측정**(이 설계 그대로 재적용 — 개념·1단계·2단계 모두 유효). 측정 토대(offset 안정)를 먼저 다진 뒤 anchor를 평가해야 self-seek 오차 여부도 진짜로 가려짐.

### 2차 재측정 + 트랙 보류(close) (2026-06-05, HISTORY (136))
v0.0.120(offset 안정화, #1) 후 1단계 재측정 — 1차 롤백 사유(offset 거짓)가 해소되어 깨끗한 평가 가능. realign 주기 발동(vfDiff≥60 OR N초) 구현(v0.0.121), 주기 2초/5초 스윕 측정(호스트 S947N + 게스트 S901N, 1배속, 평상시).

| 주기 | realign 횟수 | drift vfDiff med | offset stdev |
|------|-------------|------------------|--------------|
| baseline (realign 0) | 0 | **-4.83 / -5.42** | 1.0~1.2 |
| 5초 | 19 | **-15.05** | 0.38 |
| 2초 | 70 | **-26.38** | 0.51 |

**realign 빈도↑ = vfDiff 악화** (2초 -26 → 5초 -15 → ∞/baseline -5 = 주기↑일수록 baseline 수렴). offset 3개 측정 모두 안정이라 신뢰 가능(측정 아티팩트 아님). raw: realign 직후 vfDiff가 음수로 점프 후 다음 realign까지 고정 + 그동안 drift(rate) ±2~5 정상 = **거짓말 패턴**(baseline이 어긋난 자리에 박힘, rate는 맞음). **self-seek가 매번 음수 편향으로 박는 게 root** — establish(처음, accum≈0)는 -5로 정확한데 주기 realign(accum 누적)만 악화 = framePos 실이동 + accum 가상보정 **이중카운트 가설**(native virtualFrame/framePos 관계 미확정).

**왜 점프 방식 자체가 막히나 (close의 진짜 근거)**: 측정 1단계는 합의(`:282` "seek는 차이 클 때만, 기존 메커니즘이 알아서")와 달리 realign이 **매번 seek 동반**(1단계 MVP `:287`이 통찰과 모순). 합의판(숫자만 갱신, seek 분리)을 따져도 못 고침 — vfDiff(절대 위치)는 **anchor 독립**(`:1727-1728`)이라 숫자만 갱신하면 게스트가 안 움직여 -5 불변 + 기존 drift seek(`:1826`)는 baseline 갱신마다 drift 0 리셋(`:1788 clear`)으로 죽음 + -5는 drift에 안 보임(거짓말 패턴). 즉 -5는 vfDiff 문제인데 **기존 보정은 전부 drift(rate) 기반**(`:1813`/`:1826`, vfDiff 안 봄 `:1810`) → 점프(seek)로는 악화/떨림, **rate-bend(#5)만 깨끗**. 세 갈래(숫자만=무해무익 / seek=악화 / rate-bend=큰비용) 다 막혀 close.

**결정 (사용자 합의)**: seek 기반 1단계 **실패 확정** → **트랙 보류(close)**. 청감 "대체로 OK"(vfDiff -26인데 무영향 = 잔재 청감 임계 아래) + seek 접근은 할수록 해로움 + 2단계 rate-bend는 native+Dart 큰 비용 → **효용<비용**. baseline(v0.0.120, anchor 한 번 박기)이 현재 최선이라 유지. **결함 B 음향 11ms close (132)와 동형.** **재개조건**: BT 등 큰 비대칭 경로 체감 시 / 다른 큰 이슈 해결 후 마지막 병목 시 → 그땐 **seek 아닌 2단계 rate-bend**로.

### 2단계 (보류 — 결함 A 재개 시 진입점, seek 대신 rate-bend)
- **rate-bend 미세 정렬층**: 작은 어긋남을 seek(점프) 대신 SoundTouch `setTempo`(Android)/`AVAudioUnitTimePitch.rate`(iOS) ±0.05%로 흡수 → 점프 0 = 진동 원천 차단(ts.ok 불안정·ring 재충전 없음). vfDiff를 폐루프 입력으로. native + Dart 작업이라 1단계 효과 측정 후 착수.

### 리스크/메모
- 주기 realign이 매번 seek면 떨림 → `_realignIntervalMs`(주기)와 cooldown(1초)의 비율이 관건. 주기 < cooldown이면 cooldown이 빈도 상한. 측정으로 최적.
- self-seek 검증 무력화(결함 A 약점 2)는 1단계에서 그대로 — realign 직후 driftMs는 정의상 ~0. ANCHOR-VERIFY(`:1411`)가 seek 도달 오차 감시 유지.
- 별도 트랙(isOffsetStable jitter, 150ms 임계)은 이 트랙과 독립.
