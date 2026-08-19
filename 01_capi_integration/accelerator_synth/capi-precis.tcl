
set PSL_FPGA ./psl_fpga
set LIBCAPI  ./capi
set VERSION   [binary format A24 [exec $LIBCAPI/scripts/version.py]]

if { $argc != 3 } {
    puts "SET Project to DEFAULT"
    set my_project "capi-precis"
    set algorithm  "memcpy"
    set cu_count   "20"
} else {
    puts "SET Project to ARGV"
    set my_project "[lindex $argv 0]"
    set algorithm  "[lindex $argv 1]"
    set cu_count   "[lindex $argv 2]"
}

puts "Project   $my_project"
puts "Algorithm $algorithm"
puts "CU Count  $cu_count"

set project_name $my_project
set project_revision $my_project

project_new $project_name -overwrite -revision $project_revision

set_global_assignment -name TOP_LEVEL_ENTITY psl_fpga


source $LIBCAPI/fpga/common.tcl
source $LIBCAPI/fpga/ibm_sources.tcl
source $LIBCAPI/fpga/pins.tcl
source $LIBCAPI/fpga/build_version.tcl
source $LIBCAPI/fpga/accelerator_sources.tcl

set repo_root [file normalize [file join [file dirname [info script]] ../..]]
add_accelerator_manifest $repo_root $algorithm
