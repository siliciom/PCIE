class PCIe_MAC_monitor extends uvm_monitor;
  `uvm_component_utils(PCIe_MAC_monitor)

  env_cfg cfg;
  string  tag;

  virtual TX_DLL_PCS_Interface rc_vif;
  virtual pipe_tx_interface    rc_pvif;

  virtual RX_DLL_PCS_Interface ep_vif;
  virtual pipe_rx_interface    ep_pvif;
  
  uvm_analysis_port #(Sequence_item) mac_tx_dll_port;
  uvm_analysis_port #(Sequence_item) mac_tx_rx_port;

  uvm_analysis_port #(Sequence_item) mac_rx_dll_port;
  uvm_analysis_port #(Sequence_item) mac_rx_rx_port;

  Sequence_item rc_item;
  bit [31:0]  rc_r_data[$];
  bit [31:0]  rc_mac_data[$];
  bit [127:0] rc_decoded_data;
  bit [31:0]  rc_os_queue[$];
  bit [10:0]  rc_length;
  bit [11:0]  rc_seq_no;
  bit [3:0]   rc_fcrc;
  bit         rc_f_p;
  bit [31:0]  rc_stp;
  bit [31:0]  rc_tlp_queue[$];
  bit [63:0]  rc_dllp_packet;
  bit [31:0]  rc_dlp_p_q[$];
  bit [127:0] rc_os_data;

  Sequence_item ep_item;
  bit [31:0]  ep_r_data[$];
  bit [127:0] ep_decoded_data;
  bit [31:0]  ep_mac_data[$];
  bit [31:0]  ep_os_queue[$];
  bit [10:0]  ep_length;
  bit [11:0]  ep_seq_no;
  bit [3:0]   ep_fcrc;
  bit         ep_f_p;
  bit [129:0] ep_data;
  bit [31:0]  ep_stp;
  bit [31:0]  ep_tlp_queue[$];
  bit [63:0]  ep_dllp_packet;
  bit [31:0]  ep_dlp_p_q[$];
  bit [127:0] ep_os_data;

  bit [22:0] polynomial = 23'h1DBFBC;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("mac_tx_monitor", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_MAC_monitor", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    mac_tx_dll_port = new("mac_tx_dll_port", this);
    mac_tx_rx_port  = new("mac_tx_rx_port",  this);
    mac_rx_dll_port = new("mac_rx_dll_port", this);
    mac_rx_rx_port  = new("mac_rx_rx_port",  this);

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", rc_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] TX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))
        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", rc_pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_tx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("PCIe_MAC_monitor", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", ep_vif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] RX_DLL_PCS_Interface not set (DLL_Vif missing)", tag))
        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", ep_pvif))
          `uvm_fatal("NO_VIF", $sformatf("[%s] pipe_rx_interface not set (pipe_Vif missing)", tag))

        `uvm_info("PCIe_MAC_monitor", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_MAC_monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

   function bit [7:0] d_s(inout bit [7:0] data);
    static bit [22:0] lfsr = 23'h7FFFFF;
    for (int i = 0; i < 8; i++) begin
      if (lfsr[22]) lfsr = (lfsr << 1) ^ polynomial;
      else          lfsr = (lfsr << 1);
      data[i] = lfsr[22] ^ data[i];
    end
    return data;
  endfunction

  function bit [127:0] os_s(inout bit [127:0] TS);
    for(int i = 8; i < 113; i = i+8) begin
      TS[i+:8] = d_s(TS[i+:8]);
    end
  endfunction

    function void rc_data_scrambling(bit TL_DL);
    bit [31:0] data;
    if(TL_DL) begin
      for(int i= 0; i<rc_tlp_queue.size(); i++) begin
        data = rc_tlp_queue[i];
        rc_tlp_queue[i] = {d_s(data[31:24]),d_s(data[23:16]),d_s(data[15:8]),d_s(data[7:0])};
      end
    end
    else begin
      rc_dllp_packet = {d_s(rc_dllp_packet[63:56]),d_s(rc_dllp_packet[55:48]),d_s(rc_dllp_packet[47:40]),d_s(rc_dllp_packet[39:32]),d_s(rc_dllp_packet[31:24]),d_s(rc_dllp_packet[23:16]),16'h0};
    end
  endfunction

   function void ep_data_scrambling(bit TL_DL);
    bit [31:0] data;
    if(TL_DL) begin
      for(int i= 0; i<ep_tlp_queue.size(); i++) begin
        data = ep_tlp_queue[i];
        ep_tlp_queue[i] = {d_s(data[31:24]),d_s(data[23:16]),d_s(data[15:8]),d_s(data[7:0])};
      end
    end
    else begin
      ep_dllp_packet = {d_s(ep_dllp_packet[63:56]),d_s(ep_dllp_packet[55:48]),d_s(ep_dllp_packet[47:40]),d_s(ep_dllp_packet[39:32]),d_s(ep_dllp_packet[31:24]),d_s(ep_dllp_packet[23:16]),16'h0};
    end
  endfunction

  virtual task run_phase(uvm_phase phase);

    case(cfg.mode)

      RC_MODE: begin

		super.run_phase(phase);
        //item_port.write(rc_item);
          
    rc_vif.dl_tx_ready = 0;
       @(posedge rc_vif.CLK);
     rc_vif.dl_tx_ready = 1;
   fork
      begin
      rc_item = Sequence_item::type_id::create("rc_item");
      forever begin
     
     // @(negedge rc_vif.CLK);
        @(posedge rc_vif.dl_tx_valid);
     // if (rc_vif.dl_tx_valid && rc_vif.dl_tx_ready) begin
        
        while(1) begin
       // $display("time at monitor %t",$time);
        
        @(posedge rc_vif.CLK);
          if(rc_vif.dl_tx_valid && rc_vif.dl_tx_ready && rc_vif.tl_packet) begin
          //rc_item.mac_rx_data.push_back({});
          rc_mac_data.push_back(rc_vif.dl_tx_data);
          end
	 else if(rc_vif.dl_tx_valid && rc_vif.dl_tx_ready && rc_vif.dl_packet) begin
             rc_item.dllp_tx_packet.push_back(rc_vif.dl_tx_data);
       `uvm_info("MAC_TX_MON", $sformatf("DLLL_tx_PACKET %p",rc_item.dllp_tx_packet),UVM_LOW)
     end
          else
            break;
        //  $display("time at monitor %t data = %p",$time,rc_item.tx_data);
        //rc_item.print();
        end
	foreach(rc_mac_data[i])
        `uvm_info("MAC_TX_MON", $sformatf("DLL Packet Sent %h",rc_mac_data[i]),UVM_LOW)
        rc_item.mac_tx_data.push_back(rc_mac_data);
       // $display("time at monitor %t data = %p",$time,rc_item.tx_data);
        `uvm_info("MAC_TX_MON", $sformatf("DLL Packet Sent %p size %d count = %d",rc_item.mac_tx_data,rc_item.mac_tx_data.size(),rc_item.count_tlp),UVM_LOW)
        rc_mac_data.delete();
        
        if((rc_item.mac_tx_data.size() == rc_item.count_tx_tlp) || (rc_item.dllp_tx_packet.size()>0)) begin
          `uvm_info("MAC_TX_MON", $sformatf("MATCHED_DLLL %p %d",rc_item.mac_tx_data,rc_item.dllp_tx_packet.size()),UVM_LOW)
        mac_tx_dll_port.write(rc_item);
	rc_item.dllp_tx_packet.delete();
          `uvm_info("MAC_TX_MON", $sformatf("WRITE COMPLETED"),UVM_LOW)
        end
        `uvm_info("MAC_TX_MON", $sformatf("DLLL_PACKET %p",rc_item.dllp_tx_packet),UVM_LOW)      
      
        end
        end
   begin   
      forever begin

    
  rc_item = Sequence_item::type_id::create("rc_item");

  @(posedge rc_pvif.RxValid);

  while(1) begin

    @(negedge rc_pvif.PCLK)

    if(!rc_pvif.RxValid)
      break;

    if(rc_pvif.RxData[129:128] == 2'b10) begin

      rc_decoded_data = rc_pvif.RxData[127:0];

      // Split 128 -> 4 x 32
      for(int i = 0; i < 4; i++) begin
        rc_r_data.push_back(rc_decoded_data[(3-i)*32 +: 32]);
      end
    end
    else if(rc_pvif.RxData[129:128] == 2'b01) begin
      case(rc_pvif.RxData[127:120])
        8'h1E : begin
          rc_os_data = rc_pvif.RxData[127:0];
          void'(os_s(rc_os_data));
          rc_item.os_t.push_back(rc_os_data);
          `uvm_info("MAC_TX", $sformatf("Packet Sent %h",rc_os_data),UVM_LOW)
        end
        8'h2D : begin
          rc_os_data = rc_pvif.RxData[127:0];
          void'(os_s(rc_os_data));
          rc_item.os_t.push_back(rc_os_data);
          `uvm_info("MAC_TX", $sformatf("Packet Sent %h",rc_os_data),UVM_LOW)
        end
         8'h00 : begin
          rc_os_data = rc_pvif.RxData[127:0];
          rc_item.os_t.push_back(rc_os_data);
          `uvm_info("MAC_TX", $sformatf("Packet Sent %h",rc_os_data),UVM_LOW)
        end
      endcase
    end
  end
     
    foreach(rc_r_data[i])
    `uvm_info("MAC_TX_MON", $sformatf("Packet Sent %h",rc_r_data[i]),UVM_LOW)

  //------------------------------------------------
  // Parse all packets from rc_r_data
  //------------------------------------------------
  while(rc_r_data.size() > 0) begin
    //`uvm_info("MAC_TX_MON", $sformatf("INSIDE WHILE LOOP"),UVM_LOW)

    if(rc_r_data[0][27:24] == 4'hF) begin
      rc_stp = rc_r_data.pop_front();
      rc_length = {rc_stp[22:16], rc_stp[31:28]};
      rc_fcrc  = rc_stp[15:12];
      rc_seq_no = {rc_stp[7:0], rc_stp[11:8]};

      `uvm_info("MAC_TX",$sformatf("STP=%h rc_length=%0d seq=%0h",rc_stp,rc_length,rc_seq_no),UVM_LOW)

     // rc_tlp_queue.delete();

          for(int i = 0; i < (rc_length-1); i++) 
	    begin
	      if(rc_r_data.size() == 0)
               break;

             rc_tlp_queue.push_back(rc_r_data.pop_front());
             // `uvm_info("MAC_RX",$sformatf("TLP Queue = %p i = %d rc_length = %d",rc_tlp_queue,i,rc_length),UVM_LOW)

           end

           if(rc_r_data.size() >= 2) begin

              if(rc_r_data[0][31:16] == 16'hF0AC) begin

                   rc_dllp_packet = {
                          rc_r_data[0][15:0],
                          rc_r_data[1][31:16],
                          rc_r_data[1][15:0],
                          16'h0
                        };

                   rc_r_data.delete(0);
                   rc_r_data.delete(0);

                  `uvm_info("MAC_TX",
                    $sformatf("DLLP = %h", rc_dllp_packet),
                    UVM_LOW)
              end
           end
      
        if(rc_r_data[0] == 32'h1f809000) begin
          //end_packet = rc_r_data.pop_front();
          `uvm_info("MAC_TX", $sformatf("BEFORE_SCRAMBLING %p  time = %t",rc_tlp_queue,$time),UVM_LOW)
          rc_data_scrambling(1);
          `uvm_info("MAC_TX", $sformatf("AFTER_SCRAMBLING  %p  time = %t",rc_tlp_queue,$time),UVM_LOW)

          rc_item.tlp_queue = rc_tlp_queue;
            rc_r_data.delete();
          `uvm_info("MAC_TX", $sformatf("MAC RX DATA CAPTURED %p time = %t",rc_tlp_queue,$time),UVM_LOW)
        end
      end
     else if(rc_r_data[0][31:16] == 16'hF0AC) begin
           `uvm_info("MAC_TX_MON", $sformatf("INSIDE WHILE LOOP"),UVM_LOW)
            rc_dlp_p_q.push_back({rc_r_data[0][15:0],rc_r_data[1][31:16]});
	    rc_dlp_p_q.push_back({rc_r_data[1][15:0],16'h0});
	    rc_r_data.delete(0);
	    rc_r_data.delete(0);
            foreach(rc_r_data[i])
		    rc_dlp_p_q.push_back(rc_r_data[i]);
          rc_item.dlp_queue = rc_dlp_p_q;
	   foreach(rc_dlp_p_q[i])
              `uvm_info("MAC_TX_MON", $sformatf("Packet Sent %h",rc_dlp_p_q[i]),UVM_LOW)
	  rc_r_data.delete();
    end

    end
   // else begin
      //  if(rc_pvif.RxValid == 0) begin
     `uvm_info("MAC_TX_MON",$sformatf("ODERED SETS = %p", rc_item.os_t),UVM_LOW)
          mac_tx_rx_port.write(rc_item);
          
           rc_item.os_t.delete();
      // end
   end

  end
   join_none
//end
      end

      EP_MODE: begin

		super.run_phase(phase);
        //item_port.write(ep_item);
      
               
    ep_vif.dl_tx_ready = 0;
       @(posedge ep_vif.CLK);
     ep_vif.dl_tx_ready = 1;
   fork
      begin
     ep_item = Sequence_item::type_id::create("ep_item");
      forever begin
     
     // @(negedge ep_vif.CLK);
        @(posedge ep_vif.dl_tx_valid);
     // if (ep_vif.dl_tx_valid && ep_vif.dl_tx_ready) begin
        
        while(1) begin
       // $display("time at monitor %t",$time);
        
        @(negedge ep_vif.CLK);
          if(ep_vif.dl_tx_valid && ep_vif.dl_tx_ready && ep_vif.tl_packet) begin
          //ep_item.mac_rx_data.push_back({});
          ep_mac_data.push_back(ep_vif.dl_tx_data);
//	foreach(ep_mac_data[i]) 
 //       `uvm_info("MAC_RX_MON", $sformatf("DLL_Packet_Sent %h valid = %d ready %d tl_packet = %d",ep_mac_data[i],ep_vif.dl_tx_valid, ep_vif.dl_tx_ready,ep_vif.tl_packet),UVM_LOW)
          end
	 else if(ep_vif.dl_tx_valid && ep_vif.dl_tx_ready && ep_vif.dl_packet) begin
             ep_item.dllp_packet.push_back(ep_vif.dl_tx_data);
   //     `uvm_info("MAC_RX_MON", $sformatf("DLLL_PACKET %p",ep_item.dllp_packet),UVM_LOW)
     end
     else begin
     //   `uvm_info("MAC_RX_MON", $sformatf("CHECK_DLL_Packet_Sent %p valid = %d ready %d tl_packet = %d",ep_mac_data,ep_vif.dl_tx_valid, ep_vif.dl_tx_ready,ep_vif.tl_packet),UVM_LOW)
       // `uvm_info("MAC_RX_MON", $sformatf("BREAK_CALLED"),UVM_LOW)
            break;

    end
        //  $display("time at monitor %t data = %p",$time,ep_item.tx_data);
        //ep_item.print();
        end
	//foreach(ep_mac_data[i]) 
        //`uvm_info("MAC_RX_MON", $sformatf("DLL_Packet_Sent_1 %h",ep_mac_data[i]),UVM_LOW)
        ep_item.mac_rx_data.push_back(ep_mac_data);
       // $display("time at monitor %t data = %p",$time,ep_item.tx_data);
        `uvm_info("MAC_RX_MON", $sformatf("DLL Packet Sent %p size %d count = %d",ep_item.mac_rx_data,ep_item.mac_rx_data.size(),ep_item.count_tlp),UVM_LOW)
        ep_mac_data.delete();
        
        if((ep_item.mac_rx_data.size() == ep_item.count_tlp)||(ep_item.dllp_packet.size()>0)) begin
        `uvm_info("MAC_RX_MON", $sformatf("MATCHED_RX_DLLL %p %p %d",ep_item.mac_rx_data,ep_item.dllp_packet,ep_item.count_tlp),UVM_LOW)
        mac_rx_dll_port.write(ep_item);
	ep_item.dllp_packet.delete();
        `uvm_info("MAC_RX_MON", $sformatf("WRITE COMPLETED"),UVM_LOW)
        end
        `uvm_info("MAC_RX_MON", $sformatf("DLLL_PACKET %p",ep_item.dllp_packet),UVM_LOW)
	//mac_rx_dll_port.write(ep_item);
      end
    end
 
      
      
      
   begin   
      
   forever begin

  ep_item = Sequence_item::type_id::create("ep_item");

  @(posedge ep_pvif.RxValid);

  while(1) begin

    @(negedge ep_pvif.PCLK)

    if(!ep_pvif.RxValid)
      break;

    if(ep_pvif.RxData[129:128] == 2'b10) begin

      ep_decoded_data = ep_pvif.RxData[127:0];

      // Split 128 -> 4 x 32
      for(int i = 0; i < 4; i++) begin
        ep_r_data.push_back(ep_decoded_data[(3-i)*32 +: 32]);
      end
    end
    else if(ep_pvif.RxData[129:128] == 2'b01) begin
      case(ep_pvif.RxData[127:120])
        8'h1E : begin
          ep_os_data = ep_pvif.RxData[127:0];
          void'(os_s(ep_os_data));
          ep_item.os_t.push_back(ep_os_data);
         // `uvm_info("MAC_RX", $sformatf("Packet Sent %h",ep_os_data),UVM_LOW)
        end
         8'h2D : begin
          ep_os_data = ep_pvif.RxData[127:0];
          void'(os_s(ep_os_data));
          ep_item.os_t.push_back(ep_os_data);
         // `uvm_info("MAC_RX", $sformatf("Packet Sent %h",ep_os_data),UVM_LOW)
        end
        8'h00 : begin
          $display("data %h",ep_pvif.RxData);
          ep_os_data = ep_pvif.RxData[127:0];
          //void'(os_s(ep_os_data));
          ep_item.os_t.push_back(ep_os_data);
        end
      endcase
    end
  end
     
  `uvm_info("MAC_RX",$sformatf("Complete ep_r_data = %p", ep_r_data),UVM_LOW)

  while(ep_r_data.size() > 0) begin

    if(ep_r_data[0][27:24] == 4'hF) begin

      ep_stp = ep_r_data.pop_front();
      ep_length = {ep_stp[22:16], ep_stp[31:28]};
      ep_fcrc  = ep_stp[15:12];
      ep_seq_no = {ep_stp[7:0], ep_stp[11:8]};

      `uvm_info("MAC_RX",$sformatf("STP=%h ep_length=%0d seq=%0h",ep_stp,ep_length,ep_seq_no),UVM_LOW)

     // ep_tlp_queue.delete();

      for(int i = 0; i < (ep_length-1); i++) begin

        if(ep_r_data.size() == 0)
          break;

        ep_tlp_queue.push_back(ep_r_data.pop_front());
       // `uvm_info("MAC_RX",$sformatf("TLP Queue = %p i = %d ep_length = %d",ep_tlp_queue,i,ep_length),UVM_LOW)

      end

      if(ep_r_data.size() >= 2) begin

        if(ep_r_data[0][31:16] == 16'hF0AC) begin

          ep_dllp_packet = {
                          ep_r_data[0][15:0],
                          ep_r_data[1][31:16],
                          ep_r_data[1][15:0],
                          16'h0
                        };

          ep_r_data.delete(0);
          ep_r_data.delete(0);

          `uvm_info("MAC_RX",
                    $sformatf("DLLP = %h", ep_dllp_packet),
                    UVM_LOW)
        end
      end

      if(ep_r_data[0] == 32'h1f809000) begin

          //end_packet =1r_data.pop_front();
          `uvm_info("MAC_RX", $sformatf("BEFORE_SCRAMBLING %p  time = %t",ep_tlp_queue,$time),UVM_LOW)
        ep_data_scrambling(1);
          `uvm_info("MAC_RX", $sformatf("AFTER_SCRAMBLING  %d  time = %t",ep_tlp_queue.size(),$time),UVM_LOW)

          ep_item.tlp_queue_t = ep_tlp_queue;
           ep_r_data.delete();
          `uvm_info("MAC_RX", $sformatf("EP MAC RX DATA CAPTURED %p  time = %t",ep_tlp_queue,$time),UVM_LOW)
        end
      end
       else if(ep_r_data[0][31:16] == 16'hF0AC) begin
           `uvm_info("MAC_TX_MON", $sformatf("INSIDE WHILE LOOP"),UVM_LOW)
            ep_dlp_p_q.push_back({ep_r_data[0][15:0],ep_r_data[1][31:16]});
	    ep_dlp_p_q.push_back({ep_r_data[1][15:0],16'h0});
	    ep_r_data.delete(0);
	    ep_r_data.delete(0);
            foreach(ep_r_data[i])
		    ep_dlp_p_q.push_back(ep_r_data[i]);
          ep_item.dlp_rx_queue = ep_dlp_p_q;
	   foreach(ep_dlp_p_q[i])
              `uvm_info("MAC_TX_MON", $sformatf("Packet Sent %h",ep_dlp_p_q[i]),UVM_LOW)
	  ep_r_data.delete();
      end
    end
   // else begin
      //  if(ep_pvif.RxValid == 0) begin
     `uvm_info("MAC_RX_MON", $sformatf("EP MAC RX ORDEREDSET CAPTURED %p  time = %t",ep_tlp_queue,$time),UVM_LOW)
           mac_rx_rx_port.write(ep_item);
           
          ep_item.os_t.delete();
      // end
   end

 end
   join_none
//end
      end

      default: `uvm_fatal("PCIe_MAC_monitor", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask
endclass
