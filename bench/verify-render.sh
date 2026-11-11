#!/usr/bin/env bash
# Check that the patched TIC-80 core renders exactly like plain upstream TIC-80.
#
# usage: ./bench/verify-render.sh [cart-dir] [frames]
#   cart-dir: folder of .tic carts (default: generated drawing/language tests + bunnymarks)
#   frames:   frames per cart (default 600)
#
# Builds PC (x86-64) versions of both cores in Docker (~10 min the first time), runs every cart
# with the same scripted button input, and compares a checksum of every frame.
# A fixed clock (bench/fixedtime.c) makes carts that seed randomness from the time repeatable.
# Carts that still differ between two runs of the *plain* core are reported as
# non-deterministic (e.g. Lua pairs() order depends on memory addresses) and not compared.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="aemiii91/miyoomini-toolchain:latest"
TAG="v1.4.1"
FRAMES="${2:-600}"
W="$HERE/work"
V="$W/verify"
mkdir -p "$V" "$W/scripts" "$W/bench"

[ -d "$W/tic80-$TAG" ] && [ -x "$W/tools/cmake/bin/cmake" ] || { echo "Run ./build-core.sh first."; exit 1; }
if [ ! -d "$W/tic80-$TAG-plain" ]; then
  git clone --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules \
    https://github.com/nesbox/TIC-80.git "$W/tic80-$TAG-plain"
fi
cp "$HERE/scripts/docker-build-x86.sh" "$HERE/scripts/libretro.map" "$W/scripts/"
cp "$HERE/bench/ticbench.c" "$HERE/bench/fixedtime.c" "$W/bench/"
cp "$(find "$W/tic80-$TAG" -path '*libretro-common/include/libretro.h' | head -1)" "$W/bench/"

run() { docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$W:/work" "$@"; }

for v in plain patched; do
  src="tic80-$TAG"; [ $v = plain ] && src="tic80-$TAG-plain"
  if [ ! -f "$W/x86-$v/tic80_libretro.so" ]; then
    echo ">> building PC core: $v"
    run -e SRC="/work/$src" -e OUT="/work/x86-$v" "$IMAGE" /work/scripts/docker-build-x86.sh
  fi
done
run "$IMAGE" sh -c 'cd /work/bench && gcc -O2 -o ticbench-x86 ticbench.c -ldl -pthread &&
                    gcc -O2 -shared -fPIC -o fixedtime.so fixedtime.c'

# carts
C="${1:-}"
if [ -z "$C" ]; then
  C="$V/carts"; rm -rf "$C"; mkdir -p "$C"
  python3 -I "$HERE/bench/make_gfx_carts.py" "$C" >/dev/null
  python3 -I "$HERE/bench/make_lang_carts.py" "$C" >/dev/null
  D="$W/tic80-$TAG/demos/bunny"
  for p in luamark.lua moonmark.moon yuemark.yue jsmark.js wrenmark.wren squirrelmark.nut pythonmark.py schememark.scm; do
    python3 -I "$HERE/bench/prj2tic.py" "$D/$p" "$C/${p%%.*}.tic" >/dev/null
  done
  python3 -I "$HERE/bench/prj2tic.py" "$D/wasmmark/wasmmark.wasmp" "$C/wasmmark.tic" --binary "$D/wasmmark/wasmmark.wasm" >/dev/null
else
  C="$(cd "$C" && pwd)"
fi
rm -rf "$V/out"; mkdir -p "$V/out"

echo ">> running $(ls "$C"/*.tic | wc -l) carts x $FRAMES frames (plain twice, patched once)"
docker run --rm --user "$(id -u):$(id -g)" -v "$W:/work" -v "$C:/carts:ro" "$IMAGE" sh -c '
  cd /work/verify/out
  for c in /carts/*.tic; do
    n=$(basename "$c" .tic)
    for r in plain:a plain:b patched:p; do
      core=${r%%:*}; tag=${r#*:}
      LD_PRELOAD=/work/bench/fixedtime.so /work/bench/ticbench-x86 /work/x86-$core/tic80_libretro.so "$c" hash '"$FRAMES"' \
        > "$n.$tag" 2>/dev/null || echo crash > "$n.$tag"
    done
  done'

same=0; diff=0; nondet=0
for a in "$V"/out/*.a; do
  n=$(basename "$a" .a)
  if ! cmp -s "$a" "$V/out/$n.b"; then
    echo "  non-deterministic (skipped): $n"; nondet=$((nondet + 1))
  elif cmp -s "$a" "$V/out/$n.p"; then
    same=$((same + 1))
  else
    first=$(diff "$a" "$V/out/$n.p" | sed -n 2p | cut -d' ' -f2)
    echo "  DIFFERENT: $n (first differing frame: $first)"; diff=$((diff + 1))
  fi
done
echo "identical: $same   different: $diff   non-deterministic: $nondet"
[ "$diff" = 0 ]
