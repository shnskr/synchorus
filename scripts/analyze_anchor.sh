#!/usr/bin/env bash
# anchor 주기 재발행 트랙 측정 분석 — 결함 A 잔재 + offset 안정성 정량화.
#
# 사용: ./scripts/analyze_anchor.sh measurements/auto_YYYY-MM-DD_HHMMSS.csv
#
# 컬럼은 헤더에서 동적으로 찾음(포맷 변경 안전). 핵심 컬럼:
#   vf_diff_ms, offset_ms, last_rtt_ms, event
#
# 핵심 질문: v0.0.120 offset 안정화 후
#   ① fallback 지배(이전 109회) 해소됐나? → event 비율
#   ② anchor 경로(drift) vfDiff −19.5 일정 편향 잔존? → drift vf_diff 분포
#   ③ fallback이 anchor보다 정확한가(결함 A)? → fallback vs drift vf_diff 비교

set -euo pipefail
CSV="${1:?사용: $0 <csv 경로>}"
[[ -f "$CSV" ]] || { echo "csv 없음: $CSV" >&2; exit 1; }

# BSD awk엔 asort 없음 → 삽입정렬(1-base) + 동적 컬럼 인덱스 헬퍼.
COMMON='function isort(a, len,   i,j,t){for(i=2;i<=len;i++){t=a[i];j=i-1;while(j>=1&&a[j]>t){a[j+1]=a[j];j--}a[j+1]=t}}
function med(a, len){return (len%2)?a[int((len+1)/2)]:(a[len/2]+a[len/2+1])/2}'

echo "=== $CSV ($(($(wc -l <"$CSV") - 1)) 행) ==="
echo
echo "── event 카운트 ──"
awk -F',' '
    NR==1 { for(i=1;i<=NF;i++) if($i=="event") ec=i; next }
    { c[$ec]++; n++ } END { for (e in c) printf "  %6d  %5.1f%%  %s\n", c[e], 100*c[e]/n, e }
' "$CSV" | sort -rn -k1

# vf_diff 분포 (signed mean / |mean| / RMS / range / median) — event 인자로 선택
dist() {
    local ev="$1"
    awk -F',' -v ev="$ev" "$COMMON"'
        NR==1 { for(i=1;i<=NF;i++){ if($i=="event")ec=i; if($i=="vf_diff_ms")vc=i } next }
        $ec==ev { n++; v[n]=$vc; s+=$vc; a+=($vc<0?-$vc:$vc); sq+=$vc*$vc;
            if (n==1||$vc>mx) mx=$vc; if (n==1||$vc<mn) mn=$vc }
        END {
            if (n==0) { printf "  %-22s (없음)\n", ev; exit }
            isort(v, n)
            printf "  %-22s n=%-4d signed=%+7.2f |mean|=%6.2f med=%+7.2f RMS=%6.2f range=[%+.1f, %+.1f]\n",
                   ev, n, s/n, a/n, med(v,n), sqrt(sq/n), mn, mx
        }' "$CSV"
}
echo
echo "── vf_diff 분포 (결함 A: anchor 경로 일정 편향 vs fallback 정확도) ──"
dist "drift"
dist "fallback"
dist "anchor_realign_vfdiff"
dist "anchor_realign_periodic"

echo
echo "── offset 안정성 (v0.0.120 효과: drift 행의 offset_ms) ──"
awk -F',' "$COMMON"'
    NR==1 { for(i=1;i<=NF;i++){ if($i=="event")ec=i; if($i=="offset_ms")oc=i } next }
    $ec=="drift" && $oc!="" { v[n++]=$oc; s+=$oc; if(n==1||$oc>mx)mx=$oc; if(n==1||$oc<mn)mn=$oc }
    END {
        if (n==0) { print "  (offset 없음)"; exit }
        m=s/n; for(i=0;i<n;i++){d=v[i]-m; sd+=d*d}
        printf "  n=%d  mean=%.2f  stdev=%.2f  range=[%.1f, %.1f]  span=%.1f\n",
               n, m, sqrt(sd/n), mn, mx, mx-mn
    }' "$CSV"

echo
echo "── anchor establish/reset 시퀀스 (결함 A: 매 establish 편향 변동) ──"
awk -F',' '
    NR==1 { for(i=1;i<=NF;i++){ if($i=="event")ec=i; if($i=="vf_diff_ms")vc=i; if($i=="seq")sc=i } next }
    $ec ~ /^anchor_(set|realign|reset)/ { printf "  seq=%-6s %-26s vf_diff=%s\n", $sc, $ec, $vc }
' "$CSV"

echo
echo "── RTT 양상 (참고: v0.0.120 잔여 reject — RTT 양극화 여부) ──"
awk -F',' "$COMMON"'
    NR==1 { for(i=1;i<=NF;i++) if($i=="last_rtt_ms") rc=i; next }
    $rc!="" && $rc+0>0 { n++; r[n]=$rc+0; s+=$rc }
    END { if(n==0){print "  (rtt 없음)";exit}
        isort(r, n)
        printf "  last_rtt_ms: n=%d mean=%.1f median=%.1f min=%.1f max=%.1f\n", n, s/n, med(r,n), r[1], r[n] }' "$CSV"
