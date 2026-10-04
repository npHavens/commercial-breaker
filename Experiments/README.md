# DIRECTV browser experiment

Source: https://github.com/jvanakker/tvosbrowser
Pinned checkout: 9b90e0e6d0cecd381e739cdeec4ea7033cbba3c8.
Local change: default homepage in BrowserNavigationService.m is https://stream.directv.com/.
This uses unsupported private tvOS WebKit APIs; it is a device experiment, not an App Store implementation.

## Build

```sh
DEVELOPER_DIR=/Users/nickhavens/Downloads/Xcode.app/Contents/Developer xcodebuild -project Experiments/tvOSBrowser/_Project/Browser.xcodeproj -scheme Browser -configuration Debug -destination 'generic/platform=tvOS' -derivedDataPath /tmp/skybox-browser-build DEVELOPMENT_TEAM=SHL25NTZ48 PRODUCT_BUNDLE_IDENTIFIER=com.nohandsstack.skybox.browser CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates build
```

Signed build and installation on Living Room Apple TV succeeded on 2026-09-19. Upstream compiler warnings remain (nullability, deprecated APIs, initializer annotations). DIRECTV login and protected live playback are not yet verified.

## Device test

1. Open tvOS Browser and dismiss the usage hints.
2. The default start page is DIRECTV. If necessary, press Play/Pause once to open Quick Menu and enter https://stream.directv.com/.
3. Move the cursor with the remote touch surface and click to select. Double-click the center to toggle cursor/scroll modes.
4. Sign in directly on the device. Do not put credentials into source files or diagnostic logs.
5. Select a subscribed live channel. Verify continuous video and audio for at least 30 seconds.
6. Report whether failure occurs at page load, login, or playback, with the displayed error text.

Keep experimental native fullscreen playback disabled for the initial test; use the website player. Player mute control and commercial detection are subsequent experiments, not implemented by this setup.

## tvOS 27 startup correction

The initial device launch crashed in `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` (SIGTRAP), before WebKit or DIRECTV loaded. Added a single-window scene manifest and BrowserSceneDelegate, moved cookie persistence callbacks to the scene lifecycle, and retained Main.storyboard as the scene's initial UI. Rebuilt and reinstalled successfully.
