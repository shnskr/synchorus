# Synchorus

여러 핸드폰을 동기화된 스피커로 만드는 Flutter 앱 (P2P 기반)

## 프로젝트 구조

```
lib/
├── main.dart
├── models/
│   ├── peer.dart              # 연결된 피어 모델
│   └── room.dart              # 방 모델
├── providers/
│   └── app_providers.dart     # Riverpod providers (p2p, sync, audio, discovery)
├── screens/
│   ├── home_screen.dart       # 홈 (방 만들기 / IP 직접 입력으로 참가)
│   ├── room_screen.dart       # 방 화면 (접속자, 로그, 동기화)
│   └── player_screen.dart     # 플레이어 (파일선택, URL, 재생 컨트롤)
└── services/
    ├── p2p_service.dart       # TCP 소켓 통신 (호스트/참가자)
    ├── discovery_service.dart # UDP 브로드캐스트 (디바이스 발견)
    ├── sync_service.dart      # 시간 동기화 (ping/pong offset)
    ├── audio_service.dart     # 오디오 재생/공유/동기화
    └── audio_handler.dart     # 백그라운드 재생 (audio_service 패키지)
```

## 핵심 아키텍처

- **호스트**: TCP 서버 오픈 (포트 41235), 방 코드 생성, 오디오 소스 관리, 재생 명령 전송
- **게스트**: 호스트에 TCP 연결, 시간 동기화 후 오디오 수신, 호스트 명령에 따라 재생
- **메시지 형식**: JSON over TCP, 줄바꿈(\n) 구분, 바이트 단위 버퍼링
- **파일 전송**: HTTP 파일 서버 (shelf_static, 포트 41236) — 호스트가 임시 디렉토리에서 서빙, 게스트가 URL로 스트리밍
- **동기화**: 호스트 시간 기준 즉시 재생 + elapsed 보정 + 엔진 레이턴시 보정

## P2P 메시지 타입

| 타입 | 방향 | 용도 |
|------|------|------|
| join/welcome | 게스트↔호스트 | 입장/승인 |
| sync-ping/sync-pong | 게스트↔호스트 | 시간 동기화 |
| sync-position | 호스트→게스트 | 5초 주기 position 브로드캐스트 (drift 보정) |
| audio-url | 호스트→게스트 | URL 공유 |
| audio-request | 게스트→호스트 | 현재 오디오 요청 (늦은 입장 시) |
| play/pause/seek | 호스트→게스트 | 재생 제어 |
| state-request/state-response | 게스트↔호스트 | 현재 재생 상태 동기화 |
| peer-joined/peer-left | 호스트→게스트 | 참가자 입퇴장 알림 |

## 테스트 환경

- 에뮬레이터 (Pixel 6, API 34) + Galaxy S22 (SM-S901N)
- 에뮬레이터는 UDP 브로드캐스트 불가 → IP 직접 입력으로 참가
- `flutter run -d emulator-5554` / `flutter run -d R3CT60D20XE`

## 현재 상태

- Phase 1 핵심 기능 구현 완료
- 실기기 테스트 및 버그 수정 진행 중
- 상세 진행 상황은 PLAN.md 참조

## v3 폐루프 리아키텍처 (설계 단계)

새로운 동기화 설계 작업 진행 중. **현재 코드(v2: just_audio + 개방 루프)는 그대로 동작.** v3는 PoC 통과 후 본 구현 시작 — 그전엔 v2 코드 유지·수정.

- **방향**: just_audio → 네이티브 엔진(Android: Oboe / iOS: AVAudioEngine), 개방 루프 → 폐루프 (실측 기반)
- **PoC 목적**: 디자인 가설(엔진 sub-ms 정밀도, 폐루프 수렴, Wi-Fi clock sync 노이즈) 측정 검증
- **자세한 내용**: PLAN.md `핵심 기술 설계 (v3) — 폐루프 리아키텍처` 섹션 (단일 참조 지점)

