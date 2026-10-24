// Rowline — la BARRA (14/10/2026), chiesta dall'autore provando la v1.0: "non mi dice molto, crea uno slider".
// Poi, stessa sera: "minimal, non ingombrante, niente contorni strani e contenitori". Quindi niente capsula e niente
// riquadro: una linea sottile per finestra, larga come la finestra. Quelle che si vedono sullo schermo sono più chiare,
// quelle fuori vista quasi spente, quella attiva azzurra. Passandoci sopra le linee si ispessiscono (più facili da
// cliccare). Quando cambi finestra compare per un attimo sopra il nome dell'app e il posto ("Chrome  2 di 5").
// Clic su una linea: si va a quella finestra. Trascinare: la parte chiara scorre e al rilascio la fila la segue.

import AppKit
import SwiftUI
import Combine

enum ModoBarra: String, CaseIterable { case sempre, quandoCambi, mai
    var titolo: String { self == .sempre ? T("Sempre", "Always") : self == .quandoCambi ? T("Quando cambi", "When it changes") : T("Mai", "Never") }
}

final class Barra: ObservableObject {
    static let shared = Barra()
    static var alta: CGFloat { Anteprime.shared.accese ? 230 : 44 }
    static let margine: CGFloat = 4, larghezzaVista: CGFloat = 64, massima: CGFloat = 300

    @Published var modo: ModoBarra = ModoBarra(rawValue: Archivio.d.string(forKey: "barra") ?? "") ?? .sempre {
        didSet { Archivio.d.set(modo.rawValue, forKey: "barra"); aggiorna(); Motore.shared.disponiTutto() }
    }
    /// Quanto spazio le finestre lasciano libero in basso: solo la striscia delle linee.
    static var riserva: CGFloat { shared.modo == .sempre ? 16 + extraDemo : 0 }
    /// Ripresa del reel: una fascia libera sopra lo slider per le righe di testo (comando riserva:<pt>, 17/10).
    static var extraDemo: CGFloat = 0

    private var pannelli: [CGDirectDisplayID: NSPanel] = [:]
    private var sub: AnyCancellable?
    private var spegni: DispatchWorkItem?

    func avvia() {
        sub = Motore.shared.$mappa.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.aggiorna(mostra: true) }
        }
        aggiorna()
    }

    /// Scala comune: lo schermo diventa largo `larghezzaVista`, la fila intera al massimo `massima`.
    static func scala(_ st: StrisciaVista) -> CGFloat {
        let totale = max(st.colonne.last.map { $0.x + $0.w } ?? 1, st.vista)
        return min(larghezzaVista / max(st.vista, 1), massima / totale)
    }
    static func larghezza(_ st: StrisciaVista) -> CGFloat {
        (st.colonne.last.map { $0.x + $0.w } ?? 1) * scala(st)
    }

    func aggiorna(mostra: Bool = false) {
        let m = Motore.shared
        let attivi = Set(modo == .mai || !m.acceso ? [] : m.mappa.map(\.id))
        for (id, p) in pannelli where !attivi.contains(id) { p.orderOut(nil); pannelli[id] = nil }
        for st in m.mappa where attivi.contains(st.id) {
            guard let sc = NSScreen.screens.first(where: { $0.numero == st.id }) else { continue }
            let p = pannelli[st.id] ?? crea(st.id)
            pannelli[st.id] = p
            let w = max(Barra.larghezza(st) + 40, Anteprime.shared.accese ? 300 : 220)       // largo abbastanza per il nome dell'app
            let v = sc.visibleFrame
            p.setFrame(NSRect(x: v.midX - w / 2, y: v.minY + Barra.margine, width: w, height: Barra.alta), display: true)
            if modo == .sempre || mostra { p.alphaValue = 1; p.orderFrontRegardless() }
        }
        if modo == .quandoCambi && mostra {
            spegni?.cancel()
            let w = DispatchWorkItem { [weak self] in
                self?.pannelli.values.forEach { p in NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) }) }
            }
            spegni = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: w)
        }
    }

    private func crea(_ id: CGDirectDisplayID) -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isMovable = false
        let host = NSHostingView(rootView: VistaBarra(schermo: id).environmentObject(Motore.shared).environmentObject(Tinta.shared).environmentObject(Anteprime.shared))
        host.layer?.backgroundColor = .clear
        p.contentView = host
        return p
    }
}

struct VistaBarra: View {
    let schermo: CGDirectDisplayID
    @EnvironmentObject var m: Motore
    @EnvironmentObject var t: Tinta
    @EnvironmentObject var ant: Anteprime
    @State private var trascina: CGFloat?
    @State private var sopraID: CGWindowID?
    @State private var sopra = false
    @State private var sopraApp: String?
    @State private var etichetta = false
    @State private var nascondi: DispatchWorkItem?

