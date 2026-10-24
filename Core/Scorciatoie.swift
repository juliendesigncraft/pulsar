// Tutte le scorciatoie globali di Pulsar in un elenco solo, per la pagina Scorciatoie delle Impostazioni (fase 3).
// Solo Foundation: si prova senza l'app. Cercate il 19/10/2026 nei RegisterEventHotKey e nei monitor keyDown e
// flagsChanged di tutti i moduli: Agent (agente.swift, addHotkeys), Voce (anima.swift, AnimaKeys), Griglia
// (griglia.swift, RegisterEventHotKey), Rowline (Moduli/Rowline/Kit/tasti.swift, Azione.predefinita: si cambiano dal
// pannello di Rowline, qui ci sono quelle di serie). Le altre scorciatoie (Esc, frecce, Invio) valgono solo dentro una finestra aperta.
// Se un modulo ne registra una nuova, va aggiunta qui.
import Foundation

enum Scorciatoie {
    /// La lingua di `tutte`. L'app usa `elenco(italiano: pulsarItalian)`, che segue anche la dimostrazione in inglese.
    static var italiano = Locale.preferredLanguages.first?.hasPrefix("it") ?? false

    static var tutte: [(tasti: String, cosa: String, modulo: String)] { elenco(italiano: italiano) }

    /// `griglia`: il tasto della griglia scelto oggi (GridModule.hotKey: ⌘4, ⌃⌥Spazio o Spenta), lo passa la pagina.
    static func elenco(italiano it: Bool, griglia: String = "⌘4") -> [(tasti: String, cosa: String, modulo: String)] {
        func t(_ i: String, _ e: String) -> String { it ? i : e }
        return [
            ("⌃⌥Y", t("Consenti la richiesta di Claude Code", "Allow the Claude Code request"), "Agent"),
            ("⌃⌥N", t("Nega la richiesta", "Deny the request"), "Agent"),
            ("⌃⌥A", t("Consenti sempre", "Always allow"), "Agent"),
            ("⌃⌥P", t("Apri e chiudi il pannello", "Open and close the panel"), "Agent"),
            // ⌃⌥L sta nel monitor dell'Agente: funziona con l'Agente acceso e i Temi sbloccati
            ("⌃⌥L", t("Passa fra Dark Matte e White Matte", "Switch between Dark Matte and White Matte"), "Agent"),
            ("⌃⌥", t("Tieni premuto per dettare", "Hold to dictate"), t("Voce", "Voice")),
            ("⌃⌘", t("Tieni premuto per dare un comando", "Hold to give a command"), t("Voce", "Voice")),
            ("⌃⇧", t("Tieni premuto per cerchiare e chiedere", "Hold to circle and ask"), t("Voce", "Voice")),
            // la scorciatoia della griglia si sceglie fra ⌘4, ⌃⌥Spazio e spenta (GridModule.HotKey): una sola alla volta
            (griglia, t("Griglia delle app", "App grid"), t("Griglia", "Grid")),
        ] + rowline(it)
    }

    /// Rowline: le scorciatoie di serie (Azione.predefinita in tasti.swift), ⌃⌥⌘ e ⌃⌥⇧⌘. Chi le cambia lo fa nel pannello di Rowline.
    private static func rowline(_ it: Bool) -> [(tasti: String, cosa: String, modulo: String)] {
        func t(_ i: String, _ e: String) -> String { it ? i : e }
        let mod = t("Rowline, di serie", "Rowline, defaults")
        let i = "⌃⌥⌘", s = "⌃⌥⇧⌘"
        return [
            (i + "F", t("Apri Rowline", "Open Rowline")),
            (i + "P", t("Accendi o spegni", "Turn on or off")),
            (i + "←", t("Finestra a sinistra", "Window on the left")),
            (i + "→", t("Finestra a destra", "Window on the right")),
            (i + "↑", t("Su nella pila", "Up in the stack")),
            (i + "↓", t("Giù nella pila", "Down in the stack")),
            (s + "←", t("Sposta a sinistra", "Move left")),
            (s + "→", t("Sposta a destra", "Move right")),
            (i + "1", t("Metà schermo", "Half screen")),
            (i + "2", t("Due terzi", "Two thirds")),
            (i + "3", t("Schermo intero", "Full width")),
            (i + "R", t("Cambia larghezza", "Change width")),
            (i + "=", t("Più larga", "Wider")),
            (i + "-", t("Più stretta", "Narrower")),
            (i + "C", t("Al centro", "Centre")),
            (i + "[", t("Impila a sinistra", "Stack left")),
            (i + "]", t("Impila a destra", "Stack right")),
            (s + "[", t("Stacca a sinistra", "Pop out left")),
            (s + "]", t("Stacca a destra", "Pop out right")),
            (i + "T", t("Galleggia o rimetti in fila", "Float or put back")),
            (i + "G", t("Griglia", "Grid")),
            (i + "N", t("All'altro schermo", "To the other display")),
            (i + "4", t("Postazione 1", "Workspace 1")),
            (i + "5", t("Postazione 2", "Workspace 2")),
            (i + "6", t("Postazione 3", "Workspace 3")),
        ].map { (tasti: $0.0, cosa: $0.1, modulo: mod) }
    }
}
