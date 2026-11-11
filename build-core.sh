#!/usr/bin/env bash
# Build an optimized TIC-80 libretro core for the Miyoo Mini / Mini+.
#
# usage: ./build-core.sh [tic80-tag] [opt-level]
#   ./build-core.sh                 -> v1.4.1, -O3  (the build we benchmarked as "E")
#   ./build-core.sh v1.4.1 -O2
#
# Output: dist/tic80_libretro.so  (+ dist/BUILD-INFO.txt)
# Patches: patches/tic80-<tag>-*.patch are applied to the source (speed optimizations, see
#          README). NO_PATCHES=1 ./build-core.sh builds plain upstream TIC-80 instead.
# Needs: docker, git, curl. Takes ~5 min (+ a 2.4 GB toolchain image on first run).
set -euo pipefail

TAG="${1:-v1.4.1}"
OPT="${2:-O3}"; OPT="-${OPT#-}"
IMAGE="aemiii91/miyoomini-toolchain:latest"   # Onion's own build toolchain (GCC 8.3, glibc 2.28)
CMAKE_VER="3.27.9"                             # toolchain's cmake 3.13 is too old for TIC-80 1.4

# Languages: everything except the ones that don't build with this toolchain:
#   Ruby (needs host ruby/rake), Janet (runs a cross-compiled helper at build time),
#   Gravity (patch step fails out-of-tree), MiniScript (needs C++20 designated initializers).
LANGS="-DBUILD_WITH_ALL=ON -DBUILD_WITH_RUBY=OFF -DBUILD_WITH_JANET=OFF -DBUILD_WITH_GRAVITY=OFF -DBUILD_WITH_MINISCRIPT=OFF"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/work"
mkdir -p "$WORK/tools" "$WORK/scripts" "$HERE/dist"
cp "$HERE/scripts/miyoo.cmake" "$HERE/scripts/docker-build.sh" "$HERE/scripts/libretro.map" "$WORK/scripts/"
chmod +x "$WORK/scripts/docker-build.sh"

echo ">> toolchain image"
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"

echo ">> cmake $CMAKE_VER"
if [ ! -x "$WORK/tools/cmake/bin/cmake" ]; then
  curl -fL "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VER/cmake-$CMAKE_VER-linux-x86_64.tar.gz" \
    | tar xz -C "$WORK/tools"
  mv "$WORK/tools/cmake-$CMAKE_VER-linux-x86_64" "$WORK/tools/cmake"
fi

SRC_NAME="tic80-$TAG"; SUFFIX=""
[ "${NO_PATCHES:-0}" = 1 ] && { SRC_NAME="tic80-$TAG-plain"; SUFFIX="-plain"; }
echo ">> TIC-80 source $TAG"
if [ ! -d "$WORK/$SRC_NAME" ]; then
  git clone --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules \
    https://github.com/nesbox/TIC-80.git "$WORK/$SRC_NAME"
fi

PATCHES=""
if [ "${NO_PATCHES:-0}" != 1 ]; then
  for p in "$HERE"/patches/tic80-"$TAG"-*.patch; do
    [ -f "$p" ] || continue
    if git -C "$WORK/$SRC_NAME" apply --reverse --check "$p" 2>/dev/null; then
      echo ">> patch already applied: $(basename "$p")"
    else
      echo ">> applying patch: $(basename "$p")"
      git -C "$WORK/$SRC_NAME" apply "$p"
    fi
    PATCHES="$PATCHES $(basename "$p" .patch)"
  done
fi

OUT_NAME="out-$TAG$OPT$SUFFIX"
rm -rf "$WORK/$OUT_NAME"
echo ">> building $TAG with $OPT (log: work/$OUT_NAME/make.log)"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -e SRC="/work/$SRC_NAME" -e OUT="/work/$OUT_NAME" -e OPT="$OPT" -e LANGS="$LANGS" \
  -v "$WORK:/work" "$IMAGE" /work/scripts/docker-build.sh

cp "$WORK/$OUT_NAME/tic80_libretro.so" "$HERE/dist/tic80_libretro.so"
{
  echo "TIC-80 $TAG, $OPT -mcpu=cortex-a7 -mfpu=neon-vfpv4 -flto, built $(date -I)"
  echo "patches:${PATCHES:- none}"
  echo "languages: $(grep -oE 'BUILD_WITH_[A-Z]+: ON' "$WORK/$OUT_NAME/cmake.log" | sed 's/BUILD_WITH_//; s/: ON//' | grep -v ALL | tr '\n' ' ')"
} > "$HERE/dist/BUILD-INFO.txt"

echo ">> sanity check"
readelf -A "$HERE/dist/tic80_libretro.so" | grep -E 'Tag_FP_arch|Advanced_SIMD'
need=$(objdump -T "$HERE/dist/tic80_libretro.so" | grep -oE 'GLIBC_[0-9.]+' | sort -V | tail -1)
echo "highest glibc symbol: $need (Miyoo has 2.28)"
cat "$HERE/dist/BUILD-INFO.txt"
echo "done -> dist/tic80_libretro.so"
