
set PSL_FPGA ./psl_fpga
set LIBCAPI  ./capi
set VERSION   [binary format A24 [exec $LIBCAPI/scripts/version.py]]

if { $argc != 3 } {
	puts "SET Project to DEFAULT"
	set my_project "capi-precis"
	set algorithm  "cu_memcpy"
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


# foreach filename [glob ../accelerator/rtl/*.vhd] {
#     set_global_assignment -name VHDL_FILE $filename
# }

# foreach filename [glob ../accelerator/rtl/*.v] {
#     set_global_assignment -name SYSTEMVERILOG_FILE $filename
# }

foreach filename [glob ../accelerator_rtl/afu_control/*.sv] {
    set_global_assignment -name SYSTEMVERILOG_FILE $filename
}

# foreach filename [glob ../accelerator/pkg/*.vhd] {
#     set_global_assignment -name VHDL_FILE $filename
# }

# foreach filename [glob ../accelerator/pkg/*.v] {
#     set_global_assignment -name SYSTEMVERILOG_FILE $filename
# }

foreach filename [glob ../accelerator_rtl/afu_pkgs/*.sv] {
    set_global_assignment -name SYSTEMVERILOG_FILE $filename
}

# foreach filename [glob ../accelerator/cu/*.vhd] {
#     set_global_assignment -name VHDL_FILE $filename
# }

# foreach filename [glob ../accelerator/cu/*.v] {
#     set_global_assignment -name SYSTEMVERILOG_FILE $filename
# }


foreach filename [glob ../accelerator_rtl/cu_control/$algorithm/global_pkg/*.sv] {
	set_global_assignment -name SYSTEMVERILOG_FILE $filename
}

foreach filename [glob ../accelerator_rtl/cu_control/$algorithm//global_cu/*.sv] {
	set_global_assignment -name SYSTEMVERILOG_FILE $filename
}

foreach filename [glob ../accelerator_rtl/cu_control/$algorithm//memcpy/*.sv] {
	set_global_assignment -name SYSTEMVERILOG_FILE $filename
}
