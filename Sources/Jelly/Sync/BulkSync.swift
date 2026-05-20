import Foundation

/// Aggregate counts returned by `pushUnsyncedAnnotations`. Lets the UI
/// show "Pushed N of M, K already on server, J failed" without surfacing
/// per-annotation error noise to the user.
public struct BulkSyncResult: Equatable, Sendable {
    /// New POST attempts made against the server (annotations the
    /// server didn't already have).
    public let attempted: Int
    public let synced: Int
    public let failed: Int
    /// Local annotations whose IDs the server already had — no POST
    /// was needed, but the local `syncedTo` flag was updated so they
    /// stop showing as pending in the UI.
    public let skipped: Int

    public var isEmpty: Bool { attempted == 0 && skipped == 0 }
    public var allSucceeded: Bool { attempted > 0 && failed == 0 }

    public init(attempted: Int, synced: Int, failed: Int, skipped: Int = 0) {
        self.attempted = attempted
        self.synced = synced
        self.failed = failed
        self.skipped = skipped
    }
}

/// Verify-and-push: queries the server for annotation IDs already
/// present in the room, then pushes only the locally-stored annotations
/// that the server doesn't have. Annotations the server already knows
/// are marked `syncedTo` locally and counted as `skipped`.
///
/// This is the catch-up button's "Sync now" action. It's strictly more
/// correct than relying on the local `syncedTo` flag because it
/// recovers from cases where the local flag is stale (browser refreshed
/// to a fresh room, server was restarted, the iOS app crashed mid-sync,
/// etc.). The server-side answer is the source of truth.
///
/// Behavior:
/// 1. `GET /sessions` to list sessions in the room.
/// 2. `GET /sessions/{sid}` for each to collect annotation IDs.
/// 3. For each local screen key with at least one annotation NOT on
///    the server: create a fresh session (`POST /sessions`) and push
///    each missing annotation + its baked image.
/// 4. Mark already-on-server annotations as `syncedTo` (with a
///    sentinel value) so the local pending count drops to zero.
///
/// Failures on individual annotations don't abort the batch. If the
/// initial verification step fails (server unreachable / auth
/// rejected), the whole call returns with `attempted = synced = 0`
/// and an empty skipped count — the caller surfaces that as
/// "Couldn't reach endpoint."
@MainActor
func pushUnsyncedAnnotations(store: AnnotationStore, api: JellyAPI) async -> BulkSyncResult {
    // Step 1: build a Set<String> of annotation IDs the server already has.
    let serverIds: Set<String>
    do {
        serverIds = try await fetchServerAnnotationIds(api: api)
    } catch {
        // Server unreachable; nothing to do. Caller turns this into
        // "Couldn't reach endpoint."
        return BulkSyncResult(attempted: 0, synced: 0, failed: 0, skipped: 0)
    }

    let all = store.enumerateAll()
    var attempted = 0
    var synced = 0
    var failed = 0
    var skipped = 0

    for (screenKey, anns) in all {
        let pendingIndices = anns.indices.filter { !serverIds.contains(anns[$0].id) }
        let alreadyThereIndices = anns.indices.filter { serverIds.contains(anns[$0].id) }

        // Mirror server state into local `syncedTo` for any annotations
        // whose IDs the server already has — even when there's nothing
        // pending, so the pending count UI is accurate after the call.
        var updated = anns
        for idx in alreadyThereIndices where updated[idx].syncedTo == nil {
            updated[idx].syncedTo = "verified"
            skipped += 1
        }

        if pendingIndices.isEmpty {
            if alreadyThereIndices.contains(where: { anns[$0].syncedTo == nil }) {
                store.save(screenKey: screenKey, annotations: updated)
            }
            continue
        }

        // Step 2: fresh session for this screen key, push the pending.
        let sid: String
        do {
            sid = try await api.createSession(url: "screen:\(screenKey)").id
        } catch {
            attempted += pendingIndices.count
            failed += pendingIndices.count
            store.save(screenKey: screenKey, annotations: updated)
            continue
        }

        for idx in pendingIndices {
            attempted += 1
            let ann = anns[idx]
            do {
                var withSession = ann
                withSession.sessionId = sid
                let result = try await api.syncAnnotation(sessionId: sid, annotation: withSession)
                var withSyncedTo = result
                withSyncedTo.syncedTo = sid
                updated[idx] = withSyncedTo

                // Upload baked screenshot bytes (best-effort). Resolve
                // through `JellyScreenshot.resolve` so an absolute path
                // saved by a previous install (with a now-rotated
                // container UUID) still points at the actual file.
                if let path = JellyScreenshot.resolve(storedPath: ann.screenshotPath),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    let contentType = path.lowercased().hasSuffix(".webp") ? "image/webp"
                                    : path.lowercased().hasSuffix(".png")  ? "image/png"
                                    : "image/jpeg"
                    try? await api.uploadAnnotationImage(
                        annotationId: result.id,
                        bytes: data,
                        contentType: contentType
                    )
                }
                synced += 1
            } catch {
                failed += 1
            }
        }
        store.save(screenKey: screenKey, annotations: updated)
    }

    return BulkSyncResult(attempted: attempted, synced: synced, failed: failed, skipped: skipped)
}

/// Lists every annotation ID currently held by the configured room
/// (across every session in it). Used by `pushUnsyncedAnnotations` to
/// verify before pushing.
@MainActor
private func fetchServerAnnotationIds(api: JellyAPI) async throws -> Set<String> {
    let sessions = try await api.listSessions()
    var ids = Set<String>()
    for sess in sessions {
        // GET /sessions/{id} returns the session with its annotations.
        // We swallow per-session errors so one bad session doesn't poison
        // the whole verification — annotations in healthy sessions still
        // get accounted for.
        if let withAnns = try? await api.getSession(sess.id) {
            for ann in withAnns.annotations {
                ids.insert(ann.id)
            }
        }
    }
    return ids
}
