"""Draws a version label under the title of assets/thumbnail-base.png.

Usage: python tools/draw_thumbnail.py <output png> <label>

Reads assets/thumbnail-base.png from the repo this script sits in, draws <label>
centred under the title in yellow with a black outline and drop shadow, and
writes the result to <output png>. The base is only read. Needs Pillow.

tools/stage.ps1 -Minor and -Major run this with the thumbnail path from
Info.json and the release version as vMAJOR.MINOR.

Exits 0 on success, 1 on bad arguments, a missing base, or missing Pillow.
"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError:
    print("draw_thumbnail.py: Pillow is not installed. Run: python -m pip install --user pillow", file=sys.stderr)
    sys.exit(1)

BASE = Path(__file__).resolve().parent.parent / 'assets' / 'thumbnail-base.png'
FONT = r'C:\Windows\Fonts\ariblk.ttf'
YELLOW = (253, 237, 8, 255)
CAP_H = 43           # title letter height, px
TOP = 253 + 31       # bottom of PASSIVES plus the gap between the title lines, px
CENTER_X = 258       # centre of the title lines, px
SHADOW_ALPHA = 0.85
SHADOW_OFFSET = (3, 4)
SHADOW_BLUR = 2


def draw(base_path, out_path, text):
    base = Image.open(base_path).convert('RGBA')
    w, h = base.size

    # smallest size whose digit height reaches the title's letter height
    size = 40
    while -ImageFont.truetype(FONT, size).getbbox('1', anchor='ls')[1] < CAP_H:
        size += 1
    font = ImageFont.truetype(FONT, size)
    bb = font.getbbox(text, anchor='ls')
    x = CENTER_X - (bb[2] - bb[0]) / 2 - bb[0]
    y = TOP + CAP_H  # baseline

    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255, anchor='ls')
    outline = mask.filter(ImageFilter.MaxFilter(7))
    shadow = ImageChops.offset(outline.filter(ImageFilter.MaxFilter(3)), *SHADOW_OFFSET)
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))

    black = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    out = Image.composite(black, base, shadow.point(lambda v: int(v * SHADOW_ALPHA)))
    out = Image.composite(black, out, outline)
    out = Image.composite(Image.new('RGBA', (w, h), YELLOW), out, mask)
    out.save(out_path)
    return size


def main(argv):
    if len(argv) != 3 or not argv[2]:
        print("usage: python tools/draw_thumbnail.py <output png> <label>", file=sys.stderr)
        return 1
    out_path, text = Path(argv[1]).resolve(), argv[2]
    if not BASE.is_file():
        print(f"draw_thumbnail.py: base image not found at {BASE}", file=sys.stderr)
        return 1
    if out_path == BASE:
        print("draw_thumbnail.py: the output path is the base image; refusing to overwrite it", file=sys.stderr)
        return 1
    size = draw(BASE, out_path, text)
    print(f"drew '{text}' on {out_path.name} at font size {size}")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
