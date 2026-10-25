// Muta (fase 4, Pulsar Complete): il centro. Converte i file lasciati sulle tessere del notch, mette a posto quelli
// sciolti di Scrivania e Download secondo le regole, dice dove li ha messi e sa annullare l'ultima volta.
// La logica pura è in convertitore-logica.swift, riordino-logica.swift e muta-zona.swift; qui c'è solo il lavoro vero.
// Regole che non si toccano: mai sovrascrivere, mai cancellare (il Cestino si svuota solo a mano), mai entrare nelle
// cartelle, mai toccare i file arrivati prima che il riordino fosse acceso se non lo chiede l'utente.
import Foundation
import AppKit
import AVKit

/// Un'azione fatta, per poterla annullare.
enum AzioneMuta: Equatable {
    case spostato(da: URL, a: URL, regola: String)
    case nelCestino(da: URL, a: URL)
    case creato(URL)
}

final class MutaCentro: ObservableObject {
    static let shared = MutaCentro()

    /// Vero solo mentre il modulo gira (licenza Complete e modulo acceso).
    @Published private(set) var attivo = false

    // MARK: impostazioni

    @Published var riordino: Bool = MutaCentro.flag(.mutaRiordino, personale: true) {
        didSet {
            Impostazioni.set(riordino, .mutaRiordino)
            if riordino && Impostazioni.object(.mutaDal) == nil { Impostazioni.set(Date().timeIntervalSince1970, .mutaDal) }
            riprogramma()
        }
    }
    @Published var scrivania: Bool = MutaCentro.flag(.mutaScrivania, personale: true) { didSet { Impostazioni.set(scrivania, .mutaScrivania) } }
    @Published var download: Bool = MutaCentro.flag(.mutaDownload, personale: true) { didSet { Impostazioni.set(download, .mutaDownload) } }
    @Published var dopoConversione: Bool = MutaCentro.flag(.mutaDopoConversione, personale: true) { didSet { Impostazioni.set(dopoConversione, .mutaDopoConversione) } }
    @Published var attesaMinuti: Int = (Impostazioni.object(.mutaAttesa) as? Int) ?? 2 { didSet { Impostazioni.set(attesaMinuti, .mutaAttesa) } }
    /// Le cartelle scelte dall'utente al posto di quelle predefinite: nome della regola → percorso.
    @Published private(set) var cartelle: [String: String] = (Impostazioni.dictionary(.mutaCartelle) as? [String: String]) ?? [:]

    /// Valore predefinito: nella build dell'autore acceso, nella vendita spento finché il cliente non lo sceglie.
    private static func flag(_ k: Chiave, personale: Bool) -> Bool {
        if let v = Impostazioni.object(k) as? Bool { return v }
        return k == .mutaDopoConversione || k == .mutaScrivania
    }

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Le regole in uso: quelle di base con le cartelle scelte dall'utente al loro posto.
    var regole: [Regola] {
        var r = Riordino.regolePredefinite(home: home)
        for i in r.indices {
            if case .cartella = r[i].destinazione, let p = cartelle[r[i].nome] { r[i].destinazione = .cartella(URL(fileURLWithPath: p)) }
        }
        return r
    }

    func scegliCartella(per regola: String) {
        let pan = NSOpenPanel()
        pan.canChooseDirectories = true
        pan.canChooseFiles = false
        pan.canCreateDirectories = true
        pan.prompt = T("Scegli", "Choose")
        let nome = Self.nomeRegola(regola)   // "Immagini" diventa "Images" in inglese
        pan.message = T("Dove vanno i file di \(nome)", "Where \(nome) files go")
        NSApp.activate(ignoringOtherApps: true)
        guard pan.runModal() == .OK, let u = pan.url else { return }
        cartelle[regola] = u.path
        Impostazioni.set(cartelle, .mutaCartelle)
    }

    /// La cartella o "nel Cestino" per le persone (la traduzione sta già in Riordino.etichetta).
    func etichetta(_ d: Destinazione) -> String { Riordino.etichetta(d, home: home) }

