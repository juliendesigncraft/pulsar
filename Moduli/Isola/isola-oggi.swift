// La scheda Oggi dell'isola (31/10/2026), dal reel di NotchOwl che l'autore ha mandato: nel notch le attività di oggi,
// un timer di concentrazione con le cifre a puntini, una nota e gli eventi del calendario, una card accanto all'altra.
// Tre viste come nel riferimento: Lavoro (le card), Andamento (gli ultimi 7 giorni) e Personalizza (quali card e in che ordine).
// Rifatta nella grammatica dell'isola nuova (VCard, Volta, niente contorni) e senza doppioni: le attività sono la lista
// dell'Anima (AnimaCose), il timer è quello della Ghiera (DialStore), gli eventi vengono da CalendarModel.
// I promemoria nel notch stanno in isola-promemoria.swift; l'ora a destra del notch nella testa (isola-nuova.swift).
import SwiftUI
import AppKit

// MARK: - L'ora in testo

enum OraTesto {
    static func hm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    static func giorno(_ d: Date, _ template: String = "EEEE d MMMM") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: pulsarItalian ? "it_IT" : "en_GB")
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d).capitalized
    }
}

// MARK: - Lo stato della scheda

enum OggiMetrics {
    static let altezza: CGFloat = 196
    static let larghezza: CGFloat = 1000
}

/// Quale vista è aperta, e quali card si vedono in Lavoro e in che ordine (salvato).
final class OggiStato: ObservableObject {
    static let shared = OggiStato()
    enum Vista: CaseIterable { case lavoro, andamento, personalizza
        var titolo: String {
            switch self { case .lavoro: return T("Lavoro", "Workspace"); case .andamento: return T("Andamento", "Insights"); case .personalizza: return T("Personalizza", "Customize") }
        }
    }
    enum Card: String, CaseIterable, Identifiable {
        case attivita, focus, nota, eventi
        var id: String { rawValue }
        var titolo: String {
            switch self { case .attivita: return T("Attività", "Tasks"); case .focus: return "Focus"; case .nota: return T("Nota", "Note"); case .eventi: return T("Eventi", "Events") }
        }
        var simbolo: String {
            switch self { case .attivita: return "checklist"; case .focus: return "timer"; case .nota: return "note.text"; case .eventi: return "calendar" }
        }
    }

    @Published var vista: Vista = .lavoro
    @Published var ordine: [Card] {
        didSet { Impostazioni.set(ordine.map(\.rawValue), .isolaOggiOrdine) }
    }
    @Published var nascoste: Set<Card> {
        didSet { Impostazioni.set(nascoste.map(\.rawValue), .isolaOggiNascoste) }
    }

    init() {
        let o = (Impostazioni.stringArray(.isolaOggiOrdine) ?? []).compactMap(Card.init(rawValue:))
        ordine = o.count == Card.allCases.count ? o : Card.allCases           // una card nuova in un aggiornamento: si riparte dall'ordine di serie
        nascoste = Set((Impostazioni.stringArray(.isolaOggiNascoste) ?? []).compactMap(Card.init(rawValue:)))
    }

    var visibili: [Card] { ordine.filter { !nascoste.contains($0) } }

    func sposta(_ c: Card, di d: Int) {
        guard let i = ordine.firstIndex(of: c) else { return }
        let j = i + d
        guard ordine.indices.contains(j) else { return }
        ordine.swapAt(i, j)
    }
    func ripristina() { ordine = Card.allCases; nascoste = [] }
}

// MARK: - Lo storico per l'Andamento

/// Per ogni giorno: attività aggiunte, attività fatte, secondi di focus finiti. Solo sul Mac, ultimi 60 giorni.
final class OggiStoria: ObservableObject {
    static let shared = OggiStoria()
    struct Giorno: Codable, Equatable { var aggiunte = 0; var fatte = 0; var focus = 0 }
    enum Evento { case aggiunta, fatta, focus(secondi: Int) }

    @Published private(set) var giorni: [String: Giorno] = [:]

    init() {
        if let d = Impostazioni.data(.isolaOggiStoria), let g = try? JSONDecoder().decode([String: Giorno].self, from: d) { giorni = g }
    }

