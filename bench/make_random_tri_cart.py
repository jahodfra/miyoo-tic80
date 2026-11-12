"""Generate a cart that draws 600 random flat triangles per frame: sizes from 2 to 200 pixels,
random fractional, pixel-centre and integer coordinates (so many are degenerate - zero area),
partly or fully off-screen, and a clip() region every third frame. Used to check that the
Fast Triangles span code covers exactly the same pixels after changes, and that degenerate or
clipped-away triangles are handled (an early bug left their row range uninitialized).

usage: python3 -I make_random_tri_cart.py <out.tic>
"""
import struct
import sys

CODE = """-- script: lua
t=0
local seed=1
local function rnd() seed=(seed*1103515245+12345)%2147483648 return seed/2147483648 end
function TIC()
 seed=t*31+7
 if t%3==1 then clip(7+t%30,5,180,100) else clip() end
 cls(0)
 for k=1,600 do
  local s=({2,6,20,60,200})[k%5+1]
  local x,y=rnd()*300-30,rnd()*190-27
  local function c() local r=rnd() if r<0.2 then return math.floor(rnd()*s) elseif r<0.4 then return math.floor(rnd()*s)+0.5 end return rnd()*s end
  tri(x+c(),y+c(),x+c(),y+c(),x+c(),y+c(),k%15+1)
 end
 t=t+1
end
"""

if __name__ == "__main__":
    data = struct.pack("<BHB", 5, len(CODE), 0) + CODE.encode()
    open(sys.argv[1], "wb").write(data)
    print(f"{sys.argv[1]}: {len(data)} bytes")
