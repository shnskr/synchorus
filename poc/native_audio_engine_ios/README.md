# PoC: Native Audio Engine — iOS (AVAudioEngine)

본 앱(Synchorus) 동기 재생 엔진의 **iOS 측 PoC**. AVAudioEngine 기반 네이티브 출력 + 호스트/게스트 동기화 알고리즘이 Android Oboe와 동일한 정밀도로 동작하는지 검증한 격리 프로젝트.

> **격리 사유**: Android PoC와 동일 (`poc/native_audio_engine_android/README.md` 1번 항목 참고). 본 앱과 별 프로젝트.

> **Dart 레이어는 Android PoC와 동일** — `lib/main.dart`는 Android PoC와 같은 MethodChannel 인터페이스(`com.synchorus.poc/native_audio`)를 사용해 호스트/게스트 코드를 공유. 차이는 **네이티브 구현** 한 곳뿐. Android는 Oboe(C++/JNI), iOS는 AVAudioEngine(Swift). 따라서 이 README는 **iOS 고유 부분**만 다루고, 알고리즘·CSV·분석 스크립트·실측 결과는 Android PoC README를 참고.

---

## 1. 답한 질문

`docs/PLAN.md` §6-1의 3가지 질문 중 **크로스플랫폼 검증** 부분:

| Q | 결론 | 근거 |
|---|---|---|
| Q1 (네이티브 정밀도) | ✅ Android와 동등 | Phase 0+1 iPhone: `frames/ms = 48.0010` (S22의 48.0003과 사실상 동일) |
| 크로스플랫폼 싱크 정확도 | ✅ ±20ms 99.6% | Phase 6 30분 stress S22 호스트 ↔ iPhone 게스트: `mean drift = +4.5ms`, `\|d\|<20ms = 99.6%` |
| 역방향 (iPhone 호스트 → S22 게스트) | ✅ 동일 정밀도 | 3 세션 모두 `\|d\|<20ms = 100%`, mean ±2ms |

상세는 `docs/HISTORY.md` 2026-04-15 "iOS PoC Phase 2~6" 섹션.

---

## 2. iOS 고유 구현 차이

### Native: `ios/Runner/AudioEngine.swift` (209줄)

Android `oboe_engine.cpp`와 동일한 5개 메서드(`start/stop/getTimestamp/seekToFrame/getVirtualFrame`)를 구현하되, Apple 오디오 스택 특성을 보정.

| 항목 | Android (Oboe) | iOS (AVAudioEngine) |
|---|---|---|
| 출력 노드 | `oboe::AudioStream` LowLatency Exclusive Float Stereo | `AVAudioEngine` + `AVAudioSourceNode` (render block) |
| sampleRate | `setSampleRate` 요청 → HAL이 채택 | `AVAudioSession.sampleRate` (요청 48000, hw가 44100일 수 있음 — 실제 적용값 사용) |
| 저지연 버퍼 | `setPerformanceMode(LowLatency)` | `setPreferredIOBufferDuration(0.005)` (5ms) |
| 타임스탬프 캡처 | `mStream->getTimestamp(CLOCK_MONOTONIC, ...)` | `engine.outputNode.lastRenderTime` (`sampleTime`, `hostTime`) |
| **HAL → DAC 보정** | Oboe getTimestamp가 이미 DAC 시점 반환 | `lastRenderTime`은 렌더링 시점 → `outputLatency + ioBufferDuration + nodeLatency` 빼야 DAC 시점 |
| Wall clock 변환 | `clock_gettime(REALTIME)` + `(MONOTONIC)` | `mach_absolute_time()` + `mach_timebase_info` + `Date().timeIntervalSince1970` |
| 락 | `std::mutex` | `os_unfair_lock` |

`AudioEngine.swift:147-198`의 `getTimestamp()`가 핵심:
```
lastRenderTime → sampleTime - latencyFrames = framePos (DAC 시점)
hostTime → numer/denom 변환 → timeNs (mach absolute → ns)
wallAtFramePosNs = wallNow - (monoNow - timeNs)
```

이 공식이 Android `oboe_engine.cpp:133-150`의 `wallAtFramePosNs` 계산과 1:1 대응 → 게스트 측 drift 외삽이 플랫폼 무관하게 동작.

### MethodChannel 핸들러: `ios/Runner/AppDelegate.swift`

`FlutterImplicitEngineDelegate` 구현, 채널 `com.synchorus.poc/native_audio` 등록. Android `MainActivity.kt`와 메서드 시그니처 동일.

#### ⚠️ b0415-7 버그 (이식 시 반드시 확인)

