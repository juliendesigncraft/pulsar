// Pagine Terminale e Barra di sviluppo (07/11/2026, dal reel di ZincWolf). Acceso è lo stesso interruttore dei Pezzi
// di Pulsar nel menu e del benvenuto. Tutto passa da ModuloTerminale e ModuloBarraSviluppo.
import SwiftUI

struct PaginaTerminale: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("terminale", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.terminale.titolo,
                               riga: T("Un terminale vero che scende dal notch con una scorciatoia.",
                                       "A real terminal that drops from the notch with one shortcut."),
                               prodotto: RegistroModuli.shared.prodotto(di: "terminale") ?? .agent)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.terminale.titolo,
                                              nota: T("⌃⌥Invio lo fa scendere dal notch e lo richiude. Un clic fuori lo fa risalire. La shell resta aperta: quando torni ritrovi quello che c'era.",
                                                      "⌃⌥Return drops it from the notch and folds it back. Click anywhere else and it slides up. The shell stays open: come back and it is all still there.")) {
                    GruppoAcceso(valore: { ModuloTerminale.shared.acceso }) { ModuloTerminale.shared.acceso = $0 }
                    Text(T("Per macOS quello che fai nel terminale lo fa Pulsar: se un comando legge i dati di un'altra app, macOS può chiederti il permesso a nome di Pulsar.",
                           "To macOS, whatever you run in this terminal is run by Pulsar: if a command reads another app's data, macOS may ask for permission in Pulsar's name."))
                        .font(.system(size: MisureImpostazioni.piccolo))
                        .padding(.horizontal, MisureImpostazioni.margine)
                } }
            }
        }
    }
}

struct PaginaBarraSviluppo: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var acceso: Bool { ModuloBarraSviluppo.shared.acceso }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("barradev", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.barradev.titolo,
                               riga: T("Il branch Git, i server accesi e il limite di Claude nella barra in alto.",
                                       "Your Git branch, running servers and Claude limit in the menu bar."),
                               prodotto: RegistroModuli.shared.prodotto(di: "barradev") ?? .agent)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.barradev.titolo,
                                              nota: T("Tre voci accanto a Pulsar, sempre in vista anche con la Barra pulita.",
                                                      "Three items next to Pulsar, always visible, even with Clean bar on.")) {
                    GruppoAcceso(valore: { Self.acceso }) { ModuloBarraSviluppo.shared.acceso = $0 }
                    GruppoImpostazioni(T("Voci", "Items")) {
                        RigaInterruttore(T("Branch Git del progetto di Claude Code", "Git branch of the Claude Code project"),
                                         valore: { ModuloBarraSviluppo.mostra(.branch) }) { ModuloBarraSviluppo.imposta(.branch, $0) }
                        RigaInterruttore(T("Server accesi, per porta", "Running servers, by port"),
                                         valore: { ModuloBarraSviluppo.mostra(.server) }) { ModuloBarraSviluppo.imposta(.server, $0) }
                        RigaInterruttore(T("Limite di Claude rimasto", "Claude limit left"),
                                         valore: { ModuloBarraSviluppo.mostra(.limite) }) { ModuloBarraSviluppo.imposta(.limite, $0) }
                    }
                    .attenuata(!Self.acceso)
                    Text(T("Per il limite Pulsar legge l'accesso di Claude Code nel Portachiavi: la prima volta macOS chiede il permesso. L'accesso non esce dal Mac se non verso Anthropic, e Pulsar non lo salva.",
                           "For the limit Pulsar reads Claude Code's sign-in from the Keychain: macOS asks the first time. It only goes to Anthropic, and Pulsar never stores it."))
                        .font(.system(size: MisureImpostazioni.piccolo))
                        .padding(.horizontal, MisureImpostazioni.margine)
                } }
            }
        }
    }
}
