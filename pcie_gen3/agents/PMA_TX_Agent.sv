class pma_tx_agent extends uvm_agent;
  
  pma_tx_driver pma_tx_drv;
  pma_tx_sequencer pma_tx_seqr;
  pma_tx_monitor pma_tx_mon;
  
  `uvm_component_utils(pma_tx_agent)
  
  function new (string name = "pma_tx_agent", uvm_component parent = null);
      super.new(name, parent);
  endfunction 
  
  function void build_phase(uvm_phase phase);
      super.build_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      pma_tx_drv = pma_tx_driver::type_id::create("pma_tx_drv",this);
      pma_tx_seqr = pma_tx_sequencer::type_id::create("pma_tx_seqr",this);
       end
    pma_tx_mon =pma_tx_monitor::type_id::create("pma_tx_mon",this);
  endfunction

 

  
  function  void connect_phase(uvm_phase phase);
	super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      pma_tx_drv.seq_item_port.connect(pma_tx_seqr.seq_item_export);
       end
    pma_tx_mon.pma_tx_port.connect(pma_tx_drv.pma_tx_recv);
  endfunction
  
endclass
