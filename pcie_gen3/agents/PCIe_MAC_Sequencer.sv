class PCIe_MAC_Sequencer extends uvm_sequencer #(Sequence_item);
  `uvm_component_utils(PCIe_MAC_Sequencer)


  function new(string name = "PCIe_MAC_Sequencer", uvm_component parent);
    super.new(name, parent);
endfunction


endclass
