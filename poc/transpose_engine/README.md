# transpose_engine PoC

§H Transpose (pitch shift, 시간 무변경) 검증용 격리 Flutter 프로젝트.

## 격리 사유

본 앱 v0.0.91에서 H-1 시도 (Sonic + SoundTouch + AVAudioUnitTimePitch) 모두 실패 후 revert. Root cause: 음악용 batch processing 알고리즘이 oboe LowLatency callback burst(~96 frames)와 mismatch. 본 앱에 직접 통합하면 sync 알고리즘 회귀 위험 + 디버깅 변수 다수.

격리해서 검증 후 본 앱 통합.

## 격리 범위

| 포함 | 제외 (본 앱으로 미룸) |
|---|---|
| SoundTouch NDK 통합 + 컴파일 옵션 | UI 통합 (단순 슬라이더만) |
| Worker thread + lock-free ring buffer | P2P broadcast |
| Algorithm latency 측정 | sync 알고리즘 |
| Timing drift 측정 (input vf vs output frame) | iOS (별도 트랙) |
| 청감 검증 (±12 sweep) | 다중 audio source |
| 30분 stress (반복 cents 변경) | A-B 반복 / seek 메모리 |

## 통과 기준

- ✅ 청감: ±12 sweep 동안 click/buzz/속도 변화 0
- ✅ Timing drift: 1분 재생 후 input vf == output frame ±10ms
- ✅ Algorithm latency 안정 (분 단위 변동 < 5ms)
- ✅ Underrun/glitch 분당 0회
- ✅ 30분 stress crash 0

미달 시: SoundTouch 한계 확정 → Rubberband (GPL) 또는 ExoPlayer SonicAudioProcessor (Kotlin layer) 시도.

## 본 앱과 매핑

| PoC 결과 | 본 앱 통합 |
|---|---|
| Worker thread 패턴 검증 | `oboe_engine.cpp`에 같은 패턴 적용 |
| Algorithm latency 측정 식 | `getLatestTimestamp` outputLatencyMs에 더하기 |
| Bypass 분기 (cents=0) | 본 앱도 동일 (음질 손실 0) |
| Timing drift 보정 식 | sync 알고리즘에 반영 (호스트/게스트 동일 패턴이라 자동 상쇄) |

## 디자인 명세

[docs/SYNC_ALGORITHM_V2.md §H](../../docs/SYNC_ALGORITHM_V2.md) — H-2-A~H 합의 항목.

## 재실행

```bash
cd poc/transpose_engine
flutter run --device-id <android_device>
```

S22 (R3CT60D20XE) 또는 S24 (R3KL207HBBF) — 본 앱과 동일 device.

## 라이센스

- Flutter project: Apache 2.0 (synchorus 본 앱과 동일)
- SoundTouch (통합 예정): LGPL v2.1 (.so 동적 로드, 소스 위치 명시)

## 진행 상태

- ✅ Scaffold (Flutter Android 프로젝트)
- ⏳ NDK + Oboe + SoundTouch CMake 통합
- ⏳ Worker thread + ring buffer 구현
- ⏳ 측정 인프라 (algorithm latency + timing drift + glitch counter)
- ⏳ 청감 검증 UI (음원 선택 + 슬라이더)
- ⏳ 30분 stress + 보고서
