`define DRV_IF vif.SLAVE_mp
class apb_slv_driver extends uvm_driver #(apb_slv_xtn);
     `uvm_component_utils(apb_slv_driver)

     virtual apb_interface vif;
     PCIe_Cfg_Space_Model cfg_model;

     bit [DATA_WIDTH-1:0] mem[int];  // last 24-DATA_WIDTH-1 is reserved memory


     function new(string name = "apb_slv_driver", uvm_component parent);
          super.new(name, parent);
     endfunction

     virtual function void build_phase(uvm_phase phase);
          super.build_phase(phase);
          if (!uvm_config_db#(virtual apb_interface)::get(this, "", "svif", vif))
               `uvm_fatal(get_type_name(), "didn't get handle to virtual interface")
          if (!uvm_config_db#(PCIe_Cfg_Space_Model)::get(
                  this, "", "cfg_model", cfg_model
              ))  // ← add this
               `uvm_fatal(get_type_name(), "didn't get handle to cfg_model")
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          forever begin
               if (vif.PRESETn == 0) reset();
               seq_item_port.get_next_item(req);
               drive_2_dut(req);
               seq_item_port.item_done();
          end
     endtask

     task reset();
          vif.PREADY  <= 0;
          vif.PRDATA  <= 0;
          vif.PSLVERR <= 0;
          wait (vif.PRESETn == 1);
          @(posedge vif.PCLK);
     endtask

     task drive_2_dut(apb_slv_xtn xtnh);
          begin
               case (xtnh.op)
                    without_wait: nowait_rsp(xtnh);
                    with_wait: wait_rsp(xtnh);
                    slave_illegal: illegal(xtnh);
               endcase
          end
     endtask

     task wait_rsp(apb_slv_xtn xtnh);
          wait (vif.PSEL == 1'b1);
          uvm_report_info("SLAVE", "-IN SETUP", UVM_HIGH);
          @(posedge vif.PENABLE);
          uvm_report_info("SLAVE", "-IN ACCESS", UVM_HIGH);
          if (vif.PWRITE == 1'b1) begin
               repeat (xtnh.rsp_count) begin
                    @(posedge vif.PCLK);
               end
               vif.PREADY <= 1'b1;
               uvm_report_info("SLAVE", "PREADY-DRIVEN", UVM_HIGH);

               cfg_model.write_reg(vif.PADDR, vif.PWDATA);
               $display("cfg_mem[%0d] = %0h", vif.PADDR, cfg_model.read_reg(vif.PADDR));
               vif.PSLVERR <= 1'b0;
               @(posedge vif.PCLK);
               vif.PREADY <= 1'b0;
          end else begin
               repeat (xtnh.rsp_count) begin
                    @(posedge vif.PCLK);
               end
               vif.PREADY <= 1'b1;
               uvm_report_info("SLAVE", "PREADY-DRIVEN", UVM_HIGH);

               vif.PRDATA  <= cfg_model.read_reg(vif.PADDR);
               vif.PSLVERR <= 1'b0;
               @(posedge vif.PCLK);
               vif.PREADY <= 1'b0;
          end
     endtask


     task nowait_rsp(apb_slv_xtn xtnh);
          wait (vif.PSEL == 1'b1);
          uvm_report_info("SLAVE", "-IN SETUP", UVM_HIGH);
          @(posedge vif.PENABLE);
          uvm_report_info("SLAVE", "-IN ACCESS", UVM_HIGH);
          if (vif.PWRITE == 1'b1) begin
               vif.PREADY <= 1'b1;
               uvm_report_info("SLAVE", "PREADY-DRIVEN", UVM_HIGH);


               cfg_model.write_reg(vif.PADDR, vif.PWDATA);
               $display("cfg_mem[%0d] = %0h", vif.PADDR, cfg_model.read_reg(vif.PADDR));

               vif.PSLVERR <= 1'b0;
               @(posedge vif.PCLK);
               vif.PSLVERR <= 1'b0;
          end else begin
               vif.PREADY <= 1'b1;
               uvm_report_info("SLAVE", "PREADY-DRIVEN", UVM_HIGH);

               vif.PRDATA  <= cfg_model.read_reg(vif.PADDR);
               vif.PSLVERR <= 1'b0;
               @(posedge vif.PCLK);
               vif.PSLVERR <= 1'b0;
          end
     endtask

     task illegal(apb_slv_xtn xtnh);

          @(posedge vif.PCLK);
          if (vif.PSEL == 1'b1) begin
               @(posedge vif.PCLK);
               if (vif.PENABLE == 1'b1) begin
                    if(vif.PWRITE == 1'b1)   //write with no wait state
                        begin
                         vif.PREADY <= 1'b1;
                         if (vif.PADDR <= 1024) begin
                              mem[vif.PADDR] = $urandom_range(100, 200);
                              vif.PSLVERR <= 1'b0;
                         end else vif.PSLVERR <= 1'b1;
                         @(posedge vif.PCLK);
                         vif.PREADY  <= 1'b0;
                         vif.PSLVERR <= 1'b0;
                    end else  //write with no wait state
                    begin
                         vif.PREADY <= 1'b1;
                         if (mem.exists(vif.PADDR)) begin
                              vif.PRDATA  <= $urandom_range(1000, 2000);
                              vif.PSLVERR <= 1'b0;
                         end else vif.PSLVERR <= 1'b1;
                         @(posedge vif.PCLK);
                         vif.PREADY  <= 1'b0;
                         vif.PSLVERR <= 1'b0;
                    end
               end else begin
                    vif.PSLVERR <= 1'b1;  //voilation in the protocol
                    vif.PREADY  <= 1'b0;
                    @(posedge vif.PCLK);
               end
          end else begin
               vif.PREADY  <= 1'b0;
               vif.PSLVERR <= 1'b0;
               @(posedge vif.PCLK);
          end
     endtask

endclass



