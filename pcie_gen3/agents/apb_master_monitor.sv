//`define MON_IF vif.MASTER_mp
class monitor_apb_master extends uvm_monitor;
	`uvm_component_utils(monitor_apb_master)

	virtual apb_interface vif;
	uvm_analysis_port #(seq_item_apb_master) item_port;
	seq_item_apb_master item;
 
	function new (string name = "monitor_apb_master",uvm_component parent = null);
	   super.new(name, parent);
	   item = new();
	endfunction
 
//////////////////////////////////build phase/////////////////////////////////////////////////

	function void build_phase(uvm_phase phase);
	   super.build_phase(phase);
	   item_port = new ("item_port", this);
	   item = seq_item_apb_master::type_id::create("item");
	   if(! uvm_config_db #(virtual apb_interface):: get (this, "", "mvif",vif)) 
	      `uvm_error (get_type_name (), "DUT interface not found")
	endfunction
  
  uvm_event mas2cov;
//////////////////////////////////run phase//////////////////////////////////////////////////

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		mas2cov = uvm_event_pool::get_global("m2c");
		master_monitor();	
	endtask

	task master_monitor();
		forever begin
		 @(negedge vif.PCLK);
		 if(vif.PSEL==1) begin
		 		item.PADDR = vif.PADDR;
		 		item.PWDATA = vif.PWDATA;
		  	if(vif.PWRITE==1) item.rd_wr=item.write;
		 		else item.rd_wr=item.read;
		 		if(vif.PENABLE && vif.PREADY) begin
	  			item_port.write(item);
				end
				mas2cov.trigger;
		 end
		end
	endtask
	
endclass
