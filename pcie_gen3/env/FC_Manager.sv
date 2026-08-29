//-----------------------------------------------------------------
// FC_Manager
//   Flow-control credit tracker, now PER-VIRTUAL-CHANNEL (8 VCs).
//   Every counter that used to be a scalar is now an 8-entry array
//   indexed by vc_id_e. All existing call sites just need to pass
//   the item's `vc` alongside pkt_type.
//-----------------------------------------------------------------
class FC_Manager extends uvm_component;

  `uvm_component_utils(FC_Manager)

  // NEW: pulsed every time consume_credit()/return_credit() actually
  // changes a counter. PCIe_TL_Driver's drive_tx_fc_thread/drive_rx_fc_thread
  // block on this instead of blindly re-driving the interface every clock -
  // this IS the "flag" that tells the DL layer a fresh (post-INITFC) credit
  // update is available and an UPDATEFC DLLP needs to go out.
  uvm_event fc_update_ev;

  // Last VC that changed - purely informational/logging, mirrors what
  // triggered fc_update_ev most recently.
  vc_id_e last_updated_vc;

  function new(string name = "FC_Manager", uvm_component parent);
    super.new(name,parent);
    fc_update_ev = new("fc_update_ev");
  endfunction

  localparam int PH_TOTAL   = 128;
  localparam int NPH_TOTAL  = 128;
  localparam int CPLH_TOTAL = 128;

  localparam int PD_TOTAL   = 2048;
  localparam int NPD_TOTAL  = 2048;
  localparam int CPLD_TOTAL = 2048;

  // [8] => one pool per VC (VC0..VC7)
  reg [7:0][7:0] ph_avail;
  reg [7:0][7:0] nph_avail;
  reg [7:0][7:0] cplh_avail;

  reg [7:0][11:0] pd_avail;
  reg [7:0][11:0] npd_avail;
  reg [7:0][11:0] cpld_avail;

  reg [7:0][7:0] ph_return = 0;
  reg [7:0][7:0] nph_return = 0;
  reg [7:0][7:0] cplh_return = 0;

  reg [7:0][11:0] pd_return = 0;
  reg [7:0][11:0] npd_return = 0;
  reg [7:0][11:0] cpld_return = 0;


  function void build_phase(uvm_phase phase);

    super.build_phase(phase);

    foreach (ph_avail[v]) begin
      ph_avail[v]   = PH_TOTAL;
      nph_avail[v]  = NPH_TOTAL;
      cplh_avail[v] = CPLH_TOTAL;

      pd_avail[v]   = PD_TOTAL;
      npd_avail[v]  = NPD_TOTAL;
      cpld_avail[v] = CPLD_TOTAL;
    end

  endfunction

  function void consume_credit(vc_id_e vc, packet_type_e pkt_type, int header_credit, int data_credit);

    `uvm_info("FC_Manager", $sformatf("[%0t] consume_credit called (vc=%0d)", $time, vc), UVM_LOW);

    `uvm_info("FC_Manager", $sformatf("vc=%0d pkt_type=%s hc=%0d dc=%0d", vc, pkt_type.name(), header_credit, data_credit), UVM_LOW);

    case(pkt_type)

      P: begin
        ph_avail[vc] -= header_credit;
        pd_avail[vc] -= data_credit;
      end

      NP: begin
        nph_avail[vc] -= header_credit;
        npd_avail[vc] -= data_credit;
      end

      CMPL: begin
        cplh_avail[vc] -= header_credit;
        cpld_avail[vc] -= data_credit;
      end

    endcase

    `uvm_info("FC", $sformatf("CONSUME vc=%0d %s hc=%0d dc=%0d -> now PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d",
         vc, pkt_type.name(), header_credit, data_credit,
         ph_avail[vc], pd_avail[vc], nph_avail[vc], npd_avail[vc], cplh_avail[vc], cpld_avail[vc]), UVM_MEDIUM)

    send_fc_update(vc);

    // NEW: wake up whoever is waiting to push a fresh value onto the
    // TL<->DL interface (see PCIe_TL_Driver::drive_tx/rx_fc_thread).
    last_updated_vc = vc;
    fc_update_ev.trigger();

  endfunction


  function void calc_required_credit(Sequence_item req, output int hdr_credit, output int data_credit); 

    case(req.pkt_type)

      P : begin data_credit = (req.length + 3)/4; hdr_credit = 1; end
      NP : if(req.e_type == MEM_RD) begin data_credit = 0; hdr_credit = 1; end
          else begin data_credit = (req.length + 3)/4; hdr_credit = 1; end

	  CMPL: begin data_credit = (req.length + 3)/4; hdr_credit = 1; end

    endcase

  endfunction


  function void return_credit(vc_id_e vc, packet_type_e pkt_type, int header_credit, int data_credit);

    case(pkt_type)

       P: begin
         ph_return[vc] += header_credit;
         pd_return[vc] += data_credit;
       end

       NP: begin
         nph_return[vc] += header_credit;
         npd_return[vc] += data_credit;
       end

       CMPL: begin
         cplh_return[vc] += header_credit;
         cpld_return[vc] += data_credit;
       end

    endcase

   send_fc_update(vc);

    // NEW: same wakeup as consume_credit() - a credit was just returned
    // (buffer freed after LUT processing), so the advertised value going
    // out to the link partner needs to be re-driven / re-advertised.
    last_updated_vc = vc;
    fc_update_ev.trigger();


    `uvm_info("FC", $sformatf("RETURN vc=%0d %s hc=%0d dc=%0d -> return-pool PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d",
         vc, pkt_type.name(), header_credit, data_credit,
         ph_return[vc], pd_return[vc], nph_return[vc], npd_return[vc], cplh_return[vc], cpld_return[vc]), UVM_MEDIUM)

  endfunction

  function void send_fc_update(vc_id_e vc);

    `uvm_info("FC", $sformatf("vc=%0d avail: PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d",
              vc, ph_avail[vc], pd_avail[vc], nph_avail[vc], npd_avail[vc], cplh_avail[vc], cpld_avail[vc]), UVM_HIGH)

  endfunction


  function bit has_sufficient_credit(vc_id_e vc, Sequence_item req);

    int hdr_req, data_req;
    int hdr_avail, data_avail;
    int hdr_short, data_short;

    calc_required_credit(req, hdr_req, data_req);

    case(req.pkt_type)

        P: begin
            hdr_avail  = ph_avail[vc];
            data_avail = pd_avail[vc];
        end

        NP: begin
            hdr_avail  = nph_avail[vc];
            data_avail = npd_avail[vc];
        end

        CMPL: begin
            hdr_avail  = cplh_avail[vc];
            data_avail = cpld_avail[vc];
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

  function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);
    s = "\n================ FC_Manager SUMMARY (credits remaining) ================\n";
    foreach (ph_avail[v]) begin
      if (ph_avail[v] != PH_TOTAL || pd_avail[v] != PD_TOTAL ||
          nph_avail[v] != NPH_TOTAL || npd_avail[v] != NPD_TOTAL ||
          cplh_avail[v] != CPLH_TOTAL || cpld_avail[v] != CPLD_TOTAL)
        s = {s, $sformatf("  VC%0d: PH=%0d/%0d PD=%0d/%0d NPH=%0d/%0d NPD=%0d/%0d CPLH=%0d/%0d CPLD=%0d/%0d\n",
                          v, ph_avail[v], PH_TOTAL, pd_avail[v], PD_TOTAL,
                          nph_avail[v], NPH_TOTAL, npd_avail[v], NPD_TOTAL,
                          cplh_avail[v], CPLH_TOTAL, cpld_avail[v], CPLD_TOTAL)};
    end
    s = {s, "======================================================================"};
    `uvm_info("FC", s, UVM_NONE)
  endfunction

endclass : FC_Manager


