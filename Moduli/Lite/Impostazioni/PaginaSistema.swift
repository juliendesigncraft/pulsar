// Pagina Sistema e rete (13/11/2026, ondata 3 di VORSSAINT.md): l'interruttore del modulo (lo stesso dei Pezzi di Pulsar e
// del benvenuto) e cosa fanno le tre schede del pannello. Tutto il resto si usa dal pannello della barra.
import SwiftUI

struct PaginaSistema: View {
    @Environment(\.fotoBloccato) private var fotoBloccato
    @Environment(\.fotoImpostazioni) private var foto

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("sistema", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.sistema.titolo,
                               riga: T("CPU, memoria e rete dal vivo, prova di velocità, pulizia e aggiornamenti delle app.",
                                       "Live CPU, memory and network, speed test, cleanup and app updates."),
                               prodotto: RegistroModuli.shared.prodotto(di: "sistema") ?? .complete)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.sistema.titolo,
                                              nota: T("Tre schede in più nel pannello della barra. Si misura solo mentre una scheda è aperta.",
                                                      "Three more tabs in the menu bar panel. Pulsar measures only while a tab is open.")) {
                    GruppoAcceso(valore: { foto ? true : ModuloSistema.shared.acceso }) { ModuloSistema.shared.acceso = $0 }
                    GruppoImpostazioni(T("Nel pannello", "In the panel")) {
                        RigaValore(T("Sistema", "System"), sotto: T("CPU, GPU, memoria e batteria", "CPU, GPU, memory and battery"), simbolo: "cpu", valore: "")
                        RigaValore(T("Rete", "Network"), sotto: T("Velocità dal vivo e prova di velocità", "Live speed and speed test"), simbolo: "network", valore: "")
                        RigaValore(T("Manutenzione", "Maintenance"), sotto: T("Aggiornamenti, pulizia, disinstalla: tutto nel Cestino", "Updates, cleanup, uninstall: all to the Trash"),
                                   simbolo: "arrow.triangle.2.circlepath", valore: "")
                    }
                } }
            }
        }
    }
}
