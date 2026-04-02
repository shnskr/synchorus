# Synchorus - 구현 계획서

여러 핸드폰을 동기화된 스피커로 만드는 모바일 앱 (Flutter)

## 현재 진행 상황

### Phase 1 완료 항목
- [x] 프로젝트 생성 (Flutter, 패키지명: com.synchorus.synchorus)
- [x] GitHub 연동 (https://github.com/shnskr/synchorus.git)
- [x] 개발 환경 세팅 (Flutter SDK, Android Studio, Xcode, CocoaPods)
- [x] 패키지 구조 생성 (screens, services, models, providers, widgets)
- [x] P2P 연결 코드 작성
  - p2p_service.dart: TCP 소켓 통신 (호스트/참가자)
  - discovery_service.dart: UDP 브로드캐스트 (디바이스 발견)
  - home_screen.dart: 홈 화면 (방 만들기/참가)
  - room_screen.dart: 방 화면 (연결 상태/로그)
  - models (peer.dart, room.dart)
  - providers (app_providers.dart)
- [x] 시간 동기화 구현
  - sync_service.dart: ping/pong 방식 offset 계산 (best RTT 기준)
  - room_screen에서 참가 시 자동 동기화 수행
- [x] 오디오 재생/공유 구현
  - audio_service.dart: just_audio 기반 재생, 파일 전송(청크), URL 공유, 동기화 play/pause/seek
  - player_screen.dart: 플레이어 UI (파일 선택, URL 입력, 시크바, 볼륨)

### 실기기 테스트 및 버그 수정 (진행 중)

테스트 환경: 에뮬레이터(Pixel 6 API 34) + Galaxy S22 (SM-S901N)

#### 완료된 수정사항
- [x] Android 네트워크 권한 추가 (INTERNET, ACCESS_WIFI_STATE 등 + usesCleartextTraffic)
- [x] IP 직접 입력으로 방 참가 (에뮬레이터는 UDP 브로드캐스트 불가)
- [x] TCP 패킷 분할 문제 해결 (UTF-8 문자열 버퍼링 → 바이트 단위 버퍼링)
- [x] 포트 재사용 에러 해결 (disconnect() 후 startHost, ServerSocket shared: true)
- [x] 시스템 뒤로가기 지원 (PopScope 적용)
- [x] 다중 참가 방지 (_isJoining 플래그)
- [x] 게스트 roomCode 표시 (welcome 메시지에 roomCode 포함)
- [x] 파일 변경 시 상태 초기화 (_handleAudioMeta에서 이전 상태 클리어)
- [x] 방 나가기 시 임시 파일 삭제 (clearTempFiles)
- [x] play/pause에 positionMs 포함 (반복 재생 시 싱크 밀림 방지)
- [x] state-request/response 프로토콜 (게스트 늦은 입장 시 호스트 상태 동기화)
- [x] audio.startListening을 RoomScreen으로 이동 (PlayerScreen 열기 전에도 메시지 수신)
- [x] 5초 앞/뒤 건너뛰기 버튼
- [x] 파일 수신 중 로딩 인디케이터 (호스트/게스트 모두)
- [x] 호스트 나가기 확인 팝업 ("모든 참가자의 연결이 끊어집니다")
- [x] 호스트 연결 끊김 시 게스트 자동 퇴장 (onDisconnected 스트림)
- [x] socket.close() → socket.destroy() (TCP 종료 핸드셰이크 대기 제거)
- [x] _sendTo에 try-catch + socket.add() (소켓 에러 시 크래시 방지)
- [x] socket.done.catchError 추가 (Broken pipe unhandled exception 방지)
- [x] Navigator.popUntil(route.isFirst) (PlayerScreen 위에서도 홈까지 복귀)
- [x] 구독 먼저 취소 후 disconnect (cleanup 중 setState 콜백 방지)
- [x] mounted 체크 (_addLog, _startSync에서 dispose 후 setState 방지)
- [x] 파일 캐시 + 새 피어 입장 시 오디오 자동 전송 (sendCurrentAudioToPeer)
- [x] 세대 카운터 (_sendGeneration) - 파일 전송 충돌 시 이전 전송 자동 취소
- [x] audio-request 방식으로 변경 - 게스트가 sync 완료 후 직접 오디오 요청 (호스트 백그라운드 문제 해결)
- [x] 호스트 IP 표시 및 복사 기능 (RoomScreen 카드에 IP 표시 + 복사 버튼)
- [x] WiFi 연결 체크 (connectivity_plus) - 방 만들기/참가/검색 시 WiFi 미연결 차단
- [x] WiFi 끊김 감지 시 자동 퇴장 (onConnectivityChanged)
- [x] TCP 연결 타임아웃 5초 추가 (Socket.connect timeout)
- [x] 참가 시 로딩 표시 (IP 입력, 방 목록 모두)
- [x] 연결 실패 시 "같은 WiFi 확인" 안내 메시지
- [x] permission_handler 패키지 및 불필요 권한 제거 (위치 권한 불필요)
- [x] WiFi 재연결 후 방 생성 시 stale 이벤트 방지 (1초 대기 + checkConnectivity 재확인)
- [x] Heartbeat 메커니즘 추가 (3초 간격 ping/ack, 9초 타임아웃으로 죽은 피어 감지)
- [x] 피어 퇴장 시 접속자 수 즉시 반영 (_peerNames → _peerMap으로 변경)
- [x] 중복 퇴장 이벤트 방지 (heartbeat 제거 후 socket.done 중복 발화 차단)
- [x] 게스트 접속자 수 표시 (welcome peerCount + peer-joined/peer-left 추적)
- [x] 재생 시 재동기화 (게스트가 play 수신 시 3회 빠른 re-sync)
- [x] 지연 초과 시 position 보정 (delayMs <= 0이면 늦은 만큼 position 앞으로 조정)
- [x] 호스트 메시지 핸들러 가드 추가 (play/pause/seek/audio-meta 등 게스트 전용 메시지 차단)
- [x] file_picker 캐시 삭제 문제 해결 (앱 임시 디렉토리에 복사 후 플레이어 로드)
- [x] 음소거 버튼 추가 (컨트롤 영역 왼쪽, 이전 볼륨 복원)
- [x] SafeArea 적용 (하단 네비게이션 바 영역 겹침 방지)
- [x] 게스트 안내 문구 개선 ("음악 대기 중")
- [x] 방 만들기/참가 시 검색 모드 자동 중지
- [x] print → debugPrint 마이그레이션 (avoid_print 경고 해결)
- [x] 기존 lint 이슈 전체 해결 (use_build_context_synchronously, unused_import, unused_local_variable)

#### 알려진 이슈 / 다음에 확인할 것
- [ ] 호스트 파일선택 창 열고 있는 동안 게스트 입퇴장 시 안정성 (audio-request 방식으로 개선 완료, 추가 테스트 필요)
- [x] 대용량 파일 전송 중 TCP 연결 끊김 (청크 32KB, 딜레이 20ms로 조정, 20MB 테스트 통과)
- [x] 호스트가 재생 중 파일 로드 시 가끔 호스트만 재생 안 되는 현상 (원인: file_picker 캐시 삭제 → 앱 임시 디렉토리에 복사하여 해결)
- [x] 에뮬레이터 ↔ 실기기 간 네트워크 (UDP 브로드캐스트 불가 → IP 직접 입력으로 연결 가능)

### 다음 할 일
- [ ] 위 알려진 이슈 추가 테스트 및 수정 (실기기 2대)
- [ ] 알림바/잠금화면 재생 컨트롤 (audio_service 패키지, 백그라운드 재생 자체는 동작 확인)
- [ ] 연결 끊김 시 자동 재연결

### 사용 중인 패키지
```yaml
flutter_riverpod: ^2.6.1      # 상태 관리/DI
network_info_plus: ^6.1.1     # WiFi IP 확인 (호스트 IP 표시용)
connectivity_plus: ^7.1.0     # WiFi 연결 여부 확인
just_audio: ^0.9.43           # 오디오 재생
file_picker: ^8.1.7           # 파일 선택
path_provider: ^2.1.5         # 임시 파일 저장 경로
```

### 추가 예정 패키지 (백그라운드 재생 구현 시)
```yaml
audio_service: ^0.18.x        # 백그라운드 재생 + 잠금화면 컨트롤
```

## 핵심 요구사항

1. 각각의 핸드폰이 모두 스피커가 되어 같은 오디오를 재생
2. 동시 재생이므로 싱크가 맞게끔 재생
3. 음원 파일 선택 또는 URL로 재생 가능

## 아키텍처: 하이브리드 (P2P + 클라우드)

### 설계 원칙

- **오디오 싱크/전송은 P2P** → 같은 WiFi 내 직접 연결, 지연 최소화, 서버 트래픽 비용 0
- **인증/결제/분석은 클라우드 서버** → 수익화, 사용자 관리, 제품 개선

### 전체 구조

```
┌─────────────────────────────────────────────────┐
│                 클라우드 서버                      │
│          (인증 / 결제 검증 / 분석)                  │
│       Firebase Auth + Cloud Functions (TS)        │
└──────────┬──────────────────┬────────────────────┘
           │ 로그인/결제       │ 사용 통계
           │                  │
    ┌──────▼──────┐    ┌──────▼──────┐
    │  호스트 폰   │    │  참가자 폰   │
    │ TCP 서버 오픈 │◄───│ TCP 연결     │
    │             │───►│             │
    └─────────────┘    └─────────────┘
         같은 WiFi 내 P2P 직접 연결
      (디바이스 발견 / 오디오 전송 / 싱크)
```

### 왜 하이브리드인가

| 역할 | P2P (로컬) | 클라우드 서버 |
|------|-----------|-------------|
| 오디오 데이터 전송 | ✅ | ❌ (트래픽 비용 큼) |
| 재생 싱크 명령 | ✅ | ❌ (지연 발생) |
| 시간 동기화 | ✅ (호스트 기준) | ❌ |
| 사용자 인증 | ❌ | ✅ |
| 결제/구독 검증 | ❌ (크랙 취약) | ✅ (서버에서 영수증 검증) |
| 사용 통계/분석 | ❌ | ✅ |
| 원격 기능 (향후) | ❌ | ✅ |

## 기술 스택

| 구성 | 기술 | 이유 |
|------|------|------|
| 앱 | Flutter (Dart) | iOS/Android 하나의 코드베이스, 네이티브 성능 |
| P2P 통신 | `dart:io` (TCP/UDP 소켓) | 외부 의존 없이 로컬 네트워크 직접 통신 |
| 디바이스 발견 | UDP 브로드캐스트 | 같은 WiFi 내 호스트 자동 감지 |
| 오디오 재생 | `just_audio` | 정밀한 position 제어, 버퍼링 관리, 백그라운드 재생 |
| 오디오 서비스 | `audio_service` | 백그라운드 재생 + 잠금화면 컨트롤 |
| 파일 선택 | `file_picker` | 로컬 음원 파일 선택 |
| 상태 관리 | `riverpod` | 간결하고 테스트 가능한 상태 관리 |
| 클라우드 (인증/결제) | Firebase Auth + Cloud Functions (TypeScript) | 빠른 구축, 확장 가능, Flutter 공식 연동 |
| 분석 | Firebase Analytics | 사용 패턴 수집 |

## 프로젝트 구조

```
sync-speaker/
├── cloud/                          # Firebase Cloud Functions (TypeScript)
│   └── functions/
│       ├── src/
│       │   └── index.ts            # 결제 영수증 검증 등
│       ├── package.json
│       └── tsconfig.json
│
└── app/                            # Flutter 프로젝트
    └── lib/
        ├── main.dart               # 앱 진입점
        ├── screens/
        │   ├── home_screen.dart         # 방 생성/참가 화면
        │   ├── player_screen.dart       # 오디오 재생 + 컨트롤 화면
        │   └── settings_screen.dart     # 설정 화면
        ├── services/
        │   ├── p2p_service.dart         # TCP/UDP 소켓 P2P 통신
        │   ├── discovery_service.dart   # UDP 브로드캐스트 디바이스 발견
        │   ├── sync_service.dart        # 시간 동기화 로직
        │   ├── audio_service.dart       # 오디오 재생 제어
        │   └── auth_service.dart        # Firebase 인증
        ├── models/
        │   ├── room.dart                # Room 모델
        │   └── peer.dart                # 연결된 Peer 모델
        └── providers/
            └── app_providers.dart       # Riverpod providers
```

## 핵심 메커니즘

### 1. 디바이스 발견 (같은 WiFi)

```
호스트 폰                              참가자 폰
  │                                      │
  │── UDP 브로드캐스트 (포트 41234) ──────>│
  │   "SYNC_SPEAKER:호스트이름:TCP포트"    │
  │                                      │
  │   (또는 참가자가 방 코드 직접 입력)     │
  │<──────────── TCP 연결 요청 ───────────│
  │── 연결 승인 ─────────────────────────>│
```

- 호스트가 주기적으로 UDP 브로드캐스트 → 참가자가 자동 감지
- 대안으로 방 코드(4자리) 입력 방식도 지원

### 2. 시간 동기화 (호스트 기준)

```
참가자                     호스트
   |--- ping (t1) ----------->|
   |<-- pong (t1, hostTime) --|
   |                          |
   RTT = now - t1
   offset = hostTime - (t1 + RTT/2)
```

- 연결 시 ping을 여러 번(5~10회) 보내서 호스트와의 시간 차이(offset) 계산
- RTT가 가장 작은 샘플을 기준으로 offset 확정 (가장 정확한 측정값)
- 호스트가 "hostTime X에 재생해라" 명령 → 각 디바이스가 offset 보정해서 동시 재생

### 3. 오디오 공유 방식

- **파일 공유**: 호스트가 파일 선택 → TCP 소켓으로 참가자에게 직접 전송
- **URL 재생**: 호스트가 URL 입력 → URL 문자열만 전달 → 각 디바이스가 직접 스트리밍

### 4. 동기화된 재생 (Dart 의사코드)

```dart
// 호스트가 보내는 명령
final command = {
  'action': 'play',
  'startAt': DateTime.now().millisecondsSinceEpoch + 2000, // 2초 후
};
broadcastToAllPeers(command);

// 각 참가자
final startAt = command['startAt'];
final localPlayTime = startAt + myOffset;  // 호스트 시간 → 로컬 시간 변환
final delay = localPlayTime - DateTime.now().millisecondsSinceEpoch;

Future.delayed(Duration(milliseconds: delay), () {
  audioPlayer.play();
});
```

- 2초 여유를 두어 모든 디바이스가 버퍼링 완료 후 동시 시작
- `just_audio`의 `seek()` + `play()`로 정밀 제어

## P2P 프로토콜 정의

### 메시지 포맷 (JSON over TCP)

```json
{
  "type": "이벤트명",
  "data": { ... },
  "timestamp": 1234567890
}
```

### 이벤트 목록

| 이벤트 | 방향 | 데이터 | 설명 |
|--------|------|--------|------|
| `join` | 참가→호스트 | `{ name }` | 방 입장 |
| `welcome` | 호스트→참가 | `{ peerId, peerList }` | 입장 승인 + 참가자 목록 |
| `peer-joined` | 호스트→전체 | `{ peerId, name }` | 새 참가자 알림 |
| `peer-left` | 호스트→전체 | `{ peerId }` | 참가자 퇴장 알림 |
| `sync-ping` | 참가→호스트 | `{ t1 }` | 시간 동기화 ping |
| `sync-pong` | 호스트→참가 | `{ t1, hostTime }` | 시간 동기화 pong |
| `audio-meta` | 호스트→전체 | `{ fileName, fileSize, duration }` | 오디오 파일 정보 (전송 시작 전) |
| `audio-transfer` | 호스트→전체 | 바이너리 데이터 | 오디오 파일 청크 전송 |
| `audio-url` | 호스트→전체 | `{ url }` | 외부 오디오 URL |
| `play` | 호스트→전체 | `{ startAt }` | 동기화 재생 |
| `pause` | 호스트→전체 | `{ pauseAt }` | 동기화 일시정지 |
| `seek` | 호스트→전체 | `{ position, startAt }` | 동기화 탐색 |
| `volume` | 로컬 전용 | - | 각 디바이스 개별 볼륨 (전송 불필요) |

## 주요 Flutter 패키지

```yaml
dependencies:
  flutter:
    sdk: flutter
  just_audio: ^0.9.x              # 오디오 재생
  audio_service: ^0.18.x          # 백그라운드 재생
  file_picker: ^8.x               # 파일 선택
  flutter_riverpod: ^2.x          # 상태 관리
  firebase_core: ^3.x             # Firebase 코어
  firebase_auth: ^5.x             # 인증
  firebase_analytics: ^11.x       # 분석
  network_info_plus: ^6.x         # WiFi IP 주소 확인
  permission_handler: ^11.x       # 권한 관리
```

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

## 수익화 전략

### 프리미엄 모델 (추천)

| 기능 | 무료 | 프리미엄 |
|------|------|---------|
| 동시 연결 디바이스 | 2대 | 무제한 |
| 재생 시간 | 30분/세션 | 무제한 |
| 오디오 품질 | 표준 | 고음질 (무손실) |
| 이퀄라이저 | ❌ | ✅ |
| 스테레오 분리 | ❌ | ✅ |
| 광고 | 배너 | 없음 |

### 결제 검증 흐름

```
앱 → 앱스토어/플레이스토어 결제 → 영수증 → Cloud Functions에서 검증 → 프리미엄 활성화
```

## 고려사항 / 한계

- **네트워크**: 같은 WiFi 필수 (P2P 특성), AP 격리 설정 시 동작 불가
- **iOS 백그라운드**: `audio_service` 설정 + Info.plist에 background mode 추가 필요
- **Android 백그라운드**: foreground service 알림 필요
- **오디오 포맷**: mp3, m4a, wav, ogg, flac 등 `just_audio` 지원 포맷
- **파일 전송 크기**: 대용량 파일은 청크 단위 전송 + 진행률 표시
- **방화벽/AP 격리**: 일부 공용 WiFi에서는 P2P 차단될 수 있음
- **로컬 네트워크 권한**: iOS 14+에서 로컬 네트워크 접근 권한 팝업 필요

## 출시 전략

Flutter 앱만으로 핵심 기능이 전부 동작 (서버 불필요) → 무료 앱 먼저 출시 → 유저 반응 확인 → Firebase 붙여서 수익화

```
Phase 1~2: Flutter 앱만 개발 → 무료 출시 (서버 비용 0원)
Phase 3:   유저 반응 좋으면 → Firebase 연동해서 프리미엄 모델 도입
Phase 4:   확장 기능 추가
```

## 구현 순서 (MVP → 확장)

### Phase 1: MVP (Flutter 앱만, 서버 없음) → 출시 가능
- [ ] P2P 연결 (TCP 소켓 + UDP 디바이스 발견)
- [ ] 시간 동기화
- [ ] 오디오 파일 공유 + 동기화 재생/일시정지
- [ ] 기본 UI (홈 + 플레이어)

### Phase 2: 안정화 (Flutter 앱만, 서버 없음) → 업데이트
- [ ] 백그라운드 재생
- [ ] seek 동기화
- [ ] 연결 끊김 시 자동 재연결
- [ ] 에러 처리 + UX 개선

### Phase 3: 수익화 (Firebase 연동 시작)
- [ ] Firebase 인증 + 결제 연동
- [ ] 프리미엄 기능 게이팅
- [ ] Firebase Analytics 연동

### Phase 4: 확장
- [ ] 볼륨 개별 제어 (디바이스별)
- [ ] 스테레오 분리 (L/R 채널 할당)
- [ ] 재생 목록 (Playlist)
- [ ] QR 코드로 방 참가
- [ ] 이퀄라이저
- [ ] 원격 싱크 (클라우드 서버 경유, 다른 장소 지원)
