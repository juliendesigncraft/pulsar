// Pulsar — BORDI (11/10/2026): ghiere e colonna dell'Agente si spostano lungo i bordi.
// Richiesta dell'autore: "dammi la possibilità di spostare questi nuovi elementi dove voglio".
// Si trascinano su e giù lungo il bordo o fino al bordo opposto; restano sempre attaccati a un bordo coi
// raccordi concavi (staccati solo finché li tieni). Quando si staccano fanno una goccia: il collo si allunga,
// si assottiglia e si rompe con un "plip" (sounds/goccia). Due elementi sullo stesso bordo che si avvicinano
// si attraggono e si fondono in una colonna unica; trascinandone uno via si separano di nuovo.
// Niente timer quando è tutto fermo: si lavora solo sugli eventi del mouse e su animazioni brevi.

import AppKit
import SwiftUI
import QuartzCore

enum EdgeSide: String { case left, right }

// MARK: - Zone dove il trascinamento resta alla vista

/// Un rettangolo (coordinate della finestra, dall'alto) dove il clic-e-trascina appartiene al controllo:
/// la corona della ghiera (solo l'anello, il centro si può prendere) e i cursori del mixer.
struct DragBlock: Equatable {
    let rect: CGRect
    let ring: Bool
}

struct DragBlockKey: PreferenceKey {
    static var defaultValue: [DragBlock] { [] }
    static func reduce(value: inout [DragBlock], nextValue: () -> [DragBlock]) { value.append(contentsOf: nextValue()) }
}

extension View {
    func dragBlock(ring: Bool = false) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: DragBlockKey.self, value: [DragBlock(rect: g.frame(in: .global), ring: ring)])
        })
    }
}

// MARK: - Lo stato visivo di un elemento del bordo

/// Solo la forma (raccordi o goccia): un oggetto a parte, così a ogni fotogramma del motore si ridisegna la sagoma
/// e non tutta la ghiera (11/10 sera: prima ogni fotogramma ricalcolava le 40 tacche e il 15% dei fotogrammi sforava).
final class EdgeForm: ObservableObject {
    @Published var attach: CGFloat = 1          // 1 attaccato (raccordi concavi), 0 goccia libera (angoli tondi)
}

/// Rilegge la sagoma quando cambia la forma, senza toccare il contenuto.
struct EdgeFormed<M: ViewModifier>: ViewModifier {
    @ObservedObject var form: EdgeForm
    let make: () -> M
    func body(content: Content) -> some View { content.modifier(make()) }
}

final class EdgeLook: ObservableObject {
    @Published var side: EdgeSide
    let form = EdgeForm()
    var attach: CGFloat {                      // inoltra alla forma: cambiarla non ridisegna chi osserva solo EdgeLook
        get { form.attach }
        set { form.attach = newValue }
    }
    @Published var joinTop: CGFloat = 0         // larghezza in comune con l'elemento sopra (0 = raccordo normale)
    @Published var joinBottom: CGFloat = 0
    @Published var squash = CGSize(width: 1, height: 1)
    @Published var screenID: CGDirectDisplayID = 0    // per l'aspetto Sfondo: quale sfondo sta dietro
    @Published var libero = false                    // 21/10: lasciato lontano dai bordi, sta lì e resta in vista
    var blocks: [DragBlock] = []                // non pubblicato: lo legge solo il mouse
    init(side: EdgeSide) { self.side = side }

    func blocked(_ p: CGPoint) -> Bool {
        blocks.contains { b in
            guard b.rect.insetBy(dx: -3, dy: -3).contains(p) else { return false }
            guard b.ring else { return true }
            let d = hypot(p.x - b.rect.midX, p.y - b.rect.midY)
            return d > 40 && d < b.rect.width / 2 + 4
        }
    }
    var anchor: UnitPoint { side == .left ? .leading : .trailing }
}

/// La forma degli elementi del bordo: la linguetta coi raccordi concavi (TabShape) generalizzata.
/// attach: da raccordi concavi (1) ad angoli tondi da goccia (0). joinTop/joinBottom: quando due elementi
/// sono fusi, l'estremità continua dritta con la larghezza in comune e si raccorda con una curva concava.
struct DockShape: Shape {
    var r: CGFloat
    var side: EdgeSide
    var attach: CGFloat
    var joinTop: CGFloat
    var joinBottom: CGFloat

    init(r: CGFloat, look: EdgeLook) {
        self.r = r; side = look.side; attach = look.attach; joinTop = look.joinTop; joinBottom = look.joinBottom
    }

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(attach, AnimatablePair(joinTop, joinBottom)) }
        set { attach = newValue.first; joinTop = newValue.second.first; joinBottom = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let p = DockShape.rightPath(rect, r: r, a: attach, cTop: joinTop, cBot: joinBottom)
        guard side == .left else { return p }
        return p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width - 2 * rect.minX, y: 0))
    }

    /// Disegnata col bordo a destra (come TabShape); a sinistra si specchia.
    static func rightPath(_ rect: CGRect, r: CGFloat, a rawA: CGFloat, cTop: CGFloat, cBot: CGFloat) -> Path {
        // 21/10: libero (lontano dai bordi) non ha un lato attaccato allo schermo: angoli tondi su tutti e quattro,
        // a capsula se è basso (la colonna in orizzontale). Prima il lato del bordo restava dritto e faceva le punte.
        if rawA <= 0.02 { return Path(roundedRect: rect, cornerRadius: min(22, rect.height / 2, rect.width / 2), style: .continuous) }
        let a = max(-0.35, min(1, rawA))        // sotto 0: la molla della goccia arrotonda un po' di più
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        let w = rect.width, k: CGFloat = 0.5523
        let bt = y0 + r, bb = y1 - r
        var p = Path()
        // estremità alta
        let ct = max(0, min(w, cTop))
        let rT = min(r, max(0, (w - ct) / 2))
        let sx = x1 - ct
        let sTy = bt + rT * (1 - 2 * a)
        p.move(to: CGPoint(x: x1, y: y0))
        if ct > 0.01 { p.addLine(to: CGPoint(x: sx, y: y0)) }
        p.addLine(to: CGPoint(x: sx, y: sTy))
        p.addCurve(to: CGPoint(x: sx - rT, y: bt),
                   control1: CGPoint(x: sx, y: sTy + k * rT * (2 * a - 1)),
                   control2: CGPoint(x: sx - rT + k * rT, y: bt))
        p.addLine(to: CGPoint(x: x0 + rT, y: bt))
        if rT > 0.01 {
            p.addArc(center: CGPoint(x: x0 + rT, y: bt + rT), radius: rT, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        }
        // estremità bassa
        let cb = max(0, min(w, cBot))
        let rB = min(r, max(0, (w - cb) / 2))
        p.addLine(to: CGPoint(x: x0, y: bb - rB))
        if rB > 0.01 {
            p.addArc(center: CGPoint(x: x0 + rB, y: bb - rB), radius: rB, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        }
        let bx = x1 - cb
        let sBy = bb - rB * (1 - 2 * a)
        p.addLine(to: CGPoint(x: bx - rB, y: bb))
        p.addCurve(to: CGPoint(x: bx, y: sBy),
                   control1: CGPoint(x: bx - rB + k * rB, y: bb),
                   control2: CGPoint(x: bx, y: sBy - k * rB * (2 * a - 1)))
        p.addLine(to: CGPoint(x: bx, y: y1))
        if cb > 0.01 { p.addLine(to: CGPoint(x: x1, y: y1)) }
        p.closeSubpath()
        return p
    }
}

// MARK: - La sagoma sulla scheda grafica (11/10 sera)

/// Il fondo pieno (aspetti Notte e Scuro) disegnato come livello Core Animation: un gradiente mascherato dalla sagoma.
/// Prima lo dipingeva SwiftUI col processore a ogni cambio di forma, ed era la causa dei fotogrammi persi mentre
/// la goccia si staccava e si riattaccava. Ora cambiare forma vuol dire solo cambiare il tracciato della maschera.
struct DockLayerFill: NSViewRepresentable {
    let r: CGFloat
    let side: EdgeSide
    let attach: CGFloat, joinTop: CGFloat, joinBottom: CGFloat
    let top: NSColor, bottom: NSColor

    init(r: CGFloat, look: EdgeLook, top: NSColor, bottom: NSColor) {
        self.r = r; side = look.side; attach = look.attach; joinTop = look.joinTop; joinBottom = look.joinBottom
        self.top = top; self.bottom = bottom
    }

    func makeNSView(context: Context) -> DockLayerView { DockLayerView() }
    func updateNSView(_ v: DockLayerView, context: Context) { v.spec = self }
}

final class DockLayerView: NSView {
    private let grad = CAGradientLayer()
    private let mask = CAShapeLayer()
    var spec: DockLayerFill? { didSet { apply() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(grad)
        mask.fillColor = NSColor.black.cgColor
        grad.mask = mask
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }      // solo fondo: i clic passano
    override func layout() { super.layout(); apply() }

    private func apply() {
        guard let s = spec else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let b = bounds
        grad.frame = b; mask.frame = b
        grad.colors = [s.top.cgColor, s.bottom.cgColor]
        grad.startPoint = CGPoint(x: 0.5, y: isFlipped ? 0 : 1); grad.endPoint = CGPoint(x: 0.5, y: isFlipped ? 1 : 0)
        // la sagoma di SwiftUI è disegnata dall'alto: se la vista non è capovolta, la si ribalta
        var path = DockShape.rightPath(CGRect(origin: .zero, size: b.size), r: s.r, a: s.attach, cTop: s.joinTop, cBot: s.joinBottom)
        if s.side == .left { path = path.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -b.width, y: 0)) }
        if !isFlipped { path = path.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -b.height)) }
        mask.path = path.cgPath
        CATransaction.commit()
    }
}

