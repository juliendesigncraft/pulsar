// Rowline — la Griglia (19/10/2026). Idea da un commento al reel: "Divvy ti fa anche disporre le finestre su una griglia".
// ⌃⌥⌘G apre al centro dello schermo una griglia piccola, con le proporzioni dello schermo: trascini sulle celle
// (o un clic su una sola) e la finestra col fuoco esce dalla fila e scivola in quel riquadro. ⌃⌥⌘T la rimette in fila.
// Esc o un clic fuori chiude. Frecce e Invio funzionano anche senza mouse. Misura in Regole: 4 × 3, 6 × 4, 8 × 6.

import AppKit
import SwiftUI

/// Pannello che prende i tasti (Esc, frecce, Invio) senza attivare Rowline: l'app della finestra resta davanti.
private final class PannelloChiave: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Reticolo: ObservableObject {
    static let shared = Reticolo()
    static let misure = ["4x3", "6x4", "8x6"]
    static var misura: String {
        let m = Archivio.d.string(forKey: "griglia") ?? "6x4"
        return misure.contains(m) ? m : "6x4"
    }

    @Published var colonne = 6
    @Published var righe = 4
    @Published var inizio: (c: Int, r: Int)? = nil
    @Published var fine: (c: Int, r: Int)? = nil
    @Published var app = ""
    var proporzione: CGFloat = 1.6

    private var pannello: NSPanel?
    private var monitor: [Any] = []
    private var bersaglio: AXUIElement?
    private var schermo: NSScreen?

    func apri() {
        if pannello?.isVisible == true { chiudi(); return }
        guard let w = Motore.shared.finestraColFuoco() else { NSSound.beep(); return }
        let el = w.el, sc = w.schermo, nome = w.app
        let parti = Reticolo.misura.split(separator: "x").compactMap { Int($0) }
        colonne = parti.first ?? 6; righe = parti.last ?? 4
        bersaglio = el; schermo = sc; app = nome
        let area = Motore.shared.areaGriglia(sc)
        proporzione = area.width / max(1, area.height)
        // si parte dalle celle che la finestra occupa adesso: si vede dov'è, e con le frecce la si sposta
        if let r = AX.cornice(el) { let (a, b) = celle(di: r, in: area); inizio = a; fine = b } else { inizio = nil; fine = nil }

        let p = pannello ?? {
            let p = PannelloChiave(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false   // l'ombra la fa la vista, niente filo scuro
            p.level = .statusBar; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            return p
        }()
        pannello = p
        let host = NSHostingView(rootView: VistaReticolo().environmentObject(self).environmentObject(Tinta.shared))
        p.contentView = host
        let size = host.fittingSize
        p.setFrame(NSRect(x: sc.frame.midX - size.width / 2, y: sc.frame.midY - size.height / 2, width: size.width, height: size.height), display: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 1 }

        monitor.forEach(NSEvent.removeMonitor); monitor = []
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.tasto(e) == true ? nil : e }) { monitor.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.chiudi() }) { monitor.append(m) }
    }

    func chiudi() {
        monitor.forEach(NSEvent.removeMonitor); monitor = []
        guard let p = pannello, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    /// La selezione diventa un riquadro sullo schermo, e la finestra ci scivola dentro.
    func applica() {
        guard let el = bersaglio, let sc = schermo, let a = inizio, let b = fine else { chiudi(); return }
        let area = Motore.shared.areaGriglia(sc), g = Motore.shared.g
        let cw = (area.width + g) / CGFloat(colonne), ch = (area.height + g) / CGFloat(righe)
        let c0 = min(a.c, b.c), c1 = max(a.c, b.c), r0 = min(a.r, b.r), r1 = max(a.r, b.r)
        let r = CGRect(x: (area.minX + CGFloat(c0) * cw).rounded(), y: (area.minY + CGFloat(r0) * ch).rounded(),
                       width: (CGFloat(c1 - c0 + 1) * cw - g).rounded(), height: (CGFloat(r1 - r0 + 1) * ch - g).rounded())
        chiudi()
        Motore.shared.posaInGriglia(el, r)
    }

    /// Esc chiude, Invio posa, le frecce spostano la selezione, con ⇧ la allargano o la stringono.
    private func tasto(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 53: chiudi(); return true
        case 36, 76: applica(); return true
        case 123, 124, 125, 126:
            let dx = e.keyCode == 123 ? -1 : e.keyCode == 124 ? 1 : 0
            let dy = e.keyCode == 126 ? -1 : e.keyCode == 125 ? 1 : 0
            var a = inizio ?? (0, 0), b = fine ?? a
            if e.modifierFlags.contains(.shift) {
                b = (max(a.c, min(colonne - 1, b.c + dx)), max(a.r, min(righe - 1, b.r + dy)))
            } else {
                let w = b.c - a.c, h = b.r - a.r
                let c = max(0, min(colonne - 1 - w, a.c + dx)), r = max(0, min(righe - 1 - h, a.r + dy))
                a = (c, r); b = (c + w, r + h)
            }
            inizio = a; fine = b
            return true
        default: return false
        }
    }

    private func celle(di r: CGRect, in area: CGRect) -> ((c: Int, r: Int), (c: Int, r: Int)) {
        let cw = area.width / CGFloat(colonne), ch = area.height / CGFloat(righe)
        func cl(_ v: Int, _ n: Int) -> Int { max(0, min(n - 1, v)) }
        let c0 = cl(Int(((r.minX - area.minX) / cw).rounded()), colonne)
        let c1 = cl(Int(((r.maxX - area.minX) / cw).rounded()) - 1, colonne)
        let r0 = cl(Int(((r.minY - area.minY) / ch).rounded()), righe)
        let r1 = cl(Int(((r.maxY - area.minY) / ch).rounded()) - 1, righe)
        return ((c0, r0), (max(c0, c1), max(r0, r1)))
    }

    func scelta(_ c: Int, _ r: Int) -> Bool {
        guard let a = inizio, let b = fine else { return false }
        return (min(a.c, b.c)...max(a.c, b.c)).contains(c) && (min(a.r, b.r)...max(a.r, b.r)).contains(r)
    }
}

