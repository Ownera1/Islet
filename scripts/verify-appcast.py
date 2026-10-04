#!/usr/bin/env python3
"""Reject foreign/unsigned enclosures and verify locally available update archives."""
import base64
import pathlib
import plistlib
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
ROOT = pathlib.Path(__file__).resolve().parents[1]
PREFIX = 'https://github.com/Ownera1/agent-usage-notch/releases/download/'


def validate(feed, archives=None, expected_build=None):
    tree = ET.parse(feed)
    channel = tree.getroot().find('channel')
    assert channel is not None
    items = channel.findall('item')
    if expected_build is not None:
        assert items and items[0].findtext(SPARKLE + 'version') == str(expected_build), 'Wrong latest build'
    key = plistlib.loads((ROOT / 'boringNotch/Info.plist').read_bytes())['SUPublicEDKey']
    assert len(base64.b64decode(key, validate=True)) == 32
    versions = set()
    for item in items:
        build = item.findtext(SPARKLE + 'version')
        assert build and build not in versions, 'Missing or duplicate build'
        versions.add(build)
        assert item.find('enclosure') is not None, 'Missing full update archive'
        for enclosure in item.iter('enclosure'):
            url = enclosure.get('url', '')
            assert url.startswith(PREFIX), 'Foreign update URL'
            parts = urllib.parse.urlparse(url)
            assert not parts.query and not parts.fragment
            path_parts = parts.path.split('/')
            assert len(path_parts) == 7 and path_parts[-2].startswith('v'), 'Invalid release path'
            name = urllib.parse.unquote(path_parts[-1])
            assert '/' not in name and name not in ('', '.', '..'), 'Invalid asset name'
            signature = enclosure.get(SPARKLE + 'edSignature', '')
            assert len(base64.b64decode(signature, validate=True)) == 64, 'Missing update signature'
            assert int(enclosure.get('length', '0')) > 0, 'Missing update length'
            if archives is not None and (archive := pathlib.Path(archives) / name).is_file():
                assert archive.stat().st_size == int(enclosure.get('length'))
                subprocess.run(['swift', str(ROOT / 'scripts/verify-update-signature.swift'),
                                str(archive), signature, key], check=True)
    return len(items)


if __name__ == '__main__':
    count = validate(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None,
                     sys.argv[3] if len(sys.argv) > 3 else None)
    print(f'Validated appcast: {count} release(s)')
