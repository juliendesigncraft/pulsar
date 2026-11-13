// Promesse (01/11/2026, dal post di Kier di Mario Jankovic: "Remember every promise").
// Pulsar legge WhatsApp e Mail sul Mac, il modello locale trova cosa hai promesso o cosa ti hanno chiesto,
// il notch te lo ricorda quando scade e si accorge da solo quando l'hai fatto. Niente esce dal Mac.
// Qui solo la logica pura (date, filtri, ordine): la provano `prove/promesse.swift`, senza AppKit.
import Foundation

/// Un messaggio letto da una fonte. Vive solo in memoria, non si salva mai.
struct PMessaggio: Equatable {
    var id: String          // fonte + chiave del messaggio nella fonte
    var fonte: String       // "WhatsApp" o "Mail"
    var chatID: String      // la chat di WhatsApp, o il filo della mail (oggetto senza Re: + indirizzo)
    var chat: String        // il nome che si mostra: "Marta", "Tipografia Rossi"
    var daMe: Bool
    var testo: String
    var data: Date
    var allegato = false    // foto, video o documento mandato nella chat
}

/// Una promessa: tua ("te lo mando venerdì") o chiesta a te ("puoi mandarmelo entro venerdì?").
struct Promessa: Codable, Identifiable, Equatable {
    var id: String          // l'id del messaggio da cui nasce: la stessa frase non diventa due promesse
    var titolo: String      // l'azione, corta: "Mandare i file del logo"
    var chi: String
    var fonte: String
    var chatID: String
    var citazione: String   // la frase vera, tagliata a 160 caratteri
    var mia: Bool           // vero se l'hai detta tu
    var detta: Date
    var scadenza: Date?
    var rimandata: Date?    // tasto Domani: fino a quel momento non suona
    var fatta: Date?
    var perche: String?     // "Hai risposto nella chat", "Segnata a mano"

    var aperta: Bool { fatta == nil }
}

enum PromesseLogica {
    static let oraAvviso = 9        // una promessa con scadenza "venerdì" suona venerdì alle 9

    // MARK: scadenze

    private static let giorni: [(parole: [String], wd: Int)] = [   // weekday di Calendar: 1 = domenica
        (["domenica", "sunday", "sun"], 1), (["lunedì", "lunedi", "monday", "mon"], 2), (["martedì", "martedi", "tuesday", "tue"], 3),
        (["mercoledì", "mercoledi", "wednesday", "wed"], 4), (["giovedì", "giovedi", "thursday", "thu"], 5),
        (["venerdì", "venerdi", "friday", "fri"], 6), (["sabato", "saturday", "sat"], 7),
    ]

