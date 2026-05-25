class mac_tx_sequencer extends uvm_sequencer #(Sequence_item);
  `uvm_component_utils(mac_tx_sequencer)


  function new(string name = "mac_tx_sequencer", uvm_component parent);
    super.new(name, parent);
endfunction


endclass