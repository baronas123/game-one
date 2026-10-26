import SwiftUI

extension NaktinisGreitkelis {

    /// Prietaisų skydelis: laikas, atstumas, galinio vaizdo veidrodėlis, kitas miestas, spidometras, nitro.
    struct HudView: View {
        let engine: RaceEngine
        let cameraOn: Bool
        let nitroHint: String
        let onPause: () -> Void

        var body: some View {
            TimelineView(.animation) { _ in
                content
            }
        }

        private var content: some View {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    GlassBox {
                        Label2(title: "LAIKAS", value: "\(Int(engine.timeLeft.rounded(.up)))",
                               color: engine.timeLeft < 10 ? Color(red: 1, green: 0.3, blue: 0.37) : .white)
                    }
                    Spacer()
                    GlassBox {
                        Label2(title: "NUVAŽIUOTA", value: engine.km.lt(1), color: .white, trailing: true)
                    }
                    Button(action: onPause) {
                        Text("II").font(.system(size: 15, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                    }
                    .accessibilityLabel("Pauzė")
                }

                RearMirror(engine: engine, cameraOn: cameraOn)

                Text("→ \(RaceEngine.cityName(engine.checkpoint).uppercased()) \(engine.kmToNext.lt(1)) km")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Neon.sign, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
                    .allowsHitTesting(false)

                Spacer()

                ZStack {
                    if engine.mode == .countdown {
                        Text("\(Int(engine.countdown.rounded(.up)))")
                            .font(.system(size: 120, weight: .black, design: .rounded))
                            .shadow(color: Neon.magenta, radius: 20)
                    } else if engine.bannerVisible {
                        VStack(spacing: 4) {
                            Text(engine.bannerTitle)
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .italic()
                                .shadow(color: Neon.magenta, radius: 12)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            if !engine.bannerSubtitle.isEmpty {
                                Text(engine.bannerSubtitle)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Neon.cyan)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)

                Spacer()

                HStack(alignment: .bottom) {
                    GlassBox {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(engine.speedKmh)")
                                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                Text("km/h").font(.caption).foregroundStyle(.white.opacity(0.7))
                            }
                            Text("NITRO").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.12))
                                    Capsule()
                                        .fill(LinearGradient(colors: [Neon.cyan, Neon.magenta], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: g.size.width * CGFloat(engine.nitro))
                                }
                            }
                            .frame(width: 100, height: 8)
                        }
                    }
                    .allowsHitTesting(false)
                    Spacer()
                    NitroButton(engine: engine, hint: nitroHint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private struct GlassBox<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
    }

    private struct Label2: View {
        let title: String
        let value: String
        let color: Color
        var trailing = false

        var body: some View {
            VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
                Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(color)
            }
        }
    }

    /// Nitro mygtukas: laikyk – veikia nitro.
    private struct NitroButton: View {
        let engine: RaceEngine
        let hint: String
        @State private var pressed = false

        var body: some View {
            VStack(spacing: 0) {
                Text("N₂O").font(.system(size: 18, weight: .bold))
                Text(hint).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 84, height: 84)
            .background(
                Circle().fill(RadialGradient(colors: pressed ? [Neon.magenta.opacity(0.7), Neon.cyan.opacity(0.4)]
                                                             : [Neon.cyan.opacity(0.35), Neon.night.opacity(0.7)],
                                             center: .center, startRadius: 0, endRadius: 42))
            )
            .overlay(Circle().stroke(Neon.cyan, lineWidth: 2))
            .shadow(color: Neon.cyan.opacity(0.5), radius: 10)
            .scaleEffect(pressed ? 0.95 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; Haptics.tap() }
                        engine.nitroHeld = true
                    }
                    .onEnded { _ in
                        pressed = false
                        engine.nitroHeld = false
                    }
            )
            .accessibilityLabel("Nitro")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// Galinio vaizdo veidrodėlis: priekinė kamera (tavo veidas) arba nupieštas kelias už nugaros.
    struct RearMirror: View {
        let engine: RaceEngine
        let cameraOn: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.08, green: 0.06, blue: 0.12)).frame(width: 8, height: 10)
                ZStack {
                    if cameraOn {
                        CameraPreview(position: .front, mirrored: true) {
                            MirrorRoad(engine: engine)
                        }
                        Color(red: 0.31, green: 0.16, blue: 0.55).opacity(0.18)
                    } else {
                        MirrorRoad(engine: engine)
                    }
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.22), location: 0),
                        .init(color: .white.opacity(0), location: 0.35),
                        .init(color: .white.opacity(0), location: 0.6),
                        .init(color: .white.opacity(0.08), location: 0.7),
                        .init(color: .white.opacity(0), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(width: 200, height: 68)
                .clipShape(shape)
                .padding(5)
                .background(Color(red: 0.1, green: 0.08, blue: 0.14), in: RoundedRectangle(cornerRadius: 31, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
            }
            .allowsHitTesting(false)
            .accessibilityLabel(cameraOn ? "Galinio vaizdo veidrodėlis su kamera" : "Galinio vaizdo veidrodėlis")
        }
    }

    /// Nupieštas „kelias už nugaros“ veidrodėlyje: dangus, kelias, sekančios mašinos žibintai.
    struct MirrorRoad: View {
        let engine: RaceEngine

        var body: some View {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(stops: [
                    .init(color: Color(red: 0.11, green: 0.04, blue: 0.24), location: 0),
                    .init(color: Color(red: 0.42, green: 0.10, blue: 0.43), location: 0.5),
                    .init(color: Color(red: 0.08, green: 0.02, blue: 0.16), location: 0.52),
                    .init(color: Color(red: 0.05, green: 0.02, blue: 0.13), location: 1)
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                let hz = h * 0.51, cx = w / 2 - CGFloat(engine.steerVisual) * 6
                var road = Path()
                road.move(to: CGPoint(x: cx - 2, y: hz))
                road.addLine(to: CGPoint(x: cx + 2, y: hz))
                road.addLine(to: CGPoint(x: cx + w * 0.5, y: h))
                road.addLine(to: CGPoint(x: cx - w * 0.5, y: h))
                road.closeSubpath()
                ctx.fill(road, with: .color(Neon.roadB))
                var edges = Path()
                edges.move(to: CGPoint(x: cx - 2, y: hz)); edges.addLine(to: CGPoint(x: cx - w * 0.5, y: h))
                edges.move(to: CGPoint(x: cx + 2, y: hz)); edges.addLine(to: CGPoint(x: cx + w * 0.5, y: h))
                ctx.stroke(edges, with: .color(Neon.magenta.opacity(0.8)), lineWidth: 1.5)
                let t = engine.time
                let fx = cx + CGFloat(sin(t * 0.7)) * w * 0.08
                let fy = hz + h * CGFloat(0.1 + (t * 0.6).truncatingRemainder(dividingBy: 1) * 0.05)
                for d in [-1.0, 1.0] {
                    let p = CGPoint(x: fx + CGFloat(d) * 7, y: fy)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)),
                             with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.86).opacity(0.95), .clear]),
                                                   center: p, startRadius: 0, endRadius: 12))
                }
            }
        }
    }
}