    static func chiave(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func segna(_ e: Evento, _ quando: Date = Date()) {
        let k = Self.chiave(quando)
        var g = giorni[k] ?? Giorno()
        switch e {
        case .aggiunta: g.aggiunte += 1
        case .fatta: g.fatte += 1
        case .focus(let s): g.focus += s
        }
        giorni[k] = g
        if giorni.count > 60, let vecchio = giorni.keys.sorted().first { giorni[vecchio] = nil }
        if let d = try? JSONEncoder().encode(giorni) { Impostazioni.set(d, .isolaOggiStoria) }
    }

    /// Gli ultimi n giorni fino a oggi, dal più vecchio (con `prima` = quanti giorni indietro partire).
    func ultimi(_ n: Int, prima: Int = 0) -> [(data: Date, g: Giorno)] {
        let cal = Calendar.current, oggi = cal.startOfDay(for: Date())
        return (0..<n).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -(i + prima), to: oggi).map { ($0, giorni[Self.chiave($0)] ?? Giorno()) }
        }
    }
}

// MARK: - La testa: viste e ora

/// A destra del notch, nella testa del pannello: le tre viste (solo nella scheda Oggi) e l'ora con il giorno.
struct OggiTestaDestra: View {
    let mostraViste: Bool
    var stato: String = ""
    @ObservedObject private var s = OggiStato.shared
    var body: some View {
        HStack(spacing: 10) {
            if mostraViste {
                HStack(spacing: 2) {
                    ForEach(OggiStato.Vista.allCases, id: \.self) { v in
                        Button { withAnimation(.easeOut(duration: 0.2)) { s.vista = v } } label: {
                            Text(v.titolo).font(.system(size: 11.5, weight: s.vista == v ? .medium : .regular))
                                .foregroundStyle(s.vista == v ? Volta.t1 : Volta.t3)
                                .padding(.horizontal, 10).frame(height: 22)
                                .background(Capsule().fill(s.vista == v ? Volta.pill : .clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !stato.isEmpty {
                Text(stato).font(.system(size: 11.5)).foregroundStyle(Volta.t3).lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                HStack(spacing: 6) {
                    Text(OraTesto.giorno(ctx.date, "EEE d")).foregroundStyle(Volta.t3)
                    Text(OraTesto.hm(ctx.date)).foregroundStyle(Volta.t1).monospacedDigit()
                }
                .font(.system(size: 11.5, weight: .medium)).lineLimit(1).fixedSize()
            }
        }
        .padding(.trailing, 4)
    }
}

// MARK: - La scheda Oggi

struct IslandOggi: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var s = OggiStato.shared
    var body: some View {
        Group {
            switch s.vista {
            case .lavoro: lavoro
            case .andamento: AndamentoVista()
            case .personalizza: PersonalizzaVista(store: model.dial?.store)
            }
        }
        .frame(height: OggiMetrics.altezza)
    }

    @ViewBuilder private var lavoro: some View {
        if s.visibili.isEmpty {
            VCard(padding: 16) {
                Text(T("Nessuna card accesa. Sceglile in Personalizza.", "No cards on. Pick them in Customize."))
                    .font(.system(size: 12.5)).foregroundStyle(Volta.t3).frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                ForEach(s.visibili) { c in
                    switch c {
                    case .attivita: AttivitaCard().frame(minWidth: 260, maxWidth: .infinity)
                    case .focus: FocusCard(store: model.dial?.store).frame(width: 214)
                    case .nota: NotaCard().frame(width: 214)
                    case .eventi: EventiCard().frame(width: 230)
                    }
                }
            }
        }
    }
}

/// Il titolo piccolo di ogni card: icona, nome, e a destra un dettaglio tenue.
private struct OggiTesta: View {
    let symbol: String
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Volta.a2)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Volta.t1).lineLimit(1)
            Spacer(minLength: 4)
            if !detail.isEmpty { Text(detail).font(.system(size: 11.5)).foregroundStyle(Volta.t3).lineLimit(1) }
        }
    }
}

/// Una riga-dato: etichetta a sinistra, valore a destra (la firma di Margin).
private struct RigaDato: View {
    let etichetta: String
    let valore: String
    var body: some View {
        HStack {
            Text(etichetta).foregroundStyle(Volta.t2)
            Spacer(minLength: 6)
            Text(valore).foregroundStyle(Volta.t1).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

// MARK: Attività

/// Le cose da fare dell'Anima: si spuntano col cerchio, si aggiungono scrivendo in fondo (Invio),
/// e la campanella dà un'ora: a quell'ora il promemoria esce dal notch.
private struct AttivitaCard: View {
    @ObservedObject private var cose = AnimaCose.shared
    @State private var nuova = ""

    var body: some View {
        VCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                OggiTesta(symbol: "checklist", title: T("Attività", "Tasks"),
                          detail: cose.aperte.isEmpty ? "" : T("\(cose.aperte.count) da fare", "\(cose.aperte.count) to do"))
                if cose.aperte.isEmpty {
                    Spacer(minLength: 0)
                    Text(T("Niente in lista. Scrivi qui sotto la prima.", "Nothing on the list. Write the first one below."))
                        .font(.system(size: 12.5)).foregroundStyle(Volta.t3)
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(cose.aperte) { t in riga(t) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Volta.t3)
                    TextField(T("Aggiungi un'attività", "Add a task"), text: $nuova)
                        .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Volta.t1)
                        .onSubmit(aggiungi)
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(Capsule().fill(Volta.card2))
            }
        }
        .onAppear { cose.start() }
    }

    private func riga(_ t: AnimaCose.Todo) -> some View {
        HStack(spacing: 9) {
            Button { withAnimation(.easeOut(duration: 0.25)) { cose.spunta(t) } } label: {
                ZStack {
                    Circle().strokeBorder(Volta.t3, lineWidth: 1.2).opacity(t.fatto ? 0 : 1)
                    if t.fatto { Circle().fill(Volta.a2); Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Volta.body) }
                }
                .frame(width: 15, height: 15).contentShape(Circle())
            }
            .buttonStyle(.plain)
            Text(t.testo).font(.system(size: 12.5)).foregroundStyle(t.fatto ? Volta.t3 : Volta.t1)
                .strikethrough(t.fatto, color: Volta.t3).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button(T("Tra 15 minuti", "In 15 minutes")) { cose.promemoria(t, Date().addingTimeInterval(15 * 60)) }
                Button(T("Tra un'ora", "In an hour")) { cose.promemoria(t, Date().addingTimeInterval(3600)) }
                Button(T("Stasera alle 18", "This evening at 6 pm")) { cose.promemoria(t, Self.alle(18, domani: false)) }
                Button(T("Domani alle 9", "Tomorrow at 9 am")) { cose.promemoria(t, Self.alle(9, domani: true)) }
                if t.quando != nil { Divider(); Button(T("Togli il promemoria", "Remove reminder")) { cose.promemoria(t, nil) } }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: t.quando == nil ? "bell" : "bell.fill").font(.system(size: 10))
                    if let q = t.quando { Text(OraTesto.hm(q)).font(.system(size: 11).monospacedDigit()) }
                }
                .foregroundStyle(t.quando == nil ? Volta.t3 : Volta.a2)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(T("Promemoria nel notch", "Reminder in the notch"))
        }
        .padding(.vertical, 4)
    }

    /// Le 18 di oggi (o di domani se sono già passate), le 9 di domani.
    private static func alle(_ h: Int, domani: Bool) -> Date {
        let cal = Calendar.current
        var d = cal.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        if domani || d <= Date() { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    private func aggiungi() {
        let s = nuova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) { cose.aggiungi(s) }
        nuova = ""
    }
}

