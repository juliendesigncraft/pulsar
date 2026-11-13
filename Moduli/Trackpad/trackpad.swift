// Bordi del trackpad (06/11/2026, idea da EdgeBar, reel salvato DfPlCCapZZ4): un dito che scorre lungo il bordo
// del trackpad regola volume, luce dello schermo o tracce, senza tasti e senza barra. Facoltativo: spento di serie,
// si accende dai Pezzi di Pulsar nel menu, dal benvenuto o dalla pagina Trackpad (regola dell'autore del 06/11).
//
// Lettura: MultitouchSupport, framework privato di macOS (lo stesso di BetterTouchTool e degli altri). Si carica a
// runtime come DisplayServices nella ghiera: se una versione di macOS lo toglie, la pagina lo dice invece di rompersi.
// Provato nella tappa 1 su macOS 26.6.2: nessun permesso, funziona anche con la firma della vendita (hardened runtime),
// i gesti di sistema restano di macOS (si ascolta, non si blocca niente). Riceve i tocchi solo nella sessione di chi è collegato.
// Limite: mentre il dito scorre sul bordo si muove anche il puntatore (fermarlo vorrebbe il permesso Accessibilità).
//
// Il riconoscimento del gesto sta in trackpad-logica.swift (puro, provato in prove/trackpad).
import AppKit
import SwiftUI

// MARK: - Lettura grezza

/// Il ponte con MultitouchSupport. Le funzioni C non portano contesto: il gestore sta in una variabile statica.
enum LettoreTrackpad {
    private typealias CreaLista = @convention(c) () -> Unmanaged<CFArray>
    private typealias Richiamo = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Registra = @convention(c) (UnsafeMutableRawPointer?, Richiamo) -> Void
    private typealias Avvia = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias Ferma = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private static let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private static func f<T>(_ n: String, _ t: T.Type) -> T? { dlsym(h, n).map { unsafeBitCast($0, to: t) } }
    private static let creaLista = f("MTDeviceCreateList", CreaLista.self)
    private static let registra = f("MTRegisterContactFrameCallback", Registra.self)
    private static let togli = f("MTUnregisterContactFrameCallback", Registra.self)
    private static let avviaDev = f("MTDeviceStart", Avvia.self)
    private static let fermaDev = f("MTDeviceStop", Ferma.self)

    static var disponibile: Bool { creaLista != nil && registra != nil && avviaDev != nil }

    /// Riceve le dita di ogni fotogramma, sul filo principale.
    static var gestore: (([DitoTrackpad]) -> Void)?
    private static var dispositivi: [AnyObject] = []

    // Ogni dito è un blocco di 96 byte; x e y normalizzati (0...1) a 32 e 36 (misurato nella tappa 1).
    private static let richiamo: Richiamo = { _, dati, n, _, _ in
        var dita: [DitoTrackpad] = []
        if let p = dati, n > 0 {
            for i in 0..<Int(n) {
                let b = p.advanced(by: i * 96)
                dita.append(DitoTrackpad(x: b.load(fromByteOffset: 32, as: Float.self), y: b.load(fromByteOffset: 36, as: Float.self)))
            }
        }
        DispatchQueue.main.async { gestore?(dita); altri.values.forEach { $0(dita) } }
        return 0
    }

    /// Quanti trackpad ascolta (0 = nessuno trovato o framework assente).
    @discardableResult
    static func avvia() -> Int {
        ferma()
        guard disponibile, let lista = creaLista?() else { return 0 }
        dispositivi = lista.takeRetainedValue() as [AnyObject]
        for d in dispositivi {
            let p = Unmanaged.passUnretained(d).toOpaque()
            registra?(p, richiamo)
            avviaDev?(p, 0)
        }
        return dispositivi.count
    }

    /// 13/11: altri che ascoltano il trackpad (il clic centrale a tre dita di Moduli/Input), oltre ai bordi.
    private static var altri: [String: ([DitoTrackpad]) -> Void] = [:]
    static func ascolta(_ id: String, _ g: @escaping ([DitoTrackpad]) -> Void) {
        altri[id] = g
        if dispositivi.isEmpty { avvia() }
    }
    static func smetti(_ id: String) {
        guard altri.removeValue(forKey: id) != nil else { return }
        if altri.isEmpty && gestore == nil { ferma() }
    }
    /// Il modulo Trackpad si spegne: i dispositivi si fermano solo se nessun altro ascolta.
    static func fermaSeNessuno() { if altri.isEmpty { ferma() } }

