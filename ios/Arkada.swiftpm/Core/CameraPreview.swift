import AVFoundation
import SwiftUI
import UIKit

/// Gyvas kameros vaizdas bet kuriam žaidimui (pvz. tavo veidas galinio vaizdo veidrodėlyje).
///
/// ```swift
/// CameraPreview(position: .front)
///     .frame(width: 120, height: 60)
///     .clipShape(RoundedRectangle(cornerRadius: 10))
/// ```
/// Leidimo paprašoma automatiškai pirmą kartą. Jei vartotojas neleidžia arba kameros
/// nėra (simuliatorius), rodomas `placeholder` – žaidimas turi veikti ir be kameros.
struct CameraPreview<Placeholder: View>: View {
    var position: AVCaptureDevice.Position = .front
    var mirrored = true
    var placeholder: () -> Placeholder

    @State private var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    init(position: AVCaptureDevice.Position = .front, mirrored: Bool = true,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.position = position
        self.mirrored = mirrored
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if authorized {
                CameraLayerView(position: position, mirrored: mirrored)
            } else {
                placeholder()
            }
        }
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            }
        }
    }
}

extension CameraPreview where Placeholder == Color {
    init(position: AVCaptureDevice.Position = .front, mirrored: Bool = true) {
        self.init(position: position, mirrored: mirrored) { Color.black }
    }
}

private struct CameraLayerView: UIViewRepresentable {
    let position: AVCaptureDevice.Position
    let mirrored: Bool

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.configure(position: position, mirrored: mirrored)
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.stop()
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "arkada.camera")

        func configure(position: AVCaptureDevice.Position, mirrored: Bool) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            let session = self.session
            queue.async {
                session.beginConfiguration()
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
                session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    guard let connection = self?.previewLayer.connection,
                          connection.isVideoMirroringSupported else { return }
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
            }
        }

        func stop() {
            let session = self.session
            queue.async { session.stopRunning() }
        }
    }
}