// MARK: - La goccia: collo e ponti disegnati dietro gli elementi mentre li trascini

/// Clessidra fra due segmenti paralleli A (a0-a1) e B (b0-b1): i fianchi si stringono verso il centro.
/// waist 1 = dritta, 0 = rotta. Sempre la stessa struttura di punti, così Core Animation la può trasformare.
private func hourglass(_ a0: CGPoint, _ a1: CGPoint, _ b0: CGPoint, _ b1: CGPoint, waist: CGFloat) -> CGPath {
    func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
    func lerp(_ p: CGPoint, _ q: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t) }
    let mA = mid(a0, a1), mB = mid(b0, b1), c = mid(mA, mB)
    let ux = mB.x - mA.x, uy = mB.y - mA.y
    let h: CGFloat = 0.45                                         // maniglie lunghe: profilo tondo da liquido, non a rombo (11/10 sera)
    let hx = ux * h, hy = uy * h
    let w0 = lerp(c, mid(a0, b0), waist), w1 = lerp(c, mid(a1, b1), waist)
    let p = CGMutablePath()
    p.move(to: a0)
    p.addCurve(to: w0, control1: CGPoint(x: a0.x + hx, y: a0.y + hy), control2: CGPoint(x: w0.x - hx, y: w0.y - hy))
    p.addCurve(to: b0, control1: CGPoint(x: w0.x + hx, y: w0.y + hy), control2: CGPoint(x: b0.x - hx, y: b0.y - hy))
    p.addLine(to: b1)
    p.addCurve(to: w1, control1: CGPoint(x: b1.x - hx, y: b1.y - hy), control2: CGPoint(x: w1.x + hx, y: w1.y + hy))
    p.addCurve(to: a1, control1: CGPoint(x: w1.x - hx, y: w1.y - hy), control2: CGPoint(x: a1.x + hx, y: a1.y + hy))
    p.closeSubpath()
    return p
}

/// Una finestra trasparente grande quanto lo schermo, sotto gli elementi, che esiste solo durante un
/// trascinamento. Ogni pezzo di goccia è un gradiente (gli stessi colori della superficie) mascherato dal collo.
private final class GooWindow: NSPanel {
    private var pieces: [String: (grad: CAGradientLayer, mask: CAShapeLayer)] = [:]
    private var origin = CGPoint.zero

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)   // sotto ghiere e colonna
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        contentView = v
        origin = screen.frame.origin
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func moveTo(_ screen: NSScreen) {
        guard screen.frame.origin != origin || screen.frame.size != frame.size else { return }
        setFrame(screen.frame, display: false)
        origin = screen.frame.origin
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (_, p) in pieces { p.grad.frame = contentView!.bounds; p.mask.frame = contentView!.bounds; p.mask.path = nil }
        CATransaction.commit()
    }

    /// Da coordinate dello schermo a coordinate del livello.
    func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }

    private func piece(_ key: String) -> (grad: CAGradientLayer, mask: CAShapeLayer) {
        if let p = pieces[key] { return p }
        let g = CAGradientLayer(), m = CAShapeLayer()
        g.frame = contentView!.bounds; m.frame = contentView!.bounds
        m.fillColor = NSColor.black.cgColor
        g.mask = m
        contentView!.layer!.addSublayer(g)
        pieces[key] = (g, m)
        return (g, m)
    }

    /// Disegna un pezzo. span: da dove a dove (in y dello schermo) va il gradiente della superficie.
    func set(_ key: String, _ path: CGPath?, colors: (NSColor, NSColor), span: ClosedRange<CGFloat>, opacity: Float = 1) {
        let p = piece(key)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        p.mask.removeAllAnimations()
        p.mask.path = path
        p.grad.colors = [colors.0.cgColor, colors.1.cgColor]
        let hgt = max(1, frame.height)
        p.grad.startPoint = CGPoint(x: 0.5, y: (span.upperBound - origin.y) / hgt)
        p.grad.endPoint = CGPoint(x: 0.5, y: (span.lowerBound - origin.y) / hgt)
        p.grad.opacity = opacity
        CATransaction.commit()
    }

    func has(_ key: String) -> Bool { pieces[key]?.mask.path != nil }

    /// Il collo si rompe: torna verso `to` (di solito un punto sul bordo) e sparisce.
    func snap(_ key: String, to collapsed: CGPath, duration: Double = 0.3) {
        guard let p = pieces[key], let from = p.mask.path else { return }
        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = from
        anim.toValue = collapsed
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        p.mask.path = nil
        p.mask.add(anim, forKey: "snap")
        CATransaction.commit()
    }

    func fadeOut(_ done: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            animator().alphaValue = 0
        }, completionHandler: done)
    }
}

extension EdgeDock {
    /// Quanti fotogrammi del motore hanno sforato (più lunghi di un fotogramma e mezzo a 120 Hz). Per la prova della goccia.
    static var frames = 0, slowFrames = 0
    static func frameReport() -> String {
        let r = " (fotogrammi \(frames), lenti \(slowFrames))"; frames = 0; slowFrames = 0; return r
    }
}

/// CADisplayLink vuole un oggetto Objective-C come bersaglio: questo inoltra al motore.
private final class LinkProxy: NSObject {
    let f: (CADisplayLink) -> Void
    init(_ f: @escaping (CADisplayLink) -> Void) { self.f = f }
    @objc func fire(_ l: CADisplayLink) { f(l) }
}

// MARK: - Il regista dei bordi

final class EdgeDock {
    static let shared = EdgeDock()

