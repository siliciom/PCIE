class Env_Top extends uvm_env;

  `uvm_component_utils(Env_Top)

  function new(string name = "Env_Top", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  env_cfg cfg;

  PCIe_TL_Agent  PCIe_TL_Agnt;
  PCIe_DLL_Agent PCIe_DLL_Agnt;
  PCIe_MAC_agent TX_MAC_Agnt;
  PCIe_PMA_agent TX_PMA_Agnt;

  TL_Scoreboard TL_Scb;

  VC_Arbiter Vc_Arb;
  
  FC_Manager FC_mgr;
  

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("Env_Top",
        $sformatf("env_cfg not found for %s", get_full_name()))
    else
      `uvm_info("Env_Top",
        $sformatf("%s configured as mode=%s",
                   get_full_name(), cfg.mode.name()), UVM_LOW)

    if (!uvm_config_db#(TL_Scoreboard)::get(this, "", "TL_Scb", TL_Scb))
      `uvm_fatal("Env_Top",
        $sformatf("TL_Scoreboard handle not found for %s", get_full_name()))


    // Get the shared TL_Scoreboard handle set by pcie_base_test
   	
   cfg.apply_tc2vc_map(); 
    // PCIe_LUT is local to each env — EP driver gets it via lut_handle
    FC_mgr     = FC_Manager::type_id::create("FC_mgr", this);
    uvm_config_db #(FC_Manager)::set(this, "*", "fc_mgr", FC_mgr);
    
Vc_Arb     = VC_Arbiter::type_id::create("Vc_Arb", this);
    uvm_config_db #(VC_Arbiter)::set(this, "*", "vc_arb", Vc_Arb);

    PCIe_TL_Agnt  = PCIe_TL_Agent::type_id::create("PCIe_TL_Agnt",  this);
    PCIe_DLL_Agnt = PCIe_DLL_Agent::type_id::create("PCIe_DLL_Agnt", this);
    TX_MAC_Agnt = PCIe_MAC_agent::type_id::create("TX_MAC_Agnt", this);
    TX_PMA_Agnt = PCIe_PMA_agent::type_id::create("TX_PMA_Agnt", this);

    
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (cfg.mode == RC_MODE) begin
      PCIe_TL_Agnt.TX_TL_Mon.TX_TL_Send.connect(TL_Scb.TX_TL_Recv);
      //TX_MAC_Agnt.mon.mac_sb_rc_port.connect(MAC_Scb.Mac_rc_recv);
      // RX_TL_Send and RX_TL_MON_Send never fire in RC mode — no connection needed
    end else begin
      // EP_MODE
      PCIe_TL_Agnt.TX_TL_Mon.RX_TL_Send.connect(TL_Scb.RX_TL_Recv);
            // TX_TL_Send never fires in EP mode — no connection needed
       end

  endfunction : connect_phase

endclass : Env_Top