PoC 작성 초기 `seekToFrame` 핸들러가 `call.arguments`를 `[String: Any]` 딕셔너리로 파싱 시도 → Dart 측은 숫자 직접 전달 → 항상 `FlutterError` 반환 → seekToFrame이 한 번도 성공한 적 없음. drift는 2ms로 보였지만(rate 정확) 실제 오디오는 1초 뒤처짐.

**수정**:
```swift
guard let newFrame = (call.arguments as? NSNumber)?.int64Value else { ... }
```

본 앱 이식 시 동일 패턴 그대로 사용 (`AppDelegate.swift:35-44`).

---

## 3. 본 앱(Synchorus)으로의 이식 매핑

| PoC | 본 앱 | 차이 |
|---|---|---|
| `ios/Runner/AudioEngine.swift` | `ios/Runner/AudioEngine.swift` | `AVAudioSourceNode`(비프) → `AVAudioPlayerNode` + `AVAudioFile`(파일 재생). seek 구현은 `scheduleSegment` 기반 (stop → reschedule → play). virtualFrame은 `playerTime(forNodeTime:)` 기반 |
| `ios/Runner/AppDelegate.swift` | `ios/Runner/AppDelegate.swift` | `loadFile` 핸들러 추가, 채널명 `com.synchorus.poc/native_audio` → `com.synchorus/native_audio` |
| `getTimestamp` 반환에 `sampleRate, totalFrames` 없음 | 동일 + `sampleRate, totalFrames, outputLatencyMs, nodeLatencyMs, totalLatencyMs, ioBufferDurationMs` 노출 | 본 앱은 BT 보정용 outputLatency 동적 추적 (v0.0.38) |
| Info.plist 백그라운드 모드 없음 | `audio` 백그라운드 모드 + `AVAudioSession.setCategory(.playback)` | 본 앱은 백그라운드 재생 필요 |

본 앱 이식은 HISTORY.md 2026-04-15 `step 1-1`, `step 1-2`, `step 1-3`, `step 1-4`. PoC와 본 앱이 같은 알고리즘을 쓴다는 사실은 b0415-7~8 30분 stress 통과로 확인됨.

---

## 4. 코드 구조

```
poc/native_audio_engine_ios/
├── ios/Runner/
│   ├── AudioEngine.swift   # AVAudioEngine 래퍼 (209줄)
│   └── AppDelegate.swift   # MethodChannel 핸들러 (53줄)
├── lib/main.dart           # Android PoC와 거의 동일 (1859줄, 호스트/게스트 + drift/seek 알고리즘)
└── pubspec.yaml            # 본 앱과 분리된 Flutter 앱
```

**측정 데이터**: 이 디렉토리에는 `analysis/` 없음. iOS PoC 측정도 동일한 5종 CSV를 생성하지만 분석은 Android PoC의 Python 스크립트를 그대로 사용해 처리. iOS 세션 CSV는 측정 후 `poc/native_audio_engine_android/analysis/data/`로 옮기거나 별도 위치에 보관(현재는 보관 안 됨 — HISTORY.md 2026-04-15 결과는 청각 검증 + 텍스트 통계만 남음).

---

## 5. 빌드·실행

### 사전 조건
- macOS + Xcode
- Flutter SDK
- iPhone 실기기 + Apple Developer 계정

### 빌드
```bash
cd poc/native_audio_engine_ios
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

### 설치
**`flutter install` 미지원** — iOS는 Xcode를 거쳐야 함. CLAUDE.md "실기기 빌드/설치" 규칙은 본 앱에만 적용. PoC는:
1. `flutter run --device-id <iPhone UDID>` (USB)
2. 또는 Xcode `Runner.xcworkspace` 열고 Run

> **주의**: iOS 26.4.1 + macOS 26.3 환경에서 `flutter run`이 1~3분 hung되는 문제 (HISTORY (43), PLAN.md LOW-14). IntelliJ Run 또는 Xcode IDE 직접 Run 권장.

### 실측 절차
Android PoC와 동일 (호스트 IP 입력 → 자동 동기화 → CSV 5종 생성). iOS는 `getApplicationDocumentsDirectory()`로 떨어짐 (Files 앱 또는 Xcode Devices에서 추출).

---

## 6. 주의

- **Dart 코드는 Android PoC와 사실상 동일** — `lib/main.dart` 1821줄 vs 1859줄 차이는 `widget_test.dart` 잔재 등 minor. 알고리즘 변경은 **양쪽 동시에** 반영해야 PoC 의미 유지.
- **outputLatency는 BT 환경에서 underreported 가능** (Apple 포럼 합의, `developer.apple.com/forums/thread/126277`). PoC §6-1 Q2에서는 wired 출력만 검증. BT 시나리오는 본 앱 v0.0.38+ `_anchoredOutLatDeltaMs`로 별도 처리.
- **CLAUDE.md `version patch bump` 규칙은 PoC 제외** — 측정/실험용이라 버전 안 올림.
