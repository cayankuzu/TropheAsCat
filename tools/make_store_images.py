"""Store-page images for itch.io and fikkis (2026-11-17) from the clean 1920x1080 screenshots in tests/out
(made with "-- --no-hud"): the cover (630x500), the page banner (960x300), JPG screenshots and the fikkis
previews (1600x960 PNG). Writes to builds/store/.

Usage (from the project folder): python -I tools/make_store_images.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "tests", "out")
OUT = os.path.join(ROOT, "builds", "store")
FONT = os.path.join(ROOT, "assets", "fonts", "Fredoka.ttf")
os.makedirs(OUT, exist_ok=True)


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def shot(name):
    return Image.open(os.path.join(SHOTS, name)).convert("RGB")


def text_outlined(draw, xy, text, fnt, fill, outline=(10, 12, 20), width=6, anchor="mm"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=width, stroke_fill=outline)


def cover():
    im = shot("tool_hat_closeup.png")
    w, h = im.size
    box = (460, max(h - 830, 0), 1460, max(h - 830, 0) + 794)
    im = im.crop(box).resize((630, 500), Image.LANCZOS)
    shade = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(shade)
    for y in range(150):
        d.line([(0, y), (630, y)], fill=int(170 * (1.0 - y / 150.0)))
    for y in range(390, 500):
        d.line([(0, y), (630, y)], fill=int(150 * (y - 390) / 110.0))
    im = Image.composite(Image.new("RGB", im.size, (8, 10, 18)), im, shade)
    d = ImageDraw.Draw(im)
    text_outlined(d, (315, 62), "CAT AS TROPHE", font(70), (255, 238, 205), width=7)
    text_outlined(d, (315, 465), "Nothing is off the table.", font(30, 600), (255, 215, 90), width=5)
    im.save(os.path.join(OUT, "cover_630x500.png"))


def banner():
    im = shot("giants_wheel_roll.png")
    w, h = im.size
    im = im.crop((0, int(h * 0.18), w, int(h * 0.18) + 600)).resize((1920, 600), Image.LANCZOS).resize((960, 300), Image.LANCZOS)
    shade = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(shade)
    for x in range(560):
        d.line([(x, 0), (x, 300)], fill=int(215 * max(0.0, 1.0 - x / 560.0) ** 0.8))
    im = Image.composite(Image.new("RGB", im.size, (8, 10, 18)), im, shade)
    d = ImageDraw.Draw(im)
    d.text((48, 66), "MEMODE SUNAR", font=font(20, 600), fill=(255, 215, 90))
    text_outlined(d, (46, 142), "CAT AS TROPHE", font(78), (255, 240, 210), width=6, anchor="lm")
    body = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Nunito.ttf"), 22)   # Fredoka has no ş
    d.text((48, 196), "Masada olmayan hiçbir şey yok", font=body, fill=(235, 235, 240))
    d.text((48, 228), "Nothing is off the table", font=body, fill=(170, 200, 230))
    im.save(os.path.join(OUT, "banner_960x300.png"))


SCREENS = ["tool_hat_closeup.png", "domino_finale.png", "giants_wheel_roll.png", "people_nice_kitty.png",
           "giants_tower_down.png", "domino_wave.png", "mk_city.png"]


def screenshots():
    for i, n in enumerate(SCREENS):
        im = shot(n)
        if im.size != (1920, 1080):
            im = im.resize((1920, 1080), Image.LANCZOS)
        im.save(os.path.join(OUT, "screenshot_%d.jpg" % (i + 1)), quality=88, optimize=True)


FIKKIS = [("catastrophe-hat.png", "tool_hat_closeup.png"), ("catastrophe-dominoes.png", "domino_finale.png"),
          ("catastrophe-wheel.png", "giants_wheel_roll.png")]


def fikkis():
    for out, n in FIKKIS:
        im = shot(n)
        w, h = im.size
        tw = int(h * 1600 / 960)
        x0 = max((w - tw) // 2, 0)
        im = im.crop((x0, 0, x0 + min(tw, w), h)).resize((1600, 960), Image.LANCZOS)
        im.save(os.path.join(OUT, out), optimize=True)


cover()
banner()
screenshots()
fikkis()
for f in sorted(os.listdir(OUT)):
    print("%-28s %5d KB" % (f, os.path.getsize(os.path.join(OUT, f)) // 1024))
