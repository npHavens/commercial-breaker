# Sportradar NFL commercial signals — documentation review

Reviewed September 20, 2026. No account, trial, or subscription started. No live API calls made.

## Important correction

The NFL FAQ's Pulse Data section explicitly lists `payload.pulse.event_type` values `tv_timeout` and `tv_timeout_over`, as well as `timeout`, `timeout_over`, `players_lining_up`, `play_start`, `review`, and `review_over`. The earlier statement that no end event was documented was incomplete: it overlooked Push Pulse's separate event vocabulary.

Source: https://developer.sportradar.com/football/reference/nfl-faq

## Product and timing distinctions

- Standard Game Play-by-Play lists `tv_timeout`, `timeout`, `two_minute_warning`, `period_end` and other events, but not the Pulse end-event pair. Its live cache TTL is three seconds; this is not an end-to-end latency guarantee.
- Push Pulse describes on-field activity before/during/after plays. Access explicitly requires a Realtime plan with Pulse enabled and contact with sales. Trial URLs in code examples do not establish self-service entitlement; the access-level table lists production.
- Pulse `wall_clock` is documented as the previous play's snap timestamp, updated with the play event. It must not be assumed to timestamp a timeout boundary. `created_at` is message creation time. Correct broadcast alignment remains unverified.
- The live-game guide says initial play results typically arrive 5–10 seconds behind the broadcast. That statement concerns play-by-play results, not a specific Pulse timeout latency guarantee or Nick's delayed DIRECTV/AirPlay stream.

Sources:
- https://developer.sportradar.com/football/reference/nfl-play-by-play
- https://developer.sportradar.com/football/reference/nfl-push-pulse
- https://developer.sportradar.com/football/docs/nfl-ig-live-game-retrieval
- https://developer.sportradar.com/getting-started/docs/your-account

## Evidence limits

The public short Pulse JSON example includes `players_lining_up`, but no `tv_timeout` or `timeout_over` matches. The full-game download link could not be opened by the web reader. No complete-game break pairs were validated.

Sample: https://api-docs.sportradar.us/NFL/NFL_v7_Push_Pulse_Example.json

The reviewed documentation does not promise all broadcaster commercial breaks are captured, explain whether quarter/halftime/injury-related commercial breaks also receive TV-timeout pairs, or equate an on-field timeout end with a particular broadcaster's return to commentary. No DIRECTV/local insertion coverage or price is established.

## Recommendation before trial

Ask the provider specifically about NFL Push Pulse evaluation access and pricing, complete-game examples containing both TV timeout events, coverage of other break types, and the timing semantics/latency of each boundary. A generic REST trial does not establish the capabilities needed here. These questions are prepared but have not been sent. If access is practical, validate in observation-only mode against the actual stream before muting.
