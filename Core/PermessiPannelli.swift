// Parte pura dei permessi di macOS: solo Foundation, così si prova senza l'app.
import Foundation

enum StatoPermesso { case concesso, negato, daChiedere }

enum Permessi {
    /// L'indirizzo del pannello di Impostazioni di Sistema, Privacy e sicurezza, dove si concede il permesso.
    static func pannello(_ p: Permesso) -> String {
        let nome: String
        switch p {
        case .accessibilita: nome = "Accessibility"
        case .automazione: nome = "Automation"
        case .registrazioneSchermo: nome = "ScreenCapture"
        case .microfono: nome = "Microphone"
        case .riconoscimentoVocale: nome = "SpeechRecognition"
        case .calendario: nome = "Calendars"
        }
        return "x-apple.systempreferences:com.apple.preference.security?Privacy_" + nome
    }
}

/// Cosa offre la riga di un permesso: niente (concesso), la richiesta di macOS, o il pannello di Impostazioni di Sistema.
enum AzionePermesso: Equatable { case nessuna, chiedi, apriPannello }

extension Permessi {
    /// La chiave che ricorda che la richiesta di macOS è già stata mostrata. Solo Accessibilità e Registrazione schermo:
    /// per loro macOS mostra la richiesta una volta sola e `stato` non dà mai `.negato`, quindi dopo il primo rifiuto
    /// "Concedi" non farebbe più niente. Gli altri permessi hanno uno stato "negato" vero.
    static func chiaveChiesto(_ p: Permesso) -> Chiave? {
        switch p {
        case .accessibilita: return .askedAccessibility
        case .registrazioneSchermo: return .askedScreenRecording
        default: return nil
        }
    }

    static func giaChiesto(_ p: Permesso) -> Bool { chiaveChiesto(p).map(Impostazioni.bool) ?? false }

    /// Da segnare appena si mostra la richiesta di macOS.
    static func segnaChiesto(_ p: Permesso) { if let k = chiaveChiesto(p) { Impostazioni.set(true, k) } }

    /// Negato, o da chiedere ma già chiesto una volta (solo dove macOS non ripete la richiesta): si apre il pannello.
    static func azione(_ p: Permesso, stato: StatoPermesso, giaChiesto: Bool) -> AzionePermesso {
        switch stato {
        case .concesso: return .nessuna
        case .negato: return .apriPannello
        case .daChiedere: return giaChiesto && chiaveChiesto(p) != nil ? .apriPannello : .chiedi
        }
    }
}
