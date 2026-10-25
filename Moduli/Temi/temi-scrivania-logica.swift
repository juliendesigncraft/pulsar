// Temi per chi compra (25/10/2026): la parte senza Pulsar di sfondo e cartelle (la usa Moduli/Temi/temi-scrivania.swift).
// Niente impostazioni, niente finestre: così si prova in prove/temi/ su una cartella finta, senza toccare la scrivania vera.
// Lo sfondo vero non si prova mai da qui: cambierebbe quello di chi lancia la prova.
import AppKit

/// Uno sfondo come macOS lo dà per uno schermo: il file e le opzioni (scala, ritaglio, colore di riempimento).
struct SfondoSalvato: Codable, Equatable {
    var percorso: String
    var scala: Int? = nil
    var ritaglio: Bool? = nil
    var riempimento: [Double]? = nil      // r, g, b, a in sRGB
}

/// Cosa c'era prima che Pulsar toccasse la scrivania. Si scrive quando si accende l'interruttore (e quando si aggiunge
/// una cartella con l'interruttore acceso), si legge e si cancella quando si spegne.
struct OriginaliScrivania: Codable, Equatable {
    var sfondi: [String: SfondoSalvato] = [:]      // numero dello schermo → sfondo
    var cartelle: [String: String] = [:]           // percorso → nome del PNG salvato, "" = la cartella non aveva un'icona sua

    static func leggi(_ url: URL) -> OriginaliScrivania? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OriginaliScrivania.self, from: d)
    }

    func scrivi(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }
}

enum LogicaScrivania {
    /// L'interruttore "Cambia anche sfondo e cartelle": valore mancante o strano = spento (di serie spento).
    static func acceso(_ salvato: Any?) -> Bool { salvato as? Bool ?? false }

    /// Uno sfondo si salva solo se è un file e non è uno dei nostri (se no, spegnendo, si rimetterebbe il Matte).
    static func daSalvare(_ percorso: String?, nostri: String) -> Bool {
        guard let p = percorso, !p.isEmpty else { return false }
        let n = (nostri as NSString).standardizingPath
        return !(p as NSString).standardizingPath.hasPrefix(n + "/")
    }

    /// La lista delle cartelle con quelle nuove in fondo: percorsi puliti, senza doppioni, l'ordine di prima resta.
    static func aggiungi(_ nuove: [String], a lista: [String]) -> [String] {
        var r = lista
        for c in nuove {
            let p = (c as NSString).standardizingPath
            if !p.isEmpty, p != "/", !r.contains(p) { r.append(p) }
        }
        return r
    }

    /// Lo sfondo da rimettere su uno schermo: il suo, o se lo schermo è nuovo il primo salvato (in ordine di numero).
    static func perSchermo(_ id: String, in sfondi: [String: SfondoSalvato]) -> SfondoSalvato? {
        sfondi[id] ?? sfondi.keys.sorted().first.flatMap { sfondi[$0] }
    }

    /// Le cartelle della Scrivania da proporre: niente nascoste, niente pacchetti (app, librerie di Foto), in ordine di nome.
    static func cartelleScrivania(_ voci: [(nome: String, cartella: Bool, pacchetto: Bool)]) -> [String] {
        voci.filter { $0.cartella && !$0.pacchetto && !$0.nome.hasPrefix(".") }
            .map(\.nome)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Un nome di file stabile per l'icona salvata di una cartella (FNV-1a sul percorso).
    static func nomeIcona(_ percorso: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in percorso.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx.png", h)
    }
}

/// L'icona di una cartella: salvarla prima di cambiarla, rimetterla dopo. Una cartella con un'icona sua ha dentro
/// il file nascosto "Icon\r": se c'è si salva una copia PNG di quella che si vede, se no basta togliere la nostra.
enum IconeCartella {
    static func haIconaSua(_ cartella: String) -> Bool {
        FileManager.default.fileExists(atPath: (cartella as NSString).appendingPathComponent("Icon\r"))
    }

    /// Salva l'icona di adesso in `dir` e torna il nome del PNG, o "" se la cartella non aveva un'icona sua.
    static func salva(_ cartella: String, in dir: URL) -> String {
        guard haIconaSua(cartella) else { return "" }
        let img = NSWorkspace.shared.icon(forFile: cartella)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
        NSGraphicsContext.restoreGraphicsState()
        let nome = LogicaScrivania.nomeIcona(cartella)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard (try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(nome))) != nil else { return "" }
        return nome
    }

    /// Mette un'icona (sul filo principale: da un filo secondario setIcon fallisce in silenzio, 11/10).
    static func metti(_ img: NSImage, su cartella: String) {
        guard FileManager.default.fileExists(atPath: cartella) else { return }
        NSWorkspace.shared.setIcon(img, forFile: cartella, options: [])
        NSWorkspace.shared.noteFileSystemChanged(cartella)
    }

    /// Rimette l'icona salvata (`nome` dato da `salva`) e cancella la copia; con "" toglie l'icona di Pulsar.
    static func rimetti(_ cartella: String, nome: String, da dir: URL) {
        guard FileManager.default.fileExists(atPath: cartella) else { return }
        let file = dir.appendingPathComponent(nome)
        if !nome.isEmpty, let img = NSImage(contentsOf: file) {
            NSWorkspace.shared.setIcon(img, forFile: cartella, options: [])
            try? FileManager.default.removeItem(at: file)
        } else {
            NSWorkspace.shared.setIcon(nil, forFile: cartella, options: [])
        }
        NSWorkspace.shared.noteFileSystemChanged(cartella)
    }
}
