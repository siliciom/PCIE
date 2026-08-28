//-----------------------------------------------------------------
// RX_PCIe_LUT
//   Ported from the reference project's RX_PCIe_LUT.sv, adapted
//   to this project's fmt/r_type-based Sequence_item instead of
//   the reference's separate e_type (tlp_type_e) field, which
//   does not exist here. Request-type dispatch is done via the
//   same r_type encodings used by Sequence_item's own
//   constraints (mem_fmt_constraint, io_fmt_constraint,
//   configuration_fmt_constraint, completion_fmt_constraint):
//     r_type 00000/00001 -> Memory Read / Memory Write
//     r_type 00010       -> IO Read (fmt selects rd/wr)
//     r_type 00100       -> Config Type0 Read/Write
//     r_type 00101       -> Config Type1 Read/Write
//   fmt distinguishes read (no data, fmt=000/001) from write
//   (has data, fmt=010/011) within each r_type group.
//
//   Created once per Env_Top instance (inside EP_MODE's TX_TL
//   agent build_phase) and looked up via config_db scoped to
//   that instance - this already works correctly for multiple
//   Env_Top instances with no extra change, since the original
//   Env_Top.sv pattern (uvm_config_db::set(this,"*",...)) scopes
//   to "this" at creation time.
//-----------------------------------------------------------------
class RX_PCIe_LUT extends uvm_component;

  virtual RX_TL_DL_Interface RX_TL_DL;

  uvm_analysis_imp #(Sequence_item, RX_PCIe_LUT) RX_LUT_imp;

  // CHANGED: was `uvm_tlm_fifo #(Sequence_item) cpl_fifo;`
  uvm_analysis_port #(Sequence_item) cpl_ap;

  Tag_Manager tag_mgr;
  FC_Manager fc_mgr;

  int hdr_credit, data_credit;

  localparam int MAX_CPL_BYTES = 128;

  Sequence_item req_q[$];

  bit [31:0] mem_space [longint unsigned];
  bit [31:0] io_space [longint unsigned];

  PCIe_Cfg_Space_Model cfg_model;

  bit [7:0] ep_bus      = 8'h0;
  bit [4:0] ep_device   = 5'h02;
  bit [2:0] ep_function = 3'h0;

  bit [31:0] bar[6];
  bit bar_is_64[6];  

  // Local mirror of the configure_bar() calls made in build_phase -
  // needed here (not just inside cfg_model) so is_addr_supported()
  // can decode base+size for the ERR_UNSUPPORTED_REQ checker
  // without adding new accessors to PCIe_Cfg_Space_Model.
  bit        bar_used[6];
  bit        bar_cfg_is_io[6];
  bit        bar_cfg_is_64[6];
  bit [31:0] bar_cfg_mask[6];

  `uvm_component_utils(RX_PCIe_LUT)

  function new(string name="PCIe_LUT", uvm_component parent=null);
    super.new(name,parent);
    RX_LUT_imp = new("RX_LUT_imp",this);
    // CHANGED: was `cpl_fifo = new("cpl_fifo", this, 32);`
    cpl_ap = new("cpl_ap", this);
  endfunction

  function void write(Sequence_item req);
    req_q.push_back(req);
    `uvm_info("RX_PCIe_LUT", $sformatf("LUT WRITE CALLED, queue size after push = %0d, fmt=%03b r_type=%05b",
                                        req_q.size(), req.fmt, req.r_type), UVM_LOW)
  endfunction

  function void build_phase(uvm_phase phase);
     super.build_phase(phase);

     if(!uvm_config_db #(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))
        `uvm_fatal("SEQ","Cannot get Tag Manager")

      if(!uvm_config_db #(FC_Manager)::get(this, "", "fc_mgr", fc_mgr))
        `uvm_fatal("RX_PCIe_LUT", "Cannot get FC_Manager")

     if(!uvm_config_db #(PCIe_Cfg_Space_Model)::get(this, "", "cfg_model", cfg_model))
        `uvm_fatal("RX_PCIe_LUT", "Cannot get shared PCIe_Cfg_Space_Model (cfg_model) from Env_Top")

      `uvm_info("RX_PCIe_LUT", $sformatf("Using shared cfg_model: cfg[0]=%08h cfg[BAR0]=%08h", cfg_model.read_reg(10'h0), cfg_model.read_reg(10'h4)), UVM_NONE)
      

            // Mirror the same 4 configure_bar() calls locally so
      // is_addr_supported() below can decode base/size per-BAR.
      bar_used[0] = 1; bar_cfg_is_io[0] = 0; bar_cfg_is_64[0] = 0; bar_cfg_mask[0] = 32'hFFF0_0000;
      bar_used[1] = 1; bar_cfg_is_io[1] = 0; bar_cfg_is_64[1] = 1; bar_cfg_mask[1] = 32'hE000_0000;
      bar_used[2] = 0; // BAR2 is the high DW of the BAR1/2 64-bit pair - not independently decoded
      bar_used[3] = 1; bar_cfg_is_io[3] = 1; bar_cfg_is_64[3] = 0; bar_cfg_mask[3] = 32'hFFFF_FF00;
      bar_used[4] = 0;
      bar_used[5] = 0;

      `uvm_info("INIT", $sformatf("After init: cfg[0]=%08h cfg[BAR0]=%08h", cfg_model.read_reg(10'h0), cfg_model.read_reg(10'h4)), UVM_NONE)  

    endfunction

  //-----------------------------------------------------------
  // is_addr_supported()
  //   ERR_UNSUPPORTED_REQ checker: walks every implemented,
  //   currently-programmed BAR and reports whether `addr` (mem or
  //   IO, per is_io) falls inside any of them. Real hardware would
  //   simply not claim the transaction; here we use it to decide
  //   UR vs a normal completion / silently drop a posted write.
  //-----------------------------------------------------------
  function automatic bit is_addr_supported(bit [63:0] addr, bit is_io);
    for (int b = 0; b < 6; b++) begin
      bit [63:0] base, size;
      bit [31:0] raw_lo, raw_hi;

      if (!bar_used[b] || bar_cfg_is_io[b] != is_io)
        continue;

      raw_lo = cfg_model.read_reg(4 + b);
      size   = {32'h0, (~bar_cfg_mask[b]) + 32'h1};

      if (bar_cfg_is_io[b]) begin
        base = {32'h0, raw_lo & bar_cfg_mask[b]};
      end
      else if (bar_cfg_is_64[b] && (b < 5)) begin
        raw_hi = cfg_model.read_reg(4 + b + 1);
        base   = {raw_hi, raw_lo & bar_cfg_mask[b]};
      end
      else begin
        base = {32'h0, raw_lo & bar_cfg_mask[b]};
      end

      if (size == 0)
        continue;   // BAR not sized/programmed

      if (addr >= base && addr < (base + size))
        return 1;
    end
    return 0;
  endfunction

  //-----------------------------------------------------------
  // is_ca_trigger_addr()
  //   ERR_COMPLETER_ABORT checker: BAR0 is otherwise a perfectly
  //   valid, claimed range, but this one offset inside it is
  //   reserved to model a completer-side internal failure (e.g. a
  //   parity/ECC error on the backing storage, a locked internal
  //   register, etc.) - the request IS accepted by the completer
  //   (unlike UR, which never claims the address at all), but the
  //   completer cannot service it, so it must abort with CA
  //   (3'b100) instead of returning data.
  //-----------------------------------------------------------
  localparam bit [63:0] CA_TRIGGER_OFFSET = 64'hC0;

  function automatic bit is_ca_trigger_addr(bit [63:0] addr);
    bit [63:0] base;
    bit [31:0] raw_lo;

    if (!bar_used[0] || bar_cfg_is_io[0])
      return 0;

    raw_lo = cfg_model.read_reg(4 + 0);
    base   = {32'h0, raw_lo & bar_cfg_mask[0]};

    return (addr == (base + CA_TRIGGER_OFFSET));
  endfunction

  task run_phase(uvm_phase phase);

    Sequence_item req;
    Sequence_item cpl;

    bit is_mem_rd, is_mem_wr, is_io_rd, is_io_wr;
    bit is_cfg0_rd, is_cfg0_wr, is_cfg1_rd, is_cfg1_wr;

    super.run_phase(phase);

    `uvm_info("RX_PCIe_LUT", "LUT RUN PHASE STARTED", UVM_LOW)

    forever begin

      wait(req_q.size() > 0);
      req = req_q.pop_front();

      `uvm_info("LUT_REQ", $sformatf("REQ: fmt=%03b r_type=%05b reg=%0d ext=%0d tag=%0d",
           req.fmt, req.r_type, req.register_num, req.ext_register_num, req.tag), UVM_NONE)

      is_mem_rd  = (req.r_type inside {5'b00000, 5'b00001}) && (req.fmt inside {3'b000, 3'b001});
      is_mem_wr  = (req.r_type inside {5'b00000, 5'b00001}) && (req.fmt inside {3'b010, 3'b011});
      is_io_rd   = (req.r_type == 5'b00010) && (req.fmt inside {3'b000, 3'b001});
      is_io_wr   = (req.r_type == 5'b00010) && (req.fmt inside {3'b010, 3'b011});
      is_cfg0_rd = (req.r_type == 5'b00100) && (req.fmt == 3'b000);
      is_cfg0_wr = (req.r_type == 5'b00100) && (req.fmt inside {3'b010, 3'b011});
      is_cfg1_rd = (req.r_type == 5'b00101) && (req.fmt inside {3'b000, 3'b001});
      is_cfg1_wr = (req.r_type == 5'b00101) && (req.fmt inside {3'b010, 3'b011});

      if(is_mem_wr) begin
        bit [3:0] be;
        bit [31:0] old_word;

        // ERR_UNSUPPORTED_REQ checker: posted write to an
        // address no implemented BAR claims - a real completer
        // drops it silently on the wire (no completion for a
        // posted request), but must never apply it to memory.
        // FIX: is_addr_supported() was never actually called here,
        // so a write to an unclaimed address was silently applied
        // to mem_space anyway. Also removed the duplicate
        // calc_required_credit/return_credit call that ran twice
        // for the same TLP.
        fc_mgr.calc_required_credit(req, hdr_credit, data_credit);
        fc_mgr.return_credit(req.vc, req.pkt_type, hdr_credit, data_credit);

        if (!is_addr_supported(req.addr, 0)) begin
          `uvm_info("RX_PCIe_LUT",
            $sformatf("MEM_WR to unsupported addr=%0h - UR, posted write dropped (no completion)",
                       req.addr), UVM_LOW)
        end
        else begin
          foreach(req.payload[i]) begin
            if(req.length == 1)      be = req.first_BE;
            else if(i == 0)          be = req.first_BE;
            else if(i == req.length-1) be = req.last_BE;
            else                     be = 4'b1111;

            old_word = mem_space[req.addr + (i*4)];
            mem_space[req.addr + (i*4)] = apply_be(old_word, req.payload[i], be);
          end
        end
      end

      else if(is_io_wr) begin
        bit [31:0] old_word;
        old_word = io_space[req.addr];
        io_space[req.addr] = apply_be(old_word, req.payload[0], req.first_BE);

        cpl = generate_io_wr_cpl(req);
        cpl_ap.write(cpl);              // CHANGED: was cpl_fifo.put(cpl);
      end

      else if(is_mem_rd) begin
         // ERR_UNSUPPORTED_REQ checker: a non-posted request
         // (MEM_RD) to an address no BAR claims must come back as
         // Unsupported Request (compl_status = 3'b001), not data.
         if (!is_addr_supported(req.addr, 0)) begin
		 `uvm_info("RX_PCIe_LUT",
            $sformatf("MEM_WR to unsupported addr=%0h - UR, posted write dropped (no completion)",
                       req.addr), UVM_LOW)

           req.compl_status = 3'b001;   // Unsupported Request
         end
         // ERR_COMPLETER_ABORT checker: address IS claimed by BAR0,
         // but this offset models an internal completer-side
         // failure servicing an otherwise-legal request.
         else if (is_ca_trigger_addr(req.addr)) begin
           `uvm_info("RX_PCIe_LUT",
            $sformatf("MEM_RD to addr=%0h hit completer-side failure trap - CA",
                       req.addr), UVM_LOW)

           req.compl_status = 3'b100;   // Completer Abort
         end
         generate_mem_cpl(req);
         tag_mgr.free_tag(req.tag);
	 fc_mgr.calc_required_credit(req, hdr_credit, data_credit);
         fc_mgr.return_credit(req.vc, req.pkt_type, hdr_credit, data_credit);
      end

      else if(is_io_rd) begin
        cpl = generate_io_cpl(req);
        cpl_ap.write(cpl);              // CHANGED: was cpl_fifo.put(cpl);
        tag_mgr.free_tag(cpl.tag);
      end

      else if(is_cfg0_wr) begin
         cfg_write(req);
         cpl = generate_cfg_wr_cpl(req);
         cpl_ap.write(cpl);             // CHANGED: was cpl_fifo.put(cpl);
         tag_mgr.free_tag(cpl.tag);
      end

      else if(is_cfg1_wr) begin
         cfg_write(req);
         cpl = generate_cfg_wr_cpl(req);
         cpl_ap.write(cpl);             // CHANGED: was cpl_fifo.put(cpl);
         tag_mgr.free_tag(cpl.tag);
      end

      else if(is_cfg0_rd) begin
        if ((req.ep_bus == ep_bus) && (req.ep_device == ep_device) && (req.ep_function_n == ep_function)) begin
          cpl = generate_cfg_cpl(req);
          cpl_ap.write(cpl);           // CHANGED: was cpl_fifo.put(cpl);
          tag_mgr.free_tag(cpl.tag);
        end
        else
          `uvm_info("RX_PCIe_LUT", "Configuration Request not for this EP", UVM_LOW);
      end

      else if(is_cfg1_rd) begin
        if ((req.ep_bus == ep_bus) && (req.ep_device == ep_device) && (req.ep_function_n == ep_function)) begin
          cpl = generate_cfg_cpl(req);
          cpl_ap.write(cpl);           // CHANGED: was cpl_fifo.put(cpl);
          tag_mgr.free_tag(cpl.tag);
        end
        else
          `uvm_info("RX_PCIe_LUT", "Configuration Request not for this EP", UVM_LOW);
      end

    end

  endtask

  function void cfg_write(Sequence_item req);
    bit [9:0] dw_addr;
    dw_addr = {req.ext_register_num, req.register_num};
    cfg_model.write_reg(dw_addr, req.payload[0], (req.length == 1) ? req.first_BE : 4'hF);
  endfunction

    function automatic bit [1:0] calc_lower_addr_lsb(bit [3:0] first_be);
    casez(first_be)
      4'b???1 : calc_lower_addr_lsb = 2'b00;
      4'b??10 : calc_lower_addr_lsb = 2'b01;
      4'b?100 : calc_lower_addr_lsb = 2'b10;
      4'b1000 : calc_lower_addr_lsb = 2'b11;
      default : calc_lower_addr_lsb = 2'b00;  // 4'b0000
    endcase
  endfunction : calc_lower_addr_lsb

  task generate_mem_cpl(Sequence_item req);
    Sequence_item cpl;
    int bytes_remaining, current_addr, byte_count, cpl_bytes, dw_count;
    bit first_cpl;

      if(req.compl_status != 3'b000) begin
      cpl = Sequence_item::type_id::create("cpl");
      cpl.fmt           = 3'b000;      // Completion without Data
      cpl.r_type        = 5'b01010;
      cpl.e_type        = CPL;
      cpl.completer_id  = 16'h0100;
      cpl.compl_status  = req.compl_status;
      cpl.bcm           = req.bcm;
      cpl.byte_count    = 12'h4;
      cpl.req_id        = req.req_id;
      cpl.tag           = req.tag;
      cpl.lower_addr    = 7'h0;
      cpl.length        = 0;
      cpl.at            = req.at;
      cpl.td            = req.td;
      cpl.pack_tlp();

      cpl_ap.write(cpl);
      return;
    end

    bytes_remaining = req.length * 4;
    current_addr    = req.addr;
    byte_count      = bytes_remaining;
    first_cpl       = 1'b1;

    while(bytes_remaining > 0) begin
      cpl = Sequence_item::type_id::create("cpl");
      cpl.fmt    = 3'b010;
      cpl.r_type = 5'b01010;
      cpl.e_type = CPL_DATA;
      cpl.completer_id = 16'h0100;
      cpl.compl_status = req.compl_status;
      cpl.bcm = req.bcm;
      cpl.byte_count = byte_count;
      cpl.req_id = req.req_id;
      cpl.tag = req.tag;

      if(first_cpl)
        cpl.lower_addr = {current_addr[6:2], calc_lower_addr_lsb(req.first_BE)};
      else
        cpl.lower_addr = {5'b00000, 2'b00};
        

      cpl_bytes = (bytes_remaining > MAX_CPL_BYTES) ? MAX_CPL_BYTES : bytes_remaining;
      dw_count = cpl_bytes / 4;
      cpl.length = dw_count;
      cpl.payload = new[cpl.length];
      foreach(cpl.payload[i])
        cpl.payload[i] = mem_space[current_addr + i*4];

      cpl.at = req.at;
      cpl.td = req.td;
      cpl.pack_tlp();

      cpl_ap.write(cpl);               // CHANGED: was cpl_fifo.put(cpl);

      bytes_remaining -= cpl_bytes;
      byte_count -= cpl_bytes;
      current_addr += cpl_bytes;
      first_cpl = 1'b0;
    end
  endtask : generate_mem_cpl

  // generate_io_wr_cpl / generate_io_cpl / generate_cfg_cpl / generate_cfg_wr_cpl / apply_be
  // are unchanged from the original — they just build and return a Sequence_item.

  
  function Sequence_item generate_io_wr_cpl(Sequence_item req);
    Sequence_item cpl;

    cpl = Sequence_item::type_id::create("cpl");

    cpl.fmt    = 3'b000;          // CPL (no data)
    cpl.r_type = 5'b01010;

    cpl.completer_id = 16'h0100;
    cpl.compl_status = 3'b000;
    cpl.bcm          = 0;
    cpl.byte_count   = 0;
    cpl.req_id       = req.req_id;
    cpl.tag          = req.tag;
    cpl.lower_addr   = req.addr[6:0];
    cpl.length       = 0;
    cpl.td           = req.td;
    cpl.at           = req.at;

    cpl.pack_tlp();
   
    return cpl;
  endfunction

  function Sequence_item generate_io_cpl(Sequence_item req);
    Sequence_item cpl;

    cpl = Sequence_item::type_id::create("cpl");

    cpl.fmt    = 3'b010;          // CPL_DATA
    cpl.r_type = 5'b01010;

    cpl.completer_id = 16'h0100;
    cpl.compl_status = 3'b000;
    cpl.bcm          = req.bcm;
    cpl.byte_count   = 4;
    cpl.req_id       = req.req_id;
    cpl.tag          = req.tag;
    cpl.lower_addr   = req.addr[6:0];
    cpl.length       = 1;

    cpl.payload    = new[1];
    cpl.payload[0] = io_space[req.addr];

    cpl.td = req.td;
    cpl.at = req.at;

    cpl.pack_tlp();
 
    return cpl;
  endfunction : generate_io_cpl

  function Sequence_item generate_cfg_cpl(Sequence_item req);

    Sequence_item cpl;
    bit [9:0] dw_addr;

    cpl = Sequence_item::type_id::create("cpl");

    dw_addr = {req.ext_register_num, req.register_num};

    cpl.e_type        = CPL_DATA;
    cpl.completer_id  = 16'h0100;
    cpl.compl_status  = 3'b000;
    cpl.bcm           = req.bcm;
    cpl.byte_count    = 4;
    cpl.req_id        = req.req_id;
    cpl.tag           = req.tag;
    cpl.td            = req.td;    
    cpl.lower_addr    = req.addr[6:0];
    cpl.length        = 1;

    cpl.payload = new[1];
    cpl.payload[0] = cfg_model.read_reg(dw_addr);

    `uvm_info("RX_PCIE_LUT",
      $sformatf("CFG_RD dw_addr=%0h (ext=%0d reg=%0d) data=%08h",
                 dw_addr, req.ext_register_num, req.register_num, cpl.payload[0]), UVM_LOW)

    cpl.pack_tlp();

    `uvm_info("CFG_CPL",
  $sformatf("[%0t] Generating completion for reg=%0d tag=%0d",
            $time, req.register_num, req.tag),
  UVM_LOW)
 
    return cpl;

  endfunction


  function Sequence_item generate_cfg_wr_cpl(Sequence_item req);

  Sequence_item cpl;

  cpl = Sequence_item::type_id::create("cfg_wr_cpl");

  cpl.fmt           = 3'b000;      // Completion without Data
  
  cpl.r_type        = 5'b01010;    // Completion

  cpl.e_type        = CPL;

  cpl.completer_id  = 16'h0100;

  cpl.compl_status  = 3'b000;      // Successful Completion

  cpl.bcm           = 0;

  cpl.byte_count    = 0;

  cpl.req_id        = req.req_id;

  cpl.tag           = req.tag;

  cpl.lower_addr    = req.addr[6:0];

  cpl.length        = 0;           // No Data

  cpl.td            = req.td;

  cpl.at            = req.at;

  cpl.pack_tlp();

    return cpl;

endfunction


  function automatic bit [31:0] apply_be(bit [31:0] old_data, bit [31:0] new_data, bit [3:0]  be);

    apply_be = old_data;

    if(be[0])
      apply_be[7:0]   = new_data[7:0];

    if(be[1])
      apply_be[15:8]  = new_data[15:8];

    if(be[2])
      apply_be[23:16] = new_data[23:16];

    if(be[3])
      apply_be[31:24] = new_data[31:24];
   
  endfunction : apply_be
    
endclass : RX_PCIe_LUT
