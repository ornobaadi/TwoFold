"""Play Store screenshots in 3D phone mockups, and the feature graphic.

Run from the project folder:  python tool/store_mockups.py
Inputs: build/mock/*.png (SHOTS=1 SHOT_SIZE=1220x2712 store_shots_test) and
assets/screenshots/ (phone captures). Writes docs/store/mockups/.
Only public domain or openly licensed books may appear in store images.
"""

import glob
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = 'assets/fonts'
OUT = 'docs/store/mockups'

PAPER = (243, 237, 226)
PAPER_INK = (28, 26, 23)
PAPER_MUTED = (108, 100, 90)
NIGHT = (23, 23, 58)          # brand midnight #17173A
NIGHT_INK = (247, 241, 230)
NIGHT_MUTED = (184, 182, 214)
CORAL = (255, 107, 107)       # brand coral #FF6B6B
GOLD = (255, 224, 138)        # brand gold #FFE08A


def font(name, size, weight, opsz=None):
    f = ImageFont.truetype(os.path.join(FONTS, name), size)
    axes = f.get_variation_axes()
    values = []
    for a in axes:
        n = a['name'].decode() if isinstance(a['name'], bytes) else a['name']
        if n == 'Weight':
            values.append(weight)
        else:
            values.append(max(a['minimum'], min(a['maximum'], opsz or size)))
    f.set_variation_by_axes(values)
    return f


def serif(size, weight=700):
    return font('Literata.ttf', size, weight, opsz=72)


def sans(size, weight=400):
    return font('Inter.ttf', size, weight, opsz=32)


# ---------------------------------------------------------------- editing

def repaint_now_playing(im):
    """Replaces a copyrighted book in the now-playing strip with Pride and
    Prejudice, drawn the way the app draws a book without a cover."""
    im = im.convert('RGB')
    d = ImageDraw.Draw(im)
    bg = im.getpixel((700, 2345))
    dark = sum(bg) < 200
    # Cover: book cloth with a monogram, as BookCover does when small.
    d.rectangle((40, 2316, 136, 2450), fill=bg)
    d.rounded_rectangle((44, 2320, 131, 2446), radius=12, fill=(122, 46, 42))
    f = serif(54, 600)
    d.text((87.5, 2383), 'P', font=f, fill=(242, 230, 214), anchor='mm')
    # Title: same place, size and weight as the app's titleSmall.
    d.rectangle((150, 2328, 940, 2388), fill=bg)
    ink = (236, 230, 220) if dark else (28, 26, 23)
    d.text((164, 2358), 'Pride and Prejudice', font=sans(38, 560),
           fill=ink, anchor='lm')
    return im


# ---------------------------------------------------------------- phone

def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1),
                                        radius=radius, fill=255)
    return m


def phone(screen, width):
    """A flat, modern phone around [screen], [width] pixels wide."""
    scale = width / (screen.width + 2 * 34)
    sw = int(screen.width * scale)
    sh = int(screen.height * scale)
    bezel = int(34 * scale)
    w, h = sw + 2 * bezel, sh + 2 * bezel
    body = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    r = int(150 * scale)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=(18, 18, 22))
    # A thin lighter rim reads as a metal edge.
    d.rounded_rectangle((2, 2, w - 3, h - 3), radius=r - 2,
                        outline=(70, 70, 82), width=max(2, int(4 * scale)))
    shot = screen.convert('RGB').resize((sw, sh), Image.LANCZOS)
    body.paste(shot, (bezel, bezel), rounded_mask((sw, sh), r - bezel))
    # Punch-hole camera.
    cx, cy, cr = w // 2, bezel + int(46 * scale), int(17 * scale)
    d.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=(10, 10, 12))
    return body


def side(body, depth):
    """Adds the phone's thickness on the left, so the tilt reads as 3D."""
    w, h = body.size
    out = Image.new('RGBA', (w + depth, h), (0, 0, 0, 0))
    edge = Image.new('RGBA', body.size, (52, 52, 60, 255))
    edge.putalpha(body.getchannel('A'))
    for i in range(depth, 0, -1):
        out.alpha_composite(edge, (depth - i, 0))
    out.alpha_composite(body, (depth, 0))
    return out


def perspective(img, turn=0.10, lift=0.035):
    """Turns the phone away to the right: the far edge shrinks."""
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    nw = int(w * (1 - turn * 0.6))
    dst = [(0, 0), (nw, int(h * lift)), (nw, int(h * (1 - lift))), (0, h)]
    # Solve for PIL's coefficients mapping output -> input.
    a = []
    b = []
    for (x, y), (u, v) in zip(dst, src):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        b += [u, v]
    coeffs = np.linalg.solve(np.array(a, float), np.array(b, float))
    return img.transform((nw, h), Image.PERSPECTIVE, tuple(coeffs),
                         Image.BICUBIC)


def shadow(img, blur, offset, alpha):
    s = Image.new('RGBA', (img.width + blur * 4, img.height + blur * 4),
                  (0, 0, 0, 0))
    a = img.getchannel('A').point(lambda p: int(p * alpha))
    dark = Image.new('RGBA', img.size, (8, 8, 20, 255))
    dark.putalpha(a)
    s.alpha_composite(dark, (blur * 2 + offset[0], blur * 2 + offset[1]))
    return s.filter(ImageFilter.GaussianBlur(blur))


