`timescale 1ns / 1ps
// tb_hw2.sv - EHB326E HW2 testbench
// Abdurrahim Yilmaz - 820220519
//
// For every setting in the experiment list:
//   1) put the setting on GPIO IN and reset the system
//   2) read the UART output, write it to the console and to sim_log.txt
//   3) when the program prints "END", go to the next experiment
//
// Setting word: bit31 = interrupt mode, bit30 = events on,
//               bit29 = slow ISR, bit28 = blocking UART,
//               bit19..0 = event period (cycles)

module tb_hw2;
    localparam integer BIT_CLK = 434;          // UART bit time (cycles)
    localparam integer TIMEOUT = 8_000_000;    // max cycles for one experiment

    reg         clk   = 1'b0;
    reg         rst_n = 1'b0;
    reg  [31:0] cfg   = 32'd0;
    wire        uart_tx;

    always #5 clk = ~clk;                      // 100 MHz

    hw2_system_wrapper dut (
        .clk_i_0     (clk),
        .rst_ni_0    (rst_n),
        .uart_tx_o_0 (uart_tx),
        .gpio_in_i_0 (cfg)
    );

    // ---------------- experiment list ----------------
    localparam [31:0] POLL = 32'h4000_0000;    // polling, events on
    localparam [31:0] IRQ  = 32'hC000_0000;    // interrupt, events on
    localparam [31:0] SLOW = 32'hE000_0000;    // interrupt, slow ISR

    integer n_exp = 19;
    reg [31:0] exp_list [0:18];
    initial begin
        exp_list[0]  = 32'h0000_0000;          // polling, no events
        exp_list[1]  = 32'h8000_0000;          // interrupt, no events (reference)
        exp_list[2]  = POLL | 20000;   exp_list[3]  = IRQ | 20000;
        exp_list[4]  = POLL | 5000;    exp_list[5]  = IRQ | 5000;
        exp_list[6]  = POLL | 1000;    exp_list[7]  = IRQ | 1000;
        exp_list[8]  = POLL | 500;     exp_list[9]  = IRQ | 500;
        exp_list[10] = POLL | 200;     exp_list[11] = IRQ | 200;
        exp_list[12] = POLL | 100;     exp_list[13] = IRQ | 100;
        exp_list[14] = POLL | 50;      exp_list[15] = IRQ | 50;
        exp_list[16] = SLOW | 1000;    exp_list[17] = SLOW | 200;
        exp_list[18] = 32'h9000_0000;          // blocking UART, no events
    end

    // ---------------- UART receiver ----------------
    integer i, fd;
    reg [7:0]  ch;
    reg [23:0] last3;                          // last 3 characters (for "END")

    initial begin
        fd = $fopen("sim_log.txt", "w");
        forever begin
            @(negedge uart_tx);                // start bit
            repeat (BIT_CLK/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (BIT_CLK) @(posedge clk);
                ch[i] = uart_tx;
            end
            repeat (BIT_CLK) @(posedge clk);   // stop bit
            $write("%c", ch);
            $fwrite(fd, "%c", ch);
            last3 = {last3[15:0], ch};
        end
    end

    // ---------------- main flow ----------------
    integer e, t;

    initial begin
        for (e = 0; e < n_exp; e = e + 1) begin
            @(negedge clk);
            cfg   = exp_list[e];
            rst_n = 1'b0;
            last3 = 24'd0;
            repeat (20) @(negedge clk);
            rst_n = 1'b1;
            $display("\n===== Experiment %0d, cfg = %h, t = %0d us =====", e, cfg, $time/1000);
            $fwrite(fd, "\n===== Experiment %0d, cfg = %h, t = %0d us =====\n", e, cfg, $time/1000);

            for (t = 0; t < TIMEOUT && last3 != "END"; t = t + 1)
                @(posedge clk);
            if (last3 != "END") begin
                $display("\nTIMEOUT (experiment %0d)", e);
                $fwrite(fd, "\nTIMEOUT\n");
            end
        end
        $fclose(fd);
        $display("\nAll experiments done.");
        $finish;
    end
endmodule
