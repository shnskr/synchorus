"""Clock sync filter 비교 분석.

온디바이스 필터(EMA 0.9/0.1, RTT-min window 5)가 더 정교한 방법 대비
얼마나 좋은지 같은 CSV 데이터에 여러 방법을 돌려서 비교한다.

평가 기준:
  - filtered offset의 안정성 (stdev, range)
  - 초기 수렴 속도 (초기 추정값이 "진값"에 근접하기까지)
  - 이상치 저항 (RTT 스파이크에 얼마나 흔들리는지)

여기서 "진값(ground truth)"은 모든 샘플 기반 중앙값으로 가정한다
(더 나은 기준이 없으므로. 28초 세션이라 실제 clock drift 변화는 무시 가능).
"""

from __future__ import annotations

import csv
import math
import statistics
from dataclasses import dataclass
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
matplotlib.rcParams["font.family"] = "AppleGothic"
matplotlib.rcParams["axes.unicode_minus"] = False
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
DATA = HERE / "data" / "sync_2026-04-09T22-06-33-153879.csv"
OUT = HERE / "output"
OUT.mkdir(exist_ok=True)


@dataclass
class Sample:
    seq: int
    t1: int
    t2: int
    t3: int

    @property
    def rtt(self) -> int:
        return self.t3 - self.t1

    @property
    def raw_offset(self) -> float:
        # host wall(t2) - guest wall 중간값
        return self.t2 - (self.t1 + self.t3) / 2.0


def load(path: Path) -> list[Sample]:
    samples: list[Sample] = []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            samples.append(
                Sample(
                    seq=int(row["seq"]),
                    t1=int(row["t1"]),
                    t2=int(row["t2"]),
                    t3=int(row["t3"]),
                )
            )
    return samples


# ─────────────────────────────────────────────────────────────
# Filters: 각각 (list[Sample]) → list[float | None] 반환.
# None = "아직 추정값 없음".
# 모두 온라인(prefix-only) 방식. i번째 출력은 0..i 샘플만 사용.
# ─────────────────────────────────────────────────────────────

def naive_raw(samples: list[Sample]) -> list[float | None]:
    """필터 없음: 최신 raw 값 그대로."""
    return [s.raw_offset for s in samples]


def ema_fixed(samples: list[Sample], alpha: float, rtt_min_window: int = 5,
              init_count: int = 10) -> list[float | None]:
    """온디바이스와 동일한 방식:
      - 초기 init_count 샘플 축적 → RTT 최소 샘플의 raw offset으로 고정
      - 이후 rtt_min_window 창 내 RTT 최소 샘플을 new로 보고 EMA 업데이트.
    """
    out: list[float | None] = []
    filt: float | None = None
    window: list[Sample] = []
    initial_done = False
    for i, s in enumerate(samples):
        if not initial_done:
            if i < init_count:
                out.append(None)
                continue
            # init 단계 끝 → 지금까지 모은 샘플 중 RTT 최소 채택
            best = min(samples[:init_count], key=lambda x: x.rtt)
            filt = best.raw_offset
            initial_done = True
            # 현재 i >= init_count 이므로 아래로 떨어져서 업데이트 진행
        window.append(s)
        if len(window) > rtt_min_window:
            window.pop(0)
        best = min(window, key=lambda x: x.rtt)
        filt = filt * (1 - alpha) + best.raw_offset * alpha  # type: ignore
        out.append(filt)
    return out


def median_window(samples: list[Sample], window: int = 20,
                  init_count: int = 10) -> list[float | None]:
    """최근 window개 raw offset의 중앙값."""
    out: list[float | None] = []
    buf: list[float] = []
    for i, s in enumerate(samples):
        buf.append(s.raw_offset)
        if len(buf) > window:
            buf.pop(0)
        if i < init_count:
            out.append(None)
            continue
        out.append(statistics.median(buf))
    return out


