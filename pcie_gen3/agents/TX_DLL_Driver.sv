class TX_DLL_Driver extends uvm_driver #(Sequence_item);
  
  virtual TX_DLL_PCS_Interface TX_DLL_PCS;
  
  uvm_analysis_imp#(Sequence_item, TX_DLL_Driver) TX_MD_Recv;
  
  `uvm_component_utils(TX_DLL_Driver)
  
  function new(string name = "TX_DLL_Driver", uvm_component parent = null);
    super.new(name, parent);
    TX_MD_Recv  = new("TX_MD_Recv", this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
      begin
        `uvm_fatal("TX_DLL_Driver", "Unable to access the TX_DLL_PCS from config_db")
       end      
    
    else  
      `uvm_info("TX_DLL_Driver", "Successfully accessed the TX_DLL_PCS from config_db", UVM_LOW);
  
  endfunction
  
  function void write(Sequence_item t_x);

  endfunction : write
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
     @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid=1;
    TX_DLL_PCS.dl_tx_ready=1;
    
    TX_DLL_PCS.dl_tx_data=32'hfafafafa;
     @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid=1;
    TX_DLL_PCS.dl_tx_ready=1;
    
    TX_DLL_PCS.dl_tx_data=32'hf5f5f5f5;
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid=1;
    TX_DLL_PCS.dl_tx_ready=1;
    
    TX_DLL_PCS.dl_tx_data=32'hfbfbfbfb;
    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid=0;
    TX_DLL_PCS.dl_tx_ready=0;
    
    
  endtask : run_phase
  
endclass : TX_DLL_Driver