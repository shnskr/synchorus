#!/usr/bin/env python3
"""
acoustic 측정용 음원 생성 — 5ms chirp(1k→4kHz) 1초 주기.

목적: 호스트·게스트가 이 파일을 P2P 동기 재생 → 맥북 마이크로 녹음 →
analyze.py가 두 폰 click 시차를 matched filter로 측정해 음향 sync 오차(부호+크기) 확정.

왜 chirp(click 아님): 5ms chirp는 pulse-compression으로 cross-correlation peak가
순톤·임펄스보다 날카로움 → 20ms 시차도 sub-ms 정밀. 1k~4kHz는 폰 스피커/마이크
대역 안전 구간.

사용: python3 gen_chirp.py [out.wav] [duration_sec]
기본: scripts/acoustic/measure_chirp.wav, 60초
"""
import sys
import numpy as np
from scipy.io import wavfile

SR = 48000
PERIOD = 1.0          # 비프 주기 (초)
CHIRP_MS = 5.0        # chirp 길이
F0, F1 = 1000.0, 4000.0
AMP = 0.7             # 클리핑 마진

out = sys.argv[1] if len(sys.argv) > 1 else "scripts/acoustic/measure_chirp.wav"
dur = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0

n_chirp = int(CHIRP_MS / 1000 * SR)
t = np.arange(n_chirp) / SR
# linear chirp + Hann window (click 노이즈/스펙트럼 누설 억제)
phase = 2 * np.pi * (F0 * t + (F1 - F0) / (2 * (CHIRP_MS / 1000)) * t**2)
chirp = np.sin(phase) * np.hanning(n_chirp)

total = int(dur * SR)
x = np.zeros(total, dtype=np.float32)
period_n = int(PERIOD * SR)
for start in range(0, total - n_chirp, period_n):
    x[start:start + n_chirp] += (AMP * chirp).astype(np.float32)

wavfile.write(out, SR, x)
n_beeps = len(range(0, total - n_chirp, period_n))
print(f"생성: {out}")
print(f"  sr={SR} dur={dur}s chirp={CHIRP_MS}ms({F0:.0f}->{F1:.0f}Hz) period={PERIOD}s beeps={n_beeps}")
