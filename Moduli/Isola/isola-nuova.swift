// L'isola nuova (17/10/2026), dall'anteprima approvata dall'autore (agente/anteprima-notch.html, versione 2):
// grammatica di coucou (Louis Raillé), razzo di Spazio al posto della mascotte. Regole sue: niente contorni,
// solo sfumature dell'azzurro di Spazio, tasto principale azzurro chiaro, mai coprire la barra dei menu:
// il pannello si apre SOTTO la barra, attaccato al notch da un collo largo quanto il notch.
import SwiftUI
import AppKit

// MARK: - Colori

// MARK: - Forma

/// Il fondo del pannello, di nuovo attaccato al bordo alto dello schermo coi raccordi del notch (l'autore, 17/10 sera:
/// "agganciare il notch al bordo superiore come era prima"). In Dark Matte la fascia in alto sfuma dal nero al grafite.
struct IslandShellFill: View {
    let neckWidth: CGFloat
    let neckHeight: CGFloat
    // 25/10, l'autore: "su White Matte il notch è ancora nero". Theme.light non è osservato: senza questo la forma
    // aperta restava scura finché l'isola non si chiudeva. Ora si ridisegna a ogni cambio d'aspetto.
    @ObservedObject private var look = GhieraLook.shared
    var body: some View {
        let shape = NotchShape(shoulder: 10, bottom: 28)
        ZStack(alignment: .top) {
            shape.fill(Volta.body)
            if !Theme.light {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.85), location: 0.5), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: neckHeight + 26)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(shape)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(Theme.light ? 0.10 : 0.30), radius: 22, x: 0, y: 12)
    }
}

// MARK: - Mattoni

/// Una tessera: fondo card, angoli 20, la luce dello stato che sale dal basso (niente bordi).
struct VCard<Content: View>: View {
    var glow: Color = Volta.a2
    var motion: [Color]? = nil          // 17/10: colori della copertina che si muovono dietro (musica in riproduzione)
    var breathe = false
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content
    @State private var up = false
    var body: some View {
        content()
            .padding(.horizontal, padding + 2).padding(.vertical, padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Volta.card)
                    if let motion {
                        MusicGlow(colors: motion, playing: true, strength: Theme.light ? 0.28 : 0.34)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    RadialGradient(colors: [glow.opacity(Theme.light ? 0.22 : 0.30), .clear], center: UnitPoint(x: 0.5, y: 1.25), startRadius: 0, endRadius: 260)
                        .opacity(breathe ? (up ? 1 : 0.5) : 0.85)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .onAppear { if breathe { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true } } }
    }
}

/// Bottone a pillola senza contorno. `.primary` è azzurro chiaro; la scorciatoia è solo testo più tenue.
struct VPill: View {
    enum Kind { case normal, primary, ghost, on }
    let title: String
    var key: String? = nil
    var kind: Kind = .normal
    var help: String? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: kind == .primary ? .medium : .regular))
                if let key { Text(key).font(.system(size: 10.5, weight: .medium)).opacity(0.45) }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 14).frame(height: 30)
            .background(Capsule().fill(bg))
            .offset(y: hover ? -1 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hover = h } }
        .help(help ?? "")
    }
    private var bg: Color {
        switch kind {
        case .normal: return Volta.pill
        case .primary: return Volta.prim
        case .ghost: return .clear
        case .on: return Volta.a2.opacity(0.26)
        }
    }
    private var fg: Color {
        switch kind {
        case .normal: return Volta.pillT
        case .primary: return Volta.primT
        case .ghost: return Volta.t3
        case .on: return Volta.a1
        }
    }
}

/// La riga piccola sopra il titolo: puntino azzurro, progetto, cosa succede.
struct VWho: View {
    let project: String
    let what: String
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Volta.a2).frame(width: 6, height: 6)
            Text(project).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Volta.t1).lineLimit(1)
            Text(what).font(.system(size: 12.5)).foregroundStyle(Volta.t2).lineLimit(1).layoutPriority(1)
        }
    }
}

// MARK: - Testa del pannello

enum IslandTab { case casa, tessere }

