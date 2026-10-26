// I Lanciatori, la lista (24/10/2026, nella Lite): cartelle di siti da aprire con un clic. Solo Foundation: si prova in prove/main.swift.
// Qui stanno i dati e le mosse della pagina Lanciatori delle Impostazioni (aggiungere, togliere, riordinare, spostare di cartella).
// Le mosse sono pure: prendono la lista e ne danno una nuova, così la pagina, i comandi pulsar:// e le prove usano lo stesso codice.
import Foundation

struct VoceLanciatore: Identifiable, Codable, Equatable {
    var id: String { app.map { "app:" + $0 } ?? u }
    let n: String; let u: String
    /// Un'app da aprire per id invece di un sito: la mette solo una fonte che sa aprirla (FonteLanciatori.apri).
    var app: String? = nil
    /// 25/10: la categoria dentro la cartella (Azione, Libri...): la griglia la mostra come titoletto. Facoltativa.
    var cat: String? = nil
    /// 25/10: l'immagine dell'icona quando il sito non ne ha una (i giochi di Steam: la copertina da Steam). Facoltativa.
    var icona: String? = nil
}

struct CartellaLanciatori: Identifiable, Codable, Equatable {
    let id: String
    /// Il nome scritto da chi l'ha creata. Le liste di prima non l'hanno: si mostra l'id con la maiuscola.
    var nome: String? = nil
    var voci: [VoceLanciatore]
    var titolo: String { nome ?? (id.prefix(1).uppercased() + id.dropFirst()) }
}

enum ListaLanciatori {
    typealias Cartella = CartellaLanciatori
    typealias Voce = VoceLanciatore

    enum Errore: Error, Equatable { case linkNonValido, giaPresente, cartellaMancante }

    /// I siti del primo avvio: siti pubblici e gratuiti, in inglese come il resto del materiale di vendita.
    static let esempi: [Cartella] = [
        Cartella(id: "play", nome: "Play", voci: [Voce(n: "Lichess", u: "https://lichess.org"),
                                                  Voce(n: "Chrome Dino", u: "https://chromedino.com"),
                                                  Voce(n: "2048", u: "https://play2048.co")]),
        Cartella(id: "learn", nome: "Learn", voci: [Voce(n: "Wikipedia", u: "https://en.wikipedia.org"),
                                                    Voce(n: "Khan Academy", u: "https://www.khanacademy.org"),
                                                    Voce(n: "MDN Web Docs", u: "https://developer.mozilla.org")]),
        Cartella(id: "tools", nome: "Tools", voci: [Voce(n: "Excalidraw", u: "https://excalidraw.com"),
                                                    Voce(n: "Squoosh", u: "https://squoosh.app")]),
        // 26/10: le app vanno nel riquadro sul desktop, i siti nella barra accanto al Dock (come nel reel di Pulsar)
        Cartella(id: "apps", nome: "Apps", voci: [Voce(n: "Notes", u: "file:///System/Applications/Notes.app/"),
                                                  Voce(n: "Calendar", u: "file:///System/Applications/Calendar.app/"),
                                                  Voce(n: "Music", u: "file:///System/Applications/Music.app/"),
                                                  Voce(n: "Photos", u: "file:///System/Applications/Photos.app/")]),
        Cartella(id: "design", nome: "Design", voci: [Voce(n: "Preview", u: "file:///System/Applications/Preview.app/"),
                                                      Voce(n: "Freeform", u: "file:///System/Applications/Freeform.app/")]),
    ]

    /// Gli schemi che non si accettano mai come link: file:// (le app si aggiungono col tasto apposta), ftp, script e dati.
    static let schemiVietati: Set<String> = ["file", "ftp", "javascript", "data", "about"]

