class PCIe_TL_Agent extends uvm_agent;
  
  `uvm_component_utils(PCIe_TL_Agent)
  
  function new(string name = "PCIe_TL_Agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  PCIe_TL_Monitor   PCIe_TL_Mon;
  PCIe_TL_Driver    PCIe_TL_Drv;
  PCIe_TL_Sequencer PCIe_TL_Seqr;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    PCIe_TL_Mon  = PCIe_TL_Monitor::type_id::create("PCIe_TL_Mon", this);
    PCIe_TL_Drv  = PCIe_TL_Driver::type_id::create("PCIe_TL_Drv", this);
    PCIe_TL_Seqr = PCIe_TL_Sequencer::type_id::create("PCIe_TL_Seqr", this);
    
  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    PCIe_TL_Drv.seq_item_port.connect(PCIe_TL_Seqr.seq_item_export);
  endfunction : connect_phase
  
endclass : PCIe_TL_Agent

    
    
