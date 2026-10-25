// Widget dell'isola: tessere orizzontali da 1 a 4 celle, ridimensionabili, riordinabili, che seguono il tema.
// Spec: docs/2026-10-11-isola-design.md, sezione 2. Layout e meteo (logica pura) in isola-logica.swift.
// Una tessera non ha stile suo: colori e materiale vengono da Theme e da Color.primary (colorScheme dell'isola).
import SwiftUI
import AppKit
import EventKit

enum TileMetrics {
    static let cell: CGFloat = 84
    static let gap: CGFloat = 8
    static let rowH: CGFloat = 96
    static let radius: CGFloat = 20
}

protocol IslandWidget {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    func body(cells: Int) -> AnyView
}

/// Layout salvato (UserDefaults `isolaTiles`) e modalità modifica, condivisi fra riga e isola.
final class TileModel: ObservableObject {
    @Published var layout: TileLayout = TileLayout.decode(Impostazioni.data(.isolaTiles)) {
        didSet { Impostazioni.set(layout.encode(), .isolaTiles) }
    }
    @Published var editing = false
}

// MARK: - La riga di tessere

struct TileRow: View {
    @ObservedObject var tiles: TileModel
    let widgets: [IslandWidget]
    @State private var dragID: String?
    @State private var dragDX: CGFloat = 0
    @State private var startMouse: CGFloat = 0
    @State private var resizeBase: Int?
    @State private var appeared = false

    private func width(_ cells: Int) -> CGFloat { CGFloat(cells) * TileMetrics.cell + CGFloat(cells - 1) * TileMetrics.gap }
    private var shown: [(Tile, IslandWidget)] {
        tiles.layout.tiles.compactMap { t in widgets.first { $0.id == t.id }.map { (t, $0) } }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: TileMetrics.gap) {
                ForEach(Array(shown.enumerated()), id: \.element.0.id) { i, pair in tile(pair.0, pair.1, index: i) }
            }
            if tiles.editing { chips }
        }
        .onAppear { appeared = true }
    }

    private func tile(_ t: Tile, _ w: IslandWidget, index: Int) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous).fill(Volta.card)   // 17/10: come le tessere della Casa
            w.body(cells: t.cells)
                .padding(10)
                .frame(width: width(t.cells), height: TileMetrics.rowH, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous))
                .allowsHitTesting(!tiles.editing)
            if tiles.editing {
                Button { tiles.layout.remove(t.id) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundStyle(Night.red, Color.primary.opacity(0.9))
                }
                .buttonStyle(.plain)
                .offset(x: -5, y: -5)
                HStack { Spacer(); handle(t) }
            }
        }
        .frame(width: width(t.cells), height: TileMetrics.rowH)
        .offset(x: dragID == t.id ? dragDX : 0)
        .zIndex(dragID == t.id ? 1 : 0)
        .opacity(appeared ? 1 : 0)                          // le tessere entrano una dopo l'altra
        .offset(y: appeared ? 0 : -8)
        .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(Double(index) * 0.045), value: appeared)
        .gesture(reorder(t), including: tiles.editing ? .all : .none)
    }

    /// La maniglia sul bordo destro: trascinandola la tessera si allarga o si stringe di una cella alla volta.
    /// Misura col mouse sullo schermo, non con la vista: la finestra si ricentra mentre cambia larghezza.
    private func handle(_ t: Tile) -> some View {
        Capsule().fill(Color.primary.opacity(0.55)).frame(width: 4, height: 30)
            .frame(width: 18, height: TileMetrics.rowH)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if resizeBase == nil { resizeBase = t.cells; startMouse = NSEvent.mouseLocation.x }
                let dx = NSEvent.mouseLocation.x - startMouse
                tiles.layout.resize(t.id, to: (resizeBase ?? t.cells) + Int((dx / (TileMetrics.cell + TileMetrics.gap)).rounded()))
            }.onEnded { _ in resizeBase = nil })
    }

    /// Trascinando una tessera si sposta: al rilascio va dove cade il suo centro.
    private func reorder(_ t: Tile) -> some Gesture {
        DragGesture(minimumDistance: 6).onChanged { _ in
            if dragID != t.id { dragID = t.id; startMouse = NSEvent.mouseLocation.x }
            dragDX = NSEvent.mouseLocation.x - startMouse
        }.onEnded { _ in
            var x: CGFloat = 0, center: CGFloat = 0
            var centers: [(String, CGFloat)] = []
            for (tt, _) in shown {
                let w = width(tt.cells)
                centers.append((tt.id, x + w / 2))
                if tt.id == t.id { center = x + w / 2 }
                x += w + TileMetrics.gap
            }
            let target = centers.filter { $0.0 != t.id && $0.1 < center + dragDX }.count
            tiles.layout.move(t.id, to: target)
            dragID = nil; dragDX = 0
        }
    }

    /// In modifica: i widget tolti si rimettono con un tocco.
    /// Le tessere da aggiungere: una riga che scorre (17/10: tutte in fila allargavano il pannello oltre lo schermo,
    /// spingevano fuori le icone in alto e schiacciavano i nomi). Larga quanto la riga delle tessere.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(widgets.filter { w in !tiles.layout.tiles.contains { $0.id == w.id } }, id: \.id) { w in
                    Button { tiles.layout.add(w.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Volta.a2)
                            Image(systemName: w.symbol).font(.system(size: 11))
                            Text(w.title).font(.system(size: 11.5)).fixedSize()
                        }
                        .foregroundStyle(Volta.pillT)
                        .padding(.horizontal, 11).frame(height: 26)
                        .background(Capsule().fill(Volta.pill))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: max(200, shown.reduce(CGFloat(0)) { $0 + width($1.0.cells) } + CGFloat(max(0, shown.count - 1)) * TileMetrics.gap), height: 26)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}

