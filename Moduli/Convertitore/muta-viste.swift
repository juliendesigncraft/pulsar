// Muta: le viste. Il "misto" scelto dall'autore il 19/10 (docs/bozze/muta-bozze.html), poi reso grafico la sera stessa
// ("il riferimento, Tangerine, era molto più grafico: un'icona dove si può, un'animazione ogni tanto"):
// - mentre si trascina (MutaDropCard): a sinistra l'anteprima vera del file in mano, tre tessere con un'icona grande e
//   una parola, sotto i formati come piccoli documenti; il dettaglio compare solo sulla tessera sotto il mouse;
// - dopo (MutaPeekRiga): nel notch chiuso una cartella che salta, il numero, Annulla e Mostra come icone;
// - le scelte (MutaSection): le regole come cartelle in griglia, ognuna col suo simbolo.
// Grammatica del notch del 17/10: niente contorni, solo l'azzurro di Spazio, tasto principale azzurro chiaro.
import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - Tessere nel notch

struct MutaDropCard: View {
    @ObservedObject var muta = MutaCentro.shared
    let altroveTitolo: String
    var altroveClaude = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            AnteprimaInMano(urls: muta.trascinati)
                .frame(width: MutaZona.anteprima, height: MutaZona.altezza)
            ForEach(Array(muta.posti.enumerated()), id: \.offset) { _, p in
                vista(p)
                    .frame(width: p.rect.width, height: p.rect.height)
                    .offset(x: p.rect.minX, y: p.rect.minY)
            }
        }
        .frame(width: MutaZona.larghezza, height: MutaZona.altezza, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: muta.sotto)
    }

    @ViewBuilder private func vista(_ p: Posto) -> some View {
        let on = muta.sotto == p.bersaglio
        switch p.bersaglio {
        case .scopo(let s): Tessera(scopo: s, peso: peso(s), on: on)
        case .formato(let f): Documentino(sigla: f.etichetta, simbolo: nil, on: on, aiuto: f.etichetta)
        case .unisci: Documentino(sigla: nil, simbolo: "square.stack", on: on, aiuto: T("Unisci in un PDF", "Merge into one PDF"))
        case .altrove: Documentino(sigla: nil, simbolo: altroveClaude ? "sparkles" : "tray", on: on, aiuto: altroveTitolo, tenue: true)
        case .strumento(let st): TesseraStrumento(strumento: st, on: on)
        case .email: Documentino(sigla: nil, simbolo: "envelope", on: on, aiuto: "Email")
        }
    }

    /// Sotto lo scopo, cosa diventerà: "WebP, 2000 px" (mai il puntino come separatore).
    private func peso(_ s: Scopo) -> String {
        guard let fam = muta.trascinati.lazy.compactMap({ Convertitore.famiglia(di: $0) }).first,
              let r = Convertitore.ricetta(s, per: fam) else { return "" }
        var t = r.formato.etichetta
        if let l = r.latoMax { t += ", \(l) px" }
        if r.comprimi { t += T(", più leggero", ", lighter") }
        return t
    }
}

/// L'anteprima vera del file in mano (Quick Look), una pila se sono di più, col numero. Respira piano.
private struct AnteprimaInMano: View {
    let urls: [URL]
    @State private var su = false
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.offset) { i, u in
                    Miniatura(url: u, lato: 64)
                        .rotationEffect(.degrees(Double(i) * 6 - (urls.count > 1 ? 4 : 0)))
                        .offset(x: CGFloat(i) * 5, y: CGFloat(i) * -3)
                }
            }
            .frame(width: 84, height: 74)
            .offset(y: su ? -2 : 2)
            if urls.count > 1 {
                Text("\(urls.count)").font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(Volta.primT)
                    .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(Volta.prim))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Volta.card))
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { su = true } }
    }
}

/// Miniatura di Quick Look; finché non arriva, l'icona del Finder.
struct Miniatura: View {
    let url: URL
    let lato: CGFloat
    @State private var img: NSImage?
    var body: some View {
        Image(nsImage: img ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: lato, height: lato)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .task(id: url) {
                let r = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: lato, height: lato),
                                                     scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                if let t = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: r) { img = t.nsImage }
            }
    }
}

/// Uno strumento (con ⌥): stessa grammatica della tessera degli scopi, più bassa, icona e una parola.
private struct TesseraStrumento: View {
    let strumento: Strumento
    let on: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: strumento.simbolo)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Volta.primT : Volta.a2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(on ? Volta.prim : Volta.card2))
                .symbolEffect(.bounce, value: on)
            Text(T(strumento.nomi.it, strumento.nomi.en))
                .font(.system(size: 13, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Volta.t1 : Volta.t2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Volta.a4 : Volta.card))
        .scaleEffect(on ? 1.03 : 1)
    }
}

private struct Tessera: View {
    let scopo: Scopo
    let peso: String
    let on: Bool
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: simbolo)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(on ? Volta.primT : Volta.a2)
                .frame(width: 46, height: 46)
                .background(Circle().fill(on ? Volta.prim : Volta.card2))
                .symbolEffect(.bounce, value: on)
            // una parola; il dettaglio solo sulla tessera sotto il mouse
            Text(on && !peso.isEmpty ? peso : titolo)
                .font(.system(size: 12, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Volta.t1 : Volta.t2).lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Volta.a4 : Volta.card))
        .scaleEffect(on ? 1.03 : 1)
    }
    private var titolo: String {
        switch scopo { case .web: return "Web"; case .mandare: return T("Invia", "Send"); case .stampare: return T("Stampa", "Print") }
    }
    private var simbolo: String {
        switch scopo { case .web: return "globe"; case .mandare: return "paperplane.fill"; case .stampare: return "printer.fill" }
    }
}

/// Un formato come un piccolo documento con l'angolo piegato e la sigla sopra (JPG, PNG...), o un simbolo.
private struct Documentino: View {
    let sigla: String?
    let simbolo: String?
    let on: Bool
    let aiuto: String
    var tenue = false
    var body: some View {
        ZStack {
            FoglioPiegato().fill(on ? Volta.prim : tenue ? Volta.card : Volta.pill)
                .frame(width: 30, height: 36)
            if let sigla {
                Text(sigla.count > 4 ? String(sigla.prefix(4)) : sigla)
                    .font(.system(size: sigla.count > 3 ? 7.5 : 8.5, weight: .bold))
                    .foregroundStyle(on ? Volta.primT : tenue ? Volta.t2 : Volta.pillT)
                    .offset(y: 3)
            } else if let simbolo {
                Image(systemName: simbolo).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(on ? Volta.primT : Volta.a2).offset(y: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: on ? -3 : 0)
        .help(aiuto)
    }
}

/// Il foglio con l'angolo in alto a destra piegato.
private struct FoglioPiegato: Shape {
    func path(in r: CGRect) -> Path {
        let k: CGFloat = r.width * 0.32, rr: CGFloat = 5
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rr, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - k, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + k))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rr))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rr, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rr, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rr), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rr))
        p.addQuadCurve(to: CGPoint(x: r.minX + rr, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Resoconto nel notch chiuso (comparsa)

struct MutaPeekRiga: View {
    let item: PeekItem
    @State private var salto = 0
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Volta.a2)
                .symbolEffect(.bounce, value: salto)
                .symbolEffect(.rotate, isActive: item.symbol == "arrow.triangle.2.circlepath")
            Text(item.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                .help(item.detail)
            Spacer(minLength: 4)
            if item.symbol != "arrow.triangle.2.circlepath" {      // durante la conversione niente bottoni
                Icona(simbolo: "arrow.uturn.backward", aiuto: T("Annulla", "Undo")) { MutaCentro.shared.annulla() }
                Icona(simbolo: "eye", aiuto: T("Mostra nel Finder", "Show in Finder"), primaria: true) { MutaCentro.shared.mostra() }
            }
        }
        .padding(.horizontal, 12)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { salto += 1 } }
    }

    /// Titolo corto e due icone: la larghezza la decide il titolo (il dettaglio compare al passaggio).
    static func larghezza(_ item: PeekItem, notch: CGFloat) -> CGFloat {
        max(notch + 20, CGFloat(item.title.count) * 6.6 + 110)
    }
}

private struct Icona: View {
    let simbolo: String
    let aiuto: String
    var primaria = false
    let azione: () -> Void
    @State private var sopra = false
    var body: some View {
        Button(action: azione) {
            Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(primaria ? Volta.primT : Volta.a2)
                .frame(width: 22, height: 20)
                .background(Capsule().fill(primaria ? Volta.prim : Volta.a2.opacity(sopra ? 0.22 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help(aiuto)
    }
}

// MARK: - Sezione del pannello laterale

struct MutaSection: View {
    @ObservedObject var muta = MutaCentro.shared
    private let colonne = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 15)).foregroundStyle(Volta.a2)
                    .frame(width: 34, height: 34).background(Circle().fill(Volta.a2.opacity(0.16)))
                    .symbolEffect(.bounce, value: muta.ultimaVolta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stow").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                    Text(muta.riordino ? T("Mette a posto da sola", "Tidies up on its own") : T("Riordino spento", "Tidy is off"))
                        .font(.system(size: 12)).foregroundStyle(Night.t2).lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $muta.riordino).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Volta.a2)
            }
            .padding(.bottom, 14)

            if RegistroModuli.shared.bloccato("muta") {
                Text(T("Stow è in Pulsar Complete.", "Stow comes with Pulsar Complete."))
                    .font(.system(size: 12.5)).foregroundStyle(Night.t2).padding(.vertical, 8)
            } else if !muta.attivo {
                Text(T("Stow è spento nel menu di Pulsar.", "Stow is off in the Pulsar menu."))
                    .font(.system(size: 12.5)).foregroundStyle(Night.t2).padding(.vertical, 8)
            } else {
                contenuto
            }
        }
    }

    @ViewBuilder private var contenuto: some View {
        // dove guarda e quanto aspetta: icone accese o spente
        HStack(spacing: 6) {
            Scelta(simbolo: "menubar.dock.rectangle", aiuto: T("Scrivania", "Desktop"), on: $muta.scrivania)
            Scelta(simbolo: "arrow.down.circle", aiuto: "Download", on: $muta.download)
            Scelta(simbolo: "wand.and.stars", aiuto: T("I file convertiti seguono le regole", "Converted files follow the rules"), on: $muta.dopoConversione)
            Spacer()
            HStack(spacing: 2) {
                Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(Night.t3).padding(.trailing, 3)
                ForEach([1, 2, 5], id: \.self) { m in
                    Button { muta.attesaMinuti = m } label: {
                        Text("\(m)'").font(.system(size: 11.5, weight: muta.attesaMinuti == m ? .medium : .regular))
                            .foregroundStyle(muta.attesaMinuti == m ? Volta.a1 : Night.t3)
                            .frame(width: 26, height: 24)
                            .background(Capsule().fill(muta.attesaMinuti == m ? Volta.a2.opacity(0.22) : .clear))
                    }
                    .buttonStyle(.plain)
                    .help(T("Aspetta \(m) minuti prima di spostare", "Waits \(m) minutes before moving"))
                }
            }
        }
        .padding(.bottom, 14)

        // le regole come cartelle
        LazyVGrid(columns: colonne, spacing: 8) {
            ForEach(Array(muta.regole.enumerated()), id: \.offset) { _, r in
                Cartellina(regola: r, meta: meta(r)) { if case .cartella = r.destinazione { muta.scegliCartella(per: r.nome) } }
            }
        }

        if let r = muta.ultimoResoconto, !muta.ultime.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: -10) {
                    ForEach(Array(file(muta.ultime).prefix(5).enumerated()), id: \.offset) { _, u in Miniatura(url: u, lato: 30) }
                }
                Text(r).font(.system(size: 12)).foregroundStyle(Night.t2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Icona(simbolo: "arrow.uturn.backward", aiuto: T("Annulla", "Undo")) { muta.annulla() }
                    Icona(simbolo: "eye", aiuto: T("Mostra nel Finder", "Show in Finder"), primaria: true) { muta.mostra() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Night.card))
            .padding(.top, 14)
        }

        Button { muta.giro(anchePrima: true) } label: {
            Label(T("Metti a posto anche i file di prima", "Also tidy older files"), systemImage: "sparkles")
                .font(.system(size: 12)).foregroundStyle(Night.t2)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .help(T("Una volta sola, poi si annulla dal resoconto", "Once, and you can undo it from the report"))
    }

    private func meta(_ r: Regola) -> String {
        if case .cartella(let c) = r.destinazione { return c.lastPathComponent }
        let g = Int((r.attesa ?? 0) / 86400)
        return T("Cestino, \(g) g", "Trash, \(g) d")
    }

    private func file(_ a: [AzioneMuta]) -> [URL] {
        a.compactMap { switch $0 { case .spostato(_, let to, _): return to; case .creato(let u): return u; case .nelCestino: return nil } }
    }
}

