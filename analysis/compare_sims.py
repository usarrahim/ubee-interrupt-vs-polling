#!/usr/bin/env python3
"""Compares the RESULT lines of two simulation logs (for example Vivado XSim and Verilator).

usage: python3 analysis/compare_sims.py <log A> <log B> [markdown output]
exit code 0 = every experiment has exactly the same counters in both logs.
"""
import sys
from ubee_log import read_log, FIELDS

a_path, b_path = sys.argv[1], sys.argv[2]
a, _ = read_log(a_path)
b, _ = read_log(b_path)
rows, same = [], 0
for ra, rb in zip(a, b):
    if ra["timeout"] or rb["timeout"]:
        eq = ra["timeout"] == rb["timeout"]
    else:
        eq = all(ra[f] == rb[f] for f in FIELDS)
    same += eq
    rows.append("| %d | `%08x` | %s | %s | %s | %s |" % (
        ra["exp"], ra["cfg"], ra["mode"], ra.get("period", 0),
        "-" if ra["timeout"] else "{:,}".format(ra["cycles"]), "identical" if eq else "**different**"))
ok = same == len(a) == len(b)
text = ["| Exp | Setting | Mode | Period | CYCLES | XSim vs Verilator |", "|---|---|---|---|---|---|"] + rows
text.append("")
text.append("%d / %d experiments have identical counters (all %d RESULT fields)." % (same, len(a), len(FIELDS)))
print("\n".join(text))
if len(sys.argv) > 3:
    open(sys.argv[3], "w").write("\n".join(text) + "\n")
sys.exit(0 if ok else 1)
