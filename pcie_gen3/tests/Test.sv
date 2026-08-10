class pcie_base_test extends uvm_test;

  `uvm_component_utils(pcie_base_test)


  Env_Top RC_Env[];
  Env_Top EP_Env[];
  env_cfg rc_cfg[];
  env_cfg ep_cfg[];

  TL_Scoreboard  TL_Scb;
  Scoreboard_Top Top_Scb;
  
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
      `uvm_info("TEST", $sformatf("REQ TAG = %0d  CPL TAG = %0d", rd_seq.req.tag, cpl.tag), UVM_LOW)
      if(cpl.tag == rd_seq.req.tag) begin
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
      if(cpl.tag == wr_seq.req.tag) found = 1;
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
    Mem_Seq_tx.p_length = 10;
    `uvm_info("TEST",
$sformatf("BAR0 Base=%h WR_FMT=%s RD_FMT=%s",
           Mem_Seq_tx.p_addr,
           Mem_Seq_tx.p_wr_fmt.name(),
           Mem_Seq_tx.p_rd_fmt.name()),
UVM_NONE)

    Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
   
    #90000;
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

    #90000;
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

    Seq_tx = Multiple_Mem_Wr_Rd_3DW::type_id::create("Seq_tx");
   
    Seq_tx.p_wr_fmt = bar_wr_fmt[0];
    Seq_tx.p_rd_fmt = bar_rd_fmt[0];
    Seq_tx.p_addr   = curr_addr;
    Seq_tx.p_length = 100;
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

    repeat(4) begin
	    
      Seq_tx = Multiple_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
      Seq_tx.p_wr_fmt = bar_wr_fmt[1];
      Seq_tx.p_rd_fmt = bar_rd_fmt[1];
      Seq_tx.p_addr   = curr_addr;
      Seq_tx.p_length = 70;
      Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

      curr_addr += Seq_tx.p_length * 4;

    end

    #90000;
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

    curr_addr = bar_base[3] + offset;

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

    repeat(4) begin

      Seq_tx = Multiple_IO_Wr_Rd_3DW::type_id::create("Seq_tx");
      Seq_tx.p_wr_fmt = bar_wr_fmt[3];
      Seq_tx.p_rd_fmt = bar_rd_fmt[3];
      Seq_tx.p_addr = curr_addr;
      Seq_tx.p_length = 1;
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





