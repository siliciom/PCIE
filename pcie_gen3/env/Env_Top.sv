class Env_Top extends uvm_env;

  `uvm_component_utils(Env_Top)

  function new(string name = "Env_Top", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  env_cfg cfg;
 DL_Scoreboard  DL_Scb;
 PCIe_TL_Coverage pcie_cov;

  PCIe_TL_Agent  PCIe_TL_Agnt;
  PCIe_DLL_Agent PCIe_DLL_Agnt;
  PCIe_MAC_agent TX_MAC_Agnt;
  PCIe_PMA_agent TX_PMA_Agnt;

  TL_Scoreboard TL_Scb;
  PCIe_MAC_Scoreboard mac_scb;

  VC_Arbiter Vc_Arb;
  
  FC_Manager FC_mgr;
 
  agent_apb_master                         Apb_Master_Agnt;
  apb_slv_agent                            Apb_Slave_Agnt;    
  PCIe_Cfg_Space_Model                     cfg_model;           
  pcie_type0_cfg_reg_block                 Ral;
//  pcie_type1_cfg_reg_block                 Ral_type1;
  apb_reg_adapter                          Reg2Apb;
  uvm_reg_predictor #(seq_item_apb_master) Apb_Predictor;
 // uvm_reg_predictor #(seq_item_apb_master) Apb_Predictor1;

 

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
 if  (!uvm_config_db#(DL_Scoreboard)::get(this, "", "DL_Scb", DL_Scb))
      `uvm_fatal("Env_Top",
        $sformatf("DL_Scoreboard handle not found for %s", get_full_name()))


	    if  (!uvm_config_db#(PCIe_TL_Coverage)::get(this, "", "pcie_cov",  pcie_cov))
      `uvm_fatal("Env_Top",
        $sformatf("subscriber handle not found for %s", get_full_name()))




cfg_model = PCIe_Cfg_Space_Model::type_id::create("cfg_model");
cfg_model.init();
uvm_config_db#(PCIe_Cfg_Space_Model)::set(this, "*", "cfg_model", cfg_model);
 if (!uvm_config_db#(PCIe_MAC_Scoreboard)::get(this, "", "mac_scb", mac_scb))
      `uvm_fatal("Env_Top",
        $sformatf("PCIe_MAC_Scoreboard handle not found for %s", get_full_name()))


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

        // ---- ADDED: build RAL + APB agent only for the endpoint ----
    // (Type0 config header belongs to the EP; if your RC also needs
    //  a reg model, mirror this same block under an RC_MODE check.)
    if (cfg.mode == EP_MODE) begin
      uvm_config_db#(uvm_active_passive_enum)::set(this, "Apb_Master_Agnt", "is_active", UVM_ACTIVE);
      Apb_Master_Agnt = agent_apb_master::type_id::create("Apb_Master_Agnt", this);

       Apb_Slave_Agnt = apb_slv_agent::type_id::create("Apb_Slave_Agnt", this);   // ← add this line

      Ral = pcie_type0_cfg_reg_block::type_id::create("Ral");
      Ral.build();
      Ral.lock_model();
      Reg2Apb = apb_reg_adapter::type_id::create("Reg2Apb");
      Apb_Predictor = uvm_reg_predictor#(seq_item_apb_master)::type_id::create("Apb_Predictor", this);

     //  Ral_type1 =  pcie_type1_cfg_reg_block::type_id::create("Ral_type1");
     //  Ral_type1.build();
     //  Ral_type1.lock_model();
    //   Apb_Predictor1 = uvm_reg_predictor#(seq_item_apb_master)::type_id::create("Apb_Predictor1",this);
    
    end
    
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (cfg.mode == RC_MODE) begin
      PCIe_TL_Agnt.TX_TL_Mon.TX_TL_Send.connect(TL_Scb.TX_TL_Recv);
       PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_tx.connect(DL_Scb.rc_tx_imp);
      PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_rx.connect(DL_Scb.rc_rx_imp);
PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_dllp_tx.connect(DL_Scb.rc_dllp_tx_imp);
  PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_dllp_rx.connect(DL_Scb.rc_dllp_rx_imp);

      //TX_MAC_Agnt.mon.mac_sb_rc_port.connect(MAC_Scb.Mac_rc_recv);
      // RX_TL_Send and RX_TL_MON_Send never fire in RC mode — no connection needed
      TX_MAC_Agnt.mon.mac_sb_rc_tx_port.connect(mac_scb.rc_tx_imp);
      TX_MAC_Agnt.mon.mac_sb_rc_rx_port.connect(mac_scb.rc_rx_imp);
      PCIe_TL_Agnt.TX_TL_Mon.TX_TL_Send.connect(pcie_cov.TX_TL_Recvx);

    end else begin
      // EP_MODE
      PCIe_TL_Agnt.TX_TL_Mon.RX_TL_Send.connect(TL_Scb.RX_TL_Recv);
       TX_MAC_Agnt.mon.mac_sb_ep_tx_port.connect(mac_scb.ep_tx_imp);
      TX_MAC_Agnt.mon.mac_sb_ep_rx_port.connect(mac_scb.ep_rx_imp);

      PCIe_DLL_Agnt.PCIe_DLL_Mon.ep_tx.connect(DL_Scb.ep_tx_imp);
      PCIe_DLL_Agnt.PCIe_DLL_Mon.ep_rx.connect(DL_Scb.ep_rx_imp);
       PCIe_TL_Agnt.TX_TL_Mon.RX_TL_Send.connect(pcie_cov.RX_TL_Recvx);


      PCIe_DLL_Agnt.PCIe_DLL_Mon.ep_dllp_tx.connect(DL_Scb.ep_dllp_tx_imp);
  PCIe_DLL_Agnt.PCIe_DLL_Mon.ep_dllp_rx.connect(DL_Scb.ep_dllp_rx_imp);


       // ---- ADDED: RAL <-> APB agent wiring ----
      Ral.default_map.set_sequencer(Apb_Master_Agnt.sequencer, Reg2Apb);
      Apb_Predictor.map     = Ral.default_map;
      Apb_Predictor.adapter = Reg2Apb;
      Apb_Master_Agnt.monitor.item_port.connect(Apb_Predictor.bus_in);

     // Ral_type1.default_map.set_sequencer(Apb_Master_Agnt.sequencer, Reg2Apb);
   //   Apb_Predictor1.adapter = Reg2Apb;
   //   Apb_Predictor1.map = Ral_type1.default_map;
  //    Apb_Master_Agnt.monitor.item_port.connect(Apb_Predictor1.bus_in);  

       end

  endfunction : connect_phase

  task run_phase(uvm_phase phase);
  without_wait_state slv_seq;
  if (cfg.mode == EP_MODE) begin
    fork
      forever begin
        slv_seq = without_wait_state::type_id::create("slv_seq");
        assert(slv_seq.randomize() with { cnt == 500; });
        slv_seq.start(Apb_Slave_Agnt.sequencer);
      end
    join_none
  end
endtask : run_phase



endclass : Env_Top
