// Il benvenuto di Pulsar (fase 3, compito 7): tre schermate in una finestra sua di 560x440.
// (1) cos'è Pulsar, con la missione e la prova di 7 giorni; (2) quali moduli accendere; (3) i permessi uno alla volta.
// Si apre da solo solo nella vendita, al primo avvio (BenvenutoLogica.deveAprire); nella build personale con
// pulsar://benvenuto. `benvenutoVisto` si scrive appena si apre: chiuderlo a metà non lo fa ripartire.
// Al primo avvio i moduli a pagamento non partono finché il benvenuto è aperto (RegistroModuli.inAttesa): gli interruttori
// scrivono la scelta, e alla chiusura della finestra il registro li avvia secondo quella.
// Gli interruttori dei moduli chiamano gli stessi setter delle pagine (e quindi del menu): scrivono le stesse chiavi.
// Le Ghiere sono una riga sola che accende o spegne le due insieme: qui si sceglie il modulo, il dettaglio (solo una
// delle due) sta nella pagina Ghiere, e il modulo gira se almeno una è accesa (DialModule.acceso).
// Stesso stile della finestra Impostazioni (mattoni in MattoniImpostazioni.swift), e la stessa vista fa le foto.
import SwiftUI
import AppKit

/// Dove si trova il benvenuto: la schermata, i permessi da chiedere (calcolati entrando nella terza) e quello mostrato.
final class StatoBenvenuto: ObservableObject {
    @Published var schermata = 0
    @Published var permessi: [Permesso] = []
    @Published var indice = 0
    /// Solo nelle foto: lo stato del permesso da disegnare al posto di quello vero (per vedere "Da concedere" e "Negato").
    var statoFoto: StatoPermesso?
}

/// Un modulo da accendere nella seconda schermata. `valore` e `cambia` sono quelli della sua pagina delle Impostazioni.
struct VoceBenvenuto {
    let id: String
    let pagina: PaginaImpostazioni
    let valore: () -> Bool
    let cambia: (Bool) -> Void
    let permessi: () -> [Permesso]

    /// I moduli da accendere, solo quelli sbloccati (in prova tutti). Temi e Griglia no: non hanno un interruttore.
    /// Senza l'app avviata (foto) i moduli vivi sono nil: si leggono le stesse chiavi salvate delle pagine.
    static var tutte: [VoceBenvenuto] {
        let f = FinestraImpostazioni.shared
        let voci = [
            VoceBenvenuto(id: "agente", pagina: .agent,
                          valore: { f.agent?.enabled ?? (Impostazioni.object(.agentEnabled) as? Bool ?? true) },
                          cambia: { f.agent?.enabled = $0 }, permessi: { f.agent?.permessi ?? [] }),
            VoceBenvenuto(id: "ghiera", pagina: .mixer,
                          valore: {
                              if let g = f.ghiere { return g.enabled || g.lightEnabled }
                              return (Impostazioni.object(.dialEnabled) as? Bool ?? true) || (Impostazioni.object(.lightEnabled) as? Bool ?? true)
                          },
                          cambia: { f.ghiere?.enabled = $0; f.ghiere?.lightEnabled = $0 }, permessi: { f.ghiere?.permessi ?? [] }),
            VoceBenvenuto(id: "isola", pagina: .isola,
                          valore: { f.isola?.enabled ?? (Impostazioni.object(.isolaEnabled) as? Bool ?? true) },
                          cambia: { f.isola?.enabled = $0 }, permessi: { f.isola?.permessi ?? [] }),
            VoceBenvenuto(id: "anima", pagina: .voce,
                          valore: { f.anima?.enabled ?? Impostazioni.animaAccesa },
                          cambia: { f.anima?.enabled = $0 }, permessi: { f.anima?.permessi ?? [] }),
            VoceBenvenuto(id: "rowline", pagina: .rowline,
                          valore: { ModuloRowline.shared.acceso },
                          cambia: { ModuloRowline.shared.acceso = $0 }, permessi: { ModuloRowline.shared.permessi }),
            VoceBenvenuto(id: "muta", pagina: .muta,
                          valore: { f.muta?.acceso ?? (Impostazioni.object(.mutaAcceso) as? Bool ?? true) },
                          cambia: { f.muta?.acceso = $0 }, permessi: { f.muta?.permessi ?? [] }),
            // 25/10, l'autore: "metti il tasto Lanciatori nei Pezzi di Pulsar" (Lite, nessun permesso)
            VoceBenvenuto(id: "lanciatori", pagina: .lanciatori,
                          valore: { ModuloLanciatori.shared.acceso },
                          cambia: { ModuloLanciatori.shared.acceso = $0 }, permessi: { ModuloLanciatori.shared.permessi }),
        ]
        return voci.filter { !RegistroModuli.shared.bloccato($0.id) }
    }

