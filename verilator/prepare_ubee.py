#!/usr/bin/env python3
"""Copy the uBee RTL from a clone of GSTL-ITU/uBee and make it Verilator friendly.

The uBee IP is not part of this repository. This script copies IP/uBee_soc/src
from your own clone and applies two small, behaviour-preserving edits that
Verilator 5.020 needs:

  1. default values on input ports (`input logic x = '0`) are removed
     (the wrapper always drives these ports),
  2. the branch predictor table is written as a packed array, so the reset
     loop becomes one assignment (Verilator does not accept a non-blocking
     assignment to an unpacked array inside a loop).

usage: python3 prepare_ubee.py <path to uBee clone> <output dir>
"""
import re
import shutil
import sys
from pathlib import Path

src = Path(sys.argv[1]) / "IP" / "uBee_soc" / "src"
out = Path(sys.argv[2])
if not src.is_dir():
    sys.exit("cannot find %s - is this a clone of https://github.com/GSTL-ITU/uBee ?" % src)

out.mkdir(parents=True, exist_ok=True)
for f in src.iterdir():
    if f.suffix in (".sv", ".svh"):
        shutil.copy(f, out / f.name)

# 1) port default values
port_default = re.compile(r"^(\s*input\s+logic\b[^=;\n]*?)\s*=\s*[^,\n)]+(\s*,?)\s*$", re.M)
for f in out.glob("*.sv"):
    text = f.read_text()
    new = port_default.sub(r"\1\2", text)
    if new != text:
        f.write_text(new)
        print("removed port defaults:", f.name)

# 2) branch predictor table
bp = out / "uBee_branch_predictor.sv"
text = bp.read_text()
text = text.replace("logic [1:0] counter_table [BP_ENTRIES-1:0];",
                    "logic [BP_ENTRIES-1:0][1:0] counter_table;")
text = re.sub(r"for \(int unsigned entry = 0; entry < BP_ENTRIES; entry\+\+\) begin\s*"
              r"counter_table\[entry\] <= BP_WNT;\s*end",
              "counter_table <= {BP_ENTRIES{BP_WNT}};", text)
if "counter_table <= {BP_ENTRIES{BP_WNT}};" not in text:
    sys.exit("branch predictor edit failed - the uBee RTL may have changed")
bp.write_text(text)
print("packed branch predictor table:", bp.name)
print("uBee RTL ready in", out)
