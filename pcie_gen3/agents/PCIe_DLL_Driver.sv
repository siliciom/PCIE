class PCIe_DLL_Driver extends uvm_driver #(Sequence_item);

  `uvm_component_utils(PCIe_DLL_Driver)

  env_cfg cfg;
 virtual TX_TL_DL_Interface   TX_TL_DL;    // valid when RC_MODE
  virtual RX_TL_DL_Interface   RX_TL_DL;    // valid when EP_MODE

  virtual TX_DLL_PCS_Interface tx_dll_vif;  // valid when RC_MODE
  virtual RX_DLL_PCS_Interface rx_dll_vif;  // valid when EP_MODE

  string tag;

  uvm_analysis_imp#(Sequence_item, PCIe_DLL_Driver) TX_MD_Recv;

  function new(string name = "PCIe_DLL_Driver", uvm_component parent = null);
    super.new(name, parent);
    TX_MD_Recv = new("TX_MD_Recv", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_DLL_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_DLL_Driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
	  if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("TX_DLL_Monitor", $sformatf("[%s] Cannot get TX_TL_DL_Interface (TL_Vif)", tag))

        `uvm_info("RC_INTF_DLL_DRV", $sformatf("[%s] TX_DLL_PCS_Interface connected", tag), UVM_LOW)

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", tx_dll_vif))
          `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Cannot get TX_DLL_PCS_Interface (DLL_Vif)", tag))
        
        `uvm_info("RC_INTF_DLL_DRV", $sformatf("[%s] TX_DLL_PCS_Interface connected", tag), UVM_LOW)
      end

      EP_MODE: begin
	 if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Cannot get RX_TL_DL_Interface (TL_Vif)", tag))

         `uvm_info("EP_INTF_DLL_DRV", $sformatf("[%s] RX_DLL_PCS_Interface connected", tag), UVM_LOW)

        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", rx_dll_vif))
          `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Cannot get RX_DLL_PCS_Interface (DLL_Vif)", tag))
       
         `uvm_info("EP_INTF_DLL_DRV", $sformatf("[%s] RX_DLL_PCS_Interface connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  function void write(Sequence_item t_x);
    // Handle item received from monitor
  endfunction : write

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_DLL_Driver", $sformatf("[%s] RC driver active", tag), UVM_LOW)
        // Drive tx_dll_vif using cfg
      end

      EP_MODE: begin
        `uvm_info("PCIe_DLL_Driver", $sformatf("[%s] EP driver active", tag), UVM_LOW)
        // Drive/sample rx_dll_vif using cfg
      end

      default: `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask : run_phase

endclass
