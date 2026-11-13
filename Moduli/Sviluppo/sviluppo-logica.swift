// La barra di sviluppo (07/11/2026, dal reel di ZincWolf MenuBar): la parte pura, senza AppKit, provata in prove/sviluppo.
// Tre letture: i server accesi per porta (da `lsof`), il branch Git di un progetto (da `git status`) e quanto resta
// del limite di Claude (dalla risposta di api.anthropic.com/api/oauth/usage, la stessa che legge /usage di Claude Code).
import Foundation

/// Un server in ascolto sul Mac.
struct ServerAcceso: Equatable {
    let porta: Int
    let pid: Int32
    let comando: String      // il nome breve che dà lsof (python3, node, ruby…)
    var cartella: String = ""   // da dove è partito (cwd), la si legge dopo
}

enum LetturaServer {
    /// I programmi che ascoltano su una porta ma non sono server di sviluppo: AirPlay, condivisione, demoni di macOS e app.
    /// Confronto in minuscolo sull'inizio del nome (lsof lo tronca a 9 lettere). Ollama ha il suo server ma non è un sito.
    static let nonSviluppo: [String] = ["controlce", "rapportd", "sharingd", "identitys", "launchd", "mdnsrespo",
                                        "wifiagent", "spotify", "dropbox", "figma", "adobe", "onedrive",
                                        "pulsar", "rowline", "code\\x20h", "cursor", "raycast", "steam_osx", "ollama"]

    /// Pura: dalle righe di `lsof -nP -iTCP -sTCP:LISTEN -F pcn` ai server, una riga per porta (IPv4 e IPv6 insieme).
    /// Il formato -F dà un campo per riga: `p<pid>`, `c<comando>`, `n<indirizzo:porta>`.
    static func leggi(_ testo: String) -> [ServerAcceso] {
        var pid: Int32 = 0, cmd = ""
        var visti = Set<Int>(), out: [ServerAcceso] = []
        for riga in testo.split(separator: "\n") {
            guard let k = riga.first else { continue }
            let v = String(riga.dropFirst())
            switch k {
            case "p": pid = Int32(v) ?? 0
            case "c": cmd = v
            case "n":
                guard let due = v.lastIndex(of: ":"), let porta = Int(v[v.index(after: due)...]) else { continue }
                guard eSviluppo(porta: porta, comando: cmd), !visti.contains(porta) else { continue }
                visti.insert(porta)
                out.append(ServerAcceso(porta: porta, pid: pid, comando: cmd))
            default: break
            }
        }
        return out.sorted { $0.porta < $1.porta }
    }

    /// Pura: un server di sviluppo è un programma non di sistema su una porta da sviluppo (1024-49151).
    /// Sopra la 49152 macOS dà porte a caso ai programmi (sono effimere): lì non c'è mai un sito da aprire.
    static func eSviluppo(porta: Int, comando: String) -> Bool {
        guard (1024...49151).contains(porta) else { return false }
        let c = comando.lowercased()
        return !nonSviluppo.contains(where: { c.hasPrefix($0) })
    }

    /// Pura: dalla cartella di partenza un nome da riga ("vault_os" in Vault → "Vault"); vuota resta vuota.
    static func nomeCartella(_ percorso: String) -> String {
        let p = percorso.hasSuffix("/") ? String(percorso.dropLast()) : percorso
        return p.split(separator: "/").last.map(String.init) ?? ""
    }
}

/// Lo stato Git di un progetto.
struct StatoGit: Equatable {
    var branch: String
    var modificati: Int = 0
    var avanti: Int = 0
    var indietro: Int = 0
}

enum LetturaGit {
    /// Pura: dalla prima riga e dalle altre di `git status --porcelain=v1 -b`.
    /// Prima riga: `## main...origin/main [ahead 2, behind 1]`, oppure `## HEAD (no branch)`, oppure `## No commits yet on main`.
    static func leggi(_ testo: String) -> StatoGit? {
        let righe = testo.split(separator: "\n", omittingEmptySubsequences: true)
        guard let prima = righe.first, prima.hasPrefix("## ") else { return nil }
        var t = String(prima.dropFirst(3))
        if t.hasPrefix("No commits yet on ") { t = String(t.dropFirst("No commits yet on ".count)) }
        var s = StatoGit(branch: t)
        if let r = t.range(of: "...") { s.branch = String(t[..<r.lowerBound]) }
        else if let sp = t.firstIndex(of: " ") { s.branch = String(t[..<sp]) }
        if t.hasPrefix("HEAD (no branch)") { s.branch = "HEAD" }
        if let a = t.range(of: "ahead ") { s.avanti = Int(t[a.upperBound...].prefix { $0.isNumber }) ?? 0 }
        if let b = t.range(of: "behind ") { s.indietro = Int(t[b.upperBound...].prefix { $0.isNumber }) ?? 0 }
        s.modificati = righe.count - 1
        return s
    }
}

/// Quanto resta del limite di Claude: le due finestre che mostra /usage di Claude Code.
struct LimiteClaude: Equatable {
    struct Finestra: Equatable { let usato: Double; let azzera: Date? }   // usato in percento, 0...100
    var cinqueOre: Finestra?
    var settimana: Finestra?
    var settimanaOpus: Finestra?

    /// Il numero da mettere nella barra: quanto resta nella finestra più vicina al tetto.
    var restaNellaBarra: Int? {
        let peggiore = [cinqueOre, settimana].compactMap { $0?.usato }.max()
        return peggiore.map { max(0, min(100, Int((100 - $0).rounded()))) }
    }
}

enum LetturaLimite {
    /// Pura: la risposta di /api/oauth/usage. Ogni finestra ha `utilization` (0-100) e `resets_at` (ISO 8601), o è null.
    static func leggi(_ dati: Data) -> LimiteClaude? {
        guard let o = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] else { return nil }
        func f(_ k: String) -> LimiteClaude.Finestra? {
            guard let w = o[k] as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return .init(usato: u, azzera: (w["resets_at"] as? String).flatMap(data))
        }
        let l = LimiteClaude(cinqueOre: f("five_hour"), settimana: f("seven_day"), settimanaOpus: f("seven_day_opus"))
        return l.cinqueOre == nil && l.settimana == nil ? nil : l
    }

    /// Pura: il token di Claude Code salvato nel Portachiavi (JSON con claudeAiOauth.accessToken e expiresAt in ms).
    /// Nil se manca o se è scaduto: Pulsar non lo rinnova mai da sé, lo fa Claude Code al prossimo avvio.
    static func token(_ dati: Data, adesso: Date = Date()) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let c = o["claudeAiOauth"] as? [String: Any], let t = c["accessToken"] as? String, !t.isEmpty else { return nil }
        if let ms = (c["expiresAt"] as? NSNumber)?.doubleValue, Date(timeIntervalSince1970: ms / 1000) <= adesso { return nil }
        return t
    }

    /// Pura: "tra 2 h 10 min", "tra 3 g".
    static func tra(_ d: Date, adesso: Date = Date(), it: Bool) -> String {
        let s = max(0, Int(d.timeIntervalSince(adesso)))
        let g = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        let pre = it ? "tra " : "in "
        if g > 0 { return pre + (it ? "\(g) g \(h) h" : "\(g)d \(h)h") }
        if h > 0 { return pre + (it ? "\(h) h \(m) min" : "\(h)h \(m)m") }
        return pre + (it ? "\(m) min" : "\(m)m")
    }

    private static func data(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
