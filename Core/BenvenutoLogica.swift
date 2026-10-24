// La parte pura del benvenuto (fase 3, compito 7): quali permessi chiedere e quando aprirlo. Solo Foundation.
import Foundation

enum BenvenutoLogica {
    /// I permessi dei moduli scelti: unione senza doppioni, nell'ordine fisso di `Permesso.allCases`
    /// (Accessibilità, Automazione, Registrazione schermo, Microfono, Riconoscimento vocale, Calendario).
    static func permessiDa(_ moduli: [(id: String, permessi: [Permesso])], scelti: Set<String>) -> [Permesso] {
        Registro.permessi(moduli.filter { scelti.contains($0.id) }.map(\.permessi))
    }

    /// Si apre da solo solo nella vendita, al primo avvio. Nella build personale mai (si apre con pulsar://benvenuto).
    static func deveAprire(visto: Bool, personale: Bool) -> Bool { !visto && !personale }

    /// I moduli a pagamento non partono finché il benvenuto è aperto: così nessuno chiede un permesso prima della scelta.
    /// Lite (fuori dal registro) parte subito come sempre. Senza benvenuto non aspetta nessuno.
    static let moduliAPagamento: Set<String> = ["agente", "ghiera", "isola", "griglia", "anima", "muta", "rowline"]
    static func moduliInAttesa(apreBenvenuto: Bool) -> Set<String> { apreBenvenuto ? moduliAPagamento : [] }
}
