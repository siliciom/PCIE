//-----------------------------------------------------------------
//-----------------------------------------------------------------
class PCIe_MAC_Monitor extends uvm_monitor;
  `uvm_component_utils(PCIe_MAC_Monitor)

  env_cfg cfg;

  virtual TX_DLL_PCS_Interface vif;    // valid when RC_MODE
  virtual RX_DLL_PCS_Interface rvif;   // valid when EP_MODE
  virtual pipe_tx_interface    pvif;   // valid when RC_MODE
  virtual pipe_rx_interface    rpvif;  // valid when EP_MODE

  string tag;

  uvm_analysis_port #(Sequence_item) item_port;
  Sequence_item item;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    item_port = new("item_port", this);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_MAC_Monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_MAC_Monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] TX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))

        `uvm_info("RC_INTF_MAC_MON", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("RC_INTF_MAC_MON", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", rvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] RX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))

        `uvm_info("EP_INTF_MAC_MON", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", rpvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("EP_INTF_MAC_MON", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_MAC_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_MAC_Monitor", $sformatf("[%s] RC monitor active", tag), UVM_LOW)
      end

      EP_MODE: begin
        `uvm_info("PCIe_MAC_Monitor", $sformatf("[%s] EP monitor active", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_MAC_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask
endclass
