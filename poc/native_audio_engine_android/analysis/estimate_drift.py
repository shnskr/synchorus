"""Host/Guest clock drift 추정.

3개의 CSV를 같이 본다:
  - audio_obs: host가 보낸 (framePos, timeNs) 관측값
  - guest_ts:  guest Oboe getTimestamp 폴링 결과 (framePos, timeNs, wallMs)
  - sync:      clock-sync 핑퐁 (t1, t2, t3) + 그로부터 계산되는 host-guest offset

목표:
  1) Host audio clock의 실시간 대비 "프레임/ms" 기울기 측정
  2) Guest audio clock의 실시간 대비 "프레임/ms" 기울기 측정
  3) 두 기울기 차이(= audio clock drift) → 30분 누적 오차 시나리오 추정
  4) 추가로 sync offset의 선형 추세(시간에 따른 wall clock drift)도 확인
  5) 결과를 PNG + stdout 요약으로 저장

drift 정의:
  - 각 기기 audio clock은 이상적으로 48000 frames/s = 48.000 frames/ms
  - 실제 칩마다 PPM 단위로 편차가 있음 (±20~50ppm은 흔함)
  - 이 PoC에서는 "28초 세션" 동안 두 기기가 얼마나 벌어졌는지만 보면 충분
"""

from __future__ import annotations

import csv
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
DATA = HERE / "data"
OUT = HERE / "output"
OUT.mkdir(exist_ok=True)

SESSION = "2026-04-09T22-06-33-153879"
AUDIO_OBS = DATA / f"audio_obs_{SESSION}.csv"
GUEST_TS = DATA / f"guest_ts_{SESSION}.csv"
SYNC = DATA / f"sync_{SESSION}.csv"

IDEAL_FRAMES_PER_MS = 48.0  # 48000 Hz


@dataclass
class AudioObs:
    """Host audio clock 관측값 (from host engine getTimestamp).

    timeNs: CLOCK_MONOTONIC nanos (host 로컬 기준)
    """

    seq: int
    frame_pos: int
    time_ns: int
    ok: int


@dataclass
class GuestTs:
    """Guest audio clock 관측값 (from guest Oboe getTimestamp).

    wall_ms: guest wall clock millis
    time_ns: CLOCK_MONOTONIC nanos (guest 로컬 기준)
    """

    wall_ms: int
    frame_pos: int
    time_ns: int
    ok: int


@dataclass
class SyncRow:
    seq: int
    t1: int  # guest wall ms (ping 보낸 시각)
    t2: int  # host wall ms  (pong 만든 시각)
    t3: int  # guest wall ms (pong 받은 시각)

    @property
    def rtt(self) -> int:
        return self.t3 - self.t1

    @property
    def raw_offset_ms(self) -> float:
        return self.t2 - (self.t1 + self.t3) / 2.0


def load_audio_obs(p: Path) -> list[AudioObs]:
    out: list[AudioObs] = []
    with p.open() as f:
        r = csv.DictReader(f)
        for row in r:
            if int(row.get("ok", 1)) == 0:
                continue
            out.append(
                AudioObs(
                    seq=int(row.get("seq", 0) or 0),
                    frame_pos=int(row["framePos"]),
                    time_ns=int(row["timeNs"]),
                    ok=int(row.get("ok", 1)),
                )
            )
    return out


def load_guest_ts(p: Path) -> list[GuestTs]:
    out: list[GuestTs] = []
    with p.open() as f:
        r = csv.DictReader(f)
        for row in r:
            if int(row.get("ok", 1)) == 0:
                continue
            out.append(
                GuestTs(
                    wall_ms=int(row["wallMs"]),
                    frame_pos=int(row["framePos"]),
                    time_ns=int(row["timeNs"]),
                    ok=int(row.get("ok", 1)),
                )
            )
    return out


def load_sync(p: Path) -> list[SyncRow]:
    out: list[SyncRow] = []
    with p.open() as f:
        r = csv.DictReader(f)
        for row in r:
            out.append(
                SyncRow(
                    seq=int(row["seq"]),
                    t1=int(row["t1"]),
                    t2=int(row["t2"]),
                    t3=int(row["t3"]),
                )
            )
    return out


def linreg(xs: np.ndarray, ys: np.ndarray) -> tuple[float, float]:
    """단순 최소제곱. (slope, intercept) 반환."""
    xm = xs.mean()
    ym = ys.mean()
    denom = ((xs - xm) ** 2).sum()
    if denom == 0:
        return 0.0, ym
    slope = ((xs - xm) * (ys - ym)).sum() / denom
    intercept = ym - slope * xm
    return float(slope), float(intercept)


