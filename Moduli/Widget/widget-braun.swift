// Funzioni viste in LaunchMe, disegnate con le forme del disegno industriale (14/10/2026). Studio in docs/2026-10-14-braun.md.
// l'autore: "aggiungi qualche funzione di LaunchMe sulla nostra notch mantenendo il nostro stile"; "un commento dice che sembra
// Braun / NeXT: studia i prodotti iconici e applica forme e misure"; "applica tutto quello che vedi".
// Da LaunchMe le funzioni (orologio, mese a puntini, alba e tramonto, bordo dello schermo coi colori della copertina,
// lettore a tutto schermo col giradischi); da Braun le forme (quadrante AB1, griglia della T3); il colore resta il nostro.
// Lasciati fuori: il gattino in pixel (personaggi bocciati il 04/10) e lo sfondo con la copertina animata.
import SwiftUI
import AppKit

private enum Braun {
    static var ink: Color { Theme.light ? Color(red: 0.12, green: 0.13, blue: 0.17) : Color(red: 0.93, green: 0.94, blue: 0.97) }
    static var soft: Color { ink.opacity(0.45) }
    static var face: Color { Theme.light ? Color.white : Color(red: 0.13, green: 0.14, blue: 0.18) }
}

// MARK: - Orologio (quadrante Braun AB1)

struct ClockWidget: IslandWidget {
    let id = "clock"
    var title: String { T("Orologio", "Clock") }
    let symbol = "clock"
    func body(cells: Int) -> AnyView { AnyView(ClockTile(cells: cells)) }
}

private struct ClockTile: View {
    let cells: Int
    @ObservedObject private var look = GhieraLook.shared
    var body: some View {
        HStack(spacing: 14) {
            BraunDial().frame(width: 74, height: 74)
            if cells >= 2 {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: pulsarItalian ? "it_IT" : "en_US"))).capitalized)
                            .font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.5))
                        Text(ctx.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: pulsarItalian ? "it_IT" : "en_US"))))
                            .font(.system(size: 14, weight: .regular)).foregroundStyle(Color.primary.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cells >= 2 ? .leading : .center)
    }
}

/// Quadrante: tacche dei minuti sottili, delle ore lunghe, numeri 12 3 6 9, lancette arrotondate, secondi nell'accento.
struct BraunDial: View {
    @ObservedObject private var look = GhieraLook.shared
    var body: some View {
        // Pulsar leggera: la lancetta dei secondi scatta una volta al secondo (come un Braun al quarzo), se no scivola
        TimelineView(.animation(minimumInterval: Leggera.on ? 1.0 : 1.0 / 20)) { ctx in
            Canvas { g, size in
                let d = min(size.width, size.height), r = d / 2, c = CGPoint(x: size.width / 2, y: size.height / 2)
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: d, height: d)), with: .color(Braun.face))
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * .pi - .pi / 2
                    let hour = i % 5 == 0
                    let r1 = r * (hour ? 0.80 : 0.88), r2 = r * 0.94
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
                    g.stroke(p, with: .color(Braun.ink.opacity(hour ? 0.85 : 0.3)), lineWidth: hour ? d * 0.022 : d * 0.009)
                }
                for (n, i) in [(12, 0), (3, 15), (6, 30), (9, 45)] {
                    let a = Double(i) / 60 * 2 * .pi - .pi / 2
                    let rr = r * 0.6
                    g.draw(Text("\(n)").font(.system(size: d * 0.13, weight: .regular)).foregroundColor(Braun.ink),
                           at: CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr))
                }
                let cal = Calendar.current, now = ctx.date
                let s = Double(cal.component(.second, from: now)) + (Leggera.on ? 0 : now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1))
                let m = Double(cal.component(.minute, from: now)) + s / 60
                let h = Double(cal.component(.hour, from: now) % 12) + m / 60
                func hand(_ frac: Double, _ len: Double, _ w: CGFloat, _ col: Color, tail: Double = 0.12) {
                    let a = frac * 2 * .pi - .pi / 2
                    var p = Path()
                    p.move(to: CGPoint(x: c.x - cos(a) * r * tail, y: c.y - sin(a) * r * tail))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * r * len, y: c.y + sin(a) * r * len))
                    g.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round))
                }
                hand(h / 12, 0.5, d * 0.05, Braun.ink)
                hand(m / 60, 0.76, d * 0.035, Braun.ink)
                hand(s / 60, 0.84, d * 0.014, DotColors.azzurro, tail: 0.2)          // l'unico accento, come il giallo di Braun
                g.fill(Path(ellipseIn: CGRect(x: c.x - d * 0.04, y: c.y - d * 0.04, width: d * 0.08, height: d * 0.08)), with: .color(DotColors.azzurro))
            }
        }
    }
}

