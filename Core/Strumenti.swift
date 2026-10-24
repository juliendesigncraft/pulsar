// Strumenti comuni: testi nelle due lingue, shell, AppleScript e stato di sistema (18/10/2026, riordino fase 1): spostati qui da main.swift.
import AppKit
import SwiftUI

func T(_ it: String, _ en: String) -> String { pulsarItalian ? it : en }

@discardableResult
func shell(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return (-1, "") }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (p.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
}

/// Esegue un AppleScript e restituisce il codice d'errore (0 = tutto bene).
@discardableResult
func runAppleScript(_ source: String) -> Int {
    // NSAppleScript così il prompt Automazione (TCC) è attribuito a Pulsar.
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error {
        let msg = error[NSAppleScript.errorMessage] as? String ?? "?"
        NSLog("AppleScript error: %@", msg)
        return (error[NSAppleScript.errorNumber] as? Int) ?? -1
    }
    return 0
}

// MARK: - Stato di sistema

enum SystemState {
    static var darkMode: Bool {
        // v1.7: legge il tema di SISTEMA. Dalla v1.6 Pulsar è sempre scura, quindi il suo aspetto
        // (NSApp.effectiveAppearance) diceva "scuro" anche col Mac in chiaro: la spunta mentiva.
        Impostazioni.string(.appleInterfaceStyle) == "Dark"
    }
    static var desktopIconsHidden: Bool {
        let (status, out) = shell("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        guard status == 0 else { return false } // chiave assente = icone visibili
        return out == "0" || out.lowercased() == "false"
    }
    static var hiddenFilesShown: Bool {
        let (status, out) = shell("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"])
        guard status == 0 else { return false }
        return out == "1" || out.lowercased() == "true"
    }
    static var muted: Bool {
        let (_, out) = shell("/usr/bin/osascript", ["-e", "output muted of (get volume settings)"])
        return out == "true"
    }
    static var stageManager: Bool {
        let (status, out) = shell("/usr/bin/defaults", ["read", "com.apple.WindowManager", "GloballyEnabled"])
        guard status == 0 else { return false }
        return out == "1"
    }
}

// MARK: - Lingua (v1.9): italiano sui Mac in italiano, inglese altrove (spostato da main.swift)

var pulsarItalian = Locale.preferredLanguages.first?.hasPrefix("it") ?? false   // la dimostrazione la forza in inglese
/// Dimostrazione (11/10): il menu mostra dati finti al posto di app e cartelle vere (materiale pubblico).
var pulsarDemoMenu = false
