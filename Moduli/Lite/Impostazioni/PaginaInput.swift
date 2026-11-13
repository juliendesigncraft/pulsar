// Pagina Mouse e tastiera (13/11/2026, ondata 4 di VORSSAINT.md): l'interruttore del modulo, le sette funzioni e
// l'elenco delle scorciatoie di testo (sigla e testo, si aggiungono e si tolgono qui; file snippet.json nella cartella dati).
import SwiftUI

struct PaginaInput: View {
    @Environment(\.fotoBloccato) private var fotoBloccato
    @Environment(\.fotoImpostazioni) private var foto
    @Environment(\.matte) private var m
    @State private var lista: [Snippet] = PresaInput.snippet

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("input", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.input.titolo,
                               riga: T("Scorciatoie di testo, super tasto, clic centrale a tre dita e scorrimento morbido.",
                                       "Text snippets, super key, three-finger middle click and smooth scrolling."),
                               prodotto: RegistroModuli.shared.prodotto(di: "input") ?? .complete)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.input.titolo,
                                              nota: T("Ognuna è spenta finché non la accendi. Serve il permesso Accessibilità.",
                                                      "Each one stays off until you turn it on. Needs the Accessibility permission.")) {
                    GruppoAcceso(valore: { foto ? true : ModuloInput.shared.acceso }) { ModuloInput.shared.acceso = $0 }
                    GruppoImpostazioni(T("Funzioni", "Features")) {
                        ForEach(FunzioneInput.allCases, id: \.self) { f in
                            RigaInterruttore(f.titolo, sotto: f.sotto, valore: { foto ? f == .snippet : f.acceso }) { f.acceso = $0 }
                        }
                    }
                    GruppoImpostazioni(T("Scorciatoie di testo", "Text snippets")) {
                        ForEach($lista) { $s in
                            HStack(spacing: 8) {
                                // nelle foto i campi di testo non si disegnano (ImageRenderer): lì si mostra il testo
                                if foto {
                                    Text(s.sigla).frame(width: 90, alignment: .leading).font(.system(size: MisureImpostazioni.testo).monospaced()).foregroundStyle(m.t1)
                                    Text(s.testo).frame(maxWidth: .infinity, alignment: .leading).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1)
                                } else {
                                    TextField(";sigla", text: $s.sigla).textFieldStyle(.plain).frame(width: 90)
                                        .font(.system(size: MisureImpostazioni.testo).monospaced()).foregroundStyle(m.t1)
                                    TextField(T("Testo, anche con {data} e {ora}", "Text, also with {data} and {ora}"), text: $s.testo).textFieldStyle(.plain)
                                        .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1)
                                }
                                Button { lista.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).foregroundStyle(m.t3)
                            }
                            .padding(.horizontal, 14).frame(height: 40)
                        }
                        RigaTasto(T("Nuova scorciatoia", "New snippet"), tasto: T("Aggiungi", "Add")) { lista.append(Snippet(sigla: ";", testo: "")) }
                    }
                    .onChange(of: lista) { _, nuova in if !foto { PresaInput.salvaSnippet(nuova) } }
                    GruppoImpostazioni(T("Azioni", "Actions")) {
                        RigaTasto(T("Installa da immagine disco", "Install from disk image"), sotto: T("L'app va in Applicazioni, il .dmg nel Cestino", "The app goes to Applications, the .dmg to the Trash"),
                                  tasto: T("Scegli…", "Choose…")) { InstallaDMG.scegli() }
                    }
                } }
            }
        }
    }
}
