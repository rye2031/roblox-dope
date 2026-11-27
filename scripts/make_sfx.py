#!/usr/bin/env python3
"""Synthesize Wildbound's sound effects (stdlib only) into one sprite file.

Every sound is generated from oscillators, noise and simple filters, so nothing is
downloaded and everything is original. The sounds are laid end to end with short
silences in art/audio/sfx_bank.wav; src/shared/SfxBank.luau lists each sound's
start and length so the game can play just that slice (Sound.PlaybackRegion).

Usage:
  python3 -I scripts/make_sfx.py            # writes the bank + the Luau table
  python3 -I scripts/make_sfx.py --split D  # also writes each sound as D/<name>.wav
"""
import array
import json
import math
import os
import random
import sys
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(7)


# ----------------------------------------------------------------------------------------
# building blocks (all return lists of floats)

def silence(sec):
    return [0.0] * int(sec * SR)


def n(sec):
    return int(sec * SR)


def env(sec, a=0.003, d=0.1, curve=4.0, hold=0.0):
    """Attack then exponential-ish decay to 0 over the remaining time."""
    out = []
    total = n(sec)
    na, nh = max(1, n(a)), n(hold)
    for i in range(total):
        if i < na:
            out.append(i / na)
        elif i < na + nh:
            out.append(1.0)
        else:
            k = (i - na - nh) / max(1, total - na - nh)
            out.append((1 - k) ** curve)
    return out


def osc(sec, f0, f1=None, shape='sine', phase=0.0, vib=0.0, vibrate=6.0):
    """Oscillator with an exponential pitch glide f0 -> f1 and optional vibrato."""
    f1 = f1 or f0
    out = []
    ph = phase
    total = n(sec)
    for i in range(total):
        k = i / max(1, total - 1)
        f = f0 * (f1 / f0) ** k
        if vib:
            f *= 1 + vib * math.sin(2 * math.pi * vibrate * i / SR)
        ph += f / SR
        x = ph % 1.0
        if shape == 'sine':
            v = math.sin(2 * math.pi * x)
        elif shape == 'tri':
            v = 4 * abs(x - 0.5) - 1
        elif shape == 'square':
            v = 1.0 if x < 0.5 else -1.0
        elif shape == 'saw':
            v = 2 * x - 1
        else:
            v = 0.0
        out.append(v)
    return out


def noise(sec):
    return [rng.uniform(-1, 1) for _ in range(n(sec))]


def mul(a, b):
    m = min(len(a), len(b))
    return [a[i] * b[i] for i in range(m)]


def gain(a, g):
    return [x * g for x in a]


def mix(*parts):
    """mix((signal, offset_seconds, gain), ...)"""
    length = max(n(off) + len(sig) for sig, off, _ in parts)
    out = [0.0] * length
    for sig, off, g in parts:
        o = n(off)
        for i, v in enumerate(sig):
            out[o + i] += v * g
    return out


def lowpass(a, cutoff, cutoff_end=None):
    """One-pole low-pass, optionally sweeping."""
    out = []
    y = 0.0
    total = len(a)
    for i, x in enumerate(a):
        c = cutoff if cutoff_end is None else cutoff * (cutoff_end / cutoff) ** (i / max(1, total - 1))
        alpha = 1 - math.exp(-2 * math.pi * c / SR)
        y += alpha * (x - y)
        out.append(y)
    return out


def highpass(a, cutoff):
    lp = lowpass(a, cutoff)
    return [a[i] - lp[i] for i in range(len(a))]


def bandpass(a, f0, f1=None, q=1.5):
    """State-variable band-pass with a swept centre (whooshes)."""
    f1 = f1 or f0
    out = []
    low = band = 0.0
    total = len(a)
    damp = 1.0 / q
    for i, x in enumerate(a):
        f = f0 * (f1 / f0) ** (i / max(1, total - 1))
        fc = 2 * math.sin(math.pi * min(f, SR / 6) / SR)
        high = x - low - damp * band
        band += fc * high
        low += fc * band
        out.append(band)
    return out


def pluck(sec, freq, bright=0.5):
    """Karplus-Strong string (bow twang)."""
    period = int(SR / freq)
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(n(sec)):
        v = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = (v * bright + nxt * (1 - bright)) * 0.996
        out.append(v)
    return out


