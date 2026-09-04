
class apb_reg_adapter extends uvm_reg_adapter;
     `uvm_object_utils(apb_reg_adapter)

     function new(string name = "apb_reg_adapter");
          super.new(name);
          supports_byte_enable = 0;  // APB has no per-byte strobes in this VIP
          provides_responses   = 1;  // driver returns tx via seq_item_port.put()
     endfunction


     virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
          seq_item_apb_master item = seq_item_apb_master::type_id::create("item");

          item.PADDR   = rw.addr >> 2;  // means: divide by 4 → cm to box number
          item.PWDATA  = rw.data;
          item.rd_wr   = (rw.kind == UVM_WRITE) ? item.write : item.read;
          item.corrupt = 0;  // never inject protocol errors on RAL-driven access

          return item;
     endfunction


     virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
          seq_item_apb_master item;

          if (!$cast(item, bus_item))
               `uvm_fatal("APB_ADAPTER", "Failed to cast bus_item to seq_item_apb_master")

          rw.addr   = item.PADDR << 2;  // means: multiply by 4 → box number to cm
          rw.data   = (item.rd_wr == item.write) ? item.PWDATA : item.PRDATA;
          rw.kind   = (item.rd_wr == item.write) ? UVM_WRITE : UVM_READ;
          rw.status = item.PSLVERR_captured ? UVM_NOT_OK : UVM_IS_OK;

     endfunction

endclass
