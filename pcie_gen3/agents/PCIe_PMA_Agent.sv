class PCIe_PMA_agent extends uvm_agent;
  
  PCIe_PMA_driver PCIe_PMA_drv;
  PCIe_PMA_sequencer PCIe_PMA_seqr;
  PCIe_PMA_monitor PCIe_PMA_mon;
  
  `uvm_component_utils(PCIe_PMA_agent)
  
  function new (string name = "PCIe_PMA_agent", uvm_component parent = null);
      super.new(name, parent);
  endfunction 
  
  function void build_phase(uvm_phase phase);
      super.build_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      PCIe_PMA_drv = PCIe_PMA_driver::type_id::create("PCIe_PMA_drv",this);
      PCIe_PMA_seqr = PCIe_PMA_sequencer::type_id::create("PCIe_PMA_seqr",this);
       end
    PCIe_PMA_mon =PCIe_PMA_monitor::type_id::create("PCIe_PMA_mon",this);
  endfunction

 

  
  function  void connect_phase(uvm_phase phase);
	super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      PCIe_PMA_drv.seq_item_port.connect(PCIe_PMA_seqr.seq_item_export);
       end
    PCIe_PMA_mon.pma_tx_mac_port.connect(PCIe_PMA_drv.pma_tx_recv_mac);
    PCIe_PMA_mon.pma_tx_rx_port.connect(PCIe_PMA_drv.pma_tx_recv_rx);
    PCIe_PMA_mon.pma_rx_mac_port.connect(PCIe_PMA_drv.pma_rx_recv_mac);
    PCIe_PMA_mon.pma_rx_tx_port.connect(PCIe_PMA_drv.pma_rx_recv_tx);
  endfunction
  
endclass