def bell(sec, f, decay=3.0, partials=((1, 1.0), (2.01, 0.45), (3.02, 0.22), (4.17, 0.12), (5.43, 0.06))):
    """Additive bell / chime."""
    out = [0.0] * n(sec)
    for ratio, amp in partials:
        tone = osc(sec, f * ratio)
        e = env(sec, a=0.002, curve=decay * (1 + ratio * 0.35))
        for i in range(len(out)):
            out[i] += tone[i] * e[i] * amp
    return out


def reverb(a, wet=0.25, size=1.0, tail=0.6):
    """Small Schroeder reverb for shiny tails."""
    out = a + [0.0] * n(tail)
    combs = [int(d * size) for d in (1116, 1188, 1277, 1356)]
    res = [0.0] * len(out)
    for d in combs:
        buf = [0.0] * d
        idx = 0
        for i in range(len(out)):
            y = buf[idx]
            buf[idx] = out[i] + y * 0.78
            idx = (idx + 1) % d
            res[i] += y * 0.25
    for d in (556, 441):
        buf = [0.0] * d
        idx = 0
        for i in range(len(res)):
            b = buf[idx]
            y = -res[i] + b
            buf[idx] = res[i] + b * 0.5
            idx = (idx + 1) % d
            res[i] = y
    return [out[i] + res[i] * wet for i in range(len(out))]


def fade_tail(a, sec=0.01):
    k = min(len(a), n(sec))
    for i in range(k):
        a[len(a) - 1 - i] *= i / k
    return a


def finish(a, peak=0.89):
    """Soft-limit, normalise and fade the end so slices never click."""
    a = [math.tanh(x * 1.2) for x in a]
    m = max(1e-9, max(abs(x) for x in a))
    a = [x / m * peak for x in a]
    # trim trailing near-silence
    end = len(a)
    while end > 1 and abs(a[end - 1]) < 0.0015:
        end -= 1
    a = a[:end + n(0.01)]
    return fade_tail(a, 0.008)


def note(name):
    names = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    base = names[name[0]]
    acc = 1 if '#' in name else -1 if name[1:2] == 'b' else 0
    octave = int(name[-1])
    return 440.0 * 2 ** ((base + acc + (octave - 4) * 12) / 12)


# ----------------------------------------------------------------------------------------
# the sounds

S = {}


def sfx(name):
    def wrap(fn):
        S[name] = fn
        return fn
    return wrap


# --- UI / haptics ---
@sfx('tap')  # tiny haptic tick for every button
def _():
    body = mul(osc(0.035, 220, 140), env(0.035, a=0.0008, curve=5))
    click = mul(highpass(noise(0.01), 3000), env(0.01, a=0.0003, curve=6))
    return mix((body, 0, 0.9), (click, 0, 0.35))


@sfx('open')  # panel opens: soft upward pop
def _():
    pop = mul(osc(0.09, 420, 880, 'sine'), env(0.09, a=0.002, curve=3))
    sh = mul(osc(0.09, 1260, 1760), env(0.09, a=0.002, curve=5))
    return mix((pop, 0, 0.8), (sh, 0.01, 0.2))


@sfx('close')
def _():
    return mul(osc(0.08, 700, 360), env(0.08, a=0.002, curve=3))


@sfx('error')  # gentle "nope" double bonk
def _():
    b = lambda: mul(osc(0.09, 200, 160, 'tri'), env(0.09, a=0.002, curve=3))
    return mix((lowpass(b(), 1400), 0, 0.9), (lowpass(b(), 1200), 0.11, 0.8))


@sfx('toast')
def _():
    return reverb(mix((bell(0.35, note('E6'), 4), 0, 0.6), (bell(0.3, note('B6'), 5), 0.05, 0.35)), wet=0.2, tail=0.25)


@sfx('select')  # picking a card / monster
def _():
    return mix((mul(osc(0.05, 900, 1200), env(0.05, a=0.001, curve=4)), 0, 0.6), (mul(osc(0.04, 1800), env(0.04, a=0.001, curve=6)), 0, 0.2))


# --- economy (the satisfying ones) ---
@sfx('coin')  # bright two-step ching
def _():
    a = mix((bell(0.12, note('B5'), 6, ((1, 1), (2.0, 0.5), (3.0, 0.3), (4.0, 0.15))), 0, 0.7))
    b = bell(0.45, note('E6'), 3.2, ((1, 1), (2.0, 0.5), (3.0, 0.32), (4.0, 0.2), (5.0, 0.1)))
    return reverb(mix((a, 0, 0.75), (b, 0.055, 0.85)), wet=0.15, tail=0.2)


