// Il tema di Pulsar in un posto solo: aspetto, colori e ombra. Nomi e valori invariati, spostati qui da agente, sfondo,
// ghiera, isola-nuova, nothing e temi (18/10/2026, riordino fase 1). GhieraLook.shared.mode resta l'unica fonte dell'aspetto.
import SwiftUI
import AppKit

// MARK: - Aspetto (Dark Matte, White Matte, Sfondo)

enum AgentMode: String, CaseIterable {
    case notte, bianco, sfondo
    // 11/10 sera: Notte è il Dark Matte; Bianco è il White Matte (stessa grammatica, chiaro, piatto e opaco)
    var title: String { ["notte": "Dark Matte", "bianco": "White Matte", "sfondo": T("Sfondo", "Wallpaper")][rawValue]! }
    /// Notte, Bianco e Sfondo: colonna di icone che resta accanto al pannello.
    var rail: Bool { self == .notte || self == .bianco || self == .sfondo }
    var scheme: ColorScheme { self == .bianco ? .light : .dark }
    /// Gli aspetti vecchi (Scuro, Vetro, Vetro scuro) e un valore mancante o strano diventano Dark Matte.
    static func migra(_ raw: String?) -> AgentMode { AgentMode(rawValue: aspettoMigrato(raw)) ?? .notte }
    static var saved: AgentMode {
        get {
            // 06/10/2026: Notte diventa il predefinito anche per chi aveva già scelto un aspetto (una volta sola)
            if !Impostazioni.bool(.agentLookNotte) { Impostazioni.set(true, .agentLookNotte); Impostazioni.set("notte", .agentLook) }
            return migra(Impostazioni.string(.agentLook))
        }
        set { Impostazioni.set(newValue.rawValue, .agentLook) }
    }
}

// MARK: - Notte (06/10/2026): la grammatica di Kinso
// Colonna di icone in una pillola scura attaccata al bordo; l'icona accesa è un quadratino bianco col glifo scuro.
// Il pannello si apre a sinistra: alto e stretto, vetro blu notte con gradiente (più chiaro in alto), angoli grandi,
// bordo appena visibile. In alto bottoni tondi, in mezzo il contenuto della sezione, in basso il campo arrotondato.

