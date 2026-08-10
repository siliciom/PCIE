interface pipe_tx_interface #(parameter int unsigned NUM_LANES = `PCIE_NUM_LANES)
                              (input bit PCLK, input bit RESET);
  logic        dl_mac_packet;
  logic        tl_mac_packet;

  //-----------------------------------------------------------
  // Data Stream signals - genuine per-lane arrays. No generate/
  // assign fan-out here: PCIe_MAC_Driver.sv drives every active
  // lane explicitly (broadcast, per Option A), and
  // PCIe_PMA_Monitor.sv / PCIe_MAC_Monitor.sv read a representative
  // lane explicitly. See those files for the per-lane loops.
  //-----------------------------------------------------------
  logic         [NUM_LANES-1:0]TxDataValid ;
  logic  [NUM_LANES-1:0][129:0]TxData      ;
  logic         [NUM_LANES-1:0]TxDataK     ;
  logic         [NUM_LANES-1:0]RxValid     ;
  logic  [NUM_LANES-1:0][129:0]RxData      ;
  logic         [NUM_LANES-1:0]RxDataK     ;

  //-----------------------------------------------------------
  // Per-lane Detect.Quiet / Detect.Active control+status signals.
  // TxDetectRx is MAC(LTSSM)->PHY: asserted by the MAC driver to
  // request receiver detection on that lane.
  // PhyStatus/RxStatus are PHY->MAC: driven by the PMA driver in
  // response, once per lane.
  //-----------------------------------------------------------
  logic [NUM_LANES-1:0] TxDetectRx;
  logic [NUM_LANES-1:0] TxElecIdle;
  logic [NUM_LANES-1:0] PhyStatus;
  logic  [NUM_LANES-1:0][2:0]RxStatus ;
  logic [NUM_LANES-1:0] RxElecIdle;

  logic [2:0] PowerDown;
  logic [2:0] PCLK_Rate;
  logic [1:0] Rate;
  logic RxWidth;
  logic TxWidth;
  logic DataBusWidth;
endinterface

