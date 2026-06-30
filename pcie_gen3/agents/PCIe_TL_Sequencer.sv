class PCIe_TL_Sequencer extends uvm_sequencer #(Sequence_item);
  
  `uvm_component_utils(PCIe_TL_Sequencer)
  
  function new(string name = "PCIe_TL_Sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
endclass : PCIe_TL_Sequencer 
