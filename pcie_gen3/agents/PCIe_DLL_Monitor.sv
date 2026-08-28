class PCIe_DLL_Monitor extends uvm_monitor;

  env_cfg cfg;
  string  tag;

  //-----------------------------------------------------------
  // Role-specific interface handles (already distinctly typed)
  //-----------------------------------------------------------
  virtual TX_TL_DL_Interface   TX_TL_DL;
  virtual TX_DLL_PCS_Interface TX_DLL_PCS;

  virtual RX_TL_DL_Interface   RX_TL_DL;
  virtual RX_DLL_PCS_Interface RX_DLL_PCS;

  //-----------------------------------------------------------
  // RC_MODE analysis ports -> TX_DLL_Driver's rc_RX_MD_Recv / rc_TX_MD_Recv
  //-----------------------------------------------------------
  uvm_analysis_port #(Sequence_item) rc_RX_MD_ap;
  uvm_analysis_port #(Sequence_item) rc_TX_MD_ap;

   uvm_analysis_port #(Sequence_item) rc_FC_MD_ap;
     uvm_analysis_port #(Sequence_item) rc_tx;  // scoreboard port
  uvm_analysis_port #(Sequence_item) rc_rx;  // scoreboard port
  uvm_analysis_port #(Sequence_item) ep_tx;  // scoreboard port
  uvm_analysis_port #(Sequence_item) ep_rx;  // scoreboard port

  uvm_analysis_port #(Sequence_item) rc_dllp_tx;
  uvm_analysis_port #(Sequence_item) rc_dllp_rx;
  uvm_analysis_port #(Sequence_item) ep_dllp_tx;
  uvm_analysis_port #(Sequence_item) ep_dllp_rx;

  uvm_event rc_nack_ev;
  uvm_event rc_ack_ev;

  bit RC_NACK_SCHEDULED;
  
  bit [11:0] RC_NRS = 0;

  //-----------------------------------------------------------
  // EP_MODE analysis ports -> TX_DLL_Driver's ep_RX_MD_Recv / ep_TX_MD_Recv
  //-----------------------------------------------------------
  uvm_analysis_port #(Sequence_item) ep_RX_MD_ap;
  uvm_analysis_port #(Sequence_item) ep_TX_MD_ap;
    uvm_analysis_port #(Sequence_item) ep_FC_MD_ap;

  uvm_event ep_nack_ev;
  uvm_event ep_ack_ev;

  bit EP_NACK_SCHEDULED;

  bit [11:0] EP_NRS = 0;

  //-----------------------------------------------------------
  // Shared global event - LCRC mismatch notification
  //-----------------------------------------------------------

  `uvm_component_utils(PCIe_DLL_Monitor)

  function new(string name = "PCIe_DLL_Monitor", uvm_component parent = null);
    super.new(name, parent);

    rc_RX_MD_ap = new("rc_RX_MD_ap", this);
    rc_TX_MD_ap = new("rc_TX_MD_ap", this);
    ep_RX_MD_ap = new("ep_RX_MD_ap", this);
    ep_TX_MD_ap = new("ep_TX_MD_ap", this);
        rc_tx = new("rc_tx", this);  //scoreboard
    rc_rx = new("rc_rx", this);  //scoreboard
    ep_tx = new("ep_tx", this);  //scoreboard
    ep_rx = new("ep_rx", this);  //scoreboard
    rc_dllp_tx = new("rc_dllp_tx", this);
    rc_dllp_rx = new("rc_dllp_rx", this);
    ep_dllp_tx = new("ep_dllp_tx", this);
    ep_dllp_rx = new("ep_dllp_rx", this);


    rc_FC_MD_ap = new("rc_FC_MD_ap", this);
    ep_FC_MD_ap = new("ep_FC_MD_ap", this);

  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_DLL_Monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();

    case(cfg.mode)

      RC_MODE: begin
    rc_nack_ev = uvm_event_pool::get_global("RC_NAK_DLLP_EVENT");
    rc_ack_ev  = uvm_event_pool::get_global("RC_ACK_DLLP_EVENT");
        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unable to access TX_TL_DL from config_db", tag))

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unable to access TX_DLL_PCS from config_db", tag))
        end

      EP_MODE: begin
    ep_nack_ev = uvm_event_pool::get_global("EP_NAK_DLLP_EVENT");
    ep_ack_ev  = uvm_event_pool::get_global("EP_ACK_DLLP_EVENT");
      
        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("RX_DLL_MON", $sformatf("[%s] Cannot Access RX_TL_DL", tag))

        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
          `uvm_fatal("RX_DLL_MON", $sformatf("[%s] Cannot Access RX_DLL_PCS", tag))

              end

      default: `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  //-----------------------------------------------------------
  // Shared helper - byte-identical across all 4 reference files
  //-----------------------------------------------------------
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

  //-----------------------------------------------------------
  // RC_MODE tasks - preserved exactly as PCIe_DLL_Monitor.sv
  //-----------------------------------------------------------
task rc_monitor_tx();

    Sequence_item tx_pkt;

    forever begin

      tx_pkt = Sequence_item::type_id::create("tx_pkt");

      rc_collect_data_TX(tx_pkt);

      rc_TX_MD_ap.write(tx_pkt);

    end

  endtask

  task rc_monitor_rx();

Sequence_item rx_pkt;

  forever begin

    @(negedge TX_DLL_PCS.CLK);

    // Wait until a valid transfer occurs
    if (!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready))
      continue;

    rx_pkt = Sequence_item::type_id::create("rx_pkt");

    //------------------------------------------------------
    // DLLP Packet
    //------------------------------------------------------
    if (TX_DLL_PCS.dl_mac_packet) begin

      rc_collect_dllp(rx_pkt);

      if (rx_pkt.dllp_packet_q.size() > 0) begin
                rc_RX_MD_ap.write(rx_pkt);

              end

    end

    //------------------------------------------------------
    // TLP Packet
    //------------------------------------------------------
    else if (TX_DLL_PCS.tl_mac_packet) begin

      rc_collect_tlp(rx_pkt);

      if (rx_pkt.rx_data_t.size() > 0|| rx_pkt.rc_ack_nak_seq>0) begin
                rc_RX_MD_ap.write(rx_pkt);

              end

    end   

  end

  endtask

  task rc_monitor_sb();

    Sequence_item tx_pkt;

  forever begin

    @(negedge TX_DLL_PCS.CLK);

    // Wait until a valid transfer occurs
    if (!(TX_DLL_PCS.dl_tx_valid &&
          TX_DLL_PCS.dl_tx_ready))
      continue;

    tx_pkt = Sequence_item::type_id::create("tx_pkt");

     if (TX_DLL_PCS.tl_packet) begin

      rc_collect_request(tx_pkt);

      if (tx_pkt.tx_data_sb.size() > 0) begin
            rc_tx.write(tx_pkt);

              end

    end
        if (TX_DLL_PCS.dl_packet) begin

      rc_collect_dllp_sb(tx_pkt);

      if (tx_pkt.rc_dllp_packet_sb.size() > 0) begin
      //  rc_RX_MD_ap.write(tx_pkt);
      end

    end

    end

  endtask


//-----------------------------------------------------------
// Dedicated RC FC-credit monitor - decoupled from TLP capture
//-----------------------------------------------------------
task rc_monitor_fc_credits();

  Sequence_item fc_pkt;

  forever begin

    @(negedge TX_TL_DL.CLK);

      fc_pkt = Sequence_item::type_id::create("fc_pkt");

      fc_pkt.fc_ph    = TX_TL_DL.fc_ph;
      fc_pkt.fc_pd    = TX_TL_DL.fc_pd;
      fc_pkt.fc_nph   = TX_TL_DL.fc_nph;
      fc_pkt.fc_npd   = TX_TL_DL.fc_npd;
      fc_pkt.fc_cmplh = TX_TL_DL.fc_cmplh;
      fc_pkt.fc_cmpld = TX_TL_DL.fc_cmpld;
      rc_FC_MD_ap.write(fc_pkt);
       end

endtask

task rc_collect_data_TX(Sequence_item t_x);

  bit [31:0] data_dw;
  bit        eop;

  ////////////////////////////////////////////////////
  // Wait For Start Of Packet
  ////////////////////////////////////////////////////
  t_x.tx_data_t.delete();

  @(negedge TX_TL_DL.CLK);
  wait(TX_TL_DL.tl_tx_valid);

  while (1) begin

    @(posedge TX_TL_DL.CLK);

    if (TX_TL_DL.tl_tx_valid && TX_TL_DL.tl_tx_ready) begin
      data_dw = TX_TL_DL.tl_tx_data;
      t_x.tx_data_t.push_back(data_dw);

      `uvm_info("TX_COLLECT",
        $sformatf("RC: Collected DW = %08h (queue size=%0d)",
                   data_dw, t_x.tx_data_t.size()),
        UVM_LOW)
    end

    if (!TX_TL_DL.tl_tx_valid)
      break;

  end

