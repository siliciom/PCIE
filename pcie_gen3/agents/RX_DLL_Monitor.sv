class RX_DLL_Monitor extends uvm_monitor;
  
  virtual RX_DLL_PCS_Interface RX_DLL_PCS;
  virtual RX_TL_DL_Interface RX_TL_DL;
  
  Sequence_item t_x;
  
  uvm_analysis_port #(Sequence_item) RX_MD_ap;
  
  `uvm_component_utils(RX_DLL_Monitor)
  
  function new(string name = "RX_DLL_Monitor", uvm_component parent = null);
    super.new(name, parent);
    RX_MD_ap = new("RX_MD_ap", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
      begin
        `uvm_fatal("RX_DLL_Monitor", "Unable to access the RX_TL_DL from config_db")
       end      
    
    else  
      `uvm_info("RX_DLL_Monitor", "Successfully accessed the RX_TL_DL from config_db", UVM_LOW);
    
    if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
      begin
        `uvm_fatal("RX_DLL_Monitor", "Unable to access the RX_DLL_PCS from config_db")
       end      
    
    else  
      `uvm_info("RX_DLL_Monitor", "Successfully accessed the RX_DLL_PCS from config_db", UVM_LOW);
  
  endfunction
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    // Monitor Logic //
    
    RX_MD_ap.write(t_x);

    
  endtask : run_phase
  
endclass : RX_DLL_Monitor