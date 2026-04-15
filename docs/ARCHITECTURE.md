# Synchorus 아키텍처

v3 폐루프 리아키텍처 기준 설계/로직. v2는 Appendix (legacy, 동작 유지).

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
| 오디오 데이터 전송 | O | X (트래픽 비용 큼) |
| 재생 싱크 명령 | O | X (지연 발생) |
| 시간 동기화 | O (호스트 기준) | X |
| 사용자 인증 | X | O |
| 결제/구독 검증 | X (크랙 취약) | O (서버에서 영수증 검증) |
| 사용 통계/분석 | X | O |
| 원격 기능 (향후) | X | O |


## 기술 스택

| 구성 | 기술 | 이유 |
|------|------|------|
| 앱 | Flutter (Dart) | iOS/Android 하나의 코드베이스, 네이티브 성능 |
| P2P 통신 (현재) | `dart:io` (TCP/UDP 소켓) | 외부 의존 없이 로컬 네트워크 직접 통신 |
| P2P 통신 (향후) | WebRTC | 원격 P2P 지원, NAT traversal |
| 디바이스 발견 | UDP 브로드캐스트 | 같은 WiFi 내 호스트 자동 감지 |
| 오디오 재생 (v2) | `just_audio` | 정밀한 position 제어, 버퍼링 관리, 백그라운드 재생 |
| 오디오 재생 (v3) | Android: Oboe (C++), iOS: AVAudioEngine (Swift) | sub-ms 타임스탬프 + 네이티브 PCM 제어 |
| 오디오 서비스 | `audio_service` | 백그라운드 재생 + 잠금화면 컨트롤 |
| 파일 공유 | 로컬 HTTP 서버 | Base64 전송 대체, 스트리밍 재생 가능 |
| 파일 선택 | `file_picker` | 로컬 음원 파일 선택 |
| 상태 관리 | `riverpod` | 간결하고 테스트 가능한 상태 관리 |
| 클라우드 (인증/결제) | Firebase Auth + Cloud Functions (TypeScript) | 빠른 구축, 확장 가능, Flutter 공식 연동 |
| 분석 | Firebase Analytics | 사용 패턴 수집 |


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
| `join` | 참가->호스트 | `{ name }` | 방 입장 |
| `welcome` | 호스트->참가 | `{ peerId, peerList }` | 입장 승인 + 참가자 목록 |
| `peer-joined` | 호스트->전체 | `{ peerId, name }` | 새 참가자 알림 |
| `peer-left` | 호스트->전체 | `{ peerId }` | 참가자 퇴장 알림 |
| `sync-ping` | 참가->호스트 | `{ t1 }` | 시간 동기화 ping |
| `sync-pong` | 호스트->참가 | `{ t1, hostTime }` | 시간 동기화 pong |
| `audio-url` | 호스트->전체 | `{ url, playing }` | 오디오 URL 공유 + 현재 재생 상태 |
| `play` | 호스트->전체 | `{ hostTime, positionMs, engineLatencyMs }` | 재생 (호스트 시간 + position + 엔진 레이턴시) |
| `pause` | 호스트->전체 | `{ positionMs }` | 일시정지 |
| `seek` | 호스트->전체 | `{ hostTime, positionMs, engineLatencyMs }` | 탐색 |
| `sync-position` | 호스트->전체 | `{ hostTime, positionMs, engineLatencyMs }` | 재생 중 position 동기화 (5초마다) |
| `state-request` | 참가->호스트 | `{}` | 게스트가 준비 완료 후 호스트의 최신 상태 요청 |
| `state-response` | 호스트->참가 | `{ hostTime, positionMs, playing, engineLatencyMs }` | 호스트의 현재 재생 상태 응답 |
| `volume` | 로컬 전용 | - | 각 디바이스 개별 볼륨 (전송 불필요) |

### 제거된 이벤트 (v2에서 불필요)

| 이벤트 | 제거 이유 |
|--------|----------|
| `audio-meta` | HTTP 서버 방식으로 전환, 파일 메타 전송 불필요 |
| `audio-transfer` | HTTP 서버 방식으로 전환, 청크 전송 불필요 |
| `audio-request` | ~~HTTP URL 공유로 대체~~ → 다시 활용 (게스트 동기화 완료 후 현재 오디오 요청, 에러 복구 시 재요청) |
| `state-request/response` | ~~play 메시지의 hostTime+position으로 통합~~ → 다시 활용 (게스트 준비 완료 후 최신 상태 요청, pendingPlay 대체) |

