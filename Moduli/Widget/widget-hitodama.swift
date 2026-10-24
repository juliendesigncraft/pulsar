// Tessere prese dall'isola di Hitodama (12/10/2026, reel di otism_dev "This is not linux"): le schede Controls, Stats,
// Power e, da Spazio, il tempo di utilizzo. Le schede di Hitodama qui diventano tessere, come il resto dell'isola.
// l'autore: "io non vedo le nuove cose che vedo qua"; "così come un widget per tempo di utilizzo". Gli sfondi no.
import SwiftUI
import AppKit

// MARK: - Controlli (al posto dei pulsanti a sinistra del notch, che ora sono la stella)

struct ControlsWidget: IslandWidget {
    let id = "controls"
    var title: String { T("Controlli", "Controls") }
    let symbol = "switch.2"
    weak var model: IslandModel?
    func body(cells: Int) -> AnyView { AnyView(ControlsTile(model: model, sys: .shared, cells: cells)) }
}

/// Wi-Fi e Bluetooth: stato letto ogni tanto, cambiato con i comandi di sistema (niente permessi nuovi).
final class SysToggles: ObservableObject {
    static let shared = SysToggles()
    @Published private(set) var wifi: Bool?
    @Published private(set) var bluetooth: Bool?
    private let q = DispatchQueue(label: "pulsar.toggles")
    private lazy var wifiPort: String? = {
        let out = Self.run("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = out.components(separatedBy: "\n")
        for (i, l) in lines.enumerated() where l.contains("Wi-Fi") || l.contains("AirPort") {
            if i + 1 < lines.count, let r = lines[i + 1].range(of: "Device: ") { return String(lines[i + 1][r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }()
    // IOBluetooth espone l'interruttore come funzione C non documentata: si cerca a runtime, se manca il tasto si spegne
    private typealias GetBT = @convention(c) () -> Int32
    private typealias SetBT = @convention(c) (Int32) -> Void
    private lazy var bt: (GetBT, SetBT)? = {
        guard let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let g = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState"), let s = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") else { return nil }
        return (unsafeBitCast(g, to: GetBT.self), unsafeBitCast(s, to: SetBT.self))
    }()

    func refresh() {
        q.async { [self] in
            let w = wifiPort.map { Self.run("/usr/sbin/networksetup", ["-getairportpower", $0]).contains(": On") }
            let b = bt.map { $0.0() != 0 }
            DispatchQueue.main.async { self.wifi = w; self.bluetooth = b }
        }
    }
    func setWifi(_ on: Bool) {
        wifi = on
        q.async { [self] in if let p = wifiPort { _ = Self.run("/usr/sbin/networksetup", ["-setairportpower", p, on ? "on" : "off"]) } }
    }
    func setBluetooth(_ on: Bool) {
        bluetooth = on
        q.async { [self] in bt?.1(on ? 1 : 0) }
    }
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let d = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }
}

private struct ControlsTile: View {
    weak var model: IslandModel?
    @ObservedObject var sys: SysToggles
    let cells: Int
    var body: some View {
        let items: [(String, String, Bool?, () -> Void)] = [
            ("wifi", "Wi-Fi", sys.wifi, { sys.setWifi(!(sys.wifi ?? true)) }),
            ("dot.radiowaves.left.and.right", "Bluetooth", sys.bluetooth, { sys.setBluetooth(!(sys.bluetooth ?? true)) }),
            ("circle.lefthalf.filled", T("Tema", "Theme"), nil, { model?.toggleTheme?() }),
            ("speaker.wave.2", T("Volume", "Volume"), nil, {
                if let d = model?.dial, d.enabled, let it = d.soundItem { EdgeDock.shared.reveal(it, hideAfter: 4) } }),
            ("sun.max", T("Luce", "Light"), nil, {
                if let d = model?.dial, d.lightEnabled, let it = d.lightItem { EdgeDock.shared.reveal(it, hideAfter: 4) } }),
            ("square.grid.3x3", T("App", "Apps"), nil, { model?.openGrid?() }),
            ("gearshape", T("Impostazioni", "Settings"), nil, { IslandActions.settings() }),
            ("dot.radiowaves.up.forward", "AirDrop", nil, { IslandActions.airDrop() }),
        ]
        // solo icone (regola "meno testo, più icone"): il nome è nel suggerimento al passaggio
        let n = cells >= 3 ? 8 : cells == 2 ? 6 : 4
        let cols = n / 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
            ForEach(Array(items.prefix(n).enumerated()), id: \.offset) { _, it in
                ControlChip(symbol: it.0, label: it.1, on: it.2, action: it.3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)      // centrata in altezza (l'autore: "sotto c'è più spazio che sopra")
        .onAppear { sys.refresh() }
    }
}

/// Cinque LED in fila: blu-grafite come la griglia del notch, con la testa chiara che va e torna.
struct LEDStrip: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Leggera.on)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let head = 2 + 2 * sin(t * 2.2)                         // da 0 a 4 e ritorno, morbido
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    let w = max(0, 1 - abs(Double(i) - head) / 1.4)
                    ZStack {
                        Circle().fill(DotColors.base.opacity(0.7))
                        Circle().fill(DotColors.head.opacity(w * 0.95))
                    }
                    .frame(width: 2.6, height: 2.6)
                    .shadow(color: DotColors.head.opacity(w * 0.6), radius: 2)
                }
            }
        }
        .frame(height: 3)
    }
}

