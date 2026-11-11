"""Generate the same pure-computation benchmark in each TIC-80 language (no drawing).
Per frame: N iterations of   s = (s*17 + i) % 1000003 ;  a[i%100] = a[(i+1)%100] + s%7
(integer math + modulo + array read/write - typical game-logic work).
Cost per iteration = (ms/frame - empty cart ms/frame) / N.

usage: python3 -I make_lang_carts.py <out-dir>
Writes <out-dir>/calc_<lang>.tic and <out-dir>/calc_tests.txt ("name N" per line).
(WASM is not included: it needs a compiler toolchain; its speed shows in the bunnymark test.)
"""
import os
import struct
import sys

N = 20000

SRC = {
"lua": f"""-- script: lua
local a={{}} for i=0,99 do a[i]=i end
local s=0
function TIC()
 for i=1,{N} do
  s=(s*17+i)%1000003
  a[i%100]=a[(i+1)%100]+s%7
 end
end
""",
"moon": f"""-- script: moon
a = {{}}
for i=0,99
  a[i] = i
s = 0
export TIC = ->
  for i=1,{N}
    s = (s*17+i)%1000003
    a[i%100] = a[(i+1)%100]+s%7
""",
"yue": f"""-- script: yue
a = {{}}
for i=0,99
  a[i] = i
s = 0
global TIC=->
  for i=1,{N}
    s = (s*17+i)%1000003
    a[i%100] = a[(i+1)%100]+s%7
""",
"fennel": f""";; script: fennel
(local a {{}})
(for [i 0 99] (tset a i i))
(var s 0)
(fn _G.TIC []
  (for [i 1 {N}]
    (set s (% (+ (* s 17) i) 1000003))
    (tset a (% i 100) (+ (. a (% (+ i 1) 100)) (% s 7)))))
""",
"js": f"""// script: js
var a=[]; for(var i=0;i<100;i++) a[i]=i;
var s=0;
function TIC(){{
  for(var i=1;i<={N};i++){{
    s=(s*17+i)%1000003;
    a[i%100]=a[(i+1)%100]+s%7;
  }}
}}
""",
"wren": f"""// script: wren
class Game is TIC {{
  construct new() {{
    _a = List.filled(100, 0)
    for (i in 0...100) _a[i] = i
    _s = 0
  }}
  TIC() {{
    for (i in 1..{N}) {{
      _s = (_s*17+i)%1000003
      _a[i%100] = _a[(i+1)%100]+_s%7
    }}
  }}
}}
""",
"squirrel": f"""// script: squirrel
a <- array(100, 0);
for(local i=0;i<100;i++) a[i]=i;
s <- 0;
function TIC() {{
  for(local i=1;i<={N};i++) {{
    s=(s*17+i)%1000003;
    a[i%100]=a[(i+1)%100]+s%7;
  }}
}}
""",
"python": f"""# script: python
a=[i for i in range(100)]
s=0
def TIC():
  global s
  for i in range(1,{N + 1}):
    s=(s*17+i)%1000003
    a[i%100]=a[(i+1)%100]+s%7
""",
"scheme": f""";; script: scheme
(define a (make-vector 100 0))
(do ((i 0 (+ i 1))) ((= i 100)) (vector-set! a i i))
(define s 0)
(define (TIC)
  (do ((i 1 (+ i 1))) ((> i {N}))
    (set! s (modulo (+ (* s 17) i) 1000003))
    (vector-set! a (modulo i 100) (+ (vector-ref a (modulo (+ i 1) 100)) (modulo s 7)))))
""",
}


def tic_chunk(ctype, data):
    return struct.pack("<BHB", ctype, len(data) & 0xFFFF, 0) + data


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "calc_tests.txt"), "w") as f:
        for lang, code in SRC.items():
            open(os.path.join(out, f"calc_{lang}.tic"), "wb").write(tic_chunk(5, code.encode()))
            f.write(f"calc_{lang}\t{N}\n")
    print(f"{len(SRC)} carts in {out}")