endtask
task rc_collect_dllp(Sequence_item r_x);
    
    bit [31:0] header [2];
    bit [31:0] crc_pkt_q;

    bit [15:0] crc;
    bit [15:0] cal_crc;

  r_x.dllp_packet_q.delete();

    while (TX_DLL_PCS.dl_mac_packet) begin

    wait (TX_DLL_PCS.dl_rx_valid &&
        TX_DLL_PCS.dl_rx_ready)
      
      header[0] = TX_DLL_PCS.dl_rx_data;
       r_x.rc_dllp_data_sb.push_back(header[0]);

      `uvm_info("RX_PKT", $sformatf("RC: Received DATA on TX_DLL_PCS.dl_rx_data = %08h", header[0]), UVM_LOW)
      crc_pkt_q = header[0];
                  
    @(negedge TX_DLL_PCS.CLK);
      
          wait (TX_DLL_PCS.dl_rx_valid &&
        TX_DLL_PCS.dl_rx_ready)
      
      header[1] = TX_DLL_PCS.dl_rx_data;
       r_x.rc_dllp_data_sb.push_back(header[1]);

        ///////WRITE///////
       rc_dllp_rx.write(r_x);  
      `uvm_info("RX_PKT", $sformatf("RC: Received DATA on TX_DLL_PCS.dl_rx_data = %08h", header[1]), UVM_LOW)
      crc  = header[1][31:16];
            
    @(negedge TX_DLL_PCS.CLK);

      
      cal_crc = crc16(crc_pkt_q);
                  `uvm_info("CRC_CHECK", $sformatf("RC: CRC MATCH - Calculated CRC = %04h, Received CRC = %04h", cal_crc, crc), UVM_LOW)
              `uvm_info("CRC_CHECK", $sformatf("EP: CRC MATCH - Calculated CRC = %04h, Received CRC = %04h", cal_crc, crc), UVM_LOW)
             if(cal_crc == crc) begin

              r_x.dllp_packet_q.push_back(crc_pkt_q);
        
              r_x.dllp_packet_q.push_back(crc);
	      	      	     if(header[0][7:4] == 4'b0100 || header[0][7:4] == 4'b1000) begin

  r_x.rc_data_type    = header[0][7:4];
  r_x.rc_dllp_vc      = header[0][2:0];
  r_x.rc_header_pfc   = header[0][17:10];
  r_x.rc_data_pfc     = header[0][31:20];

  `uvm_info("RC_FC",
            $sformatf("RC P FC DLLP: Type=%04b, VC=%0h, Header FC=%0h, Data FC=%0h",
                      r_x.rc_data_type,
                      r_x.rc_dllp_vc,
                      r_x.rc_header_pfc,
                      r_x.rc_data_pfc),
            UVM_LOW)

end

if(header[0][7:4] == 4'b0101 || header[0][7:4] == 4'b1001) begin

  r_x.rc_data_type     = header[0][7:4];
  r_x.rc_dllp_vc       = header[0][2:0];
  r_x.rc_header_npfc   = header[0][17:10];
  r_x.rc_data_npfc     = header[0][31:20];

  `uvm_info("RC_FC",
            $sformatf("RC NP FC DLLP: Type=%04b, VC=%0h, Header FC=%0h, Data FC=%0h",
                      r_x.rc_data_type,
                      r_x.rc_dllp_vc,
                      r_x.rc_header_npfc,
                      r_x.rc_data_npfc),
            UVM_LOW)

