# Synchorus 구현 계획

제품 기획/구현 계획/PoC 플랜. 설계·이력·결정은 아래 문서 참고.

- 아키텍처·로직: [ARCHITECTURE.md](ARCHITECTURE.md)
- 설계 결정: [DECISIONS.md](DECISIONS.md)
- 작업 이력: [HISTORY.md](HISTORY.md)

## PoC 플랜 (v3)

### 6-1. PoC가 답해야 할 3가지

1. **네이티브 엔진 정밀도**가 정말 sub-ms인가
2. **Wi-Fi clock sync 노이즈**가 어느 수준인가 (5-10ms 가정 검증)
3. **폐루프가 진짜 수렴**하는가 (drift → 보정 → 안정 사이클)

이 3개에 답하면 본 구현 GO. 못 답하면 설계 재검토.

### 6-2. 범위 (격리 원칙)

**PoC = 변수 하나만 실험**. 다른 모든 변수는 의도적으로 제외:

| 포함 | 제외 (본 구현 단계로 미룸) |
|---|---|
| Android Oboe 네이티브 엔진 | UI 폴리싱 |
| getTimestamp 폴링 + 로그 파일 | audio_service 플러그인 통합 |
| 최소 P2P (audio-obs, drift-report) | ~~iOS (별도 task)~~ ✅ |
| Drift 계산 + seek 보정 | rate 조정 |
| 광범위한 로깅 | 백그라운드 모드 |
| 호스트 1 + 게스트 1 | 멀티 게스트 |
| 로컬 파일 직접 재생 | HTTP 파일 전송 |

**왜 격리하는가**: 전부 다 넣으면 drift 원인 추적 불가능 ("sync 알고리즘 탓? 플러그인 충돌? HTTP 지연? 백그라운드?"). 좁게 잡아야 인과 분석 가능.

### 6-3. 단계별 진행

| 단계 | 내용 | 출력/통과 기준 | 상태 |
|---|---|---|---|
| 0 | Oboe 래퍼 + 단순 재생 | "소리 나옴" 확인 | ✅ 2026-04-08 S22 통과 |
| 1 | getTimestamp 폴링 + 파일 로그 | (framePos, ns) 시계열 확보 | ✅ 2026-04-08 S22 통과 |
| 2 | P2P audio-obs 송수신 | 게스트가 호스트 obs 수신 | ✅ 2026-04-09 S22+S10 통과 |
| 3 | drift 계산 (선형 보간) + clock sync | drift 시계열 로그, 네트워크 지연 분리 | ✅ |
| 4 | seek 보정 + drift-report | 보정 전/후 비교 | ✅ |
| 5 | 정적 노이즈 측정 (재생 후 30s) | 실측 noise floor | ✅ |
| 6 | S22 30분 stress + 네트워크 블립 | 누적 drift, 글리칭 검증 | ✅ 2026-04-14 |
| iOS | AVAudioEngine 동일 패턴 | 크로스플랫폼 싱크 ±6ms | ✅ 2026-04-15 (S22↔iPhone) |

각 단계 끝에 로그 분석으로 통과 판정. 다음 단계 가기 전 측정값 확인.

**Phase 0~1 실측 결과 (2026-04-08, S22 SM-S901N, Android 16 API 36 arm64)**
- Oboe 설정: `LowLatency + Exclusive + Float + Stereo` → `sampleRate = 48000 Hz`
- `frames/ms = 48.00` — 48000/1000 정확 일치. HAL이 Flutter 레이어까지 내부 일관된 타임스탬프를 전달함
- `framePos` 단조 ✓ / `timeNs` (CLOCK_MONOTONIC) 단조 ✓
- `Timer.periodic(100ms)` + MethodChannel 폴링, ok 유효율 거의 100%
→ **PoC 6-1의 질문 1번 (네이티브 엔진 정밀도 sub-ms)에 긍정 답**. `(framePos, deviceTimeNs)` pair가 JNI→Kotlin→MethodChannel→Dart 경로를 거쳐 손상 없이 도달 확인.

