class apb_slv_agent extends uvm_agent;

     apb_slv_driver driver;
     apb_slv_sequencer sequencer;
     apb_slv_monitor monitor;

     `uvm_component_utils(apb_slv_agent)

     function new(string name = "apb_slv_agent", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);
          driver = apb_slv_driver::type_id::create("driver", this);
          sequencer = apb_slv_sequencer::type_id::create("sequencer", this);
          monitor = apb_slv_monitor::type_id::create("monitor", this);
     endfunction




     function void connect_phase(uvm_phase phase);
          super.connect_phase(phase);
          driver.seq_item_port.connect(sequencer.seq_item_export);
     endfunction

endclass
