import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / 'Tools/summarize-live-cues.py'
spec = importlib.util.spec_from_file_location('cue_labels', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def marker(time, message):
    return {'uptime': time, 'message': message}


def window(start, end, music=0.8):
    return {'event': 'scores', 'startUptime': start, 'endUptime': end,
            'music': music, 'speech': 0.3, 'crowd': 0.2}


class MarkerLabels(unittest.TestCase):
    def test_existing_markers_label_intervals_without_an_extra_button(self):
        events = [marker(10, 'Marked Football returned; collecting ten seconds after marker'),
                  marker(40, 'Marked Commercial started; collecting ten seconds after marker'),
                  marker(70, 'Changed game'), marker(100, 'Marked Football returned; collecting')]
        times = [(1, 4), (8, 11), (20, 23), (37, 40), (50, 53), (80, 83), (110, 113)]
        result = module.assign_windows(events, [window(*time) for time in times])
        self.assertEqual([w['markedState'] for w in result],
                         ['unknown', 'boundary', 'football', 'boundary', 'commercial', 'unknown', 'football'])

    def test_stop_and_duplicate_markers_do_not_create_fake_state(self):
        events = [marker(0, 'Marked Football returned; collecting'),
                  marker(30, 'Marked Football returned; collecting'), marker(60, 'Capture session stopped')]
        result = module.assign_windows(events, [window(20, 23), window(40, 43), window(70, 73)])
        self.assertEqual([w['markedState'] for w in result], ['football', 'football', 'unknown'])

    def test_window_crossing_boundary_is_excluded_even_with_zero_margin(self):
        result = module.assign_windows([marker(10, 'Marked Commercial started; collecting')],
                                       [window(9, 12)], boundary_margin=0)
        self.assertEqual(result[0]['markedState'], 'boundary')

    def test_invalid_scores_fail_instead_of_polluting_averages(self):
        with self.assertRaises(ValueError):
            module.summarize([], [window(0, 3, float('nan'))])


if __name__ == '__main__':
    unittest.main()