enum Night {
    // 11/10 sera: in White Matte (aspetto Bianco) gli stessi nomi danno i toni chiari, così tutto Pulsar cambia insieme.
    private static var W: Bool { GhieraLook.shared.mode == .bianco }
    private static func c(_ h: UInt32) -> Color { Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255) }
    // 11/10 sera, "matte dark": l'autore ha messo come sfondo il fondo della dimostrazione (gradiente blu grafite
    // (0.13,0.14,0.19) → (0.10,0.11,0.13)) e vuole Notte sugli stessi toni: superfici opache un po' più chiare dello
    // sfondo per staccarsi, selezioni un tono più scure, bordi bianchi al 6-8%, niente nero puro, niente lucidità.
    static var top: Color { W ? c(0xF6F7F9) : Color(red: 0.170, green: 0.180, blue: 0.235) }     // #2B2E3C, pannello in alto
    static var bottom: Color { W ? c(0xEEF0F3) : Color(red: 0.135, green: 0.145, blue: 0.185) }  // #22252F, pannello in basso
    static var rail: Color { W ? c(0xE7E9EE) : Color(red: 0.115, green: 0.123, blue: 0.160) }    // #1D1F29
    static var bar: Color { W ? c(0xEDEFF3) : Color(red: 0.145, green: 0.155, blue: 0.200) }     // #252833, colonna e ghiere in basso
    static var barTop: Color { W ? c(0xF5F6F9) : Color(red: 0.165, green: 0.175, blue: 0.228) }  // #2A2D3A, la stessa luce in alto
    static var barSel: Color { W ? c(0xE0E3E9) : Color(red: 0.112, green: 0.120, blue: 0.157) }  // #1C1F28, selezione: un tono più scura
    // veli scuri trasparenti: prendono la sfumatura del pannello che hanno dietro (06/10, "troppo contrasto")
    // 11/10: negli aspetti chiari (Vetro, Sfondo chiaro) gli stessi veli più leggeri; mai bianchi
    static var sel: Color { Color.black.opacity(Theme.light ? 0.10 : 0.28) }   // selezione: lo sfondo un po' più scuro
    static var veil: Color { Color.black.opacity(Theme.light ? 0.05 : 0.16) }  // righe dei passi e dei file
    static var prominent: Color { Theme.light ? Color(white: 0.1) : .white }  // comandi principali (Allow, invio)
    static var onProminent: Color { Theme.light ? .white : ink }
    static var barFill: LinearGradient { LinearGradient(colors: [barTop, bar], startPoint: .top, endPoint: .bottom) }
    /// 11/10: fusa sotto un altro elemento la colonna parte dal suo stesso blu, così la giuntura non si vede.
    static func barFill(joinedTop: Bool) -> LinearGradient {
        LinearGradient(colors: [joinedTop ? bar : barTop, bar], startPoint: .top, endPoint: .bottom)
    }
    static let ink = Color(red: 0.075, green: 0.080, blue: 0.118)     // glifo scuro sul quadratino bianco
    static let card = Color.primary.opacity(0.055)
    static var event: Color { Theme.light ? Color.white.opacity(0.45) : Color(red: 0.112, green: 0.120, blue: 0.157).opacity(0.9) }   // righe: un tono sotto il pannello
    static let t2 = Color.primary.opacity(0.56)
    static var t3: Color { Color.primary.opacity(Theme.light ? 0.45 : 0.34) }
    // 13/10, l'autore: "al posto del verde usa l'azzurro in tutti e due i temi; giallo, arancione e rosso un po' più matte".
    // `green` resta il nome (lo usano in tanti posti) ma è l'azzurro dei temi: #8FC7FF in Dark Matte, #3B82D0 in White Matte.
    static var red: Color { W ? c(0xC9564F) : c(0xE07A72) }
    static var green: Color { W ? c(0x3B82D0) : c(0x8FC7FF) }
    static var amber: Color { W ? c(0xC2913E) : c(0xE3BC79) }
}

// MARK: - Un solo aspetto per tutto Pulsar (11/10/2026)
// l'autore: "se cambio tema, allora tutti gli strumenti di Pulsar devono cambiare tema." Un'unica fonte:
// GhieraLook.shared.mode (pubblicato) + AgentMode.saved (UserDefaults). Theme.apply li cambia insieme,
// con l'aspetto dell'app (menu e avvisi) e lo stato dell'Agente. Le misure sono le stesse in tutti gli aspetti:
// cambiano solo materiali e colori.

enum Theme {
    static var mode: AgentMode { GhieraLook.shared.mode }
    /// La colonna dell'Agente: in Sfondo il chiaro/scuro si decide sullo sfondo dietro di lei.
    static weak var agentLook: EdgeLook?
    static var light: Bool {
        switch mode {
        case .bianco: return true
        case .sfondo:
            if let l = agentLook { return WallpaperTint.shared.info(l).darkText }
            return WallpaperTint.shared.info(screen: EdgeDock.defaultScreen, side: .right).darkText
        default: return false
        }
    }
    static var scheme: ColorScheme { light ? .light : .dark }
    static var veil: Color {
        if let l = agentLook { return Color(nsColor: WallpaperTint.shared.info(l).veil) }
        return Color(nsColor: WallpaperTint.shared.info(screen: EdgeDock.defaultScreen, side: .right).veil)
    }
    static var accent: Color {
        if mode == .sfondo, let l = agentLook { return Color(nsColor: WallpaperTint.shared.accent(l)) }
        return Color(nsColor: .controlAccentColor)
    }

