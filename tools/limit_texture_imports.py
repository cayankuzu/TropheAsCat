"""Smaller texture imports so the Windows game fits itch.io's 1 GB a file (2026-11-17).

assets/textures (ambientCG materials): VRAM compressed with mipmaps, at most 1536 px (the 34 terrain source maps
were lossless without mipmaps; the baked StrataTextureSet is not affected). The two 4K sky HDRIs and Trophe's
4K maps: at most 2048 px. Godot reimports what changed on the next --import.

Usage (from the project folder): python -I tools/limit_texture_imports.py
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def edit(path, changes):
    raw = open(path, "rb").read().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")
    before = text
    for key, value in changes.items():
        pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
        if pat.search(text):
            text = pat.sub("%s=%s" % (key, value), text)
        else:
            text = text.rstrip("\n") + "\n%s=%s\n" % (key, value)
    if text != before:
        open(path, "wb").write(text.replace("\n", nl).encode("utf-8"))
        return True
    return False


n = 0
for p in glob.glob(os.path.join(ROOT, "assets", "textures", "*", "*.import")):
    n += edit(p, {"compress/mode": "2", "mipmaps/generate": "true", "process/size_limit": "1536"})
for p in glob.glob(os.path.join(ROOT, "assets", "sky", "*.hdr.import")):
    n += edit(p, {"process/size_limit": "2048"})
for p in glob.glob(os.path.join(ROOT, "assets", "models", "cat", "sphynx_cat_*.import")):
    n += edit(p, {"process/size_limit": "2048"})
print("changed", n, "import files")
