class pcie_base_test extends uvm_test;

  `uvm_component_utils(pcie_base_test)

  //localparam int unsigned NUM_RC = `ifdef NUM_RC `NUM_RC `else 1 `endif;
  //localparam int unsigned NUM_EP = `ifdef NUM_EP `NUM_EP `else 1 `endif;


  int unsigned num_rc = `PCIE_NUM_RC;
  int unsigned num_ep = `PCIE_NUM_EP;
  // Dynamic arrays - independent sizes for RC and EP
  Env_Top RC_Env[];
  Env_Top EP_Env[];
  env_cfg rc_cfg[];
  env_cfg ep_cfg[];

  function new(string name = "pcie_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string rc_name, ep_name;
    super.build_phase(phase);

    `uvm_info("pcie_base_test",
      $sformatf("NUM_RC macro = %0d, NUM_EP macro = %0d (must match vlog +define+NUM_RC/+define+NUM_EP used for TOP.sv)",
                 num_rc, num_ep), UVM_LOW)
 //   if(!uvm_config_db#(int)::get(this, "", "num_rc", num_rc))
   //   `uvm_fatal("CFG", "num_rc not set in config_db")
   // if(!uvm_config_db#(int)::get(this, "", "num_ep", num_ep))
    //  `uvm_fatal("CFG", "num_ep not set in config_db")

    RC_Env = new[num_rc];
    rc_cfg = new[num_rc];

    EP_Env = new[num_ep];
    ep_cfg = new[num_ep];

    //-----------------------------------------------
    // Build RC environments
    //-----------------------------------------------
    for(int unsigned i = 0; i < num_rc; i++) begin

      rc_name = $sformatf("RC_Env_%0d", i);

      rc_cfg[i] = env_cfg::type_id::create($sformatf("rc_cfg_%0d", i));
      rc_cfg[i].mode = RC_MODE;

      uvm_config_db#(env_cfg)::set(this, {rc_name, ".*"}, "env_cfg", rc_cfg[i]);
     // uvm_config_db#(env_cfg)::set(this, rc_name,         "env_cfg", rc_cfg[i]);

      RC_Env[i] = Env_Top::type_id::create(rc_name, this);

    end

    //-----------------------------------------------
    // Build EP environments
    //-----------------------------------------------
    for(int unsigned i = 0; i < num_ep; i++) begin

      ep_name = $sformatf("EP_Env_%0d", i);

      ep_cfg[i] = env_cfg::type_id::create($sformatf("ep_cfg_%0d", i));
      ep_cfg[i].mode = EP_MODE;

      uvm_config_db#(env_cfg)::set(this, {ep_name, ".*"}, "env_cfg", ep_cfg[i]);
      //uvm_config_db#(env_cfg)::set(this, ep_name,         "env_cfg", ep_cfg[i]);

      EP_Env[i] = Env_Top::type_id::create(ep_name, this);

    end

  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    uvm_top.print_topology;
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    phase.raise_objection(this);
      #10;
    phase.drop_objection(this);

  endtask : run_phase

endclass
