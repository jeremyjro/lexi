#!/usr/bin/env python3
import math
import os
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


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def rounded_rect_alpha(x: float, y: float, size: int, radius: float) -> float:
    cx = min(max(x, radius), size - radius)
    cy = min(max(y, radius), size - radius)
    d = math.hypot(x - cx, y - cy)
    return max(0.0, min(1.0, radius + 0.8 - d))


def in_rect(x: int, y: int, left: int, top: int, right: int, bottom: int) -> bool:
    return left <= x < right and top <= y < bottom


def render(size: int) -> bytes:
    pixels = bytearray(size * size * 4)
    radius = size * 0.22
    bg_a = (54, 91, 255)
    bg_b = (155, 79, 255)
    bg_c = (17, 24, 39)

    stem_left = round(size * 0.29)
    stem_right = round(size * 0.43)
    stem_top = round(size * 0.23)
    stem_bottom = round(size * 0.75)
    foot_left = stem_left
    foot_right = round(size * 0.72)
    foot_top = round(size * 0.62)
    foot_bottom = round(size * 0.76)
    dot_cx = size * 0.67
    dot_cy = size * 0.32
    dot_r = size * 0.07

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4
            rr = rounded_rect_alpha(x + 0.5, y + 0.5, size, radius)
            if rr <= 0:
                pixels[idx:idx + 4] = b"\x00\x00\x00\x00"
                continue

            diagonal = (x + y) / max(1, (size - 1) * 2)
            vertical = y / max(1, size - 1)
            base = mix(bg_a, bg_b, diagonal)
            base = mix(base, bg_c, max(0.0, vertical - 0.50) * 0.55)

            highlight = max(0.0, 1.0 - math.hypot(x - size * 0.22, y - size * 0.17) / (size * 0.65))
            base = mix(base, (255, 255, 255), highlight * 0.18)

            glyph = in_rect(x, y, stem_left, stem_top, stem_right, stem_bottom) or in_rect(x, y, foot_left, foot_top, foot_right, foot_bottom)
            dot = math.hypot(x - dot_cx, y - dot_cy) <= dot_r
            if glyph or dot:
                base = mix(base, (255, 255, 255), 0.92)

            pixels[idx] = base[0]
            pixels[idx + 1] = base[1]
            pixels[idx + 2] = base[2]
            pixels[idx + 3] = round(rr * 255)

    return bytes(pixels)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    for size, filename in SPECS:
        write_png(ICONSET / filename, size, size, render(size))
    print(f"Generated {ICONSET}")


if __name__ == "__main__":
    main()
