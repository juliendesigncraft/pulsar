// Promesse: il motore, la tessera "In attesa" e l'avviso nel notch (01/11/2026, da Kier: "It remembers what you promised.
// It taps you when it's due. And notices when it's done."). Ogni 10 minuti legge i messaggi nuovi di WhatsApp e Mail,
// il modello locale (Ollama, lo stesso dell'Anima) sceglie le frasi che sono promesse, la data la legge PromesseLogica.
// Salva solo le promesse (titolo, persona, la frase), mai i messaggi. Niente esce dal Mac.
import SwiftUI
import AppKit

final class Promesse: ObservableObject {
    static let shared = Promesse()

    @Published private(set) var lista: [Promessa] = []
    @Published private(set) var lavora = false
    @Published private(set) var demo = false

    private struct Dati: Codable { var lista: [Promessa] = []; var waPK = 0 }
    private var dati = Dati()
    private var timer: Timer?
    private var giri = 0                // Mail una volta ogni 5 giri
    private var pkPrima = 0             // dove riprendere se il modello non risponde
    private var file: URL { Cartelle.dati.appendingPathComponent("promesse.json") }
    private var fileStato: URL { Cartelle.dati.appendingPathComponent("promesse-stato.txt") }

    /// L'interruttore "Promesse" (Personalizza). Acceso di serie: senza Ollama acceso non legge niente.
    static var enabled: Bool {
        get { Impostazioni.object(.isolaPromesse) as? Bool ?? true }
        set { Impostazioni.set(newValue, .isolaPromesse) }
    }

    var aperte: [Promessa] { PromesseLogica.ordina(lista) }
    func dovute(_ ora: Date = Date()) -> [Promessa] { PromesseLogica.dovute(lista, ora: ora) }

    func start() {
        if let d = try? Data(contentsOf: file), let x = try? JSONDecoder().decode(Dati.self, from: d) { dati = x; lista = x.lista }
        guard timer == nil else { return }
        // 09/11: WhatsApp ogni 2 minuti (è una lettura leggera del file), Mail ogni 10 come prima
        let t = Timer(timeInterval: 120, repeats: true) { [weak self] _ in self?.leggi() }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.leggi() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func salva() {
        guard !demo else { return }             // i dati del reel non toccano mai il file vero
        dati.lista = lista
        if let d = try? JSONEncoder().encode(dati) { try? d.write(to: file, options: .atomic) }
    }

    // MARK: tasti

    func fatta(_ p: Promessa, perche: String = T("Segnata a mano", "Marked by hand")) {
        guard let i = lista.firstIndex(where: { $0.id == p.id }) else { return }
        lista[i].fatta = Date(); lista[i].perche = perche
        salva()
    }

    /// Domani alle 9 (tasto Domani dell'avviso).
    func rimanda(_ p: Promessa) {
        guard let i = lista.firstIndex(where: { $0.id == p.id }) else { return }
        let cal = Calendar.current
        lista[i].rimandata = cal.date(byAdding: .day, value: 1, to: Date()).flatMap {
            cal.date(bySettingHour: PromesseLogica.oraAvviso, minute: 0, second: 0, of: $0)
        }
        salva()
    }

    func togli(_ p: Promessa) { lista.removeAll { $0.id == p.id }; salva() }

    // MARK: lettura

    /// Un giro: WhatsApp e Mail, poi chi è fatta, poi il modello sulle frasi nuove.
    func leggi() {
        guard Self.enabled, !demo, !lavora else { return }
        lavora = true
        let pk = dati.waPK
        let conMail = giri % 5 == 0
        giri += 1
        pkPrima = pk
        // le chat delle promesse aperte: i tuoi messaggi dopo la promessa contano anche se già letti in un giro passato
        let aperte = lista.filter { $0.aperta && $0.fonte == "WhatsApp" }
        let chat = Array(Set(aperte.compactMap { Int64($0.chatID.dropFirst(3)) }))
        let daQuando = aperte.map(\.detta).min() ?? Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let wa = FonteWhatsApp.esiste ? FonteWhatsApp.leggi(dopoPK: pk) : ([], pk, "WhatsApp non c'è")
            let miei = FonteWhatsApp.esiste ? FonteWhatsApp.mieiDopo(chat: chat, da: daQuando) : []
            let finisci: ([PMessaggio], String?) -> Void = { mail, errMail in
                DispatchQueue.main.async {
                    self?.giro(messaggi: wa.messaggi + mail, miei: miei, waPK: wa.ultimoPK, note: [wa.errore, errMail].compactMap { $0 })
                }
            }
            if conMail { FonteMail.leggi(giorni: pk == 0 ? 4 : 2, finisci) } else { finisci([], nil) }
        }
    }

