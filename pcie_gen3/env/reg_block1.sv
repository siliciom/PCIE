// DW00 (0x00): Device ID | Vendor ID
class reg_vendor_device_id1 extends uvm_reg;
     rand uvm_reg_field vendor_id;
     rand uvm_reg_field device_id;
     `uvm_object_utils(reg_vendor_device_id1)

     function new(string name = "reg_vendor_device_id1");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          vendor_id = uvm_reg_field::type_id::create("vendor_id");
          device_id = uvm_reg_field::type_id::create("device_id");
          vendor_id.configure(this, 16, 0, "RO", 0, 16'h0000, 1, 0, 1);
          device_id.configure(this, 16, 16, "RO", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// DW01 (0x04): Status | Command
class reg_command_status1 extends uvm_reg;
     rand uvm_reg_field command;
     rand uvm_reg_field status;
     `uvm_object_utils(reg_command_status1)

     function new(string name = "reg_command_status1");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          command = uvm_reg_field::type_id::create("command");
          status  = uvm_reg_field::type_id::create("status");
          command.configure(this, 16, 0, "RW", 0, 16'h0000, 1, 0, 1);
          status.configure(this, 16, 16, "W1C", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// DW02 (0x08): Class Code | Revision ID
class reg_class_rev extends uvm_reg;
     rand uvm_reg_field revision_id;
     rand uvm_reg_field class_code;
     `uvm_object_utils(reg_class_rev)

     function new(string name = "reg_class_rev");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          revision_id = uvm_reg_field::type_id::create("revision_id");
          class_code  = uvm_reg_field::type_id::create("class_code");
          revision_id.configure(this, 8, 0, "RO", 0, 8'h00, 1, 0, 1);
          class_code.configure(this, 24, 8, "RO", 0, 24'h0, 1, 0, 1);
     endfunction
endclass

// DW03 (0x0C): BIST | Header Type | Latency Timer | Cache Line Size
class reg_bist_hdr_lat_cls1 extends uvm_reg;
     rand uvm_reg_field cache_line_size;
     rand uvm_reg_field latency_timer;
     rand uvm_reg_field header_type;
     rand uvm_reg_field bist;
     `uvm_object_utils(reg_bist_hdr_lat_cls1)

     function new(string name = "reg_bist_hdr_lat_cls1");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          cache_line_size = uvm_reg_field::type_id::create("cache_line_size");
          latency_timer   = uvm_reg_field::type_id::create("latency_timer");
          header_type     = uvm_reg_field::type_id::create("header_type");
          bist            = uvm_reg_field::type_id::create("bist");
          cache_line_size.configure(this, 8, 0, "RW", 0, 8'h00, 1, 0, 1);
          latency_timer.configure(this, 8, 8, "RW", 0, 8'h00, 1, 0, 1);
          header_type.configure(this, 8, 16, "RO", 0, 8'h01, 1, 0, 1);  // 0x01 = Type1
          bist.configure(this, 8, 24, "RW", 0, 8'h00, 1, 0, 1);
     endfunction
endclass

// DW04 (0x10) / DW05 (0x14): Base Address 0 / 1
class reg_bar1 extends uvm_reg;
     rand uvm_reg_field bar_val;
     `uvm_object_utils(reg_bar1)

     function new(string name = "reg_bar1");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          bar_val = uvm_reg_field::type_id::create("bar_val");
          bar_val.configure(this, 32, 0, "RW", 0, 32'h0000_0000, 1, 0, 1);
     endfunction
endclass

// DW06 (0x18): Secondary Latency Timer | Subordinate Bus | Secondary Bus | Primary Bus
class reg_bus_numbers extends uvm_reg;
     rand uvm_reg_field primary_bus_num;
     rand uvm_reg_field secondary_bus_num;
     rand uvm_reg_field subordinate_bus_num;
     rand uvm_reg_field secondary_latency_timer;
     `uvm_object_utils(reg_bus_numbers)

     function new(string name = "reg_bus_numbers");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          primary_bus_num         = uvm_reg_field::type_id::create("primary_bus_num");
          secondary_bus_num       = uvm_reg_field::type_id::create("secondary_bus_num");
          subordinate_bus_num     = uvm_reg_field::type_id::create("subordinate_bus_num");
          secondary_latency_timer = uvm_reg_field::type_id::create("secondary_latency_timer");
          primary_bus_num.configure(this, 8, 0, "RW", 0, 8'h00, 1, 0, 1);
          secondary_bus_num.configure(this, 8, 8, "RW", 0, 8'h00, 1, 0, 1);
          subordinate_bus_num.configure(this, 8, 16, "RW", 0, 8'h00, 1, 0, 1);
          secondary_latency_timer.configure(this, 8, 24, "RW", 0, 8'h00, 1, 0, 1);
     endfunction
endclass

// DW07 (0x1C): Secondary Status | I/O Limit | I/O Base
class reg_io_base_limit extends uvm_reg;
     rand uvm_reg_field io_base;
     rand uvm_reg_field io_limit;
     rand uvm_reg_field secondary_status;
     `uvm_object_utils(reg_io_base_limit)

     function new(string name = "reg_io_base_limit");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          io_base          = uvm_reg_field::type_id::create("io_base");
          io_limit         = uvm_reg_field::type_id::create("io_limit");
          secondary_status = uvm_reg_field::type_id::create("secondary_status");
          io_base.configure(this, 8, 0, "RW", 0, 8'h00, 1, 0, 1);
          io_limit.configure(this, 8, 8, "RW", 0, 8'h00, 1, 0, 1);
          secondary_status.configure(this, 16, 16, "W1C", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// DW08 (0x20): Memory Limit | Memory Base
class reg_mem_base_limit extends uvm_reg;
     rand uvm_reg_field memory_base;
     rand uvm_reg_field memory_limit;
     `uvm_object_utils(reg_mem_base_limit)

     function new(string name = "reg_mem_base_limit");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          memory_base  = uvm_reg_field::type_id::create("memory_base");
          memory_limit = uvm_reg_field::type_id::create("memory_limit");
          memory_base.configure(this, 16, 0, "RW", 0, 16'h0000, 1, 0, 1);
          memory_limit.configure(this, 16, 16, "RW", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// DW09 (0x24): Prefetchable Memory Limit | Prefetchable Memory Base
class reg_pf_mem_base_limit extends uvm_reg;
     rand uvm_reg_field pf_mem_base;
     rand uvm_reg_field pf_mem_limit;
     `uvm_object_utils(reg_pf_mem_base_limit)

     function new(string name = "reg_pf_mem_base_limit");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          pf_mem_base  = uvm_reg_field::type_id::create("pf_mem_base");
          pf_mem_limit = uvm_reg_field::type_id::create("pf_mem_limit");
          pf_mem_base.configure(this, 16, 0, "RW", 0, 16'h0000, 1, 0, 1);
          pf_mem_limit.configure(this, 16, 16, "RW", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// DW10 (0x28) / DW11 (0x2C): Prefetchable Base/Limit Upper 32-bits
class reg_pf_upper32 extends uvm_reg;
     rand uvm_reg_field upper32;
     `uvm_object_utils(reg_pf_upper32)

     function new(string name = "reg_pf_upper32");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          upper32 = uvm_reg_field::type_id::create("upper32");
          upper32.configure(this, 32, 0, "RW", 0, 32'h0000_0000, 1, 0, 1);
     endfunction
endclass

// DW12 (0x30): I/O Limit Upper 16-bits | I/O Base Upper 16-bits
class reg_io_upper16 extends uvm_reg;
     rand uvm_reg_field io_base_upper;
     rand uvm_reg_field io_limit_upper;
     `uvm_object_utils(reg_io_upper16)

     function new(string name = "reg_io_upper16");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          io_base_upper  = uvm_reg_field::type_id::create("io_base_upper");
          io_limit_upper = uvm_reg_field::type_id::create("io_limit_upper");
          io_base_upper.configure(this, 16, 0, "RW", 0, 16'h0000, 1, 0, 1);
          io_limit_upper.configure(this, 16, 16, "RW", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// DW13 (0x34): Reserved | Capabilities Pointer
class reg_cap_ptr extends uvm_reg;
     rand uvm_reg_field capabilities_pointer;
     rand uvm_reg_field reserved;
     `uvm_object_utils(reg_cap_ptr)

     function new(string name = "reg_cap_ptr");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          capabilities_pointer = uvm_reg_field::type_id::create("capabilities_pointer");
          reserved             = uvm_reg_field::type_id::create("reserved");
          capabilities_pointer.configure(this, 8, 0, "RO", 0, 8'h00, 1, 0, 1);
          reserved.configure(this, 24, 8, "RO", 0, 24'h0, 1, 0, 1);
     endfunction
endclass

// DW14 (0x38): Expansion ROM Base Address
class reg_exp_rom extends uvm_reg;
     rand uvm_reg_field exp_rom_base;
     `uvm_object_utils(reg_exp_rom)

     function new(string name = "reg_exp_rom");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          exp_rom_base = uvm_reg_field::type_id::create("exp_rom_base");
          exp_rom_base.configure(this, 32, 0, "RW", 0, 32'h0000_0000, 1, 0, 1);
     endfunction
endclass

// DW15 (0x3C): Bridge Control | Interrupt Pin | Interrupt Line
class reg_bridge_ctrl_int extends uvm_reg;
     rand uvm_reg_field interrupt_line;
     rand uvm_reg_field interrupt_pin;
     rand uvm_reg_field bridge_control;
     `uvm_object_utils(reg_bridge_ctrl_int)

     function new(string name = "reg_bridge_ctrl_int");
          super.new(name, 32, UVM_NO_COVERAGE);
     endfunction

     virtual function void build();
          interrupt_line = uvm_reg_field::type_id::create("interrupt_line");
          interrupt_pin  = uvm_reg_field::type_id::create("interrupt_pin");
          bridge_control = uvm_reg_field::type_id::create("bridge_control");
          interrupt_line.configure(this, 8, 0, "RW", 0, 8'h00, 1, 0, 1);
          interrupt_pin.configure(this, 8, 8, "RO", 0, 8'h00, 1, 0, 1);
          bridge_control.configure(this, 16, 16, "RW", 0, 16'h0000, 1, 0, 1);
     endfunction
endclass

// TYPE1 CONFIGURATION SPACE REG_BLOCK
class pcie_type1_cfg_reg_block extends uvm_reg_block;

     reg_vendor_device_id1 vendor_device_id;  // 0x00
     reg_command_status1   command_status;  // 0x04
     reg_class_rev         class_rev;  // 0x08
     reg_bist_hdr_lat_cls1 bist_hdr_lat_cls;  // 0x0C
     reg_bar1              bar0;  // 0x10
     reg_bar1              bar1;  // 0x14
     reg_bus_numbers       bus_numbers;  // 0x18
     reg_io_base_limit     io_base_limit;  // 0x1C
     reg_mem_base_limit    mem_base_limit;  // 0x20
     reg_pf_mem_base_limit pf_mem_base_limit;  // 0x24
     reg_pf_upper32        pf_base_upper32;  // 0x28
     reg_pf_upper32        pf_limit_upper32;  // 0x2C
     reg_io_upper16        io_upper16;  // 0x30
     reg_cap_ptr           cap_ptr;  // 0x34
     reg_exp_rom           exp_rom;  // 0x38
     reg_bridge_ctrl_int   bridge_ctrl_int;  // 0x3C

     `uvm_object_utils(pcie_type1_cfg_reg_block)

     function new(string name = "pcie_type1_cfg_reg_block");
          super.new(name, build_coverage(UVM_NO_COVERAGE));
     endfunction

     virtual function void build();
          default_map       = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN);

          vendor_device_id  = reg_vendor_device_id1::type_id::create("vendor_device_id");
          command_status    = reg_command_status1::type_id::create("command_status");
          class_rev         = reg_class_rev::type_id::create("class_rev");
          bist_hdr_lat_cls  = reg_bist_hdr_lat_cls1::type_id::create("bist_hdr_lat_cls");
          bar0              = reg_bar1::type_id::create("bar0");
          bar1              = reg_bar1::type_id::create("bar1");
          bus_numbers       = reg_bus_numbers::type_id::create("bus_numbers");
          io_base_limit     = reg_io_base_limit::type_id::create("io_base_limit");
          mem_base_limit    = reg_mem_base_limit::type_id::create("mem_base_limit");
          pf_mem_base_limit = reg_pf_mem_base_limit::type_id::create("pf_mem_base_limit");
          pf_base_upper32   = reg_pf_upper32::type_id::create("pf_base_upper32");
          pf_limit_upper32  = reg_pf_upper32::type_id::create("pf_limit_upper32");
          io_upper16        = reg_io_upper16::type_id::create("io_upper16");
          cap_ptr           = reg_cap_ptr::type_id::create("cap_ptr");
          exp_rom           = reg_exp_rom::type_id::create("exp_rom");
          bridge_ctrl_int   = reg_bridge_ctrl_int::type_id::create("bridge_ctrl_int");

          vendor_device_id.configure(this);
          vendor_device_id.build();
          command_status.configure(this);
          command_status.build();
          class_rev.configure(this);
          class_rev.build();
          bist_hdr_lat_cls.configure(this);
          bist_hdr_lat_cls.build();
          bar0.configure(this);
          bar0.build();
          bar1.configure(this);
          bar1.build();
          bus_numbers.configure(this);
          bus_numbers.build();
          io_base_limit.configure(this);
          io_base_limit.build();
          mem_base_limit.configure(this);
          mem_base_limit.build();
          pf_mem_base_limit.configure(this);
          pf_mem_base_limit.build();
          pf_base_upper32.configure(this);
          pf_base_upper32.build();
          pf_limit_upper32.configure(this);
          pf_limit_upper32.build();
          io_upper16.configure(this);
          io_upper16.build();
          cap_ptr.configure(this);
          cap_ptr.build();
          exp_rom.configure(this);
          exp_rom.build();
          bridge_ctrl_int.configure(this);
          bridge_ctrl_int.build();

          default_map.add_reg(vendor_device_id, 32'h00, "RW");
          default_map.add_reg(command_status, 32'h04, "RW");
          default_map.add_reg(class_rev, 32'h08, "RW");
          default_map.add_reg(bist_hdr_lat_cls, 32'h0C, "RW");
          default_map.add_reg(bar0, 32'h10, "RW");
          default_map.add_reg(bar1, 32'h14, "RW");
          default_map.add_reg(bus_numbers, 32'h18, "RW");
          default_map.add_reg(io_base_limit, 32'h1C, "RW");
          default_map.add_reg(mem_base_limit, 32'h20, "RW");
          default_map.add_reg(pf_mem_base_limit, 32'h24, "RW");
          default_map.add_reg(pf_base_upper32, 32'h28, "RW");
          default_map.add_reg(pf_limit_upper32, 32'h2C, "RW");
          default_map.add_reg(io_upper16, 32'h30, "RW");
          default_map.add_reg(cap_ptr, 32'h34, "RW");
          default_map.add_reg(exp_rom, 32'h38, "RW");
          default_map.add_reg(bridge_ctrl_int, 32'h3C, "RW");

          lock_model();
     endfunction
endclass
