# Integrating Jelly into an iOS app

For human readers: see [`README.md`](README.md). The quick-start integration is a three-step copy-paste.

For agents (or agent-assisted integration): the full step-by-step procedure should live as a Claude Code skill mirroring `~/.claude/skills/jelly-android/SKILL.md`.

## Reference integration

Files touched in a host app for a normal integration:

- `<your-app>.xcodeproj/project.pbxproj` (or `Package.swift`) — Swift Package reference + library product on the app target
- `<App>.swift` (the SwiftUI `App` or UIKit `AppDelegate`) — `#if DEBUG` guarded `Jelly.install()` from `init()` / `application(_:didFinishLaunchingWithOptions:)`

Total: 1 modified file in the Xcode project plus 1 line of host code. No SDK source copied.

## Recommended pattern: `#if DEBUG` everywhere

Swift Package Manager has no equivalent to Gradle's `debugImplementation` configuration. Two options:

1. **Source-level gate.** Wrap every `import Jelly` and `Jelly.install()` call in `#if DEBUG`. Compiles in any project setup.

2. **Build-condition link.** In your host's `Package.swift`, conditionally link the library:
   ```swift
   .product(name: "Jelly", package: "jelly-swift", condition: .when(configuration: .debug))
   ```
   This is closer to Android's `debugImplementation` because the framework binary is excluded from release. Combine with the source-level gate so non-debug compiles do not see the imports.

Either approach keeps Jelly out of release builds. The source-level gate is simpler and works in mixed Xcode-project-and-SwiftPM setups.
