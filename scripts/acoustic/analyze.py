#!/usr/bin/env python3
"""
acoustic 녹음 분석 — 호스트/게스트 click 시차(음향 sync 오차) 부호+크기 측정.

원리:
  녹음에는 1초마다 chirp가 2개(호스트·게스트, sync 오차만큼 시차) 찍힘.
  matched filter(녹음 ⨯ chirp template) → correlation envelope에 peak 2개/주기.
  마이크를 호스트에 가까이 둬서 진폭 큰 peak = 호스트, 작은 peak = 게스트로 식별.
  두 peak 시각차 = 음향 도달 시차 → 거리차 음속 보정 → 출력(emit) 시차.

부호 정의 (emit_dt = t_guest_emit - t_host_emit):
  emit_dt > 0 : 게스트가 늦게 소리냄  → 호스트가 음향상 앞
  emit_dt < 0 : 게스트가 먼저 소리냄  → 게스트가 음향상 앞

사용:
  python3 analyze.py 녹음.wav --d-host 10 --d-guest 45
    --d-host/--d-guest : 마이크~폰 거리 (cm). 음속 보정용. 생략 시 보정 0.

녹음(맥북 내장 마이크, wav)이 m4a/mov면 먼저:
  ffmpeg -i 녹음.m4a -ar 48000 -ac 1 녹음.wav
"""
import sys
import argparse
import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, hilbert, find_peaks

SR = 48000
CHIRP_MS, F0, F1 = 5.0, 1000.0, 4000.0
PERIOD = 1.0
C_CM_PER_MS = 34.3  # 음속 343 m/s

