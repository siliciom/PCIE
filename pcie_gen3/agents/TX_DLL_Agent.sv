class TX_DLL_Agent extends uvm_agent;
  
  `uvm_component_utils(TX_DLL_Agent)
  
  function new(string name = "TX_DLL_Agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  TX_DLL_Monitor   TX_DLL_Mon;
  TX_DLL_Driver    TX_DLL_Drv;
  TX_DLL_Sequencer TX_DLL_Seqr;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    TX_DLL_Mon  = TX_DLL_Monitor::type_id::create("TX_DLL_Mon", this);
    TX_DLL_Drv  = TX_DLL_Driver::type_id::create("TX_DLL_Drv", this);
    TX_DLL_Seqr = TX_DLL_Sequencer::type_id::create("TX_DLL_Seqr", this);
    
  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    TX_DLL_Drv.seq_item_port.connect(TX_DLL_Seqr.seq_item_export);
    TX_DLL_Mon.TX_MD_ap.connect(TX_DLL_Drv.TX_MD_Recv);
  endfunction : connect_phase
    
endclass : TX_DLL_Agent