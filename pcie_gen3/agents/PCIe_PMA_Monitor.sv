class PCIe_PMA_monitor extends uvm_monitor;
     `uvm_component_utils(PCIe_PMA_monitor)

     env_cfg cfg;
     string tag;

     virtual phy_tx_interface phy_tx_vif;
     virtual pipe_tx_interface pipe_tx_vif;

     virtual phy_rx_interface phy_rx_vif;
     virtual pipe_rx_interface pipe_rx_vif;

     uvm_analysis_port #(Sequence_item) pma_tx_mac_port;
     uvm_analysis_port #(Sequence_item) pma_tx_rx_port;

     uvm_analysis_port #(Sequence_item) pma_rx_mac_port;
     uvm_analysis_port #(Sequence_item) pma_rx_tx_port;

     Sequence_item pma_tx_item;  // RC_MODE
     Sequence_item pma_rx_item;  // EP_MODE

     uvm_event pma_rx_tx_drive;  // EP_MODE driver triggers each bit -> RC_MODE monitor watches
     uvm_event pma_tx_rx_drive;  // RC_MODE driver triggers each bit -> EP_MODE monitor watches

     // Note: the old shared class-level s[]/data/count/size_rx/size
     // fields were removed - Thread B now uses per-lane local
     // automatic variables (s_lane[]/data_lane[]/count_lane[]) declared
     // inside its own begin/end block, since each lane now reassembles
     // its serial bit stream independently.

     function new(string name = "PCIe_PMA_monitor", uvm_component parent);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          if (!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
               `uvm_fatal("PCIe_PMA_monitor", $sformatf("env_cfg not found for %s", get_full_name()
                          ))

          tag = get_full_name();
          `uvm_info("PCIe_PMA_monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()),
                    UVM_HIGH)

          pma_rx_tx_drive = uvm_event_pool::get_global("pma_rx_tx");
          pma_tx_rx_drive = uvm_event_pool::get_global("pma_tx_rx");

          pma_tx_mac_port = new("pma_tx_mac_port", this);
          pma_tx_rx_port  = new("pma_tx_rx_port", this);
          pma_rx_mac_port = new("pma_rx_mac_port", this);
          pma_rx_tx_port  = new("pma_rx_tx_port", this);

          case (cfg.mode)

               RC_MODE: begin
                    if (!uvm_config_db#(virtual phy_tx_interface)::get(
                            this, "", "phy_Vif", phy_tx_vif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] phy_tx_interface not set (phy_Vif missing)", tag))

                    if (!uvm_config_db#(virtual pipe_tx_interface)::get(
                            this, "", "pipe_Vif", pipe_tx_vif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

                    `uvm_info("PCIe_PMA_monitor", $sformatf("[%s] RC interfaces connected", tag),
                              UVM_HIGH)
               end

               EP_MODE: begin
                    if (!uvm_config_db#(virtual phy_rx_interface)::get(
                            this, "", "phy_Vif", phy_rx_vif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] phy_rx_interface not set (phy_Vif missing)", tag))

                    if (!uvm_config_db#(virtual pipe_rx_interface)::get(
                            this, "", "pipe_Vif", pipe_rx_vif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))

                    `uvm_info("PCIe_PMA_monitor", $sformatf("[%s] EP interfaces connected", tag),
                              UVM_HIGH)
               end

               default: `uvm_fatal("PCIe_PMA_monitor", $sformatf("[%s] Unknown mode", tag))

          endcase

     endfunction

     virtual task run_phase(uvm_phase phase);
          super.run_phase(phase);

          case (cfg.mode)

               RC_MODE: begin
                    fork
                         // Thread A: watch PIPE_TX -> forward to pma_tx_driver
                         // (RC_MODE). Each active lane is captured by its own
                         // independent sub-process: lane l waits for its own
                         // TxDataValid[l] posedge and fills tx_data_q[l] from
                         // TxData[l] until TxDataValid[l] deasserts. Once every
                         // active lane's capture for this burst completes, the
                         // combined per-lane item is forwarded downstream.
                         begin
                              forever begin
                                   automatic int lanes_pending = 0;

                                   pma_tx_item =
                                       Sequence_item::type_id::create("pma_tx_item", this);

                                   for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                                        automatic int l = lane;
                                        if (cfg.active_lane_mask[l]) begin
                                             lanes_pending++;
                                             fork
                                                  begin
                                                       @(posedge pipe_tx_vif.TxDataValid[l]);
                                                       while (1) begin
                                                            @(negedge pipe_tx_vif.PCLK);
                                                            if (!pipe_tx_vif.TxDataValid[l]) break;
                                                            pma_tx_item.tx_data_q[l].push_back(
                                                                pipe_tx_vif.TxData[l]);
                                                       end
                                                       lanes_pending--;
                                                  end
                                             join_none
                                        end
                                   end

                                   wait (lanes_pending == 0);

                                   `uvm_info("PMA_TX_MON", $sformatf(
                                             "[%s] TX packet captured on PMA lanes, forwarded to PMA RX path",
                                             tag
                                             ), UVM_LOW)
                                   pma_tx_rx_port.write(pma_tx_item);
                                   `uvm_info("PMA_TX_MON", $sformatf(
                                             "[%s] MAC TX DATA CAPTURED lane0=%0d words time = %t",
                                             tag,
                                             pma_tx_item.tx_data_q[0].size(),
                                             $time
                                             ), UVM_HIGH)
                              end
                         end
                         begin
                              Sequence_item cur_item;      // Thread B's OWN item — never shared with Thread A
                              int expected_size;
                              bit [129:0] data_lane[`PCIE_NUM_LANES];
                              bit s_lane[`PCIE_NUM_LANES][$];
                              int count_lane[`PCIE_NUM_LANES];

                              forever begin
                                   pma_rx_tx_drive.wait_trigger();
                                   #2;

                                   for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                                        if (!cfg.active_lane_mask[lane]) continue;
                                        if ($isunknown(phy_tx_vif.RX[lane])) continue;

                                        s_lane[lane].push_back(phy_tx_vif.RX[lane]);
                                        count_lane[lane]++;

                                        if (count_lane[lane] == 130) begin
                                             {>>130{data_lane[lane]}} = {<<{s_lane[lane]}};
                                             count_lane[lane] = 0;
                                             s_lane[lane].delete();

                                             if (cur_item == null) begin
                                                  cur_item = Sequence_item::type_id::create(
                                                      "cur_item", this);
                                                  wait (Sequence_item::size_rx_tx.size() > 0);
                                                  expected_size = Sequence_item::size_rx_tx.pop_front();
                                                  `uvm_info(
                                                      "PMA_RX_MON",
                                                      $sformatf(
                                                          "[%s] RC EXECEPTED_SIZE = %d time = %t",
                                                          tag, expected_size, $time), UVM_HIGH)
                                             end

                                             cur_item.pma_tx_data[lane].push_back(data_lane[lane]);
                                        end
                                   end

                                   if (cur_item != null) begin

                                        bit all_lanes_done;
                                        all_lanes_done = 1;

                                        for (int lane = 0; lane < cfg.num_lanes; lane++)
                                        if(cfg.active_lane_mask[lane] && cur_item.pma_tx_data[lane].size() != expected_size)
                                             all_lanes_done = 0;

                                        if (all_lanes_done) begin
                                             `uvm_info("PMA_TX_MON",
                                                       $sformatf("[%s] size_rx = %d time = %t",
                                                                 tag, expected_size, $time),
                                                       UVM_HIGH)
                                             `uvm_info(
                                                 "PMA_TX_MON",
                                                 $sformatf(
                                                     "[%s] TX packet reassembled from PMA lanes, forwarded to MAC layer",
                                                     tag), UVM_LOW)
                                             pma_tx_mac_port.write(cur_item);
                                             `uvm_info(
                                                 "PMA_TX_MON",
                                                 $sformatf(
                                                     "[%s] RC PMA RX DATA CAPTURED lane0=%p complete: %0d words time %t",
                                                     tag, cur_item.pma_tx_data[0],
                                                     cur_item.pma_tx_data[0].size(), $time),
                                                 UVM_HIGH)
                                             cur_item = null;
                                        end

                                   end
                              end
                         end
                    join_none
               end

               EP_MODE: begin
                    fork
                         // Thread A: watch PIPE_RX -> forward to pma_tx_driver
                         // (EP_MODE). Same per-lane independent capture as RC_MODE.
                         begin
                              forever begin
                                   automatic int lanes_pending = 0;

                                   pma_rx_item =
                                       Sequence_item::type_id::create("pma_rx_item", this);

                                   // See the matching RC_MODE comment above: this for-loop
                                   // must run directly (not wrapped in its own outer
                                   // fork...join_none), otherwise lanes_pending++ races
                                   // with wait(lanes_pending == 0) below and this forever
                                   // loop spins at zero simulation time forever.
                                   for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                                        automatic int l = lane;
                                        if (cfg.active_lane_mask[l]) begin
                                             lanes_pending++;
                                             fork
                                                  begin
                                                       @(posedge pipe_rx_vif.TxDataValid[l]);
                                                       while (1) begin
                                                            @(negedge pipe_rx_vif.PCLK);
                                                            if (!pipe_rx_vif.TxDataValid[l]) break;
                                                            pma_rx_item.pma_tx_data_t[l].push_back(
                                                                pipe_rx_vif.TxData[l]);
                                                       end
                                                       lanes_pending--;
                                                  end
                                             join_none
                                        end
                                   end

                                   wait (lanes_pending == 0);

                                   `uvm_info("PMA_RX_MON", $sformatf(
                                             "[%s] EP PMA TX DATA CAPTURED lane0=%0p time = %t",
                                             tag,
                                             pma_rx_item.pma_tx_data_t[0],
                                             $time
                                             ), UVM_HIGH)
                                   `uvm_info("PMA_RX_MON", $sformatf(
                                             "[%s] RX packet captured on PMA lanes, forwarded to PMA TX path",
                                             tag
                                             ), UVM_LOW)
                                   pma_rx_tx_port.write(pma_rx_item);
                              end
                         end

                         // Thread B: sample serial PHY TX line, per lane -> each
                         // lane independently reassembles its own 130-bit words
                         // from phy_rx_vif.RX[lane].
                         begin
                              Sequence_item cur_item;      // Thread B's OWN item — never shared with Thread A
                              int expected_size;
                              bit [129:0] data_lane[`PCIE_NUM_LANES];
                              bit s_lane[`PCIE_NUM_LANES][$];
                              int count_lane[`PCIE_NUM_LANES];

                              forever begin
                                   pma_tx_rx_drive.wait_trigger();
                                   #2;

                                   for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                                        if (!cfg.active_lane_mask[lane]) continue;
                                        if ($isunknown(phy_rx_vif.RX[lane])) continue;

                                        s_lane[lane].push_back(phy_rx_vif.RX[lane]);
                                        count_lane[lane]++;

                                        if (count_lane[lane] == 130) begin
                                             {>>130{data_lane[lane]}} = {<<{s_lane[lane]}};
                                             count_lane[lane] = 0;
                                             s_lane[lane].delete();

                                             if (cur_item == null) begin
                                                  cur_item = Sequence_item::type_id::create(
                                                      "pma_rx_capture_item", this);
                                                  wait (Sequence_item::size_tx_rx.size() > 0);
                                                  expected_size = Sequence_item::size_tx_rx.pop_front();
                                                  `uvm_info(
                                                      "PMA_RX_MON",
                                                      $sformatf(
                                                          "[%s] EP EXECEPTED_SIZE = %d time = %t",
                                                          tag, expected_size, $time), UVM_HIGH)
                                             end

                                             cur_item.pma_rx_data[lane].push_back(data_lane[lane]);
                                             $display("lane %0d data = %p size %0d", lane,
                                                      cur_item.pma_rx_data[lane],
                                                      cur_item.pma_rx_data[lane].size());
                                        end
                                   end

                                   if (cur_item != null) begin

                                        bit all_lanes_done;
                                        all_lanes_done = 1;

                                        for (int lane = 0; lane < cfg.num_lanes; lane++)
                                        if(cfg.active_lane_mask[lane] && cur_item.pma_rx_data[lane].size() != expected_size)
                                             all_lanes_done = 0;

                                        if (all_lanes_done) begin
                                             `uvm_info(
                                                 "PMA_RX_MON",
                                                 $sformatf(
                                                     "[%s] RX packet reassembled from PMA lanes, forwarded to MAC layer",
                                                     tag), UVM_LOW)
                                             pma_rx_mac_port.write(cur_item);
                                             `uvm_info(
                                                 "PMA_RX_MON",
                                                 $sformatf(
                                                     "[%s] EP PMA RX DATA lane0=%0p words time = %t",
                                                     tag, cur_item.pma_rx_data[0], $time), UVM_HIGH)
                                             cur_item = null;
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