end

if(header[0][7:4] == 4'b0110 || header[0][7:4] == 4'b1010) begin

  r_x.rc_data_type       = header[0][7:4];
  r_x.rc_dllp_vc         = header[0][2:0];
  r_x.rc_header_cmplfc   = header[0][17:10];
  r_x.rc_data_cmplfc     = header[0][31:20];

  `uvm_info("RC_FC",
            $sformatf("RC CPL FC DLLP: Type=%04b, VC=%0h, Header FC=%0h, Data FC=%0h",
                      r_x.rc_data_type,
                      r_x.rc_dllp_vc,
                      r_x.rc_header_cmplfc,
                      r_x.rc_data_cmplfc),
            UVM_LOW)

end
        if(header[0][31:24]==8'b0000_0000 || header[0][31:24]== 8'b0001_0000) begin
          r_x.rc_ack_nack = header[0][31:24];
            
          r_x.rc_ack_nack_seq = header[0][12:0];
                 end
      end
        
          else begin

        `uvm_info("CRC_CHECK", $sformatf("RC: CRC MISMATCH - Calculated CRC = %04h, Received CRC = %04h", cal_crc, crc), UVM_LOW)
        `uvm_error("TX_DLL_MON",
               $sformatf("CRC MISMATCH : CALCULATED CRC = %08h RECEIVED CRC = %08h",
                         cal_crc,
                         crc))
          end

  end

endtask

task rc_collect_tlp(Sequence_item r_x);
  bit [31:0] seq_no;
  bit [31:0] dw;
  bit [31:0] body_q[$];   // raw DWs after seq_no: header+payload+ecrc+lcrc, undecoded
  bit [31:0] lcrc;
  bit [31:0] calc_lcrc;
  bit [31:0] lcrc_pkt_q[$];
    r_x.rx_data_t.delete();
    lcrc_pkt_q.delete();
    r_x.rc_com_data_sb.delete();
    body_q.delete();
  ////////////////////////////////////////////////////////////
  // SEQ NUM
  ////////////////////////////////////////////////////////////
 if(TX_DLL_PCS.tl_mac_packet) begin
  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));
 
       seq_no = TX_DLL_PCS.dl_rx_data;
 
       `uvm_info("RX_PKT", $sformatf("RC: Received DATA on TX_DLL_PCS.dl_rx_data = %08h", seq_no), UVM_LOW)
      
  lcrc_pkt_q.push_back(seq_no);
   r_x.rc_com_data_sb.push_back(seq_no);
  ////////////////////////////////////////////////////////////
  // COLLECT REST OF PACKET - no fmt/hdr_len/payload_length/td_bit
  // decode. Ride the handshake DW by DW until dl_rx_valid drops;
  // the last DW collected is the LCRC, everything before it is
  // header+payload+ecrc combined.
  ////////////////////////////////////////////////////////////
  while (1) begin
    @(negedge TX_DLL_PCS.CLK);
    if (TX_DLL_PCS.dl_rx_valid && TX_DLL_PCS.dl_rx_ready) begin
      dw = TX_DLL_PCS.dl_rx_data;
      `uvm_info("RX_PKT", $sformatf("RC: Received DATA on TX_DLL_PCS.dl_rx_data = %08h", dw), UVM_LOW)
      body_q.push_back(dw);
    end
    if (!TX_DLL_PCS.dl_rx_valid)
      break;
  end
  ////////////////////////////////////////////////////////////
  // LAST DW = LCRC, REST = HEADER+PAYLOAD+ECRC
  ////////////////////////////////////////////////////////////
  lcrc = body_q.pop_back();
  foreach(body_q[i]) begin
    lcrc_pkt_q.push_back(body_q[i]);
    r_x.rc_com_data_sb.push_back(body_q[i]);
  end
  r_x.rc_com_data_sb.push_back(lcrc);
/////////////////////////////call_write_for_SB/////////////////////
   rc_rx.write(r_x);
  calc_lcrc = rc_calculate_lcrc(lcrc_pkt_q);
  ////////////////////////////////////////////////////////////
  // LCRC CHECK
  ////////////////////////////////////////////////////////////
  `uvm_info("LCRC_CHECK", $sformatf("RC: LCRC MATCH - Calculated LCRC = %08h, Received LCRC = %08h", calc_lcrc, lcrc), UVM_LOW)
  `uvm_info("LCRC_CHECK", $sformatf("EP: LCRC MATCH - Calculated LCRC = %08h, Received LCRC = %08h", calc_lcrc, lcrc), UVM_LOW)
  if(calc_lcrc == lcrc) begin
   if(seq_no == RC_NRS)
  begin
    rc_ack_ev.trigger();
    
    r_x.rc_ack_nak_seq = seq_no;
    RC_NRS = RC_NRS + 1;
    RC_NACK_SCHEDULED = 0;
    //////////////////////////////////////////////////////////
    // STORE HEADER+PAYLOAD+ECRC (everything but LCRC)
    //////////////////////////////////////////////////////////
    foreach(body_q[i])
      r_x.rx_data_t.push_back(body_q[i]);
  end
    else if(seq_no < RC_NRS)
  begin
        rc_ack_ev.trigger();
    
    r_x.rc_ack_nak_seq = seq_no;
    RC_NACK_SCHEDULED = 0;
  end
    else if(seq_no > RC_NRS)
  begin
    	      if(RC_NACK_SCHEDULED == 0) begin

    // ERR_SEQ_NUM checker: the sender skipped/jumped ahead of
    // the sequence number this receiver expected next - a gap in
    // the DL sequence space. NAK + replay (below/triggered) is the
    // correct recovery; this uvm_error makes the anomaly explicit
    // for the negative test to catch.
    `uvm_error("SEQ_CHECK",
      $sformatf("Out-of-order/skipped DL sequence number: expected %0d, got %0d",
                 RC_NRS, seq_no))

    rc_nack_ev.trigger();
    if(RC_NRS == 0) begin
     r_x.rc_ack_nak_seq = 4095;
     end
    else begin
    r_x.rc_ack_nak_seq = RC_NRS-1;
    end
    RC_NACK_SCHEDULED = 1;
    
    end
  end
  end  else begin
        `uvm_info("LCRC_CHECK", $sformatf("RC: LCRC MISMATCH - Calculated LCRC = %08h, Received LCRC = %08h", calc_lcrc, lcrc), UVM_LOW)
        `uvm_error("TX_DLL_MON",
               $sformatf("LCRC MISMATCH : CALCULATED LCRC = %08h RECEIVED LCRC = %08h",
                         calc_lcrc,
                         lcrc))
	      if(RC_NACK_SCHEDULED == 0) begin
    rc_nack_ev.trigger();
    if(RC_NRS == 0) begin
     r_x.rc_ack_nak_seq = 4095;
     end
    else begin
    r_x.rc_ack_nak_seq = RC_NRS-1;
    end
    RC_NACK_SCHEDULED = 1;
     
     end
   
  end
  end
