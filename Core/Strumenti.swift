import CoreAudio
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
    // 13/11: letture dirette delle preferenze (CFPreferences) e del muto (CoreAudio) al posto di `defaults` e `osascript`:
    // il pannello della barra le chiedeva a ogni apertura e ogni processo costava decine di millisecondi (250-470 ms in tutto).
    private static func preferenza(_ chiave: String, _ dominio: String) -> Any? {
        CFPreferencesAppSynchronize(dominio as CFString)
        return CFPreferencesCopyAppValue(chiave as CFString, dominio as CFString)
    }
    private static func vero(_ v: Any?) -> Bool? {
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["1", "true", "yes"].contains(s.lowercased()) }
        return nil
    }
    static var desktopIconsHidden: Bool { vero(preferenza("CreateDesktop", "com.apple.finder")).map { !$0 } ?? false }   // assente = icone visibili
    static var hiddenFilesShown: Bool { vero(preferenza("AppleShowAllFiles", "com.apple.finder")) ?? false }
    static var muted: Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0, dim = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &dim, &id) == noErr, id != 0 else { return false }
        var m = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0; dim = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &m), AudioObjectGetPropertyData(id, &m, 0, nil, &dim, &v) == noErr else { return false }
        return v != 0
    }
    static var stageManager: Bool { vero(preferenza("GloballyEnabled", "com.apple.WindowManager")) ?? false }
}

// MARK: - Lingua (v1.9): italiano sui Mac in italiano, inglese altrove (spostato da main.swift)

var pulsarItalian = Locale.preferredLanguages.first?.hasPrefix("it") ?? false   // la dimostrazione la forza in inglese
/// Dimostrazione (11/10): il menu mostra dati finti al posto di app e cartelle vere (materiale pubblico).
var pulsarDemoMenu = false
