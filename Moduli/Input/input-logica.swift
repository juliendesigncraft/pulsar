// Mouse e tastiera, la parte pura (13/11/2026, ondata 4 di VORSSAINT.md). Solo Foundation (più DitoTrackpad, anche lui
// puro): si prova in prove/main.swift.
import Foundation

/// Le scorciatoie di testo: scrivi ";mail" e diventa l'indirizzo intero.
struct Snippet: Codable, Equatable, Identifiable {
    var id = UUID()
    var sigla: String
    var testo: String

    static let esempi = [Snippet(sigla: ";ciao", testo: "Ciao, grazie del messaggio!"),
                         Snippet(sigla: ";data", testo: "{data}")]

    /// La sigla più lunga con cui finisce quello che si è appena scritto (nil = nessuna).
    static func trova(_ scritto: String, in lista: [Snippet]) -> Snippet? {
        lista.filter { !$0.sigla.isEmpty && scritto.hasSuffix($0.sigla) }.max { $0.sigla.count < $1.sigla.count }
    }

    /// Il testo da scrivere, coi segnaposto: {data} = oggi (13/11/2026), {ora} = adesso (14:05).
    static func espandi(_ testo: String, adesso: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy"; let d = f.string(from: adesso)
        f.dateFormat = "HH:mm"; let o = f.string(from: adesso)
        return testo.replacingOccurrences(of: "{data}", with: d).replacingOccurrences(of: "{ora}", with: o)
    }

    static func leggi(_ dati: Data?) -> [Snippet]? { dati.flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } }
}

/// Tasti che rimbalzano: un tasto che torna giù troppo presto dopo essere salito è un doppio colpo sbagliato.
enum Rimbalzo {
    /// true = da ignorare. `su` = quando ogni tasto è stato rilasciato l'ultima volta (secondi), `soglia` in secondi.
    static func ignora(tasto: Int64, ora: Double, su: [Int64: Double], soglia: Double) -> Bool {
        guard let s = su[tasto] else { return false }
        return ora - s < soglia
    }
}

/// Un tocco con tre dita (giù e su in fretta, quasi senza muoversi) diventa il clic centrale.
struct ToccoTreDita {
    private var inizio: Double?
    private var partenza: [DitoTrackpad] = []
    private var massimo = 0
    private var mosso = false
    static let durata = 0.28
    static let spostamento: Float = 0.035

    /// Un fotogramma del trackpad. Ritorna true quando un tocco a tre dita si è appena concluso.
    mutating func fotogramma(_ dita: [DitoTrackpad], t: Double) -> Bool {
        if dita.isEmpty {
            defer { inizio = nil; partenza = []; massimo = 0; mosso = false }
            guard let i = inizio else { return false }
            return massimo == 3 && !mosso && t - i <= Self.durata
        }
        if inizio == nil { inizio = t; partenza = dita }
        massimo = max(massimo, dita.count)
        if dita.count == 3 && partenza.count < 3 { partenza = dita }      // le dita arrivano quasi insieme: si prende la terza
        if dita.count == partenza.count {
            for (a, b) in zip(dita, partenza) where abs(a.x - b.x) > Self.spostamento || abs(a.y - b.y) > Self.spostamento { mosso = true }
        }
        return false
    }
}
