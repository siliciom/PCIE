//-----------------------------------------------------------------
// PCIe_PMA_Monitor - see TX_TL_Driver.sv header for design notes
//-----------------------------------------------------------------
class PCIe_PMA_Monitor extends uvm_monitor;
  `uvm_component_utils(PCIe_PMA_Monitor)

  env_cfg cfg;

  virtual phy_tx_interface  pvif;       // valid when RC_MODE
  virtual phy_rx_interface  rpvif;      // valid when EP_MODE
  virtual pipe_tx_interface pipe_vif;   // valid when RC_MODE
  virtual pipe_rx_interface pipe_rvif;  // valid when EP_MODE

  string tag;

  uvm_analysis_port #(Sequence_item) pma_tx_port;
  Sequence_item pma_tx_item;

  function new (string name = "PCIe_PMA_Monitor", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    pma_tx_port = new ("pma_tx_port", this);
    pma_tx_item = Sequence_item::type_id::create("pma_tx_item", this);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_PMA_Monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_PMA_Monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual phy_tx_interface)::get(this, "", "phy_Vif", pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] phy_tx_interface must be set for:%s.phy_Vif", tag, get_full_name()))

        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", pipe_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface must be set for:%s.pipe_Vif", tag, get_full_name()))

        `uvm_info("PCIe_PMA_Monitor", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual phy_rx_interface)::get(this, "", "phy_Vif", rpvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] phy_rx_interface must be set for:%s.phy_Vif", tag, get_full_name()))

        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", pipe_rvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface must be set for:%s.pipe_Vif", tag, get_full_name()))

        `uvm_info("PCIe_PMA_Monitor", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_PMA_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_PMA_Monitor", $sformatf("[%s] RC monitor active", tag), UVM_LOW)
        pma_tx_port.write(pma_tx_item);
      end

      EP_MODE: begin
        `uvm_info("PCIe_PMA_Monitor", $sformatf("[%s] EP monitor active", tag), UVM_LOW)
        // EP side sampling logic here
      end

      default: `uvm_fatal("PCIe_PMA_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass
