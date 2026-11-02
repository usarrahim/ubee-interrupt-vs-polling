#!/usr/bin/env python3
"""Analysis of the extended Verilator sweep (verilator/run_sweep.sh).

usage: python3 analysis/sweep.py <sweep_log.txt> <lat_log.txt> <output dir>

What it does
  * CPU loss, latency and missed events for 24 periods (50 ... 20000 cycles)
  * a simple cost model fitted to the measurements:
        lost cycles (polling)   = L0 + c_poll * N      (L0: STATUS reads even without events)
        lost cycles (interrupt) =      c_irq  * N
    N = number of handled events. The break-even point follows from the model and
    is compared with the crossover found directly in the measurements.
  * latency histograms from the per-event latency log
"""
import csv
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

from ubee_log import read_log, add_metrics, check
from plot_style import plt, COLORS, LABELS, TEXT2, save

log, lat_log, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)

runs, texts = read_log(log)
w_ref, loop = add_metrics(runs)
print("sweep: %d experiments, W_ref = %d, one loop = %.1f cycles" % (len(runs), w_ref, loop))
for name, passed in check(runs, texts):
    print("  [%s] %s" % ("ok" if passed else "FAIL", name))
timeouts = [r for r in runs if r["timeout"]]
print("  time-outs (livelock):", [(r["mode"], r["period"]) for r in timeouts] or "none")

ok = [r for r in runs if not r["timeout"]]
ref_poll = [r for r in ok if r["mode"] == "poll" and r["period"] == 0][0]
ref_irq = [r for r in ok if r["mode"] == "irq" and r["period"] == 0][0]
T = ref_irq["cycles"]


def series(mode):
    return sorted([r for r in runs if r["mode"] == mode and r["period"] > 0], key=lambda r: r["period"])


# ---------------- model fit ----------------
def fit_origin(xs, ys):
    c = sum(x * y for x, y in zip(xs, ys)) / sum(x * x for x in xs)
    return c


