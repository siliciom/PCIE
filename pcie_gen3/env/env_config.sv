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
  // Link Control 2 register, bit 4 (Enter Compliance). Not modeled
  // as a real register yet - flip this directly from a test/sequence
  // to force immediate/mid-state transition to Polling.Compliance.
  bit link_ctrl2_enter_compliance = 1'b0;
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