    /// Cambia l'aspetto di tutto: ghiere, luce, colonna, pannello, pillola, menu e avvisi.
    static func apply(_ m: AgentMode) {
        AgentMode.saved = m
        if GhieraLook.shared.mode != m { GhieraLook.shared.mode = m }
        refreshAppearance()
        Ombra.aggiornaTutte()
    }
    static func refreshAppearance() {
        NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    }
}

/// L'aspetto delle ghiere segue quello dell'Agente (menu AGENTE → Aspetto, ⌃⌥L): Dark Matte, White Matte, Sfondo.
final class GhieraLook: ObservableObject {
    static let shared = GhieraLook()
    @Published var mode: AgentMode = AgentMode.saved
}

/// I colori della superficie per la goccia che si allunga dietro la ghiera mentre la trascini.
enum GhieraColors {
    static var goo: (NSColor, NSColor) {
        switch GhieraLook.shared.mode {
        case .notte, .bianco: return (NSColor(Night.barTop), NSColor(Night.bar))
        case .sfondo: let v = WallpaperTint.shared.info(screen: EdgeDock.defaultScreen, side: .left).veil; return (v, v)
        }
    }
}

/// La scala dell'isola nuova. Dark Matte: grafite con l'azzurro di Spazio; White Matte: chiaro con l'azzurro scuro.
/// 19/10 (fase 3): i valori stanno in `Volta.Scala`, così le Impostazioni possono chiedere la scala di un aspetto preciso
/// (le foto di Dark e White Matte) senza cambiare quello di Pulsar. I nomi statici leggono l'aspetto corrente come prima.
enum Volta {
    private static var L: Bool { Theme.light }
    private static var s: Scala { Scala(chiaro: L) }
    static var body: Color { s.body }
    static var card: Color { s.card }
    static var card2: Color { s.card2 }
    static var t1: Color { s.t1 }
    static var t2: Color { s.t2 }
    static var t3: Color { s.t3 }
    static var a1: Color { s.a1 }
    static var a2: Color { s.a2 }
    static var a3: Color { s.a3 }
    static var a4: Color { s.a4 }
    static var pill: Color { s.pill }
    static var pillT: Color { s.pillT }
    static var prim: Color { s.prim }
    static var primT: Color { s.primT }

    struct Scala {
        let chiaro: Bool
        private var L: Bool { chiaro }
        private func c(_ h: UInt32, _ a: Double = 1) -> Color {
            Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255).opacity(a)
        }
        var body: Color { L ? c(0xF4F6F9) : c(0x1D1F29) }
        var card: Color { L ? c(0xE8ECF2) : c(0x252836) }
        var card2: Color { L ? c(0xDDE3EC) : c(0x2E3242) }
        var t1: Color { L ? c(0x1C1F28) : c(0xEDEFF6) }
        var t2: Color { L ? c(0x1C1F28, 0.6) : c(0xEDEFF6, 0.58) }
        var t3: Color { L ? c(0x1C1F28, 0.4) : c(0xEDEFF6, 0.36) }
        var a1: Color { L ? c(0x1F4F8C) : c(0xD6EBFF) }      // azzurro più chiaro sul scuro, più scuro sul chiaro
        var a2: Color { L ? c(0x3B82D0) : c(0x8FC7FF) }      // l'azzurro di Spazio
        var a3: Color { L ? c(0x7FB0E6) : c(0x5C8FCC) }
        var a4: Color { L ? c(0xC7DDF5) : c(0x33507A) }
        var pill: Color { L ? c(0xDCE3EE) : c(0x2F3446) }
        var pillT: Color { L ? c(0x22283A) : c(0xDCE2F0) }
        var prim: Color { L ? c(0xBFDDFB) : c(0xCFE6FF) }    // al posto del bianco: azzurro chiaro (l'autore, 17/10)
        var primT: Color { L ? c(0x14304F) : c(0x13203A) }
        // fase 3, finestra Impostazioni: barra laterale, fondo della pagina, gruppi e manopole. Mai bianco o nero puri.
        var lato: Color { L ? c(0xE8ECF2) : c(0x1D1F29) }
        var pagina: Color { L ? c(0xF4F6F9) : c(0x252836) }
        var gruppo: Color { L ? c(0xFBFCFD) : c(0x2E3242) }
        var manopola: Color { L ? c(0xFBFCFD) : c(0xEDEFF6) }
    }
}

