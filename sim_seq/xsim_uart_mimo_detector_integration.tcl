set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set repo_root [file normalize [file join $script_dir ".."]]

if {![file exists [file join $repo_root "rtl_seq" "uart_mimo_protocol.sv"]]} {
    set cwd_root [file normalize [pwd]]

    if {[file exists [file join $cwd_root "rtl_seq" "uart_mimo_protocol.sv"]]} {
        set repo_root $cwd_root
    } else {
        puts "FAIL: Could not determine repository root"
        exit 1
    }
}

cd $repo_root

set work_dir [file normalize [file join $repo_root "build" "xsim_uart_mimo_detector_integration"]]
set empty_include_dir [file join $work_dir "empty_include"]
file mkdir $work_dir
file mkdir $empty_include_dir

set empty_pkg [file join $empty_include_dir "fixed_point_pkg.sv"]
set fp [open $empty_pkg w]
puts $fp ""
close $fp

set tool_dir [file dirname [info nameofexecutable]]

proc find_tool {tool_name} {
    global tool_dir

    foreach candidate [list \
        [file join $tool_dir "${tool_name}.bat"] \
        [file join $tool_dir $tool_name] \
        $tool_name \
    ] {
        if {[file exists $candidate] || $candidate eq $tool_name} {
            return $candidate
        }
    }
}

proc run_cmd {args} {
    puts ""
    puts "CMD: $args"

    if {[catch {exec {*}$args 2>@1} result]} {
        puts $result
        puts "FAIL: command failed"
        exit 1
    }

    if {$result ne ""} {
        puts $result
    }

    return $result
}

puts "============================================================"
puts "XSIM UART MIMO detector integration simulation"
puts "Repository root: $repo_root"
puts "Build directory: $work_dir"
puts "============================================================"

set xvlog [find_tool "xvlog"]
set xelab [find_tool "xelab"]
set xsim [find_tool "xsim"]
set work_lib "uart_mimo_integration"

set incdirs [list \
    -i $empty_include_dir \
    -i [file join $repo_root "rtl"] \
    -i [file join $repo_root "rtl_seq"] \
    -i [file join $repo_root "tb"] \
    -i [file join $repo_root "tb_seq"] \
]

set sv_files [list \
    [file join $repo_root "rtl" "mode_select_unit.sv"] \
    [file join $repo_root "rtl" "x_to_xout_converter.sv"] \
    [file join $repo_root "rtl" "qpsk_slicer_array.sv"] \
    [file join $repo_root "rtl_seq" "gram_matrix_seq.sv"] \
    [file join $repo_root "rtl_seq" "matched_filter_seq.sv"] \
    [file join $repo_root "rtl_seq" "regularization_metric_seq.sv"] \
    [file join $repo_root "rtl_seq" "signed_divider_seq.sv"] \
    [file join $repo_root "rtl_seq" "gs_solver_seq.sv"] \
    [file join $repo_root "rtl_seq" "mimo_detector_top_seq.sv"] \
    [file join $repo_root "rtl_seq" "uart_mimo_protocol.sv"] \
    [file join $repo_root "tb_seq" "tb_uart_mimo_detector_integration.sv"] \
]

foreach sv_file $sv_files {
    if {![file exists $sv_file]} {
        puts "FAIL: Missing source file: $sv_file"
        exit 1
    }
}

run_cmd $xvlog -nolog -work $work_lib -sv [file join $repo_root "rtl" "fixed_point_pkg.sv"]
run_cmd $xvlog -nolog -work $work_lib -sv {*}$incdirs {*}$sv_files
run_cmd $xelab -nolog -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision ${work_lib}.tb_uart_mimo_detector_integration -s tb_uart_mimo_detector_integration_sim
set sim_output [run_cmd $xsim -nolog tb_uart_mimo_detector_integration_sim -runall]

if {[string first "tb_uart_mimo_detector_integration PASSED" $sim_output] < 0} {
    puts ""
    puts "FAIL: tb_uart_mimo_detector_integration did not report PASSED"
    exit 1
}

if {[string first "Error:" $sim_output] >= 0 || [string first "FAILED" $sim_output] >= 0} {
    puts ""
    puts "FAIL: tb_uart_mimo_detector_integration reported simulation errors"
    exit 1
}

puts ""
puts "PASS: tb_uart_mimo_detector_integration completed"
exit 0
