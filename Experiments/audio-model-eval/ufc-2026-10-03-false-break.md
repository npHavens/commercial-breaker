# UFC replay false mute — October 3, 2026

User ground truth: post-fight replay; should remain audible.
Session: D072469B-5D60-48E1-B9C9-803E582E0991.
Automatic log: automatic-03921083-89A5-4F47-BD9C-AAB054FF875D.jsonl.
Muted 23:48:51 UTC (18:48:51 America/Chicago).

NOTE: Earlier chat called this 5:48:51; the UTC log converts to 6:48:51 CDT.
Restored at 23:49:18 UTC (18:49:18 CDT), approximately 27 seconds later.
Two promo predictions triggered the mute; timestamps show fresh inputs rather
than a stale result. Model evidence described a network-show promotion, but that
evidence is not a verified transcript. Nick identified the segment as a replay.
No marked WAV/JSON clip exists in this session directory at inspection, so the
original audio cannot be replayed for a before/after classification comparison.

Prompt change: embedded promotional reads, including series/streaming/schedule
mentions during event coverage, stay program; uncertain standalone-versus-read
cases become unclear. Require contextual evidence for a self-contained spot.
No network-specific phrase blacklist or confidence threshold was added. Two-vote
confirmation is unchanged; overlapping windows can repeat a classification error.

Prior prompt preserved as prompt-sports-v1.txt. The worker reads the prompt only
at startup. Stop and restart automatic mode to load this revision. No new live
accuracy result is claimed; no audio uploaded as part of this change.

## False return during an MMA-themed advertisement

Nick reported TV playback returning during a commercial mentioning MMA.
At 2026-10-04T00:43:47–48Z, session
70223482-A910-4304-A435-65AA3E1FC796 produced two Program predictions.
The model described an official UFC social casino and then a sponsor with crowd
noise, inferring an embedded sponsorship segment. These descriptions are model
evidence, not independently verified transcripts. Routing requested TV at 00:43:48Z.

Prompt revision requires positive editorial event evidence for Program and
explicitly excludes sports topics, official sponsor status and crowd noise as
sufficient evidence. Embedded reads remain Program only with independent audible
editorial context; ambiguous sponsor-only excerpts are unclear. Standalone
sports-service ads and future-fight promos remain breaks. Two-result confirmation
is unchanged. Previous prompt preserved as prompt-sports-v2.txt.
New SHA256: 924467590beeace4981b3d6a800111fc22529042b1169b5228ba9e845fbdf109.
No replay evaluation has established improved accuracy yet. Each worker loads the
prompt at startup; stop/start Automatic to apply it immediately.


### Beginning-of-fight embedded read
Nick subsequently reported an unwanted mute for an announcer's promotion at
the beginning of a fight. Session 5E9DAF2F-373E-4E7B-8CAD-2A9C3E679E03
logged promo predictions at 00:50:14–16Z based on show names and network/streaming
information, then Program at 00:50:21–22Z for an introduction. These are model
descriptions, not independently verified transcripts. The prompt now explicitly
keeps embedded beginning-of-bout reads as Program when editorial context is
audible. Sponsor-only excerpts without independent replacement-spot evidence are
Unclear; lack of fight discussion does not establish a break. This complements
the sports-themed-ad exclusion rather than reversing it. Previous revision is
prompt-sports-v3.txt. Live accuracy remains unverified; restart the worker to load.
