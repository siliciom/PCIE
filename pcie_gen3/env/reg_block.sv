
//=========================================================
// Register : Vendor ID / Device ID
// DW 0x00 - Read Only  (cfg_mem[DW_VID_DID] = 32'h1234_5678)
//=========================================================
class reg_vendor_device_id extends uvm_reg;
  `uvm_object_utils(reg_vendor_device_id)

  uvm_reg_field vendor_id;   // [15:0]
  uvm_reg_field device_id;   // [31:16]

  function new(string name = "reg_vendor_device_id");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    vendor_id = uvm_reg_field::type_id::create("vendor_id");
    vendor_id.configure(this, 16, 0, "RO", 0, 16'h5678, 1, 0, 1);

    device_id = uvm_reg_field::type_id::create("device_id");
    device_id.configure(this, 16, 16, "RO", 0, 16'h1234, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Command / Status
// DW 0x01 - Mixed RW / RO / W1C  (reset 32'h0010_0000, ro_mask 32'hFFF8_0000)
//=========================================================
class reg_command_status extends uvm_reg;
  `uvm_object_utils(reg_command_status)

  rand uvm_reg_field io_space_enable;       // Bit0  RW
  rand uvm_reg_field memory_space_enable;   // Bit1  RW
  rand uvm_reg_field bus_master_enable;     // Bit2  RW
  uvm_reg_field      special_cycle_enable;  // Bit3  RO
  uvm_reg_field      mem_write_inv_enable;  // Bit4  RO
  uvm_reg_field      vga_palette_snoop;     // Bit5  RO
  rand uvm_reg_field parity_error_response; // Bit6  RW
  uvm_reg_field      reserved_cmd0;         // Bit7  RO
  rand uvm_reg_field serr_enable;           // Bit8  RW
  uvm_reg_field      fast_b2b_enable;       // Bit9  RO
  rand uvm_reg_field interrupt_disable;     // Bit10 RW
  uvm_reg_field      reserved_cmd1;         // [15:11] RO

  uvm_reg_field reserved_low;               // [18:16] RO
  uvm_reg_field interrupt_status;           // Bit19 RO
  uvm_reg_field capabilities_list;          // Bit20 RO, reset=1
  uvm_reg_field mhz66_capable;              // Bit21 RO
  uvm_reg_field reserved_status;            // Bit22 RO
  uvm_reg_field fast_b2b_capable;           // Bit23 RO
  uvm_reg_field master_data_parity_error;   // Bit24 W1C
  uvm_reg_field devsel_timing;              // [26:25] RO
  uvm_reg_field signaled_target_abort;      // Bit27 W1C
  uvm_reg_field received_target_abort;      // Bit28 W1C
  uvm_reg_field received_master_abort;      // Bit29 W1C
  uvm_reg_field signaled_system_error;      // Bit30 W1C
  uvm_reg_field detected_parity_error;      // Bit31 W1C

  function new(string name = "reg_command_status");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    io_space_enable = uvm_reg_field::type_id::create("io_space_enable");
    io_space_enable.configure(this, 1, 0, "RW", 0, 0, 1, 0, 1);

    memory_space_enable = uvm_reg_field::type_id::create("memory_space_enable");
    memory_space_enable.configure(this, 1, 1, "RW", 0, 0, 1, 0, 1);

    bus_master_enable = uvm_reg_field::type_id::create("bus_master_enable");
    bus_master_enable.configure(this, 1, 2, "RW", 0, 0, 1, 0, 1);

    special_cycle_enable = uvm_reg_field::type_id::create("special_cycle_enable");
    special_cycle_enable.configure(this, 1, 3, "RO", 0, 0, 1, 0, 1);

    mem_write_inv_enable = uvm_reg_field::type_id::create("mem_write_inv_enable");
    mem_write_inv_enable.configure(this, 1, 4, "RO", 0, 0, 1, 0, 1);

    vga_palette_snoop = uvm_reg_field::type_id::create("vga_palette_snoop");
    vga_palette_snoop.configure(this, 1, 5, "RO", 0, 0, 1, 0, 1);

    parity_error_response = uvm_reg_field::type_id::create("parity_error_response");
    parity_error_response.configure(this, 1, 6, "RW", 0, 0, 1, 0, 1);

    reserved_cmd0 = uvm_reg_field::type_id::create("reserved_cmd0");
    reserved_cmd0.configure(this, 1, 7, "RO", 0, 0, 1, 0, 1);

    serr_enable = uvm_reg_field::type_id::create("serr_enable");
    serr_enable.configure(this, 1, 8, "RW", 0, 0, 1, 0, 1);

    fast_b2b_enable = uvm_reg_field::type_id::create("fast_b2b_enable");
    fast_b2b_enable.configure(this, 1, 9, "RO", 0, 0, 1, 0, 1);

    interrupt_disable = uvm_reg_field::type_id::create("interrupt_disable");
    interrupt_disable.configure(this, 1, 10, "RW", 0, 0, 1, 0, 1);

    reserved_cmd1 = uvm_reg_field::type_id::create("reserved_cmd1");
    reserved_cmd1.configure(this, 5, 11, "RO", 0, 0, 1, 0, 1);

    reserved_low = uvm_reg_field::type_id::create("reserved_low");
    reserved_low.configure(this, 3, 16, "RO", 0, 0, 1, 0, 1);

    interrupt_status = uvm_reg_field::type_id::create("interrupt_status");
    interrupt_status.configure(this, 1, 19, "RO", 1, 0, 1, 0, 1);

    capabilities_list = uvm_reg_field::type_id::create("capabilities_list");
    capabilities_list.configure(this, 1, 20, "RO", 0, 1, 1, 0, 1);

    mhz66_capable = uvm_reg_field::type_id::create("mhz66_capable");
    mhz66_capable.configure(this, 1, 21, "RO", 0, 0, 1, 0, 1);

    reserved_status = uvm_reg_field::type_id::create("reserved_status");
    reserved_status.configure(this, 1, 22, "RO", 0, 0, 1, 0, 1);

    fast_b2b_capable = uvm_reg_field::type_id::create("fast_b2b_capable");
    fast_b2b_capable.configure(this, 1, 23, "RO", 0, 0, 1, 0, 1);

    master_data_parity_error = uvm_reg_field::type_id::create("master_data_parity_error");
    master_data_parity_error.configure(this, 1, 24, "W1C", 1, 0, 1, 0, 1);

    devsel_timing = uvm_reg_field::type_id::create("devsel_timing");
    devsel_timing.configure(this, 2, 25, "RO", 0, 0, 1, 0, 1);

    signaled_target_abort = uvm_reg_field::type_id::create("signaled_target_abort");
    signaled_target_abort.configure(this, 1, 27, "W1C", 1, 0, 1, 0, 1);

    received_target_abort = uvm_reg_field::type_id::create("received_target_abort");
    received_target_abort.configure(this, 1, 28, "W1C", 1, 0, 1, 0, 1);

    received_master_abort = uvm_reg_field::type_id::create("received_master_abort");
    received_master_abort.configure(this, 1, 29, "W1C", 1, 0, 1, 0, 1);

    signaled_system_error = uvm_reg_field::type_id::create("signaled_system_error");
    signaled_system_error.configure(this, 1, 30, "W1C", 1, 0, 1, 0, 1);

    detected_parity_error = uvm_reg_field::type_id::create("detected_parity_error");
    detected_parity_error.configure(this, 1, 31, "W1C", 1, 0, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Class Code / Revision ID
// DW 0x02 - Read Only  (reset 32'h0200_0001)
//=========================================================
class reg_classcode_revid extends uvm_reg;
  `uvm_object_utils(reg_classcode_revid)

  uvm_reg_field revision_id;  // [7:0]
  uvm_reg_field prog_if;      // [15:8]
  uvm_reg_field sub_class;    // [23:16]
  uvm_reg_field base_class;   // [31:24]

  function new(string name = "reg_classcode_revid");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    revision_id = uvm_reg_field::type_id::create("revision_id");
    revision_id.configure(this, 8, 0, "RO", 0, 8'h01, 1, 0, 1);

    prog_if = uvm_reg_field::type_id::create("prog_if");
    prog_if.configure(this, 8, 8, "RO", 0, 8'h00, 1, 0, 1);

    sub_class = uvm_reg_field::type_id::create("sub_class");
    sub_class.configure(this, 8, 16, "RO", 0, 8'h00, 1, 0, 1);

    base_class = uvm_reg_field::type_id::create("base_class");
    base_class.configure(this, 8, 24, "RO", 0, 8'h02, 1, 0, 1);   // matches cfg_model (Network ctrlr = 0x02)
  endfunction
endclass


//=========================================================
// Register : BIST / Header Type / Latency Timer / Cache Line
// DW 0x03 - reset 32'h0000_0000, ro_mask 32'hFFFF_00FF
//=========================================================
class reg_bist_hdr_lat_cache extends uvm_reg;
  `uvm_object_utils(reg_bist_hdr_lat_cache)

  rand uvm_reg_field cache_line_size;  // [7:0]   RW
  uvm_reg_field      latency_timer;    // [15:8]  RO
  uvm_reg_field      header_type;      // [22:16] RO
  uvm_reg_field      mfd;              // Bit23   RO
  rand uvm_reg_field bist_code;        // [27:24] RO
  uvm_reg_field      bist_reserved;    // Bit28   RO
  rand uvm_reg_field bist_start;       // Bit30   RW
  uvm_reg_field      bist_capable;     // Bit31   RO

  function new(string name = "reg_bist_hdr_lat_cache");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    cache_line_size = uvm_reg_field::type_id::create("cache_line_size");
    cache_line_size.configure(this, 8, 0, "RW", 0, 8'h00, 1, 0, 1);

    latency_timer = uvm_reg_field::type_id::create("latency_timer");
    latency_timer.configure(this, 8, 8, "RO", 0, 8'h00, 1, 0, 1);

    header_type = uvm_reg_field::type_id::create("header_type");
    header_type.configure(this, 7, 16, "RO", 0, 7'h00, 1, 0, 1);

    mfd = uvm_reg_field::type_id::create("mfd");
    mfd.configure(this, 1, 23, "RO", 0, 1'h0, 1, 0, 1);

    bist_code = uvm_reg_field::type_id::create("bist_code");
    bist_code.configure(this, 4, 24, "RO", 1, 4'h0, 1, 0, 1);

    bist_reserved = uvm_reg_field::type_id::create("bist_reserved");
    bist_reserved.configure(this, 1, 28, "RO", 0, 1'h0, 1, 0, 1);

    bist_start = uvm_reg_field::type_id::create("bist_start");
    bist_start.configure(this, 1, 30, "RW", 0, 1'h0, 1, 0, 1);

    bist_capable = uvm_reg_field::type_id::create("bist_capable");
    bist_capable.configure(this, 1, 31, "RO", 0, 1'h0, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Base Address Register (BAR) - memory-space variant
// Used for BAR0, BAR1, BAR2, BAR4, BAR5 (DW 0x04-0x06, 0x08-0x09)
//
// NOTE: BAR3 (DW 0x07) is configured as an IO-space BAR by
// RX_PCIe_LUT (configure_bar(3, .is_io(1), ...)). An IO BAR has a
// totally different bit layout (bit0=1 fixed, bits[31:2]=address,
// no type/prefetchable fields) and does NOT belong in this class.
// A separate reg_bar_io class should be used for BAR3 if you need
// RAL coverage of it -- ask if you want that written too.
//
// Reset values below are per-instance overrides applied in
// pcie_type0_cfg_reg_block::build(), matching exactly what
// configure_bar() programs for each BAR:
//   BAR0: memory, 32-bit  -> reset 0x0
//   BAR1: memory, 64-bit  -> reset 0x4
//   BAR2: memory, 32-bit  -> reset 0x0
//   BAR4, BAR5: unused    -> reset 0x0
//=========================================================
class reg_bar extends uvm_reg;
  `uvm_object_utils(reg_bar)

  uvm_reg_field      space_indicator;  // Bit0     RO, always 0 for memory BAR
  uvm_reg_field      bar_type;         // [2:1]    RO
  uvm_reg_field      prefetchable;     // Bit3     RO
  rand uvm_reg_field base_addr;        // [31:4]   RW

  function new(string name = "reg_bar");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    space_indicator = uvm_reg_field::type_id::create("space_indicator");
    space_indicator.configure(this, 1, 0, "RO", 0, 1'h0, 1, 0, 1);

    bar_type = uvm_reg_field::type_id::create("bar_type");
    bar_type.configure(this, 2, 1, "RO", 0, 2'b00, 1, 0, 1);   // default 32-bit; overridden per-instance below

    prefetchable = uvm_reg_field::type_id::create("prefetchable");
    prefetchable.configure(this, 1, 3, "RO", 0, 1'h0, 1, 0, 1); // cfg_model never sets this bit

    base_addr = uvm_reg_field::type_id::create("base_addr");
    base_addr.configure(this, 28, 4, "RW", 0, 28'h0, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : CardBus CIS Pointer
// DW 0x0A - Read Only, reset 0
//=========================================================
class reg_cardbus_cis extends uvm_reg;
  `uvm_object_utils(reg_cardbus_cis)

  uvm_reg_field cis_ptr;

  function new(string name = "reg_cardbus_cis");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    cis_ptr = uvm_reg_field::type_id::create("cis_ptr");
    cis_ptr.configure(this, 32, 0, "RO", 0, 32'h0000_0000, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Subsystem Vendor ID / Subsystem ID
// DW 0x0B - reset 32'h0000_0000 in cfg_model (never explicitly set)
//=========================================================
class reg_subsystem_id extends uvm_reg;
  `uvm_object_utils(reg_subsystem_id)

  uvm_reg_field subsystem_vendor_id;
  uvm_reg_field subsystem_id;

  function new(string name = "reg_subsystem_id");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    subsystem_vendor_id = uvm_reg_field::type_id::create("subsystem_vendor_id");
    subsystem_vendor_id.configure(this, 16, 0, "RO", 0, 16'h0000, 1, 0, 1);

    subsystem_id = uvm_reg_field::type_id::create("subsystem_id");
    subsystem_id.configure(this, 16, 16, "RO", 0, 16'h0000, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Expansion ROM Base Address
// DW 0x0C - reset 0 (no ro_mask entry -> fully RW in cfg_model)
//=========================================================
class reg_exp_rom_bar extends uvm_reg;
  `uvm_object_utils(reg_exp_rom_bar)

  rand uvm_reg_field rom_enable;
  uvm_reg_field      reserved_rom;
  rand uvm_reg_field rom_base_addr;

  function new(string name = "reg_exp_rom_bar");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rom_enable = uvm_reg_field::type_id::create("rom_enable");
    rom_enable.configure(this, 1, 0, "RW", 0, 1'h0, 1, 0, 1);

    reserved_rom = uvm_reg_field::type_id::create("reserved_rom");
    reserved_rom.configure(this, 10, 1, "RW", 0, 10'h0, 1, 0, 1);

    rom_base_addr = uvm_reg_field::type_id::create("rom_base_addr");
    rom_base_addr.configure(this, 21, 11, "RW", 0, 21'h0, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Capabilities Pointer
// DW 0x0D - Read Only, reset 32'h0000_0040
//=========================================================
class reg_cap_pointer extends uvm_reg;
  `uvm_object_utils(reg_cap_pointer)

  uvm_reg_field cap_ptr;      // [7:0]
  uvm_reg_field reserved_1;   // [31:8]

  function new(string name = "reg_cap_pointer");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    cap_ptr = uvm_reg_field::type_id::create("cap_ptr");
    cap_ptr.configure(this, 8, 0, "RO", 0, 8'h40, 1, 0, 1);

    reserved_1 = uvm_reg_field::type_id::create("reserved_1");
    reserved_1.configure(this, 24, 8, "RO", 0, 24'h0, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Reserved (DW 0x0E, byte 0x38)
//=========================================================
class reg_reserved_38 extends uvm_reg;
  `uvm_object_utils(reg_reserved_38)

  uvm_reg_field reserved;

  function new(string name = "reg_reserved_38");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    reserved = uvm_reg_field::type_id::create("reserved");
    reserved.configure(this, 32, 0, "RO", 0, 32'h0, 1, 0, 1);
  endfunction
endclass


//=========================================================
// Register : Interrupt Line / Pin / Min_Gnt / Max_Lat
// DW 0x0F - reset 32'h0000_0100, ro_mask 32'hFFFF_FE00
//=========================================================
class reg_interrupt extends uvm_reg;
  `uvm_object_utils(reg_interrupt)

  rand uvm_reg_field interrupt_line;  // [7:0]   RW
  uvm_reg_field      interrupt_pin;   // [15:8]  RO
  uvm_reg_field      min_gnt;         // [23:16] RO
  uvm_reg_field      max_lat;         // [31:24] RO

  function new(string name = "reg_interrupt");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    interrupt_line = uvm_reg_field::type_id::create("interrupt_line");
    interrupt_line.configure(this, 8, 0, "RW", 0, 8'h00, 1, 0, 1);   // cfg_mem[DW_INT_LINE_PIN][7:0] = 0x00

    interrupt_pin = uvm_reg_field::type_id::create("interrupt_pin");
    interrupt_pin.configure(this, 8, 8, "RO", 0, 8'h01, 1, 0, 1);    // INTA#

    min_gnt = uvm_reg_field::type_id::create("min_gnt");
    min_gnt.configure(this, 8, 16, "RO", 0, 8'h00, 1, 0, 1);

    max_lat = uvm_reg_field::type_id::create("max_lat");
    max_lat.configure(this, 8, 24, "RO", 0, 8'h00, 1, 0, 1);
  endfunction
endclass

//=========================================================
// REG BLOCK : PCIe Type 0 Configuration Header + PCIe Capability
//=========================================================
class pcie_type0_cfg_reg_block extends uvm_reg_block;
  `uvm_object_utils(pcie_type0_cfg_reg_block)

  //--------------------------------------
  // Type0 header (DW 0x00 - 0x0F)
  //--------------------------------------
  rand reg_vendor_device_id    vendor_device_id;   // DW 0x00
  rand reg_command_status      command_status;     // DW 0x01
  rand reg_classcode_revid     classcode_revid;    // DW 0x02
  rand reg_bist_hdr_lat_cache  bist_hdr;           // DW 0x03
  rand reg_bar                 bar0;               // DW 0x04
  rand reg_bar                 bar1;               // DW 0x05
  rand reg_bar                 bar2;               // DW 0x06
  // BAR3 (DW 0x07) intentionally not modeled here -- it's an IO BAR,
  // see the note above reg_bar. Add reg_bar_io + bar3 handle if needed.
  rand reg_bar                 bar4;               // DW 0x08
  rand reg_bar                 bar5;               // DW 0x09
       reg_cardbus_cis         cardbus_cis;        // DW 0x0A
       reg_subsystem_id        subsystem_id;       // DW 0x0B
  rand reg_exp_rom_bar         exp_rom_bar;        // DW 0x0C
       reg_cap_pointer         cap_pointer;        // DW 0x0D
       reg_reserved_38         reserved_38;        // DW 0x0E
  rand reg_interrupt           interrupt_reg;      // DW 0x0F


   uvm_reg_map default_map;

  function new(string name = "pcie_type0_cfg_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction



  virtual function void build();

    //--------------------------------------
    // Type0 header
    //--------------------------------------
    vendor_device_id = reg_vendor_device_id::type_id::create("vendor_device_id");
    vendor_device_id.configure(this); vendor_device_id.build();

    command_status = reg_command_status::type_id::create("command_status");
    command_status.configure(this); command_status.build();

    classcode_revid = reg_classcode_revid::type_id::create("classcode_revid");
    classcode_revid.configure(this); classcode_revid.build();

    bist_hdr = reg_bist_hdr_lat_cache::type_id::create("bist_hdr");
    bist_hdr.configure(this); bist_hdr.build();

    // BAR0: memory, 32-bit -> reset 0x0
    bar0 = reg_bar::type_id::create("bar0");
    bar0.configure(this); bar0.build();
    bar0.bar_type.set_reset(2'b00);
    bar0.prefetchable.set_reset(1'b0);

    // BAR1: memory, 64-bit -> reset 0x4
    bar1 = reg_bar::type_id::create("bar1");
    bar1.configure(this); bar1.build();
    bar1.bar_type.set_reset(2'b10);
    bar1.prefetchable.set_reset(1'b0);

    // BAR2: memory, 32-bit -> reset 0x0
    bar2 = reg_bar::type_id::create("bar2");
    bar2.configure(this); bar2.build();
    bar2.bar_type.set_reset(2'b00);
    bar2.prefetchable.set_reset(1'b0);

    // BAR4, BAR5: unused -> reset 0x0
    bar4 = reg_bar::type_id::create("bar4");
    bar4.configure(this); bar4.build();
    bar4.bar_type.set_reset(2'b00);
    bar4.prefetchable.set_reset(1'b0);

    bar5 = reg_bar::type_id::create("bar5");
    bar5.configure(this); bar5.build();
    bar5.bar_type.set_reset(2'b00);
    bar5.prefetchable.set_reset(1'b0);

    cardbus_cis = reg_cardbus_cis::type_id::create("cardbus_cis");
    cardbus_cis.configure(this); cardbus_cis.build();

    subsystem_id = reg_subsystem_id::type_id::create("subsystem_id");
    subsystem_id.configure(this); subsystem_id.build();

    exp_rom_bar = reg_exp_rom_bar::type_id::create("exp_rom_bar");
    exp_rom_bar.configure(this); exp_rom_bar.build();

    cap_pointer = reg_cap_pointer::type_id::create("cap_pointer");
    cap_pointer.configure(this); cap_pointer.build();

    reserved_38 = reg_reserved_38::type_id::create("reserved_38");
    reserved_38.configure(this); reserved_38.build();

    interrupt_reg = reg_interrupt::type_id::create("interrupt_reg");
    interrupt_reg.configure(this); interrupt_reg.build();

   
    //--------------------------------------
    // Create map -- n_bytes=4 => 32-bit DWORD access, byte-addressed
    // (the apb_reg_adapter converts these byte offsets to cfg_model's
    //  DW indices with >>2 / <<2 -- see apb_reg_adapter.sv)
    //--------------------------------------
    default_map = create_map(
      .name            ("default_map"),
      .base_addr       ('h0),
      .n_bytes         (4),
      .endian          (UVM_LITTLE_ENDIAN),
      .byte_addressing (1)
    );

    //--------------------------------------
    // Type0 header -- byte offset = DW*4
    //--------------------------------------
    default_map.add_reg(vendor_device_id, 'h00, "RO");
    default_map.add_reg(command_status,   'h04, "RW");
    default_map.add_reg(classcode_revid,  'h08, "RO");
    default_map.add_reg(bist_hdr,         'h0C, "RW");
    default_map.add_reg(bar0,             'h10, "RW");
    default_map.add_reg(bar1,             'h14, "RW");
    default_map.add_reg(bar2,             'h18, "RW");
    // 'h1C (BAR3) intentionally skipped -- IO BAR, not modeled yet
    default_map.add_reg(bar4,             'h20, "RW");
    default_map.add_reg(bar5,             'h24, "RW");
    default_map.add_reg(cardbus_cis,      'h28, "RO");
    default_map.add_reg(subsystem_id,     'h2C, "RO");
    default_map.add_reg(exp_rom_bar,      'h30, "RW");
    default_map.add_reg(cap_pointer,      'h34, "RO");
    default_map.add_reg(reserved_38,      'h38, "RO");
    default_map.add_reg(interrupt_reg,    'h3C, "RW");

   

    
    lock_model();
  endfunction

endclass
