//=========================================================
// pcie_ral_seq_lib.sv
//
// uvm_reg_sequence library for pcie_type0_cfg_reg_block
// (reg_block.sv). Follows the pcie_ral_base_seq pattern:
// UVM hands every uvm_reg_sequence a generic `model` handle
// (of type uvm_reg_block); we $cast it down to our specific
// pcie_type0_cfg_reg_block so field-level access is available.
//=========================================================

class pcie_ral_base_seq extends uvm_reg_sequence #(uvm_sequence #(seq_item_apb_master));
  `uvm_object_utils(pcie_ral_base_seq)

  pcie_type0_cfg_reg_block regmodel;

  function new(string name = "pcie_ral_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    if (!$cast(regmodel, model))
      `uvm_fatal("RAL_SEQ", "model handle is not a pcie_type0_cfg_reg_block")
  endtask
endclass


//=========================================================
// 1) Read-Only register check
//    Reads every fully-RO register and confirms the value
//    matches the reset value defined in build(). Also
//    attempts a write to confirm hardware ignores it.
//=========================================================
class pcie_cfg_ro_check_seq extends pcie_ral_base_seq;
  `uvm_object_utils(pcie_cfg_ro_check_seq)

  function new(string name = "pcie_cfg_ro_check_seq");
    super.new(name);
  endfunction

  task body();
    uvm_status_e   status;
    uvm_reg_data_t rdata, expected;

    super.body();

    // Vendor/Device ID
    regmodel.vendor_device_id.read(status, rdata, .map(regmodel.default_map));
    expected = regmodel.vendor_device_id.get_reset();
    if (rdata !== expected)
      `uvm_error("RO_CHECK", $sformatf("vendor_device_id mismatch: got 0x%08h exp 0x%08h", rdata, expected))

    regmodel.vendor_device_id.write(status, 32'hFFFF_FFFF, .map(regmodel.default_map));
    regmodel.vendor_device_id.read(status, rdata, .map(regmodel.default_map));
    if (rdata !== expected)
      `uvm_error("RO_CHECK", "vendor_device_id changed after write — should be RO")

    // Class Code / Rev ID
    regmodel.classcode_revid.read(status, rdata, .map(regmodel.default_map));
    expected = regmodel.classcode_revid.get_reset();
    if (rdata !== expected)
      `uvm_error("RO_CHECK", $sformatf("classcode_revid mismatch: got 0x%08h exp 0x%08h", rdata, expected))

    // Capabilities pointer
    regmodel.cap_pointer.read(status, rdata, .map(regmodel.default_map));
    expected = regmodel.cap_pointer.get_reset();
    if (rdata !== expected)
      `uvm_error("RO_CHECK", $sformatf("cap_pointer mismatch: got 0x%08h exp 0x%08h", rdata, expected))

    // Subsystem ID
    regmodel.subsystem_id.read(status, rdata, .map(regmodel.default_map));
    expected = regmodel.subsystem_id.get_reset();
    if (rdata !== expected)
      `uvm_error("RO_CHECK", $sformatf("subsystem_id mismatch: got 0x%08h exp 0x%08h", rdata, expected))

    // CardBus CIS pointer
    regmodel.cardbus_cis.read(status, rdata, .map(regmodel.default_map));
    expected = regmodel.cardbus_cis.get_reset();
    if (rdata !== expected)
      `uvm_error("RO_CHECK", $sformatf("cardbus_cis mismatch: got 0x%08h exp 0x%08h", rdata, expected))

    `uvm_info("RO_CHECK", "Read-only register check complete", UVM_LOW)
  endtask
endclass


//=========================================================
// 2) Standard PCI/PCIe BAR sizing sequence
//    Write all-1's, read back, decode aperture size from the
//    returned pattern, then restore the original value.
//
//    NOTE: only bar0, bar1, bar2, bar4, bar5 are modeled in
//    reg_block.sv. BAR3 (DW 0x07) is deliberately NOT present
//    in pcie_type0_cfg_reg_block — RX_PCIe_LUT configures it
//    as an IO-space BAR (configure_bar(3, .is_io(1), ...)),
//    which has a completely different bit layout (bit0 fixed
//    to 1, bits[31:2]=address, no type/prefetch fields) and
//    isn't safe to size with this memory-BAR algorithm. If a
//    reg_bar_io class + bar3 handle gets added to the reg
//    block, add a dedicated size_one_io_bar() task for it
//    rather than reusing this one.
//=========================================================
class pcie_bar_sizing_seq extends pcie_ral_base_seq;
  `uvm_object_utils(pcie_bar_sizing_seq)

  function new(string name = "pcie_bar_sizing_seq");
    super.new(name);
  endfunction

  // helper: size one memory BAR, return decoded size in bytes
  task automatic size_one_bar(uvm_reg bar_reg, string bar_name);
    uvm_status_e   status;
    uvm_reg_data_t orig_val, size_pattern, decoded_size;

    bar_reg.read(status, orig_val, .map(regmodel.default_map));

    bar_reg.write(status, 32'hFFFF_FFFF, .map(regmodel.default_map));
    bar_reg.read(status, size_pattern, .map(regmodel.default_map));

    // mask off the fixed attribute bits [3:0] (space/type/prefetch);
    // remaining 1's region indicates programmable address bits
    // To clear BAR attribute bits [3:0] (Memory/IO, 32/64-bit, Prefetchable), which are not part of the address mask.
    size_pattern &= 32'hFFFF_FFF0;  //size_pattern = size_pattern & 32'hFFFF_FFF0;

    if (size_pattern == 0)
      `uvm_info("BAR_SIZE", $sformatf("%s: not implemented / size 0", bar_name), UVM_LOW) // Indicates bar size is not implemented
    else begin
      decoded_size = (~size_pattern) + 1;
      `uvm_info("BAR_SIZE", $sformatf("%s: aperture size = 0x%08h (%0d bytes)",
                 bar_name, decoded_size, decoded_size), UVM_LOW)
    end

    // restore original programmed address
    bar_reg.write(status, orig_val, .map(regmodel.default_map));
  endtask

  task body();
    super.body();
    size_one_bar(regmodel.bar0, "BAR0");
    size_one_bar(regmodel.bar1, "BAR1");
    size_one_bar(regmodel.bar2, "BAR2");
    // BAR3 skipped intentionally — IO BAR, not modeled in regmodel
    size_one_bar(regmodel.bar4, "BAR4");
    size_one_bar(regmodel.bar5, "BAR5");
  endtask
endclass


//=========================================================
// 3) Command/Status register test
//    - Sets enable bits in Command (RW)
//    - Confirms RO status bits (fast_b2b_capable etc.) can't
//      be written
//    - Exercises W1C behavior: write 1 to a status error bit
//      and confirm it reads back 0 (self-clearing on write-1,
//      per reg_command_status field config in reg_block.sv)
//=========================================================
class pcie_command_status_rw1c_seq extends pcie_ral_base_seq;
  `uvm_object_utils(pcie_command_status_rw1c_seq)

  function new(string name = "pcie_command_status_rw1c_seq");
    super.new(name);
  endfunction

  task body();
    uvm_status_e   status;
    uvm_reg_data_t rdata;

    super.body();

    // Enable bus master + memory space via individual fields
    regmodel.command_status.bus_master_enable.set(1'b1);
  regmodel.command_status.memory_space_enable.set(1'b1);
regmodel.command_status.update(status, .map(regmodel.default_map)); 
  
  
    regmodel.command_status.read(status, rdata, .map(regmodel.default_map));
    if (rdata[2] !== 1'b1 || rdata[1] !== 1'b1)
      `uvm_error("CMD_STATUS", "bus_master_enable/memory_space_enable did not set as expected")

    // Confirm RO status field can't be forced via RAL write
    regmodel.command_status.fast_b2b_capable.write(status, 1'b1, .map(regmodel.default_map));
    regmodel.command_status.fast_b2b_capable.read(status, rdata, .map(regmodel.default_map));
    if (rdata !== 1'b0)
      `uvm_error("CMD_STATUS", "fast_b2b_capable (RO) changed via write — should be ignored")

    // W1C pattern: writing 1 clears the bit (uvm_reg_field configured
    // with access "W1C" auto-models this — no backdoor force needed).
    regmodel.command_status.detected_parity_error.write(status, 1'b1, .map(regmodel.default_map));
    regmodel.command_status.detected_parity_error.read(status, rdata, .map(regmodel.default_map));
    if (rdata !== 1'b0)
      `uvm_error("CMD_STATUS", "detected_parity_error did not clear after write-1 (W1C)")

    regmodel.command_status.signaled_target_abort.write(status, 1'b1, .map(regmodel.default_map));
    regmodel.command_status.signaled_target_abort.read(status, rdata, .map(regmodel.default_map));
    if (rdata !== 1'b0)
      `uvm_error("CMD_STATUS", "signaled_target_abort did not clear after write-1 (W1C)")

    `uvm_info("CMD_STATUS", "Command/Status register test complete", UVM_LOW)
  endtask
endclass


//=========================================================
// 4) Top-level virtual sequence — runs the full suite, plus
//    UVM's built-in reset/access sequences for free coverage
//    of every register in the map.
//=========================================================
class pcie_cfg_full_ral_seq extends pcie_ral_base_seq;
  `uvm_object_utils(pcie_cfg_full_ral_seq)

  function new(string name = "pcie_cfg_full_ral_seq");
    super.new(name);
  endfunction

  task body();
    pcie_cfg_ro_check_seq        ro_seq;
    pcie_bar_sizing_seq          bar_seq;
    pcie_command_status_rw1c_seq cmd_seq;
    uvm_reg_hw_reset_seq         reset_seq;
    uvm_reg_access_seq           access_seq;

    super.body();

    // built-in: Reads every register and compares it with get_reset() from the RAL model
    reset_seq = uvm_reg_hw_reset_seq::type_id::create("reset_seq"); 
    reset_seq.model = regmodel;
    reset_seq.start(null);

    // built-in: generic RW/RO access-policy check across the whole map
    access_seq = uvm_reg_access_seq::type_id::create("access_seq");
    access_seq.model = regmodel;
    access_seq.start(null);

    // directed sequences
    ro_seq = pcie_cfg_ro_check_seq::type_id::create("ro_seq");
    ro_seq.model = regmodel;
    ro_seq.start(null);

    bar_seq = pcie_bar_sizing_seq::type_id::create("bar_seq");
    bar_seq.model = regmodel;
    bar_seq.start(null);

    cmd_seq = pcie_command_status_rw1c_seq::type_id::create("cmd_seq");
    cmd_seq.model = regmodel;
    cmd_seq.start(null);

    `uvm_info("PCIE_CFG_SEQ", "Full PCIe config-space RAL sequence complete", UVM_LOW)
  endtask
endclass
