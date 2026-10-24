// Pagina Permessi: i permessi di macOS che servono ai moduli accesi (più quelli di Lite), uno per riga, con il perché,
// lo stato e il tasto per concederlo. Lo stato si rilegge quando la finestra torna davanti: per Accessibilità e
// Registrazione schermo la risposta arriva da Impostazioni di Sistema, dopo che `Permessi.chiedi` ha già risposto.
// Per quei due macOS mostra la richiesta una volta sola: dopo, se non concessi, la riga offre il pannello (Permessi.azione).
import SwiftUI
import AppKit

struct PaginaPermessi: View {
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto
    @State private var giro = 0

    /// Lite: la Dark Mode dell'interruttore passa da System Events (Automazione); i suoni dei tasti vogliono Accessibilità.
    /// La usa anche il benvenuto (compito 7), così le due liste di permessi coincidono.
    static var permessiLite: [Permesso] {
        Impostazioni.bool(.soundsEnabled) ? [.accessibilita, .automazione] : [.automazione]
    }

    var body: some View {
        // nelle foto il registro è vuoto (l'app non è partita): si mostrano tutti, con lo stato vero letto in sola lettura
        let elenco = foto ? Permesso.allCases : RegistroModuli.shared.permessiInUso(altri: Self.permessiLite)
        PaginaCornice(titolo: PaginaImpostazioni.permessi.titolo,
                      nota: T("Pulsar chiede solo i permessi delle funzioni accese. Si possono togliere in ogni momento da Impostazioni di Sistema, Privacy e sicurezza.",
                              "Pulsar only asks for what the features you turned on need. You can take them back anytime in System Settings, Privacy & Security.")) {
            GruppoImpostazioni {
                ForEach(elenco, id: \.self) { p in RigaPermesso(permesso: p) { giro += 1 } }
            }
        }
        .id(giro)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in giro += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            if FinestraImpostazioni.shared.eLaFinestra(n.object) { giro += 1 }   // solo la finestra delle Impostazioni
        }
        .onReceive(NotificationCenter.default.publisher(for: .licenzaCambiata)) { _ in giro += 1 }   // i moduli sbloccati cambiano i permessi in uso
    }
}

private struct RigaPermesso: View {
    let permesso: Permesso
    let aggiorna: () -> Void
    @Environment(\.matte) private var m
    @Environment(\.fotoGiaChiesto) private var fotoGiaChiesto

    var body: some View {
        // nelle foto "già chiesto" i due permessi senza negato vero si disegnano non concessi, qualunque sia lo stato del Mac
        let s: StatoPermesso = fotoGiaChiesto && Permessi.chiaveChiesto(permesso) != nil ? .daChiedere : Permessi.stato(permesso)
        // Accessibilità e Registrazione schermo già chieste: macOS non mostra più la richiesta, quindi il pannello
        let azione = Permessi.azione(permesso, stato: s, giaChiesto: fotoGiaChiesto || Permessi.giaChiesto(permesso))
        RigaBase(titolo: Permessi.nome(permesso), sotto: Permessi.perche(permesso)) {
            HStack(spacing: 10) {
                switch s {
                case .concesso:
                    Label(T("Concesso", "Allowed"), systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: MisureImpostazioni.testo - 1))
                        .foregroundStyle(m.a2)
                case .daChiedere:
                    // l'automazione senza System Events acceso risponde "da chiedere" anche se è concessa: si verifica chiedendo
                    // col tasto lungo del pannello lo stato si legge già dal tasto: niente testo, se no va a capo lettera per lettera
                    if azione == .chiedi {
                        Text(permesso == .automazione ? T("Da verificare", "To check") : T("Da concedere", "Not yet allowed"))
                            .font(.system(size: MisureImpostazioni.testo - 1)).foregroundStyle(m.t2)
                            .fixedSize()
                    }
                    if azione == .chiedi {
                        TastoImpostazioni(T("Concedi", "Allow")) {
                            Permessi.chiedi(permesso) { _ in aggiorna() }
                        }
                    } else {
                        TastoImpostazioni(T("Apri Impostazioni di Sistema", "Open System Settings")) { Permessi.apriPannello(permesso) }
                    }
                case .negato:
                    Text(T("Negato", "Denied")).font(.system(size: MisureImpostazioni.testo - 1)).foregroundStyle(m.t2)
                        .fixedSize()
                    TastoImpostazioni(T("Apri Impostazioni di Sistema", "Open System Settings")) { Permessi.apriPannello(permesso) }
                }
            }
        }
    }
}
