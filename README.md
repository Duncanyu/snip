# Snip

Snip is a native macOS rolling screen recorder. It keeps recent video in a compressed memory buffer so a shortcut can save the last few seconds without starting a new recording. It supports system audio, app specific video and audio rules, color adjustments, custom resolution, and a configurable memory cap.

## Download and install

Download **Snip-v0.1.0-preview-macos-arm64.zip** from the [0.1.0 preview release](https://github.com/Duncanyu/clipper/releases/tag/v0.1.0-preview). This preview requires an Apple Silicon Mac running macOS 15 or later.

1. Unzip the download and drag **Snip.app** into **Applications**.
2. Open Snip from Applications. This preview is ad hoc signed and is **not notarized**. If macOS blocks the first launch, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions](https://support.apple.com/en-us/102445). Only bypass this warning for a copy you downloaded from this repository.
3. Allow **Screen & System Audio Recording** when macOS asks. If you change this permission in System Settings, quit and reopen Snip.
4. Snip appears in the menu bar while capture is active. Choose **Settings** there to select a display, clip length, quality, shortcuts, and save folder. If the menu bar icon is hidden, open Snip from the Dock to show Settings.

The release includes a SHA-256 checksum file so you can verify the ZIP with `shasum -a 256 Snip-v0.1.0-preview-macos-arm64.zip`.

## Use

- Press **⌘⇧9** to save the recent clip to `~/Movies/Clips` by default. Press **⌘⌥P** to pause or resume capture. Both shortcuts can be changed in **Settings → Clips**.
- Choose 30, 60, or 120 FPS. Snip caps capture at the selected display's refresh rate; a 120 FPS choice on a 60 Hz display captures up to 60 FPS.
- **Retina** uses the captured display's full pixel resolution. Half, normal, and custom output sizes are also available. A custom size above the source size is upscaled.
- Choose a quality preset or set bitrate from Auto (0) to 200 Mbps. Higher bitrates consume more of the rolling buffer, so the available history may be shorter than the requested clip length.
- In **Sources**, record all apps, only selected apps, or all except selected apps. Video and system audio have separate rules. You can also exclude Snip's save sound from clips.
- In **Color**, adjust brightness, contrast, and saturation of the recorded video. Neutral values preserve the original capture colors.

## Measured performance and quality

On an **Apple M4 Mac with 16 GiB RAM and macOS 27.0.1**, a 30-second stationary desktop sample at **2940 × 1912 Retina output**, system audio, 16 Mbps target, and a requested 120 FPS on a 60 Hz display measured:

| Build | Median CPU¹ | 95th percentile CPU¹ | Median memory (RSS) |
| --- | ---: | ---: | ---: |
| Before display refresh cap | 21.0% | 27.62% | 151.41 MiB |
| With display refresh cap | 5.1% | 5.71% | 134.36 MiB |

¹ `ps` CPU percentage: 100% is one logical CPU, not the whole Mac. These are two short observations, not a controlled game performance test. The improvement may include ordinary workload variation; it should not be treated as a guaranteed speedup. A saved clip was confirmed as **2940 × 1912 HEVC Main with AAC 48 kHz audio**, matching the display's physical pixel dimensions. That short clip alone does not measure visual fidelity or sustained frame delivery.

See the [measurement report](benchmarks/2026-10-13-m4.md), [raw samples](benchmarks/raw/), and [reproducible measurement script](scripts/benchmark.py) for the method, exact settings, and limits.

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
