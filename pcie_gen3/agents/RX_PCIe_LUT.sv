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

  uvm_tlm_fifo #(Sequence_item) cpl_fifo;

  Sequence_item req_q[$];

  //////////////////////////////  MEMORY SPACE  ///////////////////////////////
  bit [31:0] mem_space [longint unsigned];

  ///////////////////////////////  IO SPACE  /////////////////////////////////
  bit [31:0] io_space [longint unsigned];

  ///////////////////////////// CONFIG SPACE /////////////////////////////////
  bit [31:0] cfg_space [0:4095];

  `uvm_component_utils(RX_PCIe_LUT)

  function new(string name="PCIe_LUT", uvm_component parent=null);
    super.new(name,parent);
    RX_LUT_imp = new("RX_LUT_imp",this);
    cpl_fifo = new("cpl_fifo", this, 32);
  endfunction

  function void write(Sequence_item req);
    req_q.push_back(req);
    `uvm_info("RX_PCIe_LUT", $sformatf("LUT WRITE CALLED, queue size after push = %0d, fmt=%03b r_type=%05b",
                                        req_q.size(), req.fmt, req.r_type), UVM_LOW)
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

      `uvm_info("RX_PCIe_LUT",
                $sformatf("LUT RECEIVED REQUEST fmt=%03b r_type=%05b", req.fmt, req.r_type),
                UVM_LOW)

      // Decode (fmt, r_type) into the equivalent of the reference
      // project's e_type. fmt={000,001}=no-data(read), {010,011}=data(write).
      is_mem_rd  = (req.r_type inside {5'b00000, 5'b00001}) && (req.fmt inside {3'b000, 3'b001});
      is_mem_wr  = (req.r_type inside {5'b00000, 5'b00001}) && (req.fmt inside {3'b010, 3'b011});
      is_io_rd   = (req.r_type == 5'b00010) && (req.fmt inside {3'b000, 3'b001});
      is_io_wr   = (req.r_type == 5'b00010) && (req.fmt inside {3'b010, 3'b011});
      is_cfg0_rd = (req.r_type == 5'b00100) && (req.fmt inside {3'b000, 3'b001});
      is_cfg0_wr = (req.r_type == 5'b00100) && (req.fmt inside {3'b010, 3'b011});
      is_cfg1_rd = (req.r_type == 5'b00101) && (req.fmt inside {3'b000, 3'b001});
      is_cfg1_wr = (req.r_type == 5'b00101) && (req.fmt inside {3'b010, 3'b011});

      if(is_mem_wr) begin

        foreach(req.payload[i]) begin
          mem_space[req.addr + (i*4)] = req.payload[i];
          `uvm_info("RX_PCIe_LUT",
                    $sformatf("MEMORY WRITE ADDR=%h DATA=%h FIRST_BE=%b LAST_BE=%b",
                              req.addr + (i*4), req.payload[i], req.first_BE, req.last_BE),
                    UVM_LOW)
        end

      end
      else if(is_io_wr) begin

        io_space[req.addr] = req.payload[0];
        `uvm_info("RX_PCIe_LUT", $sformatf("IO WRITE ADDR=%0h DATA=%0h", req.addr, req.payload[0]), UVM_LOW)

        cpl = generate_io_wr_cpl(req);
        cpl_fifo.put(cpl);

      end
      else if(is_mem_rd) begin

        `uvm_info("RX_PCIe_LUT", "MEMORY READ RECEIVED", UVM_LOW)
        cpl = generate_mem_cpl(req);
        cpl_fifo.put(cpl);

      end
      else if(is_io_rd) begin

        `uvm_info("RX_PCIe_LUT", "IO READ RECEIVED", UVM_LOW)
        cpl = generate_io_cpl(req);
        cpl_fifo.put(cpl);

      end
      else if(is_cfg0_wr) begin

        cfg_space[{req.ext_register_num, req.register_num}] = req.payload[0];

      end
      else if(is_cfg1_wr) begin

        cfg_space[{req.ext_register_num, req.register_num}] = req.payload[0];

      end
      else if(is_cfg0_rd) begin

        cpl = generate_cfg_cpl(req);
        cpl_fifo.put(cpl);

      end
      else if(is_cfg1_rd) begin

        cpl = generate_cfg_cpl(req);
        cpl_fifo.put(cpl);

      end

    end

  endtask

  //-----------------------------------------------------------
  // Completion generators - fmt/r_type set per the completion
  // r_type encoding (01010), fmt 000=no-data (CPL), 010=data
  // (CPL_DATA), matching this project's completion_fmt_constraint.
  //-----------------------------------------------------------

  function Sequence_item generate_mem_cpl(Sequence_item req);
    Sequence_item cpl;

    cpl = Sequence_item::type_id::create("cpl");

    cpl.fmt    = 3'b010;          // CPL_DATA
    cpl.r_type = 5'b01010;

    cpl.completer_id = 16'h0100;
    cpl.compl_status = req.compl_status;
    cpl.bcm          = req.bcm;
    cpl.byte_count   = req.length * 4;
    cpl.req_id       = req.req_id;
    cpl.tag          = req.tag;
    cpl.lower_addr   = req.addr[6:0];
    cpl.length       = req.length;

    cpl.payload = new[req.length];
    foreach(cpl.payload[i])
      cpl.payload[i] = mem_space[req.addr + (i*4)];

    cpl.at = req.at;
    cpl.td = req.td;

    cpl.pack_tlp();

    return cpl;
  endfunction : generate_mem_cpl

  function Sequence_item generate_io_wr_cpl(Sequence_item req);
    Sequence_item cpl;

    cpl = Sequence_item::type_id::create("cpl");

    cpl.fmt    = 3'b000;          // CPL (no data)
    cpl.r_type = 5'b01010;

    cpl.completer_id = 16'h0100;
    cpl.compl_status = req.compl_status;
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
    cpl.compl_status = req.compl_status;
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

    cpl = Sequence_item::type_id::create("cpl");

    cpl.fmt    = 3'b010;          // CPL_DATA
    cpl.r_type = 5'b01010;

    cpl.completer_id = 16'h0100;
    cpl.compl_status = req.compl_status;
    cpl.bcm          = req.bcm;
    cpl.byte_count   = 4;
    cpl.req_id       = req.req_id;
    cpl.tag          = req.tag;
    cpl.lower_addr   = req.addr[6:0];
    cpl.length       = 1;

    cpl.payload    = new[1];
    cpl.payload[0] = cfg_space[{req.ext_register_num, req.register_num}];

    cpl.pack_tlp();

    return cpl;
  endfunction : generate_cfg_cpl

endclass : RX_PCIe_LUT
