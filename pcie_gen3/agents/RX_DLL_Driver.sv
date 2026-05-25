class RX_DLL_Driver extends uvm_driver #(Sequence_item);
  
  virtual RX_DLL_PCS_Interface RX_DLL_PCS;
  
  uvm_analysis_imp#(Sequence_item, RX_DLL_Driver) RX_MD_Recv;
  
  `uvm_component_utils(RX_DLL_Driver)
  
  function new(string name = "RX_DLL_Driver", uvm_component parent = null);
    super.new(name, parent);
    RX_MD_Recv  = new("RX_MD_Recv", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
      begin
        `uvm_fatal("RX_DLL_Driver", "Unable to access the RX_DLL_PCS from config_db")
       end      
    
    else  
      `uvm_info("RX_DLL_Driver", "Successfully accessed the RX_DLL_PCS from config_db", UVM_LOW);
  
  endfunction
  
  function void write(Sequence_item t_x);

  endfunction : write
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    forever begin
      seq_item_port.get_next_item(req);
      // Driver Logic //
      seq_item_port.item_done(req);
    end
    
  endtask : run_phase
  
endclass : RX_DLL_Driver