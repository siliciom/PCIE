# PCIe UVM Regression run.do
# Run: vsim -c -do "set regression_name regr_cov1; set enable_cov 1; do run.do"
# Single: vsim -c -do "set regression_name single_test; set enable_cov 1; set single_test Multiple_Mem_Wr_Rd_3DW_rand_length_test; do run.do"

if {![info exists regression_name]} { set regression_name "regr_cov1" }
if {![info exists enable_cov]} { set enable_cov 1 }

# Random seed control
#Multiple_Mem_Wr_Rd_3DW_rand_length_test
#PHY_STP_Framing_Error_test
#DLL_Replay_Timer_test
# Override on command line, e.g.: vsim -c -do "set seed 12345; do run.do"
# If not set, a seed is derived from the current time so each run is different.
if {![info exists seed]} { set seed [clock seconds] }
expr {srand($seed)}

set tests {
    B2B_Mem_Wr_Rd_4DW_test
    Single_Mem_Wr_Rd_3DW_test
    Single_Mem_Wr_Rd_4DW_test
    Multiple_Mem_Wr_Rd_3DW_test
    Multiple_Mem_Wr_Rd_4DW_test 
    B2B_Mem_Wr_Rd_3DW_test
    Single_IO_Wr_Rd_3DW_test
    Multiple_IO_Wr_Rd_3DW_test
    B2B_IO_Wr_Rd_3DW_test
    Single_Mem_Wr_Rd_3DW_Max_payload_test
    Single_Mem_Wr_Rd_4DW_Max_payload_test 
    Multiple_Mem_Wr_Rd_3DW_rand_length_test
    Multiple_Mem_Wr_Rd_4DW_rand_length_test
    LTSSM_Disabled_test
    LTSSM_Loopback_test
    LTSSM_HotReset_test
    Single_Mem_Wr_emt_Rd_3DW_test
    Multiple_Mem_Wr_Rd_3DW_tag_outstanding_test
    Multiple_Mem_Wr_Rd_3DW_tc_vc_test
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
    DLL_Replay_Num_Rollover_test
    pcie_ral_test
    
}

if {[info exists single_test]} { set tests [list $single_test] }

set SimDir "./sim"
set CovDir "./coverage_reports"
set MergedUCDB "$CovDir/merged_cov.ucdb"
set SummaryLog "$SimDir/regression_summary.log"

if {![file exists $SimDir]} { file mkdir $SimDir }
if {![file exists $CovDir]} { file mkdir $CovDir }
if {[file exists $MergedUCDB]} { file delete -force $MergedUCDB }

set StartTime [clock seconds]
set PassedTests {}
set FailedTests {}
set TestSeeds {}
set total_tests [llength $tests]

puts ""
puts "============================================================"
puts "                 PCIe UVM REGRESSION"
puts "============================================================"
puts "Regression Name : $regression_name"
puts "Coverage        : $enable_cov"
puts "Base Seed       : $seed"
puts "Total Tests     : $total_tests"
puts "============================================================"
puts ""

# Compile once
if {[file exists work]} { vdel -all }
vlib work
vmap work work

if {[catch {
    vlog -work work -cover bsectf +fcover -sv -incr -mfcu \
        +define+NUM_RC=1 +define+NUM_EP=1 \
        ../top/Package.sv ../top/TOP.sv
} compile_error]} {
    puts "COMPILATION FAILED"
    puts "$compile_error"
    quit -f
}

puts "Compilation completed successfully."

proc check_result {logfile} {
    if {![file exists $logfile]} { return "FAIL" }
    set fh [open $logfile r]
    set data [read $fh]
    close $fh
    if {[regexp {UVM_FATAL\s*:\s*[1-9][0-9]*} $data]} { return "FAIL" }
    if {[regexp {UVM_ERROR\s*:\s*[1-9][0-9]*} $data]} { return "FAIL" }
    if {[regexp {TEST FAILED} $data]} { return "FAIL" }
    return "PASS"
}

