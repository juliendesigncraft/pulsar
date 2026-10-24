// Pulsar — GHIERA (06/10/2026): una ghiera rotonda che esce dal bordo SINISTRO (a destra c'è già la colonna dell'Agente).
// Riferimento: reel di will.geez (Instagram DcVb2U9vcvZ), ghiera scura con le tacche che si accendono.
// Tre modi: Volume (uscita del Mac), Mix (volume per app, più app insieme) e Timer.
// Il volume per app usa i tap audio di macOS (14.4+), lo stesso metodo di Vorssaint, senza driver:
// il suono dell'app viene catturato, zittito all'origine e rimandato all'uscita col volume scelto.
// Quando un'app torna al 100% il tap si chiude e il suono riprende la sua strada normale.

import AppKit
import SwiftUI
import CoreAudio
import AudioToolbox
import Accelerate
import Combine

// MARK: - Core Audio, piccoli aiuti

private let sysObject = AudioObjectID(kAudioObjectSystemObject)

private func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func caValue<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ fallback: T) -> T {
    var a = addr(sel, scope)
    var v = fallback
    var size = UInt32(MemoryLayout<T>.size)
    let err = withUnsafeMutablePointer(to: &v) { AudioObjectGetPropertyData(obj, &a, 0, nil, &size, $0) }
    return err == noErr ? v : fallback
}

private func caString(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
    var a = addr(sel)
    var ref: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ref) == noErr, let s = ref else { return nil }
    return s.takeRetainedValue() as String
}

private func caList(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = addr(sel)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

enum SystemVolume {
    static var device: AudioObjectID { caValue(sysObject, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0)) }
    static var uid: String? { caString(device, kAudioDevicePropertyDeviceUID) }

    static var level: Float {
        get { caValue(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput, Float32(0)) }
        set {
            var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
            var v = Float32(max(0, min(1, newValue)))
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            if v > 0 && muted { muted = false }
        }
    }
    static var muted: Bool {
        get { caValue(device, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, UInt32(0)) != 0 }
        set {
            var a = addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
            var v: UInt32 = newValue ? 1 : 0
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        }
    }
}

// MARK: - Un tap per app

/// Il guadagno viene letto dal thread audio: una scatola condivisa, scritta dal main thread.
private final class GainBox { var value: Float = 1 }

private final class AppTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let box = GainBox()
    let processes: [AudioObjectID]
    var gain: Float { get { box.value } set { box.value = newValue } }

    init?(processes: [AudioObjectID], outputUID: String, gain: Float) {
        self.processes = processes
        box.value = gain
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped     // l'app non suona più da sola: suona solo quello che rimandiamo noi
        desc.isPrivate = true
        desc.name = "Pulsar Ghiera"
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return nil }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pulsar Ghiera",
            kAudioAggregateDeviceUIDKey: "pulsar.ghiera.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { stop(); return nil }

        let box = self.box
        let queue = DispatchQueue(label: "pulsar.ghiera.io", qos: .userInteractive)
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inInput, _, outOutput, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            let outs = UnsafeMutableAudioBufferListPointer(outOutput)
            var g = box.value
            for i in 0..<outs.count {
                let ob = outs[i]
                guard let od = ob.mData else { continue }
                let o = od.assumingMemoryBound(to: Float.self)
                let outN = Int(ob.mDataByteSize) / 4
                guard ins.count > 0, let idata = ins[min(i, ins.count - 1)].mData else { memset(od, 0, Int(ob.mDataByteSize)); continue }
                let ib = ins[min(i, ins.count - 1)]
                let inp = idata.assumingMemoryBound(to: Float.self)
                let inN = Int(ib.mDataByteSize) / 4
                let ic = max(1, Int(ib.mNumberChannels)), oc = max(1, Int(ob.mNumberChannels))
                if ic == oc {
                    let n = min(inN, outN)
                    vDSP_vsmul(inp, 1, &g, o, 1, vDSP_Length(n))
                    if outN > n { memset(o + n, 0, (outN - n) * 4) }
                } else {
                    let frames = min(inN / ic, outN / oc)
                    for f in 0..<frames { for c in 0..<oc { o[f * oc + c] = inp[f * ic + min(c, ic - 1)] * g } }
                    if outN > frames * oc { memset(o + frames * oc, 0, (outN - frames * oc) * 4) }
                }
            }
        }
        guard err == noErr, procID != nil, AudioDeviceStart(aggID, procID) == noErr else { stop(); return nil }
    }

    func stop() {
        if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }
    deinit { stop() }
}

// MARK: - Le app che suonano

struct MixApp: Identifiable, Equatable {
    let id: String                 // bundle dell'app "madre" (Chrome, non Chrome Helper)
    let name: String
    let icon: NSImage?
    var processes: [AudioObjectID]
    var playing: Bool
    static func == (a: MixApp, b: MixApp) -> Bool { a.id == b.id && a.processes == b.processes && a.playing == b.playing }
}

enum DialMode: String, CaseIterable {
    case volume, mix, timer
    var symbol: String {
        switch self { case .volume: return "speaker.wave.2.fill"; case .mix: return "slider.vertical.3"; case .timer: return "timer" }
    }
    var label: String {
        switch self { case .volume: return "VOLUME"; case .mix: return "MIX"; case .timer: return "TIMER" }
    }
}

final class DialStore: ObservableObject {
    @Published var mode: DialMode = DialMode(rawValue: Impostazioni.string(.dialMode) ?? "") ?? .volume {
        didSet {
            Impostazioni.set(mode.rawValue, .dialMode)
        }
    }
    @Published var volume: Float = SystemVolume.level
    @Published var muted: Bool = SystemVolume.muted
    @Published var apps: [MixApp] = []
    @Published var gains: [String: Float] = (Impostazioni.dictionary(.dialGains) as? [String: Float]) ?? [:]
    @Published var linked: Set<String> = Set(Impostazioni.stringArray(.dialLinked) ?? [])
    @Published var tapError = false
    // timer
    @Published var timerMinutes: Int = Impostazioni.object(.dialTimer) as? Int ?? 25
    @Published var timerEnd: Date?
    @Published var now = Date()
    var onTimerDone: (() -> Void)?

    private var taps: [String: AppTap] = [:]
    private var outputUID: String? = SystemVolume.uid
    private var poll: Timer?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func gain(_ id: String) -> Float { gains[id] ?? 1 }

    func start() {
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        listen(sysObject, addr(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in self?.outputChanged() }
        listen(sysObject, addr(kAudioHardwarePropertyProcessObjectList)) { [weak self] in self?.refresh() }
        listenVolume()
    }

    func stop() {
        poll?.invalidate(); poll = nil
        for (obj, a, b) in listeners { var a = a; AudioObjectRemovePropertyListenerBlock(obj, &a, .main, b) }
        listeners = []
        taps.values.forEach { $0.stop() }
        taps = [:]
    }

    private func listen(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ f: @escaping () -> Void) {
        var a = a
        let block: AudioObjectPropertyListenerBlock = { _, _ in f() }
        if AudioObjectAddPropertyListenerBlock(obj, &a, .main, block) == noErr { listeners.append((obj, a, block)) }
    }

    private func listenVolume() {
        let dev = SystemVolume.device
        listen(dev, addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)) { [weak self] in
            self?.volume = SystemVolume.level
        }
        listen(dev, addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)) { [weak self] in
            self?.muted = SystemVolume.muted
        }
    }

    private func tick() {
        if let end = timerEnd {
            now = Date()
            if now >= end { timerEnd = nil; onTimerDone?() }
        }
        refresh()
    }

    /// Cuffie, AirPods, altoparlanti: l'uscita è cambiata, i tap vanno rifatti sulla nuova.
    private func outputChanged() {
        outputUID = SystemVolume.uid
        volume = SystemVolume.level; muted = SystemVolume.muted
        for (obj, a, b) in listeners where obj != sysObject { var a = a; AudioObjectRemovePropertyListenerBlock(obj, &a, .main, b) }
        listeners.removeAll { $0.0 != sysObject }
        listenVolume()
        taps.values.forEach { $0.stop() }
        taps = [:]
        applyTaps()
    }

    /// Dimostrazione: app finte nel mixer (nomi neutri), al posto di quelle che suonano davvero.
    var demoApps: [MixApp]? { didSet { if let d = demoApps { apps = d } else { refresh() } } }

    /// Raggruppa i processi audio per app: Chrome Helper va sotto Chrome, WebKit sotto Safari.
    private var lastRefresh = Date.distantPast
    func refresh() {
        if let d = demoApps { if apps != d { apps = d }; return }
        // 13/10, Pulsar leggera: al massimo una volta ogni 3 secondi (prima: a ogni secondo e a ogni cambio dei processi audio)
        if Leggera.on, Date().timeIntervalSince(lastRefresh) < 3 { return }
        lastRefresh = Date()
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        var groups: [String: MixApp] = [:]
        for obj in caList(sysObject, kAudioHardwarePropertyProcessObjectList) {
            let pid = caValue(obj, kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, pid_t(-1))
            let bundle = caString(obj, kAudioProcessPropertyBundleID) ?? ""
            let playing = caValue(obj, kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal, UInt32(0)) != 0
            var owner: NSRunningApplication?
            if let app = regular.first(where: { $0.processIdentifier == pid }) { owner = app }
            else if let app = regular.first(where: { bundle.hasPrefix($0.bundleIdentifier! + ".") }) { owner = app }
            else if bundle.hasPrefix("com.apple.WebKit") { owner = regular.first { $0.bundleIdentifier == "com.apple.Safari" } }
            let id: String, name: String, icon: NSImage?
            if let o = owner { id = o.bundleIdentifier!; name = o.localizedName ?? id; icon = o.icon }
            else {
                guard !bundle.isEmpty, !bundle.hasPrefix("com.apple.") else { continue }   // suoni di sistema e demoni: fuori
                let ra = NSRunningApplication(processIdentifier: pid)
                id = bundle; name = ra?.localizedName ?? bundle.components(separatedBy: ".").last ?? bundle; icon = ra?.icon
            }
            var g = groups[id] ?? MixApp(id: id, name: name, icon: icon, processes: [], playing: false)
            g.processes.append(obj)
            g.playing = g.playing || playing
            groups[id] = g
        }
        // in lista: chi suona adesso, più chi ha un volume diverso dal 100% (così il cursore non sparisce in pausa)
        let shown = groups.values
            .filter { $0.playing || gain($0.id) != 1 || taps[$0.id] != nil }
            .sorted { ($0.playing ? 0 : 1, $0.name.lowercased()) < ($1.playing ? 0 : 1, $1.name.lowercased()) }
        if shown != apps { apps = shown }
        applyTaps(groups)
    }

    private var lastGroups: [String: MixApp] = [:]

    /// Un tap per ogni app sotto il 100%; al 100% il tap si chiude.
    private func applyTaps(_ groups: [String: MixApp]? = nil) {
        if let groups { lastGroups = groups }
        guard let uid = outputUID else { return }
        for (id, tap) in taps {
            let g = gain(id)
            let procs = lastGroups[id]?.processes.sorted()
            if g >= 0.999 || procs == nil || procs != tap.processes.sorted() { tap.stop(); taps[id] = nil }
        }
        for (id, app) in lastGroups where taps[id] == nil {
            let g = gain(id)
            guard g < 0.999, !app.processes.isEmpty else { continue }
            if let t = AppTap(processes: app.processes, outputUID: uid, gain: g) { taps[id] = t; tapError = false }
            else { tapError = true }
        }
    }

    func setGain(_ id: String, _ value: Float) {
        let v = max(0, min(1, value))
        gains[id] = v >= 0.995 ? nil : v
        Impostazioni.set(gains, .dialGains)
        if let t = taps[id] { t.gain = v; if v >= 0.995 { applyTaps() } } else { applyTaps() }
    }

    func toggleLink(_ id: String) {
        if linked.contains(id) { linked.remove(id) } else { linked.insert(id) }
        Impostazioni.set(Array(linked), .dialLinked)
    }

    /// Le app che la ghiera muove in modo Mix: quelle collegate, o tutte se non ne è collegata nessuna.
    var mixTargets: [MixApp] {
        let l = apps.filter { linked.contains($0.id) }
        return l.isEmpty ? apps : l
    }
    var mixLevel: Float {
        let t = mixTargets
        return t.isEmpty ? 1 : t.map { gain($0.id) }.reduce(0, +) / Float(t.count)
    }

    // il valore mostrato dalla ghiera, da 0 a 1
    var level: Double {
        switch mode {
        case .volume: return muted ? 0 : Double(volume)
        case .mix: return Double(mixLevel)
        case .timer:
            if let end = timerEnd { return max(0, end.timeIntervalSince(now)) / Double(timerMinutes * 60) }
            return Double(timerMinutes) / 60
        }
    }

    /// Rotella o trascinamento sulla ghiera: delta in "tacche" (40 per giro).
    func nudge(_ ticks: Double) {
        switch mode {
        case .volume: SystemVolume.level = volume + Float(ticks / 40); volume = SystemVolume.level; muted = SystemVolume.muted
        case .mix: for a in mixTargets { setGain(a.id, gain(a.id) + Float(ticks / 40)) }
        case .timer:
            guard timerEnd == nil else { return }
            timerMinutes = max(1, min(60, timerMinutes + Int(ticks.rounded())))
            Impostazioni.set(timerMinutes, .dialTimer)
        }
        objectWillChange.send()
    }

    /// Imposta un valore assoluto (trascinando sulla corona).
    func set(_ fraction: Double) {
        let f = max(0, min(1, fraction))
        switch mode {
        case .volume: SystemVolume.level = Float(f); volume = SystemVolume.level; muted = SystemVolume.muted
        case .mix: for a in mixTargets { setGain(a.id, Float(f)) }
        case .timer:
            guard timerEnd == nil else { return }
            timerMinutes = max(1, Int((f * 60).rounded())); Impostazioni.set(timerMinutes, .dialTimer)
        }
        objectWillChange.send()
    }

    /// Il tocco al centro: volume e mix = muto sì/no, timer = parte o si ferma.
    func center() {
        switch mode {
        case .volume: SystemVolume.muted = !muted; muted = SystemVolume.muted
        case .mix:
            let t = mixTargets
            let allSilent = t.allSatisfy { gain($0.id) == 0 }
            // chiave dinamica dialUnmute.<id>: resta su UserDefaults.standard
            for a in t { setGain(a.id, allSilent ? (UserDefaults.standard.object(forKey: "dialUnmute.\(a.id)") as? Float ?? 1) : 0) }
            if !allSilent { for a in t { UserDefaults.standard.set(max(0.05, gains[a.id] ?? 1), forKey: "dialUnmute.\(a.id)") } }
        case .timer:
            if timerEnd == nil { timerEnd = Date().addingTimeInterval(Double(timerMinutes * 60)); now = Date() } else { timerEnd = nil }
        }
        objectWillChange.send()
    }
}

// MARK: - La ghiera

private enum Ghiera {
    static var mode: AgentMode { GhieraLook.shared.mode }
    static var light: Bool { mode == .bianco }
    /// Sfondo (11/10): colori semantici, chiari o scuri secondo lo sfondo dietro (lo decide colorScheme sulla radice)
    static var wall: Bool { mode == .sfondo }
    static var fg: Color { wall ? .primary : light ? Color(white: 0.08) : .white }
    static var t2: Color { fg.opacity(wall ? 0.62 : 0.56) }
    static var t3: Color { fg.opacity(wall ? 0.5 : light ? 0.45 : 0.34) }
    static var mint: Color {
        if wall { return Color(nsColor: WallpaperTint.shared.accent) }      // accento di sistema o dallo sfondo
        // 12/10, l'autore: "quel bianco o grafite chiaro mi piace molto come accento" (i puntini dell'Isola)
        if mode == .bianco { return Color(red: 0.30, green: 0.33, blue: 0.41) }   // White Matte: grafite
        return Color(red: 0.86, green: 0.88, blue: 0.94)    // Dark Matte (Notte, l'unico aspetto rimasto): bianco grafite chiaro
    }
    static var tickOff: Color { fg.opacity(light || wall ? 0.16 : 0.12) }
    static var sel: Color { wall ? mint.opacity(0.24) : light ? Color.black.opacity(0.08) : Night.sel }
    // 11/10: prima richiamava se stesso all'infinito negli aspetti scuri (crash alla prima app in MUTE)
    static var amber: Color { light ? Color(red: 0.75, green: 0.48, blue: 0.05) : wall ? Color(nsColor: .systemOrange) : Night.amber }
    static var scheme: ColorScheme { mode.scheme }
    static var face: AnyShapeStyle {
        switch mode {
        case .notte, .bianco: return AnyShapeStyle(LinearGradient(colors: [Night.barTop, Night.bar], startPoint: .top, endPoint: .bottom))
        case .sfondo: return AnyShapeStyle(Color.primary.opacity(0.06))
        }
    }
    static let mono = Font.system(size: 9, weight: .regular, design: .monospaced)
}

/// Il fondo del pannello secondo l'aspetto, sulla forma attaccata al bordo.
private struct GhieraSurface: ViewModifier {
    let mode: AgentMode
    @ObservedObject var edge: EdgeLook
    @ObservedObject var wall = WallpaperTint.shared
    @ObservedObject private var form: EdgeForm      // 21/10: si ridisegna anche quando la forma passa da attaccata a libera
    init(mode: AgentMode, edge: EdgeLook) { self.mode = mode; self.edge = edge; form = edge.form }
    func body(content: Content) -> some View {
        // 11/10: la forma segue il bordo dove sta (destra o sinistra), si stacca a goccia e si fonde con chi le sta accanto
        let shape = DockShape(r: DialView.r, look: edge)
        switch mode {
        // Dark e White Matte: fondo sulla scheda grafica (bordi.swift), così la goccia si deforma senza perdere fotogrammi
        case .notte, .bianco: content.background(DockLayerFill(r: DialView.r, look: edge, top: NSColor(edge.joinTop > 0.5 ? Night.bar : Night.barTop), bottom: NSColor(Night.bar)))
        case .sfondo: content.glassEffect(.regular.tint(Color(nsColor: wall.info(edge).veil)), in: shape)   // Liquid Glass + velo dello sfondo
        }
    }
}

/// Il disegno della ghiera, uguale per volume e luce.
struct RingFace: View {
    let level: Double
    let symbol: String
    let value: String
    let label: String
    let center: () -> Void
    let set: (Double) -> Void
    static let size: CGFloat = 148
    private let ticks = 40

    var body: some View {
        let lit = Int((max(0, min(1, level)) * Double(ticks)).rounded())
        // 12/10 sera: per volume e luce le tacche accese vanno verso l'azzurro di Spazio man mano che salgono
        let sale = ["speaker.wave.2.fill", "speaker.wave.2", "speaker.wave.1.fill", "speaker.wave.3.fill", "sun.max.fill", "sun.max", "light.max", "light.min"].contains(symbol)
        ZStack {
            Circle().fill(Ghiera.face)
            Circle().strokeBorder(Ghiera.fg.opacity(0.07), lineWidth: 1)
            ForEach(0..<ticks, id: \.self) { i in
                Capsule()
                    .fill(i < lit ? (sale ? Ghiera.mint.mix(with: DotColors.azzurro, by: Double(i) / Double(ticks - 1)) : Ghiera.mint)
                            .opacity(0.55 + 0.45 * Double(i) / Double(ticks)) : Ghiera.tickOff)
                    .frame(width: 3, height: i % 5 == 0 ? 12 : 9)
                    .offset(y: -RingFace.size / 2 + 15)
                    .rotationEffect(.degrees(Double(i) / Double(ticks) * 360))
            }
            .animation(.easeOut(duration: 0.25), value: lit)
            // il segno in cima, come il triangolino del riferimento
            Triangle().fill(Ghiera.mint).frame(width: 7, height: 6).offset(y: -RingFace.size / 2 + 4)
            Button(action: center) {
                VStack(spacing: 3) {
                    DotGlyph(kind: DotGlyph.kind(for: symbol), level: level).frame(width: 22, height: 22)   // 12/10: puntini come l'Isola
                    Text(value).font(.system(size: 24, weight: .regular)).monospacedDigit().foregroundStyle(Ghiera.fg)
                    Text(label).font(Ghiera.mono).tracking(1.4).foregroundStyle(Ghiera.t3)
                }
                .frame(width: 84, height: 84)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: RingFace.size, height: RingFace.size)
        .dragBlock(ring: true)           // 11/10: la corona resta della ghiera; dal centro la si può trascinare via
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 4).onChanged { g in
            // trascinare sulla corona: l'angolo dal punto più alto, in senso orario, è il valore
            let c = RingFace.size / 2
            let dx = g.location.x - c, dy = g.location.y - c
            guard hypot(dx, dy) > 42 else { return }
            var a = atan2(dx, -dy) / (2 * .pi)
            if a < 0 { a += 1 }
            set(a)
        })
    }

}

struct DialFace: View {
    @ObservedObject var store: DialStore
    static let size = RingFace.size

    var body: some View {
        RingFace(level: store.level, symbol: centerSymbol, value: value, label: store.mode.label,
                 center: { store.center() }, set: { store.set($0) })
    }

    private var centerSymbol: String {
        switch store.mode {
        case .volume: return store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .mix: return store.mixLevel == 0 ? "speaker.slash" : "slider.vertical.3"
        case .timer: return store.timerEnd == nil ? "play.fill" : "pause.fill"
        }
    }
    private var value: String {
        switch store.mode {
        case .volume: return store.muted ? "0" : "\(Int((store.volume * 100).rounded()))"
        case .mix: return "\(Int((store.mixLevel * 100).rounded()))"
        case .timer:
            guard let end = store.timerEnd else { return "\(store.timerMinutes):00" }
            let s = max(0, Int(end.timeIntervalSince(store.now).rounded()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
    }
}

struct DialView: View {
    @ObservedObject var store: DialStore
    @ObservedObject var edge: EdgeLook
    @ObservedObject var look = GhieraLook.shared
    @ObservedObject var wall = WallpaperTint.shared
    static let r: CGFloat = 16

    var body: some View {
        let right = edge.side == .right
        HStack(alignment: .top, spacing: 14) {
            // sul bordo destro il mixer sta a sinistra della ghiera: si apre sempre verso l'interno
            if right && store.mode == .mix { MixerList(store: store).transition(.opacity.combined(with: .move(edge: .trailing))) }
            VStack(spacing: 12) {
                DialFace(store: store)
                HStack(spacing: 6) {
                    ForEach(DialMode.allCases, id: \.self) { m in
                        Button(action: { withAnimation(.easeOut(duration: 0.3)) { store.mode = m } }) {
                            Image(systemName: m.symbol).font(.system(size: 11))
                                .foregroundStyle(store.mode == m ? Ghiera.fg : Ghiera.t2)
                                .frame(width: 30, height: 26)
                                .background(Capsule().fill(store.mode == m ? Ghiera.sel : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .help(m.label.capitalized)
                    }
                }
            }
            if !right && store.mode == .mix { MixerList(store: store).transition(.opacity.combined(with: .move(edge: .leading))) }
        }
        .padding(right ? .trailing : .leading, 16).padding(right ? .leading : .trailing, store.mode == .mix ? 18 : 16)
        .padding(.vertical, edge.libero ? 18 : DialView.r * 2 + 4)   // 21/10: libera non servono i raccordi sopra e sotto
        .modifier(EdgeFormed(form: edge.form) { GhieraSurface(mode: look.mode, edge: edge) })
        .scaleEffect(edge.squash, anchor: edge.anchor)
        .onPreferenceChange(DragBlockKey.self) { [edge] in edge.blocks = $0 }
        .environment(\.colorScheme, look.mode == .sfondo ? wall.info(edge).scheme : Ghiera.scheme)
        .id("\(look.mode.rawValue)-\(look.mode == .sfondo ? wall.version : 0)")
        .fixedSize()
    }
}

struct MixerList: View {
    @ObservedObject var store: DialStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MIXER").font(Ghiera.mono).tracking(1.6).foregroundStyle(Ghiera.t3)
                Spacer()
                Text(T("\(store.apps.count) APP", "\(store.apps.count) APPS")).font(Ghiera.mono).tracking(1.6).foregroundStyle(Ghiera.t3)
            }
            .padding(.bottom, 8)
            Rectangle().fill(Ghiera.fg.opacity(0.1)).frame(height: 1)
            if store.apps.isEmpty {
                Text(T("Nessuna app sta suonando", "No app is playing")).font(.system(size: 12)).foregroundStyle(Ghiera.t2)
                    .padding(.top, 14)
            }
            ForEach(store.apps) { app in MixRow(store: store, app: app) }
            if store.tapError {
                Text(T("Serve il permesso Registrazione audio: Impostazioni → Privacy → Registrazione schermo e audio di sistema",
                       "Needs System Audio Recording: Settings → Privacy → Screen & System Audio Recording"))
                    .font(.system(size: 10)).foregroundStyle(Ghiera.amber).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !store.apps.isEmpty {
                Text(T("TOCCA L'ICONA PER COLLEGARE", "TAP AN ICON TO LINK")).font(Ghiera.mono).tracking(1.2).foregroundStyle(Ghiera.t3)
                    .padding(.top, 10)
            }
        }
        .frame(width: 236, alignment: .topLeading)
        .frame(minHeight: DialFace.size + 38, alignment: .topLeading)
    }
}

private struct MixRow: View {
    @ObservedObject var store: DialStore
    @ObservedObject private var icone = IconeApp.shared
    let app: MixApp

    var body: some View {
        let g = store.gain(app.id)
        let linked = store.linked.contains(app.id)
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Button(action: { store.toggleLink(app.id) }) {
                    ZStack {
                        if let icon = icone.icona(bundle: app.id) ?? app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        else { Image(systemName: "app").frame(width: 20, height: 20) }
                    }
                    .padding(3)
                    .overlay(Circle().strokeBorder(linked ? Ghiera.mint : Color.clear, lineWidth: 1.5).frame(width: 30, height: 30))
                }
                .buttonStyle(.plain)
                .help(linked ? T("Collegata alla ghiera", "Linked to the dial") : T("Collega alla ghiera", "Link to the dial"))
                Text(app.name).font(.system(size: 12.5)).foregroundStyle(app.playing ? Ghiera.fg : Ghiera.t2).lineLimit(1)
                Spacer()
                Text(g == 0 ? "MUTE" : "\(Int((g * 100).rounded()))%").font(Ghiera.mono).tracking(1.2)
                    .foregroundStyle(g == 0 ? Ghiera.amber : Ghiera.t2)
            }
            ThinSlider(value: Double(g)) { store.setGain(app.id, Float($0)) }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Ghiera.fg.opacity(0.07)).frame(height: 1) }
    }
}

private struct ThinSlider: View {
    let value: Double
    let set: (Double) -> Void
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ghiera.fg.opacity(0.10)).frame(height: 3)
                Capsule().fill(Ghiera.mint).frame(width: max(3, geo.size.width * value), height: 3)
                Circle().fill(Color.white).shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5).frame(width: 9, height: 9).offset(x: geo.size.width * value - 4.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { set(Double($0.location.x / geo.size.width)) })
        }
        .frame(height: 14)
        .dragBlock()
    }
}

// MARK: - Luce: schermo e tastiera (06/10/2026)
// Apple non ha un'API pubblica per queste due luci: si usano DisplayServices (schermo) e CoreBrightness
// (tastiera), le stesse di MonitorControl e delle app della barra. Si caricano a runtime: se una versione
// di macOS le toglie, la ghiera lo dice invece di rompersi.

enum LightControl {
    private typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetB = @convention(c) (UInt32, Float) -> Int32
    private static let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getB: GetB? = dlsym(ds, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetB.self) }
    private static let setB: SetB? = dlsym(ds, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetB.self) }

    /// Lo schermo del MacBook; se il coperchio è chiuso, lo schermo principale.
    private static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
    static var screenAvailable: Bool { getB != nil && setB != nil }
    static var screen: Float {
        get { var b: Float = 0; return getB?(display, &b) == 0 ? b : 0 }
        set { _ = setB?(display, max(0, min(1, newValue))) }
    }

    // tastiera: KeyboardBrightnessClient, chiamato con l'implementazione diretta (i float non passano da perform)
    private static let kbClass: NSObject.Type? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
    }()
    private static let kb: NSObject? = kbClass?.init()
    private static let kbID: UInt64? = {
        guard let kb, let ids = kb.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber] else { return nil }
        return ids.first?.uint64Value
    }()
    private typealias KGet = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KSet = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private static let kGetSel = NSSelectorFromString("brightnessForKeyboard:")
    private static let kSetSel = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let kGet: KGet? = kbClass.flatMap { class_getInstanceMethod($0, kGetSel) }.map { unsafeBitCast(method_getImplementation($0), to: KGet.self) }
    private static let kSet: KSet? = kbClass.flatMap { class_getInstanceMethod($0, kSetSel) }.map { unsafeBitCast(method_getImplementation($0), to: KSet.self) }

    // la versione con dissolvenza salva anche la preferenza (commit), come i tasti F5/F6
    private typealias KFade = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private static let kFadeSel = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
    private static let kFade: KFade? = kbClass.flatMap { class_getInstanceMethod($0, kFadeSel) }.map { unsafeBitCast(method_getImplementation($0), to: KFade.self) }
    private typealias KBool = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private static let kSuppSel = NSSelectorFromString("isBacklightSuppressedOnKeyboard:")
    private static let kSupp: KBool? = kbClass.flatMap { class_getInstanceMethod($0, kSuppSel) }.map { unsafeBitCast(method_getImplementation($0), to: KBool.self) }

    static var keyboardAvailable: Bool { kb != nil && kbID != nil && kGet != nil && (kFade != nil || kSet != nil) }
    /// Con tanta luce nella stanza macOS spegne la tastiera e ignora ogni comando (anche F5/F6).
    static var keyboardSuppressed: Bool {
        guard let kb, let id = kbID, let f = kSupp else { return false }
        return f(kb, kSuppSel, id)
    }
    static var keyboard: Float {
        get { guard let kb, let id = kbID, let f = kGet else { return 0 }; return f(kb, kGetSel, id) }
        set {
            guard let kb, let id = kbID else { return }
            let v = max(0, min(1, newValue))
            if let f = kFade { _ = f(kb, kFadeSel, v, 0, true, id) } else if let f = kSet { _ = f(kb, kSetSel, v, id) }
        }
    }
}

enum LightMode: String, CaseIterable {
    case screen, keyboard
    var symbol: String { self == .screen ? "sun.max.fill" : "light.max" }
    var label: String { self == .screen ? T("SCHERMO", "SCREEN") : T("TASTIERA", "KEYBOARD") }
}

final class LightStore: ObservableObject {
    @Published var mode: LightMode = LightMode(rawValue: Impostazioni.string(.lightMode) ?? "") ?? .screen {
        didSet { Impostazioni.set(mode.rawValue, .lightMode) }
    }
    @Published var screen: Float = LightControl.screen
    @Published var keyboard: Float = LightControl.keyboard
    @Published var suppressed: Bool = LightControl.keyboardSuppressed
    private var lastKeyboard: Float = max(0.3, Impostazioni.object(.lightKbOn) as? Float ?? 0.5)

    var available: Bool { mode == .screen ? LightControl.screenAvailable : LightControl.keyboardAvailable }
    var level: Double { Double(mode == .screen ? screen : keyboard) }

    /// Rilegge le luci: anche i tasti F1/F2 e i sensori le cambiano.
    func refresh() {
        let s = LightControl.screen, k = LightControl.keyboard
        if abs(s - screen) > 0.004 { screen = s }
        if abs(k - keyboard) > 0.004 { keyboard = k }
        let sup = LightControl.keyboardSuppressed
        if sup != suppressed { suppressed = sup }
    }

    func set(_ fraction: Double) {
        let v = Float(max(0, min(1, fraction)))
        if mode == .screen { LightControl.screen = max(0.01, v); screen = LightControl.screen }
        else { LightControl.keyboard = v; keyboard = v; if v > 0.05 { remember(v) } }
    }
    func nudge(_ ticks: Double) { set(level + ticks / 40) }

    /// Il tocco al centro: tastiera accesa o spenta (torna al livello di prima); sullo schermo passa alla tastiera.
    func center() {
        if mode == .keyboard {
            if keyboard > 0.01 { remember(keyboard); set(0) } else { set(Double(lastKeyboard)) }
        } else { mode = .keyboard }
    }
    private func remember(_ v: Float) { lastKeyboard = v; Impostazioni.set(v, .lightKbOn) }
}

struct LightView: View {
    @ObservedObject var store: LightStore
    @ObservedObject var edge: EdgeLook
    @ObservedObject var look = GhieraLook.shared
    @ObservedObject var wall = WallpaperTint.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(LightMode.allCases, id: \.self) { m in
                    Button(action: { withAnimation(.easeOut(duration: 0.3)) { store.mode = m } }) {
                        Image(systemName: m.symbol).font(.system(size: 11))
                            .foregroundStyle(store.mode == m ? Ghiera.fg : Ghiera.t2)
                            .frame(width: 30, height: 26)
                            .background(Capsule().fill(store.mode == m ? Ghiera.sel : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(m.label.capitalized)
                }
            }
            RingFace(level: store.available ? store.level : 0,
                     symbol: store.mode == .keyboard && store.keyboard < 0.01 ? "light.min" : store.mode.symbol,
                     value: store.available ? "\(Int((store.level * 100).rounded()))" : "—",
                     label: !store.available ? T("NON DISPONIBILE", "UNAVAILABLE")
                        : store.mode == .keyboard && store.suppressed ? T("SOSPESA", "SUSPENDED") : store.mode.label,
                     center: { store.center() }, set: { store.set($0) })
        }
        .help(store.mode == .keyboard && store.suppressed
              ? T("C'è abbastanza luce: macOS tiene spenta la tastiera finché la stanza non si scurisce.",
                  "The room is bright: macOS keeps the keyboard light off until it gets darker.") : "")
        .padding(.leading, 16).padding(.trailing, 16)
        .padding(.vertical, edge.libero ? 18 : DialView.r * 2 + 4)   // 21/10: libera non servono i raccordi sopra e sotto
        .modifier(EdgeFormed(form: edge.form) { GhieraSurface(mode: look.mode, edge: edge) })
        .scaleEffect(edge.squash, anchor: edge.anchor)
        .onPreferenceChange(DragBlockKey.self) { [edge] in edge.blocks = $0 }
        .environment(\.colorScheme, look.mode == .sfondo ? wall.info(edge).scheme : Ghiera.scheme)
        .id("\(look.mode.rawValue)-\(look.mode == .sfondo ? wall.version : 0)")
        .fixedSize()
    }
}

// MARK: - Finestre a scomparsa sul bordo sinistro

private final class DialPanel: NSPanel {
    // 12/10: l'ombra minima (temi.swift, Ombra) segue comparsa e trasparenza della finestra
    override func orderFrontRegardless() { super.orderFrontRegardless(); Ombra.segui(self) }
    override func orderFront(_ sender: Any?) { super.orderFront(sender); Ombra.segui(self) }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DialHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Una ghiera attaccata a un bordo: sta fuori dallo schermo e rientra quando il mouse tocca il bordo alla sua
/// altezza, come la colonna dell'Agente. Dall'11/10 dove sta lo decide EdgeDock (bordi.swift): si trascina su e giù,
/// sull'altro bordo, e si fonde con gli altri elementi dello stesso bordo.
private final class EdgeWheel {
    let win = DialPanel()
    let item: EdgeDock.Item
    private let nudge: (Double) -> Void
    private var changes: Any?

    init<V: View, O: ObservableObject>(id: String, bottom: Bool, store: O, nudge: @escaping (Double) -> Void,
                                       onReveal: @escaping () -> Void = {}, make: (EdgeLook) -> V)
    where O.ObjectWillChangePublisher == ObservableObjectPublisher {
        self.nudge = nudge
        item = EdgeDock.Item(id: id, side: .left)
        win.contentView = DialHost(rootView: make(item.look))
        item.radius = { DialView.r }
        item.size = { [weak self] in self?.cached ?? self?.size ?? NSSize(width: 200, height: 260) }
        // in alto: sotto la barra dei menu; in basso: sopra il Dock, se il Dock sta in basso
        item.defaultTop = { [weak self] vf in
            bottom ? vf.minY + 8 - DialView.r + (self?.size.height ?? 260) : vf.maxY - 8 + DialView.r
        }
        item.apply = { [weak self] in self?.layout(animated: $0) }
        item.onReveal = onReveal
        item.colors = { GhieraColors.goo }
        EdgeDock.shared.register(item, window: win)
        changes = store.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.layout(animated: true) } }
        layout(animated: false)
        win.orderFrontRegardless()
    }

    func close() { EdgeDock.shared.unregister(item); win.orderOut(nil); changes = nil }

    private var size: NSSize { win.contentView?.fittingSize ?? NSSize(width: 200, height: 260) }
    private var cached: NSSize?          // la misura si ricalcola solo nel layout, non a ogni movimento del mouse

    func layout(animated: Bool) {
        cached = size
        guard !item.dragging else { return }
        let dock = EdgeDock.shared
        dock.sizeChanged(item)
        dock.move(win, to: dock.frame(for: item), animated: animated)
    }

    func scroll(_ e: NSEvent) -> Bool {
        guard e.window === win else { return false }
        let d = e.hasPreciseScrollingDeltas ? Double(e.scrollingDeltaY) / 12 : Double(e.scrollingDeltaY)
        nudge(e.isDirectionInvertedFromDevice ? d : -d)
        return true
    }

    func reveal(hideAfter: Double? = nil) { EdgeDock.shared.reveal(item, hideAfter: hideAfter) }
    func toggle() { EdgeDock.shared.toggle(item) }
}

