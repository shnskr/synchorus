# 에뮬레이터 네트워크 설정 가이드

## 문제

Android 에뮬레이터는 가상 네트워크(10.0.2.x)를 사용하기 때문에, 같은 WiFi에 있는 실기기의 IP(192.168.x.x)로 직접 TCP 연결이 안 됨.

## 해결: adb forward

Mac을 중계 서버로 사용하여 에뮬레이터 → Mac → 실기기로 포트 포워딩.

### 설정 방법

```bash
# 1. adb 경로 (Mac 기준)
/Users/dal/Library/Android/sdk/platform-tools/adb -s R3CT60D20XE forward tcp:41235 tcp:41235
```

- `R3CT60D20XE`: Galaxy S22 디바이스 ID (다른 기기면 `adb devices`로 확인)
- `41235`: Synchorus TCP 서버 포트

### 테스트 순서

1. 위 adb forward 명령 실행
2. **실기기(폰)**에서 방 만들기 (호스트)
3. **에뮬레이터**에서 IP 입력란에 `10.0.2.2` 입력하여 참가 (게스트)

### 에뮬레이터 특수 IP

| IP | 의미 |
|-----|------|
| `10.0.2.2` | 호스트 Mac (localhost) |
| `10.0.2.15` | 에뮬레이터 자신 |
| `10.0.2.3` | DNS 서버 |

### 주의사항

- adb forward는 **Mac 재부팅, USB 재연결 시 풀림** → 다시 실행 필요
- 에뮬레이터가 **호스트(서버)**가 되면 실기기에서 접근 불가 → 반드시 실기기가 호스트
- 에뮬레이터의 connectivity_plus는 WiFi(`AndroidWifi`)로 인식하므로 앱 내 WiFi 체크는 통과함
- UDP 브로드캐스트는 에뮬레이터에서 불가 → IP 직접 입력으로만 참가 가능
