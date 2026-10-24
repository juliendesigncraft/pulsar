// Permessi di macOS nel Core: stato, richiesta, pannello di Impostazioni di Sistema, nome e perché.
// Usa le stesse chiamate che i moduli già usano (suoni, Dark Mode, calendario, Anima, miniatura).
// La parte pura (indirizzo del pannello) sta in PermessiPannelli.swift.
import AppKit
import AVFoundation
import Speech
import EventKit
import ApplicationServices
import CoreGraphics

/// v1.7: chiede (o verifica) il permesso Automazione verso System Events prima di usarlo.
/// Prima il comando falliva in silenzio se il permesso non c'era: nessun prompt, nessun segnale.
func automationAllowed(_ bundleID: String) -> OSStatus {
    let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
    var status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
    if status == OSStatus(procNotFound) {
        // System Events non è ancora partito: lo avvia un comando innocuo, poi si richiede
        _ = runAppleScript(#"tell application "System Events" to get name"#)
        status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
    }
    return status
}

extension Permessi {
    /// Stato attuale, senza mostrare nessuna richiesta (l'automazione non ha uno stato "da chiedere" senza prompt: vedi sotto).
    static func stato(_ p: Permesso) -> StatoPermesso {
        switch p {
        case .accessibilita:
            return AXIsProcessTrusted() ? .concesso : .daChiedere
        case .automazione:
            // askUserIfNeeded false: solo lettura, nessun prompt (a differenza di automationAllowed)
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
            let s = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
            if s == noErr { return .concesso }
            if s == OSStatus(errAEEventNotPermitted) { return .negato }
            return .daChiedere
        case .registrazioneSchermo:
            return CGPreflightScreenCaptureAccess() ? .concesso : .daChiedere
        case .microfono:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .concesso
            case .notDetermined: return .daChiedere
            default: return .negato
            }
        case .riconoscimentoVocale:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .concesso
            case .notDetermined: return .daChiedere
            default: return .negato
            }
        case .calendario:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .concesso
            case .notDetermined: return .daChiedere
            default: return .negato
            }
        }
    }

    /// Mostra la richiesta di macOS. Non blocca mai il filo principale; `fatto` arriva sul filo principale.
    /// Attenzione: per Accessibilità e Registrazione schermo il prompt di macOS è asincrono, quindi `fatto` riceve
    /// lo stato di PRIMA della risposta dell'utente. Le pagine devono rileggere `stato` quando l'app torna attiva
    /// (NSApplication.didBecomeActiveNotification). Microfono, voce, calendario e automazione rispondono a richiesta chiusa.
    static func chiedi(_ p: Permesso, fatto: @escaping (StatoPermesso) -> Void) {
        let fine: () -> Void = { DispatchQueue.main.async { fatto(stato(p)) } }
        switch p {
        case .accessibilita:
            segnaChiesto(p)   // macOS la mostra una volta sola: da qui in poi le pagine offrono il pannello (Permessi.azione)
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            fine()
        case .automazione:
            // la chiamata può aspettare la risposta dell'utente: fuori dal filo principale.
            // NSAppleScript solo sul principale, quindi qui System Events si avvia con NSWorkspace.
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
                var s = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
                if s == OSStatus(procNotFound),
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systemevents") {
                    let conf = NSWorkspace.OpenConfiguration()
                    conf.activates = false
                    conf.hides = true
                    let sem = DispatchSemaphore(value: 0)
                    NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, _ in sem.signal() }
                    _ = sem.wait(timeout: .now() + 10)
                    s = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
                }
                fine()
            }
        case .registrazioneSchermo:
            segnaChiesto(p)
            _ = CGRequestScreenCaptureAccess()
            fine()
        case .microfono:
            AVCaptureDevice.requestAccess(for: .audio) { _ in fine() }
        case .riconoscimentoVocale:
            SFSpeechRecognizer.requestAuthorization { _ in fine() }
        case .calendario:
            let store = EKEventStore()
            store.requestFullAccessToEvents { _, _ in _ = store; fine() }   // lo store resta vivo fino alla risposta
        }
    }

    static func apriPannello(_ p: Permesso) {
        if let url = URL(string: pannello(p)) { NSWorkspace.shared.open(url) }
    }

    static func nome(_ p: Permesso) -> String {
        switch p {
        case .accessibilita: return T("Accessibilità", "Accessibility")
        case .automazione: return T("Automazione", "Automation")
        case .registrazioneSchermo: return T("Registrazione schermo", "Screen recording")
        case .microfono: return T("Microfono", "Microphone")
        case .riconoscimentoVocale: return T("Riconoscimento vocale", "Speech recognition")
        case .calendario: return T("Calendario", "Calendar")
        }
    }

    static func perche(_ p: Permesso) -> String {
        switch p {
        case .accessibilita: return T("Per i suoni dei tasti e le scorciatoie in tutte le app", "For key sounds and shortcuts in every app")
        case .automazione: return T("Per cambiare la Dark Mode tramite System Events", "To switch Dark Mode through System Events")
        case .registrazioneSchermo: return T("Per le miniature delle finestre e per cerchiare lo schermo", "For window thumbnails and for circling the screen")
        case .microfono: return T("Per dettare e dare comandi con la voce", "To dictate and give voice commands")
        case .riconoscimentoVocale: return T("Per capire ciò che dici quando detti", "To understand what you say when you dictate")
        case .calendario: return T("Per mostrare i prossimi eventi nell'isola", "To show upcoming events in the island")
        }
    }
}
