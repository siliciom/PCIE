class RX_TL_Driver extends uvm_driver #(Sequence_item);
  
  virtual RX_TL_DL_Interface RX_TL_DL;
  uvm_analysis_imp#(Sequence_item, RX_TL_Driver) RX_DRV_Recv;
  
  `uvm_component_utils(RX_TL_Driver)
  
  function new(string name = "RX_TL_Driver", uvm_component parent = null);
    super.new(name, parent);
    RX_DRV_Recv = new("RX_DRV_Recv", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
      begin
        `uvm_fatal("RX_TL_Driver", "Unable to access the RX_TL_DLL from config_db")
       end      
    
    else  
      `uvm_info("RX_TL_Driver", "Successfully accessed the RX_TL_DLL from config_db", UVM_LOW);
  
  endfunction
  
  function void write(Sequence_item t_x);
    // PCIe Ordering Checker Logic //
  endfunction : write
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    forever begin
      seq_item_port.get_next_item(req);
      // Driver Logic //
      seq_item_port.item_done(req);
    end
    
  endtask : run_phase
  
endclass : RX_TL_Driver