// MARK: - Musica

struct MusicWidget: IslandWidget {
    let media: MediaSource
    let id = "music"
    var title: String { T("Musica", "Music") }
    let symbol = "music.note"
    func body(cells: Int) -> AnyView { AnyView(MusicTile(media: media, cells: cells)) }
}

private struct MusicTile: View {
    @ObservedObject var media: MediaSource
    let cells: Int

    var body: some View {
        if media.needsPermission {
            VStack(alignment: .leading, spacing: 4) {
                Text(T("Spotify non risponde", "Spotify not responding")).font(.system(size: 11, weight: .medium)).foregroundStyle(Night.amber)
                Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) } label: {
                    Text(T("Consenti Automazione", "Allow Automation")).font(.system(size: 11)).underline()
                }
                .buttonStyle(.plain)
            }
        } else if let t = media.track ?? media.last, cells >= 2 {
            content(t)
                // 13/10: il contenuto occupa tutta la tessera, così lo sfocato (dietro, +10 di margine) arriva ai bordi veri
                // e non lascia una fascia a destra quando i testi sono corti
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // 12/10 tarda sera, l'autore: "riempire la sezione appieno": la copertina sfocata riempie tutta la tessera
                .background(alignment: .center) {
                    // 14/10, l'autore: "in pausa lo sfondo come le altre finestre; colori e animazioni solo quando è in ascolto"
                    if media.track?.playing == true, let a = media.artwork, !Theme.light {      // 13/10: in White Matte resta chiara come le altre
                        // 13/10, l'autore: "sistema quell'alone": lo sfocato restava fuori dalla tessera. Ora è ritagliato sulla sua forma
                        // 13/10 mattina, di nuovo fuori nella griglia ⌘4: scaledToFill ingrandiva il riquadro stesso (copertina quadrata
                        // su tessera larga), così il ritaglio non serviva. Ora il riquadro è un Color.clear grande quanto la tessera
                        // e la copertina ci sta dentro, ritagliata.
                        Color.clear
                            .overlay {
                                Image(nsImage: a).resizable().scaledToFill().blur(radius: 22).opacity(Theme.light ? 0.35 : 0.45)
                                    .overlay(Theme.light ? Color.white.opacity(0.42) : Color.black.opacity(0.25))   // 13/10: in White Matte più chiara
                            }
                            // prima il ritaglio, poi l'allargamento: con l'ordine opposto il ritaglio usava la misura
                            // del contenuto (10 punti dentro) e lasciava la cornice chiara attorno
                            .clipShape(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous))
                            .padding(-10)
                            .allowsHitTesting(false)
                    }
                }
                // 13/10, l'autore: "togli il contorno da Spotify, non mi piace, troveremo un'altra soluzione più avanti": niente luce sul bordo della tessera.
        } else if let t = media.track ?? media.last {
            content(t)
        } else {
            empty
        }
    }

    @ViewBuilder private func content(_ t: Track) -> some View {
        do {
            // 12/10 sera, l'autore: "l'album, il disco, una copertina e i tasti classici", anche da fermo (l'ultimo brano)
            let live = media.track != nil
            let playing = live && t.playing
            if cells == 1 {
                VStack(spacing: 6) {
                    record(t, side: 40, playing: playing)
                    button(playing ? "pause.fill" : "play.fill", 13) { live ? media.command(.playPause) : media.resumeLast() }
                }
                .frame(maxWidth: .infinity)
            } else if cells == 2 {
                // 25/10, l'autore: "la sezione musica è tagliata". Su 2 caselle (la disposizione di serie) copertina, disco,
                // testo e tre tasti non ci stavano: qui copertina più piccola senza disco, titolo, artista, play e avanti.
                HStack(spacing: 10) {
                    art(56).shadow(color: .black.opacity(0.3), radius: 3, x: 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(t.artist).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1)
                        Spacer(minLength: 2)
                        HStack(spacing: 10) {
                            button(playing ? "pause.fill" : "play.fill", 13) { live ? media.command(.playPause) : media.resumeLast() }
                            button("forward.fill", 11) { media.command(.next) }.opacity(live ? 1 : 0.35).disabled(!live)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 56, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                let side: CGFloat = 76                                  // tutta l'altezza utile della tessera (96 - 2 x 10)
                HStack(spacing: 10) {
                    record(t, side: side, playing: playing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(t.artist).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1)
                        if cells >= 3, !live, !t.album.isEmpty {        // mentre suona l'album lascia posto a barra e tasti
                            Text(t.album).font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.42)).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        if cells >= 3, live { ProgressBar(src: media) }
                        if !live { Text(T("Ultimo ascoltato", "Last played")).font(.system(size: 9.5)).foregroundStyle(Color.primary.opacity(0.4)) }
                        HStack(spacing: cells >= 3 ? 14 : 8) {
                            button("backward.fill", 11) { media.command(.previous) }.opacity(live ? 1 : 0.35).disabled(!live)
                            button(playing ? "pause.fill" : "play.fill", 13) { live ? media.command(.playPause) : media.resumeLast() }
                            button("forward.fill", 11) { media.command(.next) }.opacity(live ? 1 : 0.35).disabled(!live)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: side, alignment: .top)        // il contenuto resta alto 76: sotto la fascia è delle onde
                // 14/10: il lettore a tutto schermo con copertina e giradischi (widget-braun.swift)
                .overlay(alignment: .topTrailing) {
                    Button { FullPlayer.shared.toggle(media: media) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.55)).frame(width: 20, height: 20).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(T("Lettore a tutto schermo", "Full screen player"))
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var empty: some View {
            VStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                if cells > 1 { Text(T("Niente in riproduzione", "Nothing playing")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)) }
                Button {
                    if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
                    }
                } label: {
                    Text("Spotify").font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
    }

    /// Copertina con il disco che esce da dietro, a destra: gira mentre suona, da fermo resta più dentro.
    private func record(_ t: Track, side: CGFloat, playing: Bool) -> some View {
        let wide = cells >= 3
        return ZStack(alignment: .leading) {
            Vinyl(art: media.artwork, playing: playing)
                .frame(width: side * 0.92, height: side * 0.92)
                .offset(x: side * (playing ? (wide ? 0.42 : 0.3) : (wide ? 0.26 : 0.18)))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: playing)
            art(side).shadow(color: .black.opacity(0.35), radius: 4, x: 2)
        }
        .frame(width: side * (wide ? 1.38 : 1.26), height: side, alignment: .leading)
    }

    private func art(_ side: CGFloat) -> some View {
        Group {
            if let a = media.artwork { Image(nsImage: a).resizable().scaledToFill() }
            else { (Theme.light ? Color(white: 0.86) : Color(white: 0.2)).overlay(Image(systemName: "music.note").foregroundStyle(Color.primary.opacity(0.4))) }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func button(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: size, weight: .medium)).frame(width: 20, height: 18).contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

/// Il disco: nero con i solchi, l'etichetta è la copertina in tondo. Gira a 33 giri scarsi, solo mentre suona.
private struct Vinyl: View {
    let art: NSImage?
    let playing: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Leggera.on || (!playing))) { ctx in
            let a = playing ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6 * 360 : 0
            GeometryReader { g in
                let d = min(g.size.width, g.size.height)
                ZStack {
                    Circle().fill(Color(white: 0.07))
                    ForEach(0..<6, id: \.self) { i in
                        Circle().stroke(Color.white.opacity(0.05 + 0.02 * Double(i % 2)), lineWidth: 0.6)
                            .padding(d * (0.08 + 0.05 * Double(i)))
                    }
                    // un riflesso fermo, così si vede che il disco gira sotto la luce
                    Circle().trim(from: 0.05, to: 0.18).stroke(Color.white.opacity(0.12), lineWidth: d * 0.25).padding(d * 0.2)
                        .rotationEffect(.degrees(-a))
                    Group {
                        if let art { Image(nsImage: art).resizable().scaledToFill() } else { Color(white: 0.3) }
                    }
                    .frame(width: d * 0.36, height: d * 0.36).clipShape(Circle())
                    Circle().fill(Color(white: 0.05)).frame(width: d * 0.05, height: d * 0.05)
                }
                .rotationEffect(.degrees(a))
            }
        }
    }
}

// MARK: - Meteo (Open-Meteo)

final class WeatherModel: ObservableObject {
    static let shared = WeatherModel()
    @Published private(set) var now: WeatherNow?
    @Published private(set) var place = ""
    @Published private(set) var failed = false
    private var fetchedAt = Date.distantPast

    /// La città si imposta dal menu o toccando la tessera; solo questo nome parte verso Open-Meteo.
    var city: String {
        get { Impostazioni.string(.isolaCity) ?? "" }
        set { Impostazioni.set(newValue, .isolaCity) }
    }

    /// Reel: Lisbona, poco nuvoloso, niente rete.
    func setDemo(_ on: Bool) {
        if on { now = WeatherNow(temp: 18, code: 2, isDay: true, hi: 20, lo: 14); place = "Lisbon"; failed = false; fetchedAt = .distantFuture }
        else { now = nil; place = ""; fetchedAt = .distantPast; refreshIfNeeded() }
    }

    func refreshIfNeeded(force: Bool = false) {
        guard !city.isEmpty else { return }
        guard force || Date().timeIntervalSince(fetchedAt) > 1800 else { return }
        fetchedAt = Date()
        let c = city
        locate(c) { [weak self] p in
            guard let self, let p else { DispatchQueue.main.async { self?.failed = true }; return }
            var comp = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comp.queryItems = [URLQueryItem(name: "latitude", value: String(p.lat)), URLQueryItem(name: "longitude", value: String(p.lon)),
                               URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
                               URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                               URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "1")]
            URLSession.shared.dataTask(with: URLRequest(url: comp.url!, timeoutInterval: 8)) { data, _, _ in
                let w = data.flatMap(WeatherParse.forecast)
                DispatchQueue.main.async { self.now = w; self.place = p.name; self.failed = w == nil }
            }.resume()
        }
    }

    private func locate(_ city: String, _ done: @escaping ((name: String, lat: Double, lon: Double)?) -> Void) {
        if Impostazioni.string(.isolaCityKey) == city, let lat = Impostazioni.object(.isolaLat) as? Double, let lon = Impostazioni.object(.isolaLon) as? Double {
            done((Impostazioni.string(.isolaCityName) ?? city, lat, lon)); return
        }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "it")]
        URLSession.shared.dataTask(with: URLRequest(url: c.url!, timeoutInterval: 8)) { data, _, _ in
            guard let p = data.flatMap(WeatherParse.place) else { done(nil); return }
            Impostazioni.set(city, .isolaCityKey); Impostazioni.set(p.lat, .isolaLat); Impostazioni.set(p.lon, .isolaLon); Impostazioni.set(p.name, .isolaCityName)
            done(p)
        }.resume()
    }

    func askCity() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T("Città del meteo", "Weather city")
        a.informativeText = T("Solo il nome della città va a Open-Meteo, niente posizione.", "Only the city name goes to Open-Meteo, never your location.")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); f.stringValue = city
        a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: T("Annulla", "Cancel"))
        if a.runModal() == .alertFirstButtonReturn {
            city = f.stringValue.trimmingCharacters(in: .whitespaces)
            now = nil; failed = false; fetchedAt = .distantPast
            refreshIfNeeded(force: true)
        }
    }
}

struct WeatherWidget: IslandWidget {
    let id = "weather"
    var title: String { T("Meteo", "Weather") }
    let symbol = "cloud.sun"
    func body(cells: Int) -> AnyView { AnyView(WeatherTile(model: .shared, cells: cells)) }
}

private struct WeatherTile: View {
    @ObservedObject var model: WeatherModel
    let cells: Int

    var body: some View {
        Group {
            if model.city.isEmpty {
                Button { model.askCity() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 16))
                        if cells > 1 { Text(T("Imposta la città", "Set your city")).font(.system(size: 11)) }
                    }
                    .foregroundStyle(Color.primary.opacity(0.6)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else if let w = model.now {
                let temp = "\(Int(w.temp.rounded()))°"
                if cells == 1 {
                    VStack(spacing: 4) {
                        Image(systemName: WeatherParse.symbol(code: w.code, isDay: w.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 22))
                        Text(temp).font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(temp).font(.system(size: 30, weight: .light))
                            Text(model.place).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(T("Max", "H")) \(Int(w.hi.rounded()))°  \(T("Min", "L")) \(Int(w.lo.rounded()))°")
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: WeatherParse.symbol(code: w.code, isDay: w.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 26))
                    }
                }
            } else {
                Text(model.failed ? T("Meteo non disponibile", "Weather unavailable") : "…")
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // 13/10: tutta la tessera, così la luce del meteo arriva ai bordi veri (prima si fermava prima, con angoli suoi)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 12/10 tarda sera: gli effetti del meteo a tutta tessera, dietro al testo (WeatherFX in widget-hitodama.swift)
        .background {
            if let w = model.now { TileWeatherFX(code: w.code, isDay: w.isDay).padding(-10) }
        }
        .onAppear { model.refreshIfNeeded() }
    }
}

// MARK: - Prossimo evento (EventKit)

final class CalendarModel: ObservableObject {
    static let shared = CalendarModel()
    /// `id` e `link` (fase 4): l'identificativo dell'evento e il link della riunione (Zoom, Meet, Teams), se c'è.
    struct Next: Equatable {
        var title: String; var start: Date; var end: Date; var allDay: Bool
        var id: String = ""; var link: URL? = nil
    }
    @Published private(set) var next: Next?
    /// Fase 4: la riunione che la fonte "riunione" dell'isola guarda. Separata da `next`, così il widget resta com'è:
    /// il primo evento con orario la cui finestra non è ancora chiusa (Riunione.scegli), cercato da un'ora fa a 24 ore da ora.
    @Published private(set) var prossimaRiunione: Next?
    @Published private(set) var denied = false
    @Published private(set) var demoDate: Date?       // reel: lo stesso giorno della barra finta
    private let store = EKEventStore()
    private var observing = false
    private var demo = false

