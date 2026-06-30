class PCIe_PMA_Agent extends uvm_agent;
  
  PCIe_PMA_Driver pma_tx_drv;
  PCIe_PMA_Sequencer pma_tx_seqr;
  PCIe_PMA_Monitor pma_tx_mon;
  
  `uvm_component_utils(PCIe_PMA_Agent)
  
  function new (string name = "PCIe_PMA_Agent", uvm_component parent = null);
      super.new(name, parent);
  endfunction 
  
  function void build_phase(uvm_phase phase);
      super.build_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      pma_tx_drv = PCIe_PMA_Driver::type_id::create("pma_tx_drv",this);
      pma_tx_seqr = PCIe_PMA_Sequencer::type_id::create("pma_tx_seqr",this);
       end
    pma_tx_mon =PCIe_PMA_Monitor::type_id::create("pma_tx_mon",this);
  endfunction

 

  
  function  void connect_phase(uvm_phase phase);
	super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      pma_tx_drv.seq_item_port.connect(pma_tx_seqr.seq_item_export);
       end
    pma_tx_mon.pma_tx_port.connect(pma_tx_drv.pma_tx_recv);
  endfunction
  
endclass
