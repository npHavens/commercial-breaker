# Commercial Breaker Safari extension

Version 0.2.22: a temporary Manifest V3 extension with three jobs. The native app does the
listening and muting; nothing here detects commercials.

- **DIRECTV handoff correction.** `directv-autoload.js` attaches `directv-airplay-recovery.js`
  to every `https://stream.directv.com` page when it finishes loading. After an AirPlay handoff
  it corrects the player's timeline with a guarded seek, the short rewind, and changes nothing
  else. `Experiments/airplay-return-oct4.md` has the investigation. In the page's console,
  `commercialBreakerDirectvRecovery.stop()` stops it until the page reloads.
- **On-page AirPlay button.** On a DIRECTV or Paramount+ tab, the popup's **Show AirPlay test
  on page** adds a panel to the top right of the page; exit video fullscreen to see it.
  - **Try AirPlay** opens Safari's native picker for the one visible player.
  - **Test return route (15 seconds)** tries a TV → Mac → TV round trip without opening a picker.
  - **Restore settings and close** puts back the player attributes it changed and removes the panel.
  The popup keeps the steps of the last attempt under **Last AirPlay attempt**.
- **Paramount+ relay capture.** See below.

On DIRECTV and Paramount+ the popup also shows whether the page's player is muted or paused.
It only reads the player and never changes it.

## Load in Safari

1. In Safari Settings, turn on developer features under Advanced.
2. In the Developer tab, load a temporary extension and choose this `SafariExtension` folder.
3. Grant the DIRECTV, Paramount+, Google DAI, Irdeto and loopback access Safari asks for.
4. Refresh any open DIRECTV, Paramount+ and relay tabs. An older DIRECTV correction keeps
   running beside the new one until its page is refreshed.

Temporary extensions expire after 24 hours or when Safari quits. See Apple's guide:
https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension

## Paramount+ relay

1. Run the root **Start Paramount Extension Helper.command** launcher and keep its Terminal
   open. It's separate from the original manual relay, so starting it doesn't stop TV playback.
2. On the playing Paramount+ tab, open Commercial Breaker, paste the helper's pairing code
   under Paramount TV setup, and click **Capture Paramount & open relay**.
3. Reload that Paramount+ tab and resume playback. Capture survives the popup closing. For up
   to two minutes it waits for this tab's successful variant playlist and authorized key
   request, then asks the helper to validate both.
4. The relay opens in a new tab. Pause the original player, then click Play and Choose AirPlay.
   Leave the relay page's own automatic mute off when the native app is listening.

The background listener captures only while explicitly armed, and only from the armed tab.
Authorization is accepted only from the exact Irdeto key endpoint with a successful response.
The credentials and pairing code stay in memory, and status responses never contain them.
Navigating away cancels capture. Safari may discard an idle background page; if capture
disappears, arm it again.

The helper accepts authenticated JSON on 127.0.0.1:8766 only, validates Host, rejects
oversized input and grants no webpage CORS access. The random code pairs the extension to
this helper run. It starts one LAN relay on an available port, and repeated setup can't
silently replace playback. Restart the helper for a new session; closing it also stops its relay.

## Permissions

- `activeTab` and `scripting` inject the status reader and the AirPlay panel into the active tab.
- `tabs` lets the background read tab addresses, to attach the DIRECTV correction and to check
  the Paramount+ tab it captures from.
- `webRequest` reads Paramount+'s playlist and key requests while capture is armed.
- Host access covers DIRECTV for the correction, Paramount+, Google DAI and Irdeto for
  capture, and `127.0.0.1` for the helper.

## Player selection

The status reader and the AirPlay panel choose the unique visible playing video. If no visible
video is playing, they accept exactly one visible video. Missing or ambiguous players produce
an error and nothing is touched. A hidden playing preview doesn't displace a visible paused player.

## Local checks

```sh
npm test
npm run lint
```

The Safari tests run the real scripts against a simulated DOM. They don't simulate Safari's
permission prompts or the services' players, so a live DIRECTV AirPlay cycle, including the
short rewind, is still the check for the handoff correction.

The earlier probes, signal recording and export, screen capture test, mute controls and
source trace, with what they found, are in
[docs/archive/safari-extension-experiments.md](../docs/archive/safari-extension-experiments.md).
