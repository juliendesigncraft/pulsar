// Chi usa Pulsar e come salutarlo. Logica pura (solo Foundation): si prova in prove/main.swift.
// Nella build dell'autore il nome è fisso ("l'autore"); nella vendita è il primo nome dell'utente del Mac.
import Foundation

enum Persona {
    /// La prima parola del nome completo, nil se è vuoto o fatto solo di spazi.
    static func primoNome(_ completo: String) -> String? {
        completo.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }


    static var nome: String? {
        return primoNome(NSFullUserName())
    }
}

enum Saluto {
    /// "Ciao l'autore" / "Hi l'autore"; senza nome solo "Ciao" / "Hi".
    static func ciao(_ nome: String?, inglese: Bool) -> String {
        let base = inglese ? "Hi" : "Ciao"
        guard let nome else { return base }
        return "\(base) \(nome)"
    }

    /// Il saluto secondo l'ora (soglie 5, 13, 18): "Buongiorno, l'autore"; senza nome senza virgola.
    static func ora(_ h: Int, _ nome: String?, inglese: Bool) -> String {
        let base: String
        if h < 5 { base = inglese ? "Late night" : "Notte fonda" }
        else if h < 13 { base = inglese ? "Good morning" : "Buongiorno" }
        else if h < 18 { base = inglese ? "Good afternoon" : "Buon pomeriggio" }
        else { base = inglese ? "Good evening" : "Buonasera" }
        guard let nome else { return base }
        return "\(base), \(nome)"
    }
}

enum App {
    /// L'identificatore del pacchetto: local.author.pulsar nella build dell'autore, com.juliendesigncraft.pulsar nella vendita.
    static var id: String { Bundle.main.bundleIdentifier ?? "com.juliendesigncraft.pulsar" }
}