set count 0
foreach test $tests {
    incr count
    puts ""
    puts "============================================================"
    puts " TEST $count/$total_tests"
    puts " $test"
    puts "============================================================"

    set TestDir "$SimDir/$test"
    set LogFile "$TestDir/$test.log"
    set UCDBFile "$CovDir/$test.ucdb"

    if {[file exists $TestDir]} { file delete -force $TestDir }
    file mkdir $TestDir
    if {[file exists $UCDBFile]} { file delete -force $UCDBFile }

    # Derive a distinct seed for this test from the base seed (deterministic
    # given the same base seed, but different per test).
    set test_seed [expr {int(rand()*1000000000)}]
    lappend TestSeeds "$test:$test_seed"

    # Register coverage save BEFORE run-all because the UVM test calls $finish.
    if {$enable_cov} {
        set child_do "coverage save -onexit $UCDBFile; run -all"
        set cmd [list vsim.exe -c -coverage -cvgperinstance -debugDB +acc work.PCIe_top +UVM_TESTNAME=$test -sv_seed $test_seed +UVM_VERBOSITY=UVM_LOW -l $LogFile -do $child_do]
    } else {
        set child_do "run -all"
        set cmd [list vsim.exe -c -debugDB +acc work.PCIe_top +UVM_TESTNAME=$test -sv_seed $test_seed +UVM_VERBOSITY=UVM_LOW -l $LogFile -do $child_do]
    }

    puts "Seed           : $test_seed"
    puts "Starting child VSIM..."
    if {[catch { exec {*}$cmd } child_error]} {
        puts "Child VSIM returned:"
        puts "$child_error"
    }

    set result [check_result $LogFile]
    if {$result eq "PASS"} {
        lappend PassedTests $test
    } else {
        lappend FailedTests $test
    }

    puts ""
    puts "RESULT : $result"
    if {[file exists $UCDBFile]} {
        puts "UCDB    : $UCDBFile"
    } else {
        puts "UCDB    : NOT GENERATED"
    }
    puts "Completed TEST $count/$total_tests"
}

puts ""
puts "============================================================"
puts "             ALL TESTS COMPLETED"
puts "============================================================"
puts "Total Tests : $total_tests"
puts "PASS        : [llength $PassedTests]"
puts "FAIL        : [llength $FailedTests]"
puts ""
puts "PASSED TESTS"
puts "------------------------------------------------------------"
foreach test $PassedTests { puts "PASS : $test" }
if {[llength $PassedTests] == 0} { puts "None" }
puts ""
puts "FAILED TESTS"
puts "------------------------------------------------------------"
foreach test $FailedTests { puts "FAIL : $test" }
if {[llength $FailedTests] == 0} { puts "None" }

puts ""
puts "============================================================"
puts "                 COVERAGE MERGE"
puts "============================================================"
set ucdbs [glob -nocomplain $CovDir/*.ucdb]
if {[llength $ucdbs] > 0} {
    puts "UCDB files found: [llength $ucdbs]"
    if {[catch { exec vcover merge -out $MergedUCDB {*}$ucdbs } merge_error]} {
        puts "Coverage merge FAILED"
        puts "$merge_error"
    } else {
        puts "Coverage merge completed."
        puts "Merged UCDB: $MergedUCDB"
    }
} else {
    puts "No UCDB files found."
}

set EndTime [clock seconds]
set Duration [expr {$EndTime - $StartTime}]
puts ""
puts "============================================================"
puts "                 REGRESSION SUMMARY"
puts "============================================================"
puts "Regression : $regression_name"
puts "Base Seed  : $seed"
puts "Total      : $total_tests"
puts "PASS       : [llength $PassedTests]"
puts "FAIL       : [llength $FailedTests]"
puts "Duration   : ${Duration} sec"
puts ""
puts "Summary log: $SummaryLog"

set fh [open $SummaryLog w]
puts $fh "PCIe UVM REGRESSION"
puts $fh "Regression : $regression_name"
puts $fh "Base Seed  : $seed"
puts $fh "Total      : $total_tests"
puts $fh "PASS       : [llength $PassedTests]"
puts $fh "FAIL       : [llength $FailedTests]"
puts $fh "Duration   : ${Duration} sec"
puts $fh ""
puts $fh "PASSED TESTS"
foreach test $PassedTests { puts $fh "PASS : $test" }
puts $fh ""
puts $fh "FAILED TESTS"
foreach test $FailedTests { puts $fh "FAIL : $test" }
puts $fh ""
puts $fh "TEST SEEDS (test:seed)"
foreach ts $TestSeeds { puts $fh $ts }
close $fh

puts ""
if {[llength $FailedTests] == 0} {
    puts "REGRESSION PASSED"
} else {
    puts "REGRESSION FAILED"
}
puts ""
quit -f


