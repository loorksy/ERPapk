# Generates the Android launcher icons and docs/brand from the two source images.
# Usage: python3 tool/gen_icons.py docs/brand/source/logo-original-transparent.png docs/brand/source/icon-original.png <out-dir>
# then copy <out-dir>/res into android/app/src/main/res and <out-dir>/brand into docs/brand.
import sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops
SRC_LOGO, SRC_ICON, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
logo = Image.open(SRC_LOGO).convert('RGBA')
icon = Image.open(SRC_ICON).convert('RGB')
W = icon.size[0]

# 1. Square icon with transparent corners: background = near-white region
#    connected to the corners.
white = icon.point(lambda v: 255 if v > 245 else 0).convert('L')
r, g, b = icon.split()
nearwhite = ImageChops.multiply(ImageChops.multiply(
    r.point(lambda v: 255 if v > 240 else 0),
    g.point(lambda v: 255 if v > 240 else 0)),
    b.point(lambda v: 255 if v > 240 else 0))
mask = nearwhite.copy()
for c in [(0, 0), (W - 1, 0), (0, W - 1), (W - 1, W - 1)]:
    ImageDraw.floodfill(mask, c, 128, thresh=0)
bg = mask.point(lambda v: 255 if v == 128 else 0)
bg = bg.filter(ImageFilter.MaxFilter(7))          # eat the light fringe
alpha = ImageChops.invert(bg).filter(ImageFilter.GaussianBlur(1.2))
square = icon.convert('RGBA'); square.putalpha(alpha)
square.save(f'{OUT}/icon-square-1254.png')

# 2. Background gradient sampled from the icon: bottom-left blue, centre
#    cyan, top-right green.
C0, C1, C2 = (0x05, 0x6d, 0xf5), (0x0b, 0xc4, 0xe8), (0x12, 0xe3, 0x9e)
def gradient(size):
    img = Image.new('RGB', (size, size)); px = img.load()
    for y in range(size):
        for x in range(size):
            t = ((x) + (size - 1 - y)) / (2 * (size - 1))  # 0 bottom-left .. 1 top-right
            if t < 0.5:
                u = t / 0.5; a, b2 = C0, C1
            else:
                u = (t - 0.5) / 0.5; a, b2 = C1, C2
            px[x, y] = tuple(round(a[i] + (b2[i] - a[i]) * u) for i in range(3))
    return img

# 3. Adaptive foreground: the transparent logo inside the safe zone.
def foreground(size, scale=0.60):
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bbox = logo.getbbox(); l = logo.crop(bbox)
    k = size * scale / max(l.size)
    l = l.resize((round(l.size[0] * k), round(l.size[1] * k)), Image.LANCZOS)
    canvas.alpha_composite(l, ((size - l.size[0]) // 2, (size - l.size[1]) // 2))
    return canvas

# 4. Monochrome (themed icons): the logo's shape with its light details
#    (keys, bars, $) cut out.
def monochrome(size, scale=0.60):
    fg = foreground(size, scale)
    r, g, b, a = fg.split()
    def lightness(px):
        return px
    rr, gg, bb = r.load(), g.load(), b.load()
    out = Image.new('L', (size, size), 0); o = out.load(); aa = a.load()
    for y in range(size):
        for x in range(size):
            al = aa[x, y]
            if al == 0: continue
            mx = max(rr[x, y], gg[x, y], bb[x, y]); mn = min(rr[x, y], gg[x, y], bb[x, y])
            sat = 0 if mx == 0 else (mx - mn) / mx
            light = mx / 255
            detail = max(0.0, min(1.0, (light - 0.80) / 0.12)) * max(0.0, min(1.0, (0.45 - sat) / 0.25))
            o[x, y] = round(al * (1 - detail))
    mono = Image.new('RGBA', (size, size), (255, 255, 255, 0)); mono.putalpha(out)
    return mono

dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
res = f'{OUT}/res'
for d, k in dens.items():
    os.makedirs(f'{res}/mipmap-{d}', exist_ok=True)
    legacy = round(48 * k)
    sq = square.resize((legacy, legacy), Image.LANCZOS)
    sq.save(f'{res}/mipmap-{d}/ic_launcher.png', optimize=True)
    # Round legacy icon: the full-bleed design in a circle.
    full = gradient(legacy).convert('RGBA'); full.alpha_composite(foreground(legacy, 0.74))
    m = Image.new('L', (legacy * 4, legacy * 4), 0)
    ImageDraw.Draw(m).ellipse((0, 0, legacy * 4 - 1, legacy * 4 - 1), fill=255)
    full.putalpha(m.resize((legacy, legacy), Image.LANCZOS))
    full.save(f'{res}/mipmap-{d}/ic_launcher_round.png', optimize=True)
    fgsize = round(108 * k)
    foreground(fgsize).save(f'{res}/mipmap-{d}/ic_launcher_foreground.png', optimize=True)
    monochrome(fgsize).save(f'{res}/mipmap-{d}/ic_launcher_monochrome.png', optimize=True)

# Brand kit files
brand = f'{OUT}/brand'; os.makedirs(brand, exist_ok=True)
square.resize((1024, 1024), Image.LANCZOS).save(f'{brand}/icon-1024.png', optimize=True)
ps = gradient(512).convert('RGBA'); ps.alpha_composite(foreground(512, 0.74)); ps.convert('RGB').save(f'{brand}/play-store-512.png', optimize=True)
lb = logo.crop(logo.getbbox()); k = 1024 / max(lb.size)
lb.resize((round(lb.size[0] * k), round(lb.size[1] * k)), Image.LANCZOS).save(f'{brand}/logo-mark-1024.png', optimize=True)
monochrome(1024, 0.92).save(f'{brand}/logo-monochrome-1024.png', optimize=True)
gradient(512).save(f'{brand}/background-gradient-512.png', optimize=True)
# In-app logo (Flutter asset)
lb.resize((round(lb.size[0] * 256 / max(lb.size)), round(lb.size[1] * 256 / max(lb.size))), Image.LANCZOS).save(f'{OUT}/logo-256.png', optimize=True)

# Previews of how launchers mask the adaptive icon.
def adaptive(size, shape):
    full = gradient(size).convert('RGBA'); full.alpha_composite(foreground(size))
    inset = round(size * 18 / 108); vis = full.crop((inset, inset, size - inset, size - inset))
    s = vis.size[0]; m = Image.new('L', (s * 4, s * 4), 0); dr = ImageDraw.Draw(m)
    if shape == 'circle': dr.ellipse((0, 0, s * 4 - 1, s * 4 - 1), fill=255)
    else: dr.rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=s * 4 * 0.28, fill=255)
    vis.putalpha(m.resize((s, s), Image.LANCZOS)); return vis
sheet = Image.new('RGBA', (900, 260), (240, 242, 245, 255))
sheet.alpha_composite(adaptive(432, 'circle').resize((200, 200)), (20, 30))
sheet.alpha_composite(adaptive(432, 'squircle').resize((200, 200)), (240, 30))
sheet.alpha_composite(square.resize((200, 200), Image.LANCZOS), (460, 30))
mono_prev = Image.new('RGBA', (200, 200), (40, 60, 90, 255)); mono_prev.alpha_composite(monochrome(200, 0.60).resize((200, 200)))
sheet.alpha_composite(mono_prev, (680, 30))
sheet.save(f'{OUT}/preview.png')
print('ok')