    /// Un elemento attaccato al bordo (ghiera, luce, colonna dell'Agente). Il modulo che lo possiede
    /// fornisce misure e stato; il regista decide dove sta e quando esce.
    final class Item {
        let id: String
        let defaultSide: EdgeSide
        let look: EdgeLook
        weak var win: NSWindow?
        var radius: () -> CGFloat = { 16 }
        var size: () -> NSSize = { NSSize(width: 44, height: 200) }
        var defaultTop: (NSRect) -> CGFloat = { $0.midY }     // dato il visibleFrame, la cima della finestra
        var forced: () -> Bool? = { nil }                      // true sempre fuori, false sempre via, nil segue il mouse
        var reach: CGFloat = 20                                // margine della fascia che lo fa uscire
        var apply: (Bool) -> Void = { _ in }                   // rifà il layout del modulo (animato o no)
        var onReveal: () -> Void = {}
        var willDrag: () -> Void = {}
        var colors: () -> (NSColor, NSColor) = { (.black, .black) }

        // dove sta (salvato in UserDefaults, chiave bordo.<id>)
        var side: EdgeSide
        var topFrac: CGFloat?                                  // distanza della cima dal bordo alto del visibleFrame, in frazione
        var screenID: CGDirectDisplayID?
        var glued = false                                      // fuso con l'elemento subito sopra
        /// 21/10, dal reel di will.geez: lasciato lontano dai bordi resta libero lì, sempre in vista, finché non lo si
        /// riporta su un bordo. L'angolo in basso a sinistra della finestra, in frazione del visibleFrame.
        var floating: CGPoint?

        // stato
        var revealed = false
        var dragging = false
        var settling = false                                   // 11/10 sera: la molla del rilascio la guida il motore
        var lastSize = NSSize.zero
        fileprivate var shownFrame = NSRect.zero
        fileprivate var hiddenFrame = NSRect.zero
        fileprivate var isShown = false
        fileprivate var head = ""                              // primo elemento della colonna fusa

        init(id: String, side: EdgeSide) {
            self.id = id
            defaultSide = side
            // chiavi dinamiche bordo.<id>: restano su UserDefaults.standard (anche sotto e in Personale/dimostrazione.swift)
            let d = UserDefaults.standard.dictionary(forKey: "bordo.\(id)")
            self.side = (d?["side"] as? String).flatMap(EdgeSide.init(rawValue:)) ?? side
            topFrac = (d?["top"] as? Double).map { CGFloat($0) }
            screenID = (d?["screen"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
            glued = false          // 11/10 sera: niente colonne fuse (il riempimento faceva il rettangolo)
            if let f = d?["free"] as? [Double], f.count == 2 { floating = CGPoint(x: f[0], y: f[1]) }
            look = EdgeLook(side: self.side)
            look.libero = floating != nil
            if floating != nil { look.attach = 0 }
        }

        fileprivate func save() {
            var d: [String: Any] = ["side": side.rawValue, "glued": glued]
            if let topFrac { d["top"] = Double(topFrac) }
            if let screenID { d["screen"] = NSNumber(value: screenID) }
            if let floating { d["free"] = [Double(floating.x), Double(floating.y)] }
            UserDefaults.standard.set(d, forKey: "bordo.\(id)")
        }
    }

    private(set) var items: [Item] = []
    private var monitors: [Any] = []
    private var hideWork: [String: DispatchWorkItem] = [:]

    // costanti del gesto
    private let threshold: CGFloat = 5          // sotto questi punti è un clic
    private let detachDist: CGFloat = 64        // quanto tirare in dentro prima che la goccia si stacchi
    private let breakDist: CGFloat = 44         // quanto allontanarsi da un elemento fuso prima che il ponte si rompa
    private let glueDist: CGFloat = 60          // al rilascio, sotto questa distanza due elementi si attaccano
    private let attractDist: CGFloat = 80       // da qui in giù un elemento che arriva comincia ad attirare

    // MARK: schermi

    static var defaultScreen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    static func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    func screen(of it: Item) -> NSScreen {
        if let id = it.screenID, let s = NSScreen.screens.first(where: { EdgeDock.displayID($0) == id }) { return s }
        return EdgeDock.defaultScreen
    }
    private func screen(at p: NSPoint) -> NSScreen? { NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } }

    // MARK: registro

