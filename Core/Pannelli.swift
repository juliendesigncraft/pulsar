// Le finestre e le forme comuni a tutti gli elementi di Pulsar (18/10/2026, riordino fase 1): spostate qui da agente.swift.
import SwiftUI
import AppKit

// MARK: - Finestre

final class FloatPanel: NSPanel {
    // 12/10: l'ombra minima (temi.swift, Ombra) segue comparsa e trasparenza della finestra
    override func orderFrontRegardless() { super.orderFrontRegardless(); Ombra.segui(self) }
    override func orderFront(_ sender: Any?) { super.orderFront(sender); Ombra.segui(self) }
    private let keyable: Bool
    /// keyable: il pannello accetta la tastiera (il campo per scrivere alla chat), solo quando si tocca il campo.
    init(level: NSWindow.Level, keyable: Bool = false) {
        self.keyable = keyable
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = true
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}

/// Click al primo colpo anche se Pulsar non è l'app attiva.
final class FirstClickHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // le cornici le decide layout(): il contenuto non deve allargare la finestra da solo (06/10, pannello oltre il bordo)
    required init(rootView: V) { super.init(rootView: rootView); sizingOptions = [] }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }
}

// MARK: - Pillola nel notch (spalle concave come il notch vero)

struct NotchShape: Shape {
    var shoulder: CGFloat = 10
    var bottom: CGFloat = 18
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = shoulder
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + s, y: r.minY + s), control: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + s + bottom, y: r.maxY), control: CGPoint(x: r.minX + s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - s - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - s, y: r.maxY - bottom), control: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - s, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Glifo a pixel (3x3) che cambia mentre lavora

struct PixelGlyph: View {
    let palette: [Color]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.16)) { ctx in
            let t = Int(ctx.date.timeIntervalSinceReferenceDate / 0.16)
            Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
                ForEach(0..<3, id: \.self) { r in
                    GridRow {
                        ForEach(0..<3, id: \.self) { c in
                            let h = (r * 7 + c * 13 + t * 5 + (r * c + t) % 4) % 11
                            RoundedRectangle(cornerRadius: 0.8)
                                .fill(palette[h % palette.count])
                                .opacity(h < 4 ? 0.18 : 1)
                                .frame(width: 3.6, height: 3.6)
                        }
                    }
                }
            }
        }
        .frame(width: 14, height: 14)
    }
}
