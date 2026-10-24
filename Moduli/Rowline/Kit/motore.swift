// Rowline (fino al 14/10 sera si chiamava Fila) — il MOTORE (14/10/2026).
// Dal post di @theaiskool su TileMyMac (Instagram DecGbJgBCTX): le finestre aperte stanno in una fila orizzontale,
// una accanto all'altra, invece di ammucchiarsi. Ogni schermo ha la sua fila; ogni posto della fila è una colonna
// che può tenere una finestra sola o più finestre impilate. La fila scorre: quella col fuoco è sempre tutta visibile,
// quelle fuori vista vengono parcheggiate nell'angolo in basso a destra dello schermo (resta un pixel, come fa AeroSpace).
//
// Tutto passa dall'API di Accessibilità di macOS (l'unico permesso che serve). Niente rete, niente account.
// Le finestre si muovono solo quando succede qualcosa (finestra nuova o chiusa, fuoco cambiato, un comando):
// se le sposti a mano Fila non te le strappa via, le rimette in fila al prossimo evento.

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Accessibilità, in piccolo

enum AX {
    static func valore(_ el: AXUIElement, _ nome: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, nome as CFString, &v) == .success ? v : nil
    }
    static func stringa(_ el: AXUIElement, _ nome: String) -> String? { valore(el, nome) as? String }
    static func vero(_ el: AXUIElement, _ nome: String) -> Bool { (valore(el, nome) as? Bool) ?? false }
    static func id(_ el: AXUIElement) -> CGWindowID? {
        var i: CGWindowID = 0
        return _AXUIElementGetWindow(el, &i) == .success && i != 0 ? i : nil
    }
    static func finestre(_ app: AXUIElement) -> [AXUIElement] {
        (valore(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    static func modificabile(_ el: AXUIElement, _ nome: String) -> Bool {
        var b: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, nome as CFString, &b) == .success && b.boolValue
    }
    static func cornice(_ el: AXUIElement) -> CGRect? {
        guard let p = valore(el, kAXPositionAttribute), let s = valore(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
    static func posa(_ el: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) }
    }
    static func misura(_ el: AXUIElement, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) }
    }
}

// MARK: - Schermi in coordinate di Accessibilità (origine in alto a sinistra dello schermo principale)

extension NSScreen {
    var numero: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0 }
    private static var altezzaPrincipale: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    private func ax(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: NSScreen.altezzaPrincipale - r.maxY, width: r.width, height: r.height) }
    var areaAX: CGRect { ax(visibleFrame) }     // senza barra dei menu e Dock
    var corniceAX: CGRect { ax(frame) }
}

// MARK: - Il modello

final class Finestra {
    let id: CGWindowID, el: AXUIElement, pid: pid_t, app: String, bundle: String
    init(id: CGWindowID, el: AXUIElement, pid: pid_t, app: String, bundle: String) {
        self.id = id; self.el = el; self.pid = pid; self.app = app; self.bundle = bundle
    }
}

final class Colonna {
    var finestre: [Finestra]
    var frazione: CGFloat          // parte della larghezza dello schermo: 1/2, 2/3, 1
    var attiva = 0                 // quale finestra della pila ha il fuoco
    init(_ f: [Finestra], frazione: CGFloat) { finestre = f; self.frazione = frazione }
}

final class Striscia {
    let schermo: CGDirectDisplayID
    var colonne: [Colonna] = []
    var fuoco = 0
    var scorrimento: CGFloat = 0
    var centrata = false           // ⌃⌥⌘C: la colonna col fuoco sta al centro anche ai bordi della fila
    // l'ultima disposizione, per disegnare la mappa nel pannello
    var xs: [CGFloat] = [], larghezze: [CGFloat] = [], vista: CGFloat = 1, alta: CGFloat = 1
    init(_ s: CGDirectDisplayID) { schermo = s }
}

// Quello che il pannello disegna (copie semplici, mai i riferimenti AX)
struct TesseraVista: Identifiable { let id: CGWindowID; let app: String; let bundle: String }
struct ColonnaVista: Identifiable { let id: Int; let x: CGFloat; let w: CGFloat; let finestre: [TesseraVista]; let attiva: Int; let fuoco: Bool }
struct StrisciaVista: Identifiable { let id: CGDirectDisplayID; let nome: String; let colonne: [ColonnaVista]; let scorrimento: CGFloat; let vista: CGFloat; let alta: CGFloat
    var fuoco: (app: String, posto: Int, totale: Int)? {
        guard let i = colonne.firstIndex(where: \.fuoco) else { return nil }
        let c = colonne[i]
        return (c.finestre[safe: c.attiva]?.app ?? "", i + 1, colonne.count)
    }
}

// MARK: - Il motore

final class Motore: ObservableObject {
    static let shared = Motore()