def dedup_monotonic(samples: list, key) -> list:
    """같은 key값이 이어지면 하나만 남김.

    guest_ts에서 framePos가 2번 같은 값으로 찍히는 행들이 있어 (아마 getTimestamp가
    오디오 쪽 업데이트 전 시점에 호출된 것) 이런 중복을 제거한다.
    """
    if not samples:
        return samples
    out = [samples[0]]
    last = key(samples[0])
    for s in samples[1:]:
        v = key(s)
        if v == last:
            continue
        out.append(s)
        last = v
    return out


# ─────────────────────────────────────────────────────────────

def main() -> None:
    host = load_audio_obs(AUDIO_OBS)
    guest = load_guest_ts(GUEST_TS)
    sync = load_sync(SYNC)
    print(f"audio_obs : {len(host):4d}")
    print(f"guest_ts  : {len(guest):4d}")
    print(f"sync      : {len(sync):4d}")

    # framePos 중복(같은 값이 두 번 이상) 제거 → 기울기 추정에 유리
    guest_d = dedup_monotonic(guest, key=lambda x: x.frame_pos)
    host_d = dedup_monotonic(host, key=lambda x: x.frame_pos)
    print(f"host   dedup→ {len(host_d)}")
    print(f"guest  dedup→ {len(guest_d)}")

    # ── 1) Host frame rate: framePos vs timeNs (local monotonic) ─
    hx = np.array([h.time_ns / 1e6 for h in host_d], dtype=np.float64)  # ms
    hy = np.array([h.frame_pos for h in host_d], dtype=np.float64)
    host_slope, host_icp = linreg(hx, hy)  # frames per ms
    host_ppm = (host_slope / IDEAL_FRAMES_PER_MS - 1.0) * 1e6
    print()
    print(f"Host  frames/ms = {host_slope:.6f}  "
          f"(vs ideal {IDEAL_FRAMES_PER_MS:.3f}, {host_ppm:+.1f} ppm)")
    print(f"Host  sample span = {(hx.max() - hx.min())/1000:.1f}s, "
          f"frame span = {int(hy.max() - hy.min())}")

    # ── 2) Guest frame rate ─
    gx = np.array([g.time_ns / 1e6 for g in guest_d], dtype=np.float64)
    gy = np.array([g.frame_pos for g in guest_d], dtype=np.float64)
    guest_slope, guest_icp = linreg(gx, gy)
    guest_ppm = (guest_slope / IDEAL_FRAMES_PER_MS - 1.0) * 1e6
    print()
    print(f"Guest frames/ms = {guest_slope:.6f}  "
          f"(vs ideal {IDEAL_FRAMES_PER_MS:.3f}, {guest_ppm:+.1f} ppm)")
    print(f"Guest sample span = {(gx.max() - gx.min())/1000:.1f}s, "
          f"frame span = {int(gy.max() - gy.min())}")

    # ── 3) 상대 drift (host - guest) ─
    # 두 기기의 audio clock이 1ms 동안 몇 프레임씩 벌어지는가
    rel_slope = host_slope - guest_slope
    rel_ppm = host_ppm - guest_ppm
    print()
    print(f"Host - Guest frames/ms = {rel_slope:+.6f}  ({rel_ppm:+.1f} ppm)")

    # 30분 누적: rel_slope [frames/ms] × 1_800_000 [ms] = 누적 프레임 차
    minutes = 30
    total_ms = minutes * 60_000
    frame_drift = rel_slope * total_ms
    ms_drift = frame_drift / IDEAL_FRAMES_PER_MS  # 정확히는 frame_drift / guest_slope
    print(f"  → {minutes}분 누적 frame 차이 ≈ {frame_drift:+.0f} frames "
          f"≈ {ms_drift:+.1f} ms")

    # ── 4) sync raw offset의 선형 추세 (wall clock drift) ─
    # t1 (guest wall ms) 기준 raw_offset을 선형회귀 → slope는 ms per ms 단위
    sx = np.array([s.t1 for s in sync], dtype=np.float64)
    sy = np.array([s.raw_offset_ms for s in sync], dtype=np.float64)
    # 아웃라이어 줄이기: rtt가 중앙값 이하인 샘플만 사용
    rtts = np.array([s.rtt for s in sync], dtype=np.float64)
    mask = rtts <= np.median(rtts)
    sx_g = sx[mask]
    sy_g = sy[mask]
    sync_slope, sync_icp = linreg(sx_g, sy_g)
    sync_ppm = sync_slope * 1e6  # ms per 1e6 ms = ppm
    print()
    print(f"sync offset slope = {sync_slope*1000:+.3f} ms/s  ({sync_ppm:+.1f} ppm)")
    print(f"  → {minutes}분 wall clock 누적 차이 ≈ {sync_slope * total_ms:+.1f} ms")

    # ── 5) PNG 출력 ─
    fig, axes = plt.subplots(3, 1, figsize=(12, 11), sharex=False)

    # (a) host/guest framePos vs local time
    ax = axes[0]
    ax.plot((hx - hx[0]) / 1000, hy / 1e6, "o-", ms=3, lw=0.7,
            label=f"host ({host_ppm:+.0f} ppm)", color="#1f77b4")
    ax.plot((gx - gx[0]) / 1000, gy / 1e6, "o-", ms=3, lw=0.7,
            label=f"guest ({guest_ppm:+.0f} ppm)", color="#ff7f0e")
    ax.set_title(f"Audio clock 기울기 (framePos vs local monotonic) - Host vs Guest")
    ax.set_xlabel("local 경과 시간 (s)")
    ax.set_ylabel("framePos (M frames)")
    ax.legend()
    ax.grid(alpha=0.3)

    # (b) residual from linear fit: 개별 샘플이 직선에서 얼마나 벗어났는지
    ax = axes[1]
    host_pred = host_slope * hx + host_icp
    guest_pred = guest_slope * gx + guest_icp
    host_res = hy - host_pred
    guest_res = gy - guest_pred
    ax.plot((hx - hx[0]) / 1000, host_res, "o-", ms=3, lw=0.7,
            label=f"host residual (stdev {host_res.std():.1f} frames)",
            color="#1f77b4")
    ax.plot((gx - gx[0]) / 1000, guest_res, "o-", ms=3, lw=0.7,
            label=f"guest residual (stdev {guest_res.std():.1f} frames)",
            color="#ff7f0e")
    ax.axhline(0, color="k", lw=0.5)
    ax.set_title("선형 추세 잔차 (작을수록 audio clock 안정)")
    ax.set_xlabel("local 경과 시간 (s)")
    ax.set_ylabel("framePos residual (frames)")
    ax.legend()
    ax.grid(alpha=0.3)

    # (c) sync raw offset + trend
    ax = axes[2]
    t_rel = (sx - sx[0]) / 1000.0
    ax.plot(t_rel, sy, "o", ms=3, color="#888888", label="raw offset")
    ax.plot((sx_g - sx[0]) / 1000.0, sy_g, "o", ms=3, color="#1f77b4",
            label="RTT<=median")
    fit_y = sync_slope * sx + sync_icp
    ax.plot(t_rel, fit_y, "-", color="red", lw=1.2,
            label=f"linear fit: {sync_slope*1000:+.3f} ms/s")
    ax.set_title("Wall clock offset 추세 (sync t1 vs raw_offset)")
    ax.set_xlabel("경과 시간 (s)")
    ax.set_ylabel("raw offset (ms)")
    ax.legend()
    ax.grid(alpha=0.3)

    plt.tight_layout()
    png = OUT / "drift.png"
    plt.savefig(png, dpi=120)
    print()
    print(f"PNG saved: {png}")

    # ── 6) 요약 한 덩어리로 출력 ─
    print()
    print("=" * 60)
    print("요약")
    print("=" * 60)
    print(f"세션 길이: host {(hx.max() - hx.min())/1000:.1f}s / "
          f"guest {(gx.max() - gx.min())/1000:.1f}s / "
          f"sync {(sx.max() - sx.min())/1000:.1f}s")
    print(f"Host  audio clock: {host_slope:.6f} frames/ms ({host_ppm:+.1f} ppm)")
    print(f"Guest audio clock: {guest_slope:.6f} frames/ms ({guest_ppm:+.1f} ppm)")
    print(f"상대 drift: {rel_ppm:+.1f} ppm "
          f"= {abs(rel_ppm) * 60 / 1000:.1f} ms/분 "
          f"= {abs(rel_ppm) * 1800 / 1000:.1f} ms/30분")
    print(f"Wall clock drift: {sync_ppm:+.1f} ppm (sync raw offset trend)")


if __name__ == "__main__":
    main()
