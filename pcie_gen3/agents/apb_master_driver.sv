//`define DRV_IF vif.MASTER_mp
class driver_apb_master extends uvm_driver#(seq_item_apb_master);
	`uvm_component_utils(driver_apb_master)

	function new (string name, uvm_component parent);
		super.new(name,parent);
	endfunction
	
	virtual apb_interface vif;

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual apb_interface)::get(this, "","mvif",vif))
		begin
	//	 `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
		end
	endfunction

	seq_item_apb_master tx;
	uvm_event m2s,s2m;
	virtual task run_phase(uvm_phase phase);
		m2s = uvm_event_pool::get_global("mas2slv");
		s2m = uvm_event_pool::get_global("slv2mas");
		forever begin
			if(vif.PRESETn==0) reset();
			seq_item_port.get(tx);
			if(tx.corrupt ==0)
	  		drive();
			else
				ill_drive();
			seq_item_port.put(tx);
		end
	endtask

	extern task reset();
	extern task drive();	
	extern task ill_drive();
	extern task three_cycles();
	extern task idle_drive();
	extern task unstable();

endclass : driver_apb_master

task driver_apb_master::drive();
// ************************* WRITE TRANSFER *************************    
    if(tx.rd_wr==tx.write) begin
// ************************* SETUP STATE ****************************
        vif.PSEL <= 1;
        vif.PWRITE <= 1;
        vif.PADDR <= tx.PADDR;
        vif.PWDATA <= tx.PWDATA;
        uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
        @(posedge vif.PCLK);
// ************************* ACCESS STATE ***************************
        vif.PENABLE <= 1;
        uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
// ************************* WAIT STATE *****************************
				wait(vif.PREADY==1);
       // uvm_report_info("MASTER","WAITING FOR PREADY",UVM_HIGH);
// ************************* LAST CYCLE *****************************
        uvm_report_info("MASTER","PREADY RECEIVED",UVM_HIGH);
        if(vif.PSLVERR==0) begin
						@(posedge vif.PCLK);
            vif.PENABLE <= 0;
        end
// *********************** IDLE if PSLVERR **************************
        else begin
 						@(posedge vif.PCLK);
            vif.PSEL <= 0;
            vif.PENABLE <= 0;
						@(posedge vif.PCLK);
        end
		end
// ************************ READ TRANSFER ***************************
		else begin
// ************************* SETUP STATE ****************************
        vif.PSEL <= 1;
        vif.PWRITE <= 0;
        vif.PADDR <= tx.PADDR;
				uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
        @(posedge vif.PCLK);
// ************************* ACCESS STATE ***************************
        vif.PENABLE <= 1;
				uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
// ************************* WAIT STATE *****************************
        wait(vif.PREADY==1);
	#1;
	 tx.PRDATA = vif.PRDATA; 
			//	uvm_report_info("MASTER","WAITING FOR PREADY",UVM_HIGH);
// ************************* LAST CYCLE *****************************
				uvm_report_info("MASTER","PREADY RECEIVED",UVM_HIGH);        
        if(vif.PSLVERR==0) begin
						@(posedge vif.PCLK);
            vif.PENABLE <= 0;
        end
// *********************** IDLE if PSLVERR **************************
        else begin
            @(posedge vif.PCLK);
            vif.PENABLE <= 0;
            vif.PSEL <= 0;
            @(posedge vif.PCLK);
        end
		end
endtask

task driver_apb_master::ill_drive();
	begin 
		case(tx.corrupt_logic)
			tx.three_cycles : three_cycles();
			tx.idle_drive : idle_drive();
			tx.unstable : unstable();
		endcase
	end
endtask

////Illegal Drive //// delay by 3 cycle/////

task driver_apb_master::three_cycles();
// ************************* WRITE TRANSFER *************************	
	if(tx.rd_wr==tx.write) begin
// ************************* SETUP STATE ****************************
		vif.PSEL <= 1;		
		vif.PWRITE <= 1;
		vif.PADDR <= tx.PADDR;
		vif.PWDATA <= tx.PWDATA;
		uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
		@(posedge vif.PCLK);
		@(posedge vif.PCLK);
// ************************* ACCESS STATE ***************************
		vif.PENABLE <= 1;
		uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
// ************************* WAIT STATE *****************************
     wait(vif.PREADY==1);
		uvm_report_info("MASTER","PREADY-RECEIVED",UVM_HIGH);
// ************************* LAST CYCLE *****************************
		if(vif.PSLVERR==0) begin
			@(posedge vif.PCLK);
			vif.PENABLE <= 0;
		end