def weighted_rtt(samples: list[Sample], window: int = 20,
                 init_count: int = 10) -> list[float | None]:
    """최근 window개에서 RTT 역수 가중 평균 (RTT 작은 샘플일수록 무게↑)."""
    out: list[float | None] = []
    buf: list[Sample] = []
    for i, s in enumerate(samples):
        buf.append(s)
        if len(buf) > window:
            buf.pop(0)
        if i < init_count:
            out.append(None)
            continue
        total_w = 0.0
        total = 0.0
        for x in buf:
            w = 1.0 / max(1.0, x.rtt)
            total_w += w
            total += x.raw_offset * w
        out.append(total / total_w)
    return out


def linreg_recent(samples: list[Sample], window: int = 20,
                  init_count: int = 10) -> list[float | None]:
    """최근 window개의 (t1, raw_offset) 선형 회귀 → 현재 t1에서의 예측값.

    장점: offset이 시간에 따라 선형으로 변하는 추세를 흡수.
    (= clock drift도 부분적으로 반영 가능)
    """
    out: list[float | None] = []
    buf: list[Sample] = []
    for i, s in enumerate(samples):
        buf.append(s)
        if len(buf) > window:
            buf.pop(0)
        if i < init_count:
            out.append(None)
            continue
        xs = np.array([x.t1 for x in buf], dtype=np.float64)
        ys = np.array([x.raw_offset for x in buf], dtype=np.float64)
        xs -= xs.mean()
        ys_mean = ys.mean()
        denom = (xs ** 2).sum()
        if denom == 0:
            out.append(ys_mean)
            continue
        slope = (xs * (ys - ys_mean)).sum() / denom
        # 현재(x=t1 최신) 시점에서의 예측값 = ys_mean + slope * (xs[-1]의 mean-shifted)
        pred = ys_mean + slope * xs[-1]
        out.append(pred)
    return out


def rttmin_linreg(samples: list[Sample], window: int = 20,
                  init_count: int = 10) -> list[float | None]:
    """선형 회귀의 변형: 최근 window 안에서 RTT가 중앙값 이하인 샘플만 사용.
    → 스파이크 영향 줄이기.
    """
    out: list[float | None] = []
    buf: list[Sample] = []
    for i, s in enumerate(samples):
        buf.append(s)
        if len(buf) > window:
            buf.pop(0)
        if i < init_count:
            out.append(None)
            continue
        if len(buf) < 3:
            out.append(buf[-1].raw_offset)
            continue
        rtt_med = statistics.median([x.rtt for x in buf])
        good = [x for x in buf if x.rtt <= rtt_med]
        if len(good) < 2:
            good = buf
        xs = np.array([x.t1 for x in good], dtype=np.float64)
        ys = np.array([x.raw_offset for x in good], dtype=np.float64)
        xs_mean = xs.mean()
        xs_shift = xs - xs_mean
        ys_mean = ys.mean()
        denom = (xs_shift ** 2).sum()
        if denom == 0:
            out.append(ys_mean)
            continue
        slope = (xs_shift * (ys - ys_mean)).sum() / denom
        pred = ys_mean + slope * (buf[-1].t1 - xs_mean)
        out.append(pred)
    return out


# ─────────────────────────────────────────────────────────────
# 평가
# ─────────────────────────────────────────────────────────────

def summarize(name: str, values: list[float | None],
              ground_truth: float) -> dict:
    valid = [v for v in values if v is not None]
    if not valid:
        return {"name": name, "n": 0}
    arr = np.array(valid, dtype=np.float64)
    errors = arr - ground_truth
    return {
        "name": name,
        "n": len(valid),
        "mean": float(arr.mean()),
        "stdev": float(arr.std(ddof=0)),
        "range": float(arr.max() - arr.min()),
        "mae_from_gt": float(np.abs(errors).mean()),
        "max_abs_err_from_gt": float(np.abs(errors).max()),
    }


def main() -> None:
    samples = load(DATA)
    print(f"Loaded {len(samples)} sync samples from {DATA.name}")

    raw_offsets = [s.raw_offset for s in samples]
    rtts = [s.rtt for s in samples]
    gt = statistics.median(raw_offsets)
    print(f"Ground truth (median of raw offsets): {gt:.2f} ms")
    print(f"Raw offset range: [{min(raw_offsets):.0f}, {max(raw_offsets):.0f}] "
          f"= {max(raw_offsets) - min(raw_offsets):.0f} ms")
    print(f"RTT: min={min(rtts)}, median={statistics.median(rtts):.0f}, "
          f"p95={np.percentile(rtts, 95):.0f}, max={max(rtts)}")
    print()

    # 평가 대상 필터
    filters = {
        "raw (no filter)": naive_raw(samples),
        "EMA α=0.05 (win5)": ema_fixed(samples, 0.05),
        "EMA α=0.1 (win5) ← 온디바이스": ema_fixed(samples, 0.1),
        "EMA α=0.2 (win5)": ema_fixed(samples, 0.2),
        "EMA α=0.1 (win10)": ema_fixed(samples, 0.1, rtt_min_window=10),
        "median (win20)": median_window(samples, 20),
        "weighted-RTT (win20)": weighted_rtt(samples, 20),
        "linreg (win20)": linreg_recent(samples, 20),
        "RTT-min linreg (win20)": rttmin_linreg(samples, 20),
    }

    print(f"{'filter':40s} {'n':>4s} {'stdev':>8s} {'range':>8s} "
          f"{'MAE':>8s} {'maxErr':>8s}")
    print("-" * 80)
    rows = []
    for name, vals in filters.items():
        s = summarize(name, vals, gt)
        if s["n"] == 0:
            print(f"{name:40s}   (no valid samples)")
            continue
        rows.append((name, s, vals))
        print(f"{name:40s} {s['n']:>4d} {s['stdev']:>8.2f} {s['range']:>8.2f} "
              f"{s['mae_from_gt']:>8.2f} {s['max_abs_err_from_gt']:>8.2f}")
    print()

    # ── PNG: 필터별 시계열 ─────────────────────────────────────
    t_rel = np.array([(s.t1 - samples[0].t1) / 1000.0 for s in samples])  # seconds
    fig, axes = plt.subplots(2, 1, figsize=(12, 8), sharex=True)

    ax = axes[0]
    ax.plot(t_rel, raw_offsets, "o-", color="#bbbbbb", ms=3, lw=0.7,
            label="raw (no filter)")
    for name, _, vals in rows:
        if "raw" in name:
            continue
        y = [v if v is not None else np.nan for v in vals]
        is_device = "온디바이스" in name
        ax.plot(t_rel, y, lw=2.2 if is_device else 1.2, label=name,
                zorder=5 if is_device else 2)
    ax.axhline(gt, color="red", ls="--", lw=0.8, label=f"ground truth (median)")
    ax.set_ylabel("offset (ms)")
    ax.set_title("Clock sync filter 비교 (raw vs 필터 여러 개)")
    ax.legend(loc="upper right", fontsize=8, ncol=2)
    ax.grid(alpha=0.3)

    ax = axes[1]
    ax.plot(t_rel, rtts, "o-", color="#555555", ms=3, lw=0.7)
    ax.set_ylabel("RTT (ms)")
    ax.set_xlabel("경과 시간 (초)")
    ax.set_title("RTT 시계열 (스파이크 패턴 확인)")
    ax.grid(alpha=0.3)

    plt.tight_layout()
    png = OUT / "sync_filters.png"
    plt.savefig(png, dpi=120)
    print(f"PNG saved: {png}")

    # ── 수렴 속도: 초기값이 gt의 ±5ms 이내로 진입한 샘플 index ─
    print()
    print("수렴 속도 (gt ±2ms 진입한 샘플 index, -1=도달 못함):")
    for name, _, vals in rows:
        if "raw" in name:
            continue
        first_within = -1
        for i, v in enumerate(vals):
            if v is not None and abs(v - gt) <= 2.0:
                first_within = i
                break
        print(f"  {name:40s}: sample {first_within}")


if __name__ == "__main__":
    main()
