#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
target="$root/dist/Snip.app"
mkdir -p "$root/dist"
staging=$(mktemp -d "$root/dist/.Snip.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Snip.app"

swift build --package-path "$root" -c release --product Clipper
bin_dir=$(swift build --package-path "$root" -c release --show-bin-path)

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/clip.wav" "$app/Contents/Resources/clip.wav"
cp "$root/Resources/SnipIcon.icns" "$root/Resources/clipper-idle.png" \
   "$root/Resources/clipper-recording.png" "$root/Resources/clipper-warning.png" \
   "$app/Contents/Resources/"
cp "$bin_dir/Clipper" "$app/Contents/MacOS/Snip"
chmod 755 "$app/Contents/MacOS/Snip"
codesign --force --sign - "$app"

backup="$root/dist/.Snip.previous.app"
if [[ -e "$target" ]]; then
    rm -rf "$backup"
    mv "$target" "$backup"
fi
mv "$app" "$target"
rm -rf "$backup"
print -r -- "$target"
