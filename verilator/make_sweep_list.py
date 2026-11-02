#!/usr/bin/env python3
"""Writes sweep_list.hex: the setting words of the extended sweep.
Setting word: bit31 interrupt, bit30 events on, bit29 slow ISR, bit28 blocking UART, bit19..0 period."""
import sys

POLL, IRQ, SLOW = 0x40000000, 0xC0000000, 0xE0000000
periods = [50, 60, 70, 80, 90, 100, 120, 140, 170, 200, 250, 300, 350, 400, 500,
           650, 800, 1000, 1500, 2000, 3000, 5000, 10000, 20000]
slow_periods = [120, 140, 170, 200, 250, 300, 400, 500, 1000, 2000, 5000]

words = [0x00000000, 0x80000000, 0x90000000]          # references: poll / irq / blocking UART, no events
for p in periods:
    words += [POLL | p, IRQ | p]
words += [SLOW | p for p in slow_periods]

out = sys.argv[1] if len(sys.argv) > 1 else "sweep_list.hex"
with open(out, "w") as f:
    for w in words:
        f.write("%08x\n" % w)
print("%d experiments -> %s" % (len(words), out))
