class PCIe_MAC_sequencer extends uvm_sequencer #(Sequence_item);
  `uvm_component_utils(PCIe_MAC_sequencer)


  function new(string name = "PCIe_MAC_sequencer", uvm_component parent);
    super.new(name, parent);
endfunction


endclass
