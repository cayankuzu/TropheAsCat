"""Lists the biggest files of a Godot 4 .pck and the totals by extension. Usage: python -I pck_list.py <file.pck> [top]"""
import collections
import struct
import sys

path = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 25
f = open(path, "rb")
assert f.read(4) == b"GDPC", "not a pck"
version, major, minor, patch = struct.unpack("<4I", f.read(16))
flags = struct.unpack("<I", f.read(4))[0]
file_base = struct.unpack("<Q", f.read(8))[0]
if version >= 3:
    dir_offset = struct.unpack("<Q", f.read(8))[0]
    f.seek(dir_offset)
else:
    f.read(16 * 4)
count = struct.unpack("<I", f.read(4))[0]
files = []
for _ in range(count):
    n = struct.unpack("<I", f.read(4))[0]
    name = f.read(n).rstrip(b"\0").decode("utf-8", "replace")
    off, size = struct.unpack("<QQ", f.read(16))
    f.read(16)
    f.read(4)
    files.append((size, name))
files.sort(reverse=True)
print("version %d, Godot %d.%d.%d, %d files, %.1f MB" % (version, major, minor, patch, count, sum(s for s, _ in files) / 1e6))
for s, n in files[:top]:
    print("%8.2f MB  %s" % (s / 1e6, n))
by = collections.Counter()
for s, n in files:
    ext = n.rsplit(".", 1)[-1] if "." in n.rsplit("/", 1)[-1] else "-"
    by[ext] += s
for ext, s in by.most_common(12):
    print("%8.1f MB  .%s" % (s / 1e6, ext))
