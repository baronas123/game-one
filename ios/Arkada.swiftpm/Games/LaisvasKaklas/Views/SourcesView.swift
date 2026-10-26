import SwiftUI

extension LaisvasKaklas {

    /// „Kodėl šie pratimai“ – trumpai ir paprastai apie įrodymus.
    struct SourcesView: View {
        @Environment(\.dismiss) private var dismiss

        private struct Source: Identifiable {
            let id: Int
            let title: String
            let finding: String
            let url: String
        }

        private let sources: [Source] = [
            Source(id: 0,
                   title: "Cochrane apžvalga, Gross ir kt., 2015 – „Exercises for mechanical neck disorders“",
                   finding: "Lėtiniam kaklo skausmui labiausiai padeda kaklo, pečių ir mentių stiprinimo pratimai bei tempimo ir stiprinimo derinys (vidutinio patikimumo įrodymai). Vien tempimo nauda maža.",
                   url: "https://www.cochranelibrary.com/cdsr/doi/10.1002/14651858.CD004250.pub5/full"),
            Source(id: 1,
                   title: "JOSPT klinikinės gairės „Neck Pain: Revision 2017“ (Blanpied ir kt.)",
                   finding: "Rekomenduoja aktyvius pratimus – judrumo, stiprinimo, ištvermės. Prieš pradedant reikia atmesti rimtų ligų požymius.",
                   url: "https://www.jospt.org/doi/10.2519/jospt.2017.0302"),
            Source(id: 2,
                   title: "NHS ligoninių lankstinukai kaklo skausmui",
                   finding: "Lėti judesiai iki patogios ribos, 10–20 kartojimų 1–2 kartus per dieną. Lengvas diskomfortas normalu, stiprus skausmas – stabdyti.",
                   url: "https://northcheshireandmersey.nhs.uk/media/emlfdohl/neck-range-of-motion-exercises-patient-advice-sheet.pdf"),
            Source(id: 3,
                   title: "Andersen ir kt., 2013 – mentių funkcijos treniruotės biuro darbuotojams",
                   finding: "10 savaičių mentis laikančių raumenų pratimų kaklo ir pečių skausmą sumažino ~2 balais iš 10.",
                   url: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4000422/")
        ]

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Programa sudaryta pagal tyrimų apžvalgas ir gydytojų bei kineziterapeutų rekomendacijas. Dozės sąmoningai atsargios, nes mankšta daroma be specialisto priežiūros.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))

                        principle("Lėtai ir kontroliuojamai", "Taškai skiriami už ramų judesį ir išlaikymą – niekada už greitį ar didžiausią amplitudę.")
                        principle("Tavo patogi riba", "Taikiniai – 65 % tavo patogios amplitudės, po kiekvienos neskausmingos mankštos +5 %, daugiausia 90 %.")
                        principle("Skausmo stebėjimas", "Prieš ir po mankštos įvertini skausmą 0–10. Jei jis didėja – programa pataria sustoti ir pasitarti su gydytoju.")

                        ForEach(sources) { s in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.title)
                                    .font(.headline)
                                Text(s.finding)
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.8))
                                if let url = URL(string: s.url) {
                                    Link("Atidaryti šaltinį", destination: url)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Palette.peach)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        Text("Tai mankšta, ne gydymas. Programos nepatikrino kineziterapeutas – jei turi galimybę, parodyk ją specialistui.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(20)
                }
                .foregroundStyle(.white)
                .background(Palette.night.ignoresSafeArea())
                .navigationTitle("Kodėl šie pratimai")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Uždaryti") { dismiss() }
                    }
                }
            }
        }

        private func principle(_ title: String, _ text: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
