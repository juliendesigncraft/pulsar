// Pagina Isola: le voci ISOLA del menu (l'isola nel notch e le sue scelte) e la griglia delle app.
// Eccezione: "Prossima riunione nel notch" non ha una voce nel menu, vive solo qui (RiunioneSource.enabled).
// Ogni controllo usa la stessa proprietà o lo stesso metodo della voce di menu: IslandModule.enabled (toggleIsola),
// impostaLED (toggleAmbiente), EdgeGlow, BrowserMediaSource, Thumbs, PeekPrefs, MediaSource.lyricsEnabled (le toggle*),
// WeatherModel.askCity (askWeatherCity), GridModule.setHotKey, GridModule.corner e open (setGridKey, toggleGridCorner, openGrid).
// Le proprietà statiche si leggono e scrivono uguali con o senza app; i moduli vivi arrivano da FinestraImpostazioni.shared
// e mancano solo nelle foto da terminale (lì i tasti non fanno niente).
// La griglia è un modulo a sé (gira anche con l'isola spenta, come nel menu): non si attenua con l'isola.
import SwiftUI

struct PaginaIsola: View {
    @Environment(\.fotoBloccato) private var fotoBloccato

    private static var i: IslandModule? { FinestraImpostazioni.shared.isola }
    private static var g: GridModule? { FinestraImpostazioni.shared.griglia }
    private static var acceso: Bool { i?.enabled ?? (Impostazioni.object(.isolaEnabled) as? Bool ?? true) }
    /// La stessa chiave che legge WeatherModel.city.
    private static var citta: String { Impostazioni.string(.isolaCity) ?? "" }

    var body: some View {
        SeLicenzaCambia {
            if moduloBloccato("isola", foto: fotoBloccato) {
                PaginaBloccata(nome: PaginaImpostazioni.isola.titolo,
                               riga: T("Il notch diventa un'isola con musica, meteo, eventi e Claude Code.",
                                       "Your notch becomes an island with music, weather, events and Claude Code."),
                               prodotto: RegistroModuli.shared.prodotto(di: "isola") ?? .complete)
            } else {
                PaginaRileggi { PaginaCornice(titolo: PaginaImpostazioni.isola.titolo) {
                    GruppoAcceso(valore: { Self.acceso }) { Self.i?.enabled = $0 }
                    Group {
                        GruppoImpostazioni(T("Nell'isola", "In the island")) {
                            RigaInterruttore(T("YouTube nell'isola", "YouTube in the island"), valore: { BrowserMediaSource.enabled }) { BrowserMediaSource.enabled = $0 }
                            RigaInterruttore(T("Testi dalla rete (LRCLIB)", "Lyrics from the web (LRCLIB)"), valore: { MediaSource.lyricsEnabled }) { MediaSource.lyricsEnabled = $0 }
                            RigaInterruttore(T("Miniatura finestre (Registrazione schermo)", "Window thumbnails (Screen Recording)"), valore: { Thumbs.enabled }) { Thumbs.enabled = $0 }
                            RigaInterruttore(T("Prossima riunione nel notch", "Next meeting in the notch"), valore: { RiunioneSource.enabled }) {
                                RiunioneSource.enabled = $0; Self.i?.riunioneCambiata()
                            }
                            RigaTasto(T("Città del meteo", "Weather city"), tasto: Self.citta.isEmpty ? T("Scegli…", "Choose…") : Self.citta + "…") {
                                WeatherModel.shared.askCity()
                            }
                        }
                        if let isola = Self.i, !isola.model.widgets.isEmpty {
                            GruppoTessere(tiles: isola.model.tiles, widgets: isola.model.widgets)
                        }
                        GruppoImpostazioni(T("Comparse", "Peeks")) {
                            RigaInterruttore(T("Notifiche e Non disturbare", "Notifications and Focus"), valore: { PeekPrefs.notifications }) { PeekPrefs.notifications = $0 }
                            RigaInterruttore(T("Batteria e salute del Mac", "Battery and Mac health"), valore: { PeekPrefs.system }) { PeekPrefs.system = $0 }
                            RigaInterruttore(T("Icone delle app ogni tanto", "App icons now and then"), valore: { PeekPrefs.ambient }) { PeekPrefs.ambient = $0 }
                        }
                        GruppoImpostazioni(T("Luce", "Light")) {
                            RigaInterruttore(T("LED sempre acceso nel notch", "Always-on notch LED"), valore: { AmbientSource.enabled }) { Self.i?.impostaLED($0) }
                            RigaInterruttore(T("Bordo dello schermo a ritmo", "Screen edge to the beat"), valore: { EdgeGlow.enabled }) { EdgeGlow.enabled = $0 }
                        }
                    }
                    .attenuata(!Self.acceso)
                    if !RegistroModuli.shared.bloccato("griglia") {
                        GruppoImpostazioni(T("Griglia delle app", "App grid")) {
                            RigaScelta(T("Scorciatoia", "Shortcut"), opzioni: GridModule.HotKey.allCases.map { (id: $0.rawValue, titolo: $0.title) },
                                       valore: { GridModule.hotKey.rawValue }) { raw in
                                if let k = GridModule.HotKey(rawValue: raw) { Self.g?.setHotKey(k) }
                            }
                            RigaInterruttore(T("Anche dall'angolo in alto a sinistra", "Also from the top left corner"), valore: { GridModule.corner }) { GridModule.corner = $0 }
                            RigaTasto(T("Griglia", "Grid"), tasto: T("Apri griglia", "Open grid")) { Self.g?.open() }
                        }
                    }
                } }
            }
        }
    }
}

