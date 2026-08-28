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
  bit [127:0] rc_received_os_lane[`PCIE_NUM_LANES][$];
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
  bit [127:0] ep_os_lane[`PCIE_NUM_LANES][$];
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
  bit [7:0]   ep_negotiated_link_num = 8'h00;
  bit [7:0]   ep_negotiated_lane_num = 8'h00;
  bit [7:0]   rc_idle_to_rlock_transitioned = 8'h00;
  bit [7:0]   ep_idle_to_rlock_transitioned = 8'h00;


 bit          rc_directed_speed_change  = 1'b0;
  bit          rc_changed_speed_recovery = 1'b0;
  int unsigned rc_gen_on_recovery_entry  = 1;
  bit          rc_successful_speed_negotiation = 1'b0;
  bit          rc_recovery_idle_via_rcvrcfg_timeout = 1'b0;

  bit          ep_directed_speed_change  = 1'b0;
  bit          ep_changed_speed_recovery = 1'b0;
  int unsigned ep_gen_on_recovery_entry  = 1;
  bit          ep_successful_speed_negotiation = 1'b0;
  bit          ep_recovery_idle_via_rcvrcfg_timeout = 1'b0;

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
    RECOVERY_RCVRLOCK, RECOVERY_RCVRCFG, RECOVERY_SPEED, RECOVERY_IDLE,
    DISABLED,
    LOOPBACK_ENTRY, LOOPBACK_ACTIVE, LOOPBACK_EXIT,
    HOT_RESET
  } rc_ltssm_state_e;
  rc_ltssm_state_e rc_state;
  typedef enum {
    EP_DETECT_QUIET, EP_DETECT_ACTIVE, EP_POLLING_ACTIVE, EP_POLLING_COMPLIANCE,
    EP_POLLING_CONFIGURATION, EP_CONFIG_LINKNUM_START, EP_CONFIG_LINKNUM_ACCEPT,
    EP_CONFIG_LANNUM_WAIT, EP_CONFIG_LANENUM_ACCEPT, EP_CONFIG_COMPLETE,
    EP_CONFIG_IDLE, EP_L0,
    EP_RECOVERY_RCVRLOCK, EP_RECOVERY_RCVRCFG, EP_RECOVERY_SPEED, EP_RECOVERY_IDLE,
    EP_DISABLED,
    EP_LOOPBACK_ENTRY, EP_LOOPBACK_ACTIVE, EP_LOOPBACK_EXIT,
    EP_HOT_RESET
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
        polling_compilance.set_threshold(1);
        polling_configuration.set_threshold(1);
        config_link_start.set_threshold(1);
        config_link_accept.set_threshold(1);
        config_lane_wait.set_threshold(1);
        config_lane_accept.set_threshold(1);
        config_complete.set_threshold(1);
        config_idle.set_threshold(1);
        lo.set_threshold(2);

        recovery_rcvrlock.set_threshold(1);
        recovery_rcvrcfg.set_threshold(1);
        recovery_speed.set_threshold(1);
        recovery_idle_bar.set_threshold(1);

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
        polling_configuration.set_threshold(1);
        config_link_start.set_threshold(1);
        config_link_accept.set_threshold(1);
        config_lane_wait.set_threshold(1);
        config_lane_accept.set_threshold(1);
        config_complete.set_threshold(1);
        config_idle.set_threshold(1);

        recovery_rcvrlock.set_threshold(1);
        recovery_rcvrcfg.set_threshold(1);
        recovery_speed.set_threshold(1);
        recovery_idle_bar.set_threshold(1);

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
    // t.mac_tx_data is a queue-of-queues: outer index [i] = one distinct
    // TLP, inner index [j] = the DWs of that TLP. Previously this was
    // flattened straight into rc_received (single dimension) with no
    // record of where one TLP ended and the next began. When the driver's
    // TX loop in rc_state_l0() later drained rc_received it called
    // rc_add_stp_to_all_packets() exactly once per drain, stamping a
    // single STP (with a single length field) across whatever happened to
    // have piled up - which is fine for one TLP, but for back-to-back
    // TLPs (e.g. Multiple_Mem_Wr_Rd_3DW_test, where several TLPs got
    // queued up before the TX loop was scheduled - seen in sim as 1031 DW
    // "RC byte-striping" bursts) it wraps ALL of them under one bogus STP
    // instead of one STP per TLP. The EP-side MAC monitor un-framer
    // (PCIe_MAC_Monitor.sv, while(rc_r_data.size()>0) / ep_r_data loop)
    // walks the reassembled stream looking for one STP (4'hF marker) per
    // TLP and trusts that STP's length field to know how many DWs belong
    // to it, so a single oversized/garbage STP corrupts the parse and the
    // later TLPs never resolve into anything the EP receives.
    //
    // Fix: frame each TLP with its own STP right here, per row of
    // t.mac_tx_data, before it goes into the flattened rc_received queue,
    // so every TLP keeps its own correctly-sized STP no matter how many
    // TLPs get batched into a single rc_received drain cycle.
    foreach(t.mac_tx_data[i]) begin
      bit [31:0] rc_tlp_q[$];
      rc_tlp_q = t.mac_tx_data[i];
      if(rc_tlp_q.size() > 0) begin
        rc_add_stp_to_all_packets(rc_tlp_q);
        `uvm_info("MAC_TX_DRV",
          $sformatf("[%s] TLP[%0d] framed with own STP: %0d DWORDs (incl. STP)",
            tag, i, rc_tlp_q.size()), UVM_HIGH)
      end
      foreach(rc_tlp_q[j]) begin
        rc_received.push_back(rc_tlp_q[j]);
      end
    end
    rc_dllp_packet = t.dllp_tx_packet;
    foreach(rc_dllp_packet[i])
      `uvm_info("MAC_TX_DRV", $sformatf("[%s] RC_DLLP_MAC_TX %h %d DWORDs", tag, rc_dllp_packet[i], rc_dllp_packet.size()), UVM_HIGH)
    t.dllp_tx_packet.delete();
  endfunction

  function void write_port_f(Sequence_item t);
    rc_received_os_lane = t.os_t_lane;
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
    // Mirrors the RC-side fix in write_port_e(): t.mac_rx_data is a
    // queue-of-queues (one row per TLP). Frame each TLP with its own STP
    // here, per row, before flattening into the single-dimension
    // ep_received queue - otherwise back-to-back TLPs queued up before the
    // EP TX loop (ep_state_l0()) drains ep_received get wrapped under one
    // bogus whole-batch STP instead of one STP per TLP, and the RC-side
    // MAC monitor's un-framer (which expects one STP per TLP) fails to
    // resolve the later TLPs.
    foreach(t.mac_rx_data[i]) begin
      bit [31:0] ep_tlp_q[$];
      ep_tlp_q = t.mac_rx_data[i];
      if(ep_tlp_q.size() > 0) begin
        ep_add_stp_to_all_packets(ep_tlp_q);
        `uvm_info("MAC_RX_DRV",
          $sformatf("[%s] TLP[%0d] framed with own STP: %0d DWORDs (incl. STP)",
            tag, i, ep_tlp_q.size()), UVM_HIGH)
      end
      foreach(ep_tlp_q[j]) begin
        ep_received.push_back(ep_tlp_q[j]);
      end
    end
    ep_dllp_packet = t.dllp_packet;
    foreach(ep_dllp_packet[i])
      `uvm_info("MAC_RX_DRV", $sformatf("[%s] EP_DLLP_MAC %h %d DWORDs", tag, ep_dllp_packet[i], ep_dllp_packet.size()), UVM_HIGH)
  endfunction

  function void write_port_h(Sequence_item t);
    ep_os_lane = t.os_t_lane;
      `uvm_info("MAC_TX_DRV", $sformatf("ORDERED_SETS %0d DWORDs",ep_os.size()), UVM_HIGH)
    if(t.tlp_queue_t.size() > 0)
      ep_tlp_fifo.push_back(t.tlp_queue_t);
    if(t.dlp_rx_queue.size() > 0)
    ep_dllp_fifo.push_back(t.dlp_rx_queue);
    foreach(t.tlp_queue_t[i])
      `uvm_info("MAC_RX_DRV", $sformatf("[%s] Received from PMA DRIVER %0h %d DWORDs", tag, t.tlp_queue_t[i], t.tlp_queue_t.size()), UVM_HIGH)
  endfunction

 function bit parity_calc(
    input  length,
    input  sequence_number
);
    bit [22:0] parity_check;

    parity_check = {length, sequence_number};

    return ^parity_check;
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

  //-----------------------------------------------------------
  // PAD value for un-assigned Link/Lane numbers (spec: all-1s).
  //-----------------------------------------------------------
  localparam bit [7:0] PAD_VAL = 8'hFF;

  // tag_ts1() / tag_ts2() - single generic field-stamping function
  // used by every Configuration/Recovery substate that needs to
  // embed rate_id and/or Link/Lane numbers into a TS1 or TS2 base
  // Ordered Set. link_num/lane_num default to PAD so callers that
  // don't care about them (e.g. POLLING_ACTIVE, Recovery.RcvrLock)
  // can omit them entirely and behave exactly as before.
   function bit [127:0] tag_ts1(bit [127:0] base_ts, bit speed_change = 1'b0,
                                bit [7:0] link_num = PAD_VAL, bit [7:0] lane_num = PAD_VAL,
                                bit disable_link = 1'b0, bit loopback = 1'b0,
                                bit hot_reset = 1'b0);
    bit [127:0] ts = base_ts;
    ts[95:88]   = rate_id_byte(cfg.gen, speed_change);
    ts[111:104] = link_num;   // TODO: confirm TS1 Link Number byte offset
                               // against real PIPE/spec Symbol mapping
    ts[119:112] = lane_num;   // TODO: confirm TS1 Lane Number byte offset
    ts[80]      = hot_reset;      // Symbol 5 (Training Control), bit 0 = Hot Reset
    ts[81]      = disable_link;   // Symbol 5 (Training Control), bit 1 = Disable Link
    ts[82]      = loopback;       // Symbol 5 (Training Control), bit 2 = Loopback
    tag_ts1     = ts;
  endfunction
   
  function bit [127:0] tag_ts2(bit [127:0] base_ts, bit speed_change = 1'b0,
                                bit [7:0] link_num = PAD_VAL, bit [7:0] lane_num = PAD_VAL);
    bit [127:0] ts = base_ts;
    ts[95:88]   = rate_id_byte(cfg.gen, speed_change);
    ts[111:104] = link_num;   // TODO: confirm TS2 Link Number byte offset
    ts[119:112] = lane_num;   // TODO: confirm TS2 Lane Number byte offset
    tag_ts2     = ts;
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


bit [7:0]   rc_striped_lanes[`PCIE_NUM_LANES][$];
bit [129:0] rc_lane_word[`PCIE_NUM_LANES];

bit [129:0] rc_lane_word_q[`PCIE_NUM_LANES][$];// one queue entry per 16B block
localparam bit [22:0] RC_LANE_SEED[8] = '{
    23'h1DBFBC,  // Lane 0 mod 8
    23'h0607BB,  // Lane 1 mod 8
    23'h1EC760,  // Lane 2 mod 8
    23'h18C0DB,  // Lane 3 mod 8
    23'h010F12,  // Lane 4 mod 8
    23'h19CFC9,  // Lane 5 mod 8
    23'h0277CE,  // Lane 6 mod 8
    23'h1BB807    // Lane 7 mod 8
};

// Forces every lane's LFSR back to its RC_LANE_SEED[lane%8] reset value.
// (Drives the reset path inside rc_lane_scramble_byte() below, since the
// LFSR itself lives in that function's static storage.)
function void rc_lane_scr_reset();
    bit [7:0] dummy;
    for (int lane = 0; lane < `PCIE_NUM_LANES; lane++)
        dummy = rc_lane_scramble_byte(lane, dummy, 1'b1);
endfunction

// Scrambles a single byte on the given lane, advancing that lane's
// LFSR by 8 bits. lfsr[] is a function-local static array (same
// static-storage pattern as rc_d_s()'s lfsr above), sized by
// `PCIE_NUM_LANES` and lazily seeded from RC_LANE_SEED[lane%8] on
// first call (an assignment-pattern literal can't be used here since
// its element count would have to be hardcoded independently of the
// `PCIE_NUM_LANES macro). Free-runs from there; pass rst=1 (see
// rc_lane_scr_reset()) to force a lane back to its seed without
// scrambling a byte.

function bit [7:0] rc_lane_scramble_byte(input int lane, inout bit [7:0] data, input bit rst = 1'b0);
    static bit [22:0] lfsr[`PCIE_NUM_LANES];
    static bit        seeded = 1'b0;
    if (!seeded) begin
        for (int l = 0; l < `PCIE_NUM_LANES; l++)
            lfsr[l] = RC_LANE_SEED[l % 8];
        seeded = 1'b1;
    end
    if (rst) begin
        lfsr[lane] = RC_LANE_SEED[lane % 8];
        return data;
    end
    for (int i = 0; i < 8; i++) begin
        if (lfsr[lane][22]) lfsr[lane] = (lfsr[lane] << 1) ^ polynomial;
        else                lfsr[lane] = (lfsr[lane] << 1);
        data[i] = lfsr[lane][22] ^ data[i];
    end
    return data;
endfunction

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

    for (int lane = 0; lane < `PCIE_NUM_LANES; lane++) begin
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
                bit [7:0] raw_byte;
                raw_byte = (idx < rc_striped_lanes[lane].size()) ? rc_striped_lanes[lane][idx] : 8'h00;
                payload[127-r*8 -: 8] = rc_lane_scramble_byte(lane, raw_byte);
            end
            rc_lane_word_q[lane].push_back({2'b10, payload});
            `uvm_info("TX_BYTE_STRIPE",
                $sformatf("Block[%0d] Lane[%0d] = %033h", blk, lane, {2'b10, payload}),
                UVM_LOW)
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
       //  if(blk != 0) @(posedge rc_pvif.PCLK);
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
    sequence_number = pkt_q[0][12:0];
      f_p = parity_calc(length, sequence_number);
      pkt_len = pkt_q.size()+1;
      stp_pkt = {
                  pkt_len[3:0],
                  4'hF,
                  f_p,
                  pkt_len[10:4],
                  fcrc[3:0],
                  sequence_number[3:0],
                  sequence_number[11:4]
                };
     pkt_q.push_front(stp_pkt);

   
   /* for(i = 0; i < pkt_q.size(); ) begin
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
    end*/
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
 function automatic bit rc_os_all_lanes_ready(int unsigned min_count = 1);
     rc_os_all_lanes_ready = 1'b1;
     for (int lane = 0; lane < cfg.num_lanes; lane++)
        if (rc_received_os_lane[lane].size() < min_count)
           rc_os_all_lanes_ready = 1'b0;
  endfunction

  function automatic bit ep_os_all_lanes_ready(int unsigned min_count = 1);
     ep_os_all_lanes_ready = 1'b1;
     for (int lane = 0; lane < cfg.num_lanes; lane++)
        if (ep_os_lane[lane].size() < min_count)
           ep_os_all_lanes_ready = 1'b0;
  endfunction

  function automatic void rc_os_lane_delete();
     for (int lane = 0; lane < cfg.num_lanes; lane++)
        rc_received_os_lane[lane].delete();
  endfunction

  function automatic void ep_os_lane_delete();
     for (int lane = 0; lane < cfg.num_lanes; lane++)
        ep_os_lane[lane].delete();
  endfunction


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
bit [129:0] ep_lane_word[`PCIE_NUM_LANES];
bit [7:0] ep_striped_lanes[`PCIE_NUM_LANES][$];

bit [129:0] ep_lane_word_q[`PCIE_NUM_LANES][$];   // one queue entry per 16B block

//-----------------------------------------------------------
// Per-lane scrambler for the EP side - mirrors the RC-side
// scrambler above. Same seed table (PCIe Base Spec: lane seed
// is a function of lane number mod 8), independent LFSR state
// per lane, free-runs across calls unless explicitly reset.
//-----------------------------------------------------------
localparam bit [22:0] EP_LANE_SEED[8] = '{
    23'h1DBFBC,  // Lane 0 mod 8
    23'h0607BB,  // Lane 1 mod 8
    23'h1EC760,  // Lane 2 mod 8
    23'h18C0DB,  // Lane 3 mod 8
    23'h010F12,  // Lane 4 mod 8
    23'h19CFC9,  // Lane 5 mod 8
    23'h0277CE,  // Lane 6 mod 8
    23'h1BB807    // Lane 7 mod 8
};

// Forces every lane's LFSR back to its EP_LANE_SEED[lane%8] reset value.
// (Drives the reset path inside ep_lane_scramble_byte() below, since the
// LFSR itself lives in that function's static storage.)
function void ep_lane_scr_reset();
    bit [7:0] dummy;
    for (int lane = 0; lane < `PCIE_NUM_LANES; lane++)
        dummy = ep_lane_scramble_byte(lane, dummy, 1'b1);
endfunction

// Scrambles a single byte on the given lane, advancing that lane's
// LFSR by 8 bits. lfsr[] is a function-local static array (same
// static-storage pattern as ep_d_s()'s lfsr above), sized by
// `PCIE_NUM_LANES` and lazily seeded from EP_LANE_SEED[lane%8] on
// first call (an assignment-pattern literal can't be used here since
// its element count would have to be hardcoded independently of the
// `PCIE_NUM_LANES macro). Free-runs from there; pass rst=1 (see
// ep_lane_scr_reset()) to force a lane back to its seed without
// scrambling a byte.
function bit [7:0] ep_lane_scramble_byte(input int lane, inout bit [7:0] data, input bit rst = 1'b0);
    static bit [22:0] lfsr[`PCIE_NUM_LANES];
    static bit        seeded = 1'b0;
    if (!seeded) begin
        for (int l = 0; l < `PCIE_NUM_LANES; l++)
            lfsr[l] = EP_LANE_SEED[l % 8];
        seeded = 1'b1;
    end
    if (rst) begin
        lfsr[lane] = EP_LANE_SEED[lane % 8];
        return data;
    end
    for (int i = 0; i < 8; i++) begin
        if (lfsr[lane][22]) lfsr[lane] = (lfsr[lane] << 1) ^ polynomial;
        else                lfsr[lane] = (lfsr[lane] << 1);
        data[i] = lfsr[lane][22] ^ data[i];
    end
    return data;
endfunction
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

    for (int lane = 0; lane < `PCIE_NUM_LANES; lane++) begin
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
                 bit [7:0] raw_byte;
                raw_byte = (idx < ep_striped_lanes[lane].size()) ? ep_striped_lanes[lane][idx] : 8'h00;
                payload[127-r*8 -: 8] = ep_lane_scramble_byte(lane, raw_byte);
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
     sequence_number = pkt_q[0][12:0];
      f_p = parity_calc(length, sequence_number);
      pkt_len = pkt_q.size()+1;
      stp_pkt = {
                  pkt_len[3:0],
                  4'hF,
                  f_p,
                  pkt_len[10:4],
                  fcrc[3:0],
                  sequence_number[3:0],
                  sequence_number[11:4]
                };
     pkt_q.push_front(stp_pkt);
/*
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
    end*/
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
     rc_os_lane_delete();

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
           wait(rc_os_all_lanes_ready(7));
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
        rc_os_lane_delete();
        rc_state = POLLING_COMPLIANCE;
        return;
     end

     if(barrier_met)
     begin

        rc_partner_rate_id = rc_received_os_lane[0][0][95:88];
        rc_negotiated_gen  = (cfg.gen < decode_max_gen(rc_partner_rate_id)) ?
                               cfg.gen : decode_max_gen(rc_partner_rate_id);

        `uvm_info("TX_LTSSM",
          $sformatf("Rate negotiation: own Gen%0d, partner rate_id=%08b (max Gen%0d) -> negotiated Gen%0d",
                     cfg.gen, rc_partner_rate_id, decode_max_gen(rc_partner_rate_id), rc_negotiated_gen),
          UVM_LOW)

        `uvm_info("TX_LTSSM",">=1024 TS1 sent, 8 consecutive matching TS received -> POLLING_CONFIGURATION",UVM_LOW)
        rc_os_lane_delete();
        rc_state = POLLING_CONFIGURATION;
        return;

     end

     // 24ms timeout without meeting the fast-path barrier - fall
     // back to Compliance (conservative default; see chat notes on
     // condition (i)/(ii) predetermined-lane-subset nuance which
     // needs the real Symbol-5 bit decode to implement exactly).
     `uvm_info("TX_LTSSM","24ms timeout without meeting fast-path barrier -> POLLING_COMPLIANCE",UVM_LOW)
     rc_os_lane_delete();
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
     ep_os_lane_delete();

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
           wait(ep_os_all_lanes_ready(9));
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
        ep_os_lane_delete();
        ep_state = EP_POLLING_COMPLIANCE;
        return;
     end

     if(barrier_met)
     begin

        ep_partner_rate_id = ep_os_lane[0][0][95:88];
        ep_negotiated_gen  = (cfg.gen < decode_max_gen(ep_partner_rate_id)) ?
                               cfg.gen : decode_max_gen(ep_partner_rate_id);

        `uvm_info("RX_LTSSM",
          $sformatf("Rate negotiation: own Gen%0d, partner rate_id=%08b (max Gen%0d) -> negotiated Gen%0d",
                     cfg.gen, ep_partner_rate_id, decode_max_gen(ep_partner_rate_id), ep_negotiated_gen),
          UVM_LOW)

        `uvm_info("RX_LTSSM",">=1024 TS1 sent, 8 consecutive matching TS received -> POLLING_CONFIGURATION",UVM_LOW)
        ep_os_lane_delete();
        ep_state = EP_POLLING_CONFIGURATION;
        return;

     end

     `uvm_info("RX_LTSSM","24ms timeout without meeting fast-path barrier -> POLLING_COMPLIANCE",UVM_LOW)
     ep_os_lane_delete();
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
      rc_os_lane_delete();
      rc_state = POLLING_CONFIGURATION;
    endtask

  // ---- EP_MODE ----
  task ep_state_polling_compliance();
      `uvm_info("RX_LTSSM","POLLING_COMPLIANCE – waiting compliance_exit",UVM_LOW)
     // compliance_exit.wait_trigger();
        wait(ep_os_all_lanes_ready(1));
      polling_compilance.wait_for();
       `uvm_info("RX_LTSSM",$sformatf("Compliance ep_os %p ep_size = %d",ep_os,ep_os.size()),UVM_LOW)
      ep_os_lane_delete();
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
     rc_os_lane_delete();

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
           wait(rc_os_all_lanes_ready(7));
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
        rc_os_lane_delete();
        rc_state = CONFIG_LINKNUM_START;
        return;
     end

     // 48ms timeout without meeting the fast-path barrier -> Detect
     `uvm_info("TX_LTSSM","48ms timeout without meeting fast-path barrier -> DETECT",UVM_LOW)
     rc_os_lane_delete();
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
     ep_os_lane_delete();

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

           wait(ep_os_all_lanes_ready(15));
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
        ep_os_lane_delete();
        ep_state = EP_CONFIG_LINKNUM_START;
        return;
     end

     // 48ms timeout without meeting the fast-path barrier -> Detect
     `uvm_info("TX_LTSSM","EP: 48ms timeout without meeting fast-path barrier -> DETECT",UVM_LOW)
     ep_os_lane_delete();
     ep_state = EP_DETECT_QUIET;

  endtask


  // ---- RC_MODE ----
    task rc_state_config_linknum_start();

      bit barrier_met;
      bit timeout_occured;
 if(cfg.link_ctrl_disable_link)
      begin
         `uvm_info("TX_LTSSM","Link Disable bit set prior to entry -> immediate DISABLED",UVM_LOW)
         rc_state = DISABLED;
         return;
      end

      //-----------------------------------------------------------
      // Directed exit: Enter Loopback -> Loopback.Entry (RC = master).
      //-----------------------------------------------------------
      if(cfg.link_ctrl_enter_loopback)
      begin
         `uvm_info("TX_LTSSM","Enter Loopback set prior to entry -> immediate LOOPBACK_ENTRY",UVM_LOW)
         rc_state = LOOPBACK_ENTRY;
         return;
      end

      // x1 single-link simplification: Downstream selects Link 0,
      // Lane number stays PAD until LINKNUM_ACCEPT assigns it.
      // TODO(multi-lane): real Link-number selection groups Lanes
      // per spec 4.2.6.3.1.1 instead of hardcoding 0.
      rc_negotiated_link_num = 8'h00;
      barrier_met            = 0;
      timeout_occured        = 0;

      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LINKNUM_START - broadcasting Link=%0h, Lane=PAD",rc_negotiated_link_num),UVM_LOW)

      rc_os_lane_delete();

      fork
         begin
            repeat(2) begin
               @(posedge rc_pvif.PCLK);
               rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_negotiated_link_num)));
            end
              @(posedge rc_pvif.PCLK);
	      rc_tx_bcast_valid(0);

	        if(cfg.link_ctrl_disable_link) begin
                 disable fork;
              end

              if(cfg.link_ctrl_enter_loopback) begin
                 disable fork;
              end

         end

         begin
            wait(rc_os_all_lanes_ready(1));   // TODO: exact 2-consecutive
                                                // non-PAD Link match check,
                                                // not just queue depth
            config_link_start.wait_for();
            barrier_met = 1;
            disable fork;
         end

         begin
            rc_ltssm_timer(cfg.config_linknum_start_timeout);
            timeout_occured = 1;
            disable fork;
         end
      join
       
      if(cfg.link_ctrl_disable_link) begin
         `uvm_info("TX_LTSSM","Link Disable bit set -> DISABLED",UVM_LOW)
         rc_os_lane_delete();
         rc_state = DISABLED;
         return;
      end

      if(cfg.link_ctrl_enter_loopback) begin
         `uvm_info("TX_LTSSM","Enter Loopback set -> LOOPBACK_ENTRY",UVM_LOW)
         rc_os_lane_delete();
         rc_state = LOOPBACK_ENTRY;
         return;
      end


      if(barrier_met) begin
         rc_link_num = rc_negotiated_link_num;
         `uvm_info("TX_LTSSM",$sformatf("CONFIG_LINKNUM_START -> negotiating | rc_link_num=%0h",rc_link_num),UVM_LOW)
         `uvm_info("TX_LTSSM","Link num broadcast done -> CONFIG_LINKNUM_ACCEPT",UVM_LOW)
         rc_os_lane_delete();
         rc_state = CONFIG_LINKNUM_ACCEPT;
         return;
      end

      `uvm_info("TX_LTSSM","24ms timeout in CONFIG_LINKNUM_START -> DETECT_QUIET",UVM_LOW)
      rc_os_lane_delete();
      rc_state = DETECT_QUIET;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_linknum_start();

      bit barrier_met;
      bit timeout_occured;
 if(cfg.link_ctrl_disable_link)
      begin
         `uvm_info("RX_LTSSM","Link Disable bit set prior to entry -> immediate DISABLED",UVM_LOW)
         ep_state = EP_DISABLED;
         return;
      end

      //-----------------------------------------------------------
      // Directed exit: Enter Loopback -> Loopback.Entry (EP = slave).
      //-----------------------------------------------------------
      if(cfg.link_ctrl_enter_loopback)
      begin
         `uvm_info("RX_LTSSM","Enter Loopback set prior to entry -> immediate LOOPBACK_ENTRY",UVM_LOW)
         ep_state = EP_LOOPBACK_ENTRY;
         return;
      end


      // Upstream mirrors whatever non-PAD Link number RC advertises;
      // starts off sending PAD/PAD until it reflects RC's value back.
      ep_negotiated_link_num = 8'h00;
      barrier_met            = 0;
      timeout_occured        = 0;

      `uvm_info("RX_LTSSM","CONFIG_LINKNUM_START - waiting for Downstream Link num",UVM_LOW)

      ep_os_lane_delete();

      fork
         begin
            repeat(2) begin
               @(posedge ep_pvif.PCLK);
               ep_drive_os(tag_ts1(ep_TS1));   // PAD/PAD until Link num is learned
            end
              @(posedge ep_pvif.PCLK);
	      ep_tx_bcast_valid(0);
	          
	       if(cfg.link_ctrl_disable_link) begin
                 disable fork;
              end

              if(cfg.link_ctrl_enter_loopback) begin
                 disable fork;
              end

         end

         begin
            wait(ep_os_all_lanes_ready(1));   // TODO: exact 2-consecutive non-PAD
                                       // Link match check
            config_link_start.wait_for();
            barrier_met = 1;
            disable fork;
         end

         begin
            ep_ltssm_timer(cfg.config_linknum_start_timeout);
            timeout_occured = 1;
            disable fork;
         end
      join
 
      if(cfg.link_ctrl_disable_link) begin
         `uvm_info("RX_LTSSM","Link Disable bit set -> DISABLED",UVM_LOW)
         ep_os_lane_delete();
         ep_state = EP_DISABLED;
         return;
      end

      if(cfg.link_ctrl_enter_loopback) begin
         `uvm_info("RX_LTSSM","Enter Loopback set -> LOOPBACK_ENTRY",UVM_LOW)
         ep_os_lane_delete();
         ep_state = EP_LOOPBACK_ENTRY;
         return;
      end

      if(barrier_met) begin
         ep_link_num = ep_negotiated_link_num;
         `uvm_info("RX_LTSSM",$sformatf("CONFIG_LINKNUM_START -> negotiating | ep_link_num=%0h",ep_link_num),UVM_LOW)
         `uvm_info("RX_LTSSM","Link num broadcast done -> CONFIG_LINKNUM_ACCEPT",UVM_LOW)
         ep_os_lane_delete();
         ep_state = EP_CONFIG_LINKNUM_ACCEPT;
         return;
      end

      `uvm_info("RX_LTSSM","24ms timeout in CONFIG_LINKNUM_START -> DETECT_QUIET",UVM_LOW)
      ep_os_lane_delete();
      ep_state = EP_DETECT_QUIET;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_linknum_accept();

      bit barrier_met;
      bit timeout_occured;

      // x1 simplification: sequential numbering 0..n-1 on the Lanes
      // that share the confirmed Link -> single Lane gets Lane 0.
      // TODO(multi-lane): real sequential assignment per 4.2.6.3.2.1.
      rc_negotiated_lane_num = 8'h00;
      barrier_met            = 0;
      timeout_occured        = 0;

      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LINKNUM_ACCEPT - assigning Link=%0h Lane=%0h",rc_negotiated_link_num,rc_negotiated_lane_num),UVM_LOW)

      rc_os_lane_delete();

      fork
         begin
            repeat(2) begin
               @(posedge rc_pvif.PCLK);
               rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_negotiated_link_num), .lane_num(rc_negotiated_lane_num)));
            end
              @(posedge rc_pvif.PCLK);
               rc_tx_bcast_valid(0);
         end

         begin
            wait(rc_os_all_lanes_ready(1));   // TODO: exact 2-consecutive
                                                // Link+Lane match check
            config_link_accept.wait_for();
            barrier_met = 1;
            disable fork;
         end

         begin
            rc_ltssm_timer(cfg.config_linknum_accept_timeout);
            timeout_occured = 1;
            disable fork;
         end
      join


      if(barrier_met) begin
         rc_lane_num = rc_negotiated_lane_num;
         `uvm_info("TX_LTSSM",$sformatf("CONFIG_LINKNUM_ACCEPT -> confirmed | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num,rc_lane_num),UVM_LOW)
         rc_os_lane_delete();
         `uvm_info("TX_LTSSM","Link-num & Lane_num accepted -> CONFIG_LANENUM_WAIT",UVM_LOW)
         rc_state = CONFIG_LANNUM_WAIT;
         return;
      end

      `uvm_info("TX_LTSSM","2ms timeout in CONFIG_LINKNUM_ACCEPT -> DETECT_QUIET",UVM_LOW)
      rc_os_lane_delete();
      rc_state = DETECT_QUIET;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_linknum_accept();

      bit barrier_met;
      bit timeout_occured;

      // Mirrors RC's assigned Lane number where possible (x1: Lane 0).
      // TODO(multi-lane): match-or-reverse assignment per 4.2.6.3.2.2.
      ep_negotiated_lane_num = 8'h00;
      barrier_met            = 0;
      timeout_occured        = 0;

      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LINKNUM_ACCEPT - assigning Link=%0h Lane=%0h",ep_negotiated_link_num,ep_negotiated_lane_num),UVM_LOW)

      ep_os_lane_delete();

      fork
         begin
            repeat(2) begin
               @(posedge ep_pvif.PCLK);
               ep_drive_os(tag_ts1(ep_TS1, .link_num(ep_negotiated_link_num), .lane_num(ep_negotiated_lane_num)));
            end
              @(posedge ep_pvif.PCLK);
               ep_tx_bcast_valid(0);
         end

         begin
            wait(ep_os_all_lanes_ready(1));   // TODO: exact 2-consecutive Link+Lane match
            config_link_accept.wait_for();
            barrier_met = 1;
            disable fork;
         end

         begin
            ep_ltssm_timer(cfg.config_linknum_accept_timeout);
            timeout_occured = 1;
            disable fork;
         end
      join


      if(barrier_met) begin
         ep_lane_num = ep_negotiated_lane_num;
         `uvm_info("RX_LTSSM",$sformatf("CONFIG_LINKNUM_ACCEPT -> confirmed | ep_link_num=%0h, ep_lane_num=%0h",ep_link_num,ep_lane_num),UVM_LOW)
         ep_os_lane_delete();
         `uvm_info("RX_LTSSM","Link-num accepted -> CONFIG_LANENUM_WAIT",UVM_LOW)
         ep_state = EP_CONFIG_LANNUM_WAIT;
         return;
      end

      `uvm_info("RX_LTSSM","2ms timeout in CONFIG_LINKNUM_ACCEPT -> DETECT_QUIET",UVM_LOW)
      ep_os_lane_delete();
      ep_state = EP_DETECT_QUIET;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_lanenum_wait();

      bit [7:0] rc_lane_num_on_entry;
      bit       barrier_met;
      bit       timeout_occured;

      // Exit condition requires the assigned Lane number to CHANGE
      // relative to whatever it was on entry into this substate
      // (spec 4.2.6.3.4.1) - latch it before doing anything else.
      rc_lane_num_on_entry = rc_negotiated_lane_num;

      barrier_met     = 0;
      timeout_occured = 0;
      rc_os_lane_delete();

      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LANENUM_WAIT - Lane on entry=%0h",rc_lane_num_on_entry),UVM_LOW)

      fork
         begin
            repeat(2) begin
               @(posedge rc_pvif.PCLK);
               rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_negotiated_link_num), .lane_num(rc_negotiated_lane_num)));
            end
              @(posedge rc_pvif.PCLK);
               rc_tx_bcast_valid(0);
         end

         begin
            // TODO: real check per 4.2.6.3.4.1 - (a) 2 consecutive TS1
            // w/ Lane num != rc_lane_num_on_entry AND not all Link
            // nums PAD, OR (b) 2 consecutive TS1 on all Lanes matching
            // exactly what's transmitted. Downstream watches TS1 only.
            wait(rc_os_all_lanes_ready(1));
            config_lane_wait.wait_for();
            barrier_met = 1;
            disable fork;
         end

         begin
            rc_ltssm_timer(cfg.config_lanenum_wait_timeout);   // TODO: add 2ms timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      rc_link_num = rc_negotiated_link_num;
      rc_lane_num = rc_negotiated_lane_num;

      if(barrier_met) begin
         `uvm_info("TX_LTSSM",$sformatf("CONFIG_LANENUM_WAIT -> negotiating | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num,rc_lane_num),UVM_LOW)
         rc_os_lane_delete();
         `uvm_info("TX_LTSSM","Lane numbers rc_received -> CONFIG_LANENUM_ACCEPT",UVM_LOW)
         rc_state = CONFIG_LANENUM_ACCEPT;
         return;
      end

      // 2ms timeout, or all-Lanes-PAD exit -> Detect
      `uvm_info("TX_LTSSM","2ms timeout / all-PAD in CONFIG_LANENUM_WAIT -> DETECT_QUIET",UVM_LOW)
      rc_os_lane_delete();
      rc_state = DETECT_QUIET;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_lanenum_wait();

      bit [7:0] ep_lane_num_on_entry;
      bit       barrier_met;
      bit       timeout_occured;

      ep_lane_num_on_entry = ep_negotiated_lane_num;

      barrier_met     = 0;
      timeout_occured = 0;
      ep_os_lane_delete();

      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LANENUM_WAIT - Lane on entry=%0h",ep_lane_num_on_entry),UVM_LOW)

      fork
         begin
            repeat(2) begin
               @(posedge ep_pvif.PCLK);
               ep_drive_os(tag_ts1(ep_TS1, .link_num(ep_negotiated_link_num), .lane_num(ep_negotiated_lane_num)));
            end
               @(posedge ep_pvif.PCLK);
               ep_tx_bcast_valid(0);
         end

         begin
            // TODO: real check per 4.2.6.3.4.2 - Upstream has TWO
            // independent exits: (a) 2 consecutive TS1 w/ Lane num
            // != ep_lane_num_on_entry AND not all Link nums PAD, OR
            // (b) ANY Lane receives 2 consecutive TS2 (no lane-num-
            // change precondition on this branch). Needs ep_os_lane[0] to
            // disambiguate TS1 vs TS2 - currently it does not.
            wait(ep_os_all_lanes_ready(1));
            config_lane_wait.wait_for();
            barrier_met = 1;
            disable fork;
         end

         begin
            ep_ltssm_timer(cfg.config_lanenum_wait_timeout);   // TODO: add 2ms timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      ep_link_num = ep_negotiated_link_num;
      ep_lane_num = ep_negotiated_lane_num;

      if(barrier_met) begin
         `uvm_info("RX_LTSSM",$sformatf("CONFIG_LANENUM_WAIT -> negotiating | ep_link_num=%0h, ep_lane_num=%0h",ep_link_num,ep_lane_num),UVM_LOW)
         ep_os_lane_delete();
         `uvm_info("RX_LTSSM","Lane broadcast done -> CONFIG_LANENUM_ACCEPT",UVM_LOW)
         ep_state = EP_CONFIG_LANENUM_ACCEPT;
         return;
      end

      `uvm_info("RX_LTSSM","2ms timeout / all-PAD in CONFIG_LANENUM_WAIT -> DETECT_QUIET",UVM_LOW)
      ep_os_lane_delete();
      ep_state = EP_DETECT_QUIET;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_lanenum_accept();

      bit full_match;
      bit timeout_occured;

      `uvm_info("TX_LTSSM",$sformatf("CONFIG_LANENUM_ACCEPT - confirming Link=%0h Lane=%0h",rc_negotiated_link_num,rc_negotiated_lane_num),UVM_LOW)

      full_match      = 0;
      timeout_occured = 0;
      rc_os_lane_delete();

      fork
         begin
            repeat(2) begin
               @(posedge rc_pvif.PCLK);
               rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_negotiated_link_num), .lane_num(rc_negotiated_lane_num)));
            end
               @(posedge rc_pvif.PCLK);
                rc_tx_bcast_valid(0);
         end

         begin
            // TODO: real check per 4.2.6.3.3.1 - 2 consecutive TS1
            // w/ non-PAD Link+Lane matching ALL transmitted values
            // (or reversed Lane0<->Lane(n-1) if reversal supported)
            // -> Configuration.Complete. Downstream watches TS1.
            // x1 simplification: subset-match branch collapses into
            // full_match/no-match since a "subset" of 1 Lane is the
            // same as full or none.
            wait(rc_os_all_lanes_ready(1));
            config_lane_accept.wait_for();
            full_match = 1;
            disable fork;
         end

         begin
            rc_ltssm_timer(cfg.config_lanenum_accept_timeout);   // TODO: add 2ms timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      rc_tx_bcast_valid(0);
      rc_link_num = rc_negotiated_link_num;
      rc_lane_num = rc_negotiated_lane_num;

      if(full_match) begin
         `uvm_info("TX_LTSSM",$sformatf("CONFIG_LANENUM_ACCEPT -> confirmed | rc_link_num=%0h, rc_lane_num=%0h",rc_link_num,rc_lane_num),UVM_LOW)
         rc_os_lane_delete();
         `uvm_info("TX_LTSSM","Lane-num accepted -> CONFIG_COMPLETE",UVM_LOW)
         rc_state = CONFIG_COMPLETE;
         return;
      end

      `uvm_info("TX_LTSSM","No Link configurable / all-PAD in CONFIG_LANENUM_ACCEPT -> DETECT_QUIET",UVM_LOW)
      rc_os_lane_delete();
      rc_state = DETECT_QUIET;
    endtask

  // ---- EP_MODE ----
  task ep_state_config_lanenum_accept();

      bit full_match;
      bit timeout_occured;

      `uvm_info("RX_LTSSM",$sformatf("CONFIG_LANENUM_ACCEPT - confirming Link=%0h Lane=%0h",ep_negotiated_link_num,ep_negotiated_lane_num),UVM_LOW)

      full_match      = 0;
      timeout_occured = 0;
      ep_os_lane_delete();

      fork
         begin
            repeat(2) begin
               @(posedge ep_pvif.PCLK);
               ep_drive_os(tag_ts1(ep_TS1, .link_num(ep_negotiated_link_num), .lane_num(ep_negotiated_lane_num)));
            end
               @(posedge ep_pvif.PCLK);
               ep_tx_bcast_valid(0);
         end

         begin
            // TODO: real check per 4.2.6.3.3.2 - Upstream watches for
            // TS2 (not TS1): 2 consecutive TS2 w/ non-PAD Link+Lane
            // matching ALL transmitted values -> Configuration.Complete.
            // Needs ep_os_lane[0] to disambiguate TS1 vs TS2.
            wait(ep_os_all_lanes_ready(1));
            config_lane_accept.wait_for();
            full_match = 1;
            disable fork;
         end

         begin
            ep_ltssm_timer(cfg.config_lanenum_accept_timeout);   // TODO: add 2ms timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      ep_link_num = ep_negotiated_link_num;
      ep_lane_num = ep_negotiated_lane_num;

      if(full_match) begin
         `uvm_info("RX_LTSSM",$sformatf("CONFIG_LANENUM_ACCEPT -> confirmed | ep_link_num=%0h, ep_lane_num=%0h",ep_link_num,ep_lane_num),UVM_LOW)
         ep_os_lane_delete();
         `uvm_info("RX_LTSSM","Lane-num accepted -> CONFIG_COMPLETE",UVM_LOW)
         ep_state = EP_CONFIG_COMPLETE;
         return;
      end

      `uvm_info("RX_LTSSM","No Link configurable / all-PAD in CONFIG_LANENUM_ACCEPT -> DETECT_QUIET",UVM_LOW)
      ep_os_lane_delete();
      ep_state = EP_DETECT_QUIET;
    endtask

  // ---- RC_MODE ----
  task rc_state_config_complete();

      bit          idle_ready;
      bit          timeout_occured;
      int unsigned rc_ts2_sent_since_first_rx;
      bit          rc_first_ts2_rx_seen;

      `uvm_info("TX_LTSSM",$sformatf("Entered CONFIG_COMPLETE (advertising Gen%0d, Link=%0h Lane=%0h)",cfg.gen,rc_negotiated_link_num,rc_negotiated_lane_num),UVM_LOW)

      idle_ready                  = 0;
      timeout_occured             = 0;
      rc_ts2_sent_since_first_rx  = 0;
      rc_first_ts2_rx_seen        = 0;
      rc_os_lane_delete();

      fork
         //-----------------------------------------------------
         // TX: switch to TS2 (not TS1) with Link/Lane matching
         // the received TS1 numbers, per 4.2.6.3.5.1.
         //-----------------------------------------------------
         begin
            repeat(16) begin
               @(posedge rc_pvif.PCLK);
               rc_drive_os(tag_ts2(TS2, .link_num(rc_negotiated_link_num), .lane_num(rc_negotiated_lane_num)));
               if(rc_first_ts2_rx_seen)
                  rc_ts2_sent_since_first_rx++;
            end
               @(posedge rc_pvif.PCLK);
               rc_tx_bcast_valid(0);
         end

         //-----------------------------------------------------
         // RX: 8 consecutive matching TS2 (Lane/Link non-PAD,
         // identical rate id) AND >=16 TS2 sent after the first
         // TS2 is received back.
         //-----------------------------------------------------
         begin
            wait(rc_os_all_lanes_ready(7));   // TODO: real 8-consecutive
                                                // match check (Lane/Link +
                                                // rate id incl. upconfigure
                                                // bit), not just queue depth
            `uvm_info("MAC_TX_DRV",$sformatf("wait_completed RC_ORDERED_SETS %0d DWORDs",rc_received_os_lane[0].size()),UVM_LOW)

            config_complete.wait_for();
            idle_ready = 1;
            disable fork;
         end

         begin
            rc_ltssm_timer(cfg.config_complete_timeout);   // TODO: add 2ms timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      rc_os_lane_delete();

      if(idle_ready) begin
         `uvm_info("TX_LTSSM","8x consecutive TS2 match + 16 sent-after-first -> CONFIG_IDLE",UVM_LOW)
         rc_state = CONFIG_IDLE;
         return;
      end

      // 2ms timeout - branch on current data rate per 4.2.6.3.5.1.
      if(cfg.gen == 1 || cfg.gen == 2) begin
         `uvm_info("TX_LTSSM","2ms timeout at Gen1/Gen2 -> DETECT_QUIET",UVM_LOW)
         rc_state = DETECT_QUIET;
      end
      else if(cfg.gen == 3 && rc_idle_to_rlock_transitioned < 8'hFF) begin
         `uvm_info("TX_LTSSM","2ms timeout, Gen3, idle_to_rlock_transitioned<FFh -> CONFIG_IDLE",UVM_LOW)
         rc_state = CONFIG_IDLE;
      end
      else begin
         `uvm_info("TX_LTSSM","2ms timeout, fallback -> DETECT_QUIET",UVM_LOW)
         rc_state = DETECT_QUIET;
      end
  endtask

  // ---- EP_MODE ----
  task ep_state_config_complete();

      bit          idle_ready;
      bit          timeout_occured;
      int unsigned ep_ts2_sent_since_first_rx;
      bit          ep_first_ts2_rx_seen;

      `uvm_info("RX_LTSSM",$sformatf("Entered CONFIG_COMPLETE (advertising Gen%0d, Link=%0h Lane=%0h)",cfg.gen,ep_negotiated_link_num,ep_negotiated_lane_num),UVM_LOW)

      idle_ready                  = 0;
      timeout_occured             = 0;
      ep_ts2_sent_since_first_rx  = 0;
      ep_first_ts2_rx_seen        = 0;
      ep_os_lane_delete();

      fork
         //-----------------------------------------------------
         // TX: Upstream matches received TS2 Link/Lane numbers
         // (not received TS1), per 4.2.6.3.5.2.
         //-----------------------------------------------------
         begin
            repeat(8) begin
               @(posedge ep_pvif.PCLK);
               ep_drive_os(tag_ts2(TS2, .link_num(ep_negotiated_link_num), .lane_num(ep_negotiated_lane_num)));
               if(ep_first_ts2_rx_seen)
                  ep_ts2_sent_since_first_rx++;
            end
               @(posedge ep_pvif.PCLK);
               ep_tx_bcast_valid(0);
         end

         begin

            wait(ep_os_all_lanes_ready(15));   // TODO: real 8-consecutive match check
            config_complete.wait_for();
            idle_ready = 1;
            disable fork;
         end

         begin
            ep_ltssm_timer(cfg.config_complete_timeout);   // TODO: add 2ms timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      ep_os_lane_delete();

      if(idle_ready) begin
         `uvm_info("RX_LTSSM","8x consecutive TS2 match + 16 sent-after-first -> CONFIG_IDLE",UVM_LOW)
         ep_state = EP_CONFIG_IDLE;
         return;
      end

      if(cfg.gen == 1 || cfg.gen == 2) begin
         `uvm_info("RX_LTSSM","2ms timeout at Gen1/Gen2 -> DETECT_QUIET",UVM_LOW)
         ep_state = EP_DETECT_QUIET;
      end
      else if(cfg.gen == 3 && ep_idle_to_rlock_transitioned < 8'hFF) begin
         `uvm_info("RX_LTSSM","2ms timeout, Gen3, idle_to_rlock_transitioned<FFh -> CONFIG_IDLE",UVM_LOW)
         ep_state = EP_CONFIG_IDLE;
      end
      else begin
         `uvm_info("RX_LTSSM","2ms timeout, fallback -> DETECT_QUIET",UVM_LOW)
         ep_state = EP_DETECT_QUIET;
      end
  endtask

  // ---- RC_MODE ----
  task rc_state_config_idle();

      bit l0_ready;
      bit timeout_occured;

      `uvm_info("TX_LTSSM","Entered CONFIG_IDLE - sending Idle data Symbols",UVM_LOW)

      l0_ready        = 0;
      timeout_occured = 0;
      rc_os_lane_delete();

      // TODO: 8b/10b sends raw Idle Symbols directly; 128b/130b needs
      // one SDS Ordered Set first to open the Data Stream (cfg field
      // for encoding selection not yet modeled - both paths currently
      // reuse the existing Idle-data broadcast below).
      fork
         begin
            repeat(1)begin
               @(posedge rc_pvif.PCLK);
               rc_tx_bcast_data({2'b01, 128'h0});
               rc_tx_bcast_valid(1);
            end
               @(posedge rc_pvif.PCLK);
               rc_tx_bcast_valid(0);
         end

         begin
            // TODO: real check - 8 consecutive Symbol Times of Idle
            // data on ALL configured Lanes, AND >=16 Idle Symbols sent
            // after receiving one Idle Symbol. rc_os_all_lanes_ready()
            // is the stand-in activity check (requires every active
            // lane's queue to be non-empty, not just lane 0) until a
            // real per-Lane consecutive-idle-symbol tracker exists.
            wait(rc_os_all_lanes_ready(0));
            config_idle.wait_for();
            `uvm_info("TX_LTSSM",$sformatf("Received rc_idle activity on all %0d active lanes in CONFIG_IDLE",cfg.num_lanes),UVM_LOW)
            l0_ready = 1;
            disable fork;
         end

         begin
            rc_ltssm_timer(cfg.config_idle_timeout);   // TODO: add 2ms min timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      rc_tx_bcast_valid(0);
      rc_os_lane_delete();

      if(l0_ready) begin
         `uvm_info("TX_LTSSM","8x consecutive Idle + 16 sent-after-first -> L0",UVM_LOW)
         rc_idle_to_rlock_transitioned = 8'h00;   // reset on transition to L0
         rc_state = L0;
         return;
      end

      // Minimum 2ms timeout - per 4.2.6.3.6.
      if(rc_idle_to_rlock_transitioned < 8'hFF) begin
         `uvm_info("TX_LTSSM",$sformatf("2ms timeout, idle_to_rlock_transitioned=%0h<FFh -> RECOVERY_RCVRLOCK",rc_idle_to_rlock_transitioned),UVM_LOW)
         if(cfg.gen == 3)
            rc_idle_to_rlock_transitioned = rc_idle_to_rlock_transitioned + 1'b1;
         else
            rc_idle_to_rlock_transitioned = 8'hFF;
         rc_state = RECOVERY_RCVRLOCK;
      end
      else begin
         `uvm_info("TX_LTSSM","2ms timeout, idle_to_rlock_transitioned=FFh -> DETECT_QUIET",UVM_LOW)
         rc_state = DETECT_QUIET;
      end
    endtask

  // ---- EP_MODE ----
  task ep_state_config_idle();

      bit l0_ready;
      bit timeout_occured;

      `uvm_info("RX_LTSSM","Entered CONFIG_IDLE - sending Idle data Symbols",UVM_LOW)

      l0_ready        = 0;
      timeout_occured = 0;
      ep_os_lane_delete();

      fork
         begin
            repeat(1) begin
               @(posedge ep_pvif.PCLK);
               ep_tx_bcast_data({2'b01, 128'h0});
               ep_tx_bcast_valid(1);
            end
               @(posedge ep_pvif.PCLK);
               ep_tx_bcast_valid(0);
         end

         begin
            // Requires an Idle OS to have been captured on every active
            // lane (not just lane 0) before considering the link idle.
            wait(ep_os_all_lanes_ready(0));
            config_idle.wait_for();
            `uvm_info("RX_LTSSM",$sformatf("Received ep_idle activity on all %0d active lanes in CONFIG_IDLE",cfg.num_lanes),UVM_LOW)
            l0_ready = 1;
            disable fork;
         end

         begin
            ep_ltssm_timer(cfg.config_idle_timeout);   // TODO: add 2ms min timeout param to cfg
            timeout_occured = 1;
            disable fork;
         end
      join

      ep_tx_bcast_valid(0);
      ep_os_lane_delete();

      if(l0_ready) begin
         `uvm_info("RX_LTSSM","8x consecutive Idle + 16 sent-after-first -> L0",UVM_LOW)
         ep_idle_to_rlock_transitioned = 8'h00;
         ep_state = EP_L0;
         return;
      end

      if(ep_idle_to_rlock_transitioned < 8'hFF) begin
         `uvm_info("RX_LTSSM",$sformatf("2ms timeout, idle_to_rlock_transitioned=%0h<FFh -> RECOVERY_RCVRLOCK",ep_idle_to_rlock_transitioned),UVM_LOW)
         if(cfg.gen == 3)
            ep_idle_to_rlock_transitioned = ep_idle_to_rlock_transitioned + 1'b1;
         else
            ep_idle_to_rlock_transitioned = 8'hFF;
         ep_state = EP_RECOVERY_RCVRLOCK;
      end
      else begin
         `uvm_info("RX_LTSSM","2ms timeout, idle_to_rlock_transitioned=FFh -> DETECT_QUIET",UVM_LOW)
         ep_state = EP_DETECT_QUIET;
      end
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
	    @(posedge rc_pvif.PCLK);
               rc_vif.rc_link_up = 1;
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
        `uvm_info("PIPE_DRV",$sformatf("DATA BEFORE_Srcambled: %0d",rc_received.size()),UVM_HIGH)
        foreach(rc_received[i])
        `uvm_info("PIPE_DRV",$sformatf("RC_SCRAMBLED_BEFORE %0h",rc_received[i]),UVM_HIGH)
        // NOTE: each TLP already carries its own STP - it was added per-TLP
        // in write_port_e() (per row of t.mac_tx_data), before being
        // flattened into this single-dimension rc_received queue. Do NOT
        // call rc_add_stp_to_all_packets(rc_received) here: rc_received can
        // legitimately hold several already-STP-framed TLPs back to back
        // (queued up faster than this loop drains them), and re-running
        // whole-queue STP insertion on top of that would stamp one bogus
        // STP over the whole batch, corrupting the per-TLP framing the
        // EP-side MAC monitor parser relies on (one STP per TLP).
      //rc_data_scrambling(0);
      //rc_sdp_packet = {SDP[15:0],rc_dllp_packet[0][31:0],rc_dllp_packet[1][31:16]}; 
      //rc_received.push_back(rc_sdp_packet[63:32]);
      //rc_received.push_back(rc_sdp_packet[31:0]);
      rc_received.push_back(EDS);
      foreach(rc_received[i])
        `uvm_info("PIPE_DRV",$sformatf("RC_SCRAMBLED_AFTER %0h",rc_received[i]),UVM_LOW)

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
      `uvm_info("MAC_TX_DRV",$sformatf("RC_DLLP_Received_1 %0p DWORDs ",rc_dllp_fifo[i]),UVM_HIGH)
        rc_dllp_queue = rc_dllp_fifo.pop_front();
	 foreach(rc_dllp_queue[i]) 
      `uvm_info("MAC_TX_DRV",$sformatf("RC_DLLP_Received_1 %0p DWORDs ",rc_dllp_queue[i]),UVM_HIGH)
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
        //   link_up_env_rx.trigger();
	   @(posedge ep_pvif.PCLK);
               ep_vif.ep_link_up = 1;

	      `uvm_info("RX_LTSSM",
          $sformatf("Speed match: running Gen%0d, negotiated Gen%0d -> RECOVERY",
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
        `uvm_info("PIPE_RX_DRV",$sformatf("EP_SCRAMBLED_BEFORE %0h",ep_received[i]),UVM_HIGH)
	
        // NOTE: each TLP already carries its own STP - added per-TLP in
        // write_port_g() before being flattened into this single-dimension
        // ep_received queue. Do not re-run whole-queue STP insertion here;
        // ep_received can legitimately hold several already-framed TLPs
        // back to back.
	foreach(ep_received[i])
        `uvm_info("PIPE_RX_DRV",$sformatf("EP_SCRAMBLED %0h",ep_received[i]),UVM_HIGH)
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

    bit barrier_met;
    bit timeout_occured;

    // directed_speed_change: this side's intent to change speed. Set
    // here from active<negotiated on the first pass into Recovery.
    // TODO: also OR in "received TS Ordered Set had speed_change=1b"
    // once exact field-decode RX checking exists.
    if(rc_active_gen < rc_negotiated_gen)
       rc_directed_speed_change = 1'b1;

    `uvm_info("TX_LTSSM",
      $sformatf("Recovery.RcvrLock - relocking @ Gen%0d (negotiated Gen%0d, directed_speed_change=%0b)",
                 rc_active_gen, rc_negotiated_gen, rc_directed_speed_change), UVM_LOW)

    barrier_met     = 0;
    timeout_occured = 0;
    rc_pvif.TxElecIdle <= '0;
    rc_os_lane_delete();

    fork
       //--------------------------------------------------------
       // TX: TS1 @ current speed, speed_change bit reflects
       // directed_speed_change (not hardcoded to 0 anymore), Link/
       // Lane numbers carried over from Configuration.
       //--------------------------------------------------------
       begin
          repeat(8) begin
             @(posedge rc_pvif.PCLK);
             rc_drive_os(tag_ts1(rc_TS1, rc_directed_speed_change,
                                  rc_negotiated_link_num, rc_negotiated_lane_num));
          end
          @(posedge rc_pvif.PCLK);
          rc_tx_bcast_valid(0);
       end

       //--------------------------------------------------------
       // RX: 8-consecutive TS1/TS2 on ALL configured Lanes with
       // Link+Lane matching transmitted, speed_change == directed.
       //--------------------------------------------------------
       begin
          wait(rc_os_all_lanes_ready(7));   // TODO: real Link+Lane+
                                             // speed_change field match
                                             // on all Lanes, not just
                                             // queue depth
          recovery_rcvrlock.wait_for();
          barrier_met = 1;
          disable fork;
       end

       //--------------------------------------------------------
       // 24ms overall timeout
       //--------------------------------------------------------
       begin
          rc_ltssm_timer(cfg.recovery_rcvrlock_timeout);   // TODO: add 24ms timeout param to cfg
          timeout_occured = 1;
          disable fork;
       end
    join

    rc_tx_bcast_valid(0);
    rc_os_lane_delete();

    if(barrier_met) begin
       `uvm_info("TX_LTSSM","Recovery.RcvrLock done (fast match) -> Recovery.RcvrCfg",UVM_LOW)
       rc_state = RECOVERY_RCVRCFG;
       return;
    end

    // 24ms timeout - Equalization/EC-related sub-branch omitted per
    // instruction; falls straight to the revert-speed / Configuration
    // / Detect tree.
    if(!rc_changed_speed_recovery && rc_active_gen > 1) begin
       `uvm_info("TX_LTSSM","24ms timeout, no speed change yet this Recovery pass, rate>2.5GT/s -> Recovery.Speed (revert to Gen1/2.5GT/s)",UVM_LOW)
       rc_target_gen = 1;
       rc_state = RECOVERY_SPEED;
       return;
    end

    if(rc_changed_speed_recovery) begin
       `uvm_info("TX_LTSSM",
          $sformatf("24ms timeout, already changed speed this Recovery pass -> Recovery.Speed (revert to Gen%0d, entry speed)",
                     rc_gen_on_recovery_entry), UVM_LOW)
       rc_target_gen = rc_gen_on_recovery_entry;
       rc_state = RECOVERY_SPEED;
       return;
    end

    `uvm_info("TX_LTSSM","24ms timeout, no conditions met -> DETECT_QUIET",UVM_LOW)
    rc_state = DETECT_QUIET;
endtask

task rc_state_recovery_rcvrcfg();

    bit path_to_speed;   // -> Recovery.Speed (successful speed negotiation)
    bit path_to_idle;    // -> Recovery.Idle
    bit timeout_occured;

    // Per spec 4.2.6.4.4: speed_change bit reflects directed_speed_change
    // as already set on entry (from RcvrLock), not recomputed here.
    `uvm_info("TX_LTSSM",
      $sformatf("Recovery.RcvrCfg - advertising TS2s (speed_change=%0b)", rc_directed_speed_change), UVM_LOW)

    path_to_speed   = 0;
    path_to_idle    = 0;
    timeout_occured = 0;
    rc_os_lane_delete();

    fork
       //--------------------------------------------------------
       // TX: TS2 on all configured Lanes, Link/Lane from
       // Configuration, speed_change = directed_speed_change.
       //--------------------------------------------------------
       begin
          repeat(16) begin
             @(posedge rc_pvif.PCLK);
             rc_drive_os(tag_ts2(TS2, rc_directed_speed_change,
                                  rc_negotiated_link_num, rc_negotiated_lane_num));
          end
          @(posedge rc_pvif.PCLK);
          rc_tx_bcast_valid(0);
       end

       //--------------------------------------------------------
       // RX: 8-consecutive-match trigger, then classify.
       // TODO: this single combined trigger stands in for the
       // spec's textually distinct conditions (i) speed-change path
       // vs the Recovery.Idle / Configuration paths, which need real
       // field-level Link/Lane/speed_change comparison to tell apart.
       // Classified here by directed_speed_change alone: speed change
       // requested -> path_to_speed; otherwise -> path_to_idle (the
       // common/expected case).
       //--------------------------------------------------------
       begin
          wait(rc_os_all_lanes_ready(7));   // TODO: real 8-consecutive match
          `uvm_info("MAC_TX_DRV",$sformatf("wait_completed RC_ORDERED_SETS %0d DWORDs",rc_received_os_lane[0].size()),UVM_LOW)

          recovery_rcvrcfg.wait_for();

          if(rc_directed_speed_change)
             path_to_speed = 1;
          else
             path_to_idle = 1;
          disable fork;
       end

       //--------------------------------------------------------
       // 48ms overall timeout
       //--------------------------------------------------------
       begin
          rc_ltssm_timer(cfg.recovery_rcvrcfg_timeout);   // TODO: add 48ms timeout param to cfg
          timeout_occured = 1;
          disable fork;
       end
    join

    rc_tx_bcast_valid(0);
    rc_os_lane_delete();

    if(path_to_speed) begin
       rc_target_gen = rc_active_gen + 1;
       rc_successful_speed_negotiation = 1'b1;
       `uvm_info("TX_LTSSM",
          $sformatf("Recovery.RcvrCfg -> Recovery.Speed (successful, Gen%0d -> Gen%0d)",
                     rc_active_gen, rc_target_gen), UVM_LOW)
       rc_state = RECOVERY_SPEED;
       return;
    end

    if(path_to_idle) begin
       rc_changed_speed_recovery = 1'b0;
       rc_directed_speed_change  = 1'b0;
       rc_recovery_idle_via_rcvrcfg_timeout = 1'b0;
       `uvm_info("TX_LTSSM","Recovery.RcvrCfg -> Recovery.Idle",UVM_LOW)
       rc_state = RECOVERY_IDLE;
       return;
    end

    // 48ms timeout branch
    if(cfg.gen == 1 || cfg.gen == 2) begin
       `uvm_info("TX_LTSSM","48ms timeout at Gen1/Gen2 -> DETECT_QUIET",UVM_LOW)
       rc_state = DETECT_QUIET;
    end
    else if(cfg.gen == 3 && rc_idle_to_rlock_transitioned < 8'hFF) begin
       `uvm_info("TX_LTSSM","48ms timeout, Gen3, idle_to_rlock_transitioned<FFh -> Recovery.Idle",UVM_LOW)
       rc_changed_speed_recovery = 1'b0;
       rc_directed_speed_change  = 1'b0;
       rc_recovery_idle_via_rcvrcfg_timeout = 1'b1;
       rc_state = RECOVERY_IDLE;
    end
    else begin
       `uvm_info("TX_LTSSM","48ms timeout, fallback -> DETECT_QUIET",UVM_LOW)
       rc_state = DETECT_QUIET;
    end
endtask

task rc_state_recovery_speed();

    bit timeout_occurred;
    bit speed_done;

    timeout_occurred = 0;
    speed_done       = 0;

    `uvm_info("TX_LTSSM",
        $sformatf(
            "Recovery.Speed - entering Electrical Idle " +
            "(successful_speed_negotiation=%0b, changed_speed_recovery=%0b)",
            rc_successful_speed_negotiation,
            rc_changed_speed_recovery
        ),
        UVM_LOW
    );

    //---------------------------------------------------------
    // Enter Electrical Idle
    //---------------------------------------------------------
    rc_pvif.TxElecIdle <= cfg.active_lane_mask;
    rc_tx_bcast_valid(0);

    //---------------------------------------------------------
    // Decide target Gen
    //---------------------------------------------------------
    if (rc_successful_speed_negotiation) begin

        rc_active_gen = rc_target_gen;
        rc_changed_speed_recovery = 1'b1;

        `uvm_info("TX_LTSSM",
            $sformatf(
                "Recovery.Speed: successful negotiation -> Gen%0d",
                rc_active_gen
            ),
            UVM_LOW
        );

    end
    else if (rc_changed_speed_recovery) begin

        rc_active_gen = rc_gen_on_recovery_entry;
        rc_changed_speed_recovery = 1'b0;

        `uvm_info("TX_LTSSM",
            $sformatf(
                "Recovery.Speed: reverting to entry Gen%0d",
                rc_active_gen
            ),
            UVM_LOW
        );

    end
    else begin

        rc_active_gen = 1;

        `uvm_info("TX_LTSSM",
            "Recovery.Speed: falling back to Gen1",
            UVM_LOW
        );

    end

    //---------------------------------------------------------
    // Change rate while in Electrical Idle
    //---------------------------------------------------------
    rc_pvif.Rate <= gen_to_rate_code(rc_active_gen);

    `uvm_info("TX_LTSSM",
        $sformatf(
            "Recovery.Speed: Rate changed to Gen%0d",
            rc_active_gen
        ),
        UVM_LOW
    );

    fork : RECOVERY_SPEED_TIMEOUT

        begin : SPEED_COMPLETE

            // PHY settle time
            #(cfg.recovery_speed_settle_time);

            speed_done = 1'b1;

        end

        begin : SPEED_TIMEOUT

            rc_ltssm_timer(cfg.recovery_speed_timeout);

            timeout_occurred = 1'b1;

        end

    join_any

    //---------------------------------------------------------
    // Kill whichever branch is still running
    //---------------------------------------------------------
    disable RECOVERY_SPEED_TIMEOUT;

    //---------------------------------------------------------
    // Timeout case
    //---------------------------------------------------------
    if (timeout_occurred && !speed_done) begin

        `uvm_info("TX_LTSSM",
            "48ms timeout in Recovery.Speed (abnormal) -> DETECT_QUIET",
            UVM_LOW
        );

        rc_pvif.TxElecIdle <= '0;
        rc_directed_speed_change = 1'b0;

        rc_state = DETECT_QUIET;

        return;
    end

    //---------------------------------------------------------
    // Successful completion
    //---------------------------------------------------------
    if (speed_done) begin

        rc_pvif.TxElecIdle <= '0;
        rc_directed_speed_change = 1'b0;

        `uvm_info("TX_LTSSM",$sformatf("Recovery.Speed done -> now running Gen%0d -> Recovery.RcvrLock",rc_active_gen),UVM_LOW);

        rc_state = RECOVERY_RCVRLOCK;

        return;
    end

endtask


task rc_state_recovery_idle();

    bit l0_ready;
    bit config_ready;    // PAD-Lane detected -> Configuration
    bit timeout_occured;

    `uvm_info("TX_LTSSM",
      $sformatf("Entered Recovery.Idle @ Gen%0d (via_rcvrcfg_timeout=%0b)",
                 rc_active_gen, rc_recovery_idle_via_rcvrcfg_timeout), UVM_LOW)

    // NOTE: Disabled / Hot Reset / Loopback and all "if directed"
    // higher-Layer transitions are intentionally not modeled - only
    // the Idle->L0 and Idle->Configuration (PAD-Lane) paths below.

   
    if(cfg.link_ctrl_hot_reset)
    begin
       `uvm_info("TX_LTSSM","Hot Reset directed -> immediate HOT_RESET",UVM_LOW)
       rc_state = HOT_RESET;
       return;
    end

    l0_ready        = 0;
    config_ready    = 0;
    timeout_occured = 0;
    rc_os_lane_delete();

    fork
       begin
          repeat(1) begin
             @(posedge rc_pvif.PCLK);
             rc_tx_bcast_data({2'b01, 128'h0});
             rc_tx_bcast_valid(1);
          end
          @(posedge rc_pvif.PCLK);
          rc_tx_bcast_valid(0);
       end

       //--------------------------------------------------------
       // L0 condition: 8-consecutive Idle Symbol Times on ALL
       // configured Lanes. For 128b/130b, additionally disqualified
       // if this substate was entered via RcvrCfg's 48ms timeout.
       //--------------------------------------------------------
       begin
          wait(rc_os_all_lanes_ready(0));   // TODO: real per-Lane
                                             // consecutive-idle-symbol
                                             // tracker, same gap as
                                             // CONFIG_IDLE

          recovery_idle_bar.wait_for();
          l0_ready = 1;
          disable fork;
       end

       //--------------------------------------------------------
       // Configuration condition: 2 consecutive TS1 received on any
       // configured Lane with Lane number == PAD.
       //--------------------------------------------------------
   //    begin
   //       wait(0);   // TODO: needs a real PAD-Lane field check on
   //                  // rc_received_os_lane entries - no such decode
   //                  // exists yet.
   //       config_ready = 1;
   //       disable fork;
   //    end

       begin
          rc_ltssm_timer(cfg.recovery_idle_timeout);   // TODO: add 2ms timeout param to cfg
          timeout_occured = 1;
          disable fork;
       end
    join

    rc_tx_bcast_valid(0);
    rc_os_lane_delete();

    if(l0_ready) begin
       `uvm_info("TX_LTSSM","Recovery.Idle: 8x consecutive Idle -> L0",UVM_LOW)
       rc_idle_to_rlock_transitioned = 8'h00;   // reset on transition to L0
       rc_state = L0;
       return;
    end

    if(config_ready) begin
       `uvm_info("TX_LTSSM","Recovery.Idle: PAD-Lane TS1 detected -> Configuration",UVM_LOW)
       rc_state = CONFIG_LINKNUM_START;
       return;
    end

    // 2ms timeout
    if(rc_idle_to_rlock_transitioned < 8'hFF) begin
       `uvm_info("TX_LTSSM",$sformatf("2ms timeout, idle_to_rlock_transitioned=%0h<FFh -> Recovery.RcvrLock",rc_idle_to_rlock_transitioned),UVM_LOW)
       if(cfg.gen == 3)
          rc_idle_to_rlock_transitioned = rc_idle_to_rlock_transitioned + 1'b1;
       else   // 5.0 GT/s (or 2.5 GT/s if supported)
          rc_idle_to_rlock_transitioned = 8'hFF;
       rc_state = RECOVERY_RCVRLOCK;
    end
    else begin
       `uvm_info("TX_LTSSM","2ms timeout, idle_to_rlock_transitioned=FFh -> DETECT_QUIET",UVM_LOW)
       rc_state = DETECT_QUIET;
    end
endtask

// ---- EP_MODE ----
int unsigned ep_target_gen;

task ep_state_recovery_rcvrlock();

    bit barrier_met;
    bit timeout_occured;

    if(ep_active_gen < ep_negotiated_gen)
       ep_directed_speed_change = 1'b1;

    `uvm_info("RX_LTSSM",
      $sformatf("Recovery.RcvrLock - relocking @ Gen%0d (negotiated Gen%0d, directed_speed_change=%0b)",
                 ep_active_gen, ep_negotiated_gen, ep_directed_speed_change), UVM_LOW)

    barrier_met     = 0;
    timeout_occured = 0;
    ep_pvif.TxElecIdle <= '0;
    ep_os_lane_delete();

    fork
       begin
          repeat(8) begin
             @(posedge ep_pvif.PCLK);
             ep_drive_os(tag_ts1(ep_TS1, ep_directed_speed_change,
                                  ep_negotiated_link_num, ep_negotiated_lane_num));
          end
          @(posedge ep_pvif.PCLK);
          ep_tx_bcast_valid(0);
       end

       begin
          wait(ep_os_all_lanes_ready(7));   // TODO: real field match
          recovery_rcvrlock.wait_for();
          barrier_met = 1;
          disable fork;
       end

       begin
          ep_ltssm_timer(cfg.recovery_rcvrlock_timeout);   // TODO: add 24ms timeout param to cfg
          timeout_occured = 1;
          disable fork;
       end
    join

    ep_tx_bcast_valid(0);
    ep_os_lane_delete();

    if(barrier_met) begin
       `uvm_info("RX_LTSSM","Recovery.RcvrLock done (fast match) -> Recovery.RcvrCfg",UVM_LOW)
       ep_state = EP_RECOVERY_RCVRCFG;
       return;
    end

    if(!ep_changed_speed_recovery && ep_active_gen > 1) begin
       `uvm_info("RX_LTSSM","24ms timeout, no speed change yet this Recovery pass, rate>2.5GT/s -> Recovery.Speed (revert to Gen1/2.5GT/s)",UVM_LOW)
       ep_target_gen = 1;
       ep_state = EP_RECOVERY_SPEED;
       return;
    end

    if(ep_changed_speed_recovery) begin
       `uvm_info("RX_LTSSM",
          $sformatf("24ms timeout, already changed speed this Recovery pass -> Recovery.Speed (revert to Gen%0d, entry speed)",
                     ep_gen_on_recovery_entry), UVM_LOW)
       ep_target_gen = ep_gen_on_recovery_entry;
       ep_state = EP_RECOVERY_SPEED;
       return;
    end

    `uvm_info("RX_LTSSM","24ms timeout, no conditions met -> DETECT_QUIET",UVM_LOW)
    ep_state = EP_DETECT_QUIET;
endtask

task ep_state_recovery_rcvrcfg();

    bit path_to_speed;
    bit path_to_idle;
    bit timeout_occured;

    `uvm_info("RX_LTSSM",
      $sformatf("Recovery.RcvrCfg - advertising TS2s (speed_change=%0b)", ep_directed_speed_change), UVM_LOW)

    path_to_speed   = 0;
    path_to_idle    = 0;
    timeout_occured = 0;
    ep_os_lane_delete();

    fork
       begin
          repeat(16) begin
             @(posedge ep_pvif.PCLK);
             ep_drive_os(tag_ts2(TS2, ep_directed_speed_change,
                                  ep_negotiated_link_num, ep_negotiated_lane_num));
          end
          @(posedge ep_pvif.PCLK);
          ep_tx_bcast_valid(0);
       end

       begin
          wait(ep_os_all_lanes_ready(7));   // TODO: real 8-consecutive match
          recovery_rcvrcfg.wait_for();

          if(ep_directed_speed_change)
             path_to_speed = 1;
          else
             path_to_idle = 1;
          disable fork;
       end

       begin
          ep_ltssm_timer(cfg.recovery_rcvrcfg_timeout);   // TODO: add 48ms timeout param to cfg
          timeout_occured = 1;
          disable fork;
       end
    join

    ep_tx_bcast_valid(0);
    ep_os_lane_delete();

    if(path_to_speed) begin
       ep_target_gen = ep_active_gen + 1;
       ep_successful_speed_negotiation = 1'b1;
       `uvm_info("RX_LTSSM",
          $sformatf("Recovery.RcvrCfg -> Recovery.Speed (successful, Gen%0d -> Gen%0d)",
                     ep_active_gen, ep_target_gen), UVM_LOW)
       ep_state = EP_RECOVERY_SPEED;
       return;
    end

    if(path_to_idle) begin
       ep_changed_speed_recovery = 1'b0;
       ep_directed_speed_change  = 1'b0;
       ep_recovery_idle_via_rcvrcfg_timeout = 1'b0;
       `uvm_info("RX_LTSSM","Recovery.RcvrCfg -> Recovery.Idle",UVM_LOW)
       ep_state = EP_RECOVERY_IDLE;
       return;
    end

    if(cfg.gen == 1 || cfg.gen == 2) begin
       `uvm_info("RX_LTSSM","48ms timeout at Gen1/Gen2 -> DETECT_QUIET",UVM_LOW)
       ep_state = EP_DETECT_QUIET;
    end
    else if(cfg.gen == 3 && ep_idle_to_rlock_transitioned < 8'hFF) begin
       `uvm_info("RX_LTSSM","48ms timeout, Gen3, idle_to_rlock_transitioned<FFh -> Recovery.Idle",UVM_LOW)
       ep_changed_speed_recovery = 1'b0;
       ep_directed_speed_change  = 1'b0;
       ep_recovery_idle_via_rcvrcfg_timeout = 1'b1;
       ep_state = EP_RECOVERY_IDLE;
    end
    else begin
       `uvm_info("RX_LTSSM","48ms timeout, fallback -> DETECT_QUIET",UVM_LOW)
       ep_state = EP_DETECT_QUIET;
    end
endtask

task ep_state_recovery_speed();

    bit timeout_occurred;
    bit speed_done;

    timeout_occurred = 0;
    speed_done       = 0;

    `uvm_info("RX_LTSSM",
        $sformatf(
            "Recovery.Speed - entering Electrical Idle " +
            "(successful_speed_negotiation=%0b, changed_speed_recovery=%0b)",
            ep_successful_speed_negotiation,
            ep_changed_speed_recovery
        ),
        UVM_LOW
    );

    //---------------------------------------------------------
    // Enter Electrical Idle
    //---------------------------------------------------------
    ep_pvif.TxElecIdle <= cfg.active_lane_mask;
    ep_tx_bcast_valid(0);

    //---------------------------------------------------------
    // Decide target Gen
    //---------------------------------------------------------
    if (ep_successful_speed_negotiation) begin

        ep_active_gen = ep_target_gen;
        ep_changed_speed_recovery = 1'b1;

        `uvm_info("RX_LTSSM",
            $sformatf(
                "Recovery.Speed: successful negotiation -> Gen%0d",
                ep_active_gen
            ),
            UVM_LOW
        );

    end
    else if (ep_changed_speed_recovery) begin

        ep_active_gen = ep_gen_on_recovery_entry;
        ep_changed_speed_recovery = 1'b0;

        `uvm_info("RX_LTSSM",
            $sformatf(
                "Recovery.Speed: reverting to entry Gen%0d",
                ep_active_gen
            ),
            UVM_LOW
        );

    end
    else begin

        ep_active_gen = 1;

        `uvm_info("RX_LTSSM",
            "Recovery.Speed: falling back to Gen1",
            UVM_LOW
        );

    end

    //---------------------------------------------------------
    // Change rate while in Electrical Idle
    //---------------------------------------------------------
    ep_pvif.Rate <= gen_to_rate_code(ep_active_gen);

    `uvm_info("RX_LTSSM",
        $sformatf(
            "Recovery.Speed: Rate changed to Gen%0d",
            ep_active_gen
        ),
        UVM_LOW
    );

    //---------------------------------------------------------
    // Recovery.Speed completion / timeout
    //---------------------------------------------------------
    fork : RECOVERY_SPEED_TIMEOUT

        begin : SPEED_COMPLETE

            #(cfg.recovery_speed_settle_time);

            speed_done = 1'b1;

        end

        begin : SPEED_TIMEOUT

            ep_ltssm_timer(cfg.recovery_speed_timeout);

            timeout_occurred = 1'b1;

        end

    join_any

    //---------------------------------------------------------
    // Stop remaining fork branch
    //---------------------------------------------------------
    disable RECOVERY_SPEED_TIMEOUT;

    //---------------------------------------------------------
    // Timeout
    //---------------------------------------------------------
    if (timeout_occurred && !speed_done) begin

        `uvm_info("RX_LTSSM",
            "48ms timeout in Recovery.Speed (abnormal) -> DETECT_QUIET",
            UVM_LOW
        );

        ep_pvif.TxElecIdle <= '0;
        ep_directed_speed_change = 1'b0;

        ep_state = EP_DETECT_QUIET;

        return;
    end

    //---------------------------------------------------------
    // Successful completion
    //---------------------------------------------------------
    if (speed_done) begin

        ep_pvif.TxElecIdle <= '0;
        ep_directed_speed_change = 1'b0;

        `uvm_info("RX_LTSSM",
            $sformatf(
                "Recovery.Speed done -> now running Gen%0d -> Recovery.RcvrLock",
                ep_active_gen
            ),
            UVM_LOW
        );

        ep_state = EP_RECOVERY_RCVRLOCK;

        return;
    end

endtask

task ep_state_recovery_idle();

    bit l0_ready;
    bit config_ready;
    bit timeout_occured;

    `uvm_info("RX_LTSSM",
      $sformatf("Entered Recovery.Idle @ Gen%0d (via_rcvrcfg_timeout=%0b)",
                 ep_active_gen, ep_recovery_idle_via_rcvrcfg_timeout), UVM_LOW)
    if(cfg.link_ctrl_hot_reset)
    begin
       `uvm_info("RX_LTSSM","Hot Reset TS1s received (modeled) -> immediate EP_HOT_RESET",UVM_LOW)
       ep_state = EP_HOT_RESET;
       return;
    end


    l0_ready        = 0;
    config_ready    = 0;
    timeout_occured = 0;
    ep_os_lane_delete();

    fork
       begin
          repeat(1) begin
             @(posedge ep_pvif.PCLK);
             ep_tx_bcast_data({2'b01, 128'h0});
             ep_tx_bcast_valid(1);
          end
          @(posedge ep_pvif.PCLK);
          ep_tx_bcast_valid(0);
       end

       begin
          wait(ep_os_all_lanes_ready(0));   // TODO: real per-Lane idle tracker

          recovery_idle_bar.wait_for();
          l0_ready = 1;
          disable fork;
       end

   //    begin
   //       wait(0);   // TODO: PAD-Lane field check not modeled - see RC side
   //       config_ready = 1;
   //       disable fork;
   //    end

       begin
          ep_ltssm_timer(cfg.recovery_idle_timeout);   // TODO: add 2ms timeout param to cfg
          timeout_occured = 1;
          disable fork;
       end
    join

    ep_tx_bcast_valid(0);
    ep_os_lane_delete();

    if(l0_ready) begin
       `uvm_info("RX_LTSSM","Recovery.Idle: 8x consecutive Idle -> L0",UVM_LOW)
       ep_idle_to_rlock_transitioned = 8'h00;
       ep_state = EP_L0;
       return;
    end

    if(config_ready) begin
       `uvm_info("RX_LTSSM","Recovery.Idle: PAD-Lane TS1 detected -> Configuration",UVM_LOW)
       ep_state = EP_CONFIG_LINKNUM_START;
       return;
    end

    if(ep_idle_to_rlock_transitioned < 8'hFF) begin
       `uvm_info("RX_LTSSM",$sformatf("2ms timeout, idle_to_rlock_transitioned=%0h<FFh -> Recovery.RcvrLock",ep_idle_to_rlock_transitioned),UVM_LOW)
       if(ep_active_gen == 3)
          ep_idle_to_rlock_transitioned = ep_idle_to_rlock_transitioned + 1'b1;
       else
          ep_idle_to_rlock_transitioned = 8'hFF;
       ep_state = EP_RECOVERY_RCVRLOCK;
    end
    else begin
       `uvm_info("RX_LTSSM","2ms timeout, idle_to_rlock_transitioned=FFh -> DETECT_QUIET",UVM_LOW)
       ep_state = EP_DETECT_QUIET;
    end
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
  task rc_state_disabled();

     int unsigned eios_beats;
     bit          rx_eios_seen;

     `uvm_info("TX_LTSSM","Entered DISABLED - broadcasting TS1 with Disable Link asserted",UVM_LOW)

     rc_os_lane_delete();
     rx_eios_seen = 0;

     fork
        begin
           repeat(cfg.disabled_ts1_count) begin
              @(posedge rc_pvif.PCLK);
              rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_link_num), .disable_link(1'b1)));
           end
           @(posedge rc_pvif.PCLK);
           rc_tx_bcast_valid(0);

           // EIOS count: 2 at 5.0 GT/s (Gen2), else 1.
           eios_beats = (rc_active_gen == 2) ? 2 : 1;
           repeat(eios_beats) @(posedge rc_pvif.PCLK);

           rc_pvif.TxElecIdle <= cfg.active_lane_mask;
        end

        begin
           forever begin
              @(posedge rc_pvif.PCLK);
              for(int lane = 0; lane < cfg.num_lanes; lane++)
                 if(cfg.active_lane_mask[lane] && rc_pvif.RxElecIdle[lane] == 1'b1) begin
                    rx_eios_seen = 1;
                    disable fork;
                 end
           end
        end
     join

     rc_os_lane_delete();

     `uvm_info("TX_LTSSM",
        $sformatf("DISABLED: EIOS transmitted, EIOS received=%0b -> LinkUp=0, Lanes Disabled",rx_eios_seen),
        UVM_LOW)

  endtask

  // ---- EP_MODE ----
  task ep_state_disabled();

     int unsigned eios_beats;
     bit          rx_eios_seen;

     `uvm_info("RX_LTSSM","Entered DISABLED - broadcasting TS1 with Disable Link asserted",UVM_LOW)

     ep_os_lane_delete();
     rx_eios_seen = 0;

     fork
        begin
           repeat(cfg.disabled_ts1_count) begin
              @(posedge ep_pvif.PCLK);
              ep_drive_os(tag_ts1(ep_TS1, .link_num(ep_link_num), .disable_link(1'b1)));
           end
           @(posedge ep_pvif.PCLK);
           ep_tx_bcast_valid(0);

           // EIOS count: 2 at 5.0 GT/s (Gen2), else 1.
           eios_beats = (ep_active_gen == 2) ? 2 : 1;
           repeat(eios_beats) @(posedge ep_pvif.PCLK);

           ep_pvif.TxElecIdle <= cfg.active_lane_mask;
        end

        begin
           forever begin
              @(posedge ep_pvif.PCLK);
              for(int lane = 0; lane < cfg.num_lanes; lane++)
                 if(cfg.active_lane_mask[lane] && ep_pvif.RxElecIdle[lane] == 1'b1) begin
                    rx_eios_seen = 1;
                    disable fork;
                 end
           end
        end
     join

     ep_os_lane_delete();

     `uvm_info("RX_LTSSM",
        $sformatf("DISABLED: EIOS transmitted, EIOS received=%0b -> LinkUp=0, Lanes Disabled",rx_eios_seen),
        UVM_LOW)

  endtask

  // ---- RC_MODE (master) ----
  task rc_state_loopback_entry();

     bit ready;
     bit timeout_occured;

     `uvm_info("TX_LTSSM","Entered LOOPBACK_ENTRY (master) - broadcasting TS1 with Loopback asserted",UVM_LOW)

     rc_os_lane_delete();
     ready           = 0;
     timeout_occured = 0;

     fork
        begin
           repeat(cfg.loopback_entry_ts1_count) begin
              @(posedge rc_pvif.PCLK);
              rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_link_num), .loopback(1'b1)));
           end
           @(posedge rc_pvif.PCLK);
           rc_tx_bcast_valid(0);
        end

        begin
           wait(rc_os_all_lanes_ready(2));   // approximates "two consecutive TS1
                                              // w/ Loopback asserted" received
           ready = 1;
           disable fork;
        end

        begin
           rc_ltssm_timer(cfg.loopback_entry_timeout);
           timeout_occured = 1;
           disable fork;
        end
     join

     rc_os_lane_delete();

     if(ready) begin
        `uvm_info("TX_LTSSM","LOOPBACK_ENTRY: slave TS1s w/ Loopback seen -> LOOPBACK_ACTIVE",UVM_LOW)
        rc_state = LOOPBACK_ACTIVE;
        return;
     end

     `uvm_info("TX_LTSSM","LOOPBACK_ENTRY: timeout (<100ms bound) -> LOOPBACK_EXIT",UVM_LOW)
     rc_state = LOOPBACK_EXIT;

  endtask

  task rc_state_loopback_active();

     bit directed;
     bit timeout_occured;

     `uvm_info("TX_LTSSM","Entered LOOPBACK_ACTIVE (master) - waiting for directed exit",UVM_LOW)

     directed        = 0;
     timeout_occured = 0;

     fork
        begin
           wait(cfg.loopback_exit_directed);
           directed = 1;
           disable fork;
        end

        begin
           rc_ltssm_timer(cfg.loopback_active_timeout);
           timeout_occured = 1;
           disable fork;
        end
     join

     `uvm_info("TX_LTSSM",
        $sformatf("LOOPBACK_ACTIVE: directed=%0b timeout=%0b -> LOOPBACK_EXIT",directed,timeout_occured),
        UVM_LOW)
     rc_state = LOOPBACK_EXIT;

  endtask

  task rc_state_loopback_exit();

     int unsigned eios_beats;

     `uvm_info("TX_LTSSM","Entered LOOPBACK_EXIT (master) - EIOS burst then Electrical Idle",UVM_LOW)

     rc_os_lane_delete();

     // spec: 1 EIOS for 2.5-GT/s-only Ports, else 8 consecutive EIOSs.
     eios_beats = (rc_active_gen == 1) ? 1 : 8;
     repeat(eios_beats) @(posedge rc_pvif.PCLK);

     rc_tx_bcast_valid(0);
     rc_pvif.TxElecIdle <= cfg.active_lane_mask;

     rc_ltssm_timer(cfg.loopback_exit_idle_time);

     `uvm_info("TX_LTSSM","LOOPBACK_EXIT: 2ms Electrical Idle complete -> LinkUp=0, exiting Loopback",UVM_LOW)

  endtask

  // ---- EP_MODE (slave) ----
  task ep_state_loopback_entry();

     bit ready;
     bit timeout_occured;

     `uvm_info("RX_LTSSM","Entered LOOPBACK_ENTRY (slave) - broadcasting PAD/PAD TS1",UVM_LOW)

     ep_os_lane_delete();
     ready           = 0;
     timeout_occured = 0;

     fork
        begin
           repeat(cfg.loopback_entry_ts1_count) begin
              @(posedge ep_pvif.PCLK);
              ep_drive_os(tag_ts1(ep_TS1, .loopback(1'b1)));   // Link/Lane = PAD
           end
           @(posedge ep_pvif.PCLK);
           ep_tx_bcast_valid(0);
        end

        begin
           wait(ep_os_all_lanes_ready(2));   // approximates Symbol lock / 2 consecutive
                                              // TS1 received on all active Lanes
           ready = 1;
           disable fork;
        end

        begin
           ep_ltssm_timer(cfg.loopback_entry_timeout);
           timeout_occured = 1;
           disable fork;
        end
     join

     ep_os_lane_delete();

     if(ready) begin
        `uvm_info("RX_LTSSM","LOOPBACK_ENTRY: Symbol lock (approx) -> LOOPBACK_ACTIVE",UVM_LOW)
        ep_state = EP_LOOPBACK_ACTIVE;
        return;
     end

     `uvm_info("RX_LTSSM","LOOPBACK_ENTRY: timeout -> LOOPBACK_EXIT",UVM_LOW)
     ep_state = EP_LOOPBACK_EXIT;

  endtask

  task ep_state_loopback_active();

     bit directed;
     bit eios_seen;
     bit timeout_occured;

     `uvm_info("RX_LTSSM","Entered LOOPBACK_ACTIVE (slave) - watching for directed exit or EIOS",UVM_LOW)

     directed        = 0;
     eios_seen       = 0;
     timeout_occured = 0;

     fork
        begin
           forever begin
              @(posedge ep_pvif.PCLK);
              for(int lane = 0; lane < cfg.num_lanes; lane++)
                 if(cfg.active_lane_mask[lane] && ep_pvif.RxElecIdle[lane] == 1'b1) begin
                    eios_seen = 1;
                    disable fork;
                 end
           end
        end

        begin
           wait(cfg.loopback_exit_directed);
           directed = 1;
           disable fork;
        end

        begin
           ep_ltssm_timer(cfg.loopback_active_timeout);
           timeout_occured = 1;
           disable fork;
        end
     join

     `uvm_info("RX_LTSSM",
        $sformatf("LOOPBACK_ACTIVE: directed=%0b eios_seen=%0b timeout=%0b -> LOOPBACK_EXIT",
                    directed,eios_seen,timeout_occured),
        UVM_LOW)
     ep_state = EP_LOOPBACK_EXIT;

  endtask

  task ep_state_loopback_exit();

     `uvm_info("RX_LTSSM","Entered LOOPBACK_EXIT (slave) - Electrical Idle",UVM_LOW)

     ep_os_lane_delete();
     ep_tx_bcast_valid(0);
     ep_pvif.TxElecIdle <= cfg.active_lane_mask;

     ep_ltssm_timer(cfg.loopback_exit_idle_time);

     `uvm_info("RX_LTSSM","LOOPBACK_EXIT: 2ms Electrical Idle complete -> LinkUp=0, exiting Loopback",UVM_LOW)

  endtask









  task rc_state_hot_reset(output bit remain);
     bit echo_seen;
     bit timeout_occured;

     `uvm_info("TX_LTSSM","Entered HOT_RESET (directed) - broadcasting TS1 with Hot Reset asserted",UVM_LOW)

     rc_os_lane_delete();
     echo_seen       = 0;
     timeout_occured = 0;

     fork
        begin
           repeat(cfg.hot_reset_ts1_count) begin
              @(posedge rc_pvif.PCLK);
              rc_drive_os(tag_ts1(rc_TS1, .link_num(rc_link_num), .lane_num(rc_lane_num), .hot_reset(1'b1)));
           end
           @(posedge rc_pvif.PCLK);
           rc_tx_bcast_valid(0);
        end

        begin
           wait(rc_os_all_lanes_ready(2));   // approximates "two consecutive TS1
                                              // w/ Hot Reset asserted, matching
                                              // Link/Lane" received
           echo_seen = 1;
           disable fork;
        end

        begin
           rc_ltssm_timer(cfg.hot_reset_timeout);
           timeout_occured = 1;
           disable fork;
        end
     join

     rc_os_lane_delete();

     if(echo_seen && cfg.hot_reset_remain_directed) begin
        `uvm_info("TX_LTSSM","HOT_RESET: echo seen, higher Layer still directing -> remaining in HOT_RESET",UVM_LOW)
        remain = 1;
        return;
     end

     `uvm_info("TX_LTSSM",
        $sformatf("HOT_RESET: echo_seen=%0b timeout=%0b -> LinkUp=0, exiting Hot Reset",echo_seen,timeout_occured),
        UVM_LOW)
     remain = 0;

  endtask

  // ---- EP_MODE (not directed) ----
  task ep_state_hot_reset(output bit remain);

     bit echo_seen;
     bit timeout_occured;

     `uvm_info("RX_LTSSM","Entered HOT_RESET (not directed) - broadcasting TS1 with Hot Reset asserted",UVM_LOW)

     ep_os_lane_delete();
     echo_seen       = 0;
     timeout_occured = 0;

     fork
        begin
           repeat(cfg.hot_reset_ts1_count) begin
              @(posedge ep_pvif.PCLK);
              ep_drive_os(tag_ts1(ep_TS1, .link_num(ep_link_num), .lane_num(ep_lane_num), .hot_reset(1'b1)));
           end
           @(posedge ep_pvif.PCLK);
           ep_tx_bcast_valid(0);
        end

        begin
           wait(ep_os_all_lanes_ready(2));   // approximates "two consecutive TS1
                                              // w/ Hot Reset asserted, matching
                                              // Link/Lane" continuing to be received
           echo_seen = 1;
           disable fork;
        end

        begin
           ep_ltssm_timer(cfg.hot_reset_timeout);
           timeout_occured = 1;
           disable fork;
        end
     join

     ep_os_lane_delete();

     // Not-directed role: continuation depends solely on TS1s with
     // Hot Reset still being received (no separate higher-Layer gate).
     if(echo_seen) begin
        `uvm_info("RX_LTSSM","HOT_RESET: matching TS1s still arriving -> remaining in HOT_RESET, timer reset",UVM_LOW)
        remain = 1;
        return;
     end

     `uvm_info("RX_LTSSM",
        $sformatf("HOT_RESET: timeout=%0b -> LinkUp=0, exiting Hot Reset",timeout_occured),
        UVM_LOW)
     remain = 0;

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
	    DISABLED              : begin
                                        rc_state_disabled();
                                        `uvm_info("TX_LTSSM","DISABLED complete - ending testcase",UVM_LOW)
                                        return;
                                     end
            LOOPBACK_ENTRY        : rc_state_loopback_entry();
            LOOPBACK_ACTIVE       : rc_state_loopback_active();
            LOOPBACK_EXIT         : begin
                                        rc_state_loopback_exit();
                                        `uvm_info("TX_LTSSM","LOOPBACK_EXIT complete - ending testcase",UVM_LOW)
                                        return;
                                     end
            HOT_RESET             : begin
                                        bit remain;
                                        rc_state_hot_reset(remain);
                                        if(!remain) begin
                                           `uvm_info("TX_LTSSM","HOT_RESET complete - ending testcase",UVM_LOW)
                                           return;
                                        end
                                     end

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
            EP_DISABLED              : begin
                                           ep_state_disabled();
                                           `uvm_info("RX_LTSSM","DISABLED complete - ending testcase",UVM_LOW)
                                           return;
                                        end
            EP_LOOPBACK_ENTRY        : ep_state_loopback_entry();
            EP_LOOPBACK_ACTIVE       : ep_state_loopback_active();
            EP_LOOPBACK_EXIT         : begin
                                           ep_state_loopback_exit();
                                           `uvm_info("RX_LTSSM","LOOPBACK_EXIT complete - ending testcase",UVM_LOW)
                                           return;
                                        end
            EP_HOT_RESET             : begin
                                           bit remain;
                                           ep_state_hot_reset(remain);
                                           if(!remain) begin
                                              `uvm_info("RX_LTSSM","HOT_RESET complete - ending testcase",UVM_LOW)
                                              return;
                                           end
                                        end

          endcase
        end
      end

      default: `uvm_fatal("PCIe_MAC_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass


