// Cuffie nel notch (04/11/2026, l'autore: "una bella animazione che mostri lo stile di Nothing mischiato a Spazio dark matte").
// Quando una cuffia Bluetooth si collega (o si scollega) esce una comparsa sotto il notch: due auricolari fatti di puntini,
// come la matrice a punti di Nothing, che si accendono a cascata, il puntino rosso che lampeggia (il segno di Nothing);
// poi i puntini si spostano e diventano il razzo di Spazio, che decolla. Testi in sans come in Spazio, azzurro di Spazio. La batteria non c'è: macOS non la dà per queste cuffie.
// Prova: open -g "pulsar://comparsa?tipo=cuffie&titolo=Nothing%20Ear"  (&dettaglio=Disconnected per lo scollegamento)
import SwiftUI
import IOBluetooth

// MARK: - Chi si è collegato

/// Controlla ogni 3 secondi le cuffie accoppiate. All'avvio ricorda quelle già collegate senza dire niente: la comparsa
/// esce solo per un collegamento nuovo. Legge solo nome e stato; nessuna scrittura, nessun permesso in più di quelli di Pulsar.
final class CuffieMonitor {
    static let shared = CuffieMonitor()
    private var timer: Timer?
    private var collegate: Set<String>?          // indirizzo → nil finché non è stata fatta la prima lettura

    func start() {
        guard timer == nil else { return }
        controlla()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.controlla() }
    }

    /// Cuffie e auricolari: classe Bluetooth "audio". Tastiere, mouse e telefoni restano fuori.
    private func audioCollegati() -> [String: String] {
        var out: [String: String] = [:]
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where d.isConnected() {
            guard d.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) else { continue }
            out[d.addressString ?? d.name ?? "?"] = d.name ?? "Bluetooth"
        }
        nomi.merge(out) { $1 }
        return out
    }

    private func controlla() {
        let ora = audioCollegati()
        defer { collegate = Set(ora.keys) }
        guard let prima = collegate, PeekPrefs.system else { return }
        for (ind, nome) in ora where !prima.contains(ind) { annuncia(nome, collegata: true) }
        for ind in prima where ora[ind] == nil { annuncia(Self.nomeNoto(ind) ?? "Bluetooth", collegata: false) }
    }

    private var nomi: [String: String] = [:]
    static func nomeNoto(_ ind: String) -> String? { shared.nomi[ind] }

    private func annuncia(_ nome: String, collegata: Bool) {
        PeekCenter.shared.post(PeekItem(key: "cuffie.\(nome)", kind: "cuffie", symbol: collegata ? "on" : "off", title: nome,
                                        detail: collegata ? T("Collegate", "Connected") : T("Scollegate", "Disconnected"),
                                        priority: 70, duration: 4.8))
    }
}

// MARK: - La comparsa

/// Due auricolari di puntini che diventano un razzo di puntini. Tutto calcolato dal tempo trascorso (TimelineView), niente stato.
struct CuffiePeek: View {
    let item: PeekItem
    @State private var inizio = Date()
    private var collegata: Bool { item.symbol != "off" }

    static let altezza: CGFloat = 64
    static let larghezza: CGFloat = 344
    private static let passo: CGFloat = 4, punto: CGFloat = 2.5
    private static let colonne = 19, righe = 14

    /// Un auricolare 9 colonne per 12 righe: testa tonda in alto, stelo in basso (la sagoma dei Nothing Ear a stelo).
    private static let sagoma: [String] = [
        "..####...", ".######..", ".#######.", ".#######.", ".#######.", "..######.",
        "...#####.", "....####.", "....####.", "....####.", ".....###.", ".....##..",
    ]
    /// Il razzo, 9 colonne per 11 righe, con la finestrella al centro (riga 5) che prende il puntino rosso.
    private static let sagomaRazzo: [String] = [
        "....#....", "...###...", "...###...", "..#####..", "..#####..", "..##.##..",
        "..#####..", ".#######.", ".#######.", "##.###.##", "...###...",
    ]
    private static let rosso = Color(red: 0.93, green: 0.13, blue: 0.17)      // il rosso di Nothing

