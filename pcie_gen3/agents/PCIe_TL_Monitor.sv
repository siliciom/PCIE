//-----------------------------------------------------------------
// PCIe_TL_Monitor - see PCIe_TL_Driver.sv header for design notes
//-----------------------------------------------------------------
class PCIe_TL_Monitor extends uvm_monitor;

  `uvm_component_utils(PCIe_TL_Monitor)

  env_cfg cfg;

  virtual TX_TL_DL_Interface TX_TL_DL;   // valid when RC_MODE
  virtual RX_TL_DL_Interface RX_TL_DL;   // valid when EP_MODE

  Sequence_item t_x;
  string tag;

  uvm_analysis_port #(Sequence_item) TX_TL_Send;

  function new(string name = "PCIe_TL_Monitor", uvm_component parent = null);
    super.new(name, parent);
    TX_TL_Send = new("TX_TL_Send", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_TL_Monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_TL_Monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("PCIe_TL_Monitor", $sformatf("[%s] Cannot get TX_TL_DL_Interface (TL_Vif)", tag))
        `uvm_info("RC_INTF_TL_MON", $sformatf("[%s] TX_TL_DL_Interface connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("PCIe_TL_Monitor", $sformatf("[%s] Cannot get RX_TL_DL_Interface (TL_Vif)", tag))
        `uvm_info("EP_INTF_TL_MON", $sformatf("[%s] RX_TL_DL_Interface connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_TL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_TL_Monitor", $sformatf("[%s] RC monitor active", tag), UVM_LOW)
        // forever begin
        //   @(posedge TX_TL_DL.CLK);
        //   // Sample RC side TLP activity into t_x
        //   TX_TL_Send.write(t_x);
        // end
      end

      EP_MODE: begin
        `uvm_info("PCIe_TL_Monitor", $sformatf("[%s] EP monitor active", tag), UVM_LOW)
        // forever begin
        //   @(posedge RX_TL_DL.CLK);
        //   // Sample EP side TLP activity into t_x
        //   PCIe_TL_Send.write(t_x);
        // end
      end

      default: `uvm_fatal("PCIe_TL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask : run_phase

endclass : PCIe_TL_Monitor
