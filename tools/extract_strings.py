"""Lists the user-facing string literals of the game's scripts (a rough filter), one block per file.
Usage: python -I extract_strings.py <project root> [out.json]"""
import json
import os
import re
import sys

ROOT = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else None
STR = re.compile(r'(?<![&^\w"])"((?:[^"\\\n]|\\.)*)"')
DEBUG = re.compile(r'\b(print|prints|printerr|push_warning|push_error|print_debug|print_rich|assert|load|preload|has_method|get_node|find_child|has_node|get_node_or_null|is_action_pressed|is_action_just_pressed|is_action_just_released|get_action_strength|has_setting|get_setting|set_setting|get_value|set_value|has_section_key|Input\.\w+|get_meta|set_meta|has_meta)\s*\(')
SKIP_DIRS = ("addons",)
out = {}
for d, dirs, fs in os.walk(os.path.join(ROOT, "game")):
    dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
    for f in sorted(fs):
        if not f.endswith(".gd"):
            continue
        path = os.path.join(d, f)
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        text = open(path, encoding="utf-8").read()
        text = re.sub(r'"""[\s\S]*?"""', '""', text)
        found = []
        for ln in text.splitlines():
            st = ln.strip()
            if st.startswith("#"):
                continue
            for m in STR.finditer(ln):
                v = m.group(1)
                if len(v) < 2 or not re.search(r'[A-Za-z]', v):
                    continue
                if v.startswith(("res://", "user://", "uid://")):
                    continue
                if re.fullmatch(r'[a-z0-9_./:\-]+', v):
                    continue
                if re.fullmatch(r'[A-Za-z0-9_]+[0-9_][A-Za-z0-9_]*', v):
                    continue
                pre = ln[:m.start()]
                if DEBUG.search(pre):
                    continue
                if v not in found:
                    found.append(v)
        if found:
            out[rel] = found
total = 0
for k, v in out.items():
    print("== %s (%d)" % (k, len(v)))
    for s in v:
        print("   " + s)
    total += len(v)
print("TOTAL", total)
if OUT:
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
