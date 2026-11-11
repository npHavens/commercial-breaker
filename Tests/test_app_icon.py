"""The app icon asset catalog: every macOS slot is filled at its pixel size, the plate sits inside a
transparent margin, and the ad bulb is dark. Tools/app-icon/render.sh makes the images."""

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
    """Width, height and one bytes object of RGBA values per row. Reads only the 8-bit,
    non-interlaced RGBA PNGs render.sh writes; anything else is this reader's limit, not a
    broken icon, so re-render rather than optimize the files."""
    data = path.read_bytes()
    # The header chunk always comes first.
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'{path.name} is not a PNG')
    width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', data[16:29])
    if depth != 8 or color != 6 or interlace:
        raise ValueError(f'{path.name}: this test reads only 8-bit, non-interlaced RGBA PNGs')
    offset, chunks = 8, []
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        if kind == b'IDAT':
            chunks.append(data[offset + 8:offset + 8 + length])
        offset += 12 + length
    raw, stride, rows, previous = zlib.decompress(b''.join(chunks)), width * 4, [], bytes(width * 4)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind > 4:
            raise ValueError(f'{path.name}: unknown filter type {kind} on row {y}')
        for i in range(stride if kind else 0):
            left = line[i - 4] if i >= 4 else 0
            up, corner = previous[i], previous[i - 4] if i >= 4 else 0
            if kind == 1:
                line[i] = (line[i] + left) & 0xFF
            elif kind == 2:
                line[i] = (line[i] + up) & 0xFF
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            else:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                line[i] = (line[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 0xFF
        previous = bytes(line)
        rows.append(previous)
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

    def test_plate_sits_inside_a_transparent_margin(self):
        # macOS draws app icons inside a margin of about 10% (the 1024 art's plate is 824 px), so
        # a full-bleed icon looks oversized next to others. Figma's PNG export of a component in
        # a component set also paints the set's white panel across the whole canvas. Either
        # fills this band, which is 5/64 of the width (1 px at 16 px, 80 px at 1024 px).
        for path in self.files:
            with self.subTest(path.name):
                width, height, rows = read_png(path)
                band = max(1, width * 5 // 64)
                opaque = [(x, y) for y in range(height) for x in range(width)
                          if (min(x, y, width - 1 - x, height - 1 - y) < band) and rows[y][x * 4 + 3]]
                self.assertEqual(opaque[:5], [], f'the outer {band} px are not transparent')

    def test_static_icon_shows_the_ad_bulb_dark(self):
        # Lit means blocking, so only the runtime Dock icon may show it. Figma's frames named
        # icon_*.png use the lit Blocking state; render.sh uses the Watching state instead. The
        # small sizes are pixel-snapped, so even at 16 px a lit bulb is one exact #F05A3C pixel.
        for path in self.files:
            with self.subTest(path.name):
                _, _, rows = read_png(path)
                lit = [row[x:x + 4] for row in rows for x in range(0, len(row), 4)
                       if row[x + 3] > 128 and all(abs(row[x + i] - LIT_BULB[i]) <= 40 for i in range(3))]
                self.assertEqual(lit[:5], [], 'the ad bulb is lit')


if __name__ == '__main__':
    unittest.main()
