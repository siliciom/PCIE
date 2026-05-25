class pcie_base_test extends uvm_test;
  
  `uvm_component_utils(pcie_base_test)
  
  function new(string name = "pcie_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction;
  
  Sequence_tx Seq_tx;
  Sequence_rx Seq_rx;
  Env_Top  Env_top;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    Seq_tx = Sequence_tx::type_id::create("Seq_tx");
    Seq_rx = Sequence_rx::type_id::create("Seq_rx");
    Env_top = Env_Top::type_id::create("Env_top", this);
    
  endfunction : build_phase
  
  function void start_of_simulation_phase(uvm_phase phase);
     super.start_of_simulation_phase(phase);
    uvm_top.print_topology;
  endfunction
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    phase.raise_objection(this);
      //Seq_tx.start(Env_top.env_tx.TX_TL_Agnt.TX_TL_Seqr);
    #10;
    phase.drop_objection(this);
    
  endtask : run_phase
  
endclass
    
