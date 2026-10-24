// Griglia ⌘4: le app a schermo intero, come quella di LaunchMe, nello stile di Pulsar (12/10/2026).
// In alto Cerca, sotto i widget dell'isola in grande, poi le app a pagine (8 x 4) con i puntini.
// Si apre con ⌘4 (o ⌃⌥Spazio, scelta nel menu ISOLA) da qualunque app, o dal pulsante a griglia nell'isola.
// Esc, un clic fuori o di nuovo la scorciatoia la chiudono. Pagine e ricerca (logica pura) in isola-logica.swift.
import SwiftUI
import Combine
import AppKit
import Carbon

struct GridApp: Identifiable, Equatable {
    let id: String          // percorso
    let name: String
    let url: URL
    let category: String    // gruppo automatico (AppCategory), da LSApplicationCategoryType
}

enum AppCatalog {
    private static let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]

    /// Le lingue del Mac, in ordine ("it-IT" e poi "it").
    private static let langs: [String] = Locale.preferredLanguages.flatMap { l -> [String] in
        let base = String(l.split(separator: "-").first ?? Substring(l))
        return [l, l.replacingOccurrences(of: "-", with: "_"), base]
    }

    /// Il nome dell'app nella lingua del Mac: Pulsar è in inglese, quindi `displayName` darebbe "Calendar" invece di
    /// "Calendario". Si legge la traduzione dentro l'app: `InfoPlist.loctable` (app di sistema) o `<lingua>.lproj/InfoPlist.strings`.
    static func localizedName(_ app: URL) -> String? {
        guard pulsarItalian else { return nil }          // Pulsar in inglese (Mac inglese, o il reel): i nomi inglesi vanno già bene
        let res = app.appendingPathComponent("Contents/Resources")
        func pick(_ d: [String: Any]?) -> String? { (d?["CFBundleDisplayName"] as? String) ?? (d?["CFBundleName"] as? String) }
        if let data = try? Data(contentsOf: res.appendingPathComponent("InfoPlist.loctable")),
           let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for l in langs { if let n = pick(table[l] as? [String: Any]) { return n } }
        }
        for l in langs {
            if let d = NSDictionary(contentsOf: res.appendingPathComponent("\(l).lproj/InfoPlist.strings")) as? [String: Any], let n = pick(d) { return n }
        }
        return nil
    }

    /// Tutte le app delle cartelle Applicazioni (anche un livello dentro le sottocartelle), una per bundle, in ordine di nome.
    static func load() -> [GridApp] {
        let fm = FileManager.default
        var seen = Set<String>(), out: [GridApp] = []
        func add(_ url: URL) {
            let key = Bundle(url: url)?.bundleIdentifier ?? url.path
            guard url.pathExtension == "app", seen.insert(key).inserted, key != Bundle.main.bundleIdentifier else { return }
            let type = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String
            out.append(GridApp(id: url.path, name: localizedName(url) ?? fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url: url,
                               category: AppCategory.group(type)))
        }
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: d), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for u in items {
                if u.pathExtension == "app" { add(u) }
                else if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, u.lastPathComponent != "Utilities" {
                    for v in (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] where v.pathExtension == "app" { add(v) }
                }
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

final class GridModel: ObservableObject {
    static let cols = 8, rows = 4
    static var perPage: Int { cols * rows }
    @Published var apps: [GridApp] = []
    @Published var query = "" { didSet { if query != oldValue { page = 0 } } }
    @Published var page = 0
    @Published var shown = false
    @Published var byCategory = Impostazioni.bool(.grigliaCategorie) {
        didSet { Impostazioni.set(byCategory, .grigliaCategorie); openCategory = nil; page = 0 }
    }
    @Published var openCategory: String? { didSet { page = 0 } }
    /// Immagini aggiunte come widget (percorsi).
    @Published var images: [String] = (Impostazioni.stringArray(.grigliaImmagini) ?? []).filter { FileManager.default.fileExists(atPath: $0) } {
        didSet { Impostazioni.set(images, .grigliaImmagini) }
    }
    /// Sfondo scelto; nil = quello del tema (lo sfondo della scrivania, sfocato e velato).
    @Published var background: String? = Impostazioni.string(.grigliaSfondo) {
        didSet { Impostazioni.set(background, .grigliaSfondo) }
    }
    @Published var weatherFX = Impostazioni.object(.grigliaMeteo) as? Bool ?? false {   // 14/10: spento di serie, lo sfondo resta com'è
        didSet { Impostazioni.set(weatherFX, .grigliaMeteo) }
    }
    var screen: NSScreen?
    private var icons: [String: NSImage] = [:]
    /// 17/10: la pagina "In riproduzione" a schermo intero, e le note come tessere della fila in alto.
    @Published var nowPlaying = false
    /// 17/10 (l'autore): il cielo della hero di Spazio e un razzo anche nella griglia. Acceso di serie, si spegne dalla barra.
    @Published var spaceSky = Impostazioni.object(.grigliaCielo) as? Bool ?? true {
        didSet { Impostazioni.set(spaceSky, .grigliaCielo) }
    }
    weak var media: MediaSource?
    @Published var notes: [GridNote] = {
        guard let d = Impostazioni.data(.grigliaNote), let n = try? JSONDecoder().decode([GridNote].self, from: d) else { return [] }
        return n
    }() { didSet { if let d = try? JSONEncoder().encode(notes) { Impostazioni.set(d, .grigliaNote) } } }
    /// Si sta scrivendo in una nota (non nella ricerca): Invio e frecce restano alla nota.
    static var typingInNote: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return !tv.isFieldEditor
    }

    /// Le app da mostrare: con la ricerca tutte quelle trovate; per categoria quelle della cartella aperta.
    var results: [GridApp] {
        if !query.isEmpty { return AppSearch.filter(apps.map(\.name), query).map { apps[$0] } }
        if byCategory, let c = openCategory { return apps.filter { $0.category == c } }
        return apps
    }
    var showsFolders: Bool { byCategory && query.isEmpty && openCategory == nil }
    var folders: [(String, [GridApp])] {
        AppCategory.order.compactMap { c in let list = apps.filter { $0.category == c }; return list.isEmpty ? nil : (c, list) }
    }
    static func title(_ c: String) -> String {
        switch c {
        case "productivity": return T("Produttività", "Productivity")
        case "creative": return T("Creatività", "Creative")
        case "developer": return T("Sviluppo", "Developer")
        case "media": return T("Musica e video", "Music and video")
        case "social": return "Social"
        case "utilities": return T("Utility", "Utilities")
        case "games": return T("Giochi", "Games")
        default: return T("Altre", "Other")
        }
    }
    var pages: Int { GridPaging.pages(count: results.count, perPage: Self.perPage) }

    func go(_ delta: Int) {
        let p = GridPaging.clamp(page: page + delta, count: results.count, perPage: Self.perPage)
        if p != page { page = p }
    }

    /// Dopo un cambio dello stile delle icone di macOS (tema): le icone si rileggono.
    func resetIcons() { icons = [:]; objectWillChange.send() }

    func icon(_ a: GridApp) -> NSImage {
        if giroIcone == nil {
            // 13/10: a ogni giro di IconeApp (stile cambiato, icone fresche arrivate) la griglia le rilegge
            giroIcone = IconeApp.shared.$versione.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resetIcons() }
        }
        if let i = icons[a.id] { return i }
        let i = IconeApp.shared.icona(a.id); icons[a.id] = i; return i
    }
    private var giroIcone: AnyCancellable?
}

/// La finestra della griglia: può prendere la tastiera (per Cerca) senza far diventare Pulsar l'app attiva.
final class GridPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class GridModule {
    enum HotKey: String, CaseIterable {
        case cmd4, ctrlOptSpace, off
        var title: String { ["cmd4": "⌘4", "ctrlOptSpace": "⌃⌥Spazio", "off": T("Spenta", "Off")][rawValue]! }
    }
    static var hotKey: HotKey {
        get { HotKey(rawValue: Impostazioni.string(.grigliaTasto) ?? "") ?? .cmd4 }
        set { Impostazioni.set(newValue.rawValue, .grigliaTasto) }
    }

    let model = GridModel()
    private let island: IslandModel
    private var win: GridPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitors: [Any] = []
    private var previous: NSRunningApplication?
    private var scrollAcc: CGFloat = 0
    private var scrollLocked = false
    private var avviato = false
    private(set) var isOpen = false
    /// Reel: l'elenco finto non si ricarica all'apertura.
    var demoLock = false

    init(island: IslandModel) { self.island = island }

    /// Angolo in alto a sinistra: il mouse fermo proprio nell'angolo per un terzo di secondo apre la griglia
    /// (l'autore, 12/10). Lì c'è anche il menu Apple: passarci sopra non basta, bisogna restare nell'angolo.
    static var corner: Bool {
        get { Impostazioni.object(.grigliaAngolo) as? Bool ?? true }
        set { Impostazioni.set(newValue, .grigliaAngolo) }
    }
    private var cornerWork: DispatchWorkItem?
    private var cornerMonitors: [Any] = []

    private func cornerMoved() {
        guard Self.corner, !isOpen else { cornerWork?.cancel(); cornerWork = nil; return }
        let p = NSEvent.mouseLocation
        let inCorner = NSScreen.screens.contains { p.x <= $0.frame.minX + 1 && p.y >= $0.frame.maxY - 1 && $0.frame.insetBy(dx: -1, dy: -1).contains(p) }
        if inCorner {
            guard cornerWork == nil else { return }
            let w = DispatchWorkItem { [weak self] in
                self?.cornerWork = nil
                let q = NSEvent.mouseLocation
                if NSScreen.screens.contains(where: { q.x <= $0.frame.minX + 1 && q.y >= $0.frame.maxY - 1 }) { self?.open() }
            }
            cornerWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33, execute: w)
        } else { cornerWork?.cancel(); cornerWork = nil }
    }

    fileprivate func boot() {
        guard !avviato else { return }
        avviato = true
        registerHotKey()
        let move: (NSEvent) -> Void = { [weak self] _ in self?.cornerMoved() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: move) { cornerMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { move($0); return $0 }) { cornerMonitors.append(l) }
        DispatchQueue.global(qos: .utility).async { let a = AppCatalog.load(); DispatchQueue.main.async { self.model.apps = a } }
    }

    /// Ferma la griglia: niente scorciatoia, niente angolo, finestra chiusa. L'angolo e il tasto scelti restano salvati.
    fileprivate func fermati() {
        guard avviato else { return }
        close(reactivate: false)
        avviato = false
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        cornerMonitors.forEach { NSEvent.removeMonitor($0) }
        cornerMonitors = []
        cornerWork?.cancel(); cornerWork = nil
    }

    func setHotKey(_ k: HotKey) { Self.hotKey = k; registerHotKey() }

    // MARK: scorciatoia globale (Carbon: non chiede permessi)

    private func registerHotKey() {
        guard avviato else { return }
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        guard Self.hotKey != .off else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, ud in
                // 19/10: con Rowline dentro Pulsar le scorciatoie sono di più: si risponde solo alla propria ("PULG")
                var hk = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                guard hk.signature == OSType(0x50554C47) else { return OSStatus(eventNotHandledErr) }
                guard let ud else { return noErr }
                let me = Unmanaged<GridModule>.fromOpaque(ud).takeUnretainedValue()
                DispatchQueue.main.async { me.toggle() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x50554C47), id: 4)      // "PULG"
        let (code, mods): (Int, Int) = Self.hotKey == .cmd4 ? (kVK_ANSI_4, cmdKey) : (kVK_Space, controlKey | optionKey)
        RegisterEventHotKey(UInt32(code), UInt32(mods), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: aprire e chiudere

    func toggle() { isOpen ? close(reactivate: true) : open() }

    func open() {
        guard avviato, !isOpen else { return }
        isOpen = true
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        if win == nil {
            let w = GridPanel()
            w.contentView = NSHostingView(rootView: GridView(model: model, tiles: island.tiles, widgets: island.widgets,
                                                             close: { [weak self] in self?.close(reactivate: true) },
                                                             launch: { [weak self] in self?.launch($0) },
                                                             pick: { [weak self] in self?.pick($0) }))
            win = w
        }
        guard let win else { return }
        previous = NSWorkspace.shared.frontmostApplication
        model.query = ""; model.page = 0; model.shown = false; model.openCategory = nil; model.screen = screen
        model.media = island.home as? MediaSource; model.nowPlaying = false
        win.setFrame(screen.frame, display: false)
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; win.animator().alphaValue = 1 }
        DispatchQueue.main.async { self.model.shown = true }
        addMonitors()
        // l'elenco si rinfresca a ogni apertura (app installate o tolte), senza far aspettare
        if !demoLock {
            DispatchQueue.global(qos: .utility).async { let a = AppCatalog.load(); DispatchQueue.main.async { if a != self.model.apps { self.model.apps = a } } }
        }
    }

    func close(reactivate: Bool) {
        guard isOpen, let win else { return }
        isOpen = false
        NotificationLog.shared.markSeen()           // 13/10: quelle che c'erano mentre era aperta ora sono "viste"
        removeMonitors()
        model.shown = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; win.animator().alphaValue = 0 }) { win.orderOut(nil) }
        if reactivate { previous?.activate() }
    }

    /// Sceglie immagini (widget) o lo sfondo. La finestra di scelta starebbe sotto la griglia: si chiude, si sceglie, si riapre.
    private func pick(_ what: GridPick) {
        close(reactivate: false)
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = what == .images
        p.message = what == .images ? T("Scegli le immagini da mettere fra i widget", "Choose images for the widgets") : T("Scegli lo sfondo della griglia", "Choose the grid background")
        if p.runModal() == .OK {
            switch what {
            case .images: model.images.append(contentsOf: p.urls.map(\.path).filter { !model.images.contains($0) })
            case .background: model.background = p.url?.path
            }
        }
        open()
    }

    private func launch(_ a: GridApp) {
        close(reactivate: false)
        NSWorkspace.shared.openApplication(at: a.url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: tastiera e rotella mentre è aperta

    private func addMonitors() {
        if let k = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self else { return e }
            switch Int(e.keyCode) {
            case kVK_Escape:
                if GridModel.typingInNote { self.win?.makeFirstResponder(nil); return nil }
                if self.model.nowPlaying { self.model.nowPlaying = false }
                else if self.model.openCategory != nil { self.model.openCategory = nil } else { self.close(reactivate: true) }
                return nil
            case kVK_Return where !GridModel.typingInNote: if let a = self.model.results.first { self.launch(a) }; return nil
            case kVK_LeftArrow where self.model.query.isEmpty && !GridModel.typingInNote: self.model.go(-1); return nil
            case kVK_RightArrow where self.model.query.isEmpty && !GridModel.typingInNote: self.model.go(1); return nil
            default: return e
            }
        }) { monitors.append(k) }
        if let s = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in self?.scroll(e); return e }) { monitors.append(s) }
        // un clic in un'altra app (o su un'altra finestra) chiude
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.async { self?.close(reactivate: false) }
        }) { monitors.append(g) }
    }

    private func removeMonitors() { monitors.forEach { NSEvent.removeMonitor($0) }; monitors = [] }

    /// Due dita o rotella: una pagina per gesto. Il trackpad ha le fasi; la rotella del mouse no.
    private func scroll(_ e: NSEvent) {
        if e.phase == .began || e.phase == .mayBegin { scrollAcc = 0; scrollLocked = false }
        let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? -e.scrollingDeltaX : -e.scrollingDeltaY
        guard !scrollLocked else {
            if e.phase == .ended || e.momentumPhase == .ended { scrollLocked = false; scrollAcc = 0 }
            return
        }
        scrollAcc += d * (e.hasPreciseScrollingDeltas ? 1 : 12)
        if abs(scrollAcc) > 60 {
            model.go(scrollAcc > 0 ? 1 : -1)
            scrollAcc = 0
            scrollLocked = true
            if e.phase == [] && e.momentumPhase == [] {           // rotella: si sblocca da sola
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.scrollLocked = false }
            }
        }
    }
}

