// Pagina Ghiere: tutto ciò che stava sotto GHIERA nel menu, più "Rimetti ghiere e colonna al loro posto".
// Ogni controllo usa la stessa proprietà o lo stesso metodo di DialModule che usava la voce di menu (enabled, lightEnabled,
// toggle, toggleLight) e EdgeDock.shared.resetAll(). Il modulo vivo arriva da FinestraImpostazioni.shared.ghiere;
// nelle foto da terminale non c'è e i valori si leggono dalle stesse chiavi salvate.
// Le Ghiere non hanno un "Acceso" unico: il modulo gira se almeno una delle due è accesa (DialModule.acceso), quindi
// in cima ci sono i due interruttori di sempre, e ogni "Mostra" si attenua quando la sua ghiera è spenta.
import SwiftUI

struct PaginaMixer: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var g: DialModule? { FinestraImpostazioni.shared.ghiere }
    private static var suono: Bool { g?.enabled ?? (Impostazioni.object(.dialEnabled) as? Bool ?? true) }
    private static var luce: Bool { g?.lightEnabled ?? (Impostazioni.object(.lightEnabled) as? Bool ?? true) }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("ghiera", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.mixer.titolo,
                               riga: T("Due ghiere sul bordo sinistro: il volume con il mixer per app e il timer, e la luce dello schermo.",
                                       "Two dials on the left edge: volume with a per-app mixer and a timer, and screen brightness."),
                               prodotto: .mixer)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.mixer.titolo) {
                    GruppoImpostazioni {
                        RigaInterruttore(T("Ghiera del suono", "Sound dial"), valore: { Self.suono }) { Self.g?.enabled = $0 }
                        RigaInterruttore(T("Ghiera della luce", "Light dial"), valore: { Self.luce }) { Self.g?.lightEnabled = $0 }
                    }
                    // ogni "Mostra" si attenua con la sua ghiera (nel menu c'è solo se la ghiera è accesa)
                    GruppoImpostazioni(T("Mostra", "Show")) {
                        RigaTasto(T("Ghiera del suono", "Sound dial"), tasto: T("Mostra ghiera", "Show dial")) { Self.g?.toggle() }
                            .attenuata(!Self.suono)
                        RigaTasto(T("Ghiera della luce", "Light dial"), tasto: T("Mostra luce", "Show light dial")) { Self.g?.toggleLight() }
                            .attenuata(!Self.luce)
                    }
                    // sempre attivo, come nel menu: rimette anche la colonna di Claude Code
                    GruppoImpostazioni {
                        RigaTasto(T("Ghiere e colonna", "Dials and column"), tasto: T("Rimetti al loro posto", "Reset positions")) { EdgeDock.shared.resetAll() }
                    }
                } }
            }
        }
    }
}