    /// Una riga breve su cosa fa, sotto il nome.
    var riga: String {
        switch id {
        case "agente": return T("Lo vedi lavorare dal vivo nel notch", "Watch it work live in the notch")
        case "ghiera": return T("Volume e luce sul bordo", "Volume and brightness on the edge")
        case "isola": return T("Musica, meteo ed eventi nel notch", "Music, weather and events in the notch")
        case "anima": return T("Detta e comanda con la voce", "Dictate and command by voice")
        case "rowline": return T("Le finestre in fila", "Your windows in a row")
        case "muta": return T("Converte e mette a posto i file", "Converts and tidies your files")
        case "lanciatori": return T("I tuoi siti accanto al Dock", "Your sites next to the Dock")
        default: return ""
        }
    }
}

final class FinestraBenvenuto: NSObject, NSWindowDelegate {
    static let shared = FinestraBenvenuto()

    private var finestra: NSWindow?
    private let stato = StatoBenvenuto()

    /// Apre (o riporta davanti) il benvenuto dalla prima schermata e lo segna come visto.
    func apri() {
        Impostazioni.set(true, .benvenutoVisto)
        stato.schermata = 0
        stato.indice = 0
        let w = finestra ?? crea()
        finestra = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func chiudi() {
        Impostazioni.set(true, .benvenutoVisto)
        finestra?.close()
    }

    /// Chiuso in qualsiasi modo (Fatto, il bottone rosso, ⌘W): i moduli che aspettavano partono secondo le scelte fatte.
    func windowWillClose(_ notification: Notification) {
        RegistroModuli.shared.liberaAttesa()
    }

    /// Vero se `oggetto` è la finestra del benvenuto (per filtrare le notifiche delle finestre).
    func eLaFinestra(_ oggetto: Any?) -> Bool { finestra != nil && (oggetto as? NSWindow) === finestra }

    private func crea() -> NSWindow {
        let w = FinestraConChiudi(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),   // ⌘W chiude, come le Impostazioni
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Pulsar"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: RadiceBenvenuto(stato: stato) { [weak self] in self?.chiudi() })
        w.center()
        return w
    }
}

/// La radice della finestra viva: segue l'aspetto di Pulsar come le Impostazioni.
private struct RadiceBenvenuto: View {
    @ObservedObject var stato: StatoBenvenuto
    let chiudi: () -> Void
    @ObservedObject private var look = GhieraLook.shared

    var body: some View {
        _ = look.mode
        return VistaBenvenuto(stato: stato, scala: Volta.Scala(chiaro: Theme.light), chiudi: chiudi)
    }
}

/// Le tre schermate e la barra dei tasti in basso. La stessa vista per la finestra e per le foto (FotoImpostazioni).
struct VistaBenvenuto: View {
    @ObservedObject var stato: StatoBenvenuto
    let scala: Volta.Scala
    var foto = false
    var chiudi: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch stato.schermata {
                case 0: SchermataCosaE()
                case 1: SchermataModuli()
                default: SchermataPermessi(stato: stato)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            barra
        }
        .padding(.top, 28)          // sotto i tre bottoni della finestra
        .frame(width: 560, height: 440)
        .background(scala.pagina)
        .environment(\.matte, scala)
        .environment(\.fotoImpostazioni, foto)
        .environment(\.colorScheme, scala.chiaro ? .light : .dark)
        .font(.system(size: MisureImpostazioni.testo))
    }

