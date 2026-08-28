//-----------------------------------------------------------------
// Error_Report_Catcher
//   Every negative/error-injection test in this bench works the
//   same way: drive one corrupted transaction, and the checker
//   that is supposed to catch it fires a real `uvm_error(...)`
//   (from a monitor, scoreboard, or the DLL driver's replay
//   logic). Left alone, that `uvm_error` would fail the UVM run.
//
//   This catcher lets a test "arm" the specific report ID(s) (and,
//   optionally, a required substring of the message) it expects to
//   see *for the duration of that one test*. Any armed uvm_error
//   is demoted to uvm_info (re-tagged EXPECTED_<id>) and counted in
//   hit_cnt, instead of failing the test. Anything NOT armed still
//   raises a real uvm_error and can still fail the run - this
//   catcher never blanket-suppresses errors.
//
//   Usage from a test:
//     catcher = Error_Report_Catcher::get();
//     catcher.reset();
//     catcher.arm("RX_TL_MONITOR", "ECRC MISMATCH");
//     ... drive the corrupted transaction, wait bounded window ...
//     if (catcher.hit_cnt > 0) `uvm_info(...".. PASS ..")
//     else                     `uvm_error("TEST_RESULT","FAIL: ...")
//-----------------------------------------------------------------
class Error_Report_Catcher extends uvm_report_catcher;

  // one process-wide instance, registered once against the global
  // report server so it sees every uvm_error from every component
  static local Error_Report_Catcher m_inst;

  int unsigned hit_cnt;

  typedef struct {
    string id;       // required report ID (exact match)
    string substr;    // required substring of the message ("" = don't care)
  } armed_entry_s;

  armed_entry_s armed[$];

  // Running log of every demotion this catcher has ever made -
  // handy for debug / final report_phase summaries.
  string hit_log[$];

  function new(string name = "Error_Report_Catcher");
    super.new(name);
    hit_cnt = 0;
  endfunction

  //-----------------------------------------------------------
  // get(): lazily create + globally register the single instance.
  // Safe to call from every test's run_phase - registration only
  // happens once.
  //-----------------------------------------------------------
  static function Error_Report_Catcher get();
    if (m_inst == null) begin
      m_inst = new("Error_Report_Catcher");
      uvm_report_cb::add(null, m_inst);   // null = every component/report object
    end
    return m_inst;
  endfunction

  //-----------------------------------------------------------
  // arm(id, substr): expect uvm_error(id, msg) where msg contains
  // substr (leave substr empty to match on id alone).
  //-----------------------------------------------------------
  function void arm(string id, string substr = "");
    armed_entry_s e;
    e.id     = id;
    e.substr = substr;
    armed.push_back(e);
  endfunction

  // Clear the armed list and hit counter/log - call at the start of
  // every negative test so results never leak between tests.
  function void reset();
    armed.delete();
    hit_log.delete();
    hit_cnt = 0;
  endfunction

  // Plain (non-regex) substring test - avoids any glob/regex special
  // -character surprises in messages that themselves contain '*','.', etc.
  local function bit msg_contains(string haystack, string needle);
    int hlen, nlen;
    hlen = haystack.len();
    nlen = needle.len();
    if (nlen == 0) return 1;
    if (nlen > hlen) return 0;
    for (int i = 0; i <= hlen - nlen; i++) begin
      if (haystack.substr(i, i + nlen - 1) == needle)
        return 1;
    end
    return 0;
  endfunction

  //-----------------------------------------------------------
  // catch(): called by uvm_report_server for EVERY report. We only
  // ever act on UVM_ERROR severity, and only on IDs that are
  // currently armed - everything else passes through untouched.
  //-----------------------------------------------------------
  function action_e catch();
    string msg;
    string id;

    if (get_severity() != UVM_ERROR)
      return THROW;

    id  = get_id();
    msg = get_message();

    foreach (armed[i]) begin
      if (armed[i].id != id)
        continue;
      if (armed[i].substr != "" && !msg_contains(msg, armed[i].substr))
        continue;   // id matched but required substring is absent
      // Match: demote instead of failing the run.
      hit_cnt++;
      hit_log.push_back($sformatf("[%0t] EXPECTED %s: %s", $time, id, msg));
      set_severity(UVM_INFO);
      set_id({"EXPECTED_", id});
      return THROW;
    end

    return THROW;   // not armed - let it through as a real error
  endfunction

endclass : Error_Report_Catcher