/// Nella fascia ai lati del notch, come in coucou: a sinistra casa e tessere (più Personalizza nelle tessere),
/// a destra lo stato o, nelle tessere, i pulsanti di prima (impostazioni, griglia, volume, luce, tema, AirDrop, File, Note).
struct IslandHead: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var tiles: TileModel
    var status: String
    init(model: IslandModel, status: String) { self.model = model; self.tiles = model.tiles; self.status = status }

    var body: some View {
        let half = max(0, (model.width - model.notchWidth) / 2 - 30)
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                icon("house.fill", T("Casa", "Home"), on: model.tab == .casa) { model.tab = .casa }
                icon("square.grid.2x2.fill", T("Tessere", "Tiles"), on: model.tab == .tessere) { model.tab = .tessere }
                if model.tab == .tessere {
                    icon(tiles.editing ? "checkmark" : "plus", T("Personalizza", "Customize"), on: tiles.editing) { tiles.editing.toggle() }
                }
                Spacer(minLength: 0)
            }
            .frame(width: half)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                if model.tab == .tessere {
                    icon("gearshape", T("Impostazioni di Sistema", "System Settings")) { IslandActions.settings() }
                    icon("square.grid.3x3", T("Griglia app", "App grid")) { model.openGrid?() }
                    if let d = model.dial {
                        if d.enabled, let it = d.soundItem { icon("speaker.wave.2", T("Volume", "Volume")) { EdgeDock.shared.reveal(it, hideAfter: 4) } }
                        if d.lightEnabled, let it = d.lightItem { icon("sun.max", T("Luminosità", "Brightness")) { EdgeDock.shared.reveal(it, hideAfter: 4) } }
                    }
                    icon("circle.lefthalf.filled", T("Dark Matte o White Matte", "Dark Matte or White Matte")) { model.toggleTheme?() }
                    icon("dot.radiowaves.up.forward", "AirDrop") { IslandActions.airDrop() }
                    icon("folder", T("File", "Files")) { IslandActions.files() }
                    icon("note.text", T("Note", "Notes")) { IslandActions.notes() }
                } else {
                    Text(status).font(.system(size: 11.5)).foregroundStyle(Volta.t3).lineLimit(1).padding(.trailing, 4)
                }
            }
            .frame(width: half)
        }
        .padding(.horizontal, 22)
        .frame(height: model.notchHeight)
    }

    private func icon(_ s: String, _ help: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(on ? Volta.t1 : Volta.t3)
                .frame(width: 24, height: 24)
                .background(Circle().fill(on ? Volta.pill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Casa

/// Niente in corso: una tessera grande con la musica e una colonna di tre righe-dato.
/// Con Claude al lavoro la tessera grande è la sua, e la colonna diventa le sessioni.
struct IslandCasa: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        if model.anteprimaFredda {
            WelcomeCard(store: model.agent, volo: true, media: model.home as? MediaSource)   // anteprima: sempre il riquadro unico
        } else if let st = model.agent, !st.active.isEmpty {
            ClaudeCasa(store: st)
        } else {
            CasaFredda(model: model)
        }
    }
}

private struct MusicCard: View {
    let media: MediaSource?
    var body: some View {
        if let media { Inner(media: media) } else { VCard { Text(T("Niente in riproduzione", "Nothing playing")).font(.system(size: 13)).foregroundStyle(Volta.t3) } }
    }
    private struct Inner: View {
        @ObservedObject var media: MediaSource
        var body: some View {
            let t = media.track ?? media.last
            let playing = media.track?.playing == true
            let cols = ArtPalette.colors(media.artwork)
            VCard(glow: playing ? cols[0] : Volta.a2, motion: playing ? cols : nil) {
                HStack(spacing: 14) {
                    Group {
                        if let a = media.artwork, media.track != nil { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
                        else { LinearGradient(colors: [Volta.a2, Volta.a4], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    }
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            if playing { PixelEQ(colors: cols, playing: true, cell: 2.4) }
                            Text(playing ? T("In ascolto", "Now playing") : t == nil ? T("Musica", "Music") : T("In pausa", "Paused"))
                                .font(.system(size: 12)).foregroundStyle(Volta.t2)
                        }
                        Text(t?.title ?? T("Niente in riproduzione", "Nothing playing")).font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1).lineLimit(1)
                        if let a = t?.artist, !a.isEmpty { Text(a).font(.system(size: 12.5)).foregroundStyle(Volta.t2).lineLimit(1) }
                        if let tr = media.track, tr.duration > 0 {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                let k = min(1, max(0, media.position(at: ctx.date) / tr.duration))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Volta.card2)
                                        Capsule().fill(Volta.a2).frame(width: g.size.width * k)
                                    }
                                }
                                .frame(height: 4).padding(.top, 7)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Claude al lavoro

/// La tessera di Claude col razzo che spinge, e accanto le sessioni in tre toni d'azzurro.
struct ClaudeCasa: View {
    @ObservedObject var store: AgentStore
    var body: some View {
        HStack(spacing: 8) {
            if let s = store.current {
                VCard(glow: Volta.a2) {
                    HStack(spacing: 18) {
                        Razzo(phase: s.pending != nil || s.question != nil ? .wait : .thrust, pixel: 3.6).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 5) {
                            VStack(alignment: .leading, spacing: 2) {
                                VWho(project: s.name, what: "Claude Code")
                                TimelineView(.periodic(from: .now, by: 1)) { _ in
                                    Text(AgentLook.duration(s)).font(.system(size: 12.5)).foregroundStyle(Volta.t3).lineLimit(1).padding(.leading, 13)
                                }
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(s.steps.suffix(3).enumerated()), id: \.offset) { _, st in
                                    HStack(spacing: 8) {
                                        Text(st.state == "now" ? "›" : st.state == "failed" ? "×" : "✓").frame(width: 12)
                                        Text(StepKind.phrase(st.state == "now" ? StepKind.of(st.kind).doing : StepKind.of(st.kind).done, st)).lineLimit(1)
                                    }
                                    .font(.system(size: 12.5)).foregroundStyle(st.state == "now" ? Volta.t1 : Volta.t3)
                                }
                                if s.steps.isEmpty { Text(s.prompt.isEmpty ? T("Sta pensando", "Thinking") : s.prompt).font(.system(size: 12.5)).foregroundStyle(Volta.t2).lineLimit(2) }
                            }
                        }
                    }
                }
            }
            WelcomeCard(store: store).frame(width: 250)
        }
    }
}

/// Compatta, a destra: un razzo solo, più corto del notch (l'autore, 17/10: "sfiora entrambi i bordi").
struct SessionRockets: View {
    @ObservedObject var store: AgentStore
    var body: some View {
        Razzo(phase: store.hasPending || store.question != nil ? .wait : .thrust, pixel: 1.15, flame: 0.6)
            .frame(width: 18, height: 25).clipped()
    }
}

// MARK: - Il pannello aperto

/// Cosa c'è sotto la barra dei menu: la testa (tranne nel trascinamento) e una tessera sola per volta.
struct IslandPanelContent: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        VStack(spacing: 0) {
            if let e = model.email {
                Spacer().frame(height: model.notchHeight + 8)
                EmailCard(bozza: e) { model.email = nil }.id(ObjectIdentifier(e))
                    .frame(height: EmailCard.altezza).padding(.horizontal, 20).padding(.bottom, 10)
            } else if model.dropHover || model.dropNote != nil {
                Spacer().frame(height: model.notchHeight + 8)
                if model.dropHover && model.dropNote == nil && MutaCentro.shared.mostraTessere {
                    // 19/10: Muta, le tessere della bozza A; in fondo alla fila il posto di prima
                    MutaDropCard(altroveTitolo: IslandDrop.goesToClaude ? T("A Claude", "To Claude") : T("Vassoio", "Tray"), altroveClaude: IslandDrop.goesToClaude)
                        .padding(.horizontal, 20).padding(.bottom, 10)
                } else {
                    DropCard(model: model).padding(.horizontal, 20).padding(.bottom, 10)
                }
            } else {
                IslandHead(model: model, status: status)          // nella fascia ai lati del notch
                Spacer().frame(height: 8)
                Group {
                    if let s = model.source, !s.usesHome {
                        s.expandedView()
                    } else if model.tab == .tessere {
                        TileRow(tiles: model.tiles, widgets: model.widgets)
                    } else {
                        IslandCasa(model: model).frame(height: 128)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 10)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()                                       // mai più alto del pannello: la testa resta al suo posto
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()          // niente può allargare il pannello oltre la sua misura
    }

    private var status: String {
        guard let st = model.agent else { return Saluto.ciao(Persona.nome, inglese: !pulsarItalian) }
        if st.question != nil { return T("Claude ti chiede", "Claude asks") }
        if st.hasPending { return T("aspetta il tuo ok", "waiting for your OK") }
        if let s = st.current, s.status == "done", Date().timeIntervalSince1970 - s.finished < 15 {
            return T("fatto in \(AgentLook.duration(s))", "done in \(AgentLook.duration(s))")
        }
        let n = st.active.count
        return n > 0 ? T("\(n) in corso", "\(n) running") : Saluto.ciao(Persona.nome, inglese: !pulsarItalian)
    }
}

/// Il trascinamento: niente bordo tratteggiato, la luce azzurra respira finché il file è sopra.
struct DropCard: View {
    @ObservedObject var model: IslandModel
    @State private var optionHeld = NSEvent.modifierFlags.contains(.option)
    private let tick = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        let toClaude = (IslandDrop.store?.acceptsContext ?? false) && !optionHeld
        VCard(glow: Volta.a1, breathe: model.dropNote == nil) {
            HStack(spacing: 18) {
                Razzo(phase: phase, pixel: 3.6).frame(width: 64, height: 88).clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(toClaude)).font(.system(size: 16, weight: .medium)).foregroundStyle(Volta.t1)
                    if model.dropNote == nil && toClaude {
                        HStack(spacing: 6) {
                            ForEach([T("Immagini", "Images"), "PDF", T("Codice", "Code"), T("Testi", "Text")], id: \.self) { t in
                                Text(t).font(.system(size: 11.5)).foregroundStyle(Volta.t2)
                                    .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(Volta.card2))
                            }
                        }
                    } else {
                        Text(detail(toClaude)).font(.system(size: 12.5)).foregroundStyle(Volta.t2).lineLimit(2)
                    }
                    if model.dropNote?.kind == .toClaude { LoadBar().padding(.top, 6) }
                }
            }
        }
        .onReceive(tick) { _ in optionHeld = NSEvent.modifierFlags.contains(.option) }
    }

    private var phase: Razzo.Phase {
        guard let n = model.dropNote else { return .catchFile }
        switch n.kind { case .toClaude: return .loaded; case .toTray: return .idle; case .taken: return .launch }
    }
    private func names(_ n: DropNote) -> String { n.names.count == 1 ? n.names[0] : T("\(n.names.count) file", "\(n.names.count) files") }
    private func title(_ toClaude: Bool) -> String {
        if let n = model.dropNote {
            switch n.kind {
            case .toClaude: return names(n) + T(" è a bordo", " is on board")
            case .toTray: return T("Nel Vassoio", "In the Tray")
            case .taken: return T("Claude l'ha preso", "Claude has it")
            }
        }
        return toClaude ? T("Lascia qui, va a Claude", "Drop here, it goes to Claude") : T("Lascia qui, va nel Vassoio", "Drop here, it goes to the Tray")
    }
    private func detail(_ toClaude: Bool) -> String {
        if let n = model.dropNote {
            switch n.kind {
            case .toClaude: return T("Parte col tuo prossimo messaggio a Claude", "It leaves with your next message to Claude")
            case .toTray: return names(n) + T(", nella tessera Vassoio", ", in the Tray tile")
            case .taken: return names(n) + T(" è arrivato col tuo messaggio", " arrived with your message")
            }
        }
        return optionHeld ? T("Con ⌥ va nel Vassoio invece che a Claude", "With ⌥ it goes to the Tray instead of Claude")
                          : T("Nessuna sessione di Claude aperta adesso", "No Claude session open right now")
    }
}

