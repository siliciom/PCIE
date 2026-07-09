typedef enum {RC_MODE, EP_MODE} pcie_mode_e;

class env_cfg extends uvm_object;

  `uvm_object_utils(env_cfg)

  pcie_mode_e mode;

  // gen : highest PCIe generation this side (RC or EP) is configured to
  //       advertise during link training: 1 (2.5 GT/s), 2 (5.0 GT/s) or
  //       3 (8.0 GT/s). Initial training always happens at Gen1; the
  //       negotiated speed is the lower of the two link partners' "gen"
  //       values, decoded from the Rate Identifier byte exchanged in
  //       TS1 ordered sets during POLLING_ACTIVE. If that negotiated
  //       speed is higher than what the link is currently running at,
  //       the LTSSM steps up one generation per RECOVERY pass
  //       (Gen1->Gen2->Gen3) once L0 is reached.
  int unsigned gen = 3;

  function new(string name="env_cfg");
    super.new(name);
  endfunction

  function void check_gen();
    if (!(gen inside {1,2,3}))
      `uvm_fatal("env_cfg",
        $sformatf("gen=%0d is invalid - must be 1 (Gen1), 2 (Gen2) or 3 (Gen3)", gen))
  endfunction

endclass
