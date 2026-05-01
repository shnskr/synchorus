# PoC: Native Audio Engine — Android (Oboe)

본 앱(Synchorus) 동기 재생 엔진의 **Android 측 PoC**. Oboe 기반 네이티브 오디오 출력 + 호스트/게스트 동기화 알고리즘을 본 앱 통합 전 단계에서 검증한 격리 프로젝트.

> **격리 사유**: 본 앱은 `audio_service` 등 Flutter 오디오 플러그인을 사용. PoC가 본 앱과 같은 프로세스에서 돌면 AAudio 세션·MediaSession·foreground service가 충돌. PoC를 별도 Flutter 앱으로 분리해 변수 하나(네이티브 엔진 정밀도)만 독립 실험. (`docs/PLAN.md` §6-2 "격리 원칙")

---

## 1. 답한 질문

`docs/PLAN.md` §6-1의 3가지 PoC 질문 중 두 개를 Android에서 검증:

| Q | 질문 | 결론 | 근거 |
|---|---|---|---|
| Q1 | 네이티브 엔진 정밀도가 정말 sub-ms인가 | ✅ **YES** | Phase 1 S22: `frames/ms = 48.00` (48000Hz 정확 일치, 60s+ 안정) |
| Q2 | Wi-Fi clock sync 노이즈 수준 | ✅ **5~10ms** 가정 검증 | Phase 3 sync ping/pong + EMA(α=0.1) → 1.34ms stdev (28s) |
| Q3 | 폐루프가 진짜 수렴하는가 | ✅ **YES** | Phase 6 31분 stress: \|drift\|<20ms = **99.9%**, seek 17회 |

---

## 2. Phase 0~6 단계별 결과

| Phase | 내용 | 통과 기준 | 결과 |
|---|---|---|---|
| 0 | Oboe 래퍼 + sine 재생 | "소리 나옴" | ✅ S22 (2026-04-08) |
| 1 | getTimestamp 폴링 + 시계열 | (framePos, ns) 단조, frames/ms=48.0 | ✅ S22 100% 유효율 |
| 2 | P2P audio-obs 송수신 | 게스트가 호스트 obs 수신 | ✅ S22+S10 (60s, gaps=0) |
| 3 | drift 계산 + clock sync | drift 시계열, 네트워크 지연 분리 | ✅ ping/pong + EMA |
| 4 | seek 보정 + drift-report | 보정 전/후 비교 | ✅ \|pre\|=47→\|post\|=25 (35%↓) |
| 5 | 정적 noise floor + 시간축 정합 | <10ms | ✅ 5/6차 max \|drift\|=8.9ms |
| 6 | 30분 stress + 네트워크 블립 | 누적 drift, 글리칭 | ✅ 31분 \|drift\|<20ms 99.9% |

상세는 `docs/HISTORY.md` 2026-04-08 ~ 2026-04-10 섹션.

### Phase 4~5에서 발견·수정한 버그 (감사 기록)

| # | 원인 | 수정 |
|---|---|---|
| A | `seekToFrame`은 `mVirtualFrame`만 덮어쓰고 HAL `framePos`는 영향 없음 → seek해도 drift 안 줄어듦 | `_seekCorrectionAccum` 누적 → `effectiveGuestFrame = framePos + accum`으로 복원 |
| B | 앵커 시점 obs는 최대 500ms 오래된 값이라 `anchorHF` 시간축 불일치 → 초기 -315ms 오프셋 | 앵커 순간의 host wall까지 obs 선형 외삽해서 저장 |
| C | 호스트 broadcast `hostTimeMs`가 broadcast 순간 wall (framePos는 100ms 전 poll값) → ±100ms 스파이크 | `hostTimeMs = latest.wallMs`로 framePos와 pair |
| D | drift = dG−dH는 rate만 봄. 초기 절대 오프셋(770ms) 영구 보존 → 청각 완전 어긋남 | 앵커 시 `seekToFrame(anchorHF)` 즉시 정렬 + `_seekCorrectionAccum += initialCorrection` |
| E | `wallMs = DateTime.now()` (Dart) vs `timeNs` (네이티브) 캡처 시점 다름 → ±40ms 변동 → 외삽 ±100ms 스파이크 | 네이티브 `getLatestTimestamp`에서 `clock_gettime(REALTIME)` + `(MONOTONIC)` 같은 lock 안에서 찍어 `wallAtFramePosNs` 반환 |
| F | `audio-obs`가 HAL framePos만 송신 → 호스트 seek 후에도 framePos는 단조 증가 → 게스트가 호스트 seek 못 알아챔 | `AudioObs.virtualFrame` 필드 추가, 콘텐츠 정렬은 vf 기반 |
| G | 큰 drift(200ms+)에서 `gain=0.8` 점진 보정이 발산 (타겟이 움직임) | \|drift\|≥200ms → 앵커 즉시 재설정 |
| H | 콘텐츠 정렬에 virtualFrame, drift 계산에도 virtualFrame 쓰면 rate 누적 오차 | 역할 분리: rate drift는 framePos, 콘텐츠 정렬은 virtualFrame |

