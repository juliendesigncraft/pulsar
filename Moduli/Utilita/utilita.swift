// Pulsar — UTILITÀ (13/11/2026, ondata 2 di VORSSAINT.md). Le piccole cose che macOS non fa da solo, prese dal reel
// dell'app del notch a schede (si copia la funzione, mai nome o testi):
//   Interruttori (spenti di serie): Chiudi è esci, Taglia e incolla nel Finder, Incolla come testo semplice (⌥⇧⌘V),
//   Pulisci i link copiati, Blocca Musica.
//   Azioni: Espelli tutti i dischi, Muta il microfono, Contagocce, scelta dell'uscita audio e del microfono.
// Un modulo solo (Lite, gratis), acceso dai Pezzi di Pulsar e dal benvenuto; ogni interruttore si cambia nella scheda
// Utilità del pannello e nella pagina Utilità delle Impostazioni. La logica pura è in utilita-logica.swift.
import AppKit
import CoreAudio
import SwiftUI

// MARK: - Le scelte

enum FunzioneUtilita: String, CaseIterable {
    case chiudiEsci, tagliaIncolla, testoSemplice, pulisciLink, bloccaMusica

    var chiave: Chiave {
        switch self {
        case .chiudiEsci: return .utilChiudiEsci
        case .tagliaIncolla: return .utilTagliaIncolla
        case .testoSemplice: return .utilTestoSemplice
        case .pulisciLink: return .utilPulisciLink
        case .bloccaMusica: return .utilBloccaMusica
        }
    }
    var titolo: String {
        switch self {
        case .chiudiEsci: return T("Chiudi è esci", "Quit on close")
        case .tagliaIncolla: return T("Taglia e incolla file", "Cut and paste files")
        case .testoSemplice: return T("Incolla senza stile  ⌥⇧⌘V", "Paste as plain text  ⌥⇧⌘V")
        case .pulisciLink: return T("Pulisci i link copiati", "Clean copied links")
        case .bloccaMusica: return T("Blocca Musica", "Block Music app")
        }
    }
    var sotto: String {
        switch self {
        case .chiudiEsci: return T("Chiusa l'ultima finestra, l'app esce del tutto", "Closing the last window quits the app")
        case .tagliaIncolla: return T("⌘X e ⌘V spostano i file nel Finder", "⌘X and ⌘V move files in Finder")
        case .testoSemplice: return T("Incolla il testo senza caratteri e colori", "Pastes text without fonts or colors")
        case .pulisciLink: return T("Toglie utm, fbclid, igsh e simili", "Removes utm, fbclid, igsh and the like")
        case .bloccaMusica: return T("Musica non si apre più da sola", "Music no longer opens by itself")
        }
    }
    var simbolo: String {
        switch self {
        case .chiudiEsci: return "xmark.square"
        case .tagliaIncolla: return "scissors"
        case .testoSemplice: return "doc.plaintext"
        case .pulisciLink: return "link"
        case .bloccaMusica: return "music.note.slash"
        }
    }
    var acceso: Bool {
        get { Impostazioni.object(chiave) as? Bool ?? false }
        nonmutating set {
            Impostazioni.set(newValue, chiave)
            // accendere una funzione accende anche il modulo: chi la vuole non deve cercare un secondo interruttore
            if newValue && !ModuloUtilita.shared.acceso { ModuloUtilita.shared.acceso = true } else { ModuloUtilita.shared.rileggi() }
        }
    }
}

// MARK: - Il modulo

final class ModuloUtilita: ModuloPulsar {
    static let shared = ModuloUtilita()
    var id: String { "utilita" }
    var nome: String { T("Utilità", "Utilities") }
    var prodotto: Prodotto { .lite }
    /// Taglia e incolla e testo semplice leggono i tasti: serve Accessibilità.
    var permessi: [Permesso] { FunzioneUtilita.tagliaIncolla.acceso || FunzioneUtilita.testoSemplice.acceso ? [.accessibilita] : [] }
    var acceso: Bool {
        get { Impostazioni.object(.utilitaAcceso) as? Bool ?? false }
        set { Impostazioni.set(newValue, .utilitaAcceso); RegistroModuli.shared.riapplica() }
    }

    private var attivo = false
    private var orologio: Timer?
    private var osservatoreApp: NSObjectProtocol?