    private struct Punto { var c: Int; var r: Int; var lato: Int }
    private static let auricolari: [Punto] = {
        var v: [Punto] = []
        for lato in 0..<2 { for (r, riga) in sagoma.enumerated() { for (c, ch) in riga.enumerated() where ch == "#" {
            v.append(Punto(c: lato == 0 ? c : 18 - c, r: r + 1, lato: lato))          // il secondo è lo specchio del primo
        } } }
        return v.sorted { ($0.r, $0.c, $0.lato) < ($1.r, $1.c, $1.lato) }
    }()
    private static let razzo: [Punto] = {
        var v: [Punto] = []
        for (r, riga) in sagomaRazzo.enumerated() { for (c, ch) in riga.enumerated() where ch == "#" { v.append(Punto(c: c + 5, r: r, lato: 0)) } }
        return v.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(inizio)
            let testo = Self.sale(t, da: 0.7, dura: 0.5) * (1 - Self.sale(t, da: 4.0, dura: 0.5))
            HStack(spacing: 0) {
                Canvas { g, _ in disegnaPunti(g, t: t) }
                    .frame(width: CGFloat(Self.colonne) * Self.passo + 2, height: CGFloat(Self.righe) * Self.passo + 2)
                Spacer(minLength: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 12.5, weight: .regular)).foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1).truncationMode(.tail)
                    Text(item.detail).font(.system(size: 10.5, weight: .light))
                        .foregroundStyle(collegata ? Volta.a2 : Color.white.opacity(0.45))
                }
                .opacity(testo).offset(x: (1 - testo) * -8)
                Spacer(minLength: 10)
                Canvas { g, size in disegnaOnde(g, size: size, t: t) }.frame(width: CGFloat(Self.colonne) * Self.passo + 2, height: CGFloat(Self.righe) * Self.passo + 2)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { inizio = Date().addingTimeInterval(0.3) }
    }

    static func sale(_ t: Double, da: Double, dura: Double) -> Double { min(1, max(0, (t - da) / dura)) }
    private static func morbido(_ x: Double) -> Double { let u = min(1, max(0, x)); return u * u * (3 - 2 * u) }

    private func disegnaPunti(_ g: GraphicsContext, t: Double) {
        let p = Self.passo, d = Self.punto
        let tMorph = 1.2, tVola = 2.8
        let su = t > tVola ? pow(t - tVola, 2) * 100 : 0                     // dopo il decollo il razzo sale
        let sparisce = t > tVola ? max(0, 1 - max(0, t - tVola - 0.35) / 0.55) : 1
        let respira = t > 2.0 && t < tVola ? sin(t * 3) * 0.8 : 0            // fermo: un respiro
        let ledAcceso = collegata ? (t > 0.5 && t < 0.62) || (t > 0.8 && t < 0.92) || t > 1.15 : false
        var ultimo = -1
        for (k, e) in Self.auricolari.enumerated() {
            let j = k * Self.razzo.count / Self.auricolari.count
            let doppio = j == ultimo; ultimo = j                              // i puntini in più si spengono: il razzo ne ha meno
            let m = collegata ? Self.morbido((t - tMorph - Double(e.r) * 0.03) / 0.75) : 0
            let r2 = Self.razzo[j]
            let cx = Double(e.c) + (Double(r2.c) - Double(e.c)) * m
            let cy = Double(e.r) + (Double(r2.r) - Double(e.r)) * m
            let x = CGFloat(cx) * p + d / 2 + 1
            let y = CGFloat(cy) * p + d / 2 + 1 - CGFloat(su) + CGFloat(respira * m)
            let nasce = Double(e.r) * 0.045 + Double(e.lato) * 0.16 + Double(e.c) * 0.008
            var a = Self.sale(t, da: nasce, dura: 0.22) * (doppio ? 1 - m : 1) * sparisce
            if !collegata { a *= 0.35 + 0.65 * max(0, 1 - max(0, t - 1.6) / 1.2) }
            var colore: Color = t < nasce + 0.4 || !collegata ? .white : Volta.a2
            if m > 0.5 { colore = Color(red: 0.86, green: 0.93, blue: 1) }      // il razzo è chiaro, come quello di Spazio
            let banda = collegata && t > 0.6 && t < tMorph ? exp(-pow(Double(e.r) - (t * 6).truncatingRemainder(dividingBy: 16) + 2, 2) / 2.2) : 0
            let sz = d * (1 + 0.28 * banda)
            let rect = CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz)
            if collegata && e.lato == 0 && e.r == 3 && e.c == 6 { continue }    // questo è il puntino rosso, lo disegna sotto
            g.fill(Path(ellipseIn: rect), with: .color(colore.opacity(a * ((0.55 + 0.45 * banda) * (1 - m) + m))))
        }
        if collegata {
            // il puntino rosso di Nothing: lampeggia sull'auricolare, poi scende a fare la finestrella del razzo
            let m = Self.morbido((t - tMorph - 0.1) / 0.75)
            let cx = 6.0 + (9.0 - 6.0) * m, cy = 3.0 + (5.0 - 3.0) * m
            let x = CGFloat(cx) * p + d / 2 + 1, y = CGFloat(cy) * p + d / 2 + 1 - CGFloat(su) + CGFloat(respira * m)
            let respiro = t > 1.3 ? 0.78 + 0.22 * sin(t * 4) : 1
            let v = (ledAcceso ? 1 : 0.12) * respiro * sparisce
            let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
            g.fill(Path(ellipseIn: rect.insetBy(dx: -1.2, dy: -1.2)), with: .color(Self.rosso.opacity(0.28 * v)))
            g.fill(Path(ellipseIn: rect), with: .color(Self.rosso.opacity(v)))
            // la fiamma: tre file di puntini sotto l'ugello, che tremano
            if t > tMorph + 0.7 && t < tVola + 1.0 {
                let forza = Self.sale(t, da: tMorph + 0.7, dura: 0.4) * (t > tVola ? 1 + (t - tVola) * 1.5 : 1)
                for riga in 0..<3 {
                    for dx in (riga == 0 ? [-1, 0, 1] : [0]) {
                        let tremo = 0.55 + 0.45 * sin(t * 31 + Double(riga) * 1.7 + Double(dx) * 2.3)
                        let fx = CGFloat(9 + dx) * p + d / 2 + 1
                        let fy = CGFloat(11 + riga) * p + d / 2 + 1 - CGFloat(su)
                        let al = forza * tremo * (1 - Double(riga) * 0.3) * sparisce
                        g.fill(Path(ellipseIn: CGRect(x: fx - d / 2, y: fy - d / 2, width: d, height: d)),
                               with: .color((riga == 0 ? Color.white : Volta.a2).opacity(al)))
                    }
                }
            }
        }
    }

    /// Tre archi di puntini dal notch: escono prima del razzo e poi si spengono.
    private func disegnaOnde(_ g: GraphicsContext, size: CGSize, t: Double) {
        guard collegata else { return }
        let fuori = 1 - Self.sale(t, da: 1.2, dura: 0.5)
        let centro = CGPoint(x: 2, y: size.height / 2)
        for (i, raggio) in [8.0, 15.0, 22.0, 29.0].enumerated() {
            let fase = (t * 1.6 - Double(i) * 0.28).truncatingRemainder(dividingBy: 2.2)
            let luce = t > 0.55 ? max(0, 1 - abs(fase - 0.4) * 1.5) : 0
            for k in -3...3 {
                let ang = Double(k) * 0.26
                let q = CGPoint(x: centro.x + raggio * cos(ang), y: centro.y + raggio * sin(ang))
                g.fill(Path(ellipseIn: CGRect(x: q.x - 1.2, y: q.y - 1.2, width: 2.4, height: 2.4)),
                       with: .color(Volta.a2.opacity((0.14 + 0.86 * luce) * fuori)))
            }
        }
    }
}
