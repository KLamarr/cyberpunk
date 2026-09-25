#!/usr/bin/env python3
"""Genera le texture procedurali a bassa risoluzione (stile Dark Engine / System Shock 2).

Uso:  python3 tools/gen_textures.py   (dalla cartella del progetto)
      python3 tools/gen_textures.py npc_atlas   (solo le funzioni indicate)
Tutte le texture sono 64x64 (o multipli) e vanno campionate con filtro nearest.
Rigenerarle è deterministico (seed fisso).
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1998)  # anno di Thief :)

# ---------------------------------------------------------------- utilità
def value_noise(w, h, cell, octaves=3, seed_off=0):
    """Value noise tileable, [0,1]."""
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = max(1, cell // (2 ** o))
        gw, gh = max(1, w // c), max(1, h // c)
        g = rng.random((gh, gw))
        ys = np.arange(h) / c
        xs = np.arange(w) / c
        y0 = np.floor(ys).astype(int) % gh
        x0 = np.floor(xs).astype(int) % gw
        y1 = (y0 + 1) % gh
        x1 = (x0 + 1) % gw
        fy = (ys - np.floor(ys))[:, None]
        fx = (xs - np.floor(xs))[None, :]
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        a = g[y0][:, x0]; b = g[y0][:, x1]; cc = g[y1][:, x0]; d = g[y1][:, x1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy)
        tot += amp
        amp *= 0.5
    return out / tot


def grain(w, h, s=1.0):
    return (rng.random((h, w)) - 0.5) * s


def rgb(img):
    return np.clip(img, 0, 255).astype(np.uint8)


def save(name, arr):
    arr = rgb(arr)
    mode = "RGBA" if arr.shape[2] == 4 else "RGB"
    Image.fromarray(arr, mode).save(os.path.join(OUT, name + ".png"))


def base(w, h, color):
    return np.ones((h, w, 3)) * np.array(color, dtype=float)


def shade(img, mask, amount):
    img[mask] = img[mask] * amount
    return img


def bevel_rect(img, x0, y0, x1, y1, light=1.25, dark=0.6):
    """Cornice in rilievo: bordo alto/sinistro chiaro, basso/destro scuro."""
    img[y0, x0:x1] *= light
    img[y0:y1, x0] *= light
    img[y1 - 1, x0:x1] *= dark
    img[y0:y1, x1 - 1] *= dark


def rivet(img, x, y, col=(150, 155, 160)):
    img[y, x] = col
    img[y + 1, x + 1] = np.array(col) * 0.45
    img[y, x + 1] = np.array(col) * 0.75


def grime(img, strength=0.35, cell=16):
    n = value_noise(img.shape[1], img.shape[0], cell, 4)
    img *= (1 - strength) + strength * n[:, :, None] * 1.4
    return img


def streaks(img, count=6, strength=0.25):
    h, w = img.shape[:2]
    for _ in range(count):
        x = rng.integers(0, w)
        y0 = rng.integers(0, h // 2)
        ln = rng.integers(h // 4, h)
        for y in range(y0, min(h, y0 + ln)):
            f = 1 - strength * (1 - (y - y0) / ln)
            img[y, x] *= f
            if rng.random() < 0.3 and x + 1 < w:
                img[y, x + 1] *= (1 + f) / 2
    return img


# ---------------------------------------------------------------- font 5x7
FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
    ">": ["01000", "00100", "00010", "00001", "00010", "00100", "01000"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    " ": ["00000"] * 7,
}


def text_width(s, spacing=1):
    return len(s) * (5 + spacing) - spacing


def draw_text(img, s, x, y, col, spacing=1, shadow=None):
    for i, ch in enumerate(s.upper()):
        g = FONT.get(ch, FONT[" "])
        for r, row in enumerate(g):
            for c, bit in enumerate(row):
                if bit == "1":
                    px, py = x + i * (5 + spacing) + c, y + r
                    if 0 <= px < img.shape[1] and 0 <= py < img.shape[0]:
                        if shadow is not None and py + 1 < img.shape[0] and px + 1 < img.shape[1]:
                            img[py + 1, px + 1, :3] = shadow
                        img[py, px, :3] = col


def draw_text_centered(img, s, y, col, shadow=None):
    x = (img.shape[1] - text_width(s)) // 2
    draw_text(img, s, x, y, col, shadow=shadow)


# ---------------------------------------------------------------- texture
def wall_panel():
    w = h = 64
    img = base(w, h, (74, 82, 92))
    img += grain(w, h, 10)[:, :, None]
    for (x0, y0, x1, y1) in [(0, 0, 32, 40), (32, 0, 64, 40), (0, 40, 64, 64)]:
        bevel_rect(img, x0, y0, x1, y1)
    # fascia bassa più scura (battiscopa)
    img[40:64] *= 0.78
    img[52:53, :] *= 0.5
    for x, y in [(3, 3), (28, 3), (35, 3), (60, 3), (3, 35), (28, 35), (35, 35), (60, 35), (4, 44), (58, 44)]:
        rivet(img, x, y)
    # piccola targhetta
    img[16:22, 40:56] = (58, 64, 70)
    img[17:21, 41:55] *= 1.3
    grime(img, 0.35)
    streaks(img, 5, 0.3)
    save("wall_panel", img)


def wall_concrete():
    w = h = 64
    n = value_noise(w, h, 16, 4)
    img = base(w, h, (86, 84, 78)) * (0.75 + 0.5 * n)[:, :, None]
    img += grain(w, h, 14)[:, :, None]
    # blocchi 32x16 sfalsati
    for row in range(4):
        y = row * 16
        img[y, :] *= 0.55
        off = 0 if row % 2 == 0 else 16
        for x in range(off, 64 + off, 32):
            img[y:y + 16, x % 64] *= 0.6
    # macchie di umidità in basso
    stain = value_noise(w, h, 8, 3)
    grad = np.linspace(0, 1, h)[:, None] ** 2
    img *= (1 - 0.35 * grad * stain)[:, :, None]
    # crepa
    x, y = 44, 4
    for _ in range(26):
        img[y % 64, x % 64] *= 0.45
        y += 1
        x += rng.integers(-1, 2)
    streaks(img, 7, 0.22)
    save("wall_concrete", img)


def wall_tech():
    w = h = 64
    img = base(w, h, (52, 62, 60))
    img += grain(w, h, 8)[:, :, None]
    bevel_rect(img, 0, 0, 64, 64, 1.2, 0.55)
    bevel_rect(img, 2, 2, 30, 62, 1.15, 0.7)
    bevel_rect(img, 34, 2, 62, 62, 1.15, 0.7)
    # feritoie di ventilazione
    for y in range(8, 30, 4):
        img[y, 6:26] = (18, 22, 22)
        img[y + 1, 6:26] *= 1.2
    # cavi
    for x in (40, 44, 47):
        img[4:60, x] = (30, 34, 40)
        img[4:60, x + 1] = (70, 64, 50) if x == 44 else (40, 46, 52)
    # quadro con LED
    img[36:56, 6:26] = (34, 38, 40)
    bevel_rect(img, 6, 36, 26, 56, 1.3, 0.6)
    for i, c in enumerate([(40, 220, 90), (40, 220, 90), (230, 170, 40), (40, 220, 90), (220, 50, 40)]):
        img[40, 9 + i * 3] = c
    img[46:52, 9:23] = (20, 60, 50)
    grime(img, 0.3)
    save("wall_tech", img)


def wall_tile():
    w = h = 64
    img = base(w, h, (150, 152, 140))
    for ty in range(0, 64, 8):
        for tx in range(0, 64, 8):
            v = 0.85 + rng.random() * 0.2
            img[ty:ty + 8, tx:tx + 8] *= v
    img[::8, :] *= 0.55
    img[:, ::8] *= 0.55
    grime(img, 0.45, 12)
    streaks(img, 9, 0.35)
    img[48:, :] *= 0.8
    save("wall_tile", img)


def floor_tiles(name="floor_tiles", col=(64, 66, 68), grout=0.5):
    w = h = 64
    img = base(w, h, col)
    for ty in (0, 32):
        for tx in (0, 32):
            img[ty:ty + 32, tx:tx + 32] *= 0.9 + rng.random() * 0.2
            bevel_rect(img, tx, ty, tx + 32, ty + 32, 1.12, 0.8)
    img[0, :] *= grout
    img[:, 0] *= grout
    img[32, :] *= grout
    img[:, 32] *= grout
    img += grain(w, h, 9)[:, :, None]
    # graffi
    for _ in range(6):
        x, y = rng.integers(0, 64, 2)
        dx = rng.choice([-1, 1])
        for i in range(rng.integers(4, 12)):
            img[(y + i) % 64, (x + i * dx) % 64] *= 1.25
    grime(img, 0.35, 16)
    save(name, img)


def floor_grate():
    w = h = 64
    img = base(w, h, (60, 62, 60))
    img += grain(w, h, 12)[:, :, None]
    # griglia: fori scuri 6x6 con barre
    for y in range(0, 64, 8):
        for x in range(0, 64, 8):
            img[y + 2:y + 7, x + 2:x + 7] = (14, 15, 16)
            img[y + 2, x + 2:x + 7] = (22, 23, 24)
            img[y + 1, x + 1:x + 8] *= 1.3
    # travi portanti
    img[31:33, :] = (40, 42, 44)
    img[30, :] *= 1.4
    img[:, 31:33] = (40, 42, 44)
    grime(img, 0.3)
    # ruggine
    rust = value_noise(w, h, 16, 3)
    mask = rust > 0.62
    img[mask] = img[mask] * 0.5 + np.array([90, 50, 25]) * 0.5
    save("floor_grate", img)


def floor_carpet():
    w = h = 64
    n = value_noise(w, h, 4, 2)
    img = base(w, h, (38, 62, 66)) * (0.8 + 0.35 * n)[:, :, None]
    img += grain(w, h, 18)[:, :, None]
    for i in range(0, 64, 16):
        img[i:i + 1, :] *= 1.25
        img[:, i:i + 1] *= 1.25
        img[i + 8, ::2] *= 0.8
    grime(img, 0.4, 32)
    save("floor_carpet", img)


def ceiling_panel():
    w = h = 64
    img = base(w, h, (112, 114, 110))
    img += grain(w, h, 8)[:, :, None]
    for ty in (0, 32):
        for tx in (0, 32):
            img[ty:ty + 32, tx:tx + 32] *= 0.9 + rng.random() * 0.15
            for _ in range(40):
                x, y = rng.integers(2, 30, 2)
                img[ty + y, tx + x] *= 0.7
    img[0:2, :] = (60, 62, 60)
    img[:, 0:2] = (60, 62, 60)
    img[31:33, :] = (60, 62, 60)
    img[:, 31:33] = (60, 62, 60)
    # pannello macchiato
    st = value_noise(w, h, 16, 3)
    img *= (1 - 0.3 * (st > 0.6))[:, :, None]
    save("ceiling_panel", img)


def ceiling_dark():
    w = h = 64
    img = base(w, h, (38, 40, 44))
    img += grain(w, h, 8)[:, :, None]
    # tubi orizzontali
    for (y, r, col) in [(10, 4, (70, 66, 58)), (30, 3, (58, 70, 74)), (48, 5, (64, 58, 52))]:
        for dy in range(-r, r + 1):
            f = 1 - (dy / (r + 1)) ** 2
            img[y + dy, :] = np.array(col) * (0.5 + 0.7 * f)
        img[y - r - 1, :] *= 0.4
        # fascette
        for x in range(4, 64, 16):
            img[y - r:y + r + 1, x:x + 2] *= 0.6
    grime(img, 0.35)
    save("ceiling_dark", img)


def hazard():
    w = h = 64
    img = base(w, h, (20, 20, 18))
    for y in range(h):
        for x in range(w):
            if ((x + y) // 8) % 2 == 0:
                img[y, x] = (196, 160, 30)
    img += grain(w, h, 20)[:, :, None]
    wear = value_noise(w, h, 8, 3)
    m = wear > 0.6
    img[m] = img[m] * 0.4 + np.array([80, 80, 78]) * 0.6
    grime(img, 0.35)
    save("hazard", img)


def door(name="door", col=(84, 90, 96), stripe=(190, 150, 30), label=None):
    w, h = 64, 96
    img = base(w, h, col)
    img += grain(w, h, 8)[:, :, None]
    bevel_rect(img, 0, 0, 64, 96, 1.3, 0.5)
    img[:, 31:33] = (20, 22, 24)  # giunto centrale
    bevel_rect(img, 4, 6, 29, 40, 1.2, 0.7)
    bevel_rect(img, 35, 6, 60, 40, 1.2, 0.7)
    # fascia di pericolo
    for y in range(52, 60):
        for x in range(64):
            if ((x + y) // 4) % 2 == 0:
                img[y, x] = stripe
            else:
                img[y, x] = (24, 24, 22)
    img[50:52] *= 0.6
    img[60:62] *= 0.6
    bevel_rect(img, 4, 66, 29, 92, 1.2, 0.7)
    bevel_rect(img, 35, 66, 60, 92, 1.2, 0.7)
    if label:
        draw_text(img, label, 40, 14, (210, 210, 200))
    grime(img, 0.3)
    streaks(img, 5, 0.3)
    save(name, img)


def crate():
    w = h = 64
    img = base(w, h, (60, 72, 58))
    img += grain(w, h, 10)[:, :, None]
    img[0:6, :] = (78, 80, 82)
    img[58:64, :] = (78, 80, 82)
    img[:, 0:6] = (78, 80, 82)
    img[:, 58:64] = (78, 80, 82)
    bevel_rect(img, 0, 0, 64, 64, 1.3, 0.5)
    bevel_rect(img, 6, 6, 58, 58, 0.6, 1.2)
    for x, y in [(2, 2), (60, 2), (2, 60), (60, 60)]:
        rivet(img, x, y)
    draw_text(img, "SB-14", 18, 20, (200, 196, 150))
    draw_text(img, "!", 29, 36, (200, 150, 40))
    grime(img, 0.4)
    save("crate", img)


def screen(name, bg, fg, lines=True):
    w = h = 64
    img = base(w, h, bg)
    if lines:
        for y in range(4, 60, 5):
            ln = rng.integers(10, 56)
            for x in range(4, 4 + ln):
                if rng.random() < 0.8:
                    img[y, x] = fg
                    if rng.random() < 0.5:
                        img[y + 1, x] = np.array(fg) * 0.6
    else:
        for i in range(6):
            hh = rng.integers(6, 40)
            img[58 - hh:58, 6 + i * 9:12 + i * 9] = fg
        img[4:6, 4:60] = fg
    img[::2] *= 0.82  # scanline
    save(name, img)


def server():
    w = h = 64
    img = base(w, h, (26, 28, 32))
    emit = np.zeros((h, w, 3))
    for u in range(0, 64, 8):
        img[u:u + 8, 2:62] = (42, 46, 52)
        bevel_rect(img, 2, u, 62, u + 8, 1.3, 0.5)
        img[u + 3:u + 5, 8:40] = (14, 14, 16)  # slot dischi
        for k in range(5):
            c = [(40, 230, 90), (40, 230, 90), (240, 170, 30), (40, 160, 240)][rng.integers(0, 4)]
            if rng.random() < 0.8:
                img[u + 3, 46 + k * 3] = c
                emit[u + 3, 46 + k * 3] = c
    img[:, 0:2] = (60, 62, 66)
    img[:, 62:64] = (60, 62, 66)
    save("server", img)
    save("server_emit", emit)


def vent_grate():
    w = h = 64
    img = np.zeros((h, w, 4))
    img[:, :, :3] = (70, 72, 70)
    img[:, :, 3] = 255
    img[:, :, :3] += grain(w, h, 10)[:, :, None]
    for y in range(6, 58, 6):
        img[y:y + 3, 5:59, 3] = 0  # fori
        img[y + 3, 5:59, :3] *= 0.6
    bevel_rect(img[:, :, :3], 0, 0, 64, 64, 1.3, 0.5)
    for x, y in [(2, 2), (60, 2), (2, 60), (60, 60)]:
        img[y, x, :3] = (140, 140, 140)
    save("vent_grate", img)


def light_panel():
    w = h = 64
    img = base(w, h, (236, 240, 232))
    img[::16, :] = (150, 152, 150)
    img[:, ::16] = (150, 152, 150)
    img[0:2, :] = (90, 90, 90)
    img[:, 0:2] = (90, 90, 90)
    save("light_panel", img)


def rust_metal():
    w = h = 64
    n = value_noise(w, h, 16, 4)
    img = base(w, h, (78, 70, 62)) * (0.75 + 0.45 * n)[:, :, None]
    img += grain(w, h, 12)[:, :, None]
    r = value_noise(w, h, 8, 3)
    m = r > 0.55
    img[m] = img[m] * 0.4 + np.array([110, 58, 28]) * 0.6
    img[0:2, :] *= 0.5
    img[:, 0:2] *= 0.5
    img[31:33, :] *= 0.55
    for x in range(4, 64, 16):
        rivet(img, x, 4, (130, 120, 110))
        rivet(img, x, 36, (130, 120, 110))
    save("rust_metal", img)


def armor():
    w = h = 64
    img = base(w, h, (46, 50, 62))
    img += grain(w, h, 12)[:, :, None]
    for y in range(0, 64, 16):
        img[y, :] *= 0.5
        img[y + 1, :] *= 1.3
    img[:, 31:33] *= 0.6
    img[20:28, 36:50] = (120, 110, 40)  # mostrina
    draw_text(img, "S", 40, 21, (20, 20, 20))
    grime(img, 0.3)
    save("armor", img)


def sign(name, text, w=128, h=16, fg=(80, 230, 220), bg=(10, 18, 22)):
    img = base(w, h, bg)
    img += grain(w, h, 6)[:, :, None]
    bevel_rect(img, 0, 0, w, h, 1.8, 0.4)
    draw_text_centered(img, text, (h - 7) // 2, fg, shadow=np.array(fg) * 0.3)
    save(name, img)


def poster():
    w, h = 32, 64
    img = base(w, h, (180, 186, 190))
    img[0:40] = (24, 40, 60)
    # logo: ala stilizzata
    for i in range(12):
        img[10 + i, 16 - i // 2:17 + i] = (120, 220, 230) if i % 3 else (240, 250, 250)
    img[24:26, 6:26] = (240, 250, 250)
    draw_text(img, "IL", 11, 44, (30, 40, 50))
    draw_text(img, "FUTURO", 0, 52, (30, 40, 50), spacing=0)
    grime(img, 0.35, 8)
    save("poster", img)


def vending():
    w, h = 64, 128
    img = base(w, h, (60, 20, 50))
    img += grain(w, h, 10)[:, :, None]
    img[8:88, 6:44] = (20, 26, 34)  # vetrina
    for row in range(5):
        y = 12 + row * 15
        img[y + 10:y + 12, 8:42] = (70, 74, 80)
        for k in range(4):
            c = [(200, 40, 40), (40, 180, 200), (230, 200, 40), (120, 230, 80)][(row + k) % 4]
            img[y + 3:y + 10, 10 + k * 8:15 + k * 8] = c
    img[10:86, 40:43] = (120, 140, 160)  # riflesso
    img[8:40, 48:60] = (230, 60, 180)  # pannello luminoso
    draw_text(img, "K", 51, 12, (255, 240, 255))
    draw_text(img, "N", 51, 24, (255, 240, 255))
    img[46:70, 48:60] = (30, 30, 34)
    img[96:112, 10:40] = (10, 10, 12)
    bevel_rect(img, 0, 0, 64, 128, 1.4, 0.5)
    save("vending", img)


def keypad():
    w = h = 32
    img = base(w, h, (40, 42, 46))
    bevel_rect(img, 0, 0, 32, 32, 1.4, 0.5)
    img[3:9, 4:28] = (30, 80, 50)
    for r in range(4):
        for c in range(3):
            x, y = 6 + c * 7, 11 + r * 5
            img[y:y + 4, x:x + 5] = (120, 124, 128)
            img[y + 3, x:x + 5] = (60, 62, 64)
    save("keypad", img)


def graffiti():
    w, h = 64, 32
    img = np.zeros((h, w, 4))
    col = np.array([230, 40, 120])
    draw = np.zeros((h, w, 3))
    draw_text(draw, "NO", 4, 4, (1, 1, 1), spacing=2)
    draw_text(draw, "CALMA", 12, 16, (1, 1, 1), spacing=2)
    m = draw[:, :, 0] > 0.5
    # "spray": ingrossa
    big = m.copy()
    big[1:, :] |= m[:-1, :]
    big[:, 1:] |= m[:, :-1]
    img[big, :3] = col
    img[big, 3] = 230
    # colature
    for x in np.where(big.any(axis=0))[0][::5]:
        ys = np.where(big[:, x])[0]
        if len(ys) and rng.random() < 0.6:
            y0 = ys.max()
            ln = rng.integers(2, 7)
            img[y0:min(h, y0 + ln), x, :3] = col
            img[y0:min(h, y0 + ln), x, 3] = 200
    save("graffiti", img)


def locker():
    w, h = 64, 128
    img = base(w, h, (70, 86, 96))
    img += grain(w, h, 8)[:, :, None]
    for x0 in (0, 32):
        bevel_rect(img, x0, 0, x0 + 32, 128, 1.3, 0.5)
        for y in range(10, 30, 4):
            img[y:y + 2, x0 + 8:x0 + 24] = (20, 24, 28)
        img[60:70, x0 + 26:x0 + 28] = (150, 150, 150)
    grime(img, 0.35)
    save("locker", img)


def desk():
    w = h = 64
    n = value_noise(w, h, 32, 2)
    img = base(w, h, (84, 82, 80)) * (0.85 + 0.3 * n)[:, :, None]
    img += grain(w, h, 6)[:, :, None]
    img[0:3, :] = (90, 92, 96)
    img[::16, :] *= 0.85  # giunti del laminato
    save("desk", img)


def glass_blue():
    w = h = 32
    img = base(w, h, (60, 150, 170))
    img[::4] *= 1.15
    img[:, 2:4] = (200, 240, 250)
    save("glass_blue", img)


def elevator_door():
    door("elevator_door", col=(96, 84, 64), stripe=(40, 160, 190), label="14")


def pipes():
    w = h = 32
    img = base(w, h, (70, 70, 66))
    for x in range(w):
        f = np.sin(np.pi * (x + 0.5) / w)
        img[:, x] *= 0.45 + 0.75 * f
    img[::8] *= 0.6
    img += grain(w, h, 8)[:, :, None]
    save("pipe", img)


def skin_face():
    """Visiera/volto: solo per il casco delle guardie (fronte)."""
    w = h = 32
    img = base(w, h, (30, 32, 36))
    img[12:18, 3:29] = (255, 255, 255)  # maschera della visiera (colorata dall'emission)
    save("helmet", img)


def npc_atlas():
    """Atlante degli NPC (128x128): 8 fasce da 16 px, una per SegmentShape.Band.
    Dettaglio quasi neutro: il colore lo danno i vertex color della tavolozza.
    u = giro attorno al segmento (0 = dietro, 0.5 = davanti), v = lungo il segmento
    (in alto l'estremità, in basso l'attacco). Ha un suo generatore casuale, così
    rigenerarlo non cambia le altre texture."""
    r = np.random.default_rng(2000)
    w, bh = 128, 16
    img = np.zeros((bh * 8, w, 3))

    def noise(h, s):
        return (r.random((h, w)) - 0.5) * s

    # 0 tessuto: trama, cucitura davanti e dietro, pieghe
    b = np.ones((bh, w)) * 196 + noise(bh, 14)
    b[::2, ::2] += 6
    b[:, 63:65] *= 0.72
    b[:, 0] *= 0.8
    b[:, 127] *= 0.8
    fold = np.sin(np.arange(w) / w * np.pi * 6) * 7
    b += fold[None, :]
    img[0:16] = b[:, :, None]
    # 1 armatura: piastre con bordi in rilievo e rivetti
    b = np.ones((bh, w)) * 190 + noise(bh, 10)
    for x0 in range(0, w, 32):
        b[:, x0] *= 0.55
        b[:, x0 + 1] *= 1.18
    b[0, :] *= 1.2
    b[1, :] *= 1.1
    b[bh - 1, :] *= 0.55
    b[7, :] *= 0.8
    for x0 in range(0, w, 32):
        for y0 in (3, 12):
            b[y0, x0 + 4] = 235
            b[y0 + 1, x0 + 5] = 110
    img[16:32] = b[:, :, None]
    # 2 pelle
    b = np.ones((bh, w)) * 226 + noise(bh, 8)
    img[32:48] = b[:, :, None]
    # 3 volto: pelle con i tratti al centro (u = 0.5 = davanti)
    b = np.ones((bh, w, 3)) * 226 + noise(bh, 8)[:, :, None]
    c = 64
    b[5, c - 7:c - 2] *= 0.78                   # sopracciglia
    b[5, c + 2:c + 7] *= 0.78
    for ex in (c - 6, c + 3):                   # occhi
        b[7, ex:ex + 3] = (70, 62, 58)
        b[7, ex + 1] = (28, 24, 22)
        b[8, ex:ex + 3] *= 0.86
    b[8:11, c - 1:c + 1] *= 0.9                 # naso
    b[10, c - 2:c + 2] *= 0.8
    b[12, c - 3:c + 3] = (150, 88, 82)          # bocca
    b[13, c - 2:c + 2] *= 0.88
    for ex in (32, 96):                         # orecchie
        b[7:11, ex - 1:ex + 1] *= 0.8
    img[48:64] = b
    # 4 gomma: stivali e guanti, costolature
    b = np.ones((bh, w)) * 150 + noise(bh, 18)
    b[::3, :] *= 0.72
    b[bh - 2:, :] *= 0.6
    img[64:80] = b[:, :, None]
    # 5 metallo spazzolato
    b = np.ones((bh, w)) * 205 + noise(bh, 10)
    b += (r.random((bh, 1)) - 0.5) * 40
    b[2, :] += 30
    img[80:96] = b[:, :, None]
    # 6 luce (parti emissive): righe di scansione
    b = np.ones((bh, w)) * 235
    b[::2, :] = 190
    b[:, ::8] *= 0.85
    img[96:112] = b[:, :, None]
    # 7 capelli: ciocche verticali
    b = np.ones((bh, w)) * 180
    strands = (r.random(w) - 0.5) * 70
    b += strands[None, :]
    b += noise(bh, 20)
    b[bh - 1, :] *= 0.7
    img[112:128] = b[:, :, None]
    save("npc_atlas", img)


def main():
    wall_panel(); wall_concrete(); wall_tech(); wall_tile()
    floor_tiles(); floor_tiles("floor_lab", (138, 146, 150), 0.6)
    floor_grate(); floor_carpet()
    ceiling_panel(); ceiling_dark()
    hazard(); door(); elevator_door(); crate()
    screen("screen_green", (4, 18, 10), (60, 240, 120))
    screen("screen_blue", (6, 14, 34), (80, 170, 255), lines=False)
    screen("screen_amber", (20, 12, 2), (255, 176, 40))
    server(); vent_grate(); light_panel(); rust_metal(); armor()
    sign("sign_seraph", "SERAPH BIOTEK", 128, 16)
    sign("sign_lab", "LAB C > SERAPH-7", 128, 16, (240, 90, 80))
    sign("sign_sec", "SICUREZZA", 64, 16, (240, 200, 80))
    sign("sign_relax", "SALA RELAX", 64, 16, (120, 230, 140))
    sign("sign_store", "MAGAZZINO", 64, 16, (200, 200, 200))
    sign("sign_lift", "SERVIZIO 14", 64, 16, (80, 200, 240))
    poster(); vending(); keypad(); graffiti(); locker(); desk(); glass_blue(); pipes(); skin_face()
    npc_atlas()
    print("texture generate in", os.path.normpath(OUT))


if __name__ == "__main__":
    import sys
    # python3 tools/gen_textures.py npc_atlas  -> rigenera solo le texture indicate
    if len(sys.argv) > 1:
        for name in sys.argv[1:]:
            globals()[name]()
    else:
        main()
