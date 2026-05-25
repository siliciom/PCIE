class TX_Env extends uvm_env;
  
  `uvm_component_utils(TX_Env)
  
  function new(string name = "TX_Env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  TX_TL_Agent  TX_TL_Agnt;
  TX_DLL_Agent TX_DLL_Agnt;
  mac_tx_agent TX_MAC_Agnt;
  pma_tx_agent TX_PMA_Agnt;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    TX_TL_Agnt  = TX_TL_Agent::type_id::create("TX_TL_Agnt", this);
    `uvm_info("ORDER", "Creating TX_TL", UVM_NONE)
    TX_DLL_Agnt = TX_DLL_Agent::type_id::create("TX_DLL_Agnt", this);
    `uvm_info("ORDER", "Creating TX_DLL", UVM_NONE)
    TX_MAC_Agnt = mac_tx_agent::type_id::create("TX_MAC_Agnt", this);
    `uvm_info("ORDER", "Creating TX_MAC", UVM_NONE)
    TX_PMA_Agnt = pma_tx_agent::type_id::create("TX_PMA_Agnt", this);
    `uvm_info("ORDER", "Creating TX_PMA", UVM_NONE)
    
  endfunction : build_phase
  
endclass : TX_Env 
  
  