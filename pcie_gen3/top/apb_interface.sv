interface apb_interface;
	logic PCLK,PRESETn;
	logic [ADDR_WIDTH-1:0] PADDR;
	logic PSEL;
	logic PENABLE;
	logic PWRITE;
	logic PSLVERR;
	logic PREADY;
	logic [DATA_WIDTH-1:0] PRDATA; 
	logic [DATA_WIDTH-1:0] PWDATA;
	
	modport MASTER_mp(input PREADY,PSLVERR,PRDATA,PCLK,output PSEL,PENABLE,PADDR,PWDATA,PWRITE);
	modport SLAVE_mp(output PREADY,PSLVERR,PRDATA,input PSEL,PENABLE,PADDR,PWDATA,PWRITE,PCLK);
	
	default clocking assertion_cb @(posedge PCLK);
		default input #1 output #1;
	endclocking

	//`include "SVA.sv"

endinterface

