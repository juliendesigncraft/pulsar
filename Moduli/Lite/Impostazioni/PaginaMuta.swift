// Pagina Muta: le scelte di Muta che stavano solo nella sua sezione del pannello (muta-viste.swift), più l'interruttore
// del modulo. Stesse proprietà e metodi: MutaModule.acceso (il registro avvia o ferma Muta), MutaCentro.riordino,
// scrivania, download, dopoConversione, attesaMinuti, scegliCartella, e AgentModule.openSection(.muta) come pulsar://muta.
// MutaCentro.shared si legge uguale con o senza app (sono chiavi salvate); il modulo vivo arriva da FinestraImpostazioni.
import SwiftUI

struct PaginaMuta: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var mod: MutaModule? { FinestraImpostazioni.shared.muta }
    private static var c: MutaCentro { MutaCentro.shared }
    /// La stessa chiave che legge MutaModule.acceso.
    private static var acceso: Bool { mod?.acceso ?? (Impostazioni.object(.mutaAcceso) as? Bool ?? true) }

    private static var regoleUniche: [Regola] {
        var visti = Set<String>()
        return c.regole.filter { visti.insert($0.nome).inserted }
    }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("muta", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.muta.titolo,
                               riga: T("Converte i file lasciati sul notch e mette a posto Scrivania e Download.",
                                       "Converts files dropped on the notch and tidies up your Desktop and Downloads."),
                               prodotto: RegistroModuli.shared.prodotto(di: "muta") ?? .complete)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.muta.titolo) {
                    GruppoAcceso(valore: { Self.acceso }) { Self.mod?.acceso = $0 }
                    Group {
                        GruppoImpostazioni(T("Riordino", "Tidy up")) {
                            RigaInterruttore(T("Mette a posto da sola", "Tidies up on its own"), valore: { Self.c.riordino }) { Self.c.riordino = $0 }
                            RigaInterruttore(T("Scrivania", "Desktop"), valore: { Self.c.scrivania }) { Self.c.scrivania = $0 }
                            RigaInterruttore("Download", valore: { Self.c.download }) { Self.c.download = $0 }
                            RigaInterruttore(T("I file convertiti seguono le regole", "Converted files follow the rules"), valore: { Self.c.dopoConversione }) { Self.c.dopoConversione = $0 }
                            RigaScelta(T("Aspetta prima di spostare", "Wait before moving"), opzioni: [1, 2, 5].map { (id: String($0), titolo: "\($0) min") },
                                       valore: { String(Self.c.attesaMinuti) }) { Self.c.attesaMinuti = Int($0) ?? 2 }
                        }
                        GruppoImpostazioni(T("Cartelle", "Folders")) {
                            // una riga per nome: due regole con lo stesso nome (estensioni diverse) hanno una sola cartella scelta
                            ForEach(Self.regoleUniche, id: \.nome) { r in
                                if case .cartella = r.destinazione {
                                    RigaTasto(MutaCentro.nomeRegola(r.nome), tasto: Self.c.etichetta(r.destinazione) + "…") { Self.c.scegliCartella(per: r.nome) }
                                } else {
                                    RigaValore(MutaCentro.nomeRegola(r.nome), valore: Self.c.etichetta(r.destinazione))
                                }
                            }
                        }
                        GruppoImpostazioni {
                            RigaTasto(T("Ultime mosse e annulla", "Recent moves and undo"), tasto: T("Apri Stow", "Open Stow")) {
                                FinestraImpostazioni.shared.agent?.openSection(.muta)
                            }
                        }
                    }
                    .attenuata(!Self.acceso)
                } }
            }
        }
    }
}