    func avvia() { attivo = true; rileggi() }

    func ferma() {
        attivo = false
        orologio?.invalidate(); orologio = nil
        TastiUtilita.ferma()
        if let o = osservatoreApp { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        osservatoreApp = nil
        finestre = [:]; inAttesa = []
    }

    /// Una funzione cambiata: si accende o si spegne solo quello che serve.
    func rileggi() {
        guard attivo, acceso else { return }
        let f = FunzioneUtilita.self
        if f.tagliaIncolla.acceso || f.testoSemplice.acceso { TastiUtilita.avvia() } else { TastiUtilita.ferma() }
        if f.chiudiEsci.acceso || f.pulisciLink.acceso {
            if orologio == nil {
                ultimoAppunti = NSPasteboard.general.changeCount
                orologio = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.giro() }
            }
        } else { orologio?.invalidate(); orologio = nil; finestre = [:]; inAttesa = [] }
        if f.bloccaMusica.acceso {
            if osservatoreApp == nil {
                osservatoreApp = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
                    guard FunzioneUtilita.bloccaMusica.acceso,
                          let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.bundleIdentifier == "com.apple.Music" else { return }
                    // un'app che si sta aprendo spesso ignora la prima richiesta: si riprova, e dopo 3 s si chiude per forza
                    app.terminate()
                    for (dopo, forza) in [(0.6, false), (1.5, false), (3.0, true)] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + dopo) { if !app.isTerminated { _ = forza ? app.forceTerminate() : app.terminate() } }
                    }
                    Utilita.avvisa("musica", "music.note.slash", T("Musica bloccata", "Music blocked"), T("Si era aperta da sola", "It opened by itself"))
                }
            }
        } else if let o = osservatoreApp { NSWorkspace.shared.notificationCenter.removeObserver(o); osservatoreApp = nil }
    }

    // MARK: Chiudi è esci e link, un giro ogni 0,6 s

    private var finestre: [Int32: Int] = [:]
    private var inAttesa = Set<Int32>()
    private var ultimoAppunti = 0
    private var scrittoDaMe = -1

    private func giro() {
        if FunzioneUtilita.pulisciLink.acceso { controllaAppunti() }
        if FunzioneUtilita.chiudiEsci.acceso { controllaFinestre() }
    }

    private func controllaAppunti() {
        let pb = NSPasteboard.general
        guard pb.changeCount != ultimoAppunti else { return }
        ultimoAppunti = pb.changeCount
        guard pb.changeCount != scrittoDaMe, let s = pb.string(forType: .string), let pulito = PulisciLink.pulisci(s) else { return }
        pb.clearContents()
        pb.setString(pulito, forType: .string)
        scrittoDaMe = pb.changeCount; ultimoAppunti = pb.changeCount
        Utilita.avvisa("link", "link", T("Link pulito", "Link cleaned"), T("Tolti i pezzi che tracciano", "Tracking bits removed"))
    }

    /// Conta le finestre vere (livello 0, non minuscole) di ogni app normale, su tutte le scrivanie, ridotte comprese.
    /// Non serve Registrazione schermo: si contano, non si leggono i titoli.
    private func controllaFinestre() {
        let app = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let pid = Set(app.map(\.processIdentifier))
        var conta: [Int32: Int] = Dictionary(uniqueKeysWithValues: pid.map { ($0, 0) })
        let lista = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in lista {
            guard let p = w[kCGWindowOwnerPID as String] as? Int32, pid.contains(p),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  (b["Width"] as? Double ?? 0) >= 120, (b["Height"] as? Double ?? 0) >= 80,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            conta[p, default: 0] += 1
        }
        let esclusi = Set(app.filter { Self.esclusi.contains($0.bundleIdentifier ?? "") || $0.processIdentifier == getpid() }.map(\.processIdentifier))
        let nuovi = Set(ChiudiEsci.daChiudere(prima: finestre, ora: conta, esclusi: esclusi))
        // conferma al giro dopo: una finestra che si chiude e se ne apre un'altra (impostazioni, nuovo documento) non chiude l'app
        for p in inAttesa where conta[p] == 0 {
            if let a = app.first(where: { $0.processIdentifier == p }) { a.terminate() }
        }
        inAttesa = nuovi
        // un'app che resta a zero mantiene il suo "aveva finestre" finché non si conferma
        var memoria = conta
        for p in nuovi { memoria[p] = finestre[p] }
        finestre = memoria
    }

    /// Mai chiuse: il Finder (non si chiude), Pulsar, e chi lavora senza finestre di proposito.
    static let esclusi: Set<String> = ["com.apple.finder", "com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver"]
}

