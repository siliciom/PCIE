class TX_TL_Driver extends uvm_driver #(Sequence_item);
  
  virtual TX_TL_DL_Interface TX_TL_DL;
  bit[31:0] TLP_HEADER[0:3];
  bit[31:0] TLP_PAYLOAD;
  bit[159:0] TLP_PACKET;
  
  `uvm_component_utils(TX_TL_Driver)
  
  function new(string name = "TX_TL_Driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
      begin
        `uvm_fatal("TX_TL_Driver", "Unable to access the TX_TL_DLL from config_db")
       end      
    
    else  
      `uvm_info("TX_TL_Driver", "Successfully accessed the TX_TL_DLL from config_db", UVM_LOW);
  
  endfunction
  
  
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
 //   forever begin
//       seq_item_port.get_next_item(req);
//       TLP_HEADER[0] = {req.fmt, req.r_type, req.R1, req.tc, req.R2, req.attr_1, req.R3, req.th, req.td, req.ep, req.attr_2, req.at, req.length};
//       TLP_HEADER[1] = {req.req_id, req.tag, req.first_BE, req.last_BE};
//       TLP_HEADER[2] = {req.addr[63:32]};
//       TLP_HEADER[3] = {req.addr[31:2], req.R4};
//       TLP_PAYLOAD   = req.payload;
      
//       $display("TLP_HEADER[0] = %0d",TLP_HEADER[0]);
//       $display("TLP_HEADER[1] = %0d",TLP_HEADER[1]);
//       $display("TLP_HEADER[2] = %0d",TLP_HEADER[2]);
//       $display("TLP_HEADER[3] = %0d",TLP_HEADER[3]);
//       $display("TLP_PAYLOAD = %0d",  TLP_PAYLOAD);
      
//       TLP_PACKET = {TLP_HEADER[0], TLP_HEADER[1], TLP_HEADER[2], TLP_HEADER[3], TLP_PAYLOAD};
//       $display("TLP_PACKET = %0d", TLP_PACKET);
      
//       send_packet(TLP_PACKET);

//       seq_item_port.item_done(req);
//     end
    
//   endtask : run_phase
  
//   task send_packet(bit [159:0] tlp_packet);
//     bit [31:0] dw;
//     for (int i = 4; i >= 0; i--) begin
//       dw = tlp_packet[i*32 +: 32];    
//       send_dw(dw);                
//     end
//   endtask
  
//   task send_dw(bit [31:0] data);
//     @(posedge TX_TL_DL.CLK);
    
//     if(TX_TL_DL.RESET) begin
//       TX_TL_DL.tl_tx_valid <= 1;
//       TX_TL_DL.tl_tx_data  <= data;
//     end
    
//     while (!TX_TL_DL.tl_tx_ready) begin
//       @(posedge TX_TL_DL.CLK);
//     end
    
//     @(posedge TX_TL_DL.CLK);
//     TX_TL_DL.tl_tx_valid <= 0;
  endtask
  
endclass : TX_TL_Driver