def make_template():
    n = int(CHIRP_MS / 1000 * SR)
    t = np.arange(n) / SR
    phase = 2 * np.pi * (F0 * t + (F1 - F0) / (2 * (CHIRP_MS / 1000)) * t**2)
    return (np.sin(phase) * np.hanning(n)).astype(np.float64)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rec")
    ap.add_argument("--d-host", type=float, default=0.0, help="마이크~호스트 거리 cm")
    ap.add_argument("--d-guest", type=float, default=0.0, help="마이크~게스트 거리 cm")
    ap.add_argument("--max-gap-ms", type=float, default=120.0, help="한 이벤트 내 두 peak 최대 간격")
    args = ap.parse_args()

    sr, rec = wavfile.read(args.rec)
    rec = rec.astype(np.float64)
    if rec.ndim > 1:
        rec = rec.mean(axis=1)
    if sr != SR:
        print(f"⚠️ 녹음 sr={sr} != {SR}. ffmpeg -ar 48000으로 변환 권장.", file=sys.stderr)

    tmpl = make_template()
    corr = correlate(rec, tmpl, mode="valid")
    env = np.abs(hilbert(corr))
    env /= env.max()

    # peak 후보: 주기당 2개를 노려 distance를 작게, height로 잡음 컷
    peaks, props = find_peaks(env, height=0.12, distance=int(0.002 * sr))
    if len(peaks) < 4:
        print(f"❌ peak {len(peaks)}개뿐 — 신호 약함/녹음 문제. height 임계 낮추거나 재녹음.")
        return
    heights = props["peak_heights"]

    # ── 녹음 timebase 캘리브레이션 ───────────────────────────────
    # measure_chirp는 정확히 PERIOD(1.0s) 주기. 녹음 장비(ffmpeg avfoundation)가
    # sample rate를 잘못 태깅하면 시간축이 압축/팽창됨 → 녹음에서 chirp 실측 주기를
    # 재서 보정. 재생은 48kHz 폰 클럭(정확)이라 실측주기=1.0s가 ground truth.
    tpk = peaks / sr
    cand = np.arange(0.80, 1.06, 0.0002)
    foldR = lambda P: abs(np.mean(np.exp(1j * (tpk % P) / P * 2 * np.pi)))
    P_meas = cand[int(np.argmax([foldR(P) for P in cand]))]
    time_scale = PERIOD / P_meas  # 녹음시간 → 실제시간 (시차에 곱)
    eff_sr = sr / time_scale

    # 인접 peak를 이벤트로 묶기 (간격 < max_gap_ms = 같은 1초 주기의 호스트+게스트)
    max_gap = int(args.max_gap_ms / 1000 * sr)
    events = []
    i = 0
    while i < len(peaks):
        j = i
        while j + 1 < len(peaks) and (peaks[j + 1] - peaks[j]) < max_gap:
            j += 1
        grp_idx = list(range(i, j + 1))
        # 이벤트당 가장 강한 2개만 (반향 제거)
        grp = sorted(grp_idx, key=lambda k: heights[k], reverse=True)[:2]
        grp = sorted(grp, key=lambda k: peaks[k])  # 시간순
        if len(grp) == 2:
            events.append((peaks[grp[0]], heights[grp[0]], peaks[grp[1]], heights[grp[1]]))
        i = j + 1

    if not events:
        print("❌ 2-peak 이벤트 없음 — 시차가 너무 작아 겹쳤거나(둘이 한 peak) 마이크가 한 폰만 잡음.")
        print("   대책: 시차가 매우 작으면 single-peak 폭으로는 부호 못 봄 → 거리/볼륨 키워 재녹음.")
        return

    correction_ms = (args.d_guest - args.d_host) / C_CM_PER_MS  # arr→emit 보정량
    rows = []
    for (t1, a1, t2, a2) in events:
        # 진폭 큰 쪽 = 호스트
        if a1 >= a2:
            host_t, guest_t, big_first = t1, t2, True   # 큰(호스트)이 먼저
            ratio = a1 / a2
        else:
            host_t, guest_t, big_first = t2, t1, False  # 큰(호스트)이 나중
            ratio = a2 / a1
        arr_dt_ms = (guest_t - host_t) / sr * 1000.0 * time_scale  # timebase 보정
        emit_dt_ms = arr_dt_ms - correction_ms
        rows.append((emit_dt_ms, ratio, big_first))

    emit = np.array([r[0] for r in rows])
    ratios = np.array([r[1] for r in rows])
    big_first = np.array([r[2] for r in rows])

    # 부호 일관성: 진폭 식별이 신뢰되려면 "큰 peak가 먼저/나중"이 한쪽으로 일관해야
    frac_big_first = big_first.mean()

    print("═" * 60)
    print(f" acoustic 분석: {args.rec}")
    print("═" * 60)
    print(f"timebase 캘리브레이션: 실측주기 {P_meas*1000:.1f}ms → scale {time_scale:.4f} "
          f"(녹음 sr {sr}→실효 {eff_sr:.0f}Hz)")
    print(f"검출 이벤트(2-peak 주기): {len(events)}개")
    print(f"진폭비 host/guest median: {np.median(ratios):.2f} "
          f"(>2면 식별 명확, ~1이면 거리 더 벌려 재녹음)")
    print(f"'큰 peak가 먼저' 비율: {frac_big_first*100:.0f}% "
          f"({'일관 ✓' if abs(frac_big_first-0.5)>0.35 else '⚠️ 섞임 — 식별 불안정'})")
    print(f"음속 보정: d_guest-d_host={args.d_guest-args.d_host:.0f}cm → {correction_ms:+.2f}ms")
    print("-" * 60)
    print(f"emit_dt (게스트−호스트 출력 시차):")
    print(f"  median {np.median(emit):+.2f}ms / mean {emit.mean():+.2f}ms / std {emit.std():.2f}ms")
    print(f"  range  {emit.min():+.2f} ~ {emit.max():+.2f}ms")
    med = np.median(emit)
    verdict = "호스트가 음향상 앞" if med > 0 else "게스트가 음향상 앞"
    print("-" * 60)
    print(f"▶ 음향 판정: {verdict} (emit_dt median {med:+.1f}ms, guest−host)")
    print(f"  position(csv vfDiff)과는 부호 반대 관계: outLat 대칭이면 emit_dt ≈ −vfDiff.")
    print(f"  monotonic 후 vfDiff≈−3.6ms(호스트 position 앞) → 대칭이면 음향 emit_dt≈+3.6(호스트 앞) 예상.")
    print(f"  음향이 게스트 앞(음수)으로 나오면 → emit_dt−(−vfDiff) 만큼이 outputLatency 비대칭(결함 B).")
    print(f"  ※ 정확한 비교는 이 녹음과 동시 기록된 호스트 sync_log csv의 vfDiff median 사용.")
    print("═" * 60)

if __name__ == "__main__":
    main()
