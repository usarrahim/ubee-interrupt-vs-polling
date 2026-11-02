#!/usr/bin/env bash
# Extended sweep with Verilator (24 periods x polling/interrupt + slow ISR + references).
# usage: verilator/run_sweep.sh <path to GSTL-ITU/uBee clone> [build dir]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
UBEE=$(cd "$1" && pwd)
BUILD=${2:-$REPO/build/verilator_sweep}

mkdir -p "$BUILD"
python3 "$REPO/verilator/prepare_ubee.py" "$UBEE" "$BUILD/ubee_rtl"
SRC=$BUILD/ubee_rtl

verilator --binary -j 0 -O3 --timing -Wno-fatal -Wno-lint -Wno-style \
    -I"$SRC" --top-module tb_sweep -Mdir "$BUILD/obj" \
    "$SRC/uBee_defs.svh" "$SRC"/*.sv \
    "$REPO/hw/evt_gen.v" "$REPO/verilator/hw2_system_wrapper.sv" "$REPO/verilator/tb_sweep.sv" \
    > "$BUILD/build.log" 2>&1 || { tail -30 "$BUILD/build.log"; exit 1; }

cp "$REPO/sw/hw2_imem.mem" "$REPO/sw/hw2_dmem.mem" "$BUILD/"
python3 "$REPO/verilator/make_sweep_list.py" "$BUILD/sweep_list.hex"
cd "$BUILD"
start=$(date +%s)
./obj/Vtb_sweep
echo "simulation time: $(( $(date +%s) - start )) s"
echo "logs: $BUILD/sweep_log.txt  $BUILD/lat_log.txt"
