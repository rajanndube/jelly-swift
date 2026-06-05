#if canImport(UIKit)
import SwiftUI
import UIKit
import AVFoundation

/// Debug-only QR scanner presented from the settings sheet to fill in the
/// MCP endpoint URL by pointing the camera at the QR code on the local
/// Jelly sync landing page (the page mints a fresh code on every refresh).
///
/// Camera-backed, so it only does anything on a real device — the iOS
/// Simulator has no capture hardware and lands on the `.unavailable` state.
///
/// **Host requirement:** the app must declare `NSCameraUsageDescription` in
/// its Info.plist. Without that key iOS terminates the process the instant
/// capture is requested, so a missing-key host gets a hard crash, not a
/// denied prompt. The sample app sets it; host apps that opt into sync must
/// too (see README).
struct QRScannerSheet: View {
    var accent: Color
    /// Called once, on the main actor, with the decoded string the first
    /// time a QR payload is read. The owner is responsible for dismissing.
    var onScan: (String) -> Void
    var onCancel: () -> Void

    @State private var phase: Phase = .checking

    enum Phase: Equatable { case checking, scanning, denied, unavailable }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .tint(accent)
        .task { await resolvePermission() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .checking:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        case .scanning:
            ZStack {
                CameraPreview(onCode: handleCode)
                    .ignoresSafeArea()
                viewfinder
            }
        case .denied:
            message(
                icon: "video.slash",
                title: "Camera access needed",
                detail: "Allow camera access in Settings, then point Jelly at the QR code on the sync landing page.",
                action: ("Open Settings", openSystemSettings)
            )
        case .unavailable:
            message(
                icon: "camera.metering.unknown",
                title: "Camera unavailable",
                detail: "No capture device is available here — QR scanning needs a real device. Paste the endpoint URL manually instead.",
                action: nil
            )
        }
    }

    private var viewfinder: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent, lineWidth: 3)
                .frame(width: 220, height: 220)
            Text("Point at the sync page's QR code")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 20)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func message(
        icon: String,
        title: String,
        detail: String,
        action: (String, () -> Void)?
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }

    private func handleCode(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScan(trimmed)
    }

    @MainActor
    private func resolvePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = cameraAvailable ? .scanning : .unavailable
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            phase = granted ? (cameraAvailable ? .scanning : .unavailable) : .denied
        default:
            phase = .denied
        }
    }

    private var cameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Bridges an `AVCaptureSession` QR pipeline into SwiftUI. The session is
/// started/stopped with the controller's appearance lifecycle and reports
/// the first decoded payload back on the main queue.
private struct CameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onCode = onCode
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dev.jelly.qr.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // startRunning() blocks; keep it off the main thread.
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReported,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        hasReported = true
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onCode?(value)
    }
}
#endif
