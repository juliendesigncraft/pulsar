// Pulsar — MANUTENZIONE (13/11/2026, ondata 3 di VORSSAINT.md): la scheda Manutenzione del pannello della barra.
//   Aggiornamenti delle app: legge la versione installata e la confronta con il feed Sparkle dell'app o con l'App Store
//     (lookup pubblico di Apple). Parte solo quando si preme "Controlla". Non aggiorna da sola: apre l'app o l'App Store.
//   Pulizia: cache, log e resti di app che non ci sono più. Si rivede la lista, si sceglie, e tutto va nel CESTINO.
//   Disinstalla: un'app e i suoi resti in ~/Library, tutto nel CESTINO. Mai app di sistema, mai Pulsar, mai app aperte.
// Mai cancellazioni dirette: dal Cestino si torna indietro.
import AppKit
import SwiftUI

// MARK: - I dati

struct VoceFile: Identifiable {
    let id = UUID()
    let url: URL
    let nome: String
    let gruppo: String
    let byte: Int64
    var scelta: Bool
}

struct AppDaAggiornare: Identifiable {
    let id = UUID()
    let nome: String
    let attuale: String
    let nuova: String
    let apri: URL
}

final class Manutenzione: ObservableObject {
    static let shared = Manutenzione()

    enum Vista: Equatable { case elenco, aggiornamenti, pulizia, disinstalla }
    @Published var vista: Vista = .elenco
    @Published var lavoro = false
    @Published var file: [VoceFile] = []
    @Published var aggiornamenti: [AppDaAggiornare] = []
    @Published var controllate = 0
    @Published var esito: String?
    @Published var appScelta: (nome: String, icona: NSImage)?

    private static let casa = FileManager.default.homeDirectoryForCurrentUser
    private static var libreria: URL { casa.appendingPathComponent("Library") }

    // MARK: misure

    static func dimensione(_ u: URL) -> Int64 {
        let fm = FileManager.default
        var dir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &dir) else { return 0 }
        let chiavi: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        if !dir.boolValue { return Int64((try? u.resourceValues(forKeys: Set(chiavi)))?.totalFileAllocatedSize ?? 0) }
        var tot: Int64 = 0, n = 0
        if let e = fm.enumerator(at: u, includingPropertiesForKeys: chiavi, options: [], errorHandler: { _, _ in true }) {
            for case let f as URL in e {
                tot += Int64((try? f.resourceValues(forKeys: Set(chiavi)))?.totalFileAllocatedSize ?? 0)
                n += 1; if n > 200_000 { break }        // cartelle enormi: basta una stima
            }
        }
        return tot
    }

    private static func contenuto(_ u: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    /// Un nome come "com.azienda.app" (almeno due punti) che non appartiene a nessuna app installata e non è di Apple.
    private static func identificatoreOrfano(_ nome: String) -> Bool {
        let id = nome.replacingOccurrences(of: ".plist", with: "").replacingOccurrences(of: ".savedState", with: "")
        guard id.filter({ $0 == "." }).count >= 2, !id.hasPrefix("com.apple."), !id.contains(" "),
              id != Bundle.main.bundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil
    }

    // MARK: pulizia

    func scansiona() {
        vista = .pulizia; lavoro = true; file = []; esito = nil
        let aperte = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [VoceFile] = []
            let lib = Self.libreria
            // cache: mai quelle di Apple e delle app aperte (si ricreano, ma un'app aperta può lamentarsi)
            for u in Self.contenuto(lib.appendingPathComponent("Caches")) {
                let n = u.lastPathComponent
                guard !n.hasPrefix("com.apple."), !aperte.contains(n.lowercased()) else { continue }
                let b = Self.dimensione(u); if b > 1_000_000 { out.append(VoceFile(url: u, nome: n, gruppo: T("Cache", "Caches"), byte: b, scelta: true)) }
            }
            for u in Self.contenuto(lib.appendingPathComponent("Logs")) {
                let b = Self.dimensione(u); if b > 200_000 { out.append(VoceFile(url: u, nome: u.lastPathComponent, gruppo: T("Log", "Logs"), byte: b, scelta: true)) }
            }
            // resti di app che non ci sono più: proposti spenti, si scelgono a mano
            for cartella in ["Preferences", "Application Support", "Containers", "Saved Application State"] {
                for u in Self.contenuto(lib.appendingPathComponent(cartella)) where Self.identificatoreOrfano(u.lastPathComponent) {
                    out.append(VoceFile(url: u, nome: u.lastPathComponent, gruppo: T("Resti di app tolte", "Leftovers of removed apps"),
                                        byte: Self.dimensione(u), scelta: false))
                }
            }
            out.sort { ($0.gruppo, -$0.byte) < ($1.gruppo, -$1.byte) }
            DispatchQueue.main.async { self.file = out; self.lavoro = false }
        }
    }

    /// Le voci scelte nel Cestino. Ritorna quante e quanto spazio; quelle protette da macOS restano e si dice.
    func cestina() {
        let scelte = file.filter(\.scelta)
        guard !scelte.isEmpty else { return }
        lavoro = true
        DispatchQueue.global(qos: .userInitiated).async {
            var fatte = 0, liberato: Int64 = 0, rifiuti = 0
            for v in scelte {
                do { try FileManager.default.trashItem(at: v.url, resultingItemURL: nil); fatte += 1; liberato += v.byte } catch { rifiuti += 1 }
            }
            DispatchQueue.main.async {
                self.file.removeAll { v in scelte.contains { $0.id == v.id } && !FileManager.default.fileExists(atPath: v.url.path) }
                self.esito = T("\(fatte) nel Cestino, \(Misura.byte(liberato))", "\(fatte) moved to Trash, \(Misura.byte(liberato))")
                    + (rifiuti > 0 ? T(". \(rifiuti) protetti da macOS, restano", ". \(rifiuti) protected by macOS, kept") : "")
                if self.vista == .disinstalla && rifiuti == 0 { self.appScelta = nil }
                self.lavoro = false
                Utilita.avvisa("pulizia", "trash", T("Nel Cestino", "Moved to Trash"), Misura.byte(liberato))
            }
        }
    }

    // MARK: disinstalla

    func scegliApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        p.prompt = T("Scegli", "Choose")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let app = p.url else { return }
        prepara(app)
    }

    func prepara(_ app: URL) {
        vista = .disinstalla; esito = nil; file = []
        let b = Bundle(url: app)
        let id = b?.bundleIdentifier ?? ""
        let nome = (b?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? app.deletingPathExtension().lastPathComponent
        if app.path.hasPrefix("/System") || id.hasPrefix("com.apple.") || id == Bundle.main.bundleIdentifier {
            esito = T("Questa app non si toglie: è di macOS o è Pulsar.", "This app can't be removed: it's part of macOS or it's Pulsar."); return
        }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == app }) {
            esito = T("\(nome) è aperta: chiudila e riprova.", "\(nome) is open: quit it and try again."); return
        }
        appScelta = (nome, NSWorkspace.shared.icon(forFile: app.path))
        lavoro = true
        DispatchQueue.global(qos: .userInitiated).async {
            var out = [VoceFile(url: app, nome: app.lastPathComponent, gruppo: T("App", "App"), byte: Self.dimensione(app), scelta: true)]
            for (cartella, perNome) in Resti.posti {
                for u in Self.contenuto(Self.libreria.appendingPathComponent(cartella))
                where Resti.appartiene(u.lastPathComponent, id: id, nome: nome, perNome: perNome) {
                    out.append(VoceFile(url: u, nome: cartella + "/" + u.lastPathComponent, gruppo: T("Resti", "Leftovers"), byte: Self.dimensione(u), scelta: true))
                }
            }
            DispatchQueue.main.async { self.file = out; self.lavoro = false }
        }
    }

    // MARK: aggiornamenti

    func controllaAggiornamenti() {
        vista = .aggiornamenti; lavoro = true; aggiornamenti = []; controllate = 0; esito = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let app = Self.appInstallate()
            let gruppo = DispatchGroup()
            var trovate: [AppDaAggiornare] = []
            let blocco = NSLock()
            for a in app {
                guard let b = Bundle(url: a), let id = b.bundleIdentifier, !id.hasPrefix("com.apple."),
                      let ver = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { continue }
                let nome = (b.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? a.deletingPathExtension().lastPathComponent
                let daStore = FileManager.default.fileExists(atPath: a.appendingPathComponent("Contents/_MASReceipt/receipt").path)
                let feed = (b.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
                let indirizzo: URL?
                if daStore { indirizzo = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)&entity=macSoftware") }
                else { indirizzo = feed?.scheme == "https" ? feed : nil }
                guard let u = indirizzo else { continue }
                gruppo.enter()
                var r = URLRequest(url: u, timeoutInterval: 10); r.setValue("Pulsar", forHTTPHeaderField: "User-Agent")
                URLSession.shared.dataTask(with: r) { dati, _, _ in
                    defer { gruppo.leave() }
                    guard let dati else { return }
                    var nuova: String?, apri = a
                    if daStore {
                        if let j = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
                           let r = (j["results"] as? [[String: Any]])?.first {
                            nuova = r["version"] as? String
                            if let tid = r["trackId"] as? Int, let m = URL(string: "macappstore://apps.apple.com/app/id\(tid)") { apri = m }
                        }
                    } else { nuova = Appcast.ultimaVersione(String(decoding: dati, as: UTF8.self)) }
                    blocco.lock(); defer { blocco.unlock() }
                    DispatchQueue.main.async { self.controllate += 1 }
                    if let n = nuova, Versioni.piuNuova(n, di: ver) { trovate.append(AppDaAggiornare(nome: nome, attuale: ver, nuova: n, apri: apri)) }
                }.resume()
            }
            gruppo.wait()
            DispatchQueue.main.async {
                self.aggiornamenti = trovate.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
                self.lavoro = false
            }
        }
    }

    private static func appInstallate() -> [URL] {
        var out: [URL] = []
        for base in ["/Applications", casa.appendingPathComponent("Applications").path] {
            for u in contenuto(URL(fileURLWithPath: base)) {
                if u.pathExtension == "app" { out.append(u) }
                else { out += contenuto(u).filter { $0.pathExtension == "app" } }     // una cartella dentro Applicazioni
            }
        }
        return out
    }
}

