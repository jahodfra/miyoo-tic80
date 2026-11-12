"""Generate a stress-test cart for line(), trib(), rrect() and rrectb(), used by verify-render.sh
to check that core changes keep rendering identical: fractional and off-screen line ends,
steep/flat/single-pixel lines, changing clip() regions, rounded rectangles with radii from 0 to
larger than the box and corner exponents (round, square-ish, pointed, default, negative).

usage: python3 -I make_shapes_test_cart.py <out.tic>
"""
import struct
import sys

CODE = """-- script: lua
t=0
local cos,sin=math.cos,math.sin
function TIC()
 local a=t/41
 if t%90<45 then clip() else clip(11+t%17,9,200,100) end
 cls(t%16)
 -- rounded rectangles: radius 0..beyond half size, many exponents (fill and border)
 local ex={2,2,0,-1,1,3.5,0.3,8,2,0.7}
 for k=0,9 do
  local x,y=4+k*24+(t%5),6+(k%2)*30
  local w,h=18+(t+k*3)%13,20+(t*2+k)%17
  local r=({0,1,3,5,8,-1,30,4,6,2})[k+1]+(t//20)%3
  rrect(x,y,w,h,(k+t//9)%16,r,ex[k+1])
  rrectb(x+2,y+40,w,h,(k*3+t//7)%16,r+1,ex[(k+3)%10+1])
 end
 -- one large rounded rectangle partly off-screen
 rrect(-20+t%30,90,140,70,(t//11)%16,25+t%10,2)
 rrectb(150,80+t%9,120,80,(t//13)%16,31,2)
 -- lines: rotating fan with fractional ends, off-screen ends, single pixel, axis-aligned
 for k=0,23 do
  local ang=a+k*0.2618
  local r=40+(k%4)*25
  line(120.37+cos(ang)*2.5,68.81+sin(ang)*1.7,120+cos(ang)*r,68+sin(ang)*r,k%16)
 end
 line(-100,-50,400,300,(t//3)%16)
 line(-30.5,130.25,260.75,-20.5,(t//5)%16)
 line(50,50,50,50,15)
 line(10.9,120.1,10.2,120.8,14)
 line(0,t%136,239,t%136,13)
 line(t%240,0,t%240,135,12)
 line(5.5,5.5,234.5,6.49,11)
 trib(-15+t%20,-10,250,40+t%25,60,150,(t//4)%16)
 trib(100.5,100.5,140.25,70.75,180.125,120.5,(t//6)%16)
 t=t+1
end
"""


def chunk(ctype, data):
    return struct.pack("<BHB", ctype, len(data) & 0xFFFF, 0) + data


if __name__ == "__main__":
    pal = bytes.fromhex("1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f6"
                        "73eff7f4f4f494b0c2566c86333c57")
    data = chunk(12, pal) + chunk(5, CODE.encode())
    open(sys.argv[1], "wb").write(data)
    print(f"{sys.argv[1]}: {len(data)} bytes")
