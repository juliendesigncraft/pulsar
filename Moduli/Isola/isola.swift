// Isola: la Dynamic Island di Pulsar sul notch.
// Spec: docs/2026-10-11-isola-design.md. Logica pura (stati, scelta della fonte) in isola-logica.swift.
// Una fonte dice cosa mostrare; l'isola sceglie chi comanda e si apre, si chiude e segue l'aspetto (Theme).
import SwiftUI
import AppKit

/// Ombra leggera sotto l'isola (l'autore, 11/10 sera): dark matte al 10%, solo perché si sollevi dal fondo.
/// La finestra è più larga e più alta della forma di `shadowPad`, altrimenti l'ombra verrebbe tagliata.
enum IslandMetrics {
    static let shadowPad: CGFloat = 22
    static let shadow = Color(red: 0.115, green: 0.123, blue: 0.160).opacity(0.10)   // il dark matte di Night.rail
}

/// Una fonte dell'isola: musica, avvisi, finestre, widget. Mai lavoro pesante sul filo principale.
protocol IslandSource: AnyObject {
    var id: String { get }
    var priority: Int { get }
    var isActive: Bool { get }
    /// L'isola lo imposta: la fonte lo chiama quando cambia `isActive` o il contenuto compatto.
    var onChange: (() -> Void)? { get set }
    /// Vero per le fonti che vivono nella riga di tessere (musica, video): aprendo l'isola si vede la casa, non una vista sola.
    var usesHome: Bool { get }
    /// Piccola, a sinistra del notch (copertina, icona).
    func compactLeading() -> AnyView
    /// Piccola, a destra del notch (equalizzatore, tempo).
    func compactTrailing() -> AnyView
    func expandedView() -> AnyView
}

extension IslandSource { var usesHome: Bool { false } }

/// Fonte di prova: compare solo con lo stato forzato (`pulsar://isola?stato=...`).
private final class ProvaSource: IslandSource {
    let id = "prova"
    let priority = 1
    var isActive = true
    var onChange: (() -> Void)?
    func compactLeading() -> AnyView {
        AnyView(Circle().fill(Theme.accent).frame(width: 16, height: 16))
    }
    func compactTrailing() -> AnyView {
        AnyView(Text("0:42").font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.85)))
    }
    func expandedView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Isola").font(.system(size: 17, weight: .medium))
                Text(T("Contenuto di prova", "Test content")).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }
}

final class IslandModel: ObservableObject {
    @Published var state: IslandState = .rest
    @Published var source: IslandSource?
    @Published var leading: IslandSource?     // chi disegna la metà sinistra della compatta
    @Published var trailing: IslandSource?    // e la destra (Claude, se lavora)
    @Published var isHome = true              // la vista aperta è la casa con le tessere
    @Published var peek: PeekItem?            // la comparsa piccola in corso
    var dial: DialModule?                     // le ghiere di volume e luce, che si aprono dai pulsanti in alto
    var width: CGFloat = 520                  // larghezza dell'isola aperta: decide quante icone di app stanno in alto
    var openGrid: (() -> Void)?               // la griglia delle app (griglia.swift)
    var toggleTheme: (() -> Void)?            // Dark Matte / White Matte per tutto lo schermo (Temi.scegli)
    var home: IslandSource?          // cosa si vede aprendo l'isola quando nessuna fonte è attiva
    let tiles = TileModel()
    var widgets: [IslandWidget] = []
    var notchWidth: CGFloat = 190
    var notchHeight: CGFloat = 32

