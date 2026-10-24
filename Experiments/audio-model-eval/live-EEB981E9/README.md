# Faster confirmation live check

September 27, 2026, v0.2.16. 66 requests produced 66 predictions without request
failures. Recorder reports zero dropped blocks. Ten fast follow-ups dispatched a
median 36 ms after the preceding result; their results arrived a median 1.69s later.
The shorter scheduling path works. No additional audio was uploaded for review.

The marked break was not confirmed until +27.11s. Several unclear samples followed
the break marker, and a football prediction arrived at +22.57s. Commercial arrived
at +24.61s and the fast promo result confirmed break at +27.11s. Thus the long delay
preceded the candidate: it was not primarily a confirmation scheduling delay.
The model repeatedly described competing room speech and faint/garbled TV audio;
these descriptions are not independently verified acoustic measurements.

Football confirmed 1.67s before the return marker, after a 1.69s follow-up result.
The marker may be late or the prediction early; its timing is not independent
truth. The only confirmed changes were initial football, break, and football.
No extra confirmed switches occurred in this log. More overlapping audio can still
reinforce the same mistake; this single run does not validate automatic playback.
