// Pulsar — MOUSE E TASTIERA (13/11/2026, ondata 4 di VORSSAINT.md). Dal reel dell'app del notch a schede si prende la
// funzione, mai nome o testi. Sette interruttori, tutti spenti di serie:
//   Scorciatoie di testo  (";mail" diventa l'indirizzo intero; {data} e {ora} si riempiono da soli)
//   Super tasto           (Caps Lock diventa ⌃⌥⇧⌘ tenuto premuto: una scorciatoia nuova per ogni lettera)
//   Clic centrale         (tocco con tre dita sul trackpad)
//   Tasti che rimbalzano  (un tasto che ritorna giù entro 45 ms dal rilascio è un doppio colpo e si ignora)
//   Tasti laterali        (i tasti 4 e 5 del mouse vanno indietro e avanti, ⌘[ e ⌘])
//   Scorrimento morbido   (la rotella del mouse scorre a pixel, con un'uscita lenta, invece che a scatti)
//   Fuoco segue il mouse  (la finestra sotto il puntatore passa davanti dopo un attimo fermo)
// Più l'azione "Installa da immagine disco": l'app dentro un .dmg va in Applicazioni e il .dmg nel Cestino.
// Gli eventi che Pulsar scrive da sé portano un segno (eventSourceUserData) e la presa li lascia passare.
import AppKit
import SwiftUI

enum FunzioneInput: String, CaseIterable {
    case snippet, superTasto, clicCentrale, rimbalzo, tastiLaterali, scorrimento, fuoco

    var chiave: Chiave {
        switch self {
        case .snippet: return .inSnippet
        case .superTasto: return .inSuperTasto
        case .clicCentrale: return .inClicCentrale
        case .rimbalzo: return .inRimbalzo
        case .tastiLaterali: return .inTastiLaterali
        case .scorrimento: return .inScorrimento
        case .fuoco: return .inFuoco
        }
    }
    var titolo: String {
        switch self {
        case .snippet: return T("Scorciatoie di testo", "Text snippets")
        case .superTasto: return T("Super tasto", "Super key")
        case .clicCentrale: return T("Clic centrale a tre dita", "Three-finger middle click")
        case .rimbalzo: return T("Tasti che rimbalzano", "Key debounce")
        case .tastiLaterali: return T("Tasti laterali del mouse", "Mouse side buttons")
        case .scorrimento: return T("Scorrimento morbido", "Smooth scrolling")
        case .fuoco: return T("La finestra segue il mouse", "Focus follows mouse")
        }
    }
    var sotto: String {
        switch self {
        case .snippet: return T("Una sigla breve diventa un testo intero", "A short trigger expands into full text")
        case .superTasto: return T("Caps Lock diventa ⌃⌥⇧⌘", "Caps Lock becomes ⌃⌥⇧⌘")
        case .clicCentrale: return T("Un tocco con tre dita sul trackpad", "A three-finger tap on the trackpad")
        case .rimbalzo: return T("Ignora i doppi colpi per sbaglio", "Ignores accidental double presses")
        case .tastiLaterali: return T("Indietro e avanti, come nel browser", "Back and forward, like in the browser")
        case .scorrimento: return T("La rotella scorre fluida", "The wheel scrolls smoothly")
        case .fuoco: return T("Passa davanti dopo un attimo fermo", "Comes forward after a short pause")
        }
    }
    var simbolo: String {
        switch self {
        case .snippet: return "text.badge.plus"
        case .superTasto: return "capslock"
        case .clicCentrale: return "hand.tap"
        case .rimbalzo: return "keyboard.badge.ellipsis"
        case .tastiLaterali: return "computermouse"
        case .scorrimento: return "scroll"
        case .fuoco: return "macwindow.on.rectangle"
        }
    }
    var acceso: Bool {
        get { Impostazioni.object(chiave) as? Bool ?? false }
        nonmutating set {
            Impostazioni.set(newValue, chiave)
            if newValue && !ModuloInput.shared.acceso { ModuloInput.shared.acceso = true } else { ModuloInput.shared.rileggi() }
        }
    }
}

// MARK: - Il modulo

final class ModuloInput: ModuloPulsar {
    static let shared = ModuloInput()
    var id: String { "input" }
    var nome: String { T("Mouse e tastiera", "Mouse and keyboard") }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [.accessibilita] }
    var acceso: Bool {
        get { Impostazioni.object(.inputAcceso) as? Bool ?? false }
        set { Impostazioni.set(newValue, .inputAcceso); RegistroModuli.shared.riapplica() }
    }

    private var attivo = false
    private var tocco = ToccoTreDita()
    private var fuoco: Timer?
    private var chiusura: NSObjectProtocol?

    func avvia() {
        attivo = true
        if chiusura == nil {   // all'uscita di Pulsar Caps Lock torna Caps Lock
            chiusura = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in SuperTasto.togli() }
        }
        rileggi()
    }

    func ferma() {
        attivo = false
        PresaInput.ferma()
        SuperTasto.togli()
        LettoreTrackpad.smetti("clicCentrale")
        fuoco?.invalidate(); fuoco = nil
    }

    func rileggi() {
        guard attivo, acceso else { return }
        let f = FunzioneInput.self
        let serveTap = f.snippet.acceso || f.superTasto.acceso || f.rimbalzo.acceso || f.tastiLaterali.acceso || f.scorrimento.acceso
        if serveTap { PresaInput.avvia() } else { PresaInput.ferma() }
        if f.superTasto.acceso { SuperTasto.metti() } else { SuperTasto.togli() }
        if f.clicCentrale.acceso {
            LettoreTrackpad.ascolta("clicCentrale") { [weak self] dita in
                guard let self else { return }
                if self.tocco.fotogramma(dita, t: ProcessInfo.processInfo.systemUptime) { PresaInput.clicCentrale() }
            }
        } else { LettoreTrackpad.smetti("clicCentrale") }
        if f.fuoco.acceso {
            if fuoco == nil { fuoco = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in FuocoMouse.giro() } }
        } else { fuoco?.invalidate(); fuoco = nil }
    }

    /// Le voci della scheda Mouse e tastiera del pannello della barra.
    static func gruppiPannello(chiudi: @escaping () -> Void, ricarica: @escaping () -> Void) -> [GruppoPannello] {
        let voci = FunzioneInput.allCases.map { f in
            VocePannello(titolo: f.titolo, simbolo: f.simbolo, immagine: nil, acceso: f.acceso, nascosta: false, figli: [],
                         esegui: { f.acceso.toggle(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: ricarica) })
        }
        let azioni = [
            VocePannello(titolo: T("Installa da immagine disco…", "Install from disk image…"), simbolo: "externaldrive.badge.plus", immagine: nil,
                         acceso: nil, nascosta: false, figli: [], esegui: { chiudi(); DispatchQueue.main.async { InstallaDMG.scegli() } }),
            VocePannello(titolo: T("Scorciatoie di testo (\(PresaInput.snippet.count))…", "Text snippets (\(PresaInput.snippet.count))…"),
                         simbolo: "text.badge.plus", immagine: nil, acceso: nil, nascosta: false, figli: [],
                         esegui: { chiudi(); FinestraImpostazioni.shared.apri(.input) }),
        ]
        return [GruppoPannello(titolo: nil, voci: voci), GruppoPannello(titolo: T("Azioni", "Actions"), voci: azioni)]
    }
}

// MARK: - La presa degli eventi (tastiera, tasti del mouse, rotella)

enum PresaInput {
    private static var presa: CFMachPort?
    private static var sorgente: CFRunLoopSource?
    /// Il segno sugli eventi scritti da Pulsar: la presa li lascia passare.
    static let segno: Int64 = 0x5055_4C53

    // scorciatoie di testo
    static var snippet: [Snippet] = caricaSnippet()
    private static var scritto = ""
    static var fileSnippet: URL { Cartelle.dati.appendingPathComponent("snippet.json") }
    static func caricaSnippet() -> [Snippet] { Snippet.leggi(try? Data(contentsOf: fileSnippet)) ?? Snippet.esempi }
    static func salvaSnippet(_ l: [Snippet]) {
        snippet = l
        try? FileManager.default.createDirectory(at: fileSnippet.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(l) { try? d.write(to: fileSnippet, options: .atomic) }
    }

    // tasti che rimbalzano
    private static var su: [Int64: Double] = [:]
    private static var ingoiati = Set<Int64>()
    static let soglia = 0.045

    // scorrimento morbido
    private static var resto: (y: Double, x: Double) = (0, 0)
    private static var morbido: Timer?

    static func avvia() {
        guard presa == nil else { return }
        let tipi: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp, .scrollWheel, .leftMouseDown]
        let maschera = tipi.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let p = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: maschera,
                                        callback: { _, tipo, ev, _ in PresaInput.evento(tipo, ev) }, userInfo: nil) else { return }
        presa = p
        sorgente = CFMachPortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), sorgente, .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
    }

    static func ferma() {
        if let p = presa { CGEvent.tapEnable(tap: p, enable: false) }
        if let s = sorgente { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        presa = nil; sorgente = nil; scritto = ""; su = [:]; ingoiati = []
        morbido?.invalidate(); morbido = nil; resto = (0, 0)
    }

    private static func passa(_ ev: CGEvent) -> Unmanaged<CGEvent>? { Unmanaged.passUnretained(ev) }

    private static func evento(_ tipo: CGEventType, _ ev: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let p = presa { CGEvent.tapEnable(tap: p, enable: true) }
            return passa(ev)
        }
        if ev.getIntegerValueField(.eventSourceUserData) == segno { return passa(ev) }
        let codice = ev.getIntegerValueField(.keyboardEventKeycode)
        let ora = ProcessInfo.processInfo.systemUptime

        switch tipo {
        case .keyDown, .keyUp:
            // Super tasto: Caps Lock è diventato F18 (SuperTasto.metti); tenuto giù aggiunge ⌃⌥⇧⌘ agli altri tasti
            if FunzioneInput.superTasto.acceso {
                if codice == SuperTasto.f18 { SuperTasto.giu = tipo == .keyDown; return nil }
                if SuperTasto.giu { ev.flags = ev.flags.union([.maskCommand, .maskAlternate, .maskControl, .maskShift]); scritto = ""; return passa(ev) }
            }
            if FunzioneInput.rimbalzo.acceso {
                if tipo == .keyUp {
                    su[codice] = ora
                    if ingoiati.remove(codice) != nil { return nil }
                } else if ev.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                          Rimbalzo.ignora(tasto: codice, ora: ora, su: su, soglia: soglia) {
                    ingoiati.insert(codice); return nil
                }
            }
            if tipo == .keyDown, FunzioneInput.snippet.acceso { return scrivi(ev, codice) }
            return passa(ev)
        case .otherMouseDown, .otherMouseUp:
            let tasto = ev.getIntegerValueField(.mouseEventButtonNumber)
            guard FunzioneInput.tastiLaterali.acceso, tasto == 3 || tasto == 4 else { return passa(ev) }
            if tipo == .otherMouseDown { premi(tasto == 3 ? 33 : 30, [.maskCommand]) }     // ⌘[ indietro, ⌘] avanti
            return nil
        case .scrollWheel:
            guard FunzioneInput.scorrimento.acceso, ev.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return passa(ev) }
            // rotella a scatti: un passo diventa 48 pixel distribuiti in circa 200 ms
            resto.y += Double(ev.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 48
            resto.x += Double(ev.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * 48
            avviaMorbido()
            return nil
        case .leftMouseDown:
            scritto = ""; return passa(ev)
        default:
            return passa(ev)
        }
    }

    /// Le scorciatoie di testo: si tiene quello che si scrive (64 caratteri) e quando finisce con una sigla la si cambia.
    private static func scrivi(_ ev: CGEvent, _ codice: Int64) -> Unmanaged<CGEvent>? {
        if !ev.flags.intersection([.maskCommand, .maskControl]).isEmpty { scritto = ""; return passa(ev) }
        switch codice {
        case 51: scritto = String(scritto.dropLast()); return passa(ev)                       // cancella
        case 36, 48, 53, 76, 115, 116, 119, 121, 123, 124, 125, 126: scritto = ""; return passa(ev)   // invio, tab, esc, frecce
        default: break
        }
        var lung = 0, car = [UniChar](repeating: 0, count: 8)
        ev.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &lung, unicodeString: &car)
        guard lung > 0 else { return passa(ev) }
        scritto = String((scritto + String(utf16CodeUnits: car, count: lung)).suffix(64))
        guard let s = Snippet.trova(scritto, in: snippet) else { return passa(ev) }
        scritto = ""
        let testo = Snippet.espandi(s.testo), via = s.sigla.count - 1      // l'ultimo carattere non è ancora arrivato: si ingoia
        DispatchQueue.main.async {
            for _ in 0..<via { premi(51, []) }
            digita(testo)
        }
        return nil
    }

    // MARK: eventi scritti da Pulsar (col segno)

    static func premi(_ codice: CGKeyCode, _ mod: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for giu in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: codice, keyDown: giu) else { continue }
            e.flags = mod; e.setIntegerValueField(.eventSourceUserData, value: segno); e.post(tap: .cgSessionEventTap)
        }
    }

    static func digita(_ testo: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let unita = Array(testo.utf16)
        var i = 0
        while i < unita.count {
            var pezzo = Array(unita[i..<min(i + 18, unita.count)])
            for giu in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: giu) else { continue }
                e.keyboardSetUnicodeString(stringLength: pezzo.count, unicodeString: &pezzo)
                e.setIntegerValueField(.eventSourceUserData, value: segno); e.post(tap: .cgSessionEventTap)
            }
            i += 18
        }
    }

    static func clicCentrale() {
        let dove = CGEvent(source: nil)?.location ?? .zero
        for tipo in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: tipo, mouseCursorPosition: dove, mouseButton: .center) else { continue }
            e.setIntegerValueField(.eventSourceUserData, value: segno); e.post(tap: .cgSessionEventTap)
        }
    }

    private static func avviaMorbido() {
        guard morbido == nil else { return }
        morbido = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
            let py = resto.y * 0.16, px = resto.x * 0.16
            resto.y -= py; resto.x -= px
            if abs(resto.y) < 0.5 && abs(resto.x) < 0.5 { resto = (0, 0); t.invalidate(); morbido = nil }
            guard abs(py) >= 0.5 || abs(px) >= 0.5,
                  let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(py.rounded()), wheel2: Int32(px.rounded()), wheel3: 0) else { return }
            e.setIntegerValueField(.eventSourceUserData, value: segno); e.post(tap: .cgSessionEventTap)
        }
        RunLoop.main.add(morbido!, forMode: .common)
    }
}

