class RX_TL_Agent extends uvm_agent;
  
  `uvm_component_utils(RX_TL_Agent)
  
  function new(string name = "RX_TL_Agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  RX_TL_Monitor   RX_TL_Mon;
  RX_TL_Driver    RX_TL_Drv;
  RX_TL_Sequencer RX_TL_Seqr;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    RX_TL_Mon  = RX_TL_Monitor::type_id::create("RX_TL_Mon", this);
    RX_TL_Drv  = RX_TL_Driver::type_id::create("RX_TL_Drv", this);
    RX_TL_Seqr = RX_TL_Sequencer::type_id::create("RX_TL_Seqr", this);
    
  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    RX_TL_Drv.seq_item_port.connect(RX_TL_Seqr.seq_item_export);
    RX_TL_Mon.RX_TL_MON_Send.connect(RX_TL_Drv.RX_DRV_Recv);
  endfunction : connect_phase
  
endclass : RX_TL_Agent

    
    