    @Published var mappa: [StrisciaVista] = []
    @Published private(set) var fidato = AXIsProcessTrusted()
    @Published var acceso: Bool = Archivio.d.object(forKey: "acceso") as? Bool ?? true {
        didSet {
            Archivio.d.set(acceso, forKey: "acceso")
            if acceso { adotta() } else { libera() }
        }
    }
    @Published var escluse: [String] = Archivio.d.stringArray(forKey: "escluse") ?? [] {
        didSet { Archivio.d.set(escluse, forKey: "escluse"); if acceso { adotta() } }
    }
    @Published var margine: Double = Archivio.d.object(forKey: "margine") as? Double ?? 10 {
        didSet { Archivio.d.set(margine, forKey: "margine"); disponiTutto() }
    }
    var g: CGFloat { CGFloat(margine) }
    /// Le finestre scivolano al loro posto (0,2 s) invece di saltare.
    @Published var animazioni: Bool = Archivio.d.object(forKey: "animazioni") as? Bool ?? true {
        didSet { Archivio.d.set(animazioni, forKey: "animazioni") }
    }
    /// Larghezza fissa per app (bundle → frazione): una finestra nuova di quell'app entra già così.
    @Published var regoleApp: [String: Double] = (Archivio.d.dictionary(forKey: "regoleApp") as? [String: Double]) ?? [:] {
        didSet { Archivio.d.set(regoleApp, forKey: "regoleApp") }
    }
    /// Quanto sbucano ai lati le finestre vicine (0 = niente): si capisce che la fila continua.
    @Published var sbirciata: Double = Archivio.d.object(forKey: "sbirciata") as? Double ?? 0 {
        didSet { Archivio.d.set(sbirciata, forKey: "sbirciata"); disponiTutto() }
    }
    @Published var postazioni: [Postazione] = Postazione.carica() {
        didSet { Postazione.salva(postazioni) }
    }
    /// Finestre fatte galleggiare sopra la fila (⌃⌥⌘T): libere finché non si rimettono.
    private var galleggianti = Set<CGWindowID>()
    /// Ripresa del reel: Rowline gestisce solo le finestre di questo processo (RowlineDemo), mai quelle dell'autore.
    var soloPid: pid_t?

    private var strisce: [CGDirectDisplayID: Striscia] = [:]
    private var fuocoID: CGWindowID?
    private var timer: Timer?
    /// App che non si mettono mai in fila: Fila stessa e Pulsar (vive nel notch e ai bordi).
    private let sempreLibere: Set<String> = Archivio.sempreLibere
    /// Dentro Pulsar (19/10): modulo spento dall'interruttore o dalla licenza. Diverso da `acceso`, che è la scelta di Rowline.
    var sospesa = false