**Phase 2 실측 결과 (2026-04-09, S22 SM-S901N Android 16 호스트 + S10 SM-G977N Android 12 게스트, 60.4s)**
- TCP 다이렉트(JSON over `\n`), 500ms 주기 broadcast, 총 122개 수신
- **seq 연속성**: gaps = 0 ✅ (유실/재정렬 없음)
- **호스트 송신 주기**: mean 498.8ms, stdev 13.2ms (Timer 매우 정확)
- **게스트 수신 주기**: mean 498.0ms, stdev 67.8ms (평균은 보존, 지터는 크다)
- **frames/ms = 48.0003** — Phase 1과 동일값, 60초 장시간 안정
- **rx-host offset**: mean 507ms, range 473~636 (clock offset + 네트워크 지연 혼재, 분리는 Phase 3에서)
→ **§6-1 질문 1 재확인** (sub-ms 정밀도 장시간 안정).
→ **§6-1 질문 2는 아직 미답** — 수신 지터가 5배 크다는 사실은 확인했으나, 이게 WiFi 노이즈인지 게스트 OS 스케줄링인지 분리 못함. `sync-ping/pong` 구현 필요.

코드: `poc/native_audio_engine_android/` (독립 Flutter 프로젝트, 본 앱과 세션 충돌 방지 위해 격리)

### 6-4. 성공 기준

| 항목 | 목표 |
|---|---|
| 정적 noise floor | <10ms |
| 30분 보정 없이 누적 drift | <100ms |
| 보정 후 안정 시간 | <1초 |
| S22 글리칭 발생 빈도 | 분당 0회 |
| 글리칭 발생 시 복구 시간 | <2초 |

미달 시 → 어디서 막혔는지 로그로 진단 → 설계 재검토.

### 6-5. 본 구현 단계 흐름 (PoC 통과 후)

| 단계 | 내용 | 상태 |
|---|---|---|
| 1-1 | 네이티브 엔진 본체 앱 이식 (Android Oboe + iOS AVAudioEngine) | ✅ 2026-04-15 |
| 1-2 | Dart 서비스 레이어 (NativeAudioService) + 오디오 파일 디코딩 재생 | ✅ 2026-04-15 |
| 1-3 | P2P + clock sync + drift 보정 통합 | ✅ 2026-04-16 |
| 1-4 | 백그라운드 재생 (audio_service 연동) + 음소거 | ✅ 2026-04-17 |
| 2 | 1:1 → 1:N 멀티 게스트 확장 | ✅ 2026-04-22 (S22 호스트 + iPhone 12 Pro + A7 Lite 동시 실측, 코드 변경 없이 동작) |
| 3 | 로컬 파일 → HTTP 전송 추가 | ✅ (step 1-3에서 구현 완료, v0.0.22에서 shelf 제거·직접 구현으로 재작성) |
| 4 | rate 조정 추가 (UX 개선) | |
| 5 | UI 폴리싱 | |

각 단계 후 회귀 테스트.

## 다음 세션 작업 후보 (우선순위)

매 세션 시작 시 이 리스트로 진입점 결정. 완료된 항목은 체크해서 위로 통과. 새 항목은 우선순위에 끼워 넣기.

세션 마감 시 "지금까지 한 것"은 [HISTORY.md](HISTORY.md)에 기록, 이 리스트는 **앞으로 할 것**만.

### HIGH

1. **v0.0.54 다중 게스트 fix 실측 검증** — 같은 모델 갤럭시 2대 이상 환경에서 peer count 3 유지 + 비행기 모드 on/off 후에도 유지 확인. 현재 보유 디바이스(S22 + iPhone 12 Pro + Tab A7 Lite)는 모델 다 달라 A안만으로도 통과 → 진짜 검증은 같은 모델 2대 이상 필요. 상세: HISTORY (52).

1-A. ~~**(81) 신규 회귀 fix — 파일 변경 시 호스트 무음 + 게스트 단독 재생**~~ — **v0.0.69 (82) 완료**. audio-url playing=false + framePos>0 sanity gate + _latestObs reset. 실기기 검증 통과.

1-B. ~~**(81) 신규 회귀 진단 — T4 peer count 갱신 누락**~~ — **v0.0.71 (84) 완료**. root cause: `socket.done.catchError` 분기 broadcast 누락. 정상/에러 분기 통합 fix. 실기기 3대 검증 통과.

