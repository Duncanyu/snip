#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
app="$root/dist/Snip.app"

swift build --package-path "$root" -c release --product Clipper
bin_dir=$(swift build --package-path "$root" -c release --show-bin-path)

if [[ -e "$app" ]]; then
    rm -r "$app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/clip.wav" "$app/Contents/Resources/clip.wav"
idle_svg="/Users/duncanyu/Downloads/clipper-idle(1).svg"
recording_svg="/Users/duncanyu/Downloads/clipper-recording.svg"
warning_svg="/Users/duncanyu/Downloads/clipper-warning.svg"

for state in idle recording warning; do
    svg_var="${state}_svg"
    rsvg-convert -w 1024 -h 1024 "${(P)svg_var}" > "$app/Contents/Resources/clipper-$state.png"
done

iconset="$app/Contents/Resources/SnipIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$idle_svg" > "$iconset/icon_${size}x${size}.png"
    double_size=$((size * 2))
    rsvg-convert -w "$double_size" -h "$double_size" "$idle_svg" > "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/SnipIcon.icns"
rm -r "$iconset"
cp "$bin_dir/Clipper" "$app/Contents/MacOS/Snip"
chmod 755 "$app/Contents/MacOS/Snip"
codesign --force --sign - "$app"

print -r -- "$app"
