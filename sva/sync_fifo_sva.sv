//-----------------------------------------------------------------------------
// Module      : sync_fifo_sva
// Description : SystemVerilog Assertions for sync_fifo.
//               Attached to the DUT with `bind`, so the RTL stays untouched.
//               Checks reset values, flag correctness, pointer behaviour,
//               overflow/underflow protection, occupancy tracking and
//               X-propagation, plus cover properties for corner cases.
//-----------------------------------------------------------------------------
module sync_fifo_sva #(
  parameter int DATA_WIDTH      = 8,
  parameter int DEPTH           = 16,
  parameter int ALMOST_FULL_TH  = DEPTH - 2,
  parameter int ALMOST_EMPTY_TH = 2
) (
  input logic                    clk,
  input logic                    rst_n,
  input logic                    wr_en,
  input logic                    rd_en,
  input logic [DATA_WIDTH-1:0]   wr_data,
  input logic [DATA_WIDTH-1:0]   rd_data,
  input logic                    full,
  input logic                    empty,
  input logic                    almost_full,
  input logic                    almost_empty,
  input logic                    overflow,
  input logic                    underflow,
  input logic [$clog2(DEPTH):0]  count,
  input logic [$clog2(DEPTH):0]  wr_ptr,   // internal DUT signal
  input logic [$clog2(DEPTH):0]  rd_ptr    // internal DUT signal
);

  localparam int AW = $clog2(DEPTH);
  localparam int PW = AW + 1;              // pointer width

  logic wr_fire, rd_fire;
  assign wr_fire = wr_en && !full;
  assign rd_fire = rd_en && !empty;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  //---------------------------------------------------------------------------
  // Reset behaviour (not disabled by reset)
  //---------------------------------------------------------------------------
  a_reset_state: assert property (disable iff (1'b0)
    !rst_n |=> (empty && !full && count == '0 && !overflow && !underflow))
    else $error("SVA: FIFO not empty / flags wrong after reset");

  //---------------------------------------------------------------------------
  // Flag consistency
  //---------------------------------------------------------------------------
  a_not_full_and_empty: assert property (!(full && empty))
    else $error("SVA: full and empty asserted together");

  a_count_in_range: assert property (count <= DEPTH)
    else $error("SVA: count %0d exceeds DEPTH", count);

  a_full_matches_count: assert property (full == (count == DEPTH))
    else $error("SVA: full flag does not match count");

  a_empty_matches_count: assert property (empty == (count == 0))
    else $error("SVA: empty flag does not match count");

  a_almost_full: assert property (almost_full == (count >= ALMOST_FULL_TH))
    else $error("SVA: almost_full incorrect (count=%0d)", count);

  a_almost_empty: assert property (almost_empty == (count <= ALMOST_EMPTY_TH))
    else $error("SVA: almost_empty incorrect (count=%0d)", count);

  //---------------------------------------------------------------------------
  // Overflow / underflow protection
  //---------------------------------------------------------------------------
  a_no_write_when_full: assert property (wr_en && full |=> $stable(wr_ptr))
    else $error("SVA: write pointer moved while FIFO was full");

  a_no_read_when_empty: assert property (rd_en && empty |=> $stable(rd_ptr))
    else $error("SVA: read pointer moved while FIFO was empty");

  a_overflow_set: assert property (wr_en && full |=> overflow)
    else $error("SVA: overflow not flagged");

  a_overflow_clr: assert property (!(wr_en && full) |=> !overflow)
    else $error("SVA: spurious overflow flag");

  a_underflow_set: assert property (rd_en && empty |=> underflow)
    else $error("SVA: underflow not flagged");

  a_underflow_clr: assert property (!(rd_en && empty) |=> !underflow)
    else $error("SVA: spurious underflow flag");

  //---------------------------------------------------------------------------
  // Pointer behaviour
  //---------------------------------------------------------------------------
  a_wr_ptr_incr: assert property (wr_fire |=> wr_ptr == PW'($past(wr_ptr) + 1'b1))
    else $error("SVA: write pointer did not increment");

  a_wr_ptr_hold: assert property (!wr_fire |=> $stable(wr_ptr))
    else $error("SVA: write pointer changed without a write");

  a_rd_ptr_incr: assert property (rd_fire |=> rd_ptr == PW'($past(rd_ptr) + 1'b1))
    else $error("SVA: read pointer did not increment");

  a_rd_ptr_hold: assert property (!rd_fire |=> $stable(rd_ptr))
    else $error("SVA: read pointer changed without a read");

  //---------------------------------------------------------------------------
  // Occupancy tracking
  //---------------------------------------------------------------------------
  a_count_inc: assert property (wr_fire && !rd_fire |=> count == $past(count) + 1)
    else $error("SVA: count did not increment on write");

  a_count_dec: assert property (rd_fire && !wr_fire |=> count == $past(count) - 1)
    else $error("SVA: count did not decrement on read");

  a_count_hold: assert property ((wr_fire == rd_fire) |=> count == $past(count))
    else $error("SVA: count changed on simultaneous/idle cycle");

  //---------------------------------------------------------------------------
  // X checks
  //---------------------------------------------------------------------------
  m_wr_data_known: assume property (wr_en |-> !$isunknown(wr_data))
    else $error("SVA: X/Z on wr_data during write");

  a_flags_known: assert property
    (!$isunknown({full, empty, almost_full, almost_empty, overflow, underflow, count}))
    else $error("SVA: X/Z on status outputs");

  a_rd_data_known: assert property (rd_fire |=> !$isunknown(rd_data))
    else $error("SVA: X/Z on rd_data after read");

  //---------------------------------------------------------------------------
  // Functional coverage of corner cases
  //---------------------------------------------------------------------------
  c_full:            cover property (full);
  c_write_when_full: cover property (wr_en && full);
  c_read_when_empty: cover property (rd_en && empty);
  c_simul_rw:        cover property (wr_fire && rd_fire);
  c_rw_when_full:    cover property (full && wr_en && rd_en);
  c_rw_when_empty:   cover property (empty && wr_en && rd_en);
  c_ptr_wrap:        cover property (wr_fire && wr_ptr[AW-1:0] == '1);
  c_full_to_empty:   cover property (full ##[1:$] empty);
  c_empty_to_full:   cover property (empty ##[1:$] full);

endmodule

//-----------------------------------------------------------------------------
// Bind the checker into every instance of sync_fifo
//-----------------------------------------------------------------------------
bind sync_fifo sync_fifo_sva #(
  .DATA_WIDTH      (DATA_WIDTH),
  .DEPTH           (DEPTH),
  .ALMOST_FULL_TH  (ALMOST_FULL_TH),
  .ALMOST_EMPTY_TH (ALMOST_EMPTY_TH)
) u_sync_fifo_sva (
  .clk          (clk),
  .rst_n        (rst_n),
  .wr_en        (wr_en),
  .rd_en        (rd_en),
  .wr_data      (wr_data),
  .rd_data      (rd_data),
  .full         (full),
  .empty        (empty),
  .almost_full  (almost_full),
  .almost_empty (almost_empty),
  .overflow     (overflow),
  .underflow    (underflow),
  .count        (count),
  .wr_ptr       (wr_ptr),
  .rd_ptr       (rd_ptr)
);