// MARK: - La vista

enum GridPick { case images, background }

/// Lo sfondo: l'immagine scelta, o quello della scrivania sfocato; sopra il velo del tema.
private struct GridBackground: View {
    @ObservedObject var model: GridModel
    var body: some View {
        ZStack {
            // 14/10, l'autore: "si intravedono i nomi delle cartelle, non deve succedere": la sfocatura lasciava i bordi
            // trasparenti e sotto passava la scrivania. Base piena e sfocatura opaca.
            (Theme.light ? Color(white: 0.95) : Night.bottom)
            if let img = image {
                Image(nsImage: img).resizable().scaledToFill().blur(radius: model.background == nil ? 40 : 0, opaque: true)
                    .clipped()
            } else {
                GridBlur(dark: !Theme.light)
            }
            (Theme.light ? Color(white: 0.97) : Night.bottom).opacity(model.background == nil ? 0.72 : 0.35)
        }
    }
    private var image: NSImage? {
        if let p = model.background { return NSImage(contentsOfFile: p) }
        guard let s = model.screen, let u = NSWorkspace.shared.desktopImageURL(for: s) else { return nil }
        return NSImage(contentsOf: u)
    }
}

/// Il meteo sullo sfondo, leggero: pioggia, neve, nebbia o nuvole, o una luce calda col sereno.
private struct WeatherFX: View {
    let code: Int
    let isDay: Bool
    private func fract(_ x: Double) -> Double { x - floor(x) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Leggera.on)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let ink: Color = Theme.light ? Color(white: 0.25) : .white
                switch code {
                case 51...67, 80...82, 95...99:                       // pioggia: righe sottili inclinate
                    for i in 0..<140 {
                        let s1 = fract(sin(Double(i) * 12.9898) * 43758.5453), s2 = fract(sin(Double(i) * 78.233) * 12543.123)
                        let speed = 520 + 380 * s2
                        let x = s1 * (size.width + 200) - 100 + fract(t * 0.02) * 40
                        let y = fract(s2 + t * speed / size.height) * (size.height + 40) - 20
                        var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - 6, y: y + 18))
                        g.stroke(p, with: .color(ink.opacity(0.10 + 0.08 * s1)), lineWidth: 1)
                    }
                case 71...77, 85, 86:                                 // neve: fiocchi che ondeggiano
                    for i in 0..<110 {
                        let s1 = fract(sin(Double(i) * 12.9898) * 43758.5453), s2 = fract(sin(Double(i) * 78.233) * 12543.123)
                        let y = fract(s2 + t * (0.04 + 0.05 * s1)) * (size.height + 20) - 10
                        let x = s1 * size.width + sin(t * (0.6 + s2) + Double(i)) * 18
                        let r = 1.5 + 2.5 * s2
                        g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(ink.opacity(0.22)))
                    }
                case 0, 1, 2:                                         // sereno: una luce morbida che respira
                    let c = CGPoint(x: size.width * 0.82, y: size.height * 0.08)
                    let r = size.width * (0.35 + 0.02 * sin(t * 0.4))
                    let warm: Color = isDay ? Color(red: 1, green: 0.85, blue: 0.6) : Color(red: 0.6, green: 0.65, blue: 1)
                    g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [warm.opacity(0.16), .clear]), center: c, startRadius: 0, endRadius: r))
                default:                                              // nuvole e nebbia: grandi macchie che passano piano
                    break   // 14/10: le nuvole a ellisse tolte (l'autore: "togli ste ellissi e lascia lo sfondo com'è")
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GridBlur: NSViewRepresentable {
    let dark: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
}

