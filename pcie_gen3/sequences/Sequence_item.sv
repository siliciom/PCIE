class Sequence_item extends uvm_sequence_item;
  
  // Generic TLP Fields //
  
  rand bit[2:0]     fmt;
  rand bit[4:0]     r_type;
       bit          R1;
  rand bit[2:0]     tc;
       bit          R2;
  rand bit          attr_1;
       bit          R3;
  rand bit          th;
  rand bit          td;
  rand bit          ep;
  rand bit[1:0]     attr_2;
  rand bit[1:0]     at;
  rand bit[9:0]     length;
  rand bit[31:0] payload[];
  
  //  Memory TLP Fields //
  
  rand bit[7:0]  bus;
  rand bit[4:0]  device;
  rand bit[2:0]  function_n;         
  rand bit[7:0]  tag;
  rand bit[3:0]  last_BE;
  rand bit[3:0]  first_BE;
  rand bit[63:0] addr;
       bit[1:0]  R4;
       bit[15:0] req_id;
  bit[31:0] data;
  bit valid;
  
  `uvm_object_utils_begin(Sequence_item)
  `uvm_field_int(fmt,        UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(r_type,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(tc,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(attr_1,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(th,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(td,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(ep,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(attr_2,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(at,         UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(length,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_array_int(payload,    UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(bus,        UVM_ALL_ON | UVM_DEC) 
  `uvm_field_int(device,     UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(function_n, UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(tag,        UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(last_BE,    UVM_ALL_ON | UVM_DEC) 
  `uvm_field_int(first_BE,   UVM_ALL_ON | UVM_DEC)
  `uvm_field_int(addr,       UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end
  
  
  function new(string name = "Sequence_item");
    super.new(name);
  endfunction
    
  function void post_randomize();
    req_id     = {bus, device, function_n};
    addr[63:0] = {addr[63:32], addr[31:2], R4[1:0]};  
  endfunction
  
  
  constraint mem_fmt_constraint {
    if (r_type inside {5'b00000, 5'b00001}) {
      fmt inside {3'b000, 3'b001, 3'b010, 3'b011};
    }
  }
  
  constraint io_fmt_constraint {
    if (r_type == 5'b00010) {
      fmt inside {3'b000, 3'b010};
    }
  }
      
  constraint configuration_fmt_constraint {
    if (r_type inside {5'b00100, 5'b00101}) {
      fmt inside {3'b000, 3'b010};
    }
  }
      
  constraint message_fmt_constraint {
    if (r_type inside {[5'b10000 : 5'b10111]}) {
      fmt inside {3'b001, 3'b011};
    }
  }
      
  constraint completion_fmt_constraint {
    if (r_type inside {5'b01010, 5'b01011}) {
      fmt inside {3'b000, 3'b010};
    }
  }
      
  constraint payload_size_constraint {
    payload.size() == length;
  }
      
  constraint byte_enable_constraint {
    if (length == 1) {
      last_BE == 4'b0000;
    }
      
      if (length > 1) {
        first_BE != 4'b0000;
      }
        
        if (length >= 3) {
          first_BE inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
          last_BE  inside {4'b0001,4'b0011,4'b0111,4'b1111,4'b1000,4'b1100,4'b1110};
        }
        }
          
   constraint traffic_class_constraint {
     tc inside {3'b000};
   }
          
   constraint address_type_constraint {
     at inside {2'b10}; // Translated Address //
   }
          
   constraint attributes_constraint {
     attr_1 inside {1'b0};
   }
          
   constraint attributes_constraint_1 {
     attr_2 inside {2'b00};
   }
          
    
          
          
endclass : Sequence_item
  
  
  	
