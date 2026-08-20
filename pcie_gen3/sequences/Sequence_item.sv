class Sequence_item extends uvm_sequence_item;
  bit [31:0] tlp_q[$];
//   bit [31:0] tl_rx_q[$:159] = {32'h44108801, 32'h80001, 32'h200d94, 32'h275257e7, 32'hb9c24057};
  
  
  // Generic TLP Fields //
  
  rand tlp_type_e e_type;
  rand fmt_e      e_fmt;
  rand packet_type_e pkt_type;
  rand bit[4:0]   r_type;
  rand bit[2:0]   fmt;
       bit        R1;
  rand bit[2:0]   tc;
  rand vc_id_e    vc;          // resolved by map_tc_to_vc() from tc + the active tc2vc_table
       bit        R2;
  rand bit        attr_1;
       bit        R3;
  rand bit        th;
  rand bit        td;
  rand bit        ep;
  rand bit[1:0]   attr_2;
  rand bit[1:0]   at;
  rand bit[9:0]   length;
  rand logic[31:0]  payload[];
  
  //  Memory TLP Fields //
  
  rand bit[7:0]  bus;
  rand bit[4:0]  device;
  rand bit[2:0]  function_n; 
  rand bit[7:0]  ep_bus;
  rand bit[4:0]  ep_device;
  rand bit[2:0]  ep_function_n;  
  rand bit[7:0]  tag;
  rand bit[3:0]  last_BE;
  rand bit[3:0]  first_BE;
  rand bit[63:0] addr;
       bit[1:0]  R4;
       bit[15:0] req_id; 
  rand bit[15:0] ep_req_id; 
       bit[15:0] completer_id; 
  rand bit[2:0]  compl_status;
  rand bit       bcm;
  rand bit[11:0] byte_count;
  rand bit[3:0]  ext_register_num;
  rand bit[5:0]  register_num;
  rand bit[6:0]  lower_addr;
       bit[3:0]  R5;
       bit       R6;
       bit[31:0] ECRC;
       bit       ecrc_error;

  //-----------------------------------------------------------
  // PMA layer fields
  //   Used by pma_tx_driver / pma_tx_monitor for both RC_MODE
  //   and EP_MODE roles (serial 130-bit word capture/replay and
  //   their associated expected-size handshake counters).
  //-----------------------------------------------------------

  // pma rx side signals (EP_MODE)
  bit [129:0] pma_rx_data [`PCIE_NUM_LANES][$];
  bit [129:0] pma_tx_data_t [`PCIE_NUM_LANES][$];
  static int size_tx_rx[$];

  // pma tx side signals (RC_MODE)
  bit [129:0] pma_tx_data[`PCIE_NUM_LANES][$];
  bit [129:0] tx_data_q[`PCIE_NUM_LANES][$];
  static int size_rx_tx[$];

  bit [129:0] pma_rc_tx_q[$];
  bit [129:0] pma_rc_rx_q[$];
  bit [129:0] pma_ep_tx_q[$];
  bit [129:0] pma_ep_rx_q[$];


  //-----------------------------------------------------------
  // DLL layer fields
  //   Used by TX_DLL_Driver/TX_DLL_Monitor for both RC_MODE and
  //   EP_MODE roles - raw TL packet queues handed off between TL
  //   and DLL layers, and DLLP queues used during link/flow-
  //   control initialization (DL_INIT_FC1/DL_INIT_FC2).
  //-----------------------------------------------------------
  bit [31:0] rx_data[$];
  bit [31:0] tx_data[$];
  bit [31:0] rx_data_t[$];
  bit [31:0] tx_data_t[$];
  bit [31:0] dllp_packet_q [$];
  bit [31:0] dllp_packet_rx_q[$];

  bit [31:0] tx_data_sb[$];
  bit [31:0] rx_data_sb[$];

  bit [31:0] rc_com_data_sb[$];
  bit [31:0] ep_req_data_sb[$];

