# Synchorus

여러 핸드폰을 동기화된 스피커로 만드는 Flutter 앱 (P2P).

현재 main 버전 / 최근 작업 / 다음 세션 후보는 코드와 docs 참고:
- 버전: `pubspec.yaml`
- 일자별 작업 로그·미해결 이슈: [docs/HISTORY.md](docs/HISTORY.md)
- 다음 세션 작업 후보 (우선순위): [docs/PLAN.md](docs/PLAN.md) "다음 세션 작업 후보"
- 알고리즘 v2 디자인: [docs/SYNC_ALGORITHM_V2.md](docs/SYNC_ALGORITHM_V2.md) — 코드 작성 전 결정 사항 합의 필수

## 작업 시작 전
설계/결정/이력/계획·라이프사이클은 `docs/` 5개 문서:
- 아키텍처·로직: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (v3 메인, v2는 Appendix)
- 설계 결정: [docs/DECISIONS.md](docs/DECISIONS.md)
- 작업 이력 + 미해결 이슈: [docs/HISTORY.md](docs/HISTORY.md)
- 구현 계획·PoC 플랜·다음 세션 후보: [docs/PLAN.md](docs/PLAN.md)
- 라이프사이클·용어: [docs/LIFECYCLE.md](docs/LIFECYCLE.md)
- 알고리즘 v2 디자인 (작업 시): [docs/SYNC_ALGORITHM_V2.md](docs/SYNC_ALGORITHM_V2.md)
- PoC (네이티브 엔진 격리 프로젝트): [poc/README.md](poc/README.md) — 격리 사유, 본 앱과 매핑, 재실행 방법

## 작업 완료 후
- 일자별 작업·버그·PoC 로그 → `HISTORY.md` (날짜 오름차순, 새 항목은 "미해결 이슈" 바로 위에 추가)
- 설계/로직 변경 → `ARCHITECTURE.md`
- 새 설계 결정 → `DECISIONS.md` (표에 한 줄 추가)
- 계획/일정/기획 변경, 다음 세션 후보 갱신 → `PLAN.md`
- 알고리즘 v2 결정 사항 채워짐 → `SYNC_ALGORITHM_V2.md`
- 위 5개에 안 맞는 새 유형 정보면 `docs/` 아래 새 문서 작성 + 본 CLAUDE.md "작업 시작 전" 섹션에 링크 추가

세션 끝낼 때 CLAUDE.md엔 진행 상태/할일 직접 적지 말고 위 docs 중 적절한 곳에 적는다 — CLAUDE.md는 stable manual에 머문다.

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
- 1:N 멀티 게스트 전제 — 같은 이름 peer가 여럿 있을 수 있음. p2p 로직 수정 시 1:1 가정 금지 (v0.0.32 → v0.0.54 fix 사례 참고).

### 크로스 플랫폼 (Android + iOS) 항상 고려
무언가 구현·수정할 때 **두 플랫폼 모두** 검토해서 진행. 한쪽만 생각하면 상대 플랫폼에서 조용히 동작 안 함.
- **POSIX errno 값 차이**: Linux(Android)와 Darwin(iOS/macOS)은 같은 의미의 errno 번호가 다름.
  - `ECONNREFUSED`: Linux=111, Darwin=61
  - `EHOSTUNREACH`: Linux=113, Darwin=65
  - `ENETUNREACH`: Linux=101, Darwin=51
  - 실제 사고: v0.0.27에서 Linux `errno=111`만 하드코딩해 iOS에서 fast-giveup 작동 안 함 → v0.0.30에서 집합 `{111,61}` / `{113,101,65,51}`로 수정.
  - 플랫폼 errno 집합 정의는 `room_lifecycle_coordinator.dart`의 `_refusedErrnos` / `_networkUnreachableErrnos` 참고.
- **라이프사이클 이벤트 도달성**: detached는 Android foreground service에선 도달 가능, iOS 강제 종료는 미도달 가능. 이런 비대칭은 `docs/LIFECYCLE.md` 매트릭스에 반영.
- **네이티브 채널**: 새 MethodChannel 추가 시 Android(Kotlin) + iOS(Swift) **양쪽 구현** 필수. 한쪽만 하면 반대 플랫폼에서 PlatformException 또는 silent fail.
- **권한·capability**: Info.plist(iOS)와 AndroidManifest.xml 둘 다 확인. 예: 마이크, 로컬 네트워크, 백그라운드 오디오.
- **connectivity / 네트워크 스택**: iOS 제어센터 WiFi 토글은 "일시 비활성화"라 `connectivity_plus`가 `none` 이벤트 안 줄 수 있음. 진짜 off 테스트는 비행기 모드 또는 설정 앱 Wi-Fi 토글로.
- **플랫폼 분기 표기**: `Platform.isIOS` / `Platform.isAndroid` 분기 작성 시 각 분기 아래에 **왜 분기했는지 주석**. 안 그러면 나중에 사유를 알 수 없어 되돌릴 위험.

### 빌드/배포/테스트
- flutter run 백그라운드 실행 후 불필요하게 상태 계속 확인하지 말 것. 빌드 진행 중이면 간단히 알려주고 기다릴 것.
- 에뮬/기기의 앱/프로세스 재시작·종료 전 반드시 사용자 확인.
- **PoC**: 실기기 우선. 에뮬은 알고리즘 로직 verify 목적에서만 선택적 추가.

#### 실기기 빌드/설치 (CLI, Xcode 불필요)
- **Galaxy S22** (R3CT60D20XE): `flutter build apk --debug` → `flutter install --debug --device-id R3CT60D20XE`
- **Galaxy Tab A7 Lite** (R9PW315GL0L): `flutter install --debug --device-id R9PW315GL0L`
- **iPhone 12 Pro** (00008101-00063C963C52001E): **CLI `flutter run` 비권장** — iOS 26.4.1 + macOS 26.3 환경에서 `Installing and launching...` 단계 1~8분 hung 재현 (HISTORY (43)/(82)/(84) MID-14). **IntelliJ Run** 또는 **Xcode IDE Run** 권장. CLI 시도 후 hung으로 종료하면 잔재 프로세스가 다음 빌드와 충돌하므로 정리 필요:
  ```bash
  ps aux | grep -iE "flutter|xcodebuild|devicectl|frontend_server|iproxy" | grep -v grep
  # 오래된 PID들 (이전 hung 종료 후 살아남은 자식 프로세스) kill
  ```

#### iOS debug 빌드 디버거 attach 필요
iOS debug 빌드는 Dart VM JIT 의존이라 디버거 끊으면 interpreter mode fallback → 동작 멈춤. 회귀 테스트 동안엔 IntelliJ/Xcode Run 창 띄워둔 채로 진행. 디버거 없이 길게 쓰려면 `flutter run --profile` (AOT 컴파일, hot reload 안 됨) 또는 release 빌드. Android debug는 무관.

### 에뮬레이터 네트워크
에뮬레이터 테스트 시 adb forward 포트포워딩 필수 (에뮬은 192.168.x.x 직접 접근 불가):
```bash
adb -s R3CT60D20XE forward tcp:41235 tcp:41235  # P2P TCP 소켓
adb -s R3CT60D20XE forward tcp:41236 tcp:41236  # HTTP 파일 서버
```
실기기(S22)가 호스트, 에뮬레이터가 게스트, `10.0.2.2`로 접속. 상세: `docs/EMULATOR_NETWORK.md`
