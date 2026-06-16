# Phase 8 ZedBoard board-demo implementation flow.
# Target: ZedBoard Zynq-7000, xc7z020clg484-1
# Top: zedboard_mimo_demo_top

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set output_root [file join $repo_root "results" "phase8_zedboard_demo"]
set build_root [file join $repo_root "build" "vivado_impl_zedboard_demo"]

set default_part_name xc7z020clg484-1
set top_name zedboard_mimo_demo_top
set detector_clock_period_ns 20.000

source [file join $script_dir "filelist_rtl_seq.tcl"]

if {![info exists argv]} {
    set argv [list]
}

set script_args $argv
set script_argc [llength $script_args]
set part_name $default_part_name

for {set arg_idx 0} {$arg_idx < $script_argc} {incr arg_idx} {
    set arg [lindex $script_args $arg_idx]

    if {$arg eq "-part"} {
        incr arg_idx
        if {$arg_idx >= $script_argc} {
            error "Missing value after -part"
        }
        set part_name [lindex $script_args $arg_idx]
    } elseif {$arg eq "-top"} {
        incr arg_idx
        if {$arg_idx >= $script_argc} {
            error "Missing value after -top"
        }
        set top_name [lindex $script_args $arg_idx]
    } elseif {$arg eq "-clock_period"} {
        incr arg_idx
        if {$arg_idx >= $script_argc} {
            error "Missing value after -clock_period"
        }
        set detector_clock_period_ns [lindex $script_args $arg_idx]
    } else {
        error "Unknown argument: $arg"
    }
}

set clock_label [format "%.3f" $detector_clock_period_ns]
set clock_dir_label [string map {. p} "clk_${clock_label}ns"]
set output_dir [file join $output_root $clock_dir_label]
set build_dir [file join $build_root $clock_dir_label]

file mkdir $output_dir
file mkdir $build_dir

proc write_available_reports {output_dir stage_name} {
    catch {report_utilization -file [file join $output_dir "utilization_${stage_name}.rpt"]} util_msg
    catch {report_timing_summary -file [file join $output_dir "timing_${stage_name}.rpt"]} timing_msg
    catch {report_route_status -file [file join $output_dir "route_status_${stage_name}.rpt"]} route_msg
    catch {report_drc -file [file join $output_dir "drc_${stage_name}.rpt"]} drc_msg
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

puts "Phase 8 ZedBoard demo Vivado implementation"
puts "Repository root: $repo_root"
puts "Output directory: $output_dir"
puts "Top module: $top_name"
puts "FPGA part: $part_name"
puts "Board input clock: clk, 10.000 ns"
puts "Detector MMCM clock target: $clock_label ns"

create_project -force adaptive_gs_mimo_detector_zedboard_demo $build_dir -part $part_name
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

set demo_rtl_file "rtl_seq/zedboard_mimo_demo_top.sv"
set board_xdc_file [file normalize [file join $repo_root "constraints" "zedboard_demo.xdc"]]

puts "Reading sequential RTL files:"
foreach rtl_file [concat $rtl_seq_files [list $demo_rtl_file]] {
    set rtl_path [file normalize [file join $repo_root $rtl_file]]
    if {![file exists $rtl_path]} {
        error "Missing RTL file: $rtl_path"
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

if {![file exists $board_xdc_file]} {
    error "Missing ZedBoard constraints file: $board_xdc_file"
}
puts "Reading constraints: $board_xdc_file"
read_xdc $board_xdc_file

set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

set stage_status [catch {
    synth_design -top $top_name -part $part_name
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during synth_design"
    puts $stage_msg
    write_available_reports $output_dir "synth_failed"
    error $stage_msg
}

write_available_reports $output_dir "post_synth"

set stage_status [catch {
    opt_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during opt_design"
    puts $stage_msg
    write_available_reports $output_dir "opt_failed"
    print_final_timing
    error $stage_msg
}

set stage_status [catch {
    place_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during place_design"
    puts $stage_msg
    write_available_reports $output_dir "place_failed"
    print_final_timing
    error $stage_msg
}

set stage_status [catch {
    phys_opt_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during phys_opt_design"
    puts $stage_msg
    write_available_reports $output_dir "phys_opt_failed"
    print_final_timing
    error $stage_msg
}

set stage_status [catch {
    route_design
} stage_msg]

if {$stage_status != 0} {
    puts "IMPLEMENTATION FAILED during route_design"
    puts $stage_msg
    write_available_reports $output_dir "route_failed"
    print_final_timing
    error $stage_msg
}

write_available_reports $output_dir "post_route"
catch {report_power -file [file join $output_dir "power_post_route.rpt"]} power_msg
print_final_timing

write_checkpoint -force [file join $output_dir "routed_zedboard_demo.dcp"]

set bitstream_path [file join $output_dir "zedboard_mimo_demo_top.bit"]
set bit_status [catch {
    write_bitstream -force $bitstream_path
} bit_msg]

if {$bit_status != 0} {
    puts "Route succeeded, but bitstream generation failed:"
    puts $bit_msg
    error $bit_msg
}

puts "ZedBoard demo implementation reports written to: $output_dir"
puts "Bitstream written to: $bitstream_path"
