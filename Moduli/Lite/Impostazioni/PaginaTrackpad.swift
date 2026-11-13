// Pagina Trackpad (06/11/2026): i bordi del trackpad. Acceso (lo stesso interruttore dei Pezzi di Pulsar nel menu e del
// benvenuto), cosa fa ogni bordo, sensibilità e il riscontro nel notch. Tutto passa da ModuloTrackpad e PreferenzeTrackpad.
import SwiftUI

struct PaginaTrackpad: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var acceso: Bool { ModuloTrackpad.shared.acceso }
    private static func opzioni(_ b: BordoTrackpad) -> [(id: String, titolo: String)] {
        b.scelte.map { (id: $0.rawValue, titolo: $0.titolo) }
    }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("trackpad", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.trackpad.titolo,
                               riga: T("Un dito sul bordo del trackpad regola volume e luce, senza tasti.",
                                       "One finger on the trackpad edge sets volume and brightness, no keys."),
                               prodotto: RegistroModuli.shared.prodotto(di: "trackpad") ?? .mixer)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.trackpad.titolo,
                                              nota: T("Appoggia un dito sul bordo del trackpad e fallo scorrere lungo il bordo. Con due o più dita vale il trackpad di sempre.",
                                                      "Rest one finger on the trackpad edge and slide it along. With two or more fingers your trackpad works as always.")) {
                    GruppoAcceso(valore: { Self.acceso }) { ModuloTrackpad.shared.acceso = $0 }
                    Group {
                        GruppoImpostazioni(T("Bordi", "Edges")) {
                            ForEach(BordoTrackpad.allCases, id: \.self) { b in
                                RigaScelta(b.titolo,
                                           sotto: b == .basso ? T("A destra e a sinistra", "Left and right") : T("Su e giù", "Up and down"),
                                           opzioni: Self.opzioni(b),
                                           valore: { PreferenzeTrackpad.azione(b).rawValue },
                                           cambia: { PreferenzeTrackpad.imposta(b, AzioneBordo(rawValue: $0) ?? .nessuna) })
                            }
                        }
                        GruppoImpostazioni(T("Risposta", "Response")) {
                            RigaCursore(T("Sensibilità", "Sensitivity"),
                                        valore: { PreferenzeTrackpad.sensibilita },
                                        cambia: { PreferenzeTrackpad.sensibilita = $0 })
                            RigaInterruttore(T("Mostra il livello nel notch", "Show the level in the notch"),
                                             valore: { PreferenzeTrackpad.riscontro }) { PreferenzeTrackpad.riscontro = $0 }
                        }
                        if !LettoreTrackpad.disponibile {
                            Text(T("Questa versione di macOS non lascia leggere il trackpad: i bordi restano spenti.",
                                   "This macOS version does not let Pulsar read the trackpad: edges stay off."))
                                .font(.system(size: MisureImpostazioni.piccolo))
                                .padding(.horizontal, MisureImpostazioni.margine)
                        }
                    }
                    .attenuata(!Self.acceso)
                } }
            }
        }
    }
}
