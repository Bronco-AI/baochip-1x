`timescale 1ns / 1ps
// `define XOUS 1

// contains "cosim" models that encapsulate some key differences between ASIC/FPGA behaviors
// particularly around reset conditions.

// WATCHDOG_CYCLES: end the simulation as a failure when `progress` (the duart TX line) has not
// toggled for this many clk cycles, i.e. the firmware has stopped printing because a test is
// stuck. Without it a stalled BIO test only ends at the harness's wall-clock timeout, with no
// indication of where it stopped. 0 disables the check; the longest idle gap is always reported
// at the end of a run so the limit can be calibrated against a clean run.
module finisher #(
    // ~9x the longest idle gap of a clean nto-tests BIO run (1,076,279 cycles)
    parameter [63:0] WATCHDOG_CYCLES = 64'd10_000_000
)(
    input wire [31:0] report,
    input wire done,
    input wire progress,
    input wire clk
);

reg progress_q = 1'b1;
reg [63:0] idle_cycles = 64'd0;
reg [63:0] max_idle_cycles = 64'd0;

always @(posedge clk) begin
    progress_q <= progress;
    if (progress != progress_q) begin
        if (idle_cycles > max_idle_cycles)
            max_idle_cycles <= idle_cycles;
        idle_cycles <= 64'd0;
    end else begin
        idle_cycles <= idle_cycles + 64'd1;
    end
    if (WATCHDOG_CYCLES != 64'd0 && idle_cycles == WATCHDOG_CYCLES) begin
        $display("[watchdog] FAIL: no UART activity for %0d cycles; the firmware stalled (report %h)", idle_cycles, report);
        $dumpflush;
        $finish;
    end
end

reg [31:0] rep_state;
reg kprint_trigger = 0;
reg kprint_trigger_d = 0;
reg kprint_done = 0;

always @(report) begin
    if (report != rep_state) begin
        rep_state <= report;
        $display("Report update: %h", report);
    end
end

always @(*) begin
    if (kprint_done == 1'b1) begin
        $dumpflush;
        $dumpoff;
        $finish;
    end
end

// This block waits for `done` to rise; then, it triggers an 'r' into the kernel
// so that the RAM usage dump gets printed. Finally, the simulation termination
// signal `kprint_done` is triggered when the '.' character is seen in the kernel log.
always @(posedge clk) begin
    // make the trigger "sticky" and one-way
    if (done == 1'b1) begin
`ifndef XOUS
        $display("[watchdog] longest UART-idle gap: %0d cycles", (idle_cycles > max_idle_cycles) ? idle_cycles : max_idle_cycles);
        $dumpflush;
        $dumpoff;
        $finish;
`endif
    end
end

// make sure we eventually stop
// initial #750_000_000 $finish;

endmodule
