class mac_rx_agent extends uvm_agent;

  `uvm_component_utils(mac_rx_agent)

  mac_rx_monitor   mon;
  mac_rx_driver    drv;
  mac_rx_sequencer seqr;

  function new(string name="mac_rx_agent", uvm_component parent=null);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    mon  = mac_rx_monitor  ::type_id::create("mon", this);
    drv  = mac_rx_driver   ::type_id::create("drv", this);
    seqr = mac_rx_sequencer::type_id::create("seqr", this);

  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.item_port.connect(drv.item_imp);

  endfunction

endclass