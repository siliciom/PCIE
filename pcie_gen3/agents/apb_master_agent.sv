class agent_apb_master extends uvm_agent;
	`uvm_component_utils(agent_apb_master)
 
	driver_apb_master driver;
	sequencer_apb_master sequencer;
	monitor_apb_master monitor;

	function new (string name = "agent_apb_master", uvm_component parent = null);
	  super.new(name, parent);
	endfunction

////////////////////build phase//////////////////////////////////////////////////
virtual apb_interface vif;
	function void build_phase(uvm_phase phase);
	  super.build_phase(phase);
	    if(get_is_active() == UVM_ACTIVE) begin
	       driver = driver_apb_master::type_id::create("driver", this);
	       sequencer = sequencer_apb_master::type_id::create("sequencer", this);
	    end
	   monitor = monitor_apb_master::type_id::create("monitor", this);
	endfunction

//////////////////////connect phase//////////////////////////////////////////////////
	function void connect_phase(uvm_phase phase);
	   super.connect_phase(phase);
	     if(get_is_active() == UVM_ACTIVE) begin
	        driver.seq_item_port.connect(sequencer.seq_item_export);
	     end
	endfunction

endclass : agent_apb_master
