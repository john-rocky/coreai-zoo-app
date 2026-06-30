# CoreAI Zoo (app)

One on-device app for the whole Core AI model zoo — the **shippable** product distributed via
**TestFlight (iOS)** and a **notarized .dmg (macOS)**. It is a thin SwiftUI shell over the shared
[`coreai-kit`](https://github.com/john-rocky/coreai-kit) engine: each capability (chat, transcribe,
…) routes to one CoreAIKit executor, and new models reach users through CoreAIKit's **live catalog**
(`catalog.json`) without an app update.

> Private product repo. The public model zoo (cards, conversion, knowledge, single-purpose sample
> apps) stays in [`coreai-models-community`](https://github.com/john-rocky/coreai-model-zoo).
> The engine/SDK lives in `coreai-kit`. This app only *composes* them.

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

| Tab | Capability | Models |
|---|---|---|
| **Chat** | streaming chat + VLM | catalog `chat` entries (Gemma 4, Qwen3.5, …) |
| **Transcribe** | speech → text | Whisper large-v3-turbo (`KitWhisperModel`) |
| **More** | roadmap | TTS · Depth · Detection · Super-Res · OCR (Phase 2) |

This is **Phase 1** (chat + transcribe). See the roadmap tab / the plan below.

## Build

Requires **Xcode 27 beta** and [xcodegen](https://github.com/yonaskolb/XcodeGen). Clone
`coreai-kit` as a **sibling** of this repo (the project references it at `../coreai-kit`):

```sh
git clone https://github.com/john-rocky/coreai-kit          # ../coreai-kit
git clone <this repo>                                        # ../coreai-zoo-app
cd coreai-zoo-app
xcodegen generate
open CoreAIZoo.xcodeproj      # set your team if needed, then Run (Release) on iPhone or Mac
```

Models download from the Hugging Face Hub on first use — no Python, nothing leaves the device.

## Roadmap

- **Phase 1** — shell + Chat + Transcribe (Whisper). ← now
- **Phase 2** — TTS (VoxCPM/Kokoro), Depth, Detection, Super-Resolution, OCR/segmentation/search.
- **Phase 3** — macOS dmg packaging (notarized) with Mac-only large models unlocked.

Heavy Python-backed generators (image/video/3D: FLUX.2, LTX-Video, TripoSplat) stay as separate
Mac apps — they don't fold cleanly into the Swift shell.

## License

BSD-3-Clause (matches coreai-kit). Model weights follow their own licenses (see each HF repo).
