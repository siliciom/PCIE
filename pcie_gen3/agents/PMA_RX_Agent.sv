class pma_rx_agent extends uvm_agent;
  
  pma_rx_driver pma_rx_drv;
  pma_rx_sequencer pma_rx_seqr;
  pma_rx_monitor pma_rx_mon;
  
  `uvm_component_utils(pma_rx_agent)
  
  function new (string name = "pma_rx_agent", uvm_component parent);
      super.new(name, parent);
  endfunction 
  
  function void build_phase(uvm_phase phase);
      super.build_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      pma_rx_drv = pma_rx_driver::type_id::create("pma_rx_drv",this);
      pma_rx_seqr = pma_rx_sequencer::type_id::create("pma_rx_seqr",this);
       end
    pma_rx_mon =pma_rx_monitor::type_id::create("pma_rx_mon",this);
  endfunction

 

  
  function  void connect_phase(uvm_phase phase);
	super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      pma_rx_drv.seq_item_port.connect(pma_rx_seqr.seq_item_export);
       end
    pma_rx_mon.pma_rx_port.connect(pma_rx_drv.pma_rx_recv);
  endfunction
  
endclass