---

## 3. 본 앱(Synchorus)으로의 이식 매핑

PoC가 검증한 패턴을 본 앱으로 옮긴 흔적. **본 앱 작업 시 PoC 코드를 직접 수정해도 본 앱엔 영향 없음** (별 프로젝트). 반대로 본 앱에서 발견한 알고리즘 수정을 PoC로 역포팅할 수도 있음.

### 네이티브 엔진

| PoC | 본 앱 | 차이 |
|---|---|---|
| `android/app/src/main/cpp/oboe_engine.cpp` | `android/app/src/main/cpp/oboe_engine.cpp` | 비프 sine 생성 → NDK `AMediaExtractor` + `AMediaCodec` 파일 디코딩 (int16 풀버퍼 ≤150MB, Oboe SRC) |
| JNI: `Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_*` | JNI: `Java_com_synchorus_synchorus_NativeAudio_*` | 네임스페이스만 변경 |
| `nativeGetTimestamp`: `[framePos, timeNs, wallAtFramePosNs, ok, virtualFrame]` (long[5]) | 동일 + `sampleRate`, `totalFrames` 추가 (long[7]) | 파일 메타데이터 노출 |
| `MethodChannel("com.synchorus.poc/native_audio")` | `MethodChannel("com.synchorus/native_audio")` | 채널명 prefix 제거 |
| `loadFile` 메서드 없음 | `loadFile(String path)` 추가 | PoC는 비프, 본 앱은 파일 |

본 앱 이식 commit 흐름 (HISTORY.md 2026-04-15):
- `step 1-1`: 엔진 본체 이식 (비프 → 본 앱 빌드)
- `step 1-2`: 비프 → 파일 디코딩으로 전환
- `step 1-3`: P2P + clock sync + drift 보정 통합
- `step 1-4`: 백그라운드 재생 (`audio_service` 연동)

### Dart 레이어

| PoC | 본 앱 |
|---|---|
| `lib/main.dart` `_HostPageState` (Oboe 폴링 + obs broadcast + seek-notify 송신) | `lib/services/native_audio_sync_service.dart` 호스트 경로 |
| `lib/main.dart` `_GuestPageState` (TCP 수신 + sync ping/pong + drift 계산 + seek 보정) | `lib/services/native_audio_sync_service.dart` 게스트 경로 |
| MethodChannel 직접 호출 | `lib/services/native_audio_service.dart` 래퍼 경유 |
| TCP 다이렉트, IP 수동 입력 | `lib/services/p2p_service.dart` (mDNS discovery + welcome/host-closed/heartbeat 프로토콜) |

### 동기화 알고리즘 (그대로 이식)

PoC §6-2 `Phase 4 알고리즘` 주석(`lib/main.dart:9-31`)이 본 앱 `native_audio_sync_service.dart`의 `_tryEstablishAnchor` / `_recomputeDrift` / `_performSeek` / `_maybeProbePostSeek` 4단계로 1:1 이식. 파라미터 상수도 동일:
- `_driftSeekThresholdMs = 20.0`
- `_seekCorrectionGain = 0.8`
- `_seekCooldown = 1000ms`
- `_idealFramesPerMs = 48.0`
- `_postSeekProbeMs = [100, 300, 500, 1000, 2000]`
- `_reAnchorThresholdMs = 200.0`
- Clock sync EMA: 초기 10회 빠른 ping (100ms 간격) → RTT-min, steady 1s/ping + window=5 RTT-min + α=0.1

