interface TX_TL_DL_Interface(input bit CLK, RESET);
  
  logic        tl_tx_valid;
  logic        tl_tx_ready;
  logic [31:0] tl_tx_data;
  logic        tl_rx_valid;
  logic        tl_rx_ready;
  logic [31:0] tl_rx_data;
  logic        tl_tx_request_sop;
  logic        tl_tx_request_eop;

  logic        dl_up;
  
  logic [7:0][8] fc_ph;
  logic [7:0][8] fc_nph;
  logic [7:0][8] fc_cmplh;
  logic [7:0][12] fc_pd;
  logic [7:0][12] fc_npd;
  logic [7:0][12] fc_cmpld;

  
  logic rc_fc_update_valid;
  logic [2:0] rc_fc_update_vc;

  logic [7:0][8] rc_fc_ph;
  logic [7:0][8] rc_fc_nph; 
  logic [7:0][8] rc_fc_cmplh;
  logic [7:0][12] rc_fc_pd;
  logic [7:0][12] rc_fc_npd; 
  logic [7:0][12] rc_fc_cmpld;
 
endinterface : TX_TL_DL_Interface

