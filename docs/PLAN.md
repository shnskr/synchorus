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
- [ ] Firebase 인증 + 결제 연동
- [ ] 프리미엄 기능 게이팅
- [ ] Firebase Analytics 연동

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
    - [ ] `RoomLifecycleCoordinator` 클래스 추출 — `room_screen.dart`의 라이프사이클/재접속/상태 로직을 별도 클래스로 분리. 역할 × 라이프사이클 매트릭스를 한 곳에서 선언. UI는 상태 구독만.
    - [x] ~~`AppLifecycleState.detached`에서 `host-closed` broadcast~~ — v0.0.26에서 구현 (`broadcastHostClosedBestEffort()`). 실측 1.4초 복구 확인(Android, 재생 중 케이스).
    - [ ] errno=111 refused 2회 연속 감지 시 watchdog 빠른 포기 — 재생 전 호스트 종료 복구(현재 watchdog 2분 → ~10초).
    - [ ] errno=113 EHOSTUNREACH / errno=101 ENETUNREACH 감지 시 `connectivity_plus` 이벤트와 연동 — WiFi 변경·AP 변경 케이스에서 WiFi 복구 대기 로직(`_waitForWifiAndReconnect`) 바로 트리거.
    - [ ] `_awayReconnectTimer` 주기 조정 여지 — 현재 5초 × 12회 = 60초 공칭이지만 timeout 7초씩이라 실제 ~2분. `Socket.connect` timeout을 2초로 줄이면 실제도 1분 이내.
    - [ ] iOS 실기기에서 라이프사이클·재접속 시나리오 T1~T4 재검증 — 현재는 Android 2대(S22+A7 Lite)로만 검증됨. iOS의 background audio 미활성 상태에서 paused 동작 특히 확인 필요.