@sfx('coins')  # a shower of coins (big payouts)
def _():
    parts = []
    t = 0.0
    for i in range(9):
        f = note('E6') * 2 ** (rng.choice([0, 2, 4, 7, 9, 12]) / 12)
        parts.append((bell(0.25, f, 5, ((1, 1), (2.0, 0.5), (3.0, 0.3))), t, 0.45 - i * 0.02))
        t += 0.035 + rng.random() * 0.03
    return reverb(mix(*parts), wet=0.22, tail=0.35)


@sfx('essence')  # glassy shimmer
def _():
    return reverb(mix((bell(0.5, note('A6'), 3, ((1, 1), (2.76, 0.4), (5.4, 0.2))), 0, 0.6), (bell(0.45, note('E7'), 4, ((1, 1), (2.76, 0.3))), 0.06, 0.35)), wet=0.3, tail=0.4)


@sfx('scroll_get')  # a scroll dropped for you
def _():
    rustle = mul(bandpass(noise(0.18), 2500, 5000, 0.8), env(0.18, a=0.01, curve=2))
    chime = mix((bell(0.4, note('G5'), 3), 0.05, 0.5), (bell(0.4, note('D6'), 3), 0.12, 0.5), (bell(0.5, note('G6'), 3), 0.19, 0.55))
    return reverb(mix((rustle, 0, 0.35), (chime, 0, 1)), wet=0.22, tail=0.35)


@sfx('level_up')  # rising arpeggio + sparkle
def _():
    notes = ['C5', 'E5', 'G5', 'C6', 'E6']
    parts = [(bell(0.5, note(x), 3), i * 0.065, 0.55) for i, x in enumerate(notes)]
    parts.append((mul(osc(0.6, note('C6')), env(0.6, a=0.01, curve=2)), 0.3, 0.25))
    parts.append((mul(highpass(noise(0.5), 6000), env(0.5, a=0.05, curve=3)), 0.25, 0.08))
    return reverb(mix(*parts), wet=0.25, tail=0.5)


@sfx('quest_done')  # short bright fanfare
def _():
    lead = []
    for i, (x, d) in enumerate([('G5', 0.09), ('C6', 0.09), ('E6', 0.09), ('G6', 0.4)]):
        lead.append((mul(osc(d + 0.05, note(x), shape='tri', vib=0.004 if d > 0.2 else 0), env(d + 0.05, a=0.004, curve=1.6, hold=d * 0.4)), i * 0.09, 0.45))
    chord = mix(*[(bell(0.7, note(x), 2.5), 0.27, 0.3) for x in ('C6', 'E6', 'G6')])
    return reverb(mix(*lead, (chord, 0, 1)), wet=0.25, tail=0.5)


@sfx('claim')  # pressing Claim: pling + coins
def _():
    pl = mix((bell(0.3, note('A6'), 4), 0, 0.6), (bell(0.3, note('E7'), 5), 0.03, 0.3))
    return mix((pl, 0, 1), (S['coin'](), 0.06, 0.7))


@sfx('buy')  # spend coins on an upgrade / storage
def _():
    return reverb(mix((bell(0.3, note('D6'), 4), 0, 0.5), (bell(0.4, note('A6'), 3.5), 0.07, 0.55), (mul(lowpass(noise(0.05), 3000), env(0.05, curve=5)), 0, 0.2)), wet=0.18, tail=0.25)


# --- combat ---
@sfx('swing')  # blade whoosh
def _():
    w = mul(bandpass(noise(0.2), 700, 3200, 1.3), env(0.2, a=0.03, curve=2.2))
    return gain(w, 1.4)


@sfx('swing_heavy')  # hammer whoosh, lower and longer
def _():
    w = mul(bandpass(noise(0.3), 300, 1200, 1.2), env(0.3, a=0.08, curve=1.8))
    return gain(w, 1.6)