    func register(_ it: Item, window: NSWindow) {
        it.win = window
        // 12/10: l'ombra minima del tema (temi.swift, Ombra), sulla sagoma vera dell'elemento
        Ombra.attacca(window) { [weak it] rect in
            guard let it else { return CGPath(rect: rect, transform: nil) }
            var p = DockShape.rightPath(rect, r: it.radius(), a: it.look.attach, cTop: it.look.joinTop, cBot: it.look.joinBottom)
            if it.look.side == .left { p = p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0)) }
            p = p.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -rect.height))   // da "dall'alto" a "dal basso"
            return p.cgPath
        }
        it.lastSize = it.size()
        items.removeAll { $0.id == it.id }
        items.append(it)
        if monitors.isEmpty { installMonitors() }
    }

    func unregister(_ it: Item) {
        items.removeAll { $0 === it }
        if drag?.item === it { drag = nil; goo?.orderOut(nil); goo = nil }
        if press?.item === it { press = nil }
        if items.isEmpty { monitors.forEach { NSEvent.removeMonitor($0) }; monitors = [] }
    }

    func isDragging(_ it: Item) -> Bool { it.dragging }

    /// Tutti al loro posto di partenza (menu).
    func resetAll() {
        for it in items {
            UserDefaults.standard.removeObject(forKey: "bordo.\(it.id)")
            it.side = it.defaultSide; it.topFrac = nil; it.screenID = nil; it.glued = false
            it.floating = nil; it.look.libero = false; it.look.attach = 1
            it.look.side = it.side
        }
        for k in ["ghiera", "luce", "agente"] { UserDefaults.standard.removeObject(forKey: "bordo.\(k)") }
        applyAll(animated: true)
    }

    // MARK: dove sta ogni elemento

    private func storedTop(_ it: Item, _ vf: NSRect) -> CGFloat {
        if let f = it.topFrac { return vf.maxY - f * vf.height }
        return it.defaultTop(vf)
    }

    /// La cima resta dentro lo schermo; i raccordi possono sporgere di r sopra e sotto.
    private func clampTop(_ t: CGFloat, _ h: CGFloat, _ vf: NSRect, _ r: CGFloat) -> CGFloat {
        min(vf.maxY + r, max(vf.minY - r + h, t))
    }

    /// Calcola posizioni, colonne fuse e raccordi di tutti gli elementi fermi.
    private func solve() {
        var slots: [String: [Item]] = [:]
        for it in items where !it.dragging && it.floating != nil {
            // libero: sta dove l'hanno lasciato, dentro lo schermo, sempre in vista
            let vf = screen(of: it).visibleFrame, s = it.size(), f = it.floating!
            let x = min(max(vf.minX + f.x * vf.width, vf.minX + 4), vf.maxX - s.width - 4)
            let y = min(max(vf.minY + f.y * vf.height, vf.minY + 4), vf.maxY - s.height - 4)
            it.shownFrame = NSRect(x: x, y: y, width: s.width, height: s.height)
            it.hiddenFrame = it.shownFrame
            it.isShown = true
            it.head = it.id
        }
        for it in items where !it.dragging && it.floating == nil {
            slots["\(EdgeDock.displayID(screen(of: it)))-\(it.side.rawValue)", default: []].append(it)
        }
        var joins: [String: (top: CGFloat, bottom: CGFloat)] = [:]
        for (_, list) in slots {
            let sc = screen(of: list[0]), sf = sc.frame, vf = sc.visibleFrame
            let sorted = list.sorted { storedTop($0, vf) > storedTop($1, vf) }
            var prev: Item?
            for it in sorted {
                let s = it.size()
                var t: CGFloat
                if it.glued, let p = prev {
                    t = p.shownFrame.minY
                    it.topFrac = (vf.maxY - t) / max(1, vf.height)      // in memoria: tiene l'ordine
                    it.head = p.head
                } else {
                    t = clampTop(storedTop(it, vf), s.height, vf, it.radius())
                    if let p = prev, t > p.shownFrame.minY - EdgeDock.spacing { t = p.shownFrame.minY - EdgeDock.spacing }   // mai a contatto
                    it.head = it.id
                }
                let shownX = it.side == .left ? sf.minX : sf.maxX - s.width
                let hiddenX = it.side == .left ? sf.minX - s.width - 2 : sf.maxX + 2
                it.shownFrame = NSRect(x: shownX, y: t - s.height, width: s.width, height: s.height)
                it.hiddenFrame = NSRect(x: hiddenX, y: t - s.height, width: s.width, height: s.height)
                it.isShown = it.forced() ?? it.revealed
                if it.glued, let p = prev {
                    // fusi: la parte in comune è larga quanto il più stretto; se uno solo è fuori, raccordi normali
                    let c = p.isShown == it.isShown ? min(p.shownFrame.width, s.width) : 0
                    joins[p.id, default: (0, 0)].bottom = c
                    joins[it.id, default: (0, 0)].top = c
                }
                prev = it
            }
        }
        for it in items {
            let sid = EdgeDock.displayID(screen(of: it))
            if it.look.screenID != sid { it.look.screenID = sid }
        }
        for it in items where !it.dragging {
            let j = joins[it.id] ?? (0, 0)
            if abs(it.look.joinTop - j.top) > 0.5 || abs(it.look.joinBottom - j.bottom) > 0.5 {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                    it.look.joinTop = j.top; it.look.joinBottom = j.bottom
                }
            }
        }
    }

    /// La cornice della finestra adesso (fuori o nascosta oltre il bordo).
    func frame(for it: Item) -> NSRect {
        if it.dragging || it.settling, let w = it.win { return w.frame }
        solve()
        return it.isShown ? it.shownFrame : it.hiddenFrame
    }
    func shownFrame(for it: Item) -> NSRect {
        if it.dragging || it.settling, let w = it.win { return w.frame }
        solve()
        return it.shownFrame
    }

    /// Stesso tempo e stessa curva per tutti: gli elementi fusi escono e rientrano insieme.
    func move(_ win: NSWindow, to f: NSRect, animated: Bool) {
        guard win.frame != f, settle?.item.win !== win else { return }   // mentre il motore la guida, nessun altro la tocca
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                win.animator().setFrame(f, display: true)
            }
        } else { win.setFrame(f, display: true) }
    }

    /// Un elemento ha cambiato misura (es. il mixer si apre): chi è fuso sotto deve seguirlo.
    func sizeChanged(_ it: Item) {
        let s = it.size()
        guard s != it.lastSize else { return }
        it.lastSize = s
        DispatchQueue.main.async { [weak self] in
            self?.items.filter { $0 !== it }.forEach { $0.apply(true) }
        }
    }

    private func applyAll(animated: Bool) { items.forEach { $0.apply(animated) } }

    // MARK: uscire e rientrare (come il Dock)

    private func group(of it: Item) -> [Item] { items.filter { !$0.dragging && $0.head == it.head } }

    func reveal(_ it: Item, hideAfter: Double? = nil) {
        if GhieraLook.shared.mode == .sfondo { WallpaperTint.shared.refreshIfChanged() }   // sfondo cambiato senza avviso
        solve()
        let g = group(of: it)
        hideWork[it.head]?.cancel(); hideWork[it.head] = nil
        for x in g where !x.revealed { x.revealed = true; x.onReveal() }
        g.forEach { $0.apply(true) }
        if let hideAfter { scheduleHide(it.head, hideAfter) }
    }

    func conceal(_ it: Item) {
        guard !it.dragging else { return }
        solve()
        let g = group(of: it)
        hideWork[it.head]?.cancel(); hideWork[it.head] = nil
        g.forEach { $0.revealed = false }
    }

    func toggle(_ it: Item) {
        solve()
        if it.isShown && it.forced() == nil {
            conceal(it); group(of: it).forEach { $0.apply(true) }
        } else { reveal(it, hideAfter: 3) }
    }

    private func scheduleHide(_ head: String, _ after: Double) {
        guard hideWork[head] == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWork[head] = nil
            let g = self.items.filter { !$0.dragging && $0.head == head }
            g.forEach { $0.revealed = false }
            g.forEach { $0.apply(true) }
        }
        hideWork[head] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }

    private func mouseMoved() {
        guard drag == nil, press == nil, !items.isEmpty, !demoActive else { return }
        let p = NSEvent.mouseLocation
        // leggero: se niente è fuori e il mouse non tocca un bordo, non c'è niente da calcolare
        if !items.contains(where: { $0.revealed }) {
            guard let sc = screen(at: p), p.x <= sc.frame.minX + 3 || p.x >= sc.frame.maxX - 4 else { return }
        }
        solve()
        let heads = Set(items.filter { !$0.dragging && $0.floating == nil }.map(\.head))
        for head in heads {
            let g = items.filter { !$0.dragging && $0.head == head }
            guard let first = g.first, g.contains(where: { $0.forced() == nil }) else { continue }
            let sf = screen(of: first).frame
            let band = g.map(\.shownFrame).reduce(NSRect.null) { $0.union($1) }
            let reach = g.map(\.reach).max() ?? 20
            let revealed = g.contains { $0.forced() == nil && $0.revealed }
            if !revealed {
                let atEdge = first.side == .left ? p.x <= sf.minX + 3 : p.x >= sf.maxX - 4
                if atEdge && sf.contains(p) && p.y <= band.maxY + reach && p.y >= band.minY - reach { reveal(first) }
                continue
            }
            let dy = reach > 40 ? reach : 24
            let nearX = first.side == .left ? p.x <= band.maxX + 36 && p.x >= sf.minX - 2 : p.x >= band.minX - 36 && p.x <= sf.maxX + 2
            let near = nearX && p.y <= band.maxY + dy && p.y >= band.minY - dy
            if near { hideWork[head]?.cancel(); hideWork[head] = nil } else { scheduleHide(head, 0.5) }
        }
    }

    // MARK: trascinare

    fileprivate struct Press { let item: Item; let win: NSWindow; let start: NSPoint }
    fileprivate final class Drag {
        let item: Item
        let start: NSPoint
        let startFrame: NSRect
        let grab: CGVector
        var free = false
        var side: EdgeSide
        var screen: NSScreen
        var partners: [(item: Item, above: Bool)] = []
        var attract: (item: Item, above: Bool, gap: CGFloat)?
        // 11/10 sera, "per niente fluida o liquida": un solo motore fisico al ritmo dello schermo guida posizione,
        // forma, collo e deformazione nello stesso fotogramma. Prima erano quattro orologi diversi.
        var mouse: NSPoint
        var pos: CGPoint
        var vel = CGVector.zero
        var attach: CGFloat = 1, attachVel: CGFloat = 0
        var sq = CGVector(dx: 1, dy: 1), sqVel = CGVector.zero
        var stub: (ex: CGFloat, yc: CGFloat, hb: CGFloat, bx: CGFloat, age: Double)?   // il collo rotto che rientra nel bordo
        var settling = false
        var toFloat = false                    // 21/10: il rilascio lo posa libero, non sul bordo
        var finalFrame = NSRect.zero
        var settleAge: Double = 0
        init(item: Item, start: NSPoint, frame: NSRect, side: EdgeSide, screen: NSScreen) {
            self.item = item; self.start = start; startFrame = frame; self.side = side; self.screen = screen
            grab = CGVector(dx: start.x - frame.minX, dy: start.y - frame.minY)
            mouse = start; pos = frame.origin
        }
    }
    fileprivate var press: Press?
    fileprivate var drag: Drag?
    var demoActive = false
    fileprivate var demoMouse: NSPoint?
    private var goo: GooWindow?
    fileprivate var settle: Drag?                 // il rilascio in corso (la molla verso il bordo)
    private var link: CADisplayLink?
    private var linkProxy: LinkProxy?
    private var lastTick: CFTimeInterval = 0

    private func installMonitors() {
        let move: (NSEvent) -> Void = { [weak self] _ in self?.mouseMoved() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: move) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { move($0); return $0 }) { monitors.append(l) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] e in
            guard let self else { return e }
            switch e.type {
            case .leftMouseDown: return self.mouseDown(e)
            case .leftMouseDragged: return self.mouseDragged(e)
            default: return self.mouseUp(e)
            }
        }) { monitors.append(l) }
    }

    private func mouseDown(_ e: NSEvent) -> NSEvent? {
        guard !demoActive, drag == nil, let w = e.window, let it = items.first(where: { $0.win === w }), w.isVisible else { press = nil; return e }
        let h = w.contentView?.bounds.height ?? w.frame.height
        let pt = CGPoint(x: e.locationInWindow.x, y: h - e.locationInWindow.y)
        if it.look.blocked(pt) { press = nil; return e }   // corona e cursori: restano alla vista
        press = Press(item: it, win: w, start: NSEvent.mouseLocation)
        return e                                           // il clic passa: se non diventa un trascinamento funziona come prima
    }

    private func mouseDragged(_ e: NSEvent) -> NSEvent? {
        guard !demoActive, let pr = press else { return e }
        let m = NSEvent.mouseLocation
        if drag == nil {
            guard hypot(m.x - pr.start.x, m.y - pr.start.y) >= threshold else { return e }
            cancelPress(pr.win)
            beginDrag(pr)
        }
        update(m)
        return nil
    }

    private func mouseUp(_ e: NSEvent) -> NSEvent? {
        if demoActive { return e }
        press = nil
        guard drag != nil else { return e }
        endDrag()
        return nil
    }

    /// Il bottone sotto il dito ha già ricevuto il clic: un rilascio lontano lo annulla senza farlo scattare.
    private func cancelPress(_ w: NSWindow) {
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            w.sendEvent(up)
        }
    }

    fileprivate func beginDrag(_ pr: Press) {
        let it = pr.item
        if let st = settle { finishSettle(st) }      // ripreso al volo mentre tornava al bordo
        guard let win = it.win else { return }
        hideWork.values.forEach { $0.cancel() }; hideWork = [:]
        solve()
        // chi era fuso con lui resta dov'è; fra i due nasce un ponte che si rompe allontanandosi
        let sc = screen(of: it), vf = sc.visibleFrame
        let slot = items.filter { !$0.dragging && $0.side == it.side && EdgeDock.displayID(screen(of: $0)) == EdgeDock.displayID(sc) }
            .sorted { $0.shownFrame.maxY > $1.shownFrame.maxY }
        var partners: [(item: Item, above: Bool)] = []
        if let i = slot.firstIndex(where: { $0 === it }) {
            if it.glued, i > 0 { partners.append((slot[i - 1], true)) }
            if i + 1 < slot.count, slot[i + 1].glued {
                let below = slot[i + 1]
                below.glued = false
                below.topFrac = (vf.maxY - below.shownFrame.maxY) / max(1, vf.height)
                partners.append((below, false))
            }
        }
        it.glued = false
        it.dragging = true
        it.willDrag()                    // es. l'Agente chiude il pannello; la colonna intanto è già nostra
        let d = Drag(item: it, start: pr.start, frame: win.frame, side: it.side, screen: sc)
        d.partners = partners
        d.free = it.floating != nil              // 21/10: un elemento libero si muove subito in tutte le direzioni
        drag = d
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { it.look.joinTop = 0; it.look.joinBottom = 0 }
        solve()
        win.orderFrontRegardless()
        // 11/10 sera, l'autore ("orribile, evita questa animazione"): niente goccia, collo né stacco.
        // Si scorre solo lungo il proprio bordo e, lasciato vicino a un altro elemento, ci si attacca accanto.
        startLink(sc)
    }

    fileprivate func update(_ m: NSPoint) {
        guard let d = drag else { return }
        d.mouse = m
        if link == nil { startLink(d.screen) }
    }

    // MARK: il motore (11/10 sera)

    /// Molla semplice (come quelle di SwiftUI: response = periodo, damping 1 = senza rimbalzo).
    private func spring(_ x: inout CGFloat, _ v: inout CGFloat, to target: CGFloat, response: CGFloat, damping: CGFloat, dt: CGFloat) {
        let k = pow(2 * .pi / response, 2), c = 4 * .pi * damping / response
        v += (-k * (x - target) - c * v) * dt
        x += v * dt
    }

    private func startLink(_ sc: NSScreen) {
        guard link == nil else { return }
        let proxy = LinkProxy { [weak self] l in self?.tick(l) }
        let l = sc.displayLink(target: proxy, selector: #selector(LinkProxy.fire(_:)))
        l.add(to: .main, forMode: .common)
        link = l; linkProxy = proxy; lastTick = 0
    }

    private func stopLink() { link?.invalidate(); link = nil; linkProxy = nil }

    private func smooth(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)
    }

    /// Un fotogramma: fisica, poi tutto il disegno nello stesso giro.
    private func tick(_ l: CADisplayLink) {
        guard let d = drag ?? settle, let win = d.item.win else { stopLink(); return }
        let now = l.timestamp
        let dtAll = lastTick == 0 ? 1.0 / 120 : min(1.0 / 30, max(1.0 / 480, now - lastTick))
        if lastTick != 0 { EdgeDock.frames += 1; if now - lastTick > 1.5 / 120 { EdgeDock.slowFrames += 1 } }
        lastTick = now
        let it = d.item, s = win.frame.size, r = it.radius()
        let sf = d.screen.frame, vf = d.screen.visibleFrame
        let edgeX = d.side == .left ? sf.minX : sf.maxX
        let dir: CGFloat = d.side == .left ? 1 : -1

        // 1. dove vuole andare, e con che molla
        var target = d.pos
        var resp: CGFloat = 0.1, damp: CGFloat = 0.85
        var attachTarget: CGFloat = 0
        var neckT: CGFloat = -1                                    // >= 0: collo attaccato al bordo (prima dello strappo)
        if d.settling {
            target = d.finalFrame.origin
            resp = 0.26; damp = 1                                   // si posa, senza rimbalzi
        } else if !d.free {
            // su e giù lungo il bordo, attaccato; tirato verso il centro di 40 pt si libera e segue il mouse (senza effetti)
            let dx = d.mouse.x - d.start.x, dy = d.mouse.y - d.start.y
            if (d.side == .left ? dx : -dx) > 40 { d.free = true } else {
                let y = min(vf.maxY + r - s.height, max(vf.minY - r, d.startFrame.minY + dy))
                target = CGPoint(x: d.side == .left ? sf.minX : sf.maxX - s.width,
                                 y: blockedY(d.item, y, s.height, d.side, d.screen))
                resp = 0.06; damp = 1
            }
        }
        // 21/10: lontano dai bordi la forma diventa tonda, e dice già dove andrà a posarsi lasciandolo
        attachTarget = d.settling ? (d.toFloat ? 0 : 1) : (d.free && liberoQui(d, s) ? 0 : 1)
        if d.free && !d.settling {
            let sc = screen(at: d.mouse) ?? d.screen
            if EdgeDock.displayID(sc) != EdgeDock.displayID(d.screen) { d.screen = sc; goo?.moveTo(sc) }
            let side: EdgeSide = d.mouse.x < sc.frame.midX ? .left : .right
            if EdgeDock.displayID(sc) != it.look.screenID { it.look.screenID = EdgeDock.displayID(sc) }
            if side != d.side {
                d.side = side
                withAnimation(.easeOut(duration: 0.25)) { it.look.side = side }
            }
            target = CGPoint(x: d.mouse.x - d.grab.dx, y: d.mouse.y - d.grab.dy)
            resp = 0.06; damp = 1                                   // segue il mouse, senza effetti
        }

        // 2. fisica, a passi piccoli (stabile anche con la molla stretta del trascinamento)
        let steps = max(1, Int(ceil(dtAll / (1.0 / 480))))
        let dt = CGFloat(dtAll) / CGFloat(steps)
        for _ in 0..<steps {
            var vx = d.vel.dx, vy = d.vel.dy
            spring(&d.pos.x, &vx, to: target.x, response: resp, damping: damp, dt: dt)
            spring(&d.pos.y, &vy, to: target.y, response: resp, damping: damp, dt: dt)
            d.vel = CGVector(dx: vx, dy: vy)
        }
        // forma: goccia lontano dal bordo, raccordi concavi quando lo tocca
        let near = d.side == .left ? d.pos.x - sf.minX : sf.maxX - (d.pos.x + s.width)
        _ = near                                                    // la forma resta sempre quella del bordo
        let aResp: CGFloat = d.free ? 0.3 : 0.12, aDamp: CGFloat = d.free ? 0.5 : 0.9
        for _ in 0..<steps { spring(&d.attach, &d.attachVel, to: attachTarget, response: aResp, damping: aDamp, dt: dt) }
        // deformazione: si allunga appena nella direzione del moto, e atterrando oscilla e si assesta
        let ax: CGFloat = 0, ay: CGFloat = 0                        // niente deformazione
        let sqT = CGVector(dx: 1 + ax - ay * 0.5, dy: 1 + ay - ax * 0.5)
        for _ in 0..<steps {
            var x = d.sq.dx, vx = d.sqVel.dx, y = d.sq.dy, vy = d.sqVel.dy
            spring(&x, &vx, to: sqT.dx, response: 0.24, damping: 0.38, dt: dt)
            spring(&y, &vy, to: sqT.dy, response: 0.24, damping: 0.38, dt: dt)
            d.sq = CGVector(dx: x, dy: y); d.sqVel = CGVector(dx: vx, dy: vy)
        }

        // 3. disegno: finestra, collo e forma nello stesso giro
        CATransaction.begin(); CATransaction.setDisableActions(true)
        win.setFrameOrigin(NSPoint(x: d.pos.x.rounded(.toNearestOrEven), y: d.pos.y.rounded(.toNearestOrEven)))
        if neckT >= 0 {
            drawEdgeNeck(d, t: neckT)
            drawPartners(d)
        } else if let g = goo {
            if let st = d.stub {                                    // il moncone del collo rotto rientra nel bordo
                d.stub!.age += dtAll
                let p = CGFloat(1 - exp(-st.age / 0.07))
                if p > 0.985 { d.stub = nil; g.set("stub", nil, colors: it.colors(), span: 0...1) }
                else {
                    let hb = st.hb * (1 - p) + 1.5, bx = st.bx + (st.ex + dir * 1 - st.bx) * p
                    let path = hourglass(g.local(CGPoint(x: st.ex, y: st.yc + hb)), g.local(CGPoint(x: st.ex, y: st.yc - hb)),
                                         g.local(CGPoint(x: bx, y: st.yc + hb * 0.6)), g.local(CGPoint(x: bx, y: st.yc - hb * 0.6)),
                                         waist: 0.14 * (1 - p))
                    g.set("stub", path, colors: it.colors(), span: (st.yc - st.hb)...(st.yc + st.hb))
                }
            }
            drawJoin(d, near: near)                                 // avvicinandosi al bordo un filo lo raggiunge e lo beve
            if !d.settling { drawAttraction(d) }
        }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) {
            if abs(it.look.attach - d.attach) > 0.003 { it.look.attach = d.attach }
        }
        squash(win, d.sq, side: d.side)
        CATransaction.commit()
        _ = edgeX

        // 4. arrivato?
        if d.settling {
            d.settleAge += dtAll
            let dist = hypot(d.pos.x - d.finalFrame.minX, d.pos.y - d.finalFrame.minY)
            let still = hypot(d.vel.dx, d.vel.dy) < 6 && abs(d.attach - (d.toFloat ? 0 : 1)) < 0.01 && abs(d.attachVel) < 0.05
                && abs(d.sq.dx - 1) < 0.002 && abs(d.sq.dy - 1) < 0.002
            if (dist < 0.4 && still) || d.settleAge > 1.6 { finishSettle(d) }
        }
    }

    /// 21/10: quanto lontano da un bordo laterale va lasciato perché resti libero.
    static let freeDist: CGFloat = 90
    private func liberoQui(_ d: Drag, _ s: NSSize) -> Bool {
        guard let w = d.item.win else { return false }
        let sf = d.screen.frame, f = w.frame
        return min(f.minX - sf.minX, sf.maxX - f.maxX) > EdgeDock.freeDist
    }

    /// Distanza minima fra due elementi sullo stesso bordo (11/10 sera, "blocca l'avvicinamento un po' più sotto"):
    /// dato dove vorrebbe stare (y della base della finestra), restituisce il punto libero più vicino.
    static let spacing: CGFloat = 28
    private func blockedY(_ it: Item, _ y: CGFloat, _ h: CGFloat, _ side: EdgeSide, _ sc: NSScreen) -> CGFloat {
        let sid = EdgeDock.displayID(sc), vf = sc.visibleFrame, r = it.radius()
        let others = items.filter { $0 !== it && !$0.dragging && $0.side == side && EdgeDock.displayID(screen(of: $0)) == sid && $0.forced() != false }
            .map(\.shownFrame)
        let lo = vf.minY - r, hi = vf.maxY + r - h
        func free(_ y: CGFloat) -> Bool {
            others.allSatisfy { y >= $0.maxY + EdgeDock.spacing || y + h <= $0.minY - EdgeDock.spacing }
        }
        if free(y) { return y }
        var cands: [CGFloat] = []
        for o in others { cands += [o.maxY + EdgeDock.spacing, o.minY - EdgeDock.spacing - h] }
        let ok = cands.filter { $0 >= lo && $0 <= hi && free($0) }
        return ok.min { abs($0 - y) < abs($1 - y) } ?? y
    }

    /// Deformazione direttamente sul livello della finestra, ancorata al lato del bordo: niente ridisegno di SwiftUI.
    private func squash(_ win: NSWindow, _ q: CGVector, side: EdgeSide) {
        guard let v = win.contentView else { return }
        v.wantsLayer = true
        guard let l = v.layer else { return }
        if abs(q.dx - 1) < 0.0005 && abs(q.dy - 1) < 0.0005 { l.sublayerTransform = CATransform3DIdentity; return }
        let b = l.bounds
        let ax = (side == .left ? 0 : b.width) - l.anchorPoint.x * b.width
        let ay = b.height / 2 - l.anchorPoint.y * b.height
        var t = CATransform3DMakeTranslation(-ax, -ay, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(q.dx, q.dy, 1))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(ax, ay, 0))
        l.sublayerTransform = t
    }

    /// La goccia che torna: un collo esce dal bordo e la raggiunge, si ingrossa man mano e sparisce sotto di lei.
    private func drawJoin(_ d: Drag, near: CGFloat) {
        guard let g = goo, let win = d.item.win else { return }
        let reach: CGFloat = 90
        guard near > 1, near < reach else { if g.has("edge") { g.set("edge", nil, colors: d.item.colors(), span: 0...1) }; return }
        let f = win.frame, r = d.item.radius()
        let ex = d.side == .left ? d.screen.frame.minX : d.screen.frame.maxX
        let dir: CGFloat = d.side == .left ? 1 : -1
        let c = 1 - near / reach                                       // 0 lontano, 1 al bordo
        let yc = f.midY, hb = (f.height / 2 - r) * (0.25 + 0.75 * c)
        let bx = (d.side == .left ? f.minX : f.maxX) + dir * (r + 8)
        let path = hourglass(g.local(CGPoint(x: ex, y: yc + hb + r * c)), g.local(CGPoint(x: ex, y: yc - hb - r * c)),
                             g.local(CGPoint(x: bx, y: yc + hb)), g.local(CGPoint(x: bx, y: yc - hb)),
                             waist: 0.06 + 0.94 * c * c)
        g.set("edge", path, colors: d.item.colors(), span: f.minY...f.maxY, opacity: Float(min(1, c * 2.2)))
    }

    private func detach(_ d: Drag) {
        guard let win = d.item.win else { return }
        d.free = true
        SuonoBordi.goccia?(1)
        // il collo si rompe: il moncone resta attaccato al bordo e rientra (lo disegna il motore)
        let f = win.frame, r = d.item.radius()
        let ex = d.side == .left ? d.screen.frame.minX : d.screen.frame.maxX
        let dir: CGFloat = d.side == .left ? 1 : -1
        d.stub = (ex: ex, yc: f.midY, hb: f.height / 2 - r, bx: (d.side == .left ? f.minX : f.maxX) + dir * (r + 8), age: 0)
        if let g = goo {
            g.set("edge", nil, colors: d.item.colors(), span: 0...1)
            for (p, above) in d.partners {
                let pf = p.shownFrame
                let y = above ? pf.minY + p.radius() : pf.maxY - p.radius()
                let px = d.side == .left ? pf.minX : pf.maxX
                g.snap("partner-\(p.id)", to: collapsed(at: CGPoint(x: px, y: y), side: d.side, g, vertical: true))
            }
        }
        d.partners = []
        d.sqVel = CGVector(dx: -1.6 * dir, dy: 1.1)                   // lo strappo: un colpetto elastico
    }

    /// Fine dell'assestamento: posizione esatta, forma piena, la goccia dietro sparisce, gli altri si rimettono in ordine.
    fileprivate func finishSettle(_ d: Drag) {
        guard settle === d else { return }
        settle = nil
        if drag == nil { stopLink() }
        let it = d.item
        it.settling = false
        it.win?.setFrame(d.finalFrame, display: true)
        if let w = it.win { squash(w, CGVector(dx: 1, dy: 1), side: d.side) }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { it.look.attach = d.toFloat ? 0 : 1; it.look.squash = CGSize(width: 1, height: 1) }
        if let g = goo, drag == nil {
            goo = nil
            g.fadeOut { g.orderOut(nil) }
        }
        it.apply(true)
    }

    /// Un colpetto elastico: schiaccia e torna, come una goccia che si stacca o atterra.
    private func pulse(_ look: EdgeLook, _ to: CGSize) {
        withAnimation(.easeOut(duration: 0.08)) { look.squash = to }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.42)) { look.squash = CGSize(width: 1, height: 1) }
        }
    }

    private func attraction(_ d: Drag, _ f: NSRect) -> (item: Item, above: Bool, gap: CGFloat)? {
        let sf = d.screen.frame
        let toEdge = d.side == .left ? f.minX - sf.minX : sf.maxX - f.maxX
        guard toEdge < 140 else { return nil }
        let sid = EdgeDock.displayID(d.screen)
        var best: (item: Item, above: Bool, gap: CGFloat)?
        for o in items where !o.dragging && o.side == d.side && EdgeDock.displayID(screen(of: o)) == sid && o.forced() != false {
            let of = o.shownFrame
            for (above, gap) in [(true, of.minY - f.maxY), (false, f.minY - of.maxY)] where gap > -30 && gap < attractDist {
                if best == nil || abs(gap) < abs(best!.gap) { best = (o, above, gap) }
            }
        }
        // chi sta nascosto oltre il bordo esce per farsi trovare
        if let b = best, !b.item.isShown { reveal(b.item) }
        return best
    }

    // MARK: disegno della goccia

    private func collapsed(at p: CGPoint, side: EdgeSide, _ g: GooWindow, vertical: Bool = false) -> CGPath {
        let c = g.local(p), dir: CGFloat = side == .left ? 1 : -1
        if vertical {
            return hourglass(CGPoint(x: c.x, y: c.y + 1), CGPoint(x: c.x + dir * 2, y: c.y + 1),
                             CGPoint(x: c.x, y: c.y - 1), CGPoint(x: c.x + dir * 2, y: c.y - 1), waist: 1)
        }
        return hourglass(CGPoint(x: c.x, y: c.y + 2), CGPoint(x: c.x, y: c.y - 2),
                         CGPoint(x: c.x + dir * 1, y: c.y + 1), CGPoint(x: c.x + dir * 1, y: c.y - 1), waist: 1)
    }

    /// Il collo fra il bordo dello schermo e l'elemento tirato in dentro.
    private func drawEdgeNeck(_ d: Drag, t: CGFloat) {
        guard let g = goo, let win = d.item.win else { return }
        let f = win.frame, r = d.item.radius()
        let ex = d.side == .left ? d.screen.frame.minX : d.screen.frame.maxX
        let dir: CGFloat = d.side == .left ? 1 : -1
        guard abs((d.side == .left ? f.minX : f.maxX) - ex) > 0.5 else { g.set("edge", nil, colors: d.item.colors(), span: f.minY...f.maxY); return }
        let yc = f.midY, hb = f.height / 2 - r
        let flare = r * (1 - t)
        let bx = (d.side == .left ? f.minX : f.maxX) + dir * (r + 8)        // nascosto sotto l'elemento
        let path = hourglass(g.local(CGPoint(x: ex, y: yc + hb + flare)), g.local(CGPoint(x: ex, y: yc - hb - flare)),
                             g.local(CGPoint(x: bx, y: yc + hb - 2)), g.local(CGPoint(x: bx, y: yc - hb + 2)),
                             waist: 1 - 0.86 * pow(t, 0.9))
        g.set("edge", path, colors: d.item.colors(), span: f.minY...f.maxY)
    }

    /// Ponte verticale fra due elementi sullo stesso bordo (u sopra, l sotto).
    private func bridge(_ g: GooWindow, upper uf: NSRect, ur: CGFloat, lower lf: NSRect, lr: CGFloat, side: EdgeSide, waist: CGFloat) -> CGPath {
        let dir: CGFloat = side == .left ? 1 : -1
        let c = min(uf.width, lf.width)
        let xu = side == .left ? uf.minX : uf.maxX, xl = side == .left ? lf.minX : lf.maxX
        let yu = uf.minY + ur + 6, yl = lf.maxY - lr - 6                   // dentro i corpi: sotto non si vede
        return hourglass(g.local(CGPoint(x: xu, y: yu)), g.local(CGPoint(x: xu + dir * c, y: yu)),
                         g.local(CGPoint(x: xl, y: yl)), g.local(CGPoint(x: xl + dir * c, y: yl)), waist: waist)
    }

    /// Mentre un elemento fuso scivola via lungo il bordo, il ponte con l'altro si allunga e si rompe.
    private func drawPartners(_ d: Drag) {
        guard let g = goo, let win = d.item.win else { return }
        let f = win.frame
        var keep: [(item: Item, above: Bool)] = []
        for (p, above) in d.partners {
            let pf = p.shownFrame
            let gap = above ? pf.minY - f.maxY : f.minY - pf.maxY
            let key = "partner-\(p.id)"
            if gap > breakDist {
                let y = above ? pf.minY + p.radius() : pf.maxY - p.radius()
                g.snap(key, to: collapsed(at: CGPoint(x: d.side == .left ? pf.minX : pf.maxX, y: y), side: d.side, g, vertical: true))
                SuonoBordi.goccia?(0.6)
                continue
            }
            keep.append((p, above))
            let waist = 1 - 0.86 * max(0, gap) / breakDist
            let path = above ? bridge(g, upper: pf, ur: p.radius(), lower: f, lr: d.item.radius(), side: d.side, waist: waist)
                             : bridge(g, upper: f, ur: d.item.radius(), lower: pf, lr: p.radius(), side: d.side, waist: waist)
            let span = min(pf.minY, f.minY)...max(pf.maxY, f.maxY)
            g.set(key, path, colors: d.item.colors(), span: span)
        }
        d.partners = keep
    }

    /// Una goccia libera vicino a un elemento dello stesso bordo: un ponte che si ingrossa man mano che si avvicina.
    private func drawAttraction(_ d: Drag) {
        guard let g = goo, let win = d.item.win else { return }
        guard let a = d.attract, a.gap > 2 else { if g.has("attract") { g.set("attract", nil, colors: d.item.colors(), span: 0...1) }; return }
        let f = win.frame, of = a.item.shownFrame
        let close = max(0, min(1, 1 - a.gap / attractDist))
        let path = a.above ? bridge(g, upper: of, ur: a.item.radius(), lower: f, lr: d.item.radius(), side: d.side, waist: 0.12 + 0.6 * close)
                           : bridge(g, upper: f, ur: d.item.radius(), lower: of, lr: a.item.radius(), side: d.side, waist: 0.12 + 0.6 * close)
        g.set("attract", path, colors: d.item.colors(), span: min(of.minY, f.minY)...max(of.maxY, f.maxY), opacity: Float(close * close))
    }

    // MARK: rilascio

    fileprivate func endDrag() {
        guard let d = drag, let win = d.item.win else { drag = nil; return }
        let it = d.item
        let m = mouse
        let sc = d.free ? (screen(at: m) ?? d.screen) : d.screen
        let vf = sc.visibleFrame, sid = EdgeDock.displayID(sc)
        let side = d.side
        let s = win.frame.size, r = it.radius()
        var top = clampTop(win.frame.maxY, s.height, vf, r)
        drag = nil

        // 21/10: lasciato lontano dai bordi resta libero lì (sempre in vista); vicino a un bordo ci torna come prima
        if d.free && liberoQui(d, s) {
            let f = win.frame
            let x = min(max(f.minX, vf.minX + 4), vf.maxX - s.width - 4), y = min(max(f.minY, vf.minY + 4), vf.maxY - s.height - 4)
            it.floating = CGPoint(x: (x - vf.minX) / max(1, vf.width), y: (y - vf.minY) / max(1, vf.height))
            it.screenID = sid; it.glued = false; it.dragging = false; it.revealed = true
            it.side = d.side
            if it.look.side != d.side { withAnimation(.easeOut(duration: 0.2)) { it.look.side = d.side } }
            it.look.libero = true
            solve()
            items.forEach { $0.save() }
            d.finalFrame = it.shownFrame
            d.toFloat = true; d.settling = true; d.settleAge = 0
            it.settling = true
            settle = d
            d.partners = []
            startLink(sc)
            return
        }
        it.floating = nil
        if it.look.libero { it.look.libero = false }

        // 11/10 sera: niente fusione. Se è troppo vicino a un altro elemento dello stesso bordo, si ferma a distanza.
        solve()
        top = blockedY(it, top - s.height, s.height, side, sc) + s.height
        it.side = side; it.screenID = sid; it.glued = false
        items.forEach { $0.glued = false }
        it.topFrac = (vf.maxY - top) / max(1, vf.height)
        it.dragging = false
        it.revealed = true
        if it.look.side != side { withAnimation(.easeOut(duration: 0.2)) { it.look.side = side } }
        solve()
        items.forEach { $0.save() }

        // torna al bordo con la molla del motore, partendo con la velocità del gesto (11/10 sera)
        d.finalFrame = it.shownFrame
        d.settling = true
        d.settleAge = 0
        it.settling = true
        settle = d
        if let g = goo {
            for (p, above) in d.partners {
                let pf = p.shownFrame
                let y = above ? pf.minY + p.radius() : pf.maxY - p.radius()
                g.snap("partner-\(p.id)", to: collapsed(at: CGPoint(x: side == .left ? pf.minX : pf.maxX, y: y), side: side, g, vertical: true), duration: 0.36)
            }
            if g.has("attract") { g.set("attract", nil, colors: it.colors(), span: 0...1) }
        }
        d.partners = []
        startLink(sc)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.items.filter { $0 !== it }.forEach { $0.apply(true) }
        }
    }
}

