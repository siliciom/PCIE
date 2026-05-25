interface RX_DLL_PCS_Interface(input bit CLK);
  
  logic        dl_tx_valid;
  logic        dl_tx_ready;
  logic [31:0] dl_tx_data;
  logic        dl_rx_valid;
  logic        dl_rx_ready;
  logic [31:0] dl_rx_data;
   
endinterface : RX_DLL_PCS_Interface