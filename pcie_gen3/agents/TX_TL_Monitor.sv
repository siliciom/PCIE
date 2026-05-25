class TX_TL_Monitor extends uvm_monitor;
  
  virtual TX_TL_DL_Interface TX_TL_DL;
  Sequence_item t_x;
  
  uvm_analysis_port #(Sequence_item) TX_TL_Send;
  
  `uvm_component_utils(TX_TL_Monitor)
  
  function new(string name = "TX_TL_Monitor", uvm_component parent = null);
    super.new(name, parent);
    TX_TL_Send = new("TX_TL_Send", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
      begin
        `uvm_fatal("TX_TL_Monitor", "Unable to access the TX_TL_DLL from config_db")
       end      
    
    else  
      `uvm_info("TX_TL_Monitor", "Successfully accessed the TX_TL_DLL from config_db", UVM_LOW);
  
  endfunction
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    // Monitor Logic //
    
    TX_TL_Send.write(t_x);
    
  endtask : run_phase
  
endclass : TX_TL_Monitor
