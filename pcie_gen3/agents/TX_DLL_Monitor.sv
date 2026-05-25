class TX_DLL_Monitor extends uvm_monitor;
  
  virtual TX_TL_DL_Interface TX_TL_DL;
  virtual TX_DLL_PCS_Interface TX_DLL_PCS;
  
  Sequence_item t_x;
  
  uvm_analysis_port #(Sequence_item) TX_MD_ap;
  
  `uvm_component_utils(TX_DLL_Monitor)
  
  function new(string name = "TX_DLL_Monitor", uvm_component parent = null);
    super.new(name, parent);
    TX_MD_ap = new("TX_MD_ap", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
      begin
        `uvm_fatal("TX_DLL_Monitor", "Unable to access the TX_TL_DLL from config_db")
       end      
    
    else  
      `uvm_info("TX_DLL_Monitor", "Successfully accessed the TX_TL_DLL from config_db", UVM_LOW);
    
    if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
      begin
        `uvm_fatal("TX_DLL_Monitor", "Unable to access the TX_DLL_PCS from config_db")
       end      
    
    else  
      `uvm_info("TX_DLL_Monitor", "Successfully accessed the TX_DLL_PCS from config_db", UVM_LOW);
  
  endfunction
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    
      TX_MD_ap.write(t_x);
    
  endtask : run_phase
    
endclass : TX_DLL_Monitor