endtask

task rc_collect_request(Sequence_item t_x);
  bit [31:0] seq_no;
  bit [31:0] dw;
  bit [31:0] header0;
  bit [31:0] body_q[$];   // remaining DWs: header1..N + payload + ecrc + lcrc
  t_x.tx_data_sb.delete();
  body_q.delete();
  ////////////////////////////////////////////////////////////
  // SEQ NUM
  ////////////////////////////////////////////////////////////
   
 if(TX_DLL_PCS.tl_packet) begin
  if(TX_DLL_PCS.dl_tx_valid && TX_DLL_PCS.dl_tx_ready)	
  seq_no = TX_DLL_PCS.dl_tx_data;
  ////////////////////////////////////////////////////////////
  // HEADER DW0
  ////////////////////////////////////////////////////////////
  do begin
    @(negedge TX_DLL_PCS.CLK);
  end
  while(!(TX_DLL_PCS.dl_tx_valid &&
          TX_DLL_PCS.dl_tx_ready));
  header0 = TX_DLL_PCS.dl_tx_data;
  ////////////////////////////////////////////////////////////
  // COLLECT REST OF PACKET - no fmt/hdr_len/payload_length/td_bit
  // decode. Ride the handshake DW by DW until dl_tx_valid drops;
  // last DW collected is LCRC, everything else is the rest of
  // header + payload + ecrc.
  ////////////////////////////////////////////////////////////
  while (1) begin
    @(negedge TX_DLL_PCS.CLK);
    if (TX_DLL_PCS.dl_tx_valid && TX_DLL_PCS.dl_tx_ready) begin
      dw = TX_DLL_PCS.dl_tx_data;
      body_q.push_back(dw);
    end
    if (!TX_DLL_PCS.dl_tx_valid)
      break;
  end
   // STORE SEQ_NO
      t_x.tx_data_sb.push_back(seq_no);
   // STORE HEADER DW0
      t_x.tx_data_sb.push_back(header0);
   // STORE REST (header1..N + payload + ecrc + lcrc, in order received)
   foreach(body_q[i])
      t_x.tx_data_sb.push_back(body_q[i]);
  end
