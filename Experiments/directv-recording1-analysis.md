# DIRECTV live football recording — September 20, 2026

Source: `/Users/nickhavens/Downloads/skybox-signals-2026-09-20T18-04-58-331Z.json` (963,651 bytes). Read directly from Downloads after the Safari save fallback. Nick confirmed this session is the real game, not pre-show.

## Observed

- Recording: 12:46:41–12:57:28 CDT, 651 entries: 647 samples, start, two manual markers, and manual stop.
- Commercial marker: 12:54:51.726 CDT. Program-return marker: 12:57:07.111 CDT. Marked interval: 135.385 seconds. Human reaction and AirPlay delay limit exact boundary precision.
- Before / during / after the marked interval: 489 / 136 / 22 samples.
- All 647 samples have an empty candidate DOM signals array. Neither video has ad-related classes. The visible video stays playing at readyState 4; the second video stays hidden and paused at readyState 0. These recorded properties do not distinguish this break.
- The visible player exposes one active metadata cue throughout, alongside captions and disabled subtitles. Cue start times advance during both programming and commercials. Some ends are null (non-finite or unavailable values normalized for export).

## Conclusion and next experiment

The current sampled DOM/player fields do not provide a usable commercial classifier for this break. This does not establish that DIRECTV exposes no ad signal: the recorder inspects a bounded top-frame DOM sample and records only cue timings, not metadata payloads.

Next inspect the metadata cue's type and a bounded, redacted payload shape. Determine whether it carries explicit ad boundaries or merely routine stream timing before collecting further full-break recordings or implementing mute decisions. Do not use cue presence, changing timestamps, or null end times alone as commercial indicators. Avoid collecting caption text, stream URLs, tokens, or arbitrary unbounded metadata values.

No automatic DIRECTV muting is enabled or validated by this recording. The successful saved export verifies recovery of this recording through the new save workflow; it does not establish general Safari stability.

## First metadata snapshot

Read `skybox-signals-2026-09-20T18-11-06-205Z.json` from Downloads. At 13:10:53 CDT the active cue has type `org.id3` and value key `PRIV`. Its value object has three fields: key, a redacted 249-character string, and one byte of binary data. The cue-level data property is null. This snapshot's program/ad state was not supplied, so it cannot establish a correlation.

The v0.2.5 probe recognizes info/owner field names and inspects short JSON-encoded strings through the same redaction rules, plus reports a fixed vocabulary of splice/ad boundary markers. No raw string payload is exported. Next snapshot should establish whether the 249-character field contains structured event data; do not infer ad status from PRIV alone.

Nick confirmed the 13:13:06 CDT snapshot (`skybox-signals-2026-09-20T18-13-08-814Z.json`) was during a commercial. It identifies the previously hidden field as info: 249 characters, no parsed JSON, no recognized boundary vocabulary; data remains one byte. This does not establish that info has no useful encoded content. v0.2.6 adds a bounded, pattern-redacted PRIV info preview and one-byte value to resolve that uncertainty.

## Paired football/commercial snapshots

Nick labeled the first export as football and the second as a commercial:

- Football: `skybox-signals-2026-09-20T18-15-22-216Z.json`, sampled 13:15:18.928 CDT.
- Commercial: `skybox-signals-2026-09-20T18-15-47-685Z.json`, sampled 13:15:42.599 CDT.

Both info values start with `www.nielsen.com/`, contain slash-separated opaque payloads and trailing numbers, and are 249 characters long. Both binary payloads equal 65 (ASCII A). The opaque portion and trailing numbers change; the prefix, first two opaque components, and final `00` component remain the same. No explicit ad/content flag was exposed. Two time-separated snapshots cannot show that changed values identify ads rather than ordinary stream progression.

Nielsen's Browser SDK API Reference documents the `www.nielsen.com` ID3 prefix and its sendID3 documentation identifies the PRIV owner payload as measurement input:

- https://engineeringportal.nielsen.com/wiki/Browser_SDK_API_Reference
- https://engineeringportal.nielsen.com/wiki/sendID3%28%29

Its DTVR Browser SDK separately documents content/ad metadata (`loadMetadata`), but whether DIRECTV supplies those events for this stream has not been inspected: https://engineeringportal.nielsen.com/wiki/DTVR_Browser_SDK

