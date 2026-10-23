import os
# Unit test of the camera tracker: a textured scene moved by known amounts; the tracker must recover each move
import sys
from playwright.sync_api import sync_playwright
JS = r"""
(cases)=>{
  const W=200,H=356, src=document.createElement('canvas'); src.width=900; src.height=1200; const s=src.getContext('2d');
  let seed=7; const rnd=()=>(seed=(seed*16807)%2147483647)/2147483647;
  s.fillStyle='#6b5a44'; s.fillRect(0,0,900,1200);
  for(let i=0;i<400;i++){ s.fillStyle=`hsl(${rnd()*360},${20+rnd()*40}%,${20+rnd()*60}%)`; s.fillRect(rnd()*900,rnd()*1200,4+rnd()*30,4+rnd()*30); }
  s.fillStyle='#f4ecd8'; s.fillRect(150,400,600,300); s.fillStyle='#222'; s.font='bold 44px Georgia';
  ['TACOS AL PASTOR $3.50','FRESH LEMONADE','Open late Friday'].forEach((t,i)=>s.fillText(t,180,470+i*80));
  const frame=(cx,cy,z,rot)=>{ const c=document.createElement('canvas'); c.width=W; c.height=H; const x=c.getContext('2d');
    x.setTransform(1,0,0,1,0,0); x.translate(W/2,H/2); x.rotate(rot); x.scale(z,z); x.translate(-cx,-cy); x.drawImage(src,0,0);
    const d=x.getImageData(0,0,W,H).data, g=new Float32Array(W*H); for(let i=0;i<W*H;i++) g[i]=d[i*4]*.299+d[i*4+1]*.587+d[i*4+2]*.114; return g; };
  const {track,newTracker}=Lens._track, out=[];
  for(const [a,b] of cases){
    const T=newTracker(); track(T,frame(...a),W,H); const t0=performance.now(); const r=track(T,frame(...b),W,H); const ms=performance.now()-t0;
    // truth: frame = z·R·(world - c) + center → motion from frame A to frame B
    const sa=a[2], sb=b[2], s=sb/sa, th=b[3]-a[3];
    // map a test point from A to B by the truth and by the estimate
    const toW=(p,f)=>{ const [x,y]=[p[0]-W/2,p[1]-H/2], c=Math.cos(-f[3]), n=Math.sin(-f[3]); return [(c*x-n*y)/f[2]+f[0], (n*x+c*y)/f[2]+f[1]]; };
    const toF=(w,f)=>{ const [x,y]=[(w[0]-f[0])*f[2],(w[1]-f[1])*f[2]], c=Math.cos(f[3]), n=Math.sin(f[3]); return [c*x-n*y+W/2, n*x+c*y+H/2]; };
    let err=0; const pts=[[30,30],[170,40],[100,178],[40,320],[170,330]];
    if(r.m) for(const p of pts){ const t=toF(toW(p,a),b), e=Lens._track.app(r.m,p[0],p[1]); err=Math.max(err,Math.hypot(t[0]-e[0],t[1]-e[1])); }
    out.push({ok:!!r.m, inl:r.m&&r.m.inl, n:r.m&&r.m.n, maxErrPx:+err.toFixed(2), ms:+ms.toFixed(1), scale:r.m&&+Math.hypot(r.m.a,r.m.b).toFixed(4), want:+s.toFixed(4)});
  }
  // timing: a 90-frame smooth pan/zoom/turn, after warm-up
  const T=newTracker(); let worst=0, tot=0, fails=0;
  for(let i=0;i<90;i++){ const f=frame(450+60*Math.sin(i/14),550+40*Math.sin(i/9),0.6*(1+.08*Math.sin(i/20)),.05*Math.sin(i/17));
    const t0=performance.now(); const r=track(T,f,W,H); const ms=performance.now()-t0; if(i>10){ tot+=ms; worst=Math.max(worst,ms); } if(i>0&&!r.m) fails++; }
  out.push({seq:'90 frames', avgMs:+(tot/79).toFixed(2), worstMs:+worst.toFixed(1), fails});
  return out;
}
"""
cases = [
  [[450,550,0.6,0],[450,550,0.6,0]],          # still
  [[450,550,0.6,0],[456,547,0.6,0]],          # small pan
  [[450,550,0.6,0],[475,535,0.6,0]],          # big pan (15 px in the small frame)
  [[450,550,0.6,0],[450,550,0.63,0]],         # zoom 5%
  [[450,550,0.6,0],[452,551,0.6,0.04]],       # turn 2.3°
  [[450,550,0.6,0],[462,544,0.62,-0.03]],     # all at once
]
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(); errs=[]; pg.on("pageerror",lambda e:errs.append(str(e)))
    pg.set_content("<html><body></body></html>"); pg.add_script_tag(path=sys.argv[1])
    res=pg.evaluate(JS, cases)
    for c,r in zip(cases+[[0,'sequence']], res): print(c[1], r)
    print("errors", errs); b.close()
