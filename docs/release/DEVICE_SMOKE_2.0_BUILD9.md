# Device smoke — CoreAI Zoo 2.0 (build 9) on iPhone 17 Pro — 2026-09-18

Gate for pressing "Release This Version" on App Store Connect (RC_DAY_RUNBOOK.md §5).
Same binary as the approved App Store build: build 9, uploaded 2026-09-14 (Delivery UUID
`<delivery uuid>`), served by the TestFlight public link
https://testflight.apple.com/join/bK4P7xby (Public Preview group; `externalBuildState` IN_BETA_TESTING).

## Environment (measured 2026-09-18 morning)

| item | value |
|---|---|
| device | iPhone 17 Pro, `<udid>`, iPhone18,1, arm64e |
| iOS | 27.0 (build 24A437), Developer Mode enabled, wired, CoreDevice tunnel connected |
| app record | CoreAI Zoo, bundle `com.daisukemajima.CoreAIChat`, app id 6780135339 |
| build | 9 (2.0), Xcode 27 RC 27A266a, minOsVersion 27.0, processingState VALID |
| before install | no `com.daisukemajima.CoreAIChat` / `.coreaizoo` on the phone (only the UITest runner) |
| catalog | https://raw.githubusercontent.com/john-rocky/coreai-kit/main/catalog.json, 61 models, 13 iOS chat variants (minicpm5-2b new since 09-01) |
| ASC state | version 2.0 PENDING_DEVELOPER_RELEASE, releaseType MANUAL, no phased release, 175 territories, Free (base USA) |

## A. RUNBOOK §5 60-second smoke (gate)

| # | item | expect | measured | verdict |
|---|---|---|---|---|
| A0 | install via TestFlight, `devicectl device info apps` | `com.daisukemajima.CoreAIChat` version 2.0 build 9 | installed by the user 09-18 morning; devicectl: version 2.0 build 9, running (pid 691), `device info crashes` empty | PASS |
| A1 | Chat: qwen3-0.6b download → load → one response | non-empty answer, StatsBar shows tok/s | user: response produced and screen-recorded (video on the phone, not transferred); user remark 「token 上限少なくない？」 = answer length capped (see Verdict); StatsBar numbers not reported | PASS (functional) |
| A2 | Vision / Ask: photo + question | streamed answer (dead screen = FM seed mismatch) | | |
| A3 | Audio tab opens | picker visible, no crash | | |

## B. P2-C per-model loop (prompt: `Reply with one short sentence: what can you do?`)

| id | iOS MB | load (s) | 1 response | tok/s (StatsBar) | verdict / crash ref |
|---|---|---|---|---|---|
| qwen3-0.6b | 456 | n/r | yes (user) | n/r (store shot 09-15: 41.1 tok/s, tokens 20→1052 for a haiku) | PASS; answer length capped — 2.0.1 item |
| minicpm5-1b | 1159 | | | | |
| qwen3.5-0.8b | 1276 | | | | |
| lfm2.5-1.2b | 1623 | | | | |
| granite-4.0-h-1b | 1786 | | | | |
| youtu-llm-2b | 2058 | | | | |
| qwen3-4b | 2498 | | | | |
| minicpm5-2b | 2685 | | | | |
| qwen3.5-2b | 2905 | | | | |
| nanbeige4.1-3b | 4387 | | | | |
| nemotron-3-nano-4b | 4626 | | | | |
| nanbeige4.2-3b | 4702 | | | | |
| gemma-4-e2b | 4931 | | | | |

## C. Capability sweep (iPhone)

| # | tab / mode | gate model | pass = | measured | verdict |
|---|---|---|---|---|---|
| C1 | Vision / Ask | qwen3-vl-2b | photo + question → streamed answer | | |
| C2 | Audio / Speak | voxcpm-0.5b | audible utterance | | |
| C3 | Audio / Transcribe | whisper-large-v3-turbo + nemotron-3.5-asr-streaming-0.6b | both transcribe a clip | | |
| C4 | Camera / Depth | depth-anything-3-small | live depth map | | |
| C5 | Camera / Detect | yolox-s | live boxes | | |
| C6 | Camera / Action | vjepa2 | 16-frame clip classified | | |
| C7 | Camera / Upscale | adcsr-x4 | picked photo upscaled | | |
| C8 | Bench | qwen3.5-0.8b trio | run completes, blob shows build 9 | | |

## Crash / log capture

- crashes: `xcrun devicectl device info crashes --device <udid>`
- processes: `xcrun devicectl device info processes --device <udid> | grep -i coreai`
- unified log: `sudo log collect --device-udid <udid> --last 10m --output <dir>/phone.logarchive`

## Verdict

- A0/A1 PASS, no crash. A2/A3 and the C sweep were not run: the user pressed **Release This Version** on
  2026-09-18 morning after A1 (ASC `appStoreState` READY_FOR_SALE / `appVersionState`
  READY_FOR_DISTRIBUTION at the next API read; store page live ~30 min later at https://apps.apple.com/us/app/coreai-zoo/id6780135339). Remaining rows stay open for 2.0.1.
- Token cap (user 09-18 「token 上限少なくない？」): the Chat tab creates `ChatSession.Configuration()`
  unchanged, so the response budget is the kit default `maxResponseTokens = 2048`, and the engine
  clamps it to `min(2048, bundle max_context_length − prompt)` (coreai-models
  `CoreAISequentialEngine.swift:532`; qwen3-0.6b iOS bundle `max_context_length` = 4096). Qwen3 thinks
  by default (the kit never passes `enable_thinking=false` for chat; a haiku took 1052 tokens in the
  09-15 store screenshot), so the 2048 budget is spent mostly on `<think>` and the visible answer is
  cut. 2.0.1: raise/remove the app-side cap (pass the bundle's context budget) and add a
  thinking on/off toggle; note the kit's own 1024-per-turn guard for nanbeige4.2-3b on iOS
  (`ModelRuntime.swift` comment) before going above 2048 on that model.

## 2.0.1 change (applied 2026-09-18; kit e25f7ad, app 416daa6, both local commits)

User decision: raise the cap to the bundle context AND add a thinking on/off switch.

- coreai-kit (`../coreai-kit`, local path dependency): `ModelRuntime.maxContextLength` (from the
  bundle's `max_context_length`); `ChatSession.Configuration.enableThinking: Bool?` +
  `setThinking(_:)` (renders `enable_thinking` through the chat template and appends the closed
  `<think>\n\n</think>` tail when off, reusing `KitTextNormalizer.closedThink`);
  `ChatSession.maxContextLength`; per-turn response budget =
  `min(maxResponseTokens, maxContextLength - promptTokens)` for both decode loops (the pipelined
  engine takes `maxTokens` at face value, so the clamp lives in the session).
- app: Chat sets `maxResponseTokens = Int.max` (= context-limited), `thinkingEnabled` state, a
  "Think" button-style toggle shown only for catalog entries with `thinking: true`, applied per
  send via `setThinking`; `MARKETING_VERSION` 2.0.1.
- Not changed: the kit's iOS note that nanbeige4.2-3b corrupts beyond KV 2048 (`ModelRuntime.swift`)
  — the old 2048 default already allowed prompt+2048 there; a per-model cap is a follow-up.
- Re-shoot candidates for the launch video (no thinking flag in the catalog, so the 2048 budget is
  not spent in `<think>` on build 9): lfm2.5-1.2b (1623 MB, recommended), granite-4.0-h-1b
  (1786 MB), gemma-4-e2b (4931 MB). None of the three was loaded on this phone today.

## "Generating" never ends on LFM2.5 (user 09-18) — cause and fix

Cause (coreai-models `VanillaDecodingStrategy`, upstream code): after a stop sequence matches it
*drained* the engine to `maxTokens` before returning, and the engines have no EOS notion, so every
turn paid for the whole remaining response budget after the answer. Mac M4 Max, same LFM2.5 1.2B
bundle as iOS (`gpu-pipelined/...`), prompt "Reply with one short sentence: what can you do?":

| build | cap | generated | text → complete |
|---|---|---|---|
| 0.2.4-zoo | 64 | 17 | 0.4 s |
| 0.2.4-zoo | 2048 | 14 | 8.3 s |
| fix | 2048 | 20 | 0.2 s |
| fix | 100000 (context-clamped) | 14 | 0.2 s |
| fix, qwen3-0.6b thinking off | 100000 | 20 | 0.1 s, no `<think>` |

On the phone (~40–60 tok/s) the same drain is 30–50 s of "Generating…" after a short answer,
which the user cancelled by hand. With the 2.0.1 cap raised to the context it would have grown.
Fix: a worktree of the coreai-models fork, branch `fix/stop-sequence-no-drain`,
commit dad1f64 on top of 0.2.4-zoo, tag `0.2.5-zoo`, pushed 2026-09-18 (branch + tag, `zoo-0.4`
fast-forwarded). Kit pinned to `exact: "0.2.5-zoo"` (kit e25f7ad); app 416daa6 = 2.0.1 Chat
changes. Kit and app commits are local (not pushed). Dev build 2.0.1 (`com.daisukemajima.coreaizoo`)
installed on the iPhone 17 Pro next to TestFlight build 9 for the user's check. Repro CLI: scratchpad `repro/` (kit
`ChatSession(catalog:)`, prints load/complete timings).
