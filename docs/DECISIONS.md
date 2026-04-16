# Synchorus 설계 결정 기록 (ADR)

v2/v3 주요 설계 결정과 그 이유. 신규 결정은 상단에 누적.

## v3 설계 결정

| 결정 | 이유 |
|---|---|
| v2 AudioSyncService 교체 (병행 X) | just_audio에 깊이 결합(780줄), 병행은 P2P/HTTP/파일 로직 중복, PoC 30분 ±20ms 검증으로 fallback 불필요 |
| SyncService in-place 업그레이드 (교체 X) | clock sync는 v2에서도 별도 서비스, v3 알고리즘은 상위 호환 (EMA 추가) |
| 게스트 파일 다운로드: dart:io HttpClient | 네이티브 엔진은 로컬 파일 경로 필요, http/dio 패키지 불필요, 새 의존성 없음 |
| Android 파일 디코딩: NDK AMediaCodec 전체 메모리 디코딩 | 스트리밍보다 단순, 150MB 제한으로 ~5분 곡 커버. iOS는 AVAudioPlayerNode가 자체 스트리밍 |
| iOS 파일 재생: AVAudioPlayerNode + scheduleSegment | AVAudioSourceNode 수동 렌더링 대비 메모리/코드 최소, seek = stop→scheduleSegment→play |
| virtualFrame/sampleRate는 파일 네이티브 레이트 기준 | 양 플랫폼 동일 단위로 Dart 서비스 레이어 단일화. 시간 변환: `ms = vf * 1000 / sampleRate` |
| 본체 앱 MethodChannel명 `com.synchorus/native_audio` | PoC(`com.synchorus.poc/native_audio`)와 구분. Android/iOS 동일 채널명으로 Dart 서비스 레이어 단일화 |
| iOS MethodChannel 인자는 Dart 원시값 직접 전달 | Android Kotlin(`call.arguments as Number`)과 동일 패턴. 딕셔너리 래핑 시 silent fail 위험 (b0415-7 버그) |
| iOS 출력 지연 = outputLatency + ioBufferDuration | Apple 포럼 합의. `outputPresentationLatency`는 ioBuffer 미포함. 노드 latency도 합산하되 보통 0 |
| 네이티브 엔진(Oboe/AVAudioEngine) 도입 | just_audio + 플랫폼 채널로는 출력 시각의 sub-ms 측정 불가 |
| 전략 D (엔진만 네이티브) | 정밀도 거의 동일, 비용 최소 (UI/P2P/플러그인 재사용) |
| Android 우선 | 앱스토어 운영 비용 회피, iOS는 동일 패턴 반복 |
| Oboe 채택 (AAudio 직접 X) | AAudio + OpenSL ES fallback + Quirks 자동 처리 + Google 공식 |
| AVAudioEngine 채택 (AVAudioPlayer X) | sample-accurate 측정(`lastRenderTime`) + `play(at:)` 정밀 예약 |
| FLAC 미지원 | AVAudioFile 비지원, 일반 사용자 거의 안 씀 |
| 폐루프 (계산 → 측정) | 측정 불가능한 변수까지 자동 내포됨 |
| `(framePos, deviceTimeNs)` 페어 | 시간/샘플 양 축 모두 있어야 디바이스 간 비교 가능 |
| 호스트 Push + Guest Drift Report 이벤트 | 단순함 + 모니터링 가시성 동시 확보 (PoC 분석에 필수) |
| 선형 보간 (실측 기반) | 앵커 기반 이론 계산은 클락 드리프트 못 잡음 (개방 루프 회귀) |
| dead zone 15ms 출발값 | 측정 노이즈(5-10ms) × 2 + 청각 임계(20ms) 미만, PoC 측정 후 재조정 |
| seek 임계 50ms | 청각 임계와 정합. 갑작스런 점프 시 "긴 에코" 대신 "한 번 클릭"이 나음 |
| 보정 후 500ms-1s 쿨다운 | oscillation 방지 |
| MethodChannel + EventChannel 분리 | 명령 RPC와 관측 스트림은 본질이 다름. 단일 채널이면 polling 발생 |
| 앵커는 native 관리 | seek/play 시점에 native 내부 상태가 가장 정확 |
| sync-position 폐기, audio-obs 신규 | sync-position은 시각 축 없어 정확 drift 계산 불가 |
| sync-ping/pong 유지 | clock offset (정적)에는 Pull (NTP) 패턴이 적합 |
| PoC 격리 원칙 | 한 번에 다 만들면 원인 추적 불가, 한 변수씩 검증 |


## v2 설계 결정

| 결정 | 이유 |
|---|---|
| 속도 조절(1.05x/0.95x) 제거 | 에뮬레이터에서 setSpeed(1.05) 시 오히려 차이 증가, 실기기에서도 보장 불가 |
| seek 단일 보정 방식 | 속도 조절보다 예측 가능하고 즉시 반영됨 |
| 호스트도 seek → play | seek 소요시간을 측정하지 않고도 양쪽 상쇄로 해결 |
| 준비 미완료 시 state-request | pendingPlay의 오래된 hostTime 대신 최신 값을 받아 elapsed 최소화 |
| _hostPlaying 플래그 | 준비 미완료 중 play/pause 상태를 추적, 준비 완료 후 적절히 대응 |
| 버퍼링 복구 시 state-request | 캐시 데이터는 호스트 seek/pause 시 stale → 항상 최신 상태 요청 |
| 쿨다운 → _awaitingStateResponse | 2초 쿨다운은 정상 복구도 차단 → 응답 대기 플래그로 자연 스로틀링 |
| syncSeek도 broadcast 먼저 | syncPlay와 동일하게 시간 찍고 메시지 먼저 → seek (seek 비용 대칭화) |
| 임계값 100ms | 20→30→100ms로 단계적 상향 — seek 자체가 추가 버퍼링을 유발해서 너무 민감하면 오히려 싱크 흔들림 |
| `_internalSeek` 래퍼 | 내부 seek로 인한 buffering→ready 전환을 buffering watch가 자연 발생으로 오인하여 state-request 루프 도는 것 방지 |
| `_storedSafeName` ↔ `_currentFileName` 분리 | 디스크/HTTP 서빙은 ASCII-safe 해시명(iOS AVPlayer 호환), UI 표시는 원본 파일명 유지 |
| URL `?v=timestamp` | AVPlayer가 같은 URL을 캐시해서 이전 세션 데이터를 재사용하는 문제 방지 |
| `_handlePlay`/`_handleStateResponse`에서 reload 먼저 | 로그 출력 후 reload하면 reload 소요시간이 elapsed 계산에 누락됨. reload 후 elapsed 재계산 |
| sync-position 5초 간격 | 드리프트/지터를 주기적으로 잡되, 너무 잦으면 seek 과다 |
| bestRtt는 로그 전용 | offset 선택 기준으로만 사용, 이후 계산에 미사용 |
| 블루투스 레이턴시 | engineLatency에 미포함, 수동 슬라이더로 대응 예정 |
