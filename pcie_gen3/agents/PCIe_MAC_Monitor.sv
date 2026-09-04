class PCIe_MAC_monitor extends uvm_monitor;
     `uvm_component_utils(PCIe_MAC_monitor)

     env_cfg cfg;
     string tag;

     virtual TX_DLL_PCS_Interface rc_vif;
     virtual pipe_tx_interface rc_pvif;

     virtual RX_DLL_PCS_Interface ep_vif;
     virtual pipe_rx_interface ep_pvif;

     uvm_analysis_port #(Sequence_item) mac_tx_dll_port;
     uvm_analysis_port #(Sequence_item) mac_tx_rx_port;

     uvm_analysis_port #(Sequence_item) mac_rx_dll_port;
     uvm_analysis_port #(Sequence_item) mac_rx_rx_port;

     // 4 separate scoreboard ports, one per task
     uvm_analysis_port #(Sequence_item) mac_sb_rc_tx_port;  // rc_collect_pipe_tx_data
     uvm_analysis_port #(Sequence_item) mac_sb_rc_rx_port;  // rc_collect_pipe_rx_data
     uvm_analysis_port #(Sequence_item) mac_sb_ep_tx_port;  // ep_collect_pipe_tx_data
     uvm_analysis_port #(Sequence_item) mac_sb_ep_rx_port;  // ep_collect_pipe_rx_data


     bit [31:0] rc_r_data[$];
     bit [31:0] rc_mac_data[$];
     bit [127:0] rc_decoded_data;
     bit [31:0] rc_os_queue[$];
     bit [10:0] rc_length;
     bit [11:0] rc_seq_no;
     bit [3:0] rc_fcrc;
     bit rc_f_p;
     bit [31:0] rc_stp;
     bit [31:0] rc_tlp_queue[$];
     bit [63:0] rc_dllp_packet;
     bit [31:0] rc_dlp_p_q[$];
     bit [127:0] rc_os_data;

     Sequence_item ep_item;
     Sequence_item ep_tx_item;
     bit [31:0] ep_r_data[$];
     bit [127:0] ep_decoded_data;
     bit [31:0] ep_mac_data[$];
     bit [31:0] ep_os_queue[$];
     bit [10:0] ep_length;
     bit [11:0] ep_seq_no;
     bit [3:0] ep_fcrc;
     bit ep_f_p;
     bit [129:0] ep_data;
     bit [31:0] ep_stp;
     bit [31:0] ep_tlp_queue[$];
     bit [63:0] ep_dllp_packet;
     bit [31:0] ep_dlp_p_q[$];
     bit [127:0] ep_os_data;

     bit [22:0] polynomial = 23'h1DBFBC;

     localparam bit [22:0] RC_LANE_SEED[8] = '{
         23'h1DBFBC,  // Lane 0 mod 8
         23'h0607BB,  // Lane 1 mod 8
         23'h1EC760,  // Lane 2 mod 8
         23'h18C0DB,  // Lane 3 mod 8
         23'h010F12,  // Lane 4 mod 8
         23'h19CFC9,  // Lane 5 mod 8
         23'h0277CE,  // Lane 6 mod 8
         23'h1BB807  // Lane 7 mod 8
     };

     // Forces every RC lane's LFSR back to its RC_LANE_SEED[lane%8] reset value.
     // (Drives the reset path inside rc_lane_descramble_byte() below, since
     // the LFSR itself lives in that function's static storage.)
     function void rc_lane_scr_reset();
          bit [7:0] dummy;
          for (int lane = 0; lane < `PCIE_NUM_LANES; lane++)
          dummy = rc_lane_descramble_byte(lane, dummy, 1'b1);
     endfunction

     // Descrambles a single byte on the given lane, advancing that
     // lane's LFSR by 8 bits. lfsr[] is a function-local static array
     // (same static-storage pattern as rc_d_s()'s lfsr in the driver),
     // sized by `PCIE_NUM_LANES` and lazily seeded from
     // RC_LANE_SEED[lane%8] on first call (an assignment-pattern literal
     // can't be used here since its element count would have to be
     // hardcoded independently of the `PCIE_NUM_LANES macro). Free-runs
     // from there; pass rst=1 (see rc_lane_scr_reset()) to force that
     // lane back to its seed without descrambling a byte.
     function bit [7:0] rc_lane_descramble_byte(input int lane, inout bit [7:0] data,
                                                input bit rst = 1'b0);
          static bit [22:0] lfsr          [`PCIE_NUM_LANES];
          static bit        seeded = 1'b0;
          if (!seeded) begin
               for (int l = 0; l < `PCIE_NUM_LANES; l++) lfsr[l] = RC_LANE_SEED[l%8];
               seeded = 1'b1;
          end
          if (rst) begin
               lfsr[lane] = RC_LANE_SEED[lane%8];
               return data;
          end
          for (int i = 0; i < 8; i++) begin
               if (lfsr[lane][22]) lfsr[lane] = (lfsr[lane] << 1) ^ polynomial;
               else lfsr[lane] = (lfsr[lane] << 1);
               data[i] = lfsr[lane][22] ^ data[i];
          end
          return data;
     endfunction

     localparam bit [22:0] EP_LANE_SEED[8] = '{
         23'h1DBFBC,  // Lane 0 mod 8
         23'h0607BB,  // Lane 1 mod 8
         23'h1EC760,  // Lane 2 mod 8
         23'h18C0DB,  // Lane 3 mod 8
         23'h010F12,  // Lane 4 mod 8
         23'h19CFC9,  // Lane 5 mod 8
         23'h0277CE,  // Lane 6 mod 8
         23'h1BB807  // Lane 7 mod 8
     };

     // Forces every EP lane's LFSR back to its EP_LANE_SEED[lane%8] reset value.
     // (Drives the reset path inside ep_lane_descramble_byte() below, since
     // the LFSR itself lives in that function's static storage.)
     function void ep_lane_scr_reset();
          bit [7:0] dummy;
          for (int lane = 0; lane < `PCIE_NUM_LANES; lane++)
          dummy = ep_lane_descramble_byte(lane, dummy, 1'b1);
     endfunction

     // Descrambles a single byte on the given lane, advancing that
     // lane's LFSR by 8 bits. lfsr[] is a function-local static array
     // (same static-storage pattern as ep_d_s()'s lfsr in the driver),
     // sized by `PCIE_NUM_LANES` and lazily seeded from
     // EP_LANE_SEED[lane%8] on first call (an assignment-pattern literal
     // can't be used here since its element count would have to be
     // hardcoded independently of the `PCIE_NUM_LANES macro). Free-runs
     // from there; pass rst=1 (see ep_lane_scr_reset()) to force that
     // lane back to its seed without descrambling a byte.
     function bit [7:0] ep_lane_descramble_byte(input int lane, inout bit [7:0] data,
                                                input bit rst = 1'b0);
          static bit [22:0] lfsr          [`PCIE_NUM_LANES];
          static bit        seeded = 1'b0;
          if (!seeded) begin
               for (int l = 0; l < `PCIE_NUM_LANES; l++) lfsr[l] = EP_LANE_SEED[l%8];
               seeded = 1'b1;
          end
          if (rst) begin
               lfsr[lane] = EP_LANE_SEED[lane%8];
               return data;
          end
          for (int i = 0; i < 8; i++) begin
               if (lfsr[lane][22]) lfsr[lane] = (lfsr[lane] << 1) ^ polynomial;
               else lfsr[lane] = (lfsr[lane] << 1);
               data[i] = lfsr[lane][22] ^ data[i];
          end
          return data;
     endfunction


     bit [129:0] rc_pipe_tx_data_q[$];  // added
     bit [129:0] rc_pipe_rx_data_q[$];  // added
     bit [129:0] ep_pipe_tx_data_q[$];  // added
     bit [129:0] ep_pipe_rx_data_q[$];  // added

     int rc_tx_trans_cnt;
     int rc_rx_trans_cnt;
     int ep_tx_trans_cnt;
     int ep_rx_trans_cnt;


     function new(string name, uvm_component parent);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          if (!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
               `uvm_fatal("mac_tx_monitor", $sformatf("env_cfg not found for %s", get_full_name()))

          tag = get_full_name();
          `uvm_info("PCIe_MAC_monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()),
                    UVM_HIGH)

          mac_tx_dll_port = new("mac_tx_dll_port", this);
          mac_tx_rx_port = new("mac_tx_rx_port", this);
          mac_rx_dll_port = new("mac_rx_dll_port", this);
          mac_rx_rx_port = new("mac_rx_rx_port", this);
          mac_sb_rc_tx_port = new("mac_sb_rc_tx_port", this);
          mac_sb_rc_rx_port = new("mac_sb_rc_rx_port", this);
          mac_sb_ep_tx_port = new("mac_sb_ep_tx_port", this);
          mac_sb_ep_rx_port = new("mac_sb_ep_rx_port", this);

          case (cfg.mode)

               RC_MODE: begin
                    if (!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(
                            this, "", "DLL_Vif", rc_vif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] TX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))
                    if (!uvm_config_db#(virtual pipe_tx_interface)::get(
                            this, "", "pipe_Vif", rc_pvif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

                    `uvm_info("PCIe_MAC_monitor", $sformatf("[%s] RC interfaces connected", tag),
                              UVM_HIGH)
               end

               EP_MODE: begin
                    if (!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(
                            this, "", "DLL_Vif", ep_vif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] RX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))
                    if (!uvm_config_db#(virtual pipe_rx_interface)::get(
                            this, "", "pipe_Vif", ep_pvif
                        ))
                         `uvm_fatal("NO_VIF", $sformatf(
                                    "[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))

                    `uvm_info("PCIe_MAC_monitor", $sformatf("[%s] EP interfaces connected", tag),
                              UVM_HIGH)
               end

               default: `uvm_fatal("PCIe_MAC_monitor", $sformatf("[%s] Unknown mode", tag))

          endcase

     endfunction

     function bit [7:0] rc_d_s(inout bit [7:0] data);
          static bit [22:0] lfsr = 23'h7FFFFF;
          for (int i = 0; i < 8; i++) begin
               if (lfsr[22]) lfsr = (lfsr << 1) ^ polynomial;
               else lfsr = (lfsr << 1);
               data[i] = lfsr[22] ^ data[i];
          end
          return data;
     endfunction

     function bit [7:0] ep_d_s(inout bit [7:0] data);
          static bit [22:0] lfsr = 23'h7FFFFF;
          for (int i = 0; i < 8; i++) begin
               if (lfsr[22]) lfsr = (lfsr << 1) ^ polynomial;
               else lfsr = (lfsr << 1);
               data[i] = lfsr[22] ^ data[i];
          end
          return data;
     endfunction

     function bit [127:0] os_s(inout bit [127:0] TS);
          for (int i = 8; i < 113; i = i + 8) begin
               TS[i+:8] = rc_d_s(TS[i+:8]);
          end
     endfunction

     function void rc_data_scrambling(bit TL_DL);
          bit [31:0] data;
          if (TL_DL) begin
               for (int i = 0; i < rc_tlp_queue.size(); i++) begin
                    data = rc_tlp_queue[i];
                    rc_tlp_queue[i] = {
                         ep_d_s(data[31:24]),
                         ep_d_s(data[23:16]),
                         ep_d_s(data[15:8]),
                         ep_d_s(data[7:0])
                    };
               end
          end else begin
               rc_dllp_packet = {
                    ep_d_s(rc_dllp_packet[63:56]),
                    ep_d_s(rc_dllp_packet[55:48]),
                    ep_d_s(rc_dllp_packet[47:40]),
                    ep_d_s(rc_dllp_packet[39:32]),
                    ep_d_s(rc_dllp_packet[31:24]),
                    ep_d_s(rc_dllp_packet[23:16]),
                    16'h0
               };
          end
     endfunction

     function void ep_data_scrambling(bit TL_DL);
          bit [31:0] data;
          if (TL_DL) begin
               for (int i = 0; i < ep_tlp_queue.size(); i++) begin
                    data = ep_tlp_queue[i];
                    ep_tlp_queue[i] = {
                         rc_d_s(data[31:24]),
                         rc_d_s(data[23:16]),
                         rc_d_s(data[15:8]),
                         rc_d_s(data[7:0])
                    };
               end
          end else begin
               ep_dllp_packet = {
                    rc_d_s(ep_dllp_packet[63:56]),
                    rc_d_s(ep_dllp_packet[55:48]),
                    rc_d_s(ep_dllp_packet[47:40]),
                    rc_d_s(ep_dllp_packet[39:32]),
                    rc_d_s(ep_dllp_packet[31:24]),
                    rc_d_s(ep_dllp_packet[23:16]),
                    16'h0
               };
          end
     endfunction

     task automatic rc_collect_pipe_tx_data();
          Sequence_item rc_pipe_tx_item;
          forever begin
               rc_pipe_tx_item = Sequence_item::type_id::create("rc_pipe_tx_item", this);

               @(posedge rc_pvif.TxDataValid);
               while (1) begin
                    @(negedge rc_pvif.PCLK);
                    if (!rc_pvif.TxDataValid) break;
                    rc_pipe_tx_data_q.push_back(rc_pvif.TxData);
               end

               // packet complete -> populate item once, write once
               rc_pipe_tx_item.pma_rc_tx_q = rc_pipe_tx_data_q;
               rc_tx_trans_cnt++;
               mac_sb_rc_tx_port.write(rc_pipe_tx_item);

               `uvm_info("RC_MAC_TX_MON1", $sformatf(
                         "rc_pipe_tx_item written to mac_sb_rc_tx_port successfully. pma_rc_tx_q=%p, size=%0d, time=%0t",
                         rc_pipe_tx_item.pma_rc_tx_q,
                         rc_pipe_tx_item.pma_rc_tx_q.size(),
                         $time
                         ), UVM_LOW)

               `uvm_info("RC_MAC_TX_MON", $sformatf(
                         "[%s] PIPE TxData CAPTURED %p size=%0d time=%t",
                         tag,
                         rc_pipe_tx_data_q,
                         rc_pipe_tx_data_q.size(),
                         $time
                         ), UVM_LOW)
               rc_pipe_tx_data_q.delete();
          end
     endtask

     task automatic rc_collect_pipe_rx_data();
          Sequence_item rc_pipe_rx_item;
          forever begin
               rc_pipe_rx_item = Sequence_item::type_id::create("rc_pipe_rx_item", this);

               @(posedge rc_pvif.RxValid);
               while (1) begin
                    @(negedge rc_pvif.PCLK);
                    if (!rc_pvif.RxValid) break;
                    rc_pipe_rx_data_q.push_back(rc_pvif.RxData);
               end

               rc_pipe_rx_item.pma_rc_rx_q = rc_pipe_rx_data_q;
               rc_rx_trans_cnt++;
               mac_sb_rc_rx_port.write(rc_pipe_rx_item);

               `uvm_info("RC_MAC_RX_MON1", $sformatf(
                         "[%s] rc_pipe_rx_item written to mac_sb_rc_rx_port successfully. RxData=%p, queue_size=%0d, time=%0t",
                         tag,
                         rc_pipe_rx_item.pma_rc_rx_q,
                         rc_pipe_rx_item.pma_rc_rx_q.size(),
                         $time
                         ), UVM_LOW)

               `uvm_info("RC_MAC_RX_MON", $sformatf(
                         "[%s] PIPE RxData CAPTURED %p queue_size=%0d time=%t",
                         tag,
                         rc_pipe_rx_data_q,
                         rc_pipe_rx_data_q.size(),
                         $time
                         ), UVM_LOW)
               rc_pipe_rx_data_q.delete();
          end
     endtask

     task automatic ep_collect_pipe_tx_data();
          Sequence_item ep_pipe_tx_item;
          forever begin
               ep_pipe_tx_item = Sequence_item::type_id::create("ep_pipe_tx_item", this);

               @(posedge ep_pvif.TxDataValid);
               while (1) begin
                    @(negedge ep_pvif.PCLK);
                    if (!ep_pvif.TxDataValid) break;
                    ep_pipe_tx_data_q.push_back(ep_pvif.TxData);
               end

               ep_pipe_tx_item.pma_ep_tx_q = ep_pipe_tx_data_q;
               ep_tx_trans_cnt++;
               mac_sb_ep_tx_port.write(ep_pipe_tx_item);

               `uvm_info("EP_MAC_TX_MON1", $sformatf(
                         "[%s] ep_pipe_tx_item written to mac_sb_ep_tx_port successfully. TxData=%p, size=%0d, time=%0t",
                         tag,
                         ep_pipe_tx_item.pma_ep_tx_q,
                         ep_pipe_tx_item.pma_ep_tx_q.size(),
                         $time
                         ), UVM_LOW)

               `uvm_info("EP_MAC_TX_MON", $sformatf(
                         "[%s] PIPE TxData CAPTURED %p size=%0d time=%t",
                         tag,
                         ep_pipe_tx_data_q,
                         ep_pipe_tx_data_q.size(),
                         $time
                         ), UVM_LOW)
               ep_pipe_tx_data_q.delete();
          end
     endtask
     task automatic ep_collect_pipe_rx_data();
          Sequence_item ep_pipe_rx_item;
          forever begin
               ep_pipe_rx_item = Sequence_item::type_id::create("ep_pipe_rx_item", this);

               @(posedge ep_pvif.RxValid);
               while (1) begin
                    @(negedge ep_pvif.PCLK);
                    if (!ep_pvif.RxValid) break;
                    ep_pipe_rx_data_q.push_back(ep_pvif.RxData);
               end

               ep_pipe_rx_item.pma_ep_rx_q = ep_pipe_rx_data_q;
               ep_rx_trans_cnt++;
               mac_sb_ep_rx_port.write(ep_pipe_rx_item);

               `uvm_info("EP_MAC_RX_MON1", $sformatf(
                         "[%s] ep_pipe_rx_item written to mac_sb_ep_rx_port successfully. RxData=%p, queue_size=%0d, time=%0t",
                         tag,
                         ep_pipe_rx_item.pma_ep_rx_q,
                         ep_pipe_rx_item.pma_ep_rx_q.size(),
                         $time
                         ), UVM_LOW)

               `uvm_info("EP_MAC_RX_MON", $sformatf(
                         "[%s] PIPE RxData CAPTURED %p queue_size=%0d time=%t",
                         tag,
                         ep_pipe_rx_data_q,
                         ep_pipe_rx_data_q.size(),
                         $time
                         ), UVM_LOW)
               ep_pipe_rx_data_q.delete();
          end
     endtask






     //BYTE UNSTRIPING
     function void rc_byte_unstriping();
          bit [  7:0] payload_bytes  [$];
          bit [129:0] unstriped_word;
          bit         eds_seen;
          int         idx;

          `uvm_info("MAC_RX_MON", $sformatf(
                    "[%s] RC byte-unstriping received block across %0d lanes", tag, cfg.num_lanes),
                    UVM_LOW)

          payload_bytes.delete();  // local scratch queue only — fine to clear
          // NOTE: do NOT delete ep_r_data here; it must accumulate across DATA
          // cycles for the current packet, exactly like the non-striped branch does.

          for (int r = 0; r < 16; r++) begin
               for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                    bit [7:0] rc_raw_byte;
                    rc_raw_byte = rc_pvif.RxData[lane][127-r*8-:8];  // FIX: ep_pvif, not rc_pvif
                    payload_bytes.push_back(rc_lane_descramble_byte(lane, rc_raw_byte));
               end
          end

          idx = 0;
          while (idx < payload_bytes.size()) begin
               unstriped_word = '0;
               unstriped_word[129:128] = 2'b10;
               for (int b = 0; b < 16; b++) begin
                    if (idx < payload_bytes.size()) begin
                         unstriped_word[127-b*8-:8] = payload_bytes[idx];
                         idx++;
                    end
               end
               `uvm_info("RC_BYTE_UNSTRIPE", $sformatf("Word = %033h", unstriped_word),
                         UVM_HIGH)  // matches observed log tag

               rc_r_data.push_back(unstriped_word[127:96]);  // FIX: ep_r_data, not rc_r_data
               rc_r_data.push_back(unstriped_word[95:64]);
               rc_r_data.push_back(unstriped_word[63:32]);
               rc_r_data.push_back(unstriped_word[31:0]);

               eds_seen = (unstriped_word[127:96] == 32'h1f809000) ||
                 (unstriped_word[95:64]  == 32'h1f809000) ||
                 (unstriped_word[63:32]  == 32'h1f809000) ||
                 (unstriped_word[31:0]   == 32'h1f809000);
               if (eds_seen) break;
          end

          `uvm_info("MAC_RX_MON", $sformatf(
                    "[%s] RC byte-unstriping complete: %0d DWs reassembled", tag, rc_r_data.size()),
                    UVM_LOW)
     endfunction


     //BYTE UNSTRIPING
     function void ep_byte_unstriping();
          bit [  7:0] payload_bytes  [$];
          bit [129:0] unstriped_word;
          bit         eds_seen;
          int         idx;

          `uvm_info("MAC_RX_MON", $sformatf(
                    "[%s] EP byte-unstriping received block across %0d lanes", tag, cfg.num_lanes),
                    UVM_LOW)

          payload_bytes.delete();  // local scratch queue only — fine to clear
          // NOTE: do NOT delete ep_r_data here; it must accumulate across DATA
          // cycles for the current packet, exactly like the non-striped branch does.

          for (int r = 0; r < 16; r++) begin
               for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                    bit [7:0] ep_raw_byte;
                    ep_raw_byte = ep_pvif.RxData[lane][127-r*8-:8];  // FIX: ep_pvif, not rc_pvif
                    payload_bytes.push_back(ep_lane_descramble_byte(lane, ep_raw_byte));
               end
          end

          idx = 0;
          while (idx < payload_bytes.size()) begin
               unstriped_word = '0;
               unstriped_word[129:128] = 2'b10;
               for (int b = 0; b < 16; b++) begin
                    if (idx < payload_bytes.size()) begin
                         unstriped_word[127-b*8-:8] = payload_bytes[idx];
                         idx++;
                    end
               end
               `uvm_info("RX_BYTE_UNSTRIPE", $sformatf("Word = %033h", unstriped_word),
                         UVM_HIGH)  // matches observed log tag

               ep_r_data.push_back(unstriped_word[127:96]);  // FIX: ep_r_data, not rc_r_data
               ep_r_data.push_back(unstriped_word[95:64]);
               ep_r_data.push_back(unstriped_word[63:32]);
               ep_r_data.push_back(unstriped_word[31:0]);

               eds_seen = (unstriped_word[127:96] == 32'h1f809000) ||
                 (unstriped_word[95:64]  == 32'h1f809000) ||
                 (unstriped_word[63:32]  == 32'h1f809000) ||
                 (unstriped_word[31:0]   == 32'h1f809000);
               if (eds_seen) break;
          end

          `uvm_info("MAC_RX_MON", $sformatf(
                    "[%s] EP byte-unstriping complete: %0d DWs reassembled", tag, ep_r_data.size()),
                    UVM_LOW)
     endfunction
     function automatic bit rc_any_lane_valid();
          rc_any_lane_valid = 1'b0;
          for (int lane = 0; lane < cfg.num_lanes; lane++)
          if (rc_pvif.RxValid[lane]) rc_any_lane_valid = 1'b1;
     endfunction

     function automatic bit ep_any_lane_valid();
          ep_any_lane_valid = 1'b0;
          for (int lane = 0; lane < cfg.num_lanes; lane++)
          if (ep_pvif.RxValid[lane]) ep_any_lane_valid = 1'b1;
     endfunction



     virtual task run_phase(uvm_phase phase);

          case (cfg.mode)

               RC_MODE: begin

                    super.run_phase(phase);

                    rc_vif.dl_tx_ready = 0;
                    @(posedge rc_vif.CLK);
                    rc_vif.dl_tx_ready = 1;
                    fork
                         begin
                              Sequence_item rc_tx_item;
                              rc_tx_item = Sequence_item::type_id::create("rc_tx_item");
                              forever begin

                                   // @(negedge rc_vif.CLK);
                                   @(posedge rc_vif.dl_tx_valid);

                                   while (1) begin

                                        @(posedge rc_vif.CLK);
                                        if(rc_vif.dl_tx_valid && rc_vif.dl_tx_ready && rc_vif.tl_packet) begin
                                             rc_mac_data.push_back(rc_vif.dl_tx_data);
                                        end
	 else if(rc_vif.dl_tx_valid && rc_vif.dl_tx_ready && rc_vif.dl_packet) begin
                                             rc_tx_item.dllp_tx_packet.push_back(rc_vif.dl_tx_data);
                                             foreach (rc_tx_item.dllp_tx_packet[i])
                                                  `uvm_info("MAC_TX_MON", $sformatf(
                                                            "DLLL_tx_PACKET %h",
                                                            rc_tx_item.dllp_tx_packet[i]
                                                            ), UVM_LOW)
                                        end else begin
                                             `uvm_info("MAC_TX_MON", $sformatf("BREAK_DONE_RC"),
                                                       UVM_HIGH)
                                             break;
                                        end
                                   end
                                   foreach (rc_mac_data[i])
                                        `uvm_info("MAC_TX_MON", $sformatf(
                                                  "DLL Packet Sent %h", rc_mac_data[i]), UVM_LOW)
                                   foreach (rc_tx_item.dllp_tx_packet[i])
                                        `uvm_info("MAC_TX_MON", $sformatf(
                                                  "DLLL_tx_PACKET %h", rc_tx_item.dllp_tx_packet[i]
                                                  ), UVM_HIGH)
                                   if (rc_mac_data.size() > 0) begin
                                        rc_tx_item.mac_tx_data.push_back(rc_mac_data);
                                        rc_mac_data.delete();
                                   end
                                   if((rc_tx_item.mac_tx_data.size()>0) || (rc_tx_item.dllp_tx_packet.size()>0)) begin
                                        foreach (rc_tx_item.dllp_tx_packet[i])
                                             `uvm_info("MAC_TX_MON", $sformatf(
                                                       "BEFORE_WRITE_PACKET %h",
                                                       rc_tx_item.dllp_tx_packet[i]
                                                       ), UVM_HIGH)
                                        `uvm_info(
                                            "MAC_TX_MON",
                                            $sformatf(
                                                "[%s] RC MAC packet forwarded to DLL layer: mac_tx_data=%0d dllp=%0d",
                                                tag, rc_tx_item.mac_tx_data.size(),
                                                rc_tx_item.dllp_tx_packet.size()), UVM_LOW)
                                        mac_tx_dll_port.write(rc_tx_item);
                                        rc_tx_item.dllp_tx_packet.delete();
                                        rc_tx_item.mac_tx_data.delete();
                                        `uvm_info("MAC_TX_MON", $sformatf("WRITE COMPLETED"),
                                                  UVM_HIGH)
                                   end
                                   `uvm_info("MAC_TX_MON", $sformatf(
                                             "DLLL_PACKET %p", rc_tx_item.dllp_tx_packet), UVM_HIGH)

                              end
                         end
                         begin
                              forever begin
                                   Sequence_item rc_item;


                                   rc_item = Sequence_item::type_id::create("rc_item");

                                   @(posedge rc_pvif.RxValid[0]);

                                   while (1) begin

                                        @(negedge rc_pvif.PCLK) if (!rc_any_lane_valid()) break;

                                        // Single pass over all active lanes: each lane is checked on its OWN
                                        // RxValid[lane] and its OWN sync header, so a lane that's idle/invalid
                                        // this cycle is simply skipped instead of pulling in stale/wrong data.
                                        // OS entries are captured right here per lane (they're independent per
                                        // lane). DATA is only flagged here (rc_data_seen) -- the actual DW
                                        // extraction still happens once below, since reconstructing a DATA
                                        // cycle (broadcast read or byte-unstriping) is inherently a cross-lane
                                        // operation and can't be done independently lane-by-lane like OS can.
                                        begin
                                             bit rc_data_seen;
                                             rc_data_seen = 1'b0;

                                             for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                                                  if (rc_pvif.RxValid[lane]) begin
                                                       if (rc_pvif.RxData[lane][129:128] == 2'b10) begin
                                                            rc_data_seen = 1'b1;
                                                            `uvm_info("MAC_TX",
                                                                      $sformatf(
                                                                          "DLLP_START %h",
                                                                          rc_pvif.RxData[lane]),
                                                                      UVM_LOW)
                                                       end
          else if (rc_pvif.RxData[lane][129:128] == 2'b01) begin
                                                            case (rc_pvif.RxData[lane][127:120])
                                                                 8'h1E: begin
                                                                      rc_os_data = rc_pvif.RxData[lane][127:0];
                                                                      //void'(os_s(rc_os_data));
                                                                      rc_item.os_t_lane[lane].push_back(
                                                                          rc_os_data);
                                                                      `uvm_info("MAC_TX", $sformatf(
                                                                                "Packet Sent lane%0d %h",
                                                                                lane,
                                                                                rc_os_data
                                                                                ), UVM_LOW)
                                                                 end
                                                                 8'h2D: begin
                                                                      rc_os_data = rc_pvif.RxData[lane][127:0];
                                                                      //void'(os_s(rc_os_data));
                                                                      rc_item.os_t_lane[lane].push_back(
                                                                          rc_os_data);
                                                                      `uvm_info("MAC_TX", $sformatf(
                                                                                "Packet Sent lane%0d %h",
                                                                                lane,
                                                                                rc_os_data
                                                                                ), UVM_LOW)
                                                                 end
                                                                 8'h00: begin
                                                                      rc_os_data = rc_pvif.RxData[lane][127:0];
                                                                      rc_item.os_t_lane[lane].push_back(
                                                                          rc_os_data);
                                                                      `uvm_info("MAC_TX", $sformatf(
                                                                                "Packet Sent lane%0d %h",
                                                                                lane,
                                                                                rc_os_data
                                                                                ), UVM_LOW)
                                                                 end
                                                            endcase
                                                       end
                                                  end
                                             end

                                             if (rc_data_seen) begin
                                                  // rc_byte_unstriping() already generalizes to any cfg.num_lanes --
                                                  // with 1 lane it reassembles the same 4 DWs the old single-lane
                                                  // broadcast read produced, so no separate broadcast path is needed.
                                                  rc_byte_unstriping();
                                             end
                                        end
                                   end
                                   foreach (rc_r_data[i])
                                        `uvm_info("MAC_TX_MON", $sformatf(
                                                  "Packet_Sent %h", rc_r_data[i]), UVM_LOW)

                                   // Parse all packets from rc_r_data
                                   while (rc_r_data.size() > 0) begin
                                        if (rc_r_data[0][27:24] == 4'hF) begin
                                             rc_stp = rc_r_data.pop_front();
                                             rc_length = {rc_stp[22:16], rc_stp[31:28]};
                                             rc_fcrc = rc_stp[15:12];
                                             rc_seq_no = {rc_stp[7:0], rc_stp[11:8]};

                                             `uvm_info("MAC_TX",
                                                       $sformatf("STP=%h rc_length=%0d seq=%0h",
                                                                 rc_stp, rc_length, rc_seq_no),
                                                       UVM_HIGH)

                                             // FIX: must clear rc_tlp_queue at the start of every new TLP (every
                                             // time a new STP is seen). Leaving this commented out let leftover
                                             // DWORDs from a TLP that hadn't yet hit its end-of-packet marker
                                             // bleed into the next back-to-back TLP's capture, corrupting the
                                             // DWORD stream used for the downstream LCRC recompute -> spurious
                                             // LCRC MISMATCH on back-to-back transfers.
                                             rc_tlp_queue.delete();

                                             for (int i = 0; i < (rc_length - 1); i++) begin
                                                  if (rc_r_data.size() == 0) break;

                                                  rc_tlp_queue.push_back(rc_r_data.pop_front());


                                             end
                                             `uvm_info(
                                                 "MAC_RX",
                                                 $sformatf(
                                                     "TLP_Queue = %p rc_r_data = %d  rc_length = %d",
                                                     rc_tlp_queue, rc_length, rc_r_data.size()),
                                                 UVM_HIGH)
                                             foreach (rc_r_data[i])
                                                  `uvm_info("MAC_TX_MON", $sformatf(
                                                            "Packet_REMAINING_Sent %h", rc_r_data[i]
                                                            ), UVM_HIGH)

                                             if (rc_r_data.size() >= 2) begin

                                                  if (rc_r_data[0][31:16] == 16'hF0AC) begin

                                                       rc_dllp_packet = {
                                                            rc_r_data[0][15:0],
                                                            rc_r_data[1][31:16],
                                                            rc_r_data[1][15:0],
                                                            16'h0
                                                       };

                                                       rc_r_data.delete(0);
                                                       rc_r_data.delete(0);

                                                       `uvm_info("MAC_TX", $sformatf(
                                                                               "DLLP = %h",
                                                                               rc_dllp_packet),
                                                                 UVM_HIGH)
                                                  end
                                             end

                                             if (rc_r_data[0] == 32'h1f809000) begin
                                                  `uvm_info("MAC_TX",
                                                            $sformatf("RC_SCRAMBLED %p  time = %t",
                                                                      rc_tlp_queue, $time),
                                                            UVM_HIGH)
                                                  `uvm_info("MAC_TX",
                                                            $sformatf("RC_ORIGINAL  %p  time = %t",
                                                                      rc_tlp_queue, $time),
                                                            UVM_HIGH)

                                                  rc_item.tlp_queue = rc_tlp_queue;
                                                  rc_r_data.delete();
                                                  rc_tlp_queue.delete();
                                                  `uvm_info("MAC_TX",
                                                            $sformatf(
                                                                "MAC RX DATA CAPTURED %p time = %t",
                                                                rc_tlp_queue, $time), UVM_HIGH)
                                             end
                                        end else if (rc_r_data[0][31:16] == 16'hF0AC) begin
                                             `uvm_info("MAC_TX_MON",
                                                       $sformatf(
                                                           "INSIDE WHILE LOOP - CONTINUOUS DLLP"),
                                                       UVM_HIGH)
                                             // Each DLLP occupies 4 raw dwords: [F0AC_xxxx][yyyy_zzzz][32'h0][32'h0].
                                             // Loop so that back-to-back DLLPs are each decoded individually and
                                             // the 2 trailing zero-pad dwords per DLLP are stripped, instead of
                                             // only decoding the first DLLP and dumping the rest raw.
                                             while(rc_r_data.size() >= 4 && rc_r_data[0][31:16] == 16'hF0AC) begin
                                                  rc_dlp_p_q.push_back(
                                                      {rc_r_data[0][15:0], rc_r_data[1][31:16]});
                                                  rc_dlp_p_q.push_back({rc_r_data[1][15:0], 16'h0});
                                                  rc_r_data.delete(0);  // F0AC dword
                                                  rc_r_data.delete(0);  // data dword
                                                  rc_r_data.delete(
                                                      0);  // zero-pad dword #1 (removed)
                                                  rc_r_data.delete(
                                                      0);  // zero-pad dword #2 (removed)
                                             end
                                             // Anything still in rc_r_data at this point is trailing zero-pad
                                             // from the fixed-width unstripe container, not real DLLP data --
                                             // only genuine non-zero leftovers indicate an actual parsing gap
                                             // and should be forwarded; all-zero padding is silently dropped.
                                             if (rc_r_data.size() > 0) begin
                                                  bit rc_leftover_nonzero;
                                                  rc_leftover_nonzero = 1'b0;
                                                  foreach (rc_r_data[i])
                                                  if (rc_r_data[i] != 32'h0)
                                                       rc_leftover_nonzero = 1'b1;

                                                  if (rc_leftover_nonzero) begin
                                                       `uvm_info(
                                                           "MAC_TX_MON",
                                                           $sformatf(
                                                               "RC_DLLP_LEFTOVER_UNHANDLED %p",
                                                               rc_r_data), UVM_HIGH)
                                                       foreach (rc_r_data[i])
                                                       rc_dlp_p_q.push_back(rc_r_data[i]);
                                                  end else begin
                                                       `uvm_info("MAC_TX_MON", $sformatf(
                                                                 "RC_DLLP_LEFTOVER_ZERO_PAD_DROPPED %p",
                                                                 rc_r_data
                                                                 ), UVM_HIGH)
                                                  end
                                             end
                                             rc_item.dlp_queue = rc_dlp_p_q;
                                             foreach (rc_dlp_p_q[i])
                                                  `uvm_info("MAC_TX_MON", $sformatf(
                                                            "EP_DLLP_Packet_recv %h", rc_dlp_p_q[i]
                                                            ), UVM_HIGH)
                                             rc_r_data.delete();
                                             rc_dlp_p_q.delete();
                                        end else begin
                                             // Neither an STP (4'hF) header nor a DLLP (F0AC) header -- if left
                                             // unhandled, rc_r_data.size() never shrinks and this while loop spins
                                             // at zero delay forever, livelocking the simulator (this is what was
                                             // hanging the DL state machine). Drop the unrecognized dword and move
                                             // on instead of stalling.
                                             bit [31:0] rc_unmatched;
                                             rc_unmatched = rc_r_data.pop_front();
                                             `uvm_warning("MAC_TX_MON", $sformatf(
                                                          "[%s] Unrecognized leading dword %h in rc_r_data (not STP/DLLP) - dropped to avoid parser livelock",
                                                          tag,
                                                          rc_unmatched
                                                          ))
                                        end


                                   end
                                   // else begin
                                   `uvm_info("MAC_TX_MON", $sformatf(
                                             "ODERED SETS = %p", rc_item.tlp_queue), UVM_HIGH)
                                   `uvm_info("MAC_TX_MON", $sformatf(
                                             "[%s] RC MAC packet forwarded to RX path: tlp_queue=%0d dlp_queue=%0d",
                                             tag,
                                             rc_item.tlp_queue.size(),
                                             rc_item.dlp_queue.size()
                                             ), UVM_LOW)
                                   mac_tx_rx_port.write(rc_item);
                                   for (int lane = 0; lane < cfg.num_lanes; lane++)
                                   rc_item.os_t_lane[lane].delete();
                                   // end
                              end

                         end
                         rc_collect_pipe_tx_data();
                         rc_collect_pipe_rx_data();

                    join_none
                    //end
               end

               EP_MODE: begin

                    super.run_phase(phase);


                    ep_vif.dl_tx_ready = 0;
                    @(posedge ep_vif.CLK);
                    ep_vif.dl_tx_ready = 1;
                    fork
                         begin
                              ep_tx_item = Sequence_item::type_id::create("ep_tx_item");
                              forever begin

                                   // @(negedge ep_vif.CLK);
                                   @(posedge ep_vif.dl_tx_valid);

                                   while (1) begin

                                        @(negedge ep_vif.CLK);
                                        if(ep_vif.dl_tx_valid && ep_vif.dl_tx_ready && ep_vif.tl_packet) begin
                                             ep_mac_data.push_back(ep_vif.dl_tx_data);
                                        end
	 else if(ep_vif.dl_tx_valid && ep_vif.dl_tx_ready && ep_vif.dl_packet) begin
                                             ep_tx_item.dllp_packet.push_back(ep_vif.dl_tx_data);
                                             foreach (ep_tx_item.dllp_packet[i])
                                                  `uvm_info(
                                                      "MAC_RX_MON", $sformatf(
                                                      "EP_DLLL_PACKET %h", ep_tx_item.dllp_packet[i]
                                                      ), UVM_HIGH)
                                        end else begin
                                             break;

                                        end
                                   end
                                   ep_tx_item.mac_rx_data.push_back(ep_mac_data);
                                   `uvm_info("MAC_RX_MON", $sformatf(
                                             "DLL Packet Sent %p size %d count = %d",
                                             ep_tx_item.mac_rx_data,
                                             ep_tx_item.mac_rx_data.size(),
                                             ep_tx_item.count_tlp
                                             ), UVM_HIGH)
                                   ep_mac_data.delete();

                                   if((ep_tx_item.mac_rx_data.size()>0)||(ep_tx_item.dllp_packet.size()>0)) begin
                                        `uvm_info("MAC_RX_MON",
                                                  $sformatf("MATCHED_RX_DLLL %p %p %d",
                                                            ep_tx_item.mac_rx_data,
                                                            ep_tx_item.dllp_packet,
                                                            ep_tx_item.count_tlp), UVM_HIGH)
                                        `uvm_info(
                                            "MAC_RX_MON",
                                            $sformatf(
                                                "[%s] EP MAC packet forwarded to DLL layer: mac_rx_data=%0d dllp=%0d",
                                                tag, ep_tx_item.mac_rx_data.size(),
                                                ep_tx_item.dllp_packet.size()), UVM_LOW)
                                        mac_rx_dll_port.write(ep_tx_item);
                                        ep_tx_item.dllp_packet.delete();
                                        ep_tx_item.mac_rx_data.delete();
                                        `uvm_info("MAC_RX_MON", $sformatf("WRITE COMPLETED"),
                                                  UVM_HIGH)
                                   end
                              end
                         end




                         begin

                              forever begin

                                   ep_item = Sequence_item::type_id::create("ep_item");

                                   @(posedge ep_pvif.RxValid[0]);
                                   while (1) begin

                                        @(negedge ep_pvif.PCLK) if (!ep_any_lane_valid()) break;

                                        // Single pass over all active lanes: each lane is checked on its OWN
                                        // RxValid[lane] and its OWN sync header, so a lane that's idle/invalid
                                        // this cycle is simply skipped. OS entries are captured right here per
                                        // lane. DATA is only flagged here (ep_data_seen) -- the actual DW
                                        // extraction still happens once below, since reconstructing a DATA
                                        // cycle (broadcast read or byte-unstriping) is inherently a cross-lane
                                        // operation and can't be done independently lane-by-lane like OS can.
                                        begin
                                             bit ep_data_seen;
                                             ep_data_seen = 1'b0;

                                             for (int lane = 0; lane < cfg.num_lanes; lane++) begin
                                                  if (ep_pvif.RxValid[lane]) begin
                                                       if (ep_pvif.RxData[lane][129:128] == 2'b10) begin
                                                            ep_data_seen = 1'b1;
                                                            `uvm_info("MAC_TX",
                                                                      $sformatf(
                                                                          "DLLP_START %h",
                                                                          ep_pvif.RxData[lane]),
                                                                      UVM_LOW)
                                                       end
          else if (ep_pvif.RxData[lane][129:128] == 2'b01) begin
                                                            case (ep_pvif.RxData[lane][127:120])
                                                                 8'h1E: begin
                                                                      ep_os_data = ep_pvif.RxData[lane][127:0];
                                                                      // void'(os_s(ep_os_data));
                                                                      ep_item.os_t_lane[lane].push_back(
                                                                          ep_os_data);
                                                                      `uvm_info("MAC_RX", $sformatf(
                                                                                "EP_ORDERSETS lane%0d %h",
                                                                                lane,
                                                                                ep_os_data
                                                                                ), UVM_LOW)
                                                                 end
                                                                 8'h2D: begin
                                                                      ep_os_data = ep_pvif.RxData[lane][127:0];
                                                                      //void'(os_s(ep_os_data));
                                                                      ep_item.os_t_lane[lane].push_back(
                                                                          ep_os_data);
                                                                 end
                                                                 8'h00: begin
                                                                      $display(
                                                                          "data lane%0d %h", lane,
                                                                          ep_pvif.RxData[lane]);
                                                                      ep_os_data = ep_pvif.RxData[lane][127:0];
                                                                      //void'(os_s(ep_os_data));
                                                                      ep_item.os_t_lane[lane].push_back(
                                                                          ep_os_data);
                                                                 end
                                                            endcase
                                                       end
                                                  end
                                             end

                                             if (ep_data_seen) begin
                                                  // ep_byte_unstriping() already generalizes to any cfg.num_lanes --
                                                  // with 1 lane it reassembles the same 4 DWs the old single-lane
                                                  // broadcast read produced, so no separate broadcast path is needed.
                                                  ep_byte_unstriping();
                                             end
                                        end
                                   end
                                   foreach (ep_r_data[i])
                                        `uvm_info("MAC_RX", $sformatf(
                                                  "Complete ep_r_data = %h", ep_r_data[i]),
                                                  UVM_HIGH)

                                   while (ep_r_data.size() > 0) begin

                                        if (ep_r_data[0][27:24] == 4'hF) begin

                                             ep_stp = ep_r_data.pop_front();
                                             ep_length = {ep_stp[22:16], ep_stp[31:28]};
                                             ep_fcrc = ep_stp[15:12];
                                             ep_seq_no = {ep_stp[7:0], ep_stp[11:8]};

                                             `uvm_info("MAC_RX", $sformatf(
                                                                     "STP=%h ep_length=%h seq=%0h",
                                                                     ep_stp, ep_length, ep_seq_no),
                                                       UVM_HIGH)

                                             // FIX: must clear ep_tlp_queue at the start of every new TLP (every
                                             // time a new STP is seen). Leaving this commented out let leftover
                                             // DWORDs from a TLP that hadn't yet hit its end-of-packet marker
                                             // bleed into the next back-to-back TLP's capture, corrupting the
                                             // DWORD stream used for the downstream LCRC recompute -> spurious
                                             // LCRC MISMATCH on back-to-back transfers (this is exactly what was
                                             // seen in B2B_Mem_Wr_Rd_3DW_test).
                                             ep_tlp_queue.delete();

                                             for (int i = 0; i < (ep_length - 1); i++) begin

                                                  if (ep_r_data.size() == 0) break;

                                                  ep_tlp_queue.push_back(ep_r_data.pop_front());

                                             end

                                             if (ep_r_data.size() >= 2) begin

                                                  if (ep_r_data[0][31:16] == 16'hF0AC) begin

                                                       ep_dllp_packet = {
                                                            ep_r_data[0][15:0],
                                                            ep_r_data[1][31:16],
                                                            ep_r_data[1][15:0],
                                                            16'h0
                                                       };

                                                       ep_r_data.delete(0);
                                                       ep_r_data.delete(0);

                                                       `uvm_info("MAC_RX", $sformatf(
                                                                               "DLLP = %h",
                                                                               ep_dllp_packet),
                                                                 UVM_HIGH)
                                                  end
                                             end

                                             if (ep_r_data[0] == 32'h1f809000) begin

                                                  foreach (ep_tlp_queue[i])
                                                       `uvm_info("MAC_RX", $sformatf(
                                                                 "EP_SCRAMBLED_BEFORE %h  time = %t",
                                                                 ep_tlp_queue[i],
                                                                 $time
                                                                 ), UVM_HIGH)
                                                  foreach (ep_tlp_queue[i])
                                                       `uvm_info("MAC_RX", $sformatf(
                                                                 "EP_SCRAMBLED_AFTER  %h  time = %t",
                                                                 ep_tlp_queue[i],
                                                                 $time
                                                                 ), UVM_HIGH)

                                                  ep_item.tlp_queue_t = ep_tlp_queue;
                                                  ep_r_data.delete();
                                                  ep_tlp_queue.delete();
                                                  `uvm_info(
                                                      "MAC_RX",
                                                      $sformatf(
                                                          "EP MAC RX DATA CAPTURED %p  time = %t",
                                                          ep_tlp_queue, $time), UVM_HIGH)
                                             end
                                        end else if (ep_r_data[0][31:16] == 16'hF0AC) begin
                                             `uvm_info("MAC_RX",
                                                       $sformatf(
                                                           "INSIDE WHILE LOOP - CONTINUOUS DLLP"),
                                                       UVM_HIGH)
                                             // Each DLLP occupies 4 raw dwords: [F0AC_xxxx][yyyy_zzzz][32'h0][32'h0].
                                             // Loop so that back-to-back DLLPs are each decoded individually and
                                             // the 2 trailing zero-pad dwords per DLLP are stripped, instead of
                                             // only decoding the first DLLP and dumping the rest raw.
                                             while(ep_r_data.size() >= 4 && ep_r_data[0][31:16] == 16'hF0AC) begin
                                                  ep_dlp_p_q.push_back(
                                                      {ep_r_data[0][15:0], ep_r_data[1][31:16]});
                                                  ep_dlp_p_q.push_back({ep_r_data[1][15:0], 16'h0});
                                                  ep_r_data.delete(0);  // F0AC dword
                                                  ep_r_data.delete(0);  // data dword
                                                  ep_r_data.delete(
                                                      0);  // zero-pad dword #1 (removed)
                                                  ep_r_data.delete(
                                                      0);  // zero-pad dword #2 (removed)
                                             end
                                             // Same rationale as the RC side: trailing dwords here are usually
                                             // just zero-pad from the fixed-width unstripe container, not real
                                             // DLLP payload. Only forward genuine non-zero unhandled leftovers.
                                             if (ep_r_data.size() > 0) begin
                                                  bit ep_leftover_nonzero;
                                                  ep_leftover_nonzero = 1'b0;
                                                  foreach (ep_r_data[i])
                                                  if (ep_r_data[i] != 32'h0)
                                                       ep_leftover_nonzero = 1'b1;

                                                  if (ep_leftover_nonzero) begin
                                                       `uvm_info(
                                                           "MAC_RX",
                                                           $sformatf(
                                                               "EP_DLLP_LEFTOVER_UNHANDLED %p",
                                                               ep_r_data), UVM_HIGH)
                                                       foreach (ep_r_data[i])
                                                       ep_dlp_p_q.push_back(ep_r_data[i]);
                                                  end else begin
                                                       `uvm_info("MAC_RX", $sformatf(
                                                                 "EP_DLLP_LEFTOVER_ZERO_PAD_DROPPED %p",
                                                                 ep_r_data
                                                                 ), UVM_HIGH)
                                                  end
                                             end
                                             ep_item.dlp_rx_queue = ep_dlp_p_q;
                                             foreach (ep_dlp_p_q[i])
                                                  `uvm_info("MAC_RX", $sformatf(
                                                            "EP_DLLP_Packet_Sent %h", ep_dlp_p_q[i]
                                                            ), UVM_HIGH)
                                             ep_r_data.delete();
                                             ep_dlp_p_q.delete();
                                        end else begin
                                             // Same livelock hazard as the RC side: neither STP nor DLLP header
                                             // unrecognized dword and move on.
                                             bit [31:0] ep_unmatched;
                                             ep_unmatched = ep_r_data.pop_front();
                                             `uvm_warning("MAC_RX_MON", $sformatf(
                                                          "[%s] Unrecognized leading dword %h in ep_r_data (not STP/DLLP) - dropped to avoid parser livelock",
                                                          tag,
                                                          ep_unmatched
                                                          ))
                                        end

                                   end
                                   // else begin
                                   `uvm_info("MAC_RX_MON", $sformatf(
                                             "EP MAC RX ORDEREDSET CAPTURED %p  time = %t",
                                             ep_item.os_t_lane,
                                             $time
                                             ), UVM_HIGH)
                                   `uvm_info("MAC_RX_MON", $sformatf(
                                             "[%s] EP MAC packet forwarded to RX path: tlp_queue=%0d dlp_queue=%0d",
                                             tag,
                                             ep_item.tlp_queue.size(),
                                             ep_item.dlp_rx_queue.size()
                                             ), UVM_LOW)
                                   mac_rx_rx_port.write(ep_item);
                                   `uvm_info("MAC_RX_MON", $sformatf("EP_deleted"), UVM_HIGH)

                                   for (int lane = 0; lane < cfg.num_lanes; lane++)
                                   ep_item.os_t_lane[lane].delete();
                                   // end
                              end

                         end
                         ep_collect_pipe_tx_data();
                         ep_collect_pipe_rx_data();

                    join_none
                    //end
               end

               default: `uvm_fatal("PCIe_MAC_monitor", $sformatf("[%s] Unknown mode", tag))

          endcase

     endtask
endclass

