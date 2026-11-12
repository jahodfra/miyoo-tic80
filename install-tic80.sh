#!/usr/bin/env bash
# STEP 3 (PC, after the first boot on the Miyoo): install the optimized TIC-80 core + fixes.
#
# usage: ./install-tic80.sh [card-mountpoint] [core.so]
#   defaults: the mounted card labelled MIYOO, dist/tic80_libretro.so
# env:   CPU_MHZ=1500  (clock while a TIC-80 game runs; 1200 = stock, delete cpuclock.txt to disable)
#        FAST_TRIANGLES=1|0  switch the core's "Fast Triangles" option on/off (unset: leave as is)
#
# What it does (each step is safe to re-run):
#   1. core      -> RetroArch/.retroarch/cores/tic80_libretro.so  (original kept as .so.orig)
#   2. speed     -> Emu/TIC/launch.sh runs cpufreq.sh (performance governor) + cpuclock.txt
#   3. aspect    -> TIC-80.cfg override: square pixels, full width, black bars (no stretching)
#   4. states    -> if the TIC-80 version changed, moves old save states aside (incompatible)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CPU_MHZ="${CPU_MHZ:-1500}"

M="${1:-}"
if [ -z "$M" ]; then
  PART=$(lsblk -lno NAME,LABEL | awk '$2=="MIYOO"{print "/dev/"$1; exit}')
  [ -n "$PART" ] || { echo "No card labelled MIYOO found - pass the mount point."; exit 1; }
  findmnt "$PART" >/dev/null || udisksctl mount -b "$PART" >/dev/null
  M=$(findmnt -no TARGET "$PART")
fi
CORE="${2:-$HERE/dist/tic80_libretro.so}"
[ -f "$CORE" ] || { echo "Core $CORE not found - run ./build-core.sh first."; exit 1; }

CORES="$M/RetroArch/.retroarch/cores"
EMU="$M/Emu/TIC"
CFG="$M/Saves/CurrentProfile/config/TIC-80"
STATES="$M/Saves/CurrentProfile/states"
for d in "$CORES" "$M/Saves/CurrentProfile/config"; do
  [ -d "$d" ] || { echo "Missing $d - boot the card in the Miyoo once first (Onion installs on first boot)."; exit 1; }
done
[ -d "$EMU" ] || { echo "Missing $EMU - enable 'TIC-80' in Apps -> Package Manager on the Miyoo first."; exit 1; }
echo "card: $M"

# 1. core ----------------------------------------------------------------------
# TIC-80 version of the new core (BUILD-INFO.txt) and of the installed one (our marker file,
# else the version number in the .info file). Save states only break between versions.
ver_of() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
NEWVER=$(head -1 "$(dirname "$CORE")/BUILD-INFO.txt" 2>/dev/null | ver_of || true)
if [ -f "$CORES/tic80_libretro.build" ]; then
  OLDVER=$(head -1 "$CORES/tic80_libretro.build" | ver_of || true)
else
  OLDVER=$(grep '^display_version' "$CORES/tic80_libretro.info" | ver_of || true)
fi
CHANGED=1
cmp -s "$CORE" "$CORES/tic80_libretro.so" && CHANGED=0
[ -n "$NEWVER" ] && [ "$NEWVER" = "$OLDVER" ] && CHANGED=0
echo "TIC-80 version: installed ${OLDVER:-?} -> new ${NEWVER:-?}"
[ -f "$CORES/tic80_libretro.so.orig" ] || cp -p "$CORES/tic80_libretro.so" "$CORES/tic80_libretro.so.orig"
[ -f "$CORES/tic80_libretro.info.orig" ] || cp -p "$CORES/tic80_libretro.info" "$CORES/tic80_libretro.info.orig"
cp "$CORE" "$CORES/tic80_libretro.so"
ver=$(head -1 "$(dirname "$CORE")/BUILD-INFO.txt" 2>/dev/null | cut -d, -f1-2 | sed 's/TIC-80 //' || true)
sed -i "s/^display_version = .*/display_version = \"${ver:-optimized} (Mini+)\"/" "$CORES/tic80_libretro.info"
cp "$(dirname "$CORE")/BUILD-INFO.txt" "$CORES/tic80_libretro.build" 2>/dev/null || true
cmp -s "$CORE" "$CORES/tic80_libretro.so" && echo "1. core installed (original: tic80_libretro.so.orig)"

# 2. speed ---------------------------------------------------------------------
cat > "$EMU/cpufreq.sh" <<'EOF'
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
EOF
cat > "$EMU/launch.sh" <<'EOF'
#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
homedir=`dirname "$1"`

# Run the CPU at full speed while playing (Onion resets it to ondemand on exit).
# The clock itself is set by RetroArch from Saves/CurrentProfile/config/TIC-80/cpuclock.txt
cd $progdir
./cpufreq.sh

cd /mnt/SDCARD/RetroArch/
HOME=/mnt/SDCARD/RetroArch/ $progdir/../../RetroArch/retroarch -v -L $progdir/../../RetroArch/.retroarch/cores/tic80_libretro.so "$1"
EOF
mkdir -p "$CFG"
printf '%s' "$CPU_MHZ" > "$CFG/cpuclock.txt"
echo "2. speed: performance governor + ${CPU_MHZ} MHz"

# 3. aspect ----------------------------------------------------------------------
# Onion's sdl_dingux video driver ignores aspect_ratio_index; video_dingux_ipu_keep_aspect is what counts.
cat > "$CFG/TIC-80.cfg" <<'EOF'
video_dingux_ipu_keep_aspect = "true"
aspect_ratio_index = "21"
video_scale_integer = "false"
EOF
echo "3. aspect: square pixels (TIC-80 only)"

# optional: "Fast Triangles" core option (TIC-80.opt is RetroArch's core options file)
if [ -n "${FAST_TRIANGLES:-}" ]; then
  val=disabled; [ "$FAST_TRIANGLES" = 1 ] && val=enabled
  OPT="$CFG/TIC-80.opt"; touch "$OPT"
  grep -v '^tic80_fast_triangles ' "$OPT" > "$OPT.tmp" || true
  printf 'tic80_fast_triangles = "%s"\n' "$val" >> "$OPT.tmp" && mv "$OPT.tmp" "$OPT"
  echo "   fast triangles: $val"
fi

# 4. old save states -------------------------------------------------------------
# (only when the TIC-80 version changed - states from the same version stay)
if [ "$CHANGED" = 1 ] && [ -d "$STATES/TIC-80" ] && [ -n "$(ls -A "$STATES/TIC-80")" ]; then
  B="$STATES/TIC-80-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$B"; mv "$STATES/TIC-80/"* "$B/"
  echo "4. old save states moved to ${B#$M/}"
else
  echo "4. save states kept (same TIC-80 version, or none present)"
fi

sync
echo "done. Eject with: udisksctl unmount -b <partition> && udisksctl power-off -b <disk>"