/// 15/11, l'autore: "togliere o aggiungere widget a scelta". La fila della scheda Tessere del notch, da qui:
/// accese in alto nell'ordine della fila (frecce per spostarle), spente sotto. Legge e scrive lo stesso TileModel
/// del tasto Personalizza nel notch (UserDefaults `isolaTiles`): un solo elenco, quello che cambia qui cambia anche lì.
/// Essere nell'elenco vuol dire accesa: una tessera spenta esce dalla fila e la fila si richiude da sola.
struct GruppoTessere: View {
    @ObservedObject var tiles: TileModel
    let widgets: [IslandWidget]
    @Environment(\.matte) private var m

    /// Le celle con cui una tessera rientra: quelle tonde stanno in una, musica e priorità respirano su tre.
    static func celle(_ id: String) -> Int {
        switch id {
        case "clock", "month", "sun", "timer": return 1
        case "music", "todo": return 3
        default: return 2
        }
    }

    private var accese: [(Tile, IslandWidget)] {
        tiles.layout.tiles.compactMap { t in widgets.first { $0.id == t.id }.map { (t, $0) } }
    }
    private var spente: [IslandWidget] {
        widgets.filter { w in !tiles.layout.tiles.contains { $0.id == w.id } }
    }

    var body: some View {
        GruppoImpostazioni(T("Tessere del notch", "Notch tiles")) {
            ForEach(Array(accese.enumerated()), id: \.element.0.id) { i, coppia in
                RigaBase(titolo: coppia.1.title, simbolo: coppia.1.symbol) {
                    HStack(spacing: 2) {
                        mossa("chevron.up", T("Sposta a sinistra", "Move left"), attiva: i > 0) { tiles.layout.move(coppia.0.id, to: i - 1) }
                        mossa("chevron.down", T("Sposta a destra", "Move right"), attiva: i < accese.count - 1) { tiles.layout.move(coppia.0.id, to: i + 1) }
                        Interruttore(acceso: true) { tiles.layout.remove(coppia.0.id) }.padding(.leading, 6)
                    }
                }
            }
            ForEach(spente, id: \.id) { w in
                RigaBase(titolo: w.title, simbolo: w.symbol) {
                    Interruttore(acceso: false) { tiles.layout.add(w.id, cells: Self.celle(w.id)) }
                }
            }
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
