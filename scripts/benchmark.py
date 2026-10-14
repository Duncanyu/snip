#!/usr/bin/env python3
"""Sample Snip's process cost and inspect a saved clip without reading its pixels."""

import argparse
import json
import plistlib
import subprocess
import time
from datetime import datetime
from fractions import Fraction
from pathlib import Path


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    return round(ordered[lower] + (ordered[min(lower + 1, len(ordered) - 1)] - ordered[lower]) * (position - lower), 2)


def summary(values):
    return {
        "median": percentile(values, 0.5),
        "p95": percentile(values, 0.95),
        "max": round(max(values), 2) if values else None,
    }


def settings():
    try:
        plist = plistlib.loads(subprocess.check_output(["defaults", "export", "local.Snip.capture", "-"]))
        saved = json.loads(plist["captureSettings"])
        keys = ("fps", "resolution", "bitrateMbps", "clipDuration", "memoryLimitMB",
                "includeAudio", "videoAppMode", "audioAppMode", "brightness", "contrast", "saturation")
        return {key: saved.get(key) for key in keys}
    except (OSError, subprocess.CalledProcessError, KeyError, ValueError):
        return {}


def system():
    display = json.loads(command("system_profiler", "SPDisplaysDataType", "-json"))["SPDisplaysDataType"][0]
    main = next((d for d in display.get("spdisplays_ndrvs", []) if d.get("spdisplays_main") == "spdisplays_yes"), {})
    return {
        "macos": command("sw_vers", "-productVersion"),
        "cpu": command("sysctl", "-n", "machdep.cpu.brand_string"),
        "ram_gib": round(int(command("sysctl", "-n", "hw.memsize")) / 2**30, 2),
        "display_pixels": main.get("_spdisplays_pixels"),
        "display_mode": main.get("_spdisplays_resolution"),
    }


def sample(args):
    pid = args.pid
    if pid is None:
        try:
            matches = command("pgrep", "-f", "^/Applications/Snip.app/Contents/MacOS/Snip$").splitlines()
        except subprocess.CalledProcessError:
            matches = []
        if len(matches) != 1:
            raise SystemExit("Expected one installed Snip process; pass --pid explicitly.")
        pid = int(matches[0])
    samples = []
    start = time.monotonic()
    while True:
        elapsed = time.monotonic() - start
        if elapsed >= args.seconds:
            break
        try:
            cpu, rss = command("ps", "-p", str(pid), "-o", "%cpu=", "-o", "rss=").split()
        except (subprocess.CalledProcessError, ValueError):
            raise SystemExit(f"Snip process {pid} stopped during measurement.")
        samples.append({"seconds": round(elapsed, 2), "cpu_percent": float(cpu),
                        "rss_mib": round(int(rss) / 1024, 2)})
        time.sleep(max(0, start + len(samples) * args.interval - time.monotonic()))
    data = {
        "label": args.label,
        "measured_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "method": "ps CPU percent (100%=one logical CPU), RSS sampled at the given interval",
        "pid": pid,
        "duration_seconds": round(time.monotonic() - start, 2),
        "interval_seconds": args.interval,
        "system": system(),
        "settings": settings(),
        "cpu_percent": summary([point["cpu_percent"] for point in samples]),
        "rss_mib": summary([point["rss_mib"] for point in samples]),
        "samples": samples,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Wrote {args.output}: CPU median {data['cpu_percent']['median']}%, RSS median {data['rss_mib']['median']} MiB")


def inspect(args):
    data = json.loads(args.output.read_text())
    probe = json.loads(command("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(args.clip)))
    video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
    audio = next((stream for stream in probe["streams"] if stream["codec_type"] == "audio"), None)
    duration = float(probe["format"]["duration"])
    size = args.clip.stat().st_size
    timestamps = []
    for line in command("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                        "frame=best_effort_timestamp_time", "-of", "csv=p=0", str(args.clip)).splitlines():
        try:
            timestamps.append(float(line.split(",")[0]))
        except ValueError:
            pass
    gaps = [(later - earlier) * 1000 for earlier, later in zip(timestamps, timestamps[1:]) if later > earlier]
    nominal_fps = float(Fraction(video.get("r_frame_rate", "0/1")))
    long_gaps = sum(gap > 1500 / nominal_fps for gap in gaps) if nominal_fps else None
    data["clip"] = {
        "duration_seconds": round(duration, 3),
        "size_mib": round(size / 2**20, 2),
        "file_bitrate_mbps": round(size * 8 / duration / 1e6, 2),
        "video_codec": video.get("codec_name"),
        "video_profile": video.get("profile"),
        "width": video.get("width"),
        "height": video.get("height"),
        "pixel_format": video.get("pix_fmt"),
        "color_space": video.get("color_space"),
        "nominal_frame_rate": video.get("r_frame_rate"),
        "average_frame_rate": video.get("avg_frame_rate"),
        "video_frames": len(timestamps),
        "decoded_frame_rate": round(len(timestamps) / duration, 2),
        "frame_gap_ms": summary(gaps),
        "frame_gaps_over_1_5_intervals": long_gaps,
        "audio_codec": audio.get("codec_name") if audio else None,
        "audio_sample_rate": audio.get("sample_rate") if audio else None,
    }
    args.output.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Updated {args.output}: {data['clip']['width']}×{data['clip']['height']}, "
          f"{data['clip']['duration_seconds']}s, {data['clip']['file_bitrate_mbps']} Mb/s")


parser = argparse.ArgumentParser(description=__doc__)
subcommands = parser.add_subparsers(dest="action", required=True)
sampling = subcommands.add_parser("sample", help="Measure one running Snip process")
sampling.add_argument("--label", required=True)
sampling.add_argument("--seconds", type=float, default=30)
sampling.add_argument("--interval", type=float, default=0.5)
sampling.add_argument("--pid", type=int)
sampling.add_argument("--output", type=Path, required=True)
inspection = subcommands.add_parser("inspect", help="Attach video metadata to a sample JSON")
inspection.add_argument("--output", type=Path, required=True)
inspection.add_argument("--clip", type=Path, required=True)
args = parser.parse_args()
if args.action == "sample":
    sample(args)
else:
    inspect(args)
