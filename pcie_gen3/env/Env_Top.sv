class Env_Top extends uvm_env;

  `uvm_component_utils(Env_Top)

  function new(string name = "Env_Top", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  env_cfg cfg;

  TL_Scoreboard  TL_Scb;

  PCIe_TL_Agent  PCIe_TL_Agnt;
  PCIe_DLL_Agent PCIe_DLL_Agnt;
  PCIe_MAC_agent TX_MAC_Agnt;
  PCIe_PMA_agent TX_PMA_Agnt;

  RX_PCIe_LUT PCIe_LUT;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("Env_Top",
        $sformatf("env_cfg not found for %s", get_full_name()))
    else
      `uvm_info("Env_Top",
        $sformatf("%s configured as mode=%s",
                   get_full_name(), cfg.mode.name()), UVM_LOW)

    // Get the shared TL_Scoreboard handle set by pcie_base_test
    if (!uvm_config_db#(TL_Scoreboard)::get(this, "", "TL_Scb", TL_Scb))
      `uvm_fatal("Env_Top",
        $sformatf("TL_Scoreboard handle not found for %s", get_full_name()))

    // PCIe_LUT is local to each env — EP driver gets it via lut_handle
    PCIe_LUT = RX_PCIe_LUT::type_id::create("PCIe_LUT", this);
    uvm_config_db#(RX_PCIe_LUT)::set(this, "*", "lut_handle", PCIe_LUT);

    PCIe_TL_Agnt  = PCIe_TL_Agent::type_id::create("PCIe_TL_Agnt",  this);
    PCIe_DLL_Agnt = PCIe_DLL_Agent::type_id::create("PCIe_DLL_Agnt", this);
    TX_MAC_Agnt = PCIe_MAC_agent::type_id::create("TX_MAC_Agnt", this);
    TX_PMA_Agnt = PCIe_PMA_agent::type_id::create("TX_PMA_Agnt", this);

  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (cfg.mode == RC_MODE) begin
      PCIe_TL_Agnt.PCIe_TL_Mon.TX_TL_Send.connect(TL_Scb.TX_TL_Recv);
      // RX_TL_Send and RX_TL_MON_Send never fire in RC mode — no connection needed
    end else begin
      // EP_MODE
      PCIe_TL_Agnt.PCIe_TL_Mon.RX_TL_Send.connect(TL_Scb.RX_TL_Recv);
      PCIe_TL_Agnt.PCIe_TL_Mon.RX_TL_MON_Send.connect(PCIe_LUT.RX_LUT_imp);
      // TX_TL_Send never fires in EP mode — no connection needed
    end

  endfunction : connect_phase

endclass : Env_Top
