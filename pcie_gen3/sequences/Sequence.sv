class Sequence_tx extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Sequence_tx)

     function new(string name = "Sequence");
          super.new(name);
     endfunction

     task body();
          repeat (4) begin

               `uvm_do_with(
                   req,
                   {e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == 32'h10; td == 1; length == 4;})

               $display("E_TYPE = %s E_FMT = %s fmt = %3b", req.e_type.name(), req.e_fmt.name(),
                        req.fmt);
               `uvm_do_with(req,
                            {e_type == MEM_RD; e_fmt == FMT_3DW_NO_DATA; addr == 32'h10; td == 1; length == 4;})
               $display("E_TYPE = %s E_FMT = %s fmt = %3b", req.e_type.name(), req.e_fmt.name(),
                        req.fmt);



          end

     endtask

endclass : Sequence_tx



// Mem write+read test case - fmt and address are set by the caller right
// before .start() method, so the same sequence class drives traffic into
// whichever BAR window enumeration discovered, with whichever fmt
// (3DW vs 4DW) that BAR's type bits called for.

class Single_Mem_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Single_Mem_Wr_Rd_3DW)

     Tag_Manager          tag_mgr;

     fmt_e                p_wr_fmt;
     fmt_e                p_rd_fmt;
     bit         [  63:0] p_addr;
     bit         [1023:0] p_length;
     bit         [   7:0] tag_id;

     function new(string name = "Mem_Wr_Rd_Seq");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          `uvm_info("SEQ", $sformatf("WR_FMT=%s RD_FMT=%s ADDR=%h LEN=%0d", p_wr_fmt.name(),
                                     p_rd_fmt.name(), p_addr, p_length), UVM_HIGH)


          `uvm_info("SEQUENCE", $sformatf("Allocated tag = %0d", tag_id), UVM_HIGH)

          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; length == local::p_length; td == 0; tag == 0; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)



          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; length == local::p_length; td == 0; tag == tag_id; tc == 0;})


     endtask : body

endclass : Single_Mem_Wr_Rd_3DW



class Single_Mem_Wr_Rd_4DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Single_Mem_Wr_Rd_4DW)

     Tag_Manager          tag_mgr;

     fmt_e                p_wr_fmt;
     fmt_e                p_rd_fmt;
     bit         [  63:0] p_addr;
     bit         [1023:0] p_length  = 34;
     bit         [   7:0] tag_id;


     function new(string name = "Single_Mem_Wr_Rd_4DW");
          super.new(name);
     endfunction


     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask


     task body();


          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == 0;tc ==0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


     endtask : body

endclass : Single_Mem_Wr_Rd_4DW




