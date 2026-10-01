#!/usr/bin/env python3
"""Pack PNG renditions into a standard ICNS container."""

from pathlib import Path
import struct
import sys

iconset = Path(sys.argv[1])
destination = Path(sys.argv[2])
renditions = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
body = bytearray()
for kind, name in renditions:
    data = (iconset / name).read_bytes()
    body += kind + struct.pack(">I", len(data) + 8) + data
destination.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
