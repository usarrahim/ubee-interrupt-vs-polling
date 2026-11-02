#!/usr/bin/env python3
"""Main analysis of the 19 experiments of sim/tb_hw2.sv.

usage: python3 analysis/analyze.py <sim_log.txt> <output dir>
writes <out>/results.csv, <out>/fig_loss_latency.png, <out>/fig_missed.png
"""
import csv
import sys
from pathlib import Path

from ubee_log import read_log, add_metrics, check
from plot_style import plt, COLORS, LABELS, save

log, out = sys.argv[1], Path(sys.argv[2] if len(sys.argv) > 2 else ".")
out.mkdir(parents=True, exist_ok=True)

runs, texts = read_log(log)
w_ref, loop = add_metrics(runs)
print("experiments:", len(runs), "| reference work W_ref =", w_ref, "| one loop = %.1f cycles" % loop)
for name, passed in check(runs, texts):
    print("  [%s] %s" % ("ok" if passed else "FAIL", name))

cols = ["exp", "mode", "period", "cycles", "time_ms", "retired", "cpi", "irq_taken", "axi_wait", "work",
        "cpu_loss", "evt_cnt", "ack_cnt", "miss_cnt", "miss_pct", "lat_avg", "lat_max", "sw_count", "interval"]
with open(out / "results.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(cols)
    for r in runs:
        w.writerow([round(r[c], 2) if isinstance(r[c], float) else r[c] for c in cols])
print("table:", out / "results.csv")


def series(mode):
    s = sorted([r for r in runs if r["mode"] == mode and r["period"] > 0], key=lambda r: r["period"])
    return [r["period"] for r in s], s


fig, ax = plt.subplots(1, 2, figsize=(10, 3.8))
for m, mk in (("poll", "o"), ("irq", "s"), ("irq_slow", "^")):
    p, s = series(m)
    ax[0].plot(p, [r["cpu_loss"] for r in s], marker=mk, color=COLORS[m], label=LABELS[m])
for m, mk in (("poll", "o"), ("irq", "s")):
    p, s = series(m)
    ax[1].plot(p, [r["lat_avg"] for r in s], marker=mk, color=COLORS[m], label=LABELS[m] + " (avg)")
    ax[1].plot(p, [r["lat_max"] for r in s], marker=mk, color=COLORS[m], ls=":", mfc="white",
               label=LABELS[m] + " (max)")
for a in ax:
    a.set_xscale("log")
    a.set_xlabel("Event period (clock cycles)")
ax[0].set_ylabel("CPU loss (%)")
ax[0].set_title("CPU loss")
ax[1].set_ylabel("Event to ACK latency (cycles)")
ax[1].set_title("Response latency")
ax[0].legend()
ax[1].set_ylim(0, 195)
ax[1].legend(fontsize=8, ncol=2, loc="upper center")
save(fig, out / "fig_loss_latency.png")

fig, ax = plt.subplots(figsize=(5.2, 3.5))
for m, mk in (("poll", "o"), ("irq", "s")):
    p, s = series(m)
    ax.plot(p, [r["miss_pct"] for r in s], marker=mk, color=COLORS[m], label=LABELS[m])
ax.set_xscale("log")
ax.set_xlabel("Event period (clock cycles)")
ax.set_ylabel("Missed events (%)")
ax.set_title("Missed events")
ax.legend()
save(fig, out / "fig_missed.png")
