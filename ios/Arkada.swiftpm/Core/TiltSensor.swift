import CoreMotion
import Foundation
import Observation

/// Telefono polinkis ir purtymas visiems žaidimams (CoreMotion).
///
/// Naudojimas vaizde:
/// ```swift
/// @State private var tilt = TiltSensor()
/// ...
/// .onAppear { tilt.start() }
/// .onDisappear { tilt.stop() }
/// // tilt.steer: -1 (pakreipta į kairę) … 1 (į dešinę)
/// ```
/// Akselerometrui leidimo prašyti nereikia. Simuliatoriuje `isAvailable == false`,
/// todėl žaidimas visada turi turėti valdymą lietimu.
@Observable
final class TiltSensor {
    /// Kairė/dešinė, laikant telefoną vertikaliai: -1…1 (jau su „negyva zona“ ir išlyginimu).
    private(set) var steer: Double = 0
    /// Pirmyn/atgal: -1 (palenkta nuo savęs) … 1 (į save).
    private(set) var pitch: Double = 0
    /// Padidėja kiekvieną kartą, kai telefonas stipriai supurtomas.
    private(set) var shakeCount = 0
    private(set) var isRunning = false

    /// Kiek laipsnių polinkio duoda pilną posūkį (mažiau = jautriau).
    var fullTiltDegrees: Double = 25
    var deadZone: Double = 0.06

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var lastShake = Date.distantPast

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let full = sin(self.fullTiltDegrees * .pi / 180)
            let rawSteer = max(-1, min(1, m.gravity.x / full))
            let rawPitch = max(-1, min(1, -m.gravity.z / full))
            let s = abs(rawSteer) < self.deadZone ? 0 : rawSteer
            // Lengvas išlyginimas, kad mašina nedrebėtų.
            self.steer += (s - self.steer) * 0.35
            self.pitch += (rawPitch - self.pitch) * 0.35

            let a = m.userAcceleration
            let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            if g > 2.2, Date().timeIntervalSince(self.lastShake) > 0.8 {
                self.lastShake = Date()
                self.shakeCount += 1
            }
        }
        isRunning = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isRunning = false
        steer = 0
        pitch = 0
    }
}
