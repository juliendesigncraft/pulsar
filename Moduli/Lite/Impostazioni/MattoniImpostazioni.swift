// I mattoni di stile della finestra Impostazioni (fase 3): ogni pagina si costruisce solo con questi.
// Mac nativo come Impostazioni di Sistema, nei colori di Dark Matte e White Matte (Volta.Scala in Core/Tema.swift),
// l'azzurro di Pulsar come unico accento, niente contorni, SF Pro regular.
// I controlli sono disegnati in SwiftUI puro (niente Toggle, Picker o Slider di sistema): così hanno i colori giusti
// e ImageRenderer li fotografa uguali alla finestra (i controlli di AppKit nelle foto non compaiono).
import SwiftUI
import AppKit

// MARK: - Ambiente: la scala dei colori e il modo foto

private struct ChiaveScala: EnvironmentKey { static let defaultValue = Volta.Scala(chiaro: false) }
private struct ChiaveFoto: EnvironmentKey { static let defaultValue = false }
private struct ChiaveFotoLibera: EnvironmentKey { static let defaultValue = false }
private struct ChiaveRileggi: EnvironmentKey { static let defaultValue: () -> Void = {} }
private struct ChiaveFotoBloccato: EnvironmentKey { static let defaultValue = false }
private struct ChiaveFotoGiaChiesto: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// I colori della finestra. La radice la mette dall'aspetto corrente di Pulsar; le foto la scelgono (Dark o White Matte).
    var matte: Volta.Scala {
        get { self[ChiaveScala.self] }
        set { self[ChiaveScala.self] = newValue }
    }
    /// Vero mentre FotoImpostazioni disegna: niente ScrollView (ImageRenderer non la disegna) e dati di prova dove servono.
    var fotoImpostazioni: Bool {
        get { self[ChiaveFoto.self] }
        set { self[ChiaveFoto.self] = newValue }
    }
    /// Chiamata dai mattoni dopo ogni cambio: chi sta sopra (`PaginaRileggi`) ridisegna le righe condizionali.
    var rileggiPagina: () -> Void {
        get { self[ChiaveRileggi.self] }
        set { self[ChiaveRileggi.self] = newValue }
    }
    /// Solo nelle foto: le pagine dei moduli si disegnano come se la licenza li bloccasse (vedi `moduloBloccato`).
    var fotoBloccato: Bool {
        get { self[ChiaveFotoBloccato.self] }
        set { self[ChiaveFotoBloccato.self] = newValue }
    }
    /// Solo nelle foto: Accessibilità e Registrazione schermo si disegnano già chieste una volta e non concesse (Permessi.azione).
    var fotoGiaChiesto: Bool {
        get { self[ChiaveFotoGiaChiesto.self] }
        set { self[ChiaveFotoGiaChiesto.self] = newValue }
    }
    /// Nelle foto "intere": la pagina prende tutta l'altezza che le serve invece di fermarsi a 520 punti.
    var fotoAltezzaLibera: Bool {
        get { self[ChiaveFotoLibera.self] }
        set { self[ChiaveFotoLibera.self] = newValue }
    }
}

/// Misure comuni.
enum MisureImpostazioni {
    static let raggio: CGFloat = 12
    static let riga: CGFloat = 44          // altezza minima di una riga
    static let margine: CGFloat = 14       // margine orizzontale dentro i gruppi
    static let testo: CGFloat = 13
    static let piccolo: CGFloat = 11
}

// MARK: - Pagina

/// La cornice di ogni pagina: titolo, nota grigia facoltativa (solo Permessi e Collega Claude Code) e i gruppi sotto.
/// Uso: `PaginaCornice(titolo: T("Generale", "General")) { GruppoImpostazioni { … } }`
struct PaginaCornice<Content: View>: View {
    let titolo: String
    var nota: String? = nil
    /// Una parola piccola accanto al titolo (per ora solo "Beta" della Voce): testo e basta, mai un riquadro dietro.
    var etichetta: String? = nil
    @ViewBuilder let content: Content
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto
    @Environment(\.fotoAltezzaLibera) private var libera

