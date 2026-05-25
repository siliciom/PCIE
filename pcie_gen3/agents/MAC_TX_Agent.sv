class mac_tx_agent extends uvm_agent;

  `uvm_component_utils(mac_tx_agent)

  mac_tx_monitor   mon;
  mac_tx_driver    drv;
  mac_tx_sequencer seqr;

  function new(string name="mac_tx_agent", uvm_component parent=null);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    mon  = mac_tx_monitor  ::type_id::create("mon", this);
    drv  = mac_tx_driver   ::type_id::create("drv", this);
    seqr = mac_tx_sequencer::type_id::create("seqr", this);

  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.item_port.connect(drv.item_imp);

  endfunction

endclass