endtask
task rc_collect_dllp_sb(Sequence_item t_x);
    bit [31:0] header [2];
    bit [31:0] crc_pkt_q;


  t_x.rc_dllp_packet_sb.delete();

    while (TX_DLL_PCS.dl_packet) begin

    wait (TX_DLL_PCS.dl_tx_valid &&
        TX_DLL_PCS.dl_tx_ready)
      
      header[0] = TX_DLL_PCS.dl_tx_data;
   //   t_x.rc_dllp_packet_sb.push_back(header[0]); 
    @(negedge TX_DLL_PCS.CLK);
      
          wait (TX_DLL_PCS.dl_tx_valid &&
        TX_DLL_PCS.dl_tx_ready)
      
      header[1] = TX_DLL_PCS.dl_tx_data;
@(negedge TX_DLL_PCS.CLK);

      t_x.rc_dllp_packet_sb.push_back(header[0]); 
      t_x.rc_dllp_packet_sb.push_back(header[1]);   
      rc_dllp_tx.write(t_x);   

`uvm_info("RC_DLLP_RX", $sformatf("RC Received DLLP Packet = {%08h, %08h}", header[1], header[0]), UVM_LOW)			
  end

endtask


  //-----------------------------------------------------------
  // EP_MODE tasks - preserved exactly as RX_DLL_Monitor.sv
  //-----------------------------------------------------------
task ep_monitor_tx();

    Sequence_item tx_pkt;

    forever begin

      tx_pkt = Sequence_item::type_id::create("tx_pkt");

      ep_collect_data_tx(tx_pkt);

      ep_TX_MD_ap.write(tx_pkt);

    end

  endtask

task ep_monitor_rx();

    Sequence_item rx_pkt;

    forever begin

 @(negedge RX_DLL_PCS.CLK);

    // Wait until a valid transfer occurs
      if (!(RX_DLL_PCS.dl_rx_valid &&
          RX_DLL_PCS.dl_rx_ready))
      continue;

    rx_pkt = Sequence_item::type_id::create("rx_pkt");

    //------------------------------------------------------
    // DLLP Packet
    //------------------------------------------------------
      if (RX_DLL_PCS.dl_mac_packet) begin

      ep_collect_dllp(rx_pkt);

        if (rx_pkt.dllp_packet_rx_q.size() > 0) begin

                ep_RX_MD_ap.write(rx_pkt);

              end

    end

    //------------------------------------------------------
    // TLP Packet
    //------------------------------------------------------
      else if (RX_DLL_PCS.tl_mac_packet) begin

      ep_collect_tlp(rx_pkt);

        if (rx_pkt.rx_data.size() > 0||rx_pkt.ep_ack_nak_seq>0) begin
   
                ep_RX_MD_ap.write(rx_pkt);

              end

    end

  end
  endtask

    task ep_monitor_sb();

    Sequence_item tx_pkt;

  forever begin

    @(negedge RX_DLL_PCS.CLK);

    // Wait until a valid transfer occurs
    if (!(RX_DLL_PCS.dl_tx_valid &&
          RX_DLL_PCS.dl_tx_ready))
      continue;

    tx_pkt = Sequence_item::type_id::create("tx_pkt");

     if (RX_DLL_PCS.tl_packet) begin

      ep_collect_completion(tx_pkt);

      if (tx_pkt.rx_data_sb.size() > 0) begin
	       ep_tx.write(tx_pkt);

              end

    end
     else if (RX_DLL_PCS.dl_packet) begin

      ep_collect_dllp_sb(tx_pkt);

      if (tx_pkt.ep_dllp_packet_sb.size() > 0) begin

      //  rc_RX_MD_ap.write(tx_pkt);

              end

    end

    // ERR_STP checker (EP->RC direction) - see the RC-side
    // rc_monitor_sb() for the fully-commented version.

    end

  endtask
 task ep_monitor_fc_credits();

  Sequence_item fc_pkt;

   forever begin

    @(negedge RX_TL_DL.CLK);

fc_pkt = Sequence_item::type_id::create("fc_pkt");

      if( RX_TL_DL.ep_fc_update_valid) begin
  fc_pkt.ep_updated_credits = 1 ; 
  fc_pkt.ep_vc       = RX_TL_DL.ep_fc_update_vc;
  fc_pkt.ep_fc_ph    = RX_TL_DL.fc_ph[fc_pkt.ep_vc];
  fc_pkt.ep_fc_nph   = RX_TL_DL.fc_nph[fc_pkt.ep_vc];
  fc_pkt.ep_fc_cmplh = RX_TL_DL.fc_cmplh[fc_pkt.ep_vc];

  fc_pkt.ep_fc_pd    = RX_TL_DL.fc_pd[fc_pkt.ep_vc];
  fc_pkt.ep_fc_npd   = RX_TL_DL.fc_npd[fc_pkt.ep_vc];
  fc_pkt.ep_fc_cmpld = RX_TL_DL.fc_cmpld[fc_pkt.ep_vc];
  `uvm_info("EP_FC_UPDATE",
            $sformatf("EP FC Update: PH=%0h, NPH=%0h, CPLH=%0h, PD=%0h, NPD=%0h, CPLD=%0h, VC=%0h",
                      fc_pkt.ep_fc_ph,
                      fc_pkt.ep_fc_nph,
                      fc_pkt.ep_fc_cmplh,
                      fc_pkt.ep_fc_pd,
                      fc_pkt.ep_fc_npd,
                      fc_pkt.ep_fc_cmpld,
		      fc_pkt.ep_vc),
            UVM_LOW)
	    ep_FC_MD_ap.write(fc_pkt);
	    fc_pkt.ep_updated_credits = 0 ; 
  end
  else begin
    fc_pkt.ep_fc_ph    = RX_TL_DL.fc_ph;
  fc_pkt.ep_fc_nph   = RX_TL_DL.fc_nph;
  fc_pkt.ep_fc_cmplh = RX_TL_DL.fc_cmplh;

  fc_pkt.ep_fc_pd    = RX_TL_DL.fc_pd;
  fc_pkt.ep_fc_npd   = RX_TL_DL.fc_npd;
  fc_pkt.ep_fc_cmpld = RX_TL_DL.fc_cmpld;
      
      ep_FC_MD_ap.write(fc_pkt);
      end


     end 