def tilted_phone(screen, width, turn=0.10, flip=False):
    body = side(phone(screen, width), max(10, width // 60))
    if flip:
        body = body.transpose(Image.FLIP_LEFT_RIGHT)
    p = perspective(body, turn)
    if flip:
        p = p.transpose(Image.FLIP_LEFT_RIGHT)
    return p


def place(canvas, img, xy, blur=40, offset=(30, 50), alpha=0.45):
    sh = shadow(img, blur, offset, alpha)
    canvas.alpha_composite(sh, (xy[0] - blur * 2, xy[1] - blur * 2))
    canvas.alpha_composite(img, xy)


# ---------------------------------------------------------------- slides

W, H = 1440, 2560


def wrap(draw, text, f, width):
    words, lines, line = text.split(), [], ''
    for word in words:
        t = (line + ' ' + word).strip()
        if draw.textlength(t, font=f) <= width:
            line = t
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def slide(screen, title, sub, dark, tilt=0.10, flip=False):
    bg, ink, muted = (NIGHT, NIGHT_INK, NIGHT_MUTED) if dark else \
        (PAPER, PAPER_INK, PAPER_MUTED)
    c = Image.new('RGBA', (W, H), bg + (255,))
    d = ImageDraw.Draw(c)
    # One quiet shape: a large soft disc behind the phone.
    disc = CORAL if dark else (232, 222, 204)
    d.ellipse((W * 0.18, H * 0.30, W * 1.35, H * 1.15),
              fill=tuple(int(disc[i] * 0.16 + bg[i] * 0.84) for i in range(3))
              if dark else disc)

    tf, sf = serif(112, 700), sans(48, 420)
    y = 150
    for line in wrap(d, title, tf, W - 220):
        d.text((110, y), line, font=tf, fill=ink)
        y += 138
    # A short coral rule ties the slides to the brand.
    d.rounded_rectangle((112, y + 18, 212, y + 28), radius=5, fill=CORAL)
    y += 70
    for line in wrap(d, sub, sf, W - 240):
        d.text((110, y), line, font=sf, fill=muted)
        y += 66

    p = tilted_phone(screen, 1060, tilt, flip)
    x = (W - p.width) // 2 + (40 if not flip else -40)
    place(c, p, (x, max(y + 90, 760)))
    return c.convert('RGB')


def feature_graphic(left_screen, right_screen):
    fw, fh = 1024, 500
    c = Image.new('RGBA', (fw, fh), NIGHT + (255,))
    d = ImageDraw.Draw(c)
    d.ellipse((560, -120, 1240, 560), fill=(58, 38, 72))
    d.ellipse((640, 60, 1180, 640), fill=(84, 46, 70))

    icon = Image.open('docs/logo/twofold-icon-512.png').convert('RGBA')
    icon = icon.resize((104, 104), Image.LANCZOS)
    c.alpha_composite(icon, (64, 92), )
    d.text((186, 144), 'TwoFold', font=serif(78, 700), fill=NIGHT_INK,
           anchor='lm')
    y = 236
    for line in ['Read it. Hear it.', 'Never lose your place.']:
        d.text((66, y), line, font=serif(40, 500), fill=GOLD)
        y += 54
    d.text((66, 372), 'Ebooks and audiobooks in one app,', font=sans(23, 420),
           fill=NIGHT_MUTED)
    d.text((66, 404), 'with thousands of free classics.', font=sans(23, 420),
           fill=NIGHT_MUTED)

    # A fan of first-edition covers (public domain) beside the phone.
    for k, angle, x, y in [('gatsby', 12, 838, 66), ('oz', 2, 812, 170),
                           ('dracula', -9, 790, 278)]:
        cover = Image.open(f'docs/store/covers/{k}.jpg').convert('RGBA')
        cover = cover.resize((128, 192), Image.LANCZOS)
        cover.putalpha(rounded_mask(cover.size, 8))
        cover = cover.rotate(angle, expand=True, resample=Image.BICUBIC)
        place(c, cover, (x, y), blur=12, offset=(6, 10), alpha=0.5)
    front = tilted_phone(left_screen, 270, 0.12)
    place(c, front, (590, 110), blur=18, offset=(14, 22), alpha=0.55)
    return c.convert('RGB')


def main():
    os.makedirs(OUT, exist_ok=True)
    caps = sorted(glob.glob('assets/screenshots/*.png'))
    phone_find = repaint_now_playing(Image.open(caps[3]))
    mock = {n: Image.open(f'build/mock/{n}.png').convert('RGB')
            for n in ['library', 'reader', 'listen', 'places', 'details',
                      'home_night']}

    slides = [
        (mock['library'], 'Your ebook and audiobook, together',
         'Come back to the same page and the same minute, every time.', True),
        (mock['reader'], 'Read with the audio at hand',
         'Play, skip and scrub without leaving the page.', False),
        (mock['listen'], 'A proper audiobook player',
         'Chapters, speed, a sleep timer and lock screen controls.', False),
        (phone_find, 'Thousands of free classics',
         'Project Gutenberg, the Internet Archive, Wikisource and Unglue.it.',
         True),
        (mock['details'], 'Everything about the book',
         'Ratings, descriptions and subjects from Open Library, kept with it.',
         False),
        (mock['places'], 'Save a place, keep the minute',
         'Each place you save holds the page and the second of audio.', True),
        (mock['home_night'], 'Easy on the eyes at night',
         'Paper, Sepia and Night, with five quiet accent colours.', False),
    ]
    for i, (shot, title, sub, dark) in enumerate(slides, 1):
        slide(shot, title, sub, dark, flip=i % 2 == 0).save(
            f'{OUT}/screenshot-{i}.png', optimize=True)
        print('screenshot', i)
    feature_graphic(mock['library'], mock['listen']).save(
        f'{OUT}/feature-graphic.png', optimize=True)
    print('feature graphic')


if __name__ == '__main__':
    main()
