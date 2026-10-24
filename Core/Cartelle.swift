// Dove Pulsar tiene i suoi dati. Solo Foundation: si prova in prove/main.swift.
// La build dell'autore resta in ~/Library/Application Support/Pulsar (la leggono Spazio e gli hook già collegati);
// la vendita usa una cartella sua col nome dell'identificatore, così le due build non si pestano i piedi.
import Foundation

enum Cartelle {
    /// Pura: `personale` dà ".../Application Support/Pulsar", altrimenti ".../Application Support/<id>".
    static func dati(personale: Bool, id: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(personale ? "Pulsar" : id, isDirectory: true)
    }

    /// La cartella dati di questa build. Se manca la crea; non cancella mai niente.
    static var dati: URL {
        let url = dati(personale: false, id: App.id)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
