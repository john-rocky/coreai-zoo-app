// UpscaleView — pick a photo, run AdcSR ×4 super-resolution on-device, compare input vs
// result. Adapted from the kit's UpscaleDemo Example to cross-platform CGImage (the Example's
// UIImage path is iOS-only; the zoo shell is multiplatform), driving CoreAIKit's SuperResolver.

import CoreAIKitVision
import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class UpscaleModel {
    var status = "Pick a photo to upscale ×4"
    var downloadFraction: Double?
    var busy = false
    var original: CGImage?
    var upscaled: CGImage?

    private var resolver: SuperResolver?

    private func ensureLoaded() async throws {
        if resolver != nil { return }
        status = "Downloading AdcSR (~1.7 GB)…"
        // Same gesture as the model card: the catalog id resolves the bundle.
        let r = try await SuperResolver(catalog: "adcsr-x4") { [weak self] p in
            Task { @MainActor in self?.downloadFraction = p.fraction }
        }
        downloadFraction = nil
        resolver = r
    }

    func setImage(from item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return }
            original = cgImage
            upscaled = nil
            status = "\(cgImage.width)×\(cgImage.height) — ready to upscale ×4"
        }
    }

    func upscale() {
        guard let original, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await ensureLoaded()
                status = "Upscaling ×4 on-device…"
                let started = ContinuousClock.now
                let out = try await resolver!.upscale(original)
                let secs = Double(started.duration(to: .now).components.seconds)
                upscaled = out
                status = String(format: "Done — %d×%d in %.0fs", out.width, out.height, secs)
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
        }
    }
}

struct UpscaleView: View {
    @State private var model = UpscaleModel()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                if let f = model.downloadFraction {
                    ProgressView(value: f) {
                        Text("Downloading model… \(Int(f * 100))%")
                    }
                }
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let original = model.original {
                    imageSection("Input — \(original.width)×\(original.height)", original)
                    Button {
                        model.upscale()
                    } label: {
                        if model.busy {
                            ProgressView()
                        } else {
                            Label("Upscale ×4", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                }

                if let upscaled = model.upscaled {
                    imageSection("AdcSR ×4 — \(upscaled.width)×\(upscaled.height)", upscaled)
                }
            }
            .padding()
        }
        .onChange(of: pickerItem) { _, item in
            if let item { model.setImage(from: item) }
        }
    }

    @ViewBuilder private func imageSection(_ title: String, _ image: CGImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
