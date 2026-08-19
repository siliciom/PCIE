////////////enum for sequences
typedef enum bit[2:0]{with_wait = 0, without_wait = 1, slave_illegal = 2} oper_mode;

////////////////////transaction
class apb_slv_xtn extends uvm_sequence_item;
	rand oper_mode op;//call enum data type
	rand bit[DATA_WIDTH-1:0] PRDATA;
	bit PREADY;
	bit PSLVERR;
	bit [ADDR_WIDTH-1:0] PADDR;
	rand int rsp_count;
	
//-------- factory and field registration -------------
`uvm_object_utils_begin(apb_slv_xtn)
   		 `uvm_field_int(PRDATA,UVM_ALL_ON)
   		 `uvm_field_int(PREADY,UVM_ALL_ON)
   		 `uvm_field_int(PSLVERR,UVM_ALL_ON)
   		 `uvm_field_int(PADDR,UVM_ALL_ON)
		   `uvm_field_enum(oper_mode, op, UVM_DEFAULT)
`uvm_object_utils_end


function new(string name = "apb_slv_xtn");
    super.new(name);
endfunction

endclass