private struct ControlChip: View {
    let symbol: String
    let label: String
    let on: Bool?
    let action: () -> Void
    @State private var over = false
    var body: some View {
        Button(action: action) {
            // 12/10 sera: provate le icone a puntini, bocciate ("non si capisce niente"): simboli di sistema come prima.
            // Acceso = sotto l'icona una fila di LED con la luce che corre (l'autore: "un'illuminazione led quando sono attivi")
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(on == false ? 0.4 : 0.9))
                if on == true { LEDStrip() }
            }
            .frame(maxWidth: .infinity).frame(height: 35)        // due file da 35 + 6 = 76: riempiono la tessera, sopra e sotto uguali
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(on == true ? Volta.a2.opacity(0.24) : over ? Volta.pill : Volta.card2))   // 17/10: toni della Casa
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .help(label)
    }
}

// MARK: - Energia

struct PowerWidget: IslandWidget {
    let id = "power"
    var title: String { T("Energia", "Power") }
    let symbol = "power"
    func body(cells: Int) -> AnyView { AnyView(PowerTile(cells: cells)) }
}

private struct PowerTile: View {
    let cells: Int
    var body: some View {
        let all: [(String, String, () -> Void)] = [
            ("lock", T("Blocca", "Lock"), { Power.lock() }),
            ("moon", T("Stop", "Sleep"), { Power.run("/usr/bin/pmset", ["sleepnow"]) }),
            ("arrow.clockwise", T("Riavvia", "Restart"), { Power.ask(T("Riavviare il Mac?", "Restart your Mac?"), "restart") }),
            ("power", T("Spegni", "Shut down"), { Power.ask(T("Spegnere il Mac?", "Shut down your Mac?"), "shut down") }),
        ]
        let n = cells == 1 ? 2 : 4
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cells >= 3 ? 4 : 2), spacing: 6) {
            ForEach(Array(all.prefix(n).enumerated()), id: \.offset) { _, a in
                Button(action: a.2) {
                    VStack(spacing: 3) {
                        Image(systemName: a.0).font(.system(size: 13, weight: .medium))
                        if cells > 1 { Text(a.1).font(.system(size: 9.5)) }
                    }
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(maxWidth: .infinity).frame(height: cells > 1 ? 44 : 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Volta.card2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(a.1)
            }
        }
    }
}

enum Power {
    static func run(_ p: String, _ a: [String]) { DispatchQueue.global().async { _ = SysToggles.run(p, a) } }
    static func lock() {
        let cg = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: cg) { run(cg, ["-suspend"]) } else { run("/usr/bin/pmset", ["displaysleepnow"]) }
    }
    /// Riavvia e spegni chiedono sempre conferma: un clic sbagliato sull'isola non deve chiudere il lavoro.
    static func ask(_ msg: String, _ verb: String) {
        let a = NSAlert()
        a.messageText = msg
        a.informativeText = T("Le app aperte verranno chiuse.", "Open apps will be closed.")
        a.addButton(withTitle: T("Sì", "Yes")); a.addButton(withTitle: T("Annulla", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        runAppleScript("tell application \"System Events\" to \(verb)")
    }
}

// MARK: - Prestazioni (la scheda Stats di Hitodama)

struct StatsWidget: IslandWidget {
    let id = "stats"
    var title: String { T("Prestazioni", "Stats") }
    let symbol = "gauge.with.dots.needle.50percent"
    func body(cells: Int) -> AnyView { AnyView(StatsTile(st: .shared, perf: .shared, cells: cells)) }
}

/// Le app che usano più memoria e la velocità della rete. Solo mentre la tessera si vede.
final class PerfMonitor: ObservableObject {
    static let shared = PerfMonitor()
    struct AppUse: Identifiable { var id: String { name }; var name: String; var mb: Double }
    @Published private(set) var top: [AppUse] = []
    @Published private(set) var down: Double = 0      // byte al secondo
    @Published private(set) var up: Double = 0
    private var timer: Timer?
    private var viewers = 0
    private var last: (Date, UInt64, UInt64)?
    private let q = DispatchQueue(label: "pulsar.perf")

    func watch(_ on: Bool) {
        viewers = max(0, viewers + (on ? 1 : -1))
        if viewers > 0, timer == nil {
            sample()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        } else if viewers == 0 { timer?.invalidate(); timer = nil; last = nil }
    }

    private func sample() {
        q.async { [self] in
            // memoria per app: somma dei processi dentro lo stesso .app
            var per: [String: Double] = [:]
            for l in SysToggles.run("/bin/ps", ["-axo", "rss=,comm="]).split(separator: "\n") {
                let parts = l.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let kb = Double(parts[0]) else { continue }
                let path = String(parts[1])
                guard let r = path.range(of: ".app/") else { continue }
                let name = URL(fileURLWithPath: String(path[..<r.lowerBound])).lastPathComponent
                per[name, default: 0] += kb / 1024
            }
            let top = per.sorted { $0.value > $1.value }.prefix(4).map { AppUse(name: $0.key, mb: $0.value) }
            // rete: byte entrati e usciti su tutte le interfacce vere
            var rin: UInt64 = 0, rout: UInt64 = 0
            var seen = Set<String>()
            for l in SysToggles.run("/usr/sbin/netstat", ["-ibn"]).split(separator: "\n").dropFirst() {
                let c = l.split(separator: " ", omittingEmptySubsequences: true)
                guard c.count >= 10, c[0].hasPrefix("en"), seen.insert(String(c[0])).inserted,
                      let i = UInt64(c[c.count - 5]), let o = UInt64(c[c.count - 2]) else { continue }
                rin += i; rout += o
            }
            let now = Date()
            var d = 0.0, u = 0.0
            if let (t, i0, o0) = last, rin >= i0, rout >= o0 {
                let dt = now.timeIntervalSince(t)
                d = Double(rin - i0) / dt; u = Double(rout - o0) / dt
            }
            last = (now, rin, rout)
            DispatchQueue.main.async { self.top = top; self.down = d; self.up = u }
        }
    }

    static func speed(_ b: Double) -> String {
        b > 1_000_000 ? String(format: "%.1f MB/s", b / 1_000_000) : String(format: "%.0f KB/s", b / 1000)
    }
}

private struct StatsTile: View {
    @ObservedObject var st: SystemStatus
    @ObservedObject var perf: PerfMonitor
    let cells: Int
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ring(st.memoryUsed, "RAM")
            if cells >= 2 { ring(st.cpu, "CPU") }
            if cells >= 3 {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(perf.top.prefix(cells >= 4 ? 4 : 3)) { a in
                        HStack(spacing: 6) {
                            Text(a.name).font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(a.mb > 1024 ? String(format: "%.1f GB", a.mb / 1024) : String(format: "%.0f MB", a.mb))
                                .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.55))
                        }
                    }
                    HStack(spacing: 8) {
                        Label(PerfMonitor.speed(perf.down), systemImage: "arrow.down").font(.system(size: 9.5).monospacedDigit())
                        Label(PerfMonitor.speed(perf.up), systemImage: "arrow.up").font(.system(size: 9.5).monospacedDigit())
                    }
                    .foregroundStyle(Color.primary.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { st.refreshStats(); perf.watch(true) }
        .onDisappear { perf.watch(false) }
        .onReceive(tick) { _ in st.refreshStats() }
    }

    private func ring(_ v: Double, _ label: String) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
            Circle().trim(from: 0, to: v).stroke(v > 0.85 ? Night.amber : Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(v * 100))%").font(.system(size: 11, weight: .medium).monospacedDigit())
                Text(label).font(.system(size: 8)).foregroundStyle(Color.primary.opacity(0.5))
            }
        }
        .frame(width: 46, height: 46)
        .animation(.easeOut(duration: 0.6), value: v)
    }
}

// MARK: - Effetti del meteo nella tessera (12/10/2026, tarda sera)
// l'autore: "magari ci aggiungi degli effetti in base al meteo". Dietro al testo, a tutta tessera, leggeri: pioggia che
// cade in diagonale, neve che scende ondeggiando, nuvole che passano, nebbia a bande, lampo raro col temporale,
// sole che respira di giorno, stelle che brillano di notte. Codici WMO di Open-Meteo.

struct TileWeatherFX: View {
    /// 13/10: spenti nelle riprese dei reel
    static var off = false
    let code: Int
    let isDay: Bool
    var body: some View {
        if Self.off { Color.clear } else { fx }
    }

    private var fx: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Leggera.on)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, sz in
                let ink = Theme.light ? Color(red: 0.25, green: 0.3, blue: 0.4) : Color.white
                switch code {
                case 51...67, 80...82:                       // pioggia
                    let heavy = code >= 63 || code >= 81
                    for i in 0..<(heavy ? 38 : 24) {
                        let s = Double(i) * 37.13
                        let x = (s.truncatingRemainder(dividingBy: 1) + Double(i) / 24).truncatingRemainder(dividingBy: 1) * (sz.width + 30)
                        let y = ((t * (heavy ? 1.6 : 1.1) + s / 13).truncatingRemainder(dividingBy: 1)) * (sz.height + 20) - 10
                        var p = Path(); p.move(to: CGPoint(x: x - y * 0.25, y: y)); p.addLine(to: CGPoint(x: x - y * 0.25 - 3, y: y + 10))
                        g.stroke(p, with: .color(ink.opacity(0.22)), lineWidth: 1)
                    }
                case 71...77, 85...86:                       // neve
                    for i in 0..<26 {
                        let s = Double(i) * 0.6180339 * 97
                        let y = ((t * 0.18 + s / 7).truncatingRemainder(dividingBy: 1)) * (sz.height + 10) - 5
                        let x = (s.truncatingRemainder(dividingBy: 1)) * sz.width + sin(t * 1.2 + s) * 6
                        let r = 1.2 + (s.truncatingRemainder(dividingBy: 0.5)) * 2
                        g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(ink.opacity(0.45)))
                    }
                case 95...99:                                // temporale: pioggia fitta e un lampo ogni tanto
                    let flash = max(0, 1 - (t.truncatingRemainder(dividingBy: 7.0)) / 0.25)
                    if flash > 0 { g.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(ink.opacity(0.18 * flash))) }
                    for i in 0..<34 {
                        let s = Double(i) * 37.13
                        let x = (Double(i) / 34) * (sz.width + 30)
                        let y = ((t * 1.7 + s / 13).truncatingRemainder(dividingBy: 1)) * (sz.height + 20) - 10
                        var p = Path(); p.move(to: CGPoint(x: x - y * 0.3, y: y)); p.addLine(to: CGPoint(x: x - y * 0.3 - 3, y: y + 11))
                        g.stroke(p, with: .color(ink.opacity(0.22)), lineWidth: 1)
                    }
                case 45, 48:                                  // nebbia
                    for i in 0..<4 {
                        let y = sz.height * (0.25 + Double(i) * 0.18)
                        let x = sin(t * 0.25 + Double(i)) * 20 - 20
                        g.fill(Path(roundedRect: CGRect(x: x, y: y, width: sz.width + 40, height: 7), cornerRadius: 4), with: .color(ink.opacity(0.08)))
                    }
                case 1...3:                                   // poco nuvoloso: niente forme (le ellissi bocciate), solo il sole di giorno
                    if isDay { sun(g, sz, t, 0.5) }
                default:                                      // sereno
                    if isDay { sun(g, sz, t, 1) }
                    else {
                        for i in 0..<18 {
                            let s = Double(i) * 0.6180339
                            let x = (s * 13).truncatingRemainder(dividingBy: 1) * sz.width
                            let y = (s * 7).truncatingRemainder(dividingBy: 1) * sz.height * 0.8
                            let a = 0.15 + 0.4 * (0.5 + 0.5 * sin(t * (0.8 + s) + Double(i)))
                            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(ink.opacity(a)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Un alone caldo che respira nell'angolo in alto a destra.
    private func sun(_ g: GraphicsContext, _ sz: CGSize, _ t: Double, _ k: Double) {
        let r = sz.height * (0.9 + 0.08 * sin(t * 0.7))
        let c = CGPoint(x: sz.width - 10, y: 6)
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.45).opacity(0.22 * k), .clear]),
                                     center: c, startRadius: 0, endRadius: r))
    }
}
