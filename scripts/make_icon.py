"""Generates the SpotiMusic app icon set (run: python3 scripts/make_icon.py)."""
import json, os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "SpotiMusic", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)
S = 1024

SS = 4  # supersampling factor for smooth edges

def master():
    N = S * SS
    top, bottom = (93, 201, 175), (86, 186, 160)
    grad = Image.new("RGB", (1, N))
    for y in range(N):
        t = y / N
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    grad = grad.resize((N, N))
    # macOS icon grid: 824pt rounded square centered on the 1024 canvas, with a soft drop shadow.
    inset, radius = 100 * SS, 185 * SS
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, N - inset, N - inset), radius, fill=255)
    icon = grad.convert("RGBA")
    icon.putalpha(mask)

    # White eighth-note pair with a slanted beam (traced from the reference artwork).
    def pt(x, y):  # reference image coordinates -> supersampled canvas
        k = 824 / 276 * SS
        return (100 * SS + (x - 68) * k, 100 * SS + (y - 22) * k)

    note = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(note)
    d.polygon([pt(162, 97), pt(259, 79), pt(259, 111), pt(162, 128)], fill=255)  # slanted beam
    d.rectangle((*pt(162, 100), *pt(179, 214)), fill=255)                       # left stem
    d.rectangle((*pt(242, 82), *pt(259, 198)), fill=255)                        # right stem
    d.ellipse((*pt(121, 190), *pt(181, 237)), fill=255)                         # left head
    d.ellipse((*pt(203, 173), *pt(261, 221)), fill=255)                         # right head
    # Blur + threshold rounds the corners like the reference glyph.
    note = note.filter(ImageFilter.GaussianBlur(5 * SS * 3)).point(lambda v: 255 if v > 128 else 0)
    note = note.filter(ImageFilter.GaussianBlur(SS / 2))
    icon.paste(Image.new("RGBA", (N, N), (255, 255, 255, 255)), (0, 0), note)

    icon = icon.resize((S, S), Image.LANCZOS)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((100, 112, S - 100, S - 88), 185, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    shadow.alpha_composite(icon)
    return shadow

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
