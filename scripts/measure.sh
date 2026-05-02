#!/usr/bin/env bash
# 측정 자동화 — 한 줄로 빌드/install/launch/대기/csv pull/통계 출력.
#
# 사용:
#   ./scripts/measure.sh                  # default: 12분 측정, S22 host + A7 Lite guest
#   ./scripts/measure.sh --quick          # 60s (smoke test)
#   ./scripts/measure.sh --short          # 3분
#   ./scripts/measure.sh --mid            # 5분
#   ./scripts/measure.sh --long           # 12분 (default, 14분 한계 안전 마진)
#   ./scripts/measure.sh -d 300           # 임의 초
#   ./scripts/measure.sh -h R3CT60D20XE -g R9PW315GL0L -d 720
#
# 동작:
#   1. host용 apk 빌드 (AUTO_MEASURE_MODE=host) → 호스트 기기 install
#   2. guest용 apk 빌드 (AUTO_MEASURE_MODE=guest) → 게스트 기기 install
#   3. 양쪽 강제 종료 + 호스트 launch + (3초 후) 게스트 launch
#   4. (durationSec + 60) 초 대기
#   5. 호스트 csv pull → measurements/auto_<timestamp>.csv
#   6. 통계 출력
#
# 요구사항:
#   - flutter, adb 설치
#   - 양쪽 기기 USB 연결 + adb devices에 device 상태
#   - assets/measure_audio.mp3 존재
#   - 양쪽 기기 같은 WiFi (P2P 통신)

set -euo pipefail

# ─── 기본 설정 ──────────────────────────────────────────
DURATION_SEC=720          # 12분
HOST_DEVICE="R3CT60D20XE" # Galaxy S22
GUEST_DEVICE="R9PW315GL0L" # Galaxy Tab A7 Lite
PACKAGE="com.synchorus.synchorus"
ACTIVITY="com.synchorus.synchorus/.MainActivity"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MEASUREMENTS_DIR="$ROOT_DIR/measurements"
APK_OUT="build/app/outputs/flutter-apk/app-debug.apk"

# ─── 인자 파싱 ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)       DURATION_SEC=60; shift ;;   # smoke test
        --short)       DURATION_SEC=180; shift ;;  # 3분
        --mid)         DURATION_SEC=300; shift ;;  # 5분
        --long)        DURATION_SEC=720; shift ;;  # 12분 (default)
        -d|--duration) DURATION_SEC="$2"; shift 2 ;;
        -h|--host)     HOST_DEVICE="$2"; shift 2 ;;
        -g|--guest)    GUEST_DEVICE="$2"; shift 2 ;;
        --help)
            sed -n '2,25p' "$0"
            exit 0
            ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done

cd "$ROOT_DIR"

ts() { date +"%H:%M:%S"; }
log() { echo "[$(ts)] $*"; }

# ─── 사전 확인 ─────────────────────────────────────────
if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter 명령 없음" >&2; exit 1
fi
if [[ ! -x "$ADB" ]]; then
    echo "adb 없음: $ADB" >&2; exit 1
fi

CONNECTED=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
for dev in "$HOST_DEVICE" "$GUEST_DEVICE"; do
    if ! grep -q "$dev" <<<"$CONNECTED"; then
        echo "기기 미연결: $dev" >&2
        echo "연결된 기기: $CONNECTED" >&2
        exit 1
    fi
done

# ─── 빌드 함수 ─────────────────────────────────────────
build_and_install() {
    local mode="$1"
    local device="$2"
    log "  $mode 빌드 ($device)..."
    flutter build apk --debug \
        --dart-define=AUTO_MEASURE_MODE="$mode" \
        --dart-define=AUTO_MEASURE_DURATION_SEC="$DURATION_SEC" \
        >/tmp/measure_build_$mode.log 2>&1 || {
            tail -20 /tmp/measure_build_$mode.log
            echo "$mode 빌드 실패. 전체 로그: /tmp/measure_build_$mode.log" >&2
            exit 1
        }
    "$ADB" -s "$device" install -r "$APK_OUT" \
        >/tmp/measure_install_$mode.log 2>&1 || {
            tail /tmp/measure_install_$mode.log
            echo "$mode install 실패" >&2
            exit 1
        }
}

