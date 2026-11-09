//-----------------------------------------------------------------------------
// Module      : sync_fifo
// Description : Parameterized synchronous FIFO (single clock domain).
//               - Circular buffer with (AW+1)-bit read/write pointers.
//                 The extra MSB distinguishes FULL from EMPTY when the
//                 address bits of both pointers are equal.
//               - Registered read data (1-cycle read latency).
//               - Writes while full and reads while empty are ignored and
//                 flagged on overflow / underflow (1-cycle pulse).
//               - Programmable almost_full / almost_empty thresholds.
//               - Active-low asynchronous reset.
//-----------------------------------------------------------------------------
module sync_fifo #(
  parameter int DATA_WIDTH      = 8,
  parameter int DEPTH           = 16,          // must be a power of 2, >= 2
  parameter int ALMOST_FULL_TH  = DEPTH - 2,   // almost_full  when count >= TH
  parameter int ALMOST_EMPTY_TH = 2            // almost_empty when count <= TH
) (
  input  logic                       clk,
  input  logic                       rst_n,

  // Write port
  input  logic                       wr_en,
  input  logic [DATA_WIDTH-1:0]      wr_data,

  // Read port
  input  logic                       rd_en,
  output logic [DATA_WIDTH-1:0]      rd_data,

  // Status
  output logic                       full,
  output logic                       empty,
  output logic                       almost_full,
  output logic                       almost_empty,
  output logic                       overflow,      // write attempted while full
  output logic                       underflow,     // read attempted while empty
  output logic [$clog2(DEPTH):0]     count          // number of stored entries
);

  localparam int AW = $clog2(DEPTH);

  // synthesis translate_off
  initial begin
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "sync_fifo: DEPTH (%0d) must be a power of 2 and >= 2", DEPTH);
    if (ALMOST_FULL_TH > DEPTH || ALMOST_EMPTY_TH > DEPTH)
      $fatal(1, "sync_fifo: almost thresholds must be <= DEPTH");
  end
  // synthesis translate_on

  //---------------------------------------------------------------------------
  // Storage and pointers
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [DEPTH];
  logic [AW:0]           wr_ptr;
  logic [AW:0]           rd_ptr;

  logic wr_fire;   // write actually accepted
  logic rd_fire;   // read actually accepted

  assign wr_fire = wr_en && !full;
  assign rd_fire = rd_en && !empty;

  // Write pointer
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)       wr_ptr <= '0;
    else if (wr_fire) wr_ptr <= wr_ptr + 1'b1;
  end

  // Memory write (no reset -> maps to distributed / block RAM)
  always_ff @(posedge clk) begin
    if (wr_fire) mem[wr_ptr[AW-1:0]] <= wr_data;
  end

  // Read pointer and registered read data
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr  <= '0;
      rd_data <= '0;
    end else if (rd_fire) begin
      rd_ptr  <= rd_ptr + 1'b1;
      rd_data <= mem[rd_ptr[AW-1:0]];
    end
  end

  //---------------------------------------------------------------------------
  // Status flags
  //---------------------------------------------------------------------------
  assign empty        = (wr_ptr == rd_ptr);
  assign full         = (wr_ptr[AW] != rd_ptr[AW]) &&
                        (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]);
  assign count        = wr_ptr - rd_ptr;      // modulo 2^(AW+1), always 0..DEPTH
  assign almost_full  = (count >= ALMOST_FULL_TH);
  assign almost_empty = (count <= ALMOST_EMPTY_TH);

  // Error pulses (registered)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow  <= 1'b0;
      underflow <= 1'b0;
    end else begin
      overflow  <= wr_en && full;
      underflow <= rd_en && empty;
    end
  end

endmodule
