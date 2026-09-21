#!/usr/bin/env python3
"""Renders Brim's artwork with no image libraries.

  Brim/Assets.xcassets/AppIcon.appiconset/icon-1024.png   full-bleed app icon
  docs/icon.png                                           512px rounded tile for the README

Same geometry as `BrimMark` in SignInView.swift: a blue gradient tile, a white
dome (top half of a circle) and a white brim bar, centered. Apple masks the app
icon's corners itself, so that one is full-bleed and opaque. Run from anywhere:

    python3 docs/make-icon.py
"""
import math, struct, zlib, pathlib

TOP_LEFT = (0x2E, 0xB4, 0xFF)
BOTTOM_RIGHT = (0x00, 0x5C, 0xB1)

# Fractions of the tile. The dome + brim bounding box is centered.
DOME = (0.5, 0.58, 0.27)               # cx, cy, r
BRIM = (0.5, 0.635, 0.72, 0.115)       # cx, cy, w, h
CORNER = 0.2237                        # iOS-like corner radius for the README tile


def smooth(d, aa=1.0):
    """Coverage from a signed distance in pixels (negative = inside)."""
    if d <= -aa: return 1.0
    if d >= aa: return 0.0
    t = (d + aa) / (2 * aa)
    return 1.0 - (t * t * (3 - 2 * t))


def render(size, rounded):
    cx, cy, r = (v * size for v in DOME)
    bx, by, bw, bh = (v * size for v in BRIM)
    rad = bh / 2
    hx = bw / 2 - rad
    corner = CORNER * size
    half = size / 2
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            t = (x + y) / (2 * size)
            px, py = x + 0.5, y + 0.5
            dome = max(math.hypot(px - cx, py - cy) - r, py - cy)
            brim = math.hypot(max(abs(px - bx) - hx, 0.0), py - by) - rad
            cov = max(smooth(dome), smooth(brim))
            rgb = [a + (b - a) * t for a, b in zip(TOP_LEFT, BOTTOM_RIGHT)]
            rgb = [c + (255 - c) * cov for c in rgb]
            row += bytes(int(c + 0.5) for c in rgb)
            if rounded:
                qx, qy = abs(px - half) - (half - corner), abs(py - half) - (half - corner)
                d = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - corner
                row.append(int(smooth(d) * 255 + 0.5))
        rows.append(bytes(row))
    return b"".join(rows)


def png(size, rounded):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    color_type = 6 if rounded else 2
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, color_type, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(render(size, rounded), 9)) + chunk(b"IEND", b""))


root = pathlib.Path(__file__).resolve().parent.parent
for path, size, rounded in [
    (root / "Brim/Assets.xcassets/AppIcon.appiconset/icon-1024.png", 1024, False),
    (root / "docs/icon.png", 512, True),
]:
    data = png(size, rounded)
    path.write_bytes(data)
    print(f"wrote {path.relative_to(root)} ({len(data)} bytes)")