// *********************** IDLE if PSLVERR **************************
		else begin
			@(posedge vif.PCLK);
			vif.PSEL <= 0;
			vif.PENABLE <= 0;
			@(posedge vif.PCLK);
		end
	end
// ************************ READ TRANSFER ***************************
	else begin
// ************************* SETUP STATE ****************************
		vif.PSEL <= 1;
		vif.PWRITE <= 0;
		vif.PADDR <= tx.PADDR;
		uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
		@(posedge vif.PCLK);
		@(posedge vif.PCLK);
// ************************* ACCESS STATE ***************************
		vif.PENABLE <= 1;
		uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
// ************************* WAIT STATE *****************************
     wait(vif.PREADY==1);
		uvm_report_info("MASTER","PREADY-RECEIVED",UVM_HIGH);
// ************************* LAST CYCLE *****************************
		if(vif.PSLVERR==0) begin
			@(posedge vif.PCLK);
			vif.PENABLE <= 0;
		end
// *********************** IDLE if PSLVERR **************************
		else begin
			@(posedge vif.PCLK);
			vif.PENABLE <= 0;
			vif.PSEL <= 0;
			@(posedge vif.PCLK);
		end
	end

endtask

////Illegal drive//// Function in idle state ////

task driver_apb_master::idle_drive();
// *********************** IDLE STATE ********************************
	vif.PSEL <= 0;
	vif.PENABLE <= 0;
	vif.PADDR <= tx.PADDR;
	if(tx.rd_wr==tx.write) begin
		vif.PWRITE <= 1;
		vif.PWDATA <= tx.PWDATA;
	end
	else vif.PWRITE <= 0;
// ************************* SETUP STATE *****************************
	@(posedge vif.PCLK);
	vif.PSEL <= 1;
	uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
// ************************* ACCESS STATE ****************************
	@(posedge vif.PCLK);
	vif.PENABLE <= 1;
	uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
	wait(vif.PREADY==1);
	uvm_report_info("MASTER","PREADY-RECEIVED",UVM_HIGH);
	@(posedge vif.PCLK);
	vif.PENABLE <= 0;

endtask

////Illegal drive//// random write data and address ////

task driver_apb_master::unstable();

// ************************* WRITE TRANSFER *************************	
	if(tx.rd_wr==tx.write) begin
// ************************* SETUP STATE ****************************
		vif.PSEL <= 1;
		vif.PWRITE <= 1;
		vif.PADDR <= tx.PADDR;
		vif.PWDATA <= tx.PWDATA;
    uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
		@(posedge vif.PCLK);
// ************************* ACCESS STATE ***************************
		vif.PENABLE <= 1;
    uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
		vif.PWDATA <= $urandom;
// ************************* WAIT STATE *****************************
    wait(vif.PREADY==1);
		uvm_report_info("MASTER","PREADY-RECEIVED",UVM_HIGH);
// ************************* LAST CYCLE *****************************
		if(vif.PSLVERR==0) begin
			@(posedge vif.PCLK);
			vif.PENABLE <= 0;
		end
// *********************** IDLE if PSLVERR **************************
		else begin
			@(posedge vif.PCLK);
			vif.PSEL <= 0;
			vif.PENABLE <= 0;
			@(posedge vif.PCLK);
		end
	end
// ************************ READ TRANSFER ***************************
	else begin
// ************************* SETUP STATE ****************************
		vif.PSEL <= 1;
		vif.PWRITE <= 0;
		vif.PADDR <= tx.PADDR;
    uvm_report_info("MASTER","PSEL-DRIVEN",UVM_HIGH);
		@(posedge vif.PCLK);
// ************************* ACCESS STATE ***************************
		vif.PENABLE <= 1;
		vif.PADDR <= $urandom;
    uvm_report_info("MASTER","PENABLE-DRIVEN",UVM_HIGH);
// ************************* WAIT STATE *****************************
    wait(vif.PREADY==1);
		uvm_report_info("MASTER","PREADY-RECEIVED",UVM_HIGH);
// ************************* LAST CYCLE *****************************
		if(vif.PSLVERR==0) begin
			@(posedge vif.PCLK);
			vif.PENABLE <= 0;
		end
// *********************** IDLE if PSLVERR **************************
		else begin
			@(posedge vif.PCLK);
			vif.PENABLE <= 0;
			vif.PSEL <= 0;
			@(posedge vif.PCLK);
		end
	end

endtask


task driver_apb_master::reset();
	vif.PWRITE   <=0;
	vif.PSEL     <=0;
	vif.PENABLE  <=0;
	vif.PADDR    <=0;
	vif.PWDATA   <=0;
	wait(vif.PRESETn==1);
	@(posedge vif.PCLK);
endtask
