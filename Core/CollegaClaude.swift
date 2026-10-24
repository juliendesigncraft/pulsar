// Collegare e scollegare Pulsar dalle impostazioni di Claude Code (~/.claude/settings.json).
// Solo Foundation: tutta la logica prende un percorso e un dizionario, così si prova su file temporanei.
// Non sceglie mai da sola il file vero: lo fa chi chiama, al clic di chi usa Pulsar.
import Foundation

enum CollegaClaude {
    /// Errori leggibili, mostrati così nella pagina di Impostazioni.
    enum Errore: Error, LocalizedError {
        case formaInattesa(evento: String)
        case nonSerializzabile
        case troppiLink
        case fileCambiato
        case hookMancante
        var errorDescription: String? {
            switch self {
            case .formaInattesa(let e): return e == "hooks"
                ? "Nel file di Claude Code la voce \"hooks\" ha una forma inattesa: non la tocco."
                : "Nel file di Claude Code l'evento \"\(e)\" ha una forma inattesa: non lo tocco."
            case .troppiLink: return "Il file delle impostazioni è un link simbolico che gira in tondo o rimanda troppe volte."
            case .nonSerializzabile: return "Le impostazioni non si possono scrivere come JSON."
            case .fileCambiato: return "Il file di Claude Code è cambiato dopo l'anteprima: non ho scritto niente. Riapri per vedere cosa cambia ora."
            case .hookMancante: return "Non sono riuscito a mettere hook.py nella cartella di Pulsar: senza, Claude Code si fermerebbe a ogni prompt."
            }
        }
    }

    /// Gli eventi di Claude Code che Pulsar ascolta, nell'ordine di lettura. Stessi eventi e timeout di `agente/hooks-claude.json`
    /// più la voce delle domande (PreToolUse con matcher "AskUserQuestion", `--ask`, timeout 120: quella di `agente/collega-domande.py`).
    private struct Voce { let evento: String; let matcher: String?; let domande: Bool; let timeout: Int }
    private static let elenco: [Voce] = [
        Voce(evento: "UserPromptSubmit", matcher: nil, domande: false, timeout: 5),
        Voce(evento: "PreToolUse", matcher: nil, domande: false, timeout: 5),
        Voce(evento: "PreToolUse", matcher: "AskUserQuestion", domande: true, timeout: 120),
        Voce(evento: "PostToolUse", matcher: nil, domande: false, timeout: 5),
        Voce(evento: "PostToolUseFailure", matcher: nil, domande: false, timeout: 5),
        Voce(evento: "PermissionRequest", matcher: nil, domande: false, timeout: 40),
        Voce(evento: "Stop", matcher: nil, domande: false, timeout: 5),
        Voce(evento: "SessionEnd", matcher: nil, domande: false, timeout: 5),
    ]
    private static let ordineEventi = elenco.map(\.evento)

    /// Il comando dell'hook. Sotto la home si scrive con `$HOME`, come lo collega l'autore a mano; altrimenti percorso assoluto.
    static func comando(cartellaDati: URL, home: URL, domande: Bool) -> String {
        let script = relativo(cartellaDati, home: home).map { "$HOME/" + $0 + "/agente/hook.py" }
            ?? cartellaDati.path + "/agente/hook.py"
        return "/usr/bin/python3 \"" + script + "\"" + (domande ? " --ask" : "")
    }

    static func voci(cartellaDati: URL, home: URL) -> [String: [[String: Any]]] {
        var risultato: [String: [[String: Any]]] = [:]
        for v in elenco {
            var voce: [String: Any] = [:]
            if let m = v.matcher { voce["matcher"] = m }
            voce["hooks"] = [["type": "command", "command": comando(cartellaDati: cartellaDati, home: home, domande: v.domande), "timeout": v.timeout] as [String: Any]]
            risultato[v.evento, default: []].append(voce)
        }
        return risultato
    }

