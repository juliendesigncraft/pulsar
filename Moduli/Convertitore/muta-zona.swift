// Muta: dove stanno le tessere nel notch mentre si trascina, e quale tessera c'è sotto il mouse.
// Solo Foundation (CoreGraphics per i rettangoli): la vista (muta-viste.swift) e l'isola usano gli stessi numeri,
// così quello che si vede e quello che riceve il file sono la stessa cosa. Si prova in prove/convertitore.
// Disposizione approvata dall'autore il 19/10 (bozza A, "misto"): in alto gli scopi grandi, sotto una fila di pillole
// con i formati, "Unisci in PDF" e in fondo dove andava il file prima di Muta (Claude o il Vassoio).
import Foundation
import CoreGraphics

enum Bersaglio: Equatable {
    case scopo(Scopo)
    case formato(Formato)
    case unisci
    /// Il comportamento di prima: a Claude se c'è una sessione, altrimenti nel Vassoio.
    case altrove
    /// 21/10: tenendo ⌥, uno strumento (strumenti-logica.swift)
    case strumento(Strumento)
    /// 24/10, da coucou: il file parte per email dal notch (isola-email.swift)
    case email
}

struct Posto: Equatable {
    var bersaglio: Bersaglio
    var rect: CGRect
}

enum MutaZona {
    static let larghezza: CGFloat = 560      // il pannello di rilascio è largo 600, con 20 di margine per lato
    /// 19/10 sera, l'autore: "più grafica, come Tangerine". A sinistra l'anteprima del file in mano, i posti a destra.
    static let anteprima: CGFloat = 112
    static var inizioX: CGFloat { anteprima + stacco + 4 }
    static var larghezzaPosti: CGFloat { larghezza - inizioX }
    static let altezzaScopi: CGFloat = 96
    static let stacco: CGFloat = 8
    static let altezzaPillole: CGFloat = 40
    static let pilloleMax = 7
    static var altezza: CGFloat { altezzaScopi + 10 + altezzaPillole }
    /// 24/10: la tessera Email c'è solo nella build dell'autore. Nella vendita non è nelle schede e chiederebbe
    /// l'Automazione di Mail: lì il suo posto torna a un formato.
    static var conEmail: Bool {
        return false
    }

    /// I posti, in coordinate del contenuto (origine in alto a sinistra, y verso il basso).
    static func disposizione(_ p: Convertitore.Proposta, email: Bool = conEmail) -> [Posto] {
        var posti: [Posto] = []
        let n = p.scopi.count
        if n > 0 {
            let w = (larghezzaPosti - stacco * CGFloat(n - 1)) / CGFloat(n)
            for (i, s) in p.scopi.enumerated() {
                posti.append(Posto(bersaglio: .scopo(s), rect: CGRect(x: inizioX + CGFloat(i) * (w + stacco), y: 0, width: w, height: altezzaScopi)))
            }
        }
        // la fila: formati quanti ne stanno, poi Unisci (se c'è), Email (solo personale), e sempre in fondo il posto di prima
        var fila: [Bersaglio] = []
        let liberi = pilloleMax - (email ? 2 : 1) - (p.unisciInPDF ? 1 : 0)
        fila += p.formati.prefix(liberi).map { .formato($0) }
        if p.unisciInPDF { fila.append(.unisci) }
        if email { fila.append(.email) }
        fila.append(.altrove)
        let y = n > 0 ? altezzaScopi + 10 : 0
        let pw = (larghezzaPosti - stacco * CGFloat(pilloleMax - 1)) / CGFloat(pilloleMax)
        // la fila si allinea a destra: il posto di prima resta sempre nello stesso punto
        let inizio = larghezza - CGFloat(fila.count) * pw - CGFloat(fila.count - 1) * stacco
        for (i, b) in fila.enumerated() {
            posti.append(Posto(bersaglio: b, rect: CGRect(x: inizio + CGFloat(i) * (pw + stacco), y: y, width: pw, height: altezzaPillole)))
        }
        return posti
    }

    /// Il bersaglio sotto il punto, con un margine di 4 punti attorno a ogni posto (fra due posti vince il più vicino).
    static func bersaglio(in posti: [Posto], a punto: CGPoint) -> Bersaglio? {
        let vicini = posti.filter { $0.rect.insetBy(dx: -4, dy: -4).contains(punto) }
        return vicini.min { distanza($0.rect, punto) < distanza($1.rect, punto) }?.bersaglio
    }

    private static func distanza(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