    private func giro(messaggi: [PMessaggio], miei: [PMessaggio], waPK: Int, note: [String]) {
        dati.waPK = waPK
        // 1. le promesse aperte che i messaggi chiudono: la comparsa solo se la risposta è di adesso
        var chiuse = 0
        let adesso = Date()
        let perChiudere = messaggi + miei
        for (i, p) in lista.enumerated() where p.aperta && PromesseLogica.sembraFatta(p, dopo: perChiudere) {
            lista[i].fatta = adesso; lista[i].perche = T("Hai risposto nella chat", "You replied in the chat")
            chiuse += 1
            let ultimo = perChiudere.filter { $0.chatID == p.chatID && $0.daMe }.map(\.data).max() ?? .distantPast
            guard PromesseLogica.fresca(ultimo, ora: adesso) else { continue }
            PeekCenter.shared.post(PeekItem(key: "promessa-fatta-\(p.id)", kind: "info", symbol: "checkmark.circle.fill",
                                            title: p.titolo, detail: T("Fatta. Hai risposto nella chat", "Done. You replied in the chat"),
                                            priority: 60, duration: 4))
        }
        // quelle troppo vecchie escono in silenzio
        for (i, p) in lista.enumerated() where PromesseLogica.daArchiviare(p, ora: adesso) {
            lista[i].fatta = adesso; lista[i].perche = T("Troppo vecchia", "Too old")
        }
        // 2. le frasi nuove che sembrano promesse, al modello in gruppi da 20 (le più recenti)
        let viste = Set(lista.map(\.id))
        let candidati = Array(messaggi.filter { PromesseLogica.candidato($0) && !viste.contains($0.id) }.suffix(60))
        scriviStato("messaggi=\(messaggi.count) candidati=\(candidati.count) chiuse=\(chiuse) note=\(note.joined(separator: "; "))")
        salva()
        let gruppi = stride(from: 0, to: candidati.count, by: 20).map { Array(candidati[$0..<min($0 + 20, candidati.count)]) }
        chiedi(gruppi, trovate: 0)
    }

    private func chiedi(_ gruppi: [[PMessaggio]], trovate: Int) {
        guard let g = gruppi.first else {
            lavora = false
            scriviStato("fine giro, promesse nuove=\(trovate)", aggiungi: true)
            return
        }
        AnimaBrain.genera(PromesseLogica.domanda(g), json: true) { [weak self] r in
            guard let self else { return }
            let nuove = r.map { PromesseLogica.leggiModello($0, messaggi: g) } ?? []
            if r == nil {
                // senza risposta del modello quei messaggi si rileggono al giro dopo: prima andavano persi
                self.scriviStato("modello: nessuna risposta (Ollama spento?)", aggiungi: true)
                self.dati.waPK = self.pkPrima
            }
            self.lista = PromesseLogica.unisci(self.lista, nuove)
            self.salva()
            let ritardi = nuove.map { Int(Date().timeIntervalSince($0.detta) / 60) }
            if let m = ritardi.max() { self.scriviStato("ritardo massimo in minuti=\(m)", aggiungi: true) }
            for p in nuove.prefix(2) where PromesseLogica.fresca(p.detta, ora: Date()) {   // su un messaggio vecchio niente avviso
                PeekCenter.shared.post(PeekItem(key: "promessa-nuova-\(p.id)", kind: "info", symbol: "checklist",
                                                title: p.titolo, detail: "\(p.chi) · \(p.fonte)", priority: 50, duration: 4))
            }
            self.chiedi(Array(gruppi.dropFirst()), trovate: trovate + nuove.count)
        }
    }

    /// Solo numeri e note tecniche, mai il testo di un messaggio.
    private func scriviStato(_ s: String, aggiungi: Bool = false) {
        let riga = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if aggiungi, let h = try? FileHandle(forWritingTo: fileStato) { h.seekToEndOfFile(); h.write(Data(riga.utf8)); try? h.close() }
        else { try? riga.write(to: fileStato, atomically: true, encoding: .utf8) }
    }

    // MARK: reel e prove (dati inventati, in inglese)

    /// pulsar://promesse?demo=1 carica promesse finte; dovuta=1 ne fa scadere una adesso; demo=0 torna ai dati veri.
    func caricaDemo(_ acceso: Bool, dovuta: Bool = false) {
        guard acceso else { demo = false; start(); lista = dati.lista; return }
        demo = true
        let cal = Calendar.current, ora = Date()
        func tra(_ g: Int) -> Date { cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: g, to: ora)!)! }
        let venerdi = cal.nextDate(after: ora, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)
            .flatMap { cal.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } ?? tra(3)
        lista = [
            Promessa(id: "demo-1", titolo: "Send Marta the logo files", chi: "Marta", fonte: "WhatsApp", chatID: "demo-a",
                     citazione: "Sure, I'll send you the files by Friday", mia: true, detta: tra(-1).addingTimeInterval(26000),
                     scadenza: dovuta ? ora.addingTimeInterval(-60) : venerdi),
            Promessa(id: "demo-2", titolo: "Reply to the print shop quote", chi: "Print shop", fonte: "Mail", chatID: "demo-b",
                     citazione: "Could you confirm the quote today?", mia: false, detta: ora.addingTimeInterval(-7200), scadenza: tra(0).addingTimeInterval(32400)),
            Promessa(id: "demo-3", titolo: "Book the table for Saturday", chi: "Luca", fonte: "WhatsApp", chatID: "demo-c",
                     citazione: "Can you book for Saturday? I'm on the train", mia: false, detta: ora.addingTimeInterval(-3600),
                     scadenza: cal.nextDate(after: ora, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)),
            Promessa(id: "demo-4", titolo: "Pay the studio invoice", chi: "Studio rent", fonte: "Mail", chatID: "demo-d",
                     citazione: "The invoice is due on the 14th", mia: false, detta: tra(-2), scadenza: tra(12)),
        ]
    }

    /// pulsar://promesse?fatta=1: la prima promessa finta si chiude da sola, come quando rispondi nella chat.
    func demoFatta() {
        guard demo, let p = aperte.first else { return }
        fatta(p, perche: T("Hai risposto nella chat", "You replied in the chat"))
        PeekCenter.shared.post(PeekItem(key: "promessa-fatta-\(p.id)", kind: "info", symbol: "checkmark.circle.fill",
                                        title: p.titolo, detail: T("Fatta. Hai risposto nella chat", "Done. You replied in the chat"),
                                        priority: 60, duration: 4))
    }

    func apriFonte(_ p: Promessa) {
        let app = p.fonte == "Mail" ? "com.apple.mail" : WhatsAppReader.bundle
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) { NSWorkspace.shared.openApplication(at: u, configuration: .init()) }
    }
}


// MARK: - L'avviso nel notch quando scade

final class PromesseSource: IslandSource {
    let id = "promesse"
    let priority = 84                       // appena sotto i promemoria (85)
    var onChange: (() -> Void)?
    var chiudi: (() -> Void)?
    private var timer: Timer?
    private var eraAttiva = false
    private var giaViste: Set<String> = []

    var prima: Promessa? { Promesse.enabled ? Promesse.shared.dovute().first : nil }
    var isActive: Bool { prima != nil }

    func start() {
        Promesse.shared.start()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.ricontrolla() }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil; eraAttiva = false }

    func ricontrolla() {
        let p = prima
        if let p, !giaViste.contains(p.id + "\(p.rimandata?.timeIntervalSince1970 ?? 0)") {
            giaViste.insert(p.id + "\(p.rimandata?.timeIntervalSince1970 ?? 0)")
            PeekCenter.shared.post(PeekItem(key: "promessa-\(p.id)", kind: "info", symbol: "hand.raised.fill", title: p.titolo,
                                            detail: p.mia ? T("Lo avevi promesso", "You promised") : T("Te l'ha chiesto \(p.chi)", "\(p.chi) asked you"),
                                            priority: 70, duration: 5))
        }
        let ora = p != nil
        if ora != eraAttiva || ora { eraAttiva = ora; onChange?() }
    }

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: "hand.raised.fill").font(.system(size: 11)).foregroundStyle(Volta.a2))
    }

    func compactTrailing() -> AnyView {
        guard let p = prima else { return AnyView(EmptyView()) }
        return AnyView(Text(p.chi).font(.system(size: 10.5)).foregroundStyle(Volta.a2).lineLimit(1).frame(maxWidth: 70))
    }

    var panelSize: CGSize? { CGSize(width: 600, height: 168) }

    func expandedView() -> AnyView {
        guard let p = prima else { return AnyView(EmptyView()) }
        return AnyView(PromessaVista(p: p,
            fatta: { [weak self] in Promesse.shared.fatta(p); self?.dopo() },
            domani: { [weak self] in Promesse.shared.rimanda(p); self?.dopo() },
            apri: { [weak self] in Promesse.shared.apriFonte(p); self?.chiudi?() }))
    }

    private func dopo() {
        chiudi?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.ricontrolla() }
    }
}

