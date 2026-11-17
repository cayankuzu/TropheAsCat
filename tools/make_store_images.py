"""Store-page images for itch.io and fikkis (2026-11-17) from the clean 1920x1080 screenshots in tests/out
(made with "-- --no-hud"): the cover (630x500), the page banner (960x300), JPG screenshots and the fikkis
previews (1600x960 PNG), plus the page and embed backgrounds and three 1200x400 pictures for the
description. The title is drawn as it glitches on screen: TROPHE AS CAT, then > CAT AS TROPHE. Writes to builds/store/.

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


MONO = os.path.join(ROOT, "assets", "fonts", "JetBrainsMono.ttf")
BODY = os.path.join(ROOT, "assets", "fonts", "Nunito.ttf")


def glitch_title(im, xy, text, size, anchor="mm", seed=7):
    """The name as it tears on screen: a red and a teal ghost to the sides, the cream text on top, and a few
    horizontal slices shifted sideways."""
    import random
    rnd = random.Random(seed)
    f = font(size)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    off = max(size // 13, 3)
    sw = max(size // 16, 2)
    d.text((xy[0] - off, xy[1] - 1), text, font=f, fill=(255, 50, 90, 215), anchor=anchor, stroke_width=sw, stroke_fill=(255, 50, 90, 215))
    d.text((xy[0] + off, xy[1] + 1), text, font=f, fill=(50, 230, 225, 215), anchor=anchor, stroke_width=sw, stroke_fill=(50, 230, 225, 215))
    d.text(xy, text, font=f, fill=(255, 241, 214, 255), anchor=anchor, stroke_width=sw, stroke_fill=(8, 10, 18, 255))
    box = d.textbbox(xy, text, font=f, anchor=anchor)
    for _ in range(2):
        y0 = rnd.randint(box[1] + 4, max(box[1] + 5, box[3] - 8))
        h = rnd.randint(3, max(4, size // 12))
        band = layer.crop((box[0] - 30, y0, box[2] + 30, y0 + h))
        layer.paste((0, 0, 0, 0), (box[0] - 30, y0, box[2] + 30, y0 + h))
        layer.paste(band, (box[0] - 30 + rnd.choice([-1, 1]) * rnd.randint(off, off * 3), y0), band)
    im.paste(layer, (0, 0), layer)
    return box


def shade_rows(im, top_alpha, top_h, bottom_alpha, bottom_h):
    w, h = im.size
    m = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(m)
    for y in range(top_h):
        d.line([(0, y), (w, y)], fill=int(top_alpha * (1.0 - y / top_h)))
    for y in range(h - bottom_h, h):
        d.line([(0, y), (w, y)], fill=int(bottom_alpha * (y - (h - bottom_h)) / bottom_h))
    return Image.composite(Image.new("RGB", im.size, (8, 10, 18)), im, m)


def cover():
    im = shot("tool_hat_closeup.png")
    w, h = im.size
    y0 = max(h - 830, 0)
    im = im.crop((460, y0, 1460, y0 + 794)).resize((630, 500), Image.LANCZOS)
    im = shade_rows(im, 190, 175, 170, 120).convert("RGBA")
    glitch_title(im, (315, 66), "TROPHE AS CAT", 64)
    d = ImageDraw.Draw(im)
    d.text((315, 122), "> CAT AS TROPHE", font=ImageFont.truetype(MONO, 22), fill=(110, 240, 225), anchor="mm")
    d.text((315, 466), "Nothing is off the table.", font=font(28, 600), fill=(255, 215, 90), anchor="mm", stroke_width=4, stroke_fill=(8, 10, 18))
    im.convert("RGB").save(os.path.join(OUT, "cover_630x500.png"))


def banner():
    im = shot("giants_wheel_roll.png")
    w, h = im.size
    im = im.crop((0, int(h * 0.18), w, int(h * 0.18) + 600)).resize((960, 300), Image.LANCZOS)
    m = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(m)
    for x in range(600):
        d.line([(x, 0), (x, 300)], fill=int(220 * max(0.0, 1.0 - x / 600.0) ** 0.8))
    im = Image.composite(Image.new("RGB", im.size, (8, 10, 18)), im, m).convert("RGBA")
    d = ImageDraw.Draw(im)
    d.text((48, 52), "MEMODE SUNAR", font=font(20, 600), fill=(255, 215, 90))
    glitch_title(im, (46, 128), "TROPHE AS CAT", 76, anchor="lm", seed=3)
    d.text((50, 184), "> CAT AS TROPHE", font=ImageFont.truetype(MONO, 20), fill=(110, 240, 225))
    body = ImageFont.truetype(BODY, 21)   # Fredoka has no Turkish letters
    d.text((50, 220), "Masada olmayan hiçbir şey yok", font=body, fill=(235, 235, 240))
    d.text((50, 248), "Nothing is off the table", font=body, fill=(170, 200, 230))
    im.convert("RGB").save(os.path.join(OUT, "banner_960x300.png"))


def page_background():
    """Behind the page column: the city from above, dark and soft (like the art behind Merbut's page)."""
    im = shot("mk_city.png").resize((1920, 1080), Image.LANCZOS).filter(ImageFilter.GaussianBlur(2.2))
    im = Image.blend(im, Image.new("RGB", im.size, (8, 10, 18)), 0.55)
    im.save(os.path.join(OUT, "page_background.jpg"), quality=86, optimize=True)


def embed_background():
    """What the browser demo shows before Run game: Trophe in her hat and the name tearing above her."""
    im = shot("tool_hat_closeup.png").resize((1920, 1080), Image.LANCZOS)
    im = im.crop((0, 236, 1500, 1080)).resize((1280, 720), Image.LANCZOS)   # Trophe right of the Run game button
    im = shade_rows(im, 215, 300, 120, 160).convert("RGBA")
    glitch_title(im, (640, 74), "TROPHE AS CAT", 96, seed=11)
    d = ImageDraw.Draw(im)
    d.text((640, 146), "> CAT AS TROPHE", font=ImageFont.truetype(MONO, 30), fill=(110, 240, 225), anchor="mm")
    im.convert("RGB").save(os.path.join(OUT, "embed_background_1280x720.jpg"), quality=88, optimize=True)


INLINE = [("inline_dominoes.jpg", "domino_finale.png", 150), ("inline_wheel.jpg", "giants_wheel_roll.png", None),
          ("inline_people.jpg", "people_nice_kitty.png", 0)]   # a top row where the middle band would cut something


def inline_images():
    """Wide pictures between the sections of the description (Merbut has three)."""
    for out, n, top in INLINE:
        im = shot(n)
        w, h = im.size
        band = w // 3   # 1200x400 like Merbut's
        y0 = max((h - band) // 2, 0) if top is None else top
        im = im.crop((0, y0, w, y0 + band)).resize((1200, 400), Image.LANCZOS)
        im.save(os.path.join(OUT, out), quality=88, optimize=True)


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
page_background()
embed_background()
inline_images()
screenshots()
fikkis()
for f in sorted(os.listdir(OUT)):
    print("%-28s %5d KB" % (f, os.path.getsize(os.path.join(OUT, f)) // 1024))
