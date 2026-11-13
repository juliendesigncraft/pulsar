// Pulsar — il saluto all'avvio (13/11/2026). l'autore: "schermata di avvio falla simile a quella di coucou".
// Da coucou si prende la grammatica: all'avvio il notch si allarga in un pannello nero, un cielo di stelline si accende,
// al centro compare chi abita il notch, saluta e il pannello si richiude. Niente mascotte né niente di suo (scelta di
// l'autore del 17/10): al centro c'è il razzo di Spazio, che sale un filo, respira e decolla. Movimenti semplici,
// curva morbida e niente rimbalzi o forme liquide (memoria pulsar-niente-goccia). Spegnibile: Impostazioni → Aspetto.
import AppKit
import SwiftUI

enum SalutoAvvio {
    static var acceso: Bool {
        get { Impostazioni.object(.avvioSaluto) as? Bool ?? true }
        set { Impostazioni.set(newValue, .avvioSaluto) }
    }
    private static var finestra: NSPanel?

    /// Mostra il saluto una volta (circa 3,4 s). `forza` per le prove (pulsar://avvio) anche a saluto spento.
    static func mostra(forza: Bool = false) {
        guard forza || acceso, finestra == nil else { return }
        let sc = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        var collo = CGSize(width: 190, height: NSStatusBar.system.thickness)
        if sc.safeAreaInsets.top > 0, let l = sc.auxiliaryTopLeftArea, let r = sc.auxiliaryTopRightArea {
            collo = CGSize(width: sc.frame.width - l.width - r.width, height: sc.safeAreaInsets.top)
        }
        let larga: CGFloat = 500, alta = collo.height + 100    // 13/11, l'autore: più bassa di prima (112), poi un filo più alta
        let p = NSPanel(contentRect: NSRect(x: sc.frame.midX - larga / 2, y: sc.frame.maxY - alta, width: larga, height: alta),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: VistaSaluto(collo: collo, larga: larga, alta: alta) {
            finestra?.orderOut(nil); finestra = nil
        })
        finestra = p
        p.orderFrontRegardless()
    }
}

private struct VistaSaluto: View {
    let collo: CGSize
    let larga: CGFloat
    let alta: CGFloat
    let fine: () -> Void
    @State private var aperto = false
    @State private var dentro = false
    @State private var fase: Razzo.Phase = .idle
    @State private var nato = Date()
    private static let curva = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.55)

    var body: some View {
        let w = aperto ? larga : collo.width, h = aperto ? alta : collo.height
        ZStack(alignment: .top) {
            ZStack {
                NotchShape(shoulder: 10, bottom: aperto ? 30 : 10).fill(Color.black)
                // 13/11, l'autore: "aggiungi un margine di contorno": stelle e razzo dentro un riquadro staccato dai bordi
                // (12 pt ai lati e in basso, sotto la fascia del notch), come le card dell'isola
                VStack(spacing: 0) {
                    Spacer().frame(height: collo.height - 8)      // 13/11: il bordo alto del riquadro più su, dentro la fascia del notch
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.075))
                        Cielo(nato: nato).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Razzo(phase: fase, pixel: 3.6)
                            .id(fase == .launch)          // il decollo parte da quando cambia fase (il razzo conta dal suo arrivo)
                            .frame(width: 56, height: 80)
                            .offset(y: dentro ? 0 : 12)
                            .clipShape(Rectangle())
                    }
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
                .opacity(dentro ? 1 : 0)
            }
            .frame(width: w, height: h)
        }
        .frame(width: larga, height: alta, alignment: .top)
        .onAppear {
            withAnimation(Self.curva) { aperto = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { nato = Date(); withAnimation(.easeOut(duration: 0.6)) { dentro = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { fase = .launch }                       // saluta: decolla
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { withAnimation(.easeIn(duration: 0.25)) { dentro = false } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.35) { withAnimation(Self.curva) { aperto = false } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: fine)
        }
    }
}

/// Stelline fisse (sempre le stesse) che si accendono una dopo l'altra e respirano piano.
/// 13/11: anche lo sfondo della Casa nel notch Minimal (SfondoCasa in isola-minimal.swift).
struct Cielo: View {
    let nato: Date
    var colore: Color = .white            // nella Casa di White Matte le stelle sono scure
    private static let stelle: [(x: Double, y: Double, r: Double, ritardo: Double)] = {
        var s: UInt64 = 13_11_2026
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 33) / Double(1 << 31) }
        return (0..<46).map { _ in (rnd(), 0.25 + rnd() * 0.72, 0.6 + rnd() * 1.1, rnd() * 0.9) }
    }()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(nato)
                for st in Self.stelle {
                    let accesa = min(1, max(0, (t - st.ritardo) / 0.5))
                    let respiro = 0.55 + 0.45 * sin(t * 2.2 + st.x * 20)
                    let a = accesa * respiro * 0.85
                    guard a > 0.01 else { continue }
                    let r = CGRect(x: st.x * size.width - st.r / 2, y: st.y * size.height - st.r / 2, width: st.r, height: st.r)
                    g.fill(Path(ellipseIn: r), with: .color(colore.opacity(a)))
                }
            }
        }
    }
}
