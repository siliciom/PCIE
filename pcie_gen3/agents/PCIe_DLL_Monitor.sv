class PCIe_DLL_Monitor extends uvm_monitor;

  env_cfg cfg;
  string  tag;

  virtual TX_TL_DL_Interface   TX_TL_DL;
  virtual TX_DLL_PCS_Interface TX_DLL_PCS;

  virtual RX_TL_DL_Interface   RX_TL_DL;
  virtual RX_DLL_PCS_Interface RX_DLL_PCS;

  uvm_analysis_port #(Sequence_item) rc_RX_MD_ap;
  uvm_analysis_port #(Sequence_item) rc_TX_MD_ap;

  uvm_analysis_port #(Sequence_item) ep_RX_MD_ap;
  uvm_analysis_port #(Sequence_item) ep_TX_MD_ap;

  uvm_event nack_ev;

  `uvm_component_utils(PCIe_DLL_Monitor)

  function new(string name = "PCIe_DLL_Monitor", uvm_component parent = null);
    super.new(name, parent);

    rc_RX_MD_ap = new("rc_RX_MD_ap", this);
    rc_TX_MD_ap = new("rc_TX_MD_ap", this);
    ep_RX_MD_ap = new("ep_RX_MD_ap", this);
    ep_TX_MD_ap = new("ep_TX_MD_ap", this);

  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_DLL_Monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_DLL_Monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    nack_ev = uvm_event_pool::get_global("NAK_DLLP_EVENT");

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unable to access TX_TL_DL from config_db", tag))

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unable to access TX_DLL_PCS from config_db", tag))

        `uvm_info("PCIe_DLL_Monitor", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("RX_DLL_MON", $sformatf("[%s] Cannot Access RX_TL_DL", tag))

        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
          `uvm_fatal("RX_DLL_MON", $sformatf("[%s] Cannot Access RX_DLL_PCS", tag))

        `uvm_info("PCIe_DLL_Monitor", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  //-----------------------------------------------------------
  // Shared helper - byte-identical across all 4 reference files
  //-----------------------------------------------------------
  function bit [31:0] calculate_lcrc(input bit [31:0] pkt_q[$]);
    bit [31:0] crc;
    bit data_bit;
    bit feedback;
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
    crc = ~crc;
    return crc;
  endfunction

  //-----------------------------------------------------------
  // RC_MODE tasks - preserved exactly as TX_DLL_Monitor.sv
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

      rx_pkt = Sequence_item::type_id::create("rx_pkt");

      rc_collect_data_RX(rx_pkt);
 `uvm_info("PCIe_DLL_MON", $sformatf("DLL_PACKET_q %p",rx_pkt.dllp_packet_q),UVM_LOW)
      if((rx_pkt.rx_data_t.size() > 0) ||(rx_pkt.dllp_packet_q.size() > 0)) begin
	      `uvm_info("PCIe_DLL_MON", $sformatf("DLL_PACKET_q %p",rx_pkt.dllp_packet_q),UVM_LOW)
        rc_RX_MD_ap.write(rx_pkt);
end

    end

  endtask

task rc_collect_data_TX(Sequence_item t_x);

  bit [31:0] header[4];
  bit [31:0] payload_q[1024];

  bit [31:0] ecrc;

  int payload_length;
  int hdr_len;

  bit [2:0] fmt;
  bit td_bit;
  bit has_data;

  ////////////////////////////////////////////////////
  // Wait For Start Of Packet
  ////////////////////////////////////////////////////
 
   
   @(negedge TX_TL_DL.CLK);
 
    wait(TX_TL_DL.tl_tx_valid);
  
        @(posedge TX_TL_DL.CLK);

  `uvm_info("MON",
          $sformatf("Waiting for dl_rx_valid at time=%0t", $time),
          UVM_LOW)
  wait(TX_TL_DL.tl_tx_valid &&
       TX_TL_DL.tl_tx_ready);
`uvm_info("MON",
          $sformatf("Waiting done dl_rx_valid at time=%0t", $time),
          UVM_LOW)
  ////////////////////////////////////////////////////
  // Capture FC Credits
  ////////////////////////////////////////////////////

  t_x.fc_ph    = TX_TL_DL.fc_ph;
  t_x.fc_nph   = TX_TL_DL.fc_nph;
  t_x.fc_cmplh = TX_TL_DL.fc_cmplh;

  t_x.fc_pd    = TX_TL_DL.fc_pd;
  t_x.fc_npd   = TX_TL_DL.fc_npd;
  t_x.fc_cmpld = TX_TL_DL.fc_cmpld;

  ////////////////////////////////////////////////////
  // HEADER DW0
  ////////////////////////////////////////////////////

  header[0] = TX_TL_DL.tl_tx_data;

    `uvm_info("PCIe_DLL_MON",
             $sformatf("HEADER[0] = %08h",
                       header[0]),
             UVM_LOW)

  ////////////////////////////////////////////////////
  // Decode Header Length
  ////////////////////////////////////////////////////

  fmt = header[0][31:29];

   if((fmt == 3'b000) ||
      (fmt == 3'b010))
    hdr_len = 3;
  else
    hdr_len = 4;

   `uvm_info("PCIe_DLL_MON",
             $sformatf("FMT = %03b  HDR_LEN = %0d DW",
                       fmt,
                       hdr_len),
             UVM_LOW)

  ////////////////////////////////////////////////////
  // Remaining Header DWs
  ////////////////////////////////////////////////////

  for(int i = 1; i < hdr_len; i++) begin

    @(posedge TX_TL_DL.CLK);

    wait(TX_TL_DL.tl_tx_valid &&
         TX_TL_DL.tl_tx_ready);

    header[i] = TX_TL_DL.tl_tx_data;

     `uvm_info("PCIe_DLL_MON",
               $sformatf("HEADER[%0d] = %08h",
                         i,
                         header[i]),
               UVM_LOW)

  end

  ////////////////////////////////////////////////////
  // Payload Info
  ////////////////////////////////////////////////////

  payload_length = header[0][9:0];

   has_data = (fmt == 3'b010) ||
   (fmt == 3'b011);

  td_bit = header[0][15];

   `uvm_info("PCIe_DLL_MON",
             $sformatf("PAYLOAD_LENGTH = %0d DW  TD = %0b  HAS_DATA = %0b",
                       payload_length,
                       td_bit,
                       has_data),
             UVM_LOW)

  ////////////////////////////////////////////////////
  // Payload Collection
  ////////////////////////////////////////////////////

  if(has_data) begin

    for(int i = 0; i < payload_length; i++) begin

      @(posedge TX_TL_DL.CLK);

      wait(TX_TL_DL.tl_tx_valid &&
           TX_TL_DL.tl_tx_ready);

      payload_q[i] = TX_TL_DL.tl_tx_data;

       `uvm_info("PCIe_DLL_MON",
                 $sformatf("PAYLOAD[%0d] = %08h",
                           i,
                           payload_q[i]),
                 UVM_LOW)

    end

  end

  ////////////////////////////////////////////////////
  // ECRC Collection
  ////////////////////////////////////////////////////

  if(td_bit) begin

    @(posedge TX_TL_DL.CLK);

    wait(TX_TL_DL.tl_tx_valid &&
         TX_TL_DL.tl_tx_ready);

    ecrc = TX_TL_DL.tl_tx_data;

    `uvm_info("PCIe_DLL_MON",
              $sformatf("ECRC = %08h",
                        ecrc),
              UVM_LOW)

  end

  ////////////////////////////////////////////////////
  // Store Header Into tx_data Queue
  ////////////////////////////////////////////////////

  for(int i = 0; i < hdr_len; i++)
    t_x.tx_data_t.push_back(header[i]);

  ////////////////////////////////////////////////////
  // Store Payload Into tx_data Queue
  ////////////////////////////////////////////////////

  if(has_data) begin

    for(int i = 0; i < payload_length; i++)begin
      t_x.tx_data_t.push_back(payload_q[i]);
    end

  end

  ////////////////////////////////////////////////////
  // Store ECRC Into tx_data Queue
  ////////////////////////////////////////////////////

  if(td_bit)
    t_x.tx_data_t.push_back(ecrc);

  ////////////////////////////////////////////////////
  // Final Packet Dump
  ////////////////////////////////////////////////////

    `uvm_info("PCIe_DLL_MON",
             $sformatf("Collected TX Packet : %0d DW",
                       t_x.tx_data_t.size()),
             UVM_LOW)

   foreach(t_x.tx_data_t[i]) begin

     `uvm_info("PCIe_DLL_MON",
               $sformatf("TX_DATA_T[%0d] = %08h",
                         i,
                         t_x.tx_data_t[i]),
               UVM_LOW)

  end

endtask

task rc_collect_data_RX(Sequence_item r_x);

  bit [31:0] seq_no;

  bit [31:0] header[4];
  bit [31:0] payload_q[1024];

  bit [31:0] ecrc;
  bit [31:0] lcrc;
  bit [31:0] calc_lcrc;

  bit [31:0] lcrc_pkt_q[$];

  int payload_length;
  int hdr_len;

  bit [2:0] fmt;
  bit td_bit;
  bit has_data;


 wait(TX_DLL_PCS.dl_rx_valid);

if (TX_DLL_PCS.dl_mac_packet) begin
  while (1) begin
    @(negedge TX_DLL_PCS.CLK);

    if (TX_DLL_PCS.dl_rx_valid && TX_DLL_PCS.dl_rx_ready && TX_DLL_PCS.dl_mac_packet) begin
      r_x.dllp_packet_q.push_back(TX_DLL_PCS.dl_rx_data);

      `uvm_info("DLL_TX_MON",
                $sformatf("DLLP_PACKET_Q = %p",
                          r_x.dllp_packet_q),
                UVM_LOW)
    end
    else begin
      break;
    end
  end
end
 

  ////////////////////////////////////////////////////////////
  // SEQ NUM
  ////////////////////////////////////////////////////////////
    @(negedge TX_DLL_PCS.CLK);
 if(TX_DLL_PCS.tl_mac_packet) begin

  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));
 
     
       seq_no = TX_DLL_PCS.dl_rx_data;
      `uvm_info("PCIe_DLL_MON",
            $sformatf("SEQ_NUM = %08h",
                      seq_no),
            UVM_LOW)

  lcrc_pkt_q.push_back(seq_no);

  ////////////////////////////////////////////////////////////
  // HEADER DW0
  ////////////////////////////////////////////////////////////

do begin
	  
    @(negedge TX_DLL_PCS.CLK);
    

  end
  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));
  header[0] = TX_DLL_PCS.dl_rx_data;

      `uvm_info("PCIe_DLL_MON",
            $sformatf("HEADER[0] = %08h",
                      header[0]),
            UVM_LOW)

  lcrc_pkt_q.push_back(header[0]);

  ////////////////////////////////////////////////////////////
  // HEADER LENGTH
  ////////////////////////////////////////////////////////////

  fmt = header[0][31:29];

  if((fmt == 3'b000) ||
     (fmt == 3'b010))
    hdr_len = 3;
  else
    hdr_len = 4;

      `uvm_info("PCIe_DLL_MON",
            $sformatf("FMT = %03b  HDR_LEN = %0d DW",
                      fmt,
                      hdr_len),
            UVM_LOW)

  ////////////////////////////////////////////////////////////
  // REMAINING HEADER DWS
  ////////////////////////////////////////////////////////////
  for(int i = 1; i < hdr_len; i++) begin

 do begin
	  
    @(negedge TX_DLL_PCS.CLK);
    

  end
  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));

    header[i] = TX_DLL_PCS.dl_rx_data;

        `uvm_info("TX_DLL_MON",
              $sformatf("HEADER[%0d] = %08h",
                        i,
                        header[i]),
              UVM_LOW)

    lcrc_pkt_q.push_back(header[i]);


  end

  ////////////////////////////////////////////////////////////
  // PAYLOAD INFO
  ////////////////////////////////////////////////////////////

  payload_length = header[0][9:0];

    has_data = (fmt == 3'b000) ||
    (fmt == 3'b010);

  td_bit = header[0][15];

    `uvm_info("PCIe_DLL_MON",
            $sformatf("PAYLOAD_LENGTH = %0d DW  TD = %0b  HAS_DATA = %0b",
                      payload_length,
                      td_bit,
                      has_data),
            UVM_LOW)

  ////////////////////////////////////////////////////////////
  // PAYLOAD
  ////////////////////////////////////////////////////////////

  if(has_data) begin

    for(int i = 0; i < payload_length; i++) begin

    do begin
	  
    @(negedge TX_DLL_PCS.CLK);
    

  end
  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));
      payload_q[i] = TX_DLL_PCS.dl_rx_data;

            `uvm_info("PCIe_DLL_MON",
                $sformatf("PAYLOAD[%0d] = %08h",
                          i,
                          payload_q[i]),
                UVM_LOW)

      lcrc_pkt_q.push_back(payload_q[i]);


    end

  end

  ////////////////////////////////////////////////////////////
  // ECRC
  ////////////////////////////////////////////////////////////

  if(td_bit) begin

     do begin
	  
    @(negedge TX_DLL_PCS.CLK);
    

  end
  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));

    ecrc = TX_DLL_PCS.dl_rx_data;

        `uvm_info("PCIe_DLL_MON",
              $sformatf("ECRC = %08h",
                        ecrc),
              UVM_LOW)

    lcrc_pkt_q.push_back(ecrc);


  end

  ////////////////////////////////////////////////////////////
  // LCRC
  ////////////////////////////////////////////////////////////

  do begin
	  
    @(negedge TX_DLL_PCS.CLK);
    

  end
  while(!(TX_DLL_PCS.dl_rx_valid &&
          TX_DLL_PCS.dl_rx_ready));
  lcrc = TX_DLL_PCS.dl_rx_data;
  


    //   `uvm_info("TX_DLL_MON",
//             $sformatf("RECEIVED LCRC = %08h",
//                       lcrc),
//             UVM_LOW)

  calc_lcrc = calculate_lcrc(lcrc_pkt_q);

  `uvm_info("RX_DLL_MON",
            $sformatf("CALCULATED LCRC = %08h",
                      calc_lcrc),
            UVM_LOW)

  ////////////////////////////////////////////////////////////
  // LCRC CHECK
  ////////////////////////////////////////////////////////////

  if(calc_lcrc == lcrc) begin

        `uvm_info("PCIe_DLL_MON",
              $sformatf("LCRC MATCHED : CALCULATED LCRC = %08h RECEIVED LCRC = %08h",
                        calc_lcrc,
                        lcrc),
              UVM_LOW)

    //////////////////////////////////////////////////////////
    // STORE HEADER
    //////////////////////////////////////////////////////////

    for(int i = 0; i < hdr_len; i++)
      r_x.rx_data_t.push_back(header[i]);

    //////////////////////////////////////////////////////////
    // STORE PAYLOAD
    //////////////////////////////////////////////////////////

    if(has_data) begin

      for(int i = 0; i < payload_length; i++)
        r_x.rx_data_t.push_back(payload_q[i]);

    end

    //////////////////////////////////////////////////////////
    // STORE ECRC
    //////////////////////////////////////////////////////////

    if(td_bit)
      r_x.rx_data_t.push_back(ecrc);

    //////////////////////////////////////////////////////////
    // FINAL PACKET DUMP
    //////////////////////////////////////////////////////////

        `uvm_info("PCIe_DLL_MON",
              $sformatf("Collected RX Packet : %0d DW",
                        r_x.rx_data_t.size()),
              UVM_LOW)

    foreach(r_x.rx_data_t[i]) begin

            `uvm_info("PCIe_DLL_MON",
                $sformatf("RX_DATA[%0d] = %08h",
                          i,
                          r_x.rx_data_t[i]),
                UVM_LOW)

    end

  end
  else begin

        `uvm_error("PCIe_DLL_MON",
               $sformatf("LCRC MISMATCH : CALCULATED LCRC = %08h RECEIVED LCRC = %08h",
                         calc_lcrc,
                         lcrc))

    nack_ev.trigger();

    return;

  end
  end
`uvm_info("DLL_TX_MON",
                $sformatf("DLLP_PACKET_Q = %p",
                          r_x.dllp_packet_q),
                UVM_LOW)

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

      rx_pkt = Sequence_item::type_id::create("rx_pkt");

      ep_collect_data_rx(rx_pkt);

		if((rx_pkt.rx_data.size() > 0) || (rx_pkt.dllp_packet_rx_q.size()>0)) begin
	      `uvm_info("DLL_RX_MON",
                $sformatf("DLLP_PACKET_Q = %p",
                          rx_pkt.dllp_packet_rx_q),
                UVM_LOW)

        ep_RX_MD_ap.write(rx_pkt);
end
    end

  endtask

task ep_collect_data_tx(Sequence_item t_x);

  bit [31:0] header[4];
  bit [31:0] payload_q[1024];

  bit [31:0] ecrc;

  int payload_length;
  int hdr_len;

  bit [2:0] fmt;
  bit td_bit;
  bit has_data;

  ////////////////////////////////////////////////////
  // Wait For Start Of Packet
  ////////////////////////////////////////////////////
 
   
    @(negedge RX_TL_DL.CLK);
 
    wait(RX_TL_DL.tl_tx_valid);
  
  
  
      @(posedge RX_TL_DL.CLK);

  
  wait(RX_TL_DL.tl_tx_valid &&
       RX_TL_DL.tl_tx_ready);

  ////////////////////////////////////////////////////
  // Capture FC Credits
  ////////////////////////////////////////////////////

  t_x.fc_ph    = RX_TL_DL.fc_ph;
  t_x.fc_nph   = RX_TL_DL.fc_nph;
  t_x.fc_cmplh = RX_TL_DL.fc_cmplh;

  t_x.fc_pd    = RX_TL_DL.fc_pd;
  t_x.fc_npd   = RX_TL_DL.fc_npd;
  t_x.fc_cmpld = RX_TL_DL.fc_cmpld;

  ////////////////////////////////////////////////////
  // HEADER DW0
  ////////////////////////////////////////////////////

  header[0] = RX_TL_DL.tl_tx_data;

  `uvm_info("RX_DLL_MON",
            $sformatf("HEADER[0] = %08h",
                      header[0]),
            UVM_LOW)

  ////////////////////////////////////////////////////
  // Decode Header Length
  ////////////////////////////////////////////////////

  fmt = header[0][31:29];

  if((fmt == 3'b000) ||
     (fmt == 3'b010))
    hdr_len = 3;
  else
    hdr_len = 4;

  `uvm_info("RX_DLL_MON",
            $sformatf("FMT = %03b  HDR_LEN = %0d DW",
                      fmt,
                      hdr_len),
            UVM_LOW)

  ////////////////////////////////////////////////////
  // Remaining Header DWs
  ////////////////////////////////////////////////////

  for(int i = 1; i < hdr_len; i++) begin

    @(posedge RX_TL_DL.CLK);

    wait(RX_TL_DL.tl_tx_valid &&
         RX_TL_DL.tl_tx_ready);

    header[i] = RX_TL_DL.tl_tx_data;

    `uvm_info("RX_DLL_MON",
              $sformatf("HEADER[%0d] = %08h",
                        i,
                        header[i]),
              UVM_LOW)

  end

  ////////////////////////////////////////////////////
  // Payload Info
  ////////////////////////////////////////////////////

  payload_length = header[0][9:0];

  has_data = (fmt == 3'b000) ||
  (fmt == 3'b010);

  td_bit = header[0][15];

  `uvm_info("RX_DLL_MON",
            $sformatf("PAYLOAD_LENGTH = %0d DW  TD = %0b  HAS_DATA = %0b",
                      payload_length,
                      td_bit,
                      has_data),
            UVM_LOW)

  ////////////////////////////////////////////////////
  // Payload Collection
  ////////////////////////////////////////////////////

  if(has_data) begin

    for(int i = 0; i < payload_length; i++) begin

      @(posedge RX_TL_DL.CLK);

      wait(RX_TL_DL.tl_tx_valid &&
           RX_TL_DL.tl_tx_ready);

      payload_q[i] = RX_TL_DL.tl_tx_data;

      `uvm_info("RX_DLL_MON",
                $sformatf("PAYLOAD[%0d] = %08h",
                          i,
                          payload_q[i]),
                UVM_LOW)

    end

  end

  ////////////////////////////////////////////////////
  // ECRC Collection
  ////////////////////////////////////////////////////

  if(td_bit) begin

    @(posedge RX_TL_DL.CLK);

    wait(RX_TL_DL.tl_tx_valid &&
         RX_TL_DL.tl_tx_ready);

    ecrc = RX_TL_DL.tl_tx_data;

    `uvm_info("RX_DLL_MON",
              $sformatf("ECRC = %08h",
                        ecrc),
              UVM_LOW)

  end

  ////////////////////////////////////////////////////
  // Store Header Into tx_data Queue
  ////////////////////////////////////////////////////

  for(int i = 0; i < hdr_len; i++)
    t_x.tx_data.push_back(header[i]);

  ////////////////////////////////////////////////////
  // Store Payload Into tx_data Queue
  ////////////////////////////////////////////////////

  if(has_data) begin

    for(int i = 0; i < payload_length; i++)
      t_x.tx_data.push_back(payload_q[i]);

  end

  ////////////////////////////////////////////////////
  // Store ECRC Into tx_data Queue
  ////////////////////////////////////////////////////

  if(td_bit)
    t_x.tx_data.push_back(ecrc);

  ////////////////////////////////////////////////////
  // Final Packet Dump
  ////////////////////////////////////////////////////

  `uvm_info("RX_DLL_MON",
            $sformatf("Collected TX Packet : %0d DW",
                      t_x.tx_data.size()),
            UVM_LOW)

  foreach(t_x.tx_data[i]) begin

    `uvm_info("RX_DLL_MON",
              $sformatf("TX_DATA[%0d] = %08h",
                        i,
                        t_x.tx_data[i]),
              UVM_LOW)

  end

endtask

task ep_collect_data_rx(Sequence_item r_x);

  bit [31:0] seq_no;

  bit [31:0] header[4];
  bit [31:0] payload_q[1024];

  bit [31:0] ecrc;
  bit [31:0] lcrc;
  bit [31:0] calc_lcrc;

  bit [31:0] lcrc_pkt_q[$];

  int payload_length;
  int hdr_len;

  bit [2:0] fmt;
  bit td_bit;
  bit has_data;

  r_x.rx_data.delete();
  lcrc_pkt_q.delete();

  ////////////////////////////////////////////////////////////
  // SEQ NUM
  ////////////////////////////////////////////////////////////
   //   @(posedge RX_DLL_PCS.CLK);
   //
   
 
  wait(RX_DLL_PCS.dl_rx_valid);

  if (RX_DLL_PCS.dl_mac_packet) begin
  while (1) begin
    @(negedge RX_DLL_PCS.CLK);

    if (RX_DLL_PCS.dl_rx_valid && RX_DLL_PCS.dl_rx_ready && RX_DLL_PCS.dl_mac_packet) begin
      r_x.dllp_packet_rx_q.push_back(RX_DLL_PCS.dl_rx_data);

      `uvm_info("DLL_RX_MON",
                $sformatf("DLLP_PACKET_Q = %p",
                          r_x.dllp_packet_rx_q),
                UVM_LOW)
    end
    else begin
      break;
    end
  end
end
    @(negedge RX_DLL_PCS.CLK);
if(RX_DLL_PCS.tl_mac_packet) begin

  if(RX_DLL_PCS.dl_rx_valid && RX_DLL_PCS.dl_rx_ready)	
  seq_no = RX_DLL_PCS.dl_rx_data;

  `uvm_info("RX_DLL_MON",
            $sformatf("@%0t SEQ_NO = %08h",
                      $time,
                      seq_no),
            UVM_LOW)

  lcrc_pkt_q.push_back(seq_no);

  ////////////////////////////////////////////////////////////
  // HEADER DW0
  ////////////////////////////////////////////////////////////

  do begin
    @(negedge RX_DLL_PCS.CLK);
  end
  while(!(RX_DLL_PCS.dl_rx_valid &&
          RX_DLL_PCS.dl_rx_ready));

  header[0] = RX_DLL_PCS.dl_rx_data;

  `uvm_info("RX_DLL_MON",
            $sformatf("@%0t HEADER[0] = %08h",
                      $time,
                      header[0]),
            UVM_LOW)

  lcrc_pkt_q.push_back(header[0]);

  ////////////////////////////////////////////////////////////
  // HEADER LENGTH
  ////////////////////////////////////////////////////////////

  fmt = header[0][31:29];

  if((fmt == 3'b000) ||
     (fmt == 3'b010))
    hdr_len = 3;
  else
    hdr_len = 4;

  `uvm_info("RX_DLL_MON",
            $sformatf("@%0t FMT=%03b HDR_LEN=%0d",
                      $time,
                      fmt,
                      hdr_len),
            UVM_LOW)

  ////////////////////////////////////////////////////////////
  // REMAINING HEADER DWS
  ////////////////////////////////////////////////////////////

  for(int i = 1; i < hdr_len; i++) begin

    do begin
      @(negedge RX_DLL_PCS.CLK);
    end
    while(!(RX_DLL_PCS.dl_rx_valid &&
            RX_DLL_PCS.dl_rx_ready));

    header[i] = RX_DLL_PCS.dl_rx_data;

    `uvm_info("RX_DLL_MON",
              $sformatf("@%0t HEADER[%0d] = %08h",
                        $time,
                        i,
                        header[i]),
              UVM_LOW)

    lcrc_pkt_q.push_back(header[i]);

  end

  ////////////////////////////////////////////////////////////
  // PAYLOAD INFO
  ////////////////////////////////////////////////////////////

  payload_length = header[0][9:0];

  has_data = (fmt == 3'b010) ||
             (fmt == 3'b011);

  td_bit = header[0][15];

  `uvm_info("RX_DLL_MON",
            $sformatf("@%0t PAYLOAD_LEN=%0d TD=%0b HAS_DATA=%0b",
                      $time,
                      payload_length,
                      td_bit,
                      has_data),
            UVM_LOW)

  ////////////////////////////////////////////////////////////
  // PAYLOAD
  ////////////////////////////////////////////////////////////

  if(has_data) begin

    for(int i = 0; i < payload_length; i++) begin

      do begin
        @(negedge RX_DLL_PCS.CLK);
      end
      while(!(RX_DLL_PCS.dl_rx_valid &&
              RX_DLL_PCS.dl_rx_ready));

      payload_q[i] = RX_DLL_PCS.dl_rx_data;

      `uvm_info("RX_DLL_MON",
                $sformatf("@%0t PAYLOAD[%0d] = %08h",
                          $time,
                          i,
                          payload_q[i]),
                UVM_LOW)

      lcrc_pkt_q.push_back(payload_q[i]);

    end

  end

  ////////////////////////////////////////////////////////////
  // ECRC
  ////////////////////////////////////////////////////////////

  if(td_bit) begin

    do begin
      @(negedge RX_DLL_PCS.CLK);
    end
    while(!(RX_DLL_PCS.dl_rx_valid &&
            RX_DLL_PCS.dl_rx_ready));

    ecrc = RX_DLL_PCS.dl_rx_data;

    `uvm_info("RX_DLL_MON",
              $sformatf("@%0t ECRC = %08h",
                        $time,
                        ecrc),
              UVM_LOW)

    lcrc_pkt_q.push_back(ecrc);

  end

  ////////////////////////////////////////////////////////////
  // LCRC
  ////////////////////////////////////////////////////////////

  do begin
    @(negedge RX_DLL_PCS.CLK);
  end
  while(!(RX_DLL_PCS.dl_rx_valid &&
          RX_DLL_PCS.dl_rx_ready));

  lcrc = RX_DLL_PCS.dl_rx_data;

  `uvm_info("RX_DLL_MON",
            $sformatf("@%0t RECEIVED_LCRC = %08h",
                      $time,
                      lcrc),
            UVM_LOW)

  calc_lcrc = calculate_lcrc(lcrc_pkt_q);

  `uvm_info("RX_DLL_MON",
            $sformatf("@%0t CALCULATED_LCRC = %08h",
                      $time,
                      calc_lcrc),
            UVM_LOW)

  ////////////////////////////////////////////////////////////
  // LCRC CHECK
  ////////////////////////////////////////////////////////////

  if(calc_lcrc == lcrc) begin

    `uvm_info("RX_DLL_MON",
              $sformatf("@%0t LCRC MATCHED",
                        $time),
              UVM_LOW)

    for(int i = 0; i < hdr_len; i++)
      r_x.rx_data.push_back(header[i]);

    if(has_data) begin
      for(int i = 0; i < payload_length; i++)
        r_x.rx_data.push_back(payload_q[i]);
    end

    if(td_bit)
      r_x.rx_data.push_back(ecrc);

    `uvm_info("RX_DLL_MON",
              $sformatf("@%0t RX_PACKET_SIZE=%0d",
                        $time,
                        r_x.rx_data.size()),
              UVM_LOW)

    foreach(r_x.rx_data[i]) begin
      `uvm_info("RX_DLL_MON",
                $sformatf("RX_DATA[%0d] = %08h",
                          i,
                          r_x.rx_data[i]),
                UVM_LOW)
    end

  end
  else begin

    `uvm_error("RX_DLL_MON",
               $sformatf("@%0t LCRC MISMATCH : CALCULATED=%08h RECEIVED=%08h",
                         $time,
                         calc_lcrc,
                         lcrc))

    `uvm_info("RX_DLL_MON",
              $sformatf("SEQ=%08h HDR0=%08h HDR_LEN=%0d",
                        seq_no,
                        header[0],
                        hdr_len),
              UVM_LOW)

    nack_ev.trigger();
    return;

  end
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
        `uvm_info("DLLL_MONITOR", $sformatf("RC MODE TL MONITOR"), UVM_LOW)
        fork
          rc_monitor_tx();
          rc_monitor_rx();
        join_none
      end

      EP_MODE: begin
        RX_DLL_PCS.dl_rx_ready = 1'b1;
        RX_TL_DL.tl_tx_ready   = 1'b1;
        fork
          ep_monitor_tx();
          ep_monitor_rx();
        join_none
      end

      default: `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass : PCIe_DLL_Monitor