// MARK: Focus

/// Il timer della Ghiera, a puntini: un solo timer in tutta Pulsar, quindi parte e si ferma anche dalla ghiera.
private struct FocusCard: View {
    let store: DialStore?
    var body: some View {
        if let store { Inner(store: store) }
        else {
            VCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    OggiTesta(symbol: "timer", title: "Focus")
                    Spacer(minLength: 0)
                    Text(T("Accendi la Ghiera nelle Impostazioni per usare il timer.", "Turn on the Dial in Settings to use the timer."))
                        .font(.system(size: 12)).foregroundStyle(Volta.t3)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private struct Inner: View {
        @ObservedObject var store: DialStore
        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let total = Double(store.timerMinutes * 60)
                let left: Double? = store.timerEnd.map { max(0, $0.timeIntervalSince(ctx.date)) }
                let shown = left ?? total
                let k = left.map { total > 0 ? 1 - $0 / total : 0 } ?? 0
                VCard(glow: left != nil ? Volta.a1 : Volta.a2, breathe: left != nil, padding: 14) {
                    VStack(spacing: 10) {
                        OggiTesta(symbol: "timer", title: "Focus", detail: left != nil ? T("in corso", "running") : T("pronto", "ready"))
                        Spacer(minLength: 0)
                        // 01/11: cifre a puntini bocciate dall'autore: SF leggero con cifre a larghezza fissa, come il Timer di Apple
                        Text(Self.mmss(shown))
                            .font(.system(size: 44, weight: .light).monospacedDigit())
                            .foregroundStyle(left != nil ? Volta.a1 : Volta.t1)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Volta.card2)
                                Capsule().fill(Volta.a2).frame(width: g.size.width * k)
                            }
                        }
                        .frame(height: 4)
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            if left == nil {
                                passo("minus", -5)
                                VPill(title: T("Avvia", "Start"), kind: .primary) { avvia() }
                                passo("plus", 5)
                            } else {
                                VPill(title: T("Ferma", "Stop"), kind: .normal) { store.timerEnd = nil }
                            }
                        }
                    }
                }
            }
        }
        private func avvia() { store.timerEnd = Date().addingTimeInterval(Double(store.timerMinutes * 60)); store.now = Date() }
        private func passo(_ symbol: String, _ d: Int) -> some View {
            Button {
                store.timerMinutes = max(1, min(60, store.timerMinutes + d))
                Impostazioni.set(store.timerMinutes, .dialTimer)
            } label: {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Volta.pillT)
                    .frame(width: 30, height: 30).background(Circle().fill(Volta.pill)).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(d > 0 ? T("5 minuti in più", "5 more minutes") : T("5 minuti in meno", "5 fewer minutes"))
        }
        static func mmss(_ s: Double) -> String {
            let n = Int(s.rounded(.up))
            return String(format: "%02d:%02d", n / 60, n % 60)
        }
    }
}