    // 17/10: trascinare file sul notch. l'autore: "nessuna animazione che captava che stavo trascinando un file,
    // l'immagine si è caricata ma non so dove è andata". Ora l'isola si apre col razzo e dice dove va e quando arriva.
    // 17/10: testa del pannello nuovo (isola-nuova.swift). Cambiare scheda ridisegna subito la finestra:
    // prima restava della misura vecchia per qualche secondo e la Casa copriva le icone in alto.
    /// 24/10: anteprima della Casa a freddo anche mentre Claude lavora (pulsar://isola?freddo=1, freddo=0 la toglie)
    @Published var anteprimaFredda = false { didSet { if anteprimaFredda != oldValue { DispatchQueue.main.async { self.dropChanged?() } } } }
    @Published var tab: IslandTab = .casa { didSet { if tab != oldValue { DispatchQueue.main.async { self.dropChanged?() } } } }
    weak var agent: AgentStore?
    @Published var dropHover = false
    @Published var dropNote: DropNote?
    /// 24/10: l'email aperta nel notch (isola-email.swift); finché c'è il pannello accetta la tastiera
    @Published var email: EmailBozza? { didSet { DispatchQueue.main.async { self.dropChanged?() } } }
    var dropChanged: (() -> Void)?
    /// Vero finché c'è un file in mano: allora "uscito" lo decide la zona fissa del controller, non la finestra che si muove.
    var dragActive: () -> Bool = { false }
    private var dropOff: DispatchWorkItem?
    private var noteOff: DispatchWorkItem?

    /// Dalla finestra (isTargeted): mentre si allarga sotto il file macOS dice "uscito" a ogni passo. Con un file in mano non conta.
    func targetChanged(_ on: Bool) {
        DropLog.add("finestra: file \(on ? "sopra" : "uscito") (drag attivo: \(dragActive()))")
        if !on && dragActive() { return }
        setDropHover(on)
    }

    func setDropHover(_ on: Bool) {
        DropLog.add("zona \(on ? "aperta" : "da chiudere")")
        dropOff?.cancel(); dropOff = nil
        if on {
            if !dropHover { MutaCentro.shared.leggiTrascinamento(); dropHover = true; dropChanged?() }   // 19/10: Muta legge i file in mano
        } else {
            // l'isola cambia misura sotto il file: si chiude solo se il file resta fuori per un attimo
            let w = DispatchWorkItem { [weak self] in self?.dropHover = false; MutaCentro.shared.fineTrascinamento(); self?.dropChanged?() }
            dropOff = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        }
    }

    func showDrop(_ note: DropNote, for seconds: Double) {
        dropOff?.cancel(); dropHover = false
        noteOff?.cancel()
        dropNote = note
        dropChanged?()
        let w = DispatchWorkItem { [weak self] in self?.dropNote = nil; self?.dropChanged?() }
        noteOff = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
}

/// Registro del trascinamento (17/10, per capire dove si perde il file): nella cartella dati (Cartelle.dati), agente/drop.log
enum DropLog {
    private static let url = AgentStore.dir.appendingPathComponent("drop.log")
    private static var last = ""
    static func add(_ s: String) {
        guard s != last else { return }          // niente righe uguali di fila (il mouse si muove spesso)
        last = s
        let line = "\(String(format: "%.2f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.data(using: .utf8)!.write(to: url) }
    }
}

/// Cosa dice l'isola dopo un trascinamento: dove è andato il file e se Claude l'ha preso.
struct DropNote: Equatable {
    enum Kind { case toClaude, toTray, taken }
    let kind: Kind
    let names: [String]
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var look = GhieraLook.shared    // cambio aspetto: l'isola si ridisegna subito
    var tap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            switch model.state {
            case .rest:
                Color.clear
            case .peek:
                if let p = model.peek {
                    PeekView(item: p, notchHeight: model.notchHeight)
                        .id(p.key + p.title + p.detail)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            case .compact:
                if let l = model.leading, let r = model.trailing {
                    HStack(spacing: 0) {
                        l.compactLeading().frame(maxWidth: .infinity)
                        Spacer().frame(width: model.notchWidth)
                        r.compactTrailing().frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: model.notchHeight)
                    .transition(.opacity)
                }
            case .expanded, .alert:
                // 17/10: il pannello nuovo sotto la barra dei menu (isola-nuova.swift)
                IslandPanelContent(model: model)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if model.state == .compact || model.state == .rest || model.state == .peek {
                // compatta e comparsa: nere negli aspetti scuri (continuano il notch vero), chiare in White Matte
                // e negli aspetti chiari (l'autore, 12/10: "il notch deve diventare chiaro in White Matte")
                Group {
                    if Theme.light { Color.clear.modifier(ThemeSurface(mode: look.mode, shape: NotchShape(bottom: model.state == .peek ? 14 : 10))) }
                    else { NotchShape(bottom: model.state == .peek ? 14 : 10).fill(Color.black) }
                }
                    .shadow(color: Ombra.colore, radius: Ombra.raggio, x: 0, y: Ombra.basso)   // 12/10: l'ombra minima del tema (temi.swift)
            } else {
                // 17/10: collo nel notch, pannello sotto la barra dei menu; ai lati del collo la barra resta libera
                IslandShellFill(neckWidth: model.notchWidth, neckHeight: model.notchHeight)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        // 17/10, da coucou: un file trascinato sul notch, anche compatto, diventa contesto per Claude
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { model.dropHover }, set: { model.targetChanged($0) })) { providers in
            IslandDrop.take(providers, model: model)
        }
        .environment(\.colorScheme, Theme.light ? .light : .dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: model.state)
        .padding(.horizontal, IslandMetrics.shadowPad).padding(.bottom, IslandMetrics.shadowPad)
    }
}

