"""Phase 4 실측: drift 시계열과 seek 이벤트를 같이 본다.

핵심 질문:
  1) seek가 실제로 drift를 줄이는가?
  2) post-seek probe [100,300,500,1000,2000]ms 시점에 drift가 얼마나 수렴하는가?
  3) 세션 전체에서 |drift|가 threshold (20ms) 안으로 들어온 비율은?

입력: drift_<session>.csv, seek_events_<session>.csv
출력: output/phase4_<session>.png + stdout 요약
"""

from __future__ import annotations

import csv
import sys
from dataclasses import dataclass
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
matplotlib.rcParams["font.family"] = "AppleGothic"
matplotlib.rcParams["axes.unicode_minus"] = False
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
OUT = HERE / "output"
OUT.mkdir(exist_ok=True)

THRESHOLD_MS = 20.0


@dataclass
class DriftRow:
    wall_ms: int
    drift_ms: float


@dataclass
class SeekEvent:
    event_id: int
    t_seek_ms: int
    pre_drift_ms: float
    correction_frames: int
    probes: list[tuple[int, float]]  # (ms_since_seek, driftMs)


def load_drift(p: Path) -> list[DriftRow]:
    out: list[DriftRow] = []
    with p.open() as f:
        r = csv.DictReader(f)
        for row in r:
            out.append(
                DriftRow(
                    wall_ms=int(row["wallMs"]),
                    drift_ms=float(row["driftMs"]),
                )
            )
    return out


def load_seeks(p: Path) -> list[SeekEvent]:
    events: dict[int, SeekEvent] = {}
    with p.open() as f:
        r = csv.DictReader(f)
        for row in r:
            eid = int(row["eventId"])
            if row["kind"] == "pre":
                events[eid] = SeekEvent(
                    event_id=eid,
                    t_seek_ms=int(row["wallMs"]),
                    pre_drift_ms=float(row["driftMs"]),
                    correction_frames=int(row["correctionFrames"]),
                    probes=[],
                )
            elif row["kind"] == "probe":
                if eid in events:
                    events[eid].probes.append(
                        (int(row["msSinceSeek"]), float(row["driftMs"]))
                    )
    return [events[k] for k in sorted(events.keys())]


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: python phase4_drift_vs_seek.py <SESSION>")
        print("  예: python phase4_drift_vs_seek.py 2026-04-09T23-15-08-800629")
        sys.exit(1)

    session = sys.argv[1]
    drift_p = DATA / f"drift_{session}.csv"
    seek_p = DATA / f"seek_events_{session}.csv"

    drift = load_drift(drift_p)
    seeks = load_seeks(seek_p)
    print(f"drift samples : {len(drift)}")
    print(f"seek events   : {len(seeks)}")

    if not drift:
        print("drift 샘플 없음, 종료")
        return

    t0 = drift[0].wall_ms
    xs = np.array([(d.wall_ms - t0) / 1000.0 for d in drift])
    ys = np.array([d.drift_ms for d in drift])
    within = np.abs(ys) < THRESHOLD_MS
    pct = within.sum() * 100.0 / len(ys)

    print(f"session length: {xs[-1]:.1f} s")
    print(f"drift min     : {ys.min():.1f} ms")
    print(f"drift max     : {ys.max():.1f} ms")
    print(f"drift mean    : {ys.mean():.1f} ms")
    print(f"drift median  : {float(np.median(ys)):.1f} ms")
    print(f"|drift|<{THRESHOLD_MS:.0f}ms ratio: {pct:.1f}%")

    # ── seek 수렴 분석: pre → 마지막 probe의 drift 변화
    converged = 0
    total_with_final = 0
    pre_abs_sum = 0.0
    post_abs_sum = 0.0
    for ev in seeks:
        if not ev.probes:
            continue
        # 마지막 probe (시간상 가장 뒤)
        last_probe = max(ev.probes, key=lambda p: p[0])
        pre = abs(ev.pre_drift_ms)
        post = abs(last_probe[1])
        pre_abs_sum += pre
        post_abs_sum += post
        total_with_final += 1
        if post < pre:
            converged += 1

    print()
    print(f"seek events (with probes) : {total_with_final}")
    if total_with_final > 0:
        print(f"  수렴한 것 (|post|<|pre|) : {converged} / {total_with_final}"
              f" ({converged*100/total_with_final:.1f}%)")
        print(f"  평균 |pre|  = {pre_abs_sum/total_with_final:.1f} ms")
        print(f"  평균 |post| = {post_abs_sum/total_with_final:.1f} ms")

    # ── PNG
    fig, axes = plt.subplots(2, 1, figsize=(12, 9), sharex=False)

    ax = axes[0]
    ax.plot(xs, ys, "-", lw=0.8, color="#1f77b4", label="drift (ms)")
    ax.axhline(THRESHOLD_MS, color="red", lw=0.5, linestyle="--")
    ax.axhline(-THRESHOLD_MS, color="red", lw=0.5, linestyle="--")
    ax.axhline(0, color="k", lw=0.4)
    # seek 이벤트를 수직선으로
    for ev in seeks:
        t_rel = (ev.t_seek_ms - t0) / 1000.0
        ax.axvline(t_rel, color="orange", lw=0.3, alpha=0.5)
    ax.set_xlabel("경과 (s)")
    ax.set_ylabel("drift (ms) · +면 게스트 앞섬")
    ax.set_title(
        f"drift 시계열 + seek 이벤트 (세션 {xs[-1]:.1f}s, "
        f"seek {len(seeks)}회, |drift|<{THRESHOLD_MS:.0f}ms {pct:.1f}%)"
    )
    ax.legend()
    ax.grid(alpha=0.3)

    # seek 이벤트별 pre vs post 비교 (scatter)
    ax = axes[1]
    if total_with_final > 0:
        pre_list = []
        post_list = []
        for ev in seeks:
            if not ev.probes:
                continue
            last = max(ev.probes, key=lambda p: p[0])
            pre_list.append(ev.pre_drift_ms)
            post_list.append(last[1])
        ax.scatter(pre_list, post_list, s=18, alpha=0.6, color="#1f77b4",
                   label="seek 이벤트")
        lim = max(abs(min(pre_list)), abs(max(pre_list)),
                  abs(min(post_list)), abs(max(post_list))) * 1.1
        ax.plot([-lim, lim], [-lim, lim], "--", color="gray", lw=0.5,
                label="y=x (변화 없음)")
        ax.plot([-lim, lim], [0, 0], "-", color="red", lw=0.5,
                label="y=0 (완벽 수렴)")
        ax.axvline(0, color="k", lw=0.4)
        ax.set_xlim(-lim, lim)
        ax.set_ylim(-lim, lim)
        ax.set_xlabel("seek 직전 drift (ms)")
        ax.set_ylabel("마지막 probe drift (ms)")
        ax.set_title(
            f"seek 수렴성: {converged}/{total_with_final}"
            f" ({converged*100/total_with_final:.1f}%)이"
            f" |post|<|pre|"
        )
        ax.legend()
        ax.grid(alpha=0.3)

    plt.tight_layout()
    png = OUT / f"phase4_{session}.png"
    plt.savefig(png, dpi=120)
    print()
    print(f"PNG saved: {png}")


if __name__ == "__main__":
    main()
