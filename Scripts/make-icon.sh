#!/bin/zsh

# Regenerates BarKit/BarKit.icns and BarKit/AppIcon-source.png from BarKit/AppIcon.svg.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
source_svg="$project_root/BarKit/AppIcon.svg"
work_dir="$project_root/build/icon"
iconset="$work_dir/BarKit.iconset"
renderer="$work_dir/render-icon"

rm -rf "$iconset"
mkdir -p "$iconset"

xcrun --sdk macosx swiftc -O "$script_dir/render-icon.swift" -o "$renderer"

for size in 16 32 128 256 512; do
    "$renderer" "$source_svg" "$iconset/icon_${size}x${size}.png" "$size"
    "$renderer" "$source_svg" "$iconset/icon_${size}x${size}@2x.png" "$((size * 2))"
done

iconutil -c icns "$iconset" -o "$project_root/BarKit/BarKit.icns"
cp "$iconset/icon_512x512@2x.png" "$project_root/BarKit/AppIcon-source.png"

printf 'Updated %s\n' "$project_root/BarKit/BarKit.icns"