본 앱은 여기에 v0.0.20+에서 추가:
- sampleRate cross-rate (PoC는 48kHz 고정, 본 앱은 파일 rate 정규화)
- BT outputLatency 비대칭 보정 (`_anchoredOutLatDeltaMs`, v0.0.38)
- 호스트 라이프사이클 프로토콜 (`host-closed`, heartbeat)

---

## 4. 코드 구조

```
poc/native_audio_engine_android/
├── android/app/src/main/
│   ├── cpp/oboe_engine.cpp         # Oboe 래퍼 + 음계 비프 + virtual playhead seek (292줄)
│   └── kotlin/.../NativeAudio.kt   # JNI 래퍼 (28줄)
├── lib/main.dart                   # PoC 단일 파일 (1821줄)
│                                   #   ├─ const 파라미터 (60-90줄)
│                                   #   ├─ Sample / AudioObs / SyncPing / SyncPong (168-323줄)
│                                   #   ├─ HostPage (329-855줄): TCP 서버 + obs broadcast + seek 버튼
│                                   #   └─ GuestPage (925-1780줄): TCP 수신 + ping + drift + seek
├── analysis/                       # 오프라인 분석 (Python)
│   ├── estimate_drift.py           # framePos vs timeNs 선형회귀 → host/guest ppm + 30분 누적 drift 추정
│   ├── compare_sync_filters.py     # 6개 clock-sync 필터 비교 (naive/EMA/median/weighted RTT/linreg)
│   ├── phase4_drift_vs_seek.py    # drift 시계열 + seek 이벤트 + post-seek 수렴 PNG 생성
│   ├── requirements.txt            # numpy, matplotlib
│   └── data/                       # 측정 CSV 81개 (Phase 2~6 모든 세션, 보존)
└── pubspec.yaml                    # 본 앱과 분리된 Flutter 앱
```

---

## 5. 측정 데이터 (`analysis/data/`)

Phase 2~6 모든 세션의 CSV 81개 (Phase 6 30분 stress 포함). git tracked. **삭제 금지** — 분석 스크립트 입력이고 알고리즘 회귀 검증 시 재실행 가능.

각 세션은 timestamp 접미사로 묶임 (예: `2026-04-09T22-06-33-153879`). 5종 한 세트:

| 파일 | 컬럼 | 의미 |
|---|---|---|
| `audio_obs_*.csv` | `seq,hostTimeMs,rxWallMs,anchorFramePos,anchorTimeNs,framePos,timeNs,playing` | 호스트가 보낸 obs를 게스트가 받은 시계열 |
| `sync_*.csv` | `seq,t1,t2,t3,rttMs,rawOffsetMs,filteredOffsetMs,phase` | clock sync ping/pong + EMA 필터 출력 |
| `guest_ts_*.csv` | `wallMs,framePos,timeNs,ok` | 게스트 자체 Oboe 폴링 |
| `drift_*.csv` | `wallMs,obsHostFrame,obsHostTimeMs,guestFrame,seekAccum,filteredOffsetMs,expectedHostFrame,driftMs` | 매 게스트 poll에서 계산된 drift (Phase 4) |
| `seek_events_*.csv` | `eventId,wallMs,msSinceSeek,driftMs,correctionFrames,oldVf,newVf,kind` | seek 이벤트 + post-seek probe (Phase 4) |

**주요 세션 인덱스**:

| 세션 timestamp | 의도 |
|---|---|
| `2026-04-09T22-06-33-*` | Phase 2 60s 기준선 (rate drift 측정용) |
| `2026-04-09T23-15-*` ~ `2026-04-10T00-09-*` | Phase 4 1~4차 (버그 A~E 발견) |
| `2026-04-10T09-40-*` ~ `2026-04-10T10-29-*` | Phase 5 5~11차 (버그 F~G fix) |
| `2026-04-10T13-06-00-238661` | Phase 6 31분 stress (최종 통과) |