1-C. ~~**(82) 신규 회귀 fix — HTTP 404 stale state**~~ — **v0.0.70 (83) 완료**. `_cleanupTempDir` 활성 파일 보호 가드 + `_handleAudioRequest` disk 확인 + 진단 logging. 실기기 통과. root cause는 자연 재현 시 `[DIAG] startListening re-entry` 로그로 좁힐 예정.

2. ~~**v0.0.53 anchor fix 효과 검증 측정**~~ — **완료 (2026-05-02 (59))**. 결과: vfDiff signed -15.94ms (v0.0.52 -3.60ms 대비 4배↑), anchored vs current diff 0.22ms (EMA 효과 없음 확정). anchor 중복 호출 제거가 root cause 아니었음. 후속 작업은 신규 HIGH 항목 2-A/2-B로 분기.

2-A. ~~**anchor establish robustness**~~ — **SYNC_ALGORITHM_V2 §D-2로 흡수 (2026-05-02 (60))**. (60) raw 진단으로 root cause가 EMA convergence lag로 좁혀짐. 단독 fix 대신 디자인 단일 commit으로 묶음 (HIGH 4 참조).

2-B. ~~**anchor_reset_offset_drift 빈도 root cause**~~ — **(60)에서 진단 완료**. idle 3분 reset 4회는 잘못된 stable 판정으로 박힌 anchor가 EMA가 진짜 값에 따라잡는 동안 5ms 임계 자연 초과한 결과. clock skew 아니라 EMA convergence lag (`SyncService.isOffsetStable` 판정 결함). 단독 fix 대신 SYNC_ALGORITHM_V2 §D-2로 명세 후 단일 commit (HIGH 4 참조).

3. ~~**첫 재생 정착 시간 — BT 무관 (HISTORY (39))**~~ — **2026-05-02 (71) v0.0.63 §D-2 fix N=2 검증으로 자연 해소**. 청감 분포 좋음/좋음 일관, fallback alignment가 사용자 청감 임계 안에서 동작 확인. (44) 13번 사이클 회피 — fix 한 줄(§D-2)로 HIGH-3/4 둘 다 해결.

4. ~~**SYNC_ALGORITHM_V2 디자인 단일 commit**~~ — **2026-05-02 (70)/(71) 완료**. v0.0.63 §D-2 fix(D2-2 AND 조합) 적용 + N=2 검증 통과. anchor EMA gap 모든 케이스 < 2ms, anchor_reset 빈도 4회→0회. §A/B/D/E/F는 현행 유지 명세화, §C는 30분+ 장시간 측정 후 결정 보류.

### MID

5. ~~**HISTORY (45) -20.84ms 잔재 자연 재현 시 root cause 분해**~~ — **2026-05-03 §D-2로 자연 해소 정황 정리**. (a) outputLatency baked-in 가설은 (59) anchored vs current diff = 0.22ms로 사실상 부정. (b) §D-2(v0.0.63) 후 vfDiff signed mean -20.84ms → -5.25~-7.33ms로 4~7배 감소. (c) 자동화 N=3까지 진행했으나 -20ms 영역 미재진입. 진단 컬럼(`out_lat_*` + vf_diff_ms)은 활성 유지 — 큰 잔재 자연 재발 시 자동 캡처되어 HISTORY 미해결 이슈에 신규 항목으로 다시 띄움.

6. ~~**EMA 단독 cherry-pick (B-1) 검토**~~ — **우선순위 ↓ (2026-05-02 (59))**. 측정 결과 outputLatency anchored vs current diff = 0.22ms로 사실상 0 → EMA 보존 효과 미미할 것으로 강한 신호. 본 항목은 (A)/(B) root cause fix 진행 후에도 잔재가 있을 때만 재고려.

7. **30분+ 장시간 idle 측정** — rate drift 누적 검증. **2026-05-02 (77) v0.0.67 자동화 12분 측정에서 vfDiff signed mean -5.25ms로 큰 추세 미관찰**. 30분 측정은 14분 PCM 한계(`oboe_engine.cpp:143` 150MB)로 직접 불가. §C 결정은 PCM streaming 구조 변경 후로 미룸. 또는 측정 mp3를 여러 번 연속 재생(seek 0 반복)으로 우회 가능 — 다만 첫 anchor reset 발생.

