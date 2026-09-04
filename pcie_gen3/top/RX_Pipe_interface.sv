interface pipe_rx_interface #(parameter int unsigned NUM_LANES = `PCIE_NUM_LANES)
                              (input bit PCLK, input bit RESET);
  // Data Stream signals - genuine per-lane arrays (see
  // TX_Pipe_interface.sv for the same note - no generate/assign
  // fan-out here, drivers/monitors handle lanes explicitly).
  logic         [NUM_LANES-1:0]TxDataValid ;
  logic  [NUM_LANES-1:0][129:0]TxData      ;
  logic         [NUM_LANES-1:0]RxValid     ;
  logic  [NUM_LANES-1:0][129:0]RxData      ;

  // Per-lane Detect.Quiet / Detect.Active control+status signals
  // (identical semantics to TX_Pipe_interface.sv, mirrored for
  // the EP side).
  logic [NUM_LANES-1:0] TxDetectRx;
  logic [NUM_LANES-1:0] TxElecIdle;
  logic [NUM_LANES-1:0] PhyStatus;
  logic  [NUM_LANES-1:0][2:0]RxStatus ;
  logic [NUM_LANES-1:0] RxElecIdle;

  logic [2:0] PCLK_Rate;
  logic [1:0] Rate;
endinterface