    var body: some View {
        let corpo = VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(titolo).font(.system(size: 20, weight: .regular)).foregroundStyle(m.t1)
                    if let etichetta { EtichettaTitolo(testo: etichetta) }
                }
                if let nota { Text(nota).font(.system(size: MisureImpostazioni.piccolo + 1)).foregroundStyle(m.t2).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        if foto && libera {
            corpo
        } else if foto {
            // senza ScrollView: in alto, e ciò che non sta in 520 punti si taglia in basso (come la finestra prima di scorrere)
            Color.clear.overlay(alignment: .top) { corpo }.clipped()
        } else {
            ScrollView { corpo }.scrollIndicators(.never)
        }
    }
}

// MARK: - Etichetta accanto al titolo

/// "Beta" accanto al nome di un modulo (fase 5, compito 2c): piccola, nell'azzurro del Matte, solo testo.
/// Niente fondino né contorno (memoria niente-box-attorno).
struct EtichettaTitolo: View {
    let testo: String
    @Environment(\.matte) private var m

    var body: some View {
        Text(testo).font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.a2)
    }
}

/// Le parole delle etichette, nelle due lingue.
enum Etichetta {
    static var beta: String { T("Beta", "Beta") }
}

// MARK: - Gruppo

/// Un gruppo arrotondato di righe, con un'etichetta piccola facoltativa sopra (l'unico maiuscolo spaziato ammesso).
/// Fra una riga e l'altra un filo leggerissimo, mai un contorno. Ogni figlio diretto è una riga.
/// Uso: `GruppoImpostazioni("Aspetto") { RigaScelta(…); RigaInterruttore(…) }`
struct GruppoImpostazioni<Content: View>: View {
    var titolo: String?
    @ViewBuilder let content: Content
    @Environment(\.matte) private var m

    init(_ titolo: String? = nil, @ViewBuilder content: () -> Content) {
        self.titolo = titolo
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let titolo {
                Text(titolo.uppercased())
                    .font(.system(size: MisureImpostazioni.piccolo - 0.5)).tracking(0.6)
                    .foregroundStyle(m.t3)
                    .padding(.leading, MisureImpostazioni.margine)
            }
            Group(subviews: content) { righe in
                VStack(spacing: 0) {
                    ForEach(righe) { r in
                        if r.id != righe.first?.id {
                            Rectangle().fill(m.t1.opacity(0.06)).frame(height: 1).padding(.leading, MisureImpostazioni.margine)
                        }
                        r
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: MisureImpostazioni.raggio, style: .continuous).fill(m.gruppo))
        }
    }
}

// MARK: - Righe

/// La struttura comune: titolo (e una riga grigia facoltativa) a sinistra, il controllo a destra.
struct RigaBase<Destra: View>: View {
    let titolo: String
    var sotto: String? = nil
    var simbolo: String? = nil
    /// Come in PaginaCornice: una parola piccola accanto al titolo, senza riquadro.
    var etichetta: String? = nil
    @ViewBuilder let destra: Destra
    @Environment(\.matte) private var m

    var body: some View {
        HStack(spacing: 10) {
            if let simbolo {
                Image(systemName: simbolo).font(.system(size: 13)).foregroundStyle(m.t2).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(titolo).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1)
                    if let etichetta { EtichettaTitolo(testo: etichetta) }
                }
                if let sotto { Text(sotto).font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            destra
        }
        .padding(.horizontal, MisureImpostazioni.margine)
        .padding(.vertical, 8)
        .frame(minHeight: MisureImpostazioni.riga)
    }
}

// Come si collegano i controlli (compiti 4-7): `valore` è una chiusura che LEGGE il valore vero dal modulo o da
// Impostazioni (la stessa proprietà che legge la voce di menu); `cambia` chiama lo stesso setter della voce di menu.
// Il mattone non tiene una copia sua: ridisegna rileggendo `valore` dopo ogni cambio (subito e di nuovo dopo 0,3 s,
// per i setter che rispondono in ritardo) e quando Pulsar torna attiva. Se il setter rifiuta il cambio (modulo
// bloccato, permesso negato) il controllo torna da solo al valore vero. Mai passare un valore copiato in una @State.

/// Ridisegna il mattone che lo usa: dopo un cambio e quando l'app torna attiva.
private struct Rilettura: ViewModifier {
    @Binding var giro: Int
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in giro += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .licenzaCambiata)) { _ in giro += 1 }   // compito 6: righe che dipendono dalla licenza
    }
}

