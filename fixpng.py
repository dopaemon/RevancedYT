#!/usr/bin/env python3
"""Rewrite res/*.png entries that are not actually PNGs.

TikTok ships resources named .png that hold WebP/JPEG data. aapt2 refuses to
recompile them ("file does not start with PNG signature"), which fails the
whole patch. Converting them keeps the artwork; if no image library is around,
a 1x1 transparent PNG keeps the build going.
"""
import shutil
import sys
import zipfile

PNG_SIG = b"\x89PNG\r\n\x1a\n"
BLANK = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000b49444154789c6360000200000500017a5eab3f00"
    "00000049454e44ae426082"
)


def to_png(data):
    try:
        import io

        from PIL import Image

        buf = io.BytesIO()
        Image.open(io.BytesIO(data)).convert("RGBA").save(buf, format="PNG")
        return buf.getvalue(), "converted"
    except Exception:
        return BLANK, "blanked"


def main(path):
    tmp = path + ".fixed"
    fixed = []
    with zipfile.ZipFile(path) as src, zipfile.ZipFile(tmp, "w") as dst:
        for info in src.infolist():
            data = src.read(info.filename)
            if (
                info.filename.startswith("res/")
                and info.filename.endswith(".png")
                and not data.startswith(PNG_SIG)
            ):
                data, how = to_png(data)
                fixed.append(f"{info.filename} ({how})")
            # Keep STORED entries stored so resources.arsc stays page aligned.
            dst.writestr(info, data, compress_type=info.compress_type)

    if not fixed:
        import os

        os.remove(tmp)
        print("no invalid PNG resources found")
        return 0

    shutil.move(tmp, path)
    print(f"repaired {len(fixed)} PNG resource(s):")
    for name in fixed[:20]:
        print("  " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