    var body: some View {
        if let st = m.mappa.first(where: { $0.id == schermo }) {
            let k = Barra.scala(st)
            let totale = st.colonne.last.map { $0.x + $0.w } ?? 1
            let s = trascina ?? st.scorrimento
            let alto: CGFloat = sopra || trascina != nil ? 8 : 4
            VStack(spacing: 7) {
                Spacer(minLength: 0)
                // l'anteprima della finestra sotto il cursore (se accese e col permesso)
                if let id = sopraID, let img = ant.immagini[id] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 260, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
                // il nome: compare quando cambi finestra o passi su una linea, con un alone e nessun riquadro
                Text(testo(st))
                    .font(.system(size: 11))
                    .foregroundStyle(t.testo.opacity(0.9))
                    .shadow(color: (t.chiaro ? Color.white : Color.black).opacity(0.7), radius: 4)
                    .opacity(etichetta || sopraApp != nil || trascina != nil ? 1 : 0)
                    .allowsHitTesting(false)
                // 17/10, l'autore: "sempre sottile, ma magari una linea unica?". Una linea sola lunga quanto la fila:
                // più chiara dove c'è lo schermo, azzurra sulla finestra col fuoco. Clic e passaggio leggono la colonna sotto il punto.
                let colonna: (CGFloat) -> ColonnaVista? = { x in
                    st.colonne.min { abs(($0.x + $0.w / 2) * k - x) < abs(($1.x + $1.w / 2) * k - x) }
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(t.testo.opacity(t.chiaro ? 0.16 : 0.2))
                        .frame(width: max(totale * k, 6), height: alto)
                    Capsule().fill(t.testo.opacity(t.chiaro ? 0.5 : 0.6))
                        .frame(width: max(min(st.vista, totale) * k, 6), height: alto)
                        .offset(x: s * k)
                    if trascina == nil, let c = st.colonne.first(where: \.fuoco) {
                        Capsule().fill(t.azzurro)
                            .frame(width: max(c.w * k - 2, 6), height: alto)
                            .offset(x: c.x * k + 1)
                    }
                }
                .contentShape(Rectangle().inset(by: -6))
                .onContinuousHover { fase in
                    switch fase {
                    case .active(let p):
                        if let c = colonna(p.x), let f = c.finestre[safe: c.attiva] { sopraApp = f.app; sopraID = f.id; ant.chiedi(f.id) }
                    case .ended: sopraApp = nil; sopraID = nil
                    }
                }
                .onTapGesture(coordinateSpace: .local) { p in
                    if let c = colonna(p.x), let f = c.finestre[safe: c.attiva] { m.scegli(f.id) }
                }
                .contextMenu {
                    if let id = sopraID, let f = st.colonne.flatMap(\.finestre).first(where: { $0.id == id }) { menu(f) }
                }
                .frame(width: totale * k, height: 8, alignment: .leading)
                .shadow(color: .black.opacity(t.chiaro ? 0.08 : 0.35), radius: 2, y: 0.5)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onHover { sopra = $0 }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        let max0 = max(0, totale - st.vista)
                        trascina = min(max0, max(0, st.scorrimento + v.translation.width / k))
                    }
                    .onEnded { _ in
                        if let x = trascina { m.scorriA(schermo, x) }
                        trascina = nil
                    })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 2)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.scorrimento)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: st.colonne.map(\.w))
            .animation(.easeOut(duration: 0.2), value: alto)
            .animation(.easeOut(duration: 0.25), value: etichetta)
            .animation(.easeOut(duration: 0.2), value: sopraApp)
            .animation(.easeOut(duration: 0.2), value: sopraID)
            .onChange(of: st.fuoco?.posto) { _, _ in mostraEtichetta() }
            .onChange(of: st.fuoco?.app) { _, _ in mostraEtichetta() }
            .environment(\.colorScheme, t.schema)
        }
    }

    /// Tasto destro su una linea: la larghezza fissa per quell'app, lasciarla libera, galleggiare.
    @ViewBuilder private func menu(_ f: TesseraVista) -> some View {
        let r = m.regoleApp[f.bundle]
        Text(T("\(f.app): quando si apre", "\(f.app): when it opens"))
        ForEach([(1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (1.0, T("Intera", "Full"))], id: \.0) { v, n in
            Button((r.map { abs($0 - v) < 0.01 } ?? false ? "✓ " : "") + T("Sempre ", "Always ") + n) { m.regoleApp[f.bundle] = v }
        }
        if r != nil { Button(T("Nessuna regola", "No rule")) { m.regoleApp[f.bundle] = nil } }
        Divider()
        Button(T("Lascia libera \(f.app)", "Leave \(f.app) free")) { m.liberaApp(f.bundle) }
    }

    private func testo(_ st: StrisciaVista) -> String {
        if let a = sopraApp { return a }
        guard let f = st.fuoco else { return "" }
        return "\(f.app)   \(f.posto) " + T("di", "of") + " \(f.totale)"
    }

    private func mostraEtichetta() {
        etichetta = true
        nascondi?.cancel()
        let w = DispatchWorkItem { etichetta = false }
        nascondi = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }
}