struct GridView: View {
    @ObservedObject var model: GridModel
    @ObservedObject var tiles: TileModel
    let widgets: [IslandWidget]
    var close: () -> Void
    var launch: (GridApp) -> Void
    var pick: (GridPick) -> Void
    @ObservedObject private var look = GhieraLook.shared
    @ObservedObject private var weather = WeatherModel.shared
    @ObservedObject private var notes = NotificationLog.shared
    @FocusState private var searching: Bool

    init(model: GridModel, tiles: TileModel, widgets: [IslandWidget], close: @escaping () -> Void, launch: @escaping (GridApp) -> Void,
         pick: @escaping (GridPick) -> Void) {
        self.model = model; self.tiles = tiles; self.widgets = widgets; self.close = close; self.launch = launch; self.pick = pick
    }

    var body: some View {
        ZStack {
            GridBackground(model: model)
            if model.spaceSky && model.background == nil {
                CieloPixel(cell: 8, fps: 6, calm: 0.35).opacity(model.shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: model.shown)
                // 17/10 (l'autore): sfumatura del tema dall'alto, piena dove stanno ricerca, widget e icone, che sparisce
                // verso il basso: il cielo si vede come un orizzonte, come nella hero di Spazio
                LinearGradient(stops: [.init(color: Volta.body.opacity(0.94), location: 0), .init(color: Volta.body.opacity(0.82), location: 0.42),
                                       .init(color: Volta.body.opacity(0.35), location: 0.72), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                // il razzo di Spazio, sospeso in basso a destra
                Razzo(phase: .idle, pixel: 5)
                    .frame(width: 70, height: 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 70).padding(.bottom, 50)
                    .opacity(model.shown ? 1 : 0)
                    .allowsHitTesting(false)
            }
            if model.weatherFX, let w = weather.now { WeatherFX(code: w.code, isDay: w.isDay) }
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: close)      // clic fuori dalle cose: chiude
            VStack(spacing: 30) {
                search
                if model.query.isEmpty && model.openCategory == nil { widgetStrip }
                if let c = model.openCategory, model.query.isEmpty { folderHeader(c) }
                if model.showsFolders { foldersView } else { pagesView; dots }
                // 13/10, l'autore: le notifiche qui sotto, dove c'è spazio (solo nella vista iniziale)
                if !notes.items.isEmpty, model.query.isEmpty, model.openCategory == nil { notificationsColumn }
            }
            .padding(.top, 64).padding(.bottom, 40)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(model.shown ? 1 : 0)
            .scaleEffect(model.shown ? 1 : 0.97)
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: model.shown)
        }
        .overlay(alignment: .topTrailing) { toolbar.padding(.top, 64).padding(.trailing, 48).opacity(model.shown ? 1 : 0) }
        .overlay {
            if model.nowPlaying, let m = model.media {
                NowPlayingPage(media: m) { withAnimation(.easeOut(duration: 0.3)) { model.nowPlaying = false } }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.nowPlaying)
        .ignoresSafeArea()
        .environment(\.colorScheme, Theme.light ? .light : .dark)
        .onAppear { weather.refreshIfNeeded() }
        .onChange(of: model.shown) { s in if s { searching = true } }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.5))
            TextField(T("Cerca", "Search"), text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 14)).focused($searching)
        }
        .padding(.horizontal, 14).frame(width: 360, height: 36)
        .background(Capsule().fill(Volta.card))
    }

    /// Le notifiche arrivate (NotificationLog): una per riga con la X, e in alto "Togli le viste".
    private var notificationsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("Notifiche", "Notifications")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if notes.hasSeen {
                    Button(T("Togli le viste", "Clear seen")) { withAnimation { notes.clearSeen() } }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            .padding(.horizontal, 4)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 12), count: 3), spacing: 12) {
                    ForEach(notes.items) { n in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(n.seen ? Color.clear : Night.green).frame(width: 6, height: 6).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                if !n.body.isEmpty {
                                    Text(n.body).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(2)
                                }
                                Text(n.date, style: .relative).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.4))
                            }
                            Spacer(minLength: 0)
                            Button { withAnimation { notes.remove(n.id) } } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18)
                                    .background(Circle().fill(Volta.card2))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous).fill(Volta.card))
                        .opacity(n.seen ? 0.7 : 1)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 3 * 260 + 2 * 12)
        .animation(.easeOut(duration: 0.25), value: notes.items)
    }

    /// In alto a destra: categorie, immagini, sfondo, meteo.
    private var toolbar: some View {
        HStack(spacing: 6) {
            // 17/10: la canzone a schermo intero, una nota, un widget
            if let m = model.media, (m.track ?? m.last) != nil {
                tool("music.note", T("In riproduzione, a schermo intero", "Now playing, full screen"), lit: m.track?.playing == true) { model.nowPlaying = true }
            }
            tool("note.text.badge.plus", T("Aggiungi una nota", "Add a note")) { model.notes.append(GridNote()) }
            Menu {
                ForEach(widgets.filter { w in !tiles.layout.tiles.contains { $0.id == w.id } }, id: \.id) { w in
                    Button { tiles.layout.add(w.id) } label: { Label(w.title, systemImage: w.symbol) }
                }
            } label: {
                Image(systemName: "plus.square.on.square").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.55))
                    .frame(width: 32, height: 32).background(Circle().fill(Volta.card))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(T("Aggiungi un widget", "Add a widget"))
            tool(model.byCategory ? "square.grid.3x3.fill" : "square.grid.3x3", model.byCategory ? T("Tutte le app", "All apps") : T("Per categoria", "By category"), lit: model.byCategory) { model.byCategory.toggle() }
            tool("photo.badge.plus", T("Aggiungi immagini ai widget", "Add images to the widgets")) { pick(.images) }
            tool("photo", T("Cambia sfondo", "Change background")) { pick(.background) }
            tool(model.spaceSky ? "sparkles" : "sparkles", T("Cielo", "Sky"), lit: model.spaceSky) { model.spaceSky.toggle() }
            if model.background != nil { tool("arrow.uturn.backward", T("Sfondo del tema", "Theme background")) { model.background = nil } }
            tool(model.weatherFX ? "cloud.sun.fill" : "cloud.sun", T("Meteo sullo sfondo", "Weather on the background"), lit: model.weatherFX) { model.weatherFX.toggle() }
        }
    }

    private func tool(_ symbol: String, _ help: String, lit: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(lit ? 0.95 : 0.55))
                .frame(width: 32, height: 32).background(Circle().fill(lit ? Volta.pill : Volta.card))
        }
        .buttonStyle(.plain).help(help)
    }

    /// I widget dell'isola in grande (si personalizzano dall'isola) e le immagini aggiunte.
    /// La fila dei widget in alto. 13/10, l'autore: "deve starci tutto". Prima era sempre ingrandita di 1.3 e, con molte tessere,
    /// diventava più larga dello schermo: allargava tutta la vista e tagliava ai lati sia la fila sia la barra in alto a destra.
    /// Ora prende la misura più grande che ci sta; se non ci sta nemmeno la più piccola, scorre.
    private var widgetStrip: some View {
        // 13/10 sera: prima era un ViewThatFits con cinque copie della fila; ognuna teneva vive le sue animazioni (meteo,
        // musica, barre) e Pulsar stava al 100% di CPU anche a griglia chiusa ("il notch lagga"). Ora la misura si calcola:
        // una sola fila, ingrandita fino a 1.3 finché ci sta nello schermo meno i margini.
        let pairs = tiles.layout.tiles.compactMap { t in widgets.first { $0.id == t.id }.map { (t, $0) } }
        let natural = pairs.reduce(CGFloat(0)) { $0 + CGFloat($1.0.cells) * TileMetrics.cell + CGFloat($1.0.cells - 1) * TileMetrics.gap }
            + CGFloat(model.images.count) * TileMetrics.rowH * 1.5 + CGFloat(model.notes.count) * TileMetrics.rowH * 1.6
        let gaps = CGFloat(max(0, pairs.count + model.images.count + model.notes.count - 1)) * 14
        let avail = (model.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440) - 96 - gaps
        let scale = max(0.6, min(1.3, natural > 0 ? avail / natural : 1.3))
        return strip(scale)
    }

    private func strip(_ scale: CGFloat) -> some View {
        HStack(spacing: 14) {
            ForEach(tiles.layout.tiles.compactMap { t in widgets.first { $0.id == t.id }.map { (t, $0) } }, id: \.0.id) { pair in
                let w = CGFloat(pair.0.cells) * TileMetrics.cell + CGFloat(pair.0.cells - 1) * TileMetrics.gap
                pair.1.body(cells: pair.0.cells)
                    .padding(10)
                    .frame(width: w, height: TileMetrics.rowH, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous).fill(Volta.card))
                    // 13/10: ritagliata come nell'isola, così copertina sfocata e luce del meteo restano dentro gli angoli
                    .clipShape(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous))
                    .scaleEffect(scale)
                    .frame(width: w * scale, height: TileMetrics.rowH * scale)
            }
            ForEach(model.images, id: \.self) { p in ImageTile(path: p, height: TileMetrics.rowH * scale) { model.images.removeAll { $0 == p } } }
            ForEach($model.notes) { $n in
                let id = n.id
                NoteTile(note: $n, height: TileMetrics.rowH * scale) { model.notes.removeAll { $0.id == id } }
            }
        }
        .fixedSize()
    }

    private func folderHeader(_ c: String) -> some View {
        HStack(spacing: 10) {
            Button { model.openCategory = nil } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
                    .background(Circle().fill(Volta.card2))
            }
            .buttonStyle(.plain)
            Text(GridModel.title(c)).font(.system(size: 20, weight: .light))
        }
    }

    /// Per categoria: una cartella per gruppo, con le prime quattro icone (come la Libreria app dell'iPhone).
    private var foldersView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(190), spacing: 26), count: 4), spacing: 26) {
            ForEach(Array(model.folders.enumerated()), id: \.element.0) { i, f in
                Button { model.openCategory = f.0 } label: {
                    VStack(spacing: 10) {
                        LazyVGrid(columns: [GridItem(.fixed(60), spacing: 14), GridItem(.fixed(60), spacing: 14)], spacing: 14) {
                            ForEach(f.1.prefix(4)) { a in Image(nsImage: model.icon(a)).resizable().interpolation(.high).frame(width: 60, height: 60) }
                        }
                        .frame(width: 134, height: 134, alignment: .topLeading)      // stessa misura anche con meno di 4 app
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Volta.card))
                        Text("\(GridModel.title(f.0))  \(f.1.count)").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .opacity(model.shown ? 1 : 0).offset(y: model.shown ? 0 : 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(i) * 0.03), value: model.shown)
            }
        }
    }

    private var pagesView: some View {
        GeometryReader { g in
            let list = model.results
            let cellW = min(140, (g.size.width - 200) / CGFloat(GridModel.cols))
            HStack(spacing: 0) {
                ForEach(0..<GridPaging.pages(count: list.count, perPage: GridModel.perPage), id: \.self) { p in
                    Group {
                        if abs(p - model.page) <= 1 { page(p, list, cellW) } else { Color.clear }
                    }
                    .frame(width: g.size.width, height: g.size.height, alignment: .top)
                }
            }
            .offset(x: -CGFloat(model.page) * g.size.width)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: model.page)
        }
        .clipped()
    }

    private func page(_ p: Int, _ list: [GridApp], _ cellW: CGFloat) -> some View {
        let r = GridPaging.range(page: p, count: list.count, perPage: GridModel.perPage)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: 0), count: GridModel.cols), spacing: 22) {
            ForEach(Array(list[r].enumerated()), id: \.element.id) { i, a in
                GridIcon(app: a, icon: model.icon(a), width: cellW) { launch(a) }
                    .opacity(model.shown ? 1 : 0)
                    .offset(y: model.shown ? 0 : 10)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(i) * 0.008), value: model.shown)
            }
        }
    }

    private var dots: some View {
        let n = model.pages
        return HStack(spacing: 8) {
            if n > 1 {
                ForEach(0..<n, id: \.self) { p in
                    Circle().fill(Color.primary.opacity(p == model.page ? 0.8 : 0.22)).frame(width: 7, height: 7)
                        .onTapGesture { model.page = p }
                }
            }
        }
        .frame(height: 10)
    }
}

