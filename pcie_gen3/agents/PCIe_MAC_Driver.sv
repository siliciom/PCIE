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
  bit [31:0]  rc_dllp_fifo[$][$];
  bit [31:0]  rc_dllp_packet[$];
  int         rc_size_dllp;
  bit [7:0]   rc_negotiated_link_num = 8'h00;
  bit [7:0]   rc_negotiated_lane_num = 8'h00;
  bit [129:0] rc_trans_data[$];
  bit [63:0]  rc_sdp_packet;
  int         rc_size;
  int         rc_size_tx;
  int         rc_size_rx;
  bit [31:0]  rc_tlp_fifo[$][$];   

  Sequence_item ep_item;
  bit [127:0] ep_os[$];
  bit [31:0]  ep_received_tlp[$];
  bit [31:0]  ep_tlp_fifo[$][$];   // FIFO of buffered TLPs: each entry is one full TLP (queue of DWORDs).
                                   // write_port_h() pushes new arrivals here instead of overwriting
                                   // ep_received_tlp, so a TLP that arrives while the previous one is
                                   // still being driven out is queued up, not lost/corrupted.
  bit [31:0]  ep_received [$];
  int         ep_size;
  int         ep_size_dll;
  int         ep_size_tlp;
  bit [129:0] ep_encoded_OS;
  bit [31:0]  ep_dllp_packet [$];
  bit [31:0]  ep_dllp_queue[$];
  bit [31:0]  ep_dllp_fifo[$][$];
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
    CONFIG_IDLE, L0,
    RECOVERY_RCVRLOCK, RECOVERY_RCVRCFG, RECOVERY_SPEED, RECOVERY_IDLE
  } rc_ltssm_state_e;
  rc_ltssm_state_e rc_state;

  typedef enum {
    EP_DETECT_QUIET, EP_DETECT_ACTIVE, EP_POLLING_ACTIVE, EP_POLLING_COMPLIANCE,
    EP_POLLING_CONFIGURATION, EP_CONFIG_LINKNUM_START, EP_CONFIG_LINKNUM_ACCEPT,
    EP_CONFIG_LANNUM_WAIT, EP_CONFIG_LANENUM_ACCEPT, EP_CONFIG_COMPLETE,
    EP_CONFIG_IDLE, EP_L0,
    EP_RECOVERY_RCVRLOCK, EP_RECOVERY_RCVRCFG, EP_RECOVERY_SPEED, EP_RECOVERY_IDLE
  } ep_ltssm_state_e;
  ep_ltssm_state_e ep_state;

  //-----------------------------------------------------------
  // Recovery entry trigger - a single shared event both RC and EP
  // threads listen for while sitting in L0. In addition to this
  // manual trigger, L0 also auto-enters RECOVERY whenever
  // negotiated_gen > active_gen (see rc_state_l0()/ep_state_l0()).
  //-----------------------------------------------------------
  uvm_event ltssm_recovery_req;

  uvm_barrier recovery_rcvrlock;
  uvm_barrier recovery_rcvrcfg;
  uvm_barrier recovery_speed;
  uvm_barrier recovery_idle_bar;

  //-----------------------------------------------------------
  // Speed-change / RECOVERY bookkeeping.
  //   active_gen      : Gen the link is CURRENTLY trained/running at.
  //                      Always starts at 1 - real PCIe always does
  //                      initial bring-up at 2.5 GT/s regardless of
  //                      capability.
  //   partner_rate_id : Rate Identifier byte decoded out of the
  //                      partner's TS1 ordered sets received during
  //                      POLLING_ACTIVE.
  //   negotiated_gen  : min(own cfg.gen, partner's advertised max Gen).
  //                      If higher than active_gen once L0 is reached,
  //                      the LTSSM steps through RECOVERY - one
  //                      generation at a time (Gen1->Gen2->Gen3) -
  //                      until active_gen catches up.
  //-----------------------------------------------------------
  int unsigned rc_active_gen      = 1;
  bit  [7:0]   rc_partner_rate_id = 8'h00;
  int unsigned rc_negotiated_gen  = 1;

  int unsigned ep_active_gen      = 1;
  bit  [7:0]   ep_partner_rate_id = 8'h00;
  int unsigned ep_negotiated_gen  = 1;

  //-----------------------------------------------------------
  // Detect.Quiet / Detect.Active per-lane bookkeeping.
  //-----------------------------------------------------------
  localparam logic [2:0] RX_DETECTED = 3'b011;

  bit [`PCIE_NUM_LANES-1:0] rc_detect_mask_first;
  bit [`PCIE_NUM_LANES-1:0] rc_detect_mask_second;

  bit [`PCIE_NUM_LANES-1:0] ep_detect_mask_first;
  bit [`PCIE_NUM_LANES-1:0] ep_detect_mask_second;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_MAC_driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_MAC_driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_HIGH)

    pma_rx_done    = uvm_event_pool::get_global("pma_rx_done");
    link_up_env    = uvm_event_pool::get_global("link_up_env");
    link_up_env_rx = uvm_event_pool::get_global("link_up_env_rx");
    ltssm_recovery_req = uvm_event_pool::get_global("ltssm_recovery_req");

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

    recovery_rcvrlock      = uvm_barrier_pool::get_global("rec_lock");
    recovery_rcvrcfg       = uvm_barrier_pool::get_global("rec_cfg");
    recovery_speed         = uvm_barrier_pool::get_global("rec_speed");
    recovery_idle_bar      = uvm_barrier_pool::get_global("rec_idle");

    mac_tx_recv_dll = new("mac_tx_recv_dll", this);
    mac_tx_recv_rx  = new("mac_tx_recv_rx",  this);
    mac_rx_recv_dll = new("mac_rx_recv_dll", this);
    mac_rx_recv_rx  = new("mac_rx_recv_rx",  this);

    rc_item = Sequence_item::type_id::create("rc_item", this);
    ep_item = Sequence_item::type_id::create("ep_item", this);

    case(cfg.mode)

      RC_MODE: begin
        // RC's original thresholds (all 2)
        polling_active.set_threshold(1);
        polling_compilance.set_threshold(2);
        polling_configuration.set_threshold(2);
        config_link_start.set_threshold(2);
        config_link_accept.set_threshold(2);
        config_lane_wait.set_threshold(2);
        config_lane_accept.set_threshold(2);
        config_complete.set_threshold(2);
        config_idle.set_threshold(2);
        lo.set_threshold(2);

        recovery_rcvrlock.set_threshold(2);
        recovery_rcvrcfg.set_threshold(2);
        recovery_speed.set_threshold(2);
        recovery_idle_bar.set_threshold(2);

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", rc_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] TX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))
        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", rc_pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("PCIe_MAC_driver", $sformatf("[%s] RC interfaces connected", tag), UVM_HIGH)
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

        recovery_rcvrlock.set_threshold(2);
        recovery_rcvrcfg.set_threshold(2);
        recovery_speed.set_threshold(2);
        recovery_idle_bar.set_threshold(2);

        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", ep_pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))
        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", ep_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] RX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))

        `uvm_info("PCIe_MAC_driver", $sformatf("[%s] EP interfaces connected", tag), UVM_HIGH)
      end

      default: `uvm_fatal("PCIe_MAC_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

    function void write_port_e(Sequence_item t);
    `uvm_info("MAC_TX_DRV", $sformatf("[%s] Write_STARTED", tag), UVM_HIGH)
    foreach(t.dllp_tx_packet[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] DLLP_INITIAL_TX %h %d DWORDs", tag, t.dllp_tx_packet[i], t.dllp_tx_packet.size()), UVM_HIGH)
    foreach(t.mac_tx_data[i]) begin
      foreach(t.mac_tx_data[i][j]) begin
        rc_received.push_back(t.mac_tx_data[i][j]);
      end
    end
    rc_dllp_packet = t.dllp_tx_packet;
    foreach(rc_dllp_packet[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] RC_DLLP_MAC_TX %h %d DWORDs", tag, rc_dllp_packet[i], rc_dllp_packet.size()), UVM_HIGH)
    t.dllp_tx_packet.delete();
  endfunction

  function void write_port_f(Sequence_item t);
    rc_received_os = t.os_t;
      `uvm_info("MAC_TX_DRV", $sformatf("RC_ORDERED_SETS %0d DWORDs",rc_received_os.size()), UVM_HIGH)
    if(t.tlp_queue.size()>0) 
       rc_tlp_fifo.push_back(t.tlp_queue);
    if(t.dlp_queue.size()>0)
       rc_dllp_fifo.push_back(t.dlp_queue);
  //  foreach(t.dlp_queue[i])
  //    rc_dllp_queue.push_back(t.dlp_queue[i]);
       foreach(rc_dllp_queue[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] RC_DLLP_Received_EP %0h DWORDs", tag, rc_dllp_queue[i]), UVM_HIGH)
    t.dlp_queue.delete();
  endfunction

   function void write_port_g(Sequence_item t);
    `uvm_info("MAC_RX_DRV", $sformatf("[%s] Write_STARTED", tag), UVM_HIGH)
    foreach(t.mac_rx_data[i]) begin
      foreach(t.mac_rx_data[i][j]) begin
        ep_received.push_back(t.mac_rx_data[i][j]);
      end
    end
    ep_dllp_packet = t.dllp_packet;
    foreach(ep_dllp_packet[i])
      `uvm_info("MAC_RX_DRV", $sformatf("[%s] EP_DLLP_MAC %h %d DWORDs", tag, ep_dllp_packet[i], ep_dllp_packet.size()), UVM_HIGH)
  endfunction

  function void write_port_h(Sequence_item t);
    ep_os = t.os_t;
      `uvm_info("MAC_TX_DRV", $sformatf("ORDERED_SETS %0d DWORDs",ep_os.size()), UVM_HIGH)
    if(t.tlp_queue_t.size() > 0)
      ep_tlp_fifo.push_back(t.tlp_queue_t);
    if(t.dlp_rx_queue.size() > 0)
    ep_dllp_fifo.push_back(t.dlp_rx_queue);
    foreach(t.tlp_queue_t[i])
      `uvm_info("MAC_RX_DRV", $sformatf("[%s] Received from PMA DRIVER %0h %d DWORDs", tag, t.tlp_queue_t[i], t.tlp_queue_t.size()), UVM_HIGH)
  endfunction

    function bit parity_calc(input length ,input sequence_number,output f_p );
    bit [22:0] parity_check = {length,sequence_number};
    if(^parity_check) f_p = 1'b1;
    else f_p = 1'b0;
  endfunction

  function bit [7:0] rc_d_s(inout bit [7:0] data);
    static bit [22:0] lfsr = 23'h7FFFFF;
    for (int i = 0; i < 8; i++) begin
      if (lfsr[22]) lfsr = (lfsr << 1) ^ polynomial;
      else          lfsr = (lfsr << 1);
      data[i] = lfsr[22] ^ data[i];
    end
    return data;
  endfunction
  
  function bit [7:0] ep_d_s(inout bit [7:0] data);
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
      os[i+:8] = rc_d_s(os[i+:8]);
  endfunction

  //-----------------------------------------------------------
  // Rate Identifier helpers (shared - operate only on cfg.gen of
  // whichever instance, RC or EP, calls them).
  //   rate_id_byte()   : builds the Rate Identifier byte (Symbol 4)
  //                      embedded into TS1/TS2 ordered sets -
  //                      bit0=2.5GT/s(Gen1, always set), bit1=5GT/s
  //                      (Gen2) supported, bit2=8GT/s(Gen3) supported,
  //                      bit5=Speed Change request (set only when
  //                      driving Recovery.RcvrCfg for an actual speed
  //                      change).
  //   decode_max_gen() : inverse - highest Gen a received Rate
  //                      Identifier byte advertises.
  //   gen_to_rate_code(): Gen (1/2/3) -> PIPE Rate[1:0] encoding.
  //   tag_ts1()        : stamps a TS1/TS2 base ordered set with this
  //                      instance's own Rate Identifier byte before
  //                      it goes out on the wire.
  //-----------------------------------------------------------
  function bit [7:0] rate_id_byte(int unsigned gen, bit speed_change = 1'b0);
    bit [7:0] b;
    b      = 8'h00;
    b[0]   = 1'b1;        // 2.5 GT/s (Gen1) - always supported
    b[1]   = (gen >= 2);  // 5.0 GT/s (Gen2) supported
    b[2]   = (gen >= 3);  // 8.0 GT/s (Gen3) supported
    b[5]   = speed_change;
    return b;
  endfunction

  function int unsigned decode_max_gen(bit [7:0] rate_id);
    if(rate_id[2])      decode_max_gen = 3;
    else if(rate_id[1]) decode_max_gen = 2;
    else                decode_max_gen = 1;
  endfunction

  function bit [1:0] gen_to_rate_code(int unsigned gen);
    case(gen)
      3       : gen_to_rate_code = 2'b10;
      2       : gen_to_rate_code = 2'b01;
      default : gen_to_rate_code = 2'b00;
    endcase
  endfunction

  function bit [127:0] tag_ts1(bit [127:0] base_ts, bit speed_change = 1'b0);
    bit [127:0] ts = base_ts;
    ts[95:88] = rate_id_byte(cfg.gen, speed_change);
    tag_ts1   = ts;
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
    foreach(rc_received[i])
    `uvm_info("PIPE_DRV",$sformatf("PACKET ENCODING: %0h size = %d",rc_received[i],rc_received.size()),UVM_HIGH)
    for(int i=0;i<rc_received.size();i=i+4) begin
      data  = {2'b10,rc_received[i],rc_received[i+1],rc_received[i+2],rc_received[i+3]};
      rc_trans_data.push_back(data);
    end
    foreach(rc_trans_data[i])
    `uvm_info("PIPE_DRV",$sformatf("data: %0h",rc_trans_data[i]),UVM_HIGH)
  endfunction
// BYTE STRIPING
localparam int NUM_LANES = 32;
localparam bit [1:0] SYNC_HDR = 2'b01;


bit [7:0]   rc_striped_lanes[NUM_LANES][$];
bit [129:0] rc_lane_word[NUM_LANES];

// --- striping task fills a queue per lane instead of a single word ---
bit [129:0] rc_lane_word_q[NUM_LANES][$];   // one queue entry per 16B block

task rc_byte_striping(input bit [31:0] rc_received[$]);
    bit [7:0] payload_bytes[$];
    bit [127:0] payload;
    bit [31:0] word;
    int total_bytes;
    int num_rounds;
    int blocks_per_lane;

    `uvm_info("MAC_TX_DRV",
      $sformatf("[%s] RC byte-striping packet: %0d DWs across %0d lanes",
        tag, rc_received.size(), cfg.num_lanes), UVM_LOW)

    payload_bytes.delete();
    foreach (rc_received[w]) begin
        word = rc_received[w];
        for (int b = 3; b >= 0; b--)
            payload_bytes.push_back(word[b*8 +: 8]);
    end

    total_bytes = payload_bytes.size();
    num_rounds  = (total_bytes + cfg.num_lanes - 1) / cfg.num_lanes;

    for (int lane = 0; lane < NUM_LANES; lane++) begin
        rc_striped_lanes[lane].delete();
        rc_lane_word_q[lane].delete();
    end

    for (int i = 0; i < total_bytes; i++) begin
        int lane = i % cfg.num_lanes;
        rc_striped_lanes[lane].push_back(payload_bytes[i]);
    end

    for (int lane = 0; lane < cfg.num_lanes; lane++)
        while (rc_striped_lanes[lane].size() < num_rounds)
            rc_striped_lanes[lane].push_back(8'h00);

    blocks_per_lane = (num_rounds + 15) / 16;

    for (int blk = 0; blk < blocks_per_lane; blk++) begin
        for (int lane = 0; lane < cfg.num_lanes; lane++) begin
            payload = '0;
            for (int r = 0; r < 16; r++) begin
                int idx = blk*16 + r;
                if (idx < rc_striped_lanes[lane].size())
                    payload[127-r*8 -: 8] = rc_striped_lanes[lane][idx];
            end
            rc_lane_word_q[lane].push_back({2'b10, payload});
            `uvm_info("TX_BYTE_STRIPE",
                $sformatf("Block[%0d] Lane[%0d] = %033h", blk, lane, {2'b10, payload}),
                UVM_HIGH)
        end
    end
endtask

// --- drive task: all blocks, all lanes aligned on the same PCLK edge ---
task rc_drive_striped_data();
    int num_blocks;
    num_blocks = rc_lane_word_q[0].size();   // same for every lane by construction

    `uvm_info("MAC_TX_DRV",
      $sformatf("[%s] Driving %0d striped block(s) onto PIPE TX lanes", tag, num_blocks),
      UVM_LOW)

    for (int blk = 0; blk < num_blocks; blk++) begin
        @(posedge rc_pvif.PCLK);
        for (int lane = 0; lane < cfg.num_lanes; lane++) begin
            rc_pvif.TxData[lane]      <= rc_lane_word_q[lane][blk];
            rc_pvif.TxDataValid[lane] <= 1;
        end
    end

    @(posedge rc_pvif.PCLK);
    for (int lane = 0; lane < cfg.num_lanes; lane++)
        rc_pvif.TxDataValid[lane] <= 0;

    `uvm_info("MAC_TX_DRV", $sformatf("[%s] RC striped block drive complete", tag), UVM_LOW)
endtask

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
      `uvm_info("PIPE_DRV",$sformatf("stp: %0h f_p %d length = %h sequen = %h",stp_pkt,f_p,pkt_len,sequence_number),UVM_HIGH)

      pkt_q.insert(i, stp_pkt);

  //    for(int j = i+1;j<(i+pkt_len);j++) begin
  //      data = pkt_q[j];
  //      pkt_q[j] = {rc_d_s(data[31:24]),rc_d_s(data[23:16]),rc_d_s(data[15:8]),rc_d_s(data[7:0])};
  //    end
      i = i + pkt_len ;
    end
  endfunction
/*
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
*/
  //-----------------------------------------------------------
  // NOTE: Training Sequences / Ordered Sets (TS1, TS2, EIEOS, SDS,
  // SKP, EIOS...) are NEVER scrambled per the PCIe Base Spec - the
  // scrambler applies only to the Data Stream (TLPs/DLLPs/Logical
  // Idle). The previous version called os_scramble(tmp) here
  // unconditionally, which also corrupted the Rate Identifier byte
  // (Symbol 4, bits [95:88]) since it falls inside the scrambled
  // byte range [119:8] - this broke rate negotiation in
  // Polling.Active (rc_partner_rate_id / ep_partner_rate_id were
  // being decoded from scrambled bits). Fixed: no scrambling here.
  //-----------------------------------------------------------
  //-----------------------------------------------------------
  // Per-lane Data Stream broadcast helpers (Option A: identical
  // content on every active lane, driven explicitly per lane -
  // e.g. for cfg.num_lanes=2 this drives TxData[0] and TxData[1]
  // directly, generalized over cfg.num_lanes instead of hardcoding
  // a lane count).
  //-----------------------------------------------------------
  task automatic rc_tx_bcast_data(bit [129:0] data);
     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane])
           rc_pvif.TxData[lane] <= data;
  endtask

  task automatic rc_tx_bcast_valid(bit valid);
     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane])
           rc_pvif.TxDataValid[lane] <= valid;
  endtask

  task automatic ep_tx_bcast_data(bit [129:0] data);
     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane])
           ep_pvif.TxData[lane] <= data;
  endtask

  task automatic ep_tx_bcast_valid(bit valid);
     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane])
           ep_pvif.TxDataValid[lane] <= valid;
  endtask

  task rc_drive_os(bit [127:0] os_val, bit [1:0] sync_hdr = 2'b01);
    rc_encoded_OS = {sync_hdr, os_val};
    rc_tx_bcast_data(rc_encoded_OS);
    rc_tx_bcast_valid(1);
  endtask

  //-----------------------------------------------------------
  // LTSSM Timer - generic time-based watchdog. Ticks on each
  // side's own PCLK so it naturally tracks whatever rate that
  // side is currently running at.
  //-----------------------------------------------------------
  task automatic rc_ltssm_timer(input time timeout);
     time start_time;
     start_time = $time;
     while(($time - start_time) < timeout)
        @(posedge rc_pvif.PCLK);
  endtask

  task automatic ep_ltssm_timer(input time timeout);
     time start_time;
     start_time = $time;
     while(($time - start_time) < timeout)
        @(posedge ep_pvif.PCLK);
  endtask

  //-----------------------------------------------------------
  // Receiver Detection (Detect.Active) - per active lane:
  //   1. Assert TxDetectRx[lane]   (MAC -> PHY)
  //   2. Wait for PhyStatus[lane]  (PHY -> MAC, PCIe_PMA_driver)
  //   3. Sample RxStatus[lane] == RX_DETECTED
  //   4. Deassert TxDetectRx[lane] and wait for PhyStatus[lane] to
  //      fall before returning, so a retry attempt doesn't race
  //      the tail end of this one.
  // All active lanes are waited on concurrently (forked), not
  // sequentially, so a PhyStatus pulse on one lane can't be missed
  // while blocked on another.
  //-----------------------------------------------------------
  task automatic rc_perform_receiver_detection(output bit [`PCIE_NUM_LANES-1:0] detect_mask);

     int lanes_pending;

     detect_mask   = '0;
     lanes_pending = 0;

     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane]) begin
           rc_pvif.TxDetectRx[lane] <= 1'b1;
           lanes_pending++;
        end

     // NOTE: fork/join_none here only launches the per-lane waiters
     // and returns immediately - it does NOT block until they
     // complete. The actual blocking wait is the explicit
     // "wait(lanes_pending == 0)" below, which each lane's process
     // decrements on completion. (An outer "join" here instead would
     // be a bug: join only waits for this spawner for-loop itself,
     // which finishes instantly since each iteration just launches a
     // detached join_none process - it would NOT wait for the lane
     // processes, causing detect_mask to be read out empty every
     // time and the caller to spin at zero simulation time.)
     fork
        for(int lane = 0; lane < cfg.num_lanes; lane++)
        begin
           automatic int l = lane;
           if(cfg.active_lane_mask[l])
           fork
              begin
                 wait(rc_pvif.PhyStatus[l]);
                 if(rc_pvif.RxStatus[l] == RX_DETECTED)
                    detect_mask[l] = 1'b1;
                 rc_pvif.TxDetectRx[l] <= 1'b0;
                 lanes_pending--;
              end
           join_none
        end
     join_none

 //    wait(lanes_pending == 0);

     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane])
           wait(!rc_pvif.PhyStatus[lane]);

  endtask

  task automatic ep_perform_receiver_detection(output bit [`PCIE_NUM_LANES-1:0] detect_mask);

     int lanes_pending;

     detect_mask   = '0;
     lanes_pending = 0;

     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane]) begin
           ep_pvif.TxDetectRx[lane] <= 1'b1;
           lanes_pending++;
        end

     fork
        for(int lane = 0; lane < cfg.num_lanes; lane++)
        begin
           automatic int l = lane;
           if(cfg.active_lane_mask[l])
           fork
              begin
                 wait(ep_pvif.PhyStatus[l]);
                 if(ep_pvif.RxStatus[l] == RX_DETECTED)
                    detect_mask[l] = 1'b1;
                 ep_pvif.TxDetectRx[l] <= 1'b0;
                 lanes_pending--;
              end
           join_none
        end
     join_none

     wait(lanes_pending == 0);

     for(int lane = 0; lane < cfg.num_lanes; lane++)
        if(cfg.active_lane_mask[lane])
           wait(!ep_pvif.PhyStatus[lane]);

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
    `uvm_info("PIPE_DRV",$sformatf("PACKET ENCODING: %0p size = %d",ep_received,ep_received.size()),UVM_HIGH)
    for(int i=0;i<ep_received.size();i=i+4) begin
      data  = {2'b10,ep_received[i],ep_received[i+1],ep_received[i+2],ep_received[i+3]};
      ep_trans_data.push_back(data);
    end
    `uvm_info("PIPE_DRV",$sformatf("data: %0p",ep_trans_data),UVM_HIGH)
  endfunction
bit [129:0] ep_lane_word[NUM_LANES];
bit [7:0] ep_striped_lanes[NUM_LANES][$];

bit [129:0] ep_lane_word_q[NUM_LANES][$];   // one queue entry per 16B block

task ep_byte_striping(input bit [31:0] ep_received[$]);
    bit [7:0] payload_bytes[$];
    bit [127:0] payload;
    bit [31:0] word;
    int total_bytes;
    int num_rounds;
    int blocks_per_lane;

    `uvm_info("MAC_TX_DRV",
      $sformatf("[%s] EP byte-striping packet: %0d DWs across %0d lanes",
        tag, ep_received.size(), cfg.num_lanes), UVM_LOW)

    payload_bytes.delete();
    foreach (ep_received[w]) begin
        word = ep_received[w];
        for (int b = 3; b >= 0; b--)
            payload_bytes.push_back(word[b*8 +: 8]);
    end

    total_bytes = payload_bytes.size();
    num_rounds  = (total_bytes + cfg.num_lanes - 1) / cfg.num_lanes;

    for (int lane = 0; lane < NUM_LANES; lane++) begin
        ep_striped_lanes[lane].delete();
        ep_lane_word_q[lane].delete();
    end

    for (int i = 0; i < total_bytes; i++) begin
        int lane = i % cfg.num_lanes;
        ep_striped_lanes[lane].push_back(payload_bytes[i]);
    end

    for (int lane = 0; lane < cfg.num_lanes; lane++)
        while (ep_striped_lanes[lane].size() < num_rounds)
            ep_striped_lanes[lane].push_back(8'h00);

    blocks_per_lane = (num_rounds + 15) / 16;

    for (int blk = 0; blk < blocks_per_lane; blk++) begin
        for (int lane = 0; lane < cfg.num_lanes; lane++) begin
            payload = '0;
            for (int r = 0; r < 16; r++) begin
                int idx = blk*16 + r;
                if (idx < ep_striped_lanes[lane].size())
                    payload[127-r*8 -: 8] = ep_striped_lanes[lane][idx];
            end
            ep_lane_word_q[lane].push_back({2'b10, payload});
            `uvm_info("EP_BYTE_STRIPE",
                $sformatf("Block[%0d] Lane[%0d] = %033h", blk, lane, {2'b10, payload}),
                UVM_HIGH)
        end
    end
endtask

// --- drive task: all blocks, all lanes aligned on the same PCLK edge ---
task ep_drive_striped_data();
    int num_blocks;
    num_blocks = ep_lane_word_q[0].size();   // same for every lane by construction

    `uvm_info("MAC_TX_DRV",
      $sformatf("[%s] Driving %0d striped block(s) onto PIPE TX lanes", tag, num_blocks),
      UVM_LOW)

    for (int blk = 0; blk < num_blocks; blk++) begin
        @(posedge ep_pvif.PCLK);
        for (int lane = 0; lane < cfg.num_lanes; lane++) begin
            ep_pvif.TxData[lane]      <= ep_lane_word_q[lane][blk];
            ep_pvif.TxDataValid[lane] <= 1;
        end
    end

    @(posedge ep_pvif.PCLK);
    for (int lane = 0; lane < cfg.num_lanes; lane++)
        ep_pvif.TxDataValid[lane] <= 0;

    `uvm_info("MAC_TX_DRV", $sformatf("[%s] EP striped block drive complete", tag), UVM_LOW)
endtask

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

 //     for(int j = i+1;j<(i+pkt_len);j++) begin
 //       data = pkt_q[j];
 //       pkt_q[j] = {ep_d_s(data[31:24]),ep_d_s(data[23:16]),ep_d_s(data[15:8]),ep_d_s(data[7:0])};
 //   end
      i = i + pkt_len ;
    end
  endfunction
/*
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
*/
  task ep_drive_os(bit [127:0] os_val, bit [1:0] sync_hdr = 2'b01);
    // See rc_drive_os note above - Ordered Sets are never scrambled.
    ep_encoded_OS = {sync_hdr, os_val};
    ep_tx_bcast_data(ep_encoded_OS);
    ep_tx_bcast_valid(1);
  endtask
  // ---- RC_MODE ----
  task rc_state_detect_active();

     bit detection_done;
     bit timeout_occured;

     `uvm_info("TX_LTSSM","Entered DETECT_ACTIVE",UVM_LOW)

     //-----------------------------------------------------------
     // First Receiver Detection attempt, with watchdog timeout
     //-----------------------------------------------------------

     detection_done  = 0;
     timeout_occured = 0;

     fork
        begin
           rc_perform_receiver_detection(rc_detect_mask_first);
           detection_done = 1;
        end
        begin
           rc_ltssm_timer(cfg.detect_active_timeout);
           timeout_occured = 1;
        end
     join_any
     disable fork;

     if(timeout_occured && !detection_done)
     begin
        `uvm_error("TX_LTSSM","Receiver Detection Timeout")
        rc_state = DETECT_QUIET;
        return;
     end

     //-----------------------------------------------------------
     // Receiver detected on all active lanes -> Polling.Active
     //-----------------------------------------------------------

     if(rc_detect_mask_first == cfg.active_lane_mask)
     begin

        `uvm_info("TX_LTSSM","Receiver detected on all active lanes",UVM_LOW)

        for(int lane = 0; lane < cfg.num_lanes; lane++)
           if(cfg.active_lane_mask[lane])
              rc_pvif.TxElecIdle[lane] <= 1'b0;

        rc_state = POLLING_ACTIVE;
        return;

     end

     //-----------------------------------------------------------
     // No receiver detected on any lane -> back to Detect.Quiet
     //-----------------------------------------------------------

     if(rc_detect_mask_first == '0)
     begin
        `uvm_info("TX_LTSSM","Receiver not detected",UVM_HIGH)
        rc_state = DETECT_QUIET;
        return;
     end

     //-----------------------------------------------------------
     // Partial detection - retry once and compare
     //-----------------------------------------------------------

     `uvm_info("TX_LTSSM","Partial lane detection. Retrying...",UVM_LOW)

     rc_ltssm_timer(cfg.detect_retry_timeout);
     rc_perform_receiver_detection(rc_detect_mask_second);

     if(rc_detect_mask_first == rc_detect_mask_second)
     begin

        `uvm_info("TX_LTSSM","Stable lane detection",UVM_HIGH)

        for(int lane = 0; lane < cfg.num_lanes; lane++)
        begin
           if(!cfg.active_lane_mask[lane]) continue;
           if(rc_detect_mask_second[lane])
              rc_pvif.TxElecIdle[lane] <= 1'b0;
           else
              rc_pvif.TxElecIdle[lane] <= 1'b1;   // no Receiver - hold Elec Idle
        end

        rc_state = POLLING_ACTIVE;

     end
     else
     begin
        `uvm_info("TX_LTSSM","Lane detection changed. Returning to Detect.Quiet",UVM_LOW)
        rc_state = DETECT_QUIET;
     end

  endtask

  // ---- EP_MODE ----
  task ep_state_detect_active();

     bit detection_done;
     bit timeout_occured;

     `uvm_info("RX_LTSSM","Entered DETECT_ACTIVE",UVM_LOW)

     detection_done  = 0;
     timeout_occured = 0;

     fork
        begin
           ep_perform_receiver_detection(ep_detect_mask_first);
           detection_done = 1;
        end
        begin
           ep_ltssm_timer(cfg.detect_active_timeout);
           timeout_occured = 1;
        end
     join_any
     disable fork;

     if(timeout_occured && !detection_done)
     begin
        `uvm_error("RX_LTSSM","Receiver Detection Timeout")
        ep_state = EP_DETECT_QUIET;
        return;
     end

     if(ep_detect_mask_first == cfg.active_lane_mask)
     begin

        `uvm_info("RX_LTSSM","Receiver detected on all active lanes",UVM_HIGH)

        for(int lane = 0; lane < cfg.num_lanes; lane++)
           if(cfg.active_lane_mask[lane])
              ep_pvif.TxElecIdle[lane] <= 1'b0;

        ep_state = EP_POLLING_ACTIVE;
        return;

     end

     if(ep_detect_mask_first == '0)
     begin
        `uvm_info("RX_LTSSM","Receiver not detected",UVM_HIGH)
        ep_state = EP_DETECT_QUIET;
        return;
     end

     `uvm_info("RX_LTSSM","Partial lane detection. Retrying...",UVM_HIGH)

     ep_ltssm_timer(cfg.detect_retry_timeout);
     ep_perform_receiver_detection(ep_detect_mask_second);

     if(ep_detect_mask_first == ep_detect_mask_second)
     begin

        `uvm_info("RX_LTSSM","Stable lane detection",UVM_HIGH)

        for(int lane = 0; lane < cfg.num_lanes; lane++)
        begin
           if(!cfg.active_lane_mask[lane]) continue;
           if(ep_detect_mask_second[lane])
              ep_pvif.TxElecIdle[lane] <= 1'b0;
           else
              ep_pvif.TxElecIdle[lane] <= 1'b1;
        end

        ep_state = EP_POLLING_ACTIVE;

     end
     else
     begin
        `uvm_info("RX_LTSSM","Lane detection changed. Returning to Detect.Quiet",UVM_LOW)
        ep_state = EP_DETECT_QUIET;
     end

  endtask

  // ---- RC_MODE ----
  localparam int unsigned MIN_TS1_COUNT = 10;

  task rc_state_polling_active();

     int unsigned ts1_sent_count;
     bit          barrier_met;
     bit          timeout_occured;
     bit          enter_compliance;

     `uvm_info("TX_LTSSM",$sformatf("Entered POLLING_ACTIVE (advertising Gen%0d)",cfg.gen),UVM_LOW)

     //-----------------------------------------------------------
     // Immediate Polling.Compliance if Enter Compliance bit was
     // already set prior to entry - no TS1 sent.
     //-----------------------------------------------------------

     if(cfg.link_ctrl2_enter_compliance)
     begin
        `uvm_info("TX_LTSSM","Enter Compliance bit set prior to entry -> immediate POLLING_COMPLIANCE",UVM_LOW)
        rc_state = POLLING_COMPLIANCE;
        return;
     end

     ts1_sent_count   = 0;
     barrier_met      = 0;
     timeout_occured  = 0;
     enter_compliance = 0;
     rc_received_os.delete();

     fork

        //--------------------------------------------------------
        // TS1 Transmit Process - keeps sending until the fast
        // barrier branch or the 24ms timeout branch disables fork.
        //--------------------------------------------------------
        begin
          // forever
          // begin
	      repeat(10) begin
              @(posedge rc_pvif.PCLK);
              rc_drive_os(tag_ts1(rc_TS1));
              ts1_sent_count++;
              end
              @(posedge rc_pvif.PCLK);
              rc_tx_bcast_valid(0);

              if(cfg.link_ctrl2_enter_compliance)
              begin
                 enter_compliance = 1;
                 disable fork;
              end
          // end
        end

        //--------------------------------------------------------
        // Fast Barrier: local conditions (>=1024 TS1 sent AND >=8
        // consecutive matching TS received) must BOTH be satisfied
        // before touching the cross-agent barrier - calling
        // wait_for() first can let the barrier drop prematurely and
        // stall this branch afterwards while the timeout races on.
        //--------------------------------------------------------
        begin
           wait(rc_received_os.size() > 7);
      `uvm_info("MAC_TX_DRV", $sformatf(" wait_completetd RC_ORDERED_SETS %0d DWORDs",rc_received_os.size()), UVM_LOW)
          // wait(ts1_sent_count > 9);

           polling_active.wait_for();

           barrier_met = 1;
           disable fork;
        end

        //--------------------------------------------------------
        // 24ms Overall Timeout
        //--------------------------------------------------------
        begin
           rc_ltssm_timer(cfg.polling_active_timeout);
           timeout_occured = 1;
           disable fork;
        end

     join


     if(enter_compliance)
     begin
        `uvm_info("TX_LTSSM","Enter Compliance bit set during POLLING_ACTIVE -> POLLING_COMPLIANCE",UVM_LOW)
        rc_received_os.delete();
        rc_state = POLLING_COMPLIANCE;
        return;
     end

     if(barrier_met)
     begin

        rc_partner_rate_id = rc_received_os[0][95:88];
        rc_negotiated_gen  = (cfg.gen < decode_max_gen(rc_partner_rate_id)) ?
                               cfg.gen : decode_max_gen(rc_partner_rate_id);

        `uvm_info("TX_LTSSM",
          $sformatf("Rate negotiation: own Gen%0d, partner rate_id=%08b (max Gen%0d) -> negotiated Gen%0d",
                     cfg.gen, rc_partner_rate_id, decode_max_gen(rc_partner_rate_id), rc_negotiated_gen),
          UVM_LOW)

        `uvm_info("TX_LTSSM",">=1024 TS1 sent, 8 consecutive matching TS received -> POLLING_CONFIGURATION",UVM_LOW)
        rc_received_os.delete();
        rc_state = POLLING_CONFIGURATION;
        return;

     end

     // 24ms timeout without meeting the fast-path barrier - fall
     // back to Compliance (conservative default; see chat notes on
     // condition (i)/(ii) predetermined-lane-subset nuance which
     // needs the real Symbol-5 bit decode to implement exactly).
     `uvm_info("TX_LTSSM","24ms timeout without meeting fast-path barrier -> POLLING_COMPLIANCE",UVM_LOW)
     rc_received_os.delete();
     rc_state = POLLING_COMPLIANCE;

  endtask

  // ---- EP_MODE ----
  task ep_state_polling_active();

     int unsigned ts1_sent_count;
     bit          barrier_met;
     bit          timeout_occured;
     bit          enter_compliance;

     `uvm_info("RX_LTSSM",$sformatf("Entered POLLING_ACTIVE (advertising Gen%0d)",cfg.gen),UVM_LOW)

     if(cfg.link_ctrl2_enter_compliance)
     begin
        `uvm_info("RX_LTSSM","Enter Compliance bit set prior to entry -> immediate POLLING_COMPLIANCE",UVM_LOW)
        ep_state = EP_POLLING_COMPLIANCE;
        return;
     end

     ts1_sent_count   = 0;
     barrier_met      = 0;
     timeout_occured  = 0;
     enter_compliance = 0;
     ep_os.delete();

     fork

        begin
           //forever
           //begin
	     repeat(8) begin
	        @(posedge ep_pvif.PCLK);
                ep_drive_os(tag_ts1(ep_TS1));
                ts1_sent_count++;
               end
	      
              @(posedge ep_pvif.PCLK);
	      ep_tx_bcast_valid(0);

              if(cfg.link_ctrl2_enter_compliance)
              begin
                 enter_compliance = 1;
                 disable fork;
              end
        //   end
        end

        begin
           wait(ep_os.size() > 9);
      `uvm_info("MAC_TX_DRV", $sformatf(" wait_completed ORDERED_SETS %0d DWORDs ts1_sent_count = %d",ep_os.size(),ts1_sent_count), UVM_LOW)
          // wait(ts1_sent_count > 7);

           polling_active.wait_for();

           barrier_met = 1;
           disable fork;
        end

        begin
           ep_ltssm_timer(cfg.polling_active_timeout);
           timeout_occured = 1;
           disable fork;
        end

     join


     if(enter_compliance)
     begin
        `uvm_info("RX_LTSSM","Enter Compliance bit set during POLLING_ACTIVE -> POLLING_COMPLIANCE",UVM_LOW)
        ep_os.delete();
        ep_state = EP_POLLING_COMPLIANCE;
        return;
     end

     if(barrier_met)
     begin

        ep_partner_rate_id = ep_os[0][95:88];
        ep_negotiated_gen  = (cfg.gen < decode_max_gen(ep_partner_rate_id)) ?
                               cfg.gen : decode_max_gen(ep_partner_rate_id);

        `uvm_info("RX_LTSSM",
          $sformatf("Rate negotiation: own Gen%0d, partner rate_id=%08b (max Gen%0d) -> negotiated Gen%0d",
                     cfg.gen, ep_partner_rate_id, decode_max_gen(ep_partner_rate_id), ep_negotiated_gen),
          UVM_LOW)

        `uvm_info("RX_LTSSM",">=1024 TS1 sent, 8 consecutive matching TS received -> POLLING_CONFIGURATION",UVM_LOW)
        ep_os.delete();
        ep_state = EP_POLLING_CONFIGURATION;
        return;

     end

     `uvm_info("RX_LTSSM","24ms timeout without meeting fast-path barrier -> POLLING_COMPLIANCE",UVM_LOW)
     ep_os.delete();
     ep_state = EP_POLLING_COMPLIANCE;

  endtask

  // ---- RC_MODE ----
  task rc_state_polling_compliance();
      `uvm_info("TX_LTSSM","POLLING_COMPLIANCE",UVM_LOW)
      // Drive a brief compliance burst (replace with your actual pattern)
      repeat(4) begin
        @(posedge rc_pvif.PCLK);
        rc_tx_bcast_data(130'h11ee965ecf269e1FFF3ecb241111b600a);   // placeholder
        rc_tx_bcast_valid(1);
      end
      @(posedge rc_pvif.PCLK);
      rc_tx_bcast_valid(0);
   
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

     int unsigned ts2_sent_count;
     int unsigned ts2_sent_after_first_rx;
     bit          received_first_ts2;
     bit          barrier_met;
     bit          timeout_occured;

     `uvm_info("TX_LTSSM","Entered POLLING_CONFIGURATION",UVM_LOW)

     //-----------------------------------------------------------
     // Entry action: Transmit Margin field of Link Control 2 must
     // be reset to 000b on entry to this substate.
     //-----------------------------------------------------------
     //cfg.link_ctrl2_transmit_margin = 3'b000;

     ts2_sent_count           = 0;
     ts2_sent_after_first_rx  = 0;
     received_first_ts2       = 0;
     barrier_met              = 0;
     timeout_occured          = 0;
     rc_received_os.delete();

     fork
        begin
          // forever
          // begin
	      repeat(16) begin
              @(posedge rc_pvif.PCLK);
              rc_drive_os(tag_ts1(TS2));    
                ts2_sent_count++;
               end
             @(posedge rc_pvif.PCLK);
	      rc_tx_bcast_valid(0);

          // end
        end

        begin
           wait(rc_received_os.size() > 7);
           `uvm_info("MAC_TX_DRV",
              $sformatf("wait_completed RC_ORDERED_SETS %0d DWORDs",rc_received_os.size()),
              UVM_LOW)


           polling_configuration.wait_for();   // TODO: cross-agent barrier event for this substate

           barrier_met = 1;
           disable fork;
        end

        //--------------------------------------------------------
        // 48ms Overall Timeout
        //--------------------------------------------------------
        begin
           rc_ltssm_timer(cfg.polling_configuration_timeout);   // TODO: add 48ms timeout param to cfg
           timeout_occured = 1;
           disable fork;
        end

     join

     if(barrier_met)
     begin
        `uvm_info("TX_LTSSM",
           "8 consecutive TS2 (PAD) received + 16 TS2 sent after first RX -> CONFIG_LINKNUM_START",
           UVM_LOW)
        rc_received_os.delete();
        rc_state = CONFIG_LINKNUM_START;
        return;
     end

     // 48ms timeout without meeting the fast-path barrier -> Detect
     `uvm_info("TX_LTSSM","48ms timeout without meeting fast-path barrier -> DETECT",UVM_LOW)
     rc_received_os.delete();
     rc_state = DETECT_QUIET;

  endtask
  // ---- EP_MODE ----
 task ep_state_polling_configuration();

     int unsigned ts2_sent_count;
     int unsigned ts2_sent_after_first_rx;
     bit          received_first_ts2;
     bit          barrier_met;
     bit          timeout_occured;

     `uvm_info("TX_LTSSM","EP Entered POLLING_CONFIGURATION",UVM_LOW)

     //-----------------------------------------------------------
     // Entry action: Transmit Margin field of Link Control 2 must
     // be reset to 000b on entry to this substate.
     //-----------------------------------------------------------
    // cfg.link_ctrl2_transmit_margin = 3'b000;

     ts2_sent_count           = 0;
     ts2_sent_after_first_rx  = 0;
     received_first_ts2       = 0;
     barrier_met              = 0;
     timeout_occured          = 0;
     ep_os.delete();

     fork

        //--------------------------------------------------------
        // TS2 Transmit Process - sends TS2 Ordered Sets with Link
        // and Lane numbers set to PAD on all Lanes that detected a
        // Receiver during Detect. Data Rate Identifier Symbol must
        // advertise ALL data rates the Port supports.
        //--------------------------------------------------------
        begin
          // forever
          // begin
              repeat(8) begin
	        @(posedge ep_pvif.PCLK);
                ep_drive_os(tag_ts1(TS2));
               end
	      
              @(posedge ep_pvif.PCLK);
	      ep_tx_bcast_valid(0);
          // end
        end

        //--------------------------------------------------------
        // Fast Barrier: next state is Configuration only after
        // BOTH -
        //   (a) 8 consecutive TS2 OS (Link/Lane = PAD) received on
        //       any Lane that detected a Receiver during Detect, and
        //   (b) 16 TS2 OS transmitted after receiving the first
        //       TS2 OS.
        //--------------------------------------------------------
        begin

           wait(ep_os.size() > 15);
           `uvm_info("MAC_TX_DRV",
              $sformatf("wait_completed EP_ORDERED_SETS %0d DWORDs",ep_os.size()),
              UVM_LOW)

           polling_configuration.wait_for();   // TODO: same barrier object as RC side - confirm
                                                 //       shared event/barrier handle wiring
           barrier_met = 1;
           disable fork;
        end

        //--------------------------------------------------------
        // 48ms Overall Timeout
        //--------------------------------------------------------
        begin
           ep_ltssm_timer(cfg.polling_configuration_timeout);   // TODO: add 48ms timeout param to cfg
           timeout_occured = 1;
           disable fork;
        end

     join

     if(barrier_met)
     begin
        `uvm_info("TX_LTSSM",
           "EP: 8 consecutive TS2 (PAD) received + 16 TS2 sent after first RX -> CONFIG_LINKNUM_START",
           UVM_LOW)
        ep_os.delete();
        ep_state = EP_CONFIG_LINKNUM_START;
        return;
     end

     // 48ms timeout without meeting the fast-path barrier -> Detect
     `uvm_info("TX_LTSSM","EP: 48ms timeout without meeting fast-path barrier -> DETECT",UVM_LOW)
     ep_os.delete();
     ep_state = EP_DETECT_QUIET;

  endtask


  // ---- RC_MODE ----
  task rc_state_config_linknum_start();
  
  rc_link_num = rc_TS1[111:104];
  rc_lane_num = rc_TS1[119:112];
      `uvm_info("TX_LTSSM","CONFIG_LINKNUM_START – broadcasting link num",UVM_LOW)
  //     rc_negotiated_link_num = 8'h00;   // x1, single link
   
      // Drive rc_TS1 with link number encoded (field placement is design-specific)
      repeat(4) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(rc_TS1);   // in real impl embed rc_link_num into the OS bytes
      end
      @(posedge rc_pvif.PCLK);
      rc_tx_bcast_valid(0);
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
      
      repeat(2) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(rc_TS1);
      end
      @(posedge rc_pvif.PCLK);
      rc_tx_bcast_valid(0);
   
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
      repeat(2) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(ep_TS1);
      end
      @(posedge ep_pvif.PCLK);
      ep_tx_bcast_valid(0);
  
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
      repeat(4) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(TS2);   // embed ep_lane_num in TS2 bytes in real impl
      end
      @(posedge ep_pvif.PCLK);
      ep_tx_bcast_valid(0);
  
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
      repeat(2) begin
        @(posedge rc_pvif.PCLK);
        rc_drive_os(TS2);
      end
      @(posedge rc_pvif.PCLK);
      rc_tx_bcast_valid(0);
   
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
      repeat(2) begin
        @(posedge ep_pvif.PCLK);
        ep_drive_os(TS2);
      end
      @(posedge ep_pvif.PCLK);
      ep_tx_bcast_valid(0);
  
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
    `uvm_info("TX_LTSSM",$sformatf("CONFIG_COMPLETE (advertising Gen%0d)",cfg.gen),UVM_LOW)
    repeat (16) begin
      @(posedge rc_pvif.PCLK);
      rc_drive_os(tag_ts1(rc_TS1));
    end
    @(posedge rc_pvif.PCLK);
    rc_tx_bcast_valid(0);
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
    `uvm_info("RX_LTSSM",$sformatf("CONFIG_COMPLETE (advertising Gen%0d)",cfg.gen),UVM_LOW)
    repeat (8) begin
      @(posedge ep_pvif.PCLK);
      ep_drive_os(tag_ts1(ep_TS1));
    end
    @(posedge ep_pvif.PCLK);
    ep_tx_bcast_valid(0);
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
      repeat(1) begin
        @(posedge rc_pvif.PCLK);
      rc_tx_bcast_data({2'b01, 128'h0});
        rc_tx_bcast_valid(1);
      end
      @(posedge rc_pvif.PCLK);
      rc_tx_bcast_valid(0);
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
      repeat(1) begin
  //       @(posedge ep_pvif.PCLK);
  //     ep_drive_os(ep_TS1);
        @(posedge ep_pvif.PCLK);
        ep_tx_bcast_data({2'h01, 128'h0});
        ep_tx_bcast_valid(1);
      end
      @(posedge ep_pvif.PCLK);
      ep_tx_bcast_valid(0);
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

      if (rc_negotiated_gen > rc_active_gen) begin
        `uvm_info("TX_LTSSM",
          $sformatf("Speed mismatch: running Gen%0d, negotiated Gen%0d -> RECOVERY",
                     rc_active_gen, rc_negotiated_gen), UVM_LOW)
        rc_state = RECOVERY_RCVRLOCK;
      end
      else begin
         link_up_env.trigger();
         fork
  forever begin
      begin
         wait(rc_received.size() > 0 || rc_dllp_packet.size() >0 );
         `uvm_info("PIPE_DRV", $sformatf("dllp_size=%0d received_size=%0d",rc_dllp_packet.size(), rc_received.size()),UVM_HIGH)
  
         if(rc_dllp_packet.size() >0) begin
  	foreach(rc_dllp_packet[i])
           `uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL: %0h",rc_dllp_packet[i]
   ),UVM_HIGH)
  
           rc_sdp_packet = {SDP[15:0],rc_dllp_packet[0][31:0],rc_dllp_packet[1][31:16]};
  	`uvm_info("PIPE_DRV",$sformatf("SDP: %0h",rc_sdp_packet),UVM_HIGH)
  	rc_dllp_packet.delete(0); 
  	rc_dllp_packet.delete(0);
          rc_dllp_packet.push_front(rc_sdp_packet[31:0]);
          rc_dllp_packet.push_front(rc_sdp_packet[63:32]);
	   rc_byte_striping(rc_dllp_packet);
  	rc_dllp_packet.delete();
           rc_drive_striped_data();
  //	rc_size_dllp = rc_dllp_packet.size();
  //	foreach(rc_dllp_packet[i])
  //	`uvm_info("PIPE_DRV",$sformatf("RC_DLLP_MAC_INITIAL: %0h rc_size %d",rc_dllp_packet[i],rc_size_dllp),UVM_HIGH)
  //       	for(int i=0;i<rc_size_dllp;i=i+4) begin
  //          @(posedge rc_pvif.PCLK);
  //          rc_tx_bcast_data({2'b10,rc_dllp_packet[i],rc_dllp_packet[i+1],rc_dllp_packet[i+2],rc_dllp_packet[i+3]});
  //          rc_tx_bcast_valid(1);
  //        end
  //         @(posedge rc_pvif.PCLK);
  //        rc_tx_bcast_valid(0);
  //		`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL_delete: %0p rc_size %d",rc_dllp_packet,rc_dllp_packet.size()),UVM_HIGH)
         end 
         else if(rc_received.size() >0) begin
        `uvm_info("PIPE_DRV",$sformatf("DATA STP ADDED and BEFORE_Srcambled: %0d",rc_received.size()),UVM_HIGH)
        foreach(rc_received[i])
        `uvm_info("PIPE_DRV",$sformatf("RC_SCRAMBLED_BEFORE %0h",rc_received[i]),UVM_HIGH)
        rc_add_stp_to_all_packets(rc_received);
                `uvm_info("PIPE_DRV",$sformatf("DATA STP ADDED and BEFORE_Srcambled: %0d",rc_received.size()),UVM_HIGH)
      //rc_data_scrambling(0);
      //rc_sdp_packet = {SDP[15:0],rc_dllp_packet[0][31:0],rc_dllp_packet[1][31:16]}; 
      //rc_received.push_back(rc_sdp_packet[63:32]);
      //rc_received.push_back(rc_sdp_packet[31:0]);
      rc_received.push_back(EDS);
      foreach(rc_received[i])
        `uvm_info("PIPE_DRV",$sformatf("RC_SCRAMBLED_AFTER %0h",rc_received[i]),UVM_HIGH)

      //rc_packet_encoding();
     // rc_received.delete();
      //rc_item.size_tx_rx = rc_trans_data.size();
     // rc_size_tx = rc_trans_data.size();
     // for(int i=0;i<rc_size_tx;i++) begin
     //    @(posedge rc_pvif.PCLK);
    //    rc_tx_bcast_data(rc_trans_data.pop_front());
      //  $display("TX DATA = %0p",rc_trans_data);
    //      rc_tx_bcast_valid(1);
	   rc_byte_striping(rc_received);
           rc_received.delete();
     // rc_trans_data.delete();      // stop driving the un-striped queue

      //@(posedge rc_pvif.PCLK);
     // for (int lane = 0; lane < cfg.num_lanes; lane++) begin
     // @(posedge rc_pvif.PCLK);
     // rc_pvif.TxData[lane] <= rc_lane_word[lane];
     // rc_pvif.TxDataValid[lane] <= 1;
     // end
     // for (int lane = 0; lane < cfg.num_lanes; lane++) begin
     // @(posedge rc_pvif.PCLK);
     // rc_pvif.TxDataValid[lane] <= 0;
     // end
      rc_drive_striped_data();
      end
      end
      end
  forever begin 
         begin
      wait(rc_tlp_fifo.size()>0 || rc_dllp_fifo.size()>0);
      // wait(queue.size() >0);
       if(rc_tlp_fifo.size() > 0) begin
	rc_received_tlp = rc_tlp_fifo.pop_front();
        rc_size_rx = rc_received_tlp.size();
	 foreach(rc_received_tlp[i])
    `uvm_info("MAC_TX_DRV", $sformatf("[%s] Compeletion_Received %0h %d  DWORDs", tag, rc_received_tlp[i],rc_size), UVM_HIGH)

        for(int i =0;i<rc_size_rx;i++) begin
          @(posedge rc_vif.CLK);
          rc_vif.dl_rx_data = rc_received_tlp.pop_front();
         `uvm_info("MAC_TX_DRV", $sformatf("[%s] Compeletion_Received_i %d  value %0h DWORDs", tag,i,rc_vif.dl_rx_data), UVM_HIGH)
          rc_vif.dl_rx_valid = 1;
          rc_vif.tl_mac_packet <= 1;
        end
         @(posedge rc_vif.CLK);
         rc_vif.dl_rx_valid = 0;
          rc_vif.tl_mac_packet <= 0;
     end
    //end
     else if(rc_dllp_fifo.size() > 0) begin
      foreach(rc_dllp_fifo[i]) 
      `uvm_info("MAC_TX_DRV",$sformatf("RC_DLLP_Received_1 %0h DWORDs ",rc_dllp_fifo[i]),UVM_HIGH)
        rc_dllp_queue = rc_dllp_fifo.pop_front();
	 foreach(rc_dllp_queue[i]) 
      `uvm_info("MAC_TX_DRV",$sformatf("RC_DLLP_Received_1 %0h DWORDs ",rc_dllp_queue[i]),UVM_HIGH)
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
      end
  endtask

  // ---- EP_MODE ----
  task ep_state_l0();
        `uvm_info("RX_LTSSM","L0 - link is up",UVM_LOW)
     // link_up.trigger();

      if (ep_negotiated_gen > ep_active_gen) begin
        `uvm_info("RX_LTSSM",
          $sformatf("Speed mismatch: running Gen%0d, negotiated Gen%0d -> RECOVERY",
                     ep_active_gen, ep_negotiated_gen), UVM_LOW)
        ep_state = EP_RECOVERY_RCVRLOCK;
      end
      else begin
           link_up_env_rx.trigger();
	      `uvm_info("RX_LTSSM",
          $sformatf("Speed mismatch: running Gen%0d, negotiated Gen%0d -> RECOVERY",
                     ep_active_gen, ep_negotiated_gen), UVM_LOW)
      fork
  forever begin 
      wait(ep_tlp_fifo.size()>0 || ep_dllp_fifo.size()>0);
      // Pull exactly one buffered TLP out of the FIFO. This assignment is a
      // value copy, so ep_received_tlp from this point on is a private
      // snapshot: write_port_h() can keep pushing new TLPs onto ep_tlp_fifo
      // in parallel without ever touching the data we're currently sending.
       if(ep_dllp_fifo.size() > 0) begin
	   ep_dllp_queue = ep_dllp_fifo.pop_front();
      foreach(ep_dllp_queue[i]) 
      `uvm_info("MAC_RX_DRV",$sformatf("EP_DLLP_Received_1 %0h DWORDs ",ep_dllp_queue[i]),UVM_HIGH)
	 foreach(ep_dllp_queue[i]) 
      `uvm_info("MAC_RX_DRV",$sformatf("EP_DLLP_Received_1 %0h DWORDs %d ",ep_dllp_queue[i],ep_size),UVM_HIGH)
        ep_size_dll = ep_dllp_queue.size();
        for(int i =0;i<ep_size_dll;i++) begin
          @(posedge ep_vif.CLK);
          ep_vif.dl_rx_data = ep_dllp_queue.pop_front();
          ep_vif.dl_rx_valid = 1;
  	ep_vif.dl_mac_packet = 1;
        end
         @(posedge ep_vif.CLK);
         ep_vif.dl_rx_valid = 0;
         ep_vif.dl_mac_packet = 0;
     end
       else if(ep_tlp_fifo.size() > 0) begin
        ep_received_tlp = ep_tlp_fifo.pop_front();
      `uvm_info("MAC_RX_DRV",$sformatf("TLP_Received_1 %p  %0d DWORDs ",ep_received_tlp,ep_received_tlp.size()),UVM_HIGH)
        ep_size_tlp = ep_received_tlp.size();
	foreach(ep_received_tlp[i])
      `uvm_info("MAC_RX_DRV",$sformatf("VALID_TO_ONE ep_received_tlp = %h",ep_received_tlp[i]),UVM_HIGH)
        for(int i =0;i<ep_size_tlp;i++) begin
          bit [31:0] ep_tlp_dword;
          ep_tlp_dword = ep_received_tlp.pop_front();
          @(posedge ep_vif.CLK);
          ep_vif.dl_rx_data    <= ep_tlp_dword;
          ep_vif.dl_rx_valid   <= 1;
          ep_vif.tl_mac_packet <= 1;
      `uvm_info("MAC_RX_DRV",$sformatf("VALID_TO_ONE i=%d ep_size = %d ep_received_tlp = %h",i,ep_size_tlp,ep_tlp_dword),UVM_HIGH)
        end
         @(posedge ep_vif.CLK);
      `uvm_info("MAC_RX_DRV",$sformatf("VALID_TO_ZERO ep_received_tlp = %d",ep_received_tlp.size()),UVM_HIGH)
         ep_vif.dl_rx_valid   <= 0;
         ep_vif.tl_mac_packet <= 0;
         // NOTE: no ep_received_tlp.delete() here anymore.
         // pop_front() above already consumed exactly the DWORDs that were
         // driven out. The old blind delete() would also wipe out any NEW
         // TLP that write_port_h() (an async analysis-port callback) had
         // written into ep_received_tlp while this loop was still driving
         // the previous TLP -- causing that new TLP to be silently dropped
         // and making the driver appear to "replay" the previous TLP's data.
     end
    //end
          end
    forever begin
      begin
         wait(ep_received.size() > 0 || ep_dllp_packet.size() >0 );
         if(ep_dllp_packet.size() >0) begin
  	foreach(ep_dllp_packet[i])
           `uvm_info("PIPE_DRV",$sformatf("EP_DLLP_MAC_INITIAL: %0h",ep_dllp_packet[i]
   ),UVM_HIGH)
  
           ep_sdp_packet = {SDP[15:0],ep_dllp_packet[0][31:0],ep_dllp_packet[1][31:16]};
  	`uvm_info("PIPE_DRV",$sformatf("SDP: %0h",ep_sdp_packet),UVM_HIGH)
  	ep_dllp_packet.delete(0); 
  	ep_dllp_packet.delete(0);
          ep_dllp_packet.push_front(ep_sdp_packet[31:0]);
          ep_dllp_packet.push_front(ep_sdp_packet[63:32]);
	 ep_byte_striping(ep_dllp_packet);
  	ep_dllp_packet.delete();
         ep_drive_striped_data();
 // 	ep_size_dllp = ep_dllp_packet.size();
 // 	foreach(ep_dllp_packet[i])
 // 	`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL: %0h ep_size %d",ep_dllp_packet[i],ep_size_dllp),UVM_HIGH)
 //        	for(int i=0;i<ep_size_dllp;i=i+4) begin
 //           @(posedge ep_pvif.PCLK);
 //           ep_tx_bcast_data({2'b10,ep_dllp_packet[i],ep_dllp_packet[i+1],ep_dllp_packet[i+2],ep_dllp_packet[i+3]});
 //           ep_tx_bcast_valid(1);
 //         end
 //          @(posedge ep_pvif.PCLK);
 //         ep_tx_bcast_valid(0);
 // 		`uvm_info("PIPE_DRV",$sformatf("DLLP_INITIAL_delete: %0p ep_size %d",ep_dllp_packet,ep_dllp_packet.size()),UVM_HIGH)
         end 
         else if(ep_received.size() >0) begin
         
         foreach(ep_received[i])
        `uvm_info("PIPE_RX_DRV",$sformatf("EP_SCRAMBLED_BEFORE and STP ADDED %0h",ep_received[i]),UVM_HIGH)
	
        ep_add_stp_to_all_packets(ep_received);
	foreach(ep_received[i])
        `uvm_info("PIPE_RX_DRV",$sformatf("EP_SCRAMBLED and STP ADDED %0h",ep_received[i]),UVM_HIGH)
    //    ep_data_scrambling(0);
      //ep_sdp_packet = {SDP[15:0],ep_dllp_packet[0][31:0],ep_dllp_packet[1][31:16]}; 
      //ep_received.push_back(ep_sdp_packet[63:32]);
      //ep_received.push_back(ep_sdp_packet[31:0]);
      ep_received.push_back(EDS);
      //ep_packet_encoding();
      //ep_received.delete();
     // ep_size = ep_trans_data.size();
     // for(int i=0;i<ep_size;i++) begin
     //    @(posedge ep_pvif.PCLK);
     //   ep_tx_bcast_data(ep_trans_data.pop_front());
      //  $display("TX DATA = %0p",ep_trans_data);
     //     ep_tx_bcast_valid(1);
     // end
     //      @(posedge ep_pvif.PCLK);
     //     ep_tx_bcast_valid(0);
	 ep_byte_striping(ep_received);
      ep_received.delete();
      ep_drive_striped_data();
      //ep_trans_data.delete();
//      ep_item.size_tx_rx = active_lanes;

  //    for (int lane = 0; lane < cfg.num_lanes; lane++)begin
  //    @(posedge ep_pvif.PCLK);
  //    ep_pvif.TxData[lane] <= ep_lane_word[lane];
  //    ep_pvif.TxDataValid[lane] <= 1;
  //    end
  //    for (int lane = 0; lane < cfg.num_lanes; lane++)begin
  //    @(posedge ep_pvif.PCLK);
  //    ep_pvif.TxDataValid[lane] <= 0;
  //    end
      end
      end
      end
      join
        end 
  endtask

// =====================================================================
// RECOVERY sub-state machine (per diagram):
//   L0 -> Recovery.RcvrLock -> Recovery.RcvrCfg -> {Recovery.Speed | Recovery.Idle}
//   Recovery.Speed -> Recovery.RcvrLock   (re-lock at the NEW speed)
//   Recovery.Idle  -> L0
//
// Flow per Gen-step:
//   1) RcvrLock : re-lock TS1s at CURRENT speed
//   2) RcvrCfg  : advertise TS2s; speed_change=1 if active_gen < negotiated_gen
//   3) if speed_change was actually needed -> Speed -> (loops back) RcvrLock
//      else                                -> Idle -> L0
// =====================================================================

// ---- RC_MODE ----
int unsigned rc_target_gen;

task rc_state_recovery_rcvrlock();
    `uvm_info("TX_LTSSM",
      $sformatf("Recovery.RcvrLock - relocking @ Gen%0d (negotiated Gen%0d)",
                 rc_active_gen, rc_negotiated_gen), UVM_LOW)

    rc_pvif.TxElecIdle <= '0;
    repeat(8) begin
      @(posedge rc_pvif.PCLK);
      rc_drive_os(tag_ts1(rc_TS1));   // TS1 @ CURRENT speed, no speed_change bit
    end
    @(posedge rc_pvif.PCLK);
    rc_tx_bcast_valid(0);

    wait(rc_received_os.size() > 0);
    recovery_rcvrlock.wait_for();
    rc_received_os.delete();

    `uvm_info("TX_LTSSM","Recovery.RcvrLock done -> Recovery.RcvrCfg",UVM_LOW)
    rc_state = RECOVERY_RCVRCFG;
endtask

task rc_state_recovery_rcvrcfg();
    bit speed_change;
    speed_change = (rc_active_gen < rc_negotiated_gen);

    `uvm_info("TX_LTSSM",
      $sformatf("Recovery.RcvrCfg - advertising TS2s (speed_change=%0b)", speed_change), UVM_LOW)

    repeat(8) begin
      @(posedge rc_pvif.PCLK);
      rc_drive_os(tag_ts1(TS2, speed_change));
    end
    @(posedge rc_pvif.PCLK);
    rc_tx_bcast_valid(0);

    wait(rc_received_os.size() > 0);
    recovery_rcvrcfg.wait_for();
    rc_received_os.delete();

    if (speed_change) begin
      rc_target_gen = rc_active_gen + 1;
      `uvm_info("TX_LTSSM",
        $sformatf("Recovery.RcvrCfg done -> Recovery.Speed (Gen%0d -> Gen%0d)",
                   rc_active_gen, rc_target_gen), UVM_LOW)
      rc_state = RECOVERY_SPEED;
    end
    else begin
      `uvm_info("TX_LTSSM","Recovery.RcvrCfg done -> Recovery.Idle (no speed change needed)",UVM_LOW)
      rc_state = RECOVERY_IDLE;
    end
endtask

task rc_state_recovery_speed();
    rc_pvif.TxElecIdle  <= cfg.active_lane_mask;
    rc_tx_bcast_valid(0);
    rc_pvif.Rate        <= gen_to_rate_code(rc_target_gen);
    rc_active_gen         = rc_target_gen;

    recovery_speed.wait_for();
    repeat(4) @(posedge rc_pvif.PCLK);   // let PCLK settle at the new rate
    rc_pvif.TxElecIdle <= '0;

    `uvm_info("TX_LTSSM",
      $sformatf("Recovery.Speed done -> now running at Gen%0d -> Recovery.RcvrLock (re-lock)",
                 rc_active_gen), UVM_LOW)

    // Per diagram: Speed always loops back to RcvrLock to re-lock at the new speed
    rc_state = RECOVERY_RCVRLOCK;
endtask

task rc_state_recovery_idle();
    repeat(8) begin
      @(posedge rc_pvif.PCLK);
      rc_tx_bcast_data({2'b01, 128'h0});
      rc_tx_bcast_valid(1);
    end
    @(posedge rc_pvif.PCLK);
    rc_tx_bcast_valid(0);

    wait(rc_received_os.size() > 0);
    recovery_idle_bar.wait_for();
    rc_received_os.delete();

    `uvm_info("TX_LTSSM",
      $sformatf("Recovery.Idle done -> L0 @ Gen%0d (final speed reached)", rc_active_gen), UVM_LOW)
    rc_state = L0;
endtask

// ---- EP_MODE ----
int unsigned ep_target_gen;

task ep_state_recovery_rcvrlock();
    `uvm_info("RX_LTSSM",
      $sformatf("Recovery.RcvrLock - relocking @ Gen%0d (negotiated Gen%0d)",
                 ep_active_gen, ep_negotiated_gen), UVM_LOW)

    ep_pvif.TxElecIdle <= '0;
    repeat(8) begin
      @(posedge ep_pvif.PCLK);
      ep_drive_os(tag_ts1(ep_TS1));   // TS1 @ CURRENT speed, no speed_change bit
    end
    @(posedge ep_pvif.PCLK);
    ep_tx_bcast_valid(0);

    wait(ep_os.size() > 0);
    recovery_rcvrlock.wait_for();
    ep_os.delete();

    `uvm_info("RX_LTSSM","Recovery.RcvrLock done -> Recovery.RcvrCfg",UVM_LOW)
    ep_state = EP_RECOVERY_RCVRCFG;
endtask

task ep_state_recovery_rcvrcfg();
    bit speed_change;
    speed_change = (ep_active_gen < ep_negotiated_gen);

    `uvm_info("RX_LTSSM",
      $sformatf("Recovery.RcvrCfg - advertising TS2s (speed_change=%0b)", speed_change), UVM_LOW)

    repeat(8) begin
      @(posedge ep_pvif.PCLK);
      ep_drive_os(tag_ts1(TS2, speed_change));
    end
    @(posedge ep_pvif.PCLK);
    ep_tx_bcast_valid(0);

    wait(ep_os.size() > 0);
    recovery_rcvrcfg.wait_for();
    ep_os.delete();

    if (speed_change) begin
      ep_target_gen = ep_active_gen + 1;
      `uvm_info("RX_LTSSM",
        $sformatf("Recovery.RcvrCfg done -> Recovery.Speed (Gen%0d -> Gen%0d)",
                   ep_active_gen, ep_target_gen), UVM_LOW)
      ep_state = EP_RECOVERY_SPEED;
    end
    else begin
      `uvm_info("RX_LTSSM","Recovery.RcvrCfg done -> Recovery.Idle (no speed change needed)",UVM_LOW)
      ep_state = EP_RECOVERY_IDLE;
    end
endtask

task ep_state_recovery_speed();
    ep_pvif.TxElecIdle  <= cfg.active_lane_mask;
    ep_tx_bcast_valid(0);
    ep_pvif.Rate        <= gen_to_rate_code(ep_target_gen);
    ep_active_gen         = ep_target_gen;

    recovery_speed.wait_for();
    repeat(4) @(posedge ep_pvif.PCLK);   // let PCLK settle at the new rate
    ep_pvif.TxElecIdle <= '0;

    `uvm_info("RX_LTSSM",
      $sformatf("Recovery.Speed done -> now running at Gen%0d -> Recovery.RcvrLock (re-lock)",
                 ep_active_gen), UVM_LOW)

    // Per diagram: Speed always loops back to RcvrLock to re-lock at the new speed
    ep_state = EP_RECOVERY_RCVRLOCK;
endtask

task ep_state_recovery_idle();
    repeat(8) begin
      @(posedge ep_pvif.PCLK);
      ep_tx_bcast_data({2'b01, 128'h0});
      ep_tx_bcast_valid(1);
    end
    @(posedge ep_pvif.PCLK);
    ep_tx_bcast_valid(0);

    wait(ep_os.size() > 0);
    recovery_idle_bar.wait_for();
    ep_os.delete();

    `uvm_info("RX_LTSSM",
      $sformatf("Recovery.Idle done -> L0 @ Gen%0d (final speed reached)", ep_active_gen), UVM_LOW)
    ep_state = EP_L0;
endtask

  // ---- RC_MODE ----
  task rc_state_detect_quiet();

     `uvm_info("TX_LTSSM","Entered DETECT_QUIET",UVM_LOW)

     rc_pvif.Rate  <= 2'b00;   // Gen1
     rc_active_gen  = 1;

     for(int lane = 0; lane < cfg.num_lanes; lane++)
     begin
        if(!cfg.active_lane_mask[lane]) continue;
        rc_pvif.TxElecIdle[lane] <= 1'b1;
        rc_pvif.TxDetectRx[lane] <= 1'b0;
     end

     rc_tx_bcast_valid(0);

     //-----------------------------------------------------------
     // Wait for: Detect Quiet Timer, OR any active lane's
     // Electrical Idle being broken (whichever comes first).
     //-----------------------------------------------------------

     fork

        begin
           rc_ltssm_timer(cfg.detect_quiet_timeout);
        end

        begin
           forever
           begin
              @(posedge rc_pvif.PCLK);
              for(int lane = 0; lane < cfg.num_lanes; lane++)
                 if(cfg.active_lane_mask[lane] && rc_pvif.RxElecIdle[lane] == 1'b0)
                    disable fork;
           end
        end

     join_any
     disable fork;

     `uvm_info("TX_LTSSM","Exit DETECT_QUIET -> DETECT_ACTIVE",UVM_LOW)
     rc_state = DETECT_ACTIVE;

  endtask

  // ---- EP_MODE ----
  task ep_state_detect_quiet();

     `uvm_info("RX_LTSSM","Entered DETECT_QUIET",UVM_LOW)

     ep_pvif.Rate  <= 2'b00;
     ep_active_gen  = 1;

     for(int lane = 0; lane < cfg.num_lanes; lane++)
     begin
        if(!cfg.active_lane_mask[lane]) continue;
        ep_pvif.TxElecIdle[lane] <= 1'b1;
        ep_pvif.TxDetectRx[lane] <= 1'b0;
     end

     ep_tx_bcast_valid(0);

     fork

        begin
           ep_ltssm_timer(cfg.detect_quiet_timeout);
        end

        begin
           forever
           begin
              @(posedge ep_pvif.PCLK);
              for(int lane = 0; lane < cfg.num_lanes; lane++)
                 if(cfg.active_lane_mask[lane] && ep_pvif.RxElecIdle[lane] == 1'b0)
                    disable fork;
           end
        end

     join_any
     disable fork;

     `uvm_info("RX_LTSSM","Exit DETECT_QUIET -> DETECT_ACTIVE",UVM_LOW)
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
            RECOVERY_RCVRLOCK     : rc_state_recovery_rcvrlock();
            RECOVERY_RCVRCFG      : rc_state_recovery_rcvrcfg();
            RECOVERY_SPEED        : rc_state_recovery_speed();
            RECOVERY_IDLE         : rc_state_recovery_idle();
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
            EP_RECOVERY_RCVRLOCK     : ep_state_recovery_rcvrlock();
            EP_RECOVERY_RCVRCFG      : ep_state_recovery_rcvrcfg();
            EP_RECOVERY_SPEED        : ep_state_recovery_speed();
            EP_RECOVERY_IDLE         : ep_state_recovery_idle();
          endcase
        end
      end

      default: `uvm_fatal("PCIe_MAC_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass

