// Sistema: le comparse piccole dell'isola (notifiche, Non disturbare, batteria, salute del Mac, icone delle app).
// Quando il mouse non c'è l'isola resta ridotta e può spuntare per due o tre secondi, molto più piccola,
// solo per far vedere una cosa. La coda e le regole (PeekQueue, BatteryRules) stanno in isola-logica.swift.
//
// Fonti: Non disturbare da INFocusStatusCenter (permesso Focus, una volta), batteria da IOKit, calore e memoria
// dal sistema, notifiche leggendo il banner di macOS con l'Accessibilità (lo stesso permesso dei suoni).
// Il testo delle notifiche resta in memoria il tempo di mostrarlo, non si salva.
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Intents
import ApplicationServices

// MARK: - Interruttori

enum PeekPrefs {
    static func flag(_ key: Chiave, _ def: Bool = true) -> Bool { Impostazioni.object(key) as? Bool ?? def }
    static var notifications: Bool { get { flag(.isolaPeekNotif) } set { Impostazioni.set(newValue, .isolaPeekNotif) } }
    static var system: Bool { get { flag(.isolaPeekSystem) } set { Impostazioni.set(newValue, .isolaPeekSystem) } }
    static var ambient: Bool { get { flag(.isolaAmbient) } set { Impostazioni.set(newValue, .isolaAmbient) } }
}

// MARK: - Il centro delle comparse

final class PeekCenter: ObservableObject {
    static let shared = PeekCenter()
    @Published private(set) var current: PeekItem?
    var onChange: (() -> Void)?
    private var queue = PeekQueue()
    private var timer: Timer?

    func post(_ item: PeekItem) {
        DispatchQueue.main.async { [self] in
            queue.push(item, now: Date())
            refresh()
        }
    }

    private func refresh() {
        let c = queue.advance(now: Date())
        if c != current { current = c; onChange?() }
        if c != nil, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.refresh() }
        } else if c == nil {
            timer?.invalidate(); timer = nil
        }
    }
}

// MARK: - Cosa sa il Mac adesso (per le tessere e per le regole)

final class SystemStatus: ObservableObject {
    static let shared = SystemStatus()
    @Published private(set) var focus = false
    @Published private(set) var battery: BatterySnapshot?
    @Published private(set) var charging = false
    @Published private(set) var healthPercent: Int?
    @Published private(set) var cycles: Int?
    @Published private(set) var minutesLeft: Int?
    @Published private(set) var cpu = 0.0              // 0...1
    @Published private(set) var memoryUsed = 0.0       // 0...1
    @Published private(set) var diskFreeGB = 0.0
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    private var lastCPU: (Double, Double)?

    func setFocus(_ f: Bool) { if focus != f { focus = f } }

    /// La batteria da IOKit: percentuale, cavo, carica in corso e tempo rimasto.
    func readBattery() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int, let mx = d[kIOPSMaxCapacityKey] as? Int, mx > 0 else { continue }
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let snap = BatterySnapshot(percent: cap * 100 / mx, pluggedIn: ac)
            DispatchQueue.main.async {
                self.battery = snap
                self.charging = d[kIOPSIsChargingKey] as? Bool ?? false
                let t = d[kIOPSTimeToEmptyKey] as? Int ?? -1
                self.minutesLeft = t > 0 && !ac ? t : nil
            }
            return snap
        }
        return nil
    }

    /// Salute e cicli dal registro di sistema (AppleSmartBattery).
    func readHealth() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return }
        let design = (d["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0
        let raw = (d["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? (d["MaxCapacity"] as? NSNumber)?.doubleValue ?? 0
        let h = BatteryRules.healthPercent(rawMax: raw, design: design)
        let c = (d["CycleCount"] as? NSNumber)?.intValue
        DispatchQueue.main.async { self.healthPercent = h; self.cycles = c }
    }

    /// CPU, memoria e disco: si chiama quando la tessera Mac è visibile, non in continuo.
    func refreshStats() {
        // CPU: differenza dei tick fra due letture
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if r == KERN_SUCCESS {
            let busy = Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.3)
            let total = busy + Double(info.cpu_ticks.2)
            if let l = lastCPU, total > l.1 { cpu = min(1, max(0, (busy - l.0) / (total - l.1))) }
            lastCPU = (busy, total)
        }
        // memoria: pagine attive, bloccate e compresse su quelle totali
        var vm = vm_statistics64()
        var vcount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(vcount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vcount) } }
        if vr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            memoryUsed = min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
            diskFreeGB = Double(v) / 1_000_000_000
        }
        thermal = ProcessInfo.processInfo.thermalState
        _ = readBattery(); readHealth()
    }
}

// MARK: - Chi guarda e avvisa

final class SystemWatch {
    private var timers: [Timer] = []
    private var memorySource: DispatchSourceMemoryPressure?
    private var lastBattery: BatterySnapshot?
    private var psSource: CFRunLoopSource?
    private var lastFocus: Bool?
    private var observers: [NSObjectProtocol] = []
    private let notifications = NotificationWatcher()
    private var lastMemoryAlert = Date.distantPast

    func start() {
        let st = SystemStatus.shared
        // Non disturbare: il sistema dice solo se un Focus è acceso; il permesso si chiede una volta
        INFocusStatusCenter.default.requestAuthorization { _ in }
        timers.append(Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.pollFocus() })
        pollFocus()
        // batteria: il sistema avvisa a ogni cambio
        lastBattery = st.readBattery(); st.readHealth()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ref in
            guard let ref else { return }
            Unmanaged<SystemWatch>.fromOpaque(ref).takeUnretainedValue().batteryChanged()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode); psSource = src
        }
        // calore
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.thermalChanged() })
        // memoria sotto pressione
        let ms = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        ms.setEventHandler { [weak self] in self?.memoryPressure() }
        ms.resume(); memorySource = ms
        // disco quasi pieno, una volta ogni mezz'ora al massimo
        timers.append(Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.checkDisk() })
        // le icone delle app ogni tanto
        timers.append(Timer.scheduledTimer(withTimeInterval: 150, repeats: true) { [weak self] _ in self?.ambient() })
        notifications.start()
        // app aperte e chiuse: la loro icona sotto il notch, mai sulla barra dei menu
        let ws = NSWorkspace.shared.notificationCenter
        for (name, opened) in [(NSWorkspace.didLaunchApplicationNotification, true), (NSWorkspace.didTerminateApplicationNotification, false)] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.appEvent(a, opened: opened)
            })
        }
    }

    private func appEvent(_ a: NSRunningApplication, opened: Bool) {
        guard PeekPrefs.ambient, a.activationPolicy == .regular, let b = a.bundleIdentifier, b != Bundle.main.bundleIdentifier else { return }
        PeekCenter.shared.post(PeekItem(key: "app.\(b)", kind: "app", symbol: b, title: a.localizedName ?? b,
                                        detail: opened ? T("aperta", "opened") : T("chiusa", "closed"), priority: 30, duration: 2.2))
    }

    func stop() {
        timers.forEach { $0.invalidate() }; timers = []
        if let s = psSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode) }
        psSource = nil
        memorySource?.cancel(); memorySource = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        notifications.stop()
    }

    // MARK: Non disturbare

    /// Col permesso Focus lo dice il sistema; senza, si legge il file dei Focus (se Pulsar può leggerlo).
    private func pollFocus() {
        let on: Bool
        if INFocusStatusCenter.default.authorizationStatus == .authorized {
            on = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        } else {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
            guard let d = try? Data(contentsOf: url), let f = FocusParse.active(d) else { return }
            on = f
        }
        SystemStatus.shared.setFocus(on)
        defer { lastFocus = on }
        guard let prev = lastFocus, prev != on, PeekPrefs.notifications else { return }
        PeekCenter.shared.post(PeekItem(key: "focus", kind: "focus", symbol: on ? "moon.fill" : "moon", title: on ? T("Non disturbare", "Do Not Disturb") : T("Notifiche attive", "Notifications on"),
                                        detail: "", priority: 60, duration: 2.4))
    }

    // MARK: batteria e salute

    private func batteryChanged() {
        guard let now = SystemStatus.shared.readBattery() else { return }
        let events = BatteryRules.events(from: lastBattery, to: now)
        lastBattery = now
        guard PeekPrefs.system else { return }
        for e in events {
            let (sym, title): (String, String) = {
                switch e {
                case "plugged": return ("bolt.fill", T("In carica", "Charging"))
                case "unplugged": return ("battery.100", T("A batteria", "On battery"))
                case "low10": return ("battery.0percent", T("Batteria quasi scarica", "Battery almost empty"))
                case "low20": return ("battery.25percent", T("Batteria al 20%", "Battery at 20%"))
                default: return ("battery.100percent", T("Carica completa", "Fully charged"))
                }
            }()
            PeekCenter.shared.post(PeekItem(key: "battery.\(e)", kind: "battery", symbol: sym, title: title, detail: "\(now.percent)%",
                                            priority: e.hasPrefix("low") ? 80 : 55, duration: e.hasPrefix("low") ? 4 : 2.6))
        }
    }

    // MARK: salute del Mac

    private func thermalChanged() {
        let t = ProcessInfo.processInfo.thermalState
        SystemStatus.shared.refreshStats()
        guard PeekPrefs.system, t == .serious || t == .critical else { return }
        PeekCenter.shared.post(PeekItem(key: "thermal", kind: "health", symbol: "thermometer.high",
                                        title: t == .critical ? T("Il Mac è molto caldo", "Your Mac is very hot") : T("Il Mac è caldo", "Your Mac is hot"),
                                        detail: "", priority: 75, duration: 4))
    }

    private func memoryPressure() {
        guard PeekPrefs.system, Date().timeIntervalSince(lastMemoryAlert) > 600 else { return }
        lastMemoryAlert = Date()
        PeekCenter.shared.post(PeekItem(key: "memory", kind: "health", symbol: "memorychip", title: T("Memoria sotto pressione", "Memory under pressure"),
                                        detail: T("Chiudi qualche app", "Close some apps"), priority: 70, duration: 4))
    }

    private func checkDisk() {
        guard PeekPrefs.system else { return }
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard let v, Double(v) / 1_000_000_000 < 15 else { return }
        if let last = Impostazioni.object(.isolaDiskAlert) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        Impostazioni.set(Date(), .isolaDiskAlert)
        PeekCenter.shared.post(PeekItem(key: "disk", kind: "health", symbol: "internaldrive", title: T("Disco quasi pieno", "Disk almost full"),
                                        detail: String(format: "%.0f GB", Double(v) / 1_000_000_000), priority: 65, duration: 4))
    }

    // MARK: le app accese

    private func ambient() {
        guard PeekPrefs.ambient else { return }
        PeekCenter.shared.post(PeekItem(key: "apps", kind: "apps", symbol: "square.grid.2x2", title: "", detail: "", priority: 5, duration: 2.8))
    }
}

// MARK: - Notifiche: il banner di macOS letto con l'Accessibilità

private func notificationCallback(_ obs: AXObserver, _ el: AXUIElement, _ name: CFString, _ ref: UnsafeMutableRawPointer?) {
    guard let ref else { return }
    let w = Unmanaged<NotificationWatcher>.fromOpaque(ref).takeUnretainedValue()
    DispatchQueue.main.async { w.handle(el) }
}

final class NotificationWatcher {
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var retry: Timer?
    private var lastKey = ""
    private var lastAt = Date.distantPast

    func start() {
        retry = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.attach() }
        attach()
    }

    func stop() { retry?.invalidate(); retry = nil; detach() }

    private func detach() {
        if let o = observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        observer = nil; pid = 0
    }

    /// Si aggancia al processo del Centro Notifiche; se si riavvia o manca il permesso, riprova ogni 30 secondi.
    private func attach() {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) else { return }
        if observer != nil, app.processIdentifier == pid { return }
        detach()
        var o: AXObserver?
        guard AXObserverCreate(app.processIdentifier, notificationCallback, &o) == .success, let o else { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(o, el, kAXWindowCreatedNotification as CFString, ref)
        AXObserverAddNotification(o, el, kAXCreatedNotification as CFString, ref)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o; pid = app.processIdentifier
    }

    /// Un banner nuovo: si aspetta un attimo che sia disegnato, poi si leggono titolo e testo.
    func handle(_ el: AXUIElement) {
        guard PeekPrefs.notifications else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [self] in
            var texts: [String] = []
            var budget = 80
            AX.texts(el, depth: 9, into: &texts, budget: &budget)
            let clean = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard let title = clean.first else { return }
            let body = clean.dropFirst().joined(separator: ". ")
            let key = title + "|" + body
            if key == lastKey, Date().timeIntervalSince(lastAt) < 3 { return }
            lastKey = key; lastAt = Date()
            PeekCenter.shared.post(PeekItem(key: "notif", kind: "notification", symbol: "bell.badge.fill", title: String(title.prefix(40)),
                                            detail: String(body.prefix(70)), priority: 85, duration: 3.6))
            NotificationLog.shared.add(title: String(title.prefix(60)), body: String(body.prefix(160)))
        }
    }
}

enum AX {
    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func string(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }
    static func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

    /// I testi di un albero, in ordine: valore, titolo o descrizione dei campi di testo.
    static func texts(_ el: AXUIElement, depth: Int, into out: inout [String], budget: inout Int) {
        guard depth > 0, budget > 0 else { return }
        budget -= 1
        if string(el, kAXRoleAttribute) == kAXStaticTextRole {
            if let t = string(el, kAXValueAttribute) ?? string(el, kAXTitleAttribute) ?? string(el, kAXDescriptionAttribute) { out.append(t) }
        }
        for c in children(el) { texts(c, depth: depth - 1, into: &out, budget: &budget) }
    }
}

// MARK: - La vista della comparsa

struct PeekView: View {
    let item: PeekItem
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: notchHeight)
            Group {
                if item.kind == "apps" { AppIconsRow() }
                else if item.kind == "app" { AppEventRow(item: item) }
                else if item.kind == "muta" { MutaPeekRiga(item: item) }      // 19/10: resoconto di Muta con Annulla e Mostra
                else {
                    // 26/10, l'autore: "il notch non è adattato". Una notifica lunga usciva dalla forma: la campanella tagliata
                    // a sinistra e il sottotitolo oltre il bordo destro. Ora margini veri dentro la forma, la larghezza la
                    // misura width(_:notch:) sul testo vero, e oltre il massimo si tronca coi puntini, prima il sottotitolo.
                    HStack(spacing: Self.stacco) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tint).symbolRenderingMode(.hierarchical)
                            .frame(width: Self.icona)
                        Text(item.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        if !item.detail.isEmpty {
                            Text(item.detail).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, Self.margine)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tint: Color {
        switch item.kind {
        case "health": return Night.amber
        case "battery": return item.priority >= 80 ? Night.red : Night.green
        case "focus": return Color(red: 0.62, green: 0.60, blue: 0.95)
        default: return .primary
        }
    }

    static let margine: CGFloat = 16, icona: CGFloat = 14, stacco: CGFloat = 8
    /// Oltre questa larghezza la comparsa non cresce più: il testo si tronca dentro.
    static let massimo: CGFloat = 440

    /// La larghezza vera di una riga di testo, col carattere che usa la vista.
    static func misura(_ s: String, _ size: CGFloat, _ peso: NSFont.Weight) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: peso)]).width)
    }

    /// Pura nel calcolo: icona, titolo e sottotitolo misurati, più i margini; mai più stretta del notch, mai oltre il massimo.
    static func larghezzaRiga(titolo: String, dettaglio: String, icona: CGFloat, notch: CGFloat) -> CGFloat {
        var w = 2 * margine + icona + stacco + misura(titolo, 11.5, .medium)
        if !dettaglio.isEmpty { w += stacco + misura(dettaglio, 11, .regular) }
        return min(massimo, max(notch + 20, w))
    }

    /// Larghezza che serve alla comparsa (prima era stimata contando i caratteri, e con testi lunghi sbagliava).
    static func width(_ item: PeekItem, notch: CGFloat) -> CGFloat {
        switch item.kind {
        case "apps": return max(notch + 20, CGFloat(AppIconsRow.apps().count) * 26 + 40)
        case "muta": return MutaPeekRiga.larghezza(item, notch: notch)
        case "app": return larghezzaRiga(titolo: item.title, dettaglio: item.detail, icona: 18, notch: notch)
        default: return larghezzaRiga(titolo: item.title, dettaglio: item.detail, icona: icona, notch: notch)
        }
    }
}

/// Un'app appena aperta o chiusa: la sua icona con un saltello, nome e stato. In `symbol` c'è il bundle.
struct AppEventRow: View {
    let item: PeekItem
    @ObservedObject private var icone = IconeApp.shared
    @State private var up = false
    var body: some View {
        HStack(spacing: 8) {
            if let i = icone.icona(bundle: item.symbol) {
                Image(nsImage: i).resizable().frame(width: 18, height: 18)
                    .offset(y: up ? -3 : 0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.45), value: up)
            }
            Text(item.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                .truncationMode(.tail).layoutPriority(1)
            Text(item.detail).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, PeekView.margine)
        .onAppear { up = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { up = false } }
    }
}

/// Le app accese in fila, a ondate: ogni icona fa un piccolo salto dopo la precedente.
struct AppIconsRow: View {
    static func apps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.icon != nil }
            .prefix(7).map { $0 }
    }
    @State private var up = false
    var body: some View {
        let list = Self.apps()
        HStack(spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.element.processIdentifier) { i, app in
                Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 20, height: 20)
                    .offset(y: up ? -3 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.5).delay(Double(i) * 0.07), value: up)
            }
        }
        .onAppear { up = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { up = false } }
    }
}


/// 13/10/2026, l'autore: "nel Launchpad metti le notifiche a destra, con la possibilità di togliere quelle già viste".
/// Le ultime notifiche lette dai banner (qui sopra), per la colonna della griglia ⌘4. Solo in memoria, mai su disco,
/// come il resto del testo delle notifiche. Una notifica diventa "vista" quando si chiude la griglia dopo averla avuta davanti.
final class NotificationLog: ObservableObject {
    static let shared = NotificationLog()
    struct Item: Identifiable, Equatable { let id = UUID(); let title: String; let body: String; let date: Date; var seen = false }
    @Published private(set) var items: [Item] = []
    private let limit = 30

    func add(title: String, body: String) {
        DispatchQueue.main.async { [self] in
            items.insert(Item(title: title, body: body, date: Date()), at: 0)
            if items.count > limit { items.removeLast(items.count - limit) }
        }
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    func markSeen() { guard items.contains(where: { !$0.seen }) else { return }; for i in items.indices { items[i].seen = true } }
    func clearSeen() { items.removeAll { $0.seen } }
    var hasSeen: Bool { items.contains { $0.seen } }
}
