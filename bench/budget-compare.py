#!/usr/bin/env -S python3 -I
"""Compare two TIC-80 Speed Budget runs (e.g. before/after a core change).

usage: budget-compare.py <before/results.txt> <after/results.txt>
Prints a Markdown table: cost per call/iteration/bunny before and after, and the speed-up.
"""
import re
import sys


def parse(path):
    base, rows = None, {}
    for line in open(path, encoding="utf-8", errors="replace"):
        f = line.rstrip("\n").split("\t")
        if f[0] in ("gfx", "calc") and len(f) >= 4:
            m = re.search(r"([\d.]+) ms/frame", line)
            if not m:
                continue
            ms, n = float(m.group(1)), int(f[2])
            if f[1] == "empty":
                base = ms
            rows[(f[0], f[1])] = (n, ms)
        elif f[0] == "lang" and len(f) >= 4:
            m = re.findall(r"([\d.]+) ms/frame", line)
            if len(m) == 2:
                rows[("lang", f[1])] = (int(f[2]) * 60, float(m[1]) - float(m[0]))
    out = {}
    for (kind, name), (n, ms) in rows.items():
        if kind == "lang":
            out[(kind, name)] = ms / n               # ms per bunny
        elif name == "empty":
            out[(kind, name)] = ms                   # ms per frame
        else:
            out[(kind, name)] = max(ms - base, 0) / n
    return out


def us(v):
    v *= 1000
    return f"{v:,.2f} µs" if v < 10 else f"{v:,.0f} µs"


a, b = parse(sys.argv[1]), parse(sys.argv[2])
titles = {"gfx": "Drawing calls (per call)", "calc": "Language logic (per loop iteration)",
          "lang": "Bunnymark (per bunny)"}
for kind in ("gfx", "calc", "lang"):
    print(f"\n### {titles[kind]}\n\n| Test | Before | After | Speed-up |\n|---|---:|---:|---:|")
    for (k, name), va in a.items():
        if k != kind or (k, name) not in b:
            continue
        vb = b[(k, name)]
        label = "empty frame (per frame)" if name == "empty" else name.replace("calc_", "")
        sp = f"{va / vb:.2f}×" if vb > 0 else "∞"
        print(f"| {label} | {us(va)} | {us(vb)} | {sp} |")