// MARK: - Il mese a puntini (la griglia della radio T3)

struct MonthWidget: IslandWidget {
    let id = "month"
    var title: String { T("Mese", "Month") }
    let symbol = "circle.grid.3x3"
    func body(cells: Int) -> AnyView { AnyView(MonthTile(cells: cells)) }
}

private struct MonthTile: View {
    let cells: Int
    @ObservedObject private var look = GhieraLook.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let cal = Calendar.current, now = ctx.date
            let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
            let today = cal.component(.day, from: now)
            let left = days - today
            let month = now.formatted(.dateTime.month(.wide).locale(Locale(identifier: pulsarItalian ? "it_IT" : "en_US"))).capitalized
            let cols = cells >= 2 ? 11 : 7
            VStack(alignment: .leading, spacing: 6) {
                Canvas { g, size in
                    let rows = Int(ceil(Double(days) / Double(cols)))
                    let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows)), dd = cell * 0.62
                    for i in 0..<days {
                        let x = CGFloat(i % cols) * cell + (cell - dd) / 2, y = CGFloat(i / cols) * cell + (cell - dd) / 2
                        let p = Path(ellipseIn: CGRect(x: x, y: y, width: dd, height: dd))
                        if i + 1 == today { g.fill(p, with: .color(DotColors.azzurro)) }
                        else { g.fill(p, with: .color(Color.primary.opacity(i + 1 < today ? 0.55 : 0.14))) }
                    }
                }
                .frame(maxHeight: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // a una cella il mese abbreviato e il numero da solo: niente a capo
                    Text(cells >= 2 ? month : String(month.prefix(3))).font(.system(size: 10.5)).lineLimit(1)
                        .foregroundStyle(Color.primary.opacity(0.75)).fixedSize()
                    Spacer(minLength: 2)
                    Text("\(left)").font(.system(size: 11, weight: .regular).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.85)).fixedSize()
                    if cells >= 2 {
                        Text(T("giorni", "days left").uppercased()).font(.system(size: 8.5, design: .monospaced)).tracking(0.8)
                            .foregroundStyle(Color.primary.opacity(0.45)).fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: - Alba e tramonto (l'arco del sole)

final class SunModel: ObservableObject {
    static let shared = SunModel()
    @Published private(set) var rise: Date?
    @Published private(set) var set: Date?
    private var day = ""
    func refresh() {
        let key = Date().formatted(.iso8601.year().month().day())
        guard key != day else { return }
        guard let lat = Impostazioni.object(.isolaLat) as? Double, let lon = Impostazioni.object(.isolaLon) as? Double,
              let u = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&daily=sunrise,sunset&timezone=auto&forecast_days=1") else { return }
        day = key
        URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 8)) { [weak self] data, _, _ in
            guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = o["daily"] as? [String: Any],
                  let r = (daily["sunrise"] as? [String])?.first, let s = (daily["sunset"] as? [String])?.first else { self?.day = ""; return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; f.timeZone = .current
            DispatchQueue.main.async { self?.rise = f.date(from: r); self?.set = f.date(from: s) }
        }.resume()
    }
}

struct SunWidget: IslandWidget {
    let id = "sun"
    var title: String { T("Sole", "Sun") }
    let symbol = "sun.horizon"
    func body(cells: Int) -> AnyView { AnyView(SunTile(sun: .shared, cells: cells)) }
}

private struct SunTile: View {
    @ObservedObject var sun: SunModel
    let cells: Int
    @ObservedObject private var look = GhieraLook.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let r = sun.rise, s = sun.set
            let p: Double? = (r != nil && s != nil) ? (now.timeIntervalSince(r!) / s!.timeIntervalSince(r!)) : nil
            let isDay = p.map { $0 >= 0 && $0 <= 1 } ?? true
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(isDay ? T("Giorno", "Day") : T("Notte", "Night")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.8))
                    Spacer()
                }
                Canvas { g, size in
                    let w = size.width, h = size.height
                    let base = h - 4
                    // l'orizzonte e l'arco del giorno
                    var hz = Path(); hz.move(to: CGPoint(x: 0, y: base)); hz.addLine(to: CGPoint(x: w, y: base))
                    g.stroke(hz, with: .color(Color.primary.opacity(0.15)), lineWidth: 1)
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: w / 2, y: base), radius: min(w / 2 - 6, h - 8), startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    g.stroke(arc, with: .color(Color.primary.opacity(0.22)), style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                    let rad = min(w / 2 - 6, h - 8)
                    let t = min(1, max(0, p ?? 0.5))
                    let a = Double.pi * (1 - t)
                    let c = CGPoint(x: w / 2 + cos(a) * rad, y: base - sin(a) * rad)
                    let sunCol = isDay ? Color(red: 1, green: 0.62, blue: 0.3) : DotColors.azzurro
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26)),
                           with: .radialGradient(Gradient(colors: [sunCol.opacity(0.35), .clear]), center: c, startRadius: 0, endRadius: 13))
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(sunCol))
                }
                HStack {
                    Text(r.map { $0.formatted(date: .omitted, time: .shortened) } ?? "--:--")
                    Spacer()
                    Text(s.map { $0.formatted(date: .omitted, time: .shortened) } ?? "--:--")
                }
                .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.45))
            }
        }
        .onAppear { sun.refresh() }
    }
}

