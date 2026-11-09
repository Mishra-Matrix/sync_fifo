//-----------------------------------------------------------------------------
// Testbench   : tb_sync_fifo
// Description : Self-checking testbench for sync_fifo.
//               - Reference model (SystemVerilog queue) as scoreboard
//               - Checks data order, count, all flags and error pulses
//                 every cycle
//               - Directed tests for corner cases + constrained-random traffic
//               - Functional coverage with a covergroup
//               Run with +SEED=<n> to change the random seed.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_sync_fifo;

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int  DATA_WIDTH      = 8;
  localparam int  DEPTH           = 16;
  localparam int  ALMOST_FULL_TH  = DEPTH - 2;
  localparam int  ALMOST_EMPTY_TH = 2;
  localparam int  AW              = $clog2(DEPTH);
  localparam real CLK_PERIOD      = 10.0;   // 100 MHz

  //---------------------------------------------------------------------------
  // Signals
  //---------------------------------------------------------------------------
  logic                  clk = 1'b0;
  logic                  rst_n;
  logic                  wr_en, rd_en;
  logic [DATA_WIDTH-1:0] wr_data, rd_data;
  logic                  full, empty, almost_full, almost_empty;
  logic                  overflow, underflow;
  logic [AW:0]           count;

  always #(CLK_PERIOD/2) clk = ~clk;

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  sync_fifo #(
    .DATA_WIDTH      (DATA_WIDTH),
    .DEPTH           (DEPTH),
    .ALMOST_FULL_TH  (ALMOST_FULL_TH),
    .ALMOST_EMPTY_TH (ALMOST_EMPTY_TH)
  ) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .wr_en        (wr_en),
    .wr_data      (wr_data),
    .rd_en        (rd_en),
    .rd_data      (rd_data),
    .full         (full),
    .empty        (empty),
    .almost_full  (almost_full),
    .almost_empty (almost_empty),
    .overflow     (overflow),
    .underflow    (underflow),
    .count        (count)
  );

  //---------------------------------------------------------------------------
  // Scoreboard / reference model
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] model[$];
  logic [DATA_WIDTH-1:0] exp_data;
  logic                  chk_pending;
  logic                  exp_ovf, exp_udf;

  int unsigned n_writes, n_reads, n_ovf, n_udf, n_checks, n_errors;

  function automatic void report_error(string msg);
    n_errors++;
    $error("[%0t] %s", $time, msg);
  endfunction

  // Monitor: sample inputs at the clock edge (driver changes them on negedge)
  always @(posedge clk) begin
    if (!rst_n) begin
      model.delete();
      chk_pending <= 1'b0;
      exp_ovf     <= 1'b0;
      exp_udf     <= 1'b0;
    end else begin
      chk_pending <= 1'b0;
      exp_ovf     <= wr_en && full;
      exp_udf     <= rd_en && empty;

      if (rd_en && !empty) begin
        if (model.size() == 0) begin
          report_error("DUT accepted a read but reference model is empty");
        end else begin
          exp_data    <= model.pop_front();
          chk_pending <= 1'b1;
          n_reads++;
        end
      end
      if (wr_en && !full) begin
        model.push_back(wr_data);
        n_writes++;
      end
      if (wr_en && full)  n_ovf++;
      if (rd_en && empty) n_udf++;
    end
  end

  // Checker: compare DUT outputs against the model mid-cycle
  always @(negedge clk) begin
    if (rst_n) begin
      n_checks++;
      if (chk_pending && rd_data !== exp_data)
        report_error($sformatf("DATA MISMATCH: got 0x%0h, expected 0x%0h", rd_data, exp_data));
      if (count !== model.size())
        report_error($sformatf("COUNT MISMATCH: got %0d, expected %0d", count, model.size()));
      if (full !== (model.size() == DEPTH))
        report_error($sformatf("FULL flag wrong (count=%0d)", model.size()));
      if (empty !== (model.size() == 0))
        report_error($sformatf("EMPTY flag wrong (count=%0d)", model.size()));
      if (almost_full !== (model.size() >= ALMOST_FULL_TH))
        report_error($sformatf("ALMOST_FULL flag wrong (count=%0d)", model.size()));
      if (almost_empty !== (model.size() <= ALMOST_EMPTY_TH))
        report_error($sformatf("ALMOST_EMPTY flag wrong (count=%0d)", model.size()));
      if (overflow !== exp_ovf)
        report_error("OVERFLOW pulse wrong");
      if (underflow !== exp_udf)
        report_error("UNDERFLOW pulse wrong");
    end
  end

  //---------------------------------------------------------------------------
  // Functional coverage
  //---------------------------------------------------------------------------
  covergroup cg_fifo @(posedge clk iff rst_n);
    cp_ops: coverpoint {wr_en, rd_en} {
      bins idle  = {2'b00};
      bins write = {2'b10};
      bins read  = {2'b01};
      bins both  = {2'b11};
    }
    cp_level: coverpoint count {
      bins empty = {0};
      bins low   = {[1 : DEPTH/2 - 1]};
      bins high  = {[DEPTH/2 : DEPTH - 1]};
      bins full  = {DEPTH};
    }
    cp_almost_full:  coverpoint almost_full;
    cp_almost_empty: coverpoint almost_empty;
    x_ops_level: cross cp_ops, cp_level;   // includes write-when-full, read-when-empty
  endgroup

  cg_fifo cg = new();

  //---------------------------------------------------------------------------
  // Driver tasks
  //---------------------------------------------------------------------------
  task automatic drive(input bit wr, input bit rd);
    @(negedge clk);
    wr_en   = wr;
    rd_en   = rd;
    wr_data = $urandom();
  endtask

  task automatic apply_reset();
    @(negedge clk);
    rst_n = 1'b0;
    wr_en = 1'b0;
    rd_en = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  task automatic random_traffic(input int cycles, input int wr_pct, input int rd_pct);
    repeat (cycles)
      drive(($urandom_range(99) < wr_pct), ($urandom_range(99) < rd_pct));
  endtask

  task automatic expect_state(input string name, input bit exp_full, input bit exp_empty);
    if (full !== exp_full || empty !== exp_empty)
      report_error($sformatf("%s: full=%0b empty=%0b (expected %0b/%0b)",
                             name, full, empty, exp_full, exp_empty));
    else
      $display("[%0t] PASS: %s", $time, name);
  endtask

  //---------------------------------------------------------------------------
  // Test sequence
  //---------------------------------------------------------------------------
  int unsigned seed;

  initial begin
    $dumpfile("sync_fifo.vcd");
    $dumpvars(0, tb_sync_fifo);

    if ($value$plusargs("SEED=%d", seed)) void'($urandom(seed));
    $display("Running sync_fifo test, DEPTH=%0d, DATA_WIDTH=%0d", DEPTH, DATA_WIDTH);

    rst_n   = 1'b0;
    wr_en   = 1'b0;
    rd_en   = 1'b0;
    wr_data = '0;
    apply_reset();

    // T1: reset state
    expect_state("T1 reset state", 0, 1);

    // T2: fill to full, then try to overflow
    repeat (DEPTH) drive(1, 0);
    repeat (3)     drive(1, 0);           // writes while full -> ignored
    drive(0, 0);
    expect_state("T2 fill + overflow attempts", 1, 0);

    // T3: drain to empty, then try to underflow
    repeat (DEPTH) drive(0, 1);
    repeat (3)     drive(0, 1);           // reads while empty -> ignored
    drive(0, 0);
    expect_state("T3 drain + underflow attempts", 0, 1);

    // T4: simultaneous read/write at half full (count must stay constant)
    repeat (DEPTH/2) drive(1, 0);
    repeat (50)      drive(1, 1);
    drive(0, 0);
    if (count !== DEPTH/2) report_error("T4 count changed during simultaneous R/W");
    else $display("[%0t] PASS: T4 simultaneous read/write", $time);

    // T5: simultaneous read/write while full
    while (!full) drive(1, 0);
    repeat (5) drive(1, 1);

    // T6: simultaneous read/write while empty
    while (!empty) drive(0, 1);
    repeat (5) drive(1, 1);
    while (!empty) drive(0, 1);
    drive(0, 0);
    expect_state("T5/T6 R/W at full and empty boundaries", 0, 1);

    // T7: constrained-random traffic in three phases
    random_traffic(3000, 70, 30);   // write-heavy (spends time near full)
    random_traffic(3000, 30, 70);   // read-heavy  (spends time near empty)
    random_traffic(4000, 50, 50);   // balanced
    $display("[%0t] DONE: T7 random traffic (10000 cycles)", $time);

    // T8: reset in the middle of traffic
    random_traffic(200, 60, 40);
    apply_reset();
    expect_state("T8 reset during traffic", 0, 1);
    random_traffic(1000, 50, 50);

    // Drain and finish
    while (!empty) drive(0, 1);
    repeat (3) drive(0, 0);

    //-------------------------------------------------------------------------
    // Summary
    //-------------------------------------------------------------------------
    $display("");
    $display("================ SYNC FIFO TEST SUMMARY ================");
    $display(" Writes accepted       : %0d", n_writes);
    $display(" Reads accepted        : %0d", n_reads);
    $display(" Overflow attempts     : %0d", n_ovf);
    $display(" Underflow attempts    : %0d", n_udf);
    $display(" Cycle checks          : %0d", n_checks);
    $display(" Functional coverage   : %0.2f %%", cg.get_coverage());
    $display(" Errors                : %0d", n_errors);
    if (n_errors == 0 && model.size() == 0)
      $display(" RESULT                : *** TEST PASSED ***");
    else
      $display(" RESULT                : *** TEST FAILED ***");
    $display("========================================================");
    $finish;
  end

  // Watchdog
  initial begin
    #(CLK_PERIOD * 100_000);
    $fatal(1, "Simulation timeout");
  end

endmodule
