class pma_tx_sequencer extends uvm_sequencer #(Sequence_item);
  `uvm_component_utils(pma_tx_sequencer)


  function new(string name = "pma_tx_sequencer", uvm_component parent = null );
    super.new(name, parent);
endfunction


endclass