/// Dove vanno i file lasciati sull'isola. Con Claude al lavoro (o toccato da poco) diventano contesto della prossima
/// richiesta: l'hook li aggiunge con UserPromptSubmit. Altrimenti, o tenendo ⌥, vanno nel Vassoio come prima.
enum IslandDrop {
    static weak var store: AgentStore?

    /// Il file andrebbe a Claude adesso? (la vista del trascinamento lo dice prima di lasciarlo)
    static var goesToClaude: Bool { (store?.acceptsContext ?? false) && !NSEvent.modifierFlags.contains(.option) }

    static func take(_ providers: [NSItemProvider], model: IslandModel) -> Bool {
        let toClaude = goesToClaude
        DropLog.add("rilasciato sull'isola: \(providers.count) elementi")
        TrayModel.load(providers) { urls in deliver(urls, toClaude: toClaude, model: model) }
        return true
    }

    static func deliver(_ urls: [URL], toClaude: Bool, model: IslandModel) {
        DropLog.add("letti \(urls.count) file, a \(toClaude ? "Claude" : "Vassoio"): \(urls.map(\.lastPathComponent).joined(separator: ", "))")
        guard !urls.isEmpty else { model.setDropHover(false); return }
        // 19/10: lasciato su una tessera di Muta (scopo, formato, unisci) lo converte Muta; sul posto di prima, come prima
        if MutaCentro.shared.prendi(urls) { DropLog.add("preso da Muta"); model.setDropHover(false); return }
        let names = urls.map(\.lastPathComponent)
        if toClaude, let st = store {
            st.addContext(urls)
            model.showDrop(DropNote(kind: .toClaude, names: names), for: 4)
        } else {
            TrayModel.shared.add(urls)
            model.tiles.layout.add("tray")
            model.showDrop(DropNote(kind: .toTray, names: names), for: 3)
        }
    }
}

