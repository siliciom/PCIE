class Env_Top extends uvm_env;

  `uvm_component_utils(Env_Top)

  function new(string name = "Env_Top", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  env_cfg cfg;

  Scoreboard_Top Top_Scb;
  TL_Scoreboard  TL_Scb;

  PCIe_TL_Agent  PCIe_TL_Agnt;
  PCIe_DLL_Agent PCIe_DLL_Agnt;
  PCIe_MAC_Agent TX_MAC_Agnt;
  PCIe_PMA_Agent TX_PMA_Agnt;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

   /* if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("Env_Top",
        $sformatf("env_cfg not found for %s - test must set it scoped to this instance",get_full_name()))
    else
      `uvm_info("Env_Top",$sformatf("%s configured as mode=%s",get_full_name(), cfg.mode.name()), UVM_LOW)
*/
    PCIe_TL_Agnt  = PCIe_TL_Agent::type_id::create("PCIe_TL_Agnt", this);
    PCIe_DLL_Agnt = PCIe_DLL_Agent::type_id::create("PCIe_DLL_Agnt", this);
    TX_MAC_Agnt = PCIe_MAC_Agent::type_id::create("TX_MAC_Agnt", this);
    TX_PMA_Agnt = PCIe_PMA_Agent::type_id::create("TX_PMA_Agnt", this);

    Top_Scb = Scoreboard_Top::type_id::create("Top_Scb", this);
    TL_Scb  = TL_Scoreboard::type_id::create("TL_Scb", this);

  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    PCIe_TL_Agnt.PCIe_TL_Mon.TX_TL_Send.connect(TL_Scb.TX_TL_Recv);
    TL_Scb.TL_Scb_Send.connect(Top_Scb.TL_Scb_Recv);
  endfunction : connect_phase

endclass : Env_Top
