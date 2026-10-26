import SwiftUI

extension ParkavimoMeistras {

    /// Žaidimo meniu: aikštelių sąrašas ir nustatymai (vairas, AR kamera).
    struct RootView: View {
        @AppStorage(GameStorage.key(ParkavimoMeistras.id, "tilt")) private var useTilt = false
        @AppStorage(GameStorage.key(ParkavimoMeistras.id, "ar")) private var useAR = false
        @State private var playing: Session?
        @State private var refresh = 0
        @State private var probe = TiltSensor()

        struct Session: Identifiable {
            let id = UUID()
            let level: Int
        }

        private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        private let taxi = Color(red: 1, green: 0.76, blue: 0.1)

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        GameCloseButton()
                        Spacer()
                    }
                    Hero()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARKADA · 12 AIKŠTELIŲ")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(taxi)
                        Text("Parkavimo meistras")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .textCase(.uppercase)
                            .minimumScaleFactor(0.7)
                        Text("Nuo vairavimo mokyklos aikštelės iki Gedimino prospekto ir požeminio garažo. Įvažiuok į švytinčią vietą, sustok tiesiai ir nekliudyk kaimynų.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Levels.all.indices, id: \.self) { i in
                            levelCard(i)
                        }
                    }

                    settings
                }
                .padding(16)
            }
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [Color(red: 0.15, green: 0.19, blue: 0.24), Color(red: 0.07, green: 0.08, blue: 0.1)],
                               startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
            .fullScreenCover(item: $playing, onDismiss: { refresh += 1 }) { s in
                GameView(level: s.level)
            }
        }

        private func stars(_ i: Int) -> Int {
            _ = refresh
            return ParkavimoMeistras.storage.int("stars.\(i)")
        }

        private func unlocked(_ i: Int) -> Bool { i == 0 || stars(i - 1) > 0 }

        private func levelCard(_ i: Int) -> some View {
            let lv = Levels.all[i]
            let open = unlocked(i)
            let earned = stars(i)
            let isNext = open && earned == 0
            return Button {
                Haptics.tap()
                playing = Session(level: i)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%02d", i + 1))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(taxi)
                    Text(lv.name)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(lv.place)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    if open {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { k in
                                Image(systemName: k < earned ? "star.fill" : "star")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(k < earned ? taxi : Color.white.opacity(0.2))
                            }
                        }
                    } else {
                        Label("UŽRAKINTA", systemImage: "lock.fill")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isNext ? taxi : Color.white.opacity(0.12), lineWidth: isNext ? 2 : 1)
                )
                .opacity(open ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!open)
            .accessibilityLabel("\(i + 1). \(lv.name), \(lv.place)" + (open ? (earned > 0 ? ", \(earned) žvaigždutės" : "") : ", užrakinta"))
        }

        private var settings: some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VAIRAS").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                    Picker("Vairas", selection: $useTilt) {
                        Text("Mygtukai").tag(false)
                        Text("Polinkis").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if useTilt && !probe.isAvailable {
                        Text("Jutikliai šiame įrenginyje nepasiekiami – vairuosi lietimu.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if useTilt {
                        Text("Laikyk telefoną prieš save ir sukite jį kaip vairą. Pedalai lieka ekrane.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Toggle(isOn: $useAR) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AR režimas").font(.system(.headline, design: .rounded))
                        Text("Galinio vaizdo kameroje – tikras telefono kameros vaizdas su kreipiamosiomis linijomis.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .tint(taxi)
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Meniu viršaus piešinys: eilė mašinų ir švytinti laisva vieta.
    struct Hero: View {
        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.22, green: 0.235, blue: 0.26)))
                var c = ctx
                let s = Double(size.height) / 7.5
                c.scaleBy(x: s, y: s)
                let wm = Double(size.width) / s
                var lines = Path()
                var x = 0.4
                while x < wm {
                    lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: 5.2))
                    x += 2.7
                }
                c.stroke(lines, with: .color(.white.opacity(0.85)), lineWidth: 0.12)
                let colors: [UInt32] = [0xC8102E, 0x2E7D4F, 0x26292E, 0x3A7BD5, 0x1F4E9C, 0xE6E6E3, 0xD4572A]
                var i = 0
                x = 1.75
                while x < wm {
                    if i != 2 {
                        Art.car(c, x: x, y: 2.7, a: Double(i % 2 == 0 ? 90 : -90) * Double.pi / 180, color: colors[i % colors.count])
                    }
                    x += 2.7
                    i += 1
                }
                let sx = 1.75 + 2 * 2.7
                let spot = CGRect(x: sx - 1.3, y: 0.1, width: 2.6, height: 5.2)
                c.stroke(Path(spot), with: .color(Color(red: 0.3, green: 0.76, blue: 1).opacity(0.3)), lineWidth: 0.4)
                c.stroke(Path(spot), with: .color(Color(red: 0.3, green: 0.76, blue: 1)), style: StrokeStyle(lineWidth: 0.14, dash: [0.6, 0.35]))
                Art.car(c, x: sx + 0.6, y: 6.2, a: -70 * Double.pi / 180, color: ParkavimoMeistras.playerColor, steer: -0.4, player: true)
                Art.tree(c, Tree(x: wm - 1.2, y: 6.4, r: 1.4), blobs: [
                    Disc(x: wm - 1.7, y: 6.0, r: 0.8), Disc(x: wm - 0.7, y: 6.1, r: 0.75),
                    Disc(x: wm - 1.3, y: 6.9, r: 0.8), Disc(x: wm - 0.8, y: 6.8, r: 0.7)
                ])
            }
            .accessibilityHidden(true)
        }
    }
}
