interface RX_TL_DL_Interface(input bit CLK, RESETn);
  
  logic        tl_tx_valid;
  logic        tl_tx_ready;
  logic [31:0] tl_tx_data;
  logic        tl_rx_valid;
  logic        tl_rx_ready=1;
  logic [31:0] tl_rx_data;
  logic        tl_rx_completion_sop;
  logic        tl_rx_completion_eop;

  logic        dl_up;
  
  //////  FLOW CONTROL INTERFACE SIGNALS  ///////////
  
  logic [7:0][8]  fc_ph;
  logic [7:0][8]  fc_nph;
  logic [7:0][8]  fc_cmplh;
  logic [7:0][12] fc_pd;
  logic [7:0][12] fc_npd;
  logic [7:0][12] fc_cmpld;

  logic ep_fc_update_valid;
  logic [2:0] ep_fc_update_vc;  

  logic [7:0][8]  ep_fc_ph;
  logic [7:0][8]  ep_fc_nph; 
  logic [7:0][8]  ep_fc_cmplh;
  logic [7:0][12] ep_fc_pd;
  logic [7:0][12] ep_fc_npd; 
  logic [7:0][12] ep_fc_cmpld;
   
endinterface : RX_TL_DL_Interface


