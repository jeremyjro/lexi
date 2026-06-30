#!/usr/bin/env python3
"""Generate Lexi's app icon (the "Aurora" brand identity).

This renders every required size of the macOS iconset as a PNG using only the
Python standard library (no Pillow / Cairo needed). The artwork is a rounded
"squircle" filled with Lexi's signature Aurora gradient (marigold -> coral ->
violet) and a white "L + spark" monogram that matches `LexiMark` in
`Sources/Lexi/DesignSystem/LexiWordmark.swift`.

Regenerating the icon (run on macOS to produce the .icns):

    python3 scripts/generate_app_icon.py          # writes assets/AppIcon.iconset/*.png
    iconutil -c icns assets/AppIcon.iconset -o assets/Lexi.icns

The PNG step is platform-independent and can be run anywhere with Python 3.9+.
The `iconutil` step is macOS-only (it is part of the Xcode command line tools).
"""

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "assets" / "AppIcon.iconset"

SPECS = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

# Aurora palette (sRGB). Mirrors LexiTheme.swift.
MARIGOLD = (0xF2, 0xA0, 0x3D)
CORAL = (0xFF, 0x6B, 0x6B)
VIOLET = (0x7C, 0x5C, 0xFF)
INK = (0x1F, 0x1B, 0x16)
WHITE = (0xFF, 0xFF, 0xFF)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = zlib.crc32(kind + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    data += png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += png_chunk(b"IEND", b"")
    path.write_bytes(data)


def mix(a, b, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def sdf_round_rect(px, py, cx, cy, hx, hy, r) -> float:
    """Signed distance to a rounded rectangle (negative inside)."""
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def coverage(distance: float, aa: float) -> float:
    """Anti-aliased coverage from a signed distance (negative == inside)."""
    return max(0.0, min(1.0, 0.5 - distance / aa))


def render(size: int) -> bytes:
    pixels = bytearray(size * size * 4)
    s = float(size)
    aa = max(1.0, s / 512.0)

    bg_radius = 0.225 * s
    bg_cx = bg_cy = s / 2.0
    bg_half = s / 2.0

    # "L + spark" monogram geometry (matches LexiMark in Swift).
    stem_cx, stem_cy, stem_hx, stem_hy = 0.385 * s, 0.50 * s, 0.085 * s, 0.34 * s
    foot_cx, foot_cy, foot_hx, foot_hy = 0.52 * s, 0.755 * s, 0.22 * s, 0.085 * s
    glyph_r = 0.05 * s
    dot_cx, dot_cy, dot_r = 0.70 * s, 0.26 * s, 0.085 * s

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4
            px, py = x + 0.5, y + 0.5

            bg_alpha = coverage(sdf_round_rect(px, py, bg_cx, bg_cy, bg_half, bg_half, bg_radius), aa)
            if bg_alpha <= 0:
                pixels[idx:idx + 4] = b"\x00\x00\x00\x00"
                continue

            # Aurora gradient along the main diagonal: marigold -> coral -> violet.
            t = (px + py) / (2.0 * s)
            if t < 0.5:
                base = mix(MARIGOLD, CORAL, t * 2.0)
            else:
                base = mix(CORAL, VIOLET, (t - 0.5) * 2.0)

            # Gentle deepening toward the bottom for dimensionality.
            base = mix(base, INK, max(0.0, py / s - 0.55) * 0.30)

            # Soft warm highlight from the upper-left.
            highlight = max(0.0, 1.0 - math.hypot(px - 0.24 * s, py - 0.18 * s) / (0.62 * s))
            base = mix(base, WHITE, highlight * 0.20)

            # White monogram with anti-aliased edges.
            stem_c = coverage(sdf_round_rect(px, py, stem_cx, stem_cy, stem_hx, stem_hy, glyph_r), aa)
            foot_c = coverage(sdf_round_rect(px, py, foot_cx, foot_cy, foot_hx, foot_hy, glyph_r), aa)
            dot_c = coverage(math.hypot(px - dot_cx, py - dot_cy) - dot_r, aa)
            glyph_alpha = max(stem_c, foot_c, dot_c)
            if glyph_alpha > 0:
                base = mix(base, WHITE, 0.96 * glyph_alpha)

            pixels[idx] = base[0]
            pixels[idx + 1] = base[1]
            pixels[idx + 2] = base[2]
            pixels[idx + 3] = round(bg_alpha * 255)

    return bytes(pixels)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    for size, filename in SPECS:
        write_png(ICONSET / filename, size, size, render(size))
    print(f"Generated {ICONSET}")
    print("On macOS, bundle the .icns with:")
    print("  iconutil -c icns assets/AppIcon.iconset -o assets/Lexi.icns")


if __name__ == "__main__":
    main()
