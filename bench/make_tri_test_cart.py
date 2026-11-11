"""Generate a stress-test cart for triangle drawing (tri, trib, ttri with all texture sources and
depth, textri with sprites and map), used by verify-render.sh to check that core changes keep
rendering identical. Triangles rotate with sub-pixel motion, go off-screen, use huge/negative
texture coordinates and are drawn under changing clip() regions.

usage: python3 -I make_tri_test_cart.py <out.tic>
"""
import struct
import sys

CODE = """-- script: lua
t=0
local cos,sin=math.cos,math.sin
local function tri3(cx,cy,r,a)
 return cx+r*cos(a),cy+r*sin(a),cx+r*cos(a+2.1),cy+r*sin(a+2.1),cx+r*cos(a+4.2),cy+r*sin(a+4.2)
end
function TIC()
 local a=t/37
 if t%120<60 then clip() else clip(13+t%20,7,190,110) end
 cls(t%16)
 -- big shapes first (drawn over by the small ones below, so every call stays visible)
 tri(-60+t%40,-40,300,20+t%30,90,210,(t//7)%16)
 -- big perspective quad (two triangles, map texture, with depth) in the left half
 local z=1.2+sin(a)*0.8
 ttri(-20,130,120,130,60,20,0,256,256,256,0,0,1,-1,0.5,0.5,z)
 ttri(120,130,90,20,60,20,256,256,256,0,0,0,1,-1,0.5,z,z)
 -- big textri from the map with huge/negative UVs in the right part, transparent color 0
 textri(130,-20,270,10,200,170,0,0,500,40,-300,600,true,0)
 -- ttri: all texture sources, chroma key on/off, large and negative UVs
 for k=0,5 do
  local x1,y1,x2,y2,x3,y3=tri3(25+k*38,35+(k%2)*10,10+k*2+t%7,a*(1+k*0.3)+k)
  local s=8+k*13
  ttri(x1,y1,x2,y2,x3,y3,-s+t%7,-3,s*3,1,5,s*2+0.5,k%3,(k==1 or k==4) and 0 or -1)
 end
 -- ttri with perspective depth (overlapping, so the z-buffer decides)
 for k=0,2 do
  local x1,y1,x2,y2,x3,y3=tri3(70+k*45,95,18,-a+k)
  ttri(x1,y1,x2,y2,x3,y3,0,0,64,0,0,64,k%2,-1,1+k*0.5,2+k,3-k*0.4)
 end
 -- textri (deprecated API): sprite sheet and map, with/without transparency
 for k=0,3 do
  local x1,y1,x2,y2,x3,y3=tri3(30+k*60,118,12+k*2,a*1.7+k*2)
  textri(x1,y1,x2,y2,x3,y3,k*20-10,k*7,100+k*30,10,30,90+k*40,k%2==1,k==2 and 0 or -1)
 end
 trib(-10,5,250,60+t%50,40,140,(t//5)%16)
 t=t+1
end
"""


def chunk(ctype, data):
    return struct.pack("<BHB", ctype, len(data) & 0xFFFF, 0) + data


def main(out):
    # tiles + sprites: varied deterministic pixels, including color 0 (transparent tests)
    tiles = bytearray()
    for n in range(256):
        for k in range(32):
            a = (n * 7 + k * 3 + (n >> 3)) % 16
            b = (n * 5 + k * 11 + 1) % 16
            tiles.append(a | (b << 4))
    sprites = bytes((b * 3 + 1) & 0xFF for b in tiles)
    # map: 240x136 tile indices
    mp = bytes((x * 3 + y * 7 + (x * y) % 5) % 256 for y in range(136) for x in range(240))
    pal = bytes.fromhex("1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f6"
                        "73eff7f4f4f494b0c2566c86333c57")
    data = (chunk(1, bytes(tiles)) + chunk(2, sprites) + chunk(12, pal)
            + chunk(4, mp[:65535]) + chunk(5, CODE.encode()))
    # map is 32640 bytes - fits one chunk
    open(out, "wb").write(data)
    print(f"{out}: {len(data)} bytes")


if __name__ == "__main__":
    main(sys.argv[1])
