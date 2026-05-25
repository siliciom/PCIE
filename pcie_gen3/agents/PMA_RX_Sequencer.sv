class pma_rx_sequencer extends uvm_sequencer #(Sequence_item);
  `uvm_component_utils(pma_rx_sequencer)


  function new(string name = "pma_rx_sequencer", uvm_component parent);
    super.new(name, parent);
endfunction


endclass