struct VistaReticolo: View {
    @EnvironmentObject var m: Reticolo
    @EnvironmentObject var t: Tinta
    @State private var trascina = false
    private let larga: CGFloat = 420
    private let passo: CGFloat = 4

    var body: some View {
        let alta = (larga / m.proporzione).rounded()
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.app).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(T("Griglia", "Grid")).font(.system(size: 12)).foregroundStyle(t.t3)
            }
            celle.frame(width: larga, height: alta)
            HStack(spacing: 0) {
                Text(T("Trascina sulle celle", "Drag across the cells")).foregroundStyle(t.t2)
                Spacer()
                Text(T("⌃⌥⌘T la rimette in fila", "⌃⌥⌘T puts it back in the row")).foregroundStyle(t.t3)
            }
            .font(.system(size: 11.5))
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(LinearGradient(colors: [t.alto, t.basso], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(t.chiaro ? 0.12 : 0.35), radius: 22, y: 10))
        .padding(28)
        .foregroundStyle(t.testo)
        .environment(\.colorScheme, t.schema)
    }

    private var celle: some View {
        GeometryReader { geo in
            let cw = (geo.size.width + passo) / CGFloat(m.colonne), ch = (geo.size.height + passo) / CGFloat(m.righe)
            ZStack(alignment: .topLeading) {
                ForEach(0..<m.righe, id: \.self) { r in
                    ForEach(0..<m.colonne, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(m.scelta(c, r) ? t.azzurro.opacity(t.chiaro ? 0.75 : 0.62) : t.velo)
                            .frame(width: cw - passo, height: ch - passo)
                            .offset(x: CGFloat(c) * cw, y: CGFloat(r) * ch)
                    }
                }
            }
            .animation(.easeOut(duration: 0.12), value: m.inizio.map { $0.c * 100 + $0.r })
            .animation(.easeOut(duration: 0.12), value: m.fine.map { $0.c * 100 + $0.r })
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = cella(v.location, cw, ch)
                    if !trascina { trascina = true; m.inizio = cella(v.startLocation, cw, ch) }
                    m.fine = p
                }
                .onEnded { v in
                    trascina = false
                    m.fine = cella(v.location, cw, ch)
                    m.applica()
                })
        }
    }

    private func cella(_ p: CGPoint, _ cw: CGFloat, _ ch: CGFloat) -> (c: Int, r: Int) {
        (max(0, min(m.colonne - 1, Int(p.x / cw))), max(0, min(m.righe - 1, Int(p.y / ch))))
    }
}
