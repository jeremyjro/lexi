#!/usr/bin/env python3
"""Render Lexi's blended brand-direction mockup.

This script produces:

    docs/brand/direction_blend.png

The mockup reflects the final blended direction:

- warm cream canvas
- near-black ink
- one warm amber accent only
- generous whitespace
- restrained shadows
- refined serif wordmark

Pillow is used when available. If it is not installed, the script exits with a
clear error message rather than silently producing a lower-fidelity mockup.
"""

from __future__ import annotations

import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError as exc:  # pragma: no cover - environment-specific
    raise SystemExit(
        "Pillow is required to generate docs/brand/direction_blend.png on this "
        "machine."
    ) from exc


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "brand" / "direction_blend.png"

SIZE = (1600, 1000)

# Blended palette.
PAPER = "#F7F2E9"
PAPER_ELEVATED = "#FFFDF8"
PAPER_SUNKEN = "#EFE8D9"
INK = "#1F1B16"
INK_SECONDARY = "#6B6258"
INK_TERTIARY = "#9A9082"
HAIRLINE = "#E7DECB"
ACCENT = "#F2A03D"
ACCENT_DEEP = "#E07F22"
ACCENT_TEXT = "#B5650C"
WHITE = "#FFFFFF"


def load_font(candidates: list[str], size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def load_font_range(candidates: list[str], size: int, minimum: int) -> list[ImageFont.FreeTypeFont | ImageFont.ImageFont]:
    fonts = []
    for s in range(size, minimum - 1, -2):
        fonts.append(load_font(candidates, s))
    return fonts


SERIF = load_font(
    [
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSerif-Regular.ttf",
    ],
    64,
)
SERIF_BOLD = load_font(
    [
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSerif-Bold.ttf",
    ],
    64,
)
SANS = load_font(
    [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ],
    34,
)
SANS_SMALL = load_font(
    [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ],
    24,
)

SERIF_HEADLINE_FONTS = load_font_range(
    [
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSerif-Regular.ttf",
    ],
    64,
    44,
)


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(round(a[i] * (1.0 - t) + b[i] * t) for i in range(3))


def gradient_image(size: tuple[int, int], top_left: str, bottom_right: str) -> Image.Image:
    width, height = size
    a = hex_rgb(top_left)
    b = hex_rgb(bottom_right)
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(height):
        for x in range(width):
            t = (x / max(1, width - 1) + y / max(1, height - 1)) / 2.0
            px[x, y] = lerp(a, b, t)
    return img


def add_shadow(base: Image.Image, box: tuple[int, int, int, int], radius: int, alpha: int) -> None:
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle(box, radius=radius, fill=(36, 28, 20, alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(10, radius // 2)))
    base.alpha_composite(shadow)


def draw_brand_mark(base: Image.Image, xy: tuple[int, int], size: int) -> None:
    x, y = xy
    radius = int(size * 0.23)
    badge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = gradient_image((size, size), ACCENT, ACCENT_DEEP).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    dmask = ImageDraw.Draw(mask)
    dmask.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    badge.paste(grad, (0, 0), mask)

    # Subtle warm highlight and edge definition.
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dover = ImageDraw.Draw(overlay)
    dover.rounded_rectangle(
        (1, 1, size - 2, size - 2),
        radius=radius,
        outline=(255, 255, 255, 42),
        width=max(1, size // 92),
    )
    badge.alpha_composite(overlay)

    # White monogram: stem, foot, spark dot.
    d = ImageDraw.Draw(badge)
    stem = (int(size * 0.30), int(size * 0.16), int(size * 0.47), int(size * 0.84))
    foot = (int(size * 0.30), int(size * 0.67), int(size * 0.74), int(size * 0.84))
    dot_r = int(size * 0.085)
    dot = (int(size * 0.70 - dot_r), int(size * 0.26 - dot_r), int(size * 0.70 + dot_r), int(size * 0.26 + dot_r))
    corner = max(2, int(size * 0.05))
    d.rounded_rectangle(stem, radius=corner, fill=WHITE)
    d.rounded_rectangle(foot, radius=corner, fill=WHITE)
    d.ellipse(dot, fill=WHITE)

    base.alpha_composite(badge, (x, y))


def draw_wordmark(base: Image.Image, xy: tuple[int, int]) -> None:
    x, y = xy
    draw = ImageDraw.Draw(base)
    draw.text((x, y), "Lexi", font=SERIF_BOLD, fill=hex_rgb(INK))


def text_width(draw: ImageDraw.ImageDraw, text: str, font) -> int:
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0]


def draw_pill(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str) -> None:
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=ACCENT)
    tx = (box[0] + box[2]) // 2
    ty = (box[1] + box[3]) // 2
    bbox = draw.textbbox((0, 0), label, font=SANS_SMALL)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((tx - tw / 2, ty - th / 2 - 1), label, font=SANS_SMALL, fill=WHITE)


def draw_card(base: Image.Image, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    add_shadow(base, box, radius=34, alpha=58)
    card = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle(box, radius=34, fill=hex_rgb(PAPER_ELEVATED), outline=hex_rgb(HAIRLINE), width=2)
    base.alpha_composite(card)

    dbase = ImageDraw.Draw(base)
    pad = 48
    left = x0 + pad
    top = y0 + pad
    inner_right = x1 - pad

    # Small label / status row.
    dbase.text((left, top), "EXAMPLE ANSWER", font=SANS_SMALL, fill=hex_rgb(ACCENT_TEXT))
    ready_bbox = dbase.textbbox((0, 0), "ready", font=SANS_SMALL)
    ready_w = ready_bbox[2] - ready_bbox[0]
    dbase.text((inner_right - ready_w, top), "ready", font=SANS_SMALL, fill=hex_rgb(INK_TERTIARY))

    # Headline.
    headline_y = top + 36
    headline = "Warm, human, calm."
    headline_font = SERIF_HEADLINE_FONTS[-1]
    for font in SERIF_HEADLINE_FONTS:
        bbox = dbase.textbbox((0, 0), headline, font=font)
        if bbox[2] - bbox[0] <= inner_right - left:
            headline_font = font
            break
    dbase.text((left, headline_y), headline, font=headline_font, fill=hex_rgb(INK))

    # Body text bars.
    bars_top = headline_y + 96
    bar_h = 16
    gap = 15
    widths = [inner_right - left - 20, inner_right - left - 72, inner_right - left - 44, inner_right - left - 110]
    fills = [hex_rgb(INK), hex_rgb(INK_SECONDARY), hex_rgb(INK_SECONDARY), hex_rgb(INK_TERTIARY)]
    for i, (w, fill) in enumerate(zip(widths, fills)):
        y = bars_top + i * (bar_h + gap)
        dbase.rounded_rectangle((left, y, left + w, y + bar_h), radius=8, fill=fill)

    # One amber pill button.
    pill_y = y1 - pad - 62
    draw_pill(dbase, (left, pill_y, left + 118, pill_y + 52), "Ask")

    # Subtle note under the button.
    note = "one accent, generous space"
    note_bbox = dbase.textbbox((0, 0), note, font=SANS_SMALL)
    note_w = note_bbox[2] - note_bbox[0]
    note_x = min(left + 138, inner_right - note_w)
    dbase.text((note_x, pill_y + 14), note, font=SANS_SMALL, fill=hex_rgb(INK_TERTIARY))


def draw_palette_strip(base: Image.Image, xy: tuple[int, int]) -> None:
    x, y = xy
    draw = ImageDraw.Draw(base)
    draw.text((x, y - 36), "Palette", font=SANS_SMALL, fill=hex_rgb(INK_TERTIARY))

    swatches = [
        ("Accent", ACCENT),
        ("Ink", INK),
        ("Paper", PAPER_ELEVATED),
        ("Hairline", HAIRLINE),
        ("Secondary", INK_SECONDARY),
    ]
    sw_w = 116
    sw_h = 78
    gap = 16
    for i, (label, color) in enumerate(swatches):
        sx = x + i * (sw_w + gap)
        draw.rounded_rectangle((sx, y, sx + sw_w, y + sw_h), radius=18, fill=hex_rgb(color), outline=hex_rgb(HAIRLINE), width=2)
        text_fill = WHITE if color in {INK, ACCENT} else hex_rgb(INK)
        draw.text((sx + 14, y + 12), label, font=SANS_SMALL, fill=text_fill)
        draw.text((sx + 14, y + 40), color, font=SANS_SMALL, fill=text_fill)


def draw_caption(base: Image.Image, xy: tuple[int, int]) -> None:
    x, y = xy
    draw = ImageDraw.Draw(base)
    draw.text((x, y), "Warm & human, calm & restrained — one accent, generous space.", font=SANS, fill=hex_rgb(INK))
    draw.text((x, y + 52), "Blend (warm + restrained)", font=SANS_SMALL, fill=hex_rgb(ACCENT_TEXT))


def render() -> Image.Image:
    base = Image.new("RGBA", SIZE, hex_rgb(PAPER) + (255,))

    # Gentle paper atmosphere.
    bg = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    d.ellipse((-260, -220, 1100, 880), fill=(255, 252, 245, 72))
    d.ellipse((720, 40, 1700, 920), fill=(243, 235, 219, 60))
    d.ellipse((1080, 620, 1800, 1260), fill=(235, 225, 208, 44))
    base.alpha_composite(bg)

    draw_brand_mark(base, (128, 112), 88)
    draw_wordmark(base, (232, 132))

    # Quiet rule and small intro copy.
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((128, 236, 476, 239), radius=2, fill=hex_rgb(HAIRLINE))
    draw.text((128, 260), "Warm paper, near-black ink, and a single amber accent.", font=SANS_SMALL, fill=hex_rgb(INK_SECONDARY))

    draw_card(base, (820, 180, 1430, 698))
    draw_palette_strip(base, (130, 720))
    draw_caption(base, (130, 860))

    return base.convert("RGB")


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image = render()
    image.save(OUT)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
