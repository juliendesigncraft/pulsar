// Rowline — SCORCIATOIE e GESTO (14/10/2026).
// Le scorciatoie sono globali (Carbon RegisterEventHotKey: non chiedono permessi) e tutte cambiabili dal pannello.
// Di serie usano ⌃⌥⌘: ⌃⌥, ⌃⌘ e ⌃⇧ tenuti premuti sono già l'Anima di Pulsar, e ⌥⌘← → cambiano scheda in Chrome.
// Il gesto: tenendo ⌥ e scorrendo in orizzontale con due dita sul trackpad la fila scorre di una finestra.

import AppKit
import Carbon.HIToolbox

struct Combo: Codable, Equatable {
    var tasto: UInt32
    var mod: UInt32      // modificatori Carbon (cmdKey, optionKey, controlKey, shiftKey)

    static let iper = UInt32(controlKey | optionKey | cmdKey)

    var testo: String {
        var s = ""
        if mod & UInt32(controlKey) != 0 { s += "⌃" }
        if mod & UInt32(optionKey) != 0 { s += "⌥" }
        if mod & UInt32(shiftKey) != 0 { s += "⇧" }
        if mod & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Combo.nome(tasto)
    }

    /// Per i menu di macOS: il tasto e i modificatori come li disegna il sistema, allineati a destra.
    var equivalente: (String, NSEvent.ModifierFlags)? {
        var f: NSEvent.ModifierFlags = []
        if mod & UInt32(controlKey) != 0 { f.insert(.control) }
        if mod & UInt32(optionKey) != 0 { f.insert(.option) }
        if mod & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if mod & UInt32(cmdKey) != 0 { f.insert(.command) }
        let frecce: [Int: Int] = [kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
                                  kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey]
        if let u = frecce[Int(tasto)], let sc = UnicodeScalar(u) { return (String(Character(sc)), f) }
        let n = Combo.nome(tasto)
        return n.count == 1 ? (n.lowercased(), f) : nil
    }

    static func da(_ e: NSEvent) -> Combo {
        var m: UInt32 = 0
        let f = e.modifierFlags
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return Combo(tasto: UInt32(e.keyCode), mod: m)
    }

    static func nome(_ k: UInt32) -> String {
        let speciali: [Int: String] = [kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                                       kVK_Space: "␣", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
                                       kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"]
        if let s = speciali[Int(k)] { return s }
        let lettere: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G",
            kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N",
            kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U",
            kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Backslash: "\\"]
        return lettere[Int(k)] ?? "#\(k)"
    }
}

enum Azione: String, CaseIterable, Identifiable {
    case precedente, successiva, su, giu, spostaSx, spostaDx, meta, dueTerzi, intera, cicla, allarga, stringi, centra,
         impila, impilaDx, staccaSx, stacca, galleggia, griglia, altroSchermo, postazione1, postazione2, postazione3, pannello, pausa
    var id: String { rawValue }

    var titolo: String {
        switch self {
        case .precedente: return T("Finestra a sinistra", "Window on the left")
        case .successiva: return T("Finestra a destra", "Window on the right")
        case .su: return T("Su nella pila", "Up in the stack")
        case .giu: return T("Giù nella pila", "Down in the stack")
        case .spostaSx: return T("Sposta a sinistra", "Move left")
        case .spostaDx: return T("Sposta a destra", "Move right")
        case .meta: return T("Metà schermo", "Half screen")
        case .dueTerzi: return T("Due terzi", "Two thirds")
        case .intera: return T("Schermo intero", "Full width")
        case .cicla: return T("Cambia larghezza", "Change width")
        case .allarga: return T("Più larga", "Wider")
        case .stringi: return T("Più stretta", "Narrower")
        case .centra: return T("Al centro", "Centre")
        case .impila: return T("Impila a sinistra", "Stack left")
        case .impilaDx: return T("Impila a destra", "Stack right")
        case .staccaSx: return T("Stacca a sinistra", "Pop out left")
        case .stacca: return T("Stacca a destra", "Pop out right")
        case .galleggia: return T("Galleggia o rimetti in fila", "Float or put back")
        case .griglia: return T("Griglia", "Grid")
        case .altroSchermo: return T("All'altro schermo", "To the other display")
        case .pannello: return T("Apri Rowline", "Open Rowline")
        case .pausa: return T("Accendi o spegni", "Turn on or off")
        case .postazione1, .postazione2, .postazione3:
            let n = self == .postazione1 ? 0 : self == .postazione2 ? 1 : 2
            return Motore.shared.postazioni[safe: n].map { T("Postazione: ", "Workspace: ") + $0.nome } ?? T("Postazione \(n + 1)", "Workspace \(n + 1)")
        }
    }

    var simbolo: String {
        switch self {
        case .precedente: "arrow.left"
        case .successiva: "arrow.right"
        case .su: "arrow.up"
        case .giu: "arrow.down"
        case .spostaSx: "arrow.left.to.line"
        case .spostaDx: "arrow.right.to.line"
        case .meta: "rectangle.split.2x1"
        case .dueTerzi: "rectangle.leadinghalf.inset.filled"
        case .intera: "rectangle.inset.filled"
        case .cicla: "arrow.left.and.right"
        case .allarga: "arrow.left.and.right.square"
        case .stringi: "arrow.right.and.line.vertical.and.arrow.left"
        case .centra: "align.horizontal.center"
        case .impila: "rectangle.split.1x2"
        case .impilaDx: "rectangle.split.1x2.fill"
        case .staccaSx: "rectangle.portrait.and.arrow.forward"
        case .stacca: "rectangle.portrait.and.arrow.right"
        case .galleggia: "macwindow.on.rectangle"
        case .griglia: "square.grid.3x3"
        case .altroSchermo: "display.2"
        case .postazione1, .postazione2, .postazione3: "square.stack"
        case .pannello: "rectangle.split.3x1"
        case .pausa: "power"
        }
    }

    var predefinita: Combo {
        let i = Combo.iper, s = Combo.iper | UInt32(shiftKey)
        switch self {
        case .precedente: return Combo(tasto: UInt32(kVK_LeftArrow), mod: i)
        case .successiva: return Combo(tasto: UInt32(kVK_RightArrow), mod: i)
        case .su: return Combo(tasto: UInt32(kVK_UpArrow), mod: i)
        case .giu: return Combo(tasto: UInt32(kVK_DownArrow), mod: i)
        case .spostaSx: return Combo(tasto: UInt32(kVK_LeftArrow), mod: s)
        case .spostaDx: return Combo(tasto: UInt32(kVK_RightArrow), mod: s)
        case .meta: return Combo(tasto: UInt32(kVK_ANSI_1), mod: i)
        case .dueTerzi: return Combo(tasto: UInt32(kVK_ANSI_2), mod: i)
        case .intera: return Combo(tasto: UInt32(kVK_ANSI_3), mod: i)
        case .cicla: return Combo(tasto: UInt32(kVK_ANSI_R), mod: i)
        case .allarga: return Combo(tasto: UInt32(kVK_ANSI_Equal), mod: i)
        case .stringi: return Combo(tasto: UInt32(kVK_ANSI_Minus), mod: i)
        case .centra: return Combo(tasto: UInt32(kVK_ANSI_C), mod: i)
        case .impila: return Combo(tasto: UInt32(kVK_ANSI_LeftBracket), mod: i)
        case .impilaDx: return Combo(tasto: UInt32(kVK_ANSI_RightBracket), mod: i)
        case .staccaSx: return Combo(tasto: UInt32(kVK_ANSI_LeftBracket), mod: s)
        case .stacca: return Combo(tasto: UInt32(kVK_ANSI_RightBracket), mod: s)
        case .galleggia: return Combo(tasto: UInt32(kVK_ANSI_T), mod: i)
        case .griglia: return Combo(tasto: UInt32(kVK_ANSI_G), mod: i)
        case .altroSchermo: return Combo(tasto: UInt32(kVK_ANSI_N), mod: i)
        case .postazione1: return Combo(tasto: UInt32(kVK_ANSI_4), mod: i)
        case .postazione2: return Combo(tasto: UInt32(kVK_ANSI_5), mod: i)
        case .postazione3: return Combo(tasto: UInt32(kVK_ANSI_6), mod: i)
        case .pannello: return Combo(tasto: UInt32(kVK_ANSI_F), mod: i)
        case .pausa: return Combo(tasto: UInt32(kVK_ANSI_P), mod: i)
        }
    }

    @MainActor func esegui() {
        Foglio.shared.annulla()
        TastiVisti.shared.mostra(self)
        let m = Motore.shared
        switch self {
        case .precedente: m.vai(-1)
        case .successiva: m.vai(1)
        case .su: m.suGiu(-1)
        case .giu: m.suGiu(1)
        case .spostaSx: m.sposta(-1)
        case .spostaDx: m.sposta(1)
        case .meta: m.larghezza(0.5)
        case .dueTerzi: m.larghezza(2.0 / 3)
        case .intera: m.larghezza(1)
        case .cicla: m.ciclaLarghezza()
        case .allarga: m.allarga(1)
        case .stringi: m.allarga(-1)
        case .centra: m.centra()
        case .impila: m.impila()
        case .impilaDx: m.impilaDestra()
        case .staccaSx: m.staccaSinistra()
        case .stacca: m.stacca()
        case .galleggia: m.galleggia()
        case .griglia: Reticolo.shared.apri()
        case .altroSchermo: m.altroSchermo()
        case .postazione1, .postazione2, .postazione3:
            let n = self == .postazione1 ? 0 : self == .postazione2 ? 1 : 2
            if let p = m.postazioni[safe: n] { m.applica(p) }
        case .pannello: Pannello.shared.alterna()
        case .pausa: m.acceso.toggle()
        }
    }
}

final class Tasti: ObservableObject {
    static let shared = Tasti()

    @Published private(set) var combo: [Azione: Combo] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installato = false

    init() {
        let salvate = (Archivio.d.data(forKey: "tasti")).flatMap { try? JSONDecoder().decode([String: Combo].self, from: $0) } ?? [:]
        for a in Azione.allCases { combo[a] = salvate[a.rawValue] ?? a.predefinita }
    }

    func cambia(_ a: Azione, _ c: Combo) {
        // la stessa combinazione non può fare due cose: chi l'aveva torna alla sua di serie (o resta senza, se coincide)
        for (b, d) in combo where b != a && d == c { combo[b] = b.predefinita == c ? Combo(tasto: 0, mod: 0) : b.predefinita }
        combo[a] = c
        salva(); registra()
    }

    func ripristina() { for a in Azione.allCases { combo[a] = a.predefinita }; salva(); registra() }

    private func salva() {
        let d = Dictionary(uniqueKeysWithValues: combo.map { ($0.key.rawValue, $0.value) })
        Archivio.d.set(try? JSONEncoder().encode(d), forKey: "tasti")
    }

    func registra() {
        if !installato {
            installato = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
                var hk = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                // 19/10, dentro Pulsar: le scorciatoie degli altri (Griglia, Pulsar) passano oltre
                guard hk.signature == OSType(0x46494C41) else { return OSStatus(eventNotHandledErr) }
                let tutte = Azione.allCases
                if Int(hk.id) < tutte.count { let a = tutte[Int(hk.id)]; DispatchQueue.main.async { a.esegui() } }
                return noErr
            }, 1, &spec, nil, nil)
        }
        sospendi()
        for (i, a) in Azione.allCases.enumerated() {
            guard let c = combo[a], c.mod != 0 else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x46494C41), id: UInt32(i))   // 'FILA'
            if RegisterEventHotKey(c.tasto, c.mod, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
        }
    }

    /// Mentre si registra una combinazione nuova le scorciatoie tacciono, se no scatterebbero.
    func sospendi() { refs.forEach { UnregisterEventHotKey($0) }; refs = [] }
}

// MARK: - Il gesto sul trackpad

/// Come TileMyMac: tre o quattro dita in orizzontale fanno scorrere la fila. Le dita si leggono da MultitouchSupport,
/// il framework del trackpad che macOS usa per i suoi gesti (privato: si apre a mano, e se manca il gesto tace).
/// macOS usa già quattro dita per cambiare Scrivania sul Mac dell'autore (TrackpadFourFingerHorizSwipeGesture = 2):
/// di serie Fila prende le dita che il sistema lascia libere. In alternativa ⌥ + due dita.
enum ModoGesto: String, CaseIterable {
    case tre, quattro, opzione, spento
    var titolo: String { ["tre": T("Tre dita", "Three fingers"), "quattro": T("Quattro dita", "Four fingers"), "opzione": T("⌥ e due dita", "⌥ and two fingers"), "spento": T("Spento", "Off")][rawValue]! }
    var dita: Int { self == .tre ? 3 : self == .quattro ? 4 : 0 }

    /// Le dita che macOS usa già per scorrere fra le Scrivanie (0 se nessuna).
    static func usateDalSistema(_ n: Int) -> Bool {
        let chiave = n == 3 ? "TrackpadThreeFingerHorizSwipeGesture" : "TrackpadFourFingerHorizSwipeGesture"
        for dom in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            if let v = UserDefaults(suiteName: dom)?.object(forKey: chiave) as? Int, v != 0 { return true }
        }
        return false
    }
    static var predefinito: ModoGesto { !usateDalSistema(3) ? .tre : !usateDalSistema(4) ? .quattro : .opzione }
}