// MARK: - Il bordo dello schermo a ritmo, coi colori della copertina

/// Una finestra trasparente grande come lo schermo che disegna solo una luce lungo i bordi. Non prende i clic.
/// Si accende quando la musica suona e l'interruttore è attivo (menu ISOLA), si spegne da sola appena si ferma.
final class EdgeGlow {
    static let shared = EdgeGlow()
    static var enabled: Bool {
        get { Impostazioni.object(.isolaBordoMusica) as? Bool ?? false }
        set { Impostazioni.set(newValue, .isolaBordoMusica); shared.check() }
    }
    private var win: NSPanel?
    private var timer: Timer?
    private weak var media: MediaSource?

    func start(media: MediaSource) {
        self.media = media
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        let on = Self.enabled && media?.track?.playing == true
        if on && win == nil { show() } else if !on && win != nil { hide() }
    }

    private func show() {
        guard let media, let s = NSScreen.main else { return }
        let w = NSPanel(contentRect: s.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let bundle = media.track?.app == "Music" ? "com.apple.Music" : "com.spotify.client"
        w.contentView = NSHostingView(rootView: EdgeGlowView(media: media, bundle: bundle))
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.8; w.animator().alphaValue = 1 }
        win = w
    }

    private func hide() {
        guard let w = win else { return }
        win = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.8; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }
}

private struct EdgeGlowView: View {
    @ObservedObject var media: MediaSource
    let bundle: String
    @ObservedObject var meter = MusicMeter.shared
    var body: some View {
        TimelineView(.animation(minimumInterval: Leggera.on ? 1.0 / 12 : 1.0 / 30)) { ctx in   // acceso a mano dal menu; in leggera più piano
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pal = CoverPalette.colors(media.artwork)
            let cols = pal.isEmpty ? [DotColors.azzurro, .white] : pal + [pal[0]]
            let lv = meter.level, kick = meter.beat
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AngularGradient(colors: cols, center: .center, angle: .degrees(t * 12)),
                        lineWidth: 10 + 22 * lv + 10 * kick)
                .blur(radius: 18 + 10 * lv)
                .opacity(0.35 + 0.55 * min(1, lv * 1.2 + kick * 0.4))
                .padding(-6)
        }
        .allowsHitTesting(false)
        .onAppear { meter.watch(true, bundle: bundle) }
        .onDisappear { meter.watch(false, bundle: bundle) }
    }
}

// MARK: - Lettore a tutto schermo: copertina e giradischi

final class FullPlayer {
    static let shared = FullPlayer()
    private var win: NSWindow?
    private var monitor: Any?

    func toggle(media: MediaSource) { win == nil ? open(media) : close() }