---

## 6. 빌드·실행

### 사전 조건
- Flutter SDK (본 앱과 동일 채널)
- Android NDK + Oboe 1.9.0 prefab (Gradle이 자동 받음)
- 실기기 2대 권장 (본 앱 CLAUDE.md 기준 S22 + S10/Z플립4 등)

### 빌드 + 설치 (본 앱과 별 프로젝트라 cd 필요)
```bash
cd poc/native_audio_engine_android
flutter pub get
flutter build apk --debug --target-platform android-arm64
# 호스트 기기
flutter install --debug --device-id <HOST_SERIAL>
# 게스트 기기 (USB 1대씩 연결 → 설치 → 교체)
flutter install --debug --device-id <GUEST_SERIAL>
```

### 실측 절차
1. 호스트: 앱 → "호스트 시작" → IP 표시 (예: `192.168.0.10`)
2. 게스트: 앱 → "게스트로 연결" → 호스트 IP 입력
3. 호스트에서 ▶ 누르면 음계 비프 재생 + obs broadcast + 게스트 자동 시작
4. 호스트에서 ±3s/±10s seek 버튼으로 호스트 seek 시나리오 시험
5. 종료 후 게스트 외부 저장소에서 CSV 5종 pull:
   ```bash
   adb -s <GUEST_SERIAL> pull /storage/emulated/0/Android/data/com.synchorus.poc.native_audio_engine_android/files/ ./pull/
   # 단, 멀티유저 환경에선 /storage/emulated/95/ 등으로 떨어질 수 있음 (HISTORY 2026-04-15 참고)
   ```
6. CSV를 `analysis/data/`로 옮기고 분석 스크립트 실행

### 분석 스크립트 실행
```bash
cd analysis
python3 -m venv .venv && source .venv/bin/activate  # 또는 .venv\Scripts\activate (Win)
pip install -r requirements.txt
# SESSION 변수를 estimate_drift.py 상단에서 수정 (예: SESSION = "2026-04-10T13-06-00-238661")
python estimate_drift.py
python compare_sync_filters.py
python phase4_drift_vs_seek.py 2026-04-10T13-06-00-238661  # session timestamp 인자
# 결과: analysis/output/*.png + stdout 통계
```

---

## 7. 향후 PoC 사용 시나리오

PoC는 **임무 완료** 상태(2026-04-15에 본 앱으로 이식). 그러나 다음 경우 재사용:

1. **알고리즘 v2 작업** (`docs/SYNC_ALGORITHM_V2.md`): NTP 정공법, EMA 단독 cherry-pick, anchor establishment 시점 변경 등 **위험 큰 알고리즘 변경**을 본 앱 회귀 위험 없이 격리 검증.
2. **회귀 검증**: 본 앱에서 동기화 회귀 발생 시 PoC로 같은 시나리오 재현 → "알고리즘 vs 통합 부산물" 분리.
3. **새 디바이스 측정**: PoC는 변수 적어 새 칩셋의 baseline 정밀도 빠르게 측정 가능.
4. **iOS와 비교**: `poc/native_audio_engine_ios/`와 같은 main.dart 인터페이스라 호스트/게스트 역할 swap 시험.

---

## 8. 주의

- **본 앱과 별 프로젝트** — `pubspec.yaml`도 별도. 본 앱 의존성 업데이트가 자동 반영 안 됨. PoC 재실행 전 `flutter pub get` 필수.
- **MethodChannel 이름 다름** — `com.synchorus.poc/native_audio` (본 앱은 `com.synchorus/native_audio`). 본 앱 코드를 PoC에 붙여넣을 때 채널명 변환 필수.
- **JNI 함수명 다름** — 본 앱 코드를 PoC `oboe_engine.cpp`로 가져갈 때 함수명 prefix 변환 필수 (`synchorus_synchorus` ↔ `poc_native_1audio_1engine_1android`).
- **CLAUDE.md `pubspec.yaml version patch bump` 규칙은 PoC 제외** — PoC는 측정/실험용이라 버전 안 올림.
