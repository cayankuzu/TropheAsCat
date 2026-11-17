"""Zips the exported builds for itch.io (2026-11-17).

builds/CatAsTrophe_Web.zip      index.html and its files at the root (itch.io "HTML" upload, played in the browser)
builds/CatAsTrophe_Windows.zip  a CatAsTrophe/ folder with the exe, the .pck and the Voxel Tools dll

Usage (from the project folder): python -I tools/package_builds.py
"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILDS = os.path.join(ROOT, "builds")


def pack(src_dir: str, out_zip: str, prefix: str) -> None:
    files = sorted(f for f in os.listdir(src_dir) if not f.startswith("."))
    if not files:
        print("nothing in", src_dir)
        sys.exit(1)
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for f in files:
            z.write(os.path.join(src_dir, f), prefix + f)
    print("%s  %.1f MB (%d files)" % (out_zip, os.path.getsize(out_zip) / 1e6, len(files)))


pack(os.path.join(BUILDS, "web"), os.path.join(BUILDS, "CatAsTrophe_Web.zip"), "")
pack(os.path.join(BUILDS, "windows"), os.path.join(BUILDS, "CatAsTrophe_Windows.zip"), "CatAsTrophe/")
