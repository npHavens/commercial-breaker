"""Playback classification and HLS marker boundary checks."""

import importlib.util
from pathlib import Path
import unittest


path = Path(__file__).resolve().parents[1] / 'Tools' / 'commercial_timing.py'
spec = importlib.util.spec_from_file_location('commercial_timing', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CommercialTimingTests(unittest.TestCase):
    def setUp(self):
        self.segments = [
            {'start_ms': 1000, 'end_ms': 2000, 'state': 'program'},
            {'start_ms': 2000, 'end_ms': 3000, 'state': 'ad'},
            {'start_ms': 3000, 'end_ms': 4000, 'state': 'program'},
        ]

    def classify(self, playhead, **changes):
        args = dict(playhead_ms=playhead, segments=self.segments,
                    sampled_at_ms=10000, now_ms=11000)
        args.update(changes)
        return module.classify_playback(**args)

    def test_exact_boundaries_and_delayed_playback(self):
        for playhead, expected in ((999, 'unknown'), (1000, 'program'),
                                   (1999, 'program'), (2000, 'ad'),
                                   (2999, 'ad'), (3000, 'program'), (4000, 'unknown')):
            with self.subTest(playhead=playhead):
                self.assertEqual(self.classify(playhead), expected)

    def test_stale_and_future_snapshots_do_not_classify(self):
        self.assertEqual(self.classify(2500, now_ms=25000), 'ad')
        self.assertEqual(self.classify(2500, now_ms=25001), 'unknown')
        self.assertEqual(self.classify(2500, now_ms=9999), 'unknown')

    def test_invalid_clock_values_do_not_classify(self):
        for field in ('playhead_ms', 'sampled_at_ms', 'now_ms'):
            for invalid in (None, float('nan'), float('inf'), -float('inf')):
                with self.subTest(field=field, invalid=invalid):
                    self.assertEqual(self.classify(2500, **{field: invalid}), 'unknown')

    def test_gaps_unknown_segments_and_overlaps_are_unknown(self):
        self.assertEqual(self.classify(2500, segments=[]), 'unknown')
        unknown = [{'start_ms': 2000, 'end_ms': 3000, 'state': 'unknown'}]
        self.assertEqual(self.classify(2500, segments=unknown), 'unknown')
        for state in ('ad', 'program'):
            overlapping = self.segments + [{'start_ms': 2400, 'end_ms': 2600, 'state': state}]
            self.assertEqual(self.classify(2500, segments=overlapping), 'unknown')

    def test_input_is_not_mutated(self):
        before = [dict(segment) for segment in self.segments]
        self.classify(2500)
        self.assertEqual(self.segments, before)


class TimelineTests(unittest.TestCase):
    def parse(self, body):
        return module.parse_timeline('#EXTM3U\n#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:00Z\n' + body)

    def test_cue_out_and_in_and_unknown_leading_content(self):
        segments = self.parse('#EXTINF:6,\na.ts\n#EXT-X-CUE-OUT:12\n#EXTINF:6,\nb.ts\n'
                              '#EXTINF:6,\nc.ts\n#EXT-X-CUE-IN\n#EXTINF:6,\nd.ts\n')
        self.assertEqual([s['state'] for s in segments], ['unknown', 'ad', 'program'])
        self.assertEqual(segments[1]['start_ms'], segments[0]['end_ms'])
        self.assertEqual(segments[2]['start_ms'] - segments[1]['start_ms'], 12000)

    def test_missing_cue_in_expires_inside_segment(self):
        segments = self.parse('#EXT-X-CUE-OUT:8\n#EXTINF:6,\na.ts\n#EXTINF:6,\nb.ts\n#EXTINF:6,\nc.ts\n')
        self.assertEqual([s['state'] for s in segments], ['ad', 'unknown'])
        self.assertEqual(segments[0]['end_ms'] - segments[0]['start_ms'], 8000)

    def test_continuation_recovers_a_break_that_started_before_the_window(self):
        for marker in ('ElapsedTime=54,Duration=60,SCTE35=opaque==', '54/60'):
            segments = self.parse(f'#EXT-X-CUE-OUT-CONT:{marker}\n#EXTINF:6,\na.ts\n#EXTINF:6,\nb.ts\n')
            self.assertEqual([s['state'] for s in segments], ['ad', 'unknown'])

    def test_discontinuity_requires_a_new_clock_and_state(self):
        segments = self.parse('#EXT-X-CUE-OUT:60\n#EXTINF:6,\na.ts\n#EXT-X-DISCONTINUITY\n'
                              '#EXTINF:6,\nb.ts\n#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:20Z\n'
                              '#EXTINF:6,\nc.ts\n#EXT-X-CUE-IN\n#EXTINF:6,\nd.ts\n')
        self.assertEqual([s['state'] for s in segments], ['ad', 'unknown', 'program'])
        self.assertEqual(segments[1]['start_ms'] - segments[0]['start_ms'], 20000)

    def test_invalid_durations_and_gap_never_produce_ad_state(self):
        for duration in ('nan', 'inf', '-2', '0', '901', 'nonsense'):
            segments = self.parse(f'#EXT-X-CUE-OUT:{duration}\n#EXTINF:6,\na.ts\n')
            self.assertEqual(segments[0]['state'], 'unknown')
        segments = self.parse('#EXT-X-CUE-OUT:60\n#EXT-X-GAP\n#EXTINF:6,\na.ts\n')
        self.assertEqual(segments[0]['state'], 'unknown')

    def test_missing_date_and_naive_date_do_not_guess_utc(self):
        for prefix in ('', '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:00\n'):
            self.assertEqual(module.parse_timeline(prefix + '#EXT-X-CUE-OUT:60\n#EXTINF:6,\na.ts\n'), [])

    def test_feed_nanosecond_dates_and_short_fractional_dates_are_supported(self):
        for fraction in ('326999992', '3', '326999'):
            text = (f'#EXT-X-PROGRAM-DATE-TIME:2026-09-19T23:51:35.{fraction}Z\n'
                    '#EXT-X-CUE-OUT:6\n#EXTINF:6,\na.ts\n')
            spans = module.parse_timeline(text)
            self.assertEqual(len(spans), 1)
            self.assertEqual(spans[0]['state'], 'ad')
            self.assertEqual(spans[0]['end_ms'] - spans[0]['start_ms'], 6000)

    def test_break_spanning_multiple_ad_splices_stays_muted_until_cue_in(self):
        text = '#EXTM3U\n#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:00.000000001Z\n#EXT-X-CUE-OUT:180\n'
        for second in (0, 30, 60, 90, 120, 150):
            if second:
                minute, sec = divmod(second, 60)
                text += (f'#EXT-X-DISCONTINUITY\n#EXT-X-PROGRAM-DATE-TIME:'
                         f'2026-09-19T21:{minute:02}:{sec:02}.000000001Z\n')
            text += '#EXTINF:5,\nsegment.ts\n' * 6
        text += ('#EXT-X-DISCONTINUITY\n#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:03:00Z\n'
                 '#EXT-X-CUE-IN\n#EXTINF:6,\nprogram.ts\n')
        spans = module.parse_timeline(text)
        self.assertEqual([span['state'] for span in spans], ['ad', 'program'])
        self.assertEqual(spans[0]['end_ms'] - spans[0]['start_ms'], 180000)
        for offset in (0, 30000, 90000, 179999):
            self.assertEqual(module.classify_playback(spans[0]['start_ms'] + offset, spans, 0, 0), 'ad')
        self.assertEqual(module.classify_playback(spans[0]['start_ms'] + 180000, spans, 0, 0), 'program')

    def test_splices_do_not_extend_the_original_break_deadline(self):
        spans = self.parse('#EXT-X-CUE-OUT:30\n#EXTINF:30,\na.ts\n#EXT-X-DISCONTINUITY\n'
                           '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:30Z\n#EXTINF:30,\nb.ts\n')
        self.assertEqual([span['state'] for span in spans], ['ad', 'unknown'])

    def test_backwards_clock_at_splice_does_not_reuse_ad_scope(self):
        spans = self.parse('#EXT-X-CUE-OUT:180\n#EXTINF:30,\na.ts\n#EXT-X-DISCONTINUITY\n'
                           '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T20:59:00Z\n#EXTINF:30,\nb.ts\n')
        self.assertEqual([span['state'] for span in spans], ['ad', 'unknown'])

    def test_submillisecond_anchor_rounding_does_not_split_a_break(self):
        spans = self.parse('#EXT-X-CUE-OUT:60\n#EXTINF:30,\na.ts\n#EXT-X-DISCONTINUITY\n'
                           '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T21:00:30.000001Z\n#EXTINF:30,\nb.ts\n')
        self.assertEqual(len(spans), 1)
        self.assertEqual(spans[0]['state'], 'ad')
        self.assertEqual(spans[0]['end_ms'] - spans[0]['start_ms'], 60000)


if __name__ == '__main__':
    unittest.main()
