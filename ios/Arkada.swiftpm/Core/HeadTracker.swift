import ARKit
import AVFoundation
import Foundation
import Observation
import Vision
import simd

/// Galvos padėties sekimas priekine kamera – bendras visiems žaidimams.
///
/// **Ženklų susitarimas (žmogaus anatomija, ne ekrano vaizdas – todėl veidrodžio taisyti nereikia):**
/// - `yaw`   > 0 – galva pasukta į **žaidėjo dešinę**;
/// - `pitch` > 0 – smakras žemyn (galva palenkta į priekį);
/// - `roll`  > 0 – **dešinė ausis link dešiniojo peties**;
/// - `depthCm` > 0 – galva atitraukta **toliau nuo telefono** (pvz. smakro įtraukimas).
/// Visi dydžiai – laipsniais / cm, **santykinai su neutralia padėtimi** (`calibrateNeutral()`).
///
/// Režimai:
/// 1. ARKit veido sekimas (`ARFaceTrackingConfiguration`, iPhone su Neural Engine) – 3 ašys + gylis.
/// 2. Vision (`VNDetectFaceRectanglesRequest`) – tik kampai, be gylio (`hasDepth == false`).
/// 3. Be kameros / neleista – `mode == .unavailable`, žaidimas turi veikti laikmačio režimu.
///
/// Kadrai apdorojami tik telefone, niekur nesaugomi ir nesiunčiami.
@Observable
final class HeadTracker {
    enum Mode: Equatable { case off, faceTracking, vision, unavailable }

    private(set) var mode: Mode = .off
    private(set) var yaw: Double = 0
    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0
    private(set) var depthCm: Double = 0
    /// Ar šiuo metu matomas veidas.
    private(set) var isTracking = false
    private(set) var cameraDenied = false

    /// Išlyginimas (0…1): didesnis – greitesnė reakcija, mažesnis – ramesnis signalas.
    var smoothing: Double = 0.35