// MARK: - Super tasto: Caps Lock diventa F18 con hidutil (pubblico, non serve la password, dura fino al riavvio)

enum SuperTasto {
    static let f18: Int64 = 79
    static var giu = false
    private static let mappa = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
    private static var messo = false

    private static func hidutil(_ a: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil"); p.arguments = a
        let t = Pipe(); p.standardOutput = t; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(decoding: t.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// Se qualcun altro (Karabiner, una mappa a mano) ha già cambiato i tasti, Pulsar non tocca niente e lo dice.
    static func metti() {
        guard !messo else { return }
        let ora = hidutil(["property", "--get", "UserKeyMapping"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ora.isEmpty || ora == "(null)" || ora == "(\n)" || ora == "()" || ora.contains("30064771181") else {
            Utilita.avvisa("super", "capslock", T("Super tasto in pausa", "Super key paused"), T("I tasti sono già mappati da un'altra app", "Keys are already remapped by another app"))
            return
        }
        _ = hidutil(["property", "--set", mappa]); messo = true
    }

    /// All'avvio di Pulsar: una mappa di Pulsar rimasta da una chiusura brusca (crash, pkill) si toglie, se il Super tasto
    /// è spento. Solo se è esattamente la nostra (Caps Lock → F18 e basta): quelle di altri non si toccano.
    static func pulisciSeRimasta() {
        guard !(FunzioneInput.superTasto.acceso && ModuloInput.shared.acceso) else { return }
        let ora = hidutil(["property", "--get", "UserKeyMapping"]).filter { !$0.isWhitespace }
        let nostra = "({HIDKeyboardModifierMappingDst=30064771181;HIDKeyboardModifierMappingSrc=30064771129;})"
        if ora == nostra { _ = hidutil(["property", "--set", #"{"UserKeyMapping":[]}"#]) }
    }

    static func togli() {
        guard messo else { return }
        _ = hidutil(["property", "--set", #"{"UserKeyMapping":[]}"#]); messo = false; giu = false
    }
}

// MARK: - Fuoco segue il mouse

enum FuocoMouse {
    private static var sotto: (pid: pid_t, numero: Int, da: Double)?

    static func giro() {
        guard NSEvent.pressedMouseButtons == 0, NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { sotto = nil; return }
        let m = NSEvent.mouseLocation
        guard let alto = NSScreen.screens.map(\.frame.maxY).max() else { return }
        let p = CGPoint(x: m.x, y: alto - m.y)                     // le finestre di CG contano dall'alto
        let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // la prima finestra (dall'alto della pila) che contiene il puntatore; se è un menu, il Dock o un pannello, niente
        guard let w = lista.first(where: { d in
            guard let b = d[kCGWindowBounds as String] as? [String: Any], let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return r.contains(p) && (d[kCGWindowAlpha as String] as? Double ?? 1) > 0.05
        }), (w[kCGWindowLayer as String] as? Int) == 0,
              let pid = w[kCGWindowOwnerPID as String] as? pid_t, let num = w[kCGWindowNumber as String] as? Int, pid != getpid() else { sotto = nil; return }
        let ora = ProcessInfo.processInfo.systemUptime
        if sotto?.numero != num { sotto = (pid, num, ora); return }
        guard ora - (sotto?.da ?? ora) >= 0.35, NSWorkspace.shared.frontmostApplication?.processIdentifier != pid ||
              !finestraDavanti(pid, num) else { return }
        sotto = (pid, num, .infinity)                                 // una volta sola per finestra
        NSRunningApplication(processIdentifier: pid)?.activate()
        alza(pid, lista.first { ($0[kCGWindowNumber as String] as? Int) == num })
    }

    private static func finestraDavanti(_ pid: pid_t, _ num: Int) -> Bool {
        let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return (l.first { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowNumber as String] as? Int) == num
    }

    /// La finestra giusta di quell'app davanti alle sue sorelle: si cerca con Accessibilità per posizione e misura.
    private static func alza(_ pid: pid_t, _ info: [String: Any]?) {
        guard let b = info?[kCGWindowBounds as String] as? [String: Any], let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return }
        let app = AXUIElementCreateApplication(pid)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success, let finestre = v as? [AXUIElement] else { return }
        for f in finestre {
            var pos: CFTypeRef?, dim: CFTypeRef?
            AXUIElementCopyAttributeValue(f, kAXPositionAttribute as CFString, &pos)
            AXUIElementCopyAttributeValue(f, kAXSizeAttribute as CFString, &dim)
            var pt = CGPoint.zero, sz = CGSize.zero
            if let pos { AXValueGetValue(pos as! AXValue, .cgPoint, &pt) }
            if let dim { AXValueGetValue(dim as! AXValue, .cgSize, &sz) }
            if abs(pt.x - r.minX) < 2 && abs(pt.y - r.minY) < 2 && abs(sz.width - r.width) < 2 {
                AXUIElementPerformAction(f, kAXRaiseAction as CFString); return
            }
        }
    }
}

// MARK: - Installa da immagine disco

enum InstallaDMG {
    static func scegli() {
        let p = NSOpenPanel()
        p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        p.allowedContentTypes = [.diskImage]
        p.prompt = T("Installa", "Install")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        installa(u)
    }

    /// Monta il .dmg senza mostrarlo, copia l'unica app in Applicazioni (una versione vecchia va nel Cestino),
    /// smonta e mette il .dmg nel Cestino. Con zero o più app dentro si ferma e lo dice.
    static func installa(_ dmg: URL, fatto: ((Bool) -> Void)? = nil) {
        Utilita.avvisa("dmg", "externaldrive.badge.plus", T("Installo…", "Installing…"), dmg.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async {
            func fine(_ ok: Bool, _ titolo: String, _ dettaglio: String) {
                DispatchQueue.main.async { Utilita.avvisa("dmg", ok ? "checkmark.circle" : "exclamationmark.triangle", titolo, dettaglio); fatto?(ok) }
            }
            let mon = Process(); mon.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mon.arguments = ["attach", "-nobrowse", "-noautoopen", "-noverify", "-plist", dmg.path]
            let t = Pipe(); mon.standardOutput = t; mon.standardError = Pipe()
            guard (try? mon.run()) != nil else { return fine(false, T("Non montata", "Not mounted"), dmg.lastPathComponent) }
            let dati = t.fileHandleForReading.readDataToEndOfFile(); mon.waitUntilExit()
            guard let pl = try? PropertyListSerialization.propertyList(from: dati, format: nil) as? [String: Any],
                  let punto = (pl["system-entities"] as? [[String: Any]])?.compactMap({ $0["mount-point"] as? String }).first else {
                return fine(false, T("Non montata", "Not mounted"), T("Forse chiede una licenza da accettare", "It may ask to accept a license"))
            }
            defer {
                let s = Process(); s.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); s.arguments = ["detach", punto, "-quiet"]
                try? s.run(); s.waitUntilExit()
            }
            let app = ((try? FileManager.default.contentsOfDirectory(atPath: punto)) ?? []).filter { $0.hasSuffix(".app") }
            guard app.count == 1, let nome = app.first else {
                return fine(false, T("Non installata", "Not installed"), app.isEmpty ? T("Dentro non c'è un'app", "No app inside") : T("Dentro ci sono più app", "More than one app inside"))
            }
            let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(nome)
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == dest.standardizedFileURL }) {
                return fine(false, T("Chiudi prima \(nome)", "Quit \(nome) first"), T("È aperta", "It's open"))
            }
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.trashItem(at: dest, resultingItemURL: nil) }
            let copia = Process(); copia.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            copia.arguments = [(punto as NSString).appendingPathComponent(nome), dest.path]
            guard (try? copia.run()) != nil else { return fine(false, T("Copia non riuscita", "Copy failed"), nome) }
            copia.waitUntilExit()
            guard copia.terminationStatus == 0 else { return fine(false, T("Copia non riuscita", "Copy failed"), nome) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { try? FileManager.default.trashItem(at: dmg, resultingItemURL: nil) }
            fine(true, T("Installata", "Installed"), nome.replacingOccurrences(of: ".app", with: ""))
        }
    }
}
