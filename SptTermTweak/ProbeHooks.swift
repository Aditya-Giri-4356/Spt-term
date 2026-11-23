import Foundation

#if SPT_PROBE
@_cdecl("spt_probe_swift_install")
public func sptProbeSwiftInstall() {
    guard spt_probe_is_enabled() else { return }
    spt_probe_log_str("SYS", "ProbeHooks Swift entry point installed")
}

@_cdecl("spt_probe_walk_swift_mirror")
public func sptProbeWalkSwiftMirror(_ object: AnyObject,
                                    _ className: UnsafePointer<CChar>,
                                    _ maxDepth: Int32,
                                    _ maxChildren: Int32) {
    guard spt_probe_is_enabled() else { return }
    spt_probe_log_str("B", "[Mirror-Stub] \(String(cString: className))")
}
#endif
