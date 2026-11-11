#!/usr/bin/env bash
# OPTIONAL: compare TIC-80 core builds on the Miyoo itself.
#
# usage: ./bench/make-bench-app.sh <name>=<core.so> [<name>=<core.so> ...]
#   e.g. ./bench/make-bench-app.sh new-O3=dist/tic80_libretro.so old-O2=work/out-v1.4.1-O2/tic80_libretro.so
#
# Installs Apps -> "TIC-80 Benchmark" on the card. It always also tests the core currently
# installed in RetroArch ("installed"). On the Miyoo: open the app, wait (~1 min per core),
# then read App/TICBench/results.txt on the PC. Delete App/TICBench afterwards.
# Each test runs the cart unthrottled (no frame limit, no display) with scripted button presses
# and reports frames/second - so >60 means headroom, <60 means the game will lag.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="aemiii91/miyoomini-toolchain:latest"
CARTS=("FPS80" "Dragon Fury" "Supernova" "Portal TIC-80" "8 Bit Panda" "Shadow Over the Twelve Lands")
[ $# -ge 1 ] || { sed -n 2,12p "$0"; exit 1; }

PART=$(lsblk -lno NAME,LABEL | awk '$2=="MIYOO"{print "/dev/"$1; exit}')
[ -n "$PART" ] || { echo "No card labelled MIYOO found."; exit 1; }
findmnt "$PART" >/dev/null || udisksctl mount -b "$PART" >/dev/null
M=$(findmnt -no TARGET "$PART")

# build the benchmark program (needs libretro.h from the TIC-80 source fetched by build-core.sh)
H=$(find "$HERE/work" -path '*libretro-common/include/libretro.h' 2>/dev/null | head -1)
[ -n "$H" ] || { echo "Run ./build-core.sh first (it fetches the TIC-80 source)."; exit 1; }
B="$HERE/work/bench"; mkdir -p "$B"
cp "$HERE/bench/ticbench.c" "$H" "$B/"
docker run --rm --user "$(id -u):$(id -g)" -v "$B:/b" "$IMAGE" \
  /opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-gcc -O2 -mcpu=cortex-a7 -mfpu=neon-vfpv4 \
  -mfloat-abi=hard -o /b/ticbench /b/ticbench.c -ldl -pthread

A="$M/App/TICBench"; rm -rf "$A"; mkdir -p "$A/cores" "$A/carts"
cp "$B/ticbench" "$A/"
names=""
for arg in "$@"; do
  n=${arg%%=*}; so=${arg#*=}
  [ -f "$so" ] || { echo "missing $so"; exit 1; }
  cp "$so" "$A/cores/$n.so"; names="$names cores/$n.so"
done
for c in "${CARTS[@]}"; do
  [ -f "$M/Roms/TIC/$c.tic" ] && cp "$M/Roms/TIC/$c.tic" "$A/carts/" || echo "note: $c.tic not on card, skipped"
done

cat > "$A/config.json" <<'EOF'
{
    "label": "TIC-80 Benchmark",
    "icon": "../../Icons/Default/tic.png",
    "launch": "launch.sh",
    "description": "Compare TIC-80 core builds"
}
EOF
cat > "$A/launch.sh" <<EOF
#!/bin/sh
# note: no 'timeout' here - the Miyoo's old busybox timeout has different syntax;
# ticbench stops itself after 8 s per test.
cd "\$(dirname "\$0")"
bin=/mnt/SDCARD/.tmp_update/bin
installed=/mnt/SDCARD/RetroArch/.retroarch/cores/tic80_libretro.so
\$bin/infoPanel --title "TIC-80 BENCHMARK" --message "Running... please wait,\ndon't press anything." --persistent &
panel=\$!
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
\$bin/cpuclock \$(cat /mnt/SDCARD/Saves/CurrentProfile/config/TIC-80/cpuclock.txt 2>/dev/null || echo 1200)
{
  echo "=== TIC-80 benchmark"
  for cart in carts/*.tic; do
    echo "--- \$(basename "\$cart")"
    for core in "\$installed"$names; do
      name=\$(basename "\$core" .so); [ "\$core" = "\$installed" ] && name=installed
      printf "%-14s " "\$name"
      ./ticbench "\$core" "\$cart" 120 1500 8 2>>errors.txt || echo "FAILED (exit \$?)"
    done
  done
  echo "=== done"
} > results.txt 2>&1
echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
kill \$panel 2>/dev/null; sync
\$bin/infoPanel --title "TIC-80 BENCHMARK" --message "Done! Results in\nApp/TICBench/results.txt" --auto
EOF
sh -n "$A/launch.sh"
sync
echo "Installed $A. Eject the card, run Apps -> TIC-80 Benchmark on the Miyoo."
