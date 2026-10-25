// Muta, riordino: la logica pura. Decide dove va un file sciolto della Scrivania o di Download, quando è pronto,
// come si dice all'utente e come si annulla. Solo Foundation: si prova in prove/convertitore.
// Chi guarda le cartelle e sposta è riordino.swift. Disegno in docs/2026-10-19-muta-riordino.md.
// Le regole dell'autore stanno in Personale/muta-autore.swift, mai qui: la vendita parte da regolePredefinite.
import Foundation

enum Destinazione: Equatable {
    case cartella(URL)
    case cestino
}

struct Regola: Equatable {
    var nome: String
    /// Estensioni senza punto, minuscole. Vuoto = qualsiasi.
    var estensioni: Set<String> = []
    /// Basta una parola nel nome, senza badare a maiuscole e accenti. Vuoto = qualsiasi.
    var parole: [String] = []
    var destinazione: Destinazione
    /// Attesa propria (per esempio gli screenshot: 2 giorni). nil = quella generale.
    var attesa: TimeInterval? = nil
}

struct Spostamento: Equatable {
    var da: URL
    /// nil se il file è andato nel Cestino (la posizione la sceglie macOS e la restituisce chi sposta).
    var a: URL?
    var regola: String
}

enum Riordino {
    /// I download a metà e i file di sistema che non si toccano mai.
    static let inCorso: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "icloud"]
    static let ignorati: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    /// La prima regola che combacia, nell'ordine dato.
    static func regola(per nome: String, tra regole: [Regola]) -> Regola? {
        let ext = (nome as NSString).pathExtension.lowercased()
        let base = (nome as NSString).deletingPathExtension
        return regole.first { r in
            (r.estensioni.isEmpty || r.estensioni.contains(ext)) &&
            (r.parole.isEmpty || r.parole.contains { base.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
        }
    }

    /// Un file si può spostare? Mai cartelle, pacchetti, alias, nascosti o download in corso;
    /// solo se non sta cambiando e se è fermo da almeno `attesa` secondi.
    static func pronto(nome: String, cartella: Bool, modificato: Date, ora: Date, attesa: TimeInterval, staCambiando: Bool) -> Bool {
        if cartella || staCambiando { return false }
        if nome.hasPrefix(".") || ignorati.contains(nome) { return false }
        if inCorso.contains((nome as NSString).pathExtension.lowercased()) { return false }
        return ora.timeIntervalSince(modificato) >= attesa
    }

    /// Dove va il file, o nil se resta dov'è. Una regola che porta nella stessa cartella è come nessuna regola.
    static func piano(per file: URL, regole: [Regola]) -> (Regola, Destinazione)? {
        guard let r = regola(per: file.lastPathComponent, tra: regole) else { return nil }
        if case .cartella(let c) = r.destinazione, c.standardizedFileURL.path == file.deletingLastPathComponent().standardizedFileURL.path { return nil }
        return (r, r.destinazione)
    }

    /// Il nome di una cartella per le persone: "Design › Mockups", senza la casa e senza "Desktop" davanti.
    static func etichetta(_ d: Destinazione, home: URL) -> String {
        guard case .cartella(let c) = d else { return T("nel Cestino", "in the Trash") }
        var parti = c.standardizedFileURL.pathComponents
        let casa = home.standardizedFileURL.pathComponents
        if parti.starts(with: casa) { parti.removeFirst(casa.count) } else { parti = Array(parti.suffix(2)) }
        if parti.first == "Desktop", parti.count > 1 { parti.removeFirst() }
        return parti.joined(separator: " › ")
    }

    /// "3 file a posto: 2 in Design › Mockups, 1 in Books" ("3 files put away: ..."). Le cartelle in ordine di quanti file, poi di nome.
    /// Il ": " separa titolo e dettaglio dell'avviso nel notch (MutaCentro.dividi): resta in tutte e due le lingue.
    static func resoconto(_ spostati: [Destinazione], home: URL) -> String {
        guard !spostati.isEmpty else { return T("Niente da mettere a posto", "Nothing to put away") }
        let cestino = etichetta(.cestino, home: home)
        var conta: [String: Int] = [:]
        for d in spostati { conta[etichetta(d, home: home), default: 0] += 1 }
        let parti = conta.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { $0.key == cestino ? "\($0.value) \(cestino)" : "\($0.value) in \($0.key)" }
        let n = spostati.count
        return T("\(n) file a posto: ", n == 1 ? "1 file put away: " : "\(n) files put away: ") + parti.joined(separator: ", ")
    }

    /// Annulla: ogni file torna da dove era venuto, in ordine inverso. Se nel frattempo il posto è preso,
    /// arriva " 2" come al solito. Chi è nel Cestino ha `a` = posizione nel Cestino data da chi ha spostato.
    static func annulla(_ fatti: [Spostamento], esiste: @escaping (URL) -> Bool) -> [(da: URL, a: URL)] {
        var presi: Set<URL> = []
        let preso: (URL) -> Bool = { esiste($0) || presi.contains($0) }
        return fatti.reversed().compactMap { s in
            guard let dove = s.a else { return nil }
            let meta = preso(s.da) ? Convertitore.uscita(per: s.da, estensione: s.da.pathExtension, esiste: preso) : s.da
            presi.insert(meta)
            return (da: dove, a: meta)
        }
    }

    /// Le regole con cui parte la versione in vendita: le cartelle standard di macOS, che ogni Mac ha.
    static func regolePredefinite(home: URL) -> [Regola] {
        [
            Regola(nome: "Immagini", estensioni: ["jpg", "jpeg", "png", "heic", "webp", "avif", "gif", "tiff", "tif", "svg"],
                   destinazione: .cartella(home.appendingPathComponent("Pictures"))),
            Regola(nome: "Video", estensioni: ["mp4", "mov", "m4v", "webm", "mkv"], destinazione: .cartella(home.appendingPathComponent("Movies"))),
            Regola(nome: "Audio", estensioni: ["mp3", "m4a", "wav", "aiff", "flac", "ogg"], destinazione: .cartella(home.appendingPathComponent("Music"))),
            Regola(nome: "Documenti", estensioni: ["pdf", "docx", "doc", "rtf", "txt", "pages", "key", "numbers", "xlsx", "pptx", "odt", "md"],
                   destinazione: .cartella(home.appendingPathComponent("Documents"))),
        ]
    }
}
