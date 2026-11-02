| Exp | Setting | Mode | Period | CYCLES | XSim vs Verilator |
|---|---|---|---|---|---|
| 0 | `00000000` | poll | 0 | 3,146,593 | identical |
| 1 | `80000000` | irq | 0 | 3,146,565 | identical |
| 2 | `40004e20` | poll | 20000 | 3,146,565 | identical |
| 3 | `c0004e20` | irq | 20000 | 3,146,633 | identical |
| 4 | `40001388` | poll | 5000 | 3,146,614 | identical |
| 5 | `c0001388` | irq | 5000 | 3,146,599 | identical |
| 6 | `400003e8` | poll | 1000 | 3,146,625 | identical |
| 7 | `c00003e8` | irq | 1000 | 3,146,611 | identical |
| 8 | `400001f4` | poll | 500 | 3,146,554 | identical |
| 9 | `c00001f4` | irq | 500 | 3,146,640 | identical |
| 10 | `400000c8` | poll | 200 | 3,146,571 | identical |
| 11 | `c00000c8` | irq | 200 | 3,146,573 | identical |
| 12 | `40000064` | poll | 100 | 3,146,626 | identical |
| 13 | `c0000064` | irq | 100 | 3,146,678 | identical |
| 14 | `40000032` | poll | 50 | 3,146,626 | identical |
| 15 | `c0000032` | irq | 50 | 3,148,161 | identical |
| 16 | `e00003e8` | irq_slow | 1000 | 3,146,631 | identical |
| 17 | `e00000c8` | irq_slow | 200 | 3,146,607 | identical |
| 18 | `90000000` | blocking | 0 | 3,146,593 | identical |

19 / 19 experiments have identical counters (all 15 RESULT fields).
