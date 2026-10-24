// Miniatura: un piccolo schermo dal vivo di una finestra, dentro l'isola.
// Spec: docs/2026-10-11-isola-design.md, sezione 3. Serve il permesso Registrazione schermo e parte solo se
// "Miniatura finestre" è acceso (menu ISOLA, o il tasto nella tessera): spento di serie, nessun permesso chiesto.
// Una sola finestra per volta, a bassa frequenza, e si ferma quando la tessera non si vede.
import SwiftUI
import AppKit
import ScreenCaptureKit
import CoreImage

enum Thumbs {
    static var enabled: Bool {
        get { Impostazioni.bool(.isolaThumb) }
        set { Impostazioni.set(newValue, .isolaThumb) }
    }

    /// Le finestre vere dell'utente: livello normale, di una certa grandezza, col titolo, non di Pulsar.
    static func candidates(_ all: [SCWindow]) -> [SCWindow] {
        all.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width > 150 && $0.frame.height > 100 && !($0.title ?? "").isEmpty
                && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }
}

final class WindowThumbnail: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var image: CGImage?
    @Published private(set) var denied = false
    @Published private(set) var windowID: UInt32?
    @Published private(set) var appName = ""

    private var stream: SCStream?
    private var generation = 0
    private let ctx = CIContext()
    private let queue = DispatchQueue(label: "pulsar.miniatura", qos: .utility)

    /// Cattura la finestra che `pick` sceglie fra quelle candidate. `nil`: nessuna cattura.
    func start(pick: @escaping ([SCWindow]) -> SCWindow?) {
        stop()
        guard Thumbs.enabled else { return }
        generation += 1
        let mine = generation
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let self, self.generation == mine, let win = pick(Thumbs.candidates(content.windows)) else { return }
                let cfg = SCStreamConfiguration()
                cfg.width = 480
                cfg.height = max(60, Int(480 * win.frame.height / win.frame.width))
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 8)
                cfg.showsCursor = false
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.queueDepth = 3
                let s = SCStream(filter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                try await s.startCapture()
                await MainActor.run {
                    if self.generation == mine { self.stream = s; self.denied = false; self.windowID = win.windowID; self.appName = win.owningApplication?.applicationName ?? "" }
                    else { Task { try? await s.stopCapture() } }
                }
            } catch {
                await MainActor.run { self?.denied = true }
            }
        }
    }

    func stop() {
        generation += 1
        if let s = stream { Task { try? await s.stopCapture() } }
        stream = nil
        image = nil
    }

    /// Passa alla finestra successiva dell'elenco.
    func cycle() {
        let current = windowID
        start { wins in
            let ids = wins.map { $0.windowID }
            guard let n = WindowPick.next(after: current, in: ids) else { return nil }
            return wins.first { $0.windowID == n }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        DispatchQueue.main.async { [weak self] in self?.image = cg }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.stream = nil }
    }
}

// MARK: - Tessera Finestra (il mini schermo)

struct WindowWidget: IslandWidget {
    let thumbnail = WindowThumbnail()
    let id = "window"
    var title: String { T("Finestra", "Window") }
    let symbol = "macwindow"
    func body(cells: Int) -> AnyView { AnyView(WindowTile(thumb: thumbnail, cells: cells)) }
}

private struct WindowTile: View {
    @ObservedObject var thumb: WindowThumbnail
    let cells: Int
    @AppStorage(Chiave.isolaThumb.rawValue) private var on = false

    var body: some View {
        Group {
            if !on {
                VStack(spacing: 6) {
                    Image(systemName: "macwindow").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.45))
                    Button { Thumbs.enabled = true; begin() } label: {
                        Text(T("Attiva miniatura", "Turn on")).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 22)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if thumb.denied {
                Text(T("Consenti Registrazione schermo a Pulsar", "Allow Screen Recording for Pulsar")).font(.system(size: 10)).foregroundStyle(Night.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let img = thumb.image {
                Image(decorative: img, scale: 1).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        Button { thumb.cycle() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                    }
                    .onTapGesture { raise() }
            } else {
                Text("…").foregroundStyle(Color.primary.opacity(0.4)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if on { begin() } }
        .onDisappear { thumb.stop() }
    }

    private var savedKey: String { Impostazioni.string(.isolaWinKey) ?? "" }

    private func begin() {
        let key = savedKey
        thumb.start { wins in
            let hit = wins.first { "\($0.owningApplication?.bundleIdentifier ?? "")|\($0.title ?? "")" == key }
            return hit ?? wins.first
        }
    }

    /// Un clic sulla miniatura porta in primo piano l'app di quella finestra.
    private func raise() {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == thumb.appName }?.activate()
    }
}