8. **BT 워밍업 잔여 개선 (HISTORY (33-2), (37))**. iPhone 게스트 BT는 처음 ~40초 잔여 패턴. Galaxy+버즈는 ~2초로 양호 (Samsung HAL 정확 보고 추정). iPhone+버즈 케이스 한정 옵션 A(무음 prebuffer + outputLatency 수렴 게이팅) 시도.

9. **호스트 `oboe::getTimestamp` 간헐 실패 — 자연 재발 대기** (HISTORY (30) → v0.0.36 → v0.0.37). 재발 시 logcat `OboeEngine:W` 태그 `streak start/end` 짝짓기 → state/xrun/wallMs로 분류.
   - **외삽 모델 검토 (가설)**: `_recomputeDrift`(`native_audio_sync_service.dart:1376-1379`)가 wall clock 외삽 — `(hostWallNow - obs.hostTimeMs) * hostFpMs` — 을 쓰므로 obs가 stale이어도 외삽이 정확한 한 streak **그 자체로는 큰 위치 점프를 안 만듦**. (30) 체감 어긋남이 진짜였다면 root cause는 (a) **호스트 오디오 자체가 streak 동안 멈춤**(stream `ACTIVE` 이탈 / xrun → 외삽은 "갔을 거"로 추정하지만 실제 출력 못 감) 또는 (b) **재생 시작 직후 streak이 첫 anchor establish 시점을 늦추거나 잘못된 baseline에 박음** 분기. (31) state + xrunDelta 진단이 이 (a)/(b) 분기 가리는 용도 — 재발 시 해당 컬럼 우선 확인.

10. **iOS host 환경 검증** — Mac 환경 필요.

11. ~~**의존성 업데이트 검토**~~ — **2026-05-02 완료 (v0.0.57~v0.0.62)**. 6개 commit:
    - v0.0.57 안전 묶음 (patch/minor 8개)
    - v0.0.58 just_audio 죽은 의존성 제거
    - v0.0.59 audio_session 0.1→0.2
    - v0.0.60 network_info_plus 죽은 의존성 제거
    - v0.0.61 file_picker 8→11 (정적 메서드 마이그레이션)
    - v0.0.62 flutter_riverpod 2→3 (코드 변경 0)
    - **보류**: `device_info_plus` 12→13 + `package_info_plus` 9→10 (file_picker 11이 win32 ^5에 묶여 충돌. file_picker가 win32 ^6 지원할 때 묶음 commit). API 무변경이라 미루는 부담 작음.
    - **다음**: 실기기 풀세트 회귀 테스트 (특히 audio_session 0.2 BT 라우팅 + file_picker 11 + riverpod 3 onDispose 사이클).

### LOW

11. **errno=65/51 분기 캡처 (v0.0.28 백업 경로)** — connectivity_plus 즉시 반응으로 우회됨. AP 이동 or 다른 AP 시나리오에서만 캡처 가능. 코드 변경 0, 실기기 2대 + 2개 AP.

12. **HISTORY (47) Tab A7 Lite 호스트 framePos 비대칭** — D-1 시도 회귀 후 보류. 호스트 측 정규화 또는 다른 방향.

13. **acoustic loopback 외부 측정** (선택, 항목 8 검증에서 잔여 100ms+ 시 우선순위 ↑) — OS API 한계(BT codec/radio 단계 미보고) 잡으려면 마이크로 round-trip 측정. AOSP CTS 표준 방식.

14. ~~**iOS 26.4.1 + macOS 26.3 환경 빌드 install hung**~~ — **회피 표준화 완료 (v0.0.71 (84) 후속)**. CLAUDE.md "실기기 빌드/설치" + "iOS debug 빌드 디버거 attach 필요" 섹션 갱신. CLI hung 발생 시 잔재 프로세스 정리 명령어 + IntelliJ/Xcode 권장 명시. 근본 fix(Apple/Flutter toolchain 측 이슈)는 미해결이지만 **운영 측면에선 표준 우회로 마감**.

