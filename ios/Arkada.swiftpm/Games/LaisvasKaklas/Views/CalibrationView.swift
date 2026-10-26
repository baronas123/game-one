import SwiftUI

extension LaisvasKaklas {

    /// Patogios amplitudės matavimas prieš pirmą mankštą (ir iš nustatymų).
    struct CalibrationView: View {
        let tracker: HeadTracker
        let start: Calibration
        let onDone: (Calibration) -> Void

        @State private var engine: CalibrationEngine?

        var body: some View {
            VStack(spacing: 18) {
                Text("Patogi judesių riba")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .padding(.top, 8)

                Text("Judėk tik tiek, kiek patogu, **be skausmo**. Tai ne varžybos – kuo ramiau, tuo tiksliau.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))

                HeadAvatar(yaw: tracker.yaw, pitch: tracker.pitch, roll: tracker.roll, tracking: tracker.isTracking)
                    .frame(width: 150, height: 150)

                if let e = engine {
                    stageView(e)
                }

                Spacer(minLength: 0)

                if tracker.mode == .unavailable || tracker.cameraDenied {
                    Text("Kamera nepasiekiama – bus naudojamos atsargios numatytosios ribos. Kamerą galima leisti Nustatymuose → Arkada.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button("Praleisti – naudoti atsargias ribas") {
                    // Ciklas pastebės `isDone` ir pats iškvies onDone.
                    if let e = engine { e.skipAll() } else { onDone(start) }
                }
                .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint, prominent: false))
            }
            .padding(20)
            .foregroundStyle(.white)
            .task {
                let e = CalibrationEngine(hasDepth: tracker.hasDepth || HeadTracker.supportsFaceTracking, start: start)
                engine = e
                var finished = false
                while !Task.isCancelled && !finished {
                    let reading: HeadReading? = tracker.isTracking
                        ? HeadReading(yaw: tracker.yaw, pitch: tracker.pitch, roll: tracker.roll,
                                      depthCm: tracker.depthCm, hasDepth: tracker.hasDepth)
                        : nil
                    e.update(now: Date().timeIntervalSinceReferenceDate, reading: reading)
                    if e.consumeNeutralRequest() {
                        tracker.calibrateNeutral()
                        Haptics.tap()
                    }
                    if e.isDone {
                        finished = true
                        Haptics.success()
                        onDone(e.result)
                    }
                    try? await Task.sleep(nanoseconds: 33_000_000)
                }
            }
        }

        @ViewBuilder
        private func stageView(_ e: CalibrationEngine) -> some View {
            switch e.stage {
            case .neutral:
                VStack(spacing: 10) {
                    Text("Atsisėsk tiesiai, telefoną laikyk akių aukštyje ~40 cm atstumu.")
                        .multilineTextAlignment(.center)
                    Text(tracker.isTracking ? "Žiūrėk tiesiai ir nejudėk…" : "Ieškau veido…")
                        .font(.headline)
                    ProgressView(value: e.progress)
                        .tint(Palette.calm)
                }
            case .measure:
                if let step = e.currentStep {
                    VStack(spacing: 10) {
                        Text(step.title)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Text(step.instruction)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(valueText(step.axis, e.bestValue))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Palette.peach)
                        ProgressView(value: e.progress)
                            .tint(Palette.peach)
                    }
                }
            case .pause:
                VStack(spacing: 10) {
                    Text("Lėtai grįžk į centrą ir atsipalaiduok")
                        .font(.headline)
                    ProgressView(value: e.progress)
                        .tint(Palette.calm)
                }
            case .done:
                Text("Išsaugota ✓")
                    .font(.headline)
            }
        }

        private func valueText(_ axis: TrackedAxis, _ v: Double) -> String {
            axis == .depth ? "\(max(0, v).lt(1)) cm" : "\(Int(max(0, v).rounded()))°"
        }
    }
}
