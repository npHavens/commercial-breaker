import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('candidates', Path(__file__).resolve().parents[2] / 'Tools/evaluate-cue-candidates.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def window(end, music=.1, crowd=.2, context=1):
    return dict(startUptime=end-3, endUptime=end, music=music, crowd=crowd, context=context)


def baseline():
    return [window(i*1.5+3) for i in range(16)]


class Candidates(unittest.TestCase):
    def test_requires_both_cues_and_persistence(self):
        before = baseline()
        self.assertEqual(m.candidates(before+[window(27,.8,.01)]), [])
        self.assertEqual(len(m.candidates(before+[window(27,.8,.01),window(28.5,.8,.01)])), 1)
        self.assertEqual(m.candidates(before+[window(27,.8,.2),window(28.5,.8,.2)]), [])
        self.assertEqual(m.candidates(before+[window(27,.1,.01),window(28.5,.1,.01)]), [])

    def test_game_change_and_gap_erase_previous_evidence(self):
        for tail in [[window(27,.8,.01,2),window(28.5,.8,.01,2)],
                     [window(90,.8,.01),window(91.5,.8,.01)]]:
            self.assertEqual(m.candidates(baseline()+tail), [])

    def test_sustained_music_is_not_repeated_trigger(self):
        tail = [window(27+i*1.5,.8,.01) for i in range(10)]
        self.assertEqual(len(m.candidates(baseline()+tail)), 1)

    def test_marker_state_cannot_change_predictions(self):
        data = baseline()+[window(27,.8,.01),window(28.5,.8,.01)]
        a = m.candidates([dict(w,markedState='football') for w in data])
        b = m.candidates([dict(w,markedState='commercial') for w in data])
        self.assertEqual([x['detectedAtUptime'] for x in a], [x['detectedAtUptime'] for x in b])

    def test_bad_score_is_error(self):
        with self.assertRaises(ValueError): m.candidates([window(3,float('nan'))])


if __name__ == '__main__': unittest.main()
