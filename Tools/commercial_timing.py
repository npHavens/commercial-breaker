"""Conservative HLS cue timing; no stream URLs or credentials in the result."""

from datetime import datetime
import math
import re


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def classify_playback(playhead_ms, segments, sampled_at_ms, now_ms, max_age_ms=15000):
    """Return 'ad', 'program', or 'unknown' for a playback position.

    Inputs are UTC timestamps in milliseconds. Each segment is a dictionary
    containing start_ms, end_ms, and state ('ad', 'program', or 'unknown').
    The parser will supply finite, valid segment bounds with start_ms < end_ms.
    Segments may overlap across playlist discontinuities.

    Contract:
    - Intervals include their start and exclude their end.
    - Exactly one covering segment determines the state. Zero or multiple
      covering segments return unknown, even if overlapping states agree.
    - Missing/nonfinite timestamps, a snapshot from the future, or a snapshot
      older than max_age_ms return unknown. Exactly max_age_ms old is valid.
    - Do not mutate the input or change any playback state.
    """
    if not all(finite(value) for value in (playhead_ms, sampled_at_ms, now_ms, max_age_ms)):
        return 'unknown'
    if max_age_ms < 0 or not 0 <= now_ms - sampled_at_ms <= max_age_ms:
        return 'unknown'
    matches = [segment for segment in segments if segment['start_ms'] <= playhead_ms < segment['end_ms']]
    return matches[0]['state'] if len(matches) == 1 else 'unknown'


def parse_timeline(text):
    """Parse supported cue markers into UTC segment spans.

    Leading content, missing timestamps, and gaps remain unknown. Discontinuity
    requires a new clock anchor but does not itself end a marked break.
    Advertised break duration bounds a mute even if CUE-IN is missing.
    """
    segments = []
    cursor = None
    duration = None
    state = 'unknown'
    deadline = None
    remaining = None
    gap = False
    expected_next = None

    def positive_seconds(value):
        try:
            result = float(value)
            return result if math.isfinite(result) and 0 < result <= 900 else None
        except (ValueError, TypeError):
            return None

    for line in text.splitlines():
        if line.startswith('#EXT-X-PROGRAM-DATE-TIME:'):
            try:
                value = line.partition(':')[2].replace('Z', '+00:00')
                # Python 3.9 accepts microseconds, while this feed carries nanoseconds.
                value = re.sub(r'(T\d{2}:\d{2}:\d{2})\.(\d+)',
                               lambda match: match[1] + '.' + match[2][:6].ljust(6, '0'), value)
                date = datetime.fromisoformat(value)
                cursor = date.timestamp() * 1000 if date.tzinfo else None
                if cursor is not None and expected_next is not None:
                    if abs(cursor - expected_next) <= 1:
                        # Normalize sub-millisecond rounding across feed timestamp anchors.
                        cursor = expected_next
                    elif cursor < expected_next:
                        state, deadline, remaining = 'unknown', None, None
            except (ValueError, OverflowError, OSError):
                cursor = None
            expected_next = None
        elif line == '#EXT-X-DISCONTINUITY':
            # Ad splices change codecs/timestamps without changing CUE-OUT scope.
            expected_next, cursor = cursor, None
        elif line.startswith('#EXT-X-CUE-OUT:'):
            value = line.partition(':')[2]
            remaining = positive_seconds(value.removeprefix('DURATION='))
            state, deadline = ('ad' if remaining else 'unknown'), None
        elif line.startswith('#EXT-X-CUE-OUT-CONT:'):
            value = line.partition(':')[2]
            try:
                if '/' in value and '=' not in value:
                    elapsed_text, total_text = value.split('/', 1)
                else:
                    attrs = dict(part.split('=', 1) for part in value.split(',') if '=' in part)
                    elapsed_text, total_text = attrs['ElapsedTime'], attrs['Duration']
                elapsed, total = float(elapsed_text), positive_seconds(total_text)
                valid = total and math.isfinite(elapsed) and 0 <= elapsed < total
                remaining = total - elapsed if valid else None
            except (ValueError, KeyError):
                remaining = None
            state = 'ad' if remaining else 'unknown'
        elif line == '#EXT-X-CUE-IN':
            state, deadline, remaining = 'program', None, None
        elif line == '#EXT-X-GAP':
            gap = True
        elif line.startswith('#EXTINF:'):
            duration = positive_seconds(line.partition(':')[2].split(',')[0])
        elif line and not line.startswith('#'):
            if cursor is not None and duration is not None:
                end = cursor + duration * 1000
                if remaining is not None:
                    proposed = cursor + remaining * 1000
                    deadline = min(deadline, proposed) if deadline is not None else proposed
                effective = 'unknown' if gap else state
                if effective == 'ad':
                    if deadline is None or deadline <= cursor:
                        effective = 'unknown'
                    elif deadline < end:
                        segments.append({'start_ms': cursor, 'end_ms': deadline, 'state': 'ad'})
                        cursor, effective = deadline, 'unknown'
                segments.append({'start_ms': cursor, 'end_ms': end, 'state': effective})
                cursor = end
            else:
                cursor, state, deadline, expected_next = None, 'unknown', None, None
            duration, remaining, gap = None, None, False
    merged = []
    for segment in segments:
        if merged and merged[-1]['end_ms'] == segment['start_ms'] and merged[-1]['state'] == segment['state']:
            merged[-1]['end_ms'] = segment['end_ms']
        else:
            merged.append(dict(segment))
    return merged
