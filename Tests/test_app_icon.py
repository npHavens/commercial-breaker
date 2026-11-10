"""The app icon asset catalog: every macOS slot is filled at its pixel size, and the ad bulb is dark."""

import json
from pathlib import Path
import re
import struct
import unittest
import zlib


root = Path(__file__).resolve().parents[1]
project = root / 'CommercialBreaker.xcodeproj' / 'project.pbxproj'
iconset = root / 'MacAudioProbe' / 'Assets.xcassets' / 'AppIcon.appiconset'

# The ad bulb lit, as in the Scoreboard CB design's Blocking state.
LIT_BULB = (0xF0, 0x5A, 0x3C)


def read_png(path):
    """Width, height and rows of RGB(A) pixels from an 8-bit, non-interlaced PNG."""
    data = path.read_bytes()
    # The header chunk always comes first.
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'{path.name} is not a PNG')
    width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', data[16:29])
    offset, idat = 8, b''
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        if kind == b'IDAT':
            idat += data[offset + 8:offset + 8 + length]
        offset += 12 + length
    if depth != 8 or color not in (2, 6) or interlace:
        raise ValueError(f'{path.name}: expected 8-bit RGB or RGBA, not interlaced')
    channels = 4 if color == 6 else 3
    raw, stride, rows, previous = zlib.decompress(idat), width * channels, [], bytes(width * channels)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up, corner = previous[i], previous[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + left) & 0xFF
            elif kind == 2:
                line[i] = (line[i] + up) & 0xFF
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif kind == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                line[i] = (line[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 0xFF
        rows.append([tuple(line[x:x + channels]) for x in range(0, stride, channels)])
        previous = bytes(line)
    return width, height, rows


class AppIconTests(unittest.TestCase):
    def setUp(self):
        self.images = json.loads((iconset / 'Contents.json').read_text(encoding='utf-8'))['images']

    def test_both_configurations_use_the_catalog_icon(self):
        text = project.read_text(encoding='utf-8')
        names = re.findall(r'^\s*ASSETCATALOG_COMPILER_APPICON_NAME = ([^;]+);', text, re.MULTILINE)
        self.assertEqual(names, ['AppIcon'] * 2)

    def test_every_mac_slot_has_a_file_at_its_pixel_size(self):
        slots = {(image['size'], image['scale']) for image in self.images}
        self.assertEqual(slots, {(f'{p}x{p}', f'{s}x') for p in (16, 32, 128, 256, 512) for s in (1, 2)})
        for image in self.images:
            with self.subTest(image['filename']):
                self.assertEqual(image['idiom'], 'mac')
                points, scale = int(image['size'].split('x')[0]), int(image['scale'][0])
                width, height, _ = read_png(iconset / image['filename'])
                self.assertEqual((width, height), (points * scale, points * scale))

    def test_static_icon_shows_the_ad_bulb_dark(self):
        # Lit means blocking, so only the runtime Dock icon may show it. Figma's frames named
        # icon_*.png use the lit Blocking state; export the Watching state instead.
        for name in sorted({image['filename'] for image in self.images}):
            with self.subTest(name):
                _, _, rows = read_png(iconset / name)
                lit = [pixel for row in rows for pixel in row
                       if all(abs(a - b) <= 40 for a, b in zip(pixel, LIT_BULB))
                       and (len(pixel) == 3 or pixel[3] > 128)]
                self.assertEqual(lit, [], 'the ad bulb is lit')


if __name__ == '__main__':
    unittest.main()