// MARK: - Tasti: taglia e incolla nel Finder, incolla come testo semplice

enum TastiUtilita {
    private static var presa: CFMachPort?
    private static var sorgente: CFRunLoopSource?
    /// Dopo un ⌘X nel Finder: il numero degli appunti della copia, per spostare solo quei file.
    static var taglio: Int?

    static func avvia() {
        guard presa == nil else { return }
        let maschera = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let p = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: maschera, callback: { _, tipo, ev, _ in TastiUtilita.tasto(tipo, ev) },
                                        userInfo: nil) else { return }    // senza Accessibilità macOS non la dà: resta spento
        presa = p
        sorgente = CFMachPortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), sorgente, .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
    }

    static func ferma() {
        if let p = presa { CGEvent.tapEnable(tap: p, enable: false) }
        if let s = sorgente { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        presa = nil; sorgente = nil; taglio = nil
    }

    private static let kX: Int64 = 7, kC: Int64 = 8, kV: Int64 = 9

    private static func tasto(_ tipo: CGEventType, _ ev: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let p = presa { CGEvent.tapEnable(tap: p, enable: true) }
            return Unmanaged.passUnretained(ev)
        }
        guard tipo == .keyDown else { return Unmanaged.passUnretained(ev) }
        let codice = ev.getIntegerValueField(.keyboardEventKeycode)
        let mod = ev.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

        // ⌥⇧⌘V ovunque: gli appunti diventano testo semplice e il tasto diventa un ⌘V normale
        if FunzioneUtilita.testoSemplice.acceso, codice == kV, mod == [.maskCommand, .maskShift, .maskAlternate] {
            let pb = NSPasteboard.general
            if let s = pb.string(forType: .string) {
                pb.clearContents(); pb.setString(s, forType: .string)
            }
            ev.flags = ev.flags.subtracting([.maskShift, .maskAlternate])
            return Unmanaged.passUnretained(ev)
        }

        guard FunzioneUtilita.tagliaIncolla.acceso, mod == [.maskCommand],
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder", !staScrivendo() else {
            return Unmanaged.passUnretained(ev)
        }
        if codice == kX {
            // il Finder non taglia i file: si copia, e il ⌘V dopo diventa ⌥⌘V (Sposta qui, che il Finder ha già)
            ev.setIntegerValueField(.keyboardEventKeycode, value: kC)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                taglio = NSPasteboard.general.changeCount
                Utilita.avvisa("taglio", "scissors", T("Pronto da spostare", "Ready to move"), T("⌘V nella cartella giusta", "⌘V in the right folder"))
            }
        } else if codice == kV, let t = taglio {
            if t == NSPasteboard.general.changeCount { ev.flags = ev.flags.union(.maskAlternate) }
            taglio = nil
        }
        return Unmanaged.passUnretained(ev)
    }

    /// Nel Finder si sta scrivendo (rinomina, ricerca, campo di testo): lì ⌘X taglia il testo, come sempre.
    private static func staScrivendo() -> Bool {
        let sistema = AXUIElementCreateSystemWide()
        var el: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedUIElementAttribute as CFString, &el) == .success, let e = el else { return false }
        var ruolo: CFTypeRef?
        AXUIElementCopyAttributeValue(e as! AXUIElement, kAXRoleAttribute as CFString, &ruolo)
        let r = ruolo as? String ?? ""
        return r == kAXTextFieldRole as String || r == kAXTextAreaRole as String || r == "AXSearchField" || r == kAXComboBoxRole as String
    }
}

// MARK: - Azioni

enum Utilita {
    /// Una comparsa nel notch (se l'isola è accesa).
    static func avvisa(_ chiave: String, _ simbolo: String, _ titolo: String, _ dettaglio: String) {
        PeekCenter.shared.post(PeekItem(key: "utilita.\(chiave)", kind: "info", symbol: simbolo, title: titolo, detail: dettaglio, priority: 60, duration: 2.6))
    }