    /// Indietro a sinistra, il tasto principale a destra: Continua, poi Fatto sull'ultimo permesso.
    private var barra: some View {
        let ultimo = stato.schermata == 2 && stato.indice >= stato.permessi.count - 1
        return HStack(spacing: 10) {
            if stato.schermata > 0 {
                TastoImpostazioni(T("Indietro", "Back")) { indietro() }
            }
            Spacer(minLength: 0)
            TastoImpostazioni(ultimo ? T("Fatto", "Done") : T("Continua", "Continue"), principale: true) { avanti() }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .padding(.top, 10)
    }

    private func avanti() {
        switch stato.schermata {
        case 0: stato.schermata = 1
        case 1:
            // la scelta di adesso (gli interruttori l'hanno già scritta nelle chiavi dei moduli): ne escono i permessi
            let voci = VoceBenvenuto.tutte
            let scelti = voci.filter { $0.valore() }.map(\.id)
            Impostazioni.set(scelti, .moduliScelti)
            stato.permessi = Self.permessi(voci, scelti: Set(scelti))
            stato.indice = 0
            stato.schermata = 2
        default:
            if stato.indice < stato.permessi.count - 1 { stato.indice += 1 } else { chiudi() }
        }
    }

    private func indietro() {
        if stato.schermata == 2 && stato.indice > 0 { stato.indice -= 1 } else { stato.schermata = max(0, stato.schermata - 1) }
    }

    /// I permessi dei moduli scelti più quelli di Lite (gli stessi della pagina Permessi), in ordine fisso.
    static func permessi(_ voci: [VoceBenvenuto], scelti: Set<String>) -> [Permesso] {
        let moduli = voci.map { (id: $0.id, permessi: $0.permessi()) } + [(id: "lite", permessi: PaginaPermessi.permessiLite)]
        return BenvenutoLogica.permessiDa(moduli, scelti: scelti.union(["lite"]))
    }
}

// MARK: - Le tre schermate

/// 1. Cos'è Pulsar: l'icona, la missione e la prova.
private struct SchermataCosaE: View {
    @Environment(\.matte) private var m

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(nsImage: PaginaInfo.icona ?? NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().frame(width: 72, height: 72)
            Text(T("Benvenuto in Pulsar", "Welcome to Pulsar"))
                .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2)
            Text(T("Il notch diventa la plancia di comando per chi lavora con Claude sul Mac",
                   "Your notch becomes the control deck for working with Claude on your Mac"))
                .font(.system(size: 22, weight: .regular)).foregroundStyle(m.t1)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            Text(T("7 giorni di prova di tutto, poi scegli cosa tenere.", "7 days to try everything, then keep what you like."))
                .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

/// 2. Quali moduli accendere: un interruttore per modulo sbloccato, che scrive subito come la sua pagina.
private struct SchermataModuli: View {
    @Environment(\.matte) private var m