// MARK: Nota

/// Un foglio unico che resta salvato: si scrive e basta, in fondo le parole.
private struct NotaCard: View {
    @State private var testo = Impostazioni.string(.isolaBlocco) ?? ""
    var body: some View {
        VCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                OggiTesta(symbol: "note.text", title: T("Nota", "Note"), detail: OraTesto.giorno(Date(), "d MMM"))
                ZStack(alignment: .topLeading) {
                    if testo.isEmpty {
                        Text(T("Scrivi qui un'idea", "Jot an idea here")).font(.system(size: 12.5)).foregroundStyle(Volta.t3)
                            .padding(.top, 1).allowsHitTesting(false)
                    }
                    TextEditor(text: $testo)
                        .font(.system(size: 12.5)).foregroundStyle(Volta.t1)
                        .scrollContentBackground(.hidden).scrollIndicators(.never)
                        .padding(.leading, -5)           // il margine interno di NSTextView, così il testo è allineato al titolo
                }
                .frame(maxHeight: .infinity)
                Text(T("\(parole) parole", "\(parole) words")).font(.system(size: 11)).foregroundStyle(Volta.t3)
            }
        }
        .onChange(of: testo) { _, v in Impostazioni.set(v, .isolaBlocco) }
    }
    private var parole: Int { testo.split { $0.isWhitespace || $0.isNewline }.count }
}

// MARK: Eventi

/// Gli eventi di oggi dal Calendario del Mac. Quelli già finiti restano, più tenui.
private struct EventiCard: View {
    @ObservedObject private var cal = CalendarModel.shared
    var body: some View {
        VCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                OggiTesta(symbol: "calendar", title: T("Eventi", "Events"), detail: T("oggi", "today"))
                if cal.denied {
                    Spacer(minLength: 0)
                    Text(T("Concedi il Calendario a Pulsar in Impostazioni di Sistema, Privacy.", "Allow Pulsar in System Settings, Privacy, Calendars."))
                        .font(.system(size: 12)).foregroundStyle(Volta.t3)
                    Spacer(minLength: 0)
                } else if cal.oggi.isEmpty {
                    Spacer(minLength: 0)
                    Text(T("Niente in programma oggi", "Nothing scheduled today")).font(.system(size: 12.5)).foregroundStyle(Volta.t3)
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(cal.oggi.enumerated()), id: \.offset) { _, e in riga(e) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .onAppear { cal.refresh() }
    }

    private func riga(_ e: CalendarModel.Next) -> some View {
        let finito = !e.allDay && e.end < Date()
        let ora = Date() >= e.start && Date() < e.end && !e.allDay
        return HStack(spacing: 9) {
            Capsule().fill(ora ? Volta.a1 : Volta.a3).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title.isEmpty ? T("Senza titolo", "Untitled") : e.title).font(.system(size: 12.5, weight: ora ? .medium : .regular))
                    .foregroundStyle(Volta.t1).lineLimit(1)
                Text(e.allDay ? T("Tutto il giorno", "All day") : "\(OraTesto.hm(e.start))-\(OraTesto.hm(e.end))")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Volta.t3)
            }
        }
        .opacity(finito ? 0.5 : 1)
    }
}

// MARK: - Andamento

/// Gli ultimi 7 giorni: a sinistra il riassunto in righe-dato, a destra le barre (attività o focus).
private struct AndamentoVista: View {
    @ObservedObject private var storia = OggiStoria.shared
    @State private var focus = false

    var body: some View {
        let sette = storia.ultimi(7), prima = storia.ultimi(7, prima: 7)
        let fatte = sette.reduce(0) { $0 + $1.g.fatte }
        let fattePrima = prima.reduce(0) { $0 + $1.g.fatte }
        let focusSec = sette.reduce(0) { $0 + $1.g.focus }
        let attivi = sette.filter { $0.g.fatte > 0 || $0.g.focus > 0 }.count
        HStack(spacing: 8) {
            VCard(padding: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    OggiTesta(symbol: "chart.bar", title: T("Ultimi 7 giorni", "Last 7 days"))
                    Spacer(minLength: 6)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(fatte)").font(.system(size: 30, weight: .light)).tracking(-0.6).foregroundStyle(Volta.t1)
                        Text(fatte == 1 ? T("attività fatta", "task done") : T("attività fatte", "tasks done")).font(.system(size: 12)).foregroundStyle(Volta.t2)
                    }
                    Text(Self.confronto(fatte, fattePrima)).font(.system(size: 11.5)).foregroundStyle(Volta.a2).lineLimit(1)
                    Spacer(minLength: 8)
                    VStack(spacing: 6) {
                        RigaDato(etichetta: T("Focus", "Focus time"), valore: Self.durata(focusSec))
                        RigaDato(etichetta: T("Giorni attivi", "Active days"), valore: T("\(attivi) su 7", "\(attivi) of 7"))
                    }
                }
            }
            .frame(width: 270)
            VCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 2) {
                        scelta(T("Attività", "Tasks"), !focus) { focus = false }
                        scelta("Focus", focus) { focus = true }
                        Spacer(minLength: 0)
                        if let a = sette.first?.data, let b = sette.last?.data {
                            Text("\(OraTesto.giorno(a, "d MMM")) - \(OraTesto.giorno(b, "d MMM"))").font(.system(size: 11.5)).foregroundStyle(Volta.t3)
                        }
                    }
                    Barre(giorni: sette, focus: focus)
                    HStack(spacing: 12) {
                        legenda(Volta.a2, focus ? T("Minuti di focus", "Focus minutes") : T("Fatte", "Done"))
                        if !focus { legenda(Volta.a2.opacity(0.25), T("Aggiunte", "Added")) }
                    }
                }
            }
        }
    }

    private func scelta(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeOut(duration: 0.2), a) }) {
            Text(t).font(.system(size: 11.5, weight: on ? .medium : .regular)).foregroundStyle(on ? Volta.t1 : Volta.t3)
                .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(on ? Volta.pill : .clear)).contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    private func legenda(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 11)).foregroundStyle(Volta.t3)
        }
    }

    static func durata(_ s: Int) -> String {
        let m = s / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    /// Una riga sola, onesta: più, meno o uguale alla settimana prima. Niente frasi da motivatore.
    static func confronto(_ ora: Int, _ prima: Int) -> String {
        if ora == 0 && prima == 0 { return T("Le spunte di oggi finiscono qui", "Today's ticks will show up here") }
        if ora == prima { return T("come la settimana prima", "same as the week before") }
        let d = abs(ora - prima)
        return ora > prima ? T("\(d) in più della settimana prima", "\(d) more than the week before")
                           : T("\(d) in meno della settimana prima", "\(d) fewer than the week before")
    }
}