# ─── 빌드 + install (호스트, 게스트 각각) ──────────────
log "[1/5] HOST/GUEST 빌드 + install..."
build_and_install "host"  "$HOST_DEVICE"
build_and_install "guest" "$GUEST_DEVICE"
log "    빌드 + install 완료"

# ─── 강제 종료 → launch ────────────────────────────────
log "[2/5] 양쪽 앱 강제 종료 + launch..."
"$ADB" -s "$HOST_DEVICE"  shell am force-stop "$PACKAGE" >/dev/null
"$ADB" -s "$GUEST_DEVICE" shell am force-stop "$PACKAGE" >/dev/null
sleep 2

"$ADB" -s "$HOST_DEVICE"  shell am start -n "$ACTIVITY" >/dev/null
log "    HOST launched"
sleep 3
"$ADB" -s "$GUEST_DEVICE" shell am start -n "$ACTIVITY" >/dev/null
log "    GUEST launched"

# ─── 측정 대기 ─────────────────────────────────────────
# 게스트 발견 60s + host 안정 5s + 재생 durationSec + 정지 5s + buffer 30s
WAIT_SEC=$((DURATION_SEC + 100))
log "[3/5] 측정 대기 (~${WAIT_SEC}s = $((WAIT_SEC / 60))분 $((WAIT_SEC % 60))초)..."
log "    진행 상황: adb -s $HOST_DEVICE logcat | grep AUTO_MEASURE"
sleep "$WAIT_SEC"

# ─── csv pull ──────────────────────────────────────────
log "[4/5] csv pull..."
mkdir -p "$MEASUREMENTS_DIR"
DATESTAMP=$(date +"%Y-%m-%d_%H%M%S")
LATEST_CSV=$("$ADB" -s "$HOST_DEVICE" shell \
    "ls -t /storage/emulated/*/Android/data/$PACKAGE/files/sync_log_*.csv 2>/dev/null | head -1" | tr -d '\r')
if [[ -z "$LATEST_CSV" ]]; then
    echo "csv 없음 — 측정 실패 가능성. logcat 확인:" >&2
    "$ADB" -s "$HOST_DEVICE" logcat -d -t 100 | grep -i "AUTO_MEASURE\|sync_log\|error" || true
    exit 1
fi
LOCAL_CSV="$MEASUREMENTS_DIR/auto_${DATESTAMP}.csv"
"$ADB" -s "$HOST_DEVICE" pull "$LATEST_CSV" "$LOCAL_CSV" >/dev/null
log "    csv pull → $LOCAL_CSV ($(wc -l <"$LOCAL_CSV") 행)"

# ─── 통계 출력 ─────────────────────────────────────────
log "[5/5] 통계 분석..."
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " 측정 결과"
echo "═══════════════════════════════════════════════════════════"
awk -F',' 'NR==1 {next} {events[$NF]++} END {
    print "[event 분포]"
    for (e in events) printf "  %-32s %d\n", e, events[e]
}' "$LOCAL_CSV"
echo ""
echo "[anchor / reset 시퀀스]"
awk -F',' 'NR==1 {next} {
    if ($NF=="anchor_reset_offset_drift" || $NF=="anchor_reset_large_drift" || $NF=="anchor_reset_seek_notify")
        printf "  RESET(%s) NR=%d filtered=%s winRaw=%s gap=%.2f\n", $NF, NR-2, $8, $17, $8-$17
    if ($NF=="anchor_set")
        printf "  ANCHOR_SET NR=%d filtered=%s winRaw=%s gap=%.2f\n", NR-2, $8, $17, $8-$17
}' "$LOCAL_CSV"
echo ""
awk -F',' 'NR==1 {next} $NF=="drift" {n++; sum+=$6; sumabs+=($6<0?-$6:$6); sumsq+=$6*$6; if ($6>max||n==1) max=$6; if ($6<min||n==1) min=$6} END {
    if (n==0) {print "[drift] 0개"; exit}
    printf "[drift 통계 (n=%d)]\n", n
    printf "  vfDiff signed mean: %.2f / |mean|: %.2f / RMS: %.2f / range: %.2f ~ %.2f\n", sum/n, sumabs/n, sqrt(sumsq/n), min, max
}' "$LOCAL_CSV"
echo "═══════════════════════════════════════════════════════════"
echo "csv 경로: $LOCAL_CSV"