/// Una regola come cartella: icona di cartella azzurra con il simbolo del tipo sopra, il nome, dove va.
private struct Cartellina: View {
    let regola: Regola
    let meta: String
    let azione: () -> Void
    @State private var sopra = false
    var body: some View {
        Button(action: azione) {
            VStack(spacing: 5) {
                ZStack {
                    Image(systemName: cestino ? "trash.fill" : "folder.fill").font(.system(size: 30))
                        .foregroundStyle(cestino ? AnyShapeStyle(Night.t3) : AnyShapeStyle(LinearGradient(colors: [Volta.a2, Volta.a3], startPoint: .top, endPoint: .bottom)))
                    if !cestino {
                        Image(systemName: simbolo).font(.system(size: 11, weight: .semibold)).foregroundStyle(Volta.primT).offset(y: 3)
                    }
                }
                .frame(height: 34)
                .offset(y: sopra ? -2 : 0)
                Text(regola.nome).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.primary.opacity(0.88)).lineLimit(1)
                Text(meta).font(.system(size: 10)).foregroundStyle(Night.t3).lineLimit(1).truncationMode(.middle)
            }
            .padding(.vertical, 10).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(sopra ? Volta.a2.opacity(0.12) : Night.card))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { sopra = h } }
        .help(cestino ? T("Gli screenshot vanno nel Cestino", "Screenshots go to the Trash") : T("Cambia cartella", "Change folder"))
    }
    private var cestino: Bool { regola.destinazione == .cestino }
    /// Il simbolo dalla regola: le estensioni dicono il tipo.
    private var simbolo: String {
        let e = regola.estensioni
        if !e.isDisjoint(with: ["otf", "ttf", "woff"]) { return "textformat" }
        if e.contains("psd") { return "macbook" }
        if !e.isDisjoint(with: ["epub", "mobi"]) { return "book.fill" }
        if !e.isDisjoint(with: ["mp4", "mov", "m4v"]) { return "film.fill" }
        if !e.isDisjoint(with: ["mp3", "m4a", "wav"]) { return "music.note" }
        if !e.isDisjoint(with: ["svg", "ai", "eps"]) || regola.parole.contains("logo") { return "seal.fill" }
        if regola.parole.contains("texture") { return "square.grid.3x3.fill" }
        if regola.parole.contains("midjourney") { return "sparkles" }
        if !e.isDisjoint(with: ["pdf", "docx", "pages"]) { return "doc.text.fill" }
        if !e.isDisjoint(with: ["jpg", "png", "heic"]) { return "photo.fill" }
        return "doc.fill"
    }
}

/// Interruttore a icona: acceso = azzurro, spento = tenue. Niente contorni; il nome al passaggio.
private struct Scelta: View {
    let simbolo: String
    let aiuto: String
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            Image(systemName: simbolo).font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Volta.a1 : Night.t3)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(on ? Volta.a2.opacity(0.22) : Color.primary.opacity(0.05)))
                .contentShape(Capsule())
                .symbolEffect(.bounce, value: on)
        }
        .buttonStyle(.plain)
        .help(aiuto + (on ? T(": acceso", ": on") : T(": spento", ": off")))
    }
}