## 핵심 기술 설계 (v3) — 폐루프 리아키텍처 (설계 단계, 코드 미반영)

> **상태**: PoC 완료 (Android + iOS), 본체 앱 통합 진행 중. step 1-1 완료 (네이티브 엔진 이식, 비프 재생). 현재 코드(v2)는 그대로 유지되며 v3 완성 시 교체. 이 섹션은 PoC와 본 구현의 단일 참조 지점이다 — 같은 토론을 반복하지 않기 위함.

### 배경: 왜 v3로 가는가

v2는 **개방 루프 (open-loop) 보정**:
1. 호스트가 "지금 X 위치에서 재생"을 알림
2. 게스트가 elapsed + engineLatency를 **계산**해서 보정 위치 산출
3. 그 위치로 seek + play

문제:
- **engineLatency 측정 한계**: Android `AudioManager.getProperty(OUTPUT_LATENCY)`가 S22에서 null, buffer duration만 잡혀 4ms 보고. iOS `AVAudioSession.outputLatency`는 실측과 차이 큼 (특히 Bluetooth)
- **계산 vs 실제 불일치**: 디코더 지연, GC, 스레드 스케줄링 등 측정 불가능한 변수 다수
- **결과**: v0.0.4 측정 시 17ms 잔여 비대칭. 일부 디바이스에서 더 큼. 드리프트 누적 위험.

v3는 **폐루프 (closed-loop) 보정**:
1. 게스트가 **자기 엔진의 실제 출력 시점**을 측정 (`getTimestamp` / `lastRenderTime`)
2. 호스트의 동일한 측정값과 비교 → 실측 drift 계산
3. drift를 보정 (seek 또는 rate 조정)

핵심 차이: **계산이 아니라 측정**. 측정 불가능한 변수도 측정값에 자동으로 녹아 있음.

### 1. 전략 선택: D (엔진만 네이티브)

| 전략 | 범위 | 평가 |
|---|---|---|
| A. 전체 네이티브 | 화면/P2P까지 전부 네이티브 | 가장 정밀, 가장 큰 비용. 기존 자산 폐기 |
| B. iOS만 네이티브 | iOS 우선 | 앱스토어 운영 비용 부담 |
| **D. 엔진만 네이티브** | 오디오 엔진만, 나머지 Flutter 유지 | 정밀도 거의 동일, 비용 최소 |

→ **D 채택**. Android 우선 (앱스토어 운영 비용 회피), iOS는 동일 패턴 반복.

### 2. 네이티브 엔진 선택

#### 2-1. Android: Oboe
- AAudio (API 27+) 자동 활용, OpenSL ES fallback
- `AAudioStream_getTimestamp(framePosition, nanoseconds)` 로 출력된 프레임의 정확한 시각 측정
- Google 공식, 활발히 유지, MediaCodec 디코딩과 결합 가능

