import Foundation

/// Mirrors `dev.jelly.capture.detectHostSource` — but with a critical
/// platform difference. On the JVM, `Throwable.stackTrace` carries source
/// filenames and line numbers because they're embedded in `.class` debug
/// info. Swift's `Thread.callStackSymbols` carries only mangled symbols
/// + module + offset; runtime resolution to `file:line` requires DWARF /
/// dSYM lookup, which fails on stripped Release/TestFlight builds.
///
/// Workaround: `Jelly.install(file: #fileID, line: #line)` captures the
/// install site at compile time. `HostSourceDetector.shared.installSite`
/// stores that single fixed source. It's a tier-3 fallback — last resort
/// when no `.jellySource()` modifier is found in the view's ancestor
/// chain. Use `.jellySource()` on screen roots when you want sub-screen
/// precision.
@MainActor
public final class HostSourceDetector {
    public static let shared = HostSourceDetector()

    /// Captured from the `Jelly.install(file:line:)` call site.
    public private(set) var installSite: JellySourceInfo?

    private init() {}

    public func setInstallSite(file: StaticString, line: UInt) {
        installSite = JellySourceInfo(file: "\(file)", line: Int(line))
    }

    public func reset() {
        installSite = nil
    }
}
