#!/bin/sh
# Runs INSIDE the toolchain container (called by bench/verify-render.sh).
# PC (x86-64) build of the libretro core, only used to compare rendering on the PC.
# Env: SRC (source dir), OUT (output dir)
set -e
mkdir -p "$OUT/build" && cd "$OUT/build"
/work/tools/cmake/bin/cmake "$SRC" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_LIBRETRO=ON -DBUILD_SDL=OFF -DBUILD_SOKOL=OFF -DBUILD_PLAYER=OFF -DBUILD_DEMO_CARTS=OFF \
  -DBUILD_EDITORS=OFF -DBUILD_SURF=OFF -DBUILD_TOOLS=OFF -DBUILD_STUB=ON \
  -DBUILD_WITH_ALL=ON -DBUILD_WITH_RUBY=OFF -DBUILD_WITH_JANET=OFF -DBUILD_WITH_GRAVITY=OFF -DBUILD_WITH_MINISCRIPT=OFF \
  -DCMAKE_C_FLAGS_RELEASE="-O2 -fvisibility=hidden -DNDEBUG" -DCMAKE_CXX_FLAGS_RELEASE="-O2 -fvisibility=hidden -DNDEBUG" \
  -DCMAKE_SHARED_LINKER_FLAGS="-pthread -Wl,--version-script=/work/scripts/libretro.map" > "$OUT/cmake.log" 2>&1
make -j2 tic80_libretro > "$OUT/make.log" 2>&1 || { grep -E 'error' "$OUT/make.log" | head; exit 1; }
cp "$(find . -name tic80_libretro.so | head -1)" "$OUT/"
ls -l "$OUT/tic80_libretro.so"
