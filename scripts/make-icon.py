"""Renders the Dotwell app icon master (1024x1024 PNG).

Design: a graphite macOS squircle holding a recessed "well" with a glowing green status dot and two
faint ping ripples. Requires Pillow and NumPy. Usage: python3 scripts/make-icon.py Resources/AppIcon.png
The output is checked in; rerun only when changing the design.
"""
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4  # supersampling factor
N = 1024 * S


def px(v):
    return int(round(v * S))


def squircle_mask(x0, y0, size, exponent=4.2):
    """Superellipse mask, close to Apple's continuous-corner icon shape."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    cx = cy = (x0 + size / 2) * S
    r = size / 2 * S
    d = np.abs((xx - cx) / r) ** exponent + np.abs((yy - cy) / r) ** exponent
    return Image.fromarray(((d <= 1.0) * 255).astype(np.uint8), "L")


def vertical_gradient(top, bottom):
    t = np.linspace(0, 1, N, dtype=np.float32)[:, None, None]
    a = np.array(top, np.float32)[None, None, :]
    b = np.array(bottom, np.float32)[None, None, :]
    rows = a + (b - a) * t
    return Image.fromarray(np.broadcast_to(rows, (N, N, len(top))).astype(np.uint8), "RGBA" if len(top) == 4 else "RGB")


def radial(cx, cy, r, inner, outer, power=1.0):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    d = np.clip(np.hypot(xx - cx * S, yy - cy * S) / (r * S), 0, 1) ** power
    a = np.array(inner, np.float32)
    b = np.array(outer, np.float32)
    img = a + (b - a) * d[..., None]
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def circle_mask(cx, cy, r, blur=0):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=255)
    return m.filter(ImageFilter.GaussianBlur(px(blur))) if blur else m


def ring_mask(cx, cy, r, width):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], outline=255, width=px(width))
    return m


def paint(base, color, mask, alpha=1.0):
    layer = Image.new("RGBA", (N, N), color)
    if alpha != 1.0:
        mask = mask.point(lambda v: int(v * alpha))
    base.alpha_composite(Image.composite(layer, Image.new("RGBA", (N, N), (0, 0, 0, 0)), mask))


def main(out):
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shape = squircle_mask(100, 100, 824)

    # Drop shadow under the tile.
    shadow = shape.transform(shape.size, Image.AFFINE, (1, 0, 0, 0, 1, -px(12))).filter(ImageFilter.GaussianBlur(px(18)))
    paint(canvas, (0, 0, 0, 255), shadow, 0.35)

    # Tile: graphite gradient with a soft top sheen.
    tile = vertical_gradient((52, 62, 76, 255), (17, 22, 29, 255))
    sheen = radial(512, 140, 620, (255, 255, 255, 34), (255, 255, 255, 0), power=1.2)
    tile.alpha_composite(sheen)
    canvas.alpha_composite(Image.composite(tile, Image.new("RGBA", (N, N), (0, 0, 0, 0)), shape))

    cx, cy, well_r = 512, 528, 270
    # Well: recessed disc, dark at the center, with an inner shadow at the top and a lit bottom rim.
    well = radial(cx, cy, well_r, (6, 9, 13, 255), (24, 31, 40, 255), power=1.6)
    well_mask = circle_mask(cx, cy, well_r)
    canvas.alpha_composite(Image.composite(well, Image.new("RGBA", (N, N), (0, 0, 0, 0)), well_mask))
    inner_shadow = ImageChops.subtract(well_mask, circle_mask(cx, cy + 22, well_r - 6, blur=14))
    paint(canvas, (0, 0, 0, 255), inner_shadow, 0.75)
    rim = ImageChops.subtract(circle_mask(cx, cy + 3, well_r + 2), circle_mask(cx, cy - 3, well_r))
    paint(canvas, (255, 255, 255, 255), rim.filter(ImageFilter.GaussianBlur(px(1.5))), 0.22)

    # Ping ripples.
    green = (52, 199, 89, 255)
    for r, a in ((210, 0.30), (155, 0.55)):
        paint(canvas, green, ring_mask(cx, cy, r, 7).filter(ImageFilter.GaussianBlur(px(1))), a)

    # Glowing status dot.
    paint(canvas, green, circle_mask(cx, cy, 140, blur=60), 0.75)
    dot_r = 92
    dot = radial(cx - 30, cy - 36, dot_r * 1.7, (175, 255, 190, 255), (20, 160, 62, 255), power=0.8)
    canvas.alpha_composite(Image.composite(dot, Image.new("RGBA", (N, N), (0, 0, 0, 0)), circle_mask(cx, cy, dot_r)))

    canvas.resize((1024, 1024), Image.LANCZOS).save(out, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