    /// Reel: un evento inventato, il calendario vero non viene letto.
    func setDemo(_ on: Bool) {
        demo = on
        demoDate = on ? Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9, minute: 41)) : nil
        if on {
            let cal = Calendar.current
            let s = cal.date(bySettingHour: 15, minute: 0, second: 0, of: demoDate ?? Date()) ?? Date()
            next = Next(title: "Design review", start: s, end: s.addingTimeInterval(1800), allDay: false); denied = false
            prossimaRiunione = nil          // nel reel nessuna riunione vera nel notch
        } else { next = nil; refresh() }
    }

    /// Per la fonte della riunione: rilegge solo se il permesso c'è già. Non chiede mai il permesso
    /// (lo chiede la tessera Calendario, come prima) e con il permesso negato non cambia niente.
    func aggiornaSeConsentito() {
        guard !demo, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        refresh()
    }

    func refresh() {
        guard !demo else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            if denied { denied = false }        // fase 4: il timer della riunione rilegge ogni 20 s, niente ripubblicazioni inutili
            load()
            if !observing {
                observing = true
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.load() }
            }
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] ok, _ in
                DispatchQueue.main.async { if ok { self?.refresh() } else { self?.denied = true } }
            }
        default:
            denied = true
        }
    }

    private func load() {
        let cal = Calendar.current, now = Date()
        guard let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil))
        let timed = events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
        let pick = timed.first ?? events.first
        let nuovo = pick.map(Self.voce)
        if nuovo != next { next = nuovo }

        // fase 4: la prossima riunione, nelle prossime 24 ore (una iniziata da poco c'è ancora)
        let ampie = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(24 * 3600), calendars: nil))
            .filter { Self.contaComeRiunione($0) }
            .sorted { $0.startDate < $1.startDate }
        let riunione = Riunione.scegli(ampie.map { (inizio: $0.startDate, fine: $0.endDate) }, ora: now).map { Self.voce(ampie[$0]) }
        if riunione != prossimaRiunione { prossimaRiunione = riunione }
    }

    /// Fase 4: niente giorno intero, niente annullati, niente rifiutati dall'utente.
    private static func contaComeRiunione(_ ev: EKEvent) -> Bool {
        guard !ev.isAllDay, ev.startDate != nil, ev.endDate != nil, ev.status != .canceled else { return false }
        if let io = ev.attendees?.first(where: { $0.isCurrentUser }), io.participantStatus == .declined { return false }
        return true
    }

    private static func voce(_ ev: EKEvent) -> Next {
        Next(title: ev.title ?? "", start: ev.startDate, end: ev.endDate, allDay: ev.isAllDay,
             id: ev.calendarItemIdentifier,
             link: Riunione.link(in: [ev.url?.absoluteString, ev.location, ev.notes]))
    }
}

