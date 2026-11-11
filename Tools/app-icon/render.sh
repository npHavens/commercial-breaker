#!/bin/sh
# Renders every slot of MacAudioProbe/Assets.xcassets/AppIcon.appiconset from the SVGs here.
#
# The SVGs are Figma SVG exports of the Watching state (ad bulb dark) of the "Final / App icon"
# component in the Scoreboard CB design: its 16, 32 and 64 px hand-drawn sizes and the 1024 art,
# saved as watching-<size>.svg. Figma paints backdrops behind a component it exports (the page
# background and the component set's white panel), as rects before the "Size=…, State=Watching"
# group; this script drops every rect before that group and fails unless the group's size
# matches the file name, so a new export can replace a file as is. Do not use Figma's PNG export, which keeps the white panel, or its icon_*.png frames,
# which show the lit bulb. Tests/test_app_icon.py checks the results.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../../MacAudioProbe/Assets.xcassets/AppIcon.appiconset"
# Beside the catalog, so the final mv is a rename on the same volume.
work=$(mktemp -d "$out/../.render.XXXXXX")
trap 'rm -rf "$work"' EXIT
xcrun swiftc -O -o "$work/render" "$here/render.swift"
mkdir "$work/slots"

render() { # <svg size> <pixels> <slot file>
    awk -v group="<g id=\"Size=$1, State=Watching\"" 'index($0, group) == 1 { art = 1 } art || !/^[[:space:]]*<rect / { print }
         END { if (!art) { print FILENAME ": no Size=" size ", State=Watching group" > "/dev/stderr"; exit 1 } }' \
        size="$1" "$here/watching-$1.svg" > "$work/$1.svg"
    "$work/render" "$work/$1.svg" "$2" "$work/slots/$3"
}

render 16 16 icon_16x16.png
render 32 32 icon_32x32.png
render 64 64 icon_32x32@2x.png
render 1024 128 icon_128x128.png
render 1024 256 icon_256x256.png
render 1024 512 icon_512x512.png
render 1024 1024 icon_512x512@2x.png
# Slots with the same pixel size share one rendering.
cp "$work/slots/icon_32x32.png" "$work/slots/icon_16x16@2x.png"
cp "$work/slots/icon_256x256.png" "$work/slots/icon_128x128@2x.png"
cp "$work/slots/icon_512x512.png" "$work/slots/icon_256x256@2x.png"
# Replace the catalog's images only once every slot has rendered.
mv "$work"/slots/*.png "$out/"
