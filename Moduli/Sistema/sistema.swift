// Pulsar — SISTEMA (13/11/2026, ondata 3 di VORSSAINT.md): le schede Sistema, Rete e Manutenzione del pannello della
// barra. Prese dal reel dell'app del notch a schede (la funzione, mai nome o testi):
//   Sistema: CPU, GPU e memoria con un grafico dell'ultimo minuto, batteria e la sua temperatura.
//   Rete: velocità in arrivo e in uscita dal vivo, grafico, totale da quando Pulsar è aperta, prova di velocità
//         con networkQuality (lo strumento di macOS: niente siti, niente server di altri scelti da noi).
// Il controllo delle ventole e le temperature di CPU e GPU NON ci sono: servono API private e scrivere nell'hardware.
// Si legge solo mentre la scheda è aperta (una volta al secondo), poi tutto si ferma.
import AppKit
import IOKit
import IOKit.ps
import SwiftUI

// MARK: - Il modulo

final class ModuloSistema: ModuloPulsar {
    static let shared = ModuloSistema()
    var id: String { "sistema" }
    var nome: String { T("Sistema e rete", "System and network") }
    var prodotto: Prodotto { .complete }
    var permessi: [Permesso] { [] }
    var acceso: Bool {
        get { Impostazioni.object(.sistemaAcceso) as? Bool ?? false }
        set { Impostazioni.set(newValue, .sistemaAcceso); RegistroModuli.shared.riapplica() }
    }
    private(set) var attivo = false
    func avvia() { attivo = true }
    func ferma() { attivo = false; Monitor.shared.guarda(false) }
}

// MARK: - Le misure

final class Monitor: ObservableObject {
    static let shared = Monitor()
    static let punti = 60

    @Published private(set) var cpu: [Double] = []
    @Published private(set) var gpu: [Double] = []
    @Published private(set) var ram: [Double] = []
    @Published private(set) var ramUsata: Int64 = 0
    @Published private(set) var giu: [Double] = []          // byte al secondo
    @Published private(set) var su: [Double] = []
    @Published private(set) var sessioneGiu: Int64 = 0
    @Published private(set) var sessioneSu: Int64 = 0
    @Published private(set) var batteria: (percento: Int, carica: Bool)?
    @Published private(set) var tempBatteria: Double?
    @Published private(set) var prova: StatoProva = .ferma

    enum StatoProva: Equatable { case ferma, inCorso, fatta(ProvaVelocita.Esito), errore }

    private var orologio: Timer?
    private var spettatori = 0
    private var tickPrima: [UInt32]?
    private var reteInizio: (Int64, Int64)?
    private var retePrima: (Int64, Int64, Date)?

    /// Una scheda si apre (true) o si chiude (false): si misura solo se qualcuno guarda.
    func guarda(_ si: Bool) {
        spettatori = max(0, spettatori + (si ? 1 : -1))
        if !si && !ModuloSistema.shared.attivo { spettatori = 0 }
        if spettatori > 0, orologio == nil {
            misura()
            orologio = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.misura() }
        } else if spettatori == 0 {
            orologio?.invalidate(); orologio = nil
        }
    }

    private func aggiungi(_ v: Double, a serie: inout [Double]) { serie.append(v); if serie.count > Self.punti { serie.removeFirst(serie.count - Self.punti) } }

    private func misura() {
        if let c = cpuOra() { aggiungi(c, a: &cpu) }
        if let g = Self.gpuOra() { aggiungi(g, a: &gpu) }
        let (usata, tot) = Self.memoria()
        ramUsata = usata
        aggiungi(tot > 0 ? Double(usata) / Double(tot) : 0, a: &ram)
        batteria = Self.batteriaOra()
        tempBatteria = Self.temperaturaBatteria()
        let (i, o) = Self.byteRete()
        if reteInizio == nil { reteInizio = (i, o) }
        let ora = Date()
        if let (pi, po, pt) = retePrima {
            let dt = max(0.2, ora.timeIntervalSince(pt))
            aggiungi(Double(max(0, i - pi)) / dt, a: &giu); aggiungi(Double(max(0, o - po)) / dt, a: &su)
        }
        retePrima = (i, o, ora)
        if let (si, so) = reteInizio { sessioneGiu = max(0, i - si); sessioneSu = max(0, o - so) }
    }

    // CPU: differenza dei tick di tutti i core fra due letture (host_processor_info)
    private func cpuOra() -> Double? {
        var n: natural_t = 0, info: processor_info_array_t?, conta: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &conta) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(conta) * MemoryLayout<integer_t>.size)) }
        let tick = (0..<Int(conta)).map { UInt32(bitPattern: info[$0]) }
        defer { tickPrima = tick }
        guard let p = tickPrima, p.count == tick.count else { return nil }
        var usati: UInt64 = 0, totali: UInt64 = 0
        for c in 0..<Int(n) {
            let b = c * Int(CPU_STATE_MAX)
            let d = (0..<Int(CPU_STATE_MAX)).map { UInt64(tick[b + $0] &- p[b + $0]) }
            usati += d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]
            totali += d.reduce(0, +)
        }
        return totali > 0 ? Double(usati) / Double(totali) : nil
    }

    /// GPU: "Device Utilization %" che il driver pubblica nel registro di IOKit (pubblico, niente permessi).
    private static func gpuOra() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var massimo: Double?
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            if let st = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let u = (st["Device Utilization %"] as? NSNumber)?.doubleValue {
                massimo = max(massimo ?? 0, u / 100)
            }
        }
        return massimo
    }

    /// Memoria usata come la conta Monitoraggio Attività: app (attive), fissa (wired) e compressa.
    private static func memoria() -> (Int64, Int64) {
        var st = vm_statistics64(), n = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &st) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n) } }
        guard ok == KERN_SUCCESS else { return (0, Int64(ProcessInfo.processInfo.physicalMemory)) }
        let pag = Int64(vm_kernel_page_size)
        let usata = (Int64(st.active_count) + Int64(st.wire_count) + Int64(st.compressor_page_count)) * pag
        return (usata, Int64(ProcessInfo.processInfo.physicalMemory))
    }

    private static func batteriaOra() -> (Int, Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let lista = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for s in lista {
            guard let d = IOPSGetPowerSourceDescription(info, s)?.takeUnretainedValue() as? [String: Any],
                  let c = d[kIOPSCurrentCapacityKey] as? Int, let m = d[kIOPSMaxCapacityKey] as? Int, m > 0 else { continue }
            return (c * 100 / m, (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }

    /// La temperatura della batteria (in centesimi di grado nel registro di AppleSmartBattery). L'unica pubblica.
    private static func temperaturaBatteria() -> Double? {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard s != 0 else { return nil }
        defer { IOObjectRelease(s) }
        guard let t = (IORegistryEntryCreateCFProperty(s, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue,
              t > 0 else { return nil }
        return t / 100
    }

    /// Byte entrati e usciti da Wi-Fi ed Ethernet (interfacce en*), coi contatori a 64 bit di NET_RT_IFLIST2.
    private static func byteRete() -> (Int64, Int64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var dim = 0
        guard sysctl(&mib, 6, nil, &dim, nil, 0) == 0, dim > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: dim)
        guard sysctl(&mib, 6, &buf, &dim, nil, 0) == 0 else { return (0, 0) }
        var dentro: Int64 = 0, fuori: Int64 = 0, i = 0
        while i < dim {
            let (lung, tipo, indice): (Int, Int32, UInt16) = buf.withUnsafeBytes { p in
                let h = p.load(fromByteOffset: i, as: if_msghdr.self)
                return (Int(h.ifm_msglen), Int32(h.ifm_type), h.ifm_index)
            }
            guard lung > 0 else { break }
            if tipo == RTM_IFINFO2 {
                var nome = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(indice), &nome) != nil, String(cString: nome).hasPrefix("en") {
                    let d = buf.withUnsafeBytes { $0.load(fromByteOffset: i, as: if_msghdr2.self).ifm_data }
                    dentro += Int64(d.ifi_ibytes); fuori += Int64(d.ifi_obytes)
                }
            }
            i += lung
        }
        return (dentro, fuori)
    }

    // MARK: Prova di velocità

    func provaVelocita() {
        guard prova != .inCorso else { return }
        prova = .inCorso
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality"); p.arguments = ["-c"]
            let tubo = Pipe(); p.standardOutput = tubo; p.standardError = Pipe()
            var esito: StatoProva = .errore
            if (try? p.run()) != nil {
                let dati = tubo.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let e = ProvaVelocita.leggi(dati) { esito = .fatta(e) }
            }
            DispatchQueue.main.async { self.prova = esito }
        }
    }
}

// MARK: - Viste

/// Un grafico dell'ultimo minuto: area leggera e linea, l'ultimo punto più acceso. Valori da 0 a `tetto`.
struct GraficoMinuto: View {
    let valori: [Double]
    var tetto: Double? = nil
    var colore: Color
    var body: some View {
        Canvas { g, size in
            guard valori.count > 1 else { return }
            let alto = max(tetto ?? (valori.max() ?? 1), 1e-9)
            let passo = size.width / CGFloat(Monitor.punti - 1)
            let x0 = size.width - CGFloat(valori.count - 1) * passo
            func pt(_ i: Int) -> CGPoint { CGPoint(x: x0 + CGFloat(i) * passo, y: size.height - CGFloat(min(1, valori[i] / alto)) * (size.height - 3) - 1.5) }
            var linea = Path(); linea.move(to: pt(0)); for i in 1..<valori.count { linea.addLine(to: pt(i)) }
            var area = linea; area.addLine(to: CGPoint(x: pt(valori.count - 1).x, y: size.height)); area.addLine(to: CGPoint(x: x0, y: size.height)); area.closeSubpath()
            g.fill(area, with: .color(colore.opacity(0.14)))
            g.stroke(linea, with: .color(colore.opacity(0.9)), lineWidth: 1.4)
            let u = pt(valori.count - 1)
            g.fill(Path(ellipseIn: CGRect(x: u.x - 2.5, y: u.y - 2.5, width: 5, height: 5)), with: .color(colore))
        }
    }
}

private struct Tessera<C: View>: View {
    let s: Volta.Scala
    @ViewBuilder let c: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { c() }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(s.chiaro ? 0 : 0.06), lineWidth: 1))
    }
}

