# Synchorus

여러 핸드폰을 동기화된 스피커로 만드는 Flutter 앱 (P2P).

## 현재 단계
v3 본 구현 진행 중 (step 1-1~1-4 완료, 다음 step 2 멀티 게스트).
v2 AudioSyncService 삭제됨 — NativeAudioSyncService로 교체.
audio_handler.dart: NativeAudioHandler (audio_service + 네이티브 엔진 연동 완료).

## 작업 시작 전
- 설계/결정/이력/계획: **docs/** 아래 4개 문서 확인
  - 아키텍처·로직: `docs/ARCHITECTURE.md` (v3 메인, v2는 Appendix)
  - 설계 결정: `docs/DECISIONS.md`
  - 작업 이력: `docs/HISTORY.md`
  - 구현 계획·PoC 플랜: `docs/PLAN.md`

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

### 검증 후 답변 (추측 금지)
- 외부 API/라이브러리/플랫폼 SDK 관련 답변 시 "제 기억으로는..." 금지
- WebSearch/문서 조회로 검증 후 출처(URL) 명시
- 사용자가 다른 곳에서 들은 정보도 반드시 검증 후 동의/반박/보강

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
- **본체 앱**: APK 설치 시 Galaxy S22 (R3CT60D20XE) + 에뮬레이터 (emulator-5554) 항상 둘 다 설치.
- **PoC**: 실기기 우선. 에뮬은 알고리즘 로직 verify 목적에서만 선택적 추가.

### 에뮬레이터 네트워크
에뮬레이터 테스트 시 adb forward 포트포워딩 필수 (에뮬은 192.168.x.x 직접 접근 불가):
```bash
adb -s R3CT60D20XE forward tcp:41235 tcp:41235  # P2P TCP 소켓
adb -s R3CT60D20XE forward tcp:41236 tcp:41236  # HTTP 파일 서버
```
실기기(S22)가 호스트, 에뮬레이터가 게스트, `10.0.2.2`로 접속. 상세: `docs/EMULATOR_NETWORK.md`
