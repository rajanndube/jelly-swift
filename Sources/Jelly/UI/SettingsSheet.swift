import SwiftUI

/// Mirrors `dev.jelly.ui.SettingsSheet`. Native iOS bottom-sheet content:
/// `NavigationStack` + `Form` + a single Done toolbar button. The dark
/// surface, rounded top corners, drag indicator, and dismiss-on-drag all
/// come from the system sheet (`.presentationDetents`,
/// `.presentationDragIndicator`) configured on the call site.
/// Status surface for the "catch-up sync" row rendered inside the
/// settings sheet. The owning view computes the count and runs the
/// push; the sheet just renders the state. Mirrors
/// `dev.jelly.ui.CatchUpSyncStatus` (jelly-android).
public struct CatchUpSyncStatus: Equatable, Sendable {
    /// Number of annotations across all screen keys whose `syncedTo`
    /// is nil — i.e. waiting to be flushed.
    public var pendingCount: Int = 0
    /// True while a push is in-flight; the button shows progress and is disabled.
    public var isPushing: Bool = false
    /// Short user-facing result string ("Pushed 5 of 5", "1 failed", …)
    /// from the most recent push, or nil if none has run this session.
    public var lastResult: String? = nil

    public init(pendingCount: Int = 0, isPushing: Bool = false, lastResult: String? = nil) {
        self.pendingCount = pendingCount
        self.isPushing = isPushing
        self.lastResult = lastResult
    }
}

struct SettingsSheet: View {
    @Binding var settings: JellySettings
    var onDismiss: () -> Void
    /// Status of the catch-up sync row (pending count, in-flight flag,
    /// last result message). Recomputed by the owner whenever the sheet
    /// opens or pushing finishes.
    var catchUpStatus: CatchUpSyncStatus = CatchUpSyncStatus()
    /// Triggered when the user taps the catch-up sync row. Implementation
    /// lives in `JellyOverlayContent` and calls
    /// `pushUnsyncedAnnotations` against the current endpoint.
    var onPushPending: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                detailLevelSection
                accentColorSection
                syncSection
            }
            .navigationTitle("Jelly Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JellyTheme.background)
        }
        .tint(settings.accentColor.color)
    }

    private var detailLevelSection: some View {
        Section {
            Picker("Detail level", selection: $settings.detailLevel) {
                ForEach(JellyDetailLevel.allCases, id: \.self) { lvl in
                    Text(lvl.label).tag(lvl)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Output detail")
        } footer: {
            Text("Controls how much metadata each annotation includes when copied or shared.")
        }
    }

    private var accentColorSection: some View {
        Section("Accent") {
            HStack(spacing: 14) {
                ForEach(JellyAccentColor.allCases, id: \.self) { c in
                    Button {
                        settings.accentColor = c
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(settings.accentColor == c ? c.color : Color.clear, lineWidth: 2.5)
                                .frame(width: 32, height: 32)
                            Circle()
                                .fill(c.color)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(c.rawValue.capitalized))
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section {
            Toggle("Sync to MCP server", isOn: $settings.syncEnabled)
            if settings.syncEnabled {
                TextField("Endpoint URL", text: Binding(
                    get: { settings.endpoint ?? "" },
                    set: { settings.endpoint = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)

                TextField("Webhook URL (optional)", text: Binding(
                    get: { settings.webhookUrl ?? "" },
                    set: { settings.webhookUrl = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Sync")
        } footer: {
            if settings.syncEnabled {
                Text("Annotations will POST to your MCP /sessions endpoint after each capture.")
            }
        }

        if settings.syncEnabled {
            catchUpSyncSection
        }
    }

    /// "Catch-up sync" row — pushes annotations captured before the
    /// endpoint was set up. Real-time per-capture sync continues
    /// automatically afterwards.
    private var catchUpSyncSection: some View {
        Section {
            catchUpButton
            if let result = catchUpStatus.lastResult {
                Text(result)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Catch-up sync")
        } footer: {
            if (settings.endpoint?.isEmpty ?? true) {
                Text("Set an endpoint URL above to enable.")
            } else {
                Text("Push annotations captured before the cable was connected. Real-time sync continues automatically afterwards.")
            }
        }
    }

    @ViewBuilder
    private var catchUpButton: some View {
        // Always tappable when an endpoint is set. The action runs a
        // verify-and-push: it queries the server for known annotation
        // IDs and only pushes the ones the server doesn't already have,
        // so re-tapping when "All synced" is a cheap no-op rather than
        // a duplicate POST. Disabling only during an in-flight push.
        let endpointSet = !(settings.endpoint?.isEmpty ?? true)
        let canPush = endpointSet && !catchUpStatus.isPushing
        let label: String = {
            if catchUpStatus.isPushing { return "Syncing…" }
            return "Sync now"
        }()

        Button(action: onPushPending) {
            HStack {
                if catchUpStatus.isPushing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                }
                Text(label)
                    .fontWeight(canPush ? .semibold : .regular)
                Spacer()
            }
            .foregroundColor(canPush ? settings.accentColor.color : .secondary)
        }
        .disabled(!canPush)
    }
}

private extension JellyDetailLevel {
    var label: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        case .forensic: return "Forensic"
        }
    }
}
