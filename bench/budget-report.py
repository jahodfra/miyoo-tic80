#!/usr/bin/env -S python3 -I
"""Turn the TIC-80 Speed Budget results into tables.

usage: python3 -I budget-report.py [results.txt]
       (default: App/TICBudget/results.txt on the mounted card labelled MIYOO)
Prints Markdown; also saves it next to results.txt as budget.md.
"""
import os
import re
import subprocess
import sys

FRAME_MS = 1000 / 60


def find_results():
    if len(sys.argv) > 1:
        return sys.argv[1]
    out = subprocess.run(["lsblk", "-lno", "LABEL,MOUNTPOINT"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0] == "MIYOO":
            return os.path.join(parts[1], "App/TICBudget/results.txt")
    sys.exit("card not mounted - pass the path to results.txt")


def fmt_us(ms):
    us = ms * 1000
    return f"{us:,.2f} µs" if us < 10 else f"{us:,.0f} µs"


def main():
    path = find_results()
    gfx, lang, calc, mhz = {}, {}, {}, "?"
    desc = {}
    gdir = os.path.join(os.path.dirname(path), "gfx", "gfx_tests.txt")
    if os.path.exists(gdir):
        for line in open(gdir):
            n, _, d = line.rstrip("\n").split("\t")
            desc[n] = d
    for line in open(path, encoding="utf-8", errors="replace"):
        f = line.rstrip("\n").split("\t")
        if f[0] == "cpu_mhz":
            mhz = f[1]
        elif f[0] == "gfx" and len(f) >= 4:
            m = re.search(r"([\d.]+) ms/frame", line)
            gfx[f[1]] = (int(f[2]), float(m.group(1)) if m else None)
        elif f[0] == "calc" and len(f) >= 4:
            m = re.search(r"([\d.]+) ms/frame", line)
            calc[f[1].replace("calc_", "")] = (int(f[2]), float(m.group(1)) if m else None)
        elif f[0] == "lang" and len(f) >= 4:
            m = re.findall(r"([\d.]+) ms/frame", line)
            lang[f[1]] = (int(f[2]), [float(x) for x in m] if len(m) == 2 else None)

    out = [f"# TIC-80 speed budget on the Miyoo ({mhz} MHz)", ""]
    base = gfx.get("empty", (1, None))[1]
    if base is not None:
        out += [f"Empty frame (core + blit, no drawing): **{base:.2f} ms** - "
                f"leaves **{FRAME_MS - base:.2f} ms** of the {FRAME_MS:.2f} ms 60 fps budget.", ""]
    out += ["## Drawing calls (called from Lua)", "",
            "| Call | Cost per call | Calls per 60 fps frame |", "|---|---:|---:|"]
    costs = {}
    for name, (n, ms) in gfx.items():
        if name == "empty":
            continue
        if ms is None or base is None:
            out.append(f"| {desc.get(name, name)} | FAILED | |")
            continue
        c = max(ms - base, 0) / n
        costs[name] = c
        fit = (FRAME_MS - base) / c if c > 0 else float("inf")
        out.append(f"| {desc.get(name, name)} | {fmt_us(c)} | {fit:,.0f} |")

    out += ["", "## Languages: game-logic speed (no drawing)", "",
            "Same loop in each language: `s=(s*17+i)%1000003; a[i%100]=a[(i+1)%100]+s%7`.", "",
            "| Language | Cost per iteration | Iterations per 60 fps frame | vs Lua |",
            "|---|---:|---:|---:|"]
    crow = []
    for name, (n, ms) in calc.items():
        if ms is None or base is None:
            out.append(f"| {name} | FAILED | | |")
            continue
        crow.append((name, max(ms - base, 0) / n))
    clua = dict(crow).get("lua")
    for name, c in sorted(crow, key=lambda r: r[1]):
        fit = (FRAME_MS - base) / c if c > 0 else float("inf")
        out.append(f"| {name} | {fmt_us(c)} | {fit:,.0f} | {c / clua:.2f}× |" if clua else
                   f"| {name} | {fmt_us(c)} | {fit:,.0f} | |")

    out += ["", "## Languages: realistic mix (TIC-80 bunnymark)", "",
            "Each bunny = position update + bounce checks + one 32x32 `spr()` call.", "",
            "| Language | Cost per bunny | Bunnies per 60 fps frame | vs Lua |",
            "|---|---:|---:|---:|"]
    rows = []
    for name, (per, ms) in lang.items():
        if not ms:
            out.append(f"| {name} | FAILED | | |")
            continue
        rows.append((name, (ms[1] - ms[0]) / (per * 60)))
    lua = dict(rows).get("lua")
    for name, c in sorted(rows, key=lambda r: r[1]):
        fit = (FRAME_MS - (base or 0)) / c if c > 0 else float("inf")
        rel = f"{c / lua:.2f}×" if lua else ""
        out.append(f"| {name} | {fmt_us(c)} | {fit:,.0f} | {rel} |")
    out += ["", "Notes: costs are measured on the device, unthrottled, without RetroArch's video "
            "output (which adds a roughly constant cost per frame). Positions vary per call, so "
            "values are averages. WASM appears only in bunnymark (its cart is precompiled)."]
    text = "\n".join(out) + "\n"
    print(text)
    try:
        open(os.path.join(os.path.dirname(path), "budget.md"), "w", encoding="utf-8").write(text)
    except OSError:
        pass


if __name__ == "__main__":
    main()
