# hw2.s - EHB326E HW2: Interrupt Performance Effect on UART
# Abdurrahim Yilmaz - 820220519
#
# The program sends the opening of "A Tale of Two Cities" over the UART.
# At the same time evt_gen (PL) makes periodic events. The events are
# handled with polling or with an interrupt. The mode is read from GPIO IN.
#
# GPIO IN (set by the testbench):
#   bit 31    : 0 = polling, 1 = interrupt
#   bit 30    : 1 = events on
#   bit 29    : 1 = slow ISR (saves registers on a stack)
#   bit 28    : 1 = blocking UART (wait while the TX FIFO is full)
#   bit 19..0 : event period (clock cycles)
#
# Task for every event (same in both modes):
#   ACK to evt_gen, read time (CLINT mtime), save time, event_count + 1
#
# The main loop does not wait for the UART. If the TX FIFO is full it
# skips the write and does some work (work counter). The time spent for
# the events is lost from this work, so the work counter shows the CPU loss.

        .equ PLIC_BASE,  0x40001000
        .equ GPIO_BASE,  0x40002000
        .equ UART_BASE,  0x40004000
        .equ MON_BASE,   0x40005000
        .equ EVG_BASE,   0x60000000
        .equ MTIME,      0x40000FF8
        .equ STACK_TOP,  0x20010000

        .data
text:
        .ascii "A TALE OF TWO CITIES\r\n"
        .ascii "by Charles Dickens\r\n\r\n"
        .ascii "Book the First--Recalled to Life\r\n"
        .ascii "Chapter I. The Period\r\n\r\n"
        .ascii "It was the best of times, it was the worst of times, it was the age\r\n"
        .ascii "of wisdom, it was the age of foolishness, it was the epoch of belief,\r\n"
        .ascii "it was the epoch of incredulity, it was the season of Light, it was\r\n"
        .ascii "the season of Darkness, it was the spring of hope, it was the winter\r\n"
        .ascii "of despair, we had everything before us, we had nothing before us, we\r\n"
        .ascii "were all going direct to Heaven, we were all going direct the other\r\n"
        .ascii "way--in short, the period was so far like the present period, that\r\n"
        .ascii "some of its noisiest authorities insisted on its being received, for\r\n"
        .ascii "good or for evil, in the superlative degree of comparison only.\r\n"
text_end:
        .ascii "\r\nRESULT:"
res_end:
        .align 2
event_count: .word 0          # number of handled events
last_time:   .word 0          # time stamp of the last event
mon_cal:     .word 0          # cost of an empty monitor measurement
isr_stack:   .space 128
isr_stack_top:

        .text
        .globl _start
_start:
        li   sp, STACK_TOP
        li   s1, UART_BASE
        li   s2, MON_BASE
        li   s3, EVG_BASE
        li   s4, PLIC_BASE

        # read settings
        li   t0, GPIO_BASE
        lw   s11, 0(t0)               # s11 = settings word
        srli s10, s11, 31             # s10 = mode (0 poll, 1 irq)
        srli s0, s11, 28
        andi s0, s0, 1                # s0 = blocking UART

        # clear variables (DMEM is not cleared by reset)
        la   t0, event_count
        sw   zero, 0(t0)
        la   t0, last_time
        sw   zero, 0(t0)

        # UART: 100 MHz / 434 = 230400 baud
        li   t0, 434
        sw   t0, 12(s1)
        li   t0, 1
        sw   t0, 8(s1)                # TX enable

        # evt_gen period
        li   t0, 0xFFFFF
        and  t0, s11, t0
        sw   t0, 4(s3)

        beqz s10, setup_done          # no interrupt setup in polling mode

        # interrupt setup
        la   t0, isr_fast
        srli t1, s11, 29
        andi t1, t1, 1
        beqz t1, set_vec
        la   t0, isr_slow
set_vec:
        csrw mtvec, t0
        la   t0, isr_stack_top
        csrw mscratch, t0             # stack of the slow ISR
        li   t0, 1
        sw   t0, 0x004(s4)            # PLIC source 1 priority = 1
        li   t0, 3
        sw   t0, 0x104(s4)            # source 1: level (high) mode
        sw   zero, 0x300(s4)          # threshold = 0
        li   t0, 2
        sw   t0, 0x180(s4)            # enable source 1
        li   t0, 0x800
        csrs mie, t0                  # MEIE: external interrupts on
        csrsi mstatus, 8              # MIE: global interrupt enable
