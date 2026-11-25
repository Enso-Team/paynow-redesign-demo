import AVFoundation
import CoreImage.CIFilterBuiltins
import PhotosUI
import SGQR
import SwiftUI
import Vision

/// Sample codes for the simulator, which has no camera. Same codes as `web/app/packages/sgqr/samples`.
extension SGQRSample: @retroactive Identifiable {
    public var id: String { rawValue }

    static let scannerSamples: [SGQRSample] = [.mobile, .uen, .nets, .rejected]

    var label: String {
        switch self {
        case .mobile: "91234567 · SGD 12.50"
        case .uen: "UEN · any amount"
        case .nets: "NETS (not PayNow)"
        case .rejected: "Rejected payee"
        case .slow: "90000001 · slow lookup"
        }
    }

    /// The sample's QR code as a crisp thumbnail.
    var thumbnail: UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(raw.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 4, y: 4)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }
}

struct ScannerView: View {
    @Environment(AppModel.self) private var app
    @State private var pickerItem: PhotosPickerItem?
    @State private var error: String?
    @State private var handled = false
    @State private var cameraAvailable = AVCaptureDevice.default(for: .video) != nil

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            camera
            VStack(spacing: 14) {
                Text("Scan QR Code")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.ink)
                Text("Line up with the frame to scan NETS, SGQR, PayNow QR codes.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text("PHOTO LIBRARY")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .overlay(Capsule().stroke(Color.inkSecondary, lineWidth: 1))
                }
                .accessibilityIdentifier("scanner.photos")
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .background(.white)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await decodePhoto(item) }
        }
        .onAppear { handled = false }
        .background(AppearProbe { app.scannerAppeared() })
    }

    private var header: some View {
        ZStack {
            Text("Scan & Pay").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.ink)
            HStack {
                Button {
                    if app.journey?.root == .scanner { app.endJourney() } else { app.closeForm() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 50)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Scan", "Your QR", "Create QR"].enumerated()), id: \.offset) { index, title in
                VStack(spacing: 14) {
                    Text(title)
                        .font(.system(size: 16.5))
                        .foregroundStyle(index == 0 ? Color.ink : Color.inkSecondary)
                    Rectangle().fill(index == 0 ? Color.scannerOrange : .clear).frame(height: 2.5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
    }

    private var camera: some View {
        ZStack {
            if cameraAvailable {
                CameraPreview { code in decoded(code) }
            } else {
                Color(hex: 0x2B2E33)
            }
            ScanFrame()
                .frame(width: 220, height: 220)
            if !cameraAvailable {
                Text("Camera isn't available. Upload a QR image or try a sample.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(width: 290)
                VStack {
                    Spacer()
                    samples
                }
                .padding(.bottom, 26)
            }
            if let error {
                VStack {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .accessibilityIdentifier("scanner.error")
                    Spacer()
                }
                .padding(.top, 16)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut, value: error)
    }

    private var samples: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SGQRSample.scannerSamples) { sample in
                    Button {
                        decoded(sample.raw)
                    } label: {
                        HStack(spacing: 7) {
                            Image(uiImage: sample.thumbnail)
                                .interpolation(.none)
                                .resizable()
                                .padding(1.5)
                                .frame(width: 26, height: 26)
                                .background(.white, in: RoundedRectangle(cornerRadius: 4))
                            Text(sample.label)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.leading, 5)
                        .padding(.trailing, 11)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sample.label)
                    .accessibilityIdentifier("sample.\(sample.rawValue)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    /// A non-PayNow code shows the error and keeps scanning.
    private func decoded(_ raw: String) {
        guard !handled else { return }
        do {
            _ = try SGQR.parse(raw)
            handled = true
            error = nil
            TraceRecorder.shared.end(AppModel.scanSpan)
            app.send(.payQR(raw), from: .journey)
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ message: String) {
        error = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if error == message { error = nil }
        }
    }

    private func decodePhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return show("Couldn't open that photo")
        }
        do {
            var request = DetectBarcodesRequest()
            request.symbologies = [.qr]
            let observations: [BarcodeObservation] = try await request.perform(on: data)
            if let payload = observations.compactMap({ $0.payloadString }).first {
                decoded(payload)
            } else {
                show("No QR code found in that photo")
            }
        } catch {
            show("No QR code found in that photo")
        }
    }
}

/// The four white corner brackets of the scan frame.
struct ScanFrame: View {
    var body: some View {
        Canvas { context, size in
            let arm: CGFloat = 34, radius: CGFloat = 8
            var path = Path()
            for (x, y) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                let corner = CGPoint(x: x * size.width, y: y * size.height)
                let dx: CGFloat = x == 0 ? 1 : -1, dy: CGFloat = y == 0 ? 1 : -1
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + dx * arm, y: corner.y), radius: radius)
                path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            }
            context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
        }
        .padding(1.5)
        .accessibilityHidden(true)
    }
}

/// Live camera preview that reports QR payloads.
struct CameraPreview: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = context.coordinator.session
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let session = AVCaptureSession()
        var onCode: (String) -> Void
        private let queue = DispatchQueue(label: "scanner.camera")

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func start() {
            queue.async { [self] in
                guard session.inputs.isEmpty else { return session.startRunning() }
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else { return }
                session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else { return }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                session.startRunning()
            }
        }

        func stop() {
            queue.async { [self] in session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first
            else { return }
            MainActor.assumeIsolated { onCode(code) }
        }
    }
}
