

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

  function new(string name = "pcie_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string rc_name, ep_name;
    super.build_phase(phase);

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
      uvm_config_db#(env_cfg)::set(this, {rc_name, ".*"}, "env_cfg", rc_cfg[i]);
      uvm_config_db#(env_cfg)::set(this,  rc_name,        "env_cfg", rc_cfg[i]);
      uvm_config_db#(TL_Scoreboard)::set(this, rc_name, "TL_Scb", TL_Scb);
      RC_Env[i]  = Env_Top::type_id::create(rc_name, this);
    end

    for(int unsigned i = 0; i < num_ep; i++) begin
      ep_name    = $sformatf("EP_Env_%0d", i);
      ep_cfg[i]  = env_cfg::type_id::create($sformatf("ep_cfg_%0d", i));
      ep_cfg[i].mode = EP_MODE;
      uvm_config_db#(env_cfg)::set(this, {ep_name, ".*"}, "env_cfg", ep_cfg[i]);
      uvm_config_db#(env_cfg)::set(this,  ep_name,        "env_cfg", ep_cfg[i]);
      uvm_config_db#(TL_Scoreboard)::set(this, ep_name, "TL_Scb", TL_Scb);
      EP_Env[i]  = Env_Top::type_id::create(ep_name, this);
    end

    DL_up_env    = uvm_event_pool::get_global("link_up_env");
    DL_up_env_rx = uvm_event_pool::get_global("link_up_env_rx");

  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    TL_Scb.t_port.connect(Top_Scb.t_imp);
    TL_Scb.r_port.connect(Top_Scb.r_imp);
  endfunction : connect_phase

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    uvm_top.print_topology;
  endfunction

endclass : pcie_base_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    3DW_SINGLE_MEMORY_WRITE_READ_TEST_CASE   /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Single_Mem_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Single_Mem_Wr_Rd_3DW_test)

  Single_Mem_Wr_Rd_3DW Seq_tx;

  function new(string name = "Single_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #90000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_Mem_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    4DW_SINGLE_MEMORY_WRITE_READ_TEST_CASE   /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Single_Mem_Wr_Rd_4DW_test extends pcie_base_test;

  `uvm_component_utils(Single_Mem_Wr_Rd_4DW_test)

  Single_Mem_Wr_Rd_4DW Seq_tx;

  function new(string name = "Single_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = Single_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #20000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_Mem_Wr_Rd_4DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    3DW_MULTIPLE_MEMORY_WRITE_READ_TEST_CASE   ///////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Multiple_Mem_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Multiple_Mem_Wr_Rd_3DW_test)

  Multiple_Mem_Wr_Rd_3DW Seq_tx;

  function new(string name = "Multiple_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = Multiple_Mem_Wr_Rd_3DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #800000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_Mem_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    4DW_MULTIPLE_MEMORY_WRITE_READ_TEST_CASE   ///////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Multiple_Mem_Wr_Rd_4DW_test extends pcie_base_test;

  `uvm_component_utils(Multiple_Mem_Wr_Rd_4DW_test)

  Multiple_Mem_Wr_Rd_4DW Seq_tx;

  function new(string name = "Multiple_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = Multiple_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #30000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_Mem_Wr_Rd_4DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    3DW_BACK_2_BACK_MEMORY_WRITE_READ_TEST_CASE   ////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class B2B_Mem_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(B2B_Mem_Wr_Rd_3DW_test)

  B2B_Mem_Wr_Rd_3DW Seq_tx;

  function new(string name = "B2B_Mem_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = B2B_Mem_Wr_Rd_3DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #20000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : B2B_Mem_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////    4DW_BACK_TO_BACK_MEMORY_WRITE_READ_TEST_CASE   ///////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class B2B_Mem_Wr_Rd_4DW_test extends pcie_base_test;

  `uvm_component_utils(B2B_Mem_Wr_Rd_4DW_test)

  B2B_Mem_Wr_Rd_4DW Seq_tx;

  function new(string name = "B2B_Mem_Wr_Rd_4DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = B2B_Mem_Wr_Rd_4DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #30000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : B2B_Mem_Wr_Rd_4DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    3DW_SINGLE_IO_WRITE_READ_TEST_CASE   /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Single_IO_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Single_IO_Wr_Rd_3DW_test)

  Single_IO_Wr_Rd_3DW Seq_tx;

  function new(string name = "Single_IO_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = Single_IO_Wr_Rd_3DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #20000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Single_IO_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    3DW_MULTIPLE_IO_WRITE_READ_TEST_CASE   ///////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class Multiple_IO_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(Multiple_IO_Wr_Rd_3DW_test)

  Multiple_IO_Wr_Rd_3DW Seq_tx;

  function new(string name = "Multiple_IO_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = Multiple_IO_Wr_Rd_3DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #40000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : Multiple_IO_Wr_Rd_3DW_test


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////    3DW_BACK_2_BACK_IO_WRITE_READ_TEST_CASE   ////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class B2B_IO_Wr_Rd_3DW_test extends pcie_base_test;

  `uvm_component_utils(B2B_IO_Wr_Rd_3DW_test)

  B2B_IO_Wr_Rd_3DW Seq_tx;

  function new(string name = "B2B_IO_Wr_Rd_3DW_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    Seq_tx = B2B_IO_Wr_Rd_3DW::type_id::create("Seq_tx");
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    DL_up_env_rx.wait_trigger();
    DL_up_env.wait_trigger();

    Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.PCIe_TL_Seqr);

    #20000;
    phase.drop_objection(this);
  endtask : run_phase

endclass : B2B_IO_Wr_Rd_3DW_test