private func percento(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }

struct SchedaSistema: View {
    @ObservedObject private var m = Monitor.shared
    @Environment(\.matte) private var s     // la scala del pannello (anche nelle foto di un altro tema)
    var body: some View {
        VStack(spacing: 6) {
            riga("CPU", m.cpu)
            riga("GPU", m.gpu)
            riga(T("Memoria", "Memory"), m.ram, extra: Misura.byte(m.ramUsata))
            Tessera(s: s) {
                HStack {
                    Image(systemName: m.batteria?.carica == true ? "battery.100.bolt" : "battery.75").foregroundStyle(s.t2)
                    Text(T("Batteria", "Battery")).font(.system(size: 12.5, weight: .medium)).foregroundStyle(s.t1)
                    Spacer()
                    Text(m.batteria.map { "\($0.percento)%" } ?? "—").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(s.t1)
                    Text(m.tempBatteria.map { String(format: "%.0f °C", $0) } ?? "").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(s.t2)
                }
            }
        }
        .onAppear { m.guarda(true) }
        .onDisappear { m.guarda(false) }
    }
    private func riga(_ nome: String, _ v: [Double], extra: String? = nil) -> some View {
        Tessera(s: s) {
            HStack(alignment: .firstTextBaseline) {
                Text(nome).font(.system(size: 12.5, weight: .medium)).foregroundStyle(s.t1)
                if let e = extra { Text(e).font(.system(size: 11)).foregroundStyle(s.t2) }
                Spacer()
                Text(percento(v.last)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(s.t1)
            }
            GraficoMinuto(valori: v, tetto: 1, colore: s.a2).frame(height: 26)
        }
    }
}

struct SchedaRete: View {
    @ObservedObject private var m = Monitor.shared
    @Environment(\.matte) private var s     // la scala del pannello (anche nelle foto di un altro tema)
    var body: some View {
        VStack(spacing: 6) {
            Tessera(s: s) {
                HStack(spacing: 18) {
                    velocita("arrow.down", Misura.alSecondo(m.giu.last ?? 0), T("In arrivo", "Download"))
                    velocita("arrow.up", Misura.alSecondo(m.su.last ?? 0), T("In uscita", "Upload"))
                }
                ZStack {
                    GraficoMinuto(valori: m.giu, tetto: max(m.giu.max() ?? 1, m.su.max() ?? 1, 1), colore: s.a2)
                    GraficoMinuto(valori: m.su, tetto: max(m.giu.max() ?? 1, m.su.max() ?? 1, 1), colore: s.t2)
                }
                .frame(height: 44)
                HStack {
                    Text(T("Da quando Pulsar è aperta", "Since Pulsar opened")).font(.system(size: 11)).foregroundStyle(s.t2)
                    Spacer()
                    Text("↓ \(Misura.byte(m.sessioneGiu))  ↑ \(Misura.byte(m.sessioneSu))").font(.system(size: 11).monospacedDigit()).foregroundStyle(s.t1)
                }
            }
            Tessera(s: s) {
                HStack {
                    Text(T("Prova di velocità", "Speed test")).font(.system(size: 12.5, weight: .medium)).foregroundStyle(s.t1)
                    Spacer()
                    switch m.prova {
                    case .ferma, .errore:
                        Button(m.prova == .errore ? T("Riprova", "Retry") : T("Prova", "Run")) { m.provaVelocita() }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(s.primT)
                            .padding(.horizontal, 12).frame(height: 24).background(Capsule().fill(s.prim))
                    case .inCorso:
                        ProgressView().controlSize(.small)
                        Text(T("Misuro… circa 20 s", "Measuring… about 20 s")).font(.system(size: 11)).foregroundStyle(s.t2)
                    case .fatta(let e):
                        Text(String(format: "↓ %.0f  ↑ %.0f Mbit/s", e.giu, e.su)).font(.system(size: 12).monospacedDigit()).foregroundStyle(s.t1)
                        Button { m.provaVelocita() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(s.t2)
                    }
                }
                if m.prova == .errore {
                    Text(T("Non riuscita: sei collegato?", "Didn't work: are you online?")).font(.system(size: 11)).foregroundStyle(s.t2)
                }
            }
        }
        .onAppear { m.guarda(true) }
        .onDisappear { m.guarda(false) }
    }
    private func velocita(_ simbolo: String, _ valore: String, _ nome: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .semibold)).foregroundStyle(s.t2)
            VStack(alignment: .leading, spacing: 1) {
                Text(valore).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(s.t1)
                Text(nome).font(.system(size: 10.5)).foregroundStyle(s.t2)
            }
        }
    }
}
