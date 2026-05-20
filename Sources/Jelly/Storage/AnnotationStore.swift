import Foundation
import Combine

/// Persists annotations per screen with 7-day expiry, mirroring
/// `dev.jelly.storage.AnnotationStore` which itself ports
/// `package/src/utils/storage.ts` (loadAnnotations / saveAnnotations).
///
/// Backed by a private `UserDefaults` suite so we don't pollute the host
/// app's standard defaults. Keyed by screen identifier so each screen has
/// an independent annotation list, matching how the web version keys by
/// `pathname` and the Android version keys by Activity class name.
public final class AnnotationStore {

    public static let suiteName = "dev.jelly.storage"

    private static let sevenDaysMillis: Int64 = 7 * 24 * 60 * 60 * 1000

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Per-screen Combine subjects so observers see in-process writes
    /// immediately, without round-tripping through `UserDefaults` change
    /// notifications.
    private var subjects: [String: CurrentValueSubject<[Annotation], Never>] = [:]
    private let lock = NSLock()

    public init(suiteName: String = AnnotationStore.suiteName) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.encoder = JSONEncoder()
        // Match the Kotlin `Json { encodeDefaults = false }` policy by
        // default — we never want our optionals to serialize as `null` and
        // create wire-format drift.
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(screenKey: String) -> [Annotation] {
        guard let raw = defaults.string(forKey: prefix(screenKey)),
              let data = raw.data(using: .utf8) else {
            return []
        }
        let decoded = (try? decoder.decode([Annotation].self, from: data)) ?? []
        return decoded.filter(isFresh)
    }

    /// Returns all stored annotations across every screen key. Used by
    /// the catch-up sync flow when the user annotates before the
    /// endpoint / cable is set up and later wants to push the backlog.
    /// Expired entries are filtered out to match `load`.
    public func enumerateAll() -> [String: [Annotation]] {
        var out: [String: [Annotation]] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(Self.keyPrefix), let raw = value as? String else { continue }
            let screenKey = String(key.dropFirst(Self.keyPrefix.count))
            guard let data = raw.data(using: .utf8) else { continue }
            let anns = (try? decoder.decode([Annotation].self, from: data)) ?? []
            let fresh = anns.filter(isFresh)
            if !fresh.isEmpty { out[screenKey] = fresh }
        }
        return out
    }

    @discardableResult
    public func save(screenKey: String, annotations: [Annotation]) -> [Annotation] {
        let key = prefix(screenKey)
        if annotations.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? encoder.encode(annotations),
                  let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: key)
        }
        subject(for: screenKey).send(annotations.filter(isFresh))
        return annotations
    }

    /// Combine publisher for live updates. Mirrors the Kotlin Flow API.
    public func observe(screenKey: String) -> AnyPublisher<[Annotation], Never> {
        let subj = subject(for: screenKey)
        // Push the current persisted value at subscription time so cold
        // subscribers don't see an empty list before the next write.
        subj.send(load(screenKey: screenKey))
        return subj.eraseToAnyPublisher()
    }

    private func subject(for screenKey: String) -> CurrentValueSubject<[Annotation], Never> {
        lock.lock(); defer { lock.unlock() }
        if let existing = subjects[screenKey] { return existing }
        let created = CurrentValueSubject<[Annotation], Never>([])
        subjects[screenKey] = created
        return created
    }

    private func isFresh(_ annotation: Annotation) -> Bool {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Self.sevenDaysMillis
        return annotation.timestamp >= cutoff
    }

    private static let keyPrefix = "annotations."
    private func prefix(_ screenKey: String) -> String { Self.keyPrefix + screenKey }

    /// One-time migration of legacy `screenshotPath` values that point
    /// into `Library/Caches/jelly/...` — that location was purged by
    /// iOS under storage pressure (the user's "annotations stayed but
    /// images vanished" symptom). The actual image bytes are copied
    /// across by `JellyScreenshot.imageDirectory()`; this method
    /// updates each affected annotation's `screenshotPath` to point at
    /// the new Application Support location whenever the migrated file
    /// actually exists. Annotations whose old file was already gone
    /// stay pointing at the dead path; the UI handles those gracefully
    /// (no image rendered, rest of the annotation intact).
    @MainActor
    public func migrateLegacyScreenshotPaths() {
        // Trigger the file-copy step (Caches/jelly → Application Support/jelly).
        let supportDir = JellyScreenshot.imageDirectory()
        let supportPath = supportDir.path

        // Heuristic for "this is a legacy Caches path": substring match
        // on `/Caches/jelly/`. Robust against absolute-path differences
        // between simulator runs (sandbox UUID changes per install).
        let cachesMarker = "/Caches/jelly/"

        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(Self.keyPrefix), let raw = value as? String,
                  let data = raw.data(using: .utf8),
                  var anns = (try? decoder.decode([Annotation].self, from: data)) else { continue }
            var changed = false
            for i in anns.indices {
                guard let oldPath = anns[i].screenshotPath else { continue }
                if oldPath.contains(cachesMarker) {
                    let filename = (oldPath as NSString).lastPathComponent
                    let newPath = (supportPath as NSString).appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: newPath) {
                        anns[i].screenshotPath = newPath
                        changed = true
                    }
                }
            }
            if changed {
                let screenKey = String(key.dropFirst(Self.keyPrefix.count))
                save(screenKey: screenKey, annotations: anns)
            }
        }
    }
}