setup_done:

        # evt_gen CTRL value: EN (if events on) + IRQ_EN (irq mode)
        li   s9, 0
        srli t0, s11, 30
        andi t0, t0, 1
        beqz t0, ctrl_done
        li   s9, 1
        beqz s10, ctrl_done
        li   s9, 3
ctrl_done:

        # cost of the monitor itself (empty measurement)
        li   t0, 4
        sw   t0, 0(s2)                # CLEAR
        li   t0, 1
        li   t1, 3
        sw   t0, 0(s2)                # ENABLE
        sw   t1, 0(s2)                # FREEZE
        lw   t0, 4(s2)                # CYCLES
        la   t1, mon_cal
        sw   t0, 0(t1)

        la   s5, text                 # s5: next character
        la   s6, text_end             # s6: end of text
        li   s7, 0                    # s7: work counter

        # ===== measurement starts =====
        li   t0, 4
        sw   t0, 0(s2)                # monitor CLEAR
        li   t0, 1
        sw   t0, 0(s2)                # monitor ENABLE
        sw   s9, 0(s3)                # start evt_gen

main_loop:
        bnez s10, no_poll             # no polling in interrupt mode
        lw   t0, 8(s3)                # read evt_gen STATUS
        andi t0, t0, 1
        beqz t0, no_poll
        # --- event: do the task ---
        li   t0, 1
        sw   t0, 8(s3)                # ACK
        li   t0, MTIME
        lw   t1, 0(t0)                # time stamp
        la   t2, last_time
        sw   t1, 0(t2)
        la   t2, event_count
        lw   t3, 0(t2)
        addi t3, t3, 1
        sw   t3, 0(t2)
no_poll:
        # --- UART: write one character if possible ---
        bgeu s5, s6, uart_skip        # all text is sent
        bnez s0, uart_wait            # blocking mode
        lw   t0, 4(s1)                # STATUS
        andi t0, t0, 8                # TX_FULL
        bnez t0, uart_skip            # FIFO full: do not wait
        j    uart_put
uart_wait:
        lw   t0, 4(s1)
        andi t0, t0, 8
        bnez t0, uart_wait            # wait until the FIFO has space
uart_put:
        lbu  t1, 0(s5)
        sw   t1, 0(s1)
        addi s5, s5, 1
uart_skip:
        # --- work: a small calculation loop ---
        li   t2, 8
work:
        addi t3, t3, 3
        xor  t4, t4, t3
        addi t2, t2, -1
        bnez t2, work
        addi s7, s7, 1                # work counter
        # --- finished? (text sent and UART empty) ---
        bltu s5, s6, main_loop
        lw   t0, 4(s1)
        andi t0, t0, 0x14             # TX_EMPTY | TX_BUSY
        li   t1, 4
        bne  t0, t1, main_loop

        # ===== measurement ends =====
        li   t0, 3
        sw   t0, 0(s2)                # monitor FREEZE
        sw   zero, 0(s3)              # stop evt_gen
        csrci mstatus, 8              # interrupts off

        # print results: RESULT:mode,period,cycles,retired,irq,axi_wait,work,
        #   events,ack,missed,lat_sum,lat_max,event_count,cal,last_time
        la   s5, text_end
        la   s6, res_end
        jal  ra, puts
        srli a0, s11, 28              # mode bits (settings >> 28)
        jal  ra, put_num
        li   t0, 0xFFFFF
        and  a0, s11, t0
        srli t1, s11, 30
        andi t1, t1, 1
        bnez t1, per_ok
        li   a0, 0                    # events off: period 0
