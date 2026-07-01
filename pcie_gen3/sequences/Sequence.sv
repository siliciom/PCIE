class Sequence_tx extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Sequence_tx)
  
  function new(string name = "Sequence");
    super.new(name);
  endfunction
  
  task body();
     repeat(4) begin
     
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1; length == 4;})

    $display("E_TYPE = %s E_FMT = %s fmt = %3b", req.e_type.name(), req.e_fmt.name(), req.fmt);
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1; length == 4;})
    $display("E_TYPE = %s E_FMT = %s fmt = %3b", req.e_type.name(), req.e_fmt.name(), req.fmt);

    
// `uvm_do_with(req, {e_type == IO_WR; addr == 32'h10; td == 1;})
// `uvm_do_with(req, {e_type == IO_RD; addr == 32'h10; td == 1;})
    
     end
        
  endtask
  
endclass : Sequence_tx
      
      
      
      
class Single_Mem_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Single_Mem_Wr_Rd_3DW)
  
  function new(string name = "Single_Mem_Wr_Rd_3DW");
    super.new(name);
  endfunction
  
  task body();
    
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1; length == 4;})
    
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1; length == 4;})
    
   
  endtask : body
  
endclass : Single_Mem_Wr_Rd_3DW



class Single_Mem_Wr_Rd_4DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Single_Mem_Wr_Rd_4DW)
  
  function new(string name = "Single_Mem_Wr_Rd_4DW");
    super.new(name);
  endfunction
  
  task body();
    
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_4DW_DATA;    addr == 64'h120; td == 1; length == 3;})
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_4DW_NO_DATA; addr == 64'h120; td == 1; length == 3;})
  
  endtask : body
  
endclass : Single_Mem_Wr_Rd_4DW




class Multiple_Mem_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Multiple_Mem_Wr_Rd_3DW)
  
  int address;
  bit [31:0] addr_q[$];
  
  function new(string name = "Multiple_Mem_Wr_Rd_3DW");
    super.new(name);
  endfunction
  
  task body();
    repeat(4) begin
     
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1; length == 4;})

    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1; length == 4;})

     end
        
  
  endtask : body
  
endclass : Multiple_Mem_Wr_Rd_3DW




class Multiple_Mem_Wr_Rd_4DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Multiple_Mem_Wr_Rd_4DW)
  
  longint unsigned address;
  bit [63:0] addr_q[$];
  
  function new(string name = "Multiple_Mem_Wr_Rd_4DW");
    super.new(name);
  endfunction
  
  task body();
    
    repeat(4) begin
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_4DW_DATA;    addr == 64'h120; td == 1; length == 3;})
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_4DW_NO_DATA; addr == 64'h120; td == 1; length == 3;})

    end
  endtask : body
  
endclass : Multiple_Mem_Wr_Rd_4DW




class B2B_Mem_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(B2B_Mem_Wr_Rd_3DW)
  
  function new(string name = "B2B_Mem_Wr_Rd_3DW");
    super.new(name);
  endfunction
  
  task body();
    
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1; length == 4;})
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == 32'h20; td == 1; length == 4;})
    
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1; length == 4;})
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h20; td == 1; length == 4;})
  
  endtask : body
  
endclass : B2B_Mem_Wr_Rd_3DW




class B2B_Mem_Wr_Rd_4DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(B2B_Mem_Wr_Rd_4DW)
  
  function new(string name = "B2B_Mem_Wr_Rd_4DW");
    super.new(name);
  endfunction
  
  task body();
    
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_4DW_DATA; addr == 32'h10; td == 1; length == 3;})
    `uvm_do_with(req, {e_type == MEM_WR; e_fmt == FMT_4DW_DATA; addr == 32'h20; td == 1; length == 3;})
    
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_4DW_NO_DATA; addr == 32'h10; td == 1; length == 3;})
    `uvm_do_with(req, {e_type == MEM_RD; e_fmt == FMT_4DW_NO_DATA; addr == 32'h20; td == 1; length == 3;})
  
  endtask : body
  
endclass : B2B_Mem_Wr_Rd_4DW




class Single_IO_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Single_IO_Wr_Rd_3DW)
  
  function new(string name = "Single_IO_Wr_Rd_3DW");
    super.new(name);
  endfunction
  
  task body();
    
    `uvm_do_with(req, {e_type == IO_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1;})
    `uvm_do_with(req, {e_type == IO_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1;})
  
  endtask : body
  
endclass : Single_IO_Wr_Rd_3DW





class Multiple_IO_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Multiple_IO_Wr_Rd_3DW)
  
  int address;
  bit [31:0] addr_q[$];
  
  function new(string name = "Multiple_IO_Wr_Rd_3DW");
    super.new(name);
  endfunction
  
  task body();
    
    repeat(4) begin
      `uvm_do_with(req, {e_type == IO_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1;})
    `uvm_do_with(req, {e_type == IO_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1;})

    end  
  endtask : body
  
endclass : Multiple_IO_Wr_Rd_3DW





class B2B_IO_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(B2B_IO_Wr_Rd_3DW)
  
  function new(string name = "B2B_IO_Wr_Rd_3DW");
    super.new(name);
  endfunction
  
  task body();
    
    `uvm_do_with(req, {e_type == IO_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1;})
    `uvm_do_with(req, {e_type == IO_WR; e_fmt == FMT_3DW_DATA; addr == 32'h20; td == 1;})
    
    `uvm_do_with(req, {e_type == IO_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1;})
    `uvm_do_with(req, {e_type == IO_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h20; td == 1;})
  
  endtask : body
  
endclass : B2B_IO_Wr_Rd_3DW





 
  
   
  
  
  
  
  
      
      
      


class Sequence_rx extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Sequence_rx)
  
  function new(string name = "Sequence");
    super.new(name);
  endfunction
  
  task body();
    // Sequence Logic //
  endtask
  
endclass : Sequence_rx
