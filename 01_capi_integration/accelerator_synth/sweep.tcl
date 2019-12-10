# By Boon Seong https://almost-a-technocrat.blogspot.com/2013/07/run-quartus-ii-fitter-and-timequest_3.html
# This tcl is used to sweep seed by running fitter and STA, the timing report will be stored in seed_rpt directory
load_package flow
load_package report
# Specify project name and revision name
set project_name capi-precis
set project_revision capi-precis

# Set seeds
set seedList { 2 3 5 7 11 13 17 19 23 29 31 27 41 43 }

set timetrynum [llength $seedList]
puts "Total compiles: $timetrynum"
project_open -revision $project_revision $project_name

# Specify seed compile report directory
set rptdir seed_rpt
file mkdir $rptdir
set trynum 0
while { $timetrynum > $trynum } {
set current_seed [lindex $seedList $trynum]
set_global_assignment -name SEED $current_seed
# Place & Route
if {[catch {execute_module -tool fit} result]} {
 puts "\nResult: $result\n"
 puts "ERROR: Quartus II Fitter failed. See the report file.\n"
 qexit -error
} else {
 puts "\nInfo: Quartus II Fitter was successful.\n"
}
# TimeQuest Timing Analyzer
if {[catch {execute_module -tool sta} result]} {
 puts "\nResult: $result\n"
 puts "ERROR: TimeQuest Analyzer failed. See the report file.\n"
 qexit -error
} else {
 puts "\nInfo: TimeQuest Analyzer was successful.\n"
}
# Store compile results
#file copy -force ./$project_revision.fit.rpt $rptdir/seed$current_seed.fit.rpt
#file copy -force ./$project_revision.sta.rpt $rptdir/seed$current_seed.sta.rpt
load_report
set panel {TimeQuest Timing Analyzer||Multicorner Timing Analysis Summary}
set id [get_report_panel_id $panel]
if {$id != -1} {
    write_report_panel -file $rptdir/Multicorner_sta_seed$current_seed.htm -html -id $id
} else {
    puts "Error: report panel could not be found."
}
unload_report
incr trynum
}
project_close