/// La vista aperta: chi l'ha chiesta, il titolo, la frase vera, dove e quando; Domani e Fatto a destra.
struct PromessaVista: View {
    let p: Promessa
    let fatta: () -> Void
    let domani: () -> Void
    let apri: () -> Void
    private var quando: String {
        let f = DateFormatter(); f.locale = Locale(identifier: pulsarItalian ? "it_IT" : "en_US"); f.dateFormat = "EEE HH:mm"
        return f.string(from: p.detta)
    }
    var body: some View {
        VCard(glow: Volta.a2, breathe: true, padding: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    VWho(project: p.mia ? T("La tua promessa", "Your promise") : T("Ti ha chiesto \(p.chi)", "\(p.chi) asked you"),
                         what: PromesseLogica.etichetta(p.scadenza, ora: Date(), it: pulsarItalian) ?? "")
                    Text(p.titolo).font(.system(size: 17, weight: .regular)).tracking(-0.2).foregroundStyle(Volta.t1).lineLimit(1)
                    Text("“\(p.citazione)”").font(.system(size: 12.5)).foregroundStyle(Volta.t2).lineLimit(1).truncationMode(.tail)
                    Button(action: apri) {
                        Text((p.mia ? T("A ", "To ") : T("Da ", "From ")) + "\(p.chi), \(p.fonte), \(quando)")
                            .font(.system(size: 11)).foregroundStyle(Volta.t3)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VPill(title: T("Domani", "Tomorrow"), kind: .normal, action: domani)
                VPill(title: T("Fatto", "Done"), kind: .primary, action: fatta)
            }
        }
        .frame(height: 168)
    }
}

// MARK: - La tessera "In attesa"

struct PromesseWidget: IslandWidget {
    let id = "promesse"
    var title: String { T("In attesa", "Waiting on you") }
    let symbol = "hand.raised"
    func body(cells: Int) -> AnyView { AnyView(PromesseTile(p: .shared, cells: cells)) }
}

private struct PromesseTile: View {
    @ObservedObject var p: Promesse
    let cells: Int

    var body: some View {
        let righe = p.aperte
        if righe.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "hand.raised").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                if cells > 1 {
                    Text(p.lavora ? T("Leggo le chat…", "Reading your chats…") : T("Nessuna promessa aperta", "Nothing waiting on you"))
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cells == 1 {
            VStack(spacing: 4) {
                Image(systemName: "hand.raised.fill").font(.system(size: 17))
                Text("\(righe.count)").font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(T("In attesa", "Waiting on you")).font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.5))
                    Spacer(minLength: 4)
                    Text("\(righe.count)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Color.primary.opacity(0.42))
                }
                .padding(.bottom, 4)
                ForEach(righe.prefix(3)) { r in riga(r) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func riga(_ r: Promessa) -> some View {
        HStack(spacing: 7) {
            Button { withAnimation(.easeOut(duration: 0.25)) { p.fatta(r) } } label: {
                Circle().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1.2).frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.titolo).font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.9)).lineLimit(1)
                if cells >= 3 {
                    Text("\(r.chi) · \(r.fonte)").font(.system(size: 9.5)).foregroundStyle(Color.primary.opacity(0.45)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let e = PromesseLogica.etichetta(r.scadenza, ora: Date(), it: pulsarItalian) {
                // niente fondino dietro l'etichetta (regola dell'autore): solo il colore
                Text(e).font(.system(size: 10, weight: .medium)).foregroundStyle(Volta.a2).fixedSize()
            }
        }
        .padding(.vertical, cells >= 3 ? 3 : 2)
        .contentShape(Rectangle())
        .onTapGesture { p.apriFonte(r) }
    }
}