    var hasDepth: Bool { mode == .faceTracking }
    static var supportsFaceTracking: Bool { ARFaceTrackingConfiguration.isSupported }
    var isSupported: Bool {
        Self.supportsFaceTracking
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    // ARKit
    @ObservationIgnored private var arSession: ARSession?
    @ObservationIgnored private var arDelegate: FaceSessionDelegate?
    @ObservationIgnored private var neutralRotation: simd_float3x3?
    @ObservationIgnored private var neutralDistance: Float = 0
    // Vision
    @ObservationIgnored private var visionCapture: VisionFaceCapture?
    @ObservationIgnored private var neutralAngles: (yaw: Double, pitch: Double, roll: Double)?

    @ObservationIgnored private var wantsNeutral = true
    @ObservationIgnored private var lostFrames = 0

    // MARK: - Valdymas

    func start() {
        guard mode == .off || mode == .unavailable else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startTracking()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startTracking()
                    } else {
                        self.cameraDenied = true
                        self.mode = .unavailable
                    }
                }
            }
        default:
            cameraDenied = true
            mode = .unavailable
        }
    }

    func stop() {
        arSession?.pause()
        arSession = nil
        arDelegate = nil
        visionCapture?.stop()
        visionCapture = nil
        if mode != .unavailable { mode = .off }
        isTracking = false
    }

    /// Dabartinė padėtis tampa nuliu (pritaikoma kitame kadre).
    func calibrateNeutral() {
        wantsNeutral = true
    }

    // MARK: - Paleidimas

    private func startTracking() {
        if Self.supportsFaceTracking {
            let session = ARSession()
            let delegate = FaceSessionDelegate()
            delegate.onFrame = { [weak self] frame in self?.handle(frame: frame) }
            delegate.onFailure = { [weak self] in self?.fallBackToVision() }
            session.delegate = delegate
            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = false
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            arSession = session
            arDelegate = delegate
            wantsNeutral = true
            mode = .faceTracking
        } else {
            fallBackToVision()
        }
    }

    private func fallBackToVision() {
        arSession?.pause()
        arSession = nil
        arDelegate = nil
        let capture = VisionFaceCapture()
        capture.onAngles = { [weak self] angles in
            DispatchQueue.main.async { self?.handle(visionAngles: angles) }
        }
        if capture.start() {
            visionCapture = capture
            wantsNeutral = true
            mode = .vision
        } else {
            mode = .unavailable
        }
    }

    // MARK: - ARKit kadrai (pagrindinė gija)

    private func handle(frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else {
            markLost()
            return
        }
        lostFrames = 0
        isTracking = true

        let t = face.transform
        let rotation = simd_float3x3(
            simd_make_float3(t.columns.0),
            simd_make_float3(t.columns.1),
            simd_make_float3(t.columns.2)
        )
        let facePosition = simd_make_float3(t.columns.3)
        let cameraPosition = simd_make_float3(frame.camera.transform.columns.3)
        let distance = simd_distance(facePosition, cameraPosition)

        if wantsNeutral || neutralRotation == nil {
            neutralRotation = rotation
            neutralDistance = distance
            wantsNeutral = false
            yaw = 0; pitch = 0; roll = 0; depthCm = 0
        }
        guard let r0 = neutralRotation else { return }

        // Santykinis pasukimas neutralios veido sistemos ašyse: R = R0 · Rrel → Rrel = R0ᵀ · R.
        // ARFaceAnchor ašys: +x – žiūrinčiojo dešinė (veido kairė), +y – viršugalvis, +z – iš veido į priekį.
        let rel = simd_mul(r0.transpose, rotation)
        let forward = rel.columns.2   // kur dabar „žiūri“ veidas
        let up = rel.columns.1        // kur dabar viršugalvis
        let fx = Double(forward.x), fy = Double(forward.y), fz = Double(forward.z)
        let ux = Double(up.x), uy = Double(up.y)

        // Pasukus į žaidėjo dešinę nosis eina į veido dešinę = −x → yaw > 0.
        let newYaw = atan2(-fx, fz) * 180 / .pi
        // Smakras žemyn → veido kryptis žemyn (−y) → pitch > 0.
        let newPitch = atan2(-fy, (fx * fx + fz * fz).squareRoot()) * 180 / .pi
        // Dešinė ausis link peties → viršugalvis į žaidėjo dešinę (−x) → roll > 0.
        let newRoll = atan2(-ux, uy) * 180 / .pi
        let newDepth = Double(distance - neutralDistance) * 100

        apply(yaw: newYaw, pitch: newPitch, roll: newRoll, depth: newDepth)
    }

    // MARK: - Vision kadrai

    private func handle(visionAngles: (yaw: Double, pitch: Double, roll: Double)?) {
        guard mode == .vision else { return }
        guard let a = visionAngles else {
            markLost()
            return
        }
        lostFrames = 0
        isTracking = true
        if wantsNeutral || neutralAngles == nil {
            neutralAngles = a
            wantsNeutral = false
            yaw = 0; pitch = 0; roll = 0; depthCm = 0
        }
        guard let n = neutralAngles else { return }
        // Pastaba: Vision kampų ženklai įrenginyje nepatikrinti. Mankštos logika kairę/dešinę
        // atpažįsta pagal „pakaitomis“, todėl apsivertęs ženklas skaičiavimo nesugadina.
        apply(yaw: a.yaw - n.yaw, pitch: a.pitch - n.pitch, roll: a.roll - n.roll, depth: 0)
    }

    private func apply(yaw y: Double, pitch p: Double, roll r: Double, depth d: Double) {
        let k = max(0.05, min(1, smoothing))
        yaw += (y - yaw) * k
        pitch += (p - pitch) * k
        roll += (r - roll) * k
        depthCm += (d - depthCm) * k
    }

    private func markLost() {
        lostFrames += 1
        if lostFrames > 6 { isTracking = false }
    }
}

// MARK: - ARKit delegatas (atskiras NSObject, kad HeadTracker liktų paprasta @Observable klase)

private final class FaceSessionDelegate: NSObject, ARSessionDelegate {
    var onFrame: ((ARFrame) -> Void)?
    var onFailure: (() -> Void)?

    // delegateQueue == nil → kviečiama pagrindinėje gijoje.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onFrame?(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onFailure?()
    }
}

// MARK: - Vision atsarginis kelias

private final class VisionFaceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onAngles: (((yaw: Double, pitch: Double, roll: Double)?) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "arkada.headtracker.vision")
    private var frameCounter = 0

    func start() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)
        session.commitConfiguration()
        let s = session
        queue.async { s.startRunning() }
        return true
    }

    func stop() {
        let s = session
        queue.async { s.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % 2 == 0 else { return }   // ~15 k/s pakanka

        let request = VNDetectFaceRectanglesRequest()
        if #available(iOS 15.0, *) {
            request.revision = VNDetectFaceRectanglesRequestRevision3
        }
        // Priekinė kamera, telefonas vertikaliai.
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([request])
        } catch {
            onAngles?(nil)
            return
        }
        guard let face = request.results?.first else {
            onAngles?(nil)
            return
        }
        let toDeg = 180 / Double.pi
        let yaw = (face.yaw?.doubleValue ?? 0) * toDeg
        let roll = (face.roll?.doubleValue ?? 0) * toDeg
        var pitch = 0.0
        if #available(iOS 15.0, *) {
            pitch = (face.pitch?.doubleValue ?? 0) * toDeg
        }
        onAngles?((yaw: yaw, pitch: pitch, roll: roll))
    }
}
