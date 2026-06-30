typedef enum {RC_MODE, EP_MODE} pcie_mode_e;

// env_cfg
//   mode : RC_MODE or EP_MODE - which role this Env_Top plays.
//          That is the only thing a driver/monitor needs from
//          this object to decide how to behave.

class env_cfg extends uvm_object;

  `uvm_object_utils(env_cfg)

  pcie_mode_e mode;

  function new(string name="env_cfg");
    super.new(name);
  endfunction

endclass
