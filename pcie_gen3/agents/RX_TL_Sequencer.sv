class RX_TL_Sequencer extends uvm_sequencer #(Sequence_item);
  
  `uvm_component_utils(RX_TL_Sequencer)
  
  function new(string name = "RX_TL__Sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
endclass : RX_TL_Sequencer 