#!/usr/bin/env bash
# Assembles hw2.s with the course rv32 tool (rv32 asm + ubee.toml memory map).
# usage:  sw/build.sh          writes hw2_imem.mem and hw2_dmem.mem
#         sw/build.sh check    assembles into a temp folder and compares with the committed files
# Set RV32 to the rv32 binary if it is not in PATH.
set -euo pipefail
cd "$(dirname "$0")"
RV32=${RV32:-rv32}
if [ "${1:-}" = "check" ]; then
    T=$(mktemp -d)
    "$RV32" asm hw2.s --devices ubee.toml --pad -o "$T/hw2_imem.mem" --dmem "$T/hw2_dmem.mem"
    cmp hw2_imem.mem "$T/hw2_imem.mem"
    cmp hw2_dmem.mem "$T/hw2_dmem.mem"
    echo "memory images are up to date"
else
    "$RV32" asm hw2.s --devices ubee.toml --pad -o hw2_imem.mem --dmem hw2_dmem.mem
fi