    private func open(_ media: MediaSource) {
        guard let s = NSScreen.main else { return }
        let w = KeyPanel(contentRect: s.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .floating
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: FullPlayerView(media: media, close: { [weak self] in self?.close() }))
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.45; w.animator().alphaValue = 1 }
        win = w
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil }                                  // Esc
            if e.keyCode == 49 { media.track != nil ? media.command(.playPause) : media.resumeLast(); return nil }   // Spazio
            return e
        }
    }

    func close() {
        guard let w = win else { return }
        win = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }

    private final class KeyPanel: NSWindow {
        override var canBecomeKey: Bool { true }
    }
}

private struct FullPlayerView: View {
    @ObservedObject var media: MediaSource
    let close: () -> Void
    var body: some View {
        let t = media.track ?? media.last
        let live = media.track != nil, playing = media.track?.playing == true
        GeometryReader { geo in
            let side = min(geo.size.height * 0.46, geo.size.width * 0.3)
            ZStack {
                // il fondo: la copertina enorme e sfocata, scurita
                Group {
                    if let a = media.artwork { Image(nsImage: a).resizable().scaledToFill().blur(radius: 80).saturation(1.2) }
                    else { Color(red: 0.09, green: 0.10, blue: 0.13) }
                }
                .frame(width: geo.size.width, height: geo.size.height).clipped()
                .overlay(Color.black.opacity(0.45))
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

                VStack(spacing: 34) {
                    HStack(spacing: -side * 0.42) {
                        Group {
                            if let a = media.artwork { Image(nsImage: a).resizable().scaledToFill() } else { Color.white.opacity(0.1) }
                        }
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
                        .zIndex(1)
                        Turntable(art: media.artwork, playing: playing).frame(width: side * 0.96, height: side * 0.96)
                            .offset(x: playing ? side * 0.2 : 0)
                            .animation(.spring(response: 0.9, dampingFraction: 0.85), value: playing)
                    }
                    VStack(spacing: 6) {
                        Text(t?.title ?? T("Niente in riproduzione", "Nothing playing")).font(.system(size: 26, weight: .regular)).tracking(-0.4)
                        Text(t?.artist ?? "").font(.system(size: 15)).opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    HStack(spacing: 40) {
                        btn("backward.fill", 20) { media.command(.previous) }.opacity(live ? 1 : 0.35)
                        btn(playing ? "pause.fill" : "play.fill", 30) { live ? media.command(.playPause) : media.resumeLast() }
                        btn("forward.fill", 20) { media.command(.next) }.opacity(live ? 1 : 0.35)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain).padding(28)
            }
        }
        .ignoresSafeArea()
    }
    private func btn(_ s: String, _ size: CGFloat, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.system(size: size)).foregroundStyle(.white).frame(width: 54, height: 54).contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

/// Il giradischi: piatto nero con i solchi, etichetta = copertina, e il braccio che si posa quando suona.
private struct Turntable: View {
    let art: NSImage?
    let playing: Bool
    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 40, paused: !playing)) { ctx in
                    let a = playing ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360 : 0
                    ZStack {
                        Circle().fill(Color(white: 0.06))
                        ForEach(0..<10, id: \.self) { i in
                            Circle().stroke(Color.white.opacity(0.04 + 0.02 * Double(i % 2)), lineWidth: 0.8).padding(d * (0.06 + 0.028 * Double(i)))
                        }
                        Group { if let art { Image(nsImage: art).resizable().scaledToFill() } else { Color(white: 0.3) } }
                            .frame(width: d * 0.34, height: d * 0.34).clipShape(Circle())
                        Circle().fill(Color(white: 0.85)).frame(width: d * 0.025, height: d * 0.025)
                    }
                    .rotationEffect(.degrees(a))
                }
                // il riflesso fermo, così si vede che il disco gira
                Circle().trim(from: 0.08, to: 0.2).stroke(Color.white.opacity(0.08), lineWidth: d * 0.3).padding(d * 0.17)
                // il braccio
                Capsule().fill(Color(white: 0.82)).frame(width: d * 0.025, height: d * 0.55)
                    .rotationEffect(.degrees(playing ? 24 : 6), anchor: .top)
                    .offset(x: d * 0.42, y: -d * 0.12)
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: playing)
                Circle().fill(Color(white: 0.7)).frame(width: d * 0.07, height: d * 0.07).offset(x: d * 0.42, y: -d * 0.4)
            }
        }
    }
}