/// La barra di carico: si riempie in tre secondi, poi resta piena.
private struct LoadBar: View {
    @State private var k: CGFloat = 0.06
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Volta.card2)
                Capsule().fill(LinearGradient(colors: [Volta.a3, Volta.a2], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * k)
            }
        }
        .frame(height: 6)
        .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 2.6)) { k = 1 } }
    }
}

// MARK: - Il cielo di Spazio

/// Il cielo a pixel della hero di Spazio (os.html, paesaggio + Vault/tema-matte.js, CIELO_SCURO e CIELO_CHIARO):
/// rumore a strati coi sette toni Matte, retinatura 4x4, stelle. Scorre piano. Dietro le sessioni (l'autore, 17/10:
/// "la finestra a destra è carina ma noiosa").
struct CieloPixel: View {
    private static let dark: [(Double, Double, Double)] = [(21, 23, 30), (26, 29, 37), (32, 36, 46), (40, 45, 58), (53, 60, 76), (84, 112, 146), (138, 186, 232)]
    private static let light: [(Double, Double, Double)] = [(243, 244, 247), (238, 240, 244), (232, 235, 240), (225, 229, 235), (216, 221, 229), (200, 210, 224), (172, 192, 220)]
    private static let perm: [Int] = {
        var p = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) { let j = Int((UInt64(i) &* 2654435761) % UInt64(i + 1)); p.swapAt(i, j) }
        return p + p
    }()
    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    private static func h2(_ i: Int, _ j: Int) -> Double { Double(perm[(perm[i & 255] + j) & 255]) / 255 }
    private static func sm(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private static func vn(_ x: Double, _ y: Double) -> Double {
        let i = Int(floor(x)), j = Int(floor(y)), fx = sm(x - floor(x)), fy = sm(y - floor(y))
        let a = h2(i, j), b = h2(i + 1, j), c = h2(i, j + 1), e = h2(i + 1, j + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + e) * fx * fy
    }
    private static func fbm(_ x: Double, _ y: Double) -> Double {
        var v = 0.0, a = 0.5, f = 1.0
        for _ in 0..<4 { v += a * vn(x * f, y * f); a *= 0.5; f *= 2.03 }
        return v
    }
    private static func pick(_ h: Double) -> Int { h < 0.30 ? 0 : h < 0.37 ? 1 : h < 0.40 ? 2 : h < 0.58 ? 3 : h < 0.63 ? 4 : h < 0.79 ? 5 : 6 }

    /// Lato di un pixel del cielo in punti (4 nella Casa, 8 a schermo intero nella griglia).
    var cell: CGFloat = 4
    var fps: Double = 8
    var calm: Double = 0        // 0 = contrasto della hero; più alto avvicina i toni al grigio medio (griglia a schermo intero)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1.0 / fps)) { ctx in
                let W = max(1, Int(ceil(geo.size.width / cell))), H = max(1, Int(ceil(geo.size.height / cell)))
                if let img = Self.render(W: W, H: H, t: ctx.date.timeIntervalSinceReferenceDate, light: Theme.light, calm: calm) {
                    Image(decorative: img, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(W) * cell, height: CGFloat(H) * cell)
                }
            }
        }
        .clipped()
    }

    /// Il cielo come immagine piccola (un pixel per cella), ingrandita senza sfumare: così anche a schermo intero
    /// costa poco (prima era un rettangolo disegnato per ogni cella a ogni fotogramma).
    static func render(W: Int, H: Int, t time: Double, light: Bool, calm: Double = 0) -> CGImage? {
        let pal = light ? Self.light : Self.dark
        let star = light ? (120.0, 130.0, 150.0) : (196.0, 206.0, 222.0)
        let t = time.truncatingRemainder(dividingBy: 10_000) * 0.012
        let k = 150.0 / Double(max(W, 1)) * 0.6 * 1.6            // scala del rumore come la hero (150 px di larghezza)
        var buf = [UInt8](repeating: 255, count: W * H * 4)
        for y in 0..<H {
            let gy = Double(y) / Double(H)
            for x in 0..<W {
                let px = Double(x) * k, py = Double(y) * k
                let n = fbm(px / 32 + t, py / 27 + t * 0.4)
                let h = n * 0.62 + gy * 0.55 - 0.08 + (bayer[(y & 3) * 4 + (x & 3)] - 7.5) / 16 * 0.05
                var c = pal[pick(h)]
                if calm > 0 { let m = pal[3]; c = (c.0 + (m.0 - c.0) * calm, c.1 + (m.1 - c.1) * calm, c.2 + (m.2 - c.2) * calm) }
                if h < 0.5 && fbm(px / 3 + 40, py / 3 - t * 2) > 0.8 { c = star }
                let o = (y * W + x) * 4
                buf[o] = UInt8(c.0); buf[o + 1] = UInt8(c.1); buf[o + 2] = UInt8(c.2)
            }
        }
        guard let prov = CGDataProvider(data: Data(buf) as CFData) else { return nil }
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}


