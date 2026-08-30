#=====================================================================
# run_all.do  -  full PCIe regression, all tests, one after another
#
# Usage (from the sim/ directory):
#   vsim -c -do run_all.do
#
#   Options (override before "do run_all.do", or -gvar on the cmdline):
#     set regression_name  my_regr      ;# label in the summary
#     set gen              1            ;# 1 / 2 / 3  (advertised PCIe generation)
#     set verbosity        UVM_LOW      ;# per-test UVM verbosity
#     set only             ""           ;# run just one test, e.g. Single_Mem_Wr_Rd_4DW_test
#     set stop_on_fail     0            ;# 1 = abort the run at the first FAIL
#
# How it works:
#   - compiles the TB ONCE
#   - then launches a SEPARATE child vsim per test (UVM calls $finish at
#     end of test, which ends that simulation - so each test must run in
#     its own vsim). exec blocks until the child exits, so tests run
#     strictly one-after-another.
#   - each test's transcript  -> sim/<test>/<test>.log
#   - overall result          -> sim/regression_summary.log
#=====================================================================

if {![info exists regression_name]} { set regression_name "regr_all" }
if {![info exists gen]}             { set gen 1 }
if {![info exists verbosity]}       { set verbosity "UVM_LOW" }
if {![info exists only]}            { set only "" }
if {![info exists stop_on_fail]}    { set stop_on_fail 0 }

#---------------------------------------------------------------------
# Test list  (edit here to add / remove / reorder)
#---------------------------------------------------------------------
set tests {
    Single_Mem_Wr_Rd_3DW_test
    Single_Mem_Wr_Rd_4DW_test
    Multiple_Mem_Wr_Rd_3DW_test
    Multiple_Mem_Wr_Rd_4DW_test
    Single_Mem_Wr_Rd_3DW_Max_payload_test
    Single_Mem_Wr_Rd_4DW_Max_payload_test
    Multiple_Mem_Wr_Rd_3DW_rand_length_test
    B2B_Mem_Wr_Rd_3DW_test
    B2B_Mem_Wr_Rd_4DW_test
    Single_IO_Wr_Rd_3DW_test
    Multiple_IO_Wr_Rd_3DW_test
    B2B_IO_Wr_Rd_3DW_test
    LTSSM_Disabled_test
    LTSSM_Loopback_test
    LTSSM_HotReset_test
    TL_ECRC_Error_test
    TL_Length_Mismatch_test
    TL_IO_Length_test
    TL_CFG_Length_test
    TL_Fmt_Rtype_Illegal_test
    TL_Bad_BE_test
    TL_EP_Poison_test
    TL_Unsupported_Request_test
    TL_Completer_Abort_test
    DLL_LCRC_Error_test
    DLL_DLLP_CRC_Error_test
    DLL_Seq_Num_test
    PHY_STP_Framing_Error_test
    DLL_Replay_Num_Rollover_test
    DLL_Replay_Timer_test
}

if {$only ne ""} { set tests [list $only] }

set SimDir     "./sim"
set SummaryLog "$SimDir/regression_summary.log"
if {![file exists $SimDir]} { file mkdir $SimDir }

#---------------------------------------------------------------------
# Compile once
#---------------------------------------------------------------------
puts ""
puts "============================================================"
puts "                 PCIe REGRESSION : $regression_name"
puts "  Tests=[llength $tests]   Gen=$gen   Verbosity=$verbosity"
puts "============================================================"

if {[file exists work]} { vdel -all }
vlib work
vmap work work

if {[catch {
    vlog -work work -sv \
        +define+NUM_RC=1 +define+NUM_EP=1 \
        +define+NUM_RC_GEN=$gen +define+NUM_EP_GEN=$gen \
        ../top/Package.sv ../top/TOP.sv
} cerr]} {
    puts "COMPILATION FAILED:\n$cerr"
    quit -f
}
puts "Compilation OK."

#---------------------------------------------------------------------
# check_result : PASS only if the test finished AND raised no errors
#---------------------------------------------------------------------
proc check_result {logfile} {
    if {![file exists $logfile]} { return "FAIL (no log)" }
    set fh [open $logfile r]; set data [read $fh]; close $fh
    if {![regexp {UVM Report Summary} $data]}          { return "FAIL (did not finish)" }
    if {[regexp {UVM_FATAL\s*:\s*[1-9]} $data]}        { return "FAIL (uvm_fatal)" }
    if {[regexp {UVM_ERROR\s*:\s*[1-9]} $data]}        { return "FAIL (uvm_error)" }
    if {[regexp {(TEST FAILED|Fatal:|\*\* Error)} $data]} { return "FAIL" }
    return "PASS"
}

#---------------------------------------------------------------------
# Run each test in its own child vsim, sequentially
#---------------------------------------------------------------------
set Passed {}
set Failed {}
set StartAll [clock seconds]
set n [llength $tests]
set i 0

foreach test $tests {
    incr i
    set TestDir "$SimDir/$test"
    set LogFile "$TestDir/$test.log"
    if {[file exists $TestDir]} { file delete -force $TestDir }
    file mkdir $TestDir

    puts ""
    puts "------------------------------------------------------------"
    puts " \[$i/$n\]  $test"
    puts "------------------------------------------------------------"
    set t0 [clock seconds]

    catch {
        exec vsim.exe -c \
            work.PCIe_top \
            +UVM_TESTNAME=$test +UVM_VERBOSITY=$verbosity \
            -l $LogFile \
            -do "run -all; quit -f"
    } rc

    set dt [expr {[clock seconds] - $t0}]
    set res [check_result $LogFile]
    puts " RESULT : $res    (${dt}s)"

    if {[string match "PASS*" $res]} {
        lappend Passed $test
    } else {
        lappend Failed [list $test $res]
        if {$stop_on_fail} {
            puts "stop_on_fail set - aborting regression."
            break
        }
    }
}

set DurAll [expr {[clock seconds] - $StartAll}]

#---------------------------------------------------------------------
# Summary
#---------------------------------------------------------------------
set report ""
append report "PCIe REGRESSION SUMMARY\n"
append report "Regression : $regression_name\n"
append report "Gen        : $gen\n"
append report "Total      : $n\n"
append report "PASS       : [llength $Passed]\n"
append report "FAIL       : [llength $Failed]\n"
append report "Duration   : ${DurAll} sec\n\n"
append report "PASSED TESTS\n"
foreach t $Passed { append report "  PASS : $t\n" }
append report "\nFAILED TESTS\n"
foreach t $Failed { append report "  FAIL : [lindex $t 0]   -> [lindex $t 1]\n" }
if {[llength $Failed] == 0} { append report "  (none)\n" }

set fh [open $SummaryLog w]; puts $fh $report; close $fh

puts ""
puts "============================================================"
puts $report
puts "Summary written to: $SummaryLog"
if {[llength $Failed] == 0} { puts "REGRESSION PASSED" } else { puts "REGRESSION FAILED" }
puts "============================================================"

quit -f
