#!/usr/bin/env bash
# OPTIONAL: measure the "speed budget" on the Miyoo: cost of each TIC-80 drawing call and
# speed of each scripting language, using the core installed on the card.
#
# usage: ./bench/make-budget-app.sh            (card labelled MIYOO must be inserted)
# Then on the Miyoo: Apps -> "TIC-80 Speed Budget" (~6 min).
# Then on the PC:    ./bench/budget-report.py   (reads the results from the card, prints tables)
#
# Graphics: one Lua cart per call (bench/make_gfx_carts.py), each repeating the call N times
#           per frame. Cost per call = (ms/frame - empty cart ms/frame) / N.
# Languages: (a) the same integer/array loop in 9 languages (bench/make_lang_carts.py), and
#           (b) TIC-80's official "bunnymark" in each language (demos/bunny in the TIC-80 source).
#           Measured at two bunny counts; cost per bunny = difference / bunnies added.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="aemiii91/miyoomini-toolchain:latest"
SRC=$(ls -d "$HERE"/work/tic80-v* 2>/dev/null | sort -V | tail -1)
[ -n "$SRC" ] || { echo "Run ./build-core.sh first (it fetches the TIC-80 source)."; exit 1; }

PART=$(lsblk -lno NAME,LABEL | awk '$2=="MIYOO"{print "/dev/"$1; exit}')
[ -n "$PART" ] || { echo "No card labelled MIYOO found."; exit 1; }
findmnt "$PART" >/dev/null || udisksctl mount -b "$PART" >/dev/null
M=$(findmnt -no TARGET "$PART")

# 1. benchmark program (ARM)
B="$HERE/work/bench"; mkdir -p "$B"
cp "$HERE/bench/ticbench.c" "$(find "$SRC" -path '*libretro-common/include/libretro.h' | head -1)" "$B/"
docker run --rm --user "$(id -u):$(id -g)" -v "$B:/b" "$IMAGE" \
  /opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-gcc -O2 -mcpu=cortex-a7 -mfpu=neon-vfpv4 \
  -mfloat-abi=hard -o /b/ticbench /b/ticbench.c -ldl -pthread

# 2. carts
A="$M/App/TICBudget"; rm -rf "$A"; mkdir -p "$A/gfx" "$A/lang" "$A/calc"
cp "$B/ticbench" "$A/"
python3 -I "$HERE/bench/make_gfx_carts.py" "$A/gfx"
python3 -I "$HERE/bench/make_lang_carts.py" "$A/calc"
D="$SRC/demos/bunny"
# name | project file | bunnies added per frame while UP is held (wren's 1...5 loop adds 4)
LANGS="lua|luamark.lua|5 moon|moonmark.moon|5 yue|yuemark.yue|5 js|jsmark.js|5 wren|wrenmark.wren|4 squirrel|squirrelmark.nut|5 python|pythonmark.py|5 scheme|schememark.scm|5"
: > "$A/lang/lang_tests.txt"
for e in $LANGS; do
  IFS='|' read -r name prj per <<<"$e"
  python3 -I "$HERE/bench/prj2tic.py" "$D/$prj" "$A/lang/$name.tic" >/dev/null
  printf '%s\t%s\n' "$name" "$per" >> "$A/lang/lang_tests.txt"
done
python3 -I "$HERE/bench/prj2tic.py" "$D/wasmmark/wasmmark.wasmp" "$A/lang/wasm.tic" \
  --binary "$D/wasmmark/wasmmark.wasm" >/dev/null
printf 'wasm\t5\n' >> "$A/lang/lang_tests.txt"

# 3. app
cat > "$A/config.json" <<'EOF'
{
    "label": "TIC-80 Speed Budget",
    "icon": "../../Icons/Default/tic.png",
    "launch": "launch.sh",
    "description": "Cost of TIC-80 draw calls + languages (~6 min)"
}
EOF
cat > "$A/launch.sh" <<'EOF'
#!/bin/sh
# no 'timeout' on purpose: the Miyoo's busybox timeout has a different syntax
cd "$(dirname "$0")"
bin=/mnt/SDCARD/.tmp_update/bin
core=/mnt/SDCARD/RetroArch/.retroarch/cores/tic80_libretro.so
$bin/infoPanel --title "TIC-80 SPEED BUDGET" --message "Running... about 6 minutes.\nPlease wait, don't press anything." --persistent &
panel=$!
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
mhz=$(cat /mnt/SDCARD/Saves/CurrentProfile/config/TIC-80/cpuclock.txt 2>/dev/null || echo 1200)
$bin/cpuclock $mhz
{
  echo "cpu_mhz	$mhz"
  while IFS='	' read -r name n desc; do
    printf 'gfx\t%s\t%s\t' "$name" "$n"
    ./ticbench "$core" "gfx/$name.tic" 20 300 3 2>>errors.txt || echo "FAILED"
  done < gfx/gfx_tests.txt
  # the triangle tests again with the "Fast Triangles" core option enabled
  for name in tri32 ttri32 ttri32map ttri32z; do
    n=$(grep "^$name	" gfx/gfx_tests.txt | cut -f2)
    printf 'gfx\t%s_fast\t%s\t' "$name" "$n"
    TICBENCH_OPTS=tic80_fast_triangles=enabled ./ticbench "$core" "gfx/$name.tic" 20 300 3 2>>errors.txt || echo "FAILED"
  done
  while IFS='	' read -r name n; do
    printf 'calc\t%s\t%s\t' "$name" "$n"
    ./ticbench "$core" "calc/$name.tic" 20 300 3 2>>errors.txt || echo "FAILED"
  done < calc/calc_tests.txt
  while IFS='	' read -r name per; do
    printf 'lang\t%s\t%s\t' "$name" "$per"
    ./ticbench "$core" "lang/$name.tic" bunny 20 60 60 6 2>>errors.txt || echo "FAILED"
  done < lang/lang_tests.txt
  echo "done"
} > results.txt 2>&1
echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
kill $panel 2>/dev/null; sync
$bin/infoPanel --title "TIC-80 SPEED BUDGET" --message "Done! Put the SD card\nback in the PC." --auto
EOF
sh -n "$A/launch.sh"
sync
echo "Installed $A ($(du -sh "$A" | cut -f1)). Eject the card and run Apps -> TIC-80 Speed Budget."
