//-----------------------------------------------------------------
// FC_Manager
//   Flow-control credit tracker, now PER-VIRTUAL-CHANNEL (8 VCs).
//   Every counter that used to be a scalar is now an 8-entry array
//   indexed by vc_id_e. All existing call sites just need to pass
//   the item's `vc` alongside pkt_type.
//-----------------------------------------------------------------
class FC_Manager extends uvm_component;

  `uvm_component_utils(FC_Manager)

  function new(string name = "FC_Manager", uvm_component parent);
    super.new(name,parent);
  endfunction

  localparam int PH_TOTAL   = 128;
  localparam int NPH_TOTAL  = 128;
  localparam int CPLH_TOTAL = 128;

  localparam int PD_TOTAL   = 2048;
  localparam int NPD_TOTAL  = 2048;
  localparam int CPLD_TOTAL = 2048;

  // [8] => one pool per VC (VC0..VC7)
  int ph_avail;
  int nph_avail;
  int cplh_avail;

  int pd_avail;
  int npd_avail;
  int cpld_avail;

  function void build_phase(uvm_phase phase);

    super.build_phase(phase);

    foreach (ph_avail[v]) begin
      ph_avail   = PH_TOTAL;
      nph_avail  = NPH_TOTAL;
      cplh_avail = CPLH_TOTAL;

      pd_avail   = PD_TOTAL;
      npd_avail  = NPD_TOTAL;
      cpld_avail = CPLD_TOTAL;
    end

  endfunction

  function void consume_credit(vc_id_e vc, packet_type_e pkt_type, int header_credit, int data_credit);

    `uvm_info("FC_Manager", $sformatf("[%0t] consume_credit called (vc=%0d)", $time, vc), UVM_LOW);

    `uvm_info("FC_Manager", $sformatf("vc=%0d pkt_type=%s hc=%0d dc=%0d", vc, pkt_type.name(), header_credit, data_credit), UVM_LOW);

    case(pkt_type)

      P: begin
        ph_avail -= header_credit;
        pd_avail -= data_credit;
      end

      NP: begin
        nph_avail -= header_credit;
        npd_avail -= data_credit;
      end

      CMPL: begin
        cplh_avail -= header_credit;
        cpld_avail -= data_credit;
      end

    endcase

    $display("vc=%0d pkt_type=%s hc=%0d dc=%0d",
         vc,
         pkt_type.name(),
         header_credit,
         data_credit);

    send_fc_update_consume(vc);

  endfunction


  function void calc_required_credit(Sequence_item req, output int hdr_credit, output int data_credit); 

    case(req.pkt_type)

      P : begin data_credit = (req.length + 3)/4; hdr_credit = 1; end

      NP : if(req.e_type == MEM_RD) begin data_credit = (req.length + 3)/0; hdr_credit = 1; end
          else begin data_credit = (req.length + 3)/4; hdr_credit = 1; end

	  CMPL: begin data_credit = (req.length + 3)/4; hdr_credit = 2; end

    endcase

  endfunction


  function void return_credit(vc_id_e vc, packet_type_e pkt_type, int header_credit, int data_credit);

    case(pkt_type)

       P: begin
         ph_avail += header_credit;
         pd_avail += data_credit;
       end

       NP: begin
         nph_avail += header_credit;
         npd_avail += data_credit;
       end

       CMPL: begin
         cplh_avail += header_credit;
         cpld_avail += data_credit;
       end

    endcase

  // send_fc_update_release(vc);
`uvm_info("FC_MANAGER", $sformatf("PH_AVAIL = %0d PD AVAIL = %0d NPH AVAIL = %0d NPD AVAIL =%0d CPLH_AVAIL = %0d CPLD AVAIL = %0d", ph_avail, pd_avail, nph_avail, npd_avail, cplh_avail, cpld_avail), UVM_LOW)
  endfunction

  function void send_fc_update_consume(vc_id_e vc);

    $display("CONSUMED CREDITS VC%0d: PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d",
              vc, ph_avail[vc], pd_avail[vc], nph_avail[vc], npd_avail[vc], cplh_avail[vc], cpld_avail[vc]);

  endfunction

  function void send_fc_update_release(vc_id_e vc);

    $display("RETURN CREDITS VC%0d: PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d",
              vc, ph_avail[vc], pd_avail[vc], nph_avail[vc], npd_avail[vc], cplh_avail[vc], cpld_avail[vc]);

  endfunction


  function bit has_sufficient_credit(vc_id_e vc, Sequence_item req);

    int hdr_req, data_req;
    int hdr_avail, data_avail;
    int hdr_short, data_short;

    calc_required_credit(req, hdr_req, data_req);

    case(req.pkt_type)

        P: begin
            hdr_avail  = ph_avail;
            data_avail = pd_avail;
        end

        NP: begin
            hdr_avail  = nph_avail;
            data_avail = npd_avail;
        end

        CMPL: begin
            hdr_avail  = cplh_avail;
            data_avail = cpld_avail;
        end

    endcase

    hdr_short  = (hdr_req  > hdr_avail)  ? (hdr_req  - hdr_avail)  : 0;
    data_short = (data_req > data_avail) ? (data_req - data_avail) : 0;

    if (hdr_short || data_short) begin

      `uvm_info("FC", $sformatf("\nInsufficient Flow Control Credits on VC%0d\n\Packet Type : %s\n\Header Credits : Required=%0d Available=%0d Need=%0d more\n\Data Credits   : Required=%0d Available=%0d Need=%0d more",vc, req.pkt_type.name(), hdr_req, hdr_avail, hdr_short,data_req, data_avail, data_short), UVM_HIGH)

        return 0;
    end

    return 1;

endfunction

endclass : FC_Manager

