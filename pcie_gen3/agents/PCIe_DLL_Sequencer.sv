class PCIe_DLL_Sequencer extends uvm_sequencer #(Sequence_item);
  
  `uvm_component_utils(PCIe_DLL_Sequencer)
  
  function new(string name = "PCIe_DLL_Sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
endclass : PCIe_DLL_Sequencer
