class Sequence_tx extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Sequence_tx)
  
  function new(string name = "Sequence");
    super.new(name);
  endfunction
  
  task body();
    req = Sequence_item::type_id::create("req");
    
    start_item(req);
    
    // Byte 0 //
    
    req.fmt           = 3'b001;
    req.r_type        = 5'b00000;
    req.R1            = 1'b0;
    req.tc            = 3'b000;
    req.R2            = 1'b0;
    req.attr_1        = 1'b0;
    req.R3            = 1'b0;
    req.th            = 1'b0;
    req.td            = 1'b0;
    req.ep            = 1'b0;
    req.attr_2        = 2'b00;    
    req.at            = 2'b10;
    req.length        = 10'd1;
    
    // Byte 1 //
    
    req.req_id        = 15'd256;
    req.tag           = 8'd0;
    req.first_BE      = 4'b1111;
    req.last_BE       = 4'b0000;
    
    // Byte 2 //
    
    req.addr[63:32]   = 32'd0;
    
    // Byte 3 //
    req.addr[31:0]    = 32'd12;
    
    //req.payload       = 32768'd15;
    
    req.R4[1:0]       = 2'b00;
    
    finish_item(req);
    
    req.print();
    
    
  endtask
  
endclass : Sequence_tx




















class Sequence_rx extends uvm_sequence #(Sequence_item);
  
  `uvm_object_utils(Sequence_rx)
  
  function new(string name = "Sequence");
    super.new(name);
  endfunction
  
  task body();
    // Sequence Logic //
  endtask
  
endclass : Sequence_rx