// MARK: - La scheda

struct SchedaManutenzione: View {
    @ObservedObject private var m = Manutenzione.shared
    @Environment(\.matte) private var s     // la scala del pannello (anche nelle foto di un altro tema)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if m.vista != .elenco {
                Button { m.vista = .elenco; m.esito = nil } label: {
                    HStack(spacing: 5) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)); Text(T("Indietro", "Back")).font(.system(size: 11.5)) }
                        .foregroundStyle(s.t2).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 4).padding(.bottom, 2)
            }
            switch m.vista {
            case .elenco: elenco
            case .aggiornamenti: aggiornamenti
            case .pulizia, .disinstalla: lista
            }
        }
    }

    private var elenco: some View {
        VStack(spacing: 6) {
            riga("arrow.down.app", T("Aggiornamenti delle app", "App updates"), T("Quali app hanno una versione nuova", "Which apps have a newer version")) { m.controllaAggiornamenti() }
            riga("sparkles", T("Pulizia", "Cleaner"), T("Cache, log e resti di app tolte", "Caches, logs and leftovers")) { m.scansiona() }
            riga("trash", T("Disinstalla un'app", "Uninstall an app"), T("L'app e i suoi resti, nel Cestino", "The app and its leftovers, to the Trash")) {
                PannelloBarra.shared.chiudi(); DispatchQueue.main.async { Manutenzione.shared.scegliApp(); PannelloBarra.shared.riapriSu("manutenzione") }
            }
        }
    }

    private func riga(_ simbolo: String, _ titolo: String, _ sotto: String, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            HStack(spacing: 10) {
                Image(systemName: simbolo).font(.system(size: 13)).foregroundStyle(s.t2).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titolo).font(.system(size: 12.5, weight: .medium)).foregroundStyle(s.t1)
                    Text(sotto).font(.system(size: 10.5)).foregroundStyle(s.t2).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(s.t3)
            }
            .padding(.horizontal, 10).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(s.chiaro ? 0 : 0.06), lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var aggiornamenti: some View {
        if m.lavoro {
            attesa(T("Controllo le app… \(m.controllate)", "Checking apps… \(m.controllate)"))
        } else if m.aggiornamenti.isEmpty {
            nota(T("Tutte aggiornate (\(m.controllate) controllate).", "All up to date (\(m.controllate) checked)."))
        } else {
            ForEach(m.aggiornamenti) { a in
                Button { NSWorkspace.shared.open(a.apri) } label: {
                    HStack {
                        Text(a.nome).font(.system(size: 12.5, weight: .medium)).foregroundStyle(s.t1).lineLimit(1)
                        Spacer()
                        Text("\(a.attuale) → \(a.nuova)").font(.system(size: 11).monospacedDigit()).foregroundStyle(s.t2)
                    }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.card)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            nota(T("Un clic apre l'app o l'App Store per aggiornarla.", "Click to open the app or the App Store to update."))
        }
    }

    @ViewBuilder private var lista: some View {
        if let a = m.appScelta, m.vista == .disinstalla {
            HStack(spacing: 8) {
                Image(nsImage: a.icona).resizable().frame(width: 26, height: 26)
                Text(a.nome).font(.system(size: 13, weight: .medium)).foregroundStyle(s.t1)
            }.padding(.leading, 4)
        }
        if let e = m.esito { nota(e) }
        if m.lavoro {
            attesa(m.vista == .pulizia ? T("Cerco cosa si può togliere…", "Looking for what can go…") : T("Un momento…", "One moment…"))
        } else if m.file.isEmpty {
            if m.esito == nil { nota(m.vista == .pulizia ? T("Niente da pulire.", "Nothing to clean.") : T("Scegli un'app.", "Choose an app.")) }
        } else {
            let gruppi = Array(Set(m.file.map(\.gruppo))).sorted()
            ForEach(gruppi, id: \.self) { g in
                Text(g).font(.system(size: 11, weight: .medium)).foregroundStyle(s.t2).padding(.leading, 4).padding(.top, 2)
                ForEach(m.file.indices.filter { m.file[$0].gruppo == g }, id: \.self) { i in
                    Button { m.file[i].scelta.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: m.file[i].scelta ? "checkmark.square.fill" : "square").font(.system(size: 13)).foregroundStyle(m.file[i].scelta ? s.t1 : s.t3)
                            Text(m.file[i].nome).font(.system(size: 11.5)).foregroundStyle(s.t1).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(Misura.byte(m.file[i].byte)).font(.system(size: 11).monospacedDigit()).foregroundStyle(s.t2)
                        }
                        .padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            let totale = m.file.filter(\.scelta).reduce(Int64(0)) { $0 + $1.byte }
            Button { m.cestina() } label: {
                Text(T("Sposta nel Cestino  ", "Move to Trash  ") + Misura.byte(totale))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(s.primT)
                    .frame(maxWidth: .infinity).frame(height: 30).background(Capsule().fill(s.prim))
            }.buttonStyle(.plain).disabled(totale == 0).opacity(totale == 0 ? 0.4 : 1).padding(.top, 4)
            nota(T("Niente si cancella: dal Cestino si torna indietro.", "Nothing is deleted: you can restore from the Trash."))
        }
    }

    private func attesa(_ t: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(t).font(.system(size: 11.5)).foregroundStyle(s.t2) }.padding(8)
    }
    private func nota(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundStyle(s.t2).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
    }
}
