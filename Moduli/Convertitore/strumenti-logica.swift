// Stow, gli strumenti (21/10/2026): tenendo ⌥ mentre si trascina, al posto degli scopi compaiono gli strumenti di modifica,
// quelli che l'autore ha visto nel riferimento (ritaglio con proporzioni, peso, metadati, taglio del video, divisione del PDF).
// Solo Foundation e CoreGraphics: si prova in prove/convertitore. Chi esegue è convertitore-motore.swift (sezione Strumenti).
import Foundation
import CoreGraphics

enum Proporzione: String, CaseIterable, Equatable {
    case quadrata = "1:1", verticale = "4:5", larga = "16:9", storia = "9:16"
    var rapporto: CGFloat {
        switch self { case .quadrata: return 1; case .verticale: return 4.0 / 5; case .larga: return 16.0 / 9; case .storia: return 9.0 / 16 }
    }
}

enum Strumento: Equatable {
    case ritaglia(Proporzione)
    /// Sotto questo peso, in KB (immagini: qualità e lato che scendono; PDF: il filtro di sistema; video: 720p).
    case comprimi(kb: Int)
    case metadati
    /// Video e audio: si apre la finestra di taglio di macOS (AVPlayerView), poi si esporta solo quel pezzo.
    case taglia
    /// PDF: una pagina per file.
    case dividi

    /// Il nome sulla tessera in italiano e in inglese (la vista sceglie con T: qui niente AppKit, si prova da solo).
    var nomi: (it: String, en: String) {
        switch self {
        case .ritaglia(let p): return (p.rawValue, p.rawValue)
        case .comprimi(let kb): let t = kb >= 1000 ? "< \(kb / 1000) MB" : "< \(kb) KB"; return (t, t)
        case .metadati: return ("Metadati", "Metadata")
        case .taglia: return ("Taglia", "Trim")
        case .dividi: return ("Dividi", "Split")
        }
    }
    /// SF Symbol della tessera.
    var simbolo: String {
        switch self {
        case .ritaglia(let p):
            switch p { case .quadrata: return "square"; case .verticale: return "rectangle.portrait"; case .larga: return "rectangle"; case .storia: return "iphone" }
        case .comprimi: return "arrow.down.right.and.arrow.up.left"
        case .metadati: return "tag.slash"
        case .taglia: return "scissors"
        case .dividi: return "doc.on.doc"
        }
    }
}

enum Strumenti {
    /// Gli strumenti per una famiglia, nell'ordine delle tessere (al massimo sei: due file da tre).
    static func per(_ f: Famiglia) -> [Strumento] {
        switch f {
        case .immagine: return [.ritaglia(.quadrata), .ritaglia(.verticale), .ritaglia(.storia), .ritaglia(.larga), .comprimi(kb: 1000), .metadati]
        case .video: return [.taglia, .comprimi(kb: 25_000), .metadati]
        case .audio: return [.taglia]
        case .pdf: return [.dividi, .comprimi(kb: 2000), .metadati]
        case .documento: return []
        }
    }

    /// Per un gruppo di file: gli strumenti che valgono per tutti (stessa famiglia). Famiglie miste: nessuno.
    static func per(file: [URL]) -> [Strumento] {
        let fam = Set(file.compactMap { Convertitore.famiglia(di: $0) })
        guard fam.count == 1, let f = fam.first else { return [] }
        // il taglio apre una finestra: ha senso su un file solo
        return per(f).filter { $0 != .taglia || file.count == 1 }
    }

    /// Il ritaglio più grande con quella proporzione, centrato (in pixel, origine in alto a sinistra).
    static func ritaglio(larghezza w: Int, altezza h: Int, _ p: Proporzione) -> CGRect {
        let W = CGFloat(w), H = CGFloat(h)
        guard W > 0, H > 0 else { return .zero }
        if W / H > p.rapporto {
            let nw = (H * p.rapporto).rounded()
            return CGRect(x: ((W - nw) / 2).rounded(.down), y: 0, width: nw, height: H)
        } else {
            let nh = (W / p.rapporto).rounded()
            return CGRect(x: 0, y: ((H - nh) / 2).rounded(.down), width: W, height: nh)
        }
    }

    /// I tentativi per stare sotto un peso: prima scende la qualità, poi il lato (mai sotto 0,4 di qualità né 640 px).
    static func tentativiPeso(latoOriginale: Int) -> [(lato: Int, qualita: Double)] {
        var out: [(Int, Double)] = []
        var lato = latoOriginale
        while true {
            for q in [0.85, 0.72, 0.6, 0.5, 0.4] { out.append((lato, q)) }
            let prossimo = Int(Double(lato) * 0.75)
            if prossimo < 640 { break }
            lato = prossimo
        }
        return out
    }
}

// MARK: - Le tessere degli strumenti nella zona di rilascio

extension MutaZona {
    /// Due file da tre tessere, alte quanto serve per stare nella stessa altezza del pannello degli scopi.
    static func disposizione(strumenti s: [Strumento]) -> [Posto] {
        guard !s.isEmpty else { return [] }
        let col = 3
        let righe = (s.count + col - 1) / col
        let h = (altezza - stacco * CGFloat(righe - 1)) / CGFloat(righe)
        let w = (larghezzaPosti - stacco * CGFloat(col - 1)) / CGFloat(col)
        return s.enumerated().map { i, st in
            Posto(bersaglio: .strumento(st), rect: CGRect(x: inizioX + CGFloat(i % col) * (w + stacco), y: CGFloat(i / col) * (h + stacco), width: w, height: h))
        }
    }
}