def fit_line(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    c = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    return my - c * mx, c


def r2(xs, ys, f):
    my = sum(ys) / len(ys)
    ss_res = sum((y - f(x)) ** 2 for x, y in zip(xs, ys))
    ss_tot = sum((y - my) ** 2 for y in ys)
    return 1 - ss_res / ss_tot


irq_fit = [r for r in series("irq") if not r["timeout"] and r["period"] >= 100]
slow_fit = [r for r in series("irq_slow") if not r["timeout"]]
poll_fit = [r for r in series("poll") if r["miss_cnt"] == 0]

N = lambda rs: [r["ack_cnt"] for r in rs]
L = lambda rs: [r["lost_cycles"] for r in rs]
c_irq = fit_origin(N(irq_fit), L(irq_fit))
c_slow = fit_origin(N(slow_fit), L(slow_fit))
L0, c_poll = fit_line(N(poll_fit), L(poll_fit))
L0_meas = ref_poll["lost_cycles"]
model = {
    "loop_cycles": loop,
    "c_irq": c_irq, "r2_irq": r2(N(irq_fit), L(irq_fit), lambda x: c_irq * x),
    "c_slow": c_slow, "r2_slow": r2(N(slow_fit), L(slow_fit), lambda x: c_slow * x),
    "c_poll": c_poll, "L0_fit": L0, "L0_no_events": L0_meas,
    "r2_poll": r2(N(poll_fit), L(poll_fit), lambda x: L0 + c_poll * x),
}
N_be = L0 / (c_irq - c_poll)
model["breakeven_period_model"] = T / N_be

# crossover in the measurements (log-linear interpolation of loss_poll - loss_irq)
poll = {r["period"]: r for r in series("poll")}
irq = {r["period"]: r for r in series("irq")}
common = sorted(set(poll) & set(irq))
cross = None
for a, b in zip(common, common[1:]):
    da = poll[a]["cpu_loss"] - irq[a]["cpu_loss"]
    db = poll[b]["cpu_loss"] - irq[b]["cpu_loss"]
    if da < 0 <= db or da > 0 >= db:
        t = da / (da - db)
        cross = math.exp(math.log(a) + t * (math.log(b) - math.log(a)))
model["crossover_period_measured"] = cross
sat_runs = [r for r in series("poll") if r["miss_cnt"] > 0]
# polling saturates: one event per main-loop turn with an event (seen with the mtime time stamps)
model["polling_max_rate_cycles_per_event"] = min(r["interval"] for r in sat_runs) if sat_runs else 0.0
json.dump(model, open(out / "model.json", "w"), indent=2)
print("model:")
for k, v in model.items():
    print("  %-34s %s" % (k, ("%.3f" % v) if isinstance(v, float) else v))

# ---------------- table ----------------
cols = ["exp", "mode", "period", "cycles", "work", "cpu_loss", "irq_taken", "axi_wait", "evt_cnt",
        "ack_cnt", "miss_cnt", "miss_pct", "lat_avg", "lat_max", "interval", "timeout"]
with open(out / "sweep.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(cols)
    for r in runs:
        w.writerow([round(r.get(c, 0), 2) if isinstance(r.get(c), float) else r.get(c, "") for c in cols])

# ---------------- figure: CPU loss + model ----------------
fig, ax = plt.subplots(figsize=(8.6, 4.4))
ps = [p for p in common]
grid = [10 ** (math.log10(40) + i * (math.log10(25000) - math.log10(40)) / 200) for i in range(201)]


def n_of(p):
    return T / p


for m, mk in (("poll", "o"), ("irq", "s"), ("irq_slow", "^")):
    s = [r for r in series(m) if not r["timeout"]]
    ax.plot([r["period"] for r in s], [r["cpu_loss"] for r in s], marker=mk, color=COLORS[m],
            label=LABELS[m] + " (measured)", lw=1.6)
    t = [r for r in series(m) if r["timeout"]]
    if t:
        ax.plot([r["period"] for r in t], [100] * len(t), "x", color=COLORS[m], ms=9, mew=2,
                label=LABELS[m] + " (did not finish)")
# model curves (only where the model is valid)
sat = model["polling_max_rate_cycles_per_event"]
gp = [p for p in grid if p >= sat]
ax.plot(gp, [100 * (L0 + c_poll * n_of(p)) / T for p in gp], "--", color=COLORS["poll"], lw=1.1, alpha=.8)
gi = [p for p in grid if p >= 50]
ax.plot(gi, [min(100, 100 * c_irq * n_of(p) / T) for p in gi], "--", color=COLORS["irq"], lw=1.1, alpha=.8)
gs = [p for p in grid if p >= 110]
ax.plot(gs, [min(100, 100 * c_slow * n_of(p) / T) for p in gs], "--", color=COLORS["irq_slow"], lw=1.1, alpha=.8)
ax.plot([], [], "--", color=TEXT2, lw=1.1, label="cost model")
ax.axvspan(40, sat, color="#2a78d6", alpha=.06)
ax.text(44, 4, "polling misses\nevents here", fontsize=8, color=TEXT2)
if cross:
    ax.axvline(cross, color=TEXT2, lw=1, ls=":")
    ax.text(cross * 1.06, 88, "break-even\n≈ %d cycles" % round(cross, -1), fontsize=8.5, color=TEXT2)
ax.set_xscale("log")
ax.set_xlim(40, 25000)
ax.set_ylim(-3, 103)
ax.set_xlabel("Event period (clock cycles, 100 MHz)")
ax.set_ylabel("CPU loss (%)")
ax.set_title("CPU loss: 24-point sweep and cost model")
ax.legend(fontsize=8, loc="upper right")
save(fig, out / "fig_sweep_cpu_loss.png")

# ---------------- figure: latency and missed events ----------------
fig, ax = plt.subplots(1, 2, figsize=(10, 3.8))
for m, mk in (("poll", "o"), ("irq", "s"), ("irq_slow", "^")):
    s = [r for r in series(m) if not r["timeout"]]
    ax[0].plot([r["period"] for r in s], [r["lat_avg"] for r in s], marker=mk, color=COLORS[m], label=LABELS[m])
for m, mk in (("poll", "o"), ("irq", "s")):
    s = [r for r in series(m) if not r["timeout"]]
    ax[1].plot([r["period"] for r in s], [r["miss_pct"] for r in s], marker=mk, color=COLORS[m], label=LABELS[m])
for a in ax:
    a.set_xscale("log")
    a.set_xlabel("Event period (clock cycles)")
    a.legend(fontsize=8)
ax[0].set_ylabel("Average latency (cycles)")
ax[0].set_title("Average response latency")
ax[1].set_ylabel("Missed events (%)")
ax[1].set_title("Missed events")
save(fig, out / "fig_sweep_latency_missed.png")

# ---------------- figure: latency histograms ----------------
lat = defaultdict(list)
cfg_of = {}
with open(lat_log) as f:
    for row in csv.DictReader(f):
        lat[int(row["exp"])].append(int(row["latency"]))
        cfg_of[int(row["exp"])] = int(row["cfg"], 16)
by_cfg = {cfg_of[e]: v for e, v in lat.items()}
fig, ax = plt.subplots(figsize=(7.6, 3.9))
for m, base in (("poll", 0x40000000), ("irq", 0xC0000000)):
    for P, ls in ((1000, "-"), (200, "--")):
        v = sorted(by_cfg.get(base | P, []))
        if not v:
            continue
        n = len(v)
        med, p99 = v[n // 2], v[min(n - 1, int(0.99 * n))]
        ax.step(v, [(i + 1) / n for i in range(n)], where="post", color=COLORS[m], ls=ls, lw=1.8,
                label="%s, P = %d  (median %d, 99%% %d, max %d)" % (LABELS[m], P, med, p99, v[-1]))
ax.set_xlim(0, 150)
ax.set_ylim(0, 1.02)
ax.set_xlabel("Event to ACK latency (cycles)")
ax.set_ylabel("Fraction of events")
ax.set_title("Latency distribution of single events (first 2000 events)")
ax.legend(fontsize=8, loc="lower right")
save(fig, out / "fig_latency_cdf.png")

# ---------------- figure: free CPU time without events ----------------
blk = [r for r in ok if r["mode"] == "blocking"]
if blk:
    names = ["Non-blocking UART\ninterrupt mode", "Non-blocking UART\npolling mode", "Blocking UART\n(busy-wait)"]
    vals = [100.0, 100 - ref_poll["cpu_loss"], 100 - blk[0]["cpu_loss"]]
    fig, ax = plt.subplots(figsize=(6.4, 3.0))
    bars = ax.barh(names[::-1], vals[::-1], color=[COLORS["irq"], COLORS["poll"], COLORS["grey"]][::-1], height=.55)
    for b, v in zip(bars, vals[::-1]):
        ax.text(v + 1, b.get_y() + b.get_height() / 2, "%.1f %%" % v, va="center", fontsize=9)
    ax.set_xlim(0, 115)
    ax.set_xlabel("CPU time left for other work while printing (%)")
    ax.set_title("Same text, same baud rate, no events")
    ax.grid(axis="y", visible=False)
    save(fig, out / "fig_uart_wait.png")
