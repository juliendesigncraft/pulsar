// Pagina Claude Code: tutto ciò che stava sotto AGENTE nel menu, più il gruppo "Collega Claude Code".
// Ogni controllo usa la stessa proprietà o lo stesso metodo di AgentModule che usava la voce di menu (enabled, tabEnabled,
// tabAutoHide, agentSounds, pillStyle, togglePanel). Il modulo vivo arriva da FinestraImpostazioni.shared.agent;
// nelle foto da terminale non c'è e i valori si leggono dalle stesse chiavi salvate.
// Collega Claude Code scrive nel file di Claude Code SOLO dopo "Conferma" nel foglio: il percorso è un parametro
// (il vero è il predefinito) così le prove passano un file finto. Le foto leggono e basta.
import SwiftUI
import AppKit

struct PaginaAgent: View {
    /// Il file delle impostazioni di Claude Code. Le prove passano un file in $TMPDIR: mai il vero.
    var fileClaude = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var a: AgentModule? { FinestraImpostazioni.shared.agent }
    private static var acceso: Bool { a?.enabled ?? (Impostazioni.object(.agentEnabled) as? Bool ?? true) }
    private static var linguetta: Bool { a?.tabEnabled ?? (Impostazioni.object(.agentTab) as? Bool ?? true) }
    private static var nascondi: Bool { a?.tabAutoHide ?? (Impostazioni.object(.agentTabAuto) as? Bool ?? true) }
    private static var suoni: Bool { a?.agentSounds ?? (Impostazioni.object(.agentSounds) as? Bool ?? true) }
    private static var capsula: PillStyle { a?.pillStyle ?? PillStyle.saved }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("agente", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.agent.titolo,
                               riga: T("Vedi Claude Code dal vivo nel notch e in una colonna sul bordo, e rispondi ai permessi da lì.",
                                       "See Claude Code live in the notch and in a column on the edge, and answer permissions from there."),
                               prodotto: .agent)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.agent.titolo) {
                    // "Claude Code dal vivo" del menu: spento ferma tutto il modulo (pillola, colonna, ascolto degli hook)
                    GruppoAcceso(valore: { Self.acceso }) { Self.a?.enabled = $0 }
                    Group {
                        GruppoImpostazioni(T("Capsula e colonna", "Capsule and column")) {
                            RigaScelta(T("Capsula", "Capsule"), opzioni: PillStyle.allCases.map { (id: $0.rawValue, titolo: $0.title) },
                                       valore: { Self.capsula.rawValue }) { raw in
                                if let st = PillStyle(rawValue: raw) { Self.a?.pillStyle = st }
                            }
                            RigaInterruttore(T("Linguetta sul bordo", "Edge tab"), valore: { Self.linguetta }) { Self.a?.tabEnabled = $0 }
                            if Self.linguetta {
                                RigaInterruttore(T("Nascondi da sola", "Hide automatically"), valore: { Self.nascondi }) { Self.a?.tabAutoHide = $0 }
                            }
                            RigaTasto(T("Pannello  ⌃⌥P", "Panel  ⌃⌥P"),
                                      tasto: Self.a?.panelOpen == true ? T("Chiudi pannello", "Close panel") : T("Apri pannello", "Open panel")) {
                                Self.a?.togglePanel()
                            }
                            RigaInterruttore(T("Suono a fine lavoro e sui permessi", "Sound when done or asking"), valore: { Self.suoni }) { Self.a?.agentSounds = $0 }
                        }
                    }
                    .attenuata(!Self.acceso)
                    // la voce del menu "Rimetti ghiere e colonna" c'è se Ghiere o Claude Code sono sbloccati, anche a modulo spento:
                    // sta nella pagina Ghiere, e qui solo quando le Ghiere sono bloccate (così chi ha solo Pulsar Agent la trova lo stesso)
                    if RegistroModuli.shared.bloccato("ghiera") {
                        GruppoImpostazioni {
                            RigaTasto(T("Colonna", "Column"), tasto: T("Rimetti al suo posto", "Reset position")) { EdgeDock.shared.resetAll() }
                        }
                    }
                    // Collega resta attivo anche a modulo spento: tocca solo il file di Claude Code, non fa girare niente
                    GruppoCollegaClaude(file: fileClaude)
                } }
            }
        }
    }
}