class Multiple_Mem_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Multiple_Mem_Wr_Rd_3DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 40;
     bit         [ 7:0] tag_id;

     function new(string name = "Multiple_Mem_Wr_Rd_3DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask


     task body();

          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; tag == 0; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; tag == tag_id; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : Multiple_Mem_Wr_Rd_3DW


class Multiple_Mem_Wr_Rd_4DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Multiple_Mem_Wr_Rd_4DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 40;
     bit         [ 7:0] tag_id;

     function new(string name = "Multiple_Mem_Wr_Rd_4DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();



          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; tag == 0;tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; tag == tag_id;tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : Multiple_Mem_Wr_Rd_4DW


class B2B_Mem_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(B2B_Mem_Wr_Rd_3DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 34;
     bit         [ 7:0] tag_id;

     function new(string name = "B2B_Mem_Wr_Rd_3DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();


          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == 0; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : B2B_Mem_Wr_Rd_3DW




class B2B_Mem_Wr_Rd_4DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(B2B_Mem_Wr_Rd_4DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 34;
     bit         [ 7:0] tag_id;

     function new(string name = "B2B_Mem_Wr_Rd_4DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == 0;tc ==0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)
          tag_id = tag_mgr.allocate_tag();
          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : B2B_Mem_Wr_Rd_4DW




class Single_IO_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Single_IO_Wr_Rd_3DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 34;
     bit         [ 7:0] tag_id;

     function new(string name = "Single_IO_Wr_Rd_3DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == IO_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


          tag_id = tag_mgr.allocate_tag();
          `uvm_do_with(
              req,
              {e_type == IO_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : Single_IO_Wr_Rd_3DW



class Multiple_IO_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Multiple_IO_Wr_Rd_3DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 40;
     bit         [ 7:0] tag_id;

     function new(string name = "Multiple_IO_Wr_Rd_3DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == IO_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == IO_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : Multiple_IO_Wr_Rd_3DW



class B2B_IO_Wr_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(B2B_IO_Wr_Rd_3DW)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 40;
     bit         [ 7:0] tag_id;

     function new(string name = "B2B_IO_Wr_Rd_3DW");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          tag_id = tag_mgr.allocate_tag();
          `uvm_do_with(
              req,
              {e_type == IO_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == IO_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)


     endtask : body

endclass : B2B_IO_Wr_Rd_3DW



// Generic single-register CFG0 read / write - these will read the contents of
// vendor id, header type, and BAR 0 - BAR 5 and also they will write to the
// command register to enable the memory and i/o space.


class Cfg_Rd0_Reg_Seq extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Cfg_Rd0_Reg_Seq)

     Tag_Manager tag_mgr;

     bit [3:0] p_ext_reg = 4'h0;
     bit [5:0] p_reg;
     bit [7:0] tag_id;

     function new(string name = "Cfg_Rd0_Reg_Seq");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          tag_id = tag_mgr.allocate_tag();

          `uvm_info("SEQUENCE", $sformatf("Allocated tag = %0d", tag_id), UVM_LOW)

          `uvm_do_with(
              req,
              {e_type == CFG_RD0; e_fmt == FMT_3DW_NO_DATA; ep_bus == 8'h0; ep_device == 5'h2; ep_function_n == 3'h0; register_num == local::p_reg; ext_register_num == local::p_ext_reg; td == 1; tag == tag_id; tc == 3'b000;})

     endtask : body

endclass : Cfg_Rd0_Reg_Seq


class Cfg_Wr0_Reg_Seq extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Cfg_Wr0_Reg_Seq)

     Tag_Manager        tag_mgr;

     bit         [ 3:0] p_ext_reg = 4'h0;
     bit         [ 5:0] p_reg;
     bit         [31:0] p_data;
     bit         [ 3:0] p_be      = 4'hF;
     bit         [ 7:0] tag_id;

     function new(string name = "Cfg_Wr0_Reg_Seq");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          tag_id = tag_mgr.allocate_tag();

          `uvm_info("SEQUENCE", $sformatf("Allocated tag = %0d", tag_id), UVM_LOW)

          `uvm_do_with(
              req,
              {e_type == CFG_WR0; e_fmt == FMT_3DW_DATA; ep_bus == 8'h0; ep_device == 5'h2; ep_function_n == 3'h0; register_num == local::p_reg; ext_register_num == local::p_ext_reg; first_BE == local::p_be; last_BE == 4'h0; payload.size() == 1; payload[0] == local::p_data; length == 1; td == 1; tag == tag_id; tc == 3'b000;})

     endtask : body

endclass : Cfg_Wr0_Reg_Seq







class Sequence_rx extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Sequence_rx)

     function new(string name = "Sequence");
          super.new(name);
     endfunction

     task body();
          // Sequence Logic //
     endtask

endclass : Sequence_rx


// Error_Inject_Seq
//   One general-purpose sequence used by every TL-layer negative
//   test in tests/Error_Tests.sv. It builds exactly one TL request
//   of the requested type/address/length/tag and the requested
//   inject_err mode (see pcie_top_defines.svh).
//   It drives through the normal named constraints (MEM_WR_CONSTRAINT,
//   MEM_RD_CONSTRAINT, IO_RD_CONSTRAINT, ...) exactly like every
//   other sequence in this file - only e_type/e_fmt/addr/length/tag/
//   inject_err are set inline. The actual corruption for
//   ERR_LEN_MISMATCH/ERR_IO_LEN/ERR_CFG_LEN/ERR_FMT_RTYPE/
//   ERR_BYTE_EN/ERR_EP_POISON happens automatically afterwards, in
//   Sequence_item::post_randomize() - it always wins over whatever
//   the solver picked, so there's no need to fight/disable the
//   named constraints here.
class Error_Inject_Seq extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Error_Inject_Seq)

     Tag_Manager           tag_mgr;

     tlp_type_e            p_type        = MEM_WR;
     fmt_e                 p_fmt         = FMT_3DW_DATA;
     bit          [  63:0] p_addr        = 64'h0;
     bit          [1023:0] p_length      = 1;
     err_inject_e          p_inject_err  = ERR_NONE;
     bit                   p_use_tag_mgr = 0;
     bit          [   7:0] p_tag         = 0;

     int                   tag_id;

     function new(string name = "Error_Inject_Seq");
          super.new(name);
     endfunction

     task pre_body();
          // Only MEM_RD-style negative tests need a real allocated tag
          // (so the completion side has something outstanding to match
          // against); posted writes and the deliberately-malformed cases
          // just use tag 0 / p_tag directly.
          if (p_use_tag_mgr)
               void'(uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr));
     endtask

     task body();

          req = Sequence_item::type_id::create("req");
          start_item(req);

          if (p_use_tag_mgr) tag_id = tag_mgr.allocate_tag();

          assert (req.randomize() with {
               e_type == local:: p_type;
               e_fmt == local:: p_fmt;
               addr == local:: p_addr;
               td == 1;
               tc == 0;
               tag == (local:: p_use_tag_mgr ? local:: tag_id : local:: p_tag);
               length == local:: p_length;
               if (local:: p_type inside {MEM_WR, IO_WR, CFG_WR0, CFG_WR1})
               payload.size() == local:: p_length;
               inject_err == local:: p_inject_err;
          })
          else `uvm_fatal("SEQ", "Error_Inject_Seq randomize failed");

          `uvm_info("SEQ", $sformatf(
                               "Error_Inject_Seq: type=%s addr=%0h len=%0d inject_err=%s tag=%0d",
                               req.e_type.name(), req.addr, req.length, req.inject_err.name(),
                               req.tag), UVM_LOW)

          finish_item(req);

     endtask : body

endclass : Error_Inject_Seq






class Zero_length_mem_rd extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Zero_length_mem_rd)

     Tag_Manager          tag_mgr;

     fmt_e                p_wr_fmt;
     fmt_e                p_rd_fmt;
     bit         [  63:0] p_addr;
     bit         [1023:0] p_length;
     bit         [   7:0] tag_id;

     function new(string name = "Mem_Wr_Rd_Seq");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          `uvm_info("SEQ", $sformatf("WR_FMT=%s RD_FMT=%s ADDR=%h LEN=%0d", p_wr_fmt.name(),
                                     p_rd_fmt.name(), p_addr, p_length), UVM_HIGH)


          `uvm_info("SEQUENCE", $sformatf("Allocated tag = %0d", tag_id), UVM_HIGH)





          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id; tc == 0; first_BE == 4'b0000; last_BE == 4'b0000;})


     endtask : body

endclass : Zero_length_mem_rd





class Multiple_Mem_Wr_256_tag extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Multiple_Mem_Wr_256_tag)

     Tag_Manager        tag_mgr;

     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length  = 40;
     bit         [ 7:0] tag_id;

     function new(string name = "Multiple_Mem_Wr_256_tag");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask


     task body();




          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)

     endtask : body

endclass : Multiple_Mem_Wr_256_tag


class Single_Mem_Wr_emt_Rd_3DW extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Single_Mem_Wr_emt_Rd_3DW)

     Tag_Manager          tag_mgr;

     fmt_e                p_wr_fmt;
     fmt_e                p_rd_fmt;
     bit         [  63:0] p_addr;
     bit         [1023:0] p_length;

     bit         [   7:0] tag_id;

     function new(string name = "Mem_Wr_Rd_Seq");
          super.new(name);
     endfunction

     task pre_body();

          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))

               `uvm_fatal("SEQ", "Cannot get Tag Manager")

     endtask

     task body();

          `uvm_info("SEQ", $sformatf("WR_FMT=%s RD_FMT=%s ADDR=%h LEN=%0d", p_wr_fmt.name(),
                                     p_rd_fmt.name(), p_addr, p_length), UVM_HIGH)


          `uvm_info("SEQUENCE", $sformatf("Allocated tag = %0d", tag_id), UVM_HIGH)

          `uvm_do_with(
              req,
              {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == 0; tc == 0;})

          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)



          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(
              req,
              {e_type == MEM_RD; e_fmt == local::p_rd_fmt; addr == local::p_addr; td == 1; length == local::p_length; td == 1; tag == tag_id; tc == 0;first_BE == 0; last_BE ==0;})


     endtask : body