struct CalendarWidget: IslandWidget {
    let id = "calendar"
    var title: String { T("Evento", "Event") }
    let symbol = "calendar"
    func body(cells: Int) -> AnyView { AnyView(CalendarTile(model: .shared, cells: cells)) }
}

private struct CalendarTile: View {
    @ObservedObject var model: CalendarModel
    let cells: Int
    /// Il giorno nella lingua di Pulsar (in inglese nel reel), non in quella del Mac.
    private var weekday: DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: pulsarItalian ? "it_IT" : "en_US"); f.dateFormat = "EEE"; return f }
    private static let hour: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let date = model.demoDate ?? ctx.date
            let day = Calendar.current.component(.day, from: date)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(weekday.string(from: date).uppercased()).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent)
                    Text("\(day)").font(.system(size: 30, weight: .light))
                }
                if cells > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        if model.denied {
                            Text(T("Consenti il Calendario", "Allow Calendar")).font(.system(size: 11)).foregroundStyle(Night.amber)
                        } else if let n = model.next {
                            Text(n.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(n.allDay ? T("Tutto il giorno", "All day") : "\(Self.hour.string(from: n.start)) - \(Self.hour.string(from: n.end))")
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.55))
                        } else {
                            Text(T("Niente per oggi", "Nothing for today")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { model.refresh() }
    }
}