15. **디버그 모드 호스트 간헐적 스터터** — 릴리스에선 무관.

16. **UI 폴리싱** — Phase 4 확장 전 MVP 마감 다듬기.

## 화면 구성

### 홈 화면 (HomeScreen)
- **방 만들기** 버튼 → 방 코드 + "대기 중..." 표시
- **방 참가** → 자동 감지된 방 목록 or 코드 입력
- 로그인 상태 표시

### 플레이어 화면 (PlayerScreen)
- 호스트 전용: 파일 선택 버튼, URL 입력 필드
- 공통: 재생/일시정지, 시크바, 현재 재생 시간
- 접속자 목록 + 싱크 상태 표시
- 볼륨 조절 슬라이더

### 설정 화면 (SettingsScreen)
- 계정 관리
- 구독 상태 / 결제
- 오디오 출력 설정
- 오디오 지연 보정 슬라이더 (블루투스 등, 향후 추가)

## 수익화 전략

### 프리미엄 모델 (추천)

| 기능 | 무료 | 프리미엄 |
|------|------|---------|
| 동시 연결 디바이스 | 2대 | 무제한 |
| 재생 시간 | 30분/세션 | 무제한 |
| 오디오 품질 | 표준 | 고음질 (무손실) |
| 이퀄라이저 | X | O |
| 스테레오 분리 | X | O |
| 광고 | 배너 | 없음 |

### 결제 검증 흐름

```
앱 → 앱스토어/플레이스토어 결제 → 영수증 → Cloud Functions에서 검증 → 프리미엄 활성화
```

## 고려사항 / 한계

- **네트워크**: 같은 WiFi 필수 (Phase 4에서 WebRTC로 원격 지원 예정)
- **iOS 백그라운드**: `audio_service` 설정 + Info.plist에 background mode 추가 필요
- **Android 백그라운드**: foreground service 알림 필요
- **오디오 포맷**: mp3, m4a, wav, ogg, flac 등 `just_audio` 지원 포맷
- **방화벽/AP 격리**: 일부 공용 WiFi에서는 P2P 차단될 수 있음
- **로컬 네트워크 권한**: iOS 14+에서 로컬 네트워크 접근 권한 팝업 필요
- **블루투스 레이턴시**: 자동 보정 어려움, 수동 슬라이더로 대응 예정

## 출시 전략

Flutter 앱만으로 핵심 기능이 전부 동작 (서버 불필요) → 무료 앱 먼저 출시 → 유저 반응 확인 → Firebase 붙여서 수익화

```
Phase 1~2: Flutter 앱만 개발 → 무료 출시 (서버 비용 0원)
Phase 3:   유저 반응 좋으면 → Firebase 연동해서 프리미엄 모델 도입
Phase 4:   확장 기능 추가
```

## 구현 순서 (MVP → 확장)

### Phase 1: MVP (Flutter 앱만, 서버 없음) → 출시 가능
- [x] P2P 연결 (TCP 소켓 + UDP 디바이스 발견)
- [x] 시간 동기화
- [x] 오디오 파일 공유 + 동기화 재생/일시정지
- [x] 기본 UI (홈 + 플레이어)

### Phase 2: 안정화 + 핵심 기술 개선 (Flutter 앱만, 서버 없음) → 업데이트
- [x] 오디오 공유 방식 변경 (Base64 청크 → 로컬 HTTP 서버)
- [x] offset 계산 개선 (10회 핑퐁 + 백그라운드 주기적 재계산)
- [x] 동기화 재생 개선 (2초 딜레이 제거 → 즉시 재생 + 경과 시간 계산)
- [x] 재생 중 싱크 보정 (5초마다 position 비교 + seek 보정)
- [x] engineLatency 측정 및 보정 (플랫폼 채널 + 호스트-게스트 차이 보정)
- [x] 백그라운드 재생 (audio_service + 알림바/잠금화면 컨트롤)
- [ ] 연결 계층 추상화 (향후 WebRTC 전환 대비, Phase 4에서 진행)
- [x] 연결 끊김 시 자동 재연결
- [x] 에러 처리 + UX 개선

### Phase 3: 수익화 (Firebase 연동 시작)

