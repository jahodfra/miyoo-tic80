"""Generate one tiny Lua cart per TIC-80 drawing call. Each cart repeats the call N times
per frame, so (ms/frame - empty-cart ms/frame) / N = cost of one call from Lua.

usage: python3 -I make_gfx_carts.py <out-dir>
Writes <out-dir>/<name>.tic and <out-dir>/gfx_tests.txt ("name N description" per line).
"""
import os
import struct
import sys

# name, N per frame, description, Lua statement (i = 1..N)
TESTS = [
    ("empty",     1,     "empty TIC() - baseline frame cost",        ""),
    ("lua_loop",  50000, "Lua loop + arithmetic (per iteration)",    "x=x+i*3%7"),
    ("cls",       50,    "cls() full screen",                        "cls(i%16)"),
    ("pix",       20000, "pix() one pixel",                          "pix(i%240,i%136,i%16)"),
    ("poke",      20000, "poke() one byte of VRAM",                  "poke(i%16320,i%256)"),
    ("line",      500,   "line() 240x136 diagonal",                  "line(0,0,239,135,i%16)"),
    ("rect16",    2000,  "rect() 16x16 filled",                      "rect(i%224,i%120,16,16,i%16)"),
    ("rectfull",  50,    "rect() 240x136 full screen",               "rect(0,0,240,136,i%16)"),
    ("rectb16",   2000,  "rectb() 16x16 outline",                    "rectb(i%224,i%120,16,16,i%16)"),
    ("circ8",     1000,  "circ() radius 8 filled",                   "circ(8+i%224,8+i%120,8,i%16)"),
    ("circb8",    1000,  "circb() radius 8 outline",                 "circb(8+i%224,8+i%120,8,i%16)"),
    ("tri32",     500,   "tri() ~32px filled triangle",              "local x,y=i%208,i%104 tri(x,y,x+32,y+8,x+8,y+32,i%16)"),
    ("ttri32",    300,   "ttri() ~32px textured triangle",           "local x,y=i%208,i%104 ttri(x,y,x+32,y+8,x+8,y+32,0,0,32,0,0,32)"),
    ("ttri32map", 300,   "ttri() ~32px textured from the map",       "local x,y=i%208,i%104 ttri(x,y,x+32,y+8,x+8,y+32,0,0,32,0,0,32,1)"),
    ("textri32",  300,   "textri() ~32px (deprecated API)",          "local x,y=i%208,i%104 textri(x,y,x+32,y+8,x+8,y+32,0,0,32,0,0,32)"),
    ("spr8",      2000,  "spr() 8x8 with transparent color",         "spr(1,i%232,i%128,0)"),
    ("spr32",     500,   "spr() 32x32 (4x4 tiles) transparent",      "spr(1,i%208,i%104,0,1,0,0,4,4)"),
    ("spr8x2",    1000,  "spr() 8x8 scaled x2 (16x16)",              "spr(1,i%224,i%120,0,2)"),
    ("map",       20,    "map() full screen 30x17 tiles",            "map(0,0,30,17,0,0)"),
    ("print",     500,   "print() 12 characters",                    "print('HELLO WORLD!',i%160,i%130,i%16)"),
]


def tic_chunk(ctype, data):
    return struct.pack("<BHB", ctype, len(data) & 0xFFFF, 0) + data


def cart(stmt, n):
    code = "-- script: lua\nx=0\n"
    if stmt:
        code += "function TIC()\n for i=1,%d do %s end\nend\n" % (n, stmt)
    else:
        code += "function TIC() end\n"
    # tiles: a striped pattern so no pixel is transparent-skipped by accident (colors 1..15)
    tile = bytes(((2 * k + 1) % 15 + 1) | (((2 * k + 2) % 15 + 1) << 4) for k in range(32))
    tiles = tile * 256
    # sweetie-16 palette
    pal = bytes.fromhex("1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f6"
                        "73eff7f4f4f494b0c2566c86333c57")
    return (tic_chunk(1, tiles[:8192]) + tic_chunk(2, tiles[:8192]) + tic_chunk(12, pal)
            + tic_chunk(5, code.encode()))


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "gfx_tests.txt"), "w") as f:
        for name, n, desc, stmt in TESTS:
            open(os.path.join(out, name + ".tic"), "wb").write(cart(stmt, n))
            f.write(f"{name}\t{n}\t{desc}\n")
    print(f"{len(TESTS)} carts in {out}")
