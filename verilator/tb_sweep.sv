`timescale 1ns / 1ps
// tb_sweep.sv - extended sweep for Verilator (not used in the Vivado flow)
// Same idea as sim/tb_hw2.sv, but the experiment list is read from a file
// (sweep_list.hex, one 32-bit setting word per line) and the latency of
// every answered event is written to lat_log.txt (first LAT_CAP events of
// each experiment). The latency is read from evt_gen with a hierarchical
// reference, so the program and the hardware are the same as in Vivado.

module tb_sweep;
    localparam integer BIT_CLK = 434;
    localparam integer TIMEOUT = 8_000_000;
    localparam integer LAT_CAP = 2000;
    localparam integer MAX_EXP = 256;

    reg         clk   = 1'b0;
    reg         rst_n = 1'b0;
    reg  [31:0] cfg   = 32'd0;
    wire        uart_tx;

    always #5 clk = ~clk;

    hw2_system_wrapper dut (
        .clk_i_0 (clk), .rst_ni_0 (rst_n), .uart_tx_o_0 (uart_tx), .gpio_in_i_0 (cfg)
    );

    reg [31:0] exp_list [0:MAX_EXP-1];
    integer n_exp;

    // ---------------- UART receiver ----------------
    integer i, fd, fl;
    reg [7:0]  ch;
    reg [23:0] last3;

    initial begin
        fd = $fopen("sweep_log.txt", "w");
        fl = $fopen("lat_log.txt", "w");
        $fwrite(fl, "exp,cfg,latency\n");
        forever begin
            @(negedge uart_tx);
            repeat (BIT_CLK/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (BIT_CLK) @(posedge clk);
                ch[i] = uart_tx;
            end
            repeat (BIT_CLK) @(posedge clk);
            $fwrite(fd, "%c", ch);
            last3 = {last3[15:0], ch};
        end
    end

    // ---------------- latency of every ACK ----------------
    integer e = 0, n_lat = 0;
    always @(posedge clk) begin
        if (rst_n && dut.evt_gen_0.ack && n_lat < LAT_CAP) begin
            $fwrite(fl, "%0d,%h,%0d\n", e, cfg, dut.evt_gen_0.lat_now);
            n_lat = n_lat + 1;
        end
    end

    // ---------------- main flow ----------------
    integer t;
    initial begin
        for (n_exp = 0; n_exp < MAX_EXP; n_exp = n_exp + 1) exp_list[n_exp] = 32'hFFFF_FFFF;
        $readmemh("sweep_list.hex", exp_list);
        n_exp = 0;
        while (n_exp < MAX_EXP && exp_list[n_exp] != 32'hFFFF_FFFF) n_exp = n_exp + 1;
        $display("sweep: %0d experiments", n_exp);

        for (e = 0; e < n_exp; e = e + 1) begin
            @(negedge clk);
            cfg   = exp_list[e];
            rst_n = 1'b0;
            last3 = 24'd0;
            n_lat = 0;
            repeat (20) @(negedge clk);
            rst_n = 1'b1;
            $display("experiment %0d / %0d, cfg = %h", e, n_exp, cfg);
            $fwrite(fd, "\n===== Experiment %0d, cfg = %h, t = %0d us =====\n", e, cfg, $time/1000);
            for (t = 0; t < TIMEOUT && last3 != "END"; t = t + 1)
                @(posedge clk);
            if (last3 != "END")
                $fwrite(fd, "\nTIMEOUT\n");
        end
        $fclose(fd);
        $fclose(fl);
        $display("All experiments done.");
        $finish;
    end
endmodule
