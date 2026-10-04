#!/bin/zsh
cd -- "${0:A:h}" || exit 1
/usr/bin/python3 Tools/hls_relay.py --prompt-playlist
printf '\nPress Return to close this window.'
read -r
