//-----------------------------------------------------------------
//-----------------------------------------------------------------
class PCIe_PMA_Driver extends uvm_driver#(Sequence_item);
  `uvm_component_utils(PCIe_PMA_Driver)

  env_cfg cfg;

  virtual phy_tx_interface phy_tx_vif;  // valid when RC_MODE
  virtual phy_rx_interface phy_rx_vif;  // valid when EP_MODE
  virtual pipe_tx_interface pipe_vif;   // valid when RC_MODE
  virtual pipe_rx_interface pipe_rvif;  // valid when EP_MODE

  string tag;

  uvm_analysis_imp#(Sequence_item, PCIe_PMA_Driver) pma_tx_recv;

  function new (string name = "PCIe_PMA_Driver", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pma_tx_recv = new("pma_tx_recv", this);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_PMA_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_PMA_Driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual phy_tx_interface)::get(this, "", "phy_Vif", phy_tx_vif))
          `uvm_fatal("PCIe_PMA_Driver",
            $sformatf("[%s] Cannot get phy_tx_interface (phy_Vif) for: %s", tag, get_full_name()))
        `uvm_info("RC_INTF_DRV_PMA", $sformatf("[%s] pipe_tx_interface connected", tag), UVM_LOW)
	  if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", pipe_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface must be set for:%s.pipe_Vif", tag, get_full_name()))

        `uvm_info("RC_INTF_DRV_PMA", $sformatf("[%s] phy_tx_interface connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual phy_rx_interface)::get(this, "", "phy_Vif", phy_rx_vif))
          `uvm_fatal("PCIe_PMA_Driver",
            $sformatf("[%s] Cannot get phy_rx_interface (phy_Vif) for: %s", tag, get_full_name()))
        `uvm_info("RC_INTF_DRV_PMA", $sformatf("[%s] phy_rx_interface connected", tag), UVM_LOW)
         if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", pipe_rvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface must be set for:%s.pipe_Vif", tag, get_full_name()))

        `uvm_info("EP_INTF_DRV_PMA", $sformatf("[%s] pipe_tx_interface connected", tag), UVM_LOW)
        `uvm_info("PCIe_PMA_Driver", $sformatf("[%s] phy_rx_interface connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_PMA_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  function void write(Sequence_item pma_tx);
    // Handle item from monitor
  endfunction

  virtual task run_phase(uvm_phase phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_PMA_Driver", $sformatf("[%s] RC driver active", tag), UVM_LOW)
        // Drive phy_tx_vif using cfg
      end

      EP_MODE: begin
        `uvm_info("PCIe_PMA_Driver", $sformatf("[%s] EP driver active", tag), UVM_LOW)
        // Sample phy_rx_vif using cfg
      end

      default: `uvm_fatal("PCIe_PMA_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass
