// Convertitore (fase 4): il motore. Esegue una Ricetta su un file e scrive la copia accanto all'originale.
// Mai sovrascrive (i nomi li sceglie Convertitore.uscita), mai rete. WebP con libwebp (Vendor/libwebp, modulo CWebP),
// il resto con quello che il Mac ha già: ImageIO, AVFoundation, PDFKit, AppKit, textutil.
// I documenti in PDF passano da NSPrintOperation, che il motore porta da solo sul filo principale.
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import PDFKit
import Quartz
import CWebP

enum ErroreConvertitore: LocalizedError {
    case nonPossibile(String)
    case lettura(String)
    case scrittura(String)

    var errorDescription: String? {
        switch self {
        case .nonPossibile(let s): return "Questa conversione non si può fare: \(s)"
        case .lettura(let s): return "Il file non si legge: \(s)"
        case .scrittura(let s): return "Il file nuovo non si scrive: \(s)"
        }
    }
}

enum MotoreConvertitore {
    /// Esegue la ricetta e restituisce i file creati (più di uno solo per un PDF di più pagine in immagini).
    static func esegui(_ r: Ricetta, su origine: URL) async throws -> [URL] {
        guard let fam = Convertitore.famiglia(di: origine) else { throw ErroreConvertitore.nonPossibile(origine.pathExtension) }
        switch fam {
        case .immagine: return [try immagine(r, origine)]
        case .video: return [try await video(r, origine)]
        case .audio: return [try audio(r, origine)]
        case .pdf: return try pdf(r, origine)
        case .documento: return [try await documento(r, origine)]
        }
    }

    /// Due o più immagini in un PDF, una per pagina, nell'ordine dato. Il PDF prende il nome della prima.
    static func unisciInPDF(_ immagini: [URL]) throws -> URL {
        guard let prima = immagini.first else { throw ErroreConvertitore.nonPossibile("nessuna immagine") }
        let d = PDFDocument()
        for u in immagini {
            guard let cg = carica(u, latoMax: nil), let p = PDFPage(image: NSImage(cgImage: cg, size: .zero)) else { throw ErroreConvertitore.lettura(u.lastPathComponent) }
            d.insert(p, at: d.pageCount)
        }
        let out = nuovo(prima, "pdf")
        guard d.write(to: out) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
        return out
    }

    // MARK: - nomi

    private static func nuovo(_ origine: URL, _ ext: String) -> URL {
        Convertitore.uscita(per: origine, estensione: ext) { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - immagini

    /// Legge l'immagine già ruotata come la mostra il Finder, ridotta se serve (mai ingrandita).
    static func carica(_ u: URL, latoMax: Int?) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let (nw, nh) = Convertitore.dimensione(larghezza: w, altezza: h, latoMax: latoMax)
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(nw, nh, 1),
        ] as CFDictionary)
    }

    private static func immagine(_ r: Ricetta, _ origine: URL) throws -> URL {
        guard let cg = carica(origine, latoMax: r.latoMax) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        let out = nuovo(origine, r.formato.estensione)
        switch r.formato {
        case .webp:
            try scriviWebP(cg, out, qualita: r.qualita ?? 0.85)
        case .pdf:
            let d = PDFDocument()
            guard let p = PDFPage(image: NSImage(cgImage: cg, size: .zero)) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
            d.insert(p, at: 0)
            guard d.write(to: out) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
        case .jpeg, .png, .heic, .avif, .tiff, .gif:
            try scriviImageIO(cg, out, tipo: tipo(r.formato), qualita: r.qualita)
        default:
            throw ErroreConvertitore.nonPossibile("immagine in \(r.formato.etichetta)")
        }
        return out
    }

    private static func tipo(_ f: Formato) -> UTType {
        switch f {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .avif: return UTType("public.avif") ?? .heic
        case .tiff: return .tiff
        case .gif: return .gif
        default: return .data
        }
    }

    /// I metadati di posizione (GPS) non passano mai nel file nuovo: si scrive solo l'immagine.
    static func scriviImageIO(_ cg: CGImage, _ out: URL, tipo: UTType, qualita: Double?) throws {
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, tipo.identifier as CFString, 1, nil) else {
            throw ErroreConvertitore.nonPossibile(tipo.preferredFilenameExtension ?? tipo.identifier)
        }
        var p: [CFString: Any] = [:]
        if let q = qualita { p[kCGImageDestinationLossyCompressionQuality] = q }
        CGImageDestinationAddImage(d, cg, p as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
    }

    /// WebP con libwebp. Vuole RGBA non premoltiplicato: si disegna premoltiplicato e si riporta indietro dove c'è trasparenza.
    static func scriviWebP(_ cg: CGImage, _ out: URL, qualita: Double) throws {
        let w = cg.width, h = cg.height, stride = w * 4
        var px = [UInt8](repeating: 0, count: stride * h)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: stride,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
        for i in Swift.stride(from: 0, to: px.count, by: 4) {
            let a = Int(px[i + 3])
            if a > 0 && a < 255 {
                for c in 0..<3 { px[i + c] = UInt8(min(255, (Int(px[i + c]) * 255 + a / 2) / a)) }
            }
        }
        var dati: UnsafeMutablePointer<UInt8>?
        let n = WebPEncodeRGBA(px, Int32(w), Int32(h), Int32(stride), Float(max(0, min(1, qualita)) * 100), &dati)
        guard n > 0, let d = dati else { throw ErroreConvertitore.scrittura("WebP") }
        defer { WebPFree(d) }
        do { try Data(bytes: d, count: n).write(to: out) } catch { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
    }

    // MARK: - video

    private static func video(_ r: Ricetta, _ origine: URL) async throws -> URL {
        let asset = AVURLAsset(url: origine)
        let out = nuovo(origine, r.formato.estensione)
        switch r.formato {
        case .gif:
            try await gif(asset, out)
            return out
        case .mp4, .mov, .m4a:
            let preset: String
            switch (r.formato, r.latoMax) {
            case (.m4a, _): preset = AVAssetExportPresetAppleM4A
            case (_, .some(let m)) where m <= 1280: preset = AVAssetExportPreset1280x720
            case (_, .some): preset = AVAssetExportPreset1920x1080
            default: preset = AVAssetExportPresetHighestQuality
            }
            let tipo: AVFileType = r.formato == .mp4 ? .mp4 : r.formato == .mov ? .mov : .m4a
            guard let e = AVAssetExportSession(asset: asset, presetName: preset) else { throw ErroreConvertitore.nonPossibile("preset \(preset)") }
            do { try await e.export(to: out, as: tipo) } catch { throw ErroreConvertitore.scrittura(error.localizedDescription) }
            return out
        default:
            throw ErroreConvertitore.nonPossibile("video in \(r.formato.etichetta)")
        }
    }

    /// GIF dei primi 10 secondi, 10 fotogrammi al secondo, lato 480: oltre diventa troppo pesante per servire.
    private static func gif(_ asset: AVURLAsset, _ out: URL) async throws {
        let durata = try await asset.load(.duration).seconds
        let secondi = min(max(durata, 0.1), 10)
        let n = max(1, Int(secondi * 10))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw ErroreConvertitore.scrittura("GIF") }
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<n {
            let (cg, _) = try await gen.image(at: CMTime(seconds: Double(i) / 10, preferredTimescale: 600))
            CGImageDestinationAddImage(d, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(d) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
    }

    // MARK: - audio

    private static func audio(_ r: Ricetta, _ origine: URL) throws -> URL {
        let src: AVAudioFile
        do { src = try AVAudioFile(forReading: origine) } catch { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        let fmt = src.processingFormat
        let sr = fmt.sampleRate, ch = fmt.channelCount
        var s: [String: Any] = [AVSampleRateKey: sr, AVNumberOfChannelsKey: ch]
        switch r.formato {
        case .m4a: s[AVFormatIDKey] = kAudioFormatMPEG4AAC; s[AVEncoderBitRateKey] = ch > 1 ? 192_000 : 128_000
        case .flac: s[AVFormatIDKey] = kAudioFormatFLAC
        case .wav: s[AVFormatIDKey] = kAudioFormatLinearPCM; s[AVLinearPCMBitDepthKey] = 16; s[AVLinearPCMIsFloatKey] = false; s[AVLinearPCMIsBigEndianKey] = false
        case .aiff: s[AVFormatIDKey] = kAudioFormatLinearPCM; s[AVLinearPCMBitDepthKey] = 16; s[AVLinearPCMIsFloatKey] = false; s[AVLinearPCMIsBigEndianKey] = true
        default: throw ErroreConvertitore.nonPossibile("audio in \(r.formato.etichetta)")
        }
        let out = nuovo(origine, r.formato.estensione)
        do {
            let dst = try AVAudioFile(forWriting: out, settings: s, commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
            // a blocchi di un secondo circa: un audio lungo non finisce tutto in memoria
            let blocco: AVAudioFrameCount = AVAudioFrameCount(max(4096, Int(sr)))
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: blocco) else { throw ErroreConvertitore.scrittura("buffer") }
            while src.framePosition < src.length {
                try src.read(into: buf, frameCount: blocco)
                if buf.frameLength == 0 { break }
                try dst.write(from: buf)
            }
        } catch let e as ErroreConvertitore { throw e } catch { throw ErroreConvertitore.scrittura(error.localizedDescription) }
        return out
    }

    // MARK: - PDF

    private static func pdf(_ r: Ricetta, _ origine: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: origine) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        switch r.formato {
        case .pdf:
            let out = nuovo(origine, "pdf")
            var opz: [PDFDocumentWriteOption: Any] = [:]
            if r.comprimi, let f = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")) {
                opz[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = f
            }
            guard doc.write(to: out, withOptions: opz) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
            return [out]
        case .txt:
            let out = nuovo(origine, "txt")
            do { try (doc.string ?? "").write(to: out, atomically: true, encoding: .utf8) } catch { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
            return [out]
        case .png, .jpeg:
            // una pagina = un file; con più pagine "nome pagina 1.png", "nome pagina 2.png"
            var fatti: [URL] = []
            for i in 0..<doc.pageCount {
                guard let p = doc.page(at: i) else { continue }
                let box = p.bounds(for: .mediaBox)
                let lato = max(box.width, box.height) * 2      // 144 punti per pollice: nitida anche su Retina
                let img = p.thumbnail(of: CGSize(width: lato, height: lato), for: .mediaBox)
                guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ErroreConvertitore.lettura("pagina \(i + 1)") }
                let base = doc.pageCount == 1 ? origine
                    : origine.deletingLastPathComponent().appendingPathComponent("\(origine.deletingPathExtension().lastPathComponent) pagina \(i + 1).pdf")
                let out = nuovo(base, r.formato.estensione)
                try scriviImageIO(cg, out, tipo: tipo(r.formato), qualita: r.formato == .jpeg ? 0.85 : nil)
                fatti.append(out)
            }
            return fatti
        default:
            throw ErroreConvertitore.nonPossibile("PDF in \(r.formato.etichetta)")
        }
    }

    // MARK: - documenti

    private static func documento(_ r: Ricetta, _ origine: URL) async throws -> URL {
        let out = nuovo(origine, r.formato.estensione)
        if r.formato == .pdf {
            try await MainActor.run { try documentoInPDF(origine, out) }
            return out
        }
        guard [.docx, .rtf, .txt, .html, .odt].contains(r.formato) else { throw ErroreConvertitore.nonPossibile("documento in \(r.formato.etichetta)") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        p.arguments = ["-convert", r.formato.rawValue, origine.path, "-output", out.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw ErroreConvertitore.scrittura("textutil") }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ErroreConvertitore.scrittura("textutil \(p.terminationStatus)") }
        return out
    }

    /// Impaginato in A4 con margini veri, non una pagina lunga: NSPrintOperation che salva su file.
    private static func documentoInPDF(_ origine: URL, _ out: URL) throws {
        let testo: NSAttributedString
        do { testo = try NSAttributedString(url: origine, options: [:], documentAttributes: nil) } catch { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = out
        let larghezza = info.paperSize.width - info.leftMargin - info.rightMargin
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: larghezza, height: 10))
        tv.textStorage?.setAttributedString(testo)
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.sizeToFit()
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: out.path) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
    }
}

// MARK: - Strumenti (21/10/2026, tenendo ⌥): ritaglio, peso, metadati, taglio, divisione

extension MotoreConvertitore {
    /// Esegue uno strumento e restituisce i file creati. Il taglio di video e audio vuole un intervallo: usa taglia(_:da:a:).
    static func esegui(_ s: Strumento, su origine: URL) async throws -> [URL] {
        guard let fam = Convertitore.famiglia(di: origine) else { throw ErroreConvertitore.nonPossibile(origine.pathExtension) }
        switch (s, fam) {
        case (.ritaglia(let p), .immagine): return [try ritaglia(origine, p)]
        case (.comprimi(let kb), .immagine): return [try comprimiImmagine(origine, kb: kb)]
        case (.comprimi, .pdf): return try pdf(Ricetta(formato: .pdf, comprimi: true), origine)
        case (.comprimi, .video): return [try await video(Ricetta(formato: .mp4, latoMax: 1280), origine)]
        case (.metadati, .immagine): return [try senzaMetadatiImmagine(origine)]
        case (.metadati, .pdf): return [try senzaMetadatiPDF(origine)]
        case (.metadati, .video): return [try await senzaMetadatiVideo(origine)]
        case (.dividi, .pdf): return try dividi(origine)
        default: throw ErroreConvertitore.nonPossibile("\(s.nomi.en) on \(origine.pathExtension)")
        }
    }

    /// "foto.jpg" con l'etichetta "4x5" diventa "foto 4x5.jpg" (o "foto 4x5 2.jpg" se c'è già).
    private static func nuovo(_ origine: URL, etichetta: String, ext: String) -> URL {
        let base = origine.deletingLastPathComponent()
            .appendingPathComponent("\(origine.deletingPathExtension().lastPathComponent) \(etichetta)").appendingPathExtension(ext)
        return FileManager.default.fileExists(atPath: base.path) ? nuovo(base, ext) : base
    }

    /// Il formato d'uscita di un'immagine modificata: lo stesso dell'originale se il Mac lo scrive, altrimenti PNG.
    private static func stessoFormato(_ u: URL) -> (UTType, String) {
        switch Convertitore.formato(di: u) {
        case .jpeg: return (.jpeg, "jpg")
        case .heic: return (.heic, "heic")
        case .tiff: return (.tiff, "tiff")
        case .png: return (.png, "png")
        default: return (.png, "png")
        }
    }

    static func ritaglia(_ origine: URL, _ p: Proporzione) throws -> URL {
        guard let cg = carica(origine, latoMax: nil) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        let r = Strumenti.ritaglio(larghezza: cg.width, altezza: cg.height, p)
        guard let tagliata = cg.cropping(to: r) else { throw ErroreConvertitore.scrittura("ritaglio") }
        let (tipo, ext) = stessoFormato(origine)
        let out = nuovo(origine, etichetta: p.rawValue.replacingOccurrences(of: ":", with: "x"), ext: ext)
        try scriviImageIO(tagliata, out, tipo: tipo, qualita: tipo == .png ? nil : 0.9)
        return out
    }

    /// JPEG sotto il peso chiesto: scende la qualità, poi il lato. Se nemmeno l'ultimo tentativo basta, tiene il più leggero.
    static func comprimiImmagine(_ origine: URL, kb: Int) throws -> URL {
        guard let tutta = carica(origine, latoMax: nil) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        let lato = max(tutta.width, tutta.height)
        var migliore: Data?
        for t in Strumenti.tentativiPeso(latoOriginale: lato) {
            guard let cg = t.lato == lato ? tutta : carica(origine, latoMax: t.lato) else { continue }
            let d = NSMutableData()
            guard let dst = CGImageDestinationCreateWithData(d, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dst, cg, [kCGImageDestinationLossyCompressionQuality: t.qualita] as CFDictionary)
            guard CGImageDestinationFinalize(dst) else { continue }
            if migliore == nil || d.length < migliore!.count { migliore = d as Data }
            if d.length <= kb * 1000 { break }
        }
        guard let dati = migliore else { throw ErroreConvertitore.scrittura("JPEG") }
        let out = nuovo(origine, etichetta: kb >= 1000 ? "\(kb / 1000)MB" : "\(kb)KB", ext: "jpg")
        do { try dati.write(to: out) } catch { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
        return out
    }

    /// Solo i pixel, già ruotati: nessun EXIF, GPS, XMP o IPTC passa nel file nuovo.
    static func senzaMetadatiImmagine(_ origine: URL) throws -> URL {
        guard let cg = carica(origine, latoMax: nil) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        let (tipo, ext) = stessoFormato(origine)
        let out = nuovo(origine, etichetta: T("pulita", "clean"), ext: ext)
        try scriviImageIO(cg, out, tipo: tipo, qualita: tipo == .png ? nil : 0.92)
        return out
    }

    static func senzaMetadatiPDF(_ origine: URL) throws -> URL {
        guard let doc = PDFDocument(url: origine) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        doc.documentAttributes = [:]
        let out = nuovo(origine, etichetta: T("pulito", "clean"), ext: "pdf")
        guard doc.write(to: out) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
        return out
    }

    static func senzaMetadatiVideo(_ origine: URL) async throws -> URL {
        let out = nuovo(origine, etichetta: T("pulito", "clean"), ext: origine.pathExtension.lowercased() == "mov" ? "mov" : "mp4")
        guard let e = AVAssetExportSession(asset: AVURLAsset(url: origine), presetName: AVAssetExportPresetPassthrough) else { throw ErroreConvertitore.nonPossibile("passthrough") }
        e.metadata = []
        e.metadataItemFilter = .forSharing()
        do { try await e.export(to: out, as: out.pathExtension == "mov" ? .mov : .mp4) } catch { throw ErroreConvertitore.scrittura(error.localizedDescription) }
        return out
    }

    /// Una pagina per file: "nome pagina 1.pdf", "nome pagina 2.pdf"...
    static func dividi(_ origine: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: origine) else { throw ErroreConvertitore.lettura(origine.lastPathComponent) }
        var fatti: [URL] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            let d = PDFDocument(); d.insert(p, at: 0)
            let out = nuovo(origine, etichetta: T("pagina \(i + 1)", "page \(i + 1)"), ext: "pdf")
            guard d.write(to: out) else { throw ErroreConvertitore.scrittura(out.lastPathComponent) }
            fatti.append(out)
        }
        return fatti
    }

    /// Solo il pezzo fra da e a (secondi), senza ricodificare: veloce e senza perdita.
    static func taglia(_ origine: URL, da: Double, a: Double) async throws -> URL {
        let audio = Convertitore.famiglia(di: origine) == .audio
        let ext = audio ? "m4a" : (origine.pathExtension.lowercased() == "mov" ? "mov" : "mp4")
        let out = nuovo(origine, etichetta: T("taglio", "trim"), ext: ext)
        let preset = audio ? AVAssetExportPresetAppleM4A : AVAssetExportPresetPassthrough
        guard let e = AVAssetExportSession(asset: AVURLAsset(url: origine), presetName: preset) else { throw ErroreConvertitore.nonPossibile(preset) }
        e.timeRange = CMTimeRange(start: CMTime(seconds: da, preferredTimescale: 600), end: CMTime(seconds: a, preferredTimescale: 600))
        do { try await e.export(to: out, as: audio ? .m4a : (ext == "mov" ? .mov : .mp4)) } catch { throw ErroreConvertitore.scrittura(error.localizedDescription) }
        return out
    }
}
