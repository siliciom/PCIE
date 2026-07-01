class PCIe_PMA_monitor extends uvm_monitor;
  `uvm_component_utils(PCIe_PMA_monitor)

  env_cfg cfg;
  string  tag;

  virtual phy_tx_interface  phy_tx_vif;
  virtual pipe_tx_interface pipe_tx_vif;

  virtual phy_rx_interface  phy_rx_vif;
  virtual pipe_rx_interface pipe_rx_vif;

  uvm_analysis_port #(Sequence_item) pma_tx_mac_port;
  uvm_analysis_port #(Sequence_item) pma_tx_rx_port;

  uvm_analysis_port #(Sequence_item) pma_rx_mac_port;
  uvm_analysis_port #(Sequence_item) pma_rx_tx_port;

  Sequence_item pma_tx_item;  // RC_MODE
  Sequence_item pma_rx_item;  // EP_MODE

  uvm_event pma_rx_tx_drive;  // EP_MODE driver triggers each bit -> RC_MODE monitor watches
  uvm_event pma_tx_rx_drive;  // RC_MODE driver triggers each bit -> EP_MODE monitor watches

  bit    s[$];
  bit [129:0] data;
  int    count   = 0;
  int    size_rx = 0;
  int    size    = 0;

  function new(string name = "PCIe_PMA_monitor", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_PMA_monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_PMA_monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    pma_rx_tx_drive = uvm_event_pool::get_global("pma_rx_tx");
    pma_tx_rx_drive = uvm_event_pool::get_global("pma_tx_rx");

    pma_tx_mac_port = new("pma_tx_mac_port", this);
    pma_tx_rx_port  = new("pma_tx_rx_port",  this);
    pma_rx_mac_port = new("pma_rx_mac_port", this);
    pma_rx_tx_port  = new("pma_rx_tx_port",  this);

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual phy_tx_interface)::get(this, "", "phy_Vif", phy_tx_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] phy_tx_interface not set (phy_Vif missing)", tag))

        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", pipe_tx_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("PCIe_PMA_monitor", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual phy_rx_interface)::get(this, "", "phy_Vif", phy_rx_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] phy_rx_interface not set (phy_Vif missing)", tag))

        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", pipe_rx_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("PCIe_PMA_monitor", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_PMA_monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        fork
          // Thread A: watch PIPE_TX -> forward to pma_tx_driver (RC_MODE)
          begin
            forever begin
              pma_tx_item = Sequence_item::type_id::create("pma_tx_item", this);
              @(posedge pipe_tx_vif.TxDataValid);
              while (1) begin
                @(negedge pipe_tx_vif.PCLK);
                if (!pipe_tx_vif.TxDataValid) break;
                pma_tx_item.tx_data_q.push_back(pipe_tx_vif.TxData);
              end
              pma_tx_rx_port.write(pma_tx_item);
              `uvm_info("PMA_TX_MON", $sformatf("[%s] MAC TX DATA CAPTURED %0d time = %t", tag, pma_tx_item.tx_data_q.size(), $time), UVM_LOW)
            end
          end

          // Thread B: sample serial PHY RX line -> reassemble 130-bit words
          begin
            forever begin
              pma_rx_tx_drive.wait_trigger();
              #2;
              if (!$isunknown(phy_tx_vif.RX)) begin
                s.push_back(phy_tx_vif.RX);
                count++;
                if (count == 130) begin
                  {>>130{data}} = {<<{s}};
                  if (pma_tx_item != null)
                    size_rx = pma_tx_item.size_rx_tx;
                  pma_tx_item.pma_tx_data.push_back(data);
                  count = 0;
                  s.delete();
                  if (size_rx > 0 && pma_tx_item.pma_tx_data.size() == size_rx) begin
                    pma_tx_mac_port.write(pma_tx_item);
                    `uvm_info("PMA_TX_MON", $sformatf("[%s] RC PMA RX DATA CAPTURED %p complete: %0d words time %t",
                                                       tag, pma_tx_item.pma_tx_data, pma_tx_item.pma_tx_data.size(), $time), UVM_LOW)
                    pma_tx_item.pma_tx_data.delete();
                  end
                end
              end
            end
          end
        join_none
      end

      EP_MODE: begin
        fork
          // Thread A: watch PIPE_RX -> forward to pma_tx_driver (EP_MODE)
          begin
            forever begin
              pma_rx_item = Sequence_item::type_id::create("pma_rx_item", this);
              @(posedge pipe_rx_vif.TxDataValid);
              while (1) begin
                @(negedge pipe_rx_vif.PCLK);
                if (!pipe_rx_vif.TxDataValid) break;
                pma_rx_item.pma_tx_data_t.push_back(pipe_rx_vif.TxData);
              end
              `uvm_info("PMA_RX_MON", $sformatf("[%s] EP PMA TX DATA CAPTURED %0p time = %t", tag, pma_rx_item.pma_tx_data_t, $time), UVM_LOW)
              pma_rx_tx_port.write(pma_rx_item);
            end
          end

          // Thread B: sample serial PHY TX line -> reassemble 130-bit words
          begin
            forever begin
              pma_tx_rx_drive.wait_trigger();
              #2;
              if (!$isunknown(phy_rx_vif.RX)) begin
                s.push_back(phy_rx_vif.RX);
                count++;
                if (count == 130) begin
                  {>>130{data}} = {<<{s}};
                  if (pma_rx_item != null)
                    size = pma_rx_item.size_tx_rx;
                  pma_rx_item.pma_rx_data.push_back(data);
                  $display("data = %p size %d", pma_rx_item.pma_rx_data, size);
                  count = 0;
                  s.delete();
                  if (size > 0 && pma_rx_item.pma_rx_data.size() == size) begin
                    pma_rx_mac_port.write(pma_rx_item);
                    `uvm_info("PMA_RX_MON", $sformatf("[%s] EP PMA RX DATA %0p words time = %t",
                                                       tag, pma_rx_item.pma_rx_data, $time), UVM_LOW)
                    pma_rx_item.pma_rx_data.delete();
                  end
                end
              end
            end
          end
        join_none
      end

      default: `uvm_fatal("pma_tx_monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass
