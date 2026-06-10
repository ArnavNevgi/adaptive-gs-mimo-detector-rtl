# Step 7 Vivado synthesis/implementation script.
# Default top is the flattened synthesis wrapper because Vivado board-level
# synthesis can be fragile with unpacked array top-level ports.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set reports_dir [file join $repo_root "syn" "reports"]
set build_dir [file join $repo_root "build" "vivado"]

file mkdir $reports_dir
file mkdir $build_dir

set default_part_name xc7a35tcpg236-1
set exploratory_part_name xc7a200tfbg484-2
source [file join $script_dir "filelist_rtl.tcl"]

set top_name $default_synth_top
set part_name $default_part_name
set positional_count 0

for {set arg_idx 0} {$arg_idx < $argc} {incr arg_idx} {
    set arg [lindex $argv $arg_idx]
    if {$arg eq "-top"} {
        incr arg_idx
        if {$arg_idx >= $argc} {
            error "Missing value after -top"
        }
        set top_name [lindex $argv $arg_idx]
    } elseif {$arg eq "-part"} {
        incr arg_idx
        if {$arg_idx >= $argc} {
            error "Missing value after -part"
        }
        set part_name [lindex $argv $arg_idx]
    } elseif {$positional_count == 0} {
        set top_name $arg
        incr positional_count
    } elseif {$positional_count == 1} {
        set part_name $arg
        incr positional_count
    } else {
        error "Unknown extra argument: $arg"
    }
}

puts "Step 7 Vivado synthesis"
puts "Repository root: $repo_root"
puts "Top module: $top_name"
puts "FPGA part: $part_name"
puts "Clock: clk, 10.000 ns"
puts "Default part: $default_part_name"
puts "Exploratory larger part: $exploratory_part_name"

create_project -force adaptive_gs_mimo_detector $build_dir -part $part_name
# set_property target_language Verilog [current_project]
# set_property simulator_language Mixed [current_project]

foreach rtl_file $rtl_files {
    read_verilog -sv [file join $repo_root $rtl_file]
}

set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

synth_design -top $top_name -part $part_name
create_clock -period 10.000 -name clk [get_ports clk]

report_utilization -file [file join $reports_dir "utilization_post_synth.rpt"]
report_timing_summary -file [file join $reports_dir "timing_post_synth.rpt"]
write_checkpoint -force [file join $reports_dir "mimo_detector_top_post_synth.dcp"]

set opt_status [catch {
    opt_design
    report_utilization -file [file join $reports_dir "utilization_post_opt.rpt"]
} opt_msg]

if {$opt_status != 0} {
    puts "STEP 7 IMPLEMENTATION STOPPED: opt_design failed."
    puts "Vivado message: $opt_msg"
    catch {report_drc -file [file join $reports_dir "drc.rpt"]}
    puts "Post-synthesis reports are available in: $reports_dir"
    exit 0
}

set place_status [catch {
    place_design
} place_msg]

if {$place_status != 0} {
    puts "STEP 7 IMPLEMENTATION STOPPED: place_design failed."
    puts "Vivado message: $place_msg"
    puts "This is expected for over-utilized designs; DRC is not suppressed."
    catch {report_utilization -file [file join $reports_dir "utilization.rpt"]}
    catch {report_timing_summary -file [file join $reports_dir "timing_summary.rpt"]}
    catch {report_power -file [file join $reports_dir "power.rpt"]}
    catch {report_drc -file [file join $reports_dir "drc.rpt"]}
    puts "Reports written to: $reports_dir"
    exit 0
}

set route_status [catch {
    route_design
} route_msg]

if {$route_status != 0} {
    puts "STEP 7 IMPLEMENTATION STOPPED: route_design failed."
    puts "Vivado message: $route_msg"
    catch {report_utilization -file [file join $reports_dir "utilization.rpt"]}
    catch {report_timing_summary -file [file join $reports_dir "timing_summary.rpt"]}
    catch {report_power -file [file join $reports_dir "power.rpt"]}
    catch {report_drc -file [file join $reports_dir "drc.rpt"]}
    puts "Reports written to: $reports_dir"
    exit 0
}

report_utilization -file [file join $reports_dir "utilization.rpt"]
report_timing_summary -file [file join $reports_dir "timing_summary.rpt"]
report_power -file [file join $reports_dir "power.rpt"]
report_drc -file [file join $reports_dir "drc.rpt"]

write_checkpoint -force [file join $reports_dir "mimo_detector_top_routed.dcp"]

puts "Reports written to: $reports_dir"
