# Synchorus

여러 핸드폰을 동기화된 스피커로 만드는 Flutter 앱 (P2P).

## 현재 단계
v3 본 구현 진행 중. 최신 릴리스 **v0.0.31** (2026-04-24) — iOS 실측 과정에서 드러난 StreamController race 수정 + CONNECTIVITY 경로 로그 보강.

- **Step 1-1 ~ 1-4**: 완료 (네이티브 엔진 이식 + Dart 서비스 + P2P/clock sync/drift 보정 + 백그라운드 재생)
- **Step 2 멀티 게스트**: 실기기 3대(S22 + iPhone 12 Pro + Galaxy Tab A7 Lite) 동시 테스트로 검증됨. 코드 변경 없이 1:N 동작
- **Step 3 HTTP 전송**: 완료 (v0.0.22에서 shelf 제거, dart:io HttpServer 직접 + 1MB chunk)
- **호스트 라이프사이클 프로토콜**: v0.0.25 추가 — `host-paused`/`host-resumed`/`host-closed` + 게스트 주기적 재접속 + watchdog. T1~T4 Android 검증 완료 (2026-04-22). v0.0.29 coordinator 추출 후 T1~T4a 재검증(S22+Pixel 6 에뮬, 2026-04-24). **v0.0.30에서 Darwin errno 버그 수정 + T4b 실측 PASS (S22+iPhone ~10초 fast giveup)**

v2 AudioSyncService 삭제됨 — NativeAudioSyncService로 교체. audio_handler.dart: NativeAudioHandler.

### 최근 해결 (2026-04-22)
- v0.0.20: seek-notify 가드(`!_playing`→`!_audioReady`) + 태블릿 가로모드 UI 스크롤
- v0.0.22: HTTP 서버 재구현 (shelf 제거 + Content-Length + 1MB chunk) + 다운로드 측정 인프라 (`download-report` P2P 메시지)
- v0.0.23: heartbeat timeout 9→15초. 다운로드 중 끊김 해결
- v0.0.25: **호스트 라이프사이클 프로토콜** (host-paused/resumed/closed) + 게스트 자리비움 배너 + 주기적 재접속 Timer + watchdog(12회/~2분). drift 노이즈 완화(C: 중앙값, A: clock sync window 10). 상세: `docs/LIFECYCLE.md`의 "앱 라이프사이클 / errno / 연결 복구 전략" 섹션
- v0.0.26: **detached에서 host-closed best-effort broadcast** — 재생 중 호스트 종료 시 게스트 복구 2분 → **실측 1.4초 확인** (S22 + A7 Lite). 재생 전 종료 / iOS 강제 종료는 detached 미도달 가능성 있어 watchdog fallback 유지
- v0.0.27: **Socket.connect timeout 5→2초** + **errno=111 2연속 → watchdog 빠른 포기** (재생 전 호스트 종료 / iOS 강제 종료 fallback ~2분 → ~10초 이론값). 실측 검증은 다음 세션. 상세: `docs/HISTORY.md` 2026-04-23 (19)
- v0.0.28: **errno=113/101 + connectivity_plus 연동** — WiFi 변경·AP 변경 시 connectivity 이벤트 늦어도 errno로 조기 감지 → `_waitForWifiAndReconnect` 즉시 트리거. 라이프사이클·연결 후보 6개 중 5개 완료. 상세: `docs/HISTORY.md` 2026-04-23 (20)
- v0.0.29: **`RoomLifecycleCoordinator` 추출** — `lib/services/room_lifecycle_coordinator.dart` 신설. `room_screen.dart`(828줄) 라이프사이클·연결 로직 약 320줄을 별도 클래스로 분리. UI는 `ValueListenableBuilder` + 콜백만. 라이프사이클·연결 후보 6개 모두 완료, Phase 4 라이프사이클 영역 종결. 상세: `docs/HISTORY.md` 2026-04-23 (21)
- **2026-04-24 (22)**: 실측 재검증 (S22 + Pixel 6 에뮬). T1~T4a **PASS** (coordinator 동등성). T4b/W는 adb forward의 TCP accept 가짜 성공 때문에 에뮬로는 검증 불가 → 실기기 LAN 필요. 상세: `docs/HISTORY.md` 2026-04-24 (22), `docs/EMULATOR_NETWORK.md`
- **v0.0.30 (2026-04-24 (23))**: iPhone 12 Pro USB 복구 후 S22+iPhone 실기기 LAN으로 T4b 실측 중 **Darwin errno=61 미체크 버그** 발견 (v0.0.27 코드가 Linux `errno=111`만 하드코딩, iOS에서 작동 안 함). `room_lifecycle_coordinator.dart`에 `_refusedErrnos = {111, 61}` + `_networkUnreachableErrnos = {113, 101, 65, 51}` 집합 도입. 재검증 **~10초 fast giveup PASS**. 상세: `docs/HISTORY.md` 2026-04-24 (23)
- **v0.0.31 (2026-04-24 (24))**: W 시나리오(iPhone WiFi 30초+ off) 재현 중 **`P2PService._disconnectedController` race 예외** 발견 (`Bad state: Cannot add new events after calling close`, p2p_service.dart:345/384) → isClosed 가드 추가. 추가로 `_handleConnectivity` / `_waitForWifiAndReconnect` 경로에 `[CONNECTIVITY]` 태그 `debugPrint` 5개 보강 (기존엔 onLog만 써서 CLI 로그에 안 찍혔음). W 시나리오 connectivity 경로 **PASS** — WiFi off 15초 대기 후 자동 leaveRoom (설계 의도대로). errno=65/51 분기는 iPhone의 connectivity_plus가 즉각 발화해 우회됨 — 별도 조건(다른 AP 이동) 필요. 상세: `docs/HISTORY.md` 2026-04-24 (24)