@sfx('hit')  # punchy hit on a monster
def _():
    thump = mul(osc(0.12, 190, 55), env(0.12, a=0.001, curve=3.5))
    snap = mul(lowpass(noise(0.03), 4500), env(0.03, a=0.0005, curve=5))
    crunch = mul(bandpass(noise(0.07), 1600, 900, 1.0), env(0.07, a=0.001, curve=4))
    return mix((thump, 0, 1.0), (snap, 0, 0.55), (crunch, 0, 0.35))


@sfx('hit_heavy')
def _():
    thump = mul(osc(0.22, 150, 40), env(0.22, a=0.001, curve=3))
    crack = mul(lowpass(noise(0.08), 3000), env(0.08, a=0.0005, curve=4))
    sub = mul(osc(0.25, 60, 38), env(0.25, a=0.004, curve=2.5))
    return mix((thump, 0, 1.0), (crack, 0, 0.6), (sub, 0, 0.6))


@sfx('crit')  # hit + metallic ring = big number
def _():
    ring = bell(0.45, note('A6'), 3.5, ((1, 1), (1.51, 0.6), (2.43, 0.4), (3.87, 0.25)))
    return reverb(mix((S['hit'](), 0, 1.0), (ring, 0.01, 0.5), (bell(0.3, note('E7'), 5), 0.03, 0.25)), wet=0.15, tail=0.25)


@sfx('slam')  # ground slam / boss landing
def _():
    boom = mul(osc(0.6, 95, 32), env(0.6, a=0.002, curve=2.5))
    rumble = mul(lowpass(noise(0.7), 400, 120), env(0.7, a=0.01, curve=2))
    crack = mul(lowpass(noise(0.1), 5000), env(0.1, a=0.0005, curve=4))
    return mix((boom, 0, 1.0), (rumble, 0, 0.8), (crack, 0, 0.5))


@sfx('zap')  # staff bolt
def _():
    fm = []
    ph = 0.0
    total = n(0.22)
    for i in range(total):
        k = i / total
        f = 500 + 1600 * k
        ph += (f + 300 * math.sin(2 * math.pi * 60 * i / SR)) / SR
        fm.append(math.sin(2 * math.pi * ph))
    sparkle = mul(highpass(noise(0.2), 5000), env(0.2, a=0.01, curve=3))
    return mix((mul(fm, env(0.22, a=0.004, curve=2)), 0, 0.7), (sparkle, 0, 0.18))


@sfx('bow')  # string twang + whoosh
def _():
    tw = mul(lowpass(pluck(0.35, 196, 0.55), 2500), env(0.35, a=0.001, curve=2))
    wh = mul(bandpass(noise(0.15), 1500, 4000, 1.5), env(0.15, a=0.02, curve=2))
    return mix((tw, 0, 0.9), (wh, 0.02, 0.45))


@sfx('arrow_hit')
def _():
    th = mul(osc(0.07, 420, 160, 'tri'), env(0.07, a=0.0005, curve=4))
    return mix((th, 0, 0.8), (mul(lowpass(noise(0.03), 3500), env(0.03, curve=5)), 0, 0.4))


@sfx('dodge')  # quick cloth whoosh
def _():
    w = mul(bandpass(noise(0.22), 1200, 400, 1.0), env(0.22, a=0.02, curve=2))
    return gain(w, 1.5)


@sfx('skill_ready')  # weapon skill back off cooldown
def _():
    return reverb(mix((bell(0.25, note('E6'), 5), 0, 0.5), (bell(0.3, note('B6'), 4), 0.06, 0.45)), wet=0.15, tail=0.2)


@sfx('hurt')  # you got hit
def _():
    thud = mul(osc(0.16, 120, 60), env(0.16, a=0.001, curve=3))
    return mix((thud, 0, 1.0), (mul(lowpass(noise(0.06), 1500), env(0.06, curve=4)), 0, 0.5))


@sfx('poof')  # monster defeated
def _():
    pop = mul(osc(0.08, 300, 900), env(0.08, a=0.001, curve=3))
    puff = mul(lowpass(noise(0.3), 2500, 600), env(0.3, a=0.01, curve=2.5))
    sp = mix((bell(0.3, note('G6'), 5), 0.06, 0.3), (bell(0.3, note('D7'), 5), 0.1, 0.2))
    return mix((pop, 0, 0.6), (puff, 0, 0.5), (sp, 0, 1))


@sfx('charge')  # an ultimate building up
def _():
    whine = mul(osc(0.9, 180, 900, 'saw', vib=0.01, vibrate=9), env(0.9, a=0.7, curve=0.6))
    return lowpass(gain(whine, 0.6), 1800, 4000)