// MARK: - Benvenuto sul cielo di Spazio

/// La finestra a destra della Casa sul cielo di Spazio (l'autore, 17/10: "bella da vedere, lo sfondo è ottimo").
/// Un dato protagonista (le ore di oggi, grande e leggero), il saluto piccolo in alto con l'ora, in basso cosa ti manca;
/// i razzi delle sessioni attraversano piano il cielo.
struct WelcomeCard: View {
    var store: AgentStore?
    /// 24/10: a freddo (né Claude né musica che suona) è il riquadro unico della Casa: il razzo vola nel cielo, come la
    /// mascotte di coucou, e una canzone in pausa diventa un tasto piccolo in basso a destra.
    var volo = false
    var media: MediaSource? = nil
    @ObservedObject private var cose = AnimaCose.shared

    var body: some View {
        if volo { casaPulita } else { conDati }
    }

    /// 24/10 sera, l'autore: "troppo confusionario, togliere il buongiorno, il razzo al centro, troppo disordine".
    /// Il cielo, il razzo che vola piano attorno al centro e una riga sola, leggera, in basso al centro.
    private var casaPulita: some View {
        ZStack {
            CieloPixel()
            RazzoInVolo()
            if haDati {    // senza il dato (Spazio non ha ancora risposto) niente riga, mai "0 ore"
                VStack {
                    Spacer()
                    Text(ore.0 + " " + ore.1).font(.system(size: 13, weight: .light)).foregroundStyle(Volta.t1.opacity(0.75))
                        .padding(.bottom, 12)
                }
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
        }
    }

    private var haDati: Bool {
        return !cose.aperte.isEmpty
    }

    private var conDati: some View {
        ZStack {
            CieloPixel()
            // un velo morbido dove sta il testo, così si legge sul cielo senza riquadri
            LinearGradient(colors: [Volta.body.opacity(Theme.light ? 0.55 : 0.6), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            // 24/10 sera, l'autore: "togli il razzo nel riquadro a destra, altrimenti ce ne sono troppi"
            VStack(alignment: .leading, spacing: 0) {
                // 24/10, l'autore: "togliere il buongiorno": niente saluto né ora, solo i dati
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ore.0).font(.system(size: 30, weight: .light)).tracking(-0.6).foregroundStyle(Volta.t1)
                    Text(ore.1).font(.system(size: 12)).foregroundStyle(Volta.t2)
                }
                Spacer(minLength: 4)
                // 19/10 sera, l'autore: pallino blu dentro un rettangolo arrotondato = AI slop; il solo testo "troppo blando".
                // Gli step aperti diventano una fila di LED (uno per step, come i segmenti di Nothing e le tacche Braun).
                if inFoto {
                    EmptyView()
                } else if cose.steps.count > 0 {
                    StepLED(n: cose.steps.count)
                } else if let m = cose.studio {
                    Text(m).font(.system(size: 11.5)).foregroundStyle(Volta.t2).lineLimit(1)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            cose.start()
        }
    }

    private var saluto: String {
        let h = Calendar.current.component(.hour, from: orologio(Date()))
        return Saluto.ora(h, Persona.nome, inglese: !pulsarItalian)
    }
    private var inFoto: Bool {
        return false
    }
    /// L'ora mostrata: quella vera; nelle foto di vendita le 14:56 di un giorno qualsiasi.
    private func orologio(_ d: Date) -> Date {
        inFoto ? (Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 14, minute: 56)) ?? d) : d
    }
    /// (il numero, cosa misura). Nella build dell'autore le ore di lavoro di oggi (Spazio); nella vendita, che non ha
    /// Spazio, le cose da fare aperte della lista locale.
    private var ore: (String, String) {
        let n = cose.aperte.count
        return ("\(n)", n == 1 ? T("cosa da fare", "thing to do") : T("cose da fare", "things to do"))
    }
}

/// Gli step aperti come fila di LED: il numero, un segmento per step (al massimo 12, poi "+"), la parola.
/// Una luce lenta li attraversa da sinistra a destra; con Pulsar leggera resta ferma.
private struct StepLED: View {
    let n: Int
    private var mostrati: Int { min(n, 12) }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(n)").font(.system(size: 15, weight: .light).monospacedDigit()).foregroundStyle(Volta.t1)
            TimelineView(.animation(minimumInterval: 1 / 20, paused: Leggera.on)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let luce = (t.truncatingRemainder(dividingBy: 3.2)) / 3.2 * Double(mostrati + 4) - 2   // la posizione della luce
                HStack(spacing: 3) {
                    ForEach(0..<mostrati, id: \.self) { i in
                        let vicino = max(0, 1 - abs(Double(i) - luce) / 1.6)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Volta.a2.opacity(0.45 + 0.55 * vicino))
                            .frame(width: 4, height: 12)
                    }
                    if n > 12 { Text("+").font(.system(size: 10, weight: .medium)).foregroundStyle(Volta.a2) }
                }
            }
            Text(n == 1 ? T("step da fare", "step to do") : T("step da fare", "steps to do"))
                .font(.system(size: 11.5)).foregroundStyle(Volta.t2).lineLimit(1)
        }
    }
}

