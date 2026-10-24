#!/usr/bin/env python3
"""Icona di Pulsar in stile Apple (macOS 26), 05/10/2026, chiesta dall'autore.
Squircle grafite con la luce sul bordo, l'interruttore di sistema (pista verde, manopola bianca) al centro.
Ombre leggere: le versioni 3D pesanti erano state bocciate il 01/10.
Uscita: assets/AppIcon.icns (e assets/AppIcon-1024.png).   python3 make_icon_apple.py
"""
import os, subprocess, shutil
import numpy as np
from PIL import Image, ImageFilter

QUI = os.path.dirname(os.path.abspath(__file__))
S = 2048                      # si disegna al doppio e si riduce: bordi puliti
K = S / 1024

def squircle(w, h, n=5.0):
    """Maschera superellisse (angoli continui come le icone Apple)."""
    y, x = np.mgrid[0:h, 0:w]
    u = (x + .5 - w / 2) / (w / 2); v = (y + .5 - h / 2) / (h / 2)
    d = np.abs(u) ** n + np.abs(v) ** n
    return np.clip((1 - d) * min(w, h) / 6 + .5, 0, 1)          # bordo morbido di ~1 px

def capsule(w, h):
    y, x = np.mgrid[0:h, 0:w]; r = h / 2
    cx = np.clip(x + .5, r, w - r); d = np.hypot(x + .5 - cx, y + .5 - r)
    return np.clip(r - d + .5, 0, 1)

def circle(d):
    y, x = np.mgrid[0:d, 0:d]; r = d / 2
    return np.clip(r - np.hypot(x + .5 - r, y + .5 - r) + .5, 0, 1)

def vgrad(h, w, top, bot):
    t = np.linspace(0, 1, h)[:, None, None]
    return (np.array(top, float) * (1 - t) + np.array(bot, float) * t) * np.ones((1, w, 1))

def layer(rgb, alpha):
    return np.dstack([rgb, alpha[..., None]])

def over(dst, src, x, y):
    """Compone src (RGBA float 0-1) su dst alla posizione x,y."""
    h, w = src.shape[:2]; d = dst[y:y + h, x:x + w]
    a = src[..., 3:]; out_a = a + d[..., 3:] * (1 - a)
    rgb = (src[..., :3] * a + d[..., :3] * d[..., 3:] * (1 - a)) / np.maximum(out_a, 1e-6)
    dst[y:y + h, x:x + w] = np.dstack([rgb, out_a])

def shadow(alpha, blur, opacity):
    im = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(im, float) / 255 * opacity

canvas = np.zeros((S, S, 4))

# 1. ombra leggera dell'icona e squircle (griglia macOS: 824 su 1024, margine 100)
B = int(824 * K); o = int(100 * K)
m = squircle(B, B)
sh = np.zeros((S, S)); sh[o + int(12 * K):o + int(12 * K) + B, o:o + B] = m
canvas = np.dstack([np.zeros((S, S, 3)), shadow(sh, 22 * K, .32)])
bg = vgrad(B, B, (0.235, 0.235, 0.255), (0.07, 0.07, 0.08))
# un filo di luce dall'alto, come il vetro di macOS 26
yy = np.linspace(0, 1, B)[:, None]
bg = bg + (0.10 * np.exp(-yy * 7))[..., None]
over(canvas, layer(np.clip(bg, 0, 1), m), o, o)
# bordo speculare: anello sottile, più chiaro in alto
inner = squircle(B - int(6 * K), B - int(6 * K)); ring = m.copy()
p = int(3 * K); ring[p:p + inner.shape[0], p:p + inner.shape[1]] -= inner
ring = np.clip(ring, 0, 1) * (0.55 * np.exp(-yy * 3.2) + 0.08)
over(canvas, layer(np.ones((B, B, 3)), ring), o, o)

# 2. la pista dell'interruttore: verde di sistema, appena incassata
TW, TH = int(560 * K), int(300 * K)
tx, ty = (S - TW) // 2, (S - TH) // 2
cm = capsule(TW, TH)
track = vgrad(TH, TW, (0.30, 0.82, 0.42), (0.16, 0.64, 0.30))
over(canvas, layer(track, cm), tx, ty)
# ombra interna in alto (incasso) e riflesso morbido sulla metà alta
ins = np.clip(np.linspace(1, 0, TH) * 3 - 2.2, 0, 1)[:, None] * cm * .22
over(canvas, layer(np.zeros((TH, TW, 3)), ins), tx, ty)
hl = np.clip(1 - np.linspace(0, 1, TH) * 2.2, 0, 1)[:, None] * capsule(TW, TH) * .20
over(canvas, layer(np.ones((TH, TW, 3)), hl), tx, ty)

# 3. la manopola: bianca, ombra corta e morbida, luce in alto
D = int(256 * K); pad = (TH - D) // 2
kx, ky = tx + TW - pad - D, ty + pad
cmask = circle(D)
ks = np.zeros((S, S)); ks[ky + int(10 * K):ky + int(10 * K) + D, kx:kx + D] = cmask
over(canvas, np.dstack([np.zeros((S, S, 3)), shadow(ks, 14 * K, .30)]), 0, 0)
knob = vgrad(D, D, (1, 1, 1), (0.90, 0.90, 0.91))
over(canvas, layer(knob, cmask), kx, ky)

img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)
out = os.path.join(QUI, "assets"); os.makedirs(out, exist_ok=True)
img.save(os.path.join(out, "AppIcon-1024.png"))

ics = os.path.join(out, "AppIcon.iconset"); shutil.rmtree(ics, ignore_errors=True); os.makedirs(ics)
for s in (16, 32, 128, 256, 512):
    img.resize((s, s), Image.LANCZOS).save(os.path.join(ics, f"icon_{s}x{s}.png"))
    img.resize((s * 2, s * 2), Image.LANCZOS).save(os.path.join(ics, f"icon_{s}x{s}@2x.png"))
subprocess.run(["iconutil", "-c", "icns", ics, "-o", os.path.join(out, "AppIcon.icns")], check=True)
print("ok", os.path.join(out, "AppIcon.icns"))