@sfx('blast')  # ultimate release
def _():
    boom = mul(osc(0.5, 120, 40), env(0.5, a=0.001, curve=2.5))
    sizzle = mul(highpass(noise(0.5), 2500), env(0.5, a=0.002, curve=2.5))
    return mix((boom, 0, 1.0), (sizzle, 0, 0.35), (S['slam'](), 0, 0.4))


@sfx('warn')  # red circle on the ground
def _():
    p = lambda: mul(osc(0.12, 330, 300, 'tri'), env(0.12, a=0.004, curve=2))
    return lowpass(mix((p(), 0, 0.8), (p(), 0.16, 0.7)), 2000)


@sfx('faint')  # your monster went down
def _():
    return mul(osc(0.45, note('E5'), note('A3'), 'tri'), env(0.45, a=0.005, curve=1.8))


@sfx('revive')
def _():
    return reverb(mix(*[(bell(0.35, note(x), 3), i * 0.06, 0.5) for i, x in enumerate(['A5', 'C#6', 'E6'])]), wet=0.25, tail=0.35)


@sfx('boss')  # a boss or titan appears
def _():
    horn = mul(lowpass(osc(1.2, 110, 104, 'saw', vib=0.006, vibrate=5), 900), env(1.2, a=0.15, curve=1.2, hold=0.4))
    horn5 = mul(lowpass(osc(1.2, 165, 156, 'saw', vib=0.006, vibrate=5), 900), env(1.2, a=0.2, curve=1.2, hold=0.4))
    return reverb(mix((horn, 0, 0.6), (horn5, 0.05, 0.4)), wet=0.3, tail=0.6)


@sfx('region')  # entering a new region
def _():
    sw = mul(bandpass(noise(0.5), 400, 2400, 1.0), env(0.5, a=0.2, curve=1.5))
    return reverb(mix((sw, 0, 0.35), (bell(0.6, note('D6'), 3), 0.25, 0.4), (bell(0.6, note('A6'), 3), 0.33, 0.35)), wet=0.3, tail=0.5)


# --- summoning ---
@sfx('scroll_land')  # sealed scroll drops onto the screen
def _():
    th = mul(osc(0.1, 160, 90), env(0.1, a=0.001, curve=3))
    paper = mul(bandpass(noise(0.12), 3000, 1500, 0.8), env(0.12, a=0.002, curve=3))
    return mix((th, 0, 0.8), (paper, 0, 0.45))


@sfx('rattle')  # the wobble
def _():
    parts = [(mul(bandpass(noise(0.04), 2500, 1800, 1.2), env(0.04, a=0.001, curve=3)), i * 0.07, 0.6) for i in range(4)]
    return mix(*parts)


@sfx('unroll')  # paper swoosh into shimmer
def _():
    sw = mul(bandpass(noise(0.4), 600, 3000, 0.9), env(0.4, a=0.05, curve=1.5))
    sh = mix(*[(bell(0.35, note(x), 4), 0.12 + i * 0.05, 0.25) for i, x in enumerate(['E6', 'A6', 'C#7'])])
    return reverb(mix((sw, 0, 0.8), (sh, 0, 1)), wet=0.2, tail=0.3)


@sfx('reveal')  # card appears (1-3 stars)
def _():
    return reverb(mix(*[(bell(0.6, note(x), 2.8), i * 0.03, 0.4) for i, x in enumerate(['C6', 'E6', 'G6'])]), wet=0.25, tail=0.4)


@sfx('reveal_rare')  # 4 stars
def _():
    ch = mix(*[(bell(0.9, note(x), 2.2), i * 0.04, 0.4) for i, x in enumerate(['A5', 'C#6', 'E6', 'A6'])])
    shimmer = mul(highpass(noise(0.8), 6000), env(0.8, a=0.05, curve=2.5))
    return reverb(mix((ch, 0, 1), (shimmer, 0.05, 0.12)), wet=0.3, tail=0.6)


