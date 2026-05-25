interface RX_TL_DL_Interface(input bit CLK, RESET);
  
  logic        tl_tx_valid;
  logic        tl_tx_ready;
  logic [31:0] tl_tx_data;
  logic        tl_rx_valid;
  logic        tl_rx_ready;
  logic [31:0] tl_rx_data;
   
endinterface : RX_TL_DL_Interface