**작업 주의**:
- v2 코드 수정 시 기존 v2 규칙(아래 동기화 핵심 규칙) 그대로 따를 것
- v3 설계 결정을 v2 코드에 섞어 적용하지 말 것 — v2와 v3는 서로 다른 아키텍처
- v3 토론 재개 시 PLAN.md `(v3)` 섹션부터 읽고 시작 (같은 토론 반복 방지)

## 작업 전 필수 확인 (매우 중요)

**어떤 코드든 수정/리뷰하기 전에 반드시 PLAN.md와 CLAUDE.md를 먼저 읽고 시작할 것.**

- 이 프로젝트의 많은 코드는 "이상해 보이지만 의도적인" 결정이 들어있다. 특히 동기화 로직.
- "버그처럼 보이는" 패턴을 발견하면 먼저 `git log -p -- <파일>` / `git blame`으로 도입 의도부터 확인.
- 주석에 "대칭화", "의도적", "방지", "stale", "race", "경합" 같은 키워드가 있으면 그 줄을 함부로 되돌리지 말 것.
- PLAN.md `3-10. 설계 결정 기록` 섹션이 모든 비직관적 결정의 근거. 수정 전 반드시 일치 여부 확인.
- 같은 실수를 반복하면 신뢰가 깨진다. 측정 후 한 번에 정확히 고치는 것이 원칙.

## 동기화 핵심 규칙 (절대 뒤집지 말 것)

- **호스트 syncPlay/syncSeek 모두 broadcast → seek/play 순서**. 시간 찍고 메시지 먼저 보내야 호스트와 게스트가 seek 비용을 대칭으로 치름. 뒤집으면 싱크 깨짐 (commit c6123b6).
- **`_handlePlay` / `_handleStateResponse`에서 idle 시 reload 먼저**, 그 후 elapsed 재계산. reload 시간이 elapsed에 누락되면 안 됨.
- **준비 미완료 시 hostTime/positionMs는 무시**, `_hostPlaying` 플래그만 저장. 준비 완료 후 state-request로 최신 상태 받기.
- **버퍼링 복구 시 캐시 데이터 사용 금지**, 항상 state-request로 최신 상태 요청.
- 게스트의 모든 seek는 `_internalSeek()` 래퍼로. `_player.seek()` 직접 호출 금지 (buffering watch가 recovery 루프 돌게 됨).

## 주의사항

- socket.write() 대신 socket.add() + try-catch 사용 (Broken pipe 방지)
- socket.close() 대신 socket.destroy() 사용 (TCP 핸드셰이크 대기 방지)
- 빠른 재생/정지 반복 시 `_commandSeq` 패턴으로 stale async 무효화
- 호스트 백그라운드 시 대량 데이터 전송 금지 (게스트가 audio-request로 직접 요청)
- setState 호출 전 mounted 체크 필수
- syncWithHost() 동시 호출 방지: `_activeSyncSub` 로컬 변수 패턴 사용
- 파일명은 `_safeFileName()`으로 ASCII-safe 해시화 후 디스크/HTTP 서빙 (iOS AVPlayer 호환). UI 표시는 `_currentFileName`(원본), 디스크 키는 `_storedSafeName`(해시) — 두 변수를 절대 합치지 말 것.
- audio-url 게스트 처리 시 URL에 `?v=timestamp` 캐시 무효화 쿼리가 붙어 있음. `Uri.decodeComponent` 전에 `?` 제거 필요.
- iOS `AVAudioSession`의 `setCategory`/`setActive`는 audio_service 플러그인이 관리. AppDelegate.swift의 MethodChannel에서 직접 호출 금지.
- 사용자가 "이전에도 같은 얘기 했다"고 하면 즉시 작업 멈추고 git log 확인부터.
- **기능적인 코드 수정 후에는 반드시 `pubspec.yaml`의 version patch 자리를 1 올릴 것** (예: `0.0.4+1` → `0.0.5+1`). 빌드/설치 전에 올리기. 단순 lint/주석/포맷 변경은 제외.
