"""Helpers to read the UART logs written by the testbenches.

Every experiment in a log starts with
    ===== Experiment <n>, cfg = <hex>, t = <us> us =====
and ends with the line printed by sw/hw2.s
    RESULT:mode,period,CYCLES,RETIRED,IRQ_TAKEN,AXI_WAIT,work,EVT_CNT,ACK_CNT,
           MISS_CNT,LAT_SUM,LAT_MAX,event_count,mon_cal,last_time
    END
An experiment that does not reach END is marked with TIMEOUT by the testbench.
"""
import re

FIELDS = ["mode_bits", "period", "cycles", "retired", "irq_taken", "axi_wait", "work",
          "evt_cnt", "ack_cnt", "miss_cnt", "lat_sum", "lat_max", "sw_count", "mon_cal", "last_time"]

# setting word >> 28
MODE_NAMES = {0: "poll", 4: "poll", 8: "irq", 12: "irq", 14: "irq_slow", 9: "blocking"}

CLOCK_HZ = 100e6


def mode_of_cfg(cfg):
    return MODE_NAMES.get(cfg >> 28, "?")


def read_log(path):
    """Returns (runs, texts). A run is a dict; runs that timed out have 'timeout': True."""
    log = open(path, encoding="latin-1", newline="").read().replace("\r", "")
    parts = re.split(r"\n===== Experiment (\d+), cfg = ([0-9a-f]+).*?=====\n", log)
    runs, texts = [], []
    for i in range(1, len(parts), 3):
        exp, cfg, body = int(parts[i]), int(parts[i + 1], 16), parts[i + 2]
        m = re.search(r"RESULT:([0-9,]+)\nEND", body)
        if m is None:
            runs.append({"exp": exp, "cfg": cfg, "mode": mode_of_cfg(cfg),
                         "period": cfg & 0xFFFFF if (cfg >> 30) & 1 else 0, "timeout": True})
            continue
        r = dict(zip(FIELDS, (int(x) for x in m.group(1).split(","))))
        r.update(exp=exp, cfg=cfg, mode=MODE_NAMES[r["mode_bits"]], timeout=False)
        runs.append(r)
        texts.append(body[:body.index("\nRESULT:")])
    return runs, texts


def add_metrics(runs):
    """CPU loss is measured against the work counter of 'interrupt mode, no events'."""
    ok = [r for r in runs if not r["timeout"]]
    ref = [r for r in ok if r["mode"] == "irq" and r["period"] == 0][0]
    w_ref = ref["work"]
    loop = ref["cycles"] / w_ref                     # cycles of one main loop turn
    for r in runs:
        if r["timeout"]:
            r["cpu_loss"] = 100.0                      # the program never finished (livelock)
            continue
        r["cpu_loss"] = 100.0 * (w_ref - r["work"]) / w_ref
        r["lost_cycles"] = (w_ref - r["work"]) * loop
        r["lat_avg"] = r["lat_sum"] / r["ack_cnt"] if r["ack_cnt"] else 0.0
        r["miss_pct"] = 100.0 * r["miss_cnt"] / r["evt_cnt"] if r["evt_cnt"] else 0.0
        r["time_ms"] = r["cycles"] / CLOCK_HZ * 1e3
        r["cpi"] = r["cycles"] / r["retired"]
        r["interval"] = r["last_time"] / r["sw_count"] if r["sw_count"] else 0.0
    return w_ref, loop


def check(runs, texts):
    """Consistency checks, returns a list of (name, passed)."""
    ok = [r for r in runs if not r["timeout"]]
    ev = [r for r in ok if r["evt_cnt"] > 0]
    return [
        ("same text in every finished experiment", all(t == texts[0] for t in texts)),
        ("EVT_CNT = ACK_CNT + MISS_CNT (+1 pending)", all(r["evt_cnt"] - r["ack_cnt"] - r["miss_cnt"] in (0, 1) for r in ev)),
        ("software event_count = ACK_CNT", all(r["sw_count"] == r["ack_cnt"] for r in ev)),
        ("interrupt mode: |IRQ_TAKEN - ACK_CNT| <= 3",
         all(abs(r["irq_taken"] - r["ack_cnt"]) <= 3 for r in ev if r["mode"] in ("irq", "irq_slow"))),
        ("polling mode: IRQ_TAKEN = 0", all(r["irq_taken"] == 0 for r in ok if r["mode"] == "poll")),
    ]