bit [31:0] rc_dllp_data_sb[$];
bit [31:0] rc_dllp_packet_sb[$];
bit [31:0] ep_dllp_data_sb[$];
bit [31:0] ep_dllp_packet_sb[$];



  // Flow-control credits exchanged via INITFC1/INITFC2 DLLPs
  reg [`NUM_VC][8]  fc_ph;
  reg [`NUM_VC][8]  fc_nph;
  reg [`NUM_VC][8]  fc_cmplh;
  reg [`NUM_VC][12] fc_pd;
  reg [`NUM_VC][12] fc_npd;
  reg [`NUM_VC][12] fc_cmpld;

    bit [7:0]  rc_header_pfc;
  bit [7:0]  rc_header_npfc;
  bit [7:0]  rc_header_cmplfc;
  bit [11:0] rc_data_pfc;
  bit [11:0] rc_data_npfc;
  bit [11:0] rc_data_cmplfc;

bit [3:0] rc_data_type;
bit [2:0] rc_dllp_vc;

    bit [7:0]  ep_header_pfc;
  bit [7:0]  ep_header_npfc;
  bit [7:0]  ep_header_cmplfc;
  bit [11:0] ep_data_pfc;
  bit [11:0] ep_data_npfc;
  bit [11:0] ep_data_cmplfc;

bit [3:0] ep_data_type;
bit [2:0] ep_dllp_vc;

