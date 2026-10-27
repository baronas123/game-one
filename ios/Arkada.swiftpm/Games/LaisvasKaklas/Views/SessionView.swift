import SwiftUI

extension LaisvasKaklas {

    /// Pati mankšta: didelė 3D figūra (tu, kaip veidrodyje) su judesio kontūru ir rodyklėmis, užuominos
    /// ir visada matomas „stabdyti“ mygtukas. Niekas nebėga pagal laikmatį – pratimas laukia tavęs.
    struct SessionView: View {
        let tracker: HeadTracker
        let engine: SessionEngine
        let voiceOn: Bool
        let onFinish: () -> Void
        let onStop: () -> Void

        @State private var coach = Coach()

        var body: some View {
            ZStack {
                DawnScene(engine: engine, showsLantern: false)

                VStack(spacing: 12) {
                    topBar
                    CoachStage(engine: engine, tracker: tracker)
                        .frame(maxHeight: .infinity)
                    if engine.phase == .intro, let ex = engine.current {
                        introCard(ex)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        if engine.phase == .active, let meter = meter {
                            MoveMeter(title: meter.title, value: meter.value, holding: meter.holding)
                        }
                        cueCard
                    }
                    stopButton
                }
                .padding(16)
                .animation(.easeInOut(duration: 0.3), value: engine.phase)
            }
            .foregroundStyle(.white)
            .task { await runLoop() }
            .onDisappear { coach.stop() }
        }

        // MARK: - Ciklas

        private func runLoop() async {
            var lastSuccess = engine.successCount
            var lastAnnouncement = -1
            var lastWarning = ""
            while !Task.isCancelled {
                let reading: HeadReading? = tracker.isTracking
                    ? HeadReading(yaw: tracker.yaw, pitch: tracker.pitch, roll: tracker.roll,
                                  depthCm: tracker.depthCm, hasDepth: tracker.hasDepth)
                    : nil
                engine.update(now: Date().timeIntervalSinceReferenceDate, reading: reading)

                if engine.successCount != lastSuccess {
                    lastSuccess = engine.successCount
                    Haptics.place()
                }
                if engine.announcementID != lastAnnouncement {
                    lastAnnouncement = engine.announcementID
                    if voiceOn { coach.say(engine.announcement) }
                }
                if engine.warning != lastWarning {
                    lastWarning = engine.warning
                    if !lastWarning.isEmpty { Haptics.tap() }
                }
                if engine.isFinished {
                    Haptics.success()
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    onFinish()
                    return
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }

        // MARK: - Viršus

        private var topBar: some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(engine.current?.name ?? "Mankšta")
                        .font(.system(.headline, design: .rounded))
                    if let ex = engine.current, engine.phase == .active {
                        Text("\(min(engine.repIndex + 1, ex.reps)) / \(ex.reps)")
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    ProgressView(value: engine.sessionProgress)
                        .tint(Palette.peach)
                        .frame(width: 140)
                    trackingChip
                }
                Spacer()
            }
        }

        private var trackingChip: some View {
            let text: String
            let symbol: String
            switch tracker.mode {
            case .faceTracking:
                text = tracker.isTracking ? "Seku galvą (3D)" : "Nematau veido"
                symbol = tracker.isTracking ? "faceid" : "eye.slash"
            case .vision:
                text = tracker.isTracking ? "Seku galvą" : "Nematau veido"
                symbol = tracker.isTracking ? "camera.viewfinder" : "eye.slash"
            case .off, .unavailable:
                text = "Laikmačio režimas"
                symbol = "timer"
            }
            return Label(engine.guided && engine.phase == .active ? "Laikmačio režimas" : text, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        }

        // MARK: - Užuominos

        private func introCard(_ ex: Exercise) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kitas pratimas · žiūrėk, kaip daro treneris, ir pradėk, kai būsi pasiruošęs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(ex.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(ex.instruction)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ex.why)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Button("Pradėti") {
                        Haptics.tap()
                        engine.startNow()
                    }
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                    Button("Praleisti") {
                        Haptics.tap()
                        engine.skipExercise()
                    }
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint, prominent: false))
                }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }

        /// Juosta po treneriu: kelias iki taikinio, išlaikymas ar grįžimas.
        private var meter: (title: String, value: Double, holding: Bool)? {
            guard let ex = engine.current else { return nil }
            switch engine.stage {
            case .approach:
                guard tracker.isTracking || engine.guided else { return nil }
                return ("Iki taikinio", engine.valueNorm * Double(engine.demoSide) / 0.92, false)
            case .hold:
                return (ex.kind == .stretch ? "Tempk ir kvėpuok" : "Išlaikyk", engine.holdProgress, true)
            case .returning:
                return ("Atgal į centrą", 1 - min(1, abs(engine.valueNorm)), false)
            case .prepare:
                return nil
            case .press:
                return ("Spausk – galva nejuda", engine.holdProgress, true)
            case .rest:
                return ("Atpalaiduok", 1, false)
            case .rhythm:
                return ("Kartojimas", engine.holdProgress, engine.isHolding)
            }
        }

        private var cueCard: some View {
            VStack(spacing: 8) {
                Text(engine.cue)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contentTransition(.opacity)
                if engine.waitingForReady {
                    Button {
                        Haptics.tap()
                        engine.confirmReady()
                    } label: {
                        Label("Delnas vietoje – spausti", systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                }
                if engine.phase == .active {
                    Button("Praleisti pratimą") {
                        Haptics.tap()
                        engine.skipExercise()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
        }

        private var stopButton: some View {
            Button {
                Haptics.error()
                coach.stop()
                onStop()
            } label: {
                Label("Svaigsta / skauda – stabdyti", systemImage: "hand.raised.fill")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Palette.stop, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Iškart sustabdo mankštą")
        }
    }
}