    /// Vero se tutte le voci di Pulsar ci sono (stesso evento, stesso matcher, un comando che porta all'hook di Pulsar).
    static func collegato(_ impostazioni: [String: Any], cartellaDati: URL, home: URL) -> Bool {
        let hooks = impostazioni["hooks"] as? [String: Any] ?? [:]
        return elenco.allSatisfy { v in
            ((hooks[v.evento] as? [[String: Any]]) ?? []).contains { esiste($0, matcher: v.matcher, cartellaDati: cartellaDati, home: home) }
        }
    }

    /// Aggiunge solo le voci mancanti, in fondo all'evento giusto; tutto il resto resta com'è.
    static func collega(_ impostazioni: [String: Any], cartellaDati: URL, home: URL) throws -> [String: Any] {
        try controlla(impostazioni, eventi: ordineEventi)
        var out = impostazioni
        var hooks = impostazioni["hooks"] as? [String: Any] ?? [:]
        let nuove = voci(cartellaDati: cartellaDati, home: home)
        for evento in Array(NSOrderedSet(array: ordineEventi)) as! [String] {
            var presenti = hooks[evento] as? [[String: Any]] ?? []
            for voce in nuove[evento] ?? [] {
                let m = voce["matcher"] as? String
                if !presenti.contains(where: { esiste($0, matcher: m, cartellaDati: cartellaDati, home: home) }) { presenti.append(voce) }
            }
            if !presenti.isEmpty { hooks[evento] = presenti }
        }
        out["hooks"] = hooks
        return out
    }

    /// Toglie solo i comandi che portano a `<cartella dati>/agente/hook.py`; le voci e gli eventi rimasti vuoti spariscono.
    static func scollega(_ impostazioni: [String: Any], cartellaDati: URL, home: URL) throws -> [String: Any] {
        try controlla(impostazioni, eventi: ordineEventi)   // gli altri eventi non sono di Pulsar: si saltano e restano invariati
        guard var hooks = impostazioni["hooks"] as? [String: Any] else { return impostazioni }
        var tolto = false
        for (evento, valore) in hooks {
            guard let voci = valore as? [[String: Any]] else { continue }
            var restano: [[String: Any]] = []
            for var voce in voci {
                guard let lista = voce["hooks"] as? [[String: Any]] else { restano.append(voce); continue }
                let tenuti = lista.filter { !riconosce($0["command"] as? String, cartellaDati: cartellaDati, home: home) }
                if tenuti.count == lista.count { restano.append(voce); continue }
                tolto = true
                if tenuti.isEmpty { continue }
                voce["hooks"] = tenuti
                restano.append(voce)
            }
            if restano.isEmpty { hooks[evento] = nil } else { hooks[evento] = restano }
        }
        var out = impostazioni
        if tolto && hooks.isEmpty { out["hooks"] = nil } else { out["hooks"] = hooks }
        return out
    }

    /// Righe leggibili di cosa cambia: "+ Evento: comando" per le voci aggiunte, "- Evento: comando" per quelle tolte.
    static func anteprima(prima: [String: Any], dopo: [String: Any]) -> [String] {
        let a = righe(prima), b = righe(dopo)
        var tolte = a
        var aggiunte: [String] = []
        for r in b {
            if let i = tolte.firstIndex(of: r) { tolte.remove(at: i) } else { aggiunte.append(r) }
        }
        return aggiunte.map { "+ " + $0 } + tolte.map { "- " + $0 }
    }

    /// File assente = nessuna impostazione. JSON illeggibile o che non è un oggetto = errore (non si sovrascrive mai).
    static func leggi(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let dati = try Data(contentsOf: url)
        guard let d = try JSONSerialization.jsonObject(with: dati) as? [String: Any] else {
            throw NSError(domain: "CollegaClaude", code: 1, userInfo: [NSLocalizedDescriptionKey: "Il file non è un oggetto JSON"])
        }
        return d
    }

