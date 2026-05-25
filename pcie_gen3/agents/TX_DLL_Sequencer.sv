class TX_DLL_Sequencer extends uvm_sequencer #(Sequence_item);
  
  `uvm_component_utils(TX_DLL_Sequencer)
  
  function new(string name = "TX_DLL_Sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
endclass : TX_DLL_Sequencer