endclass : Single_Mem_Wr_emt_Rd_3DW





class Multiple_Mem_Wr_Rd_3DW_tc_vc extends uvm_sequence #(Sequence_item);

     `uvm_object_utils(Multiple_Mem_Wr_Rd_3DW_tc_vc)
     Tag_Manager        tag_mgr;
     fmt_e              p_wr_fmt;
     fmt_e              p_rd_fmt;
     bit         [63:0] p_addr;
     int                p_length                                        = 40;
     bit         [ 7:0] tag_id;
     bit         [ 2:0] tc;  // <-- plain bit now, no randc/rand needed

     function new(string name = "Multiple_Mem_Wr_Rd_3DW_tc_vc");
          super.new(name);
     endfunction

     task pre_body();
          if (!uvm_config_db#(Tag_Manager)::get(null, get_full_name(), "tag_mgr", tag_mgr))
               `uvm_fatal("SEQ", "Cannot get Tag Manager")
     endtask

     task body();
          // DO NOT randomize tc here — it's driven from the test via direct assignment
          `uvm_do_with(req,
                       {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr;
                        td == 1; length == local::p_length; tag == tag_id; tc == local::tc;})

          `uvm_info("UVM_DBG", $sformatf("TC = %0d", req.tc), UVM_LOW)



          tag_id = tag_mgr.allocate_tag();

          `uvm_do_with(req,
                       {e_type == MEM_WR; e_fmt == local::p_wr_fmt; addr == local::p_addr;
                        td == 1; length == local::p_length; tag == tag_id; tc == local::tc;})


          `uvm_info("UVM_DBG", $sformatf("TC = %0d", req.tc), UVM_LOW)
          `uvm_info("DBG", $sformatf("e_type=%s e_fmt=%s fmt=%03b", req.e_type.name(),
                                     req.e_fmt.name(), req.fmt), UVM_LOW)
     endtask : body

endclass : Multiple_Mem_Wr_Rd_3DW_tc_vc
