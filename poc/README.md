# PoC: Native Audio Engine

본 앱(Synchorus)의 **동기 재생 엔진 핵심 기술**을 본 앱 통합 전 격리 검증한 두 개의 PoC 프로젝트.

| PoC | 플랫폼 | 네이티브 스택 | README |
|---|---|---|---|
| `native_audio_engine_android/` | Android | Oboe (C++/JNI) | [Android README](native_audio_engine_android/README.md) |
| `native_audio_engine_ios/` | iOS | AVAudioEngine (Swift) | [iOS README](native_audio_engine_ios/README.md) |

---

## 무엇을 검증했는가

`docs/PLAN.md` §6-1의 3가지 질문:

1. **네이티브 엔진 정밀도**가 정말 sub-ms인가 → ✅ Android `frames/ms = 48.0003`, iOS `48.0010` (60s+ 안정)
2. **Wi-Fi clock sync 노이즈** 수준 → ✅ EMA(α=0.1) + RTT-min로 ~5ms 안정
3. **폐루프가 진짜 수렴**하는가 → ✅ 30분 stress: Android 99.9%, iOS 99.6% (\|drift\|<20ms)

이 3개 질문에 답한 뒤 본 앱으로 통합 (HISTORY.md 2026-04-15 `step 1-1` ~ `step 1-4`). **임무 완료** 상태.

---

## 격리 원칙 (`docs/PLAN.md` §6-2)

PoC는 **변수 하나만 실험**. 본 앱과 분리된 Flutter 앱으로 만든 이유:

1. **세션 충돌 방지** — 본 앱의 `audio_service`/MediaSession/foreground service와 PoC의 raw Oboe/AVAudioSession이 같은 프로세스에서 돌면 OS audio focus 분쟁.
2. **변수 격리** — PoC가 답해야 할 3가지에 집중. UI 폴리싱·HTTP 파일 전송·백그라운드 모드·다중 게스트 등은 의도적으로 PoC에서 제외.
3. **회귀 검증 환경 보존** — 본 앱 알고리즘 변경 후 PoC로 같은 시나리오 재현 → "알고리즘 vs 통합 부산물" 분리 가능.

따라서 **본 앱 의존성 업그레이드, 알고리즘 변경, lint 규칙 변경 등은 PoC에 자동 반영되지 않음**. PoC를 다시 실행할 일이 생기면:

```bash
cd poc/native_audio_engine_android   # 또는 _ios
flutter pub get                       # PoC 자체 lockfile로
flutter build apk --debug             # 본 앱과 별개로 빌드
```

---

## 본 앱과의 관계

PoC가 검증한 알고리즘은 본 앱 `lib/services/native_audio_sync_service.dart` + `android/app/src/main/cpp/oboe_engine.cpp` + `ios/Runner/AudioEngine.swift`로 이식. 본 앱은 PoC 코드 위에:

- 비프 sine 생성 → 파일 디코딩(NDK MediaCodec / AVAudioFile)
- 1:1 → 1:N 멀티 게스트
- HTTP 파일 전송 + 호스트 라이프사이클 프로토콜
- BT outputLatency 동적 보정 (v0.0.38+)
- sampleRate cross-rate 정규화
- audio_service 백그라운드 + 알림바

본 앱의 동기화 알고리즘 코어 4단계(`_tryEstablishAnchor` / `_recomputeDrift` / `_performSeek` / `_maybeProbePostSeek`)와 파라미터 상수(`_driftSeekThresholdMs=20`, `_seekCorrectionGain=0.8`, `_seekCooldown=1s`, `_postSeekProbeMs=[100,300,500,1000,2000]`, `_reAnchorThresholdMs=200`)는 PoC와 1:1 이식.

---

## 향후 PoC 사용 시나리오

PoC는 **임무 완료** 상태지만 다음 경우 재사용 가치 큼:

- **알고리즘 v2 작업** (`docs/SYNC_ALGORITHM_V2.md`): NTP 정공법, EMA 단독 cherry-pick, anchor establishment 시점 변경 등 위험 큰 변경을 본 앱 회귀 위험 없이 격리 검증
- **새 디바이스 baseline 측정**: PoC는 변수 적어 새 칩셋 정밀도 빠르게 측정 가능
- **본 앱 회귀 디버깅**: 본 앱에서 동기화 회귀 발생 시 PoC로 동일 시나리오 재현 → 원인 분리

---

## 주의

- `docs/CLAUDE.md` "기능 수정 후 `pubspec.yaml` patch bump" 규칙은 **PoC 제외**.
- PoC 코드 수정 시 Android/iOS **양쪽 동시 반영** 필수 (Dart `lib/main.dart`는 양쪽 사실상 동일). 한쪽만 고치면 크로스플랫폼 검증 의미 상실.
- PoC의 MethodChannel 이름은 `com.synchorus.poc/native_audio` (본 앱은 `com.synchorus/native_audio`). 본 앱 ↔ PoC 간 코드 이동 시 채널명·JNI 함수명 prefix 변환 필수.
