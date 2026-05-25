class RX_DLL_Agent extends uvm_agent;
  
  `uvm_component_utils(RX_DLL_Agent)
  
  function new(string name = "RX_DLL_Agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  RX_DLL_Monitor   RX_DLL_Mon;
  RX_DLL_Driver    RX_DLL_Drv;
  RX_DLL_Sequencer RX_DLL_Seqr;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    RX_DLL_Mon  = RX_DLL_Monitor::type_id::create("RX_DLL_Mon", this);
    RX_DLL_Drv  = RX_DLL_Driver::type_id::create("RX_DLL_Drv", this);
    RX_DLL_Seqr = RX_DLL_Sequencer::type_id::create("RX_DLL_Seqr", this);
    
  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    RX_DLL_Drv.seq_item_port.connect(RX_DLL_Seqr.seq_item_export);
    RX_DLL_Mon.RX_MD_ap.connect(RX_DLL_Drv.RX_MD_Recv);
  endfunction : connect_phase
    
endclass : RX_DLL_Agent