/// Il razzo nel cielo: uno solo, sospeso in basso a destra, che respira piano (l'autore, 17/10: "quelli che fanno su
/// e giù non mi piacciono, lasciane uno solo"). Motore spento con l'oblò che pulsa se una sessione aspetta un ok.
private struct Rockets: View {
    var store: AgentStore?
    var body: some View {
        let waiting = store?.active.contains { $0.pending != nil || $0.question != nil } ?? false
        let working = !(store?.active.isEmpty ?? true)
        Razzo(phase: waiting ? .wait : working ? .thrust : .idle, pixel: 2.2)
            .frame(width: 32, height: 52)
            .padding(.trailing, 22).padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

// MARK: - Casa a freddo (24/10)

/// l'autore, 24/10: "la schermata a freddo, quando il notch non lavora con Claude, è brutta e immobile: un riquadro solo
/// un pelo più stretto con il razzo che vola nello spazio (come coucou)". Con la musica che suona resta la tessera
/// musicale accanto al benvenuto; senza, un riquadro solo sul cielo di Spazio.
struct CasaFredda: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        if let media = model.home as? MediaSource { ConMusica(media: media, store: model.agent) }
        else { WelcomeCard(store: model.agent, volo: true) }
    }
    /// Osserva la musica: quando riparte la Casa torna alla tessera musicale, quando si ferma al riquadro unico.
    private struct ConMusica: View {
        @ObservedObject var media: MediaSource
        let store: AgentStore?
        var body: some View {
            if media.track?.playing == true {
                HStack(spacing: 8) {
                    MusicCard(media: media)
                    WelcomeCard(store: store).frame(width: 250)
                }
            } else {
                WelcomeCard(store: store, volo: true, media: media)
            }
        }
    }
}

