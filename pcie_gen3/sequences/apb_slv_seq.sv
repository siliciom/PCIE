class apb_slv_base extends uvm_sequence #(apb_slv_xtn);
     `uvm_object_utils(apb_slv_base)

     function new(string name = "apb_slv_base");
          super.new(name);
     endfunction

     rand int cnt;
     constraint repeat_count {soft cnt == 500;}

endclass


class with_wait_state extends apb_slv_base;
     `uvm_object_utils(with_wait_state)

     apb_slv_xtn xtn;

     function new(string name = "with_wait_state");
          super.new(name);
     endfunction

     task body();
          repeat (cnt) begin
               xtn = apb_slv_xtn::type_id::create("xtn");
               start_item(xtn);
               assert (xtn.randomize() with {rsp_count inside {[1 : 5]};}) xtn.op = with_wait;
               finish_item(xtn);
          end
     endtask

endclass


class without_wait_state extends apb_slv_base;
     `uvm_object_utils(without_wait_state)

     apb_slv_xtn xtn;

     function new(string name = "without_wait_state");
          super.new(name);
     endfunction

     task body();
          repeat (cnt) begin
               xtn = apb_slv_xtn::type_id::create("xtn");
               start_item(xtn);
               assert (xtn.randomize());
               xtn.op = without_wait;
               finish_item(xtn);
          end
     endtask

endclass
/*
class slv_err extends apb_slv_base;
	`uvm_object_utils(slv_err)

	apb_slv_xtn xtn;

	function new(string name = "slv_err");
		super.new(name);
	endfunction

	task body();
		repeat(cnt)
			begin
				xtn = apb_slv_xtn::type_id::create("xtn");
				start_item(xtn);
				assert(xtn.randomize()); //with{slverr inside {0,1};}
				xtn.op = slave_err;
				finish_item(xtn);
			end
	endtask

endclass
*/
class apb_slv_illegal extends apb_slv_base;
     `uvm_object_utils(apb_slv_illegal)

     function new(string name = "apb_slv_illegal");
          super.new(name);
     endfunction

     apb_slv_xtn xtn;

     task body();
          repeat (cnt) begin
               xtn = apb_slv_xtn::type_id::create("xtn");
               start_item(xtn);
               assert (xtn.randomize()) xtn.op = slave_illegal;
               finish_item(xtn);
          end
     endtask
endclass

class apb_slv_seq_lib extends uvm_sequence_library #(apb_slv_xtn);

     `uvm_object_utils(apb_slv_seq_lib)
     `uvm_sequence_library_utils(apb_slv_seq_lib)

     function new(string name = "apb_slv_seq_lib");
          super.new(name);
          add_typewide_sequence(with_wait_state::get_type());
          add_typewide_sequence(without_wait_state::get_type());
          selection_mode   = UVM_SEQ_LIB_RANDC;
          min_random_count = 4;
          max_random_count = 4;
          init_sequence_library();
     endfunction

endclass

