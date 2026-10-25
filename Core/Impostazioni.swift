// Le impostazioni di Pulsar con un nome: ogni chiave di UserDefaults ha un caso di `Chiave` (il rawValue è la stringa
// di sempre, quindi nessuna preferenza salvata si perde) e si legge e scrive solo da `Impostazioni`.
// 18/10/2026, riordino fase 1. `snap` non c'è: era una chiave di animazione (CAAnimation forKey), non di UserDefaults.
// Le chiavi costruite a runtime (bordo.<id>, dialUnmute.<id>, NSStatusItem Preferred
// Position <nome>) restano su UserDefaults.standard nel punto dove nascono, con un commento.
import Foundation

enum Chiave: String, CaseIterable {
    case appleIconAppearanceTheme = "AppleIconAppearanceTheme"
    case appleInterfaceStyle = "AppleInterfaceStyle"
    case aggiornamentiAutomatici   // fase 5, 3b: Sparkle cerca gli aggiornamenti da solo (acceso se mancante, solo vendita)
    case agentEnabled
    case agentLook
    case agentLookNotte
    case agentOnlySession
    case agentPill
    case agentPillPlace
    case agentSounds
    case agentTab
    case agentTabAuto
    case agenteFinestra
    case animaEnabled
    case animaLeggi
    case animaLingua
    case animaModello
    case animaParla
    case animaSoloMac
    case askedAccessibility
    case askedScreenRecording   // fase 3: la richiesta di Registrazione schermo è già stata mostrata (macOS non la ripete)
    case barCollapsed
    case dialEnabled
    case mutaAcceso, mutaRiordino, mutaScrivania, mutaDownload, mutaDopoConversione, mutaAttesa, mutaDal, mutaCartelle   // 19/10: Muta
    case dialGains
    case dialLinked
    case dialMode
    case dialTimer
    case grigliaAngolo
    case grigliaCategorie
    case grigliaCielo
    case grigliaImmagini
    case grigliaMeteo
    case grigliaNote
    case grigliaSfondo
    case grigliaTasto
    case impostazioniPagina   // fase 3: l'ultima pagina aperta nella finestra Impostazioni
    case benvenutoVisto       // fase 3: il benvenuto è già stato aperto (si scrive alla prima schermata)
    case moduliScelti         // fase 3: i moduli accesi nella scelta del benvenuto (ne escono i permessi da chiedere)
    case isolaAmbient
    case isolaAmbiente
    case isolaBordoMusica
    case isolaBraun1
    case isolaCity
    case isolaCityKey
    case isolaCityName
    case isolaDiskAlert
    case isolaEnabled
    case isolaHitodama1
    case isolaLanciatori1
    case lanciatoriAcceso      // 24/10: il modulo Lanciatori (Lite), acceso di serie
    case lanciatoriStash
    case lanciatoriScrivania
    case lanciatoriScrivaniaPos
    case isolaLat
    case isolaLon
    case isolaLyrics
    case isolaMeteoStretto
    case isolaPeekNotif
    case isolaPeekSystem
    case isolaPrioritaLarga
    case isolaThumb
    case isolaTiles
    case isolaTray
    case isolaUltimoBrano
    case isolaWAChat
    case isolaWinKey
    case isolaYouTube
    case knownApps
    case lightEnabled
    case lightKbOn
    case lightMode
    case licenzaControllo
    case licenzaProdotti
    case licenzaProvaDal
    case pulsarLeggera
    case pulsarTema
    case soundKeyVolume
    case soundMouse
    case soundMouseVolume
    case soundPack
    case soundsEnabled
    case rowlineAcceso
    case riunioneNelNotch
    case temiCambiaMacOS      // fase 5: il tema cambia anche l'aspetto di macOS (acceso se mancante)
    case temiScrivania        // 25/10: il tema cambia anche sfondo e cartelle scelte, solo vendita (spento se mancante)
    case temiCartelle         // 25/10: le cartelle che cambiano icona col tema (Moduli/Temi/temi-scrivania.swift)
    case tempoRegistra = "tempo.registra"
    case visibleDesktopCount
    case wallAccent
}

