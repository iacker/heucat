#!/usr/bin/env python3
"""Turn the source artwork into a macOS .icns.

The artwork arrives as a rounded marble tile sitting on a white page. macOS
wants the opposite: the tile itself, corners transparent, with the small margin
Apple leaves around an icon. So this trims the page, rounds the corners, and
pads the result back out to the canonical 1024 grid.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Apple's grid: the art occupies about 82% of the canvas, the rest is breathing
# room. Matching it keeps the icon the same visual weight as its neighbours in
# the Dock instead of looking oversized.
CANVAS = 1024
ART_RATIO = 0.816
CORNER_RATIO = 0.185
SIZES = [16, 32, 64, 128, 256, 512, 1024]


def trim_page(img: Image.Image, tol: int = 246) -> Image.Image:
    """Crop the white page away, leaving just the tile."""
    grey = img.convert("L")
    mask = grey.point(lambda p: 255 if p < tol else 0)
    box = mask.getbbox()
    return img.crop(box) if box else img


def rounded(img: Image.Image, radius: int) -> Image.Image:
    """Round the corners with an antialiased mask."""
    scale = 4
    big = (img.width * scale, img.height * scale)
    mask = Image.new("L", big, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (big[0] - 1, big[1] - 1)], radius=radius * scale, fill=255
    )
    mask = mask.resize(img.size, Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def build(source: Path, out_icns: Path) -> None:
    img = Image.open(source).convert("RGBA")
    tile = trim_page(img)

    side = int(CANVAS * ART_RATIO)
    tile = tile.resize((side, side), Image.LANCZOS)
    tile = rounded(tile, int(side * CORNER_RATIO))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # A soft contact shadow so the tile reads as a physical object on light and
    # dark Dock backgrounds alike.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste(
        Image.new("RGBA", tile.size, (0, 0, 0, 62)),
        ((CANVAS - side) // 2, (CANVAS - side) // 2 + int(side * 0.022)),
        tile,
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(side * 0.028)))
    canvas.paste(tile, ((CANVAS - side) // 2, (CANVAS - side) // 2), tile)

    iconset = out_icns.with_suffix(".iconset")
    if iconset.exists():
        for f in iconset.iterdir():
            f.unlink()
    iconset.mkdir(parents=True, exist_ok=True)

    for size in SIZES:
        canvas.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
        if size <= 512:
            canvas.resize((size * 2, size * 2), Image.LANCZOS).save(
                iconset / f"icon_{size}x{size}@2x.png"
            )

    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out_icns)], check=True)
    for f in iconset.iterdir():
        f.unlink()
    iconset.rmdir()
    print(f"wrote {out_icns} ({out_icns.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: make-icon.py <source.png> <out.icns>")
    build(Path(sys.argv[1]), Path(sys.argv[2]))
