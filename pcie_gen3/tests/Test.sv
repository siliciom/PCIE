class pcie_base_test extends uvm_test;

  `uvm_component_utils(pcie_base_test)


  Env_Top RC_Env[];
  Env_Top EP_Env[];
  env_cfg rc_cfg[];
  env_cfg ep_cfg[];

  TL_Scoreboard  TL_Scb;
  DL_Scoreboard  DL_Scb;

  Scoreboard_Top Top_Scb;
  PCIe_MAC_Scoreboard mac_scb;
   PCIe_TL_Coverage pcie_cov;

 
  int unsigned num_rc = `PCIE_NUM_RC;
  int unsigned num_ep = `PCIE_NUM_EP;


  // Global link-up events (shared across all env instances)
  uvm_event DL_up_env;
  uvm_event DL_up_env_rx;

  
  //---------------------------------------------------------------
  // Enumeration state - populated by do_enumeration(), read by
  // every derived test class.
  //---------------------------------------------------------------
  uvm_tlm_analysis_fifo #(Sequence_item) cpl_fifo;

  bit        device_present;
  bit [15:0] vendor_id, device_id;
  bit [7:0]  header_type;

  bit [31:0] bar_orig      [6];   // original (pre-probe) readback
  bit [31:0] bar_sizeback  [6];   // readback after writing all-1s
  bit        bar_is_io     [6];
  bit        bar_is_64     [6];
  bit        bar_is_upper  [6];   // skip: this is the high dw of a 64-bit pair
  bit        bar_valid     [6];   // non-zero size -> BAR actually implemented
  bit [63:0] bar_base      [6];   // final assigned base (post CFG_WR0)
  fmt_e      bar_wr_fmt    [6];
  fmt_e      bar_rd_fmt    [6];

  // Base addresses this bench programs into each implemented BAR.
  // Must stay aligned to that BAR's size (checked against
  // bar_sizeback's mask at enumeration time - see do_enumeration()).
  bit [31:0] BASE_BAR0 = 32'h1000_0000;  // 32-bit mem
  bit [31:0] BASE_BAR1 = 32'h2000_0000;  // 64-bit mem pair, low dw
  bit [31:0] BASE_BAR2 = 32'h0000_0000;  // 64-bit mem pair, high dw
  bit [31:0] BASE_BAR3 = 32'h0000_1000;  // I/O


  function new(string name = "pcie_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string rc_name, ep_name;
    super.build_phase(phase);

    cpl_fifo = new("cpl_fifo", this);

    TL_Scb  = TL_Scoreboard::type_id::create("TL_Scb",  this);
    Top_Scb = Scoreboard_Top::type_id::create("Top_Scb", this);
 mac_scb = PCIe_MAC_Scoreboard::type_id::create("mac_scb",this);
   DL_Scb  = DL_Scoreboard::type_id::create("DL_Scb", this);
  pcie_cov  = PCIe_TL_Coverage::type_id::create("pcie_cov", this);

    RC_Env = new[num_rc];
    rc_cfg = new[num_rc];
    EP_Env = new[num_ep];
    ep_cfg = new[num_ep];

    for(int unsigned i = 0; i < num_rc; i++) begin
      rc_name    = $sformatf("RC_Env_%0d", i);
      rc_cfg[i]  = env_cfg::type_id::create($sformatf("rc_cfg_%0d", i));
      rc_cfg[i].mode = RC_MODE;
      rc_cfg[i].gen  = `PCIE_NUM_RC_GEN;   // set advertised PCIe generation
      rc_cfg[i].check_gen();
     // rc_cfg[i].check_lanes();
      uvm_config_db#(env_cfg)::set(this, {rc_name, ".*"}, "env_cfg", rc_cfg[i]);
      uvm_config_db#(env_cfg)::set(this,  rc_name,        "env_cfg", rc_cfg[i]);
      uvm_config_db#(TL_Scoreboard)::set(this, rc_name, "TL_Scb", TL_Scb);
       uvm_config_db#(PCIe_MAC_Scoreboard)::set(this, rc_name, "mac_scb", mac_scb);
 uvm_config_db#(DL_Scoreboard)::set(this, rc_name, "DL_Scb", DL_Scb);
  uvm_config_db#(PCIe_TL_Coverage)::set(this, rc_name, "pcie_cov", pcie_cov);


      RC_Env[i]  = Env_Top::type_id::create(rc_name, this);
    end

    for(int unsigned i = 0; i < num_ep; i++) begin
      ep_name    = $sformatf("EP_Env_%0d", i);
      ep_cfg[i]  = env_cfg::type_id::create($sformatf("ep_cfg_%0d", i));
      ep_cfg[i].mode = EP_MODE;
      ep_cfg[i].gen  = `PCIE_NUM_EP_GEN;   // set advertised PCIe generation
      ep_cfg[i].check_gen();
      //ep_cfg[i].check_lanes();
      uvm_config_db#(env_cfg)::set(this, {ep_name, ".*"}, "env_cfg", ep_cfg[i]);
      uvm_config_db#(env_cfg)::set(this,  ep_name,        "env_cfg", ep_cfg[i]);
      uvm_config_db#(TL_Scoreboard)::set(this, ep_name, "TL_Scb", TL_Scb);
       uvm_config_db#(PCIe_MAC_Scoreboard)::set(this, ep_name, "mac_scb", mac_scb);
       uvm_config_db#(DL_Scoreboard)::set(this, ep_name, "DL_Scb", DL_Scb);
       uvm_config_db#(PCIe_TL_Coverage)::set(this, ep_name, "pcie_cov", pcie_cov);



      EP_Env[i]  = Env_Top::type_id::create(ep_name, this);
    end

    DL_up_env    = uvm_event_pool::get_global("DL_active_env");
    DL_up_env_rx = uvm_event_pool::get_global("DL_active_env_rx");

  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    RC_Env[0].PCIe_TL_Agnt.TX_TL_Mon.TX_TL_Send.connect(cpl_fifo.analysis_export);

    TL_Scb.t_port.connect(Top_Scb.t_imp);
    TL_Scb.r_port.connect(Top_Scb.r_imp);
  endfunction : connect_phase

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    uvm_top.print_topology;
  endfunction

  //-------------------------------------------------------------
  // cfg_read / cfg_write: single-register CFG0 access, matched to
  // its own completion by tag.
  //-------------------------------------------------------------

  task cfg_read(bit [3:0] ext_reg, bit [5:0] reg_num, output bit [31:0] data);
    Cfg_Rd0_Reg_Seq rd_seq;
    Sequence_item   cpl;
    bit             found;

    rd_seq = Cfg_Rd0_Reg_Seq::type_id::create("rd_seq");
    rd_seq.p_ext_reg = ext_reg;
    rd_seq.p_reg     = reg_num;
    rd_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    found = 0;
    while(!found) begin
      `uvm_info("TEST","Waiting for completion...",UVM_LOW)
       cpl_fifo.get(cpl);
      `uvm_info("TEST","Completion received",UVM_LOW)
      `uvm_info("TEST", $sformatf("REQ TAG = %0d  CPL TAG = %0d  CPL TYPE = %s", rd_seq.req.tag, cpl.tag, cpl.e_type.name()), UVM_LOW)
      // NOTE: cpl_fifo carries BOTH the echoed outgoing request (from
      // rc_sending_tx_request) and the real completion (from
      // rc_collecting_rx_completion) - both tagged the same, since it's
      // the same transaction. Must qualify on e_type too, or this matches
      // the request's own echo instead of waiting for the real completion,
      // letting the next config packet fire before the DUT has completed
      // the first one.
      if((cpl.tag == rd_seq.req.tag) && (cpl.e_type == CPL_DATA)) begin
        data  = cpl.payload[0];
        found = 1;
      end
    end
  endtask : cfg_read

  task cfg_write(bit [3:0] ext_reg, bit [5:0] reg_num, bit [31:0] data, bit [3:0] be = 4'hF);
    Cfg_Wr0_Reg_Seq wr_seq;
    Sequence_item   cpl;
    bit             found;

    wr_seq = Cfg_Wr0_Reg_Seq::type_id::create("wr_seq");
    wr_seq.p_ext_reg = ext_reg;
    wr_seq.p_reg     = reg_num;
    wr_seq.p_data    = data;
    wr_seq.p_be      = be;
    wr_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    found = 0;
    while(!found) begin
      cpl_fifo.get(cpl);
      // Same reason as cfg_read: must qualify on e_type == CPL, not just
      // tag, or this matches the echoed outgoing request instead of the
      // real completion.
      if((cpl.tag == wr_seq.req.tag) && (cpl.e_type == CPL)) found = 1;
    end
  endtask : cfg_write

  //-------------------------------------------------------------
  // Full enumeration flow - see the class-header comment above for
  // the step-by-step description.
  //-------------------------------------------------------------
  
 //-------------------------------------------------------------
  // Full enumeration flow - see the class-header comment above for
  // the step-by-step description.
  //-------------------------------------------------------------
  task do_enumeration();
    bit [31:0] data;
    bit [31:0] base_pick [6];

    base_pick[0] = BASE_BAR0;
    base_pick[1] = BASE_BAR1;
    base_pick[2] = BASE_BAR2;
    base_pick[3] = BASE_BAR3;
    base_pick[4] = 32'h0;
    base_pick[5] = 32'h0;

    //-----------------------------------------------------------
    // 1) Vendor/Device ID
    //-----------------------------------------------------------
`uvm_info("ENUM", $sformatf("[%0t] Reading Vendor ID", $time), UVM_LOW)
    
    cfg_read(4'h0, 6'h0, data);
    `uvm_info("ENUM", $sformatf("[%0t] Vendor ID complete", $time), UVM_LOW)
    vendor_id      = data[15:0];
    device_id      = data[31:16];
    device_present = (vendor_id != 16'hFFFF);

    `uvm_info("ENUM", $sformatf("Reg0 VID/DID = %08h (vendor=%04h device=%04h) present=%0b",
                                  data, vendor_id, device_id, device_present), UVM_LOW)

    if(!device_present) begin
      `uvm_fatal("ENUM", "Vendor ID read back as FFFF - no device present, aborting enumeration")
      return;
    end

    //-----------------------------------------------------------
    // 2) Header Type (reg3, bits[23:16])
    //-----------------------------------------------------------
    `uvm_info("ENUM", $sformatf("[%0t] Reading Header Type", $time), UVM_LOW)
    cfg_read(4'h0, 6'h3, data);
    `uvm_info("ENUM", $sformatf("[%0t] Header Type complete", $time), UVM_LOW)
    header_type = data[23:16];

    `uvm_info("ENUM", $sformatf("Reg3 = %08h -> header_type=%02h", data, header_type), UVM_LOW)

    if(header_type != 8'h00) begin
      `uvm_fatal("ENUM", $sformatf("Header type %02h is not a normal (type 0) endpoint - this bench only models type 0", header_type))
      return;
    end

    //-----------------------------------------------------------
    // 3) Read all 6 BARs as-is, before touching anything
    //-----------------------------------------------------------
    for(int bar_num = 0; bar_num < 6; bar_num++) begin
      cfg_read(4'h0, 6'h4 + bar_num[5:0], bar_orig[bar_num]);
      `uvm_info("ENUM", $sformatf("BAR%0d original = %08h", bar_num, bar_orig[bar_num]), UVM_LOW)
    end

    //-----------------------------------------------------------
    // 4) Size each BAR: write all-1s, read back, decode. A 64-bit
    //    memory BAR's upper dw is marked and skipped here - it has
    //    no hardwired type bits of its own to decode.
    //-----------------------------------------------------------
    for(int bar_num = 0; bar_num < 6; bar_num++) begin
      if(bar_is_upper[bar_num]) continue;

      cfg_write(4'h0, 6'h4 + bar_num[5:0], 32'hFFFF_FFFF);
      cfg_read (4'h0, 6'h4 + bar_num[5:0], bar_sizeback[bar_num]);

      bar_is_io[bar_num] = bar_sizeback[bar_num][0];

      if(bar_is_io[bar_num]) begin
        bar_is_64[bar_num] = 0;
        bar_valid[bar_num] = (bar_sizeback[bar_num] & 32'hFFFF_FFFC) != 0;
      end else begin
        bar_is_64[bar_num] = (bar_sizeback[bar_num][2:1] == 2'b10);
        bar_valid[bar_num] = (bar_sizeback[bar_num] & 32'hFFFF_FFF0) != 0;
        if(bar_is_64[bar_num] && (bar_num < 5)) begin
          bar_is_upper[bar_num + 1] = 1;   // next BAR is this one's high dw
        end
    end

      bar_wr_fmt[bar_num] = bar_is_64[bar_num] ? FMT_4DW_DATA    : FMT_3DW_DATA;
      bar_rd_fmt[bar_num] = bar_is_64[bar_num] ? FMT_4DW_NO_DATA : FMT_3DW_NO_DATA;

      `uvm_info("ENUM",
        $sformatf("BAR%0d sizeback=%08h -> is_io=%0b is_64=%0b valid=%0b",
                   bar_num, bar_sizeback[bar_num], bar_is_io[bar_num],
                   bar_is_64[bar_num], bar_valid[bar_num]), UVM_LOW)
    end

    //---------------------------------

    //---------------------------------
     //-----------------------------------------------------------
    // 5) Command register: Memory Space Enable(bit1) + IO Space
    //    Enable(bit0) + Bus Master Enable(bit2).
    //-----------------------------------------------------------
    cfg_write(4'h0, 6'h1, 32'h0000_0007);
    `uvm_info("ENUM", "Command register: Mem+IO+BusMaster enabled", UVM_LOW)

    //-----------------------------------------------------------
    // 6) Assign a real base address to each valid, non-upper BAR.
    //-----------------------------------------------------------
    for(int bar_num = 0; bar_num < 6; bar_num++) begin
      if(bar_is_upper[bar_num]) begin
        cfg_write(4'h0, 6'h4 + bar_num[5:0], base_pick[bar_num]);
        continue;
      end
      if(!bar_valid[bar_num]) continue;

      cfg_write(4'h0, 6'h4 + bar_num[5:0], base_pick[bar_num]);

      if(bar_is_64[bar_num] && (bar_num < 5)) begin
        bar_base[bar_num] = {base_pick[bar_num + 1], base_pick[bar_num]};
      end else begin
        bar_base[bar_num] = {32'h0, base_pick[bar_num]};
      end

      `uvm_info("ENUM", $sformatf("BAR%0d base assigned = %016h (fmt wr=%s rd=%s)",
                 bar_num, bar_base[bar_num], bar_wr_fmt[bar_num].name(), bar_rd_fmt[bar_num].name()), UVM_LOW)
    end

  endtask : do_enumeration

  //-------------------------------------------------------------
  // run_phase: link-up, then the FULL enumeration above, then
  // drop. Every derived test's own run_phase calls super.run_phase()
  // first so this always finishes before that derived test issues a
  // single Mem/IO transaction.
  //-------------------------------------------------------------
  //
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_ptrigger();
    `uvm_info("TEST", "TRIGGERED DONE", UVM_LOW)
   
  
      DL_up_env.wait_ptrigger();
    `uvm_info("TEST", "TRIGGERED DONE", UVM_LOW)

      do_enumeration();

    phase.drop_objection(this);
  endtask : run_phase


endclass : pcie_base_test



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    3DW_SINGLE_MEMORY_WRITE_:READ_TEST_CASE   /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// BAR0: 32-bit memory -> naturally 3DW.

class Single_Mem_Wr_Rd_3DW_test extends pcie_base_test;

 `uvm_component_utils(Single_Mem_Wr_Rd_3DW_test)

  Single_Mem_Wr_Rd_3DW Mem_Seq_tx;

  function new(string name = "Single_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);      // link-up + full enumeration
    phase.raise_objection(this);

    Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
    Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
    Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
    Mem_Seq_tx.p_addr   = bar_base[0] + 64'h10;
    Mem_Seq_tx.p_length = 100;
    `uvm_info("TEST",
$sformatf("BAR0 Base=%h WR_FMT=%s RD_FMT=%s",
           Mem_Seq_tx.p_addr,
           Mem_Seq_tx.p_wr_fmt.name(),
           Mem_Seq_tx.p_rd_fmt.name()),
UVM_NONE)

    Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
   
    #2000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_Mem_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    4DW_SINGLE_MEMORY_WRITE_READ_TEST_CASE   /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// BAR1/BAR2 pair: 64-bit memory -> 4DW.

class Single_Mem_Wr_Rd_4DW_test extends pcie_base_test;

  `uvm_component_utils(Single_Mem_Wr_Rd_4DW_test)

  Single_Mem_Wr_Rd_4DW Seq_tx;

  function new(string name = "Single_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    Seq_tx = Single_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
    Seq_tx.p_wr_fmt = bar_wr_fmt[1];
    Seq_tx.p_rd_fmt = bar_rd_fmt[1];
    Seq_tx.p_addr   = bar_base[1] + 64'h20;
    Seq_tx.p_length = 40;
    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    #200000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_Mem_Wr_Rd_4DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    3DW_MULTIPLE_MEMORY_WRITE_READ_TEST_CASE   ///////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Multiple_Mem_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Multiple_Mem_Wr_Rd_3DW_test)

  Multiple_Mem_Wr_Rd_3DW Seq_tx;
  bit [5:0]  offset;
  bit [63:0] curr_addr;

  function new(string name = "Multiple_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[0] + offset;
    `uvm_info("TEST", $sformatf("curr_addr1 = %0h",curr_addr), UVM_LOW)
      
    repeat(20) begin
RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en = 1'b0;

    Seq_tx = Multiple_Mem_Wr_Rd_3DW::type_id::create("Seq_tx");
   
    Seq_tx.p_wr_fmt = bar_wr_fmt[0];
    Seq_tx.p_rd_fmt = bar_rd_fmt[0];
    Seq_tx.p_addr   = curr_addr;
    Seq_tx.p_length = 10;
    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    curr_addr += Seq_tx.p_length * 4;
    `uvm_info("TEST", $sformatf("curr_addr = %0h",curr_addr), UVM_LOW)
   
    end

    #10000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_Mem_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    4DW_MULTIPLE_MEMORY_WRITE_READ_TEST_CASE   ///////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Multiple_Mem_Wr_Rd_4DW_test extends pcie_base_test;

  `uvm_component_utils(Multiple_Mem_Wr_Rd_4DW_test)

  Multiple_Mem_Wr_Rd_4DW Seq_tx;

  bit [5:0]  offset;
  bit [63:0] curr_addr;

  function new(string name = "Multiple_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[1] + offset;

    repeat(25) begin
	    
      Seq_tx = Multiple_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
      Seq_tx.p_wr_fmt = bar_wr_fmt[1];
      Seq_tx.p_rd_fmt = bar_rd_fmt[1];
      Seq_tx.p_addr   = curr_addr;
      Seq_tx.p_length = 10;
      Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

      curr_addr += Seq_tx.p_length * 4;

    end

    #20000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_Mem_Wr_Rd_4DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    3DW_BACK_2_BACK_MEMORY_WRITE_READ_TEST_CASE   ////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Two distinct offsets inside the BAR0 window, back to back.

class B2B_Mem_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(B2B_Mem_Wr_Rd_3DW_test)

  B2B_Mem_Wr_Rd_3DW Seq_tx1, Seq_tx2;
  bit [5:0]  offset;
  bit [63:0] curr_addr;


  function new(string name = "B2B_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[0] + offset;

    Seq_tx1 = B2B_Mem_Wr_Rd_3DW::type_id::create("Seq_tx1");
    Seq_tx1.p_wr_fmt = bar_wr_fmt[0];
    Seq_tx1.p_rd_fmt = bar_rd_fmt[0];
    Seq_tx1.p_addr   = curr_addr;
    Seq_tx1.p_length = 70;
    curr_addr += Seq_tx1.p_length * 4;

    Seq_tx2 = B2B_Mem_Wr_Rd_3DW::type_id::create("Seq_tx2");
    Seq_tx2.p_wr_fmt = bar_wr_fmt[0];
    Seq_tx2.p_rd_fmt = bar_rd_fmt[0];
    Seq_tx2.p_addr   = curr_addr;
    Seq_tx2.p_length = 70;
    curr_addr += Seq_tx2.p_length * 4;

    fork
      Seq_tx1.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
      Seq_tx2.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
    join

    #90000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : B2B_Mem_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    4DW_BACK_TO_BACK_MEMORY_WRITE_READ_TEST_CASE   ///////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class B2B_Mem_Wr_Rd_4DW_test extends pcie_base_test;

  `uvm_component_utils(B2B_Mem_Wr_Rd_4DW_test)

  B2B_Mem_Wr_Rd_4DW Seq_tx1, Seq_tx2;

  function new(string name = "B2B_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    Seq_tx1 = B2B_Mem_Wr_Rd_4DW::type_id::create("Seq_tx1");
    Seq_tx1.p_wr_fmt = bar_wr_fmt[1];
    Seq_tx1.p_rd_fmt = bar_rd_fmt[1];
    Seq_tx1.p_addr   = bar_base[1] + 64'h10;
    Seq_tx1.p_length = 3;

    Seq_tx2 = B2B_Mem_Wr_Rd_4DW::type_id::create("Seq_tx2");
    Seq_tx2.p_wr_fmt = bar_wr_fmt[1];
    Seq_tx2.p_rd_fmt = bar_rd_fmt[1];
    Seq_tx2.p_addr   = bar_base[1] + 64'h20;
    Seq_tx2.p_length = 3;

    fork
      Seq_tx1.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
      Seq_tx2.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
    join

    #90000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : B2B_Mem_Wr_Rd_4DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    3DW_SINGLE_IO_WRITE_READ_TEST_CASE   /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// BAR3: I/O -> always 3DW.

class Single_IO_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Single_IO_Wr_Rd_3DW_test)

  Single_IO_Wr_Rd_3DW Seq_tx;

  function new(string name = "Single_IO_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    Seq_tx = Single_IO_Wr_Rd_3DW::type_id::create("Seq_tx");
    Seq_tx.p_wr_fmt = bar_wr_fmt[3];
    Seq_tx.p_rd_fmt = bar_rd_fmt[3];
    Seq_tx.p_addr = bar_base[3][31:0] + 32'h10;
    Seq_tx.p_length = 1;

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    #90000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_IO_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    3DW_MULTIPLE_IO_WRITE_READ_TEST_CASE   ///////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Multiple_IO_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Multiple_IO_Wr_Rd_3DW_test)

  Multiple_IO_Wr_Rd_3DW Seq_tx;
  bit [5:0]  offset;
  bit [63:0] curr_addr;

  function new(string name = "Multiple_IO_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[3] + offset;

    repeat(30) begin

RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en = 1'b0;
      Seq_tx = Multiple_IO_Wr_Rd_3DW::type_id::create("Seq_tx");
      Seq_tx.p_wr_fmt = bar_wr_fmt[3];
      Seq_tx.p_rd_fmt = bar_rd_fmt[3];
      Seq_tx.p_addr = curr_addr;
      Seq_tx.p_length =
      Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

      curr_addr += Seq_tx.p_length * 4;

    end

    #360000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_IO_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    3DW_BACK_2_BACK_IO_WRITE_READ_TEST_CASE   ////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class B2B_IO_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(B2B_IO_Wr_Rd_3DW_test)

  B2B_IO_Wr_Rd_3DW Seq_tx1, Seq_tx2;
  bit [5:0]  offset;
  bit [63:0] curr_addr;


  function new(string name = "B2B_IO_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[3] + offset;

    Seq_tx1 = B2B_IO_Wr_Rd_3DW::type_id::create("Seq_tx1");
    Seq_tx1.p_wr_fmt = bar_wr_fmt[3];
    Seq_tx1.p_rd_fmt = bar_rd_fmt[3];
    Seq_tx1.p_addr = curr_addr;
    Seq_tx1.p_length = 1;
    curr_addr += Seq_tx1.p_length * 4;

    Seq_tx2 = B2B_IO_Wr_Rd_3DW::type_id::create("Seq_tx2");
    Seq_tx2.p_wr_fmt = bar_wr_fmt[3];
    Seq_tx2.p_rd_fmt = bar_rd_fmt[3];
    Seq_tx2.p_addr = curr_addr;
    Seq_tx2.p_length = 1;
    curr_addr += Seq_tx2.p_length * 4;

    fork
      Seq_tx1.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
      Seq_tx2.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
    join

    #20000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : B2B_IO_Wr_Rd_3DW_test



class Single_Mem_Wr_Rd_3DW_Max_payload_test extends pcie_base_test;

 `uvm_component_utils(Single_Mem_Wr_Rd_3DW_Max_payload_test)

  Single_Mem_Wr_Rd_3DW Mem_Seq_tx;

  function new(string name = "Single_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);      // link-up + full enumeration
    phase.raise_objection(this);

    Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en = 1'b0;
    Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
    Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
    Mem_Seq_tx.p_addr   = bar_base[0] + 64'h10;
    Mem_Seq_tx.p_length = 0;
    `uvm_info("TEST",
$sformatf("BAR0 Base=%h WR_FMT=%s RD_FMT=%s",
           Mem_Seq_tx.p_addr,
           Mem_Seq_tx.p_wr_fmt.name(),
           Mem_Seq_tx.p_rd_fmt.name()),
UVM_NONE)

    Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
   
    #2000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_Mem_Wr_Rd_3DW_Max_payload_test




class Single_Mem_Wr_Rd_4DW_Max_payload_test extends pcie_base_test;

  `uvm_component_utils(Single_Mem_Wr_Rd_4DW_Max_payload_test)

  Single_Mem_Wr_Rd_4DW Seq_tx;

  function new(string name = "Single_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);
RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en = 1'b0;
    Seq_tx = Single_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
    Seq_tx.p_wr_fmt = bar_wr_fmt[1];
    Seq_tx.p_rd_fmt = bar_rd_fmt[1];
    Seq_tx.p_addr   = bar_base[1] + 64'h20;
    Seq_tx.p_length = 0;
    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    #2000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_Mem_Wr_Rd_4DW_Max_payload_test



class Multiple_Mem_Wr_Rd_3DW_rand_length_test extends pcie_base_test;

  `uvm_component_utils(Multiple_Mem_Wr_Rd_3DW_rand_length_test)

  Multiple_Mem_Wr_Rd_3DW Seq_tx;
  bit [5:0]  offset;
  bit [63:0] curr_addr;

  function new(string name = "Multiple_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[0] + offset;
    `uvm_info("TEST", $sformatf("curr_addr1 = %0h",curr_addr), UVM_LOW)
      
    repeat(20) begin

    Seq_tx = Multiple_Mem_Wr_Rd_3DW::type_id::create("Seq_tx");
RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en = 1'b0;
   
    Seq_tx.p_wr_fmt = bar_wr_fmt[0];
    Seq_tx.p_rd_fmt = bar_rd_fmt[0];
    Seq_tx.p_addr   = curr_addr;
    assert(std::randomize(Seq_tx.p_length) with {
    Seq_tx.p_length inside {[0:500]};});

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    curr_addr += Seq_tx.p_length * 4;
    `uvm_info("TEST", $sformatf("curr_addr = %0h",curr_addr), UVM_LOW)
   
    end

    #10000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_Mem_Wr_Rd_3DW_rand_length_test




class Multiple_Mem_Wr_Rd_4DW_rand_length_test extends pcie_base_test;

  `uvm_component_utils(Multiple_Mem_Wr_Rd_4DW_rand_length_test)

  Multiple_Mem_Wr_Rd_4DW Seq_tx;

  bit [5:0]  offset;
  bit [63:0] curr_addr;

  function new(string name = "Multiple_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    assert(std::randomize(offset) with {
    offset inside {[10:50]};
    offset % 4 == 0;     
    });

    curr_addr = bar_base[1] + offset;

    repeat(20) begin
	    
      Seq_tx = Multiple_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en = 1'b0;
      Seq_tx.p_wr_fmt = bar_wr_fmt[1];
      Seq_tx.p_rd_fmt = bar_rd_fmt[1];
      Seq_tx.p_addr   = curr_addr;
      assert(std::randomize(Seq_tx.p_length) with {
      Seq_tx.p_length inside {[0:1024]};});
      
      Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

      curr_addr += Seq_tx.p_length * 4;

    end

    #2000000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_Mem_Wr_Rd_4DW_rand_length_test


//=========================================================
// pcie_ral_test.sv
// Starts pcie_cfg_full_ral_seq (from pcie_ral_seq_lib.sv)
// against the RAL model built inside Env_Top.
//=========================================================
/*
class pcie_ral_test extends uvm_test;

  // If you already have a common base test (e.g. pcie_base_test) that
  // builds Env_Top + sets env_cfg + TL_Scb, extend THAT instead of
  // uvm_test, and delete the env_cfg/Env_Top creation lines below —
  // just keep the run_phase() task with the sequence start() call.
  `uvm_component_utils(pcie_ral_test)


  Env_Top Env_Top_h;
  env_cfg cfg;

  function new(string name = "pcie_ral_test", uvm_component parent = null);
    super.new(name, parent);

  endfunction

  function void build_phase(uvm_phase phase);
	   TL_Scoreboard TL_Scb;
  super.build_phase(phase);
       cfg = env_cfg::type_id::create("cfg");

    cfg.mode = EP_MODE;   // RAL/APB agent only builds in EP_MODE, per Env_Top
    uvm_config_db#(env_cfg)::set(this, "*", "env_cfg", cfg);
 TL_Scb = TL_Scoreboard::type_id::create("TL_Scb", this);
  uvm_config_db#(TL_Scoreboard)::set(this, "*", "TL_Scb", TL_Scb);

    

   Env_Top_h = Env_Top::type_id::create("EP_Env_0", this);  // renamed from "Env_Top_h"  
endfunction

  task run_phase(uvm_phase phase);

   pcie_cfg_full_ral_seq seq;
  // pcie_type1_cfg_full_ral_seq seq1;
   phase.raise_objection(this);
   seq = pcie_cfg_full_ral_seq::type_id::create("seq");  
   seq.model = Env_Top_h.Ral; //this tells the generic RAL sequence (seq) which register block to operate on — pointing it at your actual PCIe config-space register model (Env_Top_h.Ral) instead of leaving it with no registers to read/write at all.
    seq.start(Env_Top_h.Ral.default_map.get_sequencer());


  //  seq1 = pcie_type1_cfg_full_ral_seq::type_id::create("seq1"); 
  //  seq1.regmodel = Env_Top_h.Ral_type1;
 //   seq1.start(Env_Top_h.Ral_type1.default_map.get_sequencer());

    phase.drop_objection(this);

  endtask

endclass : pcie_ral_test
*/
class LTSSM_Disabled_test extends pcie_base_test;

  `uvm_component_utils(LTSSM_Disabled_test)

  function new(string name = "LTSSM_Disabled_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    time disabled_wait;

    phase.raise_objection(this);

    `uvm_info("TEST",
       "Setting Link Disable on RC and EP -> directing LTSSM to DISABLED out of Configuration.Linkwidth.Start",
       UVM_LOW)
    rc_cfg[0].link_ctrl_disable_link = 1'b1;
    ep_cfg[0].link_ctrl_disable_link = 1'b1;

    //-----------------------------------------------------------
    // Worst-case time for either side to reach
    // Configuration.Linkwidth.Start on its own timeouts, plus
    // margin for the Disabled state's own TS1 burst + Electrical
    // Idle settle. (Fast-path/barrier-synced bring-up is normally
    // far quicker than this, so this bound is generous on purpose.)
    //-----------------------------------------------------------
    disabled_wait = rc_cfg[0].detect_quiet_timeout
                   + rc_cfg[0].detect_active_timeout
                   + rc_cfg[0].polling_active_timeout
                   + rc_cfg[0].polling_configuration_timeout
                   + rc_cfg[0].config_linknum_start_timeout
                   + 100000;   // margin for the Disabled TS1/EIOS burst itself

    #(disabled_wait);

    `uvm_info("TEST","DISABLED functionality complete -> ending test",UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : LTSSM_Disabled_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    LTSSM_LOOPBACK_STATE_TEST_CASE   //////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
class LTSSM_Loopback_test extends pcie_base_test;

  `uvm_component_utils(LTSSM_Loopback_test)

  function new(string name = "LTSSM_Loopback_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    time entry_wait;

    phase.raise_objection(this);

    `uvm_info("TEST",
       "Setting Enter Loopback on RC and EP -> directing LTSSM to LOOPBACK_ENTRY out of Configuration.Linkwidth.Start",
       UVM_LOW)
    rc_cfg[0].link_ctrl_enter_loopback = 1'b1;
    ep_cfg[0].link_ctrl_enter_loopback = 1'b1;

    //-----------------------------------------------------------
    // Worst-case time for either side to reach
    // Configuration.Linkwidth.Start, plus Loopback.Entry's own
    // TS1 burst / lock-approximation timeout.
    //-----------------------------------------------------------
    entry_wait = rc_cfg[0].detect_quiet_timeout
               + rc_cfg[0].detect_active_timeout
               + rc_cfg[0].polling_active_timeout
               + rc_cfg[0].polling_configuration_timeout
               + rc_cfg[0].config_linknum_start_timeout
               + rc_cfg[0].loopback_entry_timeout
               + 100000;   // margin for the Entry TS1 burst itself

    #(entry_wait);

    `uvm_info("TEST","Directing Loopback.Active -> Loopback.Exit on both sides",UVM_LOW)
    rc_cfg[0].loopback_exit_directed = 1'b1;
    ep_cfg[0].loopback_exit_directed = 1'b1;

    // Exit's own EIOS burst + 2ms Electrical Idle, with margin.
    #(rc_cfg[0].loopback_exit_idle_time + 100000);

    `uvm_info("TEST","LOOPBACK_EXIT functionality complete -> ending test",UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : LTSSM_Loopback_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    LTSSM_HOT_RESET_STATE_TEST_CASE   /////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class LTSSM_HotReset_test extends pcie_base_test;

  `uvm_component_utils(LTSSM_HotReset_test)

  function new(string name = "LTSSM_HotReset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    time bring_up_wait;

    phase.raise_objection(this);

    `uvm_info("TEST",
       "Setting Hot Reset on RC (directed) and EP (not directed) at time 0, ahead of the LTSSM's own natural bring-up",
       UVM_LOW)
    rc_cfg[0].link_ctrl_hot_reset = 1'b1;
    ep_cfg[0].link_ctrl_hot_reset = 1'b1;

    //-----------------------------------------------------------
    // Worst-case time to reach Recovery.Idle the "real" way: full
    // Detect/Polling/Configuration bring-up, then one Recovery
    // pass (RcvrLock->RcvrCfg->Speed), plus Hot Reset's own 2ms
    // timeout and margin. Fast-path/barrier-synced bring-up is
    // normally far quicker than this bound, so it's intentionally
    // generous.
    //-----------------------------------------------------------
    bring_up_wait = rc_cfg[0].detect_quiet_timeout
                   + rc_cfg[0].detect_active_timeout
                   + rc_cfg[0].polling_active_timeout
                   + rc_cfg[0].polling_configuration_timeout
                   + rc_cfg[0].config_linknum_start_timeout
                   + rc_cfg[0].config_linknum_accept_timeout
                   + rc_cfg[0].config_lanenum_wait_timeout
                   + rc_cfg[0].config_lanenum_accept_timeout
                   + rc_cfg[0].config_complete_timeout
                   + rc_cfg[0].config_idle_timeout
                   + rc_cfg[0].recovery_rcvrlock_timeout
                   + rc_cfg[0].recovery_rcvrcfg_timeout
                   + rc_cfg[0].recovery_speed_timeout
                   + rc_cfg[0].recovery_idle_timeout
                   + rc_cfg[0].hot_reset_timeout
                   + 200000;   // margin for the Hot Reset TS1 burst itself

    #(bring_up_wait);

    `uvm_info("TEST","HOT_RESET functionality complete -> ending test",UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : LTSSM_HotReset_test
