class PCIe_MAC_Agent extends uvm_agent;

  `uvm_component_utils(PCIe_MAC_Agent)

  PCIe_MAC_Monitor   mon;
  PCIe_MAC_Driver    drv;
  PCIe_MAC_Sequencer seqr;

  function new(string name="PCIe_MAC_Agent", uvm_component parent=null);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    mon  = PCIe_MAC_Monitor  ::type_id::create("mon", this);
    drv  = PCIe_MAC_Driver   ::type_id::create("drv", this);
    seqr = PCIe_MAC_Sequencer::type_id::create("seqr", this);

  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.item_port.connect(drv.item_imp);

  endfunction

endclass