private func rileggiDopo(_ giro: Binding<Int>, _ pagina: () -> Void) {
    giro.wrappedValue += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { giro.wrappedValue += 1 }
    pagina()   // anche il contenitore (righe con `if` su valori vivi)
}

/// Il contenitore delle pagine con righe condizionali (un `if` su un valore vivo: permesso, interruttore di un modulo).
/// Il contenuto viene ricalcolato dopo ogni cambio fatto da un mattone qui dentro (subito e dopo 0,3 s) e quando Pulsar
/// torna attiva (si torna da Impostazioni di Sistema con un permesso concesso). Senza, l'`if` resta fermo al primo disegno.
/// Uso (OBBLIGATORIO per le pagine dei compiti 5 e 7 che hanno un `if` su valori vivi):
/// `var body: some View { PaginaRileggi { PaginaCornice(titolo: …) { GruppoImpostazioni { … if sounds.enabled { … } } } } }`
struct PaginaRileggi<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var giro = 0

    var body: some View {
        let _ = giro
        content()
            .environment(\.rileggiPagina, {
                giro += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { giro += 1 }
            })
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in giro += 1 }
    }
}

/// Ridisegna ciò che sta dentro quando cambia la licenza: la pagina di un modulo passa da bloccata a sbloccata (e viceversa)
/// anche con la finestra aperta. Uso: `var body: some View { SeLicenzaCambia { if moduloBloccato(…) { … } else { … } } }`
struct SeLicenzaCambia<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var giro = 0

    var body: some View {
        let _ = giro
        content().onReceive(NotificationCenter.default.publisher(for: .licenzaCambiata)) { _ in giro += 1 }
    }
}

extension Notification.Name {
    /// Lanciata da AppDelegate quando `LicenzaViva` dice che è cambiato cosa è sbloccato (la logica della licenza non cambia).
    static let licenzaCambiata = Notification.Name("pulsar.licenzaCambiata")
}

/// Un interruttore.
/// Uso: `RigaInterruttore(T("Suoni", "Sounds"), valore: { sounds.enabled }) { sounds.enabled = $0 }`
struct RigaInterruttore: View {
    let titolo: String
    var sotto: String? = nil
    let valore: () -> Bool
    let cambia: (Bool) -> Void
    @State private var giro = 0
    @Environment(\.rileggiPagina) private var pagina

    init(_ titolo: String, sotto: String? = nil, valore: @escaping () -> Bool, cambia: @escaping (Bool) -> Void) {
        self.titolo = titolo; self.sotto = sotto; self.valore = valore; self.cambia = cambia
    }

    var body: some View {
        let _ = giro
        let on = valore()
        RigaBase(titolo: titolo, sotto: sotto) {
            Interruttore(acceso: on) { cambia(!on); rileggiDopo($giro, pagina) }
        }
        .modifier(Rilettura(giro: $giro))
    }
}

/// L'interruttore disegnato: binario azzurro quando è acceso, manopola chiara.
struct Interruttore: View {
    let acceso: Bool
    let tocca: () -> Void
    @Environment(\.matte) private var m

    var body: some View {
        Button(action: tocca) {
            ZStack(alignment: acceso ? .trailing : .leading) {
                Capsule().fill(acceso ? m.a2 : m.t1.opacity(m.chiaro ? 0.13 : 0.16))
                Circle().fill(m.manopola).padding(2)
                    .shadow(color: .black.opacity(m.chiaro ? 0.14 : 0.2), radius: 1, y: 0.5)
            }
            .frame(width: 34, height: 20)
            .animation(.easeOut(duration: 0.15), value: acceso)
        }
        .buttonStyle(.plain)
    }
}

/// Una scelta fra poche opzioni, a pillole. La scelta corrente ha il fondo azzurro tenue e il testo azzurro.
/// Uso: `RigaScelta(T("Suono", "Sound"), opzioni: [("alpaca", "Alpaca"), ("hermes", "Hermes")], valore: { sounds.pack }) { sounds.pack = $0 }`
struct RigaScelta: View {
    let titolo: String
    var sotto: String? = nil
    let opzioni: [(id: String, titolo: String)]
    let valore: () -> String
    let cambia: (String) -> Void
    @State private var giro = 0
    @Environment(\.rileggiPagina) private var pagina
    @Environment(\.matte) private var m

