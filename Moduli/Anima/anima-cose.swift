// Anima: le cose da fare, i promemoria e le abitudini (12/10/2026, da Hitodama: "To-do list", "Scheduled search",
// "Routine": "Every morning at 9:00, open Unity and Spotify").
// Le azioni le sceglie il modello fra un elenco fisso (anima.swift → AnimaBrain.comando); qui si eseguono.
// Le cose da fare dell'isola sono due liste in una: le sue (anima.json) e, solo nella build dell'autore, i Prossimi
// step di Spazio per lui (Personale/spazio-cose.swift). Nella vendita resta solo la lista locale.
import SwiftUI
import AppKit

final class AnimaCose: ObservableObject {
    static let shared = AnimaCose()

    struct Todo: Codable, Identifiable, Equatable { var id = UUID().uuidString; var testo: String; var fatto = false; var quando: Date? }
    struct Programma: Codable, Identifiable { var id = UUID().uuidString; var quando: Date; var azioni: String; var detto: String }
    struct Routine: Codable, Identifiable { var id = UUID().uuidString; var ora: String; var giorni: String; var azioni: String; var detto: String; var ultimo: String? }
    struct Step: Identifiable, Equatable { var id: String; var titolo: String }
    private struct Dati: Codable { var todo: [Todo] = []; var programmi: [Programma] = []; var routine: [Routine] = [] }

    @Published private(set) var todo: [Todo] = []
    // steps, priorita e studio li riempie solo la build dell'autore (Personale/spazio-cose.swift, tramite applicaEsterni):
    // nella vendita restano vuoti
    @Published private(set) var steps: [Step] = []
    @Published private(set) var routine: [Routine] = []
    /// La card "Priorità di oggi" di Spazio: il primo step aperto, chi lo fa, e la riga dello studio.
    @Published private(set) var priorita: (titolo: String, chi: String)?
    @Published private(set) var studio: String?
    @Published private(set) var studioRiga: (esame: String, valore: String)?    // per la riga-dato della tessera
    private var programmi: [Programma] = []
    private var timer: Timer?
    private(set) var ultimaLettura = Date.distantPast

    // MARK: ciò che scrive la fonte esterna (chiamato da Personale/spazio-cose.swift)

    /// Segna l'inizio di una lettura esterna (anche se poi non risponde, per non riprovare ogni 20 secondi).
    func segnaLettura(ora: Date) { ultimaLettura = ora }

    /// Mette nella lista e nella card Priorità quello che la fonte esterna ha risposto.
    func applicaEsterni(steps: [Step], priorita: (titolo: String, chi: String)?, studio: String?,
                        studioRiga: (esame: String, valore: String)?, ora: Date) {
        self.steps = steps
        self.priorita = priorita
        self.studio = studio
        self.studioRiga = studioRiga
        ultimaLettura = ora
    }

    /// Toglie dalla lista uno step appena segnato fatto fuori.
    func togliStep(_ s: Step) { steps.removeAll { $0 == s } }
    private let file = AnimaBrain.casa.appendingPathComponent("anima.json")

    func start() {
        if let d = try? Data(contentsOf: file), let x = try? JSONDecoder().decode(Dati.self, from: d) {
            todo = x.todo; programmi = x.programmi; routine = x.routine
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func salva() {
        let x = Dati(todo: todo, programmi: programmi, routine: routine)
        if let d = try? JSONEncoder().encode(x) { try? d.write(to: file, options: .atomic) }
    }

    // MARK: cose da fare

    func aggiungi(_ s: String, quando: Date? = nil) { todo.insert(Todo(testo: s, quando: quando), at: 0); salva() }
    func spunta(_ t: Todo) {
        guard let i = todo.firstIndex(of: t) else { return }
        todo[i].fatto.toggle()
        salva()
        // le cose fatte escono dalla lista dopo un attimo, così si vede la spunta
        if todo[i].fatto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.todo.removeAll { $0.id == t.id }; self?.salva()
            }
        }
    }
    var aperte: [Todo] { todo }   // le spuntate escono da sole dopo 1,5 s (spunta)

    // MARK: il tempo

    private func tick() {
        let now = Date()
        // Voce bloccata (prova finita, niente Complete): niente parte da sola; le cose salvate restano e ripartono al rinnovo
        guard RegistroModuli.deveEseguire(bloccato: RegistroModuli.shared.bloccato("anima")) else { return }
        // una volta: programmi e promemoria arrivati
        let pronti = programmi.filter { $0.quando <= now }
        if !pronti.isEmpty {
            programmi.removeAll { $0.quando <= now }
            salva()
            for p in pronti { fai(p.azioni, detto: p.detto) }
        }
        // ogni giorno
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let oggi = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        let ora = f.string(from: now)
        let wd = Calendar.current.component(.weekday, from: now)   // 1 = domenica
        let weekend = wd == 1 || wd == 7
        for i in routine.indices where routine[i].ora <= ora && routine[i].ultimo != oggi {
            let g = routine[i].giorni
            guard g == "tutti" || (g == "feriali" && !weekend) || (g == "weekend" && weekend) else { continue }
            // dopo un'ora di ritardo (Mac spento o in stop) si salta, non si recupera a sorpresa
            if let h = f.date(from: routine[i].ora), let n = f.date(from: ora), n.timeIntervalSince(h) > 3600 { routine[i].ultimo = oggi; continue }
            routine[i].ultimo = oggi
            fai(routine[i].azioni, detto: routine[i].detto)
        }
        salva()
    }

    private func fai(_ json: String, detto: String) {
        guard let d = json.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        let fatto = esegui(a)
        Anima.shared.show(detto, fatto, for: 8)
    }

    // MARK: eseguire

    /// Esegue le azioni scelte dal modello e dice in una riga cosa ha fatto.
    @discardableResult
    func esegui(_ azioni: [[String: Any]]) -> String {
        var fatto: [String] = []
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        iso.timeZone = .current
        func data(_ s: Any?) -> Date? {
            guard var s = s as? String, !s.isEmpty else { return nil }
            if s.count == 16 { s += ":00" }
            return iso.date(from: s)
        }
        func json(_ x: Any?) -> String {
            guard let x, let d = try? JSONSerialization.data(withJSONObject: x) else { return "[]" }
            return String(data: d, encoding: .utf8) ?? "[]"
        }
        let quandoF = DateFormatter(); quandoF.locale = Locale(identifier: pulsarItalian ? "it_IT" : "en_US"); quandoF.dateFormat = "d MMM HH:mm"
        for a in azioni {
            switch a["tipo"] as? String ?? "" {
            case "apri_app":
                guard let n = a["nome"] as? String, let u = Self.app(n) else { fatto.append(T("App non trovata", "App not found")); continue }
                NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
                fatto.append(T("Apro ", "Opening ") + u.deletingPathExtension().lastPathComponent)
            case "apri_url":
                guard let s = a["url"] as? String, s.hasPrefix("https://") || s.hasPrefix("http://"), let u = URL(string: s) else { continue }
                NSWorkspace.shared.open(u)
                fatto.append(T("Apro ", "Opening ") + (u.host ?? s))
            case "cerca":
                let t = (a["testo"] as? String ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let dove = a["dove"] as? String ?? "google"
                let s: String = {
                    switch dove {
                    case "youtube": return "https://www.youtube.com/results?search_query=" + t
                    case "amazon": return "https://www.amazon.it/s?k=" + t
                    case "spotify": return "spotify:search:" + t
                    case "maps": return "https://maps.apple.com/?q=" + t
                    default: return "https://www.google.com/search?q=" + t
                    }
                }()
                if let u = URL(string: s) { NSWorkspace.shared.open(u) }
                fatto.append(T("Cerco su ", "Searching ") + dove.capitalized)
            case "todo":
                guard let t = a["testo"] as? String, !t.isEmpty else { continue }
                aggiungi(t)
                fatto.append(T("Aggiunto alla lista: ", "Added to the list: ") + t)
            case "promemoria":
                guard let t = a["testo"] as? String, let q = data(a["quando"]), q > Date() else { continue }
                programmi.append(Programma(quando: q, azioni: json([["tipo": "avviso", "testo": t]]), detto: T("Promemoria", "Reminder")))
                salva()
                fatto.append(T("Te lo ricordo il ", "I'll remind you on ") + quandoF.string(from: q))
            case "avviso":
                fatto.append(a["testo"] as? String ?? "")
                NSSound(named: "Glass")?.play()
            case "programma":
                guard let q = data(a["quando"]), q > Date() else { continue }
                programmi.append(Programma(quando: q, azioni: json(a["azioni"]), detto: T("Programmato", "Scheduled")))
                salva()
                fatto.append(T("Lo faccio il ", "Scheduled for ") + quandoF.string(from: q))
            case "routine":
                guard let o = a["ora"] as? String, o.count == 5 else { continue }
                let g = a["giorni"] as? String ?? "tutti"
                routine.append(Routine(ora: o, giorni: g, azioni: json(a["azioni"]), detto: T("Abitudine delle ", "Routine at ") + o))
                salva()
                fatto.append(T("Ogni giorno alle ", "Every day at ") + o)
            case "timer":
                let m = (a["minuti"] as? Double) ?? Double(a["minuti"] as? Int ?? 0)
                guard m > 0 else { continue }
                programmi.append(Programma(quando: Date().addingTimeInterval(m * 60), azioni: json([["tipo": "avviso", "testo": T("Tempo scaduto", "Time's up")]]),
                                           detto: T("Timer di \(Int(m)) min", "\(Int(m)) min timer")))
                salva()
                fatto.append(T("Timer di \(Int(m)) minuti", "\(Int(m)) minute timer"))
            default: break
            }
        }
        return fatto.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func togliRoutine(_ r: Routine) { routine.removeAll { $0.id == r.id }; salva() }

    /// Trova un'app per nome (anche in italiano o senza maiuscole) fra quelle installate.
    static func app(_ nome: String) -> URL? {
        let n = nome.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: ".app", with: "")
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var tutte: [URL] = []
        for d in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
            tutte += items.filter { $0.hasSuffix(".app") }.map { URL(fileURLWithPath: d).appendingPathComponent($0) }
        }
        func base(_ u: URL) -> String { u.deletingPathExtension().lastPathComponent.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        return tutte.first { base($0) == n } ?? tutte.first { base($0).hasPrefix(n) } ?? tutte.first { base($0).contains(n) }
    }
}

// MARK: - La tessera "Cose da fare"

struct TodoWidget: IslandWidget {
    let id = "todo"
    var title: String { T("Cose da fare", "To-do") }
    let symbol = "checklist"
    func body(cells: Int) -> AnyView { AnyView(TodoTile(cose: .shared, cells: cells)) }
}

private struct TodoTile: View {
    @ObservedObject var cose: AnimaCose
    let cells: Int

    private enum Riga: Identifiable {
        case mia(AnimaCose.Todo), step(AnimaCose.Step)
        var id: String { switch self { case .mia(let t): return "t" + t.id; case .step(let s): return "s" + s.id } }
    }

    var body: some View {
        let righe: [Riga] = cose.aperte.map { .mia($0) } + cose.steps.map { .step($0) }
        if cells >= 2, let p = cose.priorita {
            // 12/10 notte, l'autore: "su priorità fai una bella UI e riempi bene lo spazio". Grammatica stile-lori:
            // pila a tre livelli (etichetta chiara, titolo regular grande), in fondo la riga-dato di Margin (mono ai due estremi)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    StellaShape().fill(DotColors.azzurro).frame(width: 9, height: 9)
                    Text(T("Priorità di oggi", "Today's priority")).font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.5))
                    Spacer(minLength: 4)
                    Text(p.chi.uppercased()).font(.system(size: 8.5, design: .monospaced)).tracking(1.1).foregroundStyle(Color.primary.opacity(0.42))
                }
                Text(p.titolo)
                    .font(.system(size: 14.5, weight: .regular)).tracking(-0.2)
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(2).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                Spacer(minLength: 4)
                if let r = cose.studioRiga {
                    VStack(spacing: 4) {
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                        HStack {
                            Text(r.esame.uppercased()).lineLimit(1).foregroundStyle(Color.primary.opacity(0.5))
                            Spacer(minLength: 8)
                            Text(r.valore.uppercased()).lineLimit(1).fixedSize().foregroundStyle(Color.primary.opacity(0.88))
                        }
                        .font(.system(size: 8.5, design: .monospaced)).tracking(1.0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if righe.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checklist").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                if cells > 1 { Text(T("Tieni ⌃⌘ e dimmi cosa", "Hold ⌃⌘ and tell me")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cells == 1 {
            VStack(spacing: 4) {
                Image(systemName: "checklist").font(.system(size: 18))
                Text("\(righe.count)").font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(righe.prefix(3)) { r in
                    switch r {
                    case .mia(let t): riga(t.testo, fatto: t.fatto, esterna: false) { cose.spunta(t) }
                    case .step(let s): riga(s.titolo, fatto: false, esterna: true) {
                    }
                    }
                }
            }
        }
    }

    private func riga(_ testo: String, fatto: Bool, esterna: Bool, _ tap: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Button(action: tap) {
                Image(systemName: fatto ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(fatto ? 0.8 : 0.45))
                    .frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(aiuto(esterna))
            Text(testo).font(.system(size: 11)).lineLimit(1).strikethrough(fatto)
                .foregroundStyle(Color.primary.opacity(fatto ? 0.4 : 0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func aiuto(_ esterna: Bool) -> String {
        return T("Fatto", "Done")
    }
}
