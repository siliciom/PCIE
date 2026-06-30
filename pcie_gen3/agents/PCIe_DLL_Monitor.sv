//-----------------------------------------------------------------
// TX_DLL_Monitor - see TX_TL_Driver.sv header for design notes
//-----------------------------------------------------------------
class PCIe_DLL_Monitor extends uvm_monitor;

  `uvm_component_utils(PCIe_DLL_Monitor)

  env_cfg cfg;

  virtual TX_TL_DL_Interface   TX_TL_DL;    // valid when RC_MODE
  virtual RX_TL_DL_Interface   RX_TL_DL;    // valid when EP_MODE
  virtual TX_DLL_PCS_Interface TX_DLL_PCS;  // valid when RC_MODE
  virtual RX_DLL_PCS_Interface RX_DLL_PCS;  // valid when EP_MODE

  Sequence_item t_x;
  string tag;

  uvm_analysis_port #(Sequence_item) TX_MD_ap;

  function new(string name = "PCIe_DLL_Monitor", uvm_component parent = null);
    super.new(name, parent);
    TX_MD_ap = new("TX_MD_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_DLL_Monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_DLL_Monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Cannot get PCIe_TL_DL_Interface (TL_Vif)", tag))

        `uvm_info("RC_INTF_DL_MON", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Cannot get PCIe_DLL_PCS_Interface (DLL_Vif)", tag))

        `uvm_info("RC_INTF_DL_MON", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Cannot get RX_TL_DL_Interface (TL_Vif)", tag))

        `uvm_info("EP_INTF_DL_MON", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
          `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Cannot get RX_DLL_PCS_Interface (DLL_Vif)", tag))

        `uvm_info("EP_INTF_DL_MON", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_DLL_Monitor", $sformatf("[%s] RC monitor active", tag), UVM_LOW)
              end

      EP_MODE: begin
        `uvm_info("PCIe_DLL_Monitor", $sformatf("[%s] EP monitor active", tag), UVM_LOW)
             end

      default: `uvm_fatal("PCIe_DLL_Monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask : run_phase

endclass : PCIe_DLL_Monitor