/// Sette colonne: in Attività le fatte piene davanti alle aggiunte tenui, in Focus i minuti. Oggi in evidenza.
private struct Barre: View {
    let giorni: [(data: Date, g: OggiStoria.Giorno)]
    let focus: Bool
    var body: some View {
        let valori = giorni.map { focus ? Double($0.g.focus) / 60 : Double($0.g.fatte) }
        let sotto = giorni.map { focus ? 0 : Double($0.g.aggiunte) }
        let massimo = max(1, (valori + sotto).max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(giorni.enumerated()), id: \.offset) { i, d in
                let oggi = i == giorni.count - 1
                VStack(spacing: 5) {
                    GeometryReader { g in
                        let h = g.size.height
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Volta.card2)
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Volta.a2.opacity(0.25))
                                .frame(height: max(0, h * sotto[i] / massimo))
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(oggi ? Volta.a1 : Volta.a2)
                                .frame(height: max(valori[i] > 0 ? 3 : 0, h * valori[i] / massimo))
                        }
                    }
                    Text(OraTesto.giorno(d.data, "EEE")).font(.system(size: 10.5, weight: oggi ? .medium : .regular))
                        .foregroundStyle(oggi ? Volta.t1 : Volta.t3).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Personalizza

/// Quali card si vedono in Lavoro e in che ordine, la durata del focus e i promemoria nel notch.
private struct PersonalizzaVista: View {
    let store: DialStore?
    @ObservedObject private var s = OggiStato.shared
    @State private var promemoria = PromemoriaSource.enabled

    var body: some View {
        HStack(spacing: 8) {
            VCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    OggiTesta(symbol: "rectangle.3.group", title: T("Le card di Lavoro", "Workspace cards"),
                              detail: T("accendi e riordina", "toggle and reorder"))
                    Spacer(minLength: 0)
                    ForEach(Array(s.ordine.enumerated()), id: \.element) { i, c in
                        HStack(spacing: 9) {
                            Image(systemName: c.simbolo).font(.system(size: 11)).foregroundStyle(Volta.a2).frame(width: 16)
                            Text(c.titolo).font(.system(size: 12.5)).foregroundStyle(Volta.t1)
                            Spacer(minLength: 0)
                            freccia("chevron.up", attiva: i > 0) { s.sposta(c, di: -1) }
                            freccia("chevron.down", attiva: i < s.ordine.count - 1) { s.sposta(c, di: 1) }
                            InterruttoreIsola(on: Binding(get: { !s.nascoste.contains(c) },
                                                     set: { on in if on { s.nascoste.remove(c) } else { s.nascoste.insert(c) } }))
                        }
                        .frame(height: 24)
                    }
                    Spacer(minLength: 0)
                }
            }
            VCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    OggiTesta(symbol: "slider.horizontal.3", title: T("Comportamento", "Behaviour"))
                    Spacer(minLength: 0)
                    HStack {
                        Text(T("Promemoria nel notch", "Reminders in the notch")).font(.system(size: 12.5)).foregroundStyle(Volta.t1)
                        Spacer(minLength: 6)
                        InterruttoreIsola(on: $promemoria)
                            .onChange(of: promemoria) { _, v in PromemoriaSource.enabled = v }
                    }
                    if let store { DurataFocus(store: store) }
                    Spacer(minLength: 0)
                    Button { withAnimation(.easeOut(duration: 0.2)) { s.ripristina() } } label: {
                        Text(T("Ripristina le card", "Reset cards")).font(.system(size: 11.5)).foregroundStyle(Volta.t3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 300)
        }
    }

    private func freccia(_ s: String, attiva: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeOut(duration: 0.2), a) }) {
            Image(systemName: s).font(.system(size: 9, weight: .semibold)).foregroundStyle(attiva ? Volta.t2 : Volta.t3.opacity(0.4))
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!attiva)
    }

    private struct DurataFocus: View {
        @ObservedObject var store: DialStore
        var body: some View {
            HStack {
                Text(T("Durata del focus", "Focus length")).font(.system(size: 12.5)).foregroundStyle(Volta.t1)
                Spacer(minLength: 6)
                Stepper(value: Binding(get: { store.timerMinutes },
                                       set: { store.timerMinutes = $0; Impostazioni.set($0, .dialTimer) }),
                        in: 5...60, step: 5) {
                    Text("\(store.timerMinutes) min").font(.system(size: 12).monospacedDigit()).foregroundStyle(Volta.t2)
                }
                .controlSize(.small).disabled(store.timerEnd != nil)
            }
        }
    }
}

/// L'interruttore dell'isola: azzurro di Spazio quando è acceso. Quello di sistema nel pannello del notch (mai finestra
/// attiva) restava grigio anche acceso.
private struct InterruttoreIsola: View {
    @Binding var on: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { on.toggle() } } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Volta.a2 : Volta.pill)
                Circle().fill(on ? Volta.body : Volta.t3).padding(2.5)
            }
            .frame(width: 30, height: 18).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? T("acceso", "on") : T("spento", "off"))
    }
}
