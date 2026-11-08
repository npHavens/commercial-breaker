"""Build settings that decide the app's macOS identity and how it runs."""

import re
from pathlib import Path
import unittest


project = Path(__file__).resolve().parents[1] / 'CommercialBreaker.xcodeproj' / 'project.pbxproj'


class AppIdentityTests(unittest.TestCase):
    def setUp(self):
        self.text = project.read_text(encoding='utf-8')

    def settings(self, key):
        # Xcode may quote a value when it rewrites the file; the quotes are not part of it.
        return [value.strip('"') for value in re.findall(rf'^\s*{key} = ([^;]+);', self.text, re.MULTILINE)]

    def test_debug_and_release_keep_the_granted_identity(self):
        # These feed the designated requirement macOS ties microphone, system-audio and
        # Accessibility grants to. It also names the signing certificate, which no project
        # setting pins. CI builds unsigned, so it cannot check that either.
        self.assertEqual(self.settings('PRODUCT_BUNDLE_IDENTIFIER'), ['com.nohandsstack.skybox.audio-probe'] * 2)
        self.assertEqual(self.settings('DEVELOPMENT_TEAM'), ['SHL25NTZ48'] * 2)
        self.assertEqual(self.settings('CODE_SIGN_STYLE'), ['Manual'] * 2)
        self.assertEqual(self.settings('CODE_SIGN_IDENTITY'), ['Apple Development'] * 2)

    def test_no_sdk_specific_override_of_these_settings(self):
        # Xcode writes these as "KEY[sdk=macosx*]", which would win over the plain key for macOS.
        for key in ('PRODUCT_BUNDLE_IDENTIFIER', 'DEVELOPMENT_TEAM', 'CODE_SIGN_STYLE', 'CODE_SIGN_IDENTITY',
                    'CODE_SIGN_ENTITLEMENTS', 'ENABLE_APP_SANDBOX', 'ENABLE_HARDENED_RUNTIME'):
            self.assertNotIn(f'{key}[', self.text)

    def test_app_stays_unsandboxed_without_entitlements(self):
        # The app launches its Node worker from the checkout, which a sandbox would block.
        self.assertEqual(self.settings('ENABLE_APP_SANDBOX'), ['NO'] * 2)
        self.assertEqual(self.settings('CODE_SIGN_ENTITLEMENTS'), [])
        # Hardened runtime would need a microphone entitlement this app does not have.
        self.assertNotIn('YES', self.settings('ENABLE_HARDENED_RUNTIME'))

    def test_name_and_version_match_across_configurations(self):
        # macOS displays the app by its file name, and the window shows this version.
        self.assertEqual(self.settings('PRODUCT_NAME'), ['Commercial Breaker'] * 2)
        versions = self.settings('MARKETING_VERSION')
        self.assertEqual(len(versions), 2)
        self.assertEqual(len(set(versions)), 1)


if __name__ == '__main__':
    unittest.main()
