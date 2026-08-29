`uvm_analysis_imp_decl(_TX)
`uvm_analysis_imp_decl(_RX)
`uvm_analysis_imp_decl(_FC)
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_fc)

class PCIe_DLL_Driver extends uvm_driver #(Sequence_item);

  `uvm_component_utils(PCIe_DLL_Driver)

  env_cfg cfg;
  string  tag;

  //-----------------------------------------------------------
  // DLL/PHY-layer error injection: cfg.inject_err (err_inject_e,
  // declared on env_cfg - see env/env_config.sv). A test sets it
  // directly on this specific driver instance's own cfg handle -
  // e.g. RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err -
  // so the injection direction (RC->EP vs EP->RC) is simply
  // whichever side's cfg the test touches; RC and EP each own a
  // distinct env_cfg instance so there is no cross-talk.
  //
  // One-shot scenarios (ERR_LCRC, ERR_DLLP_CRC, ERR_SEQ_NUM,
  // ERR_STP) are consumed and reset to ERR_NONE the very next time
  // the corresponding code path below runs, so they never leak
  // into subsequent, unrelated transactions. Durational scenarios
  // (ERR_REPLAY_ROLLOVER, ERR_REPLAY_TIMER) are read on every
  // Ack/Nak decision for as long as the test holds them, and the
  // test itself resets cfg.inject_err back to ERR_NONE when done.
  //-----------------------------------------------------------


  //-----------------------------------------------------------
  // Role-specific interface handles (already distinctly typed)
  //-----------------------------------------------------------
  virtual TX_DLL_PCS_Interface TX_DLL_PCS;
  virtual TX_TL_DL_Interface   TX_TL_DL;

  virtual RX_DLL_PCS_Interface RX_DLL_PCS;
  virtual RX_TL_DL_Interface   RX_TL_DL;

  //-----------------------------------------------------------
  // RC_MODE analysis imps
  //-----------------------------------------------------------
  uvm_analysis_imp_RX #(Sequence_item, PCIe_DLL_Driver) rc_RX_MD_Recv;
  uvm_analysis_imp_TX #(Sequence_item, PCIe_DLL_Driver) rc_TX_MD_Recv;
  uvm_analysis_imp_FC #(Sequence_item, PCIe_DLL_Driver) rc_FC_MD_Recv;

  //-----------------------------------------------------------
  // EP_MODE analysis imps
  //-----------------------------------------------------------
  uvm_analysis_imp_rx #(Sequence_item, PCIe_DLL_Driver) ep_RX_MD_Recv;
  uvm_analysis_imp_tx #(Sequence_item, PCIe_DLL_Driver) ep_TX_MD_Recv;
  uvm_analysis_imp_fc #(Sequence_item, PCIe_DLL_Driver) ep_FC_MD_Recv;

  //-----------------------------------------------------------
  // RC_MODE state / queues / replay buffer / events
  //-----------------------------------------------------------
  bit [31:0] rc_rx_local_queue[$];
  bit [31:0] rc_tx_local_queue[$];

  bit [11:0] rc_next_transmit_seq = 0;
  bit [11:0] rc_DL_SEQ;
  bit [11:0] rc_aked_seq;
  bit [7:0]  rc_dllp_type;
  bit [11:0] rc_ack_nak_seq;

  typedef struct {
    bit [1:0]  replay_num;    	  
    bit [31:0] packet_q[$];
  } rc_replay_pkt;
  rc_replay_pkt rc_replay_buffer[2048];

  int rc_wr_ptr = 0;
  int rc_rd_ptr = 0;
  int rc_outstanding_pkt_count = 0;

  mailbox #(Sequence_item) rc_tx_pkt_mb;
  mailbox #(Sequence_item) rc_rx_pkt_tlp;
  mailbox #(Sequence_item) rc_rx_pkt_dllp;

  Sequence_item rc_rx_pkt;

  typedef enum bit [1:0] { DL_INACTIVE, DL_INIT_FC1, DL_INIT_FC2, DL_ACTIVE } rc_dl_state_e;
  rc_dl_state_e rc_dl_state;
  bit rc_FL1;
  bit rc_FL2;
  bit rc_dl_up;
  bit rc_initfc1_tx_done;
  bit rc_initfc2_tx_done;

  // Own advertised credits, per VC (from TL layer via write_FC)
  reg [`NUM_VC-1:0][7:0]   rc_fc_ph;
  reg [`NUM_VC-1:0][7:0]   rc_fc_nph;
  reg [`NUM_VC-1:0][7:0]   rc_fc_cmplh;
  reg [`NUM_VC-1:0][11:0]  rc_fc_pd;
  reg [`NUM_VC-1:0][11:0]  rc_fc_npd;
  reg [`NUM_VC-1:0][11:0]  rc_fc_cmpld;
  // Remote credits received via INITFC/UPDATEFC DLLPs, per VC
  reg [`NUM_VC-1:0][7:0]  rc_ph_fc;
  reg [`NUM_VC-1:0][7:0]  rc_nph_fc;
  reg [`NUM_VC-1:0][7:0]  rc_cmplh_fc;
  reg [`NUM_VC-1:0][11:0] rc_pd_fc;
  reg [`NUM_VC-1:0][11:0] rc_npd_fc;
  reg [`NUM_VC-1:0][11:0] rc_cmpld_fc;
  
  bit [11:0] rc_an_seq_no;
 bit [2:0] ep_vc_dllp;
  uvm_event rc_nack_ev;
  uvm_event rc_ack_ev;
  uvm_event rc_fc_received_ev;

  bit rc_replay_timer_running;
  int rc_replay_timer_count;
  int rc_replay_timer_limit =12429;

  // Arbitrates access to TX_DLL_PCS so TLP (rc_send_packet) and
  // ACK/NAK DLLP (rc_send_one_dllp) transmissions never drive the
  // physical interface in the same cycle.
  semaphore rc_phy_tx_key;

  //-----------------------------------------------------------
  // EP_MODE state / queues / replay buffer
  //-----------------------------------------------------------
  bit [31:0] ep_rx_local_queue[$];
  bit [31:0] ep_tx_local_queue[$];
  Sequence_item ep_rx_pkt;

  bit [11:0] ep_rx_next_transmit_seq = 0;
  bit [11:0] ep_RX_DL_SEQ;
  bit [11:0] ep_aked_seq;
  bit [7:0]  ep_dllp_type;
  bit [11:0] ep_ack_nak_seq;

  typedef struct {
    bit [1:0]  ep_replay_num;
    bit [31:0] ep_packet_q[$];
  } ep_replay_pkt;
  ep_replay_pkt ep_replay_buffer[2048];

  int ep_wr_ptr = 0;
  int ep_rd_ptr = 0;
  int ep_outstanding_pkt_count = 0;

  mailbox #(Sequence_item) ep_tx_pkt_mb;
  mailbox #(Sequence_item) ep_rx_pkt_tlp;
  mailbox #(Sequence_item) ep_rx_pkt_dllp;
  mailbox #(bit [2:0]) ep_fc_update_mbx;
  bit ep_rx_new_pkt_available;
  bit ep_tx_new_pkt_available;

  typedef enum bit [1:0] { EP_DL_INACTIVE, EP_DL_INIT_FC1, EP_DL_INIT_FC2, EP_DL_ACTIVE } ep_dl_state_e;
  ep_dl_state_e ep_dl_state;

  bit ep_FL1;
  bit ep_FL2;
  bit ep_dl_up;
  bit ep_initfc1_tx_done;
  bit ep_initfc2_tx_done;

  // Own advertised credits, per VC (from TL layer via write_fc)
  reg [`NUM_VC-1:0][7:0]  ep_fc_ph;
  reg [`NUM_VC-1:0][7:0]  ep_fc_nph;
  reg [`NUM_VC-1:0][7:0]  ep_fc_cmplh;
  reg [`NUM_VC-1:0][11:0] ep_fc_pd;
  reg [`NUM_VC-1:0][11:0] ep_fc_npd;
  reg [`NUM_VC-1:0][11:0] ep_fc_cmpld;
  // Remote credits received via INITFC/UPDATEFC DLLPs, per VC
  reg [`NUM_VC-1:0][7:0]  ep_ph_fc;
  reg [`NUM_VC-1:0][7:0]  ep_nph_fc;
  reg [`NUM_VC-1:0][7:0]  ep_cmplh_fc;
  reg [`NUM_VC-1:0][11:0] ep_pd_fc;
  reg [`NUM_VC-1:0][11:0] ep_npd_fc;
  reg [`NUM_VC-1:0][11:0] ep_cmpld_fc;

  bit [11:0] ep_an_seq_no;

  uvm_event ep_nack_ev;
  uvm_event ep_ack_ev;
    uvm_event ep_fc_received_ev;

  bit ep_replay_timer_running;
  int ep_replay_timer_count;
  int ep_replay_timer_limit = 12429;

  // Arbitrates access to RX_DLL_PCS so TLP (ep_send_packet) and
  // ACK/NAK DLLP (ep_send_one_dllp) transmissions never drive the
  // physical interface in the same cycle.
  semaphore ep_phy_tx_key;

  //-----------------------------------------------------------
  // Shared DLLP type enum (identical both sides)
  //-----------------------------------------------------------
  typedef enum bit [3:0] {
    INITFC1_P    = 4'b0100,
    INITFC1_NP   = 4'b0101,
    INITFC1_CPL  = 4'b0110,
    INITFC2_P    = 4'b1100,
    INITFC2_NP   = 4'b1101,
    INITFC2_CPL  = 4'b1110,
    UPDATEFC_P   = 4'b1000,
    UPDATEFC_NP  = 4'b1001,
    UPDATEFC_CPL = 4'b1010
  } dllp_type_e;

   typedef enum bit [7:0]  {
   ACK_DLLP = 8'b0000_0000,
   NAK_DLLP = 8'b0001_0000
 } ack_nak_e;

  //-----------------------------------------------------------
  // Shared global events / barriers
  //-----------------------------------------------------------
  uvm_event link_up_env;
  uvm_event DL_up_env;/////////rc///////

  uvm_event link_up_env_rx;
  uvm_event DL_up_env_rx;///////ep///////

  function new(string name = "PCIe_DLL_Driver", uvm_component parent = null);
    super.new(name, parent);

    rc_RX_MD_Recv = new("rc_RX_MD_Recv", this);
    rc_TX_MD_Recv = new("rc_TX_MD_Recv", this);
    ep_RX_MD_Recv = new("ep_RX_MD_Recv", this);
    ep_TX_MD_Recv = new("ep_TX_MD_Recv", this);
    rc_FC_MD_Recv = new("rc_FC_MD_Recv", this);
    ep_FC_MD_Recv = new("ep_FC_MD_Recv", this);

    rc_tx_pkt_mb = new();
    rc_rx_pkt_tlp = new();
    rc_rx_pkt_dllp = new();
    ep_tx_pkt_mb = new();    
    ep_rx_pkt_tlp = new();
    ep_rx_pkt_dllp = new();
       ep_fc_update_mbx = new();


    rc_phy_tx_key = new(1);
    ep_phy_tx_key = new(1);

  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_DLL_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();

    case(cfg.mode)

      RC_MODE: begin
        link_up_env = uvm_event_pool::get_global("link_up_env");
        DL_up_env   = uvm_event_pool::get_global("DL_active_env");

	rc_nack_ev = uvm_event_pool::get_global("RC_NAK_DLLP_EVENT");
       rc_ack_ev  = uvm_event_pool::get_global("RC_ACK_DLLP_EVENT");
       	rc_fc_received_ev =uvm_event_pool::get_global("RC_FC_RECEIVED");

        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unable To Access TX_TL_DL", tag))

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
          `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unable To Access TX_DLL_PCS", tag))

              end

      EP_MODE: begin
        link_up_env_rx = uvm_event_pool::get_global("link_up_env_rx");
        DL_up_env_rx   = uvm_event_pool::get_global("DL_active_env_rx");

	ep_nack_ev = uvm_event_pool::get_global("EP_NAK_DLLP_EVENT");
        ep_ack_ev  = uvm_event_pool::get_global("EP_ACK_DLLP_EVENT");
	ep_fc_received_ev =uvm_event_pool::get_global("EP_FC_RECEIVED");

        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("RX_DLL_DRIVER", $sformatf("[%s] Unable To Access RX_TL_DL", tag))

        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
          `uvm_fatal("RX_DLL_DRIVER", $sformatf("[%s] Unable To Access RX_DLL_PCS", tag))

              end

      default: `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  //-----------------------------------------------------------
  // RC_MODE write callbacks
  //-----------------------------------------------------------
function void write_FC(Sequence_item t_x);
    rc_fc_ph    = t_x.fc_ph;
    rc_fc_pd    = t_x.fc_pd;
    rc_fc_nph   = t_x.fc_nph;
    rc_fc_npd   = t_x.fc_npd;
    rc_fc_cmplh = t_x.fc_cmplh;
    rc_fc_cmpld = t_x.fc_cmpld;
     endfunction
  function void write_TX(Sequence_item t_x);
    rc_tx_pkt_mb.try_put(t_x);
  endfunction

  function void write_RX(Sequence_item r_x);
	   if (r_x.rx_data_t.size() > 0 || r_x.rc_ack_nak_seq == 0 || r_x.rc_ack_nak_seq > 0) begin
    rc_an_seq_no = r_x.rc_ack_nak_seq;
        rc_rx_pkt_tlp.try_put(r_x);
end
    if (r_x.dllp_packet_q.size() > 0) begin
        rc_rx_pkt_dllp.try_put(r_x);
     if(r_x.rc_data_type==4'b0100 || r_x.rc_data_type==4'b1000)begin
	rc_ph_fc[r_x.rc_dllp_vc]=r_x.rc_header_pfc;		       
	rc_pd_fc[r_x.rc_dllp_vc]=r_x.rc_data_pfc; 
      rc_fc_received_ev.trigger();
      
	      end 
   if(r_x.rc_data_type==4'b0101 || r_x.rc_data_type==4'b1001)begin
	rc_nph_fc[r_x.rc_dllp_vc]=r_x.rc_header_npfc ;
	rc_npd_fc[r_x.rc_dllp_vc]=r_x.rc_data_npfc;  
	rc_fc_received_ev.trigger();
	      end 
   if(r_x.rc_data_type==4'b0110 || r_x.rc_data_type==4'b1010)begin
	rc_cmplh_fc[r_x.rc_dllp_vc]=r_x.rc_header_cmplfc; 
	rc_cmpld_fc[r_x.rc_dllp_vc]=r_x.rc_data_cmplfc;  
	rc_fc_received_ev.trigger();
 end 
    end

  endfunction

  //-----------------------------------------------------------
  // EP_MODE write callbacks
  //-----------------------------------------------------------
   function void write_fc(Sequence_item t_x);

   if(t_x.ep_updated_credits == 1) begin

    ep_fc_ph[t_x.ep_vc]    = t_x.ep_fc_ph;
    ep_fc_pd[t_x.ep_vc]    = t_x.ep_fc_pd;
    ep_fc_nph[t_x.ep_vc]   = t_x.ep_fc_nph;
    ep_fc_npd[t_x.ep_vc]   = t_x.ep_fc_npd;
    ep_fc_cmplh[t_x.ep_vc] = t_x.ep_fc_cmplh;
    ep_fc_cmpld[t_x.ep_vc] = t_x.ep_fc_cmpld;
    ep_vc_dllp =  t_x.ep_vc;

    `uvm_info("WR_EP_FC_UPDATE",
          $sformatf("EP FC Credits: VC=%0d, PH=%0h, PD=%0d, NPH=%0h, NPD=%0h, CPLH=%0h, CPLD=%0h",
                    t_x.ep_vc,
                    t_x.ep_fc_ph,
                    t_x.ep_fc_pd,
                    t_x.ep_fc_nph,
                    t_x.ep_fc_npd,
                    t_x.ep_fc_cmplh,
                    t_x.ep_fc_cmpld),
          UVM_LOW)
	    ep_fc_update_mbx.try_put(t_x.ep_vc);
  end
   if(ep_dl_up == 0) begin
    ep_fc_ph    = t_x.ep_fc_ph;
    ep_fc_pd    = t_x.ep_fc_pd;
    ep_fc_nph   = t_x.ep_fc_nph;
    ep_fc_npd   = t_x.ep_fc_npd;
    ep_fc_cmplh = t_x.ep_fc_cmplh;
    ep_fc_cmpld = t_x.ep_fc_cmpld;
    end


   endfunction

      function void write_tx(Sequence_item t_x);
        ep_tx_pkt_mb.try_put(t_x);
  endfunction

 function void write_rx(Sequence_item r_x);
    if (r_x.dllp_packet_rx_q.size() > 0) begin
                ep_rx_pkt_dllp.try_put(r_x);
        	 if(r_x.ep_data_type==4'b0100 || r_x.ep_data_type==4'b1000 )begin
	ep_ph_fc[r_x.ep_dllp_vc]=r_x.ep_header_pfc; 		       
	ep_pd_fc[r_x.ep_dllp_vc]=r_x.ep_data_pfc;
	      end 
	   	      if(r_x.ep_data_type==4'b0101 || r_x.ep_data_type==4'b1001)begin
	ep_nph_fc[r_x.ep_dllp_vc]=r_x.ep_header_npfc; 
	ep_npd_fc[r_x.ep_dllp_vc]=r_x.ep_data_npfc;
	      end 
	   	      if(r_x.ep_data_type==4'b0110 || r_x.ep_data_type==4'b1010)begin
	ep_cmplh_fc[r_x.ep_dllp_vc]=r_x.ep_header_cmplfc; 
	ep_cmpld_fc[r_x.ep_dllp_vc]=r_x.ep_data_cmplfc;

	      end 

   end
    if (r_x.rx_data.size() > 0 || r_x.ep_ack_nak_seq == 0 || r_x.ep_ack_nak_seq > 0) begin
        ep_an_seq_no = r_x.ep_ack_nak_seq;
                ep_rx_pkt_tlp.try_put(r_x);
    end
