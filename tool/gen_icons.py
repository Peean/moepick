#!/usr/bin/env python3
"""Generate the MoePick launcher icon set.

Design: a sticker-style smiling face on a cherry-blossom-pink gradient.
The face uses a thick white outline with a soft outer glow — the classic
"die-cut sticker" look that says "sticker app" without any text.

Outputs (android/app/src/main/res/):
  mipmap-*/ic_launcher.png            legacy square icons (48dp baseline)
  mipmap-*/ic_launcher_round.png      legacy round icons
  mipmap-*/ic_launcher_foreground.png adaptive foreground (108dp baseline)
  drawable/ic_launcher_background.xml referenced by adaptive icon XML
  mipmap-anydpi-v26/ic_launcher.xml + ic_launcher_round.xml
plus android/playstore-icon.png (512px).

All drawing happens at 4x supersampling and is downscaled with LANCZOS, so
curves stay smooth at every density.
"""
from PIL import Image, ImageDraw, ImageFilter
import math, os

# Resolve the repo root from this script's location (tool/../) so the
# script works on any checkout.
# 以脚本自身位置(tool/../)定位仓库根，脚本在任何检出副本中均可运行。
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# App default seed colour (AppSettings.seedColorValue = 0xFFE38FB1).
PINK = (227, 143, 177)        # #E38FB1
PINK_LIGHT = (244, 178, 201)  # gradient start
PINK_DARK = (201, 105, 150)   # gradient end
INK = (61, 49, 56)            # facial features, warm near-black
BLUSH = (247, 168, 190)       # cheeks

