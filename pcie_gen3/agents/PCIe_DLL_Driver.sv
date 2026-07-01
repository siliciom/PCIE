`uvm_analysis_imp_decl(_TX)
`uvm_analysis_imp_decl(_RX)
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)

class PCIe_DLL_Driver extends uvm_driver #(Sequence_item);

  `uvm_component_utils(PCIe_DLL_Driver)

  env_cfg cfg;
  string  tag;

  virtual TX_DLL_PCS_Interface TX_DLL_PCS;
  virtual TX_TL_DL_Interface   TX_TL_DL;

  virtual RX_DLL_PCS_Interface RX_DLL_PCS;
  virtual RX_TL_DL_Interface   RX_TL_DL;

  uvm_analysis_imp_RX #(Sequence_item, PCIe_DLL_Driver) rc_RX_MD_Recv;
  uvm_analysis_imp_TX #(Sequence_item, PCIe_DLL_Driver) rc_TX_MD_Recv;

  uvm_analysis_imp_rx #(Sequence_item, PCIe_DLL_Driver) ep_RX_MD_Recv;
  uvm_analysis_imp_tx #(Sequence_item, PCIe_DLL_Driver) ep_TX_MD_Recv;
  
  
  bit [31:0] rc_rx_local_queue[$];
  bit [31:0] rc_tx_local_queue[$];

  bit [11:0] rc_next_transmit_seq = 12'd2;
  bit [11:0] rc_DL_SEQ;

  typedef struct {
    bit [31:0] packet_q[$];
  } rc_replay_pkt;
  rc_replay_pkt rc_replay_buffer[2048];

  int rc_wr_ptr = 0;
  int rc_rd_ptr = 0;
  int rc_outstanding_pkt_count = 0;

  mailbox #(Sequence_item) rc_tx_pkt_mb;
  mailbox #(Sequence_item) rc_rx_pkt_mb;
  Sequence_item rc_rx_pkt;

  typedef enum bit [1:0] { DL_INACTIVE, DL_INIT_FC1, DL_INIT_FC2, DL_ACTIVE } rc_dl_state_e;
  rc_dl_state_e rc_dl_state;
  bit rc_FL1;
  bit rc_FL2;
  bit rc_dl_up;
  bit rc_initfc1_tx_done;
  bit rc_initfc2_tx_done;

  bit [7:0]  rc_fc_ph;
  bit [7:0]  rc_fc_nph;
  bit [7:0]  rc_fc_cmplh;
  bit [11:0] rc_fc_pd;
  bit [11:0] rc_fc_npd;
  bit [11:0] rc_fc_cmpld;

  bit [31:0] ep_rx_local_queue[$];
  bit [31:0] ep_tx_local_queue[$];
  Sequence_item ep_rx_pkt;

  bit [11:0] ep_rx_next_transmit_seq = 12'd2;
  bit [11:0] ep_RX_DL_SEQ;

  typedef struct {
    bit [31:0] rx_packet_q[$];
  } ep_rx_replay_pkt;
  ep_rx_replay_pkt ep_rx_replay_buffer[2048];

  int ep_rx_wr_ptr = 0;
  int ep_rx_rd_ptr = 0;
  int ep_rx_outstanding_pkt_count = 0;

  mailbox #(Sequence_item) ep_tx_pkt_mb;
  mailbox #(Sequence_item) ep_rx_pkt_mb;

  bit ep_rx_new_pkt_available;
  bit ep_tx_new_pkt_available;

  typedef enum bit [1:0] { EP_DL_INACTIVE, EP_DL_INIT_FC1, EP_DL_INIT_FC2, EP_DL_ACTIVE } ep_dl_state_e;
  ep_dl_state_e ep_dl_state;

  bit ep_FL1;
  bit ep_FL2;
  bit ep_dl_up;
  bit ep_initfc1_tx_done;
  bit ep_initfc2_tx_done;

  bit [7:0]  ep_fc_ph;
  bit [7:0]  ep_fc_nph;
  bit [7:0]  ep_fc_cmplh;
  bit [11:0] ep_fc_pd;
  bit [11:0] ep_fc_npd;
  bit [11:0] ep_fc_cmpld;

  typedef enum bit [3:0] {
    INITFC1_P   = 4'b0100,
    INITFC1_NP  = 4'b0101,
    INITFC1_CPL = 4'b0110,
    INITFC2_P   = 4'b1100,
    INITFC2_NP  = 4'b1101,
    INITFC2_CPL = 4'b1110
  } dllp_type_e;

  uvm_event link_up_env;
  uvm_event DL_up_env;
  uvm_event link_up_env_rx;
  uvm_event DL_up_env_rx;

  uvm_barrier DL_active;
  uvm_barrier DL_FC1_b;
  uvm_barrier DL_FC2_b;

  function new(string name = "PCIe_DLL_Driver", uvm_component parent = null);
    super.new(name, parent);

    rc_RX_MD_Recv = new("rc_RX_MD_Recv", this);
    rc_TX_MD_Recv = new("rc_TX_MD_Recv", this);
    ep_RX_MD_Recv = new("ep_RX_MD_Recv", this);
    ep_TX_MD_Recv = new("ep_TX_MD_Recv", this);

    rc_tx_pkt_mb = new();
    rc_rx_pkt_mb = new();
    ep_tx_pkt_mb = new();
    ep_rx_pkt_mb = new();

  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_DLL_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_DLL_Driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    DL_active = uvm_barrier_pool::get_global("dl_a");
    DL_FC1_b  = uvm_barrier_pool::get_global("dl_fc1");
    DL_FC2_b  = uvm_barrier_pool::get_global("dl_fc2");
    DL_FC1_b.set_threshold(2);
    DL_FC2_b.set_threshold(2);

    case(cfg.mode)

      RC_MODE: begin
        link_up_env = uvm_event_pool::get_global("link_up_env");
        DL_up_env   = uvm_event_pool::get_global("link_up_env");
        DL_active.set_threshold(1);

        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("PCIe_DLL_DRIVER", $sformatf("[%s] Unable To Access TX_TL_DL", tag))

        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", TX_DLL_PCS))
          `uvm_fatal("PCIe_DLL_DRIVER", $sformatf("[%s] Unable To Access TX_DLL_PCS", tag))

        `uvm_info("PCIe_DLL_Driver", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        link_up_env_rx = uvm_event_pool::get_global("link_up_env_rx");
        DL_up_env_rx   = uvm_event_pool::get_global("link_up_env_rx");
        // NOTE: reference RX_DLL_Driver sets DL_active.set_threshold(0)
        // here, overwriting RC's set_threshold(1) above if EP's
        // build_phase runs after RC's (order-dependent, preserved
        // exactly as in the original two-file design).
        DL_active.set_threshold(0);

        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("RX_DLL_DRIVER", $sformatf("[%s] Unable To Access RX_TL_DL", tag))

        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", RX_DLL_PCS))
          `uvm_fatal("RX_DLL_DRIVER", $sformatf("[%s] Unable To Access RX_DLL_PCS", tag))

        `uvm_info("PCIe_DLL_Driver", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_DLL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  function void write_TX(Sequence_item t_x);
    rc_fc_ph    = t_x.fc_ph;
    rc_fc_pd    = t_x.fc_pd;
    rc_fc_nph   = t_x.fc_nph;
    rc_fc_npd   = t_x.fc_npd;
    rc_fc_cmplh = t_x.fc_cmplh;
    rc_fc_cmpld = t_x.fc_cmpld;
    rc_tx_pkt_mb.try_put(t_x);
  endfunction

  function void write_RX(Sequence_item r_x);
    rc_rx_pkt_mb.try_put(r_x);
    `uvm_info("PCIe_DLL_DRV", $sformatf("[%s] DLL_PACKET %p", tag, r_x.dllp_packet_q), UVM_LOW)
  endfunction

  function void write_tx(Sequence_item t_x);
    ep_fc_ph    = t_x.fc_ph;
    ep_fc_pd    = t_x.fc_pd;
    ep_fc_nph   = t_x.fc_nph;
    ep_fc_npd   = t_x.fc_npd;
    ep_fc_cmplh = t_x.fc_cmplh;
    ep_fc_cmpld = t_x.fc_cmpld;
    ep_tx_pkt_mb.try_put(t_x);
  endfunction

  function void write_rx(Sequence_item r_x);
    ep_rx_pkt_mb.try_put(r_x);
    `uvm_info("RX_DLL_DRV", $sformatf("[%s] TL_PACKET %d", tag, r_x.rx_data.size()), UVM_LOW)
  endfunction

  function bit [15:0] crc16(bit [31:0] data);
    bit [15:0] crc;
    crc = 16'hABCD;
    return crc;
  endfunction

  function bit [47:0] create_dllp(
    dllp_type_e dllp_type,
    bit [2:0]   vc_id,
    bit [7:0]   header_credit,
    bit [11:0]  data_credit
  );
    bit [47:0] dllp_pkt;
    bit [15:0] dllp_crc;
    dllp_pkt[7:4] = dllp_type;
    dllp_pkt[3]   = 1'b0;
    dllp_pkt[2:0] = vc_id;
    dllp_pkt[9:8]   = 2'b00;
    dllp_pkt[17:10] = header_credit;
    dllp_pkt[19:18] = 2'b00;
    dllp_pkt[31:20] = data_credit;
    dllp_crc = crc16(dllp_pkt[31:0]);
    dllp_pkt[47:32] = dllp_crc;
    return dllp_pkt;
  endfunction

  function bit [31:0] calculate_lcrc(input bit [31:0] pkt_q[$]);
    bit [31:0] crc;
    bit data_bit;
    bit feedback;
    crc = 32'hFFFF_FFFF;
    foreach(pkt_q[i]) begin
      for(int b = 0; b < 32; b++) begin
        data_bit = pkt_q[i][b];
        feedback = crc[31] ^ data_bit;
        crc = crc << 1;
        if(feedback)
          crc ^= 32'h04C11DB7;
      end
    end
    return ~crc;
  endfunction : calculate_lcrc

task rc_send_one_dllp(bit [47:0] dllp_pkt);

    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b1;
    TX_DLL_PCS.dl_packet <= 1'b1;
    TX_DLL_PCS.dl_tx_data  <= dllp_pkt[31:0];


    wait(TX_DLL_PCS.dl_tx_ready);
    @(posedge TX_DLL_PCS.CLK);

    TX_DLL_PCS.dl_tx_data <= {
                               16'h0000,
                               dllp_pkt[47:32]
                             };


    wait(TX_DLL_PCS.dl_tx_ready);

  endtask

task rc_send_initfc1_dllps();

    bit [47:0] initfc1_p;
    bit [47:0] initfc1_np;
    bit [47:0] initfc1_cpl;

    initfc1_p = create_dllp(INITFC1_P,
                            3'b000,
                            rc_fc_ph,
                            rc_fc_pd);

    initfc1_np = create_dllp(INITFC1_NP,
                             3'b000,
                             rc_fc_nph,
                             rc_fc_npd);

    initfc1_cpl = create_dllp(INITFC1_CPL,
                              3'b000,
                              rc_fc_cmplh,
                              rc_fc_cmpld);

    rc_send_one_dllp(initfc1_p);
    rc_send_one_dllp(initfc1_np);
    rc_send_one_dllp(initfc1_cpl);

    @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;

    rc_initfc1_tx_done = 1'b1;

  endtask

task rc_send_initfc2_dllps();

    bit [47:0] initfc2_p;
    bit [47:0] initfc2_np;
    bit [47:0] initfc2_cpl;

    initfc2_p = create_dllp(INITFC2_P,
                            3'b000,
                            rc_fc_ph,
                            rc_fc_pd);

    initfc2_np = create_dllp(INITFC2_NP,
                             3'b000,
                             rc_fc_nph,
                             rc_fc_npd);

    initfc2_cpl = create_dllp(INITFC2_CPL,
                              3'b000,
                              rc_fc_cmplh,
                              rc_fc_cmpld);

    rc_send_one_dllp(initfc2_p);
    rc_send_one_dllp(initfc2_np);
    rc_send_one_dllp(initfc2_cpl);
    @(posedge TX_DLL_PCS.CLK);

    TX_DLL_PCS.dl_tx_valid <= 1'b0;
    TX_DLL_PCS.dl_packet <= 1'b0;

    rc_initfc2_tx_done = 1'b1;

  endtask

task rc_rx_recived_packet
  (
    input bit [31:0] rx_packet_recived[$]
  );

    $display("[%0t][RX_DLL_DRIVER] Collect DATA = %p",
               $time,
               rx_packet_recived);


    foreach(rx_packet_recived[i]) begin 
	     $display("[%0t][RX_DLL_DRIVER] Ready DATA = %d",
               $time,
              TX_TL_DL.tl_rx_ready);


      wait(TX_TL_DL.tl_rx_ready);

       $display("[%0t][RX_DLL_DRIVER] Ready DATA = %d",
               $time,
              TX_TL_DL.tl_rx_ready);

      @(posedge TX_TL_DL.CLK);
      

      TX_TL_DL.tl_rx_valid <= 1'b1;
          $display("[%0t][RX_DLL_DRIVER] Valid DATA = %d",
               $time,
              TX_TL_DL.tl_rx_valid);

      

      TX_TL_DL.tl_rx_data <= rx_packet_recived[i];


      $display("[%0t][RX_DLL_DRIVER] Sent DATA[%0d] = %h",
               $time,
               i,
               rx_packet_recived[i]);

    end
      @(posedge TX_TL_DL.CLK);
    

    TX_TL_DL.tl_rx_valid <= 1'b0;

  endtask

task rc_send_packet
  (
    input bit [31:0] rx_packet_send[$]
  );

    foreach(rx_packet_send[i]) begin

     @(posedge TX_DLL_PCS.CLK);
      wait(TX_DLL_PCS.dl_tx_ready);

      TX_DLL_PCS.dl_tx_valid <= 1'b1;
      TX_DLL_PCS.tl_packet <= 1'b1;

      TX_DLL_PCS.dl_tx_data <= rx_packet_send[i];


      $display("[%0t][TX_DLL_DRIVER] Sent DATA[%0d] = %h",
               $time,
               i,
               rx_packet_send[i]);

    end
     @(posedge TX_DLL_PCS.CLK);
    TX_DLL_PCS.dl_tx_valid <= 1'b0;
      TX_DLL_PCS.tl_packet <= 1'b1;

  endtask

task rc_tx_recived_packet
  (
    input bit [31:0] tx_packet_recived[$]
  );
    
    bit [31:0] TX_DLP_PACKET[$];
    bit [31:0] rx_lcrc;
    
    wait(rc_outstanding_pkt_count < 2048);

      // Assign Sequence Number

      rc_DL_SEQ = rc_next_transmit_seq;

      rc_next_transmit_seq =
    (rc_next_transmit_seq + 1) % 4096;

//       `uvm_info("SEQ_NUM",
//                 $sformatf(
//                 "Assigned Sequence Number = %0d",
//                  rc_DL_SEQ),
//                  UVM_LOW)

      // Build DLL Packet

      TX_DLP_PACKET.delete();

      // Add Sequence Number

    TX_DLP_PACKET.push_back({20'd0, rc_DL_SEQ});

      $display("@(%0t) DLL_SEQ = %0h",
               $time,
               {20'd0, rc_DL_SEQ});
    
    for(int i = 0; i < tx_packet_recived.size(); i++) begin
      TX_DLP_PACKET.push_back(tx_packet_recived[i]);
    end
 

      rx_lcrc = calculate_lcrc(TX_DLP_PACKET);

      // Append LCRC

    TX_DLP_PACKET.push_back(rx_lcrc);

//       `uvm_info("LCRC",
//                 $sformatf(
//                 "Calculated LCRC = %0h",
//                  lcrc),
//                  UVM_LOW)

      $display("@(%0t) DLL_LCRC = %0h",
               $time,
               rx_lcrc);

      // Store Into Replay Buffer

    rc_replay_buffer[rc_wr_ptr].packet_q = TX_DLP_PACKET;

//       `uvm_info("REPLAY_BUFFER",
//                 $sformatf(
//                 "Stored Packet | WR_PTR = %0d",
//                  rc_wr_ptr),
//                  UVM_LOW)

      // Update Write Pointer

    rc_wr_ptr = (rc_wr_ptr + 1) % 2048;

      // Increment Outstanding Packet Count

      rc_outstanding_pkt_count++;

      // Send Packet

      rc_send_packet(TX_DLP_PACKET);
   
  endtask

  //-----------------------------------------------------------
  // EP_MODE tasks - preserved exactly as RX_DLL_Driver.sv
  //-----------------------------------------------------------
task ep_send_one_dllp(bit [47:0] dllp_pkt);
    @(posedge RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b1;
    RX_DLL_PCS.dl_packet <= 1'b1;
    RX_DLL_PCS.dl_tx_data  <= dllp_pkt[31:0];


    wait(RX_DLL_PCS.dl_tx_ready);
    @(posedge RX_DLL_PCS.CLK);

    RX_DLL_PCS.dl_tx_data <= {
                               dllp_pkt[47:32],
                               16'h0000
                             };


    wait(RX_DLL_PCS.dl_tx_ready);

  endtask

task ep_send_initfc1_dllps();

    bit [47:0] initfc1_p;
    bit [47:0] initfc1_np;
    bit [47:0] initfc1_cpl;

    initfc1_p = create_dllp(INITFC1_P,
                            3'b000,
                            ep_fc_ph,
                            ep_fc_pd);

    initfc1_np = create_dllp(INITFC1_NP,
                             3'b000,
                             ep_fc_nph,
                             ep_fc_npd);

    initfc1_cpl = create_dllp(INITFC1_CPL,
                              3'b000,
                              ep_fc_cmplh,
                              ep_fc_cmpld);

    ep_send_one_dllp(initfc1_p);
    ep_send_one_dllp(initfc1_np);
    ep_send_one_dllp(initfc1_cpl);
    @(posedge RX_DLL_PCS.CLK);

    RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
      ep_rx_pkt_mb.get(ep_rx_pkt);
      wait(ep_rx_pkt.dllp_packet_rx_q.size >0);
       `uvm_info("RX_DLL_DRV", $sformatf("DLL_PACKET %p",ep_rx_pkt.dllp_packet_q),UVM_LOW)
           DL_FC1_b.wait_for();
        ep_FL1 = 1'b1;
`uvm_info("RX_DLL_DRV", $sformatf("RX_DL_INIT_FC_DONE"),UVM_LOW)
          ep_dl_state = EP_DL_INIT_FC2;
    ep_initfc1_tx_done = 1'b1;

  endtask

task ep_send_initfc2_dllps();

    bit [47:0] initfc2_p;
    bit [47:0] initfc2_np;
    bit [47:0] initfc2_cpl;

    initfc2_p = create_dllp(INITFC2_P,
                            3'b000,
                            ep_fc_ph,
                            ep_fc_pd);

    initfc2_np = create_dllp(INITFC2_NP,
                             3'b000,
                             ep_fc_nph,
                             ep_fc_npd);

    initfc2_cpl = create_dllp(INITFC2_CPL,
                              3'b000,
                              ep_fc_cmplh,
                              ep_fc_cmpld);

    ep_send_one_dllp(initfc2_p);
    ep_send_one_dllp(initfc2_np);
    ep_send_one_dllp(initfc2_cpl);
    @(posedge RX_DLL_PCS.CLK);
 RX_DLL_PCS.dl_tx_valid <= 1'b0;
    RX_DLL_PCS.dl_packet <= 1'b0;
           ep_FL2 = 1'b1;

          ep_dl_up = 1'b1;
	   ep_rx_pkt_mb.get(ep_rx_pkt);
      wait(ep_rx_pkt.dllp_packet_rx_q.size >0);
       `uvm_info("RX_DLL_DRV", $sformatf("DLL_PACKET %p",ep_rx_pkt.dllp_packet_q),UVM_LOW)

`uvm_info("RX_DLL_DRV", $sformatf("RX_DL_INIT_FC2_DONE"),UVM_LOW)
           DL_FC2_b.wait_for();

//`uvm_info("RX_DLL_DRV", $sformatf("RX_DL_INIT_FC_DONE"),UVM_LOW)
          ep_dl_state = EP_DL_ACTIVE;

        ep_initfc2_tx_done = 1'b1;

  endtask

task ep_rx_recived_packet
  (
    input bit [31:0] rx_packet_recived[$]
  );

    foreach(rx_packet_recived[i]) begin

      wait(RX_TL_DL.tl_rx_ready);
      
      @(posedge RX_TL_DL.CLK);
      

      RX_TL_DL.tl_rx_valid <= 1'b1;

      RX_TL_DL.tl_rx_data <= rx_packet_recived[i];


      $display("[%0t][RX_DLL_DRIVER] Sent DATA[%0d] = %h",
               $time,
               i,
               rx_packet_recived[i]);

    end
      @(posedge RX_TL_DL.CLK);

    RX_TL_DL.tl_rx_valid <= 1'b0;

  endtask

task ep_send_packet
  (
    input bit [31:0] rx_packet_send[$]
  );
  repeat(10) begin
  @(posedge  RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
end
    foreach(rx_packet_send[i]) begin

      @(posedge RX_DLL_PCS.CLK);
      wait(RX_DLL_PCS.dl_tx_ready);

      RX_DLL_PCS.dl_tx_valid <= 1'b1;
      RX_DLL_PCS.tl_packet <= 1'b1;

      RX_DLL_PCS.dl_tx_data <= rx_packet_send[i];


      $display("[%0t][RX_DLL_DRIVER] Sent DATA[%0d] = %h",
               $time,
               i,
               rx_packet_send[i]);

    end
    @(posedge  RX_DLL_PCS.CLK);
    RX_DLL_PCS.dl_tx_valid <= 1'b0;
      RX_DLL_PCS.tl_packet <= 1'b0;
      RX_DLL_PCS.dl_tx_data  <= 0;

  endtask

task ep_tx_recived_packet
  (
    input bit [31:0] tx_packet_recived[$]
  );
    
    bit [31:0] TX_DLP_PACKET[$];
    bit [31:0] rx_lcrc;
    
    wait(ep_rx_outstanding_pkt_count < 2048);

      // Assign Sequence Number

      ep_RX_DL_SEQ = ep_rx_next_transmit_seq;

      ep_rx_next_transmit_seq =
    (ep_rx_next_transmit_seq + 1) % 4096;

//       `uvm_info("SEQ_NUM",
//                 $sformatf(
//                 "Assigned Sequence Number = %0d",
//                  ep_DL_SEQ),
//                  UVM_LOW)

      // Build DLL Packet

      TX_DLP_PACKET.delete();

      // Add Sequence Number

    TX_DLP_PACKET.push_back({20'd0, ep_RX_DL_SEQ});

      $display("@(%0t) DLL_SEQ = %0h",
               $time,
               {20'd0, ep_RX_DL_SEQ});
    
    for(int i = 0; i < tx_packet_recived.size(); i++) begin
      TX_DLP_PACKET.push_back(tx_packet_recived[i]);
    end
 

      rx_lcrc = calculate_lcrc(TX_DLP_PACKET);

      // Append LCRC

    TX_DLP_PACKET.push_back(rx_lcrc);

//       `uvm_info("LCRC",
//                 $sformatf(
//                 "Calculated LCRC = %0h",
//                  lcrc),
//                  UVM_LOW)

      $display("@(%0t) DLL_LCRC = %0h",
               $time,
               rx_lcrc);

      // Store Into Replay Buffer

    ep_rx_replay_buffer[ep_rx_wr_ptr].rx_packet_q = TX_DLP_PACKET;

//       `uvm_info("REPLAY_BUFFER",
//                 $sformatf(
//                 "Stored Packet | WR_PTR = %0d",
//                  ep_wr_ptr),
//                  UVM_LOW)

      // Update Write Pointer

    ep_rx_wr_ptr = (ep_rx_wr_ptr + 1) % 2048;

      // Increment Outstanding Packet Count

      ep_rx_outstanding_pkt_count++;

      // Send Packet

      ep_send_packet(TX_DLP_PACKET);
  endtask

  //-----------------------------------------------------------
  // run_phase - dispatches to the correct role's DLCMSM
  //-----------------------------------------------------------
  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)
      RC_MODE: rc_run_phase_body();
      EP_MODE: ep_run_phase_body();
      default: `uvm_fatal("TX_DLL_Driver", $sformatf("[%s] Unknown mode", tag))
    endcase

  endtask

  task rc_run_phase_body();
   
     Sequence_item tx_pkt;

   
   TX_TL_DL.tl_rx_valid <= 0;

   TX_TL_DL.tl_rx_data <= 0;
   TX_DLL_PCS.tl_packet  <= 0;

   wait(TX_DLL_PCS.RESET);

  rc_dl_state = DL_INACTIVE;

  forever begin


//     // Global link-down handling
//     if(!TX_DLL_PCS.phy_link_up) begin

//       rc_dl_state = DL_INACTIVE;

//       rc_FL1   = 1'b0;
//       rc_FL2   = 1'b0;
//       rc_dl_up = 1'b0;

//     end
//     else begin
//       @(posedge TX_DLL_PCS.CLK);


      case(rc_dl_state)

        //////////////////////////////////////////////////////
        // DL_INACTIVE
        //////////////////////////////////////////////////////

        DL_INACTIVE:
        begin
            link_up_env.wait_trigger();

          //if(TX_DLL_PCS.phy_link_up)
            rc_dl_state = DL_INIT_FC1;
          

        end

        //////////////////////////////////////////////////////
        // DL_INIT_FC1
        //////////////////////////////////////////////////////

        DL_INIT_FC1:
        begin

          rc_send_initfc1_dllps();
           
          rc_FL1 = 1'b1;
      rc_rx_pkt_mb.get(rc_rx_pkt);
`uvm_info("TX_DLL_DRV", $sformatf("DLL_PACKET_q %p",rc_rx_pkt.dllp_packet_q),UVM_LOW)

      wait(rc_rx_pkt.dllp_packet_q.size >0);
       `uvm_info("TX_DLL_DRV", $sformatf("DLL_PACKET_q %p",rc_rx_pkt.dllp_packet_q),UVM_LOW)

           DL_FC1_b.wait_for();
          rc_dl_state = DL_INIT_FC2;


        end

        //////////////////////////////////////////////////////
        // DL_INIT_FC2
        //////////////////////////////////////////////////////

        DL_INIT_FC2:
        begin

          rc_send_initfc2_dllps();

          rc_FL2 = 1'b1;

          rc_dl_up = 1'b1;
      rc_rx_pkt_mb.get(rc_rx_pkt);
      wait(rc_rx_pkt.dllp_packet_q.size >0);
       `uvm_info("TX_DLL_DRV", $sformatf("DLL_PACKET %p",rc_rx_pkt.dllp_packet_q),UVM_LOW)

           DL_FC2_b.wait_for();

          rc_dl_state = DL_ACTIVE;


        end

        //////////////////////////////////////////////////////
        // DL_ACTIVE
        //////////////////////////////////////////////////////

        
   DL_ACTIVE:
begin
       `uvm_info("PCIe_DLL_DRV", $sformatf("DLL_PACKET_ACTIVE TRIGGERED"),UVM_LOW)
	 DL_up_env.trigger();

  fork

    forever begin

      rc_rx_pkt_mb.get(rc_rx_pkt);

      rc_rx_local_queue = rc_rx_pkt.rx_data_t;
         $display("[%0t][RX_DLL_DRIVER] Collect DATA = %p",
               $time,
               rc_rx_local_queue);


      rc_rx_recived_packet(rc_rx_local_queue);

    end

    forever begin
      Sequence_item tx_pkt;

      rc_tx_pkt_mb.get(tx_pkt);

      rc_tx_local_queue = tx_pkt.tx_data_t;

      rc_tx_recived_packet(rc_tx_local_queue);

    end

  join_none

  wait(0);

end

      endcase

    end

//   end
  endtask

  task ep_run_phase_body();
   
   RX_TL_DL.tl_rx_valid <= 0;

   RX_TL_DL.tl_rx_data <= 0;

      RX_DLL_PCS.tl_packet <= 1'b0;
   @(posedge RX_DLL_PCS.CLK);

   wait(RX_DLL_PCS.RESET);

  ep_dl_state = EP_DL_INACTIVE;

  forever begin

  //  @(posedge RX_DLL_PCS.CLK);

//     // Global link-down handling
//     if(!RX_DLL_PCS.phy_link_up) begin

//       ep_dl_state = EP_DL_INACTIVE;

//       ep_FL1   = 1'b0;
//       ep_FL2   = 1'b0;
//       ep_dl_up = 1'b0;

//     end
//     else begin

      case(ep_dl_state)

        //////////////////////////////////////////////////////
        // DL_INACTIVE
        //////////////////////////////////////////////////////

        EP_DL_INACTIVE:
        begin
             link_up_env_rx.wait_trigger();
 
        //  if(RX_DLL_PCS.phy_link_up)
            ep_dl_state = EP_DL_INIT_FC1;

        end

        //////////////////////////////////////////////////////
        // DL_INIT_FC1
        //////////////////////////////////////////////////////

        EP_DL_INIT_FC1:
        begin

          ep_send_initfc1_dllps();

         
        end

        //////////////////////////////////////////////////////
        // DL_INIT_FC2
        //////////////////////////////////////////////////////

        EP_DL_INIT_FC2:
        begin

          ep_send_initfc2_dllps();


   
 
        end

        //////////////////////////////////////////////////////
        // DL_ACTIVE
        //////////////////////////////////////////////////////

        EP_DL_ACTIVE:

       begin
`uvm_info("RX_DLL_DRV", $sformatf("RX_Triggered"),UVM_LOW)
        DL_up_env_rx.trigger();
  fork
     $display("[%0t] Before get", $time);

    forever begin

     $display("[%0t] Before get", $time);
ep_rx_pkt_mb.get(ep_rx_pkt);
$display("[%0t] After get", $time);   
    //wait(ep_rx_pkt.rx_data.size()>0);
`uvm_info("RX_DLL_DRV", $sformatf("TL_PACKET %d",ep_rx_pkt.rx_data.size()),UVM_LOW)
      
      ep_rx_local_queue = ep_rx_pkt.rx_data;

`uvm_info("RX_DLL_DRV", $sformatf("TL_PACKET %d",ep_rx_local_queue.size()),UVM_LOW)
      ep_rx_recived_packet(ep_rx_local_queue);
            $display("-------------------------------------");


    end

    forever begin
      Sequence_item tx_pkt;

      ep_tx_pkt_mb.get(tx_pkt);

      ep_tx_local_queue = tx_pkt.tx_data;

      ep_tx_recived_packet(ep_tx_local_queue);

    end

  join_none

  wait(0);

end

      endcase

    end
  endtask

endclass : PCIe_DLL_Driver
