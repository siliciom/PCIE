`uvm_analysis_imp_decl(_port_a)
`uvm_analysis_imp_decl(_port_b)
`uvm_analysis_imp_decl(_port_c)
`uvm_analysis_imp_decl(_port_d)

class PCIe_PMA_driver extends uvm_driver #(Sequence_item);
     `uvm_component_utils(PCIe_PMA_driver)

     env_cfg cfg;
     string tag;

     virtual phy_tx_interface phy_tx_vif;
     virtual pipe_tx_interface pipe_tx_vif;

     virtual phy_rx_interface phy_rx_vif;
     virtual pipe_rx_interface pipe_rx_vif;

     uvm_analysis_imp_port_c #(Sequence_item, PCIe_PMA_driver) pma_tx_recv_mac;  // RC_MODE
     uvm_analysis_imp_port_d #(Sequence_item, PCIe_PMA_driver) pma_tx_recv_rx;  // RC_MODE

     uvm_analysis_imp_port_a #(Sequence_item, PCIe_PMA_driver) pma_rx_recv_mac;  // EP_MODE
     uvm_analysis_imp_port_b #(Sequence_item, PCIe_PMA_driver) pma_rx_recv_tx;  // EP_MODE

     uvm_event pma_tx_rx_drive;  // RC_MODE triggers, once per serialised bit
     uvm_event pma_rx_tx_drive;  // EP_MODE triggers, once per serialised bit
     uvm_event pma_rx_done;  // both RC_MODE and EP_MODE trigger this

     // RC_MODE queues - per lane. Lane l's queue talks to lane l's
     // physical wire end-to-end (see run_phase below).
     bit [129:0] tx_data_q[`PCIE_NUM_LANES][$];
     bit [129:0] mac_tx_data_q[`PCIE_NUM_LANES][$];
     int pkt_size;
     int size_t;

     // Per-packet word counts for mac_tx_data_q, one entry pushed per
     // write_port_c() call. Needed so the RC "RX DATA TRANSMISSION" fork
     // (mac_tx_data_q -> pipe_tx_vif.RxData/RxValid) can drain exactly
     // one packet at a time instead of snapshotting whatever backlog
     // happens to be sitting in the queue when it wakes up.
     int mac_tx_pkt_size_q[$];

     // EP_MODE queues - per lane.
     bit [129:0] rx_data_q[`PCIE_NUM_LANES][$];
     bit [129:0] mac_rx_data_q[`PCIE_NUM_LANES][$];
     int pkt_rx_size;

     // Per-packet word counts for rx_data_q, one entry pushed per
     // write_port_a() call. Needed so the EP "RX DATA TRANSMISSION" fork
     // (rx_data_q -> pipe_rx_vif.RxData/RxValid) can drain exactly one
     // packet at a time instead of snapshotting whatever backlog happens
     // to be sitting in the queue when it wakes up (this is what was
     // causing back-to-back packets, e.g. two Memory Reads, to merge
     // into a single continuous RxValid assertion).
     int rx_pkt_size_q[$];

     bit [`PCIE_NUM_LANES-1:0] receiver_present_mask = {`PCIE_NUM_LANES{1'b1}};

     function new(string name = "PCIe_PMA_driver", uvm_component parent);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          if (!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
               `uvm_fatal("PCIe_PMA_driver", $sformatf("env_cfg not found for %s", get_full_name()))

          tag = get_full_name();
          `uvm_info("PCIe_PMA_driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()),
                    UVM_HIGH)

          // Shared global events - same names used by pma_tx_monitor / the
          pma_tx_rx_drive = uvm_event_pool::get_global("pma_tx_rx");
          pma_rx_tx_drive = uvm_event_pool::get_global("pma_rx_tx");
          pma_rx_done     = uvm_event_pool::get_global("pma_rx_done");

          pma_tx_recv_mac = new("pma_tx_recv_mac", this);
          pma_tx_recv_rx  = new("pma_tx_recv_rx", this);
          pma_rx_recv_mac = new("pma_rx_recv_mac", this);
          pma_rx_recv_tx  = new("pma_rx_recv_tx", this);

          case (cfg.mode)

               RC_MODE: begin
                    if (!uvm_config_db#(virtual phy_tx_interface)::get(
                            this, "", "phy_Vif", phy_tx_vif
                        ))
                         `uvm_fatal("PCIe_PMA_driver", $sformatf(
                                    "[%s] Cannot get phy_tx_interface (phy_Vif)", tag))

                    if (!uvm_config_db#(virtual pipe_tx_interface)::get(
                            this, "", "pipe_Vif", pipe_tx_vif
                        ))
                         `uvm_fatal("PCIe_PMA_driver", $sformatf(
                                    "[%s] Cannot get pipe_tx_interface (pipe_Vif)", tag))

                    `uvm_info("PCIe_PMA_driver", $sformatf("[%s] RC interfaces connected", tag),
                              UVM_HIGH)
               end

               EP_MODE: begin
                    if (!uvm_config_db#(virtual phy_rx_interface)::get(
                            this, "", "phy_Vif", phy_rx_vif
                        ))
                         `uvm_fatal("PCIe_PMA_driver", $sformatf(
                                    "[%s] Cannot get phy_rx_interface (phy_Vif)", tag))

                    if (!uvm_config_db#(virtual pipe_rx_interface)::get(
                            this, "", "pipe_Vif", pipe_rx_vif
                        ))
                         `uvm_fatal("PCIe_PMA_driver", $sformatf(
                                    "[%s] Cannot get pipe_rx_interface (pipe_Vif)", tag))

                    `uvm_info("PCIe_PMA_driver", $sformatf("[%s] EP interfaces connected", tag),
                              UVM_HIGH)
               end

               default: `uvm_fatal("PCIe_PMA_driver", $sformatf("[%s] Unknown mode", tag))

          endcase

     endfunction

     function void write_port_d(Sequence_item pma_tx);
          `uvm_info("PMA_TX_DRV", $sformatf("[%s] Driving TX packet onto PMA lanes", tag), UVM_LOW)
          pkt_size = pma_tx.tx_data_q[0].size();  // representative lane 0 count
          for (int lane = 0; lane < cfg.num_lanes; lane++) begin
               if (cfg.active_lane_mask[lane]) begin
                    foreach (pma_tx.tx_data_q[lane][i]) begin
                         tx_data_q[lane].push_back(pma_tx.tx_data_q[lane][i]);
                         `uvm_info("PMA_TX_DRV", $sformatf(
                                   "[%s] tx_data_q[%d] received_data = %h",
                                   tag,
                                   lane[i],
                                   pma_tx.tx_data_q[lane][i]
                                   ), UVM_LOW)
                    end
               end
          end
          pma_tx.size_tx_rx.push_back(pkt_size);
          `uvm_info("PMA_TX_DRV", $sformatf("[%s] tx_data_q[0] size=%0d", tag, tx_data_q[0].size()),
                    UVM_HIGH)
     endfunction

     function void write_port_c(Sequence_item pma_rx);
          int pkt_words;
          `uvm_info("PMA_TX_DRV", $sformatf("[%s] Driving TX packet onto PMA MAC lanes", tag),
                    UVM_LOW)
          pkt_words = pma_rx.pma_tx_data[0].size();  // representative lane 0 count for THIS packet
          for (int lane = 0; lane < cfg.num_lanes; lane++)
          if (cfg.active_lane_mask[lane])
               foreach (pma_rx.pma_tx_data[lane][i])
               mac_tx_data_q[lane].push_back(pma_rx.pma_tx_data[lane][i]);
          mac_tx_pkt_size_q.push_back(pkt_words);  // record this packet's boundary
          `uvm_info("PMA_TX_DRV", $sformatf(
                    "[%s] mac_tx_data_q[0] size=%0d", tag, mac_tx_data_q[0].size()), UVM_HIGH)
     endfunction

     function void write_port_a(Sequence_item pma_rx);
          int pkt_words;
          `uvm_info("PMA_RX_DRV", $sformatf("[%s] RX packet received on PMA lanes", tag), UVM_LOW)
          pkt_words = pma_rx.pma_rx_data[0].size();  // representative lane 0 count for THIS packet
          for (int lane = 0; lane < cfg.num_lanes; lane++)
          if (cfg.active_lane_mask[lane])
               foreach (pma_rx.pma_rx_data[lane][i])
               rx_data_q[lane].push_back(pma_rx.pma_rx_data[lane][i]);
          rx_pkt_size_q.push_back(pkt_words);  // record this packet's boundary
          `uvm_info("PMA_RX_DRV", $sformatf(
                    "[%s] port_a: rx_data_q[0] now %0d entries", tag, rx_data_q[0].size()),
                    UVM_HIGH)
     endfunction

     function void write_port_b(Sequence_item pma_rx);
          `uvm_info("PMA_RX_DRV", $sformatf("[%s] RX packet received on PMA MAC lanes", tag),
                    UVM_LOW)
          pkt_rx_size = pma_rx.pma_tx_data_t[0].size();  // representative lane 0 count
          for (int lane = 0; lane < cfg.num_lanes; lane++)
          if (cfg.active_lane_mask[lane])
               foreach (pma_rx.pma_tx_data_t[lane][i])
               mac_rx_data_q[lane].push_back(pma_rx.pma_tx_data_t[lane][i]);
          `uvm_info("PMA_RX_DRV", $sformatf(
                    "[%s] port_b: mac_rx_data_q[0] %p now %0d entries",
                    tag,
                    mac_rx_data_q[0],
                    mac_rx_data_q[0].size()
                    ), UVM_HIGH)
          pma_rx.size_rx_tx.push_back(pkt_rx_size);
     endfunction

     virtual task run_phase(uvm_phase phase);

          case (cfg.mode)

               RC_MODE: begin

                    for (int lane = 0; lane < cfg.num_lanes; lane++)
                    if (cfg.active_lane_mask[lane]) begin
                         phy_tx_vif.TX[lane] <= 0;
                         phy_tx_vif.RX[lane] <= 0;
                    end

                    `uvm_info("PMA_TX", $sformatf(
                              "[%s] Ready for receiver detection (reactive, per-lane)", tag),
                              UVM_HIGH)

                    // Receiver Detection - reactive per lane.
                    // TxDetectRx is MAC(LTSSM)->PHY: the MAC driver asserts it
                    // per lane when it enters Detect.Active and wants a
                    // detection attempt run. This PMA model responds per lane,
                    // independently, with a small fixed settle delay before
                    // asserting PhyStatus[lane]/RxStatus[lane] - it does NOT
                    // drive TxDetectRx itself.

                    fork
                         for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                              automatic int l = lane;

                              if (!cfg.active_lane_mask[l]) continue;

                              fork
                                   forever begin

                                        @(posedge pipe_tx_vif.TxDetectRx[l]);

                                        repeat (6)
                                        @(posedge pipe_tx_vif.PCLK);  // detection settle time

                                        pipe_tx_vif.PhyStatus[l] <= 1'b1;

                                        if (receiver_present_mask[l])
                                             pipe_tx_vif.RxStatus[l] <= 3'b011;
                                        else pipe_tx_vif.RxStatus[l] <= 3'b000;

                                        @(posedge pipe_tx_vif.PCLK);
                                        pma_rx_done.trigger();

                                        @(posedge pipe_tx_vif.PCLK);
                                        pipe_tx_vif.PhyStatus[l] <= 1'b0;
                                        pipe_tx_vif.RxStatus[l]  <= 3'b000;

                                        // Wait for MAC to deassert before re-arming for the
                                        // next detection attempt (Detect.Active retry loop).
                                        @(negedge pipe_tx_vif.TxDetectRx[l]);

                                   end
                              join_none

                         end
                    join_none

                    fork
                         begin
                              forever begin
                                   wait(tx_data_q[0].size() > 0);   // representative lane 0 has data
                                   `uvm_info(
                                       "PMA_TX", $sformatf(
                                       "[%s] RC Started TX DATA TRANSMISSION time = %t", tag, $time
                                       ), UVM_HIGH)
                                   begin
                                        bit [129:0] tmp[`PCIE_NUM_LANES];
                                        int word_count;
                                        word_count = tx_data_q[0].size();

                                        for (int i = 0; i < word_count; i++) begin

                                             // Pop lane l's own word from lane l's own queue -
                                             // TxData[0] -> tx_data_q[0] -> TX[0], TxData[1] ->
                                             // tx_data_q[1] -> TX[1], etc.
                                             for (int lane = 0; lane < cfg.num_lanes; lane++)
                                             if(cfg.active_lane_mask[lane] && tx_data_q[lane].size() > 0)
                                                  tmp[lane] = tx_data_q[lane].pop_front();

                                             for (int j = 0; j < 130; j++) begin
                                                  #4;
                                                  for (int lane = 0; lane < cfg.num_lanes; lane++)
                                                  if (cfg.active_lane_mask[lane])
                                                       phy_tx_vif.TX[lane] <= tmp[lane][j];
                                                  pma_tx_rx_drive.trigger();
                                             end
                                        end
                                   end
                                   `uvm_info("PMA_TX", $sformatf(
                                             "[%s] RC Completed TX DATA TRANSMISSION time = %t",
                                             tag,
                                             $time
                                             ), UVM_HIGH)
                              end
                         end

                         begin
                              forever begin
                                   wait(mac_tx_pkt_size_q.size() > 0);   // wait for a fully recorded packet boundary
                                   `uvm_info(
                                       "PMA_TX", $sformatf(
                                       "[%s] RC Started RX DATA TRANSMISSION time = %t", tag, $time
                                       ), UVM_HIGH)
                                   size_t = mac_tx_pkt_size_q.pop_front();   // drain exactly ONE packet at a time
                                   for (int i = 0; i < size_t; i++) begin
                                        @(posedge pipe_tx_vif.PCLK);
                                        for (int lane = 0; lane < cfg.num_lanes; lane++)
                                        if(cfg.active_lane_mask[lane] && mac_tx_data_q[lane].size() > 0) begin
                                             pipe_tx_vif.RxData[lane]  <= mac_tx_data_q[lane].pop_front();
                                             pipe_tx_vif.RxValid[lane] <= 1;
                                        end
                                   end
                                   @(posedge pipe_tx_vif.PCLK);
                                   for (int lane = 0; lane < cfg.num_lanes; lane++)
                                   if (cfg.active_lane_mask[lane]) pipe_tx_vif.RxValid[lane] <= 0;
                                   `uvm_info(
                                       "PMA_TX", $sformatf(
                                       "[%s] RC Stopped RX DATA TRANSMISSION time = %t", tag, $time
                                       ), UVM_HIGH)
                              end
                         end
                    join

               end

               EP_MODE: begin

                    `uvm_info("PMA_RX", $sformatf(
                              "[%s] Ready for receiver detection (reactive, per-lane)", tag),
                              UVM_HIGH)

                    fork
                         for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                              automatic int l = lane;

                              if (!cfg.active_lane_mask[l]) continue;

                              fork
                                   forever begin

                                        @(posedge pipe_rx_vif.TxDetectRx[l]);

                                        repeat (6) @(posedge pipe_rx_vif.PCLK);

                                        pipe_rx_vif.PhyStatus[l] <= 1'b1;

                                        if (receiver_present_mask[l])
                                             pipe_rx_vif.RxStatus[l] <= 3'b011;
                                        else pipe_rx_vif.RxStatus[l] <= 3'b000;

                                        @(posedge pipe_rx_vif.PCLK);
                                        pma_rx_done.trigger();

                                        @(posedge pipe_rx_vif.PCLK);
                                        pipe_rx_vif.PhyStatus[l] <= 1'b0;
                                        pipe_rx_vif.RxStatus[l]  <= 3'b000;

                                        @(negedge pipe_rx_vif.TxDetectRx[l]);

                                   end
                              join_none

                         end
                    join_none

                    fork
                         begin
                              forever begin
                                   wait(mac_rx_data_q[0].size() > 0);   // representative lane 0 has data
                                   `uvm_info(
                                       "PMA_RX", $sformatf(
                                       "[%s] EP Started TX DATA TRANSMISSION time = %t", tag, $time
                                       ), UVM_HIGH)
                                   begin
                                        bit [129:0] tmp[`PCIE_NUM_LANES];
                                        int word_count;
                                        word_count = mac_rx_data_q[0].size();

                                        for (int i = 0; i < word_count; i++) begin

                                             for (int lane = 0; lane < cfg.num_lanes; lane++)
                                             if(cfg.active_lane_mask[lane] && mac_rx_data_q[lane].size() > 0)
                                                  tmp[lane] = mac_rx_data_q[lane].pop_front();

                                             for (int j = 0; j < 130; j++) begin
                                                  #4;
                                                  for (int lane = 0; lane < cfg.num_lanes; lane++)
                                                  if (cfg.active_lane_mask[lane])
                                                       phy_rx_vif.TX[lane] <= tmp[lane][j];
                                                  pma_rx_tx_drive.trigger();
                                             end
                                        end
                                   end
                                   `uvm_info(
                                       "PMA_RX", $sformatf(
                                       "[%s] EP Stopped TX DATA TRANSMISSION time = %t", tag, $time
                                       ), UVM_HIGH)
                              end
                         end

                         begin
                              forever begin
                                   wait(rx_pkt_size_q.size() > 0);   // wait for a fully recorded packet boundary
                                   begin
                                        int burst_size;
                                        burst_size = rx_pkt_size_q.pop_front();   // drain exactly ONE packet at a time
                                        `uvm_info("PMA_RX", $sformatf(
                                                  "[%s] EP Started RX DATA TRANSMISSION time = %t",
                                                  tag,
                                                  $time
                                                  ), UVM_HIGH)
                                        for (int i = 0; i < burst_size; i++) begin
                                             @(posedge pipe_rx_vif.PCLK);
                                             for (int lane = 0; lane < cfg.num_lanes; lane++)
                                             if(cfg.active_lane_mask[lane] && rx_data_q[lane].size() > 0) begin
                                                  pipe_rx_vif.RxData[lane]  <= rx_data_q[lane].pop_front();
                                                  pipe_rx_vif.RxValid[lane] <= 1;
                                             end
                                        end
                                        @(posedge pipe_rx_vif.PCLK);
                                        for (int lane = 0; lane < cfg.num_lanes; lane++)
                                        if (cfg.active_lane_mask[lane])
                                             pipe_rx_vif.RxValid[lane] <= 0;
                                        `uvm_info("PMA_RX", $sformatf(
                                                  "[%s] EP Stopped RX DATA TRANSMISSION time = %t",
                                                  tag,
                                                  $time
                                                  ), UVM_HIGH)
                                   end
                              end
                         end
                    join

               end

               default: `uvm_fatal("PCIe_PMA_driver", $sformatf("[%s] Unknown mode", tag))

          endcase

     endtask

endclass