bit ep_updated_credits;


  reg [`NUM_VC][8]  ep_fc_ph;
  reg [`NUM_VC][8]  ep_fc_nph;
  reg [`NUM_VC][8]  ep_fc_cmplh;
  reg [`NUM_VC][12] ep_fc_pd;
  reg [`NUM_VC][12] ep_fc_npd;
  reg [`NUM_VC][12] ep_fc_cmpld;


  bit [11:0] ep_ack_nak_seq;
  bit [11:0] rc_ack_nak_seq;

  
  ///////////rc_mon///////
  bit [7:0]  rc_ack_nack;
  bit [11:0] rc_ack_nack_seq;
  
   ///////////ep_mon///////
  bit [7:0]  ep_ack_nack;
  bit [11:0] ep_ack_nack_seq;


  //-----------------------------------------------------------
  // MAC layer fields
  //   Used by mac_tx_driver for both RC_MODE and EP_MODE roles -
  //   DLLP/TLP queues and PMA-reassembled ordered-set/data queues
  //   handed off between the PMA and DLL layers via analysis
  //   ports.
  //-----------------------------------------------------------
  bit [31:0]  dllp_packet [$];
  bit [31:0]  dllp_tx_packet [$];

  bit [31:0]  mac_rx_data[$][$];
  bit [31:0]  dlp_queue[$];
  bit [31:0]  dlp_rx_queue[$];
  bit [31:0]  mac_tx_data[$][$];

  bit [31:0]  tlp_queue_t[$];
  bit [31:0]  tlp_queue[$];
  bit [127:0] os_t_lane[`NUM_LANES][$];

  // Expected-count handshake fields used by mac_tx_monitor to
  // decide when a full TLP/DLLP burst has been captured.
  static int count_tlp = 0;
  static int count_tx_tlp = 0;

  `uvm_object_utils_begin(Sequence_item)
  `uvm_field_int(fmt,        UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(r_type,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(tc,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_enum(vc_id_e, vc, UVM_ALL_ON)
  `uvm_field_int(attr_1,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(th,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(td,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(ep,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(attr_2,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(at,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(length,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_array_int(payload,    UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(bus,        UVM_ALL_ON | UVM_DEC) 
  `uvm_field_int(device,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(function_n, UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(tag,        UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(last_BE,    UVM_ALL_ON | UVM_DEC) 
  `uvm_field_int(first_BE,   UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(addr,       UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end
  
  
  function new(string name = "Sequence_item");
    super.new(name);
  endfunction
    
   virtual function void do_print(uvm_printer printer);

  super.do_print(printer);

   // COMMON HEADER FIELDS (DW0)
 
  printer.print_field("fmt",        fmt,        3,  UVM_BIN);
  printer.print_field("r_type",     r_type,     5,  UVM_BIN);
  printer.print_field("R1",         R1,         1,  UVM_BIN);
  printer.print_field("tc",         tc,         3,  UVM_BIN);
  printer.print_field("vc",         vc,         3,  UVM_DEC);
  printer.print_field("R2",         R2,         1,  UVM_BIN);
  printer.print_field("attr_1",     attr_1,     1,  UVM_BIN);
  printer.print_field("R3",         R3,         1,  UVM_BIN);
  printer.print_field("th",         th,         1,  UVM_BIN);
  printer.print_field("td",         td,         1,  UVM_BIN);
  printer.print_field("ep",         ep,         1,  UVM_BIN);
  printer.print_field("attr_2",     attr_2,     2,  UVM_BIN);
  printer.print_field("at",         at,         2,  UVM_BIN);
  printer.print_field("length",     length,    10,  UVM_DEC);

   // TYPE SPECIFIC FIELDS
 
  case(e_type)

  // MEMORY REQUESTS
 
    MEM_RD, MEM_WR : begin
      printer.print_field("req_id",     req_id,     16, UVM_HEX);
      printer.print_field("tag",        tag,         8, UVM_HEX);
      printer.print_field("last_BE",    last_BE,     4, UVM_BIN);
      printer.print_field("first_BE",   first_BE,    4, UVM_BIN);
      printer.print_field("addr",       addr,        64, UVM_HEX);

      if(e_type == MEM_WR) begin

        foreach(payload[i]) begin

          printer.print_field($sformatf("payload[%0d]", i), payload[i], 32, UVM_HEX);

        end

      end

    end

     // IO REQUESTS
 
    IO_RD, IO_WR : begin

      printer.print_field("req_id",     req_id,     16, UVM_HEX);
      printer.print_field("tag",        tag,         8, UVM_HEX);
      printer.print_field("last_BE",    last_BE,     4, UVM_BIN);
      printer.print_field("first_BE",   first_BE,    4, UVM_BIN);
      printer.print_field("addr",       addr,        32, UVM_HEX);

      if(e_type == IO_WR) begin

        foreach(payload[i]) begin

          printer.print_field($sformatf("payload[%0d]", i), payload[i], 32, UVM_HEX);

        end

      end

    end

     // CONFIGURATION REQUESTS
 
    CFG_RD0, CFG_WR0, CFG_RD1, CFG_WR1 : begin

      printer.print_field("req_id",           req_id,           16, UVM_HEX);
      printer.print_field("tag",              tag,               8, UVM_HEX);
      printer.print_field("last_BE",          last_BE,           4, UVM_BIN);
      printer.print_field("first_BE",         first_BE,          4, UVM_BIN);
      printer.print_field("bus",              bus,               8, UVM_HEX);
      printer.print_field("device",           device,            5, UVM_HEX);
      printer.print_field("function_n",       function_n,        3, UVM_HEX);
      printer.print_field("R5",               R5,                4, UVM_BIN);
      printer.print_field("ext_register_num", ext_register_num,  4, UVM_HEX);
      printer.print_field("register_num",     register_num,      8, UVM_HEX);
      printer.print_field("R4",               R4,                2,  UVM_BIN);

      if(e_type inside {CFG_WR0, CFG_WR1}) begin

        foreach(payload[i]) begin

          printer.print_field($sformatf("payload[%0d]", i), payload[i], 32, UVM_HEX);

        end

      end

    end

     // COMPLETIONS
 
    CPL, CPL_DATA : begin

      printer.print_field("completer_id", completer_id, 16, UVM_HEX);
      printer.print_field("compl_status", compl_status,  3, UVM_BIN);
      printer.print_field("bcm",          bcm,           1, UVM_BIN);
      printer.print_field("byte_count",   byte_count,   10, UVM_DEC);
      printer.print_field("req_id",       req_id,       16, UVM_HEX);
      printer.print_field("req_id",       req_id,       16, UVM_HEX);
      printer.print_field("ep_req_id",    ep_req_id,    16, UVM_HEX);
      printer.print_field("tag",          tag,           8, UVM_HEX);
      printer.print_field("R6",           R6,            1, UVM_BIN);
      printer.print_field("lower_addr",   lower_addr,    7, UVM_HEX);

      if(e_type == CPL_DATA) begin

        foreach(payload[i]) begin

          printer.print_field($sformatf("payload[%0d]", i),payload[i], 32, UVM_HEX);

        end

      end

    end

     // MESSAGE REQUESTS
 
    MSG_RTRC, MSG_RBA, MSG_RBI, MSG_IBD, MSG_ILTAR, MSG_GARTRC, MSG_RESERVED1, MSG_RESERVED2 : begin

      printer.print_field("req_id",     req_id,     16, UVM_HEX);
      printer.print_field("tag",        tag,         8, UVM_HEX);
      printer.print_field("last_BE",    last_BE,     4, UVM_BIN);
      printer.print_field("first_BE",   first_BE,    4, UVM_BIN);
      printer.print_field("addr",       addr,       64,UVM_HEX);

    end

  endcase

endfunction

     
  // Set by the sequence/driver before randomize(), from env_cfg.tc2vc_table.
  // Declared static so every item defaults to identity mapping (tc==vc)
  // until a test explicitly installs a different table.
  static vc_id_e tc2vc_table[8] = '{VC0, VC1, VC2, VC3, VC4, VC5, VC6, VC7};

  function void post_randomize();
    req_id    = {bus, device, function_n};
    ep_req_id = {ep_bus, ep_device, ep_function_n};

    // TC -> VC mapping (mirrors the VC Resource Control register's
    // TC/VC mapping bits in real PCIe hardware)
    vc = tc2vc_table[tc];
  endfunction
      
  constraint MEM_RD_CONSTRAINT {
    
    if(e_type == MEM_RD) {
      
      r_type == 5'b00000;
      
      if(e_fmt == FMT_3DW_NO_DATA) {
        
        fmt == 3'b000;
       // addr[63:32] == 0;
       // addr[31:2] inside {[32'h4 : 32'h100]};
        
      }
        
        if(e_fmt == FMT_4DW_NO_DATA) {
          
          fmt == 3'b001;
         // addr[63:2] inside {[64'h4 : 64'h200]};
          
        }
          
          //length inside {[1:10]};
          payload.size() == 0;
          first_BE inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
          last_BE  inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
    }
  }
      
  constraint MEM_WR_CONSTRAINT {
    
    if(e_type == MEM_WR) {
      
      r_type == 5'b00000;
      
      if(e_fmt == FMT_3DW_DATA) {
        
        fmt         == 3'b010;
        //addr[63:32] == 0;
        //addr[31:2] inside {[32'h4 : 32'h100]};
        
      }
        
        if(e_fmt == FMT_4DW_DATA) {
          
          fmt   == 3'b011;
          //addr[63:2] inside {[64'h4 : 64'h200]};
          
        }
          
          payload.size() inside {[0:1023]};
      
          length == payload.size();

          first_BE inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
          last_BE  inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
    }
  }
  
  constraint IO_RD_CONSTRAINT {
    
    if(e_type == IO_RD) {
      
      r_type == 5'b00010;
            
      e_fmt       == FMT_3DW_NO_DATA;
      fmt         == 3'b000;
      //addr[63:32] == 0;
      //addr[31:2] inside {[32'h4 : 32'h100]};
        
        
        payload.size() == 0;
      
        //length == 1;
      
        first_BE inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
        
        last_BE  inside {4'b0000};
    }
  }
      
  constraint IO_WR_CONSTRAINT {
    
    if(e_type == IO_WR) {
      
      r_type == 5'b00010;
          
      e_fmt       == FMT_3DW_DATA;
      fmt         == 3'b010;
      //addr[63:32] == 0;
      //addr[31:2] inside {[32'h4 : 32'h100]};
        
        
      payload.size() == 1;
      
       // length == 1;
      
        first_BE inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
        
        last_BE  inside {4'b0000};
    }
  }
      
  constraint CFG_RD0_CONSTRAINT {
    
    if(e_type == CFG_RD0) {
      
      r_type == 5'b00100;

      e_fmt == FMT_3DW_NO_DATA;

      fmt   == 3'b000;

      payload.size() == 0;

      length == 1;

      bus        inside {[0:255]};
      device     inside {[0:31]};
      function_n inside {[0:7]};

      ext_register_num inside {[0:15]};
      register_num     inside {[0:255]};

      first_BE inside {4'b0001, 4'b0011, 4'b0111, 4'b1111, 4'b1000, 4'b1100, 4'b1110};

     last_BE == {4'b0000};
    }
  }
      
  constraint CFG_WR0_CONSTRAINT {
    
    if(e_type == CFG_WR0) {
      
      r_type == 5'b00100;

      e_fmt == FMT_3DW_DATA;
      fmt   == 3'b010;

      payload.size() == 1;

      length == 1;

      bus        inside {[0:255]};
      device     inside {[0:31]};
      function_n inside {[0:7]};

      ext_register_num inside {[0:15]};
      register_num     inside {[0:255]};

      first_BE inside {4'b0001, 4'b0011, 4'b0111, 4'b1111, 4'b1000, 4'b1100, 4'b1110};
 
      last_BE == 4'b0000;
    }
  }
      
  constraint CFG_RD1_CONSTRAINT {

    if(e_type == CFG_RD1) {

      r_type == 5'b00101;

      e_fmt == FMT_3DW_NO_DATA;
      fmt   == 3'b000;

      payload.size() == 0;

      length == 1;

      bus        inside {[0:255]};
      device     inside {[0:31]};
      function_n inside {[0:7]};

      ext_register_num inside {[0:15]};
      register_num     inside {[0:255]};

      first_BE inside {4'b0001, 4'b0011, 4'b0111, 4'b1111, 4'b1000, 4'b1100, 4'b1110};

      last_BE == 4'b0000;
    }
  }
      
  constraint CFG_WR1_CONSTRAINT {

    if(e_type == CFG_WR1) {

      r_type == 5'b00101;

      e_fmt == FMT_3DW_DATA;
      fmt   == 3'b010;

      payload.size() == 1;

      length == 1;

      bus        inside {[0:255]};
      device     inside {[0:31]};
      function_n inside {[0:7]};

      ext_register_num inside {[0:15]};
      register_num     inside {[0:255]};

      first_BE inside {4'b0001, 4'b0011, 4'b0111, 4'b1111, 4'b1000, 4'b1100, 4'b1110};

      last_BE == 4'b0000;
    }
  }
      
  constraint CPL_CONSTRAINT {

    if(e_type == CPL) {

      r_type == 5'b01010;

      e_fmt == FMT_3DW_NO_DATA;
      fmt   == 3'b000;

      payload.size() == 0;

      length inside {[0:1024]};

      completer_id inside {[0:16'hFFFF]};

      compl_status inside {[0:7]};

      bcm inside {0,1};

      byte_count inside {[0:1024]};

      lower_addr inside {[0:127]};
    }
  }
      
  constraint CPL_DATA_CONSTRAINT {
    
    if(e_type == CPL_DATA) {

      r_type == 5'b01010;

      e_fmt == FMT_3DW_DATA;
      fmt   == 3'b010;

      payload.size() inside {[1:1024]};

      length == payload.size();

      completer_id inside {[0:16'hFFFF]};

      compl_status inside {[0:7]};

      bcm inside {0,1};

      byte_count inside {[1:4096]};

      lower_addr inside {[0:127]};
    }
  }
      
  constraint RESERVED_BITS_CONSTRAINT {
    R1 == 0;
    R2 == 0;
    R3 == 0;
    R4 == 2'b00;
  }

  constraint TRAFFIC_CLASS_CONSTRAINT {
    tc inside {[0:7]};
  }
      
  constraint ATTRIBUTE_1_CONSTRAINT {
    attr_1 inside {0,1};
  }
      
  constraint TLP_PROCESSING_HINTS_CONSTRAINT {
    th inside {0,1};
  }
      
  constraint TLP_DIGEST_CONSTRAINT {
    td inside {0,1};
  }
      
  constraint ERROR_POISON_CONSTRAINT {
    ep inside {0,1};
  }
      
  constraint ADDRESS_TRANSLATION_CONSTRAINT {
    at inside {2'b10};
  }
      
  constraint BUS_CONSTRAINT {
    bus inside {8'b0};
  }
      
  constraint DEVICE_CONSTRAINT {
    device inside {5'b1};
  }
      
  constraint FUNCTION_CONSTRAINT {
    function_n inside {3'b0};
  }
      
  constraint TAG_CONSTRAINT {
    tag inside {[0:255]};
  }


  constraint PKT_TYPE_CONSTRAINT {

  if (e_type inside {MEM_WR}) {
    pkt_type == P;
  }

  if (e_type inside {MEM_RD,
                     IO_RD,
                     IO_WR,
                     CFG_RD0,
                     CFG_RD1,
                     CFG_WR0,
                     CFG_WR1}) {
    pkt_type == NP;
  }

  if (e_type inside {CPL,
                     CPL_DATA}) {
    pkt_type == CMPL;
  }

}


    function void pack_tlp();
    
    bit [31:0] dw;
    
    /////////////////////////////////////////////////////////   DOUBLE WORD ZERO (BYTE 0)   /////////////////////////////////////////////////////////////////////////
    
  case(e_type)

    CPL : begin
      fmt    = 3'b000;
      r_type = 5'b01010;
    end

    CPL_DATA : begin
      fmt    = 3'b010;
      r_type = 5'b01010;
    end

  endcase

  tlp_q.delete();
    
    dw = {fmt, r_type, R1, tc, R2, attr_1, R3, th, td, ep, attr_2, at, length};
    
    tlp_q.push_back(dw);
    
    /////////////////////////////////////////////////////////   DOUBLE WORD ONE (BYTE 4)   //////////////////////////////////////////////////////////////////////////
    
    case(e_type)
      
    MEM_RD, MEM_WR, IO_RD, IO_WR, CFG_RD0, CFG_WR0, CFG_RD1, CFG_WR1, MSG_RTRC, MSG_RBA, MSG_RBI, MSG_IBD, MSG_ILTAR, MSG_GARTRC : begin
      
      dw = {req_id, tag, last_BE, first_BE};
      
      tlp_q.push_back(dw);
    
    end

    CPL, CPL_DATA : begin
      
      dw = {completer_id, compl_status, bcm, byte_count};
      
      tlp_q.push_back(dw);
    
    end
    
    endcase
    
    /////////////////////////////////////////////////////////   DOUBLE WORD TWO (BYTE 8)   //////////////////////////////////////////////////////////////////////////
    
    case(e_type)
      
    MEM_RD, MEM_WR : begin
      
      if((e_fmt == FMT_3DW_DATA) || (e_fmt == FMT_3DW_NO_DATA)) begin
        
        dw = {addr[31:2], R4};
        tlp_q.push_back(dw);
      end

      else begin
        
        tlp_q.push_back(addr[63:32]);
        dw = {addr[31:2], R4};
        tlp_q.push_back(dw);
      end
    
    end
      
      IO_RD, IO_WR : begin
        
        dw = {addr[31:2], R4};
        tlp_q.push_back(dw);
      
      end
      
      CFG_RD0, CFG_WR0, CFG_RD1, CFG_WR1 : begin
  	`uvm_info("SEQUENCE_ITEM", $sformatf("EP_BUS = %0d, EP_DEVICE = %0d, EP_FUNCTION = %0d", ep_bus, ep_device, ep_function_n), UVM_LOW)
        
	dw = {ep_bus, ep_device, ep_function_n, R5, ext_register_num, register_num, R4};
	`uvm_info("PACK",
$sformatf("PACK: reg_num=%0d ext_reg=%0d DW2=%08h",
register_num, ext_register_num, dw), UVM_NONE)
        tlp_q.push_back(dw);
      
      end

    CPL, CPL_DATA : begin
      
      dw = {req_id, tag, R6, lower_addr};
      tlp_q.push_back(dw);
    
    end

//     MSG_RTRC, MSG_RBA, MSG_RBI, MSG_IBD, MSG_ILTAR, MSG_GARTRC : begin
      
//       tlp_q.push_back(msg_dw2);
      
//       if(e_fmt inside {FMT_4DW_NO_DATA, FMT_4DW_DATA})
//         tlp_q.push_back(msg_dw3);
    
//     end
    
    endcase
    
    ///////////////    PAYLOAD     ////////////////////
    
    foreach(payload[i])
      tlp_q.push_back(payload[i]);
    
    /////////////////    ECRC   ///////////////////
    
    if(td) begin
      
      bit [31:0] ecrc;
      
      ecrc = calculate_ecrc();
      
      tlp_q.push_back(ecrc);
    end
    
    endfunction
    
    function bit [31:0] calculate_ecrc();
      bit [31:0] crc;
      bit [31:0] ecrc;
      bit data_bit;
      bit feedback;
      
      crc = 32'hFFFF_FFFF;
      
      foreach(tlp_q[i]) begin
        
        for(int b = 0; b < 32; b++) begin
          
          data_bit  = tlp_q[i][b];

          feedback  = crc[0] ^ data_bit;

          crc = crc >> 1;
          
          if(feedback)
            crc ^= 32'hEDB8_8320;// Standard Polynomial - 04C11DB7

        end

      end
      
      crc = ~crc;

      for (int byte_num = 0; byte_num < 4; byte_num++) begin

       for (int bit_num = 0; bit_num < 8; bit_num++) begin

         ecrc[byte_num*8 + bit_num] = crc[byte_num*8 + (7-bit_num)];

       end

     end

     return ecrc;

    
    endfunction : calculate_ecrc

endclass : Sequence_item
  
  
  	



