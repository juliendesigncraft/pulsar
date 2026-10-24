// Pagina Voce (in Beta dal compito 2c della fase 5: etichetta accanto al titolo, spenta di serie nella vendita): la voce della Voce che stava sotto ISOLA nel menu (Anima.enabled, come toggleAnima) e i tre gesti.
// Nella build dell'autore anche "Leggi le risposte a voce" (AnimaVoce.leggeRisposte, come toggleAnimaLeggi).
// Il modulo vivo arriva da FinestraImpostazioni.shared.anima; nelle foto da terminale si legge la stessa chiave salvata.
import SwiftUI

struct PaginaVoce: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var v: Anima? { FinestraImpostazioni.shared.anima }
    private static var acceso: Bool { v?.enabled ?? Impostazioni.animaAccesa }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("anima", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.voce.titolo,
                               riga: T("Tieni premuti due tasti per dettare, dare un comando o cerchiare lo schermo e chiedere.",
                                       "Hold two keys to dictate, give a command, or circle the screen and ask."),
                               prodotto: RegistroModuli.shared.prodotto(di: "anima") ?? .complete,
                               etichetta: Etichetta.beta)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.voce.titolo, etichetta: Etichetta.beta) {
                    GruppoAcceso(valore: { Self.acceso }) { Self.v?.enabled = $0 }
                    Group {
                        GruppoImpostazioni(T("Tieni premuti", "Hold")) {
                            RigaValore(T("Detta", "Dictate"), simbolo: "mic.fill", valore: "⌃⌥")
                            RigaValore(T("Comanda", "Command"), simbolo: "command.circle.fill", valore: "⌃⌘")
                            RigaValore(T("Cerchia e chiedi", "Circle and ask"), simbolo: "hand.draw.fill", valore: "⌃⇧")
                        }
                    }
                    .attenuata(!Self.acceso)
                } }
            }
        }
    }
}
