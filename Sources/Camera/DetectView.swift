// DetectView — live object detection off the camera feed, on-device. Uses the same thin
// `CameraFeed → detect(in:)` gesture as DepthView/ActionView (not the kit's bespoke
// CVPixelBuffer DetectCamera app): CoreAIKitVision's shared `CameraFeed` + `KitDetector`,
// with a compact SwiftUI overlay for the normalized boxes.

import CoreAIKitVision
import SwiftUI

@MainActor
@Observable
final class DetectModel {
    var cameraImage: CGImage?
    var detections: [Detection] = []
    var status = "Loading model…"
    var inferenceMS: Double?
    /// Detection entries in the catalog; the picker restarts the feed on a new choice.
    var entries: [CatalogEntry] = []
    var selectedEntry: CatalogEntry?

    private var feed: CameraFeed?
    private var started = false

    /// Live catalog with the built-in snapshot as offline fallback.
    func loadCatalog() async {
        guard entries.isEmpty else { return }
        entries = await ModelCatalog.load().available(.detection)
        if selectedEntry == nil { selectedEntry = entries.first }
    }

    func restart() {
        stop()
        started = false
        detections = []
        Task { await start() }
    }

    func start() async {
        guard !started, let entry = selectedEntry else { return }
        started = true
        do {
            // Same gesture as the model card: the catalog id resolves the bundle.
            let detector = try await KitDetector(catalog: entry.id) { progress in
                Task { @MainActor in
                    self.status = "Downloading… \(Int(progress.fraction * 100))%"
                }
            }
            status = "Starting camera…"
            let feed = CameraFeed(framesPerSecond: 5)
            self.feed = feed
            for await frame in try await feed.start() {
                let start = SuspendingClock.now
                let boxes = try await detector.detect(in: frame, scoreThreshold: 0.4)
                let elapsed = (SuspendingClock.now - start).components
                inferenceMS =
                    Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                cameraImage = frame
                detections = boxes
                status = "Live"
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    func stop() {
        feed?.stop()
    }
}

struct DetectView: View {
    @State private var model = DetectModel()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("Model", selection: $model.selectedEntry) {
                    ForEach(model.entries) { entry in
                        Text(entry.name).tag(Optional(entry))
                    }
                }
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12)
            canvas
            HStack {
                Text(model.status)
                if let ms = model.inferenceMS {
                    Text(String(format: "· %.0f ms/frame · %d found", ms, model.detections.count))
                }
                Spacer()
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .task {
            await model.loadCatalog()
            await model.start()
        }
        .onChange(of: model.selectedEntry) { old, _ in
            if old != nil { model.restart() }
        }
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var canvas: some View {
        if let image = model.cameraImage {
            // Lay the image out at its own aspect ratio so it fills the rect edge-to-edge
            // (no letterbox): the overlay's geometry then equals the drawn image, and the
            // normalized top-left boxes map by a plain multiply.
            let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(aspect, contentMode: .fit)
                .overlay { boxes }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
        }
    }

    private static let palette: [Color] = [
        .red, .green, .blue, .orange, .purple, .cyan, .yellow, .mint, .pink,
    ]

    private var boxes: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(model.detections) { det in
                    let color = Self.palette[det.classID % Self.palette.count]
                    let w = det.box.width * geo.size.width
                    let h = det.box.height * geo.size.height
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 3)
                        Text("\(det.label) \(String(format: "%.2f", det.score))")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(color, in: RoundedRectangle(cornerRadius: 3))
                            .offset(y: -16)
                    }
                    .frame(width: w, height: h)
                    .offset(
                        x: det.box.origin.x * geo.size.width,
                        y: det.box.origin.y * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}