final class Gesto: ObservableObject {
    static let shared = Gesto()
    private var tap: CFMachPort?
    private var accumulo: CGFloat = 0
    private var ultimo = Date.distantPast

    @Published var modo: ModoGesto = ModoGesto(rawValue: Archivio.d.string(forKey: "gestoModo") ?? "") ?? ModoGesto.predefinito {
        didSet { Archivio.d.set(modo.rawValue, forKey: "gestoModo"); ferma(); avvia() }
    }
    @Published var inverti: Bool = Archivio.d.bool(forKey: "gestoInverti") {
        didSet { Archivio.d.set(inverti, forKey: "gestoInverti") }
    }

    func avvia() {
        switch modo {
        case .tre, .quattro: Dita.shared.avvia()
        case .opzione: avviaOpzione()
        case .spento: break
        }
    }

    func ferma() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
    }

    /// Un passo della fila (dal trackpad, da qualunque modo).
    func passo(_ dita: CGFloat) {
        guard Motore.shared.acceso, Date().timeIntervalSince(ultimo) > 0.18 else { return }
        ultimo = Date()
        var verso = dita < 0 ? 1 : -1          // dita verso sinistra: la fila va avanti, come scorrere una pagina
        if inverti { verso = -verso }
        DispatchQueue.main.async { Foglio.shared.annulla(); Motore.shared.vai(verso) }
    }

    private func avviaOpzione() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, tipo, ev, _ in
            if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
                if let t = Gesto.shared.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(ev)
            }
            return Gesto.shared.scorri(ev) ? nil : Unmanaged.passUnretained(ev)
        }, userInfo: nil)
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// true = l'evento è nostro e non arriva all'app sotto.
    private func scorri(_ ev: CGEvent) -> Bool {
        let f = ev.flags
        guard f.contains(.maskAlternate), !f.contains(.maskCommand), !f.contains(.maskControl), Motore.shared.acceso else { accumulo = 0; return false }
        let dx = CGFloat(ev.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let dy = CGFloat(ev.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        if ev.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return abs(dx) > abs(dy) }   // l'inerzia non conta
        if ev.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 { accumulo = 0 }                 // dita appena appoggiate
        guard abs(dx) > abs(dy) else { return false }
        accumulo += dx
        if abs(accumulo) > 90 { passo(accumulo); accumulo = 0 }
        return true
    }
}

/// Le dita sul trackpad, lette da MultitouchSupport. Ogni contatto è una struttura di 96 byte:
/// a +20 lo stato (4 = dito appoggiato), a +32 la x normalizzata (0 sinistra, 1 destra).
final class Dita {
    static let shared = Dita()
    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private var avviato = false
    fileprivate var partenza: Float?          // x media quando sono arrivate le dita giuste
    fileprivate var scattato = 0

    func avvia() {
        guard !avviato, let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let lista = dlsym(h, "MTDeviceCreateList"), let registra = dlsym(h, "MTRegisterContactFrameCallback"),
              let parti = dlsym(h, "MTDeviceStart") else { return }
        avviato = true
        typealias Lista = @convention(c) () -> Unmanaged<CFArray>
        typealias Registra = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
        typealias Parti = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        let devs = unsafeBitCast(lista, to: Lista.self)().takeUnretainedValue() as [AnyObject]
        let cb: Callback = { _, dati, n, _, _ in
            Dita.shared.frame(dati, Int(n))
            return 0
        }
        for d in devs {
            let p = Unmanaged.passUnretained(d).toOpaque()
            unsafeBitCast(registra, to: Registra.self)(p, cb)
            unsafeBitCast(parti, to: Parti.self)(p, 0)
        }
    }

    /// Arriva dal filo del trackpad, decine di volte al secondo.
    fileprivate func frame(_ dati: UnsafeMutableRawPointer?, _ n: Int) {
        let voluto = Gesto.shared.modo.dita
        guard voluto > 0, let dati else { return }
        var xs: [Float] = []
        for i in 0..<n {
            let c = dati + i * 96
            if c.load(fromByteOffset: 20, as: Int32.self) == 4 { xs.append(c.load(fromByteOffset: 32, as: Float.self)) }
        }
        guard xs.count == voluto else { partenza = nil; scattato = 0; return }
        let x = xs.reduce(0, +) / Float(xs.count)
        guard let p = partenza else { partenza = x; return }
        let d = x - p
        if abs(d) > 0.14 {                    // circa un settimo del trackpad: un passo, e si può continuare
            Gesto.shared.passo(CGFloat(-d))  // -d: le dita verso sinistra fanno avanzare
            partenza = x
            scattato += 1
        }
    }
}

