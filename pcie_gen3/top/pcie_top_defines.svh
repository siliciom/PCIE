`ifndef PCIE_DEFINES_SVH
`define PCIE_DEFINES_SVH

`ifndef NUM_RC
  `define NUM_RC 1
`endif
`ifndef NUM_EP
  `define NUM_EP 1
`endif

`ifndef NUM_RC_GEN
  `define NUM_RC_GEN 1
`endif
`ifndef NUM_EP_GEN
  `define NUM_EP_GEN 1
`endif

`ifndef NUM_LANES
  `define NUM_LANES 1 
`endif

`ifndef NUM_VC
  `define NUM_VC 8
`endif

// Alias macros - single definition point
`define PCIE_NUM_RC `NUM_RC
`define PCIE_NUM_EP `NUM_EP
`define PCIE_NUM_RC_GEN `NUM_RC_GEN
`define PCIE_NUM_EP_GEN `NUM_EP_GEN
`define PCIE_NUM_LANES `NUM_LANES
`define PCIE_NUM_VC `NUM_VC




  typedef enum bit [4:0] {

    // Memory Requests
    
    MEM_RD,
    MEM_WR,

    // IO Requests
    
    IO_RD,
    IO_WR,

    // Configuration Requests
    
    CFG_RD0,
    CFG_WR0,
    CFG_RD1,
    CFG_WR1,

    // Messages
    
    MSG_RTRC,             // ROUTE TO ROOT COMPLEX //
  	MSG_RBA,             // ROUTE BY ADDRESS //
  	MSG_RBI,            // ROUTE BY ID //
  	MSG_IBD,           // IMPLICIT BROADCAST DOWNSTREAM //
  	MSG_ILTAR,        // IMPLICIT LOCAL TERMINATE AT RECIEVER //
  	MSG_GARTRC,      // GATHER AND ROUTE TO ROOT COMPLEX //
  	MSG_RESERVED1,  // RESERVED //
  	MSG_RESERVED2, // RESERVED //


    // Completions
    
    CPL,
    CPL_DATA

  } tlp_type_e;



  typedef enum bit [2:0] {

    FMT_3DW_NO_DATA,
    FMT_4DW_NO_DATA,
    FMT_3DW_DATA,
    FMT_4DW_DATA

  } fmt_e;

  typedef enum {

    P,
    NP,
    CMPL

  } packet_type_e;




  typedef enum bit [2:0] {

    VC0, VC1, VC2, VC3, VC4, VC5, VC6, VC7

  } vc_id_e;

  //-----------------------------------------------------------------
  // err_inject_e
  //   Single knob (Sequence_item::inject_err for TL-layer scenarios,
  //   env_cfg::inject_err for DLL/PHY-layer scenarios) that tells
  //   this bench which negative/error scenario (if any) to corrupt
  //   the current transaction with. ERR_NONE means "drive it clean"
  //   - this is the default everywhere, so nothing about normal
  //   traffic changes unless a test explicitly sets inject_err.
  //-----------------------------------------------------------------
  typedef enum bit [4:0] {

    ERR_NONE,               // no injection - normal traffic

    // ---------------- TL layer (Sequence_item::inject_err,
    //                   applied in post_randomize()/pack_tlp()) ----
    ERR_ECRC,                // flip the computed ECRC before sending
    ERR_LEN_MISMATCH,        // header Length lies about DWs actually sent (Malformed, Fatal)
    ERR_IO_LEN,               // IO_RD/IO_WR with Length > 1 (spec requires Length==1)
    ERR_CFG_LEN,              // CFG_RD0/1, CFG_WR0/1 with Length > 1 (spec requires Length==1)
    ERR_FMT_RTYPE,            // reserved fmt encoding (3'b1xx)
    ERR_BYTE_EN,              // non-contiguous first_BE/last_BE pattern
    ERR_EP_POISON,            // EP (poison) bit set on an otherwise normal write
    ERR_UNSUPPORTED_REQ,      // address outside any implemented BAR range
    ERR_UNEXP_CPL,            // CPL_DATA carrying a tag that was never allocated

    // ---------------- DLL/PHY layer (env_cfg::inject_err,
    //                   applied in PCIe_DLL_Driver.sv) -------------
    ERR_LCRC,                 // corrupt the LCRC DW appended after *_calculate_lcrc()
    ERR_DLLP_CRC,             // corrupt the 16-bit CRC field of a DLLP
    ERR_SEQ_NUM,              // force a skip/out-of-order DLL sequence number
    ERR_STP,                  // corrupt the start-of-TLP packet-type marker
    ERR_REPLAY_ROLLOVER,      // keep NAK'ing so the same seq replays 4+ times
    ERR_REPLAY_TIMER          // withhold Ack past the replay timer limit

  } err_inject_e;


`endif
