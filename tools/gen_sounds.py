#!/usr/bin/env python3
"""Genera gli effetti sonori sintetici (WAV 22050 Hz mono 16 bit).

Uso:  python3 tools/gen_sounds.py   (dalla cartella del progetto)
Nessun campione esterno: tutto è rumore filtrato, oscillatori e inviluppi,
che al sample rate basso restituisce un suono "anni '90" coerente con la grafica.
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(451)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, d=0.2, curve=4.0):
    """Attacco lineare + decadimento esponenziale (d = tempo di decadimento)."""
    x = np.arange(n) / SR
    e = np.minimum(1.0, x / max(a, 1e-4))
    e *= np.exp(-np.maximum(0, x - a) / max(d, 1e-4) * (curve / 4.0) * 4.0 / 4.0)
    return e


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def resonator(x, freq, decay):
    """Filtro risonante a due poli: fa "suonare" il metallo."""
    r = np.exp(-1.0 / (decay * SR))
    w = 2 * np.pi * freq / SR
    a1, a2 = -2 * r * np.cos(w), r * r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i in range(len(x)):
        v = x[i] - a1 * y1 - a2 * y2
        y[i] = v
        y2, y1 = y1, v
    return y / (np.max(np.abs(y)) + 1e-9)


def sine(f, d, phase=0.0):
    tt = t(d)
    if callable(f):
        ph = 2 * np.pi * np.cumsum(f(tt)) / SR
    else:
        ph = 2 * np.pi * f * tt
    return np.sin(ph + phase)


def square(f, d):
    return np.sign(sine(f, d))


def saw(f, d):
    tt = t(d)
    ph = np.cumsum(f(tt) if callable(f) else np.full_like(tt, f)) / SR
    return 2 * (ph % 1.0) - 1


def pad(x, d):
    n = int(SR * d)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*xs):
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=float)
    peak = np.max(np.abs(x)) + 1e-9
    x = x / peak * gain
    # fade out anti-click
    f = min(len(x), 64)
    x[-f:] *= np.linspace(1, 0, f)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


# ---------------------------------------------------------------- passi
def steps():
    for i in range(2):
        n = noise(0.18)
        # metallo: colpo + risonanza
        m = resonator(n * env(len(n), 0.001, 0.01), 520 + i * 90, 0.05) * 0.6
        m += bandpass(n, 800, 4000) * env(len(n), 0.001, 0.02)
        m += resonator(n * env(len(n), 0.001, 0.005), 1830 + i * 140, 0.03) * 0.3
        save(f"step_metal{i}", m * env(len(m), 0.001, 0.05), 0.6)
        # grata: tintinnio
        second = np.concatenate([np.zeros(int(SR * 0.025)), resonator(n * env(len(n), 0.001, 0.003), 1500 - i * 100, 0.03)])
        g = mix(resonator(n * env(len(n), 0.001, 0.004), 1100 + i * 200, 0.04), second)
        save(f"step_grate{i}", g * 0.8, 0.55)
        # cemento: tonfo sordo
        c = lowpass(n, 700 + i * 150) * env(len(n), 0.002, 0.03)
        c += lowpass(noise(0.18), 3000) * env(len(n), 0.001, 0.008) * 0.3
        save(f"step_concrete{i}", c, 0.55)
        # moquette: fruscio morbido
        s = bandpass(n, 200, 900) * env(len(n), 0.01, 0.04)
        save(f"step_carpet{i}", s, 0.35)


def land():
    n = noise(0.35)
    x = lowpass(n, 300) * env(len(n), 0.002, 0.08) + resonator(n * env(len(n), 0.001, 0.01), 180, 0.08) * 0.4
    save("land", x, 0.8)


# ---------------------------------------------------------------- porte e dispositivi
def door_open():
    d = 0.9
    tt = t(d)
    hiss = bandpass(noise(d), 1500, 6000) * np.exp(-tt * 5) * 0.5
    motor = saw(lambda x: 70 + 50 * np.minimum(x / 0.5, 1), d) * 0.3
    motor = lowpass(motor, 900) * np.minimum(1, (d - tt) * 5) * np.minimum(1, tt * 20)
    thunk = resonator(noise(d) * env(int(SR * d), 0.001, 0.01), 90, 0.1)
    thunk = np.concatenate([np.zeros(int(SR * 0.6)), thunk[:int(SR * 0.3)]]) * 0.6
    save("door_open", mix(hiss, motor, thunk), 0.75)


def door_locked():
    d = 0.35
    x = square(110, d) * 0.5 + square(113, d) * 0.5
    x = lowpass(x, 1800) * env(int(SR * d), 0.005, 0.25)
    save("door_locked", x, 0.5)


def beep(name, freqs, dur=0.08, gap=0.03, wave_fn=sine, vol=0.5):
    parts = []
    for f in freqs:
        b = wave_fn(f, dur) * env(int(SR * dur), 0.002, dur * 0.8)
        parts.append(b)
        parts.append(np.zeros(int(SR * gap)))
    save(name, np.concatenate(parts), vol)


# ---------------------------------------------------------------- armi
def gunshot(name, low=120, crack=0.012, tail=0.25, vol=0.95):
    d = 0.7
    n = noise(d)
    e_crack = env(len(n), 0.0005, crack)
    body = lowpass(n, 1600) * env(len(n), 0.001, 0.06)
    boom = sine(lambda x: low * np.exp(-x * 8) + 40, d) * env(len(n), 0.001, 0.09)
    tailn = bandpass(noise(d), 300, 2500) * env(len(n), 0.02, tail) * 0.25  # riverbero corridoio
    save(name, n * e_crack * 0.9 + body * 0.8 + boom * 0.9 + tailn, vol)


def reload():
    parts = []
    for f, g in [(1400, 0.12), (900, 0.35), (2200, 0.2)]:
        n = noise(0.08)
        parts.append(resonator(n * env(len(n), 0.001, 0.004), f, 0.03))
        parts.append(np.zeros(int(SR * g)))
    save("reload", np.concatenate(parts), 0.6)


def empty_click():
    n = noise(0.06)
    save("empty", resonator(n * env(len(n), 0.0005, 0.002), 2600, 0.02), 0.5)


def swing():
    d = 0.3
    tt = t(d)
    n = noise(d)
    x = np.zeros(len(n))
    # passa-banda che sale e scende: "whoosh"
    for k, (lo, hi) in enumerate([(300, 900), (600, 1800), (400, 1200)]):
        seg = bandpass(n, lo, hi)
        w = np.exp(-((tt - 0.1 - k * 0.04) / 0.05) ** 2)
        x += seg * w
    save("swing", x, 0.45)


def hit_metal():
    n = noise(0.6)
    x = resonator(n * env(len(n), 0.0005, 0.004), 740, 0.25) + resonator(n * env(len(n), 0.0005, 0.003), 1910, 0.15) * 0.6
    x += resonator(n * env(len(n), 0.0005, 0.003), 3210, 0.08) * 0.4
    save("hit_metal", x * env(len(x), 0.0005, 0.3), 0.7)


def hit_flesh():
    n = noise(0.25)
    x = lowpass(n, 500) * env(len(n), 0.001, 0.04) + sine(lambda x: 90 * np.exp(-x * 10) + 50, 0.25) * env(len(n), 0.001, 0.06)
    save("hit_flesh", x, 0.75)


def ricochet():
    d = 0.35
    n = noise(d)
    x = n * env(len(n), 0.0005, 0.006) * 0.8
    x += sine(lambda tt: 3200 - 2200 * tt / d, d) * env(len(n), 0.002, 0.08) * 0.35
    save("impact", x, 0.5)


def turret_fire():
    d = 0.18
    n = noise(d)
    x = n * env(len(n), 0.0005, 0.008) + square(lambda tt: 900 * np.exp(-tt * 30) + 200, d) * env(len(n), 0.001, 0.03) * 0.5
    save("turret_fire", lowpass(x, 5000), 0.7)


def servo():
    d = 0.5
    x = saw(lambda tt: 220 + 160 * np.sin(tt * 9), d) * 0.4
    x = bandpass(x, 300, 2000) * np.minimum(1, t(d) * 20) * np.minimum(1, (d - t(d)) * 10)
    save("servo", x, 0.35)


# ---------------------------------------------------------------- ambiente
def alarm():
    d = 1.6
    tt = t(d)
    f = 520 + 260 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 1.25 * tt)))
    x = saw(lambda q: 520 + 260 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 1.25 * q))), d)
    x = lowpass(x, 2500)
    save("alarm", x, 0.5)


def ambient_drone():
    d = 8.0
    tt = t(d)
    # frequenze scelte per chiudere il loop senza click
    x = sine(55, d) * 0.35 + sine(110, d) * 0.15 + sine(82.5, d) * 0.12
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * tt / d * 2)
    n = lowpass(noise(d), 400) * 0.25
    fade = np.minimum(1, np.minimum(tt, d - tt) / 0.4)
    n *= fade
    x += n
    x += sine(60 * 3, d) * 0.03  # ronzio di rete
    save("ambient_drone", x, 0.5)


def server_hum():
    d = 4.0
    tt = t(d)
    x = sine(120, d) * 0.3 + sine(240, d) * 0.15 + sine(1875, d) * 0.03 * (0.5 + 0.5 * np.sin(2 * np.pi * tt))
    n = bandpass(noise(d), 800, 3000) * 0.08 * np.minimum(1, np.minimum(tt, d - tt) / 0.2)
    save("server_hum", x + n, 0.5)


def whisper():
    d = 2.2
    tt = t(d)
    n = noise(d)
    x = np.zeros(len(n))
    for f in (700, 1150, 2400):  # formanti "sussurrate"
        x += resonator(n, f * (1 + 0.1 * np.sin(tt[0] * 3)), 0.01) * 0.3
    envl = np.clip(np.sin(np.pi * tt / d), 0, 1) ** 1.5 * (0.6 + 0.4 * np.sin(2 * np.pi * 3.5 * tt))
    x = highpass(x, 400) * envl
    x += sine(lambda q: 80 - 20 * q / d, d) * 0.2 * envl
    save("whisper", x, 0.5)


# ---------------------------------------------------------------- oggetti
def pickup():
    beep("pickup", [880, 1320], 0.05, 0.01, vol=0.45)


def medpatch():
    d = 0.6
    x = bandpass(noise(d), 2000, 7000) * env(int(SR * d), 0.02, 0.25) * 0.6 + sine(lambda q: 400 + 400 * q, d) * env(int(SR * d), 0.01, 0.3) * 0.3
    save("medpatch", x, 0.5)


def glass_break():
    d = 0.8
    n = noise(d)
    x = np.zeros(len(n))
    for k in range(14):
        o = int(rng.uniform(0, 0.3) * SR)
        f = rng.uniform(2500, 7000)
        s = resonator(noise(0.2) * env(int(SR * 0.2), 0.0005, 0.002), f, 0.05) * rng.uniform(0.3, 1)
        x[o:o + len(s)] += s[:len(x) - o]
    x += highpass(n, 3000) * env(len(n), 0.001, 0.05) * 0.8
    save("glass_break", x, 0.6)


def grate_break():
    d = 0.9
    x = np.zeros(int(SR * d))
    for k in range(6):
        o = int(rng.uniform(0, 0.5) * SR)
        n = noise(0.3)
        s = resonator(n * env(len(n), 0.0005, 0.004), rng.uniform(400, 1400), 0.12) * rng.uniform(0.4, 1)
        x[o:o + len(s)] += s[:len(x) - o]
    save("grate_break", x, 0.7)


def grate_pry():
    d = 0.7
    tt = t(d)
    x = saw(lambda q: 180 + 60 * np.sin(q * 23) + rng.normal(0, 30, len(q)), d) * 0.4
    x = bandpass(x, 300, 1800) * np.minimum(1, tt * 10) * np.minimum(1, (d - tt) * 6)
    save("grate_pry", x, 0.4)


def clatter():
    for i in range(2):
        d = 0.5
        x = np.zeros(int(SR * d))
        for k in range(3 + i):
            o = int((0.06 * k + rng.uniform(0, 0.05)) * SR)
            n = noise(0.2)
            s = resonator(n * env(len(n), 0.0005, 0.003), rng.uniform(900, 2600), 0.05) * (1.0 / (k + 1))
            x[o:o + len(s)] += s[:len(x) - o]
        save(f"clatter{i}", x, 0.6)


def body_fall():
    d = 0.6
    n = noise(d)
    x = lowpass(n, 250) * env(len(n), 0.002, 0.12) + lowpass(noise(d), 800) * env(len(n), 0.001, 0.03) * 0.4
    x2 = np.concatenate([np.zeros(int(SR * 0.12)), (lowpass(noise(0.3), 300) * env(int(SR * 0.3), 0.002, 0.06))])
    save("body_fall", mix(x, x2 * 0.6), 0.8)


def hurt():
    d = 0.35
    x = lowpass(noise(d), 600) * env(int(SR * d), 0.002, 0.07) + sine(lambda q: 140 - 60 * q / d, d) * env(int(SR * d), 0.005, 0.12) * 0.6
    save("hurt", x, 0.8)


def heartbeat():
    d = 0.9
    x = np.zeros(int(SR * d))
    for o in (0.0, 0.22):
        s = sine(lambda q: 60 - 20 * q, 0.15) * env(int(SR * 0.15), 0.004, 0.05)
        i = int(o * SR)
        x[i:i + len(s)] += s
    save("heartbeat", x, 0.7)


def radio():
    d = 0.25
    x = bandpass(noise(d), 1500, 4000) * env(int(SR * d), 0.001, 0.08) + square(1800, d) * env(int(SR * d), 0.001, 0.02) * 0.3
    save("radio", x, 0.35)


def ui():
    beep("ui_click", [1500], 0.025, 0.0, square, 0.3)
    beep("ui_open", [600, 900], 0.04, 0.01, square, 0.3)
    beep("hack_ok", [1200, 1800], 0.04, 0.005, square, 0.35)
    beep("hack_fail", [300, 200], 0.08, 0.01, square, 0.4)
    beep("hack_win", [800, 1000, 1200, 1600], 0.06, 0.01, square, 0.35)
    beep("keypad", [1350], 0.05, 0.0, sine, 0.35)
    beep("granted", [900, 1350], 0.07, 0.02, sine, 0.45)
    beep("denied", [220, 180], 0.12, 0.02, square, 0.4)
    beep("cam_beep", [2100], 0.04, 0.0, sine, 0.35)
    beep("cam_alert", [1400, 1400, 1400], 0.06, 0.04, square, 0.4)
    beep("turret_alert", [1000, 1500, 1000, 1500], 0.05, 0.02, square, 0.45)
    beep("upgrade", [500, 750, 1000, 1500], 0.08, 0.0, sine, 0.45)
    beep("objective", [660, 880, 1320], 0.1, 0.02, sine, 0.45)
    beep("datapad", [1800, 2400], 0.03, 0.02, sine, 0.35)


def elevator():
    d = 2.5
    tt = t(d)
    x = saw(lambda q: 48 + 4 * np.sin(q * 2), d) * 0.4
    x = lowpass(x, 400) * np.minimum(1, tt * 2) * np.minimum(1, (d - tt) * 2)
    x += bandpass(noise(d), 200, 800) * 0.15
    save("elevator", x, 0.6)


# ---------------------------------------------------------------- stimoli e materiali
def steps_special():
    """Passi su cocci di vetro e nell'acqua (superfici degli stimoli, vedi Stimuli)."""
    for i in range(2):
        d = 0.2
        x = np.zeros(int(SR * d))
        for k in range(7):
            o = int(rng.uniform(0, 0.07) * SR)
            s = resonator(noise(0.06) * env(int(SR * 0.06), 0.0003, 0.0015), rng.uniform(3000, 7500), 0.02)
            x[o:o + len(s)] += s[:len(x) - o] * rng.uniform(0.3, 1.0)
        x += bandpass(noise(d), 1500, 6000) * env(int(SR * d), 0.001, 0.02) * 0.6
        save(f"step_glass{i}", x, 0.5)
        d = 0.3
        n = noise(d)
        w = bandpass(n, 250 + i * 60, 2600) * env(len(n), 0.004, 0.06)
        w += lowpass(n, 400) * env(len(n), 0.002, 0.03) * 0.8
        o = int(SR * 0.05)
        b = sine(lambda q: 700 + 900 * q / d, 0.08) * env(int(SR * 0.08), 0.002, 0.02) * 0.25
        w[o:o + len(b)] += b
        save(f"step_water{i}", w, 0.5)


