#!/usr/bin/env python3
"""Generates the original HomeLedger app icon and launch mark (no third-party artwork)."""
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter

root = sys.argv[1] if len(sys.argv) > 1 else "HomeLedger/Resources/Assets.xcassets"
S = 1024

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = min(1, max(0, (x * 0.35 + y * 0.65) / size))
            px[x, y] = lerp(top, bottom, t)
    return img

def rline(d, pts, color, width):
    """Polyline with round caps and joins."""
    d.line(pts, fill=color, width=int(width))
    r = width / 2
    for (x, y) in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)

def draw_mark(d, cx, cy, scale, color, width, accent=(120, 220, 170)):
    w = 330 * scale; h = 270 * scale
    left, right = cx - w / 2, cx + w / 2
    top = cy - h / 2 + 30 * scale
    bottom = cy + h / 2 + 70 * scale
    apex = top - 150 * scale
    # Roof with overhang, then walls and floor as one stroke.
    rline(d, [(left - 40 * scale, top + 40 * scale), (cx, apex), (right + 40 * scale, top + 40 * scale)], color, width)
    rline(d, [(left, top), (left, bottom), (right, bottom), (right, top)], color, width)
    # Ledger lines (centered) and the "organized" dot.
    lw = width * 0.62
    x0 = left + 78 * scale; x1 = right - 78 * scale
    ys = [top + (bottom - top) * f for f in (0.30, 0.52, 0.74)]
    rline(d, [(x0, ys[0]), (x1, ys[0])], color, lw)
    rline(d, [(x0, ys[1]), (x1, ys[1])], color, lw)
    rline(d, [(x0, ys[2]), (x1 - 92 * scale, ys[2])], color, lw)
    r = 30 * scale
    dx = x1 - 22 * scale
    d.ellipse([dx - r, ys[2] - r, dx + r, ys[2] + r], fill=accent)

# App icon (opaque, 1024 px)
icon = gradient(S, (38, 76, 196), (22, 44, 128))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([120, 60, 900, 760], fill=(120, 150, 255, 70))
glow = glow.filter(ImageFilter.GaussianBlur(120))
icon = Image.alpha_composite(icon.convert("RGBA"), glow)
big = icon.resize((S * 4, S * 4), Image.BICUBIC)
d = ImageDraw.Draw(big)
draw_mark(d, S * 2, S * 2, 1.45 * 4, (255, 255, 255), 46 * 4)
icon = big.resize((S, S), Image.LANCZOS).convert("RGB")
icon_dir = os.path.join(root, "AppIcon.appiconset")
os.makedirs(icon_dir, exist_ok=True)
icon.save(os.path.join(icon_dir, "AppIcon-1024.png"))
json.dump({"images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(icon_dir, "Contents.json"), "w"), indent=2)

# Launch mark (transparent, white)
for scale_name, px in (("1x", 160), ("2x", 320), ("3x", 480)):
    m = Image.new("RGBA", (px * 4, px * 4), (0, 0, 0, 0))
    md = ImageDraw.Draw(m)
    f = px * 4 / 1024
    draw_mark(md, px * 2, px * 2, 1.45 * f * 1.5, (255, 255, 255, 255), 46 * f * 1.5)
    m = m.resize((px, px), Image.LANCZOS)
    lm_dir = os.path.join(root, "LaunchMark.imageset")
    os.makedirs(lm_dir, exist_ok=True)
    m.save(os.path.join(lm_dir, f"LaunchMark@{scale_name}.png"))
json.dump({"images": [{"filename": f"LaunchMark@{s}.png", "idiom": "universal", "scale": s} for s in ("1x", "2x", "3x")],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(root, "LaunchMark.imageset", "Contents.json"), "w"), indent=2)

def colorset(name, light, dark):
    path = os.path.join(root, f"{name}.colorset"); os.makedirs(path, exist_ok=True)
    def comp(rgb): return {"color-space": "srgb", "components": {"red": f"{rgb[0]/255:.3f}", "green": f"{rgb[1]/255:.3f}", "blue": f"{rgb[2]/255:.3f}", "alpha": "1.000"}}
    json.dump({"colors": [{"idiom": "universal", "color": comp(light)},
                          {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark)}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(path, "Contents.json"), "w"), indent=2)

colorset("AccentColor", (0x1E, 0x3F, 0xA0), (0x6F, 0x8C, 0xFF))
colorset("LaunchBackground", (0x23, 0x47, 0xB5), (0x1B, 0x2A, 0x6B))
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(root, "Contents.json"), "w"), indent=2)
print("ok")