per_ok:
        jal  ra, put_num_c
        lw   a0, 4(s2)                # CYCLES
        jal  ra, put_num_c
        lw   a0, 8(s2)                # RETIRED
        jal  ra, put_num_c
        lw   a0, 0x3C(s2)             # IRQ_TAKEN
        jal  ra, put_num_c
        lw   a0, 0x34(s2)             # AXI_WAIT
        jal  ra, put_num_c
        mv   a0, s7                   # work
        jal  ra, put_num_c
        lw   a0, 0x0C(s3)             # EVT_CNT
        jal  ra, put_num_c
        lw   a0, 0x10(s3)             # ACK_CNT
        jal  ra, put_num_c
        lw   a0, 0x14(s3)             # MISS_CNT
        jal  ra, put_num_c
        lw   a0, 0x18(s3)             # LAT_SUM
        jal  ra, put_num_c
        lw   a0, 0x1C(s3)             # LAT_MAX
        jal  ra, put_num_c
        la   t0, event_count
        lw   a0, 0(t0)
        jal  ra, put_num_c
        la   t0, mon_cal
        lw   a0, 0(t0)
        jal  ra, put_num_c
        la   t0, last_time
        lw   a0, 0(t0)
        jal  ra, put_num_c
        li   a0, 13
        jal  ra, putc
        li   a0, 10
        jal  ra, putc
        li   a0, 69                   # "END"
        jal  ra, putc
        li   a0, 78
        jal  ra, putc
        li   a0, 68
        jal  ra, putc
        li   a0, 10
        jal  ra, putc
halt:
        j    halt

# ---------- helper functions (used after the measurement) ----------
putc:                                 # send character in a0
        lw   t0, 4(s1)
        andi t0, t0, 8
        bnez t0, putc
        sw   a0, 0(s1)
        ret

puts:                                 # send bytes from s5 to s6
        mv   s8, ra
puts_loop:
        bgeu s5, s6, puts_end
        lbu  a0, 0(s5)
        jal  ra, putc
        addi s5, s5, 1
        j    puts_loop
puts_end:
        mv   ra, s8
        ret

put_num_c:                            # comma, then the number
        mv   s8, ra
        mv   s9, a0
        li   a0, 44
        jal  ra, putc
        mv   a0, s9
        mv   ra, s8
put_num:                              # send a0 as a decimal number
        mv   s8, ra
        addi sp, sp, -16
        mv   t5, sp
        li   t6, 10
        mv   a1, a0
num_div:
        remu t2, a1, t6
        addi t2, t2, 48
        sb   t2, 0(t5)
        addi t5, t5, 1
        divu a1, a1, t6
        bnez a1, num_div
num_out:
        addi t5, t5, -1
        lbu  a0, 0(t5)
        jal  ra, putc
        bne  t5, sp, num_out
        addi sp, sp, 16
        mv   ra, s8
        ret

# ---------- interrupt handlers ----------
# Fast ISR: uBee changes to a second register bank (shadow bank) in a trap,
# so the ISR does not need to save registers.
isr_fast:
        li   t0, EVG_BASE
        li   t1, 1
        sw   t1, 8(t0)                # ACK
        li   t0, PLIC_BASE
        lw   t2, 0x304(t0)            # PLIC claim
        lw   t3, -8(t0)               # mtime (0x40000FF8)
        la   t4, last_time
        sw   t3, 0(t4)
        la   t4, event_count
        lw   t5, 0(t4)
        addi t5, t5, 1
        sw   t5, 0(t4)
        sw   t2, 0x308(t0)            # PLIC complete
        mret

# Slow ISR: like an ISR on a normal RISC-V core, it saves the registers
# it uses on a stack and loads them back at the end.
isr_slow:
        csrrw sp, mscratch, sp        # change to the ISR stack
        addi sp, sp, -24
        sw   t0, 0(sp)
        sw   t1, 4(sp)
        sw   t2, 8(sp)
        sw   t3, 12(sp)
        sw   t4, 16(sp)
        sw   t5, 20(sp)
        li   t0, EVG_BASE
        li   t1, 1
        sw   t1, 8(t0)                # ACK
        li   t0, PLIC_BASE
        lw   t2, 0x304(t0)            # PLIC claim
        lw   t3, -8(t0)               # mtime
        la   t4, last_time
        sw   t3, 0(t4)
        la   t4, event_count
        lw   t5, 0(t4)
        addi t5, t5, 1
        sw   t5, 0(t4)
        sw   t2, 0x308(t0)            # PLIC complete
        lw   t0, 0(sp)
        lw   t1, 4(sp)
        lw   t2, 8(sp)
        lw   t3, 12(sp)
        lw   t4, 16(sp)
        lw   t5, 20(sp)
        addi sp, sp, 24
        csrrw sp, mscratch, sp        # back to the old sp
        mret
