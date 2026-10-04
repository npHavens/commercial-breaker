# Local HLS relay experiment

The working Paramount player sends a bearer token on its encryption-key request and receives HTTP 200. A separate unauthenticated request received 403; our plain native HLS player failed after loading metadata. Nick subsequently verified moving video and sound locally and on Apple TV through this relay. Fresh-session playback still needs checking when restarting.

## Fast restart with a fresh session (October 3)

Double-click `Start Paramount Relay.command` in the project root. In Safari Web
Inspector > Network on the playing Paramount tab, copy the full URL of a recurring
media/variant `.m3u8` request from dai.google.com (not the master playlist). Paste
it at the first hidden Terminal prompt. Copy only the Authorization bearer value
from a successful cbsi.live.ott.irdeto.com key request and paste it at the second
hidden prompt. Both values stay in process memory; do not paste them into chat.
After checks pass, open the printed local player address in Safari. Pause the
original Paramount tab, Play on the relay page, then Choose AirPlay. Leave the old
playlist-based automatic mute off when using Gemini. Native app v0.2.30 supports
this relay page's Choose AirPlay button for its TV via AirPlay automatic mode.
Fresh-session TV playback was confirmed October 3; automatic relay handoffs still
need live verification.

## Run on this Mac

Python 3.9 or newer is sufficient; there are no third-party dependencies.

1. In the working Paramount Safari tab, copy the bearer value from the successful key request's Authorization header. Do not paste it into chat or save it in source code.
2. Open Terminal and run:

   ```sh
   cd /Users/nickhavens/Projects/skybox
   python3 Tools/hls_relay.py
   ```

3. Paste the token at the hidden prompt and press Return. Either the bare token or `Bearer <token>` is accepted. Nothing appears while pasting. The existing `playlist-url.txt` contains the supplied live URL and is excluded from version control.
4. The relay fetches the live playlist and tests its last referenced AES key. It starts serving only if those checks pass. Copy the printed local address into **Safari**, not the old standalone test file. Keep Terminal running.
5. Pause the original Paramount tab. Turn off Mac Screen Mirroring. On the relay page click **Play** and verify moving UFC video and audio for at least 30 seconds.
6. Only after local playback succeeds, click **Choose AirPlay → Living Room**. Confirm moving video and audio on TV, then test **Mute / Unmute** and confirm video keeps moving.
7. If playback fails, copy the page's Playback history and Relay history. They omit credentials, upstream URLs, and key contents. For a startup failure, provide only the printed error message.
8. **Stop playback** releases the stream but leaves the relay running. Press **Ctrl+C in Terminal** to shut it down. Restart with a fresh token if authentication expires.

If interface detection fails, specify the Mac's Wi-Fi/Ethernet IPv4 address using `--bind 192.168.x.x`. It must be an actual private address assigned to this Mac and reachable by Apple TV, not localhost or 0.0.0.0. A VPN default route may require this override. Use `--port 8766` if 8765 is already occupied. Allow local network/incoming connection access if macOS prompts; do not enable port forwarding.

If the stream session expires, replace the contents of `playlist-url.txt` with a fresh `.m3u8` media-playlist request URL from the working player, then restart. No session renewal or automatic credential capture is implemented.

## Data flow and limits

- The relay binds one private LAN IPv4 interface. A random 256-bit session path gates the player, playlist, diagnostics, and key routes. A fresh path is generated each run. Host headers must match the configured address and port.
- Playlist requests go only to `dai.google.com`, without bearer authorization. Live playlists are fetched again on every request and responses use `Cache-Control: no-store`.
- AES-128 identity key URIs are rewritten to local routes. Only keys registered from a validated playlist can be fetched. Authorization goes only to `cbsi.live.ott.irdeto.com` over HTTPS. Redirects are rejected, and a key response must be exactly 16 bytes. The token remains in process memory; it is neither saved nor included in URLs, HTTP responses, or logs.
- Video segment URLs remain HTTPS CDN URLs; relative segment paths are resolved against the original playlist. The relay does not fetch, decrypt, record, or transcode video. Safari/Apple TV handles playback. Cue markers, IVs, sequence numbers, and timing tags are preserved.
- The **LAN leg uses HTTP**, including key responses. The session URL is a capability: anyone who obtains it and can reach the Mac can access the session, and local HTTP provides no transport confidentiality. This is a trusted-home-network experiment, not a public server or production deployment. Do not share the session URL or expose the port to the Internet.
- No keys are cached or written to disk; native clients may cache them. Key IDs and URLs are kept in memory for rotation, bounded to 256 unique keys per run. Source and response sizes are bounded, and upstream requests time out after 15 seconds.
- This is deliberately restricted to the observed media playlist with HTTPS segments and AES-128 identity keys. Master playlists, URI-bearing tags other than `EXT-X-KEY`, variable substitution, and other encryption formats are rejected. Use the variant/media URL already captured, not an uninspected master playlist.
- The server uses Python's standard HTTP server for this local experiment; it has no production resource isolation or automated token refresh. Stop it when done. Apple TV reachability, native decryption, codec support, and AirPlay mute behavior still require the live test.

## Checks

```sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
node --test Tests/safari/*.test.cjs
```

Python checks use synthetic playlists/keys and temporary loopback HTTP servers. They cover playlist rewriting and rotation, host and route restrictions, key validation, header scoping, redirect refusal, fresh playlist fetching, HEAD behavior, and sanitized errors. JavaScript checks cover local playback gating, retry behavior, muting, and stopping. The saved real playlist was also rewritten locally without fetching credentials or changing its source file. These checks do not establish live authenticated playback.

## Playback progress diagnostics

The page labeled **Player diagnostics v2** reports current playback position, buffered and seekable ranges, video dimensions, available frame counters, audio track count and enabled state, mute, and volume. It adds a progress sample every five seconds while unpaused, and **Check playback** takes a manual snapshot. Unsupported metrics appear as unknown, distinct from zero. Counts can indicate processing without proving visible content or audible output, especially during AirPlay.

The running relay reads the HTML on each page request. Refresh its Safari page to load these diagnostics without restarting the server or re-entering the bearer token. Test local playback for 15 seconds and inspect successive progress lines before trying AirPlay.

### Tab activation investigation

Nick subsequently confirmed local moving footage and sound, then successful TV video and sound after refreshing. Switching back to the Safari player tab reportedly returns playback to the Mac; the trigger has not been isolated.

**Player diagnostics v3** adds visibility, focus, pageshow/pagehide, and explicit playback-button events. The bounded 40-line history survives page reloads in tab-scoped session storage, with a new initialization marker on each page load. These handlers only record state; they never call play, pause, load, or change the source or target. Reproduce once by selecting AirPlay, switching to a quiet tab, and switching back without clicking the player, then inspect the transition. A new initialization marker suggests a reload; an explicit control marker distinguishes button activation; a wireless transition alone does not establish its cause.

References: [WebKit's MSE/AirPlay source requirements](https://webkit.org/blog/15036/how-to-use-media-source-extensions-with-airplay/), [HLS encryption keys](https://www.rfc-editor.org/rfc/rfc8216.html#section-5).

## Extension and automatic commercial mute (v0.2.0)

This update adds server routes, so it requires **one relay restart**, not just a page refresh. In its Terminal, press Ctrl+C and run `python3 Tools/hls_relay.py` again, entering the token at the hidden prompt. Open the newly printed session URL; the old URL expires when the server stops. Reload the temporary Safari extension from the same SafariExtension directory and confirm v0.2.0 in its popup.

With the relay player active, the popup now offers manual mute and **Enable automatic mute**. The same toggle appears on the page. Closing the popup does not stop monitoring; refreshing the page turns it off. Use the page's Choose AirPlay control for the native picker.

Test one whole marked break:

1. Establish moving video and sound on the Mac, then Apple TV. Test extension Mute/Unmute before enabling automatic mode; verify actual TV audio responds while video keeps moving.
2. Open Skybox on the relay tab and click Enable automatic mute. Grant page access if requested. Its status should say Program or Commercial; unknown timing does not authorize muting. The page status updates continuously; Check again refreshes the popup status.
3. At the next marked break, verify sound stops while video continues. At return to programming, verify audio returns. Record whether transitions align with the TV content; playlist markers may not cover every in-program promotion.
4. Verify a pre-existing manual mute stays muted, and that manual mute/volume changes disable automatic mode. Turn automatic mode back on explicitly afterward.
5. Repeat a break with the Safari tab in the background. Safari timer/event scheduling and remote playhead synchronization are live-test dependencies. Missing timing or request failure releases an owned mute when the page can execute; suspension can delay that recovery.

Classification uses getStartDate() + currentTime against UTC cue spans, not wall-clock broadcast time. Missing start date, stale snapshots, overlapping spans, timestamp discontinuities without a new clock, and unmapped playheads return unknown. Advertised break duration caps each ad interval when CUE-IN is missing. The controller preserves manual mute and never changes volume, source, playback position, play/pause, or target.
