import Foundation

/// Logica pura della prossima riunione (fase 4): quale link vale, quando mostrarla, quanto manca.
/// Solo Foundation, così si prova senza interfaccia.
enum Riunione {
    /// Primo link di riunione riconosciuto, scorrendo i testi nell'ordine dato (URL, luogo, note).
    static func link(in testi: [String?]) -> URL? {
        for testo in testi {
            guard let testo = testo else { continue }
            for candidato in url(in: testo) {
                if let u = URL(string: candidato), riconosciuto(u) { return u }
            }
        }
        return nil
    }

    /// Vera da 5 minuti prima dell'inizio fino a min(fine, inizio + 10 min), estremo finale escluso.
    static func visibile(inizio: Date, fine: Date, ora: Date) -> Bool {
        let da = inizio.addingTimeInterval(-5 * 60)
        let a = min(fine, inizio.addingTimeInterval(10 * 60))
        return ora >= da && ora < a
    }

    /// Quale evento tiene la fonte: tra quelli la cui finestra non è ancora chiusa (ora < min(fine, inizio + 10 min)),
    /// quello che inizia prima. Così un blocco lungo iniziato da un'ora non copre la riunione che arriva.
    /// Restituisce l'indice nell'elenco dato, nil se nessuno.
    static func scegli(_ eventi: [(inizio: Date, fine: Date)], ora: Date) -> Int? {
        var migliore: Int?
        for (i, e) in eventi.enumerated() where ora < min(e.fine, e.inizio.addingTimeInterval(10 * 60)) {
            if let m = migliore, eventi[m].inizio <= e.inizio { continue }
            migliore = i
        }
        return migliore
    }

    /// "tra 4 min" / "in 4 min" prima dell'inizio (minuti per eccesso, minimo 1), "ora" / "now" dopo.
    static func quantoManca(inizio: Date, ora: Date, inglese: Bool) -> String {
        let s = inizio.timeIntervalSince(ora)
        if s <= 0 { return inglese ? "now" : "ora" }
        let min = Swift.max(1, Int((s / 60).rounded(.up)))
        return (inglese ? "in " : "tra ") + "\(min) min"
    }

    // MARK: - interni

    private static let prefissi = ["https://", "zoommtg://"]

    /// Tutti i possibili URL di un testo libero, nell'ordine in cui compaiono.
    /// Gli indici restano quelli di `testo` (niente lowercased(): cambia la lunghezza di alcune lettere).
    private static func url(in testo: String) -> [String] {
        var trovati: [(String.Index, String)] = []
        for p in prefissi {
            var cerca = testo.startIndex..<testo.endIndex
            while let r = testo.range(of: p, options: .caseInsensitive, range: cerca) {
                // fine: primo spazio, angolare, virgolette o parentesi quadra
                var fine = testo.endIndex
                var i = r.lowerBound
                while i < testo.endIndex {
                    let c = testo[i]
                    if c.isWhitespace || "<>\"'`[]".contains(c) { fine = i; break }
                    i = testo.index(after: i)
                }
                var s = String(testo[r.lowerBound..<fine])
                // si toglie solo la punteggiatura di chiusura in fondo al link
                while let u = s.last, ".,;:!?)(}".contains(u) { s.removeLast() }
                if s.count > p.count { trovati.append((r.lowerBound, s)) }
                if fine >= testo.endIndex { break }
                cerca = fine..<testo.endIndex
            }
        }
        return trovati.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func riconosciuto(_ u: URL) -> Bool {
        let schema = (u.scheme ?? "").lowercased()
        if schema == "zoommtg" { return true }
        guard schema == "https" else { return false }
        let host = (u.host ?? "").lowercased()
        let percorso = u.path.lowercased()
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return percorso.hasPrefix("/j/") || percorso.hasPrefix("/my/")
        }
        if host == "meet.google.com" { return percorso.count > 1 }
        if host == "teams.microsoft.com" { return percorso.hasPrefix("/l/meetup-join/") }
        if host == "teams.live.com" { return percorso.hasPrefix("/meet/") }
        return false
    }
}
