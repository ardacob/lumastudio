#!/usr/bin/env python3
"""Generate the app icon without third-party image libraries."""

from pathlib import Path
from math import hypot
import struct
import zlib

SIZE = 1024
OUT = Path(__file__).parent / "AppIcon-1024.png"


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def rounded_square(x, y):
    radius = 215
    dx = max(0, abs(x - 512) - (416 - radius))
    dy = max(0, abs(y - 512) - (416 - radius))
    return max(0.0, min(1.0, radius - hypot(dx, dy)))


rows = []
for y in range(SIZE):
    row = bytearray([0])
    for x in range(SIZE):
        alpha = rounded_square(x, y)
        blend = 0.36 * x / SIZE + 0.64 * y / SIZE
        red = int(111 - 45 * blend)
        green = int(139 - 55 * blend)
        blue = int(245 - 10 * blend)
        # Two offset lens rings form a simple, recognizable editing mark.
        d1 = hypot(x - 455, y - 455)
        d2 = hypot(x - 570, y - 570)
        ring = 175 < d1 < 208 or 150 < d2 < 180
        center = hypot(x - 520, y - 520) < 55
        if ring or center:
            red, green, blue = 255, 255, 255
        row.extend((red, green, blue, int(alpha * 255)))
    rows.append(bytes(row))

raw = b"".join(rows)
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")
OUT.write_bytes(png)
print(OUT)
