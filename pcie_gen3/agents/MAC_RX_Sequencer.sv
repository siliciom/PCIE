class mac_rx_sequencer extends uvm_sequencer #(Sequence_item);
  `uvm_component_utils(mac_rx_sequencer)


  function new(string name = "mac_rx_sequencer", uvm_component parent);
    super.new(name, parent);
endfunction


endclass