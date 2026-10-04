# Paramount+ recording 1

Source: `SafariExtension/recording1.json`. Recorded September 19, 2026, 16:43:11–16:57:45 America/Chicago. Nick reports the manual marks were approximate.

## Evidence

- 873 samples over approximately 14 minutes 34 seconds; no dropped entries or recorded errors. Maximum observed sample gap: 1.053 seconds.
- One visible video throughout, playing, unmuted, volume 0.8, readyState 4. Those fields did not distinguish commercial playback.
- The recorder scanned 2,438–2,440 attributed DOM elements per sample, below its 5,000-element scan cap.
- `.ad-info-manager` and six related child-class markers were hidden initially, visible continuously from 21:54:02.343Z to the first hidden sample at 21:56:01.839Z (119.496 seconds), then hidden through the end.
- `.ad-click-overlay` was visible during three roughly 29-second intervals within that window. It disappeared between them, including a 31-second interval. Using it alone would cause unmute gaps while the ad-info marker remained visible.
- `.mini-player-ad-countdown` remained hidden throughout. Presence of an ad-related class alone is not sufficient: most of the ad-related DOM remained present while hidden.

## Timing comparison

| Event | America/Chicago |
| --- | --- |
| Manual commercial mark | 16:53:39.825 |
| Ad-info marker first visible | 16:54:02.343 |
| Ad-info marker first hidden again | 16:56:01.839 |
| Manual broadcast-return mark | 16:57:06.397 |

The detected candidate window starts 22.518 seconds after the commercial mark and ends 64.558 seconds before the broadcast-return mark. The manually marked break spans 206.572 seconds. Approximate marks, broadcast-inserted ads without player markers, or other differences could explain the mismatch. This recording cannot distinguish them.

## Conclusion

Visible `.ad-info-manager` is a concrete candidate for Paramount+ ad detection. This is one observed window, not validated coverage of all UFC commercial breaks or other services. Next validate a read-only ad-state indicator against the actual TV picture over another break. Only after confirming behavior should an opt-in automatic mute controller use it. Hidden/missing markers should not be described as proof of program content.

No automatic mute behavior was added by this analysis.
