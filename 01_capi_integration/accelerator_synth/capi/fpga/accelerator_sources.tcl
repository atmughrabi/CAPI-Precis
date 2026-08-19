proc add_accelerator_manifest {repo_root algorithm} {
    set manifest [file join $repo_root verification rtl manifests "$algorithm.f"]
    if {![file isfile $manifest]} {
        error "Missing accelerator RTL manifest: $manifest"
    }

    set handle [open $manifest r]
    set contents [read $handle]
    close $handle

    foreach raw_line [split $contents "\n"] {
        set source [string trim $raw_line]
        if {$source eq "" || [string index $source 0] eq "#"} {
            continue
        }

        set source_path [file normalize [file join $repo_root $source]]
        if {![string match "${repo_root}/*" $source_path]} {
            error "Manifest source escapes repository root: $source"
        }
        if {![file isfile $source_path]} {
            error "Manifest source does not exist: $source_path"
        }
        set_global_assignment -name SYSTEMVERILOG_FILE $source_path
    }
}
