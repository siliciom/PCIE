class seq_item_apb_master extends uvm_sequence_item;

     rand bit [DATA_WIDTH-1:0] PWDATA;
     rand bit [ADDR_WIDTH-1:0] PADDR;
     bit      [DATA_WIDTH-1:0] PRDATA;
     bit                       PSLVERR_captured;
     typedef enum {
          read,
          write
     } write_ctrl;
     typedef enum {
          three_cycles,
          idle_drive,
          unstable
     } corrupt_logic_t;
     rand write_ctrl rd_wr;
     rand corrupt_logic_t corrupt_logic;
     rand bit corrupt;

     `uvm_object_utils_begin(seq_item_apb_master)
          `uvm_field_int(PWDATA, UVM_ALL_ON)
          `uvm_field_int(PADDR, UVM_ALL_ON)
          `uvm_field_int(PRDATA, UVM_ALL_ON | UVM_NOPACK)
          `uvm_field_enum(write_ctrl, rd_wr, UVM_ALL_ON)
          `uvm_field_enum(corrupt_logic_t, corrupt_logic, UVM_ALL_ON)
          `uvm_field_int(corrupt, UVM_ALL_ON)
     `uvm_object_utils_end

     function new(string name = "seq_item_apb_master");
          super.new(name);
     endfunction

     constraint corrupt_value {soft corrupt == 0;}
     constraint data_limit {soft PWDATA <= 50000;}
     constraint addr_limit {PADDR inside {[1000 : 3000]};}

endclass : seq_item_apb_master