enum DotColors {
    /// Gli stessi toni di NotchPulse: base blu-grafite attenuata, testa chiara. In White Matte grafite.
    static var base: Color { Theme.light ? Color(white: 0.5) : PulseMotion.tail }
    static var head: Color { Theme.light ? Color(white: 0.12) : .white }
    /// L'azzurro di Spazio Dark Matte (#8FC7FF; in White Matte #3B82D0, tema-matte.js): l'accento "che sale".
    /// l'autore, 12/10 sera: "il volume più si alza più diventa blu, e anche la luminosità".
    static var azzurro: Color { Theme.light ? Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xD0 / 255) : Color(red: 0x8F / 255, green: 0xC7 / 255, blue: 1) }
    static let baseAlpha = 0.62          // il blu "a riposo" della griglia di destra: mai pieno, se no vira all'azzurro
    static let offAlpha = 0.10
}

// MARK: - Ombre (12/10/2026): un'ombra minima, uguale per tutti gli elementi di Pulsar
// l'autore: "effetto piatto come ora, ma con un'ombra al minimo, uguale per tutti gli elementi; niente bordi, niente effetti
// liquidi; un solo punto in temi.swift". Valori:
//   Dark Matte  nero, 9%, raggio 8, 1,5 pt in basso
//   White Matte #8A93A6, 6,5% (4,5% + 2 chiesto da lui), raggio 11, 1,5 pt in basso, un solo strato
// L'ombra di sistema di macOS non va bene (aggiunge un filo di bordo scuro e non si regola), quindi la disegna Pulsar:
// sotto ogni elemento una finestrella gemella appena più grande, figlia della sua finestra (macOS la sposta con lei,
// anche mentre la trascini), con un livello Core Animation che ha solo l'ombra della forma. L'Isola, che si disegna
// già l'ombra da sola dentro la sua finestra, prende gli stessi valori da qui (Ombra.colore / raggio / basso).

enum Ombra {
    static var chiaro: Bool { GhieraLook.shared.mode == .bianco }
    static var nsColore: NSColor { chiaro ? NSColor(red: 0x8A / 255.0, green: 0x93 / 255.0, blue: 0xA6 / 255.0, alpha: 1) : .black }
    static var opacita: Float { chiaro ? 0.065 : 0.09 }
    static var raggio: CGFloat { chiaro ? 11 : 8 }
    static var basso: CGFloat { 1.5 }
    /// Per SwiftUI (Isola): stesso colore e opacità. Il raggio di SwiftUI è la sfocatura, come shadowRadius.
    static var colore: Color { Color(nsColor: nsColore).opacity(Double(opacita)) }
    static let margine: CGFloat = 18

