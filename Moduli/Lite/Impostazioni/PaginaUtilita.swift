// Pagina Utilità (13/11/2026, ondata 2 di VORSSAINT.md): l'interruttore del modulo (lo stesso dei Pezzi di Pulsar e del
// benvenuto), le cinque funzioni, una per riga, e le azioni. Tutto passa da ModuloUtilita e FunzioneUtilita.
import SwiftUI

struct PaginaUtilita: View {
    @Environment(\.fotoImpostazioni) private var foto

    var body: some View {
        PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.utilita.titolo,
                                      nota: T("Piccole cose che macOS non fa da solo. Ognuna è spenta finché non la accendi.",
                                              "Small things macOS doesn't do on its own. Each one stays off until you turn it on.")) {
            GruppoAcceso(valore: { foto ? true : ModuloUtilita.shared.acceso }) { ModuloUtilita.shared.acceso = $0 }
            GruppoImpostazioni(T("Funzioni", "Features")) {
                ForEach(FunzioneUtilita.allCases, id: \.self) { f in
                    RigaInterruttore(f.titolo, sotto: f.sotto, valore: { foto ? f == .pulisciLink : f.acceso }) { f.acceso = $0 }
                }
            }
            GruppoImpostazioni(T("Azioni", "Actions")) {
                RigaTasto(T("Espelli tutti i dischi", "Eject all disks"), sotto: T("Chiavette, dischi esterni, immagini disco", "USB sticks, external drives, disk images"),
                          tasto: T("Espelli", "Eject")) { Utilita.espelliDischi() }
                RigaTasto(T("Muta il microfono", "Mute microphone"), sotto: T("Un clic lo spegne, un altro lo riaccende", "One click mutes, another unmutes"),
                          tasto: T("Cambia", "Toggle")) { Utilita.cambiaMicrofono() }
                RigaTasto(T("Contagocce", "Color picker"), sotto: T("Il colore va negli appunti come #RRGGBB", "The color goes to the clipboard as #RRGGBB"),
                          tasto: T("Scegli", "Pick")) { Utilita.contagocce() }
            }
        } }
    }
}
