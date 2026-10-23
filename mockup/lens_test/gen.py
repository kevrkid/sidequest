import os
# Moving fake camera: a hand-held phone filming the world image. Writes world.png, cam.mjpeg and truth.json
import json, math, sys, io
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw
D=os.path.dirname(os.path.abspath(__file__)); O=os.path.join(D,'out'); os.makedirs(O,exist_ok=True)
N=int(sys.argv[1]) if len(sys.argv)>1 else 360; SPEED=float(sys.argv[2]) if len(sys.argv)>2 else 1.0
OUT=sys.argv[3] if len(sys.argv)>3 else 'cam'
PAR=float(sys.argv[4]) if len(sys.argv)>4 else 1.0   # signs on a nearer layer move PAR times as much as the wall
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':2000,'height':2800})
    pg.goto('file://'+D+'/world.html'); pg.wait_for_timeout(300); pg.screenshot(path=O+'/world.png')
    pg.evaluate("document.querySelectorAll('div[id]').forEach(e=>e.style.visibility='hidden')"); pg.screenshot(path=O+'/bg.png')
    pg.evaluate("document.querySelectorAll('div[id]').forEach(e=>e.style.visibility='visible'); document.body.style.background='transparent'; document.querySelector('svg').style.display='none'")
    pg.screenshot(path=O+'/fg.png', omit_background=True)
    # each sign's text: centre, size and turn, in world px
    signs=pg.evaluate("""[...document.querySelectorAll('[id]')].filter(e=>e.querySelector('.t')).map(e=>{ const t=e.querySelector('.t');
      const m=getComputedStyle(e).transform, r=m==='none'?0:Math.atan2(+m.split(',')[1],+m.split('(')[1].split(',')[0]);
      const box=e.getBoundingClientRect(); return {id:e.id, cx:box.left+box.width/2, cy:box.top+box.height/2, w:t.offsetWidth, h:t.offsetHeight, rot:r}; })""")
    lines=pg.evaluate("""[...document.querySelectorAll('.ln')].map(e=>{ const r=e.getBoundingClientRect(), t=e.closest('[id]'), m=getComputedStyle(t).transform;
      return {text:e.textContent, sign:t.id, cx:r.left+r.width/2, cy:r.top+r.height/2, x0:r.left, y0:r.top, x1:r.right, y1:r.bottom, rot:m==='none'?0:Math.atan2(+m.split(',')[1],+m.split('(')[1].split(',')[0])}; })""")
    b.close()
W,H=720,1280; world=Image.open(O+'/world.png').convert('RGB'); bg=Image.open(O+'/bg.png').convert('RGB'); fg=Image.open(O+'/fg.png').convert('RGBA')
def cam(i):
    t=i/N; env=0 if t<.2 else math.sin(math.pi*(t-.2)/.8)**2
    cx=1000+env*120*math.sin(2*math.pi*2*t*SPEED)+1.2*math.sin(2*math.pi*7*t)+.8*math.sin(2*math.pi*11*t+1)
    cy=1400+env*80*math.sin(2*math.pi*1.5*t*SPEED+.6)+1.0*math.sin(2*math.pi*9*t+2)
    z=.62*(1+.18*env*math.sin(2*math.pi*1.5*t))      # frame px per world px
    rot=.07*env*math.sin(2*math.pi*t)
    return cx,cy,z,rot
truth=[]; f=open(O+'/'+OUT+'.mjpeg','wb')
for i in range(N):
    cx,cy,z,rot=cam(i); c,s=math.cos(rot),math.sin(rot)
    # output (u,v) → world: w = C + R(-rot)·((u,v)-centre)/z
    a,bb=c/z, s/z; dd,e=-s/z, c/z
    aff=lambda X,Y:(a,bb,X-a*W/2-bb*H/2, dd,e,Y-dd*W/2-e*H/2)
    if PAR==1: im=world.transform((W,H),Image.AFFINE,aff(cx,cy),resample=Image.BICUBIC)
    else:
        fx,fy=1000+(cx-1000)*PAR, 1400+(cy-1400)*PAR   # the nearer layer slides further
        im=bg.transform((W,H),Image.AFFINE,aff(cx,cy),resample=Image.BICUBIC)
        lay=fg.transform((W,H),Image.AFFINE,aff(fx,fy),resample=Image.BICUBIC); im.paste(lay,(0,0),lay); cx,cy=fx,fy
    dr=ImageDraw.Draw(im)   # frame number as 12 squares along the bottom
    for k in range(12): dr.rectangle([8+k*14,H-20,8+k*14+11,H-9], fill=(255,255,255) if (i>>k)&1 else (0,0,0))
    buf=io.BytesIO(); im.save(buf,'JPEG',quality=88); f.write(buf.getvalue()); truth.append([cx,cy,z,rot])
f.close()
json.dump({'W':W,'H':H,'signs':signs,'lines':lines,'frames':truth},open(O+'/'+OUT+'.json','w'))
print(signs); print('frames',N)