    /// Copia datata accanto (solo se il file esiste), poi scrittura atomica. Indentazione di JSONSerialization, a capo finale.
    /// Se `url` è un link simbolico si scrive sul file vero (il link resta un link) e si rimettono i permessi di prima;
    /// la copia è del contenuto. Una copia già esistente non si cancella mai: si aggiunge -2, -3...
    /// Ritorna dove sta la copia (nil se non c'era un file da copiare).
    @discardableResult
    static func scrivi(_ d: [String: Any], in url: URL, copia: Bool) throws -> URL? {
        guard JSONSerialization.isValidJSONObject(d) else { throw Errore.nonSerializzabile }
        let fm = FileManager.default
        // segue i link anche se pendenti (la destinazione non esiste ancora): si scrive sempre sul file vero
        var vero = url
        for _ in 0..<16 {
            guard let d = try? fm.destinationOfSymbolicLink(atPath: vero.path) else { break }
            vero = d.hasPrefix("/") ? URL(fileURLWithPath: d) : vero.deletingLastPathComponent().appendingPathComponent(d)
        }
        if (try? fm.destinationOfSymbolicLink(atPath: vero.path)) != nil { throw Errore.troppiLink }   // ciclo o troppi salti: non si scrive niente
        vero = vero.resolvingSymlinksInPath()
        let esiste = fm.fileExists(atPath: vero.path)
        let permessi = (try? fm.attributesOfItem(atPath: vero.path))?[.posixPermissions]
        var copiata: URL?
        if copia && esiste {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let base = vero.path + ".prima-di-pulsar-" + f.string(from: Date())
            var dest = base, n = 2
            while fm.fileExists(atPath: dest) || (try? fm.destinationOfSymbolicLink(atPath: dest)) != nil { dest = base + "-\(n)"; n += 1 }
            try Data(contentsOf: vero).write(to: URL(fileURLWithPath: dest), options: .withoutOverwriting)
            if let permessi { try? fm.setAttributes([.posixPermissions: permessi], ofItemAtPath: dest) }
            copiata = URL(fileURLWithPath: dest)
        }
        try fm.createDirectory(at: vero.deletingLastPathComponent(), withIntermediateDirectories: true)
        var dati = try JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .withoutEscapingSlashes])
        dati.append(0x0A)
        try dati.write(to: vero, options: .atomic)
        if let permessi { try fm.setAttributes([.posixPermissions: permessi], ofItemAtPath: vero.path) }
        return copiata
    }

    // MARK: - Il foglio della pagina Claude Code (fase 3, compito 5)

    enum Azione { case collega, scollega }

    /// Cosa cambierebbe nel file: le righe da mostrare e le impostazioni da scrivere. Non scrive niente.
    struct Preparazione {
        let azione: Azione
        let righe: [String]
        let dopo: [String: Any]
    }

    /// Legge il file e calcola il collegamento o lo scollegamento, senza scrivere. Errori: file illeggibile, forma inattesa.
    static func prepara(_ a: Azione, url: URL, cartellaDati: URL, home: URL) throws -> Preparazione {
        let prima = try leggi(url)
        let dopo = a == .collega ? try collega(prima, cartellaDati: cartellaDati, home: home)
                                 : try scollega(prima, cartellaDati: cartellaDati, home: home)
        return Preparazione(azione: a, righe: anteprima(prima: prima, dopo: dopo), dopo: dopo)
    }

    /// Dopo "Conferma": rilegge il file e scrive solo se cambierebbe esattamente ciò che si è mostrato (altrimenti
    /// `fileCambiato` e niente scritto). Copia datata accanto: ritorna dove sta.
    /// Per collegare, PRIMA mette `hook` (l'hook.py del pacchetto) in `<cartellaDati>/agente/hook.py`: gli hook scritti
    /// puntano lì, e un file mancante fa uscire python3 con 2, che per Claude Code blocca ogni prompt. Se la copia
    /// non riesce, `hookMancante` e il file di Claude Code resta com'era. Per scollegare `hook` non serve.
    static func conferma(_ p: Preparazione, url: URL, cartellaDati: URL, home: URL, hook: URL?) throws -> URL? {
        let ora = try prepara(p.azione, url: url, cartellaDati: cartellaDati, home: home)
        guard ora.righe == p.righe, NSDictionary(dictionary: ora.dopo).isEqual(to: p.dopo) else { throw Errore.fileCambiato }
        if p.azione == .collega { try installaHook(da: hook, cartellaDati: cartellaDati) }
        return try scrivi(ora.dopo, in: url, copia: true)
    }

    /// Copia l'hook del pacchetto in `<cartellaDati>/agente/hook.py`, creando la cartella; se è già uguale non lo tocca.
    /// La usa anche AgentStore.start (prima era il suo installHook). Sorgente assente o illeggibile = `hookMancante`.
    static func installaHook(da sorgente: URL?, cartellaDati: URL) throws {
        do {
            guard let sorgente else { throw Errore.hookMancante }
            let nuovo = try Data(contentsOf: sorgente)
            let cartella = cartellaDati.appendingPathComponent("agente", isDirectory: true)
            try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
            let dst = cartella.appendingPathComponent("hook.py")
            if (try? Data(contentsOf: dst)) != nuovo { try nuovo.write(to: dst, options: .atomic) }
        } catch { throw Errore.hookMancante }
    }

    // MARK: - Dettagli

    /// Rifiuta le forme inattese: `hooks` che non è un oggetto, o un evento che non è un elenco di soli oggetti.
    /// Controlla solo gli `eventi` passati: gli altri sono di altri strumenti e non si toccano.
    private static func controlla(_ impostazioni: [String: Any], eventi: [String]) throws {
        guard let grezzo = impostazioni["hooks"] else { return }
        guard let hooks = grezzo as? [String: Any] else { throw Errore.formaInattesa(evento: "hooks") }
        for e in eventi {
            if let v = hooks[e], !(v is [[String: Any]]) { throw Errore.formaInattesa(evento: e) }
        }
    }

    private static func relativo(_ dati: URL, home: URL) -> String? {
        let h = home.path.hasSuffix("/") ? home.path : home.path + "/"
        return dati.path.hasPrefix(h) ? String(dati.path.dropFirst(h.count)) : nil
    }

    /// Il comando porta all'hook di Pulsar, scritto con `$HOME`, `${HOME}`, `~` o col percorso assoluto.
    private static func riconosce(_ comando: String?, cartellaDati: URL, home: URL) -> Bool {
        guard let c = comando else { return false }
        var chiavi = [cartellaDati.path + "/agente/hook.py"]
        if let r = relativo(cartellaDati, home: home) {
            for prefisso in ["$HOME/", "${HOME}/", "~/"] { chiavi.append(prefisso + r + "/agente/hook.py") }
        }
        // il percorso deve finire lì: seguito da virgolette (doppie o singole), spazio o fine stringa (non "hook.py.bak")
        return chiavi.contains { k in
            var da = c.startIndex
            while let r = c.range(of: k, range: da..<c.endIndex) {
                if r.upperBound == c.endIndex || c[r.upperBound] == "\"" || c[r.upperBound] == "'" || c[r.upperBound] == " " { return true }
                da = r.upperBound
            }
            return false
        }
    }

    private static func esiste(_ voce: [String: Any], matcher: String?, cartellaDati: URL, home: URL) -> Bool {
        let m = voce["matcher"] as? String
        // senza matcher, nil, "" e "*" valgono lo stesso (Claude Code li tratta come "tutti")
        if let matcher { guard m == matcher else { return false } } else { guard m == nil || m == "" || m == "*" else { return false } }
        return ((voce["hooks"] as? [[String: Any]]) ?? []).contains { riconosce($0["command"] as? String, cartellaDati: cartellaDati, home: home) }
    }

    private static func righe(_ impostazioni: [String: Any]) -> [String] {
        let hooks = impostazioni["hooks"] as? [String: Any] ?? [:]
        let eventi = hooks.keys.sorted { (ordineEventi.firstIndex(of: $0) ?? 99, $0) < (ordineEventi.firstIndex(of: $1) ?? 99, $1) }
        var out: [String] = []
        for e in eventi {
            for voce in (hooks[e] as? [[String: Any]]) ?? [] {
                let nome = (voce["matcher"] as? String).map { "\(e) (\($0))" } ?? e
                for h in (voce["hooks"] as? [[String: Any]]) ?? [] {
                    if let c = h["command"] as? String { out.append(nome + ": " + c) }
                }
            }
        }
        return out
    }
}