    /// Pura: il link come va salvato, o nil. Senza schema si aggiunge https:// ("lichess.org" va bene);
    /// http e https vogliono un host che abbia un punto. 26/10: valgono anche i link delle app (steam://rungameid/105600,
    /// spotify:..., obsidian://...), così chi compra può mettere i suoi giochi come nel reel. Mai spazi.
    static func normalizza(_ testo: String) -> String? {
        var s = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            if let r = s.range(of: "://") {
                let schema = s[..<r.lowerBound].lowercased()
                guard !schema.isEmpty, schema.first!.isLetter, schema.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }),
                      !schemiVietati.contains(schema), s[r.upperBound...].count > 0 else { return nil }
                return s
            }
            s = "https://" + s
        }
        guard let u = URL(string: s), let h = u.host, h.contains("."), !h.hasPrefix("."), !h.hasSuffix(".") else { return nil }
        return s
    }

    /// Pura: la copertina di un gioco di Steam (steam://rungameid/ID o store.steampowered.com/app/ID), come nello stash del reel.
    static func copertinaSteam(_ link: String) -> String? {
        let l = link.lowercased()
        var id: Substring?
        if let r = l.range(of: "steam://rungameid/") { id = l[r.upperBound...].prefix { $0.isNumber } }
        else if let r = l.range(of: "store.steampowered.com/app/") { id = l[r.upperBound...].prefix { $0.isNumber } }
        guard let id, !id.isEmpty else { return nil }
        return "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/library_600x900.jpg"
    }

    /// Pura: un'app del Mac scelta col tasto "Aggiungi app" (percorso del .app) diventa una voce file://; nome = nome dell'app.
    static func aggiungiApp(_ cs: [Cartella], percorso: String, in cartella: String) -> Result<[Cartella], Errore> {
        guard percorso.hasSuffix(".app") else { return .failure(.linkNonValido) }
        guard let i = cs.firstIndex(where: { $0.id == cartella }) else { return .failure(.cartellaMancante) }
        let u = URL(fileURLWithPath: percorso).absoluteString
        guard !cs[i].voci.contains(where: { $0.u == u }) else { return .failure(.giaPresente) }
        let n = ((percorso as NSString).lastPathComponent as NSString).deletingPathExtension
        var r = cs
        r[i].voci.append(Voce(n: n, u: u))
        return .success(r)
    }

    /// Pura: il nome di riserva quando non se ne scrive uno: l'host senza "www.".
    static func nomeDa(_ link: String) -> String {
        let h = URL(string: link)?.host ?? link
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Pura: un id nuovo dal nome ("My Games" → "my-games"), diverso da quelli che ci sono già.
    static func nuovoId(_ nome: String, in cs: [Cartella]) -> String {
        let base = nome.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let radice = base.isEmpty ? "folder" : base
        var id = radice, n = 2
        while cs.contains(where: { $0.id == id }) { id = "\(radice)-\(n)"; n += 1 }
        return id
    }

    /// Aggiunge in fondo alla cartella `in`. Lo stesso link due volte nella stessa cartella no (le righe si distinguono per link).
    static func aggiungi(_ cs: [Cartella], nome: String, link: String, in cartella: String) -> Result<[Cartella], Errore> {
        guard let u = normalizza(link) else { return .failure(.linkNonValido) }
        guard let i = cs.firstIndex(where: { $0.id == cartella }) else { return .failure(.cartellaMancante) }
        guard !cs[i].voci.contains(where: { $0.app == nil && $0.u == u }) else { return .failure(.giaPresente) }
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        var r = cs
        r[i].voci.append(Voce(n: n.isEmpty ? nomeDa(u) : n, u: u, icona: copertinaSteam(u)))
        return .success(r)
    }

    static func togli(_ cs: [Cartella], cartella: String, indice: Int) -> [Cartella] {
        guard let i = cs.firstIndex(where: { $0.id == cartella }), cs[i].voci.indices.contains(indice) else { return cs }
        var r = cs
        r[i].voci.remove(at: indice)
        return r
    }

    /// Sposta la voce `da` al posto `a` nella stessa cartella (le altre scorrono).
    static func sposta(_ cs: [Cartella], cartella: String, da: Int, a: Int) -> [Cartella] {
        guard let i = cs.firstIndex(where: { $0.id == cartella }), cs[i].voci.indices.contains(da), cs[i].voci.indices.contains(a), da != a
        else { return cs }
        var r = cs
        let v = r[i].voci.remove(at: da)
        r[i].voci.insert(v, at: a)
        return r
    }

    /// Porta la voce in fondo a un'altra cartella. Se là c'è già lo stesso link, resta dov'è.
    static func spostaIn(_ cs: [Cartella], da cartella: String, indice: Int, a destinazione: String) -> [Cartella] {
        guard cartella != destinazione,
              let i = cs.firstIndex(where: { $0.id == cartella }), let j = cs.firstIndex(where: { $0.id == destinazione }),
              cs[i].voci.indices.contains(indice) else { return cs }
        let v = cs[i].voci[indice]
        guard !cs[j].voci.contains(where: { $0.id == v.id }) else { return cs }
        var r = cs
        r[i].voci.remove(at: indice)
        r[j].voci.append(v)
        return r
    }

    /// Una cartella vuota in fondo. Nome vuoto: niente.
    static func nuovaCartella(_ cs: [Cartella], nome: String) -> (lista: [Cartella], id: String?) {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return (cs, nil) }
        let id = nuovoId(n, in: cs)
        return (cs + [Cartella(id: id, nome: n, voci: [])], id)
    }

    /// Si toglie solo una cartella vuota: i siti non spariscono mai insieme alla cartella.
    static func togliCartella(_ cs: [Cartella], id: String) -> [Cartella] {
        cs.filter { $0.id != id || !$0.voci.isEmpty }
    }

    /// La lista salvata, o gli esempi se il file non c'è ancora. Un file rotto dà nil: chi legge non lo sovrascrive.
    static func leggi(_ file: URL) -> [Cartella]? {
        guard let d = try? Data(contentsOf: file) else { return esempi }
        return try? JSONDecoder().decode([Cartella].self, from: d)
    }

    static func scrivi(_ cs: [Cartella], in file: URL) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let d = try? e.encode(cs) { try? d.write(to: file, options: .atomic) }
    }
}
