interface RX_DLL_PCS_Interface(input bit CLK, input bit RESET);
  
  logic        dl_tx_valid;
  logic        dl_tx_ready;
  logic [31:0] dl_tx_data;
  logic        dl_rx_valid;
  logic        dl_rx_ready;
  logic [31:0] dl_rx_data;
  logic        dl_packet;
  logic        tl_packet;
  logic        dl_mac_packet;
  logic        tl_mac_packet;
  logic        phy_link_up=1;
 
endinterface : RX_DLL_PCS_Interface
