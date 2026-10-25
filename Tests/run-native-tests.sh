#!/bin/zsh
# Compiles and runs each native test with only the app sources it needs.
# Offline only: fake workers and synthetic audio, no uploads.
# Usage: Tests/run-native-tests.sh [test-name ...]   (set DEVELOPER_DIR for a non-default Xcode)
cd -- "${0:A:h}/.." || exit 1

typeset -A sources
sources=(
  airplay-routing             "AirPlayRouteChoice"
  audio-sample-clock          "AudioSampleClock"
  automatic-commercial-policy "GeminiConfirmation AutomaticCommercialPolicy"
  gemini-buffer               "GeminiAudioBuffer"
  gemini-confirmation         "GeminiConfirmation"
  gemini-observation          "GeminiAudioBuffer GeminiRecovery GeminiConfirmation GeminiObservation"
  gemini-recovery             "GeminiRecovery"
  mac-audio                   "AudioLevels"
  skybox-panel                "AirPlayRouteChoice SafariAccessibility"
  tap-conversion              "AudioLevels AudioSampleClock AudioTap"
  viewing-activity            "ViewingActivity"
)

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
selected=(${@:-${(ok)sources}})
failed=()
for name in $selected; do
  if [[ -z ${sources[$name]} ]]; then print -u2 "Unknown test: $name"; failed+=($name); continue; fi
  files=(${(s: :)sources[$name]}); files=(MacAudioProbe/${^files}.swift)
  flags=(); grep -q '@main' Tests/$name/main.swift && flags=(-parse-as-library)
  if ! xcrun swiftc $flags -module-cache-path $work/cache $files Tests/$name/main.swift -o $work/$name; then
    print "✖ $name (compile)"; failed+=($name); continue
  fi
  if output=$($work/$name 2>&1); then print "✔ $name"; else print "✖ $name"; print -- $output | tail -3; failed+=($name); fi
done
(( ${#failed} == 0 )) || { print "Failed: $failed"; exit 1 }
