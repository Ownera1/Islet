#!/usr/bin/env python3
"""Offline trust-boundary checks for feeds before publication."""
import base64
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify_appcast', pathlib.Path(__file__).with_name('verify-appcast.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AppcastTests(unittest.TestCase):
    def feed(self, url=None, signature=None, build='4'):
        return f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>{build}</sparkle:version><enclosure url="{url or module.PREFIX + 'v0.1.3/update.zip'}"
        sparkle:edSignature="{signature if signature is not None else base64.b64encode(bytes(64)).decode()}" length="10"/>
        </item></channel></rss>'''

    def validate(self, text, expected='4'):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'feed.xml'
            path.write_text(text)
            return module.validate(path, expected_build=expected)

    def test_own_release_and_expected_build(self):
        self.assertEqual(self.validate(self.feed()), 1)

    def test_foreign_feed_or_asset_is_rejected(self):
        for url in ['https://github.com/TheBoredTeam/boring.notch/releases/download/v1/update.zip',
                    module.PREFIX + 'v0.1.3/update.zip?redirect=foreign',
                    module.PREFIX + 'v0.1.3/a%2Fb.zip']:
            with self.subTest(url=url), self.assertRaises(AssertionError):
                self.validate(self.feed(url=url))

    def test_unsigned_or_wrong_build_is_rejected(self):
        for text in [self.feed(signature=''), self.feed(build='3'), '<rss><channel/></rss>']:
            with self.subTest(text=text), self.assertRaises(AssertionError):
                self.validate(text)


if __name__ == '__main__':
    unittest.main()
