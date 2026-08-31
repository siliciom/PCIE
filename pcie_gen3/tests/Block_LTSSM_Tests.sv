//=====================================================================
// Block_LTSSM_Tests.sv  -  individual Physical-Layer / LTSSM block tests
//
//   From the Tracker "Testplan" sheet (LTSSM rows 46/47/49/50/54/55/56).
//   See docs/BLOCK_TESTPLAN_ANALYSIS.md section 3.
//
//   These do NOT inject stimulus - they DIRECT the LTSSM through the
//   same env_cfg knobs the existing LTSSM_* Top-Testplan tests use
//   (link_ctrl_hot_reset / link_ctrl_enter_loopback /
//   link_ctrl_disable_link / loopback_exit_directed), then add the
//   checkers those tests are missing:
//
//     * a state-history sampler on rc_state / ep_state (MAC driver
//       LTSSM FSM) - the PASS/FAIL gate is "did the LTSSM actually
//       enter the target state and return correctly"
//     * for the speed-change test: rc_active_gen / ep_active_gen == 3
//     * a best-effort scan of the RC TX ordered sets for the
//       Training-Control bits (Symbol 5 : hot-reset[80] / disable[81]
//       / loopback[82]) - reported as info, since Gen3 TS scrambling
//       may re-map them (adjust after run-verify)
//
//   NOTE: compile-verified only; run-verification pending a Questa
//   sim license.
//=====================================================================

`uvm_analysis_imp_decl(_bltssm_os)

// Snoops RC MAC monitor mac_tx_rx_port : os_t_lane[0] carries the
// 128-bit ordered sets the RC drove on the wire.
class pcie_ltssm_os_capture extends uvm_component;
  `uvm_component_utils(pcie_ltssm_os_capture)

  uvm_analysis_imp_bltssm_os #(Sequence_item, pcie_ltssm_os_capture) os_in;

  int n_os;          // total OS words seen
  int n_hot_reset;   // bit[80] set
  int n_disable;     // bit[81] set
  int n_loopback;    // bit[82] set

  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase); os_in = new("os_in", this); endfunction

  function void write_bltssm_os(Sequence_item t);
    bit [127:0] w;
    for (int k = 0; k < t.os_t_lane[0].size(); k++) begin
      w = t.os_t_lane[0][k];
      n_os++;
      if (w[80]) n_hot_reset++;
      if (w[81]) n_disable++;
      if (w[82]) n_loopback++;
    end
  endfunction

  function void clear(); n_os = 0; n_hot_reset = 0; n_disable = 0; n_loopback = 0; endfunction
endclass