Conclusion: the observed cue is Nielsen measurement metadata, not an established commercial-boundary signal. Do not build a classifier from opaque changes or byte 65. Next inspect DIRECTV's actual media playlist for explicit ad markers; service/player ad lifecycle metadata is another candidate. No further format-only ID3 snapshots are needed at this point.

## Safari media playlist

Read `/Users/nickhavens/Downloads/directv-playlist.m3u8` (98,817 bytes). Nick confirmed football was playing when captured. The playlist covers September 20, 16:19:07.651–17:20:07.307 CDT, so it does not overlap the earlier manually marked break around 12:54–12:57 CDT.

- 610 media segments, total 3,659.656 seconds (about 61 minutes).
- 610 PROGRAM-DATE-TIME entries; 608 segments last 6.006 seconds and two last 4.004 seconds.
- No CUE-OUT, CUE-IN, CUE-OUT-CONT, DATERANGE, SCTE tags, or DISCONTINUITY tags.
- Other tags: version, DTV-PUBLISH-TIME, target duration, media sequence, one initialization map, and two SAMPLE-AES key declarations. No key requests or decryption were attempted.
- Segment names follow one consistent numeric pattern; no explicit ad path switch is visible.

The supplied playlist has no explicit commercial markers. This excludes applying the current Paramount cue parser to this file, not every possible DIRECTV signal or rendition. The capture state and long window alone do not prove which historical segments were ads. Next candidate experiments are player ad lifecycle metadata or testing whether a local Safari frame can be read for visual detection while AirPlay is active; neither is established yet.

## Capture and event-test results

Nick subsequently reported that canvas pixel readback failed with a cross-origin tainted-canvas error. Window and full-screen capture both showed a black video area, including after disconnecting AirPlay and playing locally in Safari. These tested capture paths did not supply usable DIRECTV footage. No particular DRM mechanism is inferred from these observations.

Read `skybox-signals-2026-09-20T22-40-18-736Z.json` from Downloads. The player-event recorder ran from 17:39:17.849 to 17:39:42.901 CDT (25.052 seconds). Its five entries are start, three native video stalled events, and stop with reason manual. There are no commercial/program markers and no observed ad events. It found two video elements and no exposed Video.js registry/instances; discovery itself did not report an exception. This verifies limited DOM/media observation, not access to DIRECTV's private player event bus. It does not establish that a commercial transition occurred during the test or that DIRECTV lacks internal ad events. Stalled events must not be treated as an ad classifier.

## Player identity investigation

Inspected the signed-in DIRECTV Chrome page through browser tools after the event test. Its DOM contains `video#quickplayPlayer.player.-active` inside `.players-bridge`, and `video#freeWheelPlayer` inside `#freeWheel.player.-hidden.-home`. Loaded application scripts use hashed `att-purern.*.bundle.js` filenames. No console messages matched `player` during this inspection.

These DOM names suggest Quickplay and a separate FreeWheel integration; they do not establish SDK versions, exposed player instances, or use of the FreeWheel path for live football. This observation is from Chrome, not a fresh Safari inspection. The previous marked Safari break kept the second video hidden and paused, so merely watching for that video to play would not have detected that recorded break.

Quickplay's public web Broadpeak integration documentation shows ad lifecycle subscriptions on an `adsPlayer` instance and `playercontextchanged` events: https://developer.quickplay.com/docs/products/player/web/broadpeak . This is evidence of a possible SDK architecture, not evidence that DIRECTV uses Broadpeak or that those events are available on its DOM/window. Adding these names to DOM listeners alone would not establish coverage. Next determine whether an existing player/ad-manager instance is exposed, without initializing players, traversing application state, invoking getters, or logging credentials. If none is exposed, source-level inspection is needed before adding another event adapter.

### Safari global-name discovery result

Read `skybox-signals-2026-09-20T22-49-34-605Z.json` from Downloads (player-events report version 2). The scan inspected 1,142 own global property names with no truncation or failure. None matched Quickplay or FreeWheel. Two video elements and no exposed Video.js registry were reported again. This rules out those matching own global names in this snapshot, not differently named, nested, or module-private player instances. No commercial classifier or new event subscription was established. Next inspect the loaded application source to locate the player construction and event interface; repeating this global-name test is not useful without new evidence.
