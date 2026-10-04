"""Replay a fixed exploratory break-start rule. Never controls playback.

Thresholds are an explicit hypothesis, not learned parameters or calibrated
probabilities. Markers are used only to review emitted candidates, not to trigger
or tune them. Input is a reviewed cue-summary JSON from summarize-live-cues.py.
"""
import json
import math
import sys
from collections import deque
from pathlib import Path

RULE = {
    'historySeconds': 30, 'minimumBaselineSeconds': 15,
    'musicMinimum': 0.5, 'musicRiseMinimum': 0.15,
    'crowdBaselineMinimum': 0.08, 'crowdMaximum': 0.04,
    'crowdFractionMaximum': 0.5, 'confirmationWindows': 2,
    'cooldownSeconds': 30, 'maximumWindowStepSeconds': 3,
}


def candidates(windows):
    history = deque()
    emitted = []
    previous = None
    last_emitted = -math.inf
    for current in windows:
        start, end = current['startUptime'], current['endUptime']
        if not all(math.isfinite(x) for x in (start, end)) or end <= start:
            raise ValueError('Invalid score timestamp')
        if any(not math.isfinite(current[name]) or not 0 <= current[name] <= 1
               for name in ('music', 'crowd')):
            raise ValueError('Invalid score')
        if previous and (current['context'] != previous['context']
                         or end <= previous['endUptime']
                         or end - previous['endUptime'] > RULE['maximumWindowStepSeconds']):
            history.clear()
            last_emitted = -math.inf
        previous = current
        history.append(current)
        while history and end - history[0]['endUptime'] > RULE['historySeconds']:
            history.popleft()
        recent = list(history)[-RULE['confirmationWindows']:]
        if len(recent) < RULE['confirmationWindows']:
            continue
        # Exclude overlapping evidence: baseline ends before confirmation begins.
        baseline = [w for w in history if w['endUptime'] <= recent[0]['startUptime']]
        if not baseline or baseline[-1]['endUptime'] - baseline[0]['startUptime'] < RULE['minimumBaselineSeconds']:
            continue
        base_music = sum(w['music'] for w in baseline) / len(baseline)
        base_crowd = sum(w['crowd'] for w in baseline) / len(baseline)
        eligible = base_crowd >= RULE['crowdBaselineMinimum'] and all(
            w['music'] >= RULE['musicMinimum']
            and w['music'] - base_music >= RULE['musicRiseMinimum']
            and w['crowd'] <= RULE['crowdMaximum']
            and w['crowd'] <= base_crowd * RULE['crowdFractionMaximum'] for w in recent)
        if eligible and end - last_emitted >= RULE['cooldownSeconds']:
            emitted.append({'detectedAtUptime': end, 'evidenceStartUptime': recent[0]['startUptime'],
                            'context': current['context'], 'baselineMusic': base_music,
                            'baselineCrowd': base_crowd, 'music': current['music'],
                            'crowd': current['crowd'],
                            'reviewedState': current.get('markedState', 'unknown')})
            last_emitted = end
    return emitted


def main():
    if len(sys.argv) != 3:
        raise ValueError('Usage: evaluate-cue-candidates.py REVIEWED_SUMMARY OUTPUT_JSON')
    data = json.loads(Path(sys.argv[1]).read_text())
    result = {'rule': RULE, 'candidates': candidates(data['windows']),
              'note': 'Exploratory fixed rule on previously inspected data. No held-out accuracy claim; click times and interval labels are approximate. No return detector or playback control.'}
    Path(sys.argv[2]).write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(str(error))
