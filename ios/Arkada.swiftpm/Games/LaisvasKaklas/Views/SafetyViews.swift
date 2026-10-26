import SwiftUI

extension LaisvasKaklas {

    /// Pavojaus požymių klausimynas (pagal NHS / klinikinius „raudonųjų vėliavų“ sąrašus).
    struct ScreeningView: View {
        let onDone: (Screening) -> Void

        private struct Question: Identifiable {
            let id: Int
            let text: String
            let level: Screening
        }

        private static let questions: [Question] = [
            Question(id: 0, text: "Ar jauti rankų ar kojų silpnumą, abiejų rankų tirpimą, sutriko pusiausvyra ar eisena, pakito šlapinimasis ar tuštinimasis?", level: .emergency),
            Question(id: 1, text: "Ar kartu su kaklo skausmu svaigsta galva, sutriko rega ar kalba, sunku ryti, alpai, stipriai skauda galvą ar tirpsta veidas?", level: .urgent),
            Question(id: 2, text: "Ar neseniai patyrei traumą (kritimą, smūgį, eismo įvykį)?", level: .consult),
            Question(id: 3, text: "Ar karščiuoji, nepaaiškinamai krenta svoris arba sirgai onkologine liga?", level: .consult),
            Question(id: 4, text: "Ar skausmas labai stiprus, nuolat stiprėja arba plinta į ranką su dilgčiojimu?", level: .consult)
        ]

        @State private var answers: [Int: Bool] = [:]

        private var allAnswered: Bool { answers.count == Self.questions.count }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Prieš pradedant – saugumas")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Atsakyk sąžiningai. Tai mankšta, ne gydymas – esant šiems požymiams pirmiausia reikia gydytojo.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))

                    ForEach(Self.questions) { q in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(q.text)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                answerButton(q.id, value: false, label: "Ne")
                                answerButton(q.id, value: true, label: "Taip")
                            }
                        }
                        .padding(14)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button("Toliau") {
                        Haptics.tap()
                        onDone(result)
                    }
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                    .disabled(!allAnswered)
                    .opacity(allAnswered ? 1 : 0.5)
                }
                .padding(20)
            }
            .foregroundStyle(.white)
        }

        private var result: Screening {
            let yes = Self.questions.filter { answers[$0.id] == true }
            if yes.contains(where: { $0.level == .emergency }) { return .emergency }
            if yes.contains(where: { $0.level == .urgent }) { return .urgent }
            if !yes.isEmpty { return .consult }
            return .passed
        }

        private func answerButton(_ id: Int, value: Bool, label: String) -> some View {
            let selected = answers[id] == value
            return Button {
                Haptics.tap()
                answers[id] = value
            } label: {
                Text(label)
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? (value ? Palette.warn : Palette.calm).opacity(0.85) : Color.white.opacity(0.08))
                    )
                    .foregroundStyle(selected ? Palette.ink : Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : [])
        }
    }

    /// Kai klausimyne bent vienas „Taip“ – programa neleidžiama, aiškus patarimas.
    struct BlockedView: View {
        let screening: Screening
        let onRetake: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Programa šiuo metu išjungta tavo saugumui.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Atsakiau klaidingai – pakartoti klausimyną", action: onRetake)
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint, prominent: false))
            }
            .padding(20)
            .foregroundStyle(.white)
        }

        private var icon: String {
            screening == .emergency ? "cross.case.fill" : "stethoscope"
        }

        private var color: Color {
            screening == .consult ? Palette.warn : Palette.stop
        }

        private var title: String {
            switch screening {
            case .emergency: return "Kreipkis skubiai"
            case .urgent: return "Skubiai susisiek su gydytoju"
            default: return "Pirmiausia pasitark su gydytoju"
            }
        }

        private var message: String {
            switch screening {
            case .emergency:
                return "Rankų ar kojų silpnumas, abiejų rankų tirpimas, pusiausvyros ar šlapinimosi / tuštinimosi pokyčiai gali reikšti stuburo ar nervų pažeidimą. Vyk į priėmimo skyrių arba skambink 112."
            case .urgent:
                return "Galvos svaigimas, regos ar kalbos sutrikimai, sunkumas ryti, alpimas, stiprus galvos skausmas ar veido tirpimas kartu su kaklo skausmu turi būti skubiai įvertinti gydytojo. Nedaryk kaklo pratimų, kol gydytojas nepatvirtins, kad saugu."
            default:
                return "Po traumos, karščiuojant, nepaaiškinamai krentant svoriui, sergant onkologine liga ar esant labai stipriam, plintančiam skausmui pratimus reikia aptarti su gydytoju. Kai gydytojas leis – pakartok klausimyną."
            }
        }
    }

    /// Rodoma paspaudus „Svaigsta / skauda – stabdyti“.
    struct StopGuidanceView: View {
        let onClose: () -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Palette.stop)
                    Text("Mankšta sustabdyta")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    guidance("Atsisėsk patogiai, atsiremk ir ramiai pakvėpuok kelias minutes. Nedaryk daugiau kaklo pratimų šiandien.")
                    guidance("Jei svaigulys nepraeina per kelias minutes, atsiranda regos ar kalbos sutrikimų, veido ar rankų tirpimas, silpnumas ar stiprus galvos skausmas – skambink 112.")
                    guidance("Jei skausmas sustiprėjo ir nepraeina per dieną ar dvi – pasitark su gydytoju ar kineziterapeutu.")
                    Text("Tai mankšta, ne gydymas.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Supratau", action: onClose)
                        .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                }
                .padding(20)
            }
            .foregroundStyle(.white)
        }

        private func guidance(_ text: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Palette.peach).frame(width: 7, height: 7).padding(.top, 7)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
