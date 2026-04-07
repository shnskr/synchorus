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

## 주의사항

- socket.write() 대신 socket.add() + try-catch 사용 (Broken pipe 방지)
- socket.close() 대신 socket.destroy() 사용 (TCP 핸드셰이크 대기 방지)
- 빠른 재생/정지 반복 시 _commandSeq 패턴으로 stale async 무효화
- 호스트 백그라운드 시 대량 데이터 전송 금지 (게스트가 audio-request로 직접 요청)
- setState 호출 전 mounted 체크 필수
- syncWithHost() 동시 호출 방지: _activeSyncSub 로컬 변수 패턴 사용