@sfx('reveal_legend')  # 5 stars: fanfare and a long sparkle
def _():
    parts = []
    for i, x in enumerate(['C5', 'G5', 'C6', 'E6', 'G6', 'C7']):
        parts.append((bell(1.4, note(x), 1.6), i * 0.07, 0.36))
    pad = mul(mix((osc(1.4, note('C4'), shape='tri'), 0, 0.5), (osc(1.4, note('G4'), shape='tri'), 0, 0.4)), env(1.4, a=0.25, curve=1.3))
    sparkle = []
    for i in range(14):
        sparkle.append((bell(0.3, note('C7') * 2 ** (rng.choice([0, 4, 7, 12]) / 12), 5), 0.3 + i * 0.07, 0.12))
    return reverb(mix(*parts, (lowpass(pad, 1200), 0, 0.5), *sparkle), wet=0.32, tail=0.9)


@sfx('star')  # one star popping in (pitch raised per star in game)
def _():
    return mix((bell(0.22, note('E6'), 5), 0, 0.6), (mul(osc(0.04, 2400, 3200), env(0.04, curve=4)), 0, 0.15))


@sfx('flip')  # card flip
def _():
    return mul(bandpass(noise(0.07), 2200, 4200, 1.0), env(0.07, a=0.003, curve=2.5))


@sfx('thunder')  # lightning strike before a 4/5 star
def _():
    crack = mul(highpass(noise(0.12), 1500), env(0.12, a=0.0003, curve=3))
    crackle = []
    for i in range(6):
        crackle.append((mul(highpass(noise(0.02), 3000), env(0.02, curve=4)), 0.02 + i * 0.03 + rng.random() * 0.02, 0.5))
    rumble = mul(lowpass(noise(1.1), 350, 90), env(1.1, a=0.04, curve=1.5))
    boom = mul(osc(0.6, 80, 35), env(0.6, a=0.002, curve=2.5))
    return mix((crack, 0, 0.9), *crackle, (rumble, 0.03, 1.0), (boom, 0.01, 0.7))


@sfx('announce')  # someone in the server got a 5 star
def _():
    return reverb(mix(*[(bell(0.8, note(x), 2.4), i * 0.09, 0.42) for i, x in enumerate(['G5', 'D6', 'G6', 'B6'])]), wet=0.3, tail=0.6)


# ----------------------------------------------------------------------------------------

def main():
    split = None
    if '--split' in sys.argv:
        split = sys.argv[sys.argv.index('--split') + 1]
        os.makedirs(split, exist_ok=True)
    gap = silence(0.25)
    bank = []
    table = {}
    t = 0.0
    for name, fn in S.items():
        sig = finish(fn())
        start = len(bank) / SR
        bank += sig
        table[name] = (round(start, 4), round(len(sig) / SR, 4))
        bank += gap
        if split:
            write_wav(os.path.join(split, name + '.wav'), sig)
    out_dir = os.path.join(ROOT, 'art', 'audio')
    os.makedirs(out_dir, exist_ok=True)
    wav_path = os.path.join(out_dir, 'sfx_bank.wav')
    write_wav(wav_path, bank)
    json.dump({k: {'start': v[0], 'length': v[1]} for k, v in table.items()}, open(os.path.join(out_dir, 'sfx_bank.json'), 'w'), indent=1)
    lines = [
        '-- Generated by scripts/make_sfx.py. Do not edit: change the generator and rerun it.',
        '-- Slices of the uploaded sound bank (art/audio/sfx_bank.wav): name = { start, length } in seconds.',
        'return {',
        '\tAssetId = AssetIdPlaceholder,',
        '\tSounds = {',
    ]
    for k, (s, l) in table.items():
        lines.append(f'\t\t{k} = {{ {s}, {l} }},')
    lines += ['\t},', '}', '']
    lua_path = os.path.join(ROOT, 'src', 'shared', 'SfxBank.luau')
    old_id = '""'
    if os.path.exists(lua_path):
        import re
        m = re.search(r'AssetId = ("[^"]*"),', open(lua_path).read())
        if m:
            old_id = m.group(1)
    open(lua_path, 'w').write('\n'.join(lines).replace('AssetIdPlaceholder', old_id))
    print(f'{len(table)} sounds, {len(bank) / SR:.1f} s, {os.path.getsize(wav_path) / 1e6:.2f} MB -> {wav_path}')


def write_wav(path, sig):
    w = wave.open(path, 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    data = array.array('h', (int(max(-1.0, min(1.0, x)) * 32767) for x in sig))
    w.writeframes(data.tobytes())
    w.close()


if __name__ == '__main__':
    main()