def splash():
    """Tanica che si rompe: tonfo, crepa della plastica e acqua che si sparge."""
    d = 1.4
    n = noise(d)
    x = lowpass(n, 300) * env(len(n), 0.002, 0.06) * 1.2
    crack = highpass(noise(0.05), 2000) * env(int(SR * 0.05), 0.0005, 0.01)
    x[:len(crack)] += crack
    gush = bandpass(noise(d), 300, 3000) * env(len(n), 0.03, 0.45)
    x += gush * 0.9
    for k in range(10):
        o = int(rng.uniform(0.1, 1.0) * SR)
        f0 = rng.uniform(500, 1400)
        b = sine(lambda q, f0=f0: f0 + 800 * q / 0.06, 0.06) * env(int(SR * 0.06), 0.002, 0.015) * 0.2
        x[o:o + len(b)] += b[:len(x) - o]
    save("splash", x, 0.75)


def hiss():
    """Estintore che si scarica: schiocco e sibilo che si spegne piano."""
    d = 2.2
    tt = t(d)
    x = highpass(noise(d), 1800) * np.exp(-tt / 0.9) * (0.85 + 0.15 * np.sin(tt * 37))
    x += bandpass(noise(d), 400, 1500) * np.exp(-tt / 0.5) * 0.4
    pop = lowpass(noise(0.08), 900) * env(int(SR * 0.08), 0.0005, 0.02) * 1.5
    x[:len(pop)] += pop
    save("hiss", x * np.minimum(1, tt * 60), 0.7)


