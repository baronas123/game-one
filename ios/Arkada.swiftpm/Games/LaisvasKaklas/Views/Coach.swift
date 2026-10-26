import AVFoundation

extension LaisvasKaklas {

    /// Balso užuominos. Kalba tik jei telefone yra lietuviškas balsas (lt-LT); kitaip tyli.
    final class Coach {
        private let synthesizer = AVSpeechSynthesizer()
        private let voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "lt-LT")

        var isAvailable: Bool { voice != nil }

        func say(_ text: String) {
            guard let voice, !text.isEmpty else { return }
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .word)
            }
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
            synthesizer.speak(u)
        }

        func stop() {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
