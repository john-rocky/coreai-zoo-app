# CoreAI Zoo (app)

One on-device app for the whole Core AI model zoo, on the App Store and as a notarized Mac build.
It is a thin SwiftUI shell over the shared [`coreai-kit`](https://github.com/john-rocky/coreai-kit)
engine: each capability (chat, vision, camera, audio, bench) routes to one CoreAIKit executor, and
new models reach users through CoreAIKit's live catalog (`catalog.json`) without an app update.

- iPhone / iPad: [App Store](https://apps.apple.com/app/id6780135339) ·
  [TestFlight](https://testflight.apple.com/join/bK4P7xby)
- Mac: [notarized .dmg](https://github.com/john-rocky/coreai-model-zoo/releases/tag/mac-2.0.9)
- Models: [huggingface.co/mlboydaisuke](https://huggingface.co/mlboydaisuke) (the catalog's 61
  entries are all public weights; each keeps its own license)

The public model zoo (cards, conversion, knowledge, single-purpose sample apps) lives in
[`coreai-model-zoo`](https://github.com/john-rocky/coreai-model-zoo); the engine/SDK in
`coreai-kit`. This app only composes them.

## Why this app exists

The zoo's models were only reachable by building a per-task sample app in Xcode. Non-developers
asking *"how do I install Whisper?"* had no path. This app is that path: install once, pick any
model, download in-app, run on device.

## Architecture

```
coreai-models-community  (public zoo)   →  model cards · conversion · knowledge · sample apps
coreai-kit               (SDK/library)  →  engines + catalog.json  ← single source of truth
coreai-zoo-app           (this repo)    →  thin multiplatform shell → TestFlight + dmg
```

- **No forked backends.** Every model runs through CoreAIKit (`ChatSession`, `KitWhisperModel`,
  `KitASRModel`, `KitVisionModel`, `DepthEstimator`, `ObjectDetector`, …). Bug fixes and new models
  land in `coreai-kit` and both the sample apps and this app pick them up.
- **Catalog-driven.** Chat models come from `ModelCatalog.load()`; the patched Core AI runtime is a
  package dependency of coreai-kit, so there is no patch-stack ceremony here.
- **One model resident at a time** → memory stays within the per-process limit; weights download on
  demand and are never bundled into the `.app`.

## Status

| Tab | Capability | Gate models |
|---|---|---|
| Chat | streaming chat, Think switch on reasoning models | catalog `chat` entries (Qwen3, Qwen3.5, LFM2.5, Granite 4, MiniCPM5, Nemotron, Gemma 4, …) |
| Vision | ask about a photo (VLM); Read (OCR) on Mac | Qwen3-VL, MiniCPM-V, LFM2.5-VL |
| Camera | Depth · Detect · Action · Upscale on the live feed | Depth Anything 3, YOLOX / RF-DETR, V-JEPA 2, ADCSR |
| Audio | Speak (TTS) · Transcribe (ASR); Music and Understand on Mac | VoxCPM, Whisper large-v3-turbo, Nemotron ASR |
| Bench | fixed protocol → load / prefill / decode tok/s → shareable blob | any chat model |
| Tools (Mac) | diffusion language models | LLaDA |

iPhone shows the first five tabs; Tools and More are macOS-only.

## Build

Requires **Xcode 27** and [xcodegen](https://github.com/yonaskolb/XcodeGen). Clone
`coreai-kit` as a **sibling** of this repo (the project references it at `../coreai-kit`):

```sh
git clone https://github.com/john-rocky/coreai-kit          # ../coreai-kit
git clone https://github.com/john-rocky/coreai-zoo-app       # ../coreai-zoo-app
cd coreai-zoo-app
xcodegen generate
open CoreAIZoo.xcodeproj      # set your team if needed, then Run (Release) on iPhone or Mac
```

Models download from the Hugging Face Hub on first use — no Python, nothing leaves the device.

## Roadmap

- Read (OCR) on iPhone (the catalog now has iOS OCR variants).
- Surfaces for the catalog kinds that have none yet: diarization, forecasting, moderation,
  separation, text normalization.
- Heavy Python-backed generators (image/video/3D) stay separate Mac apps.

## License

BSD-3-Clause (matches coreai-kit). Model weights follow their own licenses (see each HF repo).
