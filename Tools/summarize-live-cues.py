"""Join local sound scores to user markers; never infer an ad from a score.

Usage: python3 Tools/summarize-live-cues.py SESSION_DIRECTORY
Writes cue-summary.json. Windows near a marker stay unassigned because clicks
are approximate. Unknown initial/game-change intervals stay unknown.
"""
import json
import math
import sys
from pathlib import Path


def assign_windows(events, scores, boundary_margin=5.0):
    if not math.isfinite(boundary_margin) or boundary_margin < 0:
        raise ValueError('Boundary margin must be finite and nonnegative')
    transitions = []
    for event in events:
        message = event.get('message', '')
        state = None
        if message.startswith('Marked Commercial started;'):
            state = 'commercial'
        elif message.startswith('Marked Football returned;'):
            state = 'football'
        elif message in ('Changed game', 'Capture session started', 'Capture session stopped'):
            state = 'unknown'
        if state is not None:
            stamp = event['uptime']
            if not math.isfinite(stamp):
                raise ValueError('Nonfinite marker time')
            transitions.append((stamp, state))
    transitions.sort(key=lambda item: item[0])
    assigned = []
    for score in scores:
        if score.get('event') != 'scores':
            continue
        start, end = score['startUptime'], score['endUptime']
        if not all(math.isfinite(x) for x in (start, end)) or end <= start:
            raise ValueError('Invalid score window')
        values = {name: score[name] for name in ('music', 'speech', 'crowd')}
        if not all(math.isfinite(x) and 0 <= x <= 1 for x in values.values()):
            raise ValueError('Invalid sound score')
        state = 'unknown'
        for stamp, label in transitions:
            if stamp <= start:
                state = label
            else:
                break
        # Exclude entire windows that touch the uncertain boundary region.
        near_marker = any(start <= stamp + boundary_margin and end >= stamp - boundary_margin
                          for stamp, _ in transitions)
        assigned.append(dict(score, markedState='boundary' if near_marker else state))
    return assigned


def summarize(events, scores):
    windows = assign_windows(events, scores)
    groups = {}
    for state in ('football', 'commercial', 'unknown', 'boundary'):
        members = [w for w in windows if w['markedState'] == state]
        groups[state] = {'windows': len(members)}
        if members:
            groups[state]['meanScores'] = {
                name: sum(w[name] for w in members) / len(members)
                for name in ('music', 'speech', 'crowd')
            }
            groups[state]['musicScoreAtLeastHalfWindows'] = sum(w['music'] >= 0.5 for w in members)
    return {'boundaryMarginSeconds': 5, 'groups': groups, 'windows': windows,
            'note': 'States come only from approximate user markers. Overlapping windows are correlated; scores and counts are not commercial detection accuracy.'}


def read_events(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main():
    if len(sys.argv) != 2:
        raise ValueError('Usage: summarize-live-cues.py SESSION_DIRECTORY')
    folder = Path(sys.argv[1])
    result = summarize(read_events(folder / 'events.jsonl'), read_events(folder / 'live-cues.jsonl'))
    if not result['windows']:
        raise ValueError('No sound-score windows in this session')
    output = folder / 'cue-summary.json'
    temporary = output.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    temporary.replace(output)
    print(json.dumps(result['groups'], indent=2))
    print(f'Saved {output}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(str(error))
