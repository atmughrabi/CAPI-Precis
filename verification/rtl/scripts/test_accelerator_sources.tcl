if {$argc != 1} {
    puts stderr "Usage: tclsh test_accelerator_sources.tcl REPO_ROOT"
    exit 2
}

set repo_root [file normalize [lindex $argv 0]]
set helper [file join $repo_root 01_capi_integration accelerator_synth capi fpga accelerator_sources.tcl]
source $helper

proc set_global_assignment {args} {
    global collected_sources
    if {[llength $args] != 3 ||
        [lindex $args 0] ne "-name" ||
        [lindex $args 1] ne "SYSTEMVERILOG_FILE"} {
        error "Unexpected Quartus assignment: $args"
    }
    lappend collected_sources [file normalize [lindex $args 2]]
}

foreach algorithm {memcpy memcpy-tutorial mmtiled} {
    set collected_sources {}
    add_accelerator_manifest $repo_root $algorithm

    set manifest [file join $repo_root verification rtl manifests "$algorithm.f"]
    set handle [open $manifest r]
    set contents [read $handle]
    close $handle

    set expected_sources {}
    foreach raw_line [split $contents "\n"] {
        set source [string trim $raw_line]
        if {$source eq "" || [string index $source 0] eq "#"} {
            continue
        }
        lappend expected_sources [file normalize [file join $repo_root $source]]
    }

    if {$collected_sources ne $expected_sources} {
        puts stderr "Quartus manifest order mismatch: $algorithm"
        exit 1
    }
    puts "PASS quartus_manifest $algorithm files=[llength $collected_sources]"
}
