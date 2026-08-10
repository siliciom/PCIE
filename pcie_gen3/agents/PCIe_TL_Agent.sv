class PCIe_TL_Agent extends uvm_agent;
  
  `uvm_component_utils(PCIe_TL_Agent)
  
  function new(string name = "PCIe_TL_Agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  PCIe_TL_Monitor   TX_TL_Mon;
  PCIe_TL_Driver    TX_TL_Drv;
  PCIe_TL_Sequencer TX_TL_Seqr;

  // TAG Manager
  Tag_Manager     tag_mgr;

  //LUT
  RX_PCIe_LUT     PCIe_LUT;
  
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    TX_TL_Mon  = PCIe_TL_Monitor::type_id::create("TX_TL_Mon", this);
    TX_TL_Drv  = PCIe_TL_Driver::type_id::create("TX_TL_Drv", this);
    TX_TL_Seqr = PCIe_TL_Sequencer::type_id::create("TX_TL_Seqr", this);

    tag_mgr = Tag_Manager::type_id::create("tag_mgr", this);
    PCIe_LUT   = RX_PCIe_LUT::type_id::create("PCIe_LUT", this);

    uvm_config_db#(RX_PCIe_LUT)::set(this, "*", "lut_handle", PCIe_LUT);
    
    uvm_config_db #(Tag_Manager)::set(this,"*","tag_mgr",tag_mgr);

  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    TX_TL_Drv.seq_item_port.connect(TX_TL_Seqr.seq_item_export);
    TX_TL_Mon.RX_TL_MON_Send.connect(PCIe_LUT.RX_LUT_imp);
    PCIe_LUT.cpl_ap.connect(TX_TL_Drv.cpl_imp);
    
  endfunction : connect_phase
  
endclass : PCIe_TL_Agent

    
    
