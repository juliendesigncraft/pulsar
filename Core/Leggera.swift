// 13/10/2026, l'autore: "rendiamola leggera, non serve che sia stratosferica e piena di animazioni, basta che funzioni per me".
// Con Pulsar leggera (di default) tutte le animazioni continue (TimelineView .animation: meteo, striscia della musica,
// pulsazione del notch, icone a puntini, stella dell'Anima...) restano ferme sul loro fotogramma: si vede tutto, non gira
// niente a 30 fotogrammi al secondo. Le riprese dei reel (isola-demo.swift) la spengono e la rimettono come prima.
import Foundation

enum Leggera {
    static var on: Bool {
        get { Impostazioni.object(.pulsarLeggera) as? Bool ?? true }
        set { Impostazioni.set(newValue, .pulsarLeggera) }
    }
}
