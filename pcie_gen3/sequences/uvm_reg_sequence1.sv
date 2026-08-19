//=====================================================
// TYPE1 CONFIGURATION SPACE FULL RAL SEQUENCE
//=====================================================
class pcie_type1_cfg_full_ral_seq extends uvm_reg_sequence;

  `uvm_object_utils(pcie_type1_cfg_full_ral_seq)

  pcie_type1_cfg_reg_block regmodel;

  function new(string name = "pcie_type1_cfg_full_ral_seq");
    super.new(name);
  endfunction

  virtual task body();
    uvm_status_e   status;
    uvm_reg_data_t rd_data;
    uvm_reg_data_t wr_data;

    if (regmodel == null)
      `uvm_fatal("RAL_SEQ", "regmodel handle not set before starting sequence")

    // ----------------------------------------------
    // DW00: Vendor ID / Device ID  -> RO, read only
    // ----------------------------------------------
    regmodel.vendor_device_id.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("vendor_device_id = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW01: Command / Status -> Command is RW, Status is W1C
    // ----------------------------------------------
    wr_data = 32'h0000_0007; // example: enable IO/Mem/Bus master in command field
    regmodel.command_status.write(status, wr_data, .parent(this));
    regmodel.command_status.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("command_status readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW02: Class Code / Revision ID -> RO
    // ----------------------------------------------
    regmodel.class_rev.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("class_rev = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW03: BIST / Header Type / Latency Timer / Cache Line Size
    // header_type = RO, bist/latency/cache_line = RW
    // ----------------------------------------------
    wr_data = 32'h0000_0010; // cache_line_size field only, low byte
    regmodel.bist_hdr_lat_cls.write(status, wr_data, .parent(this));
    regmodel.bist_hdr_lat_cls.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("bist_hdr_lat_cls readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW04: Base Address 0 -> RW
    // ----------------------------------------------
    wr_data = 32'hF000_0000;
    regmodel.bar0.write(status, wr_data, .parent(this));
    regmodel.bar0.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("bar0 readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW05: Base Address 1 -> RW
    // ----------------------------------------------
    wr_data = 32'hE000_0000;
    regmodel.bar1.write(status, wr_data, .parent(this));
    regmodel.bar1.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("bar1 readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW06: Secondary Latency Timer / Subordinate Bus / Secondary Bus / Primary Bus -> RW
    // ----------------------------------------------
    wr_data = 32'h0003_0201; // primary=01, secondary=02, subordinate=03
    regmodel.bus_numbers.write(status, wr_data, .parent(this));
    regmodel.bus_numbers.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("bus_numbers readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW07: Secondary Status (W1C) / I/O Limit / I/O Base -> RW
    // ----------------------------------------------
    wr_data = 32'h0000_F0F0;
    regmodel.io_base_limit.write(status, wr_data, .parent(this));
    regmodel.io_base_limit.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("io_base_limit readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW08: Memory Limit / Memory Base -> RW
    // ----------------------------------------------
    wr_data = 32'hFFF0_1000;
    regmodel.mem_base_limit.write(status, wr_data, .parent(this));
    regmodel.mem_base_limit.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("mem_base_limit readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW09: Prefetchable Memory Limit / Base -> RW
    // ----------------------------------------------
    wr_data = 32'hEEE0_2000;
    regmodel.pf_mem_base_limit.write(status, wr_data, .parent(this));
    regmodel.pf_mem_base_limit.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("pf_mem_base_limit readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW10: Prefetchable Base Upper 32-bits -> RW
    // ----------------------------------------------
    wr_data = 32'h0000_0001;
    regmodel.pf_base_upper32.write(status, wr_data, .parent(this));
    regmodel.pf_base_upper32.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("pf_base_upper32 readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW11: Prefetchable Limit Upper 32-bits -> RW
    // ----------------------------------------------
    wr_data = 32'h0000_0002;
    regmodel.pf_limit_upper32.write(status, wr_data, .parent(this));
    regmodel.pf_limit_upper32.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("pf_limit_upper32 readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW12: I/O Limit Upper 16 / I/O Base Upper 16 -> RW
    // ----------------------------------------------
    wr_data = 32'h0020_0010;
    regmodel.io_upper16.write(status, wr_data, .parent(this));
    regmodel.io_upper16.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("io_upper16 readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW13: Reserved / Capabilities Pointer -> RO
    // ----------------------------------------------
    regmodel.cap_ptr.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("cap_ptr = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW14: Expansion ROM Base Address -> RW
    // ----------------------------------------------
    wr_data = 32'hD000_0000;
    regmodel.exp_rom.write(status, wr_data, .parent(this));
    regmodel.exp_rom.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("exp_rom readback = 0x%0h", rd_data), UVM_LOW)

    // ----------------------------------------------
    // DW15: Bridge Control / Interrupt Pin (RO) / Interrupt Line -> RW
    // ----------------------------------------------
    wr_data = 32'h0001_0005;
    regmodel.bridge_ctrl_int.write(status, wr_data, .parent(this));
    regmodel.bridge_ctrl_int.read(status, rd_data, .parent(this));
    `uvm_info("RAL_SEQ", $sformatf("bridge_ctrl_int readback = 0x%0h", rd_data), UVM_LOW)

  endtask
endclass
