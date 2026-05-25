class RX_DLL_Sequencer extends uvm_sequencer #(Sequence_item);
  
  `uvm_component_utils(RX_DLL_Sequencer)
  
  function new(string name = "RX_DLL_Sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
endclass : RX_DLL_Sequencer