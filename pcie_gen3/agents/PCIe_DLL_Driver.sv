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

  bit [11:0] rc_next_transmit_seq = 12'd2;
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

  bit [7:0]  rc_fc_ph;
  bit [7:0]  rc_fc_nph;
  bit [7:0]  rc_fc_cmplh;
  bit [11:0] rc_fc_pd;
  bit [11:0] rc_fc_npd;
  bit [11:0] rc_fc_cmpld;
  bit [7:0]  rc_ph_fc;
  bit [7:0]  rc_nph_fc;
  bit [7:0]  rc_cmplh_fc;
  bit [11:0] rc_pd_fc;
  bit [11:0] rc_npd_fc;
  bit [11:0] rc_cmpld_fc;

  bit [11:0] rc_an_seq_no;

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

  bit [11:0] ep_rx_next_transmit_seq = 12'd2;
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

  bit ep_rx_new_pkt_available;
  bit ep_tx_new_pkt_available;

  typedef enum bit [1:0] { EP_DL_INACTIVE, EP_DL_INIT_FC1, EP_DL_INIT_FC2, EP_DL_ACTIVE } ep_dl_state_e;
  ep_dl_state_e ep_dl_state;

  bit ep_FL1;
  bit ep_FL2;
  bit ep_dl_up;
  bit ep_initfc1_tx_done;
  bit ep_initfc2_tx_done;

  bit [7:0]  ep_fc_ph;
  bit [7:0]  ep_fc_nph;
  bit [7:0]  ep_fc_cmplh;
  bit [11:0] ep_fc_pd;
  bit [11:0] ep_fc_npd;
  bit [11:0] ep_fc_cmpld;
  bit [7:0]  ep_ph_fc;
  bit [7:0]  ep_nph_fc;
  bit [7:0]  ep_cmplh_fc;
  bit [11:0] ep_pd_fc;
  bit [11:0] ep_npd_fc;
  bit [11:0] ep_cmpld_fc;

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
	   if (r_x.rx_data_t.size() > 0 || r_x.rc_ack_nak_seq > 0) begin
    rc_an_seq_no = r_x.rc_ack_nak_seq;
        rc_rx_pkt_tlp.try_put(r_x);