    /// I dischi che si possono espellere (chiavette, dischi esterni, immagini disco montate). Mai il disco di avvio.
    static var dischi: [URL] {
        let chiavi: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: chiavi, options: [.skipHiddenVolumes]) ?? []).filter { u in
            guard let v = try? u.resourceValues(forKeys: Set(chiavi)), v.volumeIsRootFileSystem != true else { return false }
            return v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsInternal == false
        }
    }

    static func espelliDischi() {
        let tutti = dischi
        guard !tutti.isEmpty else { avvisa("dischi", "eject", T("Nessun disco da espellere", "No disks to eject"), ""); return }
        DispatchQueue.global(qos: .userInitiated).async {
            var fatti = 0, rifiuti: [String] = []
            for u in tutti {
                do { try NSWorkspace.shared.unmountAndEjectDevice(at: u); fatti += 1 } catch { rifiuti.append(u.lastPathComponent) }
            }
            DispatchQueue.main.async {
                if rifiuti.isEmpty {
                    avvisa("dischi", "eject", T("Dischi espulsi", "Disks ejected"), T("\(fatti) su \(tutti.count)", "\(fatti) of \(tutti.count)"))
                } else {
                    avvisa("dischi", "exclamationmark.triangle", T("Non espulso: in uso", "Not ejected: in use"), rifiuti.joined(separator: ", "))
                }
            }
        }
    }

    /// Contagocce di macOS: il colore scelto finisce negli appunti come #RRGGBB.
    static func contagocce() {
        NSColorSampler().show { c in
            guard let c = c?.usingColorSpace(.sRGB) else { return }
            let hex = Esadecimale.da(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
            avvisa("colore", "eyedropper", hex, T("Copiato negli appunti", "Copied to clipboard"))
        }
    }

    static func cambiaMicrofono() {
        guard let muto = AudioDispositivi.microfonoMuto() else {
            avvisa("microfono", "mic.slash", T("Microfono non trovato", "No microphone found"), ""); return
        }
        if AudioDispositivi.mutaMicrofono(!muto) {
            avvisa("microfono", muto ? "mic" : "mic.slash", muto ? T("Microfono acceso", "Microphone on") : T("Microfono muto", "Microphone muted"), AudioDispositivi.nome(AudioDispositivi.predefinito(ingresso: true)))
        }
    }

    /// Le voci della scheda Utilità del pannello della barra.
    static func gruppiPannello(chiudi: @escaping () -> Void, ricarica: @escaping () -> Void) -> [GruppoPannello] {
        func dopo(_ f: @escaping () -> Void) -> () -> Void { { f(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: ricarica) } }
        let interruttori = FunzioneUtilita.allCases.map { f in
            VocePannello(titolo: f.titolo, simbolo: f.simbolo, immagine: nil, acceso: f.acceso, nascosta: false, figli: [],
                         esegui: dopo { f.acceso.toggle() })
        }
        let muto = AudioDispositivi.microfonoMuto()
        var azioni = [
            VocePannello(titolo: T("Espelli tutti i dischi", "Eject all disks") + (dischi.isEmpty ? "" : "  (\(dischi.count))"), simbolo: "eject",
                         immagine: nil, acceso: nil, nascosta: false, figli: [], esegui: { chiudi(); espelliDischi() }),
            VocePannello(titolo: T("Contagocce", "Color picker"), simbolo: "eyedropper", immagine: nil, acceso: nil, nascosta: false, figli: [],
                         esegui: { chiudi(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { contagocce() } }),
        ]
        if let m = muto {
            azioni.insert(VocePannello(titolo: T("Muta il microfono", "Mute microphone"), simbolo: "mic.slash", immagine: nil, acceso: m,
                                       nascosta: false, figli: [], esegui: dopo { cambiaMicrofono() }), at: 1)
        }
        func scelta(ingresso: Bool) -> VocePannello {
            let attuale = AudioDispositivi.predefinito(ingresso: ingresso)
            let figli = AudioDispositivi.elenco(ingresso: ingresso).map { d in
                VocePannello(titolo: d.nome, simbolo: nil, immagine: nil, acceso: d.id == attuale, nascosta: false, figli: [],
                             esegui: dopo { AudioDispositivi.imposta(d.id, ingresso: ingresso) })
            }
            return VocePannello(titolo: (ingresso ? T("Microfono: ", "Input: ") : T("Uscita: ", "Output: ")) + AudioDispositivi.nome(attuale),
                                simbolo: ingresso ? "mic" : "speaker.wave.2", immagine: nil, acceso: nil, nascosta: false, figli: figli, esegui: {})
        }
        return [GruppoPannello(titolo: nil, voci: interruttori),
                GruppoPannello(titolo: T("Azioni", "Actions"), voci: azioni),
                GruppoPannello(titolo: T("Audio", "Audio"), voci: [scelta(ingresso: false), scelta(ingresso: true)])]
    }
}

// MARK: - Audio: uscita, microfono, muto (CoreAudio)

enum AudioDispositivi {
    private static func indirizzo(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func elenco(ingresso: Bool) -> [(id: AudioDeviceID, nome: String)] {
        var a = indirizzo(kAudioHardwarePropertyDevices)
        var dim: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &dim) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(dim) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &dim, &ids) == noErr else { return [] }
        return ids.filter { canali($0, ingresso: ingresso) > 0 && !nascosto($0) }.map { ($0, nome($0)) }
    }

    private static func canali(_ id: AudioDeviceID, ingresso: Bool) -> Int {
        var a = indirizzo(kAudioDevicePropertyStreamConfiguration, ingresso ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput)
        var dim: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &dim) == noErr, dim > 0 else { return 0 }
        let p = UnsafeMutableRawPointer.allocate(byteCount: Int(dim), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &dim, p) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(p.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// I dispositivi finti che macOS usa da solo (aggregati nascosti, quelli di Zoom/Teams con "Hidden").
    private static func nascosto(_ id: AudioDeviceID) -> Bool {
        var a = indirizzo(kAudioDevicePropertyIsHidden)
        var v: UInt32 = 0, dim = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &dim, &v) == noErr && v != 0
    }

    static func nome(_ id: AudioDeviceID) -> String {
        var a = indirizzo(kAudioObjectPropertyName)
        var n: Unmanaged<CFString>?
        var dim = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard id != 0, AudioObjectGetPropertyData(id, &a, 0, nil, &dim, &n) == noErr, let s = n?.takeRetainedValue() else { return "—" }
        return s as String
    }

    static func predefinito(ingresso: Bool) -> AudioDeviceID {
        var a = indirizzo(ingresso ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0, dim = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &dim, &id)
        return id
    }

    static func imposta(_ id: AudioDeviceID, ingresso: Bool) {
        var a = indirizzo(ingresso ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var v = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
        if !ingresso {   // i suoni di sistema seguono l'uscita, come fa Impostazioni di Sistema
            var s = indirizzo(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &s, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
        }
    }

    /// nil = nessun microfono o muto non disponibile.
    static func microfonoMuto() -> Bool? {
        let id = predefinito(ingresso: true)
        guard id != 0 else { return nil }
        var a = indirizzo(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(id, &a) else { return volumeMicrofono(id).map { $0 == 0 } }
        var v: UInt32 = 0, dim = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &dim, &v) == noErr else { return nil }
        return v != 0
    }

    /// Prima il muto vero del dispositivo; se non c'è, il volume d'ingresso a zero (e si rimette quello di prima).
    @discardableResult static func mutaMicrofono(_ muto: Bool) -> Bool {
        let id = predefinito(ingresso: true)
        guard id != 0 else { return false }
        var a = indirizzo(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var dove: DarwinBoolean = false
        if AudioObjectHasProperty(id, &a), AudioObjectIsPropertySettable(id, &a, &dove) == noErr, dove.boolValue {
            var v: UInt32 = muto ? 1 : 0
            return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
        }
        if muto { volumePrima = volumeMicrofono(id) ?? 0.75 }
        return impostaVolumeMicrofono(id, muto ? 0 : (volumePrima ?? 0.75))
    }

    private static var volumePrima: Float32?

    private static func volumeMicrofono(_ id: AudioDeviceID) -> Float32? {
        var a = indirizzo(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        var v: Float32 = 0, dim = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &dim, &v) == noErr ? v : nil
    }

    private static func impostaVolumeMicrofono(_ id: AudioDeviceID, _ v: Float32) -> Bool {
        var a = indirizzo(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        var x = v
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &x) == noErr
    }
}