enum IslandActions {
    static func settings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!) }
    static func airDrop() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")) }
    static func files() { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
    static func notes() {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// La finestra dell'isola: come FloatPanel dell'Agente ma sua, così le modifiche a quella (ombre, temi) non la toccano.
final class IslandPanel: NSPanel {
    init(level: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    /// 24/10: solo mentre c'è l'email da scrivere (come Spotlight: tastiera sì, l'app davanti resta quella)
    var testo = false
    override var canBecomeKey: Bool { testo }
    override var canBecomeMain: Bool { false }
}

/// 17/10: una finestra invisibile grande quanto il notch, sempre lì, che accetta solo file trascinati.
/// Serve perché a isola chiusa la finestra dell'isola non c'è, e durante un trascinamento dal Finder
/// macOS non passa a Pulsar i movimenti del mouse (drop.log vuoto). Sul notch non c'è niente da cliccare.
final class NotchDropCatcher: NSPanel {
    var onEnter: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onMove: (() -> Void)?            // il mouse sopra questa finestra non arriva ai monitor globali: lo si gira all'isola
    init(level: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = NSColor(white: 0, alpha: 0.004)    // del tutto trasparente macOS la salterebbe
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let v = CatchView()
        v.owner = self
        contentView = v
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private final class CatchView: NSView {
        weak var owner: NotchDropCatcher?
        override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
        required init?(coder: NSCoder) { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { owner?.onMove?() }
        override func mouseMoved(with event: NSEvent) { owner?.onMove?() }
        override func mouseExited(with event: NSEvent) { owner?.onMove?() }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            DropLog.add("notch invisibile: file arrivato")
            owner?.onEnter?()
            return .copy
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { owner?.onMove?(); return .copy }   // Muta: quale tessera c'è sotto
        override func draggingExited(_ sender: NSDraggingInfo?) { DropLog.add("notch invisibile: file uscito") }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            DropLog.add("notch invisibile: rilasciato \(urls.count) file")
            owner?.onDrop?(urls)
            return !urls.isEmpty
        }
    }
}

final class IslandModule {
    let model = IslandModel()
    var dialStore: DialStore?                    // il timer dei widget è quello della Ghiera
    var agentStore: AgentStore?                  // Claude Code nel notch
    private var agentSource: AgentIslandSource?
    private var animaSource: AnimaSource?            // 12/10: dettatura, comandi, cerchia e chiedi (anima.swift)
    private let watch = SystemWatch()
    private var tilesWatch: Any?
    private var win: IslandPanel?
    private var catcher: NotchDropCatcher?
    private var catcherRaised = false
    private let islandLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    private var sources: [IslandSource] = []
    private let prova = ProvaSource()
    private let media = MediaSource()
    private let browser = BrowserMediaSource()
    private let riunione = RiunioneSource()         // fase 4: la prossima riunione (riunione-isola.swift)
    private var dwellWork: DispatchWorkItem?
    private var forced: IslandState?
    private var hover = false
    private var pinnedOpen = false
    private var hoverWork: DispatchWorkItem?
    private var monitors: [Any] = []
    private var shown = false

    var enabled: Bool {
        get { Impostazioni.object(.isolaEnabled) as? Bool ?? true }
        set { Impostazioni.set(newValue, .isolaEnabled); RegistroModuli.shared.riapplica() }
    }

    func register(_ s: IslandSource) {
        s.onChange = { [weak self] in self?.layout(animated: true) }
        sources.append(s)
        layout(animated: true)
    }

    /// Reel: mouse "sopra" l'isola senza il mouse vero (il puntatore del video è finto).
    /// Durante il reel il mouse vero non conta (se lo tocchi non apre e non chiude l'isola).
    var demoLock = false
    func demoHover(_ on: Bool) { hover = on; if !on { pinnedOpen = false }; layout(animated: true) }
    var demoMedia: MediaSource { media }

    /// Per le prove: `nil` torna al comportamento normale.
    func force(_ s: IslandState?) {
        forced = s
        if !enabled { enabled = true }
        layout(animated: true)
    }

    // MARK: schermo e notch (stessa lettura di AgentModule.notchSize)

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private var notchSize: CGSize {
        let s = screen
        guard s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else {
            return CGSize(width: 190, height: NSStatusBar.system.thickness)   // Mac senza notch: 190 pt in alto al centro
        }
        return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
    }

    // MARK: vita

    private func start() {
        guard win == nil else { return }
        let lvl = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        let w = IslandPanel(level: lvl)
        w.contentView = FirstClickHost(rootView: IslandView(model: model, tap: { [weak self] in self?.togglePinned() }))
        win = w
        let c = NotchDropCatcher(level: lvl)
        c.onEnter = { [weak self] in self?.model.setDropHover(true) }
        c.onDrop = { [weak self] urls in
            guard let self else { return }
            IslandDrop.deliver(urls, toClaude: IslandDrop.goesToClaude, model: self.model)
        }
        c.onMove = { [weak self] in self?.mouseMoved() }
        catcher = c
        placeCatcher()
        DropLog.add("avvio: schermo \(Int(screen.frame.width))x\(Int(screen.frame.height)), notch \(notchSize), finestra invisibile \(c.frame)")
        model.home = media
        model.widgets = [MusicWidget(media: media), WeatherWidget(), CalendarWidget(), TimerWidget(dial: dialStore),
                         YouTubeWidget(browser: browser), WindowWidget(), MessagesWidget(), ClipboardWidget(), TrayWidget(),
                         RecentsWidget(), MacWidget(), TodoWidget(),
                         ControlsWidget(model: model), PowerWidget(), StatsWidget()]
        model.widgets += [ClockWidget(), MonthWidget(), SunWidget()]   // 14/10: da LaunchMe, forme Braun (widget-braun.swift)
        // 12/10 sera: una volta sola, le tessere nuove che contano di più entrano nella riga (le altre dai chip)
        // 12/10 tarda sera, l'autore: "meteo non ha senso così largo", "Spotify riempi la sezione": meteo 2 celle, musica 3
        if !Impostazioni.bool(.isolaMeteoStretto) {
            Impostazioni.set(true, .isolaMeteoStretto)
            model.tiles.layout.resize("weather", to: 2); model.tiles.layout.resize("music", to: 3)
        }
        if !Impostazioni.bool(.isolaBraun1) {           // 14/10: orologio e mese entrano nella riga una volta
            Impostazioni.set(true, .isolaBraun1)
            model.tiles.layout.add("clock", cells: 1); model.tiles.layout.add("month", cells: 1)
        }
        if !Impostazioni.bool(.isolaPrioritaLarga) {      // la priorità respira su tre celle
            Impostazioni.set(true, .isolaPrioritaLarga)
            model.tiles.layout.resize("todo", to: 3)
        }
        if !Impostazioni.bool(.isolaHitodama1) {
            Impostazioni.set(true, .isolaHitodama1)
            model.tiles.layout.add("controls"); model.tiles.layout.add("todo")
        }
        ClipboardHistory.shared.start()
        RecentApps.shared.start()
        // 12/10 notte: WhatsApp si legge dall'avvio se la tessera è nella riga, così non mostra "chiuso" per i primi secondi
        if model.tiles.layout.tiles.contains(where: { $0.id == "messages" }) { WhatsAppReader.shared.retain() }
        tilesWatch = model.tiles.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.layout(animated: true) } }
        media.onChange = { [weak self] in self?.layout(animated: true) }
        sources.append(media)
        media.start()
        EdgeGlow.shared.start(media: media)          // 14/10: il bordo dello schermo a ritmo (si accende dal menu)
        browser.onChange = { [weak self] in self?.layout(animated: true) }
        sources.append(browser)
        browser.start()
        if model.dropChanged == nil { model.dropChanged = { [weak self] in self?.layout(animated: true) } }
        if let st = agentStore {
            IslandDrop.store = st
            model.agent = st
            st.onContextTaken = { [weak self] names in self?.model.showDrop(DropNote(kind: .taken, names: names), for: 3) }
            model.dropChanged = { [weak self] in self?.layout(animated: true) }
            model.dragActive = { [weak self] in self?.draggingFile ?? false }
            let a = AgentIslandSource(store: st)
            a.onChange = { [weak self] in self?.layout(animated: true) }
            agentSource = a
            sources.append(a)
        }
        let amb = AmbientSource()                        // 12/10 sera: il LED resta anche quando non c'è altro (nothing.swift)
        amb.onChange = { [weak self] in self?.layout(animated: true) }
        sources.append(amb)
        let an = AnimaSource(anima: .shared)
        an.onChange = { [weak self] in self?.layout(animated: true) }
        animaSource = an
        sources.append(an)
        riunione.onChange = { [weak self] in self?.layout(animated: true) }
        riunione.chiudi = { [weak self] in self?.chiudi() }      // Entra e Apri nel Calendario chiudono l'isola
        sources.append(riunione)
        riunione.start()
        let move: (NSEvent) -> Void = { [weak self] _ in self?.mouseMoved() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: move) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { move($0); return $0 }) { monitors.append(l) }
        // un clic fuori chiude l'isola aperta con un clic
        let fuori: (NSEvent) -> Void = { [weak self] _ in
            self?.dragBase = NSPasteboard(name: .drag).changeCount     // 17/10: per riconoscere un file trascinato dopo
            DispatchQueue.main.async { self?.clickOutside() }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            DispatchQueue.main.async { if self?.model.dropHover == true { self?.model.setDropHover(false) } }
        }) { monitors.append(g) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: fuori) { monitors.append(g) }
        PeekCenter.shared.onChange = { [weak self] in self?.layout(animated: true) }
        watch.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.layout(animated: false)
            self?.placeCatcher()
        }
        layout(animated: false)
    }

    /// La finestra che accetta i file: esattamente sul notch, sotto l'isola (che quando si apre le sta sopra).
    /// In modalità rilascio si allarga quanto tutta la zona e sale sopra l'isola: il rilascio lo prende lei (AppKit),
    /// perché quello di SwiftUI sull'isola che si anima si perdeva (drop.log del 17/10: "file uscito" e nessun rilascio).
    private func placeCatcher() {
        guard let c = catcher else { return }
        let sf = screen.frame, n = notchSize
        let raise = model.dropHover
        if raise {
            c.level = NSWindow.Level(rawValue: islandLevel.rawValue + 1)
            c.setFrame(dropZone, display: false)
            c.orderFrontRegardless()
        } else {
            c.level = islandLevel
            c.setFrame(NSRect(x: sf.midX - n.width / 2, y: sf.maxY - n.height, width: n.width, height: n.height), display: false)
            c.orderFrontRegardless()
            win.map { if $0.isVisible { $0.orderFrontRegardless() } }
        }
        if raise != catcherRaised { DropLog.add("notch invisibile: \(raise ? "allargato su tutta la zona" : "tornato sul notch")") }
        catcherRaised = raise
    }

    private func stop() {
        catcher?.orderOut(nil); catcher = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        media.stop()
        browser.stop()
        riunione.stop()
        watch.stop()
        PeekCenter.shared.onChange = nil
        ClipboardHistory.shared.stop()
        RecentApps.shared.stop()
        tilesWatch = nil
        sources.removeAll { $0 === media || $0 === browser || $0 === agentSource || $0 === animaSource || $0 === riunione || $0 is AmbientSource }
        agentSource = nil
        animaSource = nil
        NotificationCenter.default.removeObserver(self)
        win?.orderOut(nil)
        win = nil
        shown = false
    }

    // MARK: mouse

    /// La forma dell'isola dentro la finestra: tolto il margine dell'ombra.
    private func contentFrame(_ f: NSRect) -> NSRect {
        let p = IslandMetrics.shadowPad
        return NSRect(x: f.minX + p, y: f.minY + p, width: f.width - 2 * p, height: f.height - p)
    }

    /// La fascia sensibile: il notch e un po' di margine, fino al bordo alto dello schermo.
    private var wakeZone: NSRect {
        let sf = screen.frame, n = notchSize
        let w = n.width + 60
        return NSRect(x: sf.midX - w / 2, y: sf.maxY - n.height - 2, width: w, height: n.height + 6)
    }

    /// Il mouse in alto sul notch apre l'isola dopo un secondo; uscendo si chiude dopo mezzo secondo.
    /// Un file trascinato da un'altra app: tasto premuto e appunti del trascinamento cambiati dall'ultimo clic.
    private var dragBase = NSPasteboard(name: .drag).changeCount
    /// La zona di rilascio aperta, con un margine: la stessa misura che le dà layout (520 x notch + 104).
    private var dropZone: NSRect {
        let sf = screen.frame, n = notchSize
        return NSRect(x: sf.midX - 300, y: sf.maxY - n.height - 180, width: 600, height: n.height + 180)   // 19/10: alta quanto le tessere di Muta
    }
    private var draggingFile: Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return false }
        let pb = NSPasteboard(name: .drag)
        return pb.changeCount != dragBase && (pb.types ?? []).contains(.fileURL)
    }

    private func mouseMoved() {
        guard win != nil, !demoLock else { return }
        let p = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons & 1 != 0, p.y > screen.frame.maxY - 90 {
            DropLog.add("trascino in alto: x \(Int(p.x)) y \(Int(p.y)), notch \(Int(wakeZone.minX))-\(Int(wakeZone.maxX)) da y \(Int(wakeZone.minY)), file \(draggingFile)")
        }
        // 17/10: un file portato vicino al notch apre subito la zona di rilascio, anche a isola chiusa
        if NSEvent.pressedMouseButtons & 1 != 0, wakeZone.insetBy(dx: -40, dy: -10).contains(p) {
            let pb = NSPasteboard(name: .drag)
            DropLog.add("mouse premuto sul notch: drag cambiato \(pb.changeCount != dragBase), tipi \((pb.types ?? []).map(\.rawValue).prefix(3).joined(separator: " "))")
        }
        if draggingFile {
            // per aprirla basta il notch; una volta aperta conta tutta la zona di rilascio (fissa, non la finestra che si anima)
            if wakeZone.insetBy(dx: -40, dy: -10).contains(p) || (model.dropHover && dropZone.contains(p)) {
                model.setDropHover(true)
                mutaPunto(p)
                return
            }
            if model.dropHover { model.setDropHover(false) }
        }
        var inside = wakeZone.contains(p)
        if shown, let f = win?.frame, contentFrame(f).insetBy(dx: -6, dy: -6).contains(p) { inside = true }
        if inside {
            hoverWork?.cancel(); hoverWork = nil
            if !hover && dwellWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.dwellWork = nil; self?.hover = true; self?.layout(animated: true) }
                dwellWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
            }
        } else {
            dwellWork?.cancel(); dwellWork = nil
            if hover && hoverWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.hover = false; self?.hoverWork = nil; self?.layout(animated: true) }
                hoverWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: w)
            }
        }
    }

    /// Muta: il mouse in coordinate delle tessere (il contenuto parte 20 pt dentro il pannello largo 600, sotto il notch + 8).
    private func mutaPunto(_ p: NSPoint) {
        let sf = screen.frame, n = notchSize
        MutaCentro.shared.puntatore(CGPoint(x: p.x - (sf.midX - 300 + 20), y: (sf.maxY - n.height - 8) - p.y))
    }

    private func togglePinned() {
        pinnedOpen.toggle()
        layout(animated: true)
    }

    /// Chiude l'isola aperta, anche se era fissata col clic (fase 4: dopo Entra o Apri nel Calendario).
    private func chiudi() {
        pinnedOpen = false
        hover = false
        dwellWork?.cancel(); dwellWork = nil
        hoverWork?.cancel(); hoverWork = nil
        model.tiles.editing = false
        layout(animated: true)
    }

    private func clickOutside() {
        guard pinnedOpen || model.tiles.editing, let f = win?.frame, !contentFrame(f).contains(NSEvent.mouseLocation) else { return }
        pinnedOpen = false
        model.tiles.editing = false
        layout(animated: true)
    }

    // MARK: layout

    private var current: IslandSource? {
        let all = forced != nil ? sources + [prova] : sources
        let offers = all.map { SourceOffer(id: $0.id, priority: $0.priority, active: $0.isActive) }
        guard let id = IslandLogic.pick(offers, pinned: nil) else { return nil }
        return all.first { $0.id == id }
    }

    private func layout(animated: Bool) {
        guard let win else { return }
        let src = current
        let alert = agentSource?.alert == true || animaSource?.alert == true
        let peekItem = PeekCenter.shared.current
        let scrive = model.email != nil
        let dropping = model.dropHover || model.dropNote != nil || scrive
        win.testo = scrive
        if scrive && !win.isKeyWindow { DispatchQueue.main.async { win.makeKey() } }
        if model.dropHover != catcherRaised { placeCatcher() }
        let state = dropping ? .alert : forced ?? IslandLogic.state(hover: hover, pinnedOpen: pinnedOpen || model.tiles.editing, alert: alert,
                                                hasContent: src != nil || hover || pinnedOpen || model.tiles.editing, peek: peekItem != nil)
        model.peek = peekItem
        if agentSource?.recentlyDone == true {      // a fine lavoro l'avviso si ritira da solo dopo sei secondi
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.3) { [weak self] in self?.layout(animated: true) }
        }
        // compatta in due metà: Claude a destra del notch se lavora, a sinistra la musica (o il tempo)
        // fase 4: solo se la fonte scelta non conta più di Claude (la riunione, 80, batte Claude che lavora o ha finito)
        if let a = agentSource, animaSource?.isActive != true,
           IslandLogic.claudeAiLati(agente: SourceOffer(id: a.id, priority: a.priority, active: a.isActive),
                                    scelta: src.map { SourceOffer(id: $0.id, priority: $0.priority, active: $0.isActive) }) {
            model.leading = a          // 17/10: il razzo a sinistra, le sessioni a destra (anteprima approvata)
            model.trailing = a
        } else {
            model.leading = src; model.trailing = src
        }
        model.isHome = src.map { $0.usesHome } ?? true
        let notch = notchSize
        model.notchWidth = notch.width
        model.notchHeight = notch.height
        model.source = src
        if model.state != state { model.state = state }

        let sf = screen.frame
        let wing: CGFloat = 46
        let w: CGFloat, h: CGFloat
        switch state {
        case .rest:     w = notch.width + 20;                h = notch.height
        case .compact:  w = notch.width + 2 * wing + 20;     h = notch.height
        case .peek:     w = peekItem.map { PeekView.width($0, notch: notch.width) } ?? notch.width + 20; h = notch.height + 28
        case .expanded, .alert:
            // 17/10 sera: pannello attaccato al bordo alto, testa nella fascia del notch: notch + 8 + tessera + 10
            if scrive { w = 600; h = notch.height + 8 + EmailCard.altezza + 10 }
            else if dropping { w = 600; h = notch.height + 8 + (MutaCentro.shared.mostraTessere && model.dropNote == nil ? MutaZona.altezza : 132) + 10 }
            else if let s = src, !s.usesHome {
                if let a = s as? AgentIslandSource { w = 680; h = notch.height + 8 + a.height + 10 }
                else { w = 600; h = notch.height + 8 + ((s as? AnimaSource)?.height ?? 150) }
            } else if model.tab == .tessere {
                // più bassa della Casa (l'autore, 17/10); il cambio di scheda ridisegna subito, quindi niente più icone coperte
                w = min(max(700, model.tiles.layout.width(cell: TileMetrics.cell, gap: TileMetrics.gap) + 40), sf.width - 40)
                h = notch.height + 8 + TileMetrics.rowH + 10 + (model.tiles.editing ? 32 : 0)
            } else {
                // 24/10: a freddo (né Claude né musica che suona) un riquadro solo, un pelo più stretto
                let freddo = model.anteprimaFredda || ((agentSource?.isActive != true) && ((model.home as? MediaSource)?.track?.playing != true))
                w = freddo ? 580 : 700; h = notch.height + 8 + 128 + 10
            }
        }
        model.width = w
        let pad = IslandMetrics.shadowPad
        let frame = NSRect(x: sf.midX - w / 2 - pad, y: sf.maxY - h - pad, width: w + 2 * pad, height: h + pad)
        let show = state != .rest
        if show && !shown {
            // parte dalla forma del notch e si apre da lì
            win.setFrame(NSRect(x: sf.midX - (notch.width + 20) / 2 - pad, y: sf.maxY - notch.height - pad, width: notch.width + 20 + 2 * pad, height: notch.height + pad), display: false)
            win.orderFrontRegardless()
        }
        shown = show
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = model.tiles.editing ? 0.15 : 0.55
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                win.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                if self?.shown == false { win.orderOut(nil) }
            }
        } else {
            win.setFrame(frame, display: true)
            if !show { win.orderOut(nil) }
        }
    }
}

// MARK: - Registro dei moduli (fase 2): l'Isola vale solo con Pulsar Complete

extension IslandModule: ModuloPulsar {
    var id: String { "isola" }
    var nome: String { T("Isola nel notch", "Notch island") }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [.accessibilita, .automazione, .registrazioneSchermo, .calendario] }
    var acceso: Bool { enabled }
    func avvia() { start() }                        // start() esce subito se è già partita
    func ferma() { if win != nil { stop() } }
    /// Dalla pagina Isola: l'interruttore della riunione è cambiato.
    func riunioneCambiata() { riunione.rivaluta() }
}
