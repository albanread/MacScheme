#!/usr/bin/env python3
from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageColor, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "resources" / "icons"
MASTER_PNG = ICON_DIR / "macscheme-icon-1024.png"
ICONSET_DIR = ICON_DIR / "MacScheme.iconset"
ICNS_PATH = ROOT / "resources" / "MacScheme.icns"

ICONSET_SIZES = [16, 32, 128, 256, 512]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(lerp(x, y, t))) for x, y in zip(a, b))


def hex_color(value: str) -> tuple[int, int, int]:
    return ImageColor.getrgb(value)


def make_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()

    c1 = hex_color("#301860")
    c2 = hex_color("#2d7cff")
    c3 = hex_color("#17d4c0")
    c4 = hex_color("#ffd45c")

    center_x = size * 0.42
    center_y = size * 0.30
    radius = size * 1.08

    for y in range(size):
        for x in range(size):
            dx = x - center_x
            dy = y - center_y
            dist = math.sqrt(dx * dx + dy * dy) / radius
            sweep = max(0.0, min(1.0, (x + y) / (size * 1.75)))
            wave = 0.5 + 0.5 * math.sin((x / size) * math.pi * 1.35 - (y / size) * math.pi * 0.65)
            t = max(0.0, min(1.0, 0.55 * dist + 0.30 * sweep + 0.15 * wave))
            if t < 0.38:
                base = lerp_color(c1, c2, t / 0.38)
            elif t < 0.74:
                base = lerp_color(c2, c3, (t - 0.38) / 0.36)
            else:
                base = lerp_color(c3, c4, (t - 0.74) / 0.26)
            pixels[x, y] = (*base, 255)

    return image


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def add_glow(base: Image.Image, size: int) -> Image.Image:
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    draw.ellipse(
        (size * 0.10, size * 0.08, size * 0.92, size * 0.78),
        fill=(255, 255, 255, 38),
    )
    draw.ellipse(
        (size * 0.22, size * 0.18, size * 0.86, size * 0.64),
        fill=(255, 255, 255, 22),
    )

    blurred = overlay.filter(ImageFilter.GaussianBlur(radius=size * 0.04))
    return Image.alpha_composite(base, blurred)


def draw_lambda(base: Image.Image, size: int) -> Image.Image:
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    stroke = max(22, size // 18)

    left_top = (size * 0.37, size * 0.20)
    center = (size * 0.56, size * 0.57)
    right_end = (size * 0.76, size * 0.80)
    cross_start = (size * 0.49, size * 0.45)
    cross_end = (size * 0.79, size * 0.24)

    glow_width = stroke + max(16, size // 30)
    glow_draw.line([left_top, center, right_end], fill=(255, 255, 255, 160), width=glow_width, joint="curve")
    glow_draw.line([cross_start, cross_end], fill=(255, 255, 255, 120), width=glow_width - 4)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=size * 0.02))
    icon = Image.alpha_composite(base, glow)

    draw = ImageDraw.Draw(icon)
    draw.line([left_top, center, right_end], fill=(250, 250, 255, 255), width=stroke, joint="curve")
    draw.line([cross_start, cross_end], fill=(255, 244, 190, 255), width=max(12, stroke - 6))

    spark_r = size * 0.02
    for px, py, fill in [
        (size * 0.26, size * 0.26, (255, 214, 92, 230)),
        (size * 0.80, size * 0.18, (120, 255, 235, 220)),
        (size * 0.82, size * 0.70, (255, 255, 255, 180)),
    ]:
        draw.ellipse((px - spark_r, py - spark_r, px + spark_r, py + spark_r), fill=fill)

    return icon


def add_shadow_and_border(icon: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    inset = int(size * 0.055)
    radius = int(size * 0.22)
    shadow_draw.rounded_rectangle(
        (inset, inset + size * 0.02, size - inset, size - inset + size * 0.02),
        radius=radius,
        fill=(0, 0, 0, 145),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=size * 0.05))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas = Image.alpha_composite(canvas, icon)

    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=radius,
        outline=(255, 255, 255, 56),
        width=max(2, size // 128),
    )
    return Image.alpha_composite(canvas, border)


def build_master_icon(size: int = 1024) -> Image.Image:
    base = make_background(size)
    base = add_glow(base, size)
    base = draw_lambda(base, size)
    base = add_shadow_and_border(base, size)

    inset = int(size * 0.055)
    radius = int(size * 0.22)
    mask = rounded_mask(size - inset * 2, radius - inset // 3)
    clipped = Image.new("RGBA", (size - inset * 2, size - inset * 2), (0, 0, 0, 0))
    clipped.alpha_composite(base.crop((inset, inset, size - inset, size - inset)))
    clipped.putalpha(mask)

    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.alpha_composite(clipped, (inset, inset))
    return final


def save_iconset(master: Image.Image) -> None:
    if ICONSET_DIR.exists():
        shutil.rmtree(ICONSET_DIR)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    for base_size in ICONSET_SIZES:
        for scale in (1, 2):
            actual = base_size * scale
            image = master.resize((actual, actual), Image.LANCZOS)
            suffix = f"icon_{base_size}x{base_size}"
            if scale == 2:
                suffix += "@2x"
            image.save(ICONSET_DIR / f"{suffix}.png")


def build_icns() -> None:
    iconutil = shutil.which("iconutil")
    if iconutil is None:
        raise SystemExit("iconutil is required on macOS to build .icns files")
    subprocess.run([iconutil, "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)], check=True)


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    master = build_master_icon(1024)
    master.save(MASTER_PNG)
    save_iconset(master)
    build_icns()
    print(f"wrote {MASTER_PNG}")
    print(f"wrote {ICNS_PATH}")


if __name__ == "__main__":
    main()
