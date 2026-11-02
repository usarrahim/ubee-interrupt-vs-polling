`timescale 1ns / 1ps
// evt_gen.v - periodic event generator (PL side)
// Abdurrahim Yilmaz - 820220519 - EHB326E HW2
//
// Connected to uBee with AXI4-Lite (address 0x6000_0000).
// Every PERIOD cycles it makes one event and sets the PENDING bit.
// - Polling mode: the CPU reads STATUS to see the event.
// - Interrupt mode: if IRQ_EN = 1, PENDING goes to the PLIC as irq.
// The CPU writes 1 to STATUS to answer the event (ACK).
// The time from the event to the ACK (latency) is counted here in hardware.
//
// Registers:
//   0x00 CTRL     bit0 = EN (start), bit1 = IRQ_EN
//   0x04 PERIOD   event period (cycles)
//   0x08 STATUS   bit0 = PENDING (write 1 = ACK, clears it)
//   0x0C EVT_CNT  number of events
//   0x10 ACK_CNT  number of answered events
//   0x14 MISS_CNT missed events (new event while PENDING is still 1)
//   0x18 LAT_SUM  sum of latencies (cycles)
//   0x1C LAT_MAX  largest latency (cycles)

module evt_gen (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    // AXI4-Lite write channels
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // AXI4-Lite read channels
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    // to uBee ext_irq_i (bit 0 = PLIC source 1)
    output wire [15:0] irq_vec_o
);

    reg        en, irq_en;
    reg [31:0] period;
    reg [31:0] counter;      // cycles to the next event
    reg        pending;
    reg [31:0] evt_cnt, ack_cnt, miss_cnt;
    reg [31:0] lat_now;      // cycles since the event
    reg [31:0] lat_sum, lat_max;

    // ---------------- AXI write ----------------
    // accept the write when AW and W are both valid
    wire write_ok = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    assign s_axi_awready = write_ok;
    assign s_axi_wready  = write_ok;
    assign s_axi_bresp   = 2'b00;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_bvalid <= 1'b0;
        else if (write_ok)
            s_axi_bvalid <= 1'b1;
        else if (s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end

    wire wr_ctrl   = write_ok && (s_axi_awaddr[4:2] == 3'd0);
    wire wr_period = write_ok && (s_axi_awaddr[4:2] == 3'd1);
    wire ack       = write_ok && (s_axi_awaddr[4:2] == 3'd2) && s_axi_wdata[0] && pending;

    // ---------------- AXI read ----------------
    assign s_axi_arready = s_axi_arvalid && !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else if (s_axi_arready) begin
            s_axi_rvalid <= 1'b1;
            case (s_axi_araddr[4:2])
                3'd0: s_axi_rdata <= {30'd0, irq_en, en};
                3'd1: s_axi_rdata <= period;
                3'd2: s_axi_rdata <= {31'd0, pending};
                3'd3: s_axi_rdata <= evt_cnt;
                3'd4: s_axi_rdata <= ack_cnt;
                3'd5: s_axi_rdata <= miss_cnt;
                3'd6: s_axi_rdata <= lat_sum;
                3'd7: s_axi_rdata <= lat_max;
            endcase
        end else if (s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

    // ---------------- event generation ----------------
    wire fire = en && (counter == 32'd1);   // new event in this cycle

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            en       <= 1'b0;
            irq_en   <= 1'b0;
            period   <= 32'd1000;
            counter  <= 32'd1000;
            pending  <= 1'b0;
            evt_cnt  <= 32'd0;
            ack_cnt  <= 32'd0;
            miss_cnt <= 32'd0;
            lat_now  <= 32'd0;
            lat_sum  <= 32'd0;
            lat_max  <= 32'd0;
        end else begin
            if (wr_period)
                period <= s_axi_wdata;

            if (wr_ctrl) begin
                en      <= s_axi_wdata[0];
                irq_en  <= s_axi_wdata[1];
                counter <= period;          // restart the counter
            end else if (en) begin
                counter <= fire ? period : counter - 32'd1;
            end

            // latency counter: counts while the event is waiting
            if (pending)
                lat_now <= lat_now + 32'd1;

            // CPU answered the event (ACK)
            if (ack) begin
                ack_cnt <= ack_cnt + 32'd1;
                lat_sum <= lat_sum + lat_now;
                if (lat_now > lat_max)
                    lat_max <= lat_now;
            end

            // new event
            if (fire) begin
                evt_cnt <= evt_cnt + 32'd1;
                if (pending && !ack) begin
                    miss_cnt <= miss_cnt + 32'd1;   // last event not answered yet
                end else begin
                    pending <= 1'b1;
                    lat_now <= 32'd0;
                end
            end else if (ack) begin
                pending <= 1'b0;
            end
        end
    end

    assign irq_vec_o = {15'd0, pending & irq_en};

endmodule
