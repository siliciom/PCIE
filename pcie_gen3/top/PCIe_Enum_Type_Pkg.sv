
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

  //-----------------------------------------------------------
  // Virtual Channel ID - 8 VCs (VC0 mandatory, VC1-VC7 optional
  // per spec, all modeled here for arbitration + FC purposes)
  //-----------------------------------------------------------
  typedef enum bit [2:0] {

    VC0, VC1, VC2, VC3, VC4, VC5, VC6, VC7

  } vc_id_e;

