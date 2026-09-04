class PCIe_DLL_Agent extends uvm_agent;

     `uvm_component_utils(PCIe_DLL_Agent)

     function new(string name = "PCIe_DLL_Agent", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     PCIe_DLL_Monitor   PCIe_DLL_Mon;
     PCIe_DLL_Driver    PCIe_DLL_Drv;
     PCIe_DLL_Sequencer PCIe_DLL_Seqr;

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          PCIe_DLL_Mon  = PCIe_DLL_Monitor::type_id::create("PCIe_DLL_Mon", this);
          PCIe_DLL_Drv  = PCIe_DLL_Driver::type_id::create("PCIe_DLL_Drv", this);
          PCIe_DLL_Seqr = PCIe_DLL_Sequencer::type_id::create("PCIe_DLL_Seqr", this);

     endfunction : build_phase

     function void connect_phase(uvm_phase phase);
          super.connect_phase(phase);
          PCIe_DLL_Drv.seq_item_port.connect(PCIe_DLL_Seqr.seq_item_export);

          PCIe_DLL_Mon.rc_TX_MD_ap.connect(PCIe_DLL_Drv.rc_TX_MD_Recv);
          PCIe_DLL_Mon.rc_RX_MD_ap.connect(PCIe_DLL_Drv.rc_RX_MD_Recv);
          PCIe_DLL_Mon.ep_TX_MD_ap.connect(PCIe_DLL_Drv.ep_TX_MD_Recv);
          PCIe_DLL_Mon.ep_RX_MD_ap.connect(PCIe_DLL_Drv.ep_RX_MD_Recv);
          PCIe_DLL_Mon.rc_FC_MD_ap.connect(PCIe_DLL_Drv.rc_FC_MD_Recv);
          PCIe_DLL_Mon.ep_FC_MD_ap.connect(PCIe_DLL_Drv.ep_FC_MD_Recv);
     endfunction : connect_phase

endclass : PCIe_DLL_Agent
