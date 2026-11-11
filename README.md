# Miyoo Mini+ SD card with Onion OS and an optimized TIC-80 core

How to rebuild the setup from scratch: Onion OS on a fresh SD card, PICO-8 (FAKE-08)
and TIC-80 carts, and a TIC-80 core compiled specifically for the Mini+.

## Results

Measured on a Miyoo Mini+ at 1500 MHz.

**Rebuilding for the CPU.** TIC-80 1.4.1 built for the Cortex-A7 with NEON is
**2.5–3.5× faster** than Onion's stock core (generic ARMv7, TIC-80 0.90). It also runs carts made
for TIC-80 1.x.

**The speed patch on top of that.** The output is unchanged; see
[Speed patch](#speed-patch-patchestic80-v141-miyoo-optpatch).

| | Before patch | After | Faster |
|---|---:|---:|---:|
| Fixed cost per frame | 954 µs | 363 µs | 2.6× |
| `cls()` | 91 µs | 4.3 µs | 21× |
| `rect()` full screen | 1,029 µs | 10 µs | 102× |
| `spr()` 32×32 | 54 µs | 26 µs | 2.0× |
| `map()` full screen | 1,623 µs | 758 µs | 2.1× |
| Bunnymark per bunny (any language) | 39–55 µs | 23–33 µs | 1.6–1.7× |
| Python logic | 5.14 µs | 3.33 µs | 1.5× |

[Section 6](#6-speed-budget-draw-calls-and-languages-optional) explains how to measure your own
speed budget: the cost of each draw call and the speed of each language.

## Repository layout

| Path | What |
|---|---|
| `build-core.sh`, `prepare-card.sh`, `install-tic80.sh`, `download-games.sh` | Steps 0–4 below |
| `patches/` | Speed patch for TIC-80, applied automatically by `build-core.sh` |
| `scripts/` | Toolchain file, build scripts that run inside Docker, linker version script, zip verifier |
| `bench/` | Benchmark program (`ticbench.c`), benchmark apps for the Miyoo, test-cart generators, project→`.tic` converter, report/compare scripts, rendering verification |
| `work/`, `dist/` | Created by the scripts (downloads, sources, build output). Not in git |

## Steps

| Step | Where | Command |
|---|---|---|
| 0. Build the optimized TIC-80 core (once per version) | PC | `./build-core.sh` |
| 1. Format the card + copy Onion | PC | `./prepare-card.sh /dev/sdX` |
| 2. First boot + enable PICO-8 and TIC-80 | Miyoo | (manual, see below) |
| 3. Install the core, speed and aspect fixes | PC | `./install-tic80.sh` |
| 4. Download games (optional) | PC | `./download-games.sh` |
| 5. Benchmark core builds (optional) | PC + Miyoo | `./bench/make-bench-app.sh …` |
| 6. Speed budget: draw calls + languages (optional) | PC + Miyoo | `./bench/make-budget-app.sh` |

You need: Linux with `docker`, `git`, `curl`, `unzip`, `python3`, `udisksctl`/`gdbus`
(standard on Ubuntu desktops) and optionally ImageMagick for TIC-80 cover images. No sudo needed.

---

## 0. Build the optimized TIC-80 core

```sh
./build-core.sh              # TIC-80 v1.4.1 with -O3  ->  dist/tic80_libretro.so
./build-core.sh v1.4.1 -O2   # other version / optimization level
```

What it does:
- Uses Onion's own toolchain image `aemiii91/miyoomini-toolchain` (GCC 8.3, glibc 2.28, matching
  the Miyoo's system libraries). About 2.4 GB, downloaded on first run.
- Downloads CMake 3.27, because the image's CMake 3.13 is too old for TIC-80 1.4.
- Clones TIC-80 and builds the libretro core with
  `-O3 -mcpu=cortex-a7 -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -flto`.
  It links `libgcc`/`libstdc++` statically and adds `-pthread`.
- Languages: Lua, MoonScript, YueScript, Fennel, JavaScript, Wren, Squirrel, Python, Scheme and WASM.
  Ruby, Janet, Gravity and MiniScript are left out because they don't build with this toolchain.
  They're rarely used in carts.
- Everything downloaded goes into `work/` (about 1 GB), and the result goes into `dist/`.

### Speed patch (`patches/tic80-v1.4.1-miyoo-opt.patch`)

`build-core.sh` applies every `patches/tic80-<tag>-*.patch` automatically. For plain upstream
TIC-80, run `NO_PATCHES=1 ./build-core.sh`.

| # | Change | Where |
|---|---|---|
| 1 | Export only the `retro_*` functions (`-fvisibility=hidden` and `scripts/libretro.map`). Before, about 66,000 internal calls went through the PLT, including every pixel write, so link-time optimization couldn't inline them. | build flags |
| 2 | Write screen pixels directly instead of through `tic_api_poke4()`. Fill rows and spans with `memset`: `rect`, filled `circ`/`elli`, partial `cls`. | `core/draw.c` |
| 3 | Read 4 bpp sprite and map pixels directly (no function pointer per pixel). Build one colour table per `spr`/`map` call instead of one per 8×8 tile. Read text glyphs once per character (1 bpp fast path) and write 1× scale text pixels directly. | `core/draw.c` |
| 4 | `cls()` clears the 261 KB `ttri` depth buffer only if it was written to. The frame conversion rebuilds palettes only when they changed, and converts rows where vbank 1 is unused straight from vbank 0, two pixels per byte. Lua, MoonScript, Fennel and YueScript look up `SCN`/`BDR` once per frame instead of 432 times. | `core/draw.c`, `core/core.c`, `api/luaapi.c` |
| 5 | Triangles: `tri`/`ttri` get a separate copy of the pixel loop per shader, so the shader is inlined instead of called through a pointer per pixel. `floor()` is replaced by an exact inline equivalent; ARMv7 has no rounding instruction, so it was a library call, twice per pixel. `ttri` and `textri` read 4 bpp sprite and map textures directly. About 2× faster on the PC. | `core/draw.c`, `core/draw_dep.c` |

**The output is unchanged.** `bench/verify-render.sh` compared every frame of 64 carts, 600 frames
each, on PC builds of the original and patched code. The carts are the drawing and language tests,
the bunnymarks, a triangle stress cart (`bench/make_tri_test_cart.py`: every `tri`/`ttri`/`textri`
mode, depth, clipping, off-screen and odd texture coordinates) and 24 games, including FPS80 and
Portal TIC-80. All matched. Carts that seed randomness from the clock were run with a fixed clock.

One game, Dragon Fury, is non-deterministic even on plain TIC-80 because it depends on memory
addresses. Over repeated runs, both cores produce exactly the same two outcomes.

One behaviour difference: if a cart *defines* `SCN`/`BDR`/`scanline` from inside `SCN`/`BDR`
in the middle of a frame, it takes effect from the next frame instead of the next row.

### Why: benchmark on the Mini+ (Nov 2026, 1500 MHz)

Frames per second with no frame limit. Games need 60; above that is spare capacity.

| Cart | Onion's stock core (0.90, generic ARMv7, GCC 5.4) | 0.90 `-O3` Cortex-A7 | **1.4.1 `-O3` Cortex-A7** |
|---|---:|---:|---:|
| FPS80 | 15 | 21.5 | **23** |
| Dragon Fury | 34 | 122 | **101** |
| Supernova | 68 | 195 | **160** |
| 8 Bit Panda | 87 | 353 | **270** |
| Portal TIC-80 | doesn't run | doesn't run | **195** |

- **Rebuilding for the Cortex-A7 with NEON is the big win**, 2.5–3.5× faster.
- `-O3` beats `-O2` by 2–17%.
- **1.4.1 is the version to use.** It runs carts made for TIC-80 1.x, which use features like
  `vbank`, and it's fastest on the heaviest game. 0.90 is quicker only on games already far
  above 60 fps.

---

## 1. Format the card and copy Onion

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,LABEL      # find the card, e.g. /dev/sdc
./prepare-card.sh /dev/sdc               # latest Onion release
./prepare-card.sh /dev/sdc v4.3.1-1      # or a specific one
```

**This erases the whole device.** The script refuses anything that isn't a removable, USB or MMC
disk, anything holding a system mount, and anything over 512 GB. It shows the disk and asks you
to type its name before continuing.

It then:
1. Creates an MBR partition table with one FAT32 partition labelled `MIYOO`, using udisks.
2. Extracts Onion onto the card and creates `Roms/PICO` and `Roms/TIC`.
3. Remounts the card and checks every file's CRC against the zip.

A mismatch in step 3 means the card is failing or fake. Throw it away. The first card we used
had flipped bits in its data, which was why its games didn't start.

## 2. First boot on the Miyoo (manual)

1. Insert the card and power on. Onion installs itself, which takes a few minutes.
2. **Apps → Package Manager** → enable **PICO-8 (Fake8)** and **TIC-80** → apply.
3. Power off and put the card back in the PC.

Onion only creates `Emu/TIC`, `RetroArch/.retroarch/cores` and `Saves/CurrentProfile` during this
first boot, so step 3 has to come after it.

## 3. Install the TIC-80 core and fixes

```sh
./install-tic80.sh                      # finds the card labelled MIYOO
CPU_MHZ=1400 ./install-tic80.sh         # different clock for TIC-80 games
./install-tic80.sh /media/me/MIYOO some/other/tic80_libretro.so
```

| Change | File on the card | Why |
|---|---|---|
| Optimized core (original kept as `.orig`) | `RetroArch/.retroarch/cores/tic80_libretro.so` | 2.5–3.5× faster |
| Performance governor before launch | `Emu/TIC/launch.sh`, `Emu/TIC/cpufreq.sh` | Onion's TIC-80 launcher leaves the CPU on `ondemand`; the PICO-8 launcher already does this |
| CPU clock 1500 MHz while TIC-80 runs | `Saves/CurrentProfile/config/TIC-80/cpuclock.txt` | Onion's RetroArch reads this file per core; stock is 1200 MHz |
| Square pixels, no stretching | `Saves/CurrentProfile/config/TIC-80/TIC-80.cfg` | see below |
| Old save states moved aside (only if the core changed) | `Saves/CurrentProfile/states/TIC-80-backup-*` | states aren't compatible between core versions |

**The aspect fix.** Onion's RetroArch uses the `sdl_dingux` video driver, which **ignores**
`aspect_ratio_index`. The setting that matters is `video_dingux_ipu_keep_aspect` (default `false`,
which stretches everything). With it set to `true`, TIC-80's 16:9 picture fills the full width
with black bars above and below.

Safe to re-run. **Re-run it after updating Onion** or reinstalling TIC-80 from the Package
Manager, because those overwrite the core and the launcher.

## 4. Download games (optional)

```sh
./download-games.sh
```

- **PICO-8:** the 20 most-liked featured carts on the Lexaloffle BBS, saved to `Roms/PICO/*.p8.png`.
- **TIC-80:** the top 20 rated games on tic80.com plus frantisek's carts, saved to `Roms/TIC/*.tic`,
  with covers in `Roms/TIC/Imgs/`.

Edit the two lists at the top of the script to change the selection. Files already on the card
are skipped. The script also deletes Onion's game-list caches so new games show up.

## 5. Benchmark builds (optional)

```sh
./build-core.sh v1.4.1 -O2     # build a variant to compare
./bench/make-bench-app.sh O3=dist/tic80_libretro.so O2=work/out-v1.4.1-O2/tic80_libretro.so
```

On the Miyoo, open **Apps → TIC-80 Benchmark** and wait about a minute per core while
"Running…" is on screen. Then read `App/TICBench/results.txt` on the PC and delete `App/TICBench`.
The core currently installed is always included as `installed`.

## 6. Speed budget: draw calls and languages (optional)

```sh
./bench/make-budget-app.sh       # installs Apps -> "TIC-80 Speed Budget" on the card
# on the Miyoo: run it (~6 min), then back on the PC:
./bench/budget-report.py         # prints tables + saves App/TICBudget/budget.md on the card
```

It measures the core installed on the card at your TIC-80 CPU clock. It reports:

- **Empty frame cost.** What's left of the 16.67 ms frame for your game at 60 fps.
- **Cost of each drawing call when called from Lua**, and how many fit in one frame: `pix`,
  `poke`, `cls`, `line`, `rect`/`rectb`, `circ`/`circb`, `tri`, `ttri`, `spr` (8×8, 32×32,
  scaled), `map` (full screen) and `print`. One generated cart per call (`bench/make_gfx_carts.py`).
- **Game-logic speed of each language.** The same integer and array loop in Lua, MoonScript,
  YueScript, Fennel, JS, Wren, Squirrel, Python and Scheme (`bench/make_lang_carts.py`).
- **A realistic mix per language.** TIC-80's official bunnymark in each language, including WASM.
  It's converted from the TIC-80 source with `bench/prj2tic.py`.

On a PC, as a reference (the Miyoo is much slower, so run the app for real numbers):
- MoonScript, YueScript and Fennel run as fast as Lua, because they compile to Lua.
- JS is about 2× slower than Lua, Scheme 2×, Squirrel 2.7×, Wren 3.5× and Python 7× for pure logic.
- With sprites involved, as in bunnymark, the differences shrink to 1.0–1.35×, because drawing
  dominates.

To compare two runs, for example before and after a core change, keep a copy of
`App/TICBudget/results.txt` from each and run:

```sh
./bench/budget-compare.py before/results.txt after/results.txt
```

### Check that a core change doesn't change rendering

```sh
./bench/verify-render.sh                 # generated test carts + bunnymarks
./bench/verify-render.sh ~/my-carts 600  # your own .tic carts, 600 frames each
```

This builds PC versions of plain and patched TIC-80, runs every cart in both with the same
scripted input and a fixed clock, and compares a checksum of every frame. Carts that differ
between two runs of the *plain* core are reported as non-deterministic and skipped. The usual
cause is Lua `pairs()` order, which depends on memory addresses.

`bench/prj2tic.py` also works on its own. It turns TIC-80 text projects (`.lua`, `.js`, `.py`, …,
or `.wasmp` + `--binary x.wasm`) into `.tic` carts the libretro core can load.

---

## Troubleshooting

- **Eject safely**:
  `udisksctl unmount -b /dev/sdX1 && udisksctl power-off -b /dev/sdX`.
- **Changes don't take effect.** Add `--log-file /mnt/SDCARD/tic_retroarch.log` to the retroarch
  line in `Emu/TIC/launch.sh` and play a game. The log shows `Core-specific overrides found at …`,
  the `[CPU]` clock lines, and any errors.
- **A game crashes or freezes at 1500 MHz.** Lower `cpuclock.txt` to `1400` or `1300`, or delete
  it to go back to stock speed.
- **Go back to the stock core.** Rename `tic80_libretro.so.orig` to `tic80_libretro.so`, and
  `tic80_libretro.info.orig` to `tic80_libretro.info`.
- **A TIC-80 cart shows a script error** such as `attempt to call a nil value (global 'vbank')`.
  It needs a newer TIC-80, or it's written in a language this build leaves out (Ruby, Janet,
  Gravity, MiniScript).
- **PICO-8 carts.** FAKE-08 runs most carts but not all. Heavy 3D ones like PICOHOT may struggle.
  Multicart games such as PICOWARE don't work.
- **The console's `timeout` command.** It's an old BusyBox version (`timeout -t N cmd`), so don't
  use `timeout N cmd` in scripts that run on the Miyoo.
- **File dates.** The Miyoo writes 1980 timestamps, so dates can't tell you what changed on the card.

---

## License and credits

The scripts and tools in this repository are MIT licensed (see `LICENSE`).

- `patches/` modifies [TIC-80](https://github.com/nesbox/TIC-80), which is © Vadim Grigoruk and
  MIT licensed.
- The bunnymark test carts come from TIC-80's `demos/bunny`.
- [Onion OS](https://github.com/OnionUI/Onion), PICO-8/FAKE-08 and the downloaded games belong to
  their respective authors. They're fetched from their official sites and aren't included here.