    private final class Gemella: NSPanel {
        let ombra = CALayer()
        var forma: (CGRect) -> CGPath
        weak var padre: NSWindow?
        init(padre: NSWindow, forma: @escaping (CGRect) -> CGPath) {
            self.forma = forma; self.padre = padre
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true
            hidesOnDeactivate = false; isReleasedWhenClosed = false
            collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let v = NSView(); v.wantsLayer = true; contentView = v
            v.layer?.addSublayer(ombra)
            ombra.masksToBounds = false
        }
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
        func segui() {
            guard let p = padre else { return }
            let m = Ombra.margine, f = p.frame
            CATransaction.begin(); CATransaction.setDisableActions(true)
            level = p.level
            setFrame(f.insetBy(dx: -m, dy: -m), display: false)
            ombra.frame = CGRect(x: m, y: m, width: f.width, height: f.height)
            ombra.shadowPath = forma(CGRect(origin: .zero, size: f.size))
            ombra.shadowColor = Ombra.nsColore.cgColor
            ombra.shadowOpacity = Ombra.opacita
            ombra.shadowRadius = Ombra.raggio
            ombra.shadowOffset = CGSize(width: 0, height: -Ombra.basso)   // livello non capovolto: negativo = in basso
            CATransaction.commit()
            alphaValue = p.alphaValue
            if p.isVisible && parent == nil { p.addChildWindow(self, ordered: .below) }
        }
    }
    private static var gemelle: [ObjectIdentifier: Gemella] = [:]
    private static var osservatori: [Any] = []

    /// Dà l'ombra a una finestra. `forma`: il tracciato della sagoma nel rettangolo della finestra (origine in basso a sinistra).
    static func attacca(_ win: NSWindow, forma: @escaping (CGRect) -> CGPath) {
        let id = ObjectIdentifier(win)
        if let g = gemelle[id] { g.forma = forma; g.segui(); return }
        let g = Gemella(padre: win, forma: forma)
        gemelle[id] = g
        let nc = NotificationCenter.default
        for n in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didChangeOcclusionStateNotification] {
            osservatori.append(nc.addObserver(forName: n, object: win, queue: .main) { [weak g] _ in g?.segui() })
        }
        if win.isVisible { win.addChildWindow(g, ordered: .below) }
        g.segui()
    }
    /// L'elemento è comparso o ha cambiato trasparenza (lo chiamano FloatPanel e DialPanel): l'ombra lo segue.
    static func segui(_ win: NSWindow) { gemelle[ObjectIdentifier(win)]?.segui() }

    /// La trasparenza dell'ombra insieme a quella dell'elemento (dentro la stessa animazione, se c'è).
    /// 12/10: prima seguiva alphaValue con un override di NSWindow, e l'animatore di macOS crashava all'avvio.
    static func trasparenza(_ win: NSWindow, _ a: CGFloat, animata: Bool) {
        guard let g = gemelle[ObjectIdentifier(win)] else { return }
        if animata { g.animator().alphaValue = a } else { g.alphaValue = a }
    }

    /// Tema cambiato: colore, opacità e raggio nuovi per tutti.
    static func aggiornaTutte() { gemelle.values.forEach { $0.segui() } }
    /// Rettangolo coi raggi (pannello, capsule): utile per chi non ha una forma sua.
    static func tonda(_ r: CGFloat) -> (CGRect) -> CGPath { { CGPath(roundedRect: $0, cornerWidth: r, cornerHeight: r, transform: nil) } }
}

// MARK: - Moto del pixel-grid (spostato da isola-agente.swift, riordino fase 2)

/// Lo stato del moto: posizione della cometa sull'anello e del fronte dell'onda, integrate fotogramma per fotogramma.
final class PulseMotion {
    static let tail = Color(red: 0.50, green: 0.56, blue: 0.82)      // il blu-grafite di Spazio, schiarito
    static let segment = 4.0                                          // quattro tempi da 4 s: cometa, ritorno, onda, rientro
    static let turn = 1.2                                             // quanto dura un'inversione o una dissolvenza
    private static let ring: [(Int, Int)] = [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (4, 1), (4, 2), (4, 3), (4, 4),
                                              (3, 4), (2, 4), (1, 4), (0, 4), (0, 3), (0, 2), (0, 1)]
    private static let ringIndex: [Int: Int] = Dictionary(uniqueKeysWithValues: ring.enumerated().map { ($0.element.1 * 5 + $0.element.0, $0.offset) })

    private var last: Double?
    private var comet = 0.0          // 0..<16 sull'anello
    private var cometV = 0.0         // celle al secondo, con segno
    private var wave = 0.0           // 0..<3.4: fronte dell'onda (0 centro, 2 bordo)
    private var mixWave = 0.0        // 0 = cometa, 1 = onda

