class RX_Env extends uvm_env;
  
  `uvm_component_utils(RX_Env)
  
  function new(string name = "RX_Env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  RX_TL_Agent  RX_TL_Agnt;
  RX_DLL_Agent RX_DLL_Agnt;
  mac_rx_agent RX_MAC_Agnt;
  pma_rx_agent RX_PMA_Agnt;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    RX_TL_Agnt = RX_TL_Agent::type_id::create("RX_TL_Agnt", this);
    `uvm_info("ORDER", "Creating RX_TL", UVM_NONE)
    RX_DLL_Agnt = RX_DLL_Agent::type_id::create("RX_DLL_Agnt", this);
    `uvm_info("ORDER", "Creating RX_DLL", UVM_NONE)
    RX_MAC_Agnt = mac_rx_agent::type_id::create("RX_MAC_Agnt", this);
    `uvm_info("ORDER", "Creating RX_MACL", UVM_NONE)
    RX_PMA_Agnt = pma_rx_agent::type_id::create("RX_PMA_Agnt", this);
    `uvm_info("ORDER", "Creating RX_PMA", UVM_NONE)
    
  endfunction : build_phase
  
endclass : RX_Env 
  
  