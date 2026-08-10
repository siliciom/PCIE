//-----------------------------------------------------------------------------
// PCIe_Cfg_Space_Model
//
//   Register-address-indexed (DW granularity, matches this project's
//   {ext_register_num[3:0], register_num[5:0]} 10-bit addressing) memory
//   model for a Gen3 endpoint Function's config space:
//
//     0x000 - 0x03F : PCI-compatible Type0 header
//     0x040 - 0x07F : PCI Express Capability structure  (cap id 0x10)
//     0x100 - 0x12F : AER Extended Capability            (ecap id 0x0001)
//     t way: read_reg()/write_reg() both take
//     the 10-bit dw_addr.
//-----------------------------------------------------------------------------
class PCIe_Cfg_Space_Model extends uvm_object;

  `uvm_object_utils(PCIe_Cfg_Space_Model)

  // ---- backing store: 1024 DW = 4KB extended config space -----------------
  bit [31:0] cfg_mem [0:1023];

  // Read-only bit mask per dw_addr. 1 = bit is RO (writes to it are dropped).
  // Anything not entered here defaults to fully read/write.
  bit [31:0] ro_mask [int];

  // ---- BAR bookkeeping (drives 3DW vs 4DW fmt decision on the RC side) ----
  localparam int NUM_BAR = 6;
  bit [31:0] bar_val   [NUM_BAR];   // current programmed value (post-mask)
  bit        bar_is_64 [NUM_BAR];   // bit set on the LOW dword of a 64b pair
  bit        bar_is_io [NUM_BAR];
  bit        bar_used  [NUM_BAR];   // 0 = unimplemented BAR (stays all-0 on sizing)
  bit [31:0] bar_size_mask[NUM_BAR]; // e.g. 32'hFFF0_0000 for a 1MB BAR

  // ---- DW addresses (constants), byte offset = addr*4 ---------------------
  localparam int DW_VID_DID        = 'h00;
  localparam int DW_CMD_STAT       = 'h01;
  localparam int DW_CLASS_REV      = 'h02;
  localparam int DW_BIST_HDR_LAT_CL= 'h03;
  localparam int DW_BAR0           = 'h04; // BAR0..BAR5 = 'h04..'h09
  localparam int DW_SUBSYS         = 'h0B;
  localparam int DW_EXP_ROM        = 'h0C;
  localparam int DW_CAP_PTR        = 'h0D;
  localparam int DW_INT_LINE_PIN   = 'h0F;
  
  extern function void init();
  extern function bit [31:0] read_reg(bit [9:0] dw_addr);
  extern function void write_reg(bit [9:0] dw_addr, bit [31:0] wdata, bit [3:0] be = 4'hF);
  extern function bit [31:0] apply_be(bit [31:0] old_data, bit [31:0] new_data, bit [3:0] be);
  extern function void configure_bar(int bar_num, bit is_io, bit is_64bit, bit [31:0] size_mask, bit used = 1);
  extern function void handle_bar_write(int bar_num, bit [31:0] wdata);
 /* extern function fmt_e decide_mem_fmt(int bar_num);
  extern function bit is_bar_64(int bar_num);*/
 
  function new(string name = "PCIe_Cfg_Space_Model");
    super.new(name);
  endfunction

endclass : PCIe_Cfg_Space_Model


//-----------------------------------------------------------------------------
// init() - lay out Type0 header + PCIe cap + AER + VC, wire the capability
// linked lists, mark which bits are read-only.
//-----------------------------------------------------------------------------
function void PCIe_Cfg_Space_Model::init();

  foreach(cfg_mem[i]) cfg_mem[i] = 32'h0000_0000;
  ro_mask.delete();

  //------------------------------------------------------------------
  // Type0 header (0x00 - 0x3F)
  //------------------------------------------------------------------
  cfg_mem[DW_VID_DID]         = 32'h1234_5678; // [15:0] Vendor ID, [31:16] Device ID
  ro_mask[DW_VID_DID]         = 32'hFFFF_FFFF;

  cfg_mem[DW_CMD_STAT]        = 32'h0010_0000; // Command=0, Status[19]=Cap List present
  ro_mask[DW_CMD_STAT]        = 32'hFFF8_0000; // status RW1C/RO bits mostly RO here; command RW

  cfg_mem[DW_CLASS_REV]       = 32'h0200_0001; // Class=Network ctrlr(020000), Rev=01
  ro_mask[DW_CLASS_REV]       = 32'hFFFF_FFFF;

  cfg_mem[DW_BIST_HDR_LAT_CL] = 32'h0000_0000; // Header Type=0 (single function, non-bridge)
  ro_mask[DW_BIST_HDR_LAT_CL] = 32'hFFFF_00FF; // header type + BIST RO, cache line/lat timer RW

  // BAR0-5 start at 0 (unimplemented) until configure_bar()/handle_bar_write()
  for (int i = 0; i < NUM_BAR; i++) begin
    cfg_mem[DW_BAR0+i] = 32'h0000_0000;
    bar_val[i]         = 32'h0;
    bar_is_64[i]       = 0;
    bar_is_io[i]       = 0;
    bar_used[i]        = 0;
    bar_size_mask[i]   = 32'hFFFF_FFFF; // unimplemented => sizing write reads back 0
  end

  cfg_mem[DW_SUBSYS]   = 32'h0000_0000;
  cfg_mem[DW_EXP_ROM]  = 32'h0000_0000;

  cfg_mem[DW_CAP_PTR]  = 32'h0000_0040;      // points to PCIe Cap @ byte 0x40
  ro_mask[DW_CAP_PTR]  = 32'hFFFF_FFFF;

  cfg_mem[DW_INT_LINE_PIN] = 32'h0000_0100;  // INTA#, no legacy interrupt line assigned yet
  ro_mask[DW_INT_LINE_PIN] = 32'hFFFF_FE00;  // int pin/max_lat/min_gnt RO, int line RW

  
endfunction


//-----------------------------------------------------------------------------
// read_reg / write_reg - the single choke point every CFG_RD0/1 and
// CFG_WR0/1 in RX_PCIe_LUT should go through (dw_addr = {ext_register_num,
// register_num}, exactly as already built in cfg_write()).
//-----------------------------------------------------------------------------
function bit [31:0] PCIe_Cfg_Space_Model::read_reg(bit [9:0] dw_addr);
  return cfg_mem[dw_addr];
endfunction

function void PCIe_Cfg_Space_Model::write_reg(bit [9:0] dw_addr, bit [31:0] wdata, bit [3:0] be);

  bit [31:0] merged;
  bit [31:0] mask;

  mask   = ro_mask.exists(dw_addr) ? ro_mask[dw_addr] : 32'h0000_0000;
  merged = apply_be(cfg_mem[dw_addr], wdata, be);

  // preserve RO bits from the old value, take new value only where writable
  cfg_mem[dw_addr] = (cfg_mem[dw_addr] & mask) | (merged & ~mask);

  // BAR writes need the sizing/decode side-effects, not a plain store
  if (dw_addr inside {[DW_BAR0 : DW_BAR0+NUM_BAR-1]})
    handle_bar_write(dw_addr - DW_BAR0, wdata);

endfunction

function bit [31:0] PCIe_Cfg_Space_Model::apply_be(bit [31:0] old_data, bit [31:0] new_data, bit [3:0] be);
  apply_be = old_data;
  if (be[0]) apply_be[7:0]   = new_data[7:0];
  if (be[1]) apply_be[15:8]  = new_data[15:8];
  if (be[2]) apply_be[23:16] = new_data[23:16];
  if (be[3]) apply_be[31:24] = new_data[31:24];
endfunction

//-----------------------------------------------------------------------------
// BAR configuration / sizing / 3DW-vs-4DW decode
//-----------------------------------------------------------------------------

// Call once (typically from RX_PCIe_LUT::build_phase, right after init())
// to describe the memory/IO window each implemented BAR decodes, e.g.:
//   configure_bar(0, .is_io(0), .is_64bit(0), .size_mask(32'hFFF0_0000)); // 1MB, 32b mem
//   configure_bar(1, .is_io(0), .is_64bit(1), .size_mask(32'hE000_0000)); // 512MB, 64b mem, BAR1/2 pair
//   configure_bar(3, .is_io(1), .is_64bit(0), .size_mask(32'hFFFF_FF00)); // 256B IO
function void PCIe_Cfg_Space_Model::configure_bar(int bar_num, bit is_io, bit is_64bit,
                                                   bit [31:0] size_mask, bit used);
  bar_is_io[bar_num]     = is_io;
  bar_is_64[bar_num]     = is_64bit;
  bar_size_mask[bar_num] = size_mask;
  bar_used[bar_num]      = used;

  // program the type-encoding bits into the "reset" BAR value so a
  // decoded BAR read always reports the right type even before software
  // has done anything:
  //   bit0     : 0=memory, 1=IO
  //   bits[2:1]: 00=32-bit, 10=64-bit  (only meaningful when bit0=0)
  //   bit3     : prefetchable (left 0 here; set explicitly if needed)
  if (!used) begin
    cfg_mem[DW_BAR0+bar_num] = 32'h0;
  end else if (is_io) begin
    cfg_mem[DW_BAR0+bar_num] = 32'h0000_0001;
  end else begin
    cfg_mem[DW_BAR0+bar_num] = is_64bit ? 32'h0000_0004 : 32'h0000_0000;
  end
  bar_val[bar_num] = cfg_mem[DW_BAR0+bar_num];
endfunction

// Implements the standard "size a BAR" behavior a real config-space target
// must provide: a write of all-1s to a BAR returns (on the next read) a
// mask whose cleared low bits reveal the region size; a normal address
// write just stores the aligned base address back.
function void PCIe_Cfg_Space_Model::handle_bar_write(int bar_num, bit [31:0] wdata);

  bit [31:0] type_bits;

  if (!bar_used[bar_num]) begin
    cfg_mem[DW_BAR0+bar_num] = 32'h0; // unimplemented BARs always read back 0
    return;
  end

  type_bits = bar_is_io[bar_num] ? 32'h0000_0001
                                  : (bar_is_64[bar_num] ? 32'h0000_0004 : 32'h0000_0000);

  if (wdata == 32'hFFFF_FFFF) begin
    // sizing probe: report size_mask with the type bits still visible
    cfg_mem[DW_BAR0+bar_num] = (bar_size_mask[bar_num] & ~32'hF) | type_bits;
  end
  else begin
    // normal base-address program: keep it aligned to the BAR's size,
    // re-assert the type bits (they are hardwired, SW can't change them)
    cfg_mem[DW_BAR0+bar_num] = (wdata & bar_size_mask[bar_num] & ~32'hF) | type_bits;
  end

  bar_val[bar_num] = cfg_mem[DW_BAR0+bar_num];

endfunction

