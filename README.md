# Skybox

A community project for watching sports with fewer audible commercials. Skybox
uses a native macOS companion, a Safari extension, and Gemini audio detection.
It is an early development project, not a production release.

## Viewing modes

- **Mac playback:** keep the stream on your computer; mute confirmed commercials
  and restore sound on confirmed program return. You can work in other apps.
- **TV via AirPlay:** listen through the Mac microphone while the stream plays
  on TV, move a confirmed break to muted Mac playback, then return to TV when
  the program is confirmed.

Both modes release mute after three minutes and continue detecting. The current
system tap captures and mutes all Mac playback audio, including other apps.
Audio samples go to Google Vertex Gemini. TV mode can include nearby voices.

## Current state

Native v0.2.44 and Safari extension source v0.2.21. AirPlay has been working well
in personal use; Mac playback is undergoing renewed live testing. The latest
native build adds one startup retry when Safari focus returns to Skybox. Its
build passes, but the retry still needs live verification. Sports-themed ads can
cause false returns. Packaged extension attachment still needs reload testing.

## Development

Open `SkyboxProbe.xcodeproj` and select **SkyboxAudioProbe** (the macOS target).
The separate SkyboxProbe tvOS target is historical and is not the active app.
Use a full Xcode installation and configure your own signing team.

```sh
xcodebuild -project SkyboxProbe.xcodeproj -scheme SkyboxAudioProbe \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/mac-audio CODE_SIGNING_ALLOWED=NO build
node --test Tests/gemini-audio/*.test.mjs Tests/safari/*.test.cjs
python3 -m unittest discover -s Tests -p 'test_*.py'
```

The build command checks compilation without signing; running with macOS
permissions requires a signed build. See the [native runbook](MacAudioProbe/README.md)
and [extension setup](SafariExtension/README.md) for current local operation.

**Setup is not self-contained yet.** The native launcher expects Node 24 under
nvm and loads the SDK, TypeScript loader, environment and Vertex configuration
from a sibling Interview Assistant checkout. Removing this coupling is the
first portability task; a fresh clone alone cannot run detection today.

## Repository map

| Directory | Responsibility |
| --- | --- |
| `MacAudioProbe/` | Active Swift app, capture, routing and automatic policy |
| `SafariExtension/` | Safari controls and DIRECTV AirPlay correction |
| `Tools/` | Runtime classifier/relay helpers and evaluation tools |
| `Tests/` | Offline behavior and regression tests |
| `docs/` | Contributor workflow and cleanup plan |
| `Experiments/` | Findings, prompts and historical evidence; some prompts still used at runtime |
| `SkyboxProbe/` | Legacy tvOS feasibility prototype |

See [contributing](CONTRIBUTING.md) and the [cleanup roadmap](docs/roadmap.md).
Old setup and feasibility notes are preserved in the
[prototype archive](docs/archive/prototype-overview.md).

## License

MIT, copyright No Hands Stack LLC. Third-party software retains its own license.
