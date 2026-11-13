// Bordi del trackpad (06/11/2026, idea da EdgeBar): la parte pura. Riceve i fotogrammi del trackpad (le dita, in
// coordinate da 0 a 1, y = 0 è il bordo vicino a chi scrive) e dice cosa è successo: un dito partito dal bordo che
// scorre lungo il bordo regola qualcosa. Solo Foundation: si prova in prove/main.swift senza l'app.
//
// Regole, ricavate dalla sonda della tappa 1 (macOS 26.6.2):
// - vale solo con UN dito: con quattro dita (cambio di scrivania) qualche dito finisce sul bordo e non deve contare;
// - il dito deve PARTIRE nella fascia del bordo: chi attraversa il bordo muovendo il puntatore non regola niente;
// - si attiva dopo un piccolo scorrimento LUNGO il bordo; se prima va verso il centro è un movimento normale;
// - un secondo dito blocca il gesto fino a quando tutte le dita si alzano.
import Foundation

enum BordoTrackpad: String, CaseIterable {
    case destro, sinistro, basso
}

/// Cosa fa un bordo. `scatto` = un colpo solo per gesto (traccia avanti o indietro), le altre seguono il dito.
enum AzioneBordo: String, CaseIterable {
    case volume, luce, tracce, nessuna
    var aScatti: Bool { self == .tracce }
}

struct DitoTrackpad: Equatable {
    var x: Float
    var y: Float
}

enum EventoBordo: Equatable {
    case inizio(BordoTrackpad)
    /// Quanto cambiare il valore (da -1 a 1 = tutta la corsa). Su: più; per il bordo in basso: a destra = più.
    case regola(BordoTrackpad, delta: Float)
    /// Un colpo solo: avanti (su, o a destra) o indietro.
    case scatto(BordoTrackpad, avanti: Bool)
    case fine(BordoTrackpad)
}

struct RegoleBordi: Equatable {
    /// Quanto è larga la fascia del bordo, in frazione del trackpad.
    var fascia: Float
    /// Quanta strada lungo il bordo fa passare da 0 a 100% (frazione della lunghezza del bordo). Più piccola = più sensibile.
    var corsaPiena: Float
    /// Scorrimento lungo il bordo prima che il gesto parta (sotto, è un tocco o un clic).
    var avvio: Float
    /// Scorrimento che fa scattare la traccia successiva o precedente.
    var scatto: Float

    // Valori della tappa 2. La fascia sta sopra il 2,4% misurato in tappa 1 (il dito sul bordo destro arrivava a x=0,976).
    // Provati col dito dall'autore il 06/11 sulla build installata: vanno bene così. Si ritoccano solo se lui lo chiede.
    static let diSerie = RegoleBordi(fascia: 0.06, corsaPiena: 0.6, avvio: 0.03, scatto: 0.12)

    /// Sensibilità dalle Impostazioni (0 = lenta, 1 = veloce): cambia solo la corsa piena, da 0,9 a 0,35.
    func conSensibilita(_ s: Double) -> RegoleBordi {
        var r = self
        let t = Float(max(0, min(1, s)))
        r.corsaPiena = 0.9 - 0.55 * t
        return r
    }
}

struct GestoBordi {
    var regole: RegoleBordi
    /// Cosa fa ogni bordo; un bordo con `.nessuna` non si attiva mai.
    var azioni: [BordoTrackpad: AzioneBordo]

    private enum Stato: Equatable {
        case libero                                       // nessun dito
        case candidato(BordoTrackpad, partenza: DitoTrackpad)
        case attivo(BordoTrackpad, ultimo: Float, accumulo: Float, scattato: Bool)
        case bloccato                                     // fino a quando tutte le dita si alzano
    }
    private var stato: Stato = .libero

    init(regole: RegoleBordi = .diSerie, azioni: [BordoTrackpad: AzioneBordo]) {
        self.regole = regole
        self.azioni = azioni
    }

    var attivo: BordoTrackpad? {
        if case .attivo(let b, _, _, _) = stato { return b }
        return nil
    }

    /// Il bordo dove sta il dito, o nil. Negli angoli vince il bordo più vicino tra quelli che fanno qualcosa.
    func bordo(di d: DitoTrackpad) -> BordoTrackpad? {
        let f = regole.fascia
        let distanze: [(BordoTrackpad, Float)] = [(.destro, 1 - d.x), (.sinistro, d.x), (.basso, d.y)]
        return distanze
            .filter { $0.1 <= f && (azioni[$0.0] ?? .nessuna) != .nessuna }
            .min { $0.1 < $1.1 }?.0
    }

    /// La posizione lungo il bordo (y per i lati, x per il basso) e quella verso il centro.
    private static func lungo(_ b: BordoTrackpad, _ d: DitoTrackpad) -> Float { b == .basso ? d.x : d.y }
    private static func dentro(_ b: BordoTrackpad, _ d: DitoTrackpad) -> Float {
        switch b { case .destro: return 1 - d.x; case .sinistro: return d.x; case .basso: return d.y }
    }

    /// Un fotogramma del trackpad. Restituisce gli eventi da eseguire, nell'ordine.
    mutating func passo(_ dita: [DitoTrackpad]) -> [EventoBordo] {
        // nessun dito: il gesto finisce e si ricomincia da capo
        if dita.isEmpty {
            defer { stato = .libero }
            if case .attivo(let b, _, _, _) = stato { return [.fine(b)] }
            return []
        }
        // più di un dito: mai un gesto, e niente fino a quando si alzano tutte
        if dita.count > 1 {
            defer { stato = .bloccato }
            if case .attivo(let b, _, _, _) = stato { return [.fine(b)] }
            return []
        }
        let d = dita[0]
        switch stato {
        case .bloccato:
            return []
        case .libero:
            if let b = bordo(di: d) { stato = .candidato(b, partenza: d) } else { stato = .bloccato }
            return []
        case .candidato(let b, let p):
            // verso il centro prima di partire: è il puntatore, non un gesto
            if Self.dentro(b, d) > regole.fascia * 2 { stato = .bloccato; return [] }
            let corsa = Self.lungo(b, d) - Self.lungo(b, p)
            guard abs(corsa) >= regole.avvio else { return [] }
            // si conta dal punto dove il dito si è appoggiato: la strada fatta prima dell'avvio non va persa
            stato = .attivo(b, ultimo: Self.lungo(b, p), accumulo: 0, scattato: false)
            return [.inizio(b)] + passo(dita)
        case .attivo(let b, let ultimo, let accumulo, let scattato):
            let ora = Self.lungo(b, d)
            let mosso = ora - ultimo
            let azione = azioni[b] ?? .nessuna
            if azione.aScatti {
                let somma = accumulo + mosso
                if !scattato && abs(somma) >= regole.scatto {
                    stato = .attivo(b, ultimo: ora, accumulo: 0, scattato: true)
                    return [.scatto(b, avanti: somma > 0)]
                }
                stato = .attivo(b, ultimo: ora, accumulo: scattato ? 0 : somma, scattato: scattato)
                return []
            }
            stato = .attivo(b, ultimo: ora, accumulo: 0, scattato: false)
            guard mosso != 0 else { return [] }
            return [.regola(b, delta: mosso / regole.corsaPiena)]
        }
    }
}
