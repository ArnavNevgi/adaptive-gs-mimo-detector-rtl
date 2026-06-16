transcript on

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set repo_root [file normalize [file join $script_dir ".."]]

if {![file exists [file join $repo_root "rtl" "fixed_point_pkg.sv"]]} {
    set cwd_root [file normalize [pwd]]

    if {[file exists [file join $cwd_root "sim_seq" "run_all_seq.do"]] &&
        [file exists [file join $cwd_root "rtl" "fixed_point_pkg.sv"]]} {
        puts "INFO: [info script] resolved to '$script_path', not this repository."
        puts "INFO: Falling back to invocation directory '$cwd_root'."
        set repo_root $cwd_root
        set script_path [file normalize [file join $repo_root "sim_seq" "run_all_seq.do"]]
        set script_dir [file dirname $script_path]
    } else {
        puts "REGRESSION FAIL: Could not determine repository root from [info script]"
        quit -f -code 1
    }
}

if {[catch {cd $repo_root} cd_result]} {
    puts "REGRESSION FAIL: Could not cd to repository root '$repo_root'"
    puts $cd_result
    quit -f -code 1
}

puts ""
puts "============================================================"
puts "Sequential RTL full regression"
puts "Repository root: $repo_root"
puts "============================================================"

proc regression_fail {message} {
    puts ""
    puts "REGRESSION FAIL: $message"
    catch {quit -sim}
    quit -f -code 1
}

proc compile_sv {sv_file} {
    global vlog_args

    if {![file exists $sv_file]} {
        regression_fail "Missing source file: $sv_file"
    }

    puts "COMPILE: $sv_file"
    set status [catch {
        eval vlog $vlog_args [list $sv_file]
    } result]

    if {$status != 0} {
        puts $result
        regression_fail "Compile failed for $sv_file"
    }
}

proc run_seq_test {test_name {error_signal errors}} {
    puts ""
    puts "------------------------------------------------------------"
    puts "RUN: $test_name"
    puts "------------------------------------------------------------"

    set status [catch {
        vsim -voptargs=+acc work.$test_name
    } result]

    if {$status != 0} {
        puts $result
        puts "FAIL: $test_name"
        regression_fail "Could not elaborate $test_name"
    }

    catch {onfinish stop}

    set status [catch {
        run -all
    } result]

    if {$status != 0} {
        puts $result
        puts "FAIL: $test_name"
        regression_fail "Simulation failed for $test_name"
    }

    if {$error_signal ne ""} {
        set status [catch {
            examine -radix decimal "sim:/$test_name/$error_signal"
        } error_count]

        if {$status != 0} {
            puts $error_count
            puts "FAIL: $test_name"
            regression_fail "Could not read sim:/$test_name/$error_signal"
        }

        if {![regexp {[-]?[0-9]+} $error_count error_count_int]} {
            puts "FAIL: $test_name"
            regression_fail "Could not parse $error_signal value '$error_count' for $test_name"
        }

        if {$error_count_int != 0} {
            puts "FAIL: $test_name ($error_signal=$error_count_int)"
            regression_fail "$test_name reported $error_count_int errors"
        }
    }

    puts "PASS: $test_name"
    catch {quit -sim}
}

puts ""
puts "Cleaning and recreating work library"
if {[file exists work]} {
    set status [catch {
        vdel -lib work -all
    } result]

    if {$status != 0} {
        puts $result
        regression_fail "Could not delete existing work library"
    }
}

set status [catch {
    vlib work
} result]

if {$status != 0} {
    puts $result
    regression_fail "Could not create work library"
}

set status [catch {
    vmap work work
} result]

if {$status != 0} {
    puts $result
    regression_fail "Could not map work library"
}

set vlog_args [list \
    -sv \
    +incdir+rtl \
    +incdir+rtl_seq \
    +incdir+tb \
    +incdir+tb_seq \
]

set has_phase6_vectors [file exists "tb/phase6_vectors_pkg.sv"]

puts ""
puts "Compiling fixed-point package"
compile_sv rtl/fixed_point_pkg.sv

if {$has_phase6_vectors} {
    puts ""
    puts "Compiling Phase 6 vector package"
    compile_sv tb/phase6_vectors_pkg.sv
} else {
    puts ""
    puts "SKIP: tb/phase6_vectors_pkg.sv not found; vector regression tests will be skipped"
}

puts ""
puts "Compiling shared/reference RTL from rtl/"
foreach sv_file [list \
    rtl/gram_matrix_compute.sv \
    rtl/matched_filter_compute.sv \
    rtl/regularization_unit.sv \
    rtl/condition_metric_unit.sv \
    rtl/gs_solver.sv \
    rtl/mode_select_unit.sv \
    rtl/x_to_xout_converter.sv \
    rtl/qpsk_slicer.sv \
    rtl/qpsk_slicer_array.sv \
] {
    compile_sv $sv_file
}

puts ""
puts "Compiling sequential RTL from rtl_seq/"
foreach sv_file [list \
    rtl_seq/gram_matrix_seq.sv \
    rtl_seq/matched_filter_seq.sv \
    rtl_seq/regularization_metric_seq.sv \
    rtl_seq/signed_divider_seq.sv \
    rtl_seq/gs_solver_seq.sv \
    rtl_seq/mimo_detector_top_seq.sv \
] {
    compile_sv $sv_file
}

puts ""
puts "Compiling tb_seq testbenches"
foreach sv_file [list \
    tb_seq/tb_signed_divider_seq.sv \
    tb_seq/tb_gram_matrix_seq.sv \
    tb_seq/tb_matched_filter_seq.sv \
    tb_seq/tb_regularization_metric_seq.sv \
    tb_seq/tb_gs_solver_seq.sv \
    tb_seq/tb_mimo_detector_top_seq_basic.sv \
] {
    compile_sv $sv_file
}

if {$has_phase6_vectors} {
    foreach sv_file [list \
        tb_seq/tb_mimo_detector_top_seq_vectors.sv \
        tb_seq/tb_debug_vector2_seq_vs_ref.sv \
    ] {
        compile_sv $sv_file
    }
}

run_seq_test tb_signed_divider_seq
run_seq_test tb_gram_matrix_seq
run_seq_test tb_matched_filter_seq
run_seq_test tb_regularization_metric_seq
run_seq_test tb_gs_solver_seq
run_seq_test tb_mimo_detector_top_seq_basic

if {$has_phase6_vectors} {
    run_seq_test tb_mimo_detector_top_seq_vectors
    run_seq_test tb_debug_vector2_seq_vs_ref ""
}

puts ""
puts "============================================================"
puts "REGRESSION PASS: sequential RTL full regression completed"
puts "============================================================"

quit -f -code 0