#### 3-1. 결정 포인트 (진입 전 확정 필요)

| 항목 | 선택지 | 권장 초기값 |
|---|---|---|
| 계정 정책 | (A) 무료도 계정 필수 / (B) 프리미엄 전환 시만 | **B — Anonymous Auth로 식별, 전환 시 Apple/Google 연결** |
| 구독 모델 | (A) 월/연 구독 / (B) 일회성 결제 / (C) 혼합 | **A — 장기 수익 유리, IAP 심사도 구독이 관대** |
| 체험판 | (A) 없음 / (B) 7일 free trial | **B — IAP 전환율↑ 보고 많음. StoreKit 자체 지원** |
| 무료 플랜 제한 | 동시 참가자·재생 시간·기능 중 선택 | 세부는 MVP 출시 후 DAU 데이터로 결정 |

#### 3-2. 기술 스택

- **인증**: `firebase_auth` + Anonymous → Apple/Google 링크 (iOS는 Apple Sign-In 필수, App Store 정책 4.8)
- **결제**: `in_app_purchase` 플러그인 (StoreKit 2 / Google Play Billing). Firebase가 결제를 받는 게 아님 — 플랫폼 결제 30% 수수료 필수
- **영수증 검증**: Firebase Functions (Blaze plan 필요). App Store Server API / Google Play Developer API로 검증 후 Firestore `users/{uid}/subscription` 갱신
- **상태 동기화**: Firestore 구독 상태 → 앱 시작 시 `subscriptionStream`으로 구독 → UI/기능 gating
- **Analytics**: `firebase_analytics` 핵심 funnel 이벤트

#### 3-3. 구현 순서

1. Firebase 프로젝트 생성 + iOS/Android 앱 등록 + `firebase_core` 연동. 설정 파일(`GoogleService-Info.plist`, `google-services.json`) `.gitignore` 처리. FlutterFire CLI로 `firebase_options.dart` 생성.
2. `firebase_auth` + Anonymous Sign-In. 앱 시작 시 자동 로그인, uid 확보.
3. 설정 화면(`SettingsScreen`)에 계정 섹션 신설 + Apple/Google 링크 버튼 (전환 시 anonymous → federated upgrade).
4. App Store Connect + Google Play Console에서 IAP 상품 등록 (`synchorus_premium_monthly`, `synchorus_premium_yearly`). 샌드박스 테스트 계정 확보.
5. `in_app_purchase` 연동 + 구매 플로우 UI. 구매 완료 시 영수증을 Functions로 전송.
6. Firebase Functions (Node.js TypeScript) — App Store Server API / Google Play Developer API 영수증 검증 + Firestore write. 에뮬레이터로 로컬 테스트.
7. Firestore 구독 상태 스트림 → Riverpod provider → 기능 gating (예: 참가자 3명 이상, 이퀄라이저, 플레이리스트).
8. `firebase_analytics` funnel 이벤트 추가 (room_created, premium_upgrade_started, premium_upgrade_completed, churn_cancel).
9. iOS/Android 심사 제출 전 **IAP restore**, **환불 정책**, **구독 약관 URL** 필수. 취소된 구독의 grace period 처리 검토.

#### 3-4. 의존성·리스크

- **Blaze plan 요구**: Functions·Firestore 무료 티어 넘으면 사용량 과금. 출시 초기엔 무료 범위 내 예상.
- **Apple Developer/Google Play 결제 설정** 시간 소요 (Apple은 세금·은행 정보 심사 1~7일, Google 상대적으로 빠름).
- **심사 리스크**: 무료로 쓸 수 있는 기능을 지나치게 제한하면 iOS 심사 거절 가능. "동기화 재생" 자체는 무료, 편의 기능만 유료로 설계.
- **가격 설정 불확실성**: 경쟁 앱 부재라 참고치 부족. A/B 테스트 또는 초기 고정가로 시작 후 데이터 수집.

#### 3-5. 비용 추정 (월간, 1000 DAU 가정, 2026-04 시점 추정)

