#!/bin/sh
# Runs INSIDE the toolchain container (called by build-core.sh).
# Env: SRC (source dir), OUT (output dir), OPT (e.g. -O3), LANGS (cmake -D flags)
set -e
CMAKE=/work/tools/cmake/bin/cmake
CPU="-mcpu=cortex-a7 -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
# -fvisibility=hidden + version script: export only retro_* so LTO can inline internal calls
# (default visibility made ~66,000 internal calls go through the PLT, e.g. every pixel write)
VIS="-fvisibility=hidden"
FLAGS="$OPT $CPU -flto $VIS -DNDEBUG"

mkdir -p "$OUT/build"
cd "$OUT/build"
$CMAKE "$SRC" \
  -DCMAKE_TOOLCHAIN_FILE=/work/scripts/miyoo.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_LIBRETRO=ON -DBUILD_SDL=OFF -DBUILD_SOKOL=OFF -DBUILD_PLAYER=OFF \
  -DBUILD_DEMO_CARTS=OFF -DBUILD_EDITORS=OFF -DBUILD_SURF=OFF -DBUILD_TOOLS=OFF -DBUILD_STUB=ON \
  $LANGS \
  -DCMAKE_C_FLAGS_RELEASE="$FLAGS" -DCMAKE_CXX_FLAGS_RELEASE="$FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$OPT $CPU -flto $VIS -static-libgcc -static-libstdc++ -pthread -Wl,--version-script=/work/scripts/libretro.map" \
  > "$OUT/cmake.log" 2>&1 || { tail -30 "$OUT/cmake.log"; exit 1; }

make -j"$(nproc)" tic80_libretro > "$OUT/make.log" 2>&1 || { grep -E 'error' "$OUT/make.log" | head -30; exit 1; }

so=$(find . -name 'tic80_libretro.so' | head -1)
/opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-strip --strip-unneeded -o "$OUT/tic80_libretro.so" "$so"
ls -l "$OUT/tic80_libretro.so"
