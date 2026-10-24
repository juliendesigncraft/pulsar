// Convertitore (fase 4): la logica pura. Decide che cosa si può fare con i file lasciati nel notch, senza toccarli.
// Solo Foundation: si prova senza l'app (prove/convertitore.swift). Chi esegue è convertitore-motore.swift.
// Disegno in docs/2026-10-19-convertitore-design.md.
import Foundation

enum Famiglia: String, CaseIterable { case immagine, video, audio, pdf, documento }

enum Formato: String, CaseIterable {
    case jpeg, png, heic, avif, webp, tiff, gif, pdf
    case mp4, mov
    case m4a, wav, aiff, flac
    case docx, rtf, txt, html, odt

    var estensione: String { self == .jpeg ? "jpg" : rawValue }
    /// Il nome sulla tessera.
    var etichetta: String { rawValue.uppercased() }
}

enum Scopo: String, CaseIterable { case web, mandare, stampare
    var etichetta: String {
        switch self { case .web: return "Per il web"; case .mandare: return "Per mandarlo"; case .stampare: return "Per stamparlo" }
    }
}

/// Quello che il motore esegue. latoMax nil = dimensione originale. qualita nil = quella di sistema.
struct Ricetta: Equatable {
    var formato: Formato
    var latoMax: Int? = nil
    var qualita: Double? = nil
    /// Solo PDF in PDF: passa dal filtro di sistema che riduce il peso.
    var comprimi: Bool = false
}

enum Convertitore {
    private static let perEstensione: [String: Famiglia] = {
        var m: [String: Famiglia] = [:]
        for e in ["jpg", "jpeg", "png", "heic", "heif", "avif", "webp", "tif", "tiff", "gif", "bmp"] { m[e] = .immagine }
        for e in ["mp4", "mov", "m4v"] { m[e] = .video }
        for e in ["m4a", "wav", "aif", "aiff", "flac", "caf", "mp3", "aac"] { m[e] = .audio }
        m["pdf"] = .pdf
        for e in ["docx", "doc", "rtf", "txt", "html", "htm", "odt"] { m[e] = .documento }
        return m
    }()

    static func famiglia(di url: URL) -> Famiglia? { perEstensione[url.pathExtension.lowercased()] }

    /// Il formato del file d'origine, se è uno di quelli che sappiamo scrivere.
    static func formato(di url: URL) -> Formato? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "tif": return .tiff
        case "aif": return .aiff
        case "htm": return .html
        case let e: return Formato(rawValue: e)
        }
    }

    static func uscite(di f: Famiglia) -> [Formato] {
        switch f {
        case .immagine: return [.jpeg, .png, .webp, .heic, .avif, .pdf, .tiff, .gif]
        case .video: return [.mp4, .mov, .m4a, .gif]
        case .audio: return [.m4a, .wav, .aiff, .flac]
        case .pdf: return [.png, .jpeg, .txt]
        case .documento: return [.pdf, .docx, .rtf, .txt, .html, .odt]
        }
    }

    /// Le tessere dei formati per un file: le uscite della sua famiglia senza il formato che ha già.
    static func uscite(per url: URL) -> [Formato] {
        guard let f = famiglia(di: url) else { return [] }
        let origine = formato(di: url)
        return uscite(di: f).filter { $0 != origine }
    }

    static func ricetta(_ s: Scopo, per f: Famiglia) -> Ricetta? {
        switch (f, s) {
        // 19/10 sera, l'autore: "heic che fa jpg", "chi cavolo conosce webp?". Il web è JPEG; WebP resta fra i formati a scelta.
        case (.immagine, .web): return Ricetta(formato: .jpeg, latoMax: 2000, qualita: 0.8)
        case (.immagine, .mandare): return Ricetta(formato: .jpeg, latoMax: 2048, qualita: 0.75)
        case (.immagine, .stampare): return Ricetta(formato: .pdf)
        case (.video, .web): return Ricetta(formato: .mp4, latoMax: 1920)
        case (.video, .mandare): return Ricetta(formato: .mp4, latoMax: 1280)
        case (.audio, .web), (.audio, .mandare): return Ricetta(formato: .m4a)
        case (.pdf, .web), (.pdf, .mandare): return Ricetta(formato: .pdf, comprimi: true)
        case (.documento, .web): return Ricetta(formato: .html)
        case (.documento, .mandare), (.documento, .stampare): return Ricetta(formato: .pdf)
        default: return nil
        }
    }

    /// Che cosa mostra il notch per un gruppo di file.
    struct Proposta: Equatable {
        var scopi: [Scopo]
        /// Vuoto se le famiglie sono miste: un formato solo non va bene per tutti.
        var formati: [Formato]
        /// Solo per due o più immagini.
        var unisciInPDF: Bool
        /// I file che non sappiamo trattare: restano fuori e il notch lo dice.
        var ignorati: [URL]
    }

    static func proposta(per file: [URL]) -> Proposta {
        let validi = file.filter { famiglia(di: $0) != nil }
        let ignorati = file.filter { famiglia(di: $0) == nil }
        let famiglie = Set(validi.compactMap(famiglia(di:)))
        guard !famiglie.isEmpty else { return Proposta(scopi: [], formati: [], unisciInPDF: false, ignorati: ignorati) }
        let scopi = Scopo.allCases.filter { s in famiglie.allSatisfy { ricetta(s, per: $0) != nil } }
        var formati: [Formato] = []
        if famiglie.count == 1, let f = famiglie.first {
            // con un file solo si toglie il suo formato; con più file si tolgono solo i formati che hanno già tutti
            let origini = Set(validi.compactMap(formato(di:)))
            formati = uscite(di: f).filter { !(origini.count == 1 && origini.contains($0)) }
        }
        let unisci = famiglie == [.immagine] && validi.count >= 2
        return Proposta(scopi: scopi, formati: formati, unisciInPDF: unisci, ignorati: ignorati)
    }

    /// Il file nuovo accanto all'originale, come il Finder: "foto.webp", poi "foto 2.webp", "foto 3.webp".
    /// `esiste` dice se un percorso è già preso (nelle prove è un insieme, nell'app il disco).
    /// Non restituisce mai il percorso d'origine.
    static func uscita(per origine: URL, estensione: String, esiste: (URL) -> Bool) -> URL {
        let cartella = origine.deletingLastPathComponent()
        let nome = origine.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let candidato = cartella.appendingPathComponent(n == 1 ? nome : "\(nome) \(n)").appendingPathExtension(estensione)
            if candidato.standardizedFileURL != origine.standardizedFileURL && !esiste(candidato) { return candidato }
            n += 1
        }
    }

    /// Lato lungo dopo il ridimensionamento: mai ingrandire.
    static func dimensione(larghezza w: Int, altezza h: Int, latoMax: Int?) -> (Int, Int) {
        guard let m = latoMax, max(w, h) > m, w > 0, h > 0 else { return (w, h) }
        let k = Double(m) / Double(max(w, h))
        return (max(1, Int((Double(w) * k).rounded())), max(1, Int((Double(h) * k).rounded())))
    }

    /// Il riepilogo alla fine di un gruppo: "3 fatti", "9 fatti, 1 non riuscito".
    static func riepilogo(fatti: Int, falliti: Int) -> String {
        let a = fatti == 1 ? "1 fatto" : "\(fatti) fatti"
        guard falliti > 0 else { return a }
        return a + ", " + (falliti == 1 ? "1 non riuscito" : "\(falliti) non riusciti")
    }
}
