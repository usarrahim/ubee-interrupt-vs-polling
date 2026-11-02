#!/usr/bin/env bash
# Runs sim/tb_hw2.sv (the same 19 experiments as Vivado) with Verilator.
# usage: verilator/run_tb.sh <path to GSTL-ITU/uBee clone> [build dir]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
UBEE=$(cd "$1" && pwd)
BUILD=${2:-$REPO/build/verilator_tb}

mkdir -p "$BUILD"
python3 "$REPO/verilator/prepare_ubee.py" "$UBEE" "$BUILD/ubee_rtl"
SRC=$BUILD/ubee_rtl

verilator --binary -j 0 -O3 --timing -Wno-fatal -Wno-lint -Wno-style \
    -I"$SRC" --top-module tb_hw2 -Mdir "$BUILD/obj" \
    "$SRC/uBee_defs.svh" "$SRC"/*.sv \
    "$REPO/hw/evt_gen.v" "$REPO/verilator/hw2_system_wrapper.sv" "$REPO/sim/tb_hw2.sv" \
    > "$BUILD/build.log" 2>&1 || { tail -30 "$BUILD/build.log"; exit 1; }

cp "$REPO/sw/hw2_imem.mem" "$REPO/sw/hw2_dmem.mem" "$BUILD/"
cd "$BUILD"
start=$(date +%s)
./obj/Vtb_hw2 > console.txt
echo "simulation time: $(( $(date +%s) - start )) s"
echo "log: $BUILD/sim_log.txt"