endtask

task ep_collect_data_tx(Sequence_item t_x);
  bit [31:0] data_dw;
  ////////////////////////////////////////////////////
  // Wait For Start Of Packet
  ////////////////////////////////////////////////////
  t_x.tx_data.delete();
    @(negedge RX_TL_DL.CLK);
 
    wait(RX_TL_DL.tl_tx_valid);
  
      @(posedge RX_TL_DL.CLK);
  wait(RX_TL_DL.tl_tx_valid &&
       RX_TL_DL.tl_tx_ready);
  ////////////////////////////////////////////////////
  // Collect every DW while valid stays asserted - no
  // fmt/hdr_len/payload_length/td_bit decode, ride the
  // handshake until tl_tx_valid deasserts.
  ////////////////////////////////////////////////////
  data_dw = RX_TL_DL.tl_tx_data;
  t_x.tx_data.push_back(data_dw);
  while (1) begin
    @(posedge RX_TL_DL.CLK);
    if (RX_TL_DL.tl_tx_valid && RX_TL_DL.tl_tx_ready) begin
      data_dw = RX_TL_DL.tl_tx_data;
      t_x.tx_data.push_back(data_dw);
    end
    if (!RX_TL_DL.tl_tx_valid)
      break;
  end
endtask

task ep_collect_dllp(Sequence_item r_x);
    
    bit [31:0] header [2];
    bit [31:0] crc_pkt_q;

    bit [15:0] crc;
    bit [15:0] cal_crc;

  r_x.dllp_packet_rx_q.delete();

     while (RX_DLL_PCS.dl_mac_packet) begin

       wait (RX_DLL_PCS.dl_rx_valid &&
        RX_DLL_PCS.dl_rx_ready)
      
       header[0] = RX_DLL_PCS.dl_rx_data;
        r_x.ep_dllp_data_sb.push_back(header[0]);

      
       `uvm_info("RX_PKT", $sformatf("EP: Received DATA on RX_DLL_PCS.dl_rx_data = %08h", header[0]), UVM_LOW)
      crc_pkt_q = header[0];
             
    @(negedge RX_DLL_PCS.CLK);
    
  wait(RX_DLL_PCS.dl_rx_valid &&
          RX_DLL_PCS.dl_rx_ready);
      
       header[1] = RX_DLL_PCS.dl_rx_data;
         r_x.ep_dllp_data_sb.push_back(header[1]);
       ///////WRITE////////
        ep_dllp_rx.write(r_x);  
       `uvm_info("RX_PKT", $sformatf("EP: Received DATA on RX_DLL_PCS.dl_rx_data = %08h", header[1]), UVM_LOW)
      crc  = header[1][31:16];
       
    @(negedge RX_DLL_PCS.CLK);

      cal_crc = crc16(crc_pkt_q);
             if(cal_crc == crc) begin

              r_x.dllp_packet_rx_q.push_back(crc_pkt_q);
        
              r_x.dllp_packet_rx_q.push_back(crc);
	       if(header[0][7:4]==4'b0100 || header[0][7:4]==4'b1000)begin
		      r_x.ep_data_type = header[0][7:4];
		      r_x.ep_dllp_vc   = header[0][2:0];
		      r_x.ep_header_pfc = header[0][17:10];
		      r_x.ep_data_pfc   = header[0][31:20];
  `uvm_info("EP_FC",
            $sformatf("EP P FC DLLP: Type=%0b, VC=%0h, Header FC=%0h, Data FC=%0h",
                      r_x.ep_data_type,
                      r_x.ep_dllp_vc,
                      r_x.ep_header_pfc,
                      r_x.ep_data_pfc),
            UVM_LOW)
	      end 
	   	      if(header[0][7:4]==4'b0101 || header[0][7:4]==4'b1001)begin
			      r_x.ep_data_type = header[0][7:4];
			      r_x.ep_dllp_vc   = header[0][2:0];
                              r_x.ep_header_npfc = header[0][17:10];
		            r_x.ep_data_npfc   = header[0][31:20];
  `uvm_info("EP_FC",
            $sformatf("EP NP FC DLLP: Type=%0b, VC=%0h, Header FC=%0h, Data FC=%0h",
                      r_x.ep_data_type,
                      r_x.ep_dllp_vc,
                      r_x.ep_header_npfc,
                      r_x.ep_data_npfc),
            UVM_LOW)		       
	      end 
	      if(header[0][7:4]==4'b0110 || header[0][7:4]==4'b1010)begin
		      r_x.ep_data_type = header[0][7:4];
		      r_x.ep_dllp_vc   = header[0][2:0];

		      r_x.ep_header_cmplfc = header[0][17:10];
		      r_x.ep_data_cmplfc   = header[0][31:20];
		  `uvm_info("EP_FC",
            $sformatf("EP CPL FC DLLP: Type=%0b, VC=%0h, Header FC=%0h, Data FC=%0h",
                      r_x.ep_data_type,
                      r_x.ep_dllp_vc,
                      r_x.ep_header_cmplfc,
                      r_x.ep_data_cmplfc),
            UVM_LOW)       
	      end    

        if(header[0][31:24]==8'b0000_0000 || header[0][31:24]== 8'b0001_0000) begin
          r_x.ep_ack_nack = header[0][31:24];
          
          r_x.ep_ack_nack_seq = header[0][12:0];
                end
      end
       
          else begin

            `uvm_info("CRC_CHECK", $sformatf("EP: CRC MISMATCH - Calculated CRC = %04h, Received CRC = %04h", cal_crc, crc), UVM_LOW)
            `uvm_error("RX_DLL_MON",
               $sformatf("CRC MISMATCH : CALCULATED CRC = %08h RECEIVED CRC = %08h",
                         cal_crc,
                         crc))
          end

  end

endtask

task ep_collect_tlp(Sequence_item r_x);
  bit [31:0] seq_no;
  bit [31:0] dw;
  bit [31:0] body_q[$];
  bit [31:0] lcrc;
  bit [31:0] calc_lcrc;
  bit [31:0] lcrc_pkt_q[$];
  r_x.rx_data.delete();
  lcrc_pkt_q.delete();
  r_x.ep_req_data_sb.delete();
  body_q.delete();
  ////////////////////////////////////////////////////////////
  // SEQ NUM
  ////////////////////////////////////////////////////////////
   
 if(RX_DLL_PCS.tl_mac_packet) begin
  if(RX_DLL_PCS.dl_rx_valid && RX_DLL_PCS.dl_rx_ready)	
  seq_no = RX_DLL_PCS.dl_rx_data;
  `uvm_info("RX_PKT", $sformatf("EP: Received DATA on RX_DLL_PCS.dl_rx_data = %08h", seq_no), UVM_LOW)
  lcrc_pkt_q.push_back(seq_no);
  r_x.ep_req_data_sb.push_back(seq_no);
  ////////////////////////////////////////////////////////////
  // COLLECT REST OF PACKET - no fmt/hdr_len/payload_length/td_bit
  // decode. Ride the handshake DW by DW until dl_rx_valid drops;
  // last DW collected is LCRC, everything before it is
  // header+payload+ecrc combined.
  ////////////////////////////////////////////////////////////
  while (1) begin
    @(negedge RX_DLL_PCS.CLK);
    if (RX_DLL_PCS.dl_rx_valid && RX_DLL_PCS.dl_rx_ready) begin
      dw = RX_DLL_PCS.dl_rx_data;
      `uvm_info("RX_PKT", $sformatf("EP: Received DATA on RX_DLL_PCS.dl_rx_data = %08h", dw), UVM_LOW)
      body_q.push_back(dw);
    end
    if (!RX_DLL_PCS.dl_rx_valid)
      break;
  end
  lcrc = body_q.pop_back();
  foreach(body_q[i]) begin
    lcrc_pkt_q.push_back(body_q[i]);
    r_x.ep_req_data_sb.push_back(body_q[i]);
  end
  `uvm_info("RX_PKT", $sformatf("EP: Received DATA on RX_DLL_PCS.dl_rx_data = %08h", lcrc), UVM_LOW)
  r_x.ep_req_data_sb.push_back(lcrc);
  ep_rx.write(r_x); //////////SENDING_SB/////////
  calc_lcrc = ep_calculate_lcrc(lcrc_pkt_q);
  ////////////////////////////////////////////////////////////
  // LCRC CHECK
  ////////////////////////////////////////////////////////////
  if(calc_lcrc == lcrc) begin
if(seq_no == EP_NRS)
  begin
    ep_ack_ev.trigger();
    
    r_x.ep_ack_nak_seq = seq_no;
    EP_NRS = EP_NRS + 1;
    EP_NACK_SCHEDULED = 0;
    //////////////////////////////////////////////////////////
    // STORE HEADER+PAYLOAD+ECRC (everything but LCRC)
    //////////////////////////////////////////////////////////
    foreach(body_q[i])
      r_x.rx_data.push_back(body_q[i]);
    end
    
    else if(seq_no < EP_NRS)
  begin
         ep_ack_ev.trigger();
    
    r_x.ep_ack_nak_seq = seq_no;
     EP_NACK_SCHEDULED = 0;
  end
    else if(seq_no > EP_NRS)
  begin
     	      if(EP_NACK_SCHEDULED == 0) begin

    // ERR_SEQ_NUM checker (EP->RC direction) - see RC-side for
    // the fully-commented version.
    `uvm_error("SEQ_CHECK",
      $sformatf("Out-of-order/skipped DL sequence number: expected %0d, got %0d",
                 EP_NRS, seq_no))

    ep_nack_ev.trigger();
    if(EP_NRS==0) begin
	        r_x.ep_ack_nak_seq = 4095;
    end
    else begin
    r_x.ep_ack_nak_seq = EP_NRS-1;
    end
    EP_NACK_SCHEDULED = 1;
  end
  end
  end
  else begin
    `uvm_info("LCRC_CHECK", $sformatf("EP: LCRC MISMATCH - Calculated LCRC = %08h, Received LCRC = %08h", calc_lcrc, lcrc), UVM_LOW)
    `uvm_error("RX_DLL_MON",
               $sformatf("LCRC MISMATCH : CALCULATED LCRC = %08h RECEIVED LCRC = %08h",
                         calc_lcrc,
                         lcrc))
	      if(EP_NACK_SCHEDULED == 0) begin
    ep_nack_ev.trigger();
    
    EP_NACK_SCHEDULED = 1;
         if(EP_NRS==0) begin
	        r_x.ep_ack_nak_seq = 4095;
    end
    else begin
    r_x.ep_ack_nak_seq = EP_NRS-1;
    end
               end
  end
 
end
endtask

task ep_collect_completion(Sequence_item t_x);
  bit [31:0] seq_no;
  bit [31:0] dw;
  bit [31:0] header0;
  bit [31:0] body_q[$];
  t_x.rx_data_sb.delete();
  body_q.delete();
  ////////////////////////////////////////////////////////////
  // SEQ NUM
  ////////////////////////////////////////////////////////////
   
 if(RX_DLL_PCS.tl_packet) begin
  if(RX_DLL_PCS.dl_tx_valid && RX_DLL_PCS.dl_tx_ready)	
  seq_no = RX_DLL_PCS.dl_tx_data;
  ////////////////////////////////////////////////////////////
  // HEADER DW0
  ////////////////////////////////////////////////////////////
  do begin
    @(negedge RX_DLL_PCS.CLK);
  end
  while(!(RX_DLL_PCS.dl_tx_valid &&
          RX_DLL_PCS.dl_tx_ready));
  header0 = RX_DLL_PCS.dl_tx_data;
  ////////////////////////////////////////////////////////////
  // COLLECT REST OF PACKET - no fmt/hdr_len/payload_length/td_bit
  // decode. Ride the handshake DW by DW until dl_tx_valid drops;
  // last DW collected is LCRC.
  ////////////////////////////////////////////////////////////
  while (1) begin
    @(negedge RX_DLL_PCS.CLK);
    if (RX_DLL_PCS.dl_tx_valid && RX_DLL_PCS.dl_tx_ready) begin
      dw = RX_DLL_PCS.dl_tx_data;
      body_q.push_back(dw);
    end
    if (!RX_DLL_PCS.dl_tx_valid)
      break;
  end
   // STORE SEQ_NO
      t_x.rx_data_sb.push_back(seq_no);
   // STORE HEADER DW0
      t_x.rx_data_sb.push_back(header0);
   // STORE REST (header1..N + payload + ecrc + lcrc, in order received)
   foreach(body_q[i])
      t_x.rx_data_sb.push_back(body_q[i]);
   end
endtask
task ep_collect_dllp_sb(Sequence_item t_x);
    bit [31:0] header [2];
    bit [31:0] crc_pkt_q;


  t_x.ep_dllp_packet_sb.delete();

    while (RX_DLL_PCS.dl_packet) begin

    wait (RX_DLL_PCS.dl_tx_valid &&
          RX_DLL_PCS.dl_tx_ready)
      
      header[0] = RX_DLL_PCS.dl_tx_data;
    @(negedge RX_DLL_PCS.CLK);
      
          wait (RX_DLL_PCS.dl_tx_valid &&
        RX_DLL_PCS.dl_tx_ready)
      
      header[1] = RX_DLL_PCS.dl_tx_data;
@(negedge RX_DLL_PCS.CLK);

      t_x.ep_dllp_packet_sb.push_back(header[0]); 
      t_x.ep_dllp_packet_sb.push_back(header[1]);   
 ep_dllp_tx.write(t_x); 
`uvm_info("RC_DLLP_RX", $sformatf("EP Received DLLP Packet = {%08h, %08h}", header[1], header[0]), UVM_LOW)			
  end



endtask


  //-----------------------------------------------------------
  // run_phase - dispatches to the correct role's monitor threads
  //-----------------------------------------------------------
  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        TX_DLL_PCS.dl_rx_ready = 1'b1;
        TX_TL_DL.tl_tx_ready   = 1'b1;
                fork
          rc_monitor_tx();
          rc_monitor_rx();
	  rc_monitor_sb();
  rc_monitor_fc_credits();		  
        join_none
      end

      EP_MODE: begin
        RX_DLL_PCS.dl_rx_ready = 1'b1;
        RX_TL_DL.tl_tx_ready   = 1'b1;
        fork
          ep_monitor_tx();
          ep_monitor_rx();
	  ep_monitor_sb();
	  ep_monitor_fc_credits();
        join_none
      end

      default: `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass : PCIe_DLL_Monitor