    /// Il nome di una regola per le persone: le quattro delle cartelle standard (versione in vendita) si traducono, le altre restano.
    static func nomeRegola(_ nome: String) -> String {
        switch nome {
        case "Immagini": return T("Immagini", "Images")
        case "Documenti": return T("Documenti", "Documents")
        default: return nome
        }
    }

    // MARK: vita

    private var timer: Timer?
    private let coda = DispatchQueue(label: "pulsar.muta", qos: .utility)
    private var pesi: [String: Int] = [:]           // ultima misura di ogni file: se cambia, il file si sta ancora scrivendo
    @Published private(set) var ultime: [AzioneMuta] = []
    @Published private(set) var ultimoResoconto: String?
    @Published private(set) var ultimaVolta: Date?

    func avvia() { attivo = true; riprogramma() }
    func ferma() { attivo = false; timer?.invalidate(); timer = nil }

    private func riprogramma() {
        timer?.invalidate(); timer = nil
        guard attivo, riordino else { return }
        if Impostazioni.object(.mutaDal) == nil { Impostazioni.set(Date().timeIntervalSince1970, .mutaDal) }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.giro(anchePrima: false) }
        giro(anchePrima: false)
    }

    // MARK: trascinamento sul notch

    /// I file che si stanno trascinando adesso e la proposta per loro (letti all'arrivo sul notch).
    @Published private(set) var trascinati: [URL] = []
    @Published private(set) var proposta = Convertitore.Proposta(scopi: [], formati: [], unisciInPDF: false, ignorati: [])
    @Published var sotto: Bersaglio?
    /// 24/10: chi apre l'email nel notch (l'isola, isola-email.swift); Stow non sa nulla di Mail.
    static var email: (([URL]) -> Void)?

    /// 21/10: tenendo ⌥ durante il trascinamento compaiono gli strumenti (strumenti-logica.swift) al posto degli scopi.
    @Published private(set) var conStrumenti = false
    var strumenti: [Strumento] { Strumenti.per(file: trascinati) }
    var posti: [Posto] { conStrumenti && !strumenti.isEmpty ? MutaZona.disposizione(strumenti: strumenti) : MutaZona.disposizione(proposta) }
    /// Le tessere si mostrano solo se c'è almeno uno scopo, un formato o (con ⌥) uno strumento per i file in mano.
    /// 24/10: con la tessera Email (solo personale) c'è sempre qualcosa da offrire, anche per i file che Stow non converte.
    var mostraTessere: Bool { attivo && ((MutaZona.conEmail && !trascinati.isEmpty) || !proposta.scopi.isEmpty || !proposta.formati.isEmpty || (conStrumenti && !strumenti.isEmpty)) }

    func leggiTrascinamento() {
        let pb = NSPasteboard(name: .drag)
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls != trascinati {
            trascinati = urls
            proposta = Convertitore.proposta(per: urls)
        }
    }

    /// Il mouse sopra il pannello di rilascio, in coordinate del contenuto.
    func puntatore(_ p: CGPoint?) {
        let opz = NSEvent.modifierFlags.contains(.option)
        if opz != conStrumenti { conStrumenti = opz }
        let b = p.flatMap { MutaZona.bersaglio(in: posti, a: $0) }
        if b != sotto { sotto = b }
    }

    func fineTrascinamento() { sotto = nil; conStrumenti = false }


    /// Chiamata quando un file viene lasciato sull'isola. Vero se lo prende Muta; falso = comportamento di prima.
    func prendi(_ urls: [URL]) -> Bool {
        defer { sotto = nil }
        guard attivo, let b = sotto, b != .altrove, !urls.isEmpty else { return false }
        if b == .email { Self.email?(urls); return true }
        if case .strumento(let st) = b { usa(st, su: urls) } else { esegui(b, su: urls) }
        return true
    }

    // MARK: conversione

    func esegui(_ b: Bersaglio, su urls: [URL]) {
        let quanti = urls.count
        PeekCenter.shared.post(PeekItem(key: "muta", kind: "muta", symbol: "arrow.triangle.2.circlepath",
                                        title: T("Converto \(quanti)", "Converting \(quanti)"), detail: "", priority: 70, duration: 30))
        let regole = self.regole, segui = riordino && dopoConversione
        Task.detached(priority: .userInitiated) { [weak self] in
            var creati: [URL] = []
            var falliti = 0
            if b == .unisci {
                do { creati.append(try MotoreConvertitore.unisciInPDF(urls)) } catch { falliti = urls.count }
            } else {
                for u in urls {
                    guard let r = Self.ricetta(b, per: u) else { falliti += 1; continue }
                    do { creati += try await MotoreConvertitore.esegui(r, su: u) } catch { falliti += 1 }
                }
            }
            // i file nuovi seguono le regole del riordino, se l'utente lo vuole; altrimenti restano accanto all'originale
            var azioni: [AzioneMuta] = []
            var mete: [Destinazione] = []
            for c in creati {
                if segui, let (r, d) = Riordino.piano(per: c, regole: regole), let a = Self.metti(c, in: d, regola: r.nome) {
                    azioni.append(a); mete.append(d)
                } else {
                    azioni.append(.creato(c))
                }
            }
            let titolo = Convertitore.riepilogo(fatti: creati.count, falliti: falliti)
            let (azioni2, mete2, creati2) = (azioni, mete, creati)     // copie fisse da passare al filo principale
            await MainActor.run { [weak self] in
                guard let self else { return }
                let dove = mete2.isEmpty ? T("accanto all'originale", "next to the original")
                    : Riordino.resoconto(mete2, home: self.home).components(separatedBy: ": ").last ?? ""
                self.registra(azioni2, resoconto: titolo + ", " + dove, mostra: creati2.first.map { [$0] } ?? [])
            }
        }
    }

    // MARK: strumenti (⌥)

    /// Esegue uno strumento sui file lasciati. Il taglio apre prima la finestra di taglio di macOS (AVPlayerView).
    func usa(_ st: Strumento, su urls: [URL]) {
        PeekCenter.shared.post(PeekItem(key: "muta", kind: "muta", symbol: "arrow.triangle.2.circlepath",
                                        title: T(st.nomi.it, st.nomi.en), detail: "", priority: 70, duration: 30))
        Task { @MainActor [weak self] in
            guard let self else { return }
            var creati: [URL] = [], falliti = 0
            if st == .taglia, let u = urls.first {
                guard let (da, a) = await Self.chiediTaglio(u) else {
                    PeekCenter.shared.post(PeekItem(key: "muta", kind: "info", symbol: "scissors", title: T("Taglio annullato", "Trim cancelled"), detail: "", priority: 70, duration: 2))
                    return
                }
                do { creati.append(try await MotoreConvertitore.taglia(u, da: da, a: a)) } catch { falliti += 1 }
            } else {
                for u in urls {
                    do { creati += try await MotoreConvertitore.esegui(st, su: u) } catch { falliti += 1 }
                }
            }
            self.registra(creati.map { .creato($0) }, resoconto: Convertitore.riepilogo(fatti: creati.count, falliti: falliti) + ", " + T("accanto all'originale", "next to the original"), mostra: creati)
        }
    }

    /// La finestra di taglio di macOS, la stessa di QuickTime: maniglie gialle, Taglia o Annulla. Restituisce l'intervallo in secondi.
    @MainActor static func chiediTaglio(_ u: URL) async -> (Double, Double)? {
        let item = AVPlayerItem(url: u)
        let v = AVPlayerView(); v.player = AVPlayer(playerItem: item); v.controlsStyle = .inline
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = T("Taglia \(u.lastPathComponent)", "Trim \(u.lastPathComponent)")
        w.contentView = v; w.center()
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
        defer { w.close() }
        for _ in 0..<40 where !v.canBeginTrimming { try? await Task.sleep(nanoseconds: 50_000_000) }   // al massimo 2 s per caricare
        guard v.canBeginTrimming else { return nil }
        let esito = await withCheckedContinuation { (c: CheckedContinuation<AVPlayerViewTrimResult, Never>) in v.beginTrimming { c.resume(returning: $0) } }
        guard esito == .okButton else { return nil }
        let da = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime.seconds : 0
        let fine = item.forwardPlaybackEndTime.isNumeric ? item.forwardPlaybackEndTime.seconds : item.duration.seconds
        return fine > da ? (da, fine) : nil
    }

    private static func ricetta(_ b: Bersaglio, per u: URL) -> Ricetta? {
        switch b {
        case .scopo(let s): return Convertitore.famiglia(di: u).flatMap { Convertitore.ricetta(s, per: $0) }
        case .formato(let f): return Convertitore.uscite(per: u).contains(f) ? Ricetta(formato: f) : nil
        default: return nil
        }
    }

    // MARK: riordino

    /// Un giro sulle cartelle guardate. `anchePrima`: anche i file arrivati prima che il riordino fosse acceso (solo su richiesta).
    func giro(anchePrima: Bool) {
        guard attivo else { return }
        var cartelle: [URL] = []
        if scrivania { cartelle.append(home.appendingPathComponent("Desktop")) }
        if download { cartelle.append(home.appendingPathComponent("Downloads")) }
        let regole = self.regole
        let attesa = TimeInterval(max(1, attesaMinuti) * 60)
        let dal = anchePrima ? Date.distantPast : Date(timeIntervalSince1970: (Impostazioni.object(.mutaDal) as? Double) ?? Date().timeIntervalSince1970)
        coda.async { [weak self] in
            guard let self else { return }
            let chiavi: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isAliasFileKey, .isSymbolicLinkKey, .fileSizeKey,
                                            .contentModificationDateKey, .addedToDirectoryDateKey]
            var azioni: [AzioneMuta] = []
            var mete: [Destinazione] = []
            var visti: [String: Int] = [:]
            let ora = Date()
            for c in cartelle {
                let files = (try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: chiavi, options: [.skipsHiddenFiles])) ?? []
                for f in files {
                    guard let v = try? f.resourceValues(forKeys: Set(chiavi)) else { continue }
                    let peso = v.fileSize ?? -1
                    visti[f.path] = peso
                    if v.isPackage == true || v.isAliasFile == true || v.isSymbolicLink == true { continue }
                    let arrivato = max(v.addedToDirectoryDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
                    if arrivato < dal { continue }
                    guard let (r, d) = Riordino.piano(per: f, regole: regole) else { continue }
                    let cambia = self.pesi[f.path] != peso
                    guard Riordino.pronto(nome: f.lastPathComponent, cartella: v.isDirectory == true, modificato: arrivato, ora: ora,
                                          attesa: r.attesa ?? attesa, staCambiando: cambia) else { continue }
                    if let a = Self.metti(f, in: d, regola: r.nome) { azioni.append(a); mete.append(d) }
                }
            }
            self.pesi = visti
            guard !azioni.isEmpty else { return }
            let testo = Riordino.resoconto(mete, home: self.home)
            DispatchQueue.main.async { self.registra(azioni, resoconto: testo, mostra: []) }
        }
    }

    /// Sposta un file nella sua meta (o nel Cestino). Mai sovrascrive: il nome libero lo sceglie Convertitore.uscita.
    private static func metti(_ f: URL, in d: Destinazione, regola: String) -> AzioneMuta? {
        let fm = FileManager.default
        switch d {
        case .cestino:
            var dove: NSURL?
            guard (try? fm.trashItem(at: f, resultingItemURL: &dove)) != nil, let a = dove as URL? else { return nil }
            return .nelCestino(da: f, a: a)
        case .cartella(let c):
            try? fm.createDirectory(at: c, withIntermediateDirectories: true)
            let segnaposto = c.appendingPathComponent(f.lastPathComponent)
            let meta = Convertitore.uscita(per: segnaposto, estensione: f.pathExtension) { fm.fileExists(atPath: $0.path) }
            let esatta = fm.fileExists(atPath: segnaposto.path) ? meta : segnaposto
            guard (try? fm.moveItem(at: f, to: esatta)) != nil else { return nil }
            return .spostato(da: f, a: esatta, regola: regola)
        }
    }

    // MARK: resoconto e annulla

    private func registra(_ azioni: [AzioneMuta], resoconto: String, mostra: [URL]) {
        ultime = azioni
        ultimoResoconto = resoconto
        ultimaVolta = Date()
        scriviRegistro(azioni)
        let (titolo, dettaglio) = Self.dividi(resoconto)
        PeekCenter.shared.post(PeekItem(key: "muta", kind: "muta", symbol: "folder.fill", title: titolo, detail: dettaglio, priority: 70, duration: 8))
    }

    /// "3 file a posto: 2 in Design › Mockups, 1 in Books" → ("3 file a posto", "2 in Design › Mockups, 1 in Books")
    static func dividi(_ s: String) -> (String, String) {
        if let r = s.range(of: ": ") { return (String(s[..<r.lowerBound]), String(s[r.upperBound...])) }
        if let r = s.range(of: ", ") { return (String(s[..<r.lowerBound]), String(s[r.upperBound...])) }
        return (s, "")
    }

    /// Rimette tutto com'era: i file spostati tornano, quelli nel Cestino escono, quelli creati vanno nel Cestino.
    func annulla() {
        let fm = FileManager.default
        let spostati: [Spostamento] = ultime.compactMap {
            switch $0 {
            case .spostato(let da, let a, let r): return Spostamento(da: da, a: a, regola: r)
            case .nelCestino(let da, let a): return Spostamento(da: da, a: a, regola: "Cestino")
            case .creato: return nil
            }
        }
        var tornati = 0
        for m in Riordino.annulla(spostati, esiste: { fm.fileExists(atPath: $0.path) }) where (try? fm.moveItem(at: m.da, to: m.a)) != nil { tornati += 1 }
        for case .creato(let u) in ultime where (try? fm.trashItem(at: u, resultingItemURL: nil)) != nil { tornati += 1 }
        ultime = []
        ultimoResoconto = nil
        PeekCenter.shared.post(PeekItem(key: "muta", kind: "info", symbol: "arrow.uturn.backward", title: T("Annullato", "Undone"),
                                        detail: T("\(tornati) file come prima", "\(tornati) files as before"), priority: 70, duration: 3))
    }

    /// Apre nel Finder i file dell'ultima volta (selezionati).
    func mostra() {
        let urls: [URL] = ultime.compactMap {
            switch $0 { case .spostato(_, let a, _): return a; case .creato(let u): return u; case .nelCestino(_, let a): return a }
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Ogni spostamento in un registro leggibile: Application Support/<Pulsar>/muta.tsv (data, cosa, da, a).
    private func scriviRegistro(_ azioni: [AzioneMuta]) {
        let url = Cartelle.dati.appendingPathComponent("muta.tsv")
        let ora = ISO8601DateFormatter().string(from: Date())
        let righe = azioni.map { a -> String in
            switch a {
            case .spostato(let da, let to, let r): return "\(ora)\tspostato (\(r))\t\(da.path)\t\(to.path)"
            case .nelCestino(let da, let to): return "\(ora)\tcestino\t\(da.path)\t\(to.path)"
            case .creato(let u): return "\(ora)\tcreato\t\t\(u.path)"
            }
        }.joined(separator: "\n") + "\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(righe.utf8)); try? h.close() }
        else { try? Data(righe.utf8).write(to: url) }
    }
}

// MARK: - Il modulo nel registro: vale solo con Pulsar Complete (decisione dell'autore del 19/10)

final class MutaModule: ModuloPulsar {
    var id: String { "muta" }
    var nome: String { "Stow" }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [] }        // Scrivania e Download: macOS chiede da solo al primo accesso
    var acceso: Bool {
        get { Impostazioni.object(.mutaAcceso) as? Bool ?? true }
        set { Impostazioni.set(newValue, .mutaAcceso); RegistroModuli.shared.riapplica() }
    }
    func avvia() { MutaCentro.shared.avvia() }
    func ferma() { MutaCentro.shared.ferma() }
}
