# ============================================================
# PCIe Gen3 UVM - SINGLE TESTCASE CODE COVERAGE
# Questa Sim 2025.2
#
# TEST : pcie_ral_test
# SEED : 961736848
# ============================================================

set TEST_NAME "Multiple_Mem_Wr_Rd_3DW_rand_length_test"
set SEED 459550232

# Unique coverage directory
set COV_DIR "./coverage_reports_single"

set UCDB_FILE "$COV_DIR/PCIe_top.ucdb"
set REPORT_FILE "$COV_DIR/coverage_report.txt"

# ============================================================
# STEP 1 : CREATE WORK LIBRARY
# ============================================================

puts ""
puts "============================================================"
puts " STEP 1 : CREATE WORK LIBRARY"
puts "============================================================"

if {![file exists work]} {
    vlib work
}

vmap work work

# ============================================================
# STEP 2 : CREATE COVERAGE DIRECTORY
# ============================================================

puts ""
puts "============================================================"
puts " STEP 2 : CREATE COVERAGE DIRECTORY"
puts "============================================================"

if {![file exists $COV_DIR]} {
    file mkdir $COV_DIR
}

puts "Coverage directory:"
puts [file normalize $COV_DIR]

# ============================================================
# STEP 3 : COMPILE WITH COVERAGE
# ============================================================

puts ""
puts "============================================================"
puts " STEP 3 : COMPILATION"
puts "============================================================"

vlog -work work -sv -cover bcestf \
    +define+NUM_RC=1 \
    +define+NUM_EP=1 \
    ../top/Package.sv \
    ../top/TOP.sv

puts ""
puts "Compilation completed."

# ============================================================
# STEP 4 : OPTIMIZATION
# ============================================================

puts ""
puts "============================================================"
puts " STEP 4 : OPTIMIZATION"
puts "============================================================"

vopt work.PCIe_top \
    +acc \
    -o PCIe_top_cov_opt

puts ""
puts "Optimization completed."

# ============================================================
# STEP 5 : START SIMULATION
# ============================================================

puts ""
puts "============================================================"
puts " STEP 5 : START SIMULATION"
puts "============================================================"

puts ""
puts "Test = $TEST_NAME"
puts "Seed = $SEED"
puts ""

vsim -coverage \
    -sv_seed $SEED \
    -onfinish stop \
    PCIe_top_cov_opt \
    +UVM_TESTNAME=$TEST_NAME \
    +UVM_VERBOSITY=UVM_LOW \
    -l sim.log

puts ""
puts "Simulation loaded."
puts "Test = $TEST_NAME"
puts "Seed = $SEED"

# ============================================================
# STEP 6 : SIGNAL LOGGING
# ============================================================

puts ""
puts "============================================================"
puts " STEP 6 : SIGNAL LOGGING"
puts "============================================================"

log -r /*

puts "Signal logging enabled."

# ============================================================
# STEP 7 : RUN TEST
# ============================================================

puts ""
puts "============================================================"
puts " STEP 7 : RUNNING TESTCASE"
puts "============================================================"

puts ""
puts "TEST = $TEST_NAME"
puts "SEED = $SEED"
puts ""

run -all

puts ""
puts "============================================================"
puts " TESTCASE FINISHED"
puts "============================================================"

# ============================================================
# STEP 8 : COVERAGE SUMMARY
# ============================================================

puts ""
puts "============================================================"
puts " STEP 8 : COVERAGE SUMMARY"
puts "============================================================"

puts ""

coverage report -summary

# ============================================================
# STEP 9 : GENERATE COVERAGE REPORT
# ============================================================

puts ""
puts "============================================================"
puts " STEP 9 : GENERATE COVERAGE REPORT"
puts "============================================================"

puts ""

coverage report \
    -details \
    -output $REPORT_FILE

puts ""
puts "Coverage report generated:"
puts [file normalize $REPORT_FILE]

# ============================================================
# STEP 10 : SAVE UCDB
# ============================================================

puts ""
puts "============================================================"
puts " STEP 10 : SAVE UCDB"
puts "============================================================"

puts ""

coverage save $UCDB_FILE

puts ""
puts "UCDB saved:"
puts [file normalize $UCDB_FILE]

# ============================================================
# STEP 11 : VERIFY COVERAGE FILES
# ============================================================

puts ""
puts "============================================================"
puts " STEP 11 : VERIFY COVERAGE FILES"
puts "============================================================"

puts ""

if {[file exists $UCDB_FILE]} {
    puts "PASS: UCDB generated"
    puts "UCDB = [file normalize $UCDB_FILE]"
    puts "SIZE = [file size $UCDB_FILE] bytes"
} else {
    puts "FAIL: UCDB NOT generated"
}

puts ""

if {[file exists $REPORT_FILE]} {
    puts "PASS: Coverage report generated"
    puts "REPORT = [file normalize $REPORT_FILE]"
    puts "SIZE = [file size $REPORT_FILE] bytes"
} else {
    puts "FAIL: Coverage report NOT generated"
}

# ============================================================
# FINAL
# ============================================================

puts ""
puts "============================================================"
puts " PCIe SINGLE TEST COVERAGE COMPLETE"
puts "============================================================"

puts ""
puts "Test:"
puts "$TEST_NAME"

puts ""
puts "Seed:"
puts "$SEED"

puts ""
puts "UCDB:"
puts [file normalize $UCDB_FILE]

puts ""
puts "Coverage Report:"
puts [file normalize $REPORT_FILE]

puts ""
puts "============================================================"

quit -f

