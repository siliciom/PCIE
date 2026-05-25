class TX_TL_Agent extends uvm_agent;
  
  `uvm_component_utils(TX_TL_Agent)
  
  function new(string name = "TX_TL_Agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  TX_TL_Monitor   TX_TL_Mon;
  TX_TL_Driver    TX_TL_Drv;
  TX_TL_Sequencer TX_TL_Seqr;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    TX_TL_Mon  = TX_TL_Monitor::type_id::create("TX_TL_Mon", this);
    TX_TL_Drv  = TX_TL_Driver::type_id::create("TX_TL_Drv", this);
    TX_TL_Seqr = TX_TL_Sequencer::type_id::create("TX_TL_Seqr", this);
    
  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    TX_TL_Drv.seq_item_port.connect(TX_TL_Seqr.seq_item_export);
  endfunction : connect_phase
  
endclass : TX_TL_Agent

    
    