### 다음 세션 재개 포인트 (우선순위 제안)
1. **Peer count 불일치 버그** — WiFi off/on 중 재접속 반복으로 호스트 측 peer leave 처리 누적 추정. `P2PService._peers` 카운팅/제거 경로 조사 필요. 2026-04-24 (23) 실측 중 관찰.
2. **errno=65/51 분기 캡처 (v0.0.28 백업 경로)** — iPhone의 connectivity_plus가 즉시 반응해 우회됨. 다른 AP 이동 or 호스트가 네트워크 변경 시나리오에서만 캡처 가능할 것. 코드 변경 0, 실기기 2대 + 2개 AP 필요.
2. **레이턴시 자동 보정 정밀도 개선** — 엔진 측정값 10ms 오차 줄이기, S22/iPhone 버퍼 비대칭(17ms) 자동 보정 알고리즘 탐색. (**수동 슬라이더는 사용자 명시 요청 전까지 보류**)
3. **디버그 모드 호스트 간헐적 스터터** — 릴리스에선 무관, 우선순위 낮음
4. **PLAN Phase 3 (Firebase 인증·결제)** — 수익화 단계 진입
5. **UI 폴리싱** — Phase 4 확장 전 MVP 마감 위한 다듬기

상세: `docs/HISTORY.md` (최근 섹션 #14~#17), `docs/LIFECYCLE.md`, `docs/PLAN.md`

## 작업 시작 전
- 설계/결정/이력/계획: **docs/** 아래 4개 문서 확인
  - 아키텍처·로직: `docs/ARCHITECTURE.md` (v3 메인, v2는 Appendix)
  - 설계 결정: `docs/DECISIONS.md`
  - 작업 이력: `docs/HISTORY.md`
  - 구현 계획·PoC 플랜: `docs/PLAN.md`
  - 라이프사이클·용어: `docs/LIFECYCLE.md`

## 작업 완료 후
- 작업 내용은 `docs/` 아래 해당 문서에 즉시 반영
  - 일자별 작업·버그·PoC 로그 → `HISTORY.md` (날짜 오름차순, 새 항목은 "알려진 이슈" 바로 위에 추가)
  - 설계/로직 변경 → `ARCHITECTURE.md`
  - 새 설계 결정 → `DECISIONS.md` (표에 한 줄 추가)
  - 계획/일정/기획 변경 → `PLAN.md`
- 기존 4개 분류에 안 맞는 새 유형의 정보면 `docs/` 아래 새 문서 작성 + 본 CLAUDE.md "작업 시작 전" 섹션에 링크 추가해서 관리

## 기능 수정 후
pubspec.yaml version patch bump (예: 0.0.4+1 → 0.0.5+1). lint/포맷 제외.
poc/ 하위 프로젝트는 version bump 예외 (측정/실험용).

## 사용자 프로필
- Spring 백엔드 경험자, Flutter 처음
- IDE: IntelliJ
- 간결한 한국어 소통 선호 ("ㄱㄱ", "응 실행해" 등 짧게 표현)

## 협업 원칙

### 근거 기반 답변 (추측 금지)

**외부 API/라이브러리/플랫폼 SDK에 대한 답변**
- "제 기억으로는..." 금지
- WebSearch/context7 문서 조회로 검증 후 출처(URL) 명시
- 사용자가 다른 곳에서 들은 정보도 반드시 검증 후 동의/반박/보강

**프로젝트 내부 코드/동작에 대한 답변**
- 설명은 반드시 근거와 함께:
  - **코드 라인 번호** (`file.dart:123`)
  - **주석·커밋 메시지·git log/blame** 인용
  - **로그(logcat/flutter 콘솔)** 발췌
  - **실측 수치** (다운로드 속도, drift ms, 타이밍 등)
- 근거 없는 확신형 단정("~해서 이렇게 된다") 금지. 근거가 부족하면 **"가설"/"추측"임을 명시**.
- 설명한 가설이 사용자 관찰(실기기 동작, 로그, 재현 결과)과 어긋나면 즉시 **가설 철회 + 재탐색**. 억지로 기존 설명을 방어하지 말 것.
- 동작이 불확실한 구간은 "확정 못 함"으로 정직하게 기록. HISTORY/DECISIONS 문서에는 **관찰 사실**과 **가설**을 구분해서 적음.
- "~덕분에 해결된 걸로 보임" 같은 추정성 결론은 "재현 실패" 등 실측 기반 표현으로 대체.

### 설명 방식
- **낯선 도메인** (DSP/신호처리/제어이론): 전문 용어는 한 번에 하나씩, 짧은 비유·풀이 곁들이기. Claude가 먼저 쉬운 그림 그리고 사용자 확인.
- **익숙한 도메인**: "사용자가 자기 언어로 정리 → Claude가 검증·보강" 패턴 선호.
- 설명 길어지면 먼저 "여기까지 이해되셨나요?" 체크.

### 코드 수정 전 확인
- git log/blame으로 해당 줄의 도입 의도 확인 후 수정. "이상해 보이는" 패턴이 의도적 수정인 경우 많음.
- 특히 audio_service.dart의 syncPlay/syncSeek 순서(broadcast→seek)는 커밋 c6123b6에서 의도적으로 변경한 것. 되돌리지 말 것.
- 주석에 "대칭화", "의도적", "방지" 같은 단어가 있으면 함부로 되돌리지 말 것.

### 빌드/배포/테스트
- flutter run 백그라운드 실행 후 불필요하게 상태 계속 확인하지 말 것. 빌드 진행 중이면 간단히 알려주고 기다릴 것.
- 에뮬/기기의 앱/프로세스 재시작·종료 전 반드시 사용자 확인.
- **PoC**: 실기기 우선. 에뮬은 알고리즘 로직 verify 목적에서만 선택적 추가.

#### 실기기 빌드/설치 (CLI, Xcode 불필요)
- **Galaxy S22** (R3CT60D20XE): `flutter build apk --debug` → `flutter install --debug --device-id R3CT60D20XE`
- **iPhone 12 Pro** (00008101-00063C963C52001E): `flutter run --device-id 00008101-00063C963C52001E` (iOS는 flutter install 불가, 항상 flutter run)
- 실기기 테스트 시 에뮬레이터는 불필요 — S22(호스트) + iPhone(게스트) 조합으로 진행

### 에뮬레이터 네트워크
에뮬레이터 테스트 시 adb forward 포트포워딩 필수 (에뮬은 192.168.x.x 직접 접근 불가):
```bash
adb -s R3CT60D20XE forward tcp:41235 tcp:41235  # P2P TCP 소켓
adb -s R3CT60D20XE forward tcp:41236 tcp:41236  # HTTP 파일 서버
```
실기기(S22)가 호스트, 에뮬레이터가 게스트, `10.0.2.2`로 접속. 상세: `docs/EMULATOR_NETWORK.md`
