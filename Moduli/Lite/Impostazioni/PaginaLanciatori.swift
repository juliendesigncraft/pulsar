// Pagina Lanciatori (24/10/2026, Lite): l'interruttore del modulo, dove si vedono (bordo, desktop) e la lista dei siti.
// Disegno approvato dall'autore: agente/anteprima-lanciatori-impostazioni.html. Le cartelle sono pillole ("+ Cartella" ne crea una),
// sotto una riga per sito; al passaggio ↑ ↓, "Sposta in" e Togli; si riordina anche trascinando, e un sito lasciato su una pillola
// va in quella cartella. In fondo Aggiungi: nome e link, nella cartella aperta. Ogni mossa è di ListaLanciatori (pura) e passa
// da Lanciatori.cambia, che mostra e salva. Se la fonte non si cambia da qui (build dell'autore) la lista si mostra soltanto.
// Nelle foto da terminale: gli esempi del primo avvio, come li vede chi compra.
import SwiftUI
import AppKit

struct PaginaLanciatori: View {
    @Environment(\.fotoImpostazioni) private var foto
    @Environment(\.matte) private var m
    @ObservedObject private var dock = Lanciatori.shared
    @State private var scelta: String?
    @State private var nome = ""
    @State private var link = ""
    @State private var errore: ListaLanciatori.Errore?
    @State private var nuovaCartella: String?          // non nil: il campo del nome della cartella nuova è aperto

    private static var acceso: Bool { ModuloLanciatori.shared.acceso }
    private var cartelle: [Lanciatori.Cartella] { foto ? ListaLanciatori.esempi : dock.cartelle }
    private var modificabile: Bool { foto || dock.fonte.modificabile }
    private var aperta: Lanciatori.Cartella? { cartelle.first { $0.id == scelta } ?? cartelle.first }

    /// Il tasto Aggiungi e pulsar://lanciatori?aggiungi= passano da qui: nil = fatto, se no il motivo.
    @discardableResult
    static func aggiungi(nome: String, link: String, in cartella: String) -> ListaLanciatori.Errore? {
        let l = Lanciatori.shared
        guard l.fonte.modificabile else { return .cartellaMancante }
        switch ListaLanciatori.aggiungi(l.cartelle, nome: nome, link: link, in: cartella) {
        case .success(let nuove): l.cambia(nuove); return nil
        case .failure(let e): return e
        }
    }

    var body: some View {
        PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.lanciatori.titolo,
                                      nota: modificabile ? T("I siti che apri con un clic: nell'isola, accanto al Dock e sul desktop.",
                                                             "The sites you open in one click: in the island, next to the Dock and on the desktop.")
                                                         : dock.fonte.nota) {
            GruppoAcceso(valore: { Self.acceso }) { ModuloLanciatori.shared.acceso = $0 }
            Group {
                GruppoImpostazioni(T("Dove", "Where")) {
                    RigaInterruttore(T("Stash in basso a sinistra", "Stash bottom left"),
                                     sotto: T("Esce insieme al Dock dal bordo in basso dello schermo.", "Comes up with the Dock from the bottom edge of the screen."),
                                     valore: { LanciatoriStash.shared.acceso }) {
                        LanciatoriStash.shared.acceso = $0
                    }
                    RigaTasto(T("Stash", "Stash"), tasto: T("Mostra", "Show")) { LanciatoriStash.shared.mostra() }
                    RigaInterruttore(T("Sul desktop", "On the desktop"), valore: { LanciatoriDesktop.shared.acceso }) {
                        LanciatoriDesktop.shared.acceso = $0
                    }
                }
                GruppoImpostazioni(T("Siti", "Sites")) {
                    pillole
                    if let c = aperta, !c.voci.isEmpty {
                        ForEach(Array(c.voci.enumerated()), id: \.element.id) { i, v in
                            RigaSito(voce: v, indice: i, cartella: c, cartelle: cartelle, modificabile: modificabile && !foto, icona: dock.icone[Lanciatori.chiave(v)])
                        }
                    } else {
                        vuota
                    }
                }
                if modificabile {
                    GruppoImpostazioni(T("Aggiungi", "Add")) {
                        campiAggiungi
                    }
                }
                Text(T("Le icone le chiede Pulsar al sito stesso, mai a un servizio esterno. La lista resta sul tuo Mac.",
                       "Pulsar asks each site for its own icon, never an outside service. The list stays on your Mac."))
                    .font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t3)
                    .padding(.horizontal, MisureImpostazioni.margine)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .attenuata(!Self.acceso)
        } }
    }

    // MARK: cartelle

    private var pillole: some View {
        Pillole(distanza: 6) {
            ForEach(cartelle) { c in
                let on = c.id == aperta?.id
                Text(c.titolo)
                    .font(.system(size: MisureImpostazioni.testo - 1))
                    .foregroundStyle(on ? m.primT : m.t2)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(on ? m.prim : m.pill))
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { scelta = c.id } }
                    .modifier(RilascioSuCartella(attivo: modificabile && !foto, cartella: c.id, aperta: aperta))
            }
            if modificabile {
                if let testo = nuovaCartella {
                    TextField(T("Nome della cartella", "Folder name"), text: Binding(get: { testo }, set: { nuovaCartella = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: MisureImpostazioni.testo - 1)).foregroundStyle(m.t1)
                        .padding(.horizontal, 12).frame(width: 150, height: 26)
                        .background(Capsule().fill(m.t1.opacity(m.chiaro ? 0.05 : 0.06)))
                        .onSubmit(creaCartella)
                        .onExitCommand { nuovaCartella = nil }
                } else {
                    Text(T("+ Cartella", "+ Folder"))
                        .font(.system(size: MisureImpostazioni.testo - 1)).foregroundStyle(m.t3)
                        .padding(.horizontal, 10).frame(height: 26)
                        .contentShape(Capsule())
                        .onTapGesture { nuovaCartella = "" }
                }
            }
        }
        .padding(.horizontal, MisureImpostazioni.margine)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func creaCartella() {
        let r = ListaLanciatori.nuovaCartella(dock.cartelle, nome: nuovaCartella ?? "")
        nuovaCartella = nil
        guard let id = r.id else { return }
        dock.cambia(r.lista)
        scelta = id
    }

    private var vuota: some View {
        HStack {
            Text(cartelle.isEmpty ? dock.fonte.vuota : T("Nessun sito in questa cartella.", "No sites in this folder."))
                .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t3)
            Spacer(minLength: 12)
            if modificabile, cartelle.count > 1, let c = aperta {
                TastoImpostazioni(T("Togli la cartella", "Remove folder")) {
                    dock.cambia(ListaLanciatori.togliCartella(dock.cartelle, id: c.id))
                    scelta = nil
                }
            }
        }
        .padding(.horizontal, MisureImpostazioni.margine)
        .frame(minHeight: MisureImpostazioni.riga)
    }

    // MARK: aggiungi

    private var campiAggiungi: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Campo(testo: $nome, segnaposto: T("Nome", "Name")).frame(width: 150)
                Campo(testo: $link, segnaposto: "https://").onSubmit(aggiungiOra)
                TastoImpostazioni(T("Aggiungi", "Add"), principale: true, azione: aggiungiOra)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(link.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            if let errore {
                Text(errore == .giaPresente ? T("Questo sito c'è già nella cartella.", "This site is already in the folder.")
                                            : T("Il link deve iniziare con http:// o https://", "The link must start with http:// or https://"))
                    .font(.system(size: MisureImpostazioni.piccolo))
                    .foregroundStyle(m.chiaro ? Color(red: 0.79, green: 0.34, blue: 0.31) : Color(red: 0.88, green: 0.48, blue: 0.45))
            }
        }
        .padding(.horizontal, MisureImpostazioni.margine)
        .padding(.vertical, 9)
        .onChange(of: link) { errore = nil }
    }

    private func aggiungiOra() {
        guard !foto, let c = aperta else { return }
        errore = Self.aggiungi(nome: nome, link: link, in: c.id)
        if errore == nil { nome = ""; link = "" }
    }
}

/// Un sito trascinato su una pillola va in fondo a quella cartella. Spento nelle foto: ImageRenderer non disegna le zone di rilascio.
private struct RilascioSuCartella: ViewModifier {
    let attivo: Bool
    let cartella: String
    let aperta: Lanciatori.Cartella?
    func body(content: Content) -> some View {
        if attivo {
            content.dropDestination(for: String.self) { ids, _ in
                let dock = Lanciatori.shared
                guard let id = ids.first, let da = aperta, let i = da.voci.firstIndex(where: { $0.id == id }) else { return false }
                dock.cambia(ListaLanciatori.spostaIn(dock.cartelle, da: da.id, indice: i, a: cartella))
                return true
            }
        } else {
            content
        }
    }
}