    static func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }   // smoothstep

    func advance(to t: Double, slow: Bool) {
        let dt = min(0.1, max(0, t - (last ?? t)))
        last = t
        let s = slow ? 4.0 : 8.0                  // velocità della cometa
        let w = slow ? 0.55 : 0.9                 // velocità dell'onda
        let seg = Int(t / Self.segment) % 4
        let l = t.truncatingRemainder(dividingBy: Self.segment)
        let k = Self.ease(l / Self.turn)
        // la cometa: oraria, poi rallenta e torna indietro (coseno: passa da +s a -s fermandosi a metà)
        switch seg {
        case 0: cometV = s
        case 1: cometV = s * cos(.pi * k)
        case 2: cometV = -s
        default: cometV = -s * cos(.pi * k)        // si gira di nuovo mentre è nascosta, così riparte oraria
        }
        // l'onda: si allarga, poi si ferma e rientra
        let waveV: Double
        switch seg {
        case 2: waveV = w
        case 3: waveV = w * cos(.pi * k)
        case 0: waveV = -w
        default: waveV = -w * cos(.pi * k)
        }
        comet = (comet + cometV * dt).truncatingRemainder(dividingBy: 16); if comet < 0 { comet += 16 }
        wave = (wave + waveV * dt).truncatingRemainder(dividingBy: 3.4); if wave < 0 { wave += 3.4 }
        // chi si vede: dissolvenza morbida all'inizio dei tempi 2 (verso l'onda) e 0 (verso la cometa)
        switch seg {
        case 0: mixWave = 1 - k
        case 1: mixWave = 0
        case 2: mixWave = k
        default: mixWave = 1
        }
    }

    /// (quanto è acceso il pixel nel suo colore, quanto bianco gli si sovrappone)
    func level(_ x: Int, _ y: Int, t: Double) -> (Double, Double) {
        let d = max(abs(x - 2), abs(y - 2))
        // cometa: bagliore attorno alla testa e coda dietro, lunga quanto la velocità
        var cA = 0.07, cW = 0.0
        if d == 2, let i = Self.ringIndex[y * 5 + x] {
            var dist = Double(i) - comet
            dist -= 16 * (dist / 16).rounded()                 // distanza circolare, con segno
            let speed = abs(cometV) / 8
            let dir: Double = cometV >= 0 ? 1 : -1
            let behind = -dist * dir                           // positiva dietro la testa
            let glow = exp(-dist * dist / 0.9)
            let trail = behind > 0 ? speed * 0.55 * exp(-behind / 2.6) : 0
            cA = max(0.1, min(0.8, 0.55 * glow + trail))
            cW = 0.75 * exp(-dist * dist / 0.35)               // solo la testa diventa chiara
        } else if d == 0 {
            cA = 0.18 + 0.22 * (0.5 + 0.5 * sin(t * 4.2))      // il cuore respira, piano
        }
        // onda: un anello morbido che passa sui tre giri (centro, interno, bordo)
        let env = Self.ease(wave / 0.6) * (1 - Self.ease((wave - 2.5) / 0.8))
        let ringD = Double(d) - wave
        let wA = 0.07 + 0.6 * env * exp(-ringD * ringD / 0.32)
        let wW = 0.22 * env * exp(-ringD * ringD / 0.12)
        let m = mixWave
        return (cA * (1 - m) + wA * m, cW * (1 - m) + wW * m)
    }

    /// Fine lavoro: menta ferma, il bordo un po' più acceso.
    static func doneLevel(_ x: Int, _ y: Int, t: Double) -> (Double, Double) {
        let d = max(abs(x - 2), abs(y - 2))
        return (d == 2 ? 0.85 : d == 0 ? 0.7 : 0.25, 0)
    }
}