    init(_ titolo: String, sotto: String? = nil, opzioni: [(id: String, titolo: String)], valore: @escaping () -> String, cambia: @escaping (String) -> Void) {
        self.titolo = titolo; self.sotto = sotto; self.opzioni = opzioni; self.valore = valore; self.cambia = cambia
    }

    var body: some View {
        let _ = giro
        let corrente = valore()
        RigaBase(titolo: titolo, sotto: sotto) {
            HStack(spacing: 2) {
                ForEach(opzioni, id: \.id) { o in
                    Button { cambia(o.id); rileggiDopo($giro, pagina) } label: {
                        Text(o.titolo)
                            .font(.system(size: MisureImpostazioni.testo - 1))
                            .foregroundStyle(o.id == corrente ? m.a2 : m.t2)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(o.id == corrente ? m.a2.opacity(m.chiaro ? 0.13 : 0.16) : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(m.t1.opacity(m.chiaro ? 0.05 : 0.06)))
        }
        .modifier(Rilettura(giro: $giro))
    }
}

/// Un cursore da 0 a 1 (o nell'intervallo dato). Mentre lo si trascina segue il dito senza scrivere niente; al rilascio
/// chiama `cambia` col valore finale (una sola scrittura), poi `rilascio` (per il colpo di prova) e rilegge il valore vero.
/// Uso: `RigaCursore(T("Tastiera", "Keyboard"), valore: { Double(sounds.keyVolume) }, cambia: { sounds.keyVolume = Float($0) }, rilascio: { sounds.preview(mouse: false) })`
struct RigaCursore: View {
    let titolo: String
    var simbolo: String? = nil
    let valore: () -> Double
    var intervallo: ClosedRange<Double> = 0...1
    let cambia: (Double) -> Void
    var rilascio: () -> Void = {}
    @State private var giro = 0
    @Environment(\.rileggiPagina) private var pagina
    @State private var dito: Double?      // solo durante il trascinamento
    @Environment(\.matte) private var m

    init(_ titolo: String, simbolo: String? = nil, valore: @escaping () -> Double, intervallo: ClosedRange<Double> = 0...1,
         cambia: @escaping (Double) -> Void, rilascio: @escaping () -> Void = {}) {
        self.titolo = titolo; self.simbolo = simbolo; self.valore = valore; self.intervallo = intervallo
        self.cambia = cambia; self.rilascio = rilascio
    }

    var body: some View {
        let _ = giro
        let v = dito ?? valore()
        let span = intervallo.upperBound - intervallo.lowerBound
        let frazione = span > 0 ? min(max((v - intervallo.lowerBound) / span, 0), 1) : 0
        RigaBase(titolo: titolo, simbolo: simbolo) {
            GeometryReader { g in
                let w = g.size.width, k: CGFloat = 16
                ZStack(alignment: .leading) {
                    Capsule().fill(m.t1.opacity(m.chiaro ? 0.10 : 0.14)).frame(height: 4)
                    Capsule().fill(m.a2).frame(width: max(4, (w - k) * frazione + k / 2), height: 4)
                    Circle().fill(m.manopola).frame(width: k, height: k)
                        .shadow(color: .black.opacity(m.chiaro ? 0.12 : 0.25), radius: 1.5, y: 0.5)
                        .offset(x: (w - k) * frazione)
                }
                .frame(height: g.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { d in
                        // durante il trascinamento solo lo stato `dito`: il valore si scrive al rilascio, come faceva il menu
                        let f = min(max((d.location.x - k / 2) / max(w - k, 1), 0), 1)
                        dito = intervallo.lowerBound + f * span
                    }
                    .onEnded { _ in
                        if let finale = dito { cambia(finale) }
                        dito = nil; rilascio(); rileggiDopo($giro, pagina)
                    })
            }
            .frame(width: 180, height: 20)
        }
        .modifier(Rilettura(giro: $giro))
    }
}

/// Una riga di sola lettura: titolo a sinistra, valore grigio a destra.
/// Uso: `RigaValore(T("Versione", "Version"), valore: "3.0")`
struct RigaValore: View {
    let titolo: String
    var sotto: String? = nil
    var simbolo: String? = nil
    let valore: String
    @Environment(\.matte) private var m

    init(_ titolo: String, sotto: String? = nil, simbolo: String? = nil, valore: String) {
        self.titolo = titolo; self.sotto = sotto; self.simbolo = simbolo; self.valore = valore
    }

    var body: some View {
        RigaBase(titolo: titolo, sotto: sotto, simbolo: simbolo) {
            Text(valore).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2).multilineTextAlignment(.trailing)
        }
    }
}

/// Una riga con un tasto a destra. Dopo il clic avvisa il contenitore (`PaginaRileggi`): le righe che dipendono
/// da ciò che il tasto cambia (pannello aperto, città scelta) si ridisegnano.
/// Uso: `RigaTasto(T("Licenza", "License"), tasto: T("Inserisci una chiave", "Enter a key")) { LicenzaViva.shared.chiedi() }`
struct RigaTasto: View {
    let titolo: String
    var sotto: String? = nil
    let tasto: String
    var principale = false
    let azione: () -> Void
    @Environment(\.rileggiPagina) private var pagina

    init(_ titolo: String, sotto: String? = nil, tasto: String, principale: Bool = false, azione: @escaping () -> Void) {
        self.titolo = titolo; self.sotto = sotto; self.tasto = tasto; self.principale = principale; self.azione = azione
    }

    var body: some View {
        RigaBase(titolo: titolo, sotto: sotto) { TastoImpostazioni(tasto, principale: principale) { azione(); pagina() } }
    }
}

/// Un tasto. Principale: fondo azzurro; normale: fondo tenue e testo pieno. Niente contorni.
/// Uso: `TastoImpostazioni(T("Concedi", "Allow"), principale: true) { … }`
struct TastoImpostazioni: View {
    let titolo: String
    var principale = false
    let azione: () -> Void
    @Environment(\.matte) private var m

    init(_ titolo: String, principale: Bool = false, azione: @escaping () -> Void) {
        self.titolo = titolo; self.principale = principale; self.azione = azione
    }

    var body: some View {
        Button(action: azione) {
            Text(titolo)
                .font(.system(size: MisureImpostazioni.testo - 1))
                .foregroundStyle(principale ? (m.chiaro ? m.manopola : m.primT) : m.t1)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(principale ? m.a2 : m.t1.opacity(m.chiaro ? 0.07 : 0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Modulo acceso o spento

/// In cima a ogni pagina di un modulo: l'interruttore "Acceso" che ferma il modulo del tutto (anche per alleggerire il Mac).
/// `cambia` è lo stesso setter della voce di menu; il registro dei moduli avvia o ferma il servizio.
/// Uso: `GruppoAcceso(valore: { Self.acceso }) { Self.a?.enabled = $0 }`, poi il resto della pagina in `Group { … }.attenuata(!Self.acceso)`
struct GruppoAcceso: View {
    let valore: () -> Bool
    let cambia: (Bool) -> Void

    init(valore: @escaping () -> Bool, cambia: @escaping (Bool) -> Void) { self.valore = valore; self.cambia = cambia }

    var body: some View {
        GruppoImpostazioni { RigaInterruttore(T("Acceso", "On"), valore: valore, cambia: cambia) }
    }
}

extension View {
    /// Il resto della pagina di un modulo spento: resta visibile ma attenuato e non si clicca. Va dentro `PaginaRileggi`,
    /// così cambia appena si tocca "Acceso". Su un `Group` vale per ogni gruppo dentro, con le distanze della pagina.
    func attenuata(_ spenta: Bool) -> some View {
        opacity(spenta ? 0.4 : 1).allowsHitTesting(!spenta)
    }
}

// MARK: - Modulo bloccato

/// Vero se la licenza blocca il modulo `id`; nelle foto anche quando la foto chiede la pagina bloccata (`\.fotoBloccato`).
/// Uso nelle pagine: `@Environment(\.fotoBloccato) private var fotoBloccato` e `if moduloBloccato("ghiera", foto: fotoBloccato) { PaginaBloccata(…) }`
func moduloBloccato(_ id: String, foto: Bool) -> Bool { foto || RegistroModuli.shared.bloccato(id) }

/// La pagina di un modulo che la licenza non sblocca: nome, una riga su cosa fa, tasto "Sblocca con Pulsar <Prodotto>…".
/// Nessun controllo del modulo. Uso (compiti 4-5): `if RegistroModuli.shared.bloccato("isola") { PaginaBloccata(nome: T("Isola", "Island"), riga: T("…", "…"), prodotto: .complete) }`
struct PaginaBloccata: View {
    let nome: String
    let riga: String
    let prodotto: Prodotto
    var etichetta: String? = nil
    @Environment(\.matte) private var m

    var body: some View {
        PaginaCornice(titolo: nome, etichetta: etichetta) {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 26)).foregroundStyle(m.a2)
                Text(riga).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                let n = Licenza.nome(prodotto)
                TastoImpostazioni(T("Sblocca con \(n)…", "Unlock with \(n)…"), principale: true) { LicenzaViva.shared.chiedi() }
            }
            .padding(.vertical, 36).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: MisureImpostazioni.raggio, style: .continuous).fill(m.gruppo))
        }
    }
}

// MARK: - Scelta fra molte opzioni

/// Una scelta fra molte opzioni (oltre cinque o sei): il titolo sopra, le pillole a capo sotto. Stesso stile di RigaScelta.
/// Uso: `RigaSceltaMolte(T("Suono", "Sound"), opzioni: [("alpaca", "Alpaca"), …], valore: { sounds.pack }) { sounds.scegliPacchetto($0) }`
struct RigaSceltaMolte: View {
    let titolo: String
    let opzioni: [(id: String, titolo: String)]
    let valore: () -> String
    let cambia: (String) -> Void
    @State private var giro = 0
    @Environment(\.rileggiPagina) private var pagina
    @Environment(\.matte) private var m

    init(_ titolo: String, opzioni: [(id: String, titolo: String)], valore: @escaping () -> String, cambia: @escaping (String) -> Void) {
        self.titolo = titolo; self.opzioni = opzioni; self.valore = valore; self.cambia = cambia
    }

    var body: some View {
        let _ = giro
        let corrente = valore()
        VStack(alignment: .leading, spacing: 8) {
            Text(titolo).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1)
            Pillole(distanza: 4) {
                ForEach(opzioni, id: \.id) { o in
                    let scelta = o.id == corrente
                    Button {
                        cambia(o.id)
                        rileggiDopo($giro, pagina)
                    } label: {
                        Text(o.titolo)
                            .font(.system(size: MisureImpostazioni.testo - 1))
                            .foregroundStyle(scelta ? m.a2 : m.t2)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(scelta ? m.a2.opacity(m.chiaro ? 0.13 : 0.16) : m.t1.opacity(m.chiaro ? 0.05 : 0.06)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, MisureImpostazioni.margine)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(Rilettura(giro: $giro))
    }
}

/// Dispone i figli in righe, andando a capo quando non c'è più posto.
struct Pillole: Layout {
    var distanza: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        righe(proposal.width ?? 400, subviews).dimensione
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for riga in righe(bounds.width, subviews).righe {
            var x = bounds.minX
            for (i, d) in riga.voci {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
                x += d.width + distanza
            }
            y += riga.altezza + distanza
        }
    }

    private func righe(_ larghezza: CGFloat, _ subviews: Subviews) -> (righe: [(voci: [(Int, CGSize)], altezza: CGFloat)], dimensione: CGSize) {
        var out: [(voci: [(Int, CGSize)], altezza: CGFloat)] = []
        var attuale: [(Int, CGSize)] = [], x: CGFloat = 0, h: CGFloat = 0, maxX: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let d = v.sizeThatFits(.unspecified)
            if x > 0 && x + d.width > larghezza { out.append((attuale, h)); attuale = []; x = 0; h = 0 }
            attuale.append((i, d)); x += d.width + distanza; h = max(h, d.height); maxX = max(maxX, x - distanza)
        }
        if !attuale.isEmpty { out.append((attuale, h)) }
        let alto = out.reduce(0) { $0 + $1.altezza } + CGFloat(max(out.count - 1, 0)) * distanza
        return (out, CGSize(width: maxX, height: alto))
    }
}