    func avvia() {
        // comandi da Pulsar (tessera Rowline nell'Isola): "scegli:<id finestra>", "vai:1", "vai:-1"
        DistributedNotificationCenter.default().addObserver(forName: Archivio.notificaComando, object: nil, queue: .main) { [weak self] n in
            guard let c = n.object as? String else { return }
            let parti = c.split(separator: ":")
            if parti.first == "scegli", let id = parti.last.flatMap({ UInt32($0) }) { self?.scegli(id) }
            if parti.first == "vai", let d = parti.last.flatMap({ Int($0) }) { self?.vai(d) }
            self?.comandoDemo(String(parti.first ?? ""), parti.count > 1 ? String(parti[1]) : "")
        }
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                  NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                  NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.giro() }
        }
        // Cambio di Scrivania (Spaces): le finestre dell'altra Scrivania escono dalla fila, quelle di questa entrano.
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.adotta() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.adotta() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.giro() }
        if acceso { adotta() }
    }

    // MARK: Ricerca delle finestre

    private struct Trovata { let f: Finestra; let cornice: CGRect }

    /// Le finestre normali delle app normali: niente dialoghi, pannelli, finestre ridotte o a tutto schermo,
    /// niente finestre a misura fissa (Impostazioni di Sistema, calcolatrice): quelle restano libere.
    private func cerca(soloVisibili: Bool) -> [CGWindowID: Trovata] {
        var visibili = Set<CGWindowID>()
        if soloVisibili, let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in info { if let n = w[kCGWindowNumber as String] as? CGWindowID { visibili.insert(n) } }
        }
        var out: [CGWindowID: Trovata] = [:]
        let mio = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != mio {
            let b = app.bundleIdentifier ?? ""
            if let solo = soloPid { if app.processIdentifier != solo { continue } }
            else if sempreLibere.contains(b) || escluse.contains(b) { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            for w in AX.finestre(axApp) {
                guard AX.stringa(w, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      !AX.vero(w, kAXMinimizedAttribute), !AX.vero(w, "AXFullScreen"),
                      AX.modificabile(w, kAXSizeAttribute),
                      let id = AX.id(w), let c = AX.cornice(w) else { continue }
                if soloVisibili && !visibili.contains(id) { continue }
                if galleggianti.contains(id) { continue }
                // nella ripresa del reel tutte le finestre finte sono di un solo processo: il nome è il titolo della finestra
                let nome = soloPid != nil ? (AX.stringa(w, kAXTitleAttribute) ?? app.localizedName ?? b) : (app.localizedName ?? b)
                out[id] = Trovata(f: Finestra(id: id, el: w, pid: app.processIdentifier, app: nome, bundle: b), cornice: c)
            }
        }
        return out
    }

    private func schermo(per c: CGRect) -> NSScreen? {
        let centro = CGPoint(x: c.midX, y: c.midY)
        return NSScreen.screens.first { $0.corniceAX.contains(centro) }
            ?? NSScreen.screens.max { $0.corniceAX.intersection(c).area < $1.corniceAX.intersection(c).area }
    }

    private func striscia(_ s: NSScreen) -> Striscia {
        if let x = strisce[s.numero] { return x }
        let x = Striscia(s.numero); strisce[s.numero] = x; return x
    }

    /// Ricomincia da capo: le finestre visibili entrano in fila nell'ordine in cui stanno da sinistra a destra.
    func adotta() {
        fidato = AXIsProcessTrusted()
        guard acceso, fidato, !sospesa else { strisce = [:]; aggiornaMappa(); return }
        let vecchie = strisce
        strisce = [:]
        let trovate = cerca(soloVisibili: true).values.sorted { $0.cornice.minX < $1.cornice.minX }
        for t in trovate {
            guard let s = schermo(per: t.cornice) else { continue }
            // chi era già in fila tiene la sua larghezza
            let prima = vecchie.values.flatMap(\.colonne).first { $0.finestre.contains { $0.id == t.f.id } }
            striscia(s).colonne.append(Colonna([t.f], frazione: prima?.frazione ?? regoleApp[t.f.bundle].map { CGFloat($0) } ?? frazioneNuova(t.cornice.width, s)))
        }
        leggiFuoco(forza: true)
        disponiTutto()
    }

    /// La larghezza di partenza: la più vicina fra 1/2, 2/3 e intera a quella che la finestra ha già.
    private func frazioneNuova(_ w: CGFloat, _ s: NSScreen) -> CGFloat {
        let r = w / s.areaAX.width
        return [0.5, 2.0 / 3, 1].min { abs($0 - r) < abs($1 - r) }!
    }

    // MARK: Il giro (ogni 0,35 s e a ogni evento delle app)

    func giro() {
        let ora = AXIsProcessTrusted()
        if ora != fidato { fidato = ora; if ora { adotta() } }
        guard acceso, fidato, !sospesa else { return }
        var cambiate = Set<CGDirectDisplayID>()
        let tutte = cerca(soloVisibili: false)
        // via quelle chiuse, ridotte o nascoste
        for st in strisce.values {
            let prima = st.colonne.reduce(0) { $0 + $1.finestre.count }
            for c in st.colonne { c.finestre.removeAll { tutte[$0.id] == nil }; c.attiva = min(c.attiva, max(0, c.finestre.count - 1)) }
            st.colonne.removeAll { $0.finestre.isEmpty }
            if st.colonne.reduce(0, { $0 + $1.finestre.count }) != prima { cambiate.insert(st.schermo); st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1)) }
        }
        // dentro quelle nuove (solo se visibili: quelle delle altre Scrivanie restano fuori)
        let note = Set(strisce.values.flatMap { $0.colonne.flatMap { $0.finestre.map(\.id) } })
        let nuove = tutte.filter { !note.contains($0.key) }
        if !nuove.isEmpty {
            let visibili = cerca(soloVisibili: true)
            for (id, t) in nuove where visibili[id] != nil {
                guard let s = schermo(per: t.cornice) else { continue }
                let st = striscia(s)
                let posto = st.colonne.isEmpty ? 0 : st.fuoco + 1
                st.colonne.insert(Colonna([t.f], frazione: regoleApp[t.f.bundle].map { CGFloat($0) } ?? 0.5), at: posto)
                st.fuoco = posto
                cambiate.insert(st.schermo)
            }
        }
        if let s = leggiFuoco(forza: false) { cambiate.insert(s) }
        for s in cambiate { if let st = strisce[s] { disponi(st) } }
        if !cambiate.isEmpty { aggiornaMappa() }
    }

    /// Segue la finestra che ha il fuoco (clic, ⌘Tab, Dock): se è in fila la fila scorre fino a lei.
    @discardableResult
    private func leggiFuoco(forza: Bool) -> CGDirectDisplayID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let v = AX.valore(axApp, kAXFocusedWindowAttribute), CFGetTypeID(v) == AXUIElementGetTypeID(),
              let id = AX.id(v as! AXUIElement) else { return nil }
        if id == fuocoID && !forza { return nil }
        fuocoID = id
        for st in strisce.values {
            for (i, c) in st.colonne.enumerated() {
                if let j = c.finestre.firstIndex(where: { $0.id == id }) {
                    if st.fuoco != i { st.centrata = false }
                    st.fuoco = i; c.attiva = j
                    return st.schermo
                }
            }
        }
        return nil
    }

    // MARK: Disposizione

    func disponiTutto() {
        guard acceso, fidato else { return }
        strisce.values.forEach(disponi)
        aggiornaMappa()
    }

    private func disponi(_ st: Striscia) {
        guard let sc = NSScreen.screens.first(where: { $0.numero == st.schermo }) else { return }
        var area = sc.areaAX.insetBy(dx: g, dy: g)
        area.size.height -= Barra.riserva          // lo spazio della barra in basso: le finestre non ci vanno sopra
        let pieno = area                           // lo schermo intero: quello che ci cade dentro si vede
        // con la sbirciata la colonna col fuoco sta dentro una vista più stretta, e le vicine sbucano ai lati
        if st.colonne.count > 1 && sbirciata > 0 { area = area.insetBy(dx: CGFloat(sbirciata), dy: 0) }
        guard !st.colonne.isEmpty else { st.xs = []; st.larghezze = []; return }
        st.fuoco = min(st.fuoco, st.colonne.count - 1)

        // 1. le misure (alcune finestre non scendono sotto una larghezza minima: si tiene quella vera)
        var larghezze: [CGFloat] = []
        for c in st.colonne {
            let w = max(240, (c.frazione * (area.width + g) - g).rounded())
            let n = CGFloat(c.finestre.count)
            let h = ((area.height - g * (n - 1)) / n).rounded()
            var vera = w
            for f in c.finestre {
                AX.misura(f.el, CGSize(width: w, height: h))
                if let r = AX.cornice(f.el) { vera = max(vera, min(r.width, area.width)) }
            }
            larghezze.append(vera)
        }
        // 2. le posizioni nella fila e lo scorrimento minimo che mostra tutta la colonna col fuoco
        var xs: [CGFloat] = [], x: CGFloat = 0
        for w in larghezze { xs.append(x); x += w + g }
        let totale = x - g
        var s = st.scorrimento
        let fx = xs[st.fuoco], fw = larghezze[st.fuoco]
        if st.centrata {
            s = fx + fw / 2 - area.width / 2
        } else {
            if fx < s { s = fx }
            if fx + fw > s + area.width { s = fx + fw - area.width }
            s = max(0, min(s, max(0, totale - area.width)))
        }
        let prima = st.scorrimento
        st.scorrimento = s; st.xs = xs; st.larghezze = larghezze; st.vista = area.width; st.alta = area.height

        // 3. si posa tutto: quello che si vede anche solo in parte al suo posto, il resto parcheggiato nell'angolo.
        //    Le finestre che si vedono scivolano: da dove sono, o (se erano parcheggiate) da dove sarebbero state prima.
        let angolo = CGPoint(x: sc.corniceAX.maxX - 1, y: sc.corniceAX.maxY - 1)
        var mosse: [Mossa] = []
        for (i, c) in st.colonne.enumerated() {
            let sx = area.minX + xs[i] - s
            let siVede = sx + larghezze[i] > pieno.minX + 8 && sx < pieno.maxX - 8
            let n = CGFloat(c.finestre.count)
            let h = ((area.height - g * (n - 1)) / n).rounded()
            for (j, f) in c.finestre.enumerated() {
                if siVede {
                    let p = CGPoint(x: sx, y: area.minY + CGFloat(j) * (h + g))
                    let ora = AX.cornice(f.el)
                    let parcheggiata = ora.map { $0.minX >= sc.corniceAX.maxX - 4 || $0.maxX <= sc.corniceAX.minX + 4 } ?? true
                    let da = parcheggiata ? CGPoint(x: area.minX + xs[i] - prima, y: p.y) : (ora?.origin ?? p)
                    mosse.append(Mossa(el: f.el, da: da, a: p, misura: CGSize(width: larghezze[i], height: h)))
                } else {
                    AX.posa(f.el, angolo)
                }
            }
        }
        anima(mosse)
    }

    // MARK: Animazione

    private struct Mossa { let el: AXUIElement; let da: CGPoint; let a: CGPoint; let misura: CGSize }
    private var timerAnim: Timer?
    private var inCorso: [Mossa] = []

    /// 0,2 s con uscita morbida, a 60 passi al secondo. Una disposizione nuova interrompe quella in corso
    /// (le finestre di prima vanno subito al loro posto finale, così niente resta a metà).
    private func anima(_ m: [Mossa]) {
        timerAnim?.invalidate()
        for x in inCorso where !m.contains(where: { CFEqual($0.el, x.el) }) { posaFinale(x) }
        inCorso = m
        let corte = m.filter { hypot($0.a.x - $0.da.x, $0.a.y - $0.da.y) > 2 }
        guard animazioni, !corte.isEmpty else { m.forEach(posaFinale); inCorso = []; return }
        let inizio = CACurrentMediaTime(), durata = 0.2
        timerAnim = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let k = min(1, (CACurrentMediaTime() - inizio) / durata)
            let e = CGFloat(1 - pow(1 - k, 3))
            if k >= 1 {
                t.invalidate()
                self.inCorso.forEach(self.posaFinale)
                self.inCorso = []
                return
            }
            for x in self.inCorso {
                AX.posa(x.el, CGPoint(x: x.da.x + (x.a.x - x.da.x) * e, y: x.da.y + (x.a.y - x.da.y) * e))
            }
        }
    }

    private func posaFinale(_ x: Mossa) {
        AX.posa(x.el, x.a)
        AX.misura(x.el, x.misura)      // dopo lo spostamento: lo schermo non la stringe più
        AX.posa(x.el, x.a)
    }

    /// Fila spenta o chiusa: nessuna finestra deve restare nell'angolo. Tornano tutte sullo schermo, a cascata.
    func libera() {
        for st in strisce.values {
            guard let sc = NSScreen.screens.first(where: { $0.numero == st.schermo }) else { continue }
            let area = sc.areaAX.insetBy(dx: g, dy: g)
            for (k, f) in st.colonne.flatMap(\.finestre).enumerated() {
                let r = AX.cornice(f.el) ?? .zero
                if r.minX >= area.minX - 1 && r.maxX <= area.maxX + 1 { continue }   // già tutta in vista: resta dov'è
                let off = CGFloat(k % 8) * 28
                let w = min(r.width > 0 ? r.width : area.width / 2, area.width - off)
                AX.posa(f.el, CGPoint(x: area.minX + off, y: area.minY + off))
                AX.misura(f.el, CGSize(width: w, height: min(r.height > 0 ? r.height : area.height, area.height - off)))
            }
        }
        strisce = [:]
        aggiornaMappa()
    }

    // MARK: Comandi

    /// La fila su cui agire: quella della finestra col fuoco, se no quella dello schermo sotto il mouse.
    private var attiva: Striscia? {
        if let id = fuocoID, let st = strisce.values.first(where: { $0.colonne.contains { $0.finestre.contains { $0.id == id } } }) { return st }
        let m = NSEvent.mouseLocation
        let sc = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) }
        return sc.flatMap { strisce[$0.numero] }
    }

    private func porta(_ f: Finestra) {
        fuocoID = f.id
        AXUIElementSetAttributeValue(f.el, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(f.el, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: f.pid)?.activate()
    }

    private func dopo(_ st: Striscia) {
        disponi(st)
        let c = st.colonne[st.fuoco]
        porta(c.finestre[min(c.attiva, c.finestre.count - 1)])
        aggiornaMappa()
    }

    func vai(_ d: Int) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        st.centrata = false
        st.fuoco = max(0, min(st.colonne.count - 1, st.fuoco + d))
        dopo(st)
    }

    func suGiu(_ d: Int) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        c.attiva = max(0, min(c.finestre.count - 1, c.attiva + d))
        dopo(st)
    }

    func sposta(_ d: Int) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let j = st.fuoco + d
        guard j >= 0 && j < st.colonne.count else { return }
        st.colonne.swapAt(st.fuoco, j); st.fuoco = j
        dopo(st)
    }

    func larghezza(_ fr: CGFloat) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        st.colonne[st.fuoco].frazione = fr
        dopo(st)
    }

    func ciclaLarghezza() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let giri: [CGFloat] = [0.5, 2.0 / 3, 1]
        let c = st.colonne[st.fuoco]
        let i = giri.firstIndex { abs($0 - c.frazione) < 0.01 } ?? -1
        c.frazione = giri[(i + 1) % giri.count]
        dopo(st)
    }

    /// Impila: la finestra col fuoco entra nella colonna alla sua sinistra (stanno una sopra l'altra).
    func impila() {
        guard let st = attiva, st.fuoco > 0 else { return }
        let c = st.colonne[st.fuoco]
        let f = c.finestre.remove(at: c.attiva)
        let sinistra = st.colonne[st.fuoco - 1]
        sinistra.finestre.append(f); sinistra.attiva = sinistra.finestre.count - 1
        if c.finestre.isEmpty { st.colonne.remove(at: st.fuoco) } else { c.attiva = min(c.attiva, c.finestre.count - 1) }
        st.fuoco -= 1
        dopo(st)
    }

    /// Stacca: la finestra col fuoco esce dalla pila e prende un posto suo, subito a destra.
    func stacca() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        guard c.finestre.count > 1 else { return }
        let f = c.finestre.remove(at: c.attiva)
        c.attiva = min(c.attiva, c.finestre.count - 1)
        st.colonne.insert(Colonna([f], frazione: c.frazione), at: st.fuoco + 1)
        st.fuoco += 1
        dopo(st)
    }

    /// ⌃⌥⌘C: la finestra col fuoco scivola al centro dello schermo.
    func centra() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        st.centrata = true
        dopo(st)
    }

    /// ⌃⌥⌘= e ⌃⌥⌘-: un po' più larga o più stretta (passi di un decimo dello schermo).
    func allarga(_ d: CGFloat) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        c.frazione = max(0.2, min(1, (c.frazione + d * 0.1)))
        dopo(st)
    }

    /// ⌃⌥⌘]: la finestra col fuoco entra nella colonna alla sua destra.
    func impilaDestra() {
        guard let st = attiva, st.fuoco < st.colonne.count - 1 else { return }
        let c = st.colonne[st.fuoco]
        let f = c.finestre.remove(at: c.attiva)
        let destra = st.colonne[st.fuoco + 1]
        destra.finestre.append(f); destra.attiva = destra.finestre.count - 1
        if c.finestre.isEmpty { st.colonne.remove(at: st.fuoco) } else { c.attiva = min(c.attiva, c.finestre.count - 1); st.fuoco += 1 }
        dopo(st)
    }

    /// ⌃⌥⇧⌘[: esce dalla pila e prende un posto suo a sinistra.
    func staccaSinistra() {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let c = st.colonne[st.fuoco]
        guard c.finestre.count > 1 else { return }
        let f = c.finestre.remove(at: c.attiva)
        c.attiva = min(c.attiva, c.finestre.count - 1)
        st.colonne.insert(Colonna([f], frazione: c.frazione), at: st.fuoco)
        dopo(st)
    }

    /// ⌃⌥⌘T: la finestra esce dalla fila e galleggia al centro, sopra le altre. Di nuovo ⌃⌥⌘T e torna in fila.
    func galleggia() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let v = AX.valore(axApp, kAXFocusedWindowAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return }
        let el = v as! AXUIElement
        guard let id = AX.id(el) else { return }
        if galleggianti.remove(id) != nil { giro(); return }        // torna in fila al giro, dopo quella col fuoco
        galleggianti.insert(id)
        for st in strisce.values {
            for c in st.colonne { c.finestre.removeAll { $0.id == id } }
            st.colonne.removeAll { $0.finestre.isEmpty }
            st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1))
        }
        let sc = AX.cornice(el).flatMap(schermo(per:)) ?? NSScreen.main!
        let a = sc.areaAX
        let w = a.width * 0.55, h = a.height * 0.7
        AX.misura(el, CGSize(width: w, height: h))
        AX.posa(el, CGPoint(x: a.midX - w / 2, y: a.midY - h / 2))
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        strisce.values.forEach(disponi)
        aggiornaMappa()
    }

    /// La finestra col fuoco e il suo schermo (per la Griglia).
    func finestraColFuoco() -> (el: AXUIElement, schermo: NSScreen, app: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let v = AX.valore(axApp, kAXFocusedWindowAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        let el = v as! AXUIElement
        let sc = AX.cornice(el).flatMap(schermo(per:)) ?? NSScreen.main!
        return (el, sc, app.localizedName ?? "")
    }

    /// L'area dove la Griglia divide lo schermo: la stessa della fila (margini e barra in basso compresi).
    func areaGriglia(_ sc: NSScreen) -> CGRect {
        var a = sc.areaAX.insetBy(dx: g, dy: g)
        a.size.height -= Barra.riserva
        return a
    }

    /// ⌃⌥⌘G (Griglia, 19/10, idea di un commento al reel): la finestra esce dalla fila come con ⌃⌥⌘T
    /// e scivola nel riquadro scelto. ⌃⌥⌘T la rimette in fila.
    func posaInGriglia(_ el: AXUIElement, _ r: CGRect) {
        guard let id = AX.id(el) else { return }
        galleggianti.insert(id)
        for st in strisce.values {
            for c in st.colonne { c.finestre.removeAll { $0.id == id } }
            st.colonne.removeAll { $0.finestre.isEmpty }
            st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1))
        }
        strisce.values.forEach(disponi)
        let da = AX.cornice(el)?.origin ?? r.origin
        anima(inCorso + [Mossa(el: el, da: da, a: r.origin, misura: r.size)])
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        aggiornaMappa()
    }

    /// ⌃⌥⌘N: la finestra passa alla fila dell'altro schermo.
    func altroSchermo() {
        guard NSScreen.screens.count > 1, let st = attiva, !st.colonne.isEmpty,
              let i = NSScreen.screens.firstIndex(where: { $0.numero == st.schermo }) else { return }
        let dest = striscia(NSScreen.screens[(i + 1) % NSScreen.screens.count])
        let c = st.colonne[st.fuoco]
        let f = c.finestre.remove(at: c.attiva)
        if c.finestre.isEmpty { st.colonne.remove(at: st.fuoco) } else { c.attiva = min(c.attiva, c.finestre.count - 1) }
        st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1))
        let posto = dest.colonne.isEmpty ? 0 : dest.fuoco + 1
        dest.colonne.insert(Colonna([f], frazione: c.frazione), at: posto)
        dest.fuoco = posto
        disponi(st)
        dopo(dest)
    }

    /// Dal pannello: un clic su una tessera della mappa.
    func scegli(_ id: CGWindowID) {
        for st in strisce.values {
            st.centrata = false
            for (i, c) in st.colonne.enumerated() {
                if let j = c.finestre.firstIndex(where: { $0.id == id }) { st.fuoco = i; c.attiva = j; dopo(st); return }
            }
        }
    }

    /// Dalla barra: trascinata fino a `s`, il fuoco va alla colonna che sta al centro di quello che si vede.
    func scorriA(_ schermo: CGDirectDisplayID, _ s: CGFloat) {
        guard let st = strisce[schermo], !st.colonne.isEmpty, st.xs.count == st.colonne.count else { return }
        let centro = s + st.vista / 2
        let i = st.xs.indices.min { abs(st.xs[$0] + st.larghezze[$0] / 2 - centro) < abs(st.xs[$1] + st.larghezze[$1] / 2 - centro) } ?? st.fuoco
        st.scorrimento = s
        st.centrata = false
        st.fuoco = i
        dopo(st)
    }

    // MARK: Ripresa del reel (comandi da RowlineDemo, Apps/rowline/demo)

    private var linguaPrima: String?
    private var accesoPrima: Bool?          // la ripresa accende Rowline solo per le finestre finte, poi la rimette com'era
    private func comandoDemo(_ c: String, _ v: String) {
        switch c {
        case "solo":
            if v == "fine" {
                soloPid = nil; TastiVisti.shared.forzato = false; Tinta.shared.forzato = nil; Barra.extraDemo = 0
                if let l = linguaPrima { Archivio.d.set(l, forKey: "lingua") } else { Archivio.d.removeObject(forKey: "lingua") }
                linguaPrima = nil
                Pannello.shared.chiudi(); Pannello.shared.ricostruisci()
                if let a = accesoPrima, a != acceso { acceso = a } else { adotta() }
                accesoPrima = nil
            } else if let p = pid_t(v) {
                soloPid = p; TastiVisti.shared.forzato = true
                if accesoPrima == nil { accesoPrima = acceso }
                if !acceso { acceso = true }
                if linguaPrima == nil { linguaPrima = Archivio.d.string(forKey: "lingua") ?? "" }
                Archivio.d.set("en", forKey: "lingua")
                Pannello.shared.ricostruisci()
                adotta()
            }
        case "tema": Tinta.shared.forzato = v == "chiaro" ? true : v == "scuro" ? false : nil; Barra.shared.aggiorna(); Pannello.shared.ricostruisci()
        case "azione": if let a = Azione(rawValue: v) { MainActor.assumeIsolated { a.esegui() } }
        case "foglio": v == "0" ? Foglio.shared.annulla() : Foglio.shared.mostraOra()
        case "pannello":
            if v == "0" { Pannello.shared.chiudi() }
            else { if let k = StatoPannello.Scheda(rawValue: v) { Pannello.shared.stato.scheda = k }; Pannello.shared.apri() }
        case "margine": if let x = Double(v) { margine = x }
        case "riserva": if let x = Double(v) { Barra.extraDemo = CGFloat(x); disponiTutto() }
        case "sbirciata": if let x = Double(v) { sbirciata = x }
        case "scorri":
            if let f = Double(v), let st = attiva, st.xs.count == st.colonne.count, let ultimo = st.xs.last, let w = st.larghezze.last {
                let max0 = max(0, ultimo + w - st.vista)
                scorriA(st.schermo, CGFloat(f) * max0)
            }
        case "gesto": TastiVisti.shared.mostraTesto(v == "dx" ? "hand.draw" : "hand.draw", T("Tre dita", "Three fingers"))
        case "postazione":
            if v == "salva" { postazioni.removeAll { $0.nome == "Studio" || $0.nome == "Study" }; salvaPostazione("Study") }
            else if let p = postazioni.first(where: { $0.nome == "Study" }) { applica(p) }
        default: break
        }
    }

    // MARK: Postazioni

    /// Salva l'ordine e le larghezze della fila che stai usando.
    func salvaPostazione(_ nome: String) {
        guard let st = attiva, !st.colonne.isEmpty else { return }
        let posti = st.colonne.compactMap { c in c.finestre.first.map { Posto(bundle: $0.bundle, app: $0.app, frazione: Double(c.frazione)) } }
        postazioni.append(Postazione(id: UUID(), nome: nome, posti: posti))
    }

    /// Apre le app che mancano, aspetta le loro finestre (al massimo 8 s) e le mette in fila nell'ordine salvato.
    func applica(_ p: Postazione) {
        let aperte = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for b in Set(p.posti.map(\.bundle)) where !aperte.contains(b) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        let inizio = Date()
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.giro()
            let presenti = Set(self.strisce.values.flatMap { $0.colonne.flatMap { $0.finestre.map(\.bundle) } })
            if p.posti.allSatisfy({ presenti.contains($0.bundle) }) || Date().timeIntervalSince(inizio) > 8 {
                t.invalidate()
                self.ordina(p)
            }
        }
    }

    private func ordina(_ p: Postazione) {
        let m = NSEvent.mouseLocation
        guard let sc = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) ?? NSScreen.main else { return }
        let dest = striscia(sc)
        var prese: [Colonna] = []
        for posto in p.posti {
            // la prima finestra di quell'app non ancora presa, da qualunque fila
            var trovata: Finestra?
            for st in strisce.values {
                for c in st.colonne {
                    if let j = c.finestre.firstIndex(where: { f in f.bundle == posto.bundle && !prese.contains { $0.finestre.contains { $0 === f } } }) {
                        trovata = c.finestre.remove(at: j); c.attiva = max(0, min(c.attiva, c.finestre.count - 1)); break
                    }
                }
                if trovata != nil { break }
            }
            if let f = trovata { prese.append(Colonna([f], frazione: CGFloat(posto.frazione))) }
        }
        for st in strisce.values { st.colonne.removeAll { $0.finestre.isEmpty }; st.fuoco = min(st.fuoco, max(0, st.colonne.count - 1)) }
        dest.colonne = prese + dest.colonne
        dest.fuoco = 0; dest.scorrimento = 0; dest.centrata = false
        strisce.values.filter { $0 !== dest }.forEach(disponi)
        if !dest.colonne.isEmpty { dopo(dest) } else { aggiornaMappa() }
    }

    /// L'app della finestra col fuoco, per "lasciala libera".
    var appInFuoco: (nome: String, bundle: String)? {
        guard let st = attiva, !st.colonne.isEmpty else { return nil }
        let c = st.colonne[st.fuoco]
        guard let f = c.finestre[safe: c.attiva] else { return nil }
        return (f.app, f.bundle)
    }

    func liberaApp(_ bundle: String) {
        guard !bundle.isEmpty, !escluse.contains(bundle) else { return }
        // prima la si rimette sullo schermo, poi esce dalla fila
        for st in strisce.values {
            for c in st.colonne { for f in c.finestre where f.bundle == bundle { mettiInVista(f, st) } }
        }
        escluse.append(bundle)
    }

    private func mettiInVista(_ f: Finestra, _ st: Striscia) {
        guard let sc = NSScreen.screens.first(where: { $0.numero == st.schermo }) else { return }
        let a = sc.areaAX.insetBy(dx: 60, dy: 40)
        AX.posa(f.el, CGPoint(x: a.minX, y: a.minY))
        AX.misura(f.el, CGSize(width: a.width * 0.6, height: a.height))
    }

    // MARK: Mappa per il pannello

    func aggiornaMappa() {
        var out: [StrisciaVista] = []
        for (k, sc) in NSScreen.screens.enumerated() {
            guard let st = strisce[sc.numero], !st.colonne.isEmpty, st.xs.count == st.colonne.count else { continue }
            let cols = st.colonne.enumerated().map { i, c in
                ColonnaVista(id: i, x: st.xs[i], w: st.larghezze[i],
                             finestre: c.finestre.map { TesseraVista(id: $0.id, app: $0.app, bundle: $0.bundle) },
                             attiva: c.attiva, fuoco: i == st.fuoco)
            }
            let nome = NSScreen.screens.count > 1 ? (sc.localizedName.isEmpty ? T("Schermo \(k + 1)", "Display \(k + 1)") : sc.localizedName) : ""
            out.append(StrisciaVista(id: st.schermo, nome: nome, colonne: cols, scorrimento: st.scorrimento, vista: st.vista, alta: st.alta))
        }
        mappa = out
        Condiviso.scrivi(out)
    }

    var quante: Int { mappa.reduce(0) { $0 + $1.colonne.reduce(0) { $0 + $1.finestre.count } } }
}

extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

// MARK: - Dati finti (solo per le prove del pannello e per le schermate pubbliche, mai finestre vere)
extension Motore {
    func caricaDemo() {
        let b = ["com.google.Chrome", "com.apple.dt.Xcode", "com.apple.Notes", "com.apple.finder", "com.apple.Music"]
        let fr: [CGFloat] = [0.5, 2.0 / 3, 0.5, 0.5]
        var x: CGFloat = 0
        var cols: [ColonnaVista] = []
        for i in 0..<4 {
            let w = fr[i] * 1420
            let f = i == 2 ? [TesseraVista(id: 3, app: "Notes", bundle: b[2]), TesseraVista(id: 4, app: "Finder", bundle: b[3])]
                           : [TesseraVista(id: CGWindowID(i < 2 ? i : i + 1), app: "", bundle: b[i < 2 ? i : 4])]
            cols.append(ColonnaVista(id: i, x: x, w: w, finestre: f, attiva: 0, fuoco: i == 1))
            x += w + 10
        }
        mappa = [StrisciaVista(id: 1, nome: "", colonne: cols, scorrimento: 720, vista: 1420, alta: 860)]
    }
}

// MARK: - Postazioni (salvate in UserDefaults)

struct Posto: Codable, Hashable { var bundle: String; var app: String; var frazione: Double }
struct Postazione: Codable, Identifiable, Hashable {
    var id: UUID; var nome: String; var posti: [Posto]
    static func carica() -> [Postazione] {
        Archivio.d.data(forKey: "postazioni").flatMap { try? JSONDecoder().decode([Postazione].self, from: $0) } ?? []
    }
    static func salva(_ p: [Postazione]) { Archivio.d.set(try? JSONEncoder().encode(p), forKey: "postazioni") }
}

// MARK: - Lo stato per Pulsar (tessera Rowline nell'Isola)
// ~/Library/Application Support/Rowline/fila.json + notifica distribuita local.author.rowline.fila. Solo nomi e larghezze.

enum Condiviso {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Rowline/fila.json")
    static func scrivi(_ m: [StrisciaVista]) {
        let schermi: [[String: Any]] = m.map { st in
            ["vista": st.vista, "scorrimento": st.scorrimento,
             "colonne": st.colonne.map { c in ["x": c.x, "w": c.w, "fuoco": c.fuoco, "app": c.finestre[safe: c.attiva]?.app ?? "",
                                               "bundle": c.finestre[safe: c.attiva]?.bundle ?? "", "pila": c.finestre.count,
                                               "id": c.finestre[safe: c.attiva].map { Int($0.id) } ?? 0] }]
        }
        let j: [String: Any] = ["schermi": schermi, "acceso": Motore.shared.acceso, "quando": Date().timeIntervalSince1970]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: file, options: .atomic) }
        DistributedNotificationCenter.default().postNotificationName(Archivio.notificaFila, object: nil, deliverImmediately: true)
    }
}
