// Sistema, la parte pura (13/11/2026, ondata 3 di VORSSAINT.md): versioni, appcast, prova di velocità, resti delle app,
// misure leggibili. Solo Foundation: si prova in prove/main.swift.
import Foundation

enum Versioni {
    /// true se `nuova` è più alta di `attuale` ("1.10" > "1.9", "2.0" > "1.9.9", "1.2" == "1.2.0").
    static func piuNuova(_ nuova: String, di attuale: String) -> Bool {
        func parti(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parti(nuova), b = parti(attuale)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Il feed degli aggiornamenti delle app con Sparkle (appcast.xml): la versione più alta che annuncia.
enum Appcast {
    static func ultimaVersione(_ xml: String) -> String? {
        var trovate: [String] = []
        for chiave in ["sparkle:shortVersionString", "sparkle:version"] {
            // come attributo dell'enclosure (sparkle:shortVersionString="1.2") o come elemento (<sparkle:version>1.2</...>)
            for pezzo in xml.components(separatedBy: chiave).dropFirst() {
                let p = pezzo.trimmingCharacters(in: .whitespaces)
                if p.hasPrefix("=\"") || p.hasPrefix("='") {
                    let q = p.dropFirst(2); if let fine = q.firstIndex(where: { $0 == "\"" || $0 == "'" }) { trovate.append(String(q[..<fine])) }
                } else if p.hasPrefix(">") {
                    let q = p.dropFirst(); if let fine = q.firstIndex(of: "<") { trovate.append(String(q[..<fine]).trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }
            if !trovate.isEmpty { break }      // la versione da mostrare vince sul numero di build
        }
        return trovate.reduce(nil as String?) { m, v in m.map { Versioni.piuNuova(v, di: $0) ? v : $0 } ?? v }
    }
}

/// L'uscita JSON di `networkQuality -c` (lo strumento di macOS): velocità in Mbit/s.
enum ProvaVelocita {
    struct Esito: Equatable { let giu: Double; let su: Double; let risposta: Double? }
    static func leggi(_ json: Data) -> Esito? {
        guard let d = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let g = (d["dl_throughput"] as? NSNumber)?.doubleValue, let s = (d["ul_throughput"] as? NSNumber)?.doubleValue else { return nil }
        let rpm = (d["responsiveness"] as? NSNumber)?.doubleValue ?? (d["dl_responsiveness"] as? NSNumber)?.doubleValue
        return Esito(giu: g / 1_000_000, su: s / 1_000_000, risposta: rpm)
    }
}

/// I resti di un'app in ~/Library: cartelle e file che portano il suo identificatore o il suo nome.
enum Resti {
    /// Le sottocartelle di ~/Library dove le app lasciano file, e se lì si cerca per identificatore, per nome o per entrambi.
    static let posti: [(cartella: String, perNome: Bool)] = [
        ("Application Support", true), ("Caches", false), ("Preferences", false), ("Containers", false),
        ("Group Containers", false), ("Saved Application State", false), ("HTTPStorages", false), ("WebKit", false),
        ("Logs", true), ("LaunchAgents", false), ("Application Scripts", false), ("Cookies", false)]

    /// Un nome di file o cartella appartiene all'app? Identificatore esatto, con estensione (.plist, .savedState,
    /// .binarycookies) o con un suffisso (.helper); il nome solo dove i nomi sono usati e se è lungo almeno 4 lettere.
    static func appartiene(_ voce: String, id: String, nome: String, perNome: Bool) -> Bool {
        let v = voce.lowercased(), i = id.lowercased()
        if !i.isEmpty, v == i || v.hasPrefix(i + ".") || v.hasSuffix("." + i) && v.count > i.count + 2 { return true }
        let n = nome.lowercased()
        return perNome && n.count >= 4 && (v == n || v == n.replacingOccurrences(of: " ", with: ""))
    }
}

enum Misura {
    /// 1536 → "1,5 KB", 2_500_000 → "2,5 MB" (base 1000 come il Finder).
    static func byte(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: b)
    }
    /// Velocità in byte al secondo, leggibile: "14 KB/s", "4,6 MB/s".
    static func alSecondo(_ b: Double) -> String { byte(Int64(max(0, b))) + "/s" }
}