**S22 Wi-Fi + Oboe glitching 리스크 검증**:
- 과거 Samsung WiFi 드라이버 인터럽트 disable → DSP underflow 이슈 (S10, Oboe issue #1178), Android 11에서 수정
- S22는 Exynos 2200, Android 12+ → 동일 이슈 가능성 낮음. Oboe Samsung Quirks wiki에 S22 항목 없음
- Fallback: MMAP off → PerformanceMode 낮춤 → buffer size 증가 → Oboe quirk 등록

#### 2-2. iOS: AVAudioEngine
- `engine.lastRenderTime` 으로 sample-accurate 출력 시각 측정
- `play(at: AVAudioTime)` 로 정밀 예약 재생
- `AVAudioFile`로 mp3/aac/m4a/alac 단일 API 디코딩

**iOS 주의점**:
- Bluetooth(AirPods 등) latency 부정확: `outputLatency` 보고값과 실측이 다름 (193~260ms 변동, 1분 내 변화 가능) → 수동 보정 슬라이더 필요
- `AVAudioEngineConfigurationChange` notification 처리 필수 (인터럽션 후 노드 재연결)

#### 2-3. FLAC: 미지원 (생략)
- `AVAudioFile`가 FLAC 지원 안 함
- 일반 사용자 거의 사용 안 함 (mp3/aac/m4a/wav로 충분)
- 추후 필요 시 별도 디코더 통합 검토

### 3. audio_service 플러그인과의 공존

`audio_service` (백그라운드 재생 / 잠금화면 컨트롤) + 커스텀 네이티브 엔진을 같이 쓸 수 있는가?

- audio_service 공식 README: `final _player = AudioPlayer(); // e.g. just_audio` — 주석에서 다른 player도 명시적으로 허용
- BaseAudioHandler는 player 추상화에 무관, 네이티브 엔진을 wrap한 커스텀 핸들러 가능
- iOS `AVAudioSession`은 audio_service 플러그인이 카테고리/활성화 관리, 네이티브 엔진은 같은 세션 위에서 동작
- Android는 layer 분리: `audio_session`(AudioFocus) / `audio_service`(ForegroundService) / `Oboe`(PCM stream)

→ **공존 가능, 통합 가능**

### 4. 측정 인프라 설계

폐루프가 동작하기 위한 5개 항목.

#### 4-1. 관측 데이터: `(framePos, deviceTimeNs)` 페어

- **framePos**: 방금 물리 스피커에서 울린 샘플의 인덱스
  - Android: `AAudioStream_getTimestamp(CLOCK_MONOTONIC, &framePos, &nanos)`
  - iOS: `engine.lastRenderTime.sampleTime`
- **deviceTimeNs**: 그 프레임이 출력된 시각 (로컬 CLOCK_MONOTONIC, ns)
  - Android: `getTimestamp`의 두 번째 파라미터
  - iOS: `lastRenderTime.hostTime` → `mach_timebase_info`로 ns 환산

**왜 이 페어가 최소 단위인가**: 시간 축과 샘플 축이 둘 다 있어야 디바이스 간 "같은 프레임이 언제 울렸나"를 비교할 수 있음. 엔진 레이턴시·DAC 지연 등이 페어에 자동 내포됨 (계산 불필요).

**트랙 포지션 변환**:
```
trackPosMs = anchor.trackMs + (framePos - anchor.framePos) * 1000 / sampleRate
```
앵커는 마지막 seek/play 시점에 갱신.

**PoC에서 검증할 잔가지**: framePos 리셋 규칙(stream stop 시 등), 첫 프레임 시각의 정의, 초기 getTimestamp 실패 처리.

#### 4-2. 관측 주기

- **로컬 관측**: 50-100ms (로컬 API는 저렴)
- **P2P 교환 (정상)**: 500ms-1s
- **P2P 교환 (재생 시작 직후)**: 100-200ms (초기 수렴)

근거: 일반 수정 발진기 드리프트 ±20-50 ppm = 1분당 1.2~3ms 누적. 청각 임계 ~20ms (Haas effect 기반) 도달 전 충분히 보정 가능.

#### 4-3. 교환 프로토콜: A + Drift Report 하이브리드

**방향 결정**:
| 옵션 | 장점 | 단점 |
|---|---|---|
| A. Host Push | 단순 (Snapcast/AirPlay 2 PTP 패턴), 지연 최소 | 호스트가 게스트 상태 모름 |
| B. 양방향 | 로깅/모니터링 풍부 | 트래픽 2배, 대부분 낭비 |
| C. Guest Pull | 네트워크 효율 | RTT가 정확도 깎음 (position 같은 동적 값엔 부적합) |

→ **A 기본 + Guest Drift Report 이벤트** 채택. PoC 분석 단계에 가시성 확보 + 운영 시 부하 최소.

**참고 레퍼런스**:
- Snapcast: Server Push (audio + timestamps) + Client 독립 clock sync, <1ms 편차
- AirPlay 2: PTP (IEEE 1588), 마스터 push, 디바이스 간 sub-25ms
- NTP vs PTP: NTP=Client Pull (정적 offset 추정 OK), PTP=Master Push (동적 sync 적합)

**핵심 통찰**: clock sync (정적)에는 Pull, position observation (동적)에는 Push가 자연스럽다. 이게 우연히 Snapcast 패턴과 일치.

**메시지 타입**:
- `audio-obs` (호스트→게스트, 평상시 500ms 주기 broadcast) — 신규
- `audio-drift-report` (게스트→호스트, 드리프트 임계 초과 시에만) — 신규
- `sync-ping`/`sync-pong` 유지 (clock offset용)
- `sync-position` 폐기 (audio-obs로 대체 — sync-position은 시각 축이 없어 정확 drift 계산 불가)

**페이로드 (audio-obs)**:
```json
{
  "type": "audio-obs",
  "seq": 1234,
  "hostTimeMs": 1712567890123,
  "anchor": { "framePos": 0, "trackMs": 30000 },
  "framePos": 88200,
  "playing": true
}
```

**페이로드 (audio-drift-report)**:
```json
{
  "type": "audio-drift-report",
  "seq": 42,
  "hostTimeMs": 1712567890123,
  "observedTrackMs": 30050,
  "expectedTrackMs": 30105,
  "driftMs": -55
}
```

**계층 정리**:
```
[Layer 1] sync-ping/pong   → wall clock offset (기존, 유지)
                ↓ 제공
[Layer 2] audio-obs        → 엔진 상태 + 시각 (신규)
                ↓ 소비
[Layer 3] drift 계산 + 보정
```

**앵커 갱신 규칙**: 평상시 같은 앵커, seek/play 직후 즉시 새 앵커 broadcast (늦게 도착하는 옛 측정값과 혼동 방지).

#### 4-4. 드리프트 계산: 호스트 obs 선형 보간

호스트 최근 obs 두 개 `(T1, P1)`, `(T2, P2)`, 게스트 관측 순간 `T_g` (`T1 ≤ T_g ≤ T2`):

```
expectedP_at_Tg = P1 + (P2 - P1) * (T_g - T1) / (T2 - T1)
drift = observedP_g - expectedP_at_Tg
```

재생 속도 일정 시 P는 T에 대해 선형 → 보간이 수학적으로 정확.

**왜 "앵커 + 이론 계산"이 아니라 "실측 보간"인가**:
- 앵커 기반 `expectedP(T) = P_anchor + (T - T_anchor)`는 클락 드리프트를 못 잡음 = **개방 루프 그 자체**
- 호스트 obs는 실측값이라 그 자체에 호스트 측 모든 지연이 녹아 있음
- 게스트가 실측값을 기준선으로 자기 실측과 직접 비교 → 진짜 폐루프

#### 4-5. 보정 실행: 계층적

| drift 크기 | 방법 | 비고 |
|---|---|---|
| **< 15ms** | 무시 (dead zone) | 측정 노이즈 zone |
| **15 ~ 50ms** | rate 조정 (1.025~1.05×) | 매끄럽게 수렴 (본 구현 단계) |
| **> 50ms** | seek | rate로 따라잡기 너무 느림, 갑작스런 점프 대비 |

**노이즈 원천 분해** (왜 임계값이 ms 단위인가):

| 원천 | 크기 | 네이티브가 해결? |
|---|---|---|
| 엔진 타임스탬프 정밀도 | <1ms | ✅ |
| Wi-Fi clock 동기화 오차 | 5-10ms | ❌ (네트워크 본질) |
| 네트워크 전송 지연 | 우회 가능 (obs에 발생 시각 박아 보냄) | - |
| 재생 하드웨어 지연 | ~0 (`getTimestamp`가 빼고 돌려줌) | - |

→ **병목은 Wi-Fi clock 동기화**. 네이티브 가도 이건 안 줄어. 실제 floor는 3-10ms 범위. dead zone 15ms는 보수적 출발값.

**임계값은 PoC 실측 후 확정**: 정적 상태에서 noise floor 측정 → dead zone = floor × 2 (oscillation 방지). 15ms가 빡빡/헐거우면 조정.

**보정 후 쿨다운**: 한 번 보정 후 최소 500ms-1s 대기 (oscillation 방지).

**PoC 단계 (rate 조정 생략)**:
```
< 15ms   → 무시
≥ 15ms   → seek
```

본 구현 단계에서 rate 조정 추가 시 위 3계층 활성화.

**clock sync 개선 기법** (필요 시 PoC 측정 후 적용):
1. Kalman filter — RTT 시계열 필터링, 튀는 값 자동 배제
2. ping 주기 ↑ — 30s → 5-10s
3. 샘플 수 ↑ — 10 → 20-30
4. 이상치 제거 — RTT 분포 기반 outlier 버림

### 5. Flutter ↔ 네이티브 인터페이스

#### 5-1. 현재 구현 (step 1-2, MethodChannel 단일)

**채널명**: `com.synchorus/native_audio` (Android/iOS 동일)
**Dart 래퍼**: `lib/services/native_audio_service.dart`

**구현된 메서드**:

| 메서드 | 인자 | 반환 | 용도 |
|---|---|---|---|
| `loadFile` | `String` (파일 절대경로) | `bool` | 오디오 파일 디코딩/로드 |
| `start` | 없음 | `bool` | 엔진 시작 + 재생 (loadFile 후 호출) |
| `stop` | 없음 | `bool` | 엔진 정지 + 노드 해제 |
| `getTimestamp` | 없음 | `Map` | `{framePos, timeNs, wallAtFramePosNs, ok, virtualFrame, sampleRate, totalFrames, ...}` |
| `seekToFrame` | `int64` (숫자 직접) | `bool` | 재생 위치 점프 (파일 프레임 단위) |
| `getVirtualFrame` | 없음 | `int64` | 현재 콘텐츠 위치 조회 |

**네이티브 구현**:
- Android: NDK AMediaCodec 전체 디코딩 → int16 버퍼 → Oboe float 콜백 (`oboe_engine.cpp`)
- iOS: AVAudioPlayerNode + AVAudioFile 스트리밍 재생 (`AudioEngine.swift`)

**파일 위치**:
- Dart: `lib/services/native_audio_service.dart`
- Android: `android/app/src/main/cpp/oboe_engine.cpp` + `NativeAudio.kt` + `MainActivity.kt`
- iOS: `ios/Runner/AudioEngine.swift` + `AppDelegate.swift`

**제한**:
- Android: 전체 파일 메모리 디코딩 (150MB 제한, ~5분 곡). 향후 스트리밍 디코딩 전환 가능
- sampleRate/virtualFrame은 파일 네이티브 샘플레이트 기준

#### 5-2. 향후 확장 계획 (step 1-3+)

EventChannel 추가로 native 자발적 push 전환 검토:

| 채널 | 용도 |
|---|---|
| MethodChannel | 명령 (start/stop/seek/setRate 등 일회성 RPC) |
| EventChannel | 관측값 스트림 (지속 push) |

**왜 분리**: MethodChannel만 쓰면 Flutter가 50-100ms마다 polling 해야 함 → 폴링 자체가 노이즈 원천. 관측은 native 자발적 push가 정답.

**확장 시 추가될 API**:
- `setRate(double)` — drift 보정용 재생 속도 조절 (step 1-3 또는 step 4)

**설계 포인트**:
- **앵커는 native가 관리**, Flutter는 받기만 (play/seek 호출 시 native 갱신)
- **에러는 fatal/recoverable 구분**


### 8. v3 새 P2P 메시지 (요약)

| 타입 | 방향 | 페이로드 | 용도 |
|---|---|---|---|
| `audio-obs` | 호스트→게스트 | `seq`, `hostTimeMs`, `anchor`, `framePos`, `playing` | 호스트 엔진 실측값 broadcast (500ms 주기, 앵커 변경 시 즉시) |
| `audio-drift-report` | 게스트→호스트 | `seq`, `hostTimeMs`, `observedTrackMs`, `expectedTrackMs`, `driftMs` | 게스트가 임계 초과 drift 감지 시 보고 (이벤트성) |

기존 `sync-position`은 v3에서 폐기. `sync-ping`/`sync-pong`은 그대로 유지.

---

---

## Appendix: v2 설계 (legacy)

> v2는 legacy로 현재 앱에서 동작 유지 중. v3 완성 시 교체 예정.

### 1. 기기간 연결

**목표**: P2P 연결 (지연 최소화)

**현재 (Phase 1~2)**: 같은 WiFi + TCP/UDP 소켓 (`dart:io`)
- 디바이스 발견: UDP 브로드캐스트 (포트 41234)
- 데이터 통신: TCP 소켓 (포트 41235)
- 연결 유지: Heartbeat (3초 간격)

**확장 (Phase 4)**: WebRTC로 전환
- 같은 WiFi: ICE가 로컬 후보 선택 (현재와 동일 성능)
- 원격: STUN/TURN으로 P2P 연결
- 시그널링 서버: Firebase (Phase 3에서 연동)
- 연결 계층을 추상화하여 TCP → WebRTC 교체 시 상위 코드 변경 없음

```dart
// 연결 계층 추상화
abstract class ConnectionService {
  Future<void> connect(String peerId);
  void send(Uint8List data);
  Stream<Uint8List> get onData;
}

class TcpConnection implements ConnectionService { ... }     // Phase 1~2
class WebRtcConnection implements ConnectionService { ... }  // Phase 4
```

### 2. 오디오 소스 공유

**기존 방식 (제거 예정)**: Base64 인코딩 + 32KB 청크 + JSON 전송
- 문제: 33% 오버헤드, 제어 채널 간섭, 전체 다운로드 후 재생, 복잡한 워크어라운드

**새 방식: HTTP 서버**
- 호스트가 로컬 HTTP 서버 오픈 (같은 WiFi 내, 인터넷 불필요)
- 게스트에게 URL만 전달 → just_audio가 스트리밍 재생
- 다운로드 완료 전에도 재생 가능 (스트리밍)
- Base64 인코딩, 청크, 세대 카운터 등 전부 불필요

**오디오 소스 유형**:

| 소스 | 공유 방법 |
|------|----------|
| 로컬 파일 | 호스트가 HTTP 서버로 제공 → URL 전달 |
| 외부 URL | URL 문자열만 전달 |

→ 결국 둘 다 **"URL을 공유한다"**로 통일

### 3. 핵심 로직: 동기화 재생

여러 기기에서 같은 음악을 **동시에** 들리게 하는 것이 이 앱의 핵심.
"소프트웨어상 같은 position" ≠ "실제로 같은 타이밍에 소리가 남". 이 차이를 줄이는 게 전부.

#### 3-1. 동기화에 관여하는 모든 지연시간

호스트가 Play를 누른 순간부터 게스트 스피커에서 소리가 나기까지의 전체 경로:

```
호스트 Play 누름
  │
  ├─ [1] JSON 직렬화 + TCP 송신 버퍼      ─┐
  ├─ [2] WiFi 네트워크 전송                 ├─ 메시지 전달 구간
  ├─ [3] TCP 수신 버퍼 + JSON 역직렬화      ─┘
  │
  ├─ [4] seek 처리 (디코더 재위치, 버퍼 flush/refill)
  ├─ [5] play() → 오디오 엔진 디코딩
  ├─ [6] 오디오 출력 버퍼 (ringbuffer)      ─┐
  ├─ [7] DAC 출력 레이턴시                   ├─ engineLatency
  └─ [8] 스피커 물리적 지연 (~무시 가능)      ─┘
```

#### 3-2. 보정 현황

| 지연 요소 | 보정 방법 | 상태 |
|---|---|---|
| **시계 차이 (clock offset)** | RTT/2 기반 핑퐁 10회, best RTT 채택 | **보정됨** |
| **메시지 전달 지연 [1][2][3]** | `elapsed = nowAsHostTime - hostTime` | **보정됨** |
| **기기 간 engineLatency 차이 [6][7]** | `내 engineLatency - 호스트 engineLatency` | **보정됨** |
| **seek 비용 비대칭 [4]** | 호스트도 동일하게 seek → play 경로 (양쪽 상쇄) | **보정됨** |
| 오디오 엔진 디코딩 [5] | API로 측정 불가, 기기마다 비슷하므로 양쪽 상쇄 | 측정 불가 |
| 네트워크 비대칭 (업/다운 속도 차이) | RTT/2가 정확하지 않은 원인, 통계적으로만 줄일 수 있음 | 측정 불가 |
| 클럭 드리프트 | 30초 주기 재동기화 + 5초마다 sync-position 보정 | 간접 대응 |
| GC / 스레드 스케줄링 지터 | OS 레벨, 제어 불가 | 간접 대응 |
| 백그라운드 throttling | foreground service로 대응 | 간접 대응 |
| 블루투스 출력 레이턴시 | 수동 보정 슬라이더 (향후 추가) | 미구현 |

**핵심 원칙**: 측정 가능한 것은 계산으로 보정하고, 측정 불가능한 것은 호스트/게스트가 동일한 경로를 타게 하여 상쇄시킨다.

#### 3-3. 시계 동기화 (clock offset)

게스트가 호스트와의 시계 차이를 계산하여, 이후 모든 시간 계산의 기반이 됨.

```
게스트                          호스트
  |--- ping (t1) ------------->|
  |<-- pong (t1, hostTime) ----|

  RTT = t2 - t1
  offset = hostTime - (t1 + RTT/2)
  → guestTime + offset = hostTime
```

- **초기 계산**: 방 입장 시 핑퐁 10회, best RTT 기준으로 offset 확정
- **offset 유지**: 백그라운드에서 주기적으로 핑퐁 10회 재계산 (클럭 드리프트 보정)
- **한계**: RTT/2는 네트워크 대칭을 가정. 업/다운 속도가 다르면 오차 발생 (측정 불가)

#### 3-4. 엔진 레이턴시 측정

play() 호출 후 실제 스피커에서 소리가 나기까지의 시간. OS API로 측정.

- Android: `AudioManager.getProperty(OUTPUT_LATENCY)` + `framesPerBuffer / sampleRate`
- iOS: `AVAudioSession.outputLatency` + `ioBufferDuration`

**포함**: 오디오 출력 버퍼 + DAC 변환 대기
**미포함**: 오디오 엔진 디코딩 시간 (API 없음, 측정 불가 → 양쪽 상쇄로 대응)

#### 3-5. 호스트 동작

호스트는 시간의 기준. 계산 없이 실행하고 알려주기만 함.

**Play**: 메시지 전송 `{ hostTime, positionMs, engineLatencyMs }` → seek(현재position) → play()
**Pause**: pause() → 메시지 전송 `{ positionMs }`
**Seek**: 메시지 전송 `{ hostTime, positionMs, engineLatencyMs }` → seek(position)

> Play/Seek 모두 **broadcast 먼저, seek/play는 그 다음**. 게스트가 메시지를 받자마자 거의 동시에 seek를 시작하므로, 호스트와 게스트가 seek 비용을 대칭으로 치름. 게스트의 elapsed 계산에 자기 seek 시간이 포함되어 자연 상쇄. 이 순서를 뒤집으면 싱크가 깨진다 (commit c6123b6).
**5초마다**: sync-position 브로드캐스트 `{ hostTime, positionMs, engineLatencyMs }`
**sync-ping 수신**: sync-pong 응답
**state-request 수신**: 현재 상태 응답 `{ hostTime, positionMs, playing, engineLatencyMs }`

#### 3-6. 게스트 동작 — 상태별 케이스

모든 계산은 게스트에서 일어남. 게스트 상태에 따라 처리가 달라짐.

**게스트 상태 정의**:
```
준비 단계:
  [A] TCP 연결만 됨 (offset 미계산, 오디오 미로드)
  [B] offset 계산 완료, 오디오 미로드 또는 로드 중
  [C] 모두 준비 완료 (offset 계산 + 오디오 로드 완료)

재생 상태:
  [C-1] 준비 완료, 정지 중
  [C-2] 준비 완료, 재생 중
```

**게스트 플래그**: `_hostPlaying` — 호스트가 재생 중인지 여부
- play 수신 → `_hostPlaying = true`
- pause 수신 → `_hostPlaying = false`

---

##### 케이스 1: 준비 완료 상태에서 play 수신 [C-1 → C-2]

가장 정확한 케이스. elapsed가 네트워크 지연 수준으로 최소.

```
호스트: play 전송 (hostTime, positionMs, engineLatencyMs)
게스트: 수신
  _hostPlaying = true
  elapsed = nowAsHostTime - hostTime              ← 네트워크 지연만 (~20ms)
  latencyCompensation = 내 engineLatency - 호스트 engineLatency
  targetPosition = positionMs + elapsed + latencyCompensation
  seek(targetPosition) → play()
```

**타임라인 예시** (offset=-10ms, 네트워크 20ms, seek 15ms, 호스트 engineLatency 15ms, 게스트 10ms):
```
호스트:
  10:00:00.000  Play 누름, 메시지 전송, seek(5000ms)  15ms
  10:00:00.015  play(), engineLatency                  15ms
  10:00:00.030  소리 출력 (position ~5030ms)

게스트:
  10:00:00.020  메시지 수신, elapsed=20ms, target=5015ms
                seek(5015ms)                           15ms
  10:00:00.035  play(), engineLatency                  10ms
  10:00:00.045  소리 출력 (position ~5025ms)

결과: 5030ms vs 5025ms = ~5ms 차이 (측정 불가능한 영역)
```

##### 케이스 2: 준비 미완료 중 play 수신 [A/B → 나중에 C]

게스트가 아직 준비 중일 때 호스트가 play를 보낸 경우. **시간 값은 무시하고 상태만 기억**.

```
호스트: play 전송
게스트: 준비 안 됨
  _hostPlaying = true                   ← 상태만 저장, hostTime/positionMs 무시
  (offset 계산 중... 오디오 로드 중...)
  
  준비 완료!
  _hostPlaying == true → 호스트에게 state-request 전송
  호스트: 응답 (hostTime=지금, positionMs=지금position, playing=true, engineLatencyMs)
  게스트: elapsed = 네트워크 지연만 (~20ms) ← 오래된 값이 아니라 최신 값!
  targetPosition = positionMs + elapsed + latencyCompensation
  seek(targetPosition) → play()
```

**기존 방식과의 차이**:
```
기존: play 수신 → pendingPlay에 저장 → 준비 완료 후 오래된 hostTime으로 계산
      elapsed = 네트워크 지연 + 대기 시간 (수초~수십초) → 부정확

새 방식: play 수신 → 플래그만 저장 → 준비 완료 후 최신 상태 요청
         elapsed = 네트워크 지연만 (~20ms) → 항상 정확
```

##### 케이스 3: 준비 완료 상태에서 pause 수신 [C-2 → C-1]

```
호스트: pause 전송 (positionMs)
게스트:
  _hostPlaying = false
  pause()
  seek(positionMs)     ← 호스트와 같은 위치로 맞춤
```

##### 케이스 4: 준비 미완료 중 pause 수신 [A/B]

```
호스트: pause 전송
게스트: _hostPlaying = false     ← 상태만 저장
  준비 완료 후 _hostPlaying == false → 아무것도 안 함 (대기)
```

##### 케이스 5: 준비 완료, 재생 중 seek 수신 [C-2]

```
호스트: seek 전송 (hostTime, positionMs, engineLatencyMs)
게스트:
  재생 중이면:
    elapsed = nowAsHostTime - hostTime
    targetPosition = positionMs + elapsed + latencyCompensation
    seek(targetPosition) → play()
  정지 중이면:
    seek(positionMs)    ← 단순 위치 이동만
```

##### 케이스 6: 재생 중 sync-position 수신 [C-2]

5초마다 호스트가 보내는 위치 보정 신호.

```
호스트: sync-position (hostTime, positionMs, engineLatencyMs)
게스트:
  expectedPosition = positionMs + elapsed + latencyCompensation
  diff = expectedPosition - 내 position

  diff < 100ms  → 무시
  diff >= 100ms → seek(expectedPosition)
```

**안전장치**:
- `_syncSeeking`: sync-position 보정 seek 진행 중 다음 sync-position 무시
- `_internalSeeking`: 내부 seek로 인한 buffering 전환을 buffering watch가 무시 (recovery 루프 방지)
- `_awaitingStateResponse`: 버퍼링 복구 시 state-request 중복 방지 (응답 오면 해제)
- `_commandSeq`: 빠른 재생/정지 반복 시 stale async 무효화
- `_reloadInProgress`: 동시 재로드 차단

##### 케이스 7: 재생 중 버퍼링 발생 후 복구 [C-2]

네트워크 지연으로 HTTP 스트리밍 버퍼가 비어서 재생이 멈췄다가 복구된 경우.

```
버퍼링 발생 → 재생 멈춤
버퍼 채워짐 → ready 전환 감지
  state-request → 호스트가 최신 상태 응답 → seek(보정position)
  (_awaitingStateResponse: 응답 대기 중 중복 요청 방지)
```

##### 케이스 8: 재생 중 오디오 에러 (404 등) [C-2]

호스트 백그라운드 진입 등으로 HTTP 서버 연결이 끊긴 경우.

```
seek 중 에러 발생
  → _reloadAudio() (URL 다시 로드 시도)
  → 실패 시 호스트에게 audio-request 재요청
  → URL 수신 → 로드 → state-request → seek → play
```

##### 케이스 9: 재생 중 네트워크 끊김 → 재연결 [C-2 → A → C]

```
네트워크 끊김 감지
  → 자동 재연결 3회 시도 (1/2/3초 간격)
  → WiFi 끊김이면 15초간 복구 대기
  → 재연결 성공
  → 핑퐁 10회 재동기화
  → state-request → 최신 상태 수신 → seek → play
```

##### 케이스 10: 늦은 입장 (호스트 이미 재생 중) [A → B → C]

별도 처리 없음. 케이스 2와 동일한 흐름.

```
게스트 입장 → offset 계산 → 오디오 로드
준비 완료 → _hostPlaying == true → state-request → seek → play
```

#### 3-7. Play 신호 타임라인 — 정리

```
호스트 Play 누름
  │
  ├─ 호스트: seek(position) → play() → 메시지 전송
  │
  ├─ 게스트 (준비 완료):
  │    메시지 수신 → elapsed 계산 → seek(보정position) → play()
  │
  └─ 게스트 (준비 미완료):
       _hostPlaying = true (상태만 저장)
       ... 준비 완료 ...
       state-request → 최신 상태 수신 → seek(보정position) → play()
```

#### 3-8. 재생 중 싱크 유지 구조

```
[시계 동기화 계층]     30초마다 핑퐁 10회 → offset 갱신
        ↓
[위치 보정 계층]       5초마다 sync-position → 30ms 이상 차이 시 seek
        ↓
[버퍼링/에러 복구]     버퍼링 복구 시 state-request로 최신 상태 수신, 에러 시 재로드
```

#### 3-9. 게스트 방 입장 시 초기화 순서

```
1. TCP 연결
2. 핑퐁 10회 → clock offset 계산
3. 엔진 레이턴시 측정 (플랫폼 채널)
4. 호스트에게 audio-request → URL 수신 → 오디오 로드 (HTTP 스트리밍, 메타+초기 버퍼)
5. 준비 완료 → _hostPlaying 확인
   ├── true  → state-request → 최신 상태 수신 → seek → play
   └── false → 대기
```

