// Altri widget dell'isola (12/10): Messaggi (WhatsApp), Appunti, Vassoio, Recenti, Mac.
// Si aggiungono dalla modalità modifica. Stesse regole di widget.swift: tessere orizzontali, colori solo dal tema.
// Privacy: messaggi e appunti restano in memoria, non si salvano e non escono dal Mac.
import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

// MARK: - Messaggi (WhatsApp Desktop, letto con l'Accessibilità)

final class WhatsAppReader: ObservableObject {
    static let shared = WhatsAppReader()
    static let bundle = "net.whatsapp.WhatsApp"
    enum Status { case ok, closed, noWindow, noPermission }
    @Published private(set) var chats: [ChatPreview] = []
    @Published private(set) var status: Status = .closed
    private let queue = DispatchQueue(label: "pulsar.whatsapp", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var users = 0

    /// Legge solo mentre una tessera Messaggi è visibile.
    func retain() {
        users += 1
        guard users == 1 else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 4, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t; t.resume()
    }
    func release() {
        users = max(0, users - 1)
        if users == 0 { timer?.cancel(); timer = nil }
    }

    private var demo = false

    private func poll() {
        guard !demo else { return }
        guard AXIsProcessTrusted() else { publish([], .noPermission); return }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Self.bundle }) else { publish([], .closed); return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        let windows = (AX.attr(el, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let table = windows.lazy.compactMap({ Self.find($0, "ChatListView_TableView", depth: 12) }).first else { publish([], .noWindow); return }
        let you = T("Tu: ", "You: ")
        let rows = AX.children(table).compactMap { r -> ChatPreview? in
            if (AX.string(r, "AXIdentifier") ?? "").contains("archive") { return nil }
            return WhatsAppParse.row(description: AX.string(r, kAXDescriptionAttribute) ?? "", value: AX.string(r, kAXValueAttribute) ?? "", youPrefix: you)
        }
        publish(rows, .ok)
    }

    private static func find(_ e: AXUIElement, _ id: String, depth: Int) -> AXUIElement? {
        guard depth > 0 else { return nil }
        if AX.string(e, "AXIdentifier") == id { return e }
        for c in AX.children(e) { if let f = find(c, id, depth: depth - 1) { return f } }
        return nil
    }

    private func publish(_ rows: [ChatPreview], _ st: Status) {
        DispatchQueue.main.async {
            if self.chats != rows { self.chats = rows }
            if self.status != st { self.status = st }
        }
    }

    /// Prova: la struttura della finestra di WhatsApp (ruoli, identificatori, lunghezza dei testi; MAI il testo) in
    /// wa-albero.txt nella cartella dati (Cartelle.dati), per capire dove stanno la chat aperta e il campo di scrittura.
    static func dumpTree() {
        DispatchQueue.global().async {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle }) else { return }
            var out = ""
            func walk(_ e: AXUIElement, _ d: Int) {
                guard d < 22 else { return }
                let role = AX.string(e, kAXRoleAttribute) ?? "?"
                let id = AX.string(e, "AXIdentifier") ?? ""
                let dl = (AX.string(e, kAXDescriptionAttribute) ?? "").count
                let vl = (AX.string(e, kAXValueAttribute) ?? "").count
                let kids = AX.children(e)
                out += String(repeating: " ", count: d) + "\(role) id=\(id) desc=\(dl) val=\(vl) figli=\(kids.count)\n"
                for k in kids.prefix(40) { walk(k, d + 1) }
            }
            let el = AXUIElementCreateApplication(app.processIdentifier)
            for w in (AX.attr(el, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(w, 0) }
            let f = Cartelle.dati.appendingPathComponent("wa-albero.txt")
            try? out.write(to: f, atomically: true, encoding: .utf8)
        }
    }

    static func open() {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct MessagesWidget: IslandWidget {
    let id = "messages"
    var title: String { T("Messaggi", "Messages") }
    let symbol = "message"
    func body(cells: Int) -> AnyView { AnyView(MessagesTile(reader: .shared, cells: cells)) }
}

private struct MessagesTile: View {
    @ObservedObject var reader: WhatsAppReader
    let cells: Int
    @AppStorage(Chiave.isolaWAChat.rawValue) private var pinned = ""

    /// La chat fissata per prima, poi le altre nell'ordine di WhatsApp.
    private var ordered: [ChatPreview] {
        guard !pinned.isEmpty, let p = reader.chats.first(where: { $0.name == pinned }) else { return reader.chats }
        return [p] + reader.chats.filter { $0.name != pinned }
    }

    var body: some View {
        Group {
            switch reader.status {
            case .noPermission:
                note(T("Consenti l'Accessibilità a Pulsar", "Allow Accessibility for Pulsar"), amber: true)
            case .closed:
                action(T("WhatsApp è chiuso", "WhatsApp is closed"), T("Apri", "Open"))
            case .noWindow:
                action(T("Apri la finestra di WhatsApp", "Open the WhatsApp window"), T("Apri", "Open"))
            case .ok:
                if cells == 1 { single }
                else if let first = ordered.first {
                    VStack(alignment: .leading, spacing: 6) {
                        chatRow(first, lines: cells >= 3 ? 1 : 2, top: true)
                        if cells >= 3, ordered.count > 1 { chatRow(ordered[1], lines: 1, top: false) }
                    }
                } else { note(T("Nessuna chat", "No chats"), amber: false) }
            }
        }
        .onAppear { reader.retain() }
        .onDisappear { reader.release() }
    }

    private var single: some View {
        let unread = reader.chats.reduce(0) { $0 + $1.unread }
        return Button { WhatsAppReader.open() } label: {
            VStack(spacing: 4) {
                Image(systemName: unread > 0 ? "message.badge.filled.fill" : "message").font(.system(size: 20)).symbolRenderingMode(.hierarchical)
                Text(unread > 0 ? "\(unread)" : "WhatsApp").font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func chatRow(_ c: ChatPreview, lines: Int, top: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(c.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if c.unread > 0 {
                    Text("\(c.unread)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(Night.onProminent)
                        .padding(.horizontal, 5).frame(height: 14).background(Capsule().fill(Night.green))
                }
                Spacer(minLength: 4)
                Text(c.time).font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.45))
                if top {
                    Button { pinned = pinned == c.name ? "" : c.name } label: {
                        Image(systemName: pinned == c.name ? "pin.fill" : "pin").font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.6))
                    }
                    .buttonStyle(.plain).help(T("Fissa questa chat", "Pin this chat"))
                    Button { next() } label: {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.6))
                    }
                    .buttonStyle(.plain).help(T("Chat successiva", "Next chat"))
                }
            }
            Text(c.text).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(lines)
        }
        .contentShape(Rectangle())
        .onTapGesture { WhatsAppReader.open() }
    }

    /// Passa alla chat successiva e la fissa: così si sceglie "una chat specifica".
    private func next() {
        let list = reader.chats
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.name == (ordered.first?.name ?? "") } ?? -1
        pinned = list[(i + 1) % list.count].name
    }

    private func note(_ text: String, amber: Bool) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(amber ? Night.amber : Color.primary.opacity(0.55))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func action(_ text: String, _ button: String) -> some View {
        VStack(spacing: 6) {
            Text(text).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)).multilineTextAlignment(.center)
            Button { WhatsAppReader.open() } label: {
                Text(button).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Appunti (solo in memoria, mai le password)

final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()
    @Published private(set) var items: [String] = []
    private var change = NSPasteboard.general.changeCount
    private var timer: Timer?
    /// Tipi che i gestori di password e le app usano per dire "non tenermi": si saltano.
    private static let skip: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                                            "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() { timer?.invalidate(); timer = nil; items = [] }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != change else { return }
        change = pb.changeCount
        let types = Set((pb.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.skip), let s = pb.string(forType: .string) else { return }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 5000 else { return }
        items.removeAll { $0 == t }
        items.insert(t, at: 0)
        if items.count > 12 { items.removeLast(items.count - 12) }
    }

    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(s, forType: .string)
        change = pb.changeCount
        items.removeAll { $0 == s }; items.insert(s, at: 0)
    }
}

struct ClipboardWidget: IslandWidget {
    let id = "clipboard"
    var title: String { T("Appunti", "Clipboard") }
    let symbol = "doc.on.clipboard"
    func body(cells: Int) -> AnyView { AnyView(ClipboardTile(history: .shared, cells: cells)) }
}

private struct ClipboardTile: View {
    @ObservedObject var history: ClipboardHistory
    let cells: Int
    @State private var copied: String?

    var body: some View {
        if history.items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                if cells > 1 { Text(T("Copia qualcosa", "Copy something")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cells == 1 {
            Button { history.copy(history.items[0]); flash(history.items[0]) } label: {
                VStack(spacing: 4) {
                    Image(systemName: copied == nil ? "doc.on.clipboard" : "checkmark").font(.system(size: 18))
                    Text("\(history.items.count)").font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(history.items.prefix(cells >= 3 ? 3 : 2), id: \.self) { s in
                    Button { history.copy(s); flash(s) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied == s ? "checkmark" : "doc.on.doc").font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.5))
                            Text(s.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func flash(_ s: String) {
        copied = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == s { copied = nil } }
    }
}

// MARK: - Vassoio (file trascinati sull'isola)

final class TrayModel: ObservableObject {
    static let shared = TrayModel()
    @Published private(set) var files: [URL] = (Impostazioni.stringArray(.isolaTray) ?? [])
        .map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }

    private func save() { Impostazioni.set(files.map(\.path), .isolaTray) }

    func add(_ urls: [URL]) {
        for u in urls where !files.contains(u) { files.append(u) }
        if files.count > 12 { files.removeFirst(files.count - 12) }
        save()
    }
    /// Toglie dal vassoio, il file resta dov'è.
    func remove(_ u: URL) { files.removeAll { $0 == u }; save() }

    /// Legge gli URL dai file trascinati.
    static func load(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                guard let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) else { return }
                lock.lock(); urls.append(u); lock.unlock()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}

struct TrayWidget: IslandWidget {
    let id = "tray"
    var title: String { T("Vassoio", "Tray") }
    let symbol = "tray"
    func body(cells: Int) -> AnyView { AnyView(TrayTile(tray: .shared, cells: cells)) }
}

private struct TrayTile: View {
    @ObservedObject var tray: TrayModel
    let cells: Int

    var body: some View {
        if tray.files.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                if cells > 1 { Text(T("Trascina qui i file", "Drop files here")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 8) {
                ForEach(tray.files.suffix(max(1, cells * 2 - 1)), id: \.self) { u in TrayFile(url: u, tray: tray) }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct TrayFile: View {
    let url: URL
    @ObservedObject var tray: TrayModel
    @ObservedObject private var icone = IconeApp.shared
    @State private var over = false
    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: icone.icona(url.path)).resizable().frame(width: 34, height: 34)
            Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 9)).lineLimit(1).frame(width: 52)
        }
        .overlay(alignment: .topTrailing) {
            if over {
                Button { tray.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.75))
                }
                .buttonStyle(.plain).offset(x: 4, y: -4)
            }
        }
        .onHover { over = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .help(url.path)
    }
}

// MARK: - Recenti (app aperte o chiuse da poco)

final class RecentApps: ObservableObject {
    static let shared = RecentApps()
    struct Entry: Equatable { var bundle: String; var name: String; var running: Bool }
    @Published private(set) var entries: [Entry] = []
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        entries = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { a in a.bundleIdentifier.map { Entry(bundle: $0, name: a.localizedName ?? $0, running: true) } }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, a.activationPolicy == .regular,
                  let b = a.bundleIdentifier, b != Bundle.main.bundleIdentifier else { return }
            self?.touch(Entry(bundle: b, name: a.localizedName ?? b, running: true))
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let b = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  let i = self.entries.firstIndex(where: { $0.bundle == b }) else { return }
            var e = self.entries.remove(at: i); e.running = false
            self.entries.insert(e, at: 0)                      // chiusa da poco: va in testa, attenuata
        })
    }

    func stop() { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = [] }

    private var saved: [Entry]?

    private func touch(_ e: Entry) {
        entries.removeAll { $0.bundle == e.bundle }
        entries.insert(e, at: 0)
        if entries.count > 12 { entries.removeLast(entries.count - 12) }
    }

    /// Aperta: la porta davanti (anche se nascosta). Chiusa: la riapre.
    func open(_ e: Entry) {
        if let a = NSRunningApplication.runningApplications(withBundleIdentifier: e.bundle).first {
            if a.isHidden { a.unhide() }
            a.activate()
        } else if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundle) {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct RecentsWidget: IslandWidget {
    let id = "recents"
    var title: String { T("Recenti", "Recents") }
    let symbol = "clock.arrow.circlepath"
    func body(cells: Int) -> AnyView { AnyView(RecentsTile(recents: .shared, cells: cells)) }
}

private struct RecentsTile: View {
    @ObservedObject var recents: RecentApps
    @ObservedObject private var icone = IconeApp.shared
    let cells: Int
    var body: some View {
        // colonne quante ne stanno davvero nella tessera (icona 30 + 8 di spazio), su due righe
        let inner = CGFloat(cells) * TileMetrics.cell + CGFloat(cells - 1) * TileMetrics.gap - 20
        let cols = max(1, Int((inner + 8) / 38))
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: cols), spacing: 4) {
            ForEach(recents.entries.prefix(cols * 2), id: \.bundle) { e in
                VStack(spacing: 2) {
                    if let i = icone.icona(bundle: e.bundle) {
                        Image(nsImage: i).resizable().frame(width: 28, height: 28)
                            .opacity(e.running ? 1 : 0.45)
                    }
                    Circle().fill(e.running ? Color.primary.opacity(0.6) : .clear).frame(width: 3, height: 3)
                }
                .help(e.running ? e.name : T("\(e.name), chiusa: clic per riaprire", "\(e.name), closed: click to reopen"))
                .onTapGesture { recents.open(e) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mac (batteria e salute)

struct MacWidget: IslandWidget {
    let id = "mac"
    var title: String { "Mac" }
    let symbol = "laptopcomputer"
    func body(cells: Int) -> AnyView { AnyView(MacTile(st: .shared, cells: cells)) }
}

private struct MacTile: View {
    @ObservedObject var st: SystemStatus
    let cells: Int
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if cells == 1 { battery(big: true).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        battery(big: true)
                        if let h = st.healthPercent {
                            Text(T("Salute \(h)%", "Health \(h)%") + (st.cycles.map { T(", \($0) cicli", ", \($0) cycles") } ?? ""))
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.55))
                        }
                        if let m = st.minutesLeft {
                            Text(T("\(m / 60) h \(m % 60) min rimasti", "\(m / 60) h \(m % 60) min left")).font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(Color.primary.opacity(0.55))
                        }
                    }
                    if cells >= 3 {
                        VStack(alignment: .leading, spacing: 5) {
                            meter("CPU", st.cpu)
                            meter("RAM", st.memoryUsed)
                            Text(T(String(format: "Disco %.0f GB liberi", st.diskFreeGB), String(format: "Disk %.0f GB free", st.diskFreeGB)))
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.55))
                            if st.thermal == .serious || st.thermal == .critical {
                                Label(T("Caldo", "Hot"), systemImage: "thermometer.high").font(.system(size: 10)).foregroundStyle(Night.amber)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear { st.refreshStats() }
        .onReceive(tick) { _ in st.refreshStats() }
    }

    private func battery(big: Bool) -> some View {
        let p = st.battery?.percent ?? 0
        let sym = st.battery?.pluggedIn == true ? "battery.100percent.bolt" : p <= 20 ? "battery.25percent" : p <= 50 ? "battery.50percent" : "battery.75percent"
        return HStack(spacing: 6) {
            Image(systemName: sym).font(.system(size: 16)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(p <= 20 && st.battery?.pluggedIn != true ? Night.red : Color.primary)
            Text(st.battery == nil ? "…" : "\(p)%").font(.system(size: big ? 22 : 15, weight: .light).monospacedDigit())
        }
    }

    private func meter(_ label: String, _ v: Double) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.primary.opacity(0.5)).frame(width: 26, alignment: .leading)
            Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(v > 0.85 ? Night.amber : Theme.accent).frame(width: g.size.width * v) } }
            Text("\(Int(v * 100))%").font(.system(size: 9).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.55)).frame(width: 28, alignment: .trailing)
        }
    }
}
