//-----------------------------------------------------------------
// PCIe_MAC_Driver - see TX_TL_Driver.sv header for design notes
//-----------------------------------------------------------------
class PCIe_MAC_Driver extends uvm_driver #(Sequence_item);
  `uvm_component_utils(PCIe_MAC_Driver)

  env_cfg cfg;
  virtual TX_DLL_PCS_Interface vif;    // valid when RC_MODE
  virtual RX_DLL_PCS_Interface rvif;   // valid when EP_MODE
  virtual pipe_tx_interface tx_vif;   // valid when RC_MODE
  virtual pipe_rx_interface rx_vif;   // valid when EP_MODE

  string tag;

  uvm_analysis_imp #(Sequence_item, PCIe_MAC_Driver) item_imp;

  bit [31:0] received [$];
  uvm_event pipe_tx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_imp = new("item_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    pipe_tx = new();

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_MAC_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_MAC_Driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
         if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] TX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))

        `uvm_info("RC_INTF_MAC_DRV", $sformatf("[%s] pipe_tx_interface connected", tag), UVM_LOW)
        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", tx_vif))
          `uvm_fatal("PCIe_MAC_Driver", $sformatf("[%s] Cannot get pipe_tx_interface (pipe_Vif)", tag))
        `uvm_info("RC_INTF_MAC_DRV", $sformatf("[%s] pipe_tx_interface connected", tag), UVM_LOW)
      end

      EP_MODE: begin
	    if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", rvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] RX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))

        `uvm_info("EP_INTF_MAC_DRV", $sformatf("[%s] pipe_tx_interface connected", tag), UVM_LOW)
        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", rx_vif))
          `uvm_fatal("PCIe_MAC_Driver", $sformatf("[%s] Cannot get pipe_rx_interface (pipe_Vif)", tag))
        `uvm_info("EP_INTF_MAC_DRV", $sformatf("[%s] pipe_tx_interface connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_MAC_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  function void write(Sequence_item t);
    received.push_back(t.data);
    pipe_tx.trigger();
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        `uvm_info("PCIe_MAC_Driver", $sformatf("[%s] RC driver active", tag), UVM_LOW)
      end

      EP_MODE: begin
        `uvm_info("PCIe_MAC_Driver", $sformatf("[%s] EP driver active", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_MAC_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass
