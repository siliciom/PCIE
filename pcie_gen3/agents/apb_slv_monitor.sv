//`define MON_IF vif.SLAVE_mp
class apb_slv_monitor extends uvm_monitor;
  `uvm_component_utils(apb_slv_monitor)
  virtual apb_interface.APB_SLV_MON vif;
  
	uvm_analysis_port#(apb_slv_xtn) item_port;
  apb_slv_xtn slv_xtnh;


function new(string name = "apb_slv_monitor", uvm_component parent);
  super.new(name,parent);
	item_port=new("item_port",this);
endfunction

 

function void build_phase(uvm_phase phase);
 super.build_phase(phase);
  slv_xtnh = apb_slv_xtn::type_id::create("slv_xtnh");
	if(!uvm_config_db#(virtual apb_interface)::get(this,"","svif",vif))
		`uvm_fatal(get_full_name(),"UNABLE TO ACCESS INTERFACE")
endfunction
 
uvm_event slv2cov;
 
task run_phase(uvm_phase phase);
	slv2cov = uvm_event_pool::get_global("s2c");
  forever 
    begin
      collect_data();
      slv2cov.trigger;
    end
endtask


task collect_data();
	@(negedge vif.PCLK)
	if(vif.PSEL==1) begin
	slv_xtnh.PADDR = vif.PADDR;
		if(vif.PENABLE==1 && vif.PREADY == 1) begin
			slv_xtnh.PSLVERR = vif.PSLVERR;
			if(vif.PWRITE==0) begin
				slv_xtnh.PRDATA = vif.PRDATA;
				item_port.write(slv_xtnh);
			end
		end
	end
endtask

endclass