    var body: some View {
        PaginaRileggi {
            VStack(alignment: .leading, spacing: 14) {
                Intestazione(titolo: T("Cosa accendere", "What to turn on"),
                             nota: T("I moduli spenti non girano e non chiedono permessi.",
                                     "Modules you turn off don't run and don't ask for permissions."))
                GruppoImpostazioni {
                    ForEach(VoceBenvenuto.tutte, id: \.id) { v in RigaModulo(voce: v) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
        }
    }
}

/// Una riga della scelta: icona della pagina, nome, una riga grigia, interruttore.
private struct RigaModulo: View {
    let voce: VoceBenvenuto
    @Environment(\.rileggiPagina) private var rileggi

    var body: some View {
        let on = voce.valore()
        RigaBase(titolo: voce.pagina.titolo, sotto: voce.riga, simbolo: voce.pagina.simbolo,
                 etichetta: voce.id == "anima" ? Etichetta.beta : nil) {
            Interruttore(acceso: on) { voce.cambia(!on); rileggi() }
        }
    }
}

/// 3. I permessi, uno alla volta: perché serve, lo stato e il tasto per concederlo. Lo stato si rilegge quando si torna
/// da Impostazioni di Sistema (per Accessibilità e Registrazione schermo la risposta arriva solo da lì).
private struct SchermataPermessi: View {
    @ObservedObject var stato: StatoBenvenuto
    @Environment(\.matte) private var m
    @State private var giro = 0

    var body: some View {
        let _ = giro
        VStack(alignment: .leading, spacing: 14) {
            Intestazione(titolo: T("Permessi", "Permissions"),
                         nota: T("Quelli dei moduli accesi e di Pulsar Lite, uno alla volta. Si possono togliere in ogni momento da Impostazioni di Sistema.",
                                 "For the modules you turned on and Pulsar Lite, one at a time. You can take them back anytime in System Settings."))
            if stato.permessi.isEmpty {
                Text(T("Nessun permesso da chiedere: Pulsar è pronta.", "No permissions needed: Pulsar is ready."))
                    .font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(RoundedRectangle(cornerRadius: MisureImpostazioni.raggio, style: .continuous).fill(m.gruppo))
            } else {
                let i = min(stato.indice, stato.permessi.count - 1)
                SchedaPermesso(permesso: stato.permessi[i], numero: i + 1, di: stato.permessi.count, statoFoto: stato.statoFoto) { giro += 1 }
                    .id("\(i)-\(giro)")   // ridisegna la scheda (e rilegge lo stato) a ogni giro, come PaginaPermessi
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in giro += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            if FinestraBenvenuto.shared.eLaFinestra(n.object) { giro += 1 }
        }
    }
}

/// La scheda di un permesso: icona, nome, perché, e a destra lo stato o il tasto.
private struct SchedaPermesso: View {
    let permesso: Permesso
    let numero: Int
    let di: Int
    var statoFoto: StatoPermesso? = nil
    let aggiorna: () -> Void
    @Environment(\.matte) private var m
    @Environment(\.fotoGiaChiesto) private var fotoGiaChiesto

    var body: some View {
        let s = statoFoto ?? Permessi.stato(permesso)
        // come la pagina Permessi: Accessibilità e Registrazione schermo già chieste portano al pannello
        let azione = Permessi.azione(permesso, stato: s, giaChiesto: fotoGiaChiesto || Permessi.giaChiesto(permesso))
        VStack(alignment: .leading, spacing: 16) {
            Text(T("\(numero) di \(di)", "\(numero) of \(di)"))
                .font(.system(size: MisureImpostazioni.piccolo)).foregroundStyle(m.t3)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: Self.simbolo(permesso))
                    .font(.system(size: 18)).foregroundStyle(m.a2)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(m.a2.opacity(m.chiaro ? 0.13 : 0.16)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(Permessi.nome(permesso)).font(.system(size: 17)).foregroundStyle(m.t1)
                    Text(Permessi.perche(permesso)).font(.system(size: MisureImpostazioni.testo)).foregroundStyle(m.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                switch s {
                case .concesso:
                    Label(T("Concesso", "Allowed"), systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: MisureImpostazioni.testo - 1))
                        .foregroundStyle(m.a2)
                case .daChiedere:
                    // l'automazione senza System Events acceso risponde "da chiedere" anche se è concessa: si verifica chiedendo
                    Text(permesso == .automazione ? T("Da verificare", "To check") : T("Da concedere", "Not yet allowed"))
                        .font(.system(size: MisureImpostazioni.testo - 1)).foregroundStyle(m.t2)
                    if azione == .chiedi {
                        TastoImpostazioni(T("Concedi", "Allow"), principale: true) { Permessi.chiedi(permesso) { _ in aggiorna() } }
                    } else {
                        TastoImpostazioni(T("Apri Impostazioni di Sistema", "Open System Settings"), principale: true) { Permessi.apriPannello(permesso) }
                    }
                case .negato:
                    Text(T("Negato", "Denied")).font(.system(size: MisureImpostazioni.testo - 1)).foregroundStyle(m.t2)
                    TastoImpostazioni(T("Apri Impostazioni di Sistema", "Open System Settings")) { Permessi.apriPannello(permesso) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MisureImpostazioni.raggio, style: .continuous).fill(m.gruppo))
    }

    static func simbolo(_ p: Permesso) -> String {
        switch p {
        case .accessibilita: return "accessibility"
        case .automazione: return "gearshape.2.fill"
        case .registrazioneSchermo: return "rectangle.dashed.badge.record"
        case .microfono: return "mic.fill"
        case .riconoscimentoVocale: return "waveform"
        case .calendario: return "calendar"
        }
    }
}

/// Titolo e nota grigia delle schermate 2 e 3 (come PaginaCornice, senza lo scorrimento).
private struct Intestazione: View {
    let titolo: String
    let nota: String
    @Environment(\.matte) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo).font(.system(size: 20, weight: .regular)).foregroundStyle(m.t1)
            Text(nota).font(.system(size: MisureImpostazioni.piccolo + 1)).foregroundStyle(m.t2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
