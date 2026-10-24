import Foundation

// Licenza, logica pura: nessuna rete, nessun Portachiavi. Sta nel nucleo e importa solo Foundation.
// La chiave vera vive nel Portachiavi, qui c'è solo il calcolo di cosa è sbloccato.

enum Prodotto: String, CaseIterable, Codable { case lite, agent, mixer, complete }

struct StatoLicenza: Codable, Equatable {
    var prodotti: Set<Prodotto>
    var ultimoControllo: Date?
    var provaDal: Date

    init(prodotti: Set<Prodotto>, ultimoControllo: Date?, provaDal: Date) {
        self.prodotti = prodotti
        self.ultimoControllo = ultimoControllo
        self.provaDal = provaDal
    }

    // Un valore di prodotto sconosciuto (salvato da una versione più nuova) si scarta,
    // senza far fallire la lettura di tutto lo stato.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let grezzi = try c.decode([String].self, forKey: .prodotti)
        prodotti = Set(grezzi.compactMap(Prodotto.init(rawValue:)))
        ultimoControllo = try c.decodeIfPresent(Date.self, forKey: .ultimoControllo)
        provaDal = try c.decode(Date.self, forKey: .provaDal)
    }
}

enum EsitoControllo: Equatable { case valida(Prodotto), nonValida, reteAssente }

enum Licenza {
    static let giorniProva = 7
    static let giorniControllo = 30
    // Segnaposto: la fase 5 mette gli ID veri di Gumroad.
    static let idGumroad: [Prodotto: String] = [
        .agent: "DA-IMPOSTARE-agent", .mixer: "DA-IMPOSTARE-mixer", .complete: "DA-IMPOSTARE-complete"]

    private static let giorno = 86_400.0

    static func nome(_ p: Prodotto) -> String {
        switch p {
        case .lite: return "Pulsar Lite"
        case .agent: return "Pulsar Agent"
        case .mixer: return "Pulsar Mixer"
        case .complete: return "Pulsar Complete"
        }
    }

    /// I prodotti comprati a parole: Complete da solo (assorbe gli altri), altrimenti Agent e Mixer, altrimenti Lite.
    static func nomiComprati(_ prodotti: Set<Prodotto>) -> String {
        if prodotti.contains(.complete) { return nome(.complete) }
        let nomi = [Prodotto.agent, .mixer].filter(prodotti.contains).map(nome)
        return nomi.isEmpty ? nome(.lite) : nomi.joined(separator: ", ")
    }

    /// Giorni interi rimasti, arrotondati per eccesso, fra 0 e 7.
    /// Orologio spostato indietro: se `ora` è prima di `provaDal` di più di un giorno la prova
    /// è finita (0 giorni). Così chi riporta indietro la data non si regala una prova infinita;
    /// fino a un giorno di scarto si tollera (cambio di fuso, piccolo aggiustamento dell'orologio).
    /// Il calcolo resta in Double finché non è limitato, e date strane (NaN, infiniti) danno 0.
    static func giorniProvaRimasti(_ s: StatoLicenza, ora: Date) -> Int {
        let trascorsi = ora.timeIntervalSince(s.provaDal) / giorno
        if trascorsi.isNaN || trascorsi < -1 { return 0 }
        let rimasti = (Double(giorniProva) - trascorsi).rounded(.up)
        if rimasti.isNaN { return 0 }
        return Int(min(Double(giorniProva), max(0, rimasti)))
    }

    static func provaAttiva(_ s: StatoLicenza, ora: Date) -> Bool {
        giorniProvaRimasti(s, ora: ora) > 0
    }

    static func sbloccati(_ s: StatoLicenza, ora: Date, personale: Bool) -> Set<Prodotto> {
        if personale || provaAttiva(s, ora: ora) { return Set(Prodotto.allCases) }
        var out: Set<Prodotto> = [.lite]
        out.formUnion(s.prodotti)
        if s.prodotti.contains(.complete) { out.formUnion([.agent, .mixer]) }
        return out
    }

    static func serveControllo(_ s: StatoLicenza, ora: Date) -> Bool {
        guard let u = s.ultimoControllo else { return true }
        return ora.timeIntervalSince(u) > Double(giorniControllo) * giorno
    }

    /// Vera solo se `success` è vero e nessuno fra refunded, chargebacked, disputed lo è.
    static func leggiRisposta(_ data: Data) -> Bool {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (j["success"] as? Bool) == true else { return false }
        let p = j["purchase"] as? [String: Any] ?? [:]
        for k in ["refunded", "chargebacked", "disputed"] where (p[k] as? Bool) == true { return false }
        return true
    }

    /// Da una risposta HTTP a un esito, per il prodotto `p`. Solo Gumroad può togliere un prodotto:
    /// nonValida per un 404, o per un JSON con `success` falso, o per un acquisto rimborsato o contestato;
    /// valida per un JSON che `leggiRisposta` accetta. Tutto il resto (nessuna risposta, timeout, 3xx, 401, 403,
    /// 429, 5xx, un 200 con HTML o JSON illeggibile o senza `success`) è reteAssente: non cambia niente.
    static func esitoDi(_ p: Prodotto, status: Int?, data: Data?) -> EsitoControllo {
        guard let status else { return .reteAssente }
        if status == 404 { return .nonValida }
        guard (200..<300).contains(status), let data,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let successo = j["success"] as? Bool else { return .reteAssente }
        if !successo { return .nonValida }
        return leggiRisposta(data) ? .valida(p) : .nonValida
    }

    /// Il controllo periodico, una chiave per prodotto: un prodotto si toglie solo se Gumroad dice nonValida;
    /// con valida o reteAssente resta, e un prodotto senza esito (senza chiave salvata) resta.
    static func aggiorna(_ prodotti: Set<Prodotto>, esiti: [Prodotto: EsitoControllo]) -> Set<Prodotto> {
        prodotti.filter { esiti[$0] != .nonValida }
    }
}
