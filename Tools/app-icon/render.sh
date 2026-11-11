#!/bin/sh
# Renders every slot of MacAudioProbe/Assets.xcassets/AppIcon.appiconset from the SVGs here.
#
# The SVGs are Figma SVG exports of the Watching state (ad bulb dark) of the "Final / App icon"
# component in the Scoreboard CB design: its 16, 32 and 64 px hand-drawn sizes and the 1024 art.
# Figma paints the page background and the component set's white panel behind a component it
# exports, so after a re-export delete the two full-canvas <rect>s that precede the
# "Size=…, State=Watching" group (fill "#F5F5F5" and fill "white"). Do not use Figma's PNG
# export, which keeps the white panel, or its icon_*.png frames, which show the lit bulb.
# Tests/test_app_icon.py checks the results.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../../MacAudioProbe/Assets.xcassets/AppIcon.appiconset"

render() { # <svg size> <pixels> <slot file>
    swift "$here/render.swift" "$here/watching-$1.svg" "$2" "$out/$3"
}

render 16 16 icon_16x16.png
render 32 32 icon_16x16@2x.png
render 32 32 icon_32x32.png
render 64 64 icon_32x32@2x.png
render 1024 128 icon_128x128.png
render 1024 256 icon_128x128@2x.png
render 1024 256 icon_256x256.png
render 1024 512 icon_256x256@2x.png
render 1024 512 icon_512x512.png
render 1024 1024 icon_512x512@2x.png
