typedef enum {RC_MODE, EP_MODE} pcie_mode_e;

class env_cfg extends uvm_object;

  `uvm_object_utils(env_cfg)

  pcie_mode_e mode;

  int unsigned gen = 3;
  

  //-----------------------------------------------------------
  // TC -> VC mapping table (models the VC Resource Control
  // register's TC/VC map bits). Index = tc (0-7), value = the
  // VC that TC is routed into. Default: identity mapping
  // (tc == vc), i.e. every TC gets its own VC.
  //
  // Example alternate mappings a test might install:
  //   all-to-VC0          : '{VC0,VC0,VC0,VC0,VC0,VC0,VC0,VC0}
  //   isochronous vs best  : TC0-3 -> VC0, TC4-7 -> VC1
  //   effort split
  //-----------------------------------------------------------
   int unsigned num_lanes        = `PCIE_NUM_LANES;
  bit [`PCIE_NUM_LANES-1:0] active_lane_mask = {`PCIE_NUM_LANES{1'b1}};

  //-----------------------------------------------------------
  // LTSSM timing parameters (PCIe Base Spec 3.0 Table in each
  // sub-state's description). Defaults below are the spec values;
  // override in a test/sequence via uvm_config_db if you need
  // faster sim turnaround.
  //-----------------------------------------------------------
  time detect_quiet_timeout   = 2ms;    // Detect.Quiet time-out (spec: 12ms max, entry condition)
  time detect_active_timeout  = 12ms;    // Receiver Detection watchdog per attempt
  time detect_retry_timeout   = 12ms;    // Wait before re-running detection on partial-lane mismatch
  time polling_active_timeout = 5ms;    // Polling.Active overall watchdog (spec: 24ms)
  time polling_configuration_timeout = 12ms;
  time config_linknum_start_timeout  = 5ms;    // spec: 24ms
  time config_linknum_accept_timeout = 1ms;    // spec: 2ms
  time config_lanenum_wait_timeout   = 1ms;    // spec: 2ms
  time config_lanenum_accept_timeout = 1ms;    // spec: 2ms (unconfirmed bound - see note above)
  time config_complete_timeout       = 1ms;    // spec: 2ms
  time config_idle_timeout           = 1ms;    // spec: min 2ms
  //-----------------------------------------------------------

  time recovery_rcvrlock_timeout     = 5ms;    // spec: 24ms
  time recovery_speed_timeout        = 8ms;    // spec: 48ms
  time recovery_rcvrcfg_timeout      = 8ms;    // spec: 48ms
  time recovery_idle_timeout         = 1ms;    // spec: 2ms
  time recovery_speed_settle_time    = 800ns;
  bit link_ctrl2_enter_compliance = 1'b0;
  bit link_ctrl_disable_link = 1'b0;

  int unsigned disabled_ts1_count = 16;   // spec: 16 to 32 TS1s sent with Disable Link asserted

  bit          link_ctrl_enter_loopback   = 1'b0;
  bit          loopback_exit_directed     = 1'b0;
  int unsigned loopback_entry_ts1_count   = 16;   // spec: master TS1 burst in Entry
  time         loopback_entry_timeout     = 5ms;  // spec: <100ms implementation-specific bound
  time         loopback_active_timeout    = 5ms;  // bound while waiting for directed exit
  time         loopback_exit_idle_time    = 2ms;  // spec: 2ms Electrical Idle in Exit

  bit          link_ctrl_hot_reset       = 1'b0;
  bit          hot_reset_remain_directed = 1'b0;
  int unsigned hot_reset_ts1_count       = 16;
  time         hot_reset_timeout         = 2ms;  
  rand vc_id_e tc2vc_table[8];

  function new(string name="env_cfg");
    super.new(name);
    tc2vc_table = '{VC0, VC1, VC2, VC3, VC4, VC5, VC6, VC7};
  endfunction

  // Pushes this cfg's table into Sequence_item's static table so
  // every item randomized after this call maps tc->vc consistently.
  function void apply_tc2vc_map();
    Sequence_item::tc2vc_table = tc2vc_table;
  endfunction

  function void check_gen();
    if (!(gen inside {1,2,3}))
      `uvm_fatal("env_cfg",
        $sformatf("gen=%0d is invalid - must be 1 (Gen1), 2 (Gen2) or 3 (Gen3)", gen))
  endfunction
  function void check_lanes();
    if(num_lanes == 0 || num_lanes > `PCIE_NUM_LANES)
      `uvm_fatal("env_cfg",
        $sformatf("num_lanes=%0d is invalid - must be 1..%0d (`PCIE_NUM_LANES)",
                    num_lanes, `PCIE_NUM_LANES))
    if(!active_lane_mask[0])
      `uvm_fatal("env_cfg",
        "active_lane_mask[0] must be set - PCIe_PMA_Monitor.sv samples lane 0 as the representative lane under the broadcast model")
  endfunction

endclass

