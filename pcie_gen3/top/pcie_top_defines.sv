`ifndef PCIE_DEFINES_SVH
`define PCIE_DEFINES_SVH

// --------------------------------------------------
// MACROS
// --------------------------------------------------

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

`define PCIE_NUM_RC      `NUM_RC
`define PCIE_NUM_EP      `NUM_EP
`define PCIE_NUM_RC_GEN  `NUM_RC_GEN
`define PCIE_NUM_EP_GEN  `NUM_EP_GEN
`define PCIE_NUM_LANES   `NUM_LANES
`define PCIE_NUM_VC      `NUM_VC


// --------------------------------------------------
// TLP TYPE
// --------------------------------------------------

typedef enum bit [4:0] {

    MEM_RD,
    MEM_WR,

    IO_RD,
    IO_WR,

    CFG_RD0,
    CFG_WR0,
    CFG_RD1,
    CFG_WR1,

    MSG_RTRC,
    MSG_RBA,
    MSG_RBI,
    MSG_IBD,
    MSG_ILTAR,
    MSG_GARTRC,
    MSG_RESERVED1,
    MSG_RESERVED2,

    CPL,
    CPL_DATA

} tlp_type_e;


// --------------------------------------------------
// FMT TYPE
// --------------------------------------------------

typedef enum bit [2:0] {

    FMT_3DW_NO_DATA,
    FMT_4DW_NO_DATA,
    FMT_3DW_DATA,
    FMT_4DW_DATA

} fmt_e;


// --------------------------------------------------
// PACKET TYPE
// --------------------------------------------------

typedef enum {

    P,
    NP,
    CMPL

} packet_type_e;


// --------------------------------------------------
// VC ID
// --------------------------------------------------

typedef enum bit [2:0] {

    VC0,
    VC1,
    VC2,
    VC3,
    VC4,
    VC5,
    VC6,
    VC7

} vc_id_e;


// --------------------------------------------------
// ERROR INJECTION
// --------------------------------------------------

typedef enum bit [4:0] {

    ERR_NONE,

    ERR_ECRC,
    ERR_LEN_MISMATCH,
    ERR_IO_LEN,
    ERR_CFG_LEN,
    ERR_FMT_RTYPE,
    ERR_BYTE_EN,
    ERR_EP_POISON,
    ERR_UNSUPPORTED_REQ,
    ERR_UNEXP_CPL,

    ERR_LCRC,
    ERR_DLLP_CRC,
    ERR_SEQ_NUM,
    ERR_STP,
    ERR_REPLAY_ROLLOVER,
    ERR_REPLAY_TIMER

} err_inject_e;


// IMPORTANT: endif should be at the VERY END
`endif