    /// La scadenza scritta nella frase, letta senza modello: oggi, stasera, domani, un giorno della settimana,
    /// "entro il 14", "by the 14th", la settimana prossima. Nil se la frase non dice quando.
    static func scadenza(_ testo: String, da: Date, cal: Calendar = .current) -> Date? {
        let t = " " + testo.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression) + " "
        func ha(_ ps: [String]) -> Bool { ps.contains { t.contains(" \($0) ") } }
        func giorno(_ d: Date, ora: Int = oraAvviso) -> Date? {
            cal.date(bySettingHour: ora, minute: 0, second: 0, of: d)
        }
        if ha(["stasera", "tonight", "oggi", "today", "asap", "subito"]) { return giorno(da, ora: max(cal.component(.hour, from: da) + 1, 18)) }
        if ha(["dopodomani"]) { return cal.date(byAdding: .day, value: 2, to: da).flatMap { giorno($0) } }
        if ha(["domani", "tomorrow"]) { return cal.date(byAdding: .day, value: 1, to: da).flatMap { giorno($0) } }
        if ha(["settimana prossima", "next week"]) {
            return cal.nextDate(after: da, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime).flatMap { giorno($0) }
        }
        for g in giorni where ha(g.parole) {
            // "venerdì" detto di venerdì vuol dire oggi; detto prima, il prossimo venerdì
            if cal.component(.weekday, from: da) == g.wd { return giorno(da, ora: 18) }
            return cal.nextDate(after: da, matching: DateComponents(weekday: g.wd), matchingPolicy: .nextTime).flatMap { giorno($0) }
        }
        // "entro il 14", "il 14", "by the 14th", "on the 14th"
        if let r = t.range(of: "(entro il|entro|il|by the|on the|by) ([0-9]{1,2})(st|nd|rd|th)? ", options: .regularExpression) {
            let n = Int(t[r].components(separatedBy: " ").compactMap { Int($0.trimmingCharacters(in: .letters)) }.first ?? 0)
            guard (1...31).contains(n) else { return nil }
            let oggi = cal.component(.day, from: da)
            var c = cal.dateComponents([.year, .month], from: da)
            c.day = n; c.hour = oraAvviso
            if n < oggi { c.month = (c.month ?? 1) + 1 }
            return cal.date(from: c)
        }
        return nil
    }

    // MARK: quali messaggi guarda il modello

    private static let segnali = [
        // italiano: richieste e impegni
        "puoi", "potresti", "riesci", "mi mandi", "mi invii", "mi fai sapere", "ti mando", "ti invio", "ti faccio sapere",
        "ti scrivo", "ti chiamo", "ci penso io", "lo faccio", "me ne occupo", "entro", "ricordati", "non dimenticare", "scadenza",
        // inglese
        "can you", "could you", "would you", "please", "i'll", "i will", "let you know", "get back to you", "send", "by friday",
        "deadline", "due", "remind", "don't forget",
    ]
    private static let mittentiAutomatici = ["noreply", "no-reply", "no_reply", "newsletter", "notification", "notifiche", "mailer", "donotreply",
                                             "marketing", "promo", "offers", "digest", "updates", "mailing", "substack", "medium.com", "linkedin"]

    /// Il filtro prima del modello: solo le frasi che sembrano una richiesta o un impegno, così al modello arriva poco.
    static func candidato(_ m: PMessaggio) -> Bool {
        let t = m.testo.lowercased()
        guard (8...800).contains(t.count) else { return false }
        if m.fonte == "Mail", mittentiAutomatici.contains(where: { m.chatID.lowercased().contains($0) }) { return false }
        // 09/11, l'autore: "si concentra su attività inutili". Un punto di domanda da solo non basta: serve un'azione concreta.
        return segnali.contains { t.contains($0) } || (t.contains("?") && azioni.contains { t.contains($0) })
    }

    private static let azioni = ["mand", "invi", "pag", "prenot", "firm", "chiam", "port", "compr", "confer", "controll", "guard", "prepar", "scriv",
                                 "send", "pay", "book", "sign", "call", "bring", "buy", "confirm", "check", "review", "write"]

    // MARK: quando smette di contare

    /// Dopo mezz'ora un avviso su un messaggio non serve più: la promessa entra in lista in silenzio.
    static func fresca(_ d: Date, ora: Date) -> Bool { ora.timeIntervalSince(d) <= 30 * 60 }

    /// 2 giorni dopo la scadenza, o 5 giorni dopo la frase se una scadenza non c'è: quasi sempre è già fatta.
    static func daArchiviare(_ p: Promessa, ora: Date) -> Bool {
        guard p.aperta, (p.rimandata ?? .distantPast) <= ora else { return false }
        if let s = p.scadenza { return ora.timeIntervalSince(s) > 2 * 86400 }
        return ora.timeIntervalSince(p.detta) > 5 * 86400
    }

    // MARK: fatta da sola

    /// Vero se dopo la promessa, nella stessa chat, c'è un tuo messaggio che la chiude.
    /// Si guarda solo ciò che hai scritto TU dopo la frase: un "grazie" dell'altro non chiude niente.
    static func sembraFatta(_ p: Promessa, dopo messaggi: [PMessaggio]) -> Bool {
        let miei = messaggi.filter { $0.chatID == p.chatID && $0.daMe && $0.data > p.detta }
        guard !miei.isEmpty else { return false }
        // Via stretta (01/11, scelta mia: l'autore non ha risposto). Chiude un allegato mandato dopo la promessa, oppure
        // una parola di consegna. Per le promesse tue serve anche una parola del titolo ("ecco il logo" per
        // "Mandare i file del logo"), così un "ecco" detto per altro non la chiude.
        let chiavi = p.titolo.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
        return miei.contains { m in
            if m.allegato { return true }
            let t = " " + m.testo.lowercased() + " "
            guard paroleFatto.contains(where: { t.contains($0) }) else { return false }
            return !p.mia || chiavi.contains { t.contains($0) }
        }
    }

    private static let paroleFatto = [" ecco", "inviat", "mandat", " fatto", " fatta", "prenotat", "pagat", "firmat", "allegat",
                                      " here ", " here's", " sent", " done", " booked", " paid", " signed", "attached"]

    // MARK: ordine ed etichette

    /// Prima quelle scadute, poi per scadenza, in fondo quelle senza data (le più nuove prima).
    static func ordina(_ ps: [Promessa]) -> [Promessa] {
        ps.filter(\.aperta).sorted { a, b in
            switch (a.scadenza, b.scadenza) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.detta > b.detta
            }
        }
    }

    /// Le promesse che devono suonare adesso: scadute, aperte, non rimandate a dopo.
    static func dovute(_ ps: [Promessa], ora: Date) -> [Promessa] {
        ordina(ps).filter { p in
            guard let s = p.scadenza, s <= ora, ora.timeIntervalSince(s) <= 86400 else { return false }   // scaduta da più di un giorno: non suona più
            return (p.rimandata ?? .distantPast) <= ora
        }
    }

    /// La pillola a destra della riga: "Oggi", "Domani", "Ven", "14", "Scaduta".
    static func etichetta(_ s: Date?, ora: Date, it: Bool, cal: Calendar = .current) -> String? {
        guard let s else { return nil }
        if cal.isDate(s, inSameDayAs: ora) { return it ? "Oggi" : "Today" }
        if s < ora { return it ? "Scaduta" : "Overdue" }
        if let d = cal.date(byAdding: .day, value: 1, to: ora), cal.isDate(s, inSameDayAs: d) { return it ? "Domani" : "Tomorrow" }
        let giorni = cal.dateComponents([.day], from: cal.startOfDay(for: ora), to: cal.startOfDay(for: s)).day ?? 99
        let f = DateFormatter()
        f.locale = Locale(identifier: it ? "it_IT" : "en_US")
        if giorni < 7 { f.dateFormat = "EEE"; return (it ? "" : "Due ") + f.string(from: s).capitalized }
        let n = cal.component(.day, from: s)
        if it { return "Il \(n)" }
        let suf = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
        return "\(n)\(suf)"
    }

    // MARK: la risposta del modello

    /// Il modello risponde {"promesse":[{"n":3,"titolo":"...","mia":true}]}: n è il numero della riga che gli abbiamo dato.
    /// Le date non le decide lui: si leggono dalla frase con `scadenza`, così non inventa giorni.
    static func leggiModello(_ json: String, messaggi: [PMessaggio], cal: Calendar = .current) -> [Promessa] {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let lista = (o["righe"] ?? o["promesse"]) as? [[String: Any]] else { return [] }
        let tutte: [Promessa] = lista.compactMap { x in
            if let tipo = x["tipo"] as? String, tipo != "richiesta", tipo != "promessa" { return nil }
            guard let n = (x["n"] as? Int) ?? (x["n"] as? String).flatMap(Int.init), messaggi.indices.contains(n - 1),
                  let titolo = (x["titolo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !titolo.isEmpty else { return nil }
            let m = messaggi[n - 1]
            let mia = (x["mia"] as? Bool) ?? ((x["tipo"] as? String).map { $0 == "promessa" } ?? m.daMe)
            return Promessa(id: m.id, titolo: String(titolo.prefix(70)), chi: m.chat, fonte: m.fonte, chatID: m.chatID,
                            citazione: String(m.testo.prefix(160)), mia: mia, detta: m.data,
                            scadenza: scadenza(m.testo, da: m.data, cal: cal))
        }
        // una richiesta seguita dalla tua promessa nella stessa chat è una cosa sola: resta la promessa,
        // con la scadenza della richiesta se la tua frase non ne dice una
        var out: [Promessa] = []
        for p in tutte {
            if p.mia, let i = out.lastIndex(where: { !$0.mia && $0.chatID == p.chatID }) {
                var q = p
                q.scadenza = p.scadenza ?? out[i].scadenza
                out[i] = q
            } else { out.append(p) }
        }
        return out
    }

    /// La domanda al modello: righe numerate, chi parla, e una regola stretta su cosa conta.
    static func domanda(_ ms: [PMessaggio]) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM HH:mm"; f.locale = Locale(identifier: "en_US")
        let righe = ms.enumerated().map { i, m in
            "\(i + 1). [\(m.fonte), \(m.chat), \(f.string(from: m.data))] \(m.daMe ? "ME" : m.chat): \(m.testo.replacingOccurrences(of: "\n", with: " ").prefix(500))"
        }.joined(separator: "\n")
        return """
        Label each line below. The person reading is ME.
        - "richiesta": another person asks ME to do something concrete (send, sign, pay, call, review, book, confirm, buy, bring). \
        Example: "Luca: Can you book the table for Saturday?" is "richiesta".
        - "promessa": ME promises to do something concrete. Example: "ME: I'll send it tomorrow".
        Only a task that takes ME real effort counts. A question that a one-word answer settles, plans to meet, and requests addressed to someone else are "no".
        - "no": everything else (greetings, jokes, opinions, questions that only want words back like "did you see the game?", \
        ads, newsletters, automatic emails, things already done).
        For "richiesta" and "promessa" add "titolo": a short action, max 5 words, without the day. \
        Write it in the SAME language as the line: an Italian line gets an Italian title ("Mandare i file del logo"), \
        an English line an English title ("Book the table").
        Answer only JSON: {"righe":[{"n":1,"tipo":"no"},{"n":2,"tipo":"richiesta","titolo":"Book the table for Saturday"}]}

        \(righe)
        """
    }

    /// Le nuove si aggiungono, quelle già viste (stesso id) restano come sono: Fatto e Domani non si perdono.
    static func unisci(_ vecchie: [Promessa], _ nuove: [Promessa]) -> [Promessa] {
        let viste = Set(vecchie.map(\.id))
        return vecchie + nuove.filter { !viste.contains($0.id) }
    }
}
