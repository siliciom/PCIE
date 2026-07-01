typedef enum {RC_MODE, EP_MODE} pcie_mode_e;

class env_cfg extends uvm_object;

  `uvm_object_utils(env_cfg)

  pcie_mode_e mode;

  function new(string name="env_cfg");
    super.new(name);
  endfunction

endclass
