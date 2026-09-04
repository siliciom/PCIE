`uvm_analysis_imp_decl(_trx1)
`uvm_analysis_imp_decl(_rrx1)

class PCIe_DL_Coverage extends uvm_subscriber #(Sequence_item);
     `uvm_component_utils(PCIe_DL_Coverage)

     uvm_analysis_imp_trx1 #(Sequence_item, PCIe_DL_Coverage) TX_DL_Recvx1;
     uvm_analysis_imp_rrx1 #(Sequence_item, PCIe_DL_Coverage) RX_DL_Recvx1;

     Sequence_item item;




     // Build Phase
     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          TX_DL_Recvx1 = new("TX_DL_Recvx1", this);
          RX_DL_Recvx1 = new("RX_DL_Recvx1", this);
     endfunction


     // TX Analysis Port
     function void write_trx1(Sequence_item tx_pkt);

          item = tx_pkt;

          DLP_cg.sample();

     endfunction


     // RX Analysis Port
     function void write_rrx1(Sequence_item rx_pkt);

          item = rx_pkt;

          DLP_cg.sample();

     endfunction


     // Default Subscriber Write
     virtual function void write(Sequence_item t);

          item = t;

          DLP_cg.sample();

     endfunction


     // Data Link Layer Functional Coverage
     covergroup DLP_cg;

          option.per_instance = 1;
          option.name = "DLP_cg";


          // RC Flow Control Header Credits

          rc_hdr_pfc1: coverpoint item.rc_header_pfc {
               bins rc_hdr_pfc = {[0 : 255]};
          }

          rc_hdr_npfc1: coverpoint item.rc_header_npfc {bins rc_hdr_npfc = {[0 : 255]};}

          rc_hdr_cmplfc1: coverpoint item.rc_header_cmplfc {bins rc_hdr_cmplfc = {[0 : 255]};}


          // RC Flow Control Data Credits

          rc_data_pfc1: coverpoint item.rc_data_pfc {
               bins rc_data_pfc = {[0 : 4095]};
          }

          rc_data_npfc1: coverpoint item.rc_data_npfc {bins rc_data_npfc = {[0 : 4095]};}

          rc_data_cmplfc1: coverpoint item.rc_data_cmplfc {bins rc_data_cmplfc = {[0 : 4095]};}


          // RC Data Type and VC

          rc_data_typ1: coverpoint item.rc_data_type {
               bins rc_data_typ[] = {4'b0100, 4'b0101, 4'b0110, 4'b1000};
          //ignore_bins others = default;
          }

          rc_dllp_vc1: coverpoint item.rc_dllp_vc {bins rc_dllp_v[] = {[0 : 7]};}


          // EP Flow Control Header Credits

          ep_hdr_pfc1: coverpoint item.ep_header_pfc {
               bins ep_hdr_pfc = {[0 : 255]};
          }

          ep_hdr_npfc1: coverpoint item.ep_header_npfc {bins ep_hdr_npfc = {[0 : 255]};}

          ep_hdr_cmplfc1: coverpoint item.ep_header_cmplfc {bins ep_hdr_cmplfc = {[0 : 255]};}


          // EP Flow Control Data Credits

          ep_data_pfc1: coverpoint item.ep_data_pfc {
               bins ep_data_pfc = {[0 : 4095]};
          }

          ep_data_npfc1: coverpoint item.ep_data_npfc {bins ep_data_npfc = {[0 : 4095]};}

          ep_data_cmplfc1: coverpoint item.ep_data_cmplfc {bins ep_data_cmplfc = {[0 : 4095]};}


          // EP Data Type and VC

          ep_data_typ1: coverpoint item.ep_data_type {
               bins ep_data_typ[] = {4'b0100, 4'b0101, 4'b0110, 4'b1000, 4'b1010, 4'b1001};
          //ignore_bins others = default;
          }

          ep_dllp_vc1: coverpoint item.ep_dllp_vc {bins ep_dllp_v[] = {[0 : 7]};}


          // RC ACK / NAK Coverage

          rc_ack_nac1: coverpoint item.rc_ack_nack {

               bins rc_ack = {8'b0000_0000}; bins rc_nack = {8'b0001_0000};
          //ignore_bins others = default;

          }


          // RC ACK / NAK Sequence Number

          rc_ack_nack_seq1: coverpoint item.rc_ack_nack_seq {

               bins rc_seq_num[] = {[0 : 150]};

          }


          // NEW: RC TLP Sequence Number Coverage
          // 12-bit sequence number
          // Range = 0 to 4095

          rc_seq_no1: coverpoint item.rc_seq_no {

               bins rc_seq_num[] = {[0 : 150]};

          }


          // EP ACK / NAK Coverage

          ep_ack_nac1: coverpoint item.ep_ack_nack {

               bins ep_ack = {8'b0000_0000};
               ignore_bins ep_nack = {8'b0001_0000};  // not corrupting from ep side
          //ignore_bins others = default;

          }



          ep_ack_nack_seq1: coverpoint item.ep_seq_no {bins ep_seq_num[] = {[0 : 150]};}


          // NEW: EP TLP Sequence Number Coverage
          // 12-bit sequence number
          // Range = 0 to 4095

          ep_seq_no1: coverpoint item.ep_seq_no {

               bins ep_seq_num[] = {[0 : 150]};

          }

     endgroup : DLP_cg

     function new(string name, uvm_component parent);
          super.new(name, parent);
          DLP_cg = new();
     endfunction
     // Report Phase
     virtual function void report_phase(uvm_phase phase);

          `uvm_info("PCIe_DL_Coverage", $sformatf("DLP_cg coverage = %0.2f%%", DLP_cg.get_coverage()
                    ), UVM_HIGH)

     endfunction : report_phase

endclass : PCIe_DL_Coverage

