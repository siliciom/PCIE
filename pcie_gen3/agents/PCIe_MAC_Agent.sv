class PCIe_MAC_agent extends uvm_agent;

     `uvm_component_utils(PCIe_MAC_agent)

     PCIe_MAC_monitor   mon;
     PCIe_MAC_driver    drv;
     PCIe_MAC_sequencer seqr;

     function new(string name = "PCIe_MAC_agent", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          mon  = PCIe_MAC_monitor::type_id::create("mon", this);
          drv  = PCIe_MAC_driver::type_id::create("drv", this);
          seqr = PCIe_MAC_sequencer::type_id::create("seqr", this);

     endfunction

     function void connect_phase(uvm_phase phase);
          super.connect_phase(phase);

          drv.seq_item_port.connect(seqr.seq_item_export);
          mon.mac_tx_dll_port.connect(drv.mac_tx_recv_dll);
          mon.mac_tx_rx_port.connect(drv.mac_tx_recv_rx);
          mon.mac_rx_dll_port.connect(drv.mac_rx_recv_dll);
          mon.mac_rx_rx_port.connect(drv.mac_rx_recv_rx);

     endfunction

endclass