enum Impostazioni {
    private static var d: UserDefaults { .standard }
    static func bool(_ k: Chiave) -> Bool { d.bool(forKey: k.rawValue) }
    static func string(_ k: Chiave) -> String? { d.string(forKey: k.rawValue) }
    static func double(_ k: Chiave) -> Double { d.double(forKey: k.rawValue) }
    static func integer(_ k: Chiave) -> Int { d.integer(forKey: k.rawValue) }
    static func object(_ k: Chiave) -> Any? { d.object(forKey: k.rawValue) }
    static func stringArray(_ k: Chiave) -> [String]? { d.stringArray(forKey: k.rawValue) }
    static func dictionary(_ k: Chiave) -> [String: Any]? { d.dictionary(forKey: k.rawValue) }
    static func data(_ k: Chiave) -> Data? { d.data(forKey: k.rawValue) }
    static func set(_ v: Any?, _ k: Chiave) { d.set(v, forKey: k.rawValue) }
    static func remove(_ k: Chiave) { d.removeObject(forKey: k.rawValue) }
}

/// Fase 5, compito 2c: la Voce (Anima) è in Beta. Valore salvato mancante o strano = il predefinito della build:
/// acceso in quella dell'autore, spento nella vendita. Pura sul valore e sulla build, così si provano i due rami.
func animaAccesaDa(_ salvato: Any?, personale: Bool) -> Bool { salvato as? Bool ?? personale }

/// Revisione finale della fase 5: la lingua in cui la Voce ascolta. La chiave salvata (`animaLingua`) vince; senza chiave
/// la build dell'autore ascolta in italiano (com'era), la vendita nella lingua del Mac (`mac`, l'identificativo del Locale
/// corrente, "en_US" o "it_IT"), e senza quella in inglese americano. Pura, così si provano i due rami.
func animaLinguaDa(_ salvato: Any?, personale: Bool, mac: String?) -> String {
    if let s = salvato as? String, !s.isEmpty { return s }
    if personale { return "it-IT" }
    let m = (mac ?? "").split(separator: "@").first.map { $0.replacingOccurrences(of: "_", with: "-") } ?? ""
    return m.isEmpty ? "en-US" : m
}

extension Impostazioni {
    /// La lingua della Voce per questa build (vedi `animaLinguaDa`).
    static var linguaVoce: String {
        return animaLinguaDa(string(.animaLingua), personale: false, mac: Locale.current.identifier)
    }
    /// Il predefinito della Voce: `true` con PERSONALE, `false` nella vendita.
    static var animaAccesaDiSerie: Bool {
        return false
    }
    /// La Voce è accesa? La chiave salvata vince; senza chiave decide `animaAccesaDiSerie`. La usano il modulo,
    /// la pagina Voce e il benvenuto: un solo predefinito per tutti.
    static var animaAccesa: Bool { animaAccesaDa(object(.animaEnabled), personale: animaAccesaDiSerie) }
}

/// Fase 5: il tema cambia anche macOS? Valore salvato mancante o strano = sì (come prima della fase 5).
/// Pura sul valore salvato, così si prova senza AppKit; `Temi.scegli` la usa.
func temaCambiaMacOS(_ salvato: Any?) -> Bool { salvato as? Bool ?? true }

/// Fase 5, 3b: Sparkle cerca gli aggiornamenti da solo? Valore salvato mancante o strano = sì (acceso di serie).
/// Pura sul valore salvato, così si prova senza Sparkle; `Aggiornamenti` (Moduli/Lite/aggiornamenti.swift) la usa.
func aggiornamentiAutomaticiDa(_ salvato: Any?) -> Bool { salvato as? Bool ?? true }

extension Impostazioni {
    static var aggiornamentiAutomatici: Bool { aggiornamentiAutomaticiDa(object(.aggiornamentiAutomatici)) }
}

/// Gli aspetti vecchi (scuro, vetro, vetroScuro), un valore mancante o strano diventano Dark Matte ("notte").
/// Funzione pura sul rawValue di `AgentMode`, così si prova senza SwiftUI; `AgentMode.migra` la avvolge.
func aspettoMigrato(_ raw: String?) -> String {
    switch raw {
    case "bianco": return "bianco"
    case "sfondo": return "sfondo"
    default: return "notte"
    }
}
