"""The app icon asset catalog: every macOS slot is filled at its pixel size on a transparent
canvas, and the ad bulb is dark."""

from functools import lru_cache
import json
from pathlib import Path
import struct
import unittest
import zlib


iconset = Path(__file__).resolve().parents[1] / 'MacAudioProbe' / 'Assets.xcassets' / 'AppIcon.appiconset'

# The ad bulb lit, as in the Scoreboard CB design's Blocking state.
LIT_BULB = (0xF0, 0x5A, 0x3C)


@lru_cache(maxsize=None)
def read_png(path):
    """Width, height and rows of RGBA pixels. Reads only the 8-bit, non-interlaced RGBA PNGs
    the icons are exported as; anything else is this reader's limit, not a broken icon."""
    data = path.read_bytes()
    # The header chunk always comes first.
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'{path.name} is not a PNG')
    width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', data[16:29])
    if depth != 8 or color != 6 or interlace:
        raise ValueError(f'{path.name}: this test reads only 8-bit, non-interlaced RGBA PNGs')
    offset, idat = 8, b''
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        if kind == b'IDAT':
            idat += data[offset + 8:offset + 8 + length]
        offset += 12 + length
    raw, stride, rows, previous = zlib.decompress(idat), width * 4, [], bytes(width * 4)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind > 4:
            raise ValueError(f'{path.name}: unknown filter type {kind} on row {y}')
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up, corner = previous[i], previous[i - 4] if i >= 4 else 0
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
        rows.append([tuple(line[x:x + 4]) for x in range(0, stride, 4)])
        previous = bytes(line)
    return width, height, rows


class AppIconTests(unittest.TestCase):
    def setUp(self):
        self.images = json.loads((iconset / 'Contents.json').read_text(encoding='utf-8'))['images']
        self.files = sorted({iconset / image['filename'] for image in self.images})

    def test_every_mac_slot_has_one_file_at_its_pixel_size(self):
        slots = sorted((image['size'], image['scale']) for image in self.images)
        self.assertEqual(slots, sorted((f'{p}x{p}', f'{s}x') for p in (16, 32, 128, 256, 512) for s in (1, 2)))
        for image in self.images:
            with self.subTest(image['filename']):
                self.assertEqual(image['idiom'], 'mac')
                points, scale = int(image['size'].split('x')[0]), int(image['scale'][0])
                width, height, _ = read_png(iconset / image['filename'])
                self.assertEqual((width, height), (points * scale, points * scale))

    def test_canvas_around_the_plate_is_transparent(self):
        # The plate sits inside macOS's icon-grid margin. Figma's PNG export of a component in
        # a component set paints the set's white panel behind it, which would show as a white
        # square in the Dock, so the icons are rendered from SVG exports with that panel removed.
        for path in self.files:
            with self.subTest(path.name):
                width, height, rows = read_png(path)
                corners = [rows[0][0], rows[0][width - 1], rows[height - 1][0], rows[height - 1][width - 1]]
                self.assertEqual([pixel[3] for pixel in corners], [0] * 4)

    def test_static_icon_shows_the_ad_bulb_dark(self):
        # Lit means blocking, so only the runtime Dock icon may show it. Figma's frames named
        # icon_*.png use the lit Blocking state; export the Watching state instead.
        for path in self.files:
            with self.subTest(path.name):
                _, _, rows = read_png(path)
                lit = [pixel for row in rows for pixel in row
                       if pixel[3] > 128 and all(abs(a - b) <= 40 for a, b in zip(pixel, LIT_BULB))]
                self.assertEqual(lit, [], 'the ad bulb is lit')


if __name__ == '__main__':
    unittest.main()