/// Un campo di testo nello stile della finestra: fondo tenue, niente contorno. Nelle foto solo il segnaposto (ImageRenderer
/// non disegna i campi di testo).
private struct Campo: View {
    @Binding var testo: String
    let segnaposto: String
    @Environment(\.matte) private var m
    @Environment(\.fotoImpostazioni) private var foto
    var body: some View {
        Group {
            if foto {
                Text(segnaposto).foregroundStyle(m.t3).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(segnaposto, text: $testo).textFieldStyle(.plain).foregroundStyle(m.t1)
            }
        }
            .font(.system(size: MisureImpostazioni.testo))
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(m.t1.opacity(m.chiaro ? 0.05 : 0.06)))
    }
}

/// Una riga della lista: favicon, nome e sito; al passaggio le mosse. Si trascina col suo id (il link).
private struct RigaSito: View {
    let voce: Lanciatori.Voce
    let indice: Int
    let cartella: Lanciatori.Cartella
    let cartelle: [Lanciatori.Cartella]
    let modificabile: Bool
    let icona: NSImage?
    @State private var sopra = false
    @Environment(\.matte) private var m

    private var dock: Lanciatori { .shared }

    var body: some View {
        let riga = HStack(spacing: 10) {
            ZStack {
                Circle().fill(m.pill)
                if let icona {
                    Image(nsImage: icona).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15).clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Text(String(voce.n.prefix(1)).uppercased()).font(.system(size: 12)).foregroundStyle(m.t1)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(voce.n).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t1).lineLimit(1)
                Text(voce.app == nil ? ListaLanciatori.nomeDa(voce.u) : "app")
                    .font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t3).lineLimit(1)
            }
            Spacer(minLength: 12)
            if modificabile {
                HStack(spacing: 2) {
                    mossa("chevron.up", T("Sposta su", "Move up"), attiva: indice > 0) {
                        dock.cambia(ListaLanciatori.sposta(dock.cartelle, cartella: cartella.id, da: indice, a: indice - 1))
                    }
                    mossa("chevron.down", T("Sposta giù", "Move down"), attiva: indice < cartella.voci.count - 1) {
                        dock.cambia(ListaLanciatori.sposta(dock.cartelle, cartella: cartella.id, da: indice, a: indice + 1))
                    }
                    let altre = cartelle.filter { $0.id != cartella.id }
                    if !altre.isEmpty {
                        Menu {
                            ForEach(altre) { c in
                                Button(c.titolo) { dock.cambia(ListaLanciatori.spostaIn(dock.cartelle, da: cartella.id, indice: indice, a: c.id)) }
                            }
                        } label: {
                            Text(T("Sposta in…", "Move to…")).font(.system(size: MisureImpostazioni.piccolo + 1)).foregroundStyle(m.t2)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .padding(.horizontal, 7).frame(height: 24)
                    }
                    Button { dock.cambia(ListaLanciatori.togli(dock.cartelle, cartella: cartella.id, indice: indice)) } label: {
                        Text(T("Togli", "Remove")).font(.system(size: MisureImpostazioni.piccolo + 1)).foregroundStyle(m.t2)
                            .padding(.horizontal, 7).frame(height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .opacity(sopra ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: sopra)
            }
        }
        .padding(.horizontal, MisureImpostazioni.margine)
        .frame(minHeight: MisureImpostazioni.riga)
        .contentShape(Rectangle())
        .onHover { sopra = $0 }

        if modificabile {
            riga
                .draggable(voce.id)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, let da = cartella.voci.firstIndex(where: { $0.id == id }), da != indice else { return false }
                    dock.cambia(ListaLanciatori.sposta(dock.cartelle, cartella: cartella.id, da: da, a: indice))
                    return true
                }
        } else {
            riga
        }
    }

    private func mossa(_ simbolo: String, _ aiuto: String, attiva: Bool, _ fai: @escaping () -> Void) -> some View {
        Button(action: fai) {
            Image(systemName: simbolo).font(.system(size: 11)).foregroundStyle(m.t2)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!attiva).opacity(attiva ? 1 : 0.3)
        .help(aiuto)
    }
}
