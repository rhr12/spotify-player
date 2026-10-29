"""Generates the SpotiMusic app icon set (run: python3 scripts/make_icon.py)."""
import json, os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "SpotiMusic", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)
S = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def master():
    top, bottom = (252, 92, 125), (250, 35, 59)
    grad = Image.new("RGB", (S, S))
    px = grad.load()
    for y in range(S):
        for x in range(S):
            px[x, y] = lerp(top, bottom, min(1, (y * 0.8 + x * 0.2) / S))
    # macOS icon grid: 824pt rounded rect centered in 1024 canvas with drop shadow.
    inset, radius = 100, 185
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, S - inset, S - inset), radius, fill=255)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((inset, inset + 12, S - inset, S - inset + 12), radius, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.alpha_composite(shadow)
    body = grad.convert("RGBA")
    body.putalpha(mask)
    icon.alpha_composite(body)
    # White double eighth note.
    d = ImageDraw.Draw(icon)
    w = (255, 255, 255, 255)
    d.ellipse((300, 610, 440, 715), fill=w)
    d.ellipse((560, 560, 700, 665), fill=w)
    d.rectangle((410, 330, 440, 665), fill=w)
    d.rectangle((670, 280, 700, 615), fill=w)
    d.polygon([(410, 330), (700, 280), (700, 360), (410, 410)], fill=w)
    return icon

m = master()
images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        m.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