- Firebase Auth: 무료 (50K MAU까지)
- Firestore: 무료 티어 초과 시 read 1M당 ~$0.06, write 1M당 ~$0.18
- Functions: 2M 호출/월 무료
- Analytics: 무료
- **예상**: DAU 1000 × 구독 상태 체크·이벤트 기록으로 월 $1~$5 수준 시작, 사용자 증가 시 재산정

### Phase 4: 확장
- [ ] WebRTC 전환 (원격 P2P 지원)
- [ ] 볼륨 개별 제어 (디바이스별)
- [ ] 스테레오 분리 (L/R 채널 할당)
- [ ] 재생 목록 (Playlist)
- [ ] QR 코드로 방 참가
- [ ] 이퀄라이저
- [ ] 블루투스 레이턴시 수동 보정 슬라이더
- [ ] 파일 전송 대역폭 개선 후보 (현 TCP over 공유 WiFi 구조에선 소프트웨어로 낼 수 있는 수치 도달, 체감 향상은 링크 계층 변경 필요):
    - [ ] TCP `SO_SNDBUF` 조정 — 저비용, 효과 편차 큼
    - [ ] multi-stream 다운로드 (같은 파일 N개 TCP 병렬) — 중간 비용, AP가 WiFi 6+ 일 때 효과
    - [ ] Wi-Fi Direct / iOS MultipeerConnectivity — 공유기 거치지 않고 기기 간 직접 연결 (AirDrop급 속도). 크로스플랫폼 호환 위해 양 네이티브 플러그인 직접 구현 필요
    - [ ] HTTP 다운로드를 별도 Isolate로 분리 — 속도보다는 heartbeat 처리 안정성 목적 (v0.0.23 노트 참고)
- [ ] 라이프사이클·연결 추가 개선 후보 (v0.0.25 MVP 이후. 상세: `docs/LIFECYCLE.md`의 "앱 라이프사이클", "소켓 에러 코드(errno)", "연결 복구 전략" 섹션):
    - [x] ~~`RoomLifecycleCoordinator` 클래스 추출~~ — v0.0.29에서 구현 (`HISTORY.md` 2026-04-23 (21)). `lib/services/room_lifecycle_coordinator.dart` 신설, 라이프사이클/재접속/상태 로직 약 320줄 흡수. UI는 `ValueListenableBuilder` + 콜백만.
    - [x] ~~`AppLifecycleState.detached`에서 `host-closed` broadcast~~ — v0.0.26에서 구현 (`broadcastHostClosedBestEffort()`). 실측 1.4초 복구 확인(Android, 재생 중 케이스).
    - [x] ~~errno=111 refused 2회 연속 감지 시 watchdog 빠른 포기~~ — v0.0.27에서 구현 (`HISTORY.md` 2026-04-23 (19)). 이론 복구 시간 ~10초.
    - [x] ~~errno=113 EHOSTUNREACH / errno=101 ENETUNREACH 감지 시 `connectivity_plus` 이벤트와 연동~~ — v0.0.28에서 구현 (`HISTORY.md` 2026-04-23 (20)). `_maybeHandleNetworkErrno` 헬퍼 + 두 곳 호출.
    - [x] ~~`_awayReconnectTimer` 주기 조정 여지~~ — v0.0.27에서 `Socket.connect` timeout `5→2초` 적용. 12회 실패 시 실제 시간 ~2분 → ~1분 이내.
    - [ ] iOS 실기기에서 라이프사이클·재접속 시나리오 T1~T4 재검증 — 2026-04-24 (22)에서 S22 + Pixel 6 에뮬 조합으로 T1~T4a PASS 확인했으나 iOS 미검증 유지. iOS의 background audio 미활성 상태에서 paused 동작 특히 확인 필요.
    - [x] ~~errno=111 빠른 포기(v0.0.27) / errno=113·101 연동(v0.0.28) 실측 재검증~~ — 2026-04-24 (23)에서 S22+iPhone 실기기 LAN 조합으로 T4b 실측 PASS (~10초 fast giveup). 과정에서 Linux errno만 체크하던 v0.0.29 버그를 iOS 실측으로 발견 → v0.0.30에서 Darwin errno(61/65/51) 추가해 해결. W의 errno=65/51 분기 자체는 타이밍상 재현 안 됐으나 일반 재연결 성공.
