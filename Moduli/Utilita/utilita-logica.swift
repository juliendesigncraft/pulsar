// Utilità, la parte pura (12-13/11/2026, ondata 2 di VORSSAINT.md). Solo Foundation: si prova in prove/main.swift.
import Foundation

/// Toglie dai link copiati i pezzi che servono solo a tracciare (utm_, fbclid, gclid, igsh...).
enum PulisciLink {
    /// Parametri da togliere sempre.
    static let sempre: Set<String> = ["fbclid", "gclid", "dclid", "gbraid", "wbraid", "yclid", "msclkid", "mc_eid", "mc_cid",
                                      "igsh", "igshid", "_hsenc", "_hsmi", "ref_src", "ref_url", "twclid", "ttclid", "li_fat_id",
                                      "srsltid", "oly_anon_id", "oly_enc_id", "vero_id", "rb_clickid", "s_cid", "_ga", "_gl"]
    /// Parametri da togliere solo su certi siti (altrove possono servire).
    static let perSito: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature"], "youtu.be": ["si", "feature"],
        "open.spotify.com": ["si", "context"], "x.com": ["s", "t"], "twitter.com": ["s", "t"],
        "amazon.": ["ref", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pf_rd_p", "pf_rd_r", "content-id", "psc"],
    ]

    /// Il link pulito, oppure nil se non c'era niente da togliere o il testo non è un link solo.
    static func pulisci(_ testo: String) -> String? {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" "), !t.contains("\n"), t.lowercased().hasPrefix("http"),
              var c = URLComponents(string: t), let host = c.host?.lowercased(), let voci = c.queryItems, !voci.isEmpty else { return nil }
        let delSito = perSito.filter { host == $0.key || host.hasSuffix("." + $0.key) || ($0.key.hasSuffix(".") && host.contains($0.key)) }
            .reduce(into: Set<String>()) { $0.formUnion($1.value) }
        let tenute = voci.filter { v in
            let n = v.name.lowercased()
            return !(n.hasPrefix("utm_") || sempre.contains(n) || delSito.contains(n))
        }
        guard tenute.count < voci.count else { return nil }
        c.queryItems = tenute.isEmpty ? nil : tenute
        return c.string
    }
}

/// "Chiudi è esci": un'app che passa da almeno una finestra a nessuna si chiude del tutto.
enum ChiudiEsci {
    /// pid delle app da chiudere, dati i conteggi delle finestre prima e adesso (le app non più aperte non contano).
    static func daChiudere(prima: [Int32: Int], ora: [Int32: Int], esclusi: Set<Int32>) -> [Int32] {
        ora.compactMap { pid, n in
            guard n == 0, let p = prima[pid], p > 0, !esclusi.contains(pid) else { return nil }
            return pid
        }.sorted()
    }
}

/// Il colore del contagocce in esadecimale, come lo scrive l'autore (#RRGGBB, maiuscolo).
enum Esadecimale {
    static func da(_ r: Double, _ g: Double, _ b: Double) -> String {
        func h(_ v: Double) -> String { String(format: "%02X", Int((min(1, max(0, v)) * 255).rounded())) }
        return "#" + h(r) + h(g) + h(b)
    }
}
