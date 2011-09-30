//////////////////////////////////////////////////////////////
//
//      State Machine to manage FX2 USB interface
//
// By: Kirk Weedman KD7IRS
//
//////////////////////////////////////////////////////////////
/*
        The state machine checks if there is any data from the PC (in the FX2's USB
        FIFO) to be read by checking FLAGA.  If this flag is set it assumes there's
        at least RX_BURST_SZ bytes of info in the USB FIFO and transfers this amount to the
        RX_FIFO. If the flag is not set it then checks to see if FLAGC is set and if
        there's at least TX_FIFO_SZ bytes worth of data in the TX FIFO to send to the USBs
        FIFO. If so, it transfers the data.  Then this whole process is repeated
        forever.
*/

`timescale 1 ns/100 ps

module sync_usb(IF_clk, IF_rst, FX2_FD, FLAGA, FLAGB, FLAGC, SLWR, SLRD, SLOE, PKEND, FIFO_ADR,
                 Rx_fifo_wreq, Rx_fifo_wdata, Rx_fifo_used, Rx_fifo_full,
                 Tx_fifo_rreq, Tx_fifo_rdata, Tx_fifo_used, Tx_fifo_full,
                 Sp_fifo_rreq, Sp_fifo_rdata, Sp_fifo_used, Sp_fifo_full );
parameter IF_TPD      = 3;
parameter RX_FIFO_SZ  = 2048; // 16 by 2048 deep RX FIFO
parameter RX_BURST_SZ = 64;   // number of words to transfer
parameter TX_FIFO_SZ  = 4096; // 16 by 4096 deep TX FIFO
parameter TX_BURST_SZ = 256;
parameter SP_FIFO_SZ  = 1024; // 16 by 1024 deep SP FIFO
parameter SP_BURST_SZ = 64;

localparam SFSZ = clogb2(SP_FIFO_SZ-1);  // number of bits needed to hold 0 - (SP_FIFO_SZ-1)
localparam SBSZ = clogb2(SP_BURST_SZ-1);
localparam RFSZ = clogb2(RX_FIFO_SZ-1);  // number of bits needed to hold 0 - (RX_FIFO_SZ-1)
localparam RBSZ = clogb2(RX_BURST_SZ-1);
localparam TFSZ = clogb2(TX_FIFO_SZ-1);  // number of bits needed to hold 0 - (TX_FIFO_SZ-1)
localparam TBSZ = clogb2(TX_BURST_SZ-1);
localparam SZ1  = (RX_BURST_SZ < TX_BURST_SZ) ? TX_BURST_SZ : RX_BURST_SZ;
localparam BSZ  = clogb2((SZ1 < SP_BURST_SZ) ? SP_BURST_SZ : SZ1);

input  wire             IF_clk;
input  wire             IF_rst;
inout  wire      [15:0] FX2_FD;         // bidirectional FIFO data to/from the FX2                                    // ***** use this so simulation works

input  wire             FLAGA;
input  wire             FLAGB;
input  wire             FLAGC;

output reg              SLWR;           // FX2 write - active low
output reg              SLRD;           // FX2 read - active low
output reg              SLOE;           // FX2 data bus enable - active low
output wire             PKEND;
output reg        [1:0] FIFO_ADR;       // FX2 register address

output reg              Rx_fifo_wreq;   // flag for SYNC_state to know when Rx_fifo_wdata is valid
output reg       [15:0] Rx_fifo_wdata;
input  wire  [RFSZ-1:0] Rx_fifo_used;
input  wire             Rx_fifo_full;

output wire              Tx_fifo_rreq;
input  wire      [15:0] Tx_fifo_rdata;
input  wire  [TFSZ-1:0] Tx_fifo_used;
input  wire             Tx_fifo_full;

output reg              Sp_fifo_rreq;       // spectrum data signals
input  wire      [15:0] Sp_fifo_rdata;
input  wire  [SFSZ-1:0] Sp_fifo_used;
input  wire             Sp_fifo_full;

reg    [BSZ-1:0] FX_Burst_cnt; // use this when all is working
//reg [16:0] FX_Burst_cnt; // ???keep fixed size while using SignalTap and debugging different sizes
reg        [3:0] FX_state;         // state for FX2
reg        [3:0] FX_state_next;    // next state for FX2
reg              SLEN;             // Put data on FX2 bus
wire             rx_pc_rdy;
wire             tx_pc_rdy;
wire             sp_pc_rdy;
wire             from_pc_rdy;
wire             to_pc_rdy;
reg              ep_sel;
wire             Tx_sel;
wire             Sp_sel;
wire   [BSZ-1:0] from_pc_burst_sz;
wire   [BSZ-1:0] to_pc_burst_sz;

localparam EP2_ADR = 2'b00;
localparam EP4_ADR = 2'b01;
localparam EP6_ADR = 2'b10;

localparam FX_IDLE          = 0,
           FX_FROM_PC_CHECK = 1,
           FX_TO_PC_CHECK   = 2,
           FX_F1            = 3,
           FX_F6            = 4,
           FX_FDONE         = 5,
           FX_T1            = 6,
           FX_T7            = 7,
           FX_TDONE         = 8;

localparam SLWR_ASSERT = 1'b0;
localparam SLWR_NEGATE = 1'b1;

localparam SLRD_ASSERT = 1'b0;
localparam SLRD_NEGATE = 1'b1;

localparam SLOE_ASSERT = 1'b0;
localparam SLOE_NEGATE = 1'b1;

localparam SLEN_ASSERT = 1'b1;
localparam SLEN_NEGATE = 1'b0;

assign #IF_TPD Tx_fifo_rreq = (FX_state == FX_T7); 

//assign #IF_TPD tx_pc_rdy = FLAGC && (Tx_fifo_full || Tx_fifo_used[TFSZ-1:TBSZ-1]);
assign #IF_TPD tx_pc_rdy = FLAGC && ({Tx_fifo_full,Tx_fifo_used} >= TX_BURST_SZ);
// FLAGC high and at least TBSZ/2 words (TBSZ bytes) in buffer

assign #IF_TPD sp_pc_rdy = FLAGB && ({Sp_fifo_full,Sp_fifo_used} >= SP_BURST_SZ);
// FLAGB high and at least SBSZ/2 words (SBSZ bytes) in buffer

//assign #IF_TPD from_pc_rdy = FLAGA;
assign #IF_TPD rx_pc_rdy = FLAGA && ({Rx_fifo_full,Rx_fifo_used} < (252*6));

assign PKEND = 1'b1;

assign Tx_sel = (ep_sel == 1'b0);
assign Sp_sel = (ep_sel == 1'b1);

assign from_pc_burst_sz = RX_BURST_SZ;
assign from_pc_rdy      = rx_pc_rdy;

assign to_pc_burst_sz = Tx_sel ? TX_BURST_SZ : SP_BURST_SZ;
assign to_pc_rdy      = Tx_sel ? tx_pc_rdy : sp_pc_rdy;

always @ (posedge IF_clk)
begin
  if (IF_rst)
    FX_state <= #IF_TPD FX_IDLE;
  else
    FX_state <= #IF_TPD FX_state_next;

  if (IF_rst)
    SLOE <= #IF_TPD SLOE_NEGATE;
  else if (FX_state == FX_F1)
    SLOE <= #IF_TPD SLOE_ASSERT; // asserted during burst read
  else if (FX_state == FX_FDONE)
    SLOE <= #IF_TPD SLOE_NEGATE;
  
  if (IF_rst)
    SLRD <= #IF_TPD SLRD_NEGATE;
  else if (FX_state == FX_F6)
    SLRD <= #IF_TPD SLRD_ASSERT; // asserted immediately after an FX_F6 state
  else
    SLRD <= #IF_TPD SLRD_NEGATE;

  if (IF_rst)
    ep_sel <= #IF_TPD 1'b0; // 0 - TX FIFO to EP6, 1 = SP FIFO to EP4
  else if (FX_state == FX_TDONE)
    ep_sel <= #IF_TPD ~ep_sel; // see Tx_sel, Sp_sel

  if (IF_rst)
    SLWR <= #IF_TPD SLWR_NEGATE;
  else if (FX_state == FX_T7)
    SLWR <= #IF_TPD SLWR_ASSERT;
  else
    SLWR <= #IF_TPD SLWR_NEGATE;

  if (IF_rst)
    SLEN <= #IF_TPD SLEN_NEGATE;
  else if (FX_state == FX_T1)
    SLEN <= #IF_TPD SLEN_ASSERT; // asserted during write burst
  else if (FX_state == FX_TDONE)
    SLEN <= #IF_TPD SLEN_NEGATE;

  if (IF_rst)
    Rx_fifo_wreq <= #IF_TPD 1'b0;
  else
    Rx_fifo_wreq <= #IF_TPD !SLRD;

  if (IF_rst)
    Rx_fifo_wdata <= #IF_TPD 16'b0;
  else if (!SLRD)  // data from PC now available since tXFD = 15nS max
    Rx_fifo_wdata <= #IF_TPD {FX2_FD[7:0],FX2_FD[15:8]}; // swap endian

  if (IF_rst)
    Sp_fifo_rreq <= #IF_TPD 1'b0;
  else // start transfer from Tx fifo?
    Sp_fifo_rreq <= #IF_TPD ((FX_state == FX_T1) & Sp_sel) ? 1'b1 : 1'b0; // must read first to get data out of FIFO!

  if ((FX_state == FX_IDLE) || (FX_state == FX_TDONE))
    FIFO_ADR <= #IF_TPD EP2_ADR; // Must be setup 10.7nS min before checking FLAGS
  else if (FX_state == FX_FDONE)// FX_FXDONE - > FX_TO_PC_ADDR
  begin
    if (Tx_sel)
      FIFO_ADR <= #IF_TPD EP6_ADR; // Must be setup 10.7nS min before checking FLAGS
    else 
      FIFO_ADR <= #IF_TPD EP4_ADR; // Sp_sel
  end

  if ((FX_state == FX_IDLE) || (FX_state == FX_TDONE) || (FX_state == FX_FDONE))
    FX_Burst_cnt <= #IF_TPD 1'b0;
  else if ((FX_state == FX_T7) || (FX_state == FX_F6))
    FX_Burst_cnt <= #IF_TPD FX_Burst_cnt + 1'b1;
end

always @*
begin
  case (FX_state)
    FX_IDLE:
    begin
      FX_state_next = FX_FROM_PC_CHECK;
    end

    FX_FROM_PC_CHECK:                 // check for data from PC
    begin
      if (from_pc_rdy)
        FX_state_next = FX_F1;
      else
        FX_state_next = FX_FDONE;  // No data from PC so check for data ready to go to PC
    end


/* Sync reads from CY7C68013A
   FIFOADR[1:0]-+--------------------------------------+------------
               -+--------------------------------------+--------------
                |<-tSFA->|                    |<-tFAH->|
   IFCLK   ---------+                  +------------------+
                    +------------------+                  +---
                         |<-----tSRD-->|<-tRDH->
   SLRD -----------------+                     +-----------------------+--
                         +---------------------+                       +---
                                       |<-- tXFLG -->|
   Flags --------------------------------------------+------------
          -------------------------------------------+--------------
                                       < tXFD>
                      +----------------------+---------------------+
   Data  -------------+          N           +    N+1              +----------------
                      +----------------------+---------------------+
                  <-A->                                        <-B->
   SLOE  ---------+                                            +-------------------
                  +--------------------------------------------+
                                 
         tSRD   = 8.7nS? minimum
         tRDH   = 0 nS minimum
         tXFD   = 11nS max
         tXFLG  = 9.5nS max
         tSFA   = 10nS max
         tFAH   = 10nS max
         A = tOEon  = 10.5nS max
         B = tOEoff = 10.5nS max
                    
*/
    FX_F1:
      FX_state_next = FX_F6;

    FX_F6:
    begin
      if (FX_Burst_cnt != (from_pc_burst_sz-1)) // from_pc_burst_sz words = from_pc_burst_sz*2 bytes
        FX_state_next = FX_F6;
      else
        FX_state_next = FX_FDONE;
    end

    FX_FDONE:
      FX_state_next = FX_TO_PC_CHECK;


    FX_TO_PC_CHECK:
    begin
      if (to_pc_rdy)
        FX_state_next = FX_T1;
      else
        FX_state_next = FX_TDONE; // No TO-PC data so check for FROM-PC data again
    end

/* Sync writes to CY7C68013A
   IFCLK ---------+                    +--------------------+
                  +--------------------+                    +-------------
                         |<--- tSWR -->|<tWRH>|
   SLWR -----------------+                    +-----------------------
                         +--------------------+
                            |<--tSFD-->|<--tFDH-->|
                            +---------------------+
   Data  -------------------+                     +----------------
                            +---------------------+
                                       |<----tXFLG--->|
   Flags ---------------------------------------------+------------
          --------------------------------------------+--------------
                                
         tSWR   = 18.1? nS minimum
         tWRH   = 0 nS minimum
         tSFD   = 9.2 nS min
         tFDH   = 0 nS min
         tXFLG  = 9.5 nS max 
*/
    FX_T1:
      FX_state_next = FX_T7;

    FX_T7:
    begin
      if (FX_Burst_cnt != (to_pc_burst_sz-1)) // to_pc_burst_sz words = to_pc_burst_sz*2 bytes
        FX_state_next = FX_T7;
      else
        FX_state_next = FX_TDONE;
    end

    FX_TDONE:
      FX_state_next = FX_FROM_PC_CHECK;

    default:
      FX_state_next = FX_IDLE;
  endcase
end

// FX2_FD is tristate when SLEN is negated
// Swap endian so data is correct at PC end

assign FX2_FD = (SLEN & Tx_sel) ? {Tx_fifo_rdata[7:0], Tx_fifo_rdata[15:8]} : {16{1'bz}};
assign FX2_FD = (SLEN & Sp_sel) ? {Sp_fifo_rdata[7:0], Sp_fifo_rdata[15:8]} : {16{1'bz}};

function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction

endmodule