# Snip

Snip is a native macOS app that continuously keeps a short rolling screen recording. Press a shortcut to save the recent video as a `.mov` clip.

**[Download Snip 0.3.1](https://github.com/Duncanyu/snip/releases/tag/v0.3.1)** · [Install](#install) · [Use Snip](#use-snip) · [Build](#build-from-source)

## Install

Download `Snip-v0.3.1-macos-arm64.zip` from the [0.3.1 release](https://github.com/Duncanyu/snip/releases/tag/v0.3.1), unzip it, and move **Snip.app** to **Applications**. Snip requires an Apple Silicon Mac running macOS 15 or later.

The app is ad hoc signed and is not notarized. If macOS blocks it on first run, open **System Settings → Privacy & Security → FileVault → Open Anyway**, confirm, then open Snip again. See [Apple's instructions](https://support.apple.com/en-us/102445). Only bypass this warning for a copy downloaded from this repository.

Snip asks for Screen Recording permission when it starts. Enable microphone recording in **Advanced → Sources** to get a separate microphone permission prompt. If you change recording permissions in System Settings, quit and reopen Snip.

The release includes a SHA-256 checksum. To verify the download, put the checksum file beside the ZIP and run:

```sh
shasum -a 256 -c Snip-v0.3.1-macos-arm64.zip.sha256
```

## Use Snip

- **⌘⇧9** saves the recent clip. **⌘⌥P** pauses or resumes capture. Change these in **Clips** and **General**.
- Choose the clip length and display in **Dashboard**. Capture starts when Snip opens and can be paused with the switch.
- In **Advanced**, choose 30, 60, or 120 FPS, output size, and quality. Capture is capped at the selected display's refresh rate; 120 FPS on a 60 Hz display records up to 60 FPS. Retina uses the display's full pixel resolution. Custom output can upscale the source.
- In **Advanced → Sources**, set video apps, app audio, and microphone independently. Choose the system default microphone or a specific device. App rules filter video and app audio; they do not filter microphone input. The microphone is off by default. You can exclude Snip's save sound from recordings.
- In **Clips**, choose the save folder and filename pattern. Use `{date}` and `{time}`, for example `clip_{time}_{date}`. Snip adds a short ID to keep filenames unique.
- **Advanced → Recorded video color** has optional brightness, contrast, and saturation adjustments for saved clips. Neutral values preserve the original capture colors.
- In **General**, choose whether Snip appears in the Dock or menu bar, manage shortcuts and save sound, and enable or disable automatic updates. Updates are checked daily; Snip asks before installing and verifies the downloaded checksum.
- Settings save and apply as you change them. Changes to active capture settings briefly restart capture.
- The menu bar icon reflects capture and actual capture errors; save-status messages do not change it.

## Performance

On an Apple M4 with 16 GiB RAM, macOS 27.0.1, Retina output (2940 × 1912), a 16 Mbps target, system audio, and a 60 Hz display, measured median CPU use ranged from 0% while paused to 4.1% during a moving window capture. The rolling buffer is compressed with HEVC; saved audio uses AAC at 48 kHz. Buffer cleanup uses a binary search to find old frames, keeping the trim work small as the recording history grows.

These are individual desktop observations, not a game frame-time benchmark or a measure of perceptual fidelity. See the [measurement report](benchmarks/2026-10-13-m4.md), [raw samples](benchmarks/raw/), [measurement script](scripts/benchmark.py), and [moving test scene](scripts/benchmark-scene.swift) for methods and limits.

## Build from source

Install Xcode's command line tools, then run:

```sh
swift test
./scripts/build-app.sh
open dist/Snip.app
```

The build script creates an arm64 `dist/Snip.app` and ad hoc signs it for local use. It does not notarize the app. Snip uses Apple's ScreenCaptureKit, VideoToolbox, and AVFoundation.
