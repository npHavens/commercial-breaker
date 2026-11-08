"""The app's macOS identity: changing it makes every user grant permissions again."""

import re
from pathlib import Path
import unittest


project = Path(__file__).resolve().parents[1] / 'CommercialBreaker.xcodeproj' / 'project.pbxproj'


class AppIdentityTests(unittest.TestCase):
    def setUp(self):
        self.text = project.read_text(encoding='utf-8')

    def settings(self, key):
        return re.findall(rf'^\s*{key} = ([^;]+);', self.text, re.MULTILINE)

    def test_debug_and_release_keep_the_granted_identity(self):
        # macOS ties microphone, system-audio and Accessibility grants to these values.
        self.assertEqual(self.settings('PRODUCT_BUNDLE_IDENTIFIER'), ['com.nohandsstack.skybox.audio-probe'] * 2)
        self.assertEqual(self.settings('DEVELOPMENT_TEAM'), ['SHL25NTZ48'] * 2)
        self.assertEqual(self.settings('CODE_SIGN_ENTITLEMENTS'), [])

    def test_app_file_carries_the_name_system_settings_shows(self):
        self.assertEqual(self.settings('PRODUCT_NAME'), ['"Commercial Breaker"'] * 2)


if __name__ == '__main__':
    unittest.main()