// MARK: - Collega Claude Code

/// Stato, spiegazione e i tasti "Collega…" e "Scollega…". Il file si legge e basta: si scrive solo dal foglio.
struct GruppoCollegaClaude: View {
    let file: URL
    @State private var foglio: FoglioAperto?
    @State private var giro = 0
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto

    enum FoglioAperto: String, Identifiable { case collega, scollega; var id: String { rawValue } }
    private enum Stato { case collegato, nonCollegato, errore(String) }


    private var stato: Stato {
        do {
            let d = try CollegaClaude.leggi(file)   // sola lettura
            return CollegaClaude.collegato(d, cartellaDati: Cartelle.dati, home: FileManager.default.homeDirectoryForCurrentUser)
                ? .collegato : .nonCollegato
        } catch { return .errore(error.localizedDescription) }
    }

    var body: some View {
        let _ = giro
        let s = stato
        GruppoImpostazioni(T("Collega Claude Code", "Connect Claude Code")) {
            RigaBase(titolo: T("Collega Claude Code", "Connect Claude Code"),
                     sotto: T("Pulsar aggiunge i suoi hook a \(Self.breve(file)) per vedere Claude Code dal vivo. Scrive solo dopo la tua conferma.",
                              "Pulsar adds its hooks to \(Self.breve(file)) to show Claude Code live. It writes only after you confirm.")) {
                switch s {
                case .collegato: Text(T("Collegato", "Connected")).foregroundStyle(m.a2)
                case .nonCollegato: Text(T("Non collegato", "Not connected")).foregroundStyle(m.t2)
                case .errore: Text(T("Non leggibile", "Unreadable")).foregroundStyle(m.t2)
                }
            }
            if case .errore(let e) = s {
                RigaBase(titolo: T("Il file non si legge", "The file can't be read"), sotto: e, simbolo: "exclamationmark.circle") { EmptyView() }
            }
            if case .collegato = s {
                RigaTasto(T("Togli gli hook di Pulsar", "Remove Pulsar's hooks"), tasto: T("Scollega…", "Disconnect…")) { foglio = .scollega }
            } else {
                RigaTasto(T("Aggiungi gli hook di Pulsar", "Add Pulsar's hooks"), tasto: T("Collega…", "Connect…"), principale: true) { foglio = .collega }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in giro += 1 }
        .sheet(item: $foglio, onDismiss: { giro += 1 }) { f in
            FoglioCollega(azione: f == .collega ? .collega : .scollega, file: file) { foglio = nil }
                .environment(\.matte, m)
                .environment(\.colorScheme, m.chiaro ? .light : .dark)
        }
    }

    /// Il percorso con ~ al posto della home.
    static func breve(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Il foglio di conferma: le righe che cambiano, la nota sulla riscrittura e la copia, poi "Conferma" o "Annulla".
/// Dopo la scrittura dice dove sta la copia. Ogni errore si mostra qui e non scrive niente.
struct FoglioCollega: View {
    let azione: CollegaClaude.Azione
    let file: URL
    /// Solo per le foto: lo stato da disegnare al posto della lettura del file.
    var statoFoto: Esito? = nil
    let chiudi: () -> Void

    enum Esito {
        case pronta(CollegaClaude.Preparazione)
        case errore(String)
        case fatto(copia: URL?)
    }

    @State private var esito: Esito?
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto

    private var dati: URL { Cartelle.dati }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var body: some View {
        let e = statoFoto ?? esito
        VStack(alignment: .leading, spacing: 14) {
            Text(azione == .collega ? T("Collegare Claude Code?", "Connect Claude Code?") : T("Scollegare Claude Code?", "Disconnect Claude Code?"))
                .font(.system(size: 17)).foregroundStyle(m.t1)
            switch e {
            case .pronta(let p) where p.righe.isEmpty:
                Text(azione == .collega ? T("È già collegato: niente da aggiungere.", "Already connected: nothing to add.")
                                        : T("Non ci sono hook di Pulsar da togliere.", "There are no Pulsar hooks to remove."))
                    .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2)
                tasti(conferma: false)
            case .pronta(let p):
                Text(azione == .collega ? T("Pulsar aggiunge queste voci a \(GruppoCollegaClaude.breve(file)):", "Pulsar adds these entries to \(GruppoCollegaClaude.breve(file)):")
                                        : T("Pulsar toglie queste voci da \(GruppoCollegaClaude.breve(file)):", "Pulsar removes these entries from \(GruppoCollegaClaude.breve(file)):"))
                    .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2)
                    .fixedSize(horizontal: false, vertical: true)
                righe(p.righe)
                Text(T("Il file viene riscritto con le stesse impostazioni, ma l'ordine delle chiavi può cambiare. Una copia di prima resta accanto.",
                       "The file is rewritten with the same settings, but the order of the keys may change. A copy of the old file stays next to it."))
                    .font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t2)
                    .fixedSize(horizontal: false, vertical: true)
                tasti(conferma: true)
            case .errore(let msg):
                Label { Text(msg).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(m.a2) }
                    .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1)
                Text(T("Il file non è stato cambiato.", "The file was not changed.")).font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t2)
                tasti(conferma: false)
            case .fatto(let copia):
                Label { Text(azione == .collega ? T("Collegato.", "Connected.") : T("Scollegato.", "Disconnected.")) }
                    icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(m.a2) }
                    .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1)
                if let copia {
                    Text(T("La copia di prima sta in \(GruppoCollegaClaude.breve(copia))", "The old copy is at \(GruppoCollegaClaude.breve(copia))"))
                        .font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                tasti(conferma: false)
            case nil:
                Color.clear.frame(height: 40)
            }
        }
        .padding(22)
        .frame(width: 480, alignment: .leading)
        .background(m.pagina)
        .onAppear {
            guard statoFoto == nil, esito == nil else { return }
            do { esito = .pronta(try CollegaClaude.prepara(azione, url: file, cartellaDati: dati, home: home)) }
            catch { esito = .errore(error.localizedDescription) }
        }
    }

    @ViewBuilder private func righe(_ r: [String]) -> some View {
        let lista = VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(r.enumerated()), id: \.offset) { _, riga in
                Text(riga).font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t1)
                    .lineLimit(2).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        if foto {
            lista.background(RoundedRectangle(cornerRadius: MisureImpostazioni.raggio, style: .continuous).fill(m.gruppo))
        } else {
            ScrollView { lista }.frame(maxHeight: 240)
                .background(RoundedRectangle(cornerRadius: MisureImpostazioni.raggio, style: .continuous).fill(m.gruppo))
        }
    }

    @ViewBuilder private func tasti(conferma mostraConferma: Bool) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if mostraConferma {
                TastoImpostazioni(T("Annulla", "Cancel")) { chiudi() }
                    .keyboardShortcut(.cancelAction)
                TastoImpostazioni(T("Conferma", "Confirm"), principale: true) { scriviDopoConferma() }
            } else {
                TastoImpostazioni(T("Chiudi", "Close"), principale: true) { chiudi() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// L'unico punto che scrive: rilegge il file e scrive solo se cambia ciò che si è mostrato.
    private func scriviDopoConferma() {
        guard statoFoto == nil, case .pronta(let p) = esito else { return }
        // collegando, prima si mette hook.py nella cartella dati (se non riesce non si scrive niente e l'errore resta qui)
        do { esito = .fatto(copia: try CollegaClaude.conferma(p, url: file, cartellaDati: dati, home: home,
                                                              hook: Bundle.main.url(forResource: "hook", withExtension: "py"))) }
        catch { esito = .errore(error.localizedDescription) }
    }
}
