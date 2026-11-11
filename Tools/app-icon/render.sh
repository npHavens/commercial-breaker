#!/bin/sh
# Renders every slot of MacAudioProbe/Assets.xcassets/AppIcon.appiconset from the SVGs here.
#
# The SVGs are Figma SVG exports of the Watching state (ad bulb dark) of the "Final / App icon"
# component in the Scoreboard CB design: its 16, 32 and 64 px hand-drawn sizes and the 1024 art,
# saved as watching-<size>.svg. Figma paints the page background (a 1024 x 1024 rect) and the
# component set's white panel (a white rect starting above and left of the canvas) behind a
# component it exports; this script drops just those two, so a new export can replace a file
# as is. Do not use Figma's PNG export, which keeps the white panel, or its icon_*.png frames,
# which show the lit bulb.
# Tests/test_app_icon.py checks the results.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../../MacAudioProbe/Assets.xcassets/AppIcon.appiconset"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -O -o "$work/render" "$here/render.swift"

render() { # <svg size> <pixels> <slot file>
    sed -E -e '/^<rect width="1024" height="1024" fill="#[0-9A-Fa-f]{6}"\/>$/d' \
        -e '/^<rect x="-[0-9.]+" y="-[0-9.]+" [^>]*fill="white"\/>$/d' "$here/watching-$1.svg" > "$work/$1.svg"
    "$work/render" "$work/$1.svg" "$2" "$out/$3"
}

render 16 16 icon_16x16.png
render 32 32 icon_32x32.png
render 64 64 icon_32x32@2x.png
render 1024 128 icon_128x128.png
render 1024 256 icon_256x256.png
render 1024 512 icon_512x512.png
render 1024 1024 icon_512x512@2x.png
# Slots with the same pixel size share one rendering.
cp "$out/icon_32x32.png" "$out/icon_16x16@2x.png"
cp "$out/icon_256x256.png" "$out/icon_128x128@2x.png"
cp "$out/icon_512x512.png" "$out/icon_256x256@2x.png"
