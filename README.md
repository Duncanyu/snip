# Snip

**Save the last moments of your screen with one shortcut.** Snip is a native macOS recorder that keeps recent video in a compressed rolling buffer, then writes a `.mov` clip when you ask for it.

```text
Screen → hardware HEVC → compressed rolling buffer ─┐
App sound ────────────────────────────────────────────┼→ shortcut → .mov clip
Microphone (optional) ────────────────────────────────┘
```

**[Download the Apple Silicon preview](https://github.com/Duncanyu/clipper/releases/tag/v0.1.2-preview)** · [Install](#download-and-install) · [Features](#use) · [Measured performance](#measured-performance-and-quality)

## Download and install

Download **Snip-v0.1.2-preview-macos-arm64.zip** from the [0.1.2 preview release](https://github.com/Duncanyu/clipper/releases/tag/v0.1.2-preview). It requires an Apple Silicon Mac running macOS 15 or later.

1. Unzip the download and drag **Snip.app** into **Applications**.
2. Open Snip from Applications. This preview is ad hoc signed and is **not notarized**. If macOS blocks the first launch, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions](https://support.apple.com/en-us/102445). Only bypass this warning for a copy you downloaded from this repository.
3. Allow **Screen & System Audio Recording** when macOS asks. If you change this permission in System Settings, quit and reopen Snip.
4. Snip appears in the menu bar while capture is active. Choose **Settings** there to select a display, clip length, quality, shortcuts, and save folder. If the menu bar icon is hidden, open Snip from the Dock to show Settings.

The release includes a SHA-256 checksum file. Place it beside the ZIP and run `shasum -a 256 -c Snip-v0.1.2-preview-macos-arm64.zip.sha256` to verify the download.

## Use

- Press **⌘⇧9** to save the recent clip to `~/Movies/Clips` by default. Press **⌘⌥P** to pause or resume capture. Both shortcuts can be changed in **Settings → Clips**.
- Choose 30, 60, or 120 FPS. Snip caps capture at the selected display's refresh rate; a 120 FPS choice on a 60 Hz display captures up to 60 FPS.
- **Retina** uses the captured display's full pixel resolution. Half, normal, and custom output sizes are also available. A custom size above the source size is upscaled.
- Choose a quality preset or set bitrate from Auto (0) to 200 Mbps. Higher bitrates consume more of the rolling buffer, so the available history may be shorter than the requested clip length.
- In **Sources**, turn app sound and microphone recording on or off independently. The microphone is off by default and asks for macOS Microphone permission when enabled. App rules govern video and app sound; they do not filter the microphone. You can also exclude Snip's save sound from clips.
- In **Color**, adjust brightness, contrast, and saturation of the recorded video. Neutral values preserve the original capture colors.

## Measured performance and quality

Each `█` shows about 1 percentage point of median CPU on one logical CPU; exact values follow.

| Observation | CPU graph |
| --- | --- |
| Stationary, before refresh cap | `█████████████████████` 21.0% |
| Stationary, with refresh cap | `█████` 5.1% |
| Stationary, after audio trim change | `████` 4.15% |
| Moving tiles, before audio trim change | `█████` 5.3% |
| Moving tiles, after audio trim change | `████` 4.1% |
| Paused | `·` 0.0% |

On an **Apple M4 with 16 GiB RAM and macOS 27.0.1**, using **2940 × 1912 Retina output**, a 16 Mbps target, system audio, microphone off, and a 60 Hz display:

| 30-second observation | Median CPU¹ | 95th percentile CPU¹ | Median memory (RSS) |
| --- | ---: | ---: | ---: |
| Paused | 0.0% | 0.5% | 195 MiB² |
| Stationary, before refresh cap | 21.0% | 27.62% | 151 MiB |
| Stationary, with refresh cap | 5.1% | 5.71% | 134 MiB |
| Stationary, after audio trim change | 4.15% | 4.6% | 148 MiB |
| Moving tiles, before audio trim change | 5.3% | 6.0% | 155 MiB |
| Moving tiles, after audio trim change | 4.1% | 4.6% | 149 MiB |

¹ `ps` CPU percentage: 100% is one logical CPU. ² Paused RSS retained memory from earlier capture, so it is not a fresh launch baseline. A saved **30.5-second** clip from the optimized build was **2940 × 1912 HEVC Main**, **15.86 Mbps** actual whole-file bitrate, **57.38 decoded frames per second** on average, and **AAC 48 kHz** audio. Median and 95th percentile frame gaps were both 16.67 ms. Its full pixel dimensions and cadence remained comparable to the clip before the audio optimization.

These are individual observations of a desktop and a synthetic moving window, not a game frame-time benchmark or a measure of perceptual fidelity. See the [measurement report](benchmarks/2026-10-13-m4.md), [raw samples](benchmarks/raw/), [measurement script](scripts/benchmark.py), and [moving test scene](scripts/benchmark-scene.swift) for the method and limits.

## Build from source

Install Xcode's command line tools, then run:

```sh
swift test
./scripts/build-app.sh
open dist/Snip.app
```

The build script creates an arm64 `dist/Snip.app` and ad hoc signs it for local use. It does not produce a notarized distribution. To repeat the process measurements on a running `/Applications/Snip.app`:

```sh
python3 scripts/benchmark.py sample --label my-run --seconds 30 --interval 0.5 --output benchmarks/raw/my-run.json
```

The optional `inspect` command adds clip metadata and frame timestamps to a sample JSON and requires `ffprobe`:

```sh
python3 scripts/benchmark.py inspect --output benchmarks/raw/my-run.json --clip /path/to/clip.mov
```

Snip uses Apple's ScreenCaptureKit, VideoToolbox, and AVFoundation. Screen recording permission and capture behavior are controlled by macOS.