/// Un'immagine come widget: angoli come le tessere, una crocetta al passaggio per toglierla.
private struct ImageTile: View {
    let path: String
    let height: CGFloat
    let remove: () -> Void
    @State private var over = false
    var body: some View {
        Group {
            if let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: height * max(1, min(2, img.size.width / max(1, img.size.height))), height: height)
            } else { Volta.card.frame(width: height, height: height) }
        }
        .clipShape(RoundedRectangle(cornerRadius: TileMetrics.radius * 1.3, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if over {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain).padding(8)
            }
        }
        .onHover { over = $0 }
    }
}

private struct GridIcon: View {
    let app: GridApp
    let icon: NSImage
    let width: CGFloat
    let action: () -> Void
    @State private var over = false
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 72, height: 72)
                .scaleEffect(over ? 1.06 : 1)
            Text(app.name).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.85)).lineLimit(1).frame(width: width - 12)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { over = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: over)
        .onTapGesture(perform: action)
    }
}

// MARK: - Registro dei moduli (fase 2): la Griglia vale solo con Pulsar Complete

extension GridModule: ModuloPulsar {
    var id: String { "griglia" }
    var nome: String { T("Griglia app", "App grid") }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [] }
    var acceso: Bool { true }                       // non ha un interruttore suo: la griglia c'è quando c'è la licenza
    func avvia() { boot() }
    func ferma() { fermati() }
}
