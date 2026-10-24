// Pagina Licenza (solo nella vendita: nella build personale tutto è sbloccato e la pagina non è in barra).
// Prodotti comprati, giorni di prova, prodotti sbloccati e il tasto che apre la richiesta della chiave (LicenzaViva.chiedi).
import SwiftUI
import AppKit

struct PaginaLicenza: View {
    @Environment(\.matte) private var m
    @State private var giro = 0       // ridisegna quando la finestra torna davanti (dopo una chiave inserita)

    var body: some View {
        let l = LicenzaViva.shared
        let g = l.giorniProvaRimasti
        let sbloccati = l.sbloccati
        PaginaCornice(titolo: PaginaImpostazioni.licenza.titolo) {
            GruppoImpostazioni {
                // il riassunto del menu metterebbe la prova due volte: qui comprati e prova stanno su righe loro
                RigaValore(T("Comprato", "Purchased"), valore: l.riassuntoComprati)
                RigaValore(T("Prova di Complete", "Complete trial"),
                           valore: g > 0 ? (g == 1 ? T("1 giorno", "1 day") : T("\(g) giorni", "\(g) days")) : T("Finita", "Over"))
            }
            GruppoImpostazioni(T("Prodotti", "Products")) {
                ForEach(Prodotto.allCases, id: \.self) { p in
                    RigaBase(titolo: Licenza.nome(p)) {
                        Text(sbloccati.contains(p) ? T("Sbloccato", "Unlocked") : T("Bloccato", "Locked"))
                            .font(.system(size: MisureImpostazioni.testo))
                            .foregroundStyle(sbloccati.contains(p) ? m.a2 : m.t3)
                    }
                }
            }
            GruppoImpostazioni {
                RigaTasto(T("Chiave di Gumroad", "Gumroad key"), tasto: T("Inserisci una chiave", "Enter a key"), principale: true) {
                    l.chiedi(); giro += 1
                }
            }
        }
        .id(giro)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in giro += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .licenzaCambiata)) { _ in giro += 1 }   // la chiave accettata o la prova finita
    }
}