end
    if (r_x.dllp_packet_q.size() > 0) begin
        rc_rx_pkt_dllp.try_put(r_x);
     if(r_x.rc_data_type==4'b0100)begin
	rc_ph_fc=r_x.rc_header_pfc;		       
	rc_pd_fc=r_x.rc_data_pfc; 
    //  rc_fc_received_ev.trigger();
      
	      end 
	   	      if(r_x.rc_data_type==4'b0101)begin
	rc_nph_fc=r_x.rc_header_npfc ;
	rc_npd_fc=r_x.rc_data_npfc;  
//	rc_fc_received_ev.trigger();
	      end 
	   	      if(r_x.rc_data_type==4'b0110)begin
	rc_cmplh_fc=r_x.rc_header_cmplfc; 
	rc_cmpld_fc=r_x.rc_data_cmplfc;  
//	rc_fc_received_ev.trigger();
 end 
    end

  endfunction

  //-----------------------------------------------------------
  // EP_MODE write callbacks
  //-----------------------------------------------------------
  function void write_fc(Sequence_item t_x);
    ep_fc_ph    = t_x.ep_fc_ph;
    ep_fc_pd    = t_x.ep_fc_pd;
    ep_fc_nph   = t_x.ep_fc_nph;
    ep_fc_npd   = t_x.ep_fc_npd;
    ep_fc_cmplh = t_x.ep_fc_cmplh;
    ep_fc_cmpld = t_x.ep_fc_cmpld;

   endfunction

      function void write_tx(Sequence_item t_x);
        ep_tx_pkt_mb.try_put(t_x);
  endfunction

 function void write_rx(Sequence_item r_x);
    if (r_x.dllp_packet_rx_q.size() > 0) begin
                ep_rx_pkt_dllp.try_put(r_x);
        	 if(r_x.ep_data_type==4'b0100)begin
	ep_ph_fc=r_x.ep_header_pfc; 		       
	ep_pd_fc=r_x.ep_data_pfc;
    // ep_fc_received_ev.trigger();	
	      end 
	   	      if(r_x.ep_data_type==4'b0101)begin
	ep_nph_fc=r_x.ep_header_npfc; 
	ep_npd_fc=r_x.ep_data_npfc;
     // ep_fc_received_ev.trigger();	
	      end 
	   	      if(r_x.ep_data_type==4'b0110)begin
	ep_cmplh_fc=r_x.ep_header_cmplfc; 
	ep_cmpld_fc=r_x.ep_data_cmplfc;
    //  ep_fc_received_ev.trigger();	

	      end 

   end
    if (r_x.rx_data.size() > 0 || r_x.ep_ack_nak_seq > 0) begin
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
  bit feedback;

  crc = 16'hFFFF;  // Initial value

  for (int b = 0; b < 32; b++) begin
    feedback = crc[15] ^ data[b];

    crc = crc << 1;

    if (feedback)
      crc ^= 16'h100B;
  end

  return ~crc;

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
    bit data_bit;
    bit feedback;
         foreach(pkt_q[i]) begin
                end

    crc = 32'hFFFF_FFFF;
    foreach(pkt_q[i]) begin
      for(int b = 0; b < 32; b++) begin
        data_bit = pkt_q[i][b];
        feedback = crc[31] ^ data_bit;
        crc = crc << 1;
        if(feedback)
          crc ^= 32'h04C11DB7;
      end
    end
    return ~crc;
  endfunction : rc_calculate_lcrc

    function bit [31:0] ep_calculate_lcrc(input bit [31:0] pkt_q[$]);
    bit [31:0] crc;
    bit data_bit;
    bit feedback;
     foreach(pkt_q[i]) begin
                end

    crc = 32'hFFFF_FFFF;
    foreach(pkt_q[i]) begin
      for(int b = 0; b < 32; b++) begin
        data_bit = pkt_q[i][b];
        feedback = crc[31] ^ data_bit;
        crc = crc << 1;
        if(feedback)
          crc ^= 32'h04C11DB7;
      end
    end
    return ~crc;
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

            rc_nak(rc_dllp_type, rc_ack_nak_seq);
   
      end
        else begin
            rc_ackd_seq(rc_dllp_type, rc_ack_nak_seq);
        end

   end

   	
endtask

task rc_ackd_seq(input bit [7:0]rc_dllp_type, input bit [11:0] rc_ack_nak_seq); begin
    
      rc_replay_buffer[rc_rd_ptr].replay_num = 0; 
      rc_aked_seq = rc_ack_nak_seq;
    
    if(rc_dllp_type == 8'b0000_0000)begin

    while(rc_rd_ptr != rc_wr_ptr)
    begin

        bit [11:0] seq;

        seq = rc_replay_buffer[rc_rd_ptr].packet_q[0][11:0];

$display("[%0t] BEFORE DELETE : rd_ptr=%0d seq=%0d queue_size=%0d queue=%p",
         $time,
         rc_rd_ptr,
         rc_replay_buffer[rc_rd_ptr].packet_q[0][11:0],
         rc_replay_buffer[rc_rd_ptr].packet_q.size(),
         rc_replay_buffer[rc_rd_ptr].packet_q);
      
         rc_replay_buffer[rc_rd_ptr].packet_q.delete();
      
      $display("[%0t] AFTER DELETE  : rd_ptr=%0d queue_size=%0d queue=%p",
         $time,
         rc_rd_ptr,
         rc_replay_buffer[rc_rd_ptr].packet_q.size(),
         rc_replay_buffer[rc_rd_ptr].packet_q);

         rc_outstanding_pkt_count--;

         rc_rd_ptr = (rc_rd_ptr + 1) % 2048;

	  if(rc_outstanding_pkt_count==0)
	begin
    		rc_replay_timer_running=0;
    		rc_replay_timer_count=0;
		 
	end
	else
	begin
    		rc_replay_timer_running=1;
    		rc_replay_timer_count=0;
		 
	end

        // stop after deleting ACKed sequence
        if(seq > rc_ack_nak_seq)
            break;

    end
end
    
    else 
      rc_nak(rc_dllp_type,rc_ack_nak_seq);
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
        rc_replay_timer();
    
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

    initfc1_p = create_dllp(INITFC1_P,
                            3'b000,
                            rc_fc_ph,
                            rc_fc_pd);

    initfc1_np = create_dllp(INITFC1_NP,
                             3'b000,
                             rc_fc_nph,
                             rc_fc_npd);

    initfc1_cpl = create_dllp(INITFC1_CPL,
                              3'b000,
                              rc_fc_cmplh,
                              rc_fc_cmpld);

    rc_send_one_dllp(initfc1_p);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;
    rc_send_one_dllp(initfc1_np);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;
    rc_send_one_dllp(initfc1_cpl);

    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;

    rc_initfc1_tx_done = 1'b1;

  endtask

task rc_send_initfc2_dllps();

    bit [47:0] initfc2_p;
    bit [47:0] initfc2_np;
    bit [47:0] initfc2_cpl;

    initfc2_p = create_dllp(INITFC2_P,
                            3'b000,
                            rc_fc_ph,
                            rc_fc_pd);

    initfc2_np = create_dllp(INITFC2_NP,
                             3'b000,
                             rc_fc_nph,
                             rc_fc_npd);

    initfc2_cpl = create_dllp(INITFC2_CPL,
                              3'b000,
                              rc_fc_cmplh,
                              rc_fc_cmpld);

    rc_send_one_dllp(initfc2_p);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;
    rc_send_one_dllp(initfc2_np);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;
    rc_send_one_dllp(initfc2_cpl);
    @(posedge TX_DLL_PCS.CLK);

    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;

    rc_initfc2_tx_done = 1'b1;

  endtask

  task rc_Updatefc_dllps();

    bit [47:0] updatefc_p;
    bit [47:0] updatefc_np;
    bit [47:0] updatefc_cpl;

    updatefc_p = create_dllp(UPDATEFC_P,
                            3'b000,
                            rc_fc_ph,
                            rc_fc_pd);

    updatefc_np = create_dllp(UPDATEFC_NP,
                             3'b000,
                             rc_fc_nph,
                             rc_fc_npd);

    updatefc_cpl = create_dllp(UPDATEFC_CPL,
                              3'b000,
                              rc_fc_cmplh,
                              rc_fc_cmpld);

    rc_send_one_dllp(updatefc_p);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;
    rc_send_one_dllp(updatefc_np);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;
    rc_send_one_dllp(updatefc_cpl);
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;

  endtask
  task RC_ACK_NAK_dllps();

  bit [47:0] rc_ack_dllp;
  bit [47:0] rc_nak_dllp;

  forever begin

    fork

      begin
        rc_ack_ev.wait_trigger();

        rc_ack_dllp = ack_nak_dllp(ACK_DLLP, rc_an_seq_no);

        rc_send_one_dllp(rc_ack_dllp);
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

TX_TL_DL.rc_fc_ph    <= rc_ph_fc;
TX_TL_DL.rc_fc_pd    <= rc_pd_fc;

TX_TL_DL.rc_fc_nph   <= rc_nph_fc;
TX_TL_DL.rc_fc_npd   <= rc_npd_fc;

TX_TL_DL.rc_fc_cmplh <= rc_cmplh_fc;
TX_TL_DL.rc_fc_cmpld <= rc_cmpld_fc;

endtask

task rc_rx_recived_packet
  (
    input bit [31:0] rx_packet_recived[$]
  );

    $display("[%0t][RX_DLL_DRIVER] Collect DATA = %p",
               $time,
               rx_packet_recived);

    foreach(rx_packet_recived[i]) begin 
      wait(TX_TL_DL.tl_rx_ready);

      @(posedge TX_TL_DL.CLK);
       TX_TL_DL.tl_rx_valid <= 1'b1;
       TX_TL_DL.tl_rx_data <= rx_packet_recived[i];

      $display("[%0t][RX_DLL_DRIVER] Sent DATA[%0d] = %h",
               $time,
               i,
               rx_packet_recived[i]);

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
      TX_DLL_PCS.tl_packet <= 1'b1;

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

      rc_next_transmit_seq =
    (rc_next_transmit_seq + 1) % 4096;

//       
      // Build DLL Packet

      TX_DLP_PACKET.delete();

      // Add Sequence Number

    TX_DLP_PACKET.push_back({20'd0, rc_DL_SEQ});

      $display("@(%0t) DLL_SEQ = %0h",
               $time,
               {20'd0, rc_DL_SEQ});
    
    for(int i = 0; i < tx_packet_recived.size(); i++) begin
      TX_DLP_PACKET.push_back(tx_packet_recived[i]);
    end

      rx_lcrc = rc_calculate_lcrc(TX_DLP_PACKET);

      // Append LCRC

    TX_DLP_PACKET.push_back(rx_lcrc);

      $display("@(%0t) DLL_LCRC = %0h",
               $time,
               rx_lcrc);

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

        ep_nak(ep_dllp_type, ep_ack_nak_seq);
   
      end
        else begin
          ep_ackd_seq(ep_dllp_type, ep_ack_nak_seq);
        end

    end

endtask

  task ep_ackd_seq(input bit [7:0]ep_dllp_type, input bit [11:0] ep_ack_nak_seq); begin
    
    ep_replay_buffer[ep_rd_ptr].ep_replay_num = 0;
      ep_aked_seq = ep_ack_nak_seq;
    
    if(ep_dllp_type == 8'b0000_0000)begin 
      
      while(ep_rd_ptr != ep_wr_ptr)
    begin

        bit [11:0] seq;

      seq = ep_replay_buffer[ep_rd_ptr].ep_packet_q[0][11:0];

$display("[%0t] EP BEFORE DELETE : rd_ptr=%0d seq=%0d queue_size=%0d queue=%p",
         $time,
         ep_rd_ptr,
         ep_replay_buffer[ep_rd_ptr].ep_packet_q[0][11:0],
         ep_replay_buffer[ep_rd_ptr].ep_packet_q.size(),
         ep_replay_buffer[ep_rd_ptr].ep_packet_q);
      
         ep_replay_buffer[ep_rd_ptr].ep_packet_q.delete();
      
      $display("[%0t] EP AFTER DELETE  : rd_ptr=%0d queue_size=%0d queue=%p",
         $time,
         ep_rd_ptr,
               ep_replay_buffer[ep_rd_ptr].ep_packet_q.size(),
               ep_replay_buffer[ep_rd_ptr].ep_packet_q);

        ep_outstanding_pkt_count--;

      ep_rd_ptr = (ep_rd_ptr + 1) % 2048;

      if(ep_outstanding_pkt_count==0)
	begin
    		ep_replay_timer_running=0;
    		ep_replay_timer_count=0;
                
	end
	else
	begin
    		ep_replay_timer_running=1;
    		ep_replay_timer_count=0;
		                
	end

        // stop after deleting ACKed sequence
      if(seq == ep_ack_nak_seq)
            break;

    end
    end
    
    else 
      ep_nak(ep_dllp_type,ep_ack_nak_seq);
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
        ep_replay_timer();

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

    initfc1_p = create_dllp(INITFC1_P,
                            3'b000,
                            ep_fc_ph,
                            ep_fc_pd);

    initfc1_np = create_dllp(INITFC1_NP,
                             3'b000,
                             ep_fc_nph,
                             ep_fc_npd);

    initfc1_cpl = create_dllp(INITFC1_CPL,
                              3'b000,
                              ep_fc_cmplh,
                              ep_fc_cmpld);

    ep_send_one_dllp(initfc1_p);
    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
    ep_send_one_dllp(initfc1_np);
    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
    ep_send_one_dllp(initfc1_cpl);
    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;

     ep_initfc1_tx_done = 1'b1;

  endtask

task ep_send_initfc2_dllps();

    bit [47:0] initfc2_p;
    bit [47:0] initfc2_np;
    bit [47:0] initfc2_cpl;

    initfc2_p = create_dllp(INITFC2_P,
                            3'b000,
                            ep_fc_ph,
                            ep_fc_pd);

    initfc2_np = create_dllp(INITFC2_NP,
                             3'b000,
                             ep_fc_nph,
                             ep_fc_npd);

    initfc2_cpl = create_dllp(INITFC2_CPL,
                              3'b000,
                              ep_fc_cmplh,
                              ep_fc_cmpld);

    ep_send_one_dllp(initfc2_p);
    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
    ep_send_one_dllp(initfc2_np);
    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
    ep_send_one_dllp(initfc2_cpl);
    @(posedge RX_DLL_PCS.CLK);
 RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
     
        ep_initfc2_tx_done = 1'b1;

  endtask

   task EP_ACK_NAK_dllps();

  bit [47:0] ack_dllp;
  bit [47:0] nak_dllp;

  forever begin

    fork

      begin
        ep_ack_ev.wait_trigger();

        ack_dllp = ack_nak_dllp(ACK_DLLP, ep_an_seq_no);

        ep_send_one_dllp(ack_dllp);
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

//ep_fc_received_ev.wait_trigger();

@(posedge RX_TL_DL.CLK);

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

      $display("[%0t][RX_DLL_DRIVER] Sent DATA[%0d] = %h",
               $time,
               i,
               rx_packet_recived[i]);

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
      RX_DLL_PCS.tl_packet <= 1'b1;

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

      ep_rx_next_transmit_seq =
    (ep_rx_next_transmit_seq + 1) % 4096;

//       
      // Build DLL Packet

      TX_DLP_PACKET.delete();

      // Add Sequence Number

    TX_DLP_PACKET.push_back({20'd0, ep_RX_DL_SEQ});

      $display("@(%0t) DLL_SEQ = %0h",
               $time,
               {20'd0, ep_RX_DL_SEQ});
    
    for(int i = 0; i < tx_packet_recived.size(); i++) begin
      TX_DLP_PACKET.push_back(tx_packet_recived[i]);
    end

      rx_lcrc = ep_calculate_lcrc(TX_DLP_PACKET);

      // Append LCRC

    TX_DLP_PACKET.push_back(rx_lcrc);

//       
      $display("@(%0t) DLL_LCRC = %0h",
               $time,
               rx_lcrc);

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
      RC_MODE: rc_run_phase_body();
      EP_MODE: ep_run_phase_body();
      default: `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unknown mode", tag))
    endcase

  endtask

  task rc_run_phase_body();
   
     Sequence_item tx_pkt;

   TX_TL_DL.tl_rx_valid <= 0;

   TX_TL_DL.tl_rx_data <= 0;
   TX_DLL_PCS.tl_packet  <= 0;

   wait(TX_DLL_PCS.RESET);

  rc_dl_state = DL_INACTIVE;

  forever begin

  case(rc_dl_state)

        //////////////////////////////////////////////////////
        // DL_INACTIVE
        //////////////////////////////////////////////////////

        DL_INACTIVE:
        begin
            link_up_env.wait_trigger();

          //if(TX_DLL_PCS.phy_link_up)
            `uvm_info("DLCMSM", "RC DLCMSM: DL_INACTIVE -> DL_INIT_FC1", UVM_LOW)
            rc_dl_state = DL_INIT_FC1;

        end

//////////////////////////////////////////////////////
// DL_INIT_FC1
//////////////////////////////////////////////////////

DL_INIT_FC1:
begin

  int rc_initfc1_rx_cnt;

  rc_send_initfc1_dllps();

  rc_FL1 = 1'b1;

  rc_initfc1_rx_cnt = 0;

  while (rc_initfc1_rx_cnt < 3) begin

    rc_rx_pkt_dllp.get(rc_rx_pkt);

    wait(rc_rx_pkt.dllp_packet_q.size() > 0);

    rc_initfc1_rx_cnt++;

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

  //--------------------------------------------------
  // Send INITFC2 DLLPs
  //--------------------------------------------------
  rc_send_initfc2_dllps();

  rc_FL2 = 1'b1;

  rc_initfc2_rx_cnt = 0;

  //--------------------------------------------------
  // Receive 3 INITFC2 DLLPs
  //--------------------------------------------------
  while (rc_initfc2_rx_cnt < 3) begin

    rc_rx_pkt_dllp.get(rc_rx_pkt);

    wait(rc_rx_pkt.dllp_packet_q.size() > 0);

    rc_initfc2_rx_cnt++;

  end

  //--------------------------------------------------
  // INITFC2 completed
  //--------------------------------------------------
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
         $display("[%0t][RX_DLL_DRIVER] Collect DATA = %p",
               $time,
               rc_rx_local_queue);

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

	  rc_replay_timer();

  join_none

  wait(0);

end

      endcase

    end

//   end
  endtask

  task ep_run_phase_body();
   
   RX_TL_DL.tl_rx_valid <= 0;

   RX_TL_DL.tl_rx_data <= 0;

      RX_DLL_PCS.tl_packet <= 1'b0;
   @(posedge RX_DLL_PCS.CLK);

   wait(RX_DLL_PCS.RESET);

  ep_dl_state = EP_DL_INACTIVE;

  forever begin

  //  @(posedge RX_DLL_PCS.CLK);

//     // Global link-down handling
//     if(!RX_DLL_PCS.phy_link_up) begin

//       ep_dl_state = EP_DL_INACTIVE;

//       ep_FL1   = 1'b0;
//       ep_FL2   = 1'b0;
//       ep_dl_up = 1'b0;

//     end
//     else begin

      case(ep_dl_state)

        //////////////////////////////////////////////////////
        // DL_INACTIVE
        //////////////////////////////////////////////////////

        EP_DL_INACTIVE:
        begin
             link_up_env_rx.wait_trigger();
 
        //  if(RX_DLL_PCS.phy_link_up)
            `uvm_info("DLCMSM", "EP DLCMSM: DL_INACTIVE -> DL_INIT_FC1", UVM_LOW)
            ep_dl_state = EP_DL_INIT_FC1;

        end

        //////////////////////////////////////////////////////
        // DL_INIT_FC1
        //////////////////////////////////////////////////////

        EP_DL_INIT_FC1:
        begin

          int ep_initfc1_rx_cnt;

          ep_send_initfc1_dllps();

	  ep_FL1 = 1'b1;

          ep_initfc1_rx_cnt = 0;

          while(ep_initfc1_rx_cnt < 3) begin

            ep_rx_pkt_dllp.get(ep_rx_pkt);

            wait(ep_rx_pkt.dllp_packet_rx_q.size > 0);

            ep_initfc1_rx_cnt++;

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

  //------------------------------------------------------
  // Send INITFC2 DLLPs
  //------------------------------------------------------
  ep_send_initfc2_dllps();

  ep_FL2 = 1'b1;

  ep_initfc2_rx_cnt = 0;

  //------------------------------------------------------
  // Wait for 3 INITFC2 DLLPs
  //------------------------------------------------------
  while (ep_initfc2_rx_cnt < 3) begin

    ep_rx_pkt_dllp.get(ep_rx_pkt);

    wait(ep_rx_pkt.dllp_packet_rx_q.size() > 0);

    ep_initfc2_rx_cnt++;

  end

  //------------------------------------------------------
  // INITFC2 completed -> DL_ACTIVE
  //------------------------------------------------------
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
	  
	  ep_replay_timer();

  join_none

  wait(0);

end

      endcase

    end
  endtask

endclass