endfunction
  //-----------------------------------------------------------
  // Shared helpers - byte-identical pure functions across RC/EP
  //-----------------------------------------------------------
function bit [15:0] crc16
(
  input bit [31:0] data
);

  bit [15:0] crc;
    bit [15:0] crc_16;
  bit feedback;

  crc = 16'hFFFF;  // Initial value

  for (int b = 0; b < 32; b++) begin
    feedback = crc[15] ^ data[b];

    crc = crc << 1;

    if (feedback)
      crc ^= 16'h100B;
  end

  crc = ~crc;

  for (int byte_num = 0; byte_num < 2; byte_num++) begin

       for (int bit_num = 0; bit_num < 8; bit_num++) begin

         crc_16[byte_num*8 + bit_num] = crc[byte_num*8 + (7-bit_num)];

       end

     end

  return crc_16;
endfunction

  function bit [47:0] create_dllp(
    dllp_type_e dllp_type,
    bit [2:0]   vc_id,
    bit [7:0]   header_credit,
    bit [11:0]  data_credit
  );
    bit [47:0] dllp_pkt;
    bit [15:0] dllp_crc;
    dllp_pkt[7:4] = dllp_type;
    dllp_pkt[3]   = 1'b0;
    dllp_pkt[2:0] = vc_id;
    dllp_pkt[9:8]   = 2'b00;
    dllp_pkt[17:10] = header_credit;
    dllp_pkt[19:18] = 2'b00;
    dllp_pkt[31:20] = data_credit;
    dllp_crc = crc16(dllp_pkt[31:0]);
    dllp_pkt[47:32] = dllp_crc;
    return dllp_pkt;
  endfunction

  function bit [31:0] rc_calculate_lcrc(input bit [31:0] pkt_q[$]);
    bit [31:0] crc;
      bit [31:0] lcrc;
    bit data_bit;
    bit feedback;
       
    crc = 32'hFFFF_FFFF;
    foreach(pkt_q[i]) begin
      for(int b = 0; b < 32; b++) begin
        data_bit = pkt_q[i][b];
        feedback = crc[0] ^ data_bit;
        crc = crc >> 1;
        if(feedback)
           crc ^= 32'hEDB8_8320;// Standard Polynomial - 04C11DB7

      end
    end
   crc = ~crc;

     for (int byte_num = 0; byte_num < 4; byte_num++) begin

       for (int bit_num = 0; bit_num < 8; bit_num++) begin

         lcrc[byte_num*8 + bit_num] = crc[byte_num*8 + (7-bit_num)];

       end

     end

     return lcrc;
  endfunction : rc_calculate_lcrc

    function bit [31:0] ep_calculate_lcrc(input bit [31:0] pkt_q[$]);
    bit [31:0] crc;
    bit [31:0] lcrc;    
    bit data_bit;
    bit feedback;

    crc = 32'hFFFF_FFFF;
    foreach(pkt_q[i]) begin
      for(int b = 0; b < 32; b++) begin
        data_bit = pkt_q[i][b];
        feedback = crc[0] ^ data_bit;
        crc = crc >> 1;
        if(feedback)
         crc ^= 32'hEDB8_8320;// Standard Polynomial - 04C11DB7
      end
    end
     crc = ~crc;

    for (int byte_num = 0; byte_num < 4; byte_num++) begin

       for (int bit_num = 0; bit_num < 8; bit_num++) begin

         lcrc[byte_num*8 + bit_num] = crc[byte_num*8 + (7-bit_num)];

       end

     end

     return lcrc;
  endfunction : ep_calculate_lcrc

  
    function bit [47:0] ack_nak_dllp
  (
    ack_nak_e   ack_nak_type,
    bit [11:0]  ack_nak_seq
  );

    bit [47:0] dllp_pkt;
    bit [15:0] dllp_crc;

     dllp_pkt[31:24] = ack_nak_type;

     dllp_pkt[23:12]   = 2'b00;
     dllp_pkt[11:0] = ack_nak_seq;

    dllp_crc = crc16(dllp_pkt[31:0]);

    // ERR_DLLP_CRC injection: corrupt the just-computed 16-bit
    // DLLP CRC so the far end's own crc16() recompute mismatches ->
    // Bad-DLLP -> NAK path. This function is shared by the RC and
    // EP driver instances (each with its own `cfg`), so checking
    // `cfg.inject_err` here is automatically direction-selective.
    if (cfg.inject_err == ERR_DLLP_CRC) begin
      dllp_crc ^= 16'hFFFF;
      cfg.inject_err = ERR_NONE;
    end

    dllp_pkt[47:32] = dllp_crc;

    return dllp_pkt;

  endfunction

  //-----------------------------------------------------------
  // RC_MODE tasks - preserved exactly as PCIe_DLL_Driver.sv
  //-----------------------------------------------------------
  
   task rc_process_dllp();

   Sequence_item pkt; 

   forever begin
     
       rc_rx_pkt_dllp.get(pkt);

        rc_dllp_type   = pkt.rc_ack_nack;
                        
        rc_ack_nak_seq = pkt.rc_ack_nack_seq;
      
      if (rc_ack_nak_seq == rc_aked_seq) begin
	      if(rc_dllp_type == 8'b0000_0000)begin
		      rc_ackd_seq(rc_dllp_type, rc_ack_nak_seq);
	      end
	      else begin
            rc_nak(rc_dllp_type, rc_ack_nak_seq);
              end
   
      end
        else begin
            rc_ackd_seq(rc_dllp_type, rc_ack_nak_seq);
        end

   end

   	
endtask

task rc_ackd_seq(
    input bit [7:0]  rc_dllp_type,
    input bit [11:0] rc_ack_nak_seq
);
begin

    bit [11:0] seq;

    rc_aked_seq = rc_ack_nak_seq;

    if (rc_dllp_type == 8'b0000_0000) begin

        while (rc_rd_ptr != rc_wr_ptr) begin

            seq = rc_replay_buffer[rc_rd_ptr].packet_q[0][11:0];

            // Delete the ACKed entry
            if (seq == rc_ack_nak_seq) begin

                rc_replay_buffer[rc_rd_ptr].replay_num = 0;

                `uvm_info("DLL_DRV_RC", $sformatf("replay-buf: DELETE ACKED seq=%0d rd_ptr=%0d qsize=%0d outstanding=%0d",
                         seq, rc_rd_ptr, rc_replay_buffer[rc_rd_ptr].packet_q.size(), rc_outstanding_pkt_count), UVM_MEDIUM)

                rc_replay_buffer[rc_rd_ptr].packet_q.delete();

                rc_outstanding_pkt_count--;

                rc_rd_ptr = (rc_rd_ptr + 1) % 2048;

                // Stop after deleting ACKed sequence
                break;
            end

            // Delete entries preceding the ACKed sequence
            else begin

                `uvm_info("DLL_DRV_RC", $sformatf("replay-buf: DELETE PRECEDING seq=%0d rd_ptr=%0d qsize=%0d outstanding=%0d",
                         seq, rc_rd_ptr, rc_replay_buffer[rc_rd_ptr].packet_q.size(), rc_outstanding_pkt_count), UVM_MEDIUM)

                rc_replay_buffer[rc_rd_ptr].packet_q.delete();

                rc_outstanding_pkt_count--;

                rc_rd_ptr = (rc_rd_ptr + 1) % 2048;
            end

        end

        // Update replay timer after deleting ACKed packets
        if (rc_outstanding_pkt_count == 0) begin
            rc_replay_timer_running = 0;
            rc_replay_timer_count   = 0;
        end
        else begin
            rc_replay_timer_running = 1;
            rc_replay_timer_count   = 0;
        end

    end
    else begin
        rc_nak(rc_dllp_type, rc_ack_nak_seq);
    end

end
endtask

  task rc_nak(input bit [7:0]rc_dllp_type, input bit [11:0] rc_ack_nak_seq);
    
    int rc_replay_ptr;

    rc_replay_ptr = rc_rd_ptr;

    while(rc_replay_ptr != rc_wr_ptr) begin
	        if(rc_replay_buffer[rc_replay_ptr].replay_num == 3) begin

            `uvm_error("REPLAY",
                $sformatf("Seq %0d exceeded replay limit",
                rc_replay_buffer[rc_replay_ptr].packet_q[0][11:0]))

            break;
        end

        rc_replay_buffer[rc_replay_ptr].replay_num++;

        rc_send_packet(rc_replay_buffer[rc_replay_ptr].packet_q);

        rc_replay_ptr = (rc_replay_ptr + 1) % 2048;
    end

    	rc_replay_timer_count=0;
        rc_replay_timer_running=1;
	if(cfg.replay_en) begin
          rc_replay_timer();
        end
    
endtask

task rc_replay_timer();

forever begin

    @(posedge TX_DLL_PCS.CLK);

    if(rc_replay_timer_running)
    begin
        rc_replay_timer_count++;

        if(rc_replay_timer_count >= rc_replay_timer_limit)
        begin

            rc_replay_timer_count=0;

            rc_nak(NAK_DLLP,rc_aked_seq);

        end
    end

end

endtask

task rc_send_one_dllp(bit [47:0] dllp_pkt);

    rc_phy_tx_key.get(1);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b1;
    TX_DLL_PCS.dl_packet <= 1'b1;
    TX_DLL_PCS.dl_tx_data  <= dllp_pkt[31:0];
      `uvm_info("DLLP_TX",
            $sformatf("RC: Sending DLLP DATA[0] to TX_DLL_PCS.dl_tx_data = %08h",
                      dllp_pkt[31:0]),
            UVM_LOW)

    wait(TX_DLL_PCS.dl_tx_ready);
    @(posedge TX_DLL_PCS.CLK);

    TX_DLL_PCS.dl_tx_data <= {
                               dllp_pkt[47:32]
			       , 16'h0000
                             };
  `uvm_info("DLLP_TX",
            $sformatf("RC: Sending DLLP DATA[1] to TX_DLL_PCS.dl_tx_data = %08h",
                      {dllp_pkt[47:32], 16'h0000}),
            UVM_LOW)

    wait(TX_DLL_PCS.dl_tx_ready);

    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet   <= 1'b0;

    rc_phy_tx_key.put(1);

  endtask

task rc_send_initfc1_dllps();

    bit [47:0] initfc1_p;
    bit [47:0] initfc1_np;
    bit [47:0] initfc1_cpl;

    // One P/NP/CPL triplet per VC - 8VC support (NUM_VC=`NUM_VC)
    for (int vc = 0; vc < `NUM_VC; vc++) begin

      initfc1_p = create_dllp(INITFC1_P,
                              vc[2:0],
                              rc_fc_ph[vc],
                              rc_fc_pd[vc]);

      initfc1_np = create_dllp(INITFC1_NP,
                               vc[2:0],
                               rc_fc_nph[vc],
                               rc_fc_npd[vc]);

      initfc1_cpl = create_dllp(INITFC1_CPL,
                                vc[2:0],
                                rc_fc_cmplh[vc],
                                rc_fc_cmpld[vc]);

      rc_send_one_dllp(initfc1_p);
       rc_send_one_dllp(initfc1_np);
      rc_send_one_dllp(initfc1_cpl);
    end

    rc_initfc1_tx_done = 1'b1;

  endtask

task rc_send_initfc2_dllps();

    bit [47:0] initfc2_p;
    bit [47:0] initfc2_np;
    bit [47:0] initfc2_cpl;

    // One P/NP/CPL triplet per VC - 8VC support (NUM_VC=`NUM_VC)
    for (int vc = 0; vc < `NUM_VC; vc++) begin

      initfc2_p = create_dllp(INITFC2_P,
                              vc[2:0],
                              rc_fc_ph[vc],
                              rc_fc_pd[vc]);

      initfc2_np = create_dllp(INITFC2_NP,
                               vc[2:0],
                               rc_fc_nph[vc],
                               rc_fc_npd[vc]);

      initfc2_cpl = create_dllp(INITFC2_CPL,
                                vc[2:0],
                                rc_fc_cmplh[vc],
                                rc_fc_cmpld[vc]);

      rc_send_one_dllp(initfc2_p);
      rc_send_one_dllp(initfc2_np);
      rc_send_one_dllp(initfc2_cpl);

    end

    rc_initfc2_tx_done = 1'b1;

  endtask

  task rc_Updatefc_dllps();

    bit [47:0] updatefc_p;
    bit [47:0] updatefc_np;
    bit [47:0] updatefc_cpl;

    // One P/NP/CPL triplet per VC - 8VC support (NUM_VC=`NUM_VC)
    for (int vc = 0; vc < 1; vc++) begin

      updatefc_p = create_dllp(UPDATEFC_P,
                              vc[2:0],
                              rc_fc_ph[vc],
                              rc_fc_pd[vc]);

      updatefc_np = create_dllp(UPDATEFC_NP,
                               vc[2:0],
                               rc_fc_nph[vc],
                               rc_fc_npd[vc]);

      updatefc_cpl = create_dllp(UPDATEFC_CPL,
                                vc[2:0],
                                rc_fc_cmplh[vc],
                                rc_fc_cmpld[vc]);

      rc_send_one_dllp(updatefc_p);
      rc_send_one_dllp(updatefc_np);
      rc_send_one_dllp(updatefc_cpl);

    end

  endtask
  task RC_ACK_NAK_dllps();

  bit [47:0] rc_ack_dllp;
  bit [47:0] rc_nak_dllp;

  forever begin

    fork

      begin
        rc_ack_ev.wait_trigger();

        // ERR_REPLAY_ROLLOVER / ERR_REPLAY_TIMER injection: while
        // cfg.inject_err is held at one of these by a test, RC
        // keeps NAK'ing instead of ACK'ing every packet it receives
        // from the EP, forcing the EP's replay-buffer logic to keep
        // retransmitting the same packet (replay_num increments
        // each time) until either it hits the existing
        // uvm_error("REPLAY", "... exceeded replay limit") check,
        // or (if the test withholds any Ack at all) the EP's own
        // replay timer expires and re-kicks a NAK-driven replay.
        // Durational, not one-shot - the test itself resets
        // cfg.inject_err back to ERR_NONE when it's done stalling.
        if (cfg.inject_err inside {ERR_REPLAY_ROLLOVER, ERR_REPLAY_TIMER}) begin
          rc_nak_dllp = ack_nak_dllp(NAK_DLLP, rc_an_seq_no);
          rc_send_one_dllp(rc_nak_dllp);
        end
        else begin
          rc_ack_dllp = ack_nak_dllp(ACK_DLLP, rc_an_seq_no);
          rc_send_one_dllp(rc_ack_dllp);
        end
      end

      begin
        rc_nack_ev.wait_trigger();

        rc_nak_dllp = ack_nak_dllp(NAK_DLLP, rc_an_seq_no);

        rc_send_one_dllp(rc_nak_dllp);
      end

    join_any

    disable fork;

  end

endtask
task rc_fc_to_tl();

//rc_fc_received_ev.wait_trigger();

@(posedge TX_TL_DL.CLK);

// Whole-array (all `NUM_VC VCs) forward to the TL layer in one shot
TX_TL_DL.rc_fc_ph    <= rc_ph_fc;
TX_TL_DL.rc_fc_pd    <= rc_pd_fc;

TX_TL_DL.rc_fc_nph   <= rc_nph_fc;
TX_TL_DL.rc_fc_npd   <= rc_npd_fc;

TX_TL_DL.rc_fc_cmplh <= rc_cmplh_fc;
TX_TL_DL.rc_fc_cmpld <= rc_cmpld_fc;

endtask
task rc_fc_update_to_tl();
  forever begin
    rc_fc_received_ev.wait_trigger();
    rc_fc_to_tl();
  end
endtask

task rc_rx_recived_packet
  (
    input bit [31:0] rx_packet_recived[$]
  );

    `uvm_info("DLL_DRV_RC", $sformatf("DLL->TL(RC) push: %0d DW firstDW=%08h",
             rx_packet_recived.size(), rx_packet_recived.size() ? rx_packet_recived[0] : 32'h0), UVM_MEDIUM)

    foreach(rx_packet_recived[i]) begin
      wait(TX_TL_DL.tl_rx_ready);

      @(posedge TX_TL_DL.CLK);
       TX_TL_DL.tl_rx_valid <= 1'b1;
       TX_TL_DL.tl_rx_data <= rx_packet_recived[i];

      `uvm_info("DLL_DRV_RC", $sformatf("DLL->TL(RC) DW[%0d] = %08h", i, rx_packet_recived[i]), UVM_HIGH)

    end
      @(posedge TX_TL_DL.CLK);

    TX_TL_DL.tl_rx_valid <= 1'b0;

  endtask

task rc_send_packet
  (
    input bit [31:0] rx_packet_send[$]
  );

    rc_phy_tx_key.get(1);

    foreach(rx_packet_send[i]) begin

     @(posedge TX_DLL_PCS.CLK);
      wait(TX_DLL_PCS.dl_tx_ready);

      TX_DLL_PCS.dl_tx_valid <= 1'b1;
      // ERR_STP injection: corrupt the packet-type/start marker
      // for this burst so the receiver's dispatcher (dl_mac_packet/
      // tl_mac_packet) doesn't recognize it as a TLP - the DLL
      // monitor's framing watchdog flags the resulting "valid
      // transfer, no recognized marker" anomaly.
      TX_DLL_PCS.tl_packet <= (cfg.inject_err == ERR_STP) ? 1'b0 : 1'b1;

      TX_DLL_PCS.dl_tx_data <= rx_packet_send[i];
          `uvm_info("TLP_TX",
              $sformatf("RC: Sending DATA[%0d] to TX_DLL_PCS.dl_tx_data = %08h",
                        i, rx_packet_send[i]),
              UVM_LOW)


    end
     @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
      TX_DLL_PCS.tl_packet <= 1'b0;

    rc_phy_tx_key.put(1);
    if (cfg.inject_err == ERR_STP)
      cfg.inject_err = ERR_NONE;

  endtask

task rc_tx_recived_packet
  (
    input bit [31:0] tx_packet_recived[$]
  );
    
    bit [31:0] TX_DLP_PACKET[$];
    bit [31:0] rx_lcrc;
    
    wait(rc_outstanding_pkt_count < 2048);

      // Assign Sequence Number

      rc_DL_SEQ = rc_next_transmit_seq;

      // ERR_SEQ_NUM injection: skip the next sequence number
      // instead of incrementing by 1, so the far end's DL monitor
      // sees seq_no > expected (a gap) and NAKs + the gapped
      // packet gets replayed once the sender retransmits from its
      // buffer.
      if (cfg.inject_err == ERR_SEQ_NUM) begin
        rc_next_transmit_seq = (rc_next_transmit_seq + 2) % 4096;
        cfg.inject_err       = ERR_NONE;
      end
      else begin
        rc_next_transmit_seq = (rc_next_transmit_seq + 1) % 4096;
      end

//       
      // Build DLL Packet

      TX_DLP_PACKET.delete();

      // Add Sequence Number

    TX_DLP_PACKET.push_back({20'd0, rc_DL_SEQ});

      `uvm_info("DLL_DRV_RC", $sformatf("TX TLP framing: assigned seq=%0h", rc_DL_SEQ), UVM_MEDIUM)

    for(int i = 0; i < tx_packet_recived.size(); i++) begin
      TX_DLP_PACKET.push_back(tx_packet_recived[i]);
    end

      rx_lcrc = rc_calculate_lcrc(TX_DLP_PACKET);

      // ERR_LCRC injection: corrupt the just-computed LCRC before
      // it is appended, so the EP's DL monitor's own
      // rc_calculate_lcrc()-equivalent recompute is guaranteed to
      // mismatch -> Bad LCRC -> NAK + replay from the buffer below.
      if (cfg.inject_err == ERR_LCRC) begin
        rx_lcrc        = ~rx_lcrc;
        cfg.inject_err = ERR_NONE;
      end

      // Append LCRC

    TX_DLP_PACKET.push_back(rx_lcrc);

      `uvm_info("DLL_DRV_RC", $sformatf("TX TLP framed: seq=%0h lcrc=%08h total=%0d DW (seq+hdr+pyld+ecrc+lcrc)",
               rc_DL_SEQ, rx_lcrc, TX_DLP_PACKET.size()), UVM_MEDIUM)

      // Store Into Replay Buffer

    rc_replay_buffer[rc_wr_ptr].packet_q = TX_DLP_PACKET;

//       
      // Update Write Pointer

    rc_wr_ptr = (rc_wr_ptr + 1) % 2048;

      // Increment Outstanding Packet Count

      rc_outstanding_pkt_count++;

      // Send Packet

      rc_send_packet(TX_DLP_PACKET);
        if(rc_outstanding_pkt_count==1)
      begin
	      rc_replay_timer_running=1;
	      rc_replay_timer_count=0;
      end
   
  endtask

  //-----------------------------------------------------------
  // EP_MODE tasks - preserved exactly as RX_DLL_Driver.sv
  //-----------------------------------------------------------

     task ep_process_dllp();

 
    
    forever begin
	       Sequence_item pkt;

        ep_rx_pkt_dllp.get(pkt);
        
        ep_dllp_type   = pkt.ep_ack_nack;
	                        
        ep_ack_nak_seq = pkt.ep_ack_nack_seq;

      if (ep_ack_nak_seq == ep_aked_seq) begin

            if(ep_dllp_type == 8'b0000_0000)begin
		      ep_ackd_seq(ep_dllp_type, ep_ack_nak_seq);
	      end
	      else begin
            ep_nak(ep_dllp_type, ep_ack_nak_seq);
              end
   
      end
        else begin
          ep_ackd_seq(ep_dllp_type, ep_ack_nak_seq);
        end

    end

endtask

 task ep_ackd_seq(
    input bit [7:0]  ep_dllp_type,
    input bit [11:0] ep_ack_nak_seq
);
begin

    bit [11:0] seq;

    ep_aked_seq = ep_ack_nak_seq;

    if (ep_dllp_type == 8'b0000_0000) begin

        while (ep_rd_ptr != ep_wr_ptr) begin

            seq = ep_replay_buffer[ep_rd_ptr].ep_packet_q[0][11:0];

            // Delete the ACKed entry
            if (seq == ep_ack_nak_seq) begin

                ep_replay_buffer[ep_rd_ptr].ep_replay_num = 0;

                `uvm_info("DLL_DRV_EP", $sformatf("replay-buf: DELETE ACKED seq=%0d rd_ptr=%0d qsize=%0d outstanding=%0d",
                         seq, ep_rd_ptr, ep_replay_buffer[ep_rd_ptr].ep_packet_q.size(), ep_outstanding_pkt_count), UVM_MEDIUM)

                ep_replay_buffer[ep_rd_ptr].ep_packet_q.delete();

                ep_outstanding_pkt_count--;

                ep_rd_ptr = (ep_rd_ptr + 1) % 2048;

                // Stop after deleting the ACKed sequence
                break;
            end

            // Delete entries preceding the ACKed sequence
            else begin

                `uvm_info("DLL_DRV_EP", $sformatf("replay-buf: DELETE PRECEDING seq=%0d rd_ptr=%0d qsize=%0d outstanding=%0d",
                         seq, ep_rd_ptr, ep_replay_buffer[ep_rd_ptr].ep_packet_q.size(), ep_outstanding_pkt_count), UVM_MEDIUM)

                ep_replay_buffer[ep_rd_ptr].ep_packet_q.delete();

                ep_outstanding_pkt_count--;

                ep_rd_ptr = (ep_rd_ptr + 1) % 2048;
            end

        end

        // Update replay timer after ACK processing
        if (ep_outstanding_pkt_count == 0) begin
            ep_replay_timer_running = 0;
            ep_replay_timer_count   = 0;
        end
        else begin
            ep_replay_timer_running = 1;
            ep_replay_timer_count   = 0;
        end

    end
    else begin
        ep_nak(ep_dllp_type, ep_ack_nak_seq);
    end

end
endtask

task ep_nak(input bit [7:0]ep_dllp_type, input bit [11:0] ep_ack_nak_seq);
    
    int ep_replay_ptr;

    ep_replay_ptr = ep_rd_ptr;

    while(ep_replay_ptr != ep_wr_ptr) begin

      if(ep_replay_buffer[ep_replay_ptr].ep_replay_num == 3) begin

            `uvm_error("EP_REPLAY",
                $sformatf("Seq %0d exceeded replay limit",
                          ep_replay_buffer[ep_replay_ptr].ep_packet_q[0][11:0]))

            break;
        end

      ep_replay_buffer[ep_replay_ptr].ep_replay_num++;

      ep_send_packet(ep_replay_buffer[ep_replay_ptr].ep_packet_q);

      ep_replay_ptr = (ep_replay_ptr + 1) % 2048;

    end
    	ep_replay_timer_count=0;
        ep_replay_timer_running=1;
	if(cfg.replay_en) begin
        ep_replay_timer();
        end
endtask

task ep_replay_timer();

forever begin

    @(posedge RX_DLL_PCS.CLK);

    if(ep_replay_timer_running)
    begin
        ep_replay_timer_count++;

        if(ep_replay_timer_count >= ep_replay_timer_limit)
        begin

            ep_replay_timer_count=0;

            ep_nak(NAK_DLLP,ep_aked_seq);

        end
    end

end

endtask

  task ep_send_one_dllp(bit [47:0] dllp_pkt);
    ep_phy_tx_key.get(1);

    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b1;

    RX_DLL_PCS.dl_packet <= 1'b1;
    RX_DLL_PCS.dl_tx_data  <= dllp_pkt[31:0];

  `uvm_info("DLLP_TX",
            $sformatf("EP: Sending DLLP DATA[0] to RX_DLL_PCS.dl_tx_data = %08h",
                      dllp_pkt[31:0]),
            UVM_LOW)
    

    wait(RX_DLL_PCS.dl_tx_ready);
    @(posedge RX_DLL_PCS.CLK);

    RX_DLL_PCS.dl_tx_data <= {
                               dllp_pkt[47:32],
                               16'h0000
                             };
   `uvm_info("DLLP_TX",
            $sformatf("EP: Sending DLLP DATA[1] to RX_DLL_PCS.dl_tx_data = %08h",
                      {dllp_pkt[47:32], 16'h0000}),
            UVM_LOW)

    wait(RX_DLL_PCS.dl_tx_ready);

    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet   <= 1'b0;

    ep_phy_tx_key.put(1);

  endtask

task ep_send_initfc1_dllps();

    bit [47:0] initfc1_p;
    bit [47:0] initfc1_np;
    bit [47:0] initfc1_cpl;

    // One P/NP/CPL triplet per VC - 8VC support (NUM_VC=`NUM_VC)
    for (int vc = 0; vc < `NUM_VC; vc++) begin

      initfc1_p = create_dllp(INITFC1_P,
                              vc[2:0],
                              ep_fc_ph[vc],
                              ep_fc_pd[vc]);

      initfc1_np = create_dllp(INITFC1_NP,
                               vc[2:0],
                               ep_fc_nph[vc],
                               ep_fc_npd[vc]);

      initfc1_cpl = create_dllp(INITFC1_CPL,
                                vc[2:0],
                                ep_fc_cmplh[vc],
                                ep_fc_cmpld[vc]);

      ep_send_one_dllp(initfc1_p);
      ep_send_one_dllp(initfc1_np);
      ep_send_one_dllp(initfc1_cpl);

    end

     ep_initfc1_tx_done = 1'b1;

  endtask

task ep_send_initfc2_dllps();

    bit [47:0] initfc2_p;
    bit [47:0] initfc2_np;
    bit [47:0] initfc2_cpl;

    // One P/NP/CPL triplet per VC - 8VC support (NUM_VC=`NUM_VC)
    for (int vc = 0; vc < `NUM_VC; vc++) begin

      initfc2_p = create_dllp(INITFC2_P,
                              vc[2:0],
                              ep_fc_ph[vc],
                              ep_fc_pd[vc]);

      initfc2_np = create_dllp(INITFC2_NP,
                               vc[2:0],
                               ep_fc_nph[vc],
                               ep_fc_npd[vc]);

      initfc2_cpl = create_dllp(INITFC2_CPL,
                                vc[2:0],
                                ep_fc_cmplh[vc],
                                ep_fc_cmpld[vc]);

      ep_send_one_dllp(initfc2_p);
      ep_send_one_dllp(initfc2_np);
      ep_send_one_dllp(initfc2_cpl);

    end

        ep_initfc2_tx_done = 1'b1;

  endtask

  task ep_Updatefc_dllps(input bit [2:0] vc);

  bit [47:0] updatefc_p;
  bit [47:0] updatefc_np;
  bit [47:0] updatefc_cpl;

    updatefc_p = create_dllp(UPDATEFC_P,
                             vc,
                             ep_fc_ph[vc],
                             ep_fc_pd[vc]);

    updatefc_np = create_dllp(UPDATEFC_NP,
                              vc,
                              ep_fc_nph[vc],
                              ep_fc_npd[vc]);

    updatefc_cpl = create_dllp(UPDATEFC_CPL,
                               vc,
                               ep_fc_cmplh[vc],
                               ep_fc_cmpld[vc]);

    ep_send_one_dllp(updatefc_p);

     ep_send_one_dllp(updatefc_np);
 
    ep_send_one_dllp(updatefc_cpl);

endtask

   task EP_ACK_NAK_dllps();

  bit [47:0] ack_dllp;
  bit [47:0] nak_dllp;

  forever begin

    fork

      begin
        ep_ack_ev.wait_trigger();

        // ERR_REPLAY_ROLLOVER / ERR_REPLAY_TIMER injection
        // (EP->RC direction) - see the RC-side RC_ACK_NAK_dllps()
        // for the fully-commented version.
        if (cfg.inject_err inside {ERR_REPLAY_ROLLOVER, ERR_REPLAY_TIMER}) begin
          nak_dllp = ack_nak_dllp(NAK_DLLP, ep_an_seq_no);
          ep_send_one_dllp(nak_dllp);
        end
        else begin
          ack_dllp = ack_nak_dllp(ACK_DLLP, ep_an_seq_no);
          ep_send_one_dllp(ack_dllp);
        end
      end

      begin
        ep_nack_ev.wait_trigger();

        nak_dllp = ack_nak_dllp(NAK_DLLP, ep_an_seq_no);

        ep_send_one_dllp(nak_dllp);
      end

    join_any

    disable fork;

  end

endtask
task ep_fc_to_tl();


@(posedge RX_TL_DL.CLK);

// Whole-array (all `NUM_VC VCs) forward to the TL layer in one shot
RX_TL_DL.ep_fc_ph    <= ep_ph_fc;
RX_TL_DL.ep_fc_pd    <= ep_pd_fc;

RX_TL_DL.ep_fc_nph   <= ep_nph_fc;
RX_TL_DL.ep_fc_npd   <= ep_npd_fc;

RX_TL_DL.ep_fc_cmplh <= ep_cmplh_fc;
RX_TL_DL.ep_fc_cmpld <= ep_cmpld_fc;

endtask

task ep_rx_recived_packet
  (
    input bit [31:0] rx_packet_recived[$]
  );

    foreach(rx_packet_recived[i]) begin

      wait(RX_TL_DL.tl_rx_ready);
      
      @(posedge RX_TL_DL.CLK);

      RX_TL_DL.tl_rx_valid <= 1'b1;

      RX_TL_DL.tl_rx_data <= rx_packet_recived[i];

      `uvm_info("DLL_DRV_EP", $sformatf("DLL->TL(EP) DW[%0d] = %08h", i, rx_packet_recived[i]), UVM_HIGH)

    end
      @(posedge RX_TL_DL.CLK);

    RX_TL_DL.tl_rx_valid <= 1'b0;

  endtask

task ep_send_packet
  (
    input bit [31:0] rx_packet_send[$]
  );
  ep_phy_tx_key.get(1);
    repeat(10) begin
  @(posedge  RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
end
    foreach(rx_packet_send[i]) begin

      @(posedge RX_DLL_PCS.CLK);
      wait(RX_DLL_PCS.dl_tx_ready);

      RX_DLL_PCS.dl_tx_valid <= 1'b1;
      // ERR_STP injection (EP->RC direction)
      RX_DLL_PCS.tl_packet <= (cfg.inject_err == ERR_STP) ? 1'b0 : 1'b1;

      RX_DLL_PCS.dl_tx_data <= rx_packet_send[i];
    `uvm_info("TLP_TX",
              $sformatf("EP: Sending TLP DATA[%0d] to RX_DLL_PCS.dl_tx_data = %08h",
                        i,
                        rx_packet_send[i]),
              UVM_LOW)
    end
    @(posedge  RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
      RX_DLL_PCS.tl_packet <= 1'b0;
      RX_DLL_PCS.dl_tx_data  <= 0;

  ep_phy_tx_key.put(1);
  if (cfg.inject_err == ERR_STP)
    cfg.inject_err = ERR_NONE;

  endtask

task ep_tx_recived_packet
  (
    input bit [31:0] tx_packet_recived[$]
  );
    
    bit [31:0] TX_DLP_PACKET[$];
    bit [31:0] rx_lcrc;
    
    wait(ep_outstanding_pkt_count < 2048);

      // Assign Sequence Number

      ep_RX_DL_SEQ = ep_rx_next_transmit_seq;

      // ERR_SEQ_NUM injection (EP->RC direction)
      if (cfg.inject_err == ERR_SEQ_NUM) begin
        ep_rx_next_transmit_seq = (ep_rx_next_transmit_seq + 2) % 4096;
        cfg.inject_err          = ERR_NONE;
      end
      else begin
        ep_rx_next_transmit_seq = (ep_rx_next_transmit_seq + 1) % 4096;
      end

//       
      // Build DLL Packet

      TX_DLP_PACKET.delete();

      // Add Sequence Number

    TX_DLP_PACKET.push_back({20'd0, ep_RX_DL_SEQ});

      `uvm_info("DLL_DRV_EP", $sformatf("TX TLP framing: assigned seq=%0h", ep_RX_DL_SEQ), UVM_MEDIUM)

    for(int i = 0; i < tx_packet_recived.size(); i++) begin
      TX_DLP_PACKET.push_back(tx_packet_recived[i]);
    end

      rx_lcrc = ep_calculate_lcrc(TX_DLP_PACKET);

      // ERR_LCRC injection (EP->RC direction)
      if (cfg.inject_err == ERR_LCRC) begin
        rx_lcrc        = ~rx_lcrc;
        cfg.inject_err = ERR_NONE;
      end

      // Append LCRC

    TX_DLP_PACKET.push_back(rx_lcrc);

      `uvm_info("DLL_DRV_EP", $sformatf("TX TLP framed: seq=%0h lcrc=%08h total=%0d DW (seq+hdr+pyld+ecrc+lcrc)",
               ep_RX_DL_SEQ, rx_lcrc, TX_DLP_PACKET.size()), UVM_MEDIUM)

      // Store Into Replay Buffer

    ep_replay_buffer[ep_wr_ptr].ep_packet_q = TX_DLP_PACKET;

//       
      // Update Write Pointer

    ep_wr_ptr = (ep_wr_ptr + 1) % 2048;

      // Increment Outstanding Packet Count

      ep_outstanding_pkt_count++;

      // Send Packet

      ep_send_packet(TX_DLP_PACKET);
             if(ep_outstanding_pkt_count==1)
      begin
	      ep_replay_timer_running=1;
	      ep_replay_timer_count=0;
      end
  endtask

  //-----------------------------------------------------------
  // run_phase - dispatches to the correct role's DLCMSM
  //-----------------------------------------------------------
  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)
       RC_MODE: begin
        fork
          rc_run_phase_body();
          rc_drive_dl_up_thread();
        join
      end
      EP_MODE: begin
        fork
          ep_run_phase_body();
          ep_drive_dl_up_thread();
        join
      end
      default: `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unknown mode", tag))
    endcase

  endtask
  
 task rc_drive_dl_up_thread();
    TX_TL_DL.dl_up <= 1'b0;
    forever begin
      @(posedge TX_TL_DL.CLK);
      TX_TL_DL.dl_up <= rc_dl_up;
    end
  endtask

   task ep_drive_dl_up_thread();
    RX_TL_DL.dl_up <= 1'b0;
    forever begin
      @(posedge RX_TL_DL.CLK);
      RX_TL_DL.dl_up <= ep_dl_up;
end
  endtask

  task rc_run_phase_body();
   
     Sequence_item tx_pkt;

   TX_TL_DL.tl_rx_valid <= 0;

   TX_TL_DL.tl_rx_data <= 0;
   TX_DLL_PCS.tl_packet  <= 0;
   TX_DLL_PCS.rc_link_up <= 1'b0;


   wait(TX_DLL_PCS.RESET);


  forever begin

  @(posedge TX_DLL_PCS.CLK);
    // Global link-down handling
     if(!TX_DLL_PCS.rc_link_up) begin
       rc_dl_state = DL_INACTIVE;


     end
     else begin

  case(rc_dl_state)

        //////////////////////////////////////////////////////
        // DL_INACTIVE
        //////////////////////////////////////////////////////

        DL_INACTIVE:
        begin
           // link_up_env.wait_trigger();
       rc_FL1   = 1'b0;
       rc_FL2   = 1'b0;
       rc_dl_up = 1'b0;
       rc_next_transmit_seq = 1'b0;
       rc_replay_buffer[rc_rd_ptr].replay_num = 1'b0;
       rc_aked_seq = 12'hFFF;

          wait(TX_DLL_PCS.rc_link_up)
            `uvm_info("DLCMSM", "RC DLCMSM: DL_INACTIVE -> DL_INIT_FC1", UVM_LOW)
            rc_dl_state = DL_INIT_FC1;

        end

//////////////////////////////////////////////////////
// DL_INIT_FC1
//////////////////////////////////////////////////////

DL_INIT_FC1:
begin

  int rc_initfc1_rx_cnt;
  bit rc_initfc1_timeout;

  rc_initfc1_rx_cnt = 0;
  rc_FL1            = 1'b0;

  rc_send_initfc1_dllps();   // first transmission
  rc_FL1 = 1'b1;

  while (rc_initfc1_rx_cnt < (3 * `NUM_VC)) begin

    rc_initfc1_timeout = 0;

    fork
      begin : rx_wait
        rc_rx_pkt_dllp.get(rc_rx_pkt);
        wait(rc_rx_pkt.dllp_packet_q.size() > 0);
        rc_initfc1_rx_cnt++;
      end
      begin : retx_timer
        #(34us);                     // scale to your timescale/`timeunit
        rc_initfc1_timeout = 1;
      end
    join_any
    disable fork;

    if (rc_initfc1_timeout) begin
      `uvm_info("DLCMSM",
        $sformatf("RC DLCMSM: DL_INIT_FC1 retransmit (rx_cnt=%0d/%0d) - no full triplet set within 34us",
                   rc_initfc1_rx_cnt, 3 * `NUM_VC),
        UVM_LOW)
      rc_send_initfc1_dllps();     // re-issue the full P/NP/CPL set for all VCs
    end

  end

  rc_fc_to_tl();
  `uvm_info("DLCMSM", "RC DLCMSM: DL_INIT_FC1 -> DL_INIT_FC2", UVM_LOW)
  rc_dl_state = DL_INIT_FC2;

end

//////////////////////////////////////////////////////
// DL_INIT_FC2
//////////////////////////////////////////////////////

DL_INIT_FC2:
begin

  int rc_initfc2_rx_cnt;
  bit rc_initfc2_timeout;

  rc_initfc2_rx_cnt = 0;
  rc_FL2            = 1'b0;

  rc_send_initfc2_dllps();
  rc_FL2 = 1'b1;

  while (rc_initfc2_rx_cnt < (3 * `NUM_VC)) begin

    rc_initfc2_timeout = 0;

    fork
      begin : rx_wait
        rc_rx_pkt_dllp.get(rc_rx_pkt);
        wait(rc_rx_pkt.dllp_packet_q.size() > 0);
        rc_initfc2_rx_cnt++;
      end
      begin : retx_timer
        #(34us);
        rc_initfc2_timeout = 1;
      end
    join_any
    disable fork;

    if (rc_initfc2_timeout) begin
      `uvm_info("DLCMSM",
        $sformatf("RC DLCMSM: DL_INIT_FC2 retransmit (rx_cnt=%0d/%0d) - no full triplet set within 34us",
                   rc_initfc2_rx_cnt, 3 * `NUM_VC),
        UVM_LOW)
      rc_send_initfc2_dllps();
    end

  end

  rc_dl_up = 1'b1;
  `uvm_info("DLCMSM", "RC DLCMSM: DL_INIT_FC2 -> DL_ACTIVE", UVM_LOW)
  rc_dl_state = DL_ACTIVE;

end
        //////////////////////////////////////////////////////
        // DL_ACTIVE
        //////////////////////////////////////////////////////

   DL_ACTIVE:

begin
        	 DL_up_env.trigger();

  fork

    forever begin

      rc_rx_pkt_tlp.get(rc_rx_pkt);

      rc_rx_local_queue = rc_rx_pkt.rx_data_t;
         `uvm_info("DLL_DRV_RC", $sformatf("DLL(RC) collected RX completion: %0d DW firstDW=%08h",
               rc_rx_local_queue.size(), rc_rx_local_queue.size() ? rc_rx_local_queue[0] : 32'h0), UVM_MEDIUM)

      rc_rx_recived_packet(rc_rx_local_queue);

    end

    forever begin
      Sequence_item tx_pkt;

      rc_tx_pkt_mb.get(tx_pkt);

      rc_tx_local_queue = tx_pkt.tx_data_t;

      rc_tx_recived_packet(rc_tx_local_queue);

    end

          rc_process_dllp();
    
          RC_ACK_NAK_dllps();
         if(cfg.replay_en) begin 
	  rc_replay_timer();
         end

  join_none

  wait(0);

end

      endcase

    end

   end
  endtask

  task ep_run_phase_body();
   
   RX_TL_DL.tl_rx_valid <= 0;

   RX_TL_DL.tl_rx_data <= 0;

   RX_DLL_PCS.tl_packet <= 1'b0;

    RX_DLL_PCS.ep_link_up <= 1'b0;
   
   @(posedge RX_DLL_PCS.CLK);

   wait(RX_DLL_PCS.RESET);

//  ep_dl_state = EP_DL_INACTIVE;

  forever begin

    @(posedge RX_DLL_PCS.CLK);

    // Global link-down handling
      if(!RX_DLL_PCS.ep_link_up) begin

       ep_dl_state = EP_DL_INACTIVE;


     end
     else begin

      case(ep_dl_state)

        //////////////////////////////////////////////////////
        // DL_INACTIVE
        //////////////////////////////////////////////////////

        EP_DL_INACTIVE:
        begin
         //    link_up_env_rx.wait_trigger();
       ep_FL1   = 1'b0;
       ep_FL2   = 1'b0;
       ep_dl_up = 1'b0;
       ep_rx_next_transmit_seq = 1'b0;
       ep_replay_buffer[ep_rd_ptr].ep_replay_num = 1'b0;
       ep_aked_seq = 12'hFFF;

          wait(RX_DLL_PCS.ep_link_up)
            `uvm_info("DLCMSM", "EP DLCMSM: DL_INACTIVE -> DL_INIT_FC1", UVM_LOW)
            ep_dl_state = EP_DL_INIT_FC1;

        end

        //////////////////////////////////////////////////////
        // DL_INIT_FC1
        //////////////////////////////////////////////////////

       EP_DL_INIT_FC1:
begin

  int ep_initfc1_rx_cnt;
  bit ep_initfc1_timeout;

  ep_initfc1_rx_cnt = 0;
  ep_FL1            = 1'b0;

  ep_send_initfc1_dllps();   // first transmission
  ep_FL1 = 1'b1;

  while (ep_initfc1_rx_cnt < (3 * `NUM_VC)) begin

    ep_initfc1_timeout = 0;

    fork
      begin : rx_wait
        ep_rx_pkt_dllp.get(ep_rx_pkt);
        wait(ep_rx_pkt.dllp_packet_rx_q.size() > 0);
        ep_initfc1_rx_cnt++;
      end
      begin : retx_timer
        #(34us);                    
	ep_initfc1_timeout = 1;
      end
    join_any
    disable fork;

    if (ep_initfc1_timeout) begin
      `uvm_info("DLCMSM",
        $sformatf("EP DLCMSM: EP_DL_INIT_FC1 retransmit (rx_cnt=%0d/%0d) - no full triplet set within 34us",
                   ep_initfc1_rx_cnt, 3 * `NUM_VC),
        UVM_LOW)
      ep_send_initfc1_dllps();     // re-issue the full P/NP/CPL set for all VCs
    end

  end

  ep_fc_to_tl();
  `uvm_info("DLCMSM", "EP DLCMSM: DL_INIT_FC1 -> DL_INIT_FC2", UVM_LOW)
  ep_dl_state = EP_DL_INIT_FC2;

end
        //////////////////////////////////////////////////////
        // DL_INIT_FC2
        //////////////////////////////////////////////////////

EP_DL_INIT_FC2:
begin

  int ep_initfc2_rx_cnt;
  bit ep_initfc2_timeout;

  ep_initfc2_rx_cnt = 0;
  ep_FL2            = 1'b0;

  ep_send_initfc2_dllps();
  ep_FL2 = 1'b1;

  while (ep_initfc2_rx_cnt < (3 * `NUM_VC)) begin

    ep_initfc2_timeout = 0;

    fork
      begin : rx_wait
        ep_rx_pkt_dllp.get(ep_rx_pkt);
        wait(ep_rx_pkt.dllp_packet_rx_q.size() > 0);
        ep_initfc2_rx_cnt++;
      end
      begin : retx_timer
        #(34us);
        ep_initfc2_timeout = 1;
      end
    join_any
    disable fork;

    if (ep_initfc2_timeout) begin
      `uvm_info("DLCMSM",
        $sformatf("EP DLCMSM: EP_DL_INIT_FC2 retransmit (rx_cnt=%0d/%0d) - no full triplet set within 34us",
                   ep_initfc2_rx_cnt, 3 * `NUM_VC),
        UVM_LOW)
      ep_send_initfc2_dllps();
    end

  end

  ep_dl_up = 1'b1;
  `uvm_info("DLCMSM", "EP DLCMSM: DL_INIT_FC2 -> EP_DL_ACTIVE", UVM_LOW)
  ep_dl_state = EP_DL_ACTIVE;

end
        //////////////////////////////////////////////////////
        // DL_ACTIVE
        //////////////////////////////////////////////////////

        EP_DL_ACTIVE:
	begin
	//#1;
               DL_up_env_rx.trigger();
  fork

    forever begin

       ep_rx_pkt_tlp.get(ep_rx_pkt);
      
      ep_rx_local_queue = ep_rx_pkt.rx_data;

      ep_rx_recived_packet(ep_rx_local_queue);

    end

    forever begin
      Sequence_item tx_pkt;

      ep_tx_pkt_mb.get(tx_pkt);

      ep_tx_local_queue = tx_pkt.tx_data;

      ep_tx_recived_packet(ep_tx_local_queue);

    end
    
        ep_process_dllp();
              
          EP_ACK_NAK_dllps();
	  if(cfg.replay_en) begin 
	    ep_replay_timer();
          end
     forever begin
	    bit [2:0] pending_vc;
	    ep_fc_update_mbx.get(pending_vc);
	  ep_Updatefc_dllps(pending_vc);
  end

  join_none

  wait(0);

end

      endcase

    end
    end
  endtask

endclass