    static func ferma() {
        for d in dispositivi {
            let p = Unmanaged.passUnretained(d).toOpaque()
            togli?(p, richiamo)
            fermaDev?(p)
        }
        dispositivi = []
    }
}

// MARK: - Scelte salvate

enum PreferenzeTrackpad {
    static func azione(_ b: BordoTrackpad) -> AzioneBordo {
        let chiave: Chiave = b == .destro ? .trackpadDestro : b == .sinistro ? .trackpadSinistro : .trackpadBasso
        let diSerie: AzioneBordo = b == .destro ? .volume : b == .sinistro ? .luce : .tracce
        return Impostazioni.string(chiave).flatMap(AzioneBordo.init(rawValue:)) ?? diSerie
    }
    static func imposta(_ b: BordoTrackpad, _ a: AzioneBordo) {
        let chiave: Chiave = b == .destro ? .trackpadDestro : b == .sinistro ? .trackpadSinistro : .trackpadBasso
        Impostazioni.set(a.rawValue, chiave)
        ModuloTrackpad.shared.rileggi()
    }
    static var azioni: [BordoTrackpad: AzioneBordo] {
        Dictionary(uniqueKeysWithValues: BordoTrackpad.allCases.map { ($0, azione($0)) })
    }
    /// 0 = lenta, 1 = veloce. 0,5 di serie (corsa piena 0,625 del bordo).
    static var sensibilita: Double {
        get { Impostazioni.object(.trackpadSensibilita) as? Double ?? 0.5 }
        set { Impostazioni.set(newValue, .trackpadSensibilita); ModuloTrackpad.shared.rileggi() }
    }
    /// Il riscontro nel notch (acceso di serie).
    static var riscontro: Bool {
        get { Impostazioni.object(.trackpadRiscontro) as? Bool ?? true }
        set { Impostazioni.set(newValue, .trackpadRiscontro) }
    }
}

extension AzioneBordo {
    var titolo: String {
        switch self {
        case .volume: return T("Volume", "Volume")
        case .luce: return T("Luce", "Brightness")
        case .tracce: return T("Tracce", "Tracks")
        case .nessuna: return T("Niente", "Nothing")
        }
    }
    var simbolo: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .luce: return "sun.max.fill"
        case .tracce: return "forward.fill"
        case .nessuna: return "circle.slash"
        }
    }
}

extension BordoTrackpad {
    var titolo: String {
        switch self {
        case .destro: return T("Bordo destro", "Right edge")
        case .sinistro: return T("Bordo sinistro", "Left edge")
        case .basso: return T("Bordo in basso", "Bottom edge")
        }
    }
    /// Le scelte che hanno senso per il bordo: sui lati si scorre su e giù (valori), in basso a destra e sinistra.
    var scelte: [AzioneBordo] { AzioneBordo.allCases }
}

// MARK: - Il modulo

final class ModuloTrackpad: ModuloPulsar {
    static let shared = ModuloTrackpad()
    var id: String { "trackpad" }
    var nome: String { T("Trackpad", "Trackpad") }
    var prodotto: Prodotto { .mixer }
    /// Le tracce si cambiano parlando con Musica o Spotify: macOS chiede l'Automazione al primo colpo.
    var permessi: [Permesso] { PreferenzeTrackpad.azioni.values.contains(.tracce) ? [.automazione] : [] }
    /// Spento di serie: è un'alternativa per chi vuole tutto dal trackpad, non per tutti.
    var acceso: Bool {
        get { Impostazioni.object(.trackpadAcceso) as? Bool ?? false }
        set { Impostazioni.set(newValue, .trackpadAcceso); RegistroModuli.shared.riapplica() }
    }

    private var gesto = GestoBordi(azioni: PreferenzeTrackpad.azioni)
    private var osservatore: NSObjectProtocol?
    /// Quanti trackpad ascolta adesso (per la pagina). 0 a modulo spento.
    private(set) var trackpad = 0

    func avvia() {
        rileggi()
        LettoreTrackpad.gestore = { [weak self] dita in self?.fotogramma(dita) }
        trackpad = LettoreTrackpad.avvia()
        // dopo il riposo del Mac MultitouchSupport smette di chiamare: si riparte
        osservatore = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.trackpad = LettoreTrackpad.avvia() }
        }
    }

    func ferma() {
        LettoreTrackpad.gestore = nil
        LettoreTrackpad.fermaSeNessuno()     // 13/11: il clic centrale a tre dita può ascoltare ancora
        if let o = osservatore { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        osservatore = nil
        trackpad = 0
        RiscontroBordi.shared.nascondi()
    }

    /// Dopo un cambio nelle Impostazioni: nuove azioni e sensibilità, il gesto riparte da capo.
    func rileggi() {
        gesto = GestoBordi(regole: RegoleBordi.diSerie.conSensibilita(PreferenzeTrackpad.sensibilita), azioni: PreferenzeTrackpad.azioni)
    }

    private func fotogramma(_ dita: [DitoTrackpad]) {
        for e in gesto.passo(dita) { esegui(e) }
    }

    private func esegui(_ e: EventoBordo) {
        switch e {
        case .inizio(let b):
            mostra(b)
        case .regola(let b, let delta):
            switch PreferenzeTrackpad.azione(b) {
            case .volume: SystemVolume.level = SystemVolume.level + delta
            case .luce: LightControl.screen = LightControl.screen + delta
            default: break
            }
            mostra(b)
        case .scatto(let b, let avanti):
            guard PreferenzeTrackpad.azione(b) == .tracce else { return }
            ComandoTracce.salta(avanti: avanti)
            if PreferenzeTrackpad.riscontro { RiscontroBordi.shared.scatto(avanti: avanti) }
        case .fine:
            RiscontroBordi.shared.rilascia()
        }
    }

    private func mostra(_ b: BordoTrackpad) {
        guard PreferenzeTrackpad.riscontro else { return }
        switch PreferenzeTrackpad.azione(b) {
        case .volume: RiscontroBordi.shared.livello(SystemVolume.muted ? 0 : SystemVolume.level, simbolo: AzioneBordo.volume.simbolo)
        case .luce where LightControl.screenAvailable: RiscontroBordi.shared.livello(LightControl.screen, simbolo: AzioneBordo.luce.simbolo)
        default: break
        }
    }
}

/// Traccia avanti o indietro nell'app che sta suonando (Spotify se è aperto, se no Musica). Mai tasti simulati.
enum ComandoTracce {
    private static let coda = DispatchQueue(label: "pulsar.trackpad.tracce")
    static func salta(avanti: Bool) {
        let aperte = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let app = aperte.contains("com.spotify.client") ? "Spotify" : aperte.contains("com.apple.Music") ? "Music" : nil
        guard let app else { return }
        let src = "tell application \"\(app)\" to \(avanti ? "next" : "previous") track"
        coda.async {
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
        }
    }
}

// MARK: - Riscontro nel notch

/// Una lingua nera che scende dal notch, larga quanto il notch (o, con l'isola aperta, una capsula sotto l'isola e larga come lei), con il simbolo e il livello in sfumature dell'azzurro
/// di Spazio. Niente contorni (l'autore, 17/10), mai sopra la barra dei menu: sta sotto il notch e continua il suo nero.
final class StatoRiscontro: ObservableObject {
    @Published var valore: Float = 0
    @Published var simbolo = "speaker.wave.2.fill"
    @Published var scatto: Bool? = nil        // non nil: si mostra la freccia della traccia, non la barra
    /// L'altezza del notch sopra la lingua (0 sui Mac senza notch: allora è una capsula sotto la barra dei menu).
    @Published var sopra: CGFloat = 0
}

private struct VistaRiscontro: View {
    @ObservedObject var s: StatoRiscontro
    // Sul nero del notch si usa sempre la scala scura: azzurro chiaro per il simbolo, azzurro di Spazio per la barra.
    private let chiaro = Color(red: 0xD6 / 255, green: 0xEB / 255, blue: 1)
    private let azzurro = Color(red: 0x8F / 255, green: 0xC7 / 255, blue: 1)
    private let scuro = Color(red: 0x1F / 255, green: 0x4F / 255, blue: 0x8C / 255)

    var body: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: s.sopra)
            riga
        }
        .background(UnevenRoundedRectangle(topLeadingRadius: s.sopra > 0 ? 0 : 12, bottomLeadingRadius: 12,
                                           bottomTrailingRadius: 12, topTrailingRadius: s.sopra > 0 ? 0 : 12).fill(Color.black))
    }

    private var riga: some View {
        HStack(spacing: 10) {
            Image(systemName: s.scatto.map { $0 ? "forward.fill" : "backward.fill" } ?? s.simbolo)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(chiaro)
                .frame(width: 16)
            if s.scatto == nil {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(scuro.opacity(0.55))
                        Capsule()
                            .fill(LinearGradient(colors: [scuro, azzurro, chiaro], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, g.size.width * CGFloat(max(0, min(1, s.valore)))))
                    }
                }
                .frame(height: 4)
                .animation(.easeOut(duration: 0.08), value: s.valore)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class RiscontroBordi {
    static let shared = RiscontroBordi()
    private let stato = StatoRiscontro()
    private var finestra: NSPanel?
    private var via: DispatchWorkItem?

    private var schermo: NSScreen { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0] }
    private var notch: CGSize {
        let s = schermo
        guard s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else {
            return CGSize(width: 190, height: NSStatusBar.system.thickness)
        }
        return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
    }

    func livello(_ v: Float, simbolo: String) {
        stato.scatto = nil
        stato.simbolo = simbolo
        stato.valore = v
        apri(resta: nil)
    }

    func scatto(avanti: Bool) {
        stato.scatto = avanti
        apri(resta: 0.9)
    }

    /// Il dito si è alzato: la lingua resta un attimo e poi rientra.
    func rilascia() { programmaVia(0.7) }

    func nascondi() {
        via?.cancel()
        finestra?.orderOut(nil)
    }

    private func apri(resta: Double?) {
        let w = finestra ?? crea()
        finestra = w
        let n = notch, s = schermo.frame
        let alto: CGFloat = 26
        if let isola = IslandMetrics.visibile {
            // 07/11, l'autore: con l'isola aperta la lingua attaccata al notch era più stretta di lei. Ora è una capsula
            // staccata 6 punti sotto l'isola e larga come lei: non copre le tessere e i bordi tornano in colonna.
            stato.sopra = 0
            w.setFrame(NSRect(x: isola.minX, y: isola.minY - 6 - alto, width: isola.width, height: alto), display: true)
        } else if schermo.safeAreaInsets.top > 0 {
            // sotto il notch, stessa larghezza: la parte alta sta dentro il notch, nera come lui, e non copre la barra
            stato.sopra = n.height
            w.setFrame(NSRect(x: s.midX - n.width / 2, y: s.maxY - n.height - alto, width: n.width, height: n.height + alto), display: true)
        } else {
            // senza notch: una capsula sotto la barra dei menu, mai sopra
            stato.sopra = 0
            w.setFrame(NSRect(x: s.midX - 95, y: s.maxY - n.height - alto - 6, width: 190, height: alto), display: true)
        }
        if !w.isVisible { w.alphaValue = 0; w.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.12; w.animator().alphaValue = 1 }
        via?.cancel()
        if let r = resta { programmaVia(r) }
    }

    private func programmaVia(_ dopo: Double) {
        via?.cancel()
        let lavoro = DispatchWorkItem { [weak self] in
            guard let w = self?.finestra else { return }
            NSAnimationContext.runAnimationGroup({ c in c.duration = 0.25; w.animator().alphaValue = 0 }) { w.orderOut(nil) }
        }
        via = lavoro
        DispatchQueue.main.asyncAfter(deadline: .now() + dopo, execute: lavoro)
    }

    private func crea() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: VistaRiscontro(s: stato).ignoresSafeArea())
        return p
    }
}
