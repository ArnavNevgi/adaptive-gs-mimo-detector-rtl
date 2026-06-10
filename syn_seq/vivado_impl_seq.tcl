# Phase 8 Vivado implementation script for the optimized sequential architecture.
# This flow runs synthesis, opt, place, physical optimization, route, and then
# writes implementation reports/checkpoints. A bitstream is generated only after
# route_design succeeds.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set output_root [file join $repo_root "results" "phase8_impl_seq"]
set build_root [file join $repo_root "build" "vivado_impl_seq"]

set default_part_name xc7a35tcpg236-1
set clock_period_ns 20.000

source [file join $script_dir "filelist_rtl_seq.tcl"]

if {![info exists default_impl_top] || ($default_impl_top eq "")} {
    error "default_impl_top is not defined by syn_seq/filelist_rtl_seq.tcl"
}

if {![info exists argv]} {
    set argv [list]
}
set script_args $argv
set script_argc [llength $script_args]

set top_name $default_impl_top
set part_name $default_part_name
set positional_count 0
set explicit_top_override 0

for {set arg_idx 0} {$arg_idx < $script_argc} {incr arg_idx} {
    set arg [lindex $script_args $arg_idx]

    if {$arg eq "-top"} {
        incr arg_idx
        if {$arg_idx >= $script_argc} {
            error "Missing value after -top"
        }
        set top_name [lindex $script_args $arg_idx]
        set explicit_top_override 1
    } elseif {$arg eq "-part"} {
        incr arg_idx
        if {$arg_idx >= $script_argc} {
            error "Missing value after -part"
        }
        set part_name [lindex $script_args $arg_idx]
    } elseif {$arg eq "-clock_period"} {
        incr arg_idx
        if {$arg_idx >= $script_argc} {
            error "Missing value after -clock_period"
        }
        set clock_period_ns [lindex $script_args $arg_idx]
    } elseif {$positional_count == 0} {
        set clock_period_ns $arg
        incr positional_count
    } else {
        error "Unknown extra argument: $arg"
    }
}

if {(!$explicit_top_override) && ($top_name eq "mimo_detector_top_seq_synth_wrapper")} {
    error "Implementation flow must use package-placeable wrapper by default. Use mimo_detector_top_seq_impl_wrapper or pass -top intentionally."
}

set clock_label [format "%.3f" $clock_period_ns]
set clock_dir_label [string map {. p} "clk_${clock_label}ns"]
set output_dir [file join $output_root $clock_dir_label]
set build_dir [file join $build_root $clock_dir_label]

file mkdir $output_dir
file mkdir $build_dir

proc write_available_reports {output_dir} {
    catch {report_utilization -file [file join $output_dir "utilization_impl.rpt"]} util_msg
    catch {report_timing_summary -file [file join $output_dir "timing_impl.rpt"]} timing_msg
    catch {report_power -file [file join $output_dir "power_impl.rpt"]} power_msg
    catch {report_route_status -file [file join $output_dir "route_status.rpt"]} route_msg
}

proc print_final_timing {} {
    set timing_status [catch {
        report_timing_summary -return_string
    } timing_text]

    if {$timing_status == 0} {
        if {[regexp -line {^\s*([-+]?[0-9]+[.][0-9]+)\s+([-+]?[0-9]+[.][0-9]+)\s+[0-9]+} $timing_text -> wns tns]} {
            puts "Final timing summary: WNS=$wns ns, TNS=$tns ns"
            return
        }
    }

    set path_status [catch {
        get_timing_paths -quiet -setup -max_paths 1
    } paths]

    if {($path_status == 0) && ([llength $paths] > 0)} {
        set wns [get_property SLACK [lindex $paths 0]]
        puts "Final timing summary: WNS=$wns ns, TNS unavailable from Tcl parser"
    } else {
        puts "Final timing summary unavailable: no setup timing paths found"
    }
}

puts "Phase 8 sequential Vivado implementation"
puts "Repository root: $repo_root"
puts "Output directory: $output_dir"
puts "Top module: $top_name"
puts "FPGA part: $part_name"
puts "Clock: clk, $clock_label ns"

create_project -force adaptive_gs_mimo_detector_seq_impl $build_dir -part $part_name
set_property target_language Verilog [current_project]

set include_dirs [list \
    [file join $repo_root "rtl"] \
    [file join $repo_root "rtl_seq"] \
]

puts "SystemVerilog include directories:"
foreach include_dir $include_dirs {
    set include_dir_norm [file normalize $include_dir]
    if {![file isdirectory $include_dir_norm]} {
        error "Missing include directory: $include_dir_norm"
    }
    puts "  $include_dir_norm"
}

set_property include_dirs $include_dirs [current_fileset]

puts "Reading sequential RTL files:"
foreach rtl_file $rtl_seq_files {
    set rtl_path [file normalize [file join $repo_root $rtl_file]]
    if {![file exists $rtl_path]} {
        error "Missing RTL file from syn_seq/filelist_rtl_seq.tcl: $rtl_path"
    }

    puts "  read_verilog -sv $rtl_path"
    set read_status [catch {
        read_verilog -sv $rtl_path
    } read_msg]

    if {$read_status != 0} {
        puts "Failed while reading RTL file: $rtl_path"
        error $read_msg
    }
}

set clock_xdc [file join $output_dir "clock_impl.xdc"]
set clock_fh [open $clock_xdc w]
puts $clock_fh [format {create_clock -period %.3f -name clk [get_ports clk]} $clock_period_ns]
close $clock_fh
read_xdc $clock_xdc

set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

set stage_status [catch {
    synth_design -top $top_name -part $part_name
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during synth_design"
    puts $stage_msg
    write_available_reports $output_dir
    error $stage_msg
}

if {[llength [get_clocks -quiet clk]] == 0} {
    create_clock -period $clock_period_ns -name clk [get_ports clk]
}

set stage_status [catch {
    opt_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during opt_design"
    puts $stage_msg
    write_available_reports $output_dir
    print_final_timing
    error $stage_msg
}

set stage_status [catch {
    place_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during place_design"
    puts $stage_msg
    write_available_reports $output_dir
    print_final_timing
    error $stage_msg
}

set stage_status [catch {
    phys_opt_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during phys_opt_design"
    puts $stage_msg
    write_available_reports $output_dir
    print_final_timing
    error $stage_msg
}

set stage_status [catch {
    route_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during route_design"
    puts $stage_msg
    write_available_reports $output_dir
    print_final_timing
    error $stage_msg
}

write_available_reports $output_dir
print_final_timing

write_checkpoint -force [file join $output_dir "routed_impl.dcp"]

set bitstream_path [file join $output_dir "mimo_detector_top_seq.bit"]
set bit_status [catch {
    write_bitstream -force $bitstream_path
} bit_msg]

if {$bit_status != 0} {
    puts "Route succeeded, but bitstream generation failed:"
    puts $bit_msg
    error $bit_msg
}

puts "Sequential implementation reports written to: $output_dir"
puts "Bitstream written to: $bitstream_path"