//---------------------------------------------------------------------
// base : direct the LTSSM at time 0, sample rc_state / ep_state
//---------------------------------------------------------------------
class block_ltssm_base_test extends pcie_base_test;
  `uvm_component_utils(block_ltssm_base_test)

  pcie_ltssm_os_capture os_cap;
  bit rc_seen[string];      // set of RC LTSSM state names visited
  bit ep_seen[string];      // set of EP LTSSM state names visited
  int unsigned chk_pass, chk_fail;

  function new(string name = "block_ltssm_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    os_cap = pcie_ltssm_os_capture::type_id::create("os_cap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    RC_Env[0].TX_MAC_Agnt.mon.mac_tx_rx_port.connect(os_cap.os_in);
  endfunction

  function void chk(bit cond, string what);
    if (cond) begin chk_pass++; `uvm_info("BLK_CHK", $sformatf("PASS: %s", what), UVM_LOW) end
    else      begin chk_fail++; `uvm_error("BLK_CHK", $sformatf("FAIL: %s", what)) end
  endfunction

  task sample_states();
    fork
      forever begin
        @(RC_Env[0].TX_MAC_Agnt.drv.rc_state);
        rc_seen[RC_Env[0].TX_MAC_Agnt.drv.rc_state.name()] = 1;
      end
      forever begin
        @(EP_Env[0].TX_MAC_Agnt.drv.ep_state);
        ep_seen[EP_Env[0].TX_MAC_Agnt.drv.ep_state.name()] = 1;
      end
    join_none
  endtask

  function void dump_history();
    string s;
    foreach (rc_seen[k]) s = {s, k, " "};
    `uvm_info("BLK_CHK", $sformatf("RC LTSSM states visited: %s", s), UVM_LOW)
    s = "";
    foreach (ep_seen[k]) s = {s, k, " "};
    `uvm_info("BLK_CHK", $sformatf("EP LTSSM states visited: %s", s), UVM_LOW)
    `uvm_info("BLK_CHK",
      $sformatf("RC TX ordered sets: total=%0d  hot_reset_bit=%0d  disable_bit=%0d  loopback_bit=%0d",
                os_cap.n_os, os_cap.n_hot_reset, os_cap.n_disable, os_cap.n_loopback), UVM_LOW)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (chk_pass == 0 && chk_fail == 0)
      `uvm_error("BLK_CHK", $sformatf("%s ran no checks", get_type_name()))
    `uvm_info("BLK_CHK",
      $sformatf("\n==== %s LTSSM block checks: pass=%0d fail=%0d ====",
                get_type_name(), chk_pass, chk_fail), UVM_NONE)
  endfunction

  // record the current state once, then start sampling
  task start_sampling();
    rc_seen[RC_Env[0].TX_MAC_Agnt.drv.rc_state.name()] = 1;
    ep_seen[EP_Env[0].TX_MAC_Agnt.drv.ep_state.name()] = 1;
    sample_states();
  endtask

  // derived test drives this
  virtual task body(uvm_phase phase);
    `uvm_warning("BLK_LTSSM", "block_ltssm_base_test::body not overridden")
  endtask

  // NB: cannot call super.run_phase - it waits DL_ACTIVE + enumerates,
  // which never completes once the LTSSM is sent to DISABLED / LOOPBACK.
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    start_sampling();
    body(phase);
    dump_history();
    phase.drop_objection(this);
  endtask
endclass


//=====================================================================
// Rows 46 / 47 : Detect -> Polling -> Configuration -> L0 bring-up
//=====================================================================
class LTSSM_LinkUp_Reaches_L0_Test extends block_ltssm_base_test;
  `uvm_component_utils(LTSSM_LinkUp_Reaches_L0_Test)
  function new(string name = "LTSSM_LinkUp_Reaches_L0_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    DL_up_env_rx.wait_ptrigger();
    DL_up_env.wait_ptrigger();
    #2ms;
    chk(rc_seen.exists("DETECT_QUIET")   || rc_seen.exists("DETECT_ACTIVE"), "RC passed through Detect");
    chk(rc_seen.exists("POLLING_ACTIVE"),                                    "RC passed through Polling.Active");
    chk(rc_seen.exists("CONFIG_LINKNUM_START") || rc_seen.exists("CONFIG_COMPLETE"), "RC passed through Configuration");
    chk(rc_seen.exists("L0"),                                               "RC reached L0");
    chk(ep_seen.exists("EP_POLLING_ACTIVE"),                                "EP passed through Polling.Active");
    chk(ep_seen.exists("EP_L0"),                                            "EP reached L0");
    chk(RC_Env[0].TX_MAC_Agnt.drv.rc_state.name() == "L0",                  "RC LTSSM resting in L0");
    chk(EP_Env[0].TX_MAC_Agnt.drv.ep_state.name() == "EP_L0",               "EP LTSSM resting in L0");
  endtask
endclass


//=====================================================================
// Rows 49 / 50 : Recovery + speed change (Gen3 : Gen1 -> Recovery ->
//   RcvrLock/RcvrCfg/Speed/Idle -> L0 running at Gen3)
//=====================================================================
class LTSSM_Recovery_SpeedChange_Test extends block_ltssm_base_test;
  `uvm_component_utils(LTSSM_Recovery_SpeedChange_Test)
  function new(string name = "LTSSM_Recovery_SpeedChange_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    DL_up_env_rx.wait_ptrigger();
    DL_up_env.wait_ptrigger();
    #3ms;
    if (rc_cfg[0].gen >= 3) begin
      chk(rc_seen.exists("RECOVERY_RCVRLOCK"), "RC entered Recovery.RcvrLock");
      chk(rc_seen.exists("RECOVERY_RCVRCFG"),  "RC entered Recovery.RcvrCfg");
      chk(rc_seen.exists("RECOVERY_SPEED"),    "RC entered Recovery.Speed");
      chk(rc_seen.exists("RECOVERY_IDLE"),     "RC entered Recovery.Idle");
      chk(rc_seen.exists("L0"),                "RC returned to L0 after Recovery");
      chk(RC_Env[0].TX_MAC_Agnt.drv.rc_active_gen == 3, "RC link now running at Gen3");
      chk(EP_Env[0].TX_MAC_Agnt.drv.ep_active_gen == 3, "EP link now running at Gen3");
    end
    else begin
      `uvm_info("BLK_CHK", "cfg.gen < 3 : no speed change expected - checking link is simply up", UVM_LOW)
      chk(rc_seen.exists("L0"), "RC reached L0 (no recovery at Gen1/2)");
    end
    chk(RC_Env[0].TX_MAC_Agnt.drv.rc_state.name() == "L0", "RC LTSSM resting in L0 after recovery");
  endtask
endclass


//=====================================================================
// Row 54 : Hot Reset (TS1 with HR bit -> Hot Reset -> exit to Detect)
//=====================================================================
class LTSSM_HotReset_Test extends block_ltssm_base_test;
  `uvm_component_utils(LTSSM_HotReset_Test)
  function new(string name = "LTSSM_HotReset_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    `uvm_info("BLK_LTSSM", "directing Hot Reset on RC and EP", UVM_LOW)
    rc_cfg[0].link_ctrl_hot_reset = 1'b1;
    ep_cfg[0].link_ctrl_hot_reset = 1'b1;
    #60ms;   // Detect/Polling/Config bring-up + Recovery + 2ms Hot Reset + margin
    chk(rc_seen.exists("HOT_RESET"),    "RC LTSSM entered HOT_RESET");
    chk(ep_seen.exists("EP_HOT_RESET"), "EP LTSSM entered EP_HOT_RESET");
    `uvm_info("BLK_LTSSM",
      $sformatf("(info) RC TX ordered sets carrying the Hot-Reset control bit: %0d", os_cap.n_hot_reset),
      UVM_LOW);
  endtask
endclass


//=====================================================================
// Row 55 : Loopback (TS1 with LB bit -> Loopback.Entry -> Active ->
//   directed Exit)
//=====================================================================
class LTSSM_Loopback_Test extends block_ltssm_base_test;
  `uvm_component_utils(LTSSM_Loopback_Test)
  function new(string name = "LTSSM_Loopback_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    `uvm_info("BLK_LTSSM", "directing Enter Loopback on RC (master) and EP (slave)", UVM_LOW)
    rc_cfg[0].link_ctrl_enter_loopback = 1'b1;
    ep_cfg[0].link_ctrl_enter_loopback = 1'b1;
    #40ms;
    chk(rc_seen.exists("LOOPBACK_ENTRY"),  "RC LTSSM entered LOOPBACK_ENTRY");
    chk(rc_seen.exists("LOOPBACK_ACTIVE"), "RC LTSSM reached LOOPBACK_ACTIVE");

    `uvm_info("BLK_LTSSM", "directing Loopback.Exit on both sides", UVM_LOW)
    rc_cfg[0].loopback_exit_directed = 1'b1;
    ep_cfg[0].loopback_exit_directed = 1'b1;
    #(rc_cfg[0].loopback_exit_idle_time + 2ms);
    chk(rc_seen.exists("LOOPBACK_EXIT"),   "RC LTSSM reached LOOPBACK_EXIT after directed exit");
    `uvm_info("BLK_LTSSM",
      $sformatf("(info) RC TX ordered sets carrying the Loopback control bit: %0d", os_cap.n_loopback),
      UVM_LOW);
  endtask
endclass


//=====================================================================
// Row 56 : Disabled (16-32 TS1 with Disable Link bit -> Disabled)
//=====================================================================
class LTSSM_Disabled_Test extends block_ltssm_base_test;
  `uvm_component_utils(LTSSM_Disabled_Test)
  function new(string name = "LTSSM_Disabled_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    `uvm_info("BLK_LTSSM", "directing Link Disable on RC and EP", UVM_LOW)
    rc_cfg[0].link_ctrl_disable_link = 1'b1;
    ep_cfg[0].link_ctrl_disable_link = 1'b1;
    #40ms;
    chk(rc_seen.exists("DISABLED"),    "RC LTSSM entered DISABLED");
    chk(ep_seen.exists("EP_DISABLED"), "EP LTSSM entered EP_DISABLED");
    `uvm_info("BLK_LTSSM",
      $sformatf("(info) RC TX ordered sets carrying the Disable-Link control bit: %0d", os_cap.n_disable),
      UVM_LOW);
  endtask
endclass
