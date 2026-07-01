`uvm_analysis_imp_decl(_port_e)
`uvm_analysis_imp_decl(_port_f)
`uvm_analysis_imp_decl(_port_g)
`uvm_analysis_imp_decl(_port_h)

class PCIe_MAC_driver extends uvm_driver #(Sequence_item);
  `uvm_component_utils(PCIe_MAC_driver)

  env_cfg cfg;
  string  tag;

  virtual TX_DLL_PCS_Interface rc_vif;
  virtual pipe_tx_interface    rc_pvif;

  virtual RX_DLL_PCS_Interface ep_vif;
  virtual pipe_rx_interface    ep_pvif;

  uvm_analysis_imp_port_e #(Sequence_item, PCIe_MAC_driver) mac_tx_recv_dll;
  uvm_analysis_imp_port_f #(Sequence_item, PCIe_MAC_driver) mac_tx_recv_rx;

  uvm_analysis_imp_port_g #(Sequence_item, PCIe_MAC_driver) mac_rx_recv_dll;
  uvm_analysis_imp_port_h #(Sequence_item, PCIe_MAC_driver) mac_rx_recv_rx;

  Sequence_item rc_item;
  bit [31:0]  rc_received_tlp[$];
  bit [127:0] rc_received_os[$];
  bit [31:0]  rc_received [$];
  bit [129:0] rc_encoded_OS;
  bit [7:0]   rc_link_num;
  bit [7:0]   rc_lane_num;
  bit [7:0]   rc_idle;
  bit [31:0]  rc_dllp_queue[$];
  bit [31:0]  rc_dllp_packet[$];
  int         rc_size_dllp;
  bit [7:0]   rc_negotiated_link_num = 8'h00;
  bit [7:0]   rc_negotiated_lane_num = 8'h00;
  bit [129:0] rc_trans_data[$];
  bit [63:0]  rc_sdp_packet;
  int         rc_size;

  Sequence_item ep_item;
  bit [127:0] ep_os[$];
  bit [31:0]  ep_received_tlp[$];
  bit [31:0]  ep_received [$];
  int         ep_size;
  int         ep_size_tlp;
  bit [129:0] ep_encoded_OS;
  bit [31:0]  ep_dllp_packet [$];
  bit [31:0]  ep_dllp_queue[$];
  bit [129:0] ep_trans_data[$];
  bit [63:0]  ep_sdp_packet;
  int         ep_size_dllp;
  bit [7:0]   ep_link_num = 8'h00;
  bit [7:0]   ep_lane_num = 8'h00;

  bit [22:0] polynomial = 23'h1DBFBC;
  bit [15:0] SDP = 16'hF0AC;
  bit [31:0] EDS = 32'h1f809000;

  bit [127:0] rc_TS1 = {8'h1E,8'hF7,8'hF7,8'h00,8'h08,8'h00,8'h00,8'h00,8'h00,8'h00,8'h1E,8'h1E,8'h1E,8'h1E,8'h4A,8'h4A};
  bit [127:0] ep_TS1 = {8'h1E,8'hF7,8'h01,8'h00,8'h08,8'h00,8'h00,8'h00,8'h00,8'h00,8'h1E,8'h1E,8'h1E,8'h1E,8'h4A,8'h4A};
  bit [127:0] TS2   = {8'h2D,8'hF7,8'hF7,8'h00,8'h08,8'h00,8'h00,8'h2D,8'h2D,8'h2D,8'h2D,8'h2D,8'h2D,8'h2D,8'h45,8'h45};
  bit [127:0] SDS   = {8'hE1,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55,8'h55};
  bit [127:0] EIEOS = {8'h00,8'hFF,8'h00,8'hFF,8'h00,8'hFF,8'h00,8'hFF,8'h00,8'hFF,8'h00,8'hFF,8'h00,8'hFF,8'h00,8'hFF};

  bit [31:0] STP;
  bit [12:0] sequence_number;
  bit [10:0] length;
  bit [2:0]  fmt;
  bit        td;
  bit        f_p;
  bit [3:0]  fcrc;

  uvm_event pma_rx_done;
  uvm_event link_up_env;
  uvm_event link_up_env_rx;

  uvm_barrier polling_active;
  uvm_barrier polling_compilance;
  uvm_barrier polling_configuration;
  uvm_barrier config_link_start;
  uvm_barrier config_link_accept;
  uvm_barrier config_lane_wait;
  uvm_barrier config_lane_accept;
  uvm_barrier config_complete;
  uvm_barrier config_idle;
  uvm_barrier lo;

  typedef enum {
    DETECT_QUIET, DETECT_ACTIVE, POLLING_ACTIVE, POLLING_COMPLIANCE,
    POLLING_CONFIGURATION, CONFIG_LINKNUM_START, CONFIG_LINKNUM_ACCEPT,
    CONFIG_LANNUM_WAIT, CONFIG_LANENUM_ACCEPT, CONFIG_COMPLETE,
    CONFIG_IDLE, L0
  } rc_ltssm_state_e;
  rc_ltssm_state_e rc_state;

  typedef enum {
    EP_DETECT_QUIET, EP_DETECT_ACTIVE, EP_POLLING_ACTIVE, EP_POLLING_COMPLIANCE,
    EP_POLLING_CONFIGURATION, EP_CONFIG_LINKNUM_START, EP_CONFIG_LINKNUM_ACCEPT,
    EP_CONFIG_LANNUM_WAIT, EP_CONFIG_LANENUM_ACCEPT, EP_CONFIG_COMPLETE,
    EP_CONFIG_IDLE, EP_L0
  } ep_ltssm_state_e;
  ep_ltssm_state_e ep_state;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_MAC_driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_MAC_driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    pma_rx_done    = uvm_event_pool::get_global("pma_rx_done");
    link_up_env    = uvm_event_pool::get_global("link_up_env");
    link_up_env_rx = uvm_event_pool::get_global("link_up_env_rx");

    polling_active         = uvm_barrier_pool::get_global("p_a");
    polling_compilance     = uvm_barrier_pool::get_global("p_com");
    polling_configuration  = uvm_barrier_pool::get_global("p_c");
    config_link_start      = uvm_barrier_pool::get_global("c_link");
    config_link_accept     = uvm_barrier_pool::get_global("c_la");
    config_lane_wait       = uvm_barrier_pool::get_global("c_lanew");
    config_lane_accept     = uvm_barrier_pool::get_global("c_lanea");
    config_complete        = uvm_barrier_pool::get_global("c_c");
    config_idle            = uvm_barrier_pool::get_global("c_i");
    lo                     = uvm_barrier_pool::get_global("lo");

    mac_tx_recv_dll = new("mac_tx_recv_dll", this);
    mac_tx_recv_rx  = new("mac_tx_recv_rx",  this);
    mac_rx_recv_dll = new("mac_rx_recv_dll", this);
    mac_rx_recv_rx  = new("mac_rx_recv_rx",  this);

    rc_item = Sequence_item::type_id::create("rc_item", this);
    ep_item = Sequence_item::type_id::create("ep_item", this);

    case(cfg.mode)

      RC_MODE: begin
        // RC's original thresholds (all 2)
        polling_active.set_threshold(2);
        polling_compilance.set_threshold(2);
        polling_configuration.set_threshold(2);
        config_link_start.set_threshold(2);
        config_link_accept.set_threshold(2);
        config_lane_wait.set_threshold(2);
        config_lane_accept.set_threshold(2);
        config_complete.set_threshold(2);
        config_idle.set_threshold(2);
        lo.set_threshold(2);

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", rc_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] TX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))
        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", rc_pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("PCIe_MAC_driver", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        // EP's original thresholds (1 for polling_active/polling_compilance, 2 elsewhere)
        polling_active.set_threshold(1);
        polling_compilance.set_threshold(1);
        polling_configuration.set_threshold(2);
        config_link_start.set_threshold(2);
        config_link_accept.set_threshold(2);
        config_lane_wait.set_threshold(2);
        config_lane_accept.set_threshold(2);
        config_complete.set_threshold(2);
        config_idle.set_threshold(2);

        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", ep_pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))
        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", ep_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] RX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))

        `uvm_info("PCIe_MAC_driver", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_MAC_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

    function void write_port_e(Sequence_item t);
    `uvm_info("MAC_TX_DRV", $sformatf("[%s] Write_STARTED", tag), UVM_LOW)
    foreach(t.dllp_tx_packet[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] DLLP_INITIAL_TX %h %d DWORDs", tag, t.dllp_tx_packet[i], t.dllp_tx_packet.size()), UVM_LOW)
    foreach(t.mac_tx_data[i]) begin
      foreach(t.mac_tx_data[i][j]) begin
        rc_received.push_back(t.mac_tx_data[i][j]);
      end
    end
    rc_dllp_packet = t.dllp_tx_packet;
    foreach(rc_dllp_packet[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] DLLP_INITIAL_TX %h %d DWORDs", tag, rc_dllp_packet[i], rc_dllp_packet.size()), UVM_LOW)
    t.dllp_tx_packet.delete();
  endfunction

  function void write_port_f(Sequence_item t);
    rc_received_os = t.os_t;
    rc_received_tlp = t.tlp_queue;
    foreach(t.dlp_queue[i])
      rc_dllp_queue.push_back(t.dlp_queue[i]);
    `uvm_info("MAC_TX_DRV", $sformatf("[%s] Received %0d DWORDs", tag, rc_received_tlp.size()), UVM_LOW)
    foreach(rc_dllp_queue[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] DLLP_Received %0h DWORDs", tag, rc_dllp_queue[i]), UVM_LOW)
    t.dlp_queue.delete();
  endfunction

   function void write_port_g(Sequence_item t);
    `uvm_info("MAC_RX_DRV", $sformatf("[%s] Write_STARTED", tag), UVM_LOW)
    foreach(t.mac_rx_data[i]) begin
      foreach(t.mac_rx_data[i][j]) begin
        ep_received.push_back(t.mac_rx_data[i][j]);
      end
    end
    ep_dllp_packet = t.dllp_packet;
    foreach(ep_dllp_packet[i])
      `uvm_info("MAC_RX_DRV", $sformatf("[%s] DLLP_INITIAL %h %d DWORDs", tag, ep_dllp_packet[i], ep_dllp_packet.size()), UVM_LOW)
  endfunction

  function void write_port_h(Sequence_item t);
    ep_os = t.os_t;
    ep_received_tlp = t.tlp_queue_t;
    ep_dllp_queue = t.dlp_rx_queue;
    foreach(ep_received_tlp[i])
      `uvm_info("MAC_RX_DRV", $sformatf("[%s] Received from PMA DRIVER %0h %d DWORDs", tag, ep_received_tlp[i], ep_received_tlp.size()), UVM_LOW)
  endfunction

    function bit parity_calc(input length ,input sequence_number,output f_p );
    bit [22:0] parity_check = {length,sequence_number};
    if(^parity_check) f_p = 1'b1;
    else f_p = 1'b0;
  endfunction

  function bit [7:0] d_s(inout bit [7:0] data);
    static bit [22:0] lfsr = 23'h7FFFFF;
    for (int i = 0; i < 8; i++) begin
      if (lfsr[22]) lfsr = (lfsr << 1) ^ polynomial;
      else          lfsr = (lfsr << 1);
      data[i] = lfsr[22] ^ data[i];
    end
    return data;
  endfunction

  function void os_scramble(inout bit [127:0] os);
    for (int i = 8; i < 113; i = i+8)
      os[i+:8] = d_s(os[i+:8]);
  endfunction

   function void rc_packet_encoding();
    bit [129:0] data;
    if(rc_received.size()%4 == 1) begin
      rc_received.push_back(32'h0);
      rc_received.push_back(32'h0);
      rc_received.push_back(32'h0);
    end
    else if(rc_received.size()%4 == 2) begin
      rc_received.push_back(32'h0);
      rc_received.push_back(32'h0);
    end
    else if(rc_received.size()%4 == 3) begin
      rc_received.push_back(32'h0);
    end
    `uvm_info("PIPE_DRV",$sformatf("PACKET ENCODING: %0p size = %d",rc_received,rc_received.size()),UVM_LOW)
    for(int i=0;i<rc_received.size();i=i+4) begin
      data  = {2'b10,rc_received[i],rc_received[i+1],rc_received[i+2],rc_received[i+3]};
      rc_trans_data.push_back(data);
    end
    `uvm_info("PIPE_DRV",$sformatf("data: %0p",rc_trans_data),UVM_LOW)
  endfunction

  function void rc_add_stp_to_all_packets(inout bit [31:0] pkt_q[$]);
    bit [31:0] stp_pkt;
    int i;
    int pkt_len;
    bit [31:0] data;
    for(i = 0; i < pkt_q.size(); ) begin
      fmt    = pkt_q[i+1][31:29];
      td     = pkt_q[i+1][15];
      if(fmt == 3'b010 || fmt == 3'b011) begin
        length = pkt_q[i+1][9:0] + 2;
      end
      else begin
        length = 2;
      end
      if(fmt == 3'b000 || fmt == 3'b010)
        length = length + 3;   // 3DW Header
      else
        length = length + 4;   // 4DW Header
      if(td)
        length = length + 1;

      sequence_number = pkt_q[i][12:0];
      f_p = parity_calc(length, sequence_number, f_p);
      pkt_len = length+1;
      stp_pkt = {
                  pkt_len[3:0],
                  4'hF,
                  f_p,
                  pkt_len[10:4],
                  fcrc[3:0],
                  sequence_number[3:0],
                  sequence_number[11:4]
                };
      `uvm_info("PIPE_DRV",$sformatf("stp: %0h f_p %d length = %h sequen = %h",stp_pkt,f_p,pkt_len,sequence_number),UVM_LOW)

      pkt_q.insert(i, stp_pkt);

      for(int j = i+1;j<(i+pkt_len);j++) begin
        data = pkt_q[j];
        pkt_q[j] = {d_s(data[31:24]),d_s(data[23:16]),d_s(data[15:8]),d_s(data[7:0])};
      end
      i = i + pkt_len ;
    end
  endfunction

  function void rc_data_scrambling(bit TL_DL);
    bit [31:0] data;
    if(TL_DL) begin
      for(int i= 0;i<rc_received.size();i++) begin
        data = rc_received[i];
        rc_received[i] = {d_s(data[31:24]),d_s(data[23:16]),d_s(data[15:8]),d_s(data[7:0])};
      end
    end
    else begin
      rc_dllp_packet[0] = {d_s(rc_dllp_packet[0][31:24]),d_s(rc_dllp_packet[0][23:16]),d_s(rc_dllp_packet[0][15:8]),d_s(rc_dllp_packet[0][7:0])};
      rc_dllp_packet[1] = {d_s(rc_dllp_packet[1][31:24]),d_s(rc_dllp_packet[1][23:16]),8'h0,8'h0};
    end
  endfunction

  task rc_drive_os(bit [127:0] os_val, bit [1:0] sync_hdr = 2'b01);
    bit [127:0] tmp = os_val;
    os_scramble(tmp);
    rc_encoded_OS    = {sync_hdr, tmp};
    rc_pvif.TxData      <= rc_encoded_OS;
    rc_pvif.TxDataValid <= 1;
  endtask


   function void ep_packet_encoding();
    bit [129:0] data;
    if(ep_received.size()%4 == 1) begin
      ep_received.push_back(32'h0);
      ep_received.push_back(32'h0);
      ep_received.push_back(32'h0);
    end
    else if(ep_received.size()%4 == 2) begin
      ep_received.push_back(32'h0);
      ep_received.push_back(32'h0);
    end
    else if(ep_received.size()%4 == 3) begin
      ep_received.push_back(32'h0);
    end
    `uvm_info("PIPE_DRV",$sformatf("PACKET ENCODING: %0p size = %d",ep_received,ep_received.size()),UVM_LOW)
    for(int i=0;i<ep_received.size();i=i+4) begin
      data  = {2'b10,ep_received[i],ep_received[i+1],ep_received[i+2],ep_received[i+3]};
      ep_trans_data.push_back(data);
    end
    `uvm_info("PIPE_DRV",$sformatf("data: %0p",ep_trans_data),UVM_LOW)
  endfunction
/*
  function void ep_add_stp_to_all_packets(inout bit [31:0] pkt_q[$]);
    bit [31:0] stp_pkt;
    int i;
    int pkt_len;
    bit [31:0] data;
    for(i = 0; i < pkt_q.size(); ) begin
      fmt    = pkt_q[i+1][31:29];
      td     = pkt_q[i+1][15];
      if(fmt == 3'b010 || fmt == 3'b011) begin
        length = pkt_q[i+1][9:0] + 2;
      end
      else begin
        length = 2;
      end
      if(fmt == 3'b000 || fmt == 3'b010)
        length = length + 3;   // 3DW Header
      else
        length = length + 4;   // 4DW Header
      if(td)
        length = length + 1;

      sequence_number = pkt_q[i][12:0];
      f_p = parity_calc(length, sequence_number, f_p);
      pkt_len = length+1;
      stp_pkt = {
                  pkt_len[3:0],
                  4'hF,
                  f_p,
                  pkt_len[10:4],
                  fcrc[3:0],
                  sequence_number[3:0],
                  sequence_number[11:4]
                };
      `uvm_info("PIPE_DRV",$sformatf("stp: %0h f_p %d length = %h sequen = %h",stp_pkt,f_p,pkt_len,sequence_number),UVM_LOW)

      pkt_q.insert(i, stp_pkt);

      for(int j = i+1;j<(i+pkt_len);j++) begin
        data = pkt_q[j];
        pkt_q[j] = {d_s(data[31:24]),d_s(data[23:16]),d_s(data[15:8]),d_s(data[7:0])};
      end
      i = i + pkt_len ;
    end
  endfunction
*/
  function void ep_data_scrambling(bit TL_DL);
    bit [31:0] data;
    if(TL_DL) begin
      for(int i= 0;i<ep_received.size();i++) begin
        data = ep_received[i];
        ep_received[i] = {d_s(data[31:24]),d_s(data[23:16]),d_s(data[15:8]),d_s(data[7:0])};
      end
    end
    else begin
      ep_dllp_packet[0] = {d_s(ep_dllp_packet[0][31:24]),d_s(ep_dllp_packet[0][23:16]),d_s(ep_dllp_packet[0][15:8]),d_s(ep_dllp_packet[0][7:0])};
      ep_dllp_packet[1] = {d_s(ep_dllp_packet[1][31:24]),d_s(ep_dllp_packet[1][23:16]),8'h0,8'h0};
    end
  endfunction

  task ep_drive_os(bit [127:0] os_val, bit [1:0] sync_hdr = 2'b01);
    bit [127:0] tmp = os_val;
    os_scramble(tmp);
    ep_encoded_OS    = {sync_hdr, tmp};
    ep_pvif.TxData      <= ep_encoded_OS;
    ep_pvif.TxDataValid <= 1;
  endtask
  // ---- RC_MODE ----
  task rc_state_detect_active();
      `uvm_info("TX_LTSSM","DETECT_ACTIVE – waiting pma_rx_done",UVM_LOW)
      pma_rx_done.wait_trigger();
      //`uvm_info("TX_LTSSM","Receiver detected → POLLING_ACTIVE",UVM_LOW)
      while(rc_pvif.TxDetectRx !=1)begin
         @(posedge rc_pvif.PCLK);
      end
       `uvm_info("LTSSM","PMA asserted TxDetectRx -> checking RxStatus",UVM_LOW)
      wait(rc_pvif.PhyStatus === 1'b1 && rc_pvif.RxStatus === 3'b011);
      rc_pvif.TxDetectRx <= 0;
      rc_pvif.TxElecIdle <= 0;
      rc_state = POLLING_ACTIVE;
    endtask

  // ---- EP_MODE ----
  task ep_state_detect_active();
      `uvm_info("RX_LTSSM","DETECT_ACTIVE – waiting pma_rx_done",UVM_LOW)
      pma_rx_done.wait_trigger();
      `uvm_info("RX_LTSSM","Receiver detected → POLLING_ACTIVE",UVM_LOW)
      ep_pvif.TxDetectRx <= 0;
      ep_pvif.TxElecIdle <= 0;
      ep_state = EP_POLLING_ACTIVE;
    endtask

  // ---- RC_MODE ----
  task rc_state_polling_active();
      `uvm_info("TX_LTSSM","POLLING_ACTIVE – sending 10 TS1s",UVM_LOW)
     
      rc_item.size_tx_rx = 10;
      repeat(10) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(rc_TS1);
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
   
      `uvm_info("TX_LTSSM","rc_TS1 done – barrier with RX",UVM_LOW)
       
      //tx_ts1_done.trigger();
       //rx_ts1_done.wait_trigger();
      wait(rc_received_os.size() > 0);
       polling_active.wait_for();
  if (rc_received_os.size() == 8) begin
      `uvm_info("TX_LTSSM",$sformatf("POLLING_ACTIVE rc_received %p rc_size %d",rc_received_os, rc_received_os.size()),UVM_LOW)
   
    `uvm_info("TX_LTSSM","Barrier passed → 8 consecutive rc_received -> POLLING_CONFIGURATION",UVM_LOW)
      rc_received_os.delete();
      rc_state = POLLING_CONFIGURATION;
  end
  else begin
  //     polling_active.wait_for();
      `uvm_info("TX_LTSSM","Barrier passed → POLLING_COMPLIANCE",UVM_LOW)
      rc_received_os.delete();
      rc_state = POLLING_COMPLIANCE;
  end
    endtask

  // ---- EP_MODE ----
  task ep_state_polling_active();
      `uvm_info("RX_LTSSM","POLLING_ACTIVE – sending TS1s",UVM_LOW)
     
       ep_item.size_rx_tx = 8;
      repeat(8) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(ep_TS1);
      end
      @(posedge ep_pvif.PCLK);
      ep_pvif.TxDataValid <= 0;
     
     //tx_ts1_done.wait_trigger();
     //rx_ts1_done.trigger();
  
  //        wait(ep_os.size()>0);
  //     `uvm_info("RX_LTSSM","ep_TS1 barrier passed → POLLING_COMPLIANCE",UVM_LOW)
  //     polling_active.wait_for();
  //     ep_os.delete();
  //     ep_state = EP_POLLING_COMPLIANCE;
      wait(ep_os.size() > 0);
      polling_active.wait_for();
      if (ep_os.size() >= 8) begin
          `uvm_info("RX_LTSSM",$sformatf("ep_TS1 ep_received %p ep_size %0d",ep_os, ep_os.size()),UVM_LOW)
  
          `uvm_info("RX_LTSSM","Barrier passed → 8 consecutive ep_TS1 ep_received -> POLLING_CONFIGURATION",UVM_LOW)
          ep_os.delete();
          ep_state = EP_POLLING_CONFIGURATION;
      end
      else begin
        `uvm_info("RX_LTSSM",$sformatf("ep_TS1 mismatch ep_size=%0d → POLLING_COMPLIANCE",ep_os.size()),UVM_LOW)
          ep_os.delete();
          ep_state = EP_POLLING_COMPLIANCE;
      end
    endtask

  // ---- RC_MODE ----
  task rc_state_polling_compliance();
      `uvm_info("TX_LTSSM","POLLING_COMPLIANCE",UVM_LOW)
      // Drive a brief compliance burst (replace with your actual pattern)
       rc_item.size_tx_rx = 4;
      repeat(4) begin
        @(posedge rc_pvif.PCLK);
        rc_pvif.TxData      <= 130'h11ee965ecf269e1FFF3ecb241111b600a;   // placeholder
        rc_pvif.TxDataValid <= 1;
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
   
     // compliance_exit.trigger();
       // wait(rc_received.size()>0);
      `uvm_info("TX_LTSSM",$sformatf("Compliance %p",rc_received),UVM_LOW)
          polling_compilance.wait_for();
      `uvm_info("TX_LTSSM","Compliance exit → POLLING_CONFIGURATION",UVM_LOW)
      rc_received_os.delete();
      rc_state = POLLING_CONFIGURATION;
    endtask

  // ---- EP_MODE ----
  task ep_state_polling_compliance();
      `uvm_info("RX_LTSSM","POLLING_COMPLIANCE – waiting compliance_exit",UVM_LOW)
     // compliance_exit.wait_trigger();
        wait(ep_os.size()>0);
      polling_compilance.wait_for();
       `uvm_info("RX_LTSSM",$sformatf("Compliance ep_os %p ep_size = %d",ep_os,ep_os.size()),UVM_LOW)
      ep_os.delete();
      `uvm_info("RX_LTSSM","Compliance exit ep_received → POLLING_CONFIGURATION",UVM_LOW)
      ep_state = EP_POLLING_CONFIGURATION;
    endtask

  // ---- RC_MODE ----
  task rc_state_polling_configuration();
      `uvm_info("TX_LTSSM","POLLING_CONFIGURATION : rc_TS1 exchange complete - switching TX to TS2",UVM_LOW)
      `uvm_info("TX_LTSSM","POLLING_CONFIG – sending TS2s",UVM_LOW)
      rc_item.size_tx_rx = 16;
      repeat(16) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(TS2);
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
       `uvm_info("TX_LTSSM","POLLING_CONFIGURATION : TX TS2 sent - waiting RX TS2",UVM_LOW)
  
  //     tx_ts2_done.trigger();
  //     rx_ts2_done.wait_trigger();
         wait(rc_received_os.size()>0);
         polling_configuration.wait_for();
         `uvm_info("TX_LTSSM",$sformatf("POLLING %p",rc_received),UVM_LOW)
          rc_received_os.delete();
         `uvm_info("TX_LTSSM","TS2 barrier passed → CONFIG_LINKNUM_START",UVM_LOW)
          rc_state = CONFIG_LINKNUM_START;
  endtask

  // ---- EP_MODE ----
  task ep_state_polling_configuration();
      
      `uvm_info("RX_LTSSM","POLLING_CONFIGURATION : ep_TS1 exchange complete - switching TX to TS2",UVM_LOW)
      `uvm_info("RX_LTSSM","POLLING_CONFIG – sending TS2s",UVM_LOW)
      ep_item.size_rx_tx = 8;
      repeat(8) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(TS2);
      end
      @(posedge ep_pvif.PCLK);
      ep_pvif.TxDataValid <= 0;
      `uvm_info("RX_LTSSM","POLLING_CONFIGURATION : TX TS2 sent - waiting RX TS2",UVM_LOW)
  
  //     rx_ts2_done.trigger();
  //     tx_ts2_done.wait_trigger();
  //      wait(ep_os.size()>0);
  //     `uvm_info("RX_LTSSM",$sformatf("POLLING ep_os %p ep_size = %d",ep_os,ep_os.size()),UVM_LOW)
  //    polling_configuration.wait_for();
  //     ep_os.delete();
  //     `uvm_info("RX_LTSSM","TS2 barrier passed → CONFIG_LINKNUM_START",UVM_LOW)
  //     ep_state = EP_CONFIG_LINKNUM_START;
       wait(ep_os.size() > 0);   
       polling_configuration.wait_for();
      if (ep_os.size() == 16) begin
        `uvm_info("RX_LTSSM",$sformatf("TS2 exchange complete:%p ep_size=%0d → LINK_NUM_START",ep_os, ep_os.size()),UVM_LOW)
  
          ep_os.delete();
          ep_state = EP_CONFIG_LINKNUM_START;
      end
      else begin
         // polling_configuration.wait_for();
          `uvm_info("RX_LTSSM",$sformatf("TS2 mismatch → ep_size=%0d → Detect quiet",ep_os.size()),UVM_LOW)
          ep_os.delete();
          ep_state = EP_DETECT_QUIET;
  
      end
    endtask

  // ---- RC_MODE ----
  task rc_state_config_linknum_start();
  
  rc_link_num = rc_TS1[111:104];
  rc_lane_num = rc_TS1[119:112];
      `uvm_info("TX_LTSSM","CONFIG_LINKNUM_START – broadcasting link num",UVM_LOW)
  //     rc_negotiated_link_num = 8'h00;   // x1, single link
   
      // Drive rc_TS1 with link number encoded (field placement is design-specific)
       rc_item.size_tx_rx = 4;
      repeat(4) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(rc_TS1);   // in real impl embed rc_link_num into the OS bytes
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
       // wait(rc_received.size()>0);
      //link_num_valid.trigger();
      config_link_start.wait_for();
      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LINKNUM_START → negotiating | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num,rc_lane_num),UVM_LOW)
      `uvm_info("TX_LTSSM","Link num broadcast done → CONFIG_LINKNUM_ACCEPT",UVM_LOW)
       rc_received_os.delete();
      rc_state = CONFIG_LINKNUM_ACCEPT;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_linknum_start();
      ep_link_num = ep_TS1[111:104];
      ep_lane_num = ep_TS1[119:112];
      `uvm_info("RX_LTSSM","CONFIG_LINKNUM_START – waiting link_num_valid",UVM_LOW)
      //link_num_valid.wait_trigger();
  //     ep_negotiated_link_num = 8'h00;   // mirror what TX advertised
      `uvm_info("RX_LTSSM","Link number ep_received → CONFIG_LINKNUM_ACCEPT",UVM_LOW)
        wait(ep_os.size()>0);
        config_link_start.wait_for();
      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LINKNUM_START → negotiating| ep_link_num=%0h, ep_lane_num=%0h",ep_link_num, ep_lane_num),UVM_LOW)
      `uvm_info("RX_LTSSM","Link num broadcast done → CONFIG_LINKNUM_ACCEPT",UVM_LOW)
      ep_os.delete();
      ep_state = EP_CONFIG_LINKNUM_ACCEPT;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_linknum_accept();
      `uvm_info("TX_LTSSM","CONFIG_LINKNUM_ACCEPT – confirming",UVM_LOW)
       rc_item.size_tx_rx = 2;
      
      repeat(2) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(rc_TS1);
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
   
  //     tx_linknum_accept.trigger();
  //     rx_linknum_accept.wait_trigger();
      wait(rc_received_os.size()>0);
      config_link_accept.wait_for();
      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LINKNUM_ACCEPT → confirmed  | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num, rc_lane_num),UVM_LOW)
  
      rc_received_os.delete();
      `uvm_info("TX_LTSSM","Link-num & Lane_num accepted → CONFIG_LANENUM_WAIT",UVM_LOW)
      rc_state = CONFIG_LANNUM_WAIT;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_linknum_accept();
      `uvm_info("RX_LTSSM","CONFIG_LINKNUM_ACCEPT – confirming",UVM_LOW)
       ep_item.size_rx_tx = 2;
      repeat(2) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(ep_TS1);
      end
      @(posedge ep_pvif.PCLK);
      ep_pvif.TxDataValid <= 0;
  
    //  rx_linknum_accept.trigger();
    //  tx_linknum_accept.wait_trigger();
        wait(ep_os.size()>0);
      config_link_accept.wait_for();
      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LINKNUM_ACCEPT → confirmed| ep_link_num=%0h, ep_lane_num=%0h",ep_link_num, ep_lane_num),UVM_LOW)
      ep_os.delete();
      `uvm_info("RX_LTSSM","Link-num accepted → CONFIG_LANENUM_WAIT",UVM_LOW)
      ep_state = EP_CONFIG_LANNUM_WAIT;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_lanenum_wait();
      rc_link_num = rc_TS1[111:104];
      rc_lane_num = rc_TS1[111:104];
      `uvm_info("TX_LTSSM","CONFIG_LANENUM_WAIT – broadcasting lane nums",UVM_LOW)
     // lane_num_valid.wait_trigger();
      wait(rc_received_os.size()>0);
      config_lane_wait.wait_for();
          `uvm_info("TX_LTSSM",$sformatf("CONFIG_LANENUM_WAIT → negotiating | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num,rc_lane_num),UVM_LOW)
      rc_received_os.delete();
      `uvm_info("TX_LTSSM","Lane numbers rc_received → CONFIG_LANENUM_ACCEPT",UVM_LOW)
      rc_state = CONFIG_LANENUM_ACCEPT;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_lanenum_wait();
      ep_link_num = ep_TS1[111:104];
      ep_lane_num = ep_TS1[111:104];
      `uvm_info("RX_LTSSM","CONFIG_LANENUM_WAIT – broadcasting lane nums",UVM_LOW)
  //     ep_negotiated_lane_num = 8'h00;   // lane 0
       ep_item.size_rx_tx = 4;
      repeat(4) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(TS2);   // embed ep_lane_num in TS2 bytes in real impl
      end
      @(posedge ep_pvif.PCLK);
      ep_pvif.TxDataValid <= 0;
  
      //lane_num_valid.trigger();
          //wait(ep_os.size()>0);
         config_lane_wait.wait_for();
      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LANENUM_WAIT → negotiating| ep_link_num=%0h, ep_lane_num=%0h",ep_link_num, ep_lane_num),UVM_LOW)
      ep_os.delete();
      `uvm_info("RX_LTSSM","Lane broadcast done → CONFIG_LANENUM_ACCEPT",UVM_LOW)
      ep_state = EP_CONFIG_LANENUM_ACCEPT;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_lanenum_accept();
      `uvm_info("TX_LTSSM","CONFIG_LANENUM_ACCEPT – confirming lanes",UVM_LOW)
       rc_item.size_tx_rx = 2;
      repeat(2) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(TS2);
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
   
  //     tx_lanenum_accept.trigger();
  //     rx_lanenum_accept.wait_trigger();
      wait(rc_received_os.size()>0);
       config_lane_accept.wait_for();
      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LANENUM_ACCEPT → confirmed | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num,rc_lane_num),UVM_LOW)
  
      rc_received_os.delete();
      `uvm_info("TX_LTSSM","Lane-num accepted → CONFIG_COMPLETE",UVM_LOW)
      rc_state = CONFIG_COMPLETE;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_lanenum_accept();
      `uvm_info("RX_LTSSM","CONFIG_LANENUM_ACCEPT – confirming lanes",UVM_LOW)
       ep_item.size_rx_tx = 2;
      repeat(2) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(TS2);
      end
      @(posedge ep_pvif.PCLK);
      ep_pvif.TxDataValid <= 0;
  
  //     rx_lanenum_accept.trigger();
  //     tx_lanenum_accept.wait_trigger();
        wait(ep_os.size()>0);
      config_lane_accept.wait_for();
      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LANENUM_ACCEPT → confirmed | ep_link_num=%0h, ep_lane_num=%0h",ep_link_num,ep_lane_num),UVM_LOW)
  
        ep_os.delete();
      `uvm_info("RX_LTSSM","Lane-num accepted → CONFIG_COMPLETE",UVM_LOW)
      ep_state = EP_CONFIG_COMPLETE;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_complete();
    `uvm_info("TX_LTSSM","CONFIG_COMPLETE",UVM_LOW)
    rc_item.size_tx_rx = 16;
    repeat (16) begin
      @(posedge rc_pvif.PCLK);
      rc_drive_os(rc_TS1);
    end
    @(posedge rc_pvif.PCLK);
    rc_pvif.TxDataValid <= 0;
    wait(rc_received_os.size() > 0);
    config_complete.wait_for();
    `uvm_info("TX_LTSSM",$sformatf("Received %0d ordered sets",rc_received_os.size()),UVM_LOW)
        if (rc_received_os.size() == 8) begin
      `uvm_info("TX_LTSSM","Received 8 TS1s -> CONFIG_IDLE",UVM_LOW)
      rc_received_os.delete();
      rc_state = CONFIG_IDLE;
    end
    else begin
      `uvm_error("TX_LTSSM",$sformatf("Only %0d TS1s rc_received. Returning to DETECT",rc_received_os.size()))
      rc_received_os.delete();
      rc_state = DETECT_QUIET;
    end
  endtask

  // ---- EP_MODE ----
  task ep_state_config_complete();
    `uvm_info("RX_LTSSM","CONFIG_COMPLETE",UVM_LOW)
    ep_item.size_rx_tx = 8;
    repeat (8) begin
      @(posedge ep_pvif.PCLK);
      ep_drive_os(ep_TS1);
    end
    @(posedge ep_pvif.PCLK);
    ep_pvif.TxDataValid <= 0;
    wait(ep_os.size() > 0);
    config_complete.wait_for();
    `uvm_info("RX_LTSSM",$sformatf("Received %0d ordered sets", ep_os.size()),UVM_LOW)
      if (ep_os.size() == 16) begin
      `uvm_info("RX_LTSSM","Received 16 TS1s -> CONFIG_IDLE",UVM_LOW)
      ep_os.delete();
      ep_state = EP_CONFIG_IDLE;
    end
    else begin
      `uvm_error("RX_LTSSM",$sformatf("Only %0d TS1s ep_received. Returning to DETECT",ep_os.size()))
      ep_os.delete();
      ep_state = EP_DETECT_QUIET;
    end
  endtask

  // ---- RC_MODE ----
  task rc_state_config_idle();
  //     rc_idle = rc_TS1[103:96];
      `uvm_info("TX_LTSSM","CONFIG_IDLE – sending rc_idle symbols",UVM_LOW)
      // Idle = data 0x00000000 with data sync header 2'b10
       rc_item.size_tx_rx = 1;
      repeat(1) begin
        @(posedge rc_pvif.PCLK);
      rc_pvif.TxData      <= {2'b01, 128'h0};
        rc_pvif.TxDataValid <= 1;
      end
      @(posedge rc_pvif.PCLK);
      rc_pvif.TxDataValid <= 0;
  //     repeat(1) begin
  //       @(posedge rc_pvif.PCLK);
  //       rc_drive_os(rc_TS1);   
  //     end
  //     @(posedge rc_pvif.PCLK);
  //      rc_pvif.TxDataValid <= 0;
  //     tx_idle_done.trigger();
  //     rx_idle_done.wait_trigger();
      wait(rc_received_os.size()>0);
          config_idle.wait_for();
      `uvm_info("TX_LTSSM",$sformatf("Received %0d rc_idle symbol in CONFIG_IDLE",rc_received_os.size()),UVM_LOW)
  //     if (rc_received_os.size() == 1) begin
      `uvm_info("TX_LTSSM","Received 1 IDLE -> L0",UVM_LOW)
      rc_received_os.delete();
      rc_state = L0;
  //   end
  //   else begin
  //     `uvm_error("TX_LTSSM","No IDLE rc_received -> DETECT_QUIET")
  //     rc_received_os.delete();
  //     rc_state = DETECT_QUIET;
  //   end
    endtask

  // ---- EP_MODE ----
  task ep_state_config_idle();
  //       ep_idle = ep_TS1[103:96];
      `uvm_info("RX_LTSSM","CONFIG_IDLE – sending ep_idle symbols",UVM_LOW)
       ep_item.size_rx_tx = 1;
      repeat(1) begin
  //       @(posedge ep_pvif.PCLK);
  //     ep_drive_os(ep_TS1);
        @(posedge ep_pvif.PCLK);
        ep_pvif.TxData      <= {2'h01, 128'h0};
        ep_pvif.TxDataValid <= 1;
      end
      @(posedge ep_pvif.PCLK);
      ep_pvif.TxDataValid <= 0;
  //     rx_idle_done.trigger();
  //     tx_idle_done.wait_trigger();
        wait(ep_os.size()>0);
      config_idle.wait_for();
      `uvm_info("RX_LTSSM",$sformatf("Received %0d ep_idle symbol in CONFIG_IDLE",ep_os.size()),UVM_LOW)
  //     if (ep_os.size() == 1) begin
      `uvm_info("RX_LTSSM","Received 1 IDLE -> L0",UVM_LOW)
      ep_os.delete();
      ep_state = EP_L0;
  //   end
  //   else begin
  //     `uvm_error("RX_LTSSM","No IDLE ep_received -> DETECT_QUIET")
  //     ep_os.delete();
  //     ep_state = EP_DETECT_QUIET;
  //   end
    endtask

  // ---- RC_MODE ----
  task rc_state_l0();
      `uvm_info("TX_LTSSM","L0 – link is up",UVM_LOW)
      //lo.wait_for();
     // link_up.trigger();
      link_up_env.trigger();
         fork
  forever begin
      begin
         wait(rc_received.size() > 0 || rc_dllp_packet.size() >0 );
         `uvm_info("PIPE_DRV", $sformatf("dllp_size=%0d received_size=%0d",rc_dllp_packet.size(), rc_received.size()),UVM_LOW)
  
         if(rc_dllp_packet.size() >0) begin
  	foreach(rc_dllp_packet[i])
           `uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL: %0h",rc_dllp_packet[i]
   ),UVM_LOW)
  
           rc_sdp_packet = {SDP[15:0],rc_dllp_packet[0][31:0],rc_dllp_packet[1][31:16]};
  	`uvm_info("PIPE_DRV",$sformatf("SDP: %0h",rc_sdp_packet),UVM_LOW)
  	rc_dllp_packet.delete(0); 
  	rc_dllp_packet.delete(0);
          rc_dllp_packet.push_front(rc_sdp_packet[31:0]);
          rc_dllp_packet.push_front(rc_sdp_packet[63:32]);
  	rc_size_dllp = rc_dllp_packet.size();
  	foreach(rc_dllp_packet[i])
  	`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL: %0h rc_size %d",rc_dllp_packet[i],rc_size_dllp),UVM_LOW)
         	for(int i=0;i<rc_size_dllp;i=i+4) begin
            @(posedge rc_pvif.PCLK);
            rc_pvif.TxData      <= {2'b10,rc_dllp_packet[i],rc_dllp_packet[i+1],rc_dllp_packet[i+2],rc_dllp_packet[i+3]};
            rc_pvif.TxDataValid <= 1;
          end
           @(posedge rc_pvif.PCLK);
          rc_pvif.TxDataValid <= 0;
  	rc_dllp_packet.delete();
  		`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL_delete: %0p rc_size %d",rc_dllp_packet,rc_dllp_packet.size()),UVM_LOW)
         end 
         else if(rc_received.size() >0) begin
        `uvm_info("PIPE_DRV",$sformatf("DATA STP ADDED and BEFORE_Srcambled: %0d",rc_received.size()),UVM_LOW)
        foreach(rc_received[i])
        `uvm_info("PIPE_DRV",$sformatf("DATA STP ADDED and BEFORE_Srcambled: %0h",rc_received[i]),UVM_LOW)
        rc_add_stp_to_all_packets(rc_received);
        foreach(rc_received[i])
        `uvm_info("PIPE_DRV",$sformatf("DATA STP ADDED and Srcambled: %0h",rc_received[i]),UVM_LOW)
        `uvm_info("PIPE_DRV",$sformatf("DATA STP ADDED and BEFORE_Srcambled: %0d",rc_received.size()),UVM_LOW)
      //rc_data_scrambling(0);
      //rc_sdp_packet = {SDP[15:0],rc_dllp_packet[0][31:0],rc_dllp_packet[1][31:16]}; 
      //rc_received.push_back(rc_sdp_packet[63:32]);
      //rc_received.push_back(rc_sdp_packet[31:0]);
      rc_received.push_back(EDS);
      rc_packet_encoding();
      rc_received.delete();
      //rc_item.size_tx_rx = rc_trans_data.size();
      rc_size = rc_trans_data.size();
      for(int i=0;i<rc_size;i++) begin
         @(posedge rc_pvif.PCLK);
        rc_pvif.TxData      <= rc_trans_data.pop_front();
      //  $display("TX DATA = %0p",rc_trans_data);
          rc_pvif.TxDataValid <= 1;
      end
         @(posedge rc_pvif.PCLK);
          rc_pvif.TxDataValid <= 0;
      end
      end
      end
  forever begin 
         begin
      wait(rc_received_tlp.size()>0 || rc_dllp_queue.size()>0);
      // wait(queue.size() >0);
       if(rc_received_tlp.size() > 0) begin
        rc_size = rc_received_tlp.size();
        for(int i =0;i<rc_size;i++) begin
          @(posedge rc_vif.CLK);
          rc_vif.dl_rx_data = rc_received_tlp.pop_front();
          rc_vif.dl_rx_valid = 1;
          rc_vif.tl_mac_packet <= 1;
        end
         @(posedge rc_vif.CLK);
         rc_vif.dl_rx_valid = 0;
          rc_vif.tl_mac_packet <= 0;
     end
    //end
     if(rc_dllp_queue.size() > 0) begin
      foreach(rc_dllp_queue[i]) 
      `uvm_info("MAC_TX_DRV",$sformatf("DLLP_Received_1 %0h DWORDs ",rc_dllp_queue[i]),UVM_LOW)
        rc_size = rc_dllp_queue.size();
        for(int i =0;i<rc_size;i++) begin
          @(posedge rc_vif.CLK);
          rc_vif.dl_rx_data = rc_dllp_queue.pop_front();
          rc_vif.dl_rx_valid = 1;
  	rc_vif.dl_mac_packet = 1;
        end
         @(posedge rc_vif.CLK);
         rc_vif.dl_rx_valid = 0;
         rc_vif.dl_mac_packet = 0;
     end
    end
    end
      join
  endtask

  // ---- EP_MODE ----
  task ep_state_l0();
        `uvm_info("RX_LTSSM","L0 - link is up",UVM_LOW)
     // link_up.trigger();
           link_up_env_rx.trigger();
      fork
  forever begin 
         begin
      wait(ep_received_tlp.size()>0 || ep_dllp_queue.size()>0);
      `uvm_info("MAC_RX_DRV",$sformatf("TLP_Received_1 %p  %0d DWORDs ",ep_received_tlp,ep_received_tlp.size()),UVM_LOW)
      // wait(queue.size() >0);
       if(ep_received_tlp.size() > 0) begin
        ep_size_tlp = ep_received_tlp.size();
      `uvm_info("MAC_RX_DRV",$sformatf("TLP_Received_1 %0d DWORDs ",ep_size),UVM_LOW)
        for(int i =0;i<ep_size_tlp;i++) begin
          @(posedge ep_vif.CLK);
          ep_vif.dl_rx_data = ep_received_tlp[i];
          ep_vif.dl_rx_valid = 1;
          ep_vif.tl_mac_packet <= 1;
      `uvm_info("MAC_RX_DRV",$sformatf("VALID_TO_ONE i=%d ep_size = %d ep_received_tlp = %d",i,ep_size_tlp,ep_received_tlp.size()),UVM_LOW)
        end
         @(posedge ep_vif.CLK);
      `uvm_info("MAC_RX_DRV",$sformatf("VALID_TO_ZERO ep_received_tlp = %d",ep_received_tlp.size()),UVM_LOW)
         ep_vif.dl_rx_valid = 0;
          ep_vif.tl_mac_packet <= 0;
  	ep_received_tlp.delete();
     end
    //end
     if(ep_dllp_queue.size() > 0) begin
      foreach(ep_dllp_queue[i]) 
      `uvm_info("MAC_RX_DRV",$sformatf("DLLP_Received_1 %0h DWORDs ",ep_dllp_queue[i]),UVM_LOW)
        ep_size = ep_dllp_queue.size();
        for(int i =0;i<ep_size;i++) begin
          @(posedge ep_vif.CLK);
          ep_vif.dl_rx_data = ep_dllp_queue.pop_front();
          ep_vif.dl_rx_valid = 1;
  	ep_vif.dl_mac_packet = 1;
        end
         @(posedge ep_vif.CLK);
         ep_vif.dl_rx_valid = 0;
         ep_vif.dl_mac_packet = 0;
     end
      end
      end
    forever begin
      begin
         wait(ep_received.size() > 0 || ep_dllp_packet.size() >0 );
         if(ep_dllp_packet.size() >0) begin
  	foreach(ep_dllp_packet[i])
           `uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL: %0h",ep_dllp_packet[i]
   ),UVM_LOW)
  
           ep_sdp_packet = {SDP[15:0],ep_dllp_packet[0][31:0],ep_dllp_packet[1][31:16]};
  	`uvm_info("PIPE_DRV",$sformatf("SDP: %0h",ep_sdp_packet),UVM_LOW)
  	ep_dllp_packet.delete(0); 
  	ep_dllp_packet.delete(0);
          ep_dllp_packet.push_front(ep_sdp_packet[31:0]);
          ep_dllp_packet.push_front(ep_sdp_packet[63:32]);
  	ep_size_dllp = ep_dllp_packet.size();
  	foreach(ep_dllp_packet[i])
  	`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL: %0h ep_size %d",ep_dllp_packet[i],ep_size_dllp),UVM_LOW)
         	for(int i=0;i<ep_size_dllp;i=i+4) begin
            @(posedge ep_pvif.PCLK);
            ep_pvif.TxData      <= {2'b10,ep_dllp_packet[i],ep_dllp_packet[i+1],ep_dllp_packet[i+2],ep_dllp_packet[i+3]};
            ep_pvif.TxDataValid <= 1;
          end
           @(posedge ep_pvif.PCLK);
          ep_pvif.TxDataValid <= 0;
  	ep_dllp_packet.delete();
  		`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL_delete: %0p ep_size %d",ep_dllp_packet,ep_dllp_packet.size()),UVM_LOW)
         end 
         if(ep_received.size() >0) begin
        rc_add_stp_to_all_packets(ep_received);
        `uvm_info("PIPE_RX_DRV",$sformatf("DATA STP ADDED and Srcambled: %0p",ep_received),UVM_LOW)
    //    ep_data_scrambling(0);
      //ep_sdp_packet = {SDP[15:0],ep_dllp_packet[0][31:0],ep_dllp_packet[1][31:16]}; 
      //ep_received.push_back(ep_sdp_packet[63:32]);
      //ep_received.push_back(ep_sdp_packet[31:0]);
      ep_received.push_back(EDS);
      ep_packet_encoding();
      ep_received.delete();
      ep_item.size_tx_rx = ep_trans_data.size();
      ep_size = ep_trans_data.size();
      for(int i=0;i<ep_size;i++) begin
         @(posedge ep_pvif.PCLK);
        ep_pvif.TxData      <= ep_trans_data.pop_front();
      //  $display("TX DATA = %0p",ep_trans_data);
          ep_pvif.TxDataValid <= 1;
      end
           @(posedge ep_pvif.PCLK);
          ep_pvif.TxDataValid <= 0;
      end
      end
      end
      join
  endtask

  // ---- RC_MODE ----
  task rc_state_detect_quiet();
    rc_pvif.TxElecIdle  <= 1;
    rc_pvif.TxDataValid <= 0;
    rc_pvif.Rate        <= 2'b00;
    `uvm_info("TX_LTSSM","DETECT_QUIET",UVM_LOW)
    @(posedge rc_pvif.PCLK);
    rc_state = DETECT_ACTIVE;
  endtask

  // ---- EP_MODE ----
  task ep_state_detect_quiet();
    ep_pvif.TxElecIdle  <= 1;
    ep_pvif.TxDataValid <= 0;
    ep_pvif.Rate        <= 2'b00;
    `uvm_info("RX_LTSSM","DETECT_QUIET",UVM_LOW)
    @(posedge ep_pvif.PCLK);
    ep_state = EP_DETECT_ACTIVE;
  endtask

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        rc_state = DETECT_QUIET;
        forever begin
          case(rc_state)
            DETECT_QUIET          : rc_state_detect_quiet();
            DETECT_ACTIVE         : rc_state_detect_active();
            POLLING_ACTIVE        : rc_state_polling_active();
            POLLING_COMPLIANCE    : rc_state_polling_compliance();
            POLLING_CONFIGURATION : rc_state_polling_configuration();
            CONFIG_LINKNUM_START  : rc_state_config_linknum_start();
            CONFIG_LINKNUM_ACCEPT : rc_state_config_linknum_accept();
            CONFIG_LANNUM_WAIT    : rc_state_config_lanenum_wait();
            CONFIG_LANENUM_ACCEPT : rc_state_config_lanenum_accept();
            CONFIG_COMPLETE       : rc_state_config_complete();
            CONFIG_IDLE           : rc_state_config_idle();
            L0                    : rc_state_l0();
          endcase
        end
      end

      EP_MODE: begin
        ep_state = EP_DETECT_QUIET;
        forever begin
          case(ep_state)
            EP_DETECT_QUIET          : ep_state_detect_quiet();
            EP_DETECT_ACTIVE         : ep_state_detect_active();
            EP_POLLING_ACTIVE        : ep_state_polling_active();
            EP_POLLING_COMPLIANCE    : ep_state_polling_compliance();
            EP_POLLING_CONFIGURATION : ep_state_polling_configuration();
            EP_CONFIG_LINKNUM_START  : ep_state_config_linknum_start();
            EP_CONFIG_LINKNUM_ACCEPT : ep_state_config_linknum_accept();
            EP_CONFIG_LANNUM_WAIT    : ep_state_config_lanenum_wait();
            EP_CONFIG_LANENUM_ACCEPT : ep_state_config_lanenum_accept();
            EP_CONFIG_COMPLETE       : ep_state_config_complete();
            EP_CONFIG_IDLE           : ep_state_config_idle();
            EP_L0                    : ep_state_l0();
          endcase
        end
      end

      default: `uvm_fatal("PCIe_MAC_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass
