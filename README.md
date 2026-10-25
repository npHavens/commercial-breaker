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

Native v0.2.45 and Safari extension source v0.2.21. AirPlay has been working well
in personal use; Nick also confirmed Mac playback and the v0.2.44 startup fix
working on October 18. v0.2.45 changes only Gemini setup: Skybox now declares
its own Node dependencies and configuration (see below) and needs no other
checkout. Its live detection start is not yet user-verified. Sports-themed ads
can cause false returns. Packaged extension attachment still needs reload testing.

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

### Gemini setup

Detection runs a Node worker from this checkout and sends audio to Google Vertex
AI. You need Node 24, a Google Cloud project with the Vertex AI API enabled, and
Application Default Credentials. Skybox does not use Gemini API keys.

```sh
nvm install                            # Node 24, from .nvmrc
npm ci
cp .env.example .env                   # then set GOOGLE_CLOUD_PROJECT
gcloud auth application-default login
```

The app finds Node 24 under `~/.nvm/versions/node` and reads `.env` and
`node_modules` from the checkout it was built from. If setup is incomplete,
starting detection reports what is missing; recording continues.

Application Default Credentials are shared by every app on the Mac, including
their quota project. If another project sets it, add `GOOGLE_CLOUD_QUOTA_PROJECT`
to `.env` (see `.env.example`) so Skybox is metered against its own project.

## Repository map

| Directory | Responsibility |
| --- | --- |
| `MacAudioProbe/` | Active Swift app, capture, routing and automatic policy |
| `SafariExtension/` | Safari controls and DIRECTV AirPlay correction |
| `Tools/` | Runtime classifiers, prompts and relay helpers; evaluation tools |
| `Tests/` | Offline behavior and regression tests |
| `docs/` | Contributor workflow and cleanup plan |
| `Experiments/` | Findings and historical evidence; not used at runtime |
| `SkyboxProbe/` | Legacy tvOS feasibility prototype |

See [contributing](CONTRIBUTING.md) and the [cleanup roadmap](docs/roadmap.md).
Old setup and feasibility notes are preserved in the
[prototype archive](docs/archive/prototype-overview.md).

## License

MIT, copyright No Hands Stack LLC. Third-party software retains its own license.
