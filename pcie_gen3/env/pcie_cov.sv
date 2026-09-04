`uvm_analysis_imp_decl(_trx)
`uvm_analysis_imp_decl(_rrx)

class PCIe_TL_Coverage extends uvm_subscriber #(Sequence_item);
     `uvm_component_utils(PCIe_TL_Coverage)

     uvm_analysis_imp_trx #(Sequence_item, PCIe_TL_Coverage) TX_TL_Recvx;
     uvm_analysis_imp_rrx #(Sequence_item, PCIe_TL_Coverage) RX_TL_Recvx;


     Sequence_item item;

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);
          TX_TL_Recvx = new("TX_TL_Recvx", this);
          RX_TL_Recvx = new("RX_TL_Recvx", this);
     endfunction

     function void write_trx(Sequence_item tx_pkt);
          item = tx_pkt;
          TLP_cg.sample();

     endfunction
     function void write_rrx(Sequence_item rx_pkt);
          item = rx_pkt;
          TLP_cg.sample(); //  take the current packet's field values right now, and update the coverage bins accordingly
     endfunction

     virtual function void write(Sequence_item t);
          item = t;
          TLP_cg.sample();
     endfunction
     typedef enum {
          PAYLOAD_EMPTY,
          PAYLOAD_LOW_VALUES,
          PAYLOAD_MID_VALUES,
          PAYLOAD_HIGH_VALUES,
          PAYLOAD_MIXED
     } payload_range_e;

     // Classifies the ENTIRE payload array by value range - not just DW[0].
     // "low/mid/high" only applies cleanly if every DW in the payload falls
     // in the same bucket; a payload spanning multiple buckets is PAYLOAD_MIXED.
     function payload_range_e classify_payload_range(bit [31:0] payload[]);
          bit is_low, is_mid, is_high;

          if (payload.size() == 0) return PAYLOAD_EMPTY;

          is_low  = 1;
          is_mid  = 1;
          is_high = 1;

          foreach (payload[i]) begin
               if (!(payload[i] inside {[32'h0000_0000 : 32'h0000_FFFF]})) is_low = 0;
               if (!(payload[i] inside {[32'h0001_0000 : 32'h7FFF_FFFF]})) is_mid = 0;
               if (!(payload[i] inside {[32'h8000_0000 : 32'hFFFF_FFFF]})) is_high = 0;
          end

          if (is_low) return PAYLOAD_LOW_VALUES;
          if (is_mid) return PAYLOAD_MID_VALUES;
          if (is_high) return PAYLOAD_HIGH_VALUES;

          return PAYLOAD_MIXED;
     endfunction


     covergroup TLP_cg;
          option.per_instance = 1;  //"Track/report coverage separately for each instance of this covergroup."
          option.name = "TLP_cg";

          cp_e_type: coverpoint item.e_type {
               bins mem_rd = {MEM_RD};
               bins mem_wr = {MEM_WR};
               bins io_rd = {IO_RD};
               bins io_wr = {IO_WR};
               bins cfg_rd0 = {CFG_RD0};
               bins cfg_wr0 = {CFG_WR0};
               ignore_bins cfg_rd1 = {CFG_RD1};
               ignore_bins cfg_wr1 = {CFG_WR1};
               bins cpl = {CPL};
               bins cpl_data = {CPL_DATA};
          }

          cp_fmt: coverpoint item.fmt {
               bins fmt_3dw_no_data = {3'b000};
               bins fmt_4dw_no_data = {3'b001};
               bins fmt_3dw_data = {3'b010};
               bins fmt_4dw_data = {3'b011};

          }

          cp_r_type: coverpoint item.r_type {
               bins mem = {5'b00000};
               bins io = {5'b00010};
               bins cfg0 = {5'b00100};
               ignore_bins cfg1 = {5'b00101};
               bins cpl = {5'b01010};

          }


          cp_tc: coverpoint item.tc {bins tc_val[8] = {[0 : 7]};}



          cp_attr_1: coverpoint item.attr_1 {bins vals[] = {0};}
          cp_th: coverpoint item.th {bins vals[] = {0};}
          cp_td: coverpoint item.td {bins vals[] = {0, 1};}
          cp_ep: coverpoint item.ep {bins vals = {0}; ignore_bins val = {1};}

          cp_attr_2: coverpoint item.attr_2 {ignore_bins vals[4] = {[0 : 3]};}

          cp_at: coverpoint item.at {
               ignore_bins at_00 = {2'b00};
               ignore_bins at_01 = {2'b01};
               bins at_10 = {2'b10};
               ignore_bins at_11 = {2'b11};
          }

          // Length coverage - bucketed ranges across legal 1..1024 DW range
          cp_length: coverpoint item.length {
               bins len_1 = {1};
               bins len_2_4 = {[2 : 4]};
               bins len_5_16 = {[5 : 16]};
               bins len_17_64 = {[17 : 64]};
               bins len_65_256 = {[65 : 256]};
               bins len_257_1023 = {[257 : 1023]};
          }

          // First/Last Byte Enable legal combinations
          cp_first_be: coverpoint item.first_BE {
               bins be_0001 = {4'b0001};
               bins be_0011 = {4'b0011};
               bins be_0111 = {4'b0111};
               bins be_1111 = {4'b1111};
               bins be_1000 = {4'b1000};
               bins be_1100 = {4'b1100};
               bins be_1110 = {4'b1110};
               bins be_0000 = {4'b0000};
               bins be_illegal = default;
          }

          cp_last_be: coverpoint item.last_BE {
               bins be_0001 = {4'b0001};
               bins be_0011 = {4'b0011};
               bins be_0111 = {4'b0111};
               bins be_1111 = {4'b1111};
               bins be_1000 = {4'b1000};
               bins be_1100 = {4'b1100};
               bins be_1110 = {4'b1110};
               bins be_0000 = {4'b0000};
               bins be_illegal = default;
          }

          cp_addr_range: coverpoint item.addr[31:2] {
               bins addr_low = {[32'h10000004 : 32'h10000040]};
               bins addr_mid = {[32'h10000041 : 32'h1000000C0]};
               bins addr_high = {[32'h100000C1 : 32'h100000100]};
          //  bins addr_others = default;
          }

          cp_addr_64bit: coverpoint (item.addr[63:32] != 0) {
               bins addr_32bit = {0};  // this bin got hit when expression becomes false
               bins addr_64bit = {1};  // this bin got hit when expression becomes true
          }
          cp_bus: coverpoint item.bus {bins vals = {[0 : 255]};}
          cp_device: coverpoint item.device {bins vals = {[0 : 31]};}
          cp_function_n: coverpoint item.function_n {bins vals = {[0 : 7]};}
          cp_tag: coverpoint item.tag {
               bins base_tag_0_31[] = {[0 : 145]}; bins extended_tag_32_255 = {[146 : 255]};
          }

          // Completer-side routing fields (ep_bus/ep_device/ep_function_n) -
          // used for CFG requests' DW2 target-function encoding in
          // pack_tlp(). Previously unrepresented in coverage.
          cp_ep_bus: coverpoint item.ep_bus {
               bins vals = {[0 : 255]};
          }
          cp_ep_device: coverpoint item.ep_device {bins vals = {[0 : 31]};}
          cp_ep_function_n: coverpoint item.ep_function_n {bins vals = {[0 : 7]};}


          // Configuration space register access
          cp_ext_reg_num: coverpoint item.ext_register_num {
               bins vals = {[0 : 15]};
          }
          cp_reg_num: coverpoint item.register_num {bins vals = {[0 : 255]};}

          // Completion specific fields
          cp_compl_status: coverpoint item.compl_status {
               bins successful_completion = {3'b000};
               bins unsupported_request = {3'b001};
               ignore_bins config_request_retry = {3'b010};
               bins completer_abort = {3'b100};
               ignore_bins reserved = {3'b011, 3'b101, 3'b110, 3'b111};

          }

          cp_bcm: coverpoint item.bcm {bins vals = {0}; ignore_bins val1 = {1};}

          cp_byte_count: coverpoint item.byte_count {
               bins bc_1_4 = {[1 : 4]}; bins bc_5_64 = {[5 : 64]};
          }

          cp_lower_addr: coverpoint item.lower_addr {bins vals = {[0 : 127]};}


          // Payload / ECRC
          cp_payload_size: coverpoint item.payload.size() {
               bins empty = {0};
               bins single_dw = {1};
               bins few_dw = {[2 : 16]};
               bins mid_dw = {[17 : 256]};
               bins many_dw = {[257 : 1024]};
          }

          cp_payload_data_value: coverpoint classify_payload_range(
              item.payload
          ) {
               bins low_values = {PAYLOAD_LOW_VALUES};
               bins mid_values = {PAYLOAD_MID_VALUES};
               bins high_values = {PAYLOAD_HIGH_VALUES};
               bins mixed = {PAYLOAD_MIXED};
          }

          // Cross coverage
          cx_type_fmt : cross cp_e_type, cp_fmt{
               // no-data types must never pair with a *_data format
               ignore_bins no_data_illegal =
      binsof(cp_e_type) intersect {CPL, MEM_RD, CFG_RD0, IO_RD} &&
      binsof(cp_fmt)    intersect {
                    FMT_4DW_DATA, FMT_3DW_DATA
               };

               // data-bearing types must never pair with a *_no_data format
               ignore_bins data_illegal =
      binsof(cp_e_type) intersect {CPL_DATA, MEM_WR, CFG_WR0, IO_WR} &&
      binsof(cp_fmt)    intersect {
                    FMT_4DW_NO_DATA, FMT_3DW_NO_DATA
               };

               // config/IO TLPs are always 3DW, never 4DW
               ignore_bins no_4dw_for_cfg_io =
      binsof(cp_e_type) intersect {CFG_WR0, CFG_RD0, IO_WR, IO_RD} &&
      binsof(cp_fmt)    intersect {
                    FMT_4DW_DATA, FMT_4DW_NO_DATA
               };
          }
     endgroup : TLP_cg


     function new(string name = "PCIe_TL_Coverage", uvm_component parent = null);
          super.new(name, parent);
          TLP_cg = new();
     endfunction : new

     virtual function void report_phase(uvm_phase phase);
          `uvm_info("PCIe_TL_Coverage", $sformatf("TLP_cg coverage = %0.2f%%", TLP_cg.get_coverage()
                    ), UVM_HIGH)
     endfunction : report_phase

endclass : PCIe_TL_Coverage

