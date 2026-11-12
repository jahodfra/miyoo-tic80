"""Generate a cart that checks triangle meshes for gaps and overlaps (watertightness).

usage: python3 -I make_watertight_cart.py <out.tic>

Every frame builds two meshes whose triangles share vertices:
  - a 9x5 grid of jittered quads, each split into two triangles (alternating diagonals),
  - a fan of 24 thin triangles around a centre point,
with vertices at random fractional positions, exactly on pixel centres (k+0.5) and on
integer coordinates, and with random winding (clockwise / counter-clockwise).
Each triangle is drawn alone (tri() and ttri() separately) and the covered pixels are counted.
A pixel whose centre is strictly inside the mesh must be covered exactly once.
Results are reported with trace(), one line per frame and primitive:
  WT frame=<n> prim=<tri|ttri> pixels=<checked> gaps=<n> overlaps=<n>
Run it with TICBENCH_TRACE=1 (and TICBENCH_OPTS=tic80_fast_triangles=enabled for fast mode).
"""
import struct
import sys

CODE = r"""-- script: lua
local frame=0
local seed=1
local function rnd() seed=(seed*1103515245+12345)%2147483648 return seed/2147483648 end
-- a coordinate: random fraction, exact pixel centre or integer
local function coord(v)
 local r=rnd()
 if r<0.25 then return math.floor(v)+0.5 elseif r<0.45 then return math.floor(v+0.5) end
 return v
end

local cov
local function draw(prim,t)
 local x1,y1,x2,y2,x3,y3=t[1],t[2],t[3],t[4],t[5],t[6]
 if rnd()<0.5 then x2,y2,x3,y3=x3,y3,x2,y2 end -- random winding
 cls(0)
 if prim=="tri" then tri(x1,y1,x2,y2,x3,y3,1)
 else ttri(x1,y1,x2,y2,x3,y3,1,1,6,1,1,6,0,-1) end
 local xa=math.max(0,math.floor(math.min(x1,x2,x3))-1)
 local xb=math.min(239,math.ceil(math.max(x1,x2,x3))+1)
 local ya=math.max(0,math.floor(math.min(y1,y2,y3))-1)
 local yb=math.min(135,math.ceil(math.max(y1,y2,y3))+1)
 for y=ya,yb do for x=xa,xb do
  if pix(x,y)~=0 then local k=y*240+x cov[k]=(cov[k] or 0)+1 end
 end end
end

local function check(prim,tris,inside)
 cov={}
 for i=1,#tris do draw(prim,tris[i]) end
 local gaps,over,n=0,0,0
 for y=0,135 do for x=0,239 do
  local c=cov[y*240+x] or 0
  if c>1 then over=over+1 end
  if inside(x+0.5,y+0.5) then n=n+1 if c==0 then gaps=gaps+1 end end
 end end
 return n,gaps,over
end

local function grid()
 -- outer rectangle with fractional borders; border vertices only slide along the border
 local X0,X1,Y0,Y1=8.3+rnd()*3,130.7+rnd()*3,6.6+rnd()*3,70.2+rnd()*3
 local NX,NY=9,5
 local V={}
 for j=0,NY do for i=0,NX do
  local x=X0+(X1-X0)*i/NX local y=Y0+(Y1-Y0)*j/NY
  if i>0 and i<NX then x=coord(x+(rnd()-0.5)*5) end
  if j>0 and j<NY then y=coord(y+(rnd()-0.5)*5) end
  V[j*(NX+1)+i]={x,y}
 end end
 local T={}
 for j=0,NY-1 do for i=0,NX-1 do
  local a=V[j*(NX+1)+i] local b=V[j*(NX+1)+i+1]
  local c=V[(j+1)*(NX+1)+i] local d=V[(j+1)*(NX+1)+i+1]
  if (i+j)%2==0 then
   T[#T+1]={a[1],a[2],b[1],b[2],d[1],d[2]} T[#T+1]={a[1],a[2],d[1],d[2],c[1],c[2]}
  else
   T[#T+1]={a[1],a[2],b[1],b[2],c[1],c[2]} T[#T+1]={b[1],b[2],d[1],d[2],c[1],c[2]}
  end
 end end
 local m=0.02
 return T,function(x,y) return x>X0+m and x<X1-m and y>Y0+m and y<Y1-m end
end

local function fan()
 local cx,cy=coord(185+rnd()*10),coord(95+rnd()*10)
 local N,R=24,30+rnd()*8
 local P={}
 for k=0,N-1 do
  local a=k/N*2*math.pi+rnd()*0.05
  P[k]={coord(cx+R*math.cos(a)),coord(cy+R*math.sin(a))}
 end
 local T={}
 for k=0,N-1 do local p,q=P[k],P[(k+1)%N] T[#T+1]={cx,cy,p[1],p[2],q[1],q[2]} end
 -- inside = strictly inside the polygon P (convex, counter-clockwise in screen space)
 return T,function(x,y)
  for k=0,N-1 do
   local p,q=P[k],P[(k+1)%N]
   if (q[1]-p[1])*(y-p[2])-(q[2]-p[2])*(x-p[1]) <= 0.02*R then return false end
  end
  return true
 end
end

function TIC()
 seed=frame*7919+17
 local GT,gin=grid()
 local FT,fin=fan()
 for _,prim in ipairs({"tri","ttri"}) do
  local n1,g1,o1=check(prim,GT,gin)
  local n2,g2,o2=check(prim,FT,fin)
  trace(string.format("WT frame=%d prim=%s pixels=%d gaps=%d overlaps=%d",frame,prim,n1+n2,g1+g2,o1+o2))
 end
 frame=frame+1
end
"""


def chunk(ctype, data):
    return struct.pack("<BHB", ctype, len(data) & 0xFFFF, 0) + data


if __name__ == "__main__":
    # tile 0 entirely color 1 (the ttri texture)
    tiles = bytes([0x11] * 32)
    data = chunk(1, tiles) + chunk(5, CODE.encode())
    open(sys.argv[1], "wb").write(data)
    print(f"{sys.argv[1]}: {len(data)} bytes")