final class DialModule {
    let store = DialStore()
    let light = LightStore()
    private var sound: EdgeWheel?
    private var lamp: EdgeWheel?
    private var monitors: [Any] = []
    private var lightPoll: Timer?

    /// La ghiera del suono, in alto a sinistra.
    var enabled: Bool {
        get { Impostazioni.object(.dialEnabled) as? Bool ?? true }
        set { Impostazioni.set(newValue, .dialEnabled); cambiata() }
    }
    /// La ghiera della luce, in basso a sinistra.
    var lightEnabled: Bool {
        get { Impostazioni.object(.lightEnabled) as? Bool ?? true }
        set { Impostazioni.set(newValue, .lightEnabled); cambiata() }
    }

    /// Una delle due ghiere è stata accesa o spenta: se il modulo gira già e resta acceso si riavvia, altrimenti decide il registro.
    private func cambiata() {
        if RegistroModuli.shared.inEsecuzione("ghiera") && (enabled || lightEnabled) { restart() } else { RegistroModuli.shared.riapplica() }
    }

    fileprivate func restart() {
        stop()
        guard enabled || lightEnabled else { return }
        if enabled {
            store.start()
            store.onTimerDone = { [weak self] in self?.timerDone() }
            sound = EdgeWheel(id: "ghiera", bottom: false, store: store,
                              nudge: { [weak self] in self?.store.nudge($0) }, onReveal: { [weak self] in self?.store.refresh() },
                              make: { [store] in DialView(store: store, edge: $0) })
        }
        if lightEnabled {
            lamp = EdgeWheel(id: "luce", bottom: true, store: light,
                             nudge: { [weak self] in self?.light.nudge($0) }, onReveal: { [weak self] in self?.light.refresh() },
                             make: { [light] in LightView(store: light, edge: $0) })
            lightPoll = Timer.scheduledTimer(withTimeInterval: Leggera.on ? 3.0 : 1.0, repeats: true) { [weak self] _ in self?.light.refresh() }
        }
        // il mouse sul bordo (uscire e rientrare) e il trascinamento li segue EdgeDock, in bordi.swift
        // la rotella sopra una ghiera la gira (anche il trackpad a due dita)
        if let l = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            guard let self else { return e }
            if self.sound?.scroll(e) == true || self.lamp?.scroll(e) == true { return nil }
            return e
        }) { monitors.append(l) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(lookChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    /// L'Agente ha cambiato aspetto (menu o ⌃⌥L): le ghiere lo seguono.
    @objc private func lookChanged() {
        DispatchQueue.main.async { [weak self] in
            let m = AgentMode.saved
            guard GhieraLook.shared.mode != m else { return }
            GhieraLook.shared.mode = m
            self?.sound?.layout(animated: false); self?.lamp?.layout(animated: false)
        }
    }

    func stop() {
        store.stop()
        sound?.close(); sound = nil
        lamp?.close(); lamp = nil
        lightPoll?.invalidate(); lightPoll = nil
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors = []
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screensChanged() { sound?.layout(animated: false); lamp?.layout(animated: false) }

    /// Fine del timer: due rintocchi di Glass e la ghiera esce per qualche secondo.
    private func timerDone() {
        for d in [0.0, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { NSSound(named: "Glass")?.play() }
        }
        store.mode = .timer
        sound?.reveal(hideAfter: 4)
    }

    func toggle() { sound?.toggle() }
    /// Per la dimostrazione: gli elementi del bordo delle due ghiere.
    var soundItem: EdgeDock.Item? { sound?.item }
    var lightItem: EdgeDock.Item? { lamp?.item }
    func toggleLight() { lamp?.toggle() }
}

// MARK: - Registro dei moduli (fase 2): le ghiere valgono con Pulsar Mixer (o Complete)

extension DialModule: ModuloPulsar {
    var id: String { "ghiera" }
    var nome: String { T("Ghiere", "Dials") }
    var prodotto: Prodotto { .mixer }
    var permessi: [Permesso] { [] }
    var acceso: Bool { enabled || lightEnabled }
    func avvia() { restart() }
    func ferma() { stop() }
}

// MARK: - Puntini al centro delle ghiere (12/10/2026)
// l'autore, guardando l'animazione a destra del notch (isola-agente.swift, NotchPulse): "imitala, e crea un'animazione
// anche per i nostri interruttori di volume e luminosità. Quel bianco o grafite chiaro mi piace molto come accento".
// Stessa grammatica: griglia 5x5 di quadratini arrotondati, base blu-grafite schiarito (PulseMotion.tail), solo la
// testa o la cima diventa bianca; moto continuo e lento, niente scatti. In White Matte la base è grafite chiaro e la
// cima grafite scuro. Ogni modo ha la sua figura, che segue il livello vero:
//   volume: cinque colonne che salgono fino al livello e respirano piano · muto: una X spenta
//   mix: le stesse colonne, più lente · timer: l'anello acceso per il tempo che resta, con una cometa che gira
//   schermo: un sole che si allarga col livello, con un'onda dal centro · tastiera: le file accese dal basso.
struct DotGlyph: View {
    enum Kind { case volume, mute, mix, timer, timerRunning, screen, keyboard }
    let kind: Kind
    let level: Double
    @ObservedObject private var look = GhieraLook.shared

    static func kind(for symbol: String) -> Kind {
        switch symbol {
        case "speaker.slash.fill", "speaker.slash": return .mute
        case "slider.vertical.3": return .mix
        case "pause.fill": return .timerRunning
        case "play.fill", "timer": return .timer
        case "sun.max.fill", "sun.max": return .screen
        case "light.max", "light.min": return .keyboard
        default: return .volume
        }
    }

    private static let ring: [(Int, Int)] = [(2, 0), (3, 0), (4, 0), (4, 1), (4, 2), (4, 3), (4, 4), (3, 4), (2, 4),
                                              (1, 4), (0, 4), (0, 3), (0, 2), (0, 1), (0, 0), (1, 0)]   // dall'alto, in senso orario

    var body: some View {
        let chiaro = look.mode == .bianco
        let base = chiaro ? Color(red: 0.52, green: 0.56, blue: 0.66) : PulseMotion.tail
        let hi0 = chiaro ? Color(red: 0.20, green: 0.22, blue: 0.28) : Color.white
        // volume, schermo e tastiera: la luce dei puntini va verso l'azzurro col livello (come le tacche)
        let hi = [.volume, .screen, .keyboard].contains(kind) ? hi0.mix(with: DotColors.azzurro, by: max(0, min(1, level))) : hi0
        TimelineView(.animation(minimumInterval: Leggera.on ? 1.0 / 15 : 1.0 / 30)) { ctx in   // 13/10: animazione tenuta anche in Pulsar leggera (l'autore)
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let cell = min(size.width, size.height) / 5.0, px = cell * 0.78
                for y in 0..<5 {
                    for x in 0..<5 {
                        let (a, w) = Self.value(kind, level, x, y, t)
                        let r = CGRect(x: (size.width - cell * 5) / 2 + CGFloat(x) * cell + (cell - px) / 2,
                                       y: (size.height - cell * 5) / 2 + CGFloat(y) * cell + (cell - px) / 2, width: px, height: px)
                        let path = Path(roundedRect: r, cornerRadius: px * 0.28)
                        g.fill(path, with: .color(base.opacity(a)))
                        if w > 0.01 { g.fill(path, with: .color(hi.opacity(w))) }
                    }
                }
            }
        }
    }

    private static func ease(_ v: Double) -> Double { let c = min(1, max(0, v)); return c * c * (3 - 2 * c) }

    /// (quanto è acceso nel colore base, quanto accento ci va sopra) per il pixel x,y (y = 0 in alto)
    static func value(_ k: Kind, _ lv: Double, _ x: Int, _ y: Int, _ t: Double) -> (Double, Double) {
        let off = 0.08
        let lv = max(0, min(1, lv))
        switch k {
        case .volume, .mix:
            // 12/10 sera, l'autore: "fai che l'animazione resti costante". Le colonne ondeggiano di circa una cella anche
            // a volume fermo, e una luce bianca scorre avanti e indietro sulle cime. Il livello resta la quantità di griglia accesa.
            let sp = k == .mix ? 1.1 : 1.9
            let amp = 0.55 + 0.45 * min(1, lv * 2.5)
            let h = lv > 0.005 ? lv * 4.6 + 0.4 + amp * sin(t * sp + Double(x) * 1.25) : 0
            let row = Double(4 - y)                                // 0 in basso
            let fill = ease(h - row)                               // la cella si accende quando la colonna la supera
            let top = fill > 0.05 && h - row < 1.15                // la cima della colonna
            let scan = 2 + 2.2 * sin(t * (k == .mix ? 0.8 : 1.3))  // la luce che passa
            let luce = exp(-(Double(x) - scan) * (Double(x) - scan) / 0.7)
            return (off + 0.62 * fill, top ? (0.35 + 0.55 * luce) * fill : 0.25 * luce * fill)
        case .mute:
            let onX = x == y || x == 4 - y
            return (onX ? 0.28 + 0.14 * (0.5 + 0.5 * sin(t * 1.6)) : off, 0)
        case .timer, .timerRunning:
            // anello acceso per il tempo che resta; una cometa lo percorre sempre (chiara se il timer corre, tenue se è fermo)
            guard max(abs(x - 2), abs(y - 2)) == 2, let i = ring.firstIndex(where: { $0 == (x, y) }) else {
                let d = max(abs(x - 2), abs(y - 2))
                return (d == 0 ? 0.2 + 0.2 * (0.5 + 0.5 * sin(t * 2.4)) : off, 0)
            }
            let lit = Double(i) < lv * 16 + 0.2
            let run = k == .timerRunning
            let head = (t * (run ? 2.2 : 1.0)).truncatingRemainder(dividingBy: 16)
            var dist = Double(i) - head; dist -= 16 * (dist / 16).rounded()
            let w = (run ? 0.7 : 0.35) * exp(-dist * dist / 0.5)
            let coda = 0.45 * exp(-max(0, -dist) / 2.4) * (dist <= 0 ? 1 : exp(-dist * dist / 0.3))
            return (max(lit ? 0.55 : off, run ? coda : coda * 0.5), w)
        case .screen:
            // sole: centro sempre acceso, giri accesi fino al livello e un po' di respiro, un'onda chiara che esce dal centro
            let d = Double(max(abs(x - 2), abs(y - 2)))
            let reach = lv * 2.6 + 0.25 * sin(t * 1.4)
            let fill = ease(reach - d + 0.5)
            let wave = (t * 1.1).truncatingRemainder(dividingBy: 3.2)
            let wv = exp(-(d - wave) * (d - wave) / 0.22) * max(fill, 0.35)
            return (off + 0.55 * fill + 0.15 * wv, d == 0 ? 0.55 + 0.25 * (0.5 + 0.5 * sin(t * 2)) : 0.7 * wv)
        case .keyboard:
            // tasti: file accese dal basso fino al livello; una passata di luce scorre sempre sulla fila più alta
            let row = Double(4 - y)
            let h = lv * 5 + 0.2 * sin(t * 1.2)
            let fill = ease(h - row + 0.3)
            let top = fill > 0.05 && h - row < 1.3
            let scan = 2 + 2.2 * sin(t * 1.1)
            let luce = exp(-(Double(x) - scan) * (Double(x) - scan) / 0.8)
            return (off + 0.55 * fill, top ? (0.25 + 0.6 * luce) * fill : 0.15 * luce * fill)
        }
    }
}