def zap():
    """Scossa: ronzio a 60 Hz con armoniche e crepitio."""
    d = 0.45
    tt = t(d)
    x = square(60, d) * 0.5 + square(180, d) * 0.3
    x = bandpass(x, 100, 3000)
    x += highpass(noise(d), 2500) * 0.7 * (rng.random(len(tt)) < 0.35)
    gate = np.repeat(rng.random(int(d * 40) + 1) > 0.25, int(SR / 40) + 1)[:len(tt)]
    save("zap", x * gate * env(len(tt), 0.003, 0.2), 0.7)


def spark():
    """Scintille: pochi crepitii secchi."""
    d = 0.25
    x = np.zeros(int(SR * d))
    for k in range(5):
        o = int(rng.uniform(0, 0.15) * SR)
        s = highpass(noise(0.03), 2000) * env(int(SR * 0.03), 0.0003, 0.004)
        x[o:o + len(s)] += s[:len(x) - o] * rng.uniform(0.4, 1.0)
    save("spark", x, 0.5)


def main():
    steps(); land(); door_open(); door_locked()
    gunshot("pistol", 140, 0.012, 0.25)
    gunshot("guard_gun", 110, 0.015, 0.3, 0.85)
    reload(); empty_click(); swing(); hit_metal(); hit_flesh(); ricochet()
    turret_fire(); servo(); alarm(); ambient_drone(); server_hum(); whisper()
    pickup(); medpatch(); glass_break(); grate_break(); grate_pry(); clatter()
    body_fall(); hurt(); heartbeat(); radio(); ui(); elevator()
    # in fondo: i suoni di prima restano identici (stesso seme)
    steps_special(); splash(); hiss(); zap(); spark()
    print("suoni generati in", os.path.normpath(OUT))


if __name__ == "__main__":
    import sys
    # python3 tools/gen_sounds.py splash hiss  -> rigenera solo i suoni indicati
    if len(sys.argv) > 1:
        for name in sys.argv[1:]:
            globals()[name]()
    else:
        main()