// MARK: - Dimostrazione (11/10/2026): un mouse finto che passa dagli STESSI percorsi del trascinamento vero

extension EdgeDock {
    /// Dove sta il mouse per il trascinamento: quello vero, o quello della dimostrazione.
    var mouse: NSPoint { demoMouse ?? NSEvent.mouseLocation }

    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    /// Afferra un elemento come farebbe il mouse premuto in quel punto, già oltre la soglia del clic.
    func demoGrab(_ it: Item, at p: NSPoint) {
        guard drag == nil, let w = it.win else { return }
        demoMouse = p
        press = Press(item: it, win: w, start: p)
        beginDrag(press!)
    }
    func demoMove(_ p: NSPoint) {
        guard drag != nil else { return }
        demoMouse = p
        update(p)
    }
    func demoRelease() {
        guard drag != nil else { return }
        press = nil
        endDrag()
    }
    var demoDragging: Bool { drag != nil }
    func demoEnd() { demoMouse = nil; demoActive = false }

    /// Mette un elemento in un punto preciso (inizio della dimostrazione).
    func demoPlace(_ it: Item, side: EdgeSide, topFrac: CGFloat) {
        it.side = side; it.topFrac = topFrac; it.glued = false; it.screenID = nil
        it.look.side = side
        applyAllNow()
    }

    /// Rilegge da UserDefaults le posizioni (fine della dimostrazione: tutto com'era).
    func reloadPlacements() {
        for it in items {
            let d = UserDefaults.standard.dictionary(forKey: "bordo.\(it.id)")
            it.side = (d?["side"] as? String).flatMap(EdgeSide.init(rawValue:)) ?? it.defaultSide
            it.topFrac = (d?["top"] as? Double).map { CGFloat($0) }
            it.screenID = (d?["screen"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
            it.glued = false
            it.look.side = it.side
            it.look.attach = 1
        }
        applyAllNow()
    }

    func applyAllNow() { items.forEach { $0.apply(true) } }

    /// Fuori tutti quelli indicati, e nessuno si nasconde finché dura la dimostrazione.
    func demoReveal(_ list: [Item]) { list.forEach { reveal($0) } }
    func demoConcealAll() { for it in items { conceal(it); it.apply(true) } }
}

/// Gancio del suono della goccia: lo imposta l'app (main.swift), il Core non conosce KeySounds.
enum SuonoBordi { static var goccia: ((Float) -> Void)? }