SS = 4  # supersample factor


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, c0, c1, c2):
    """Diagonal 135-degree three-stop gradient."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            c = lerp(c0, c1, t / 0.5) if t < 0.5 else lerp(c1, c2, (t - 0.5) / 0.5)
            px[x, y] = c
    # Soft top-left highlight for depth.
    hl = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(hl)
    d.ellipse([-size * 0.5, -size * 0.5, size * 0.7, size * 0.7], fill=46)
    hl = hl.filter(ImageFilter.GaussianBlur(size * 0.12))
    white = Image.new("RGB", (size, size), (255, 255, 255))
    img = Image.composite(white, img, hl)
    return img


def draw_face(draw, cx, cy, r, outline, feature_scale=1.0):
    """Sticker face: white-outlined circle, dot eyes, smile, blushes, ahoge."""
    w = r * 0.165 * feature_scale          # outline width
    # Soft glow (sticker edge lifting off the background).
    glow = Image.new("RGBA", draw._image.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - r - w * 1.4, cy - r - w * 1.4, cx + r + w * 1.4, cy + r + w * 1.4],
               fill=(255, 255, 255, 45))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.8))
    draw._image.alpha_composite(glow)
    # Ahoge (single strand of sticking-up hair) behind the head: a smooth
    # rightward curl, densely sampled so no jaggies survive downscaling.
    ax, ay = cx + r * 0.05, cy - r * 0.88
    pts = []
    N = 64
    for i in range(N + 1):
        t = i / N
        x = ax + math.sin(t * math.pi * 0.85) * r * 0.40 * (1 - t * 0.30)
        y = ay - math.sin(t * math.pi * 0.5) * r * 0.55
        pts.append((x, y))
    draw.line(pts, fill=outline, width=int(w * 0.88))
    cap = w * 0.44
    for p in (pts[0], pts[-1]):
        draw.ellipse([p[0] - cap, p[1] - cap, p[0] + cap, p[1] + cap], fill=outline)
    # Head.
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=outline, width=int(w))
    # Eyes: tall bean ellipses.
    er = r * 0.13 * feature_scale
    for sx in (-1, 1):
        ex = cx + sx * r * 0.38
        ey = cy - r * 0.10
        draw.ellipse([ex - er * 0.78, ey - er * 1.25, ex + er * 0.78, ey + er * 1.25],
                     fill=INK + (255,))
    # Smile: arc with round caps. The box above is a perfect circle of radius
    # sr centred at (cx, cy - 0.15*sr + 0.18*r); parametrise endpoints on it.
    sr = r * 0.46
    box = [cx - sr, cy - sr * 1.15 + r * 0.18, cx + sr, cy + sr * 0.85 + r * 0.18]
    sw = max(int(w * 0.72), 2)
    draw.arc(box, start=25, end=155, fill=INK + (255,), width=sw)
    scy = cy - 0.15 * sr + 0.18 * r
    for ang in (25, 155):
        px = cx + sr * math.cos(math.radians(ang))
        py = scy + sr * math.sin(math.radians(ang))
        cap = sw / 2.0
        draw.ellipse([px - cap, py - cap, px + cap, py + cap], fill=INK + (255,))
    # Blush.
    brx, bry = r * 0.16, r * 0.105
    for sx in (-1, 1):
        bx = cx + sx * r * 0.62
        by = cy + r * 0.30
        draw.ellipse([bx - brx, by - bry, bx + brx, by + bry], fill=BLUSH + (200,))


def make_foreground(px):
    """Adaptive foreground: content inside the central 66/108 safe zone."""
    ss = px * SS
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = px * (27.0 / 108.0) * SS     # face radius on the 108dp canvas
    draw_face(d, ss / 2, ss / 2 + r * 0.06, r, (255, 255, 255, 255))
    return img.resize((px, px), Image.LANCZOS)


def make_legacy(px, radius_ratio=0.0):
    """Legacy full-bleed icon: gradient square (+ optional round mask) and a
    face that fills more of the tile than the adaptive version."""
    ss = px * SS
    bg = gradient(ss, PINK_LIGHT, PINK, PINK_DARK).convert("RGBA")
    d = ImageDraw.Draw(bg)
    r = ss * 0.30
    draw_face(d, ss / 2, ss / 2 + r * 0.06, r, (255, 255, 255, 255))
    img = bg.resize((px, px), Image.LANCZOS)
    if radius_ratio > 0:
        mask = Image.new("L", (px * SS, px * SS), 0)
        md = ImageDraw.Draw(mask)
        rad = px * SS * radius_ratio
        md.rounded_rectangle([0, 0, px * SS - 1, px * SS - 1], rad, fill=255)
        mask = mask.resize((px, px), Image.LANCZOS)
        out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        return out
    return img


def make_round(px):
    ss = px * SS
    bg = gradient(ss, PINK_LIGHT, PINK, PINK_DARK).convert("RGBA")
    d = ImageDraw.Draw(bg)
    r = ss * 0.30
    draw_face(d, ss / 2, ss / 2 + r * 0.06, r, (255, 255, 255, 255))
    mask = Image.new("L", (ss, ss), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, ss - 1, ss - 1], fill=255)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(bg.resize((px, px), Image.LANCZOS), (0, 0), mask.resize((px, px), Image.LANCZOS))
    return out


DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

for dpi, mult in DENSITIES.items():
    folder = os.path.join(RES, f"mipmap-{dpi}")
    os.makedirs(folder, exist_ok=True)
    base48 = int(48 * mult)
    base108 = int(108 * mult)
    make_legacy(base48).save(os.path.join(folder, "ic_launcher.png"))
    make_round(base48).save(os.path.join(folder, "ic_launcher_round.png"))
    make_foreground(base108).save(os.path.join(folder, "ic_launcher_foreground.png"))
    print(f"mipmap-{dpi}: launcher {base48}px, foreground {base108}px")

os.makedirs(os.path.join(RES, "mipmap-anydpi-v26"), exist_ok=True)
with open(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
with open(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher_round.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')

os.makedirs(os.path.join(RES, "drawable"), exist_ok=True)
with open(os.path.join(RES, "drawable", "ic_launcher_background.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <gradient android:type="linear" android:angle="135"\n'
            '        android:startColor="#F4B2C9" android:centerColor="#E38FB1" android:endColor="#C96996"/>\n'
            '</shape>\n')

# Play Store listing icon (must be flat 512x512, no transparency).
make_legacy(512).convert("RGB").save(os.path.join(ROOT, "android", "playstore-icon.png"))
print("playstore 512px done")
