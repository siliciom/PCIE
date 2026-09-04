class Tag_Manager extends uvm_component;

     `uvm_component_utils(Tag_Manager)

     bit tag_busy[256];

     int outstanding_cnt = 0;

     function new(string name = "Tag_Manager", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     function int allocate_tag();

          for (int i = 0; i < $size(tag_busy); i++) begin

               if (!tag_busy[i]) begin

                    tag_busy[i] = 1;

                    outstanding_cnt++;

                    `uvm_info("TAG_MANAGER", $sformatf(
                              "TAG_ALLOCATED=%0d OUTSTANDING=%0d", i, outstanding_cnt), UVM_LOW);

                    return i;

               end

          end


          return -1;

     endfunction

     function void free_tag(int tag);

          tag_busy[tag] = 0;

          outstanding_cnt--;

          `uvm_info("TAG_MANAGER", $sformatf("TAG_FREED=%0d", tag), UVM_LOW);

     endfunction

endclass