/// Il razzo che vola nel cielo della Casa a freddo: gira piano nella metà destra (una curva che non si ripete mai uguale),
/// spinge quando sale e plana quando scende. Resta dritto: la pixel art ruotata si sfoca. Con Pulsar leggera sta fermo.
private struct RazzoInVolo: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Leggera.on)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                // due onde lente con periodi diversi: il percorso cambia sempre, senza scatti
                // attorno al centro, piano (l'autore, 24/10: "il razzo al centro")
                // 24/10 sera: proprio al centro, oscillazione più piccola
                let x = w * (0.5 + 0.035 * sin(t * 0.21) + 0.01 * sin(t * 0.53 + 1.3))
                let y = h * (0.46 + 0.05 * sin(t * 0.33 + 0.7) + 0.01 * sin(t * 0.9))
                // la velocità verticale (derivata di y): sullo schermo y cresce verso il basso, quindi sale se è negativa
                let vy = 0.05 * 0.33 * cos(t * 0.33 + 0.7) + 0.01 * 0.9 * cos(t * 0.9)
                Razzo(phase: vy < 0 ? .thrust : .idle, pixel: 2.6)      // un po' più grande (era 2)
                    .frame(width: 36, height: 60)
                    .position(x: x.rounded(), y: y.rounded())
            }
        }
        .allowsHitTesting(false)
    }
}

/// Una canzone in pausa, piccola: la copertina vera, il titolo e il tasto per farla ripartire. In basso a destra.
private struct PausaPiccola: View {
    @ObservedObject var media: MediaSource
    var body: some View {
        if let t = media.track ?? media.last {
            Button { media.command(.playPause) } label: {
                HStack(spacing: 7) {
                    Group {
                        if let a = media.artwork { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
                        else { LinearGradient(colors: [Volta.a2, Volta.a4], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    }
                    .frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(t.title).font(.system(size: 11)).foregroundStyle(Volta.t1).lineLimit(1).frame(maxWidth: 130, alignment: .leading)
                    Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Volta.t1)
                }
                .padding(.leading, 5).padding(.trailing, 10).frame(height: 26)
                .background(Capsule().fill(Volta.body.opacity(0.7)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(T("Riprendi la musica", "Resume the music"))
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