// MARK: - Timer (quello della Ghiera)

struct TimerWidget: IslandWidget {
    let dial: DialStore?
    let id = "timer"
    var title: String { "Timer" }
    let symbol = "timer"
    func body(cells: Int) -> AnyView {
        guard let dial else {
            return AnyView(Text(T("Attiva la ghiera", "Turn on the dial")).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.5)))
        }
        return AnyView(TimerTile(store: dial, cells: cells))
    }
}

private struct TimerTile: View {
    @ObservedObject var store: DialStore
    let cells: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left: Double? = store.timerEnd.map { max(0, $0.timeIntervalSince(ctx.date)) }
            VStack(spacing: 6) {
                Text(left.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "\(store.timerMinutes):00")
                    .font(.system(size: cells == 1 ? 16 : 24, weight: .light).monospacedDigit())
                HStack(spacing: 8) {
                    if cells > 1 && left == nil { step("minus", -5); step("plus", 5) }
                    Button {
                        if store.timerEnd == nil { store.timerEnd = Date().addingTimeInterval(Double(store.timerMinutes * 60)); store.now = Date() }
                        else { store.timerEnd = nil }
                    } label: {
                        Image(systemName: left == nil ? "play.fill" : "stop.fill").font(.system(size: 12, weight: .medium))
                            .frame(width: 30, height: 24).background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func step(_ symbol: String, _ d: Int) -> some View {
        Button {
            store.timerMinutes = max(1, min(60, store.timerMinutes + d))
            Impostazioni.set(store.timerMinutes, .dialTimer)
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
