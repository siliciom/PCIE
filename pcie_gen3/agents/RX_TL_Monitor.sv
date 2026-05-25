class RX_TL_Monitor extends uvm_monitor;
  
  virtual RX_TL_DL_Interface RX_TL_DL;
  Sequence_item t_x;
  
  uvm_analysis_port #(Sequence_item) RX_TL_Send;
  uvm_analysis_port #(Sequence_item) RX_TL_MON_Send;
  
  `uvm_component_utils(RX_TL_Monitor)
  
  function new(string name = "RX_TL_Monitor", uvm_component parent = null);
    super.new(name, parent);
    RX_TL_Send     = new("RX_TL_Send", this);
    RX_TL_MON_Send = new("RX_TL_MON_Send", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
      begin
        `uvm_fatal("RX_TL_Monitor", "Unable to access the RX_TL_DLL from config_db")
       end      
    
    else  
      `uvm_info("RX_TL_Monitor", "Successfully accessed the RX_TL_DLL from config_db", UVM_LOW);
  
  endfunction
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    // Monitor Logic //
    
    RX_TL_Send.write(t_x);
    RX_TL_MON_Send.write(t_x);
    
  endtask : run_phase
  
endclass : RX_TL_Monitor
