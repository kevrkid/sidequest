import os
# Moving camera, real lens.js: are the translations on top of the words while the phone moves?
import json, math, sys, time, statistics as S
from playwright.sync_api import sync_playwright
D=os.path.dirname(os.path.abspath(__file__)); OUT=os.path.join(D,"out"); BASE=os.environ.get("SQ_BASE","http://localhost:8798")
name=sys.argv[1] if len(sys.argv)>1 else 'cam'; secs=int(sys.argv[2]) if len(sys.argv)>2 else 40
truth=json.load(open(f"{OUT}/{name}.json"))
MEASURE = r"""
(T)=>new Promise(done=>{
  const v=document.querySelector('.lz video'), st=window.__lens._st, c=document.createElement('canvas'), x=c.getContext('2d',{willReadFrequently:true});
  const out=[], t0=performance.now(), N=T.frames.length, norm=s=>s.toLowerCase().replace(/[^a-z0-9$.]+/g,' ').trim();
  function cb(now, md){
    if(performance.now()-t0>T.ms) return done(out);
    v.requestVideoFrameCallback(cb);
    const vw=v.videoWidth, vh=v.videoHeight; if(c.width!==vw){ c.width=vw; c.height=vh; }
    x.drawImage(v,0,0); const k=vw/T.W; let i=0;
    for(let b=0;b<12;b++){ const p=x.getImageData(Math.round((8+b*14+5)*k),Math.round((T.H-15)*k),1,1).data; if(p[0]>128) i|=1<<b; }
    if(i>=N) return;
    const check=(tries)=>{ if(st.mt!==md.mediaTime){ if(tries<20) setTimeout(()=>check(tries+1),2); return; }   // boxes are placed for this very frame
      const R=document.querySelector('.lz').getBoundingClientRect(), sc=Math.max(R.width/vw,R.height/vh), ox=(R.width-vw*sc)/2, oy=(R.height-vh*sc)/2;
      const [cx,cy,z,rot]=T.frames[i], scr=(X,Y)=>{ const dx=(X-cx)*z, dy=(Y-cy)*z; return [(Math.cos(rot)*dx-Math.sin(rot)*dy+T.W/2)*k*sc+ox, (Math.sin(rot)*dx+Math.cos(rot)*dy+T.H/2)*k*sc+oy]; };
      const row={i, t:i/N, lines:T.lines.map(l=>{ const [ex,ey]=scr(l.cx,l.cy); return {ex,ey,on:ex>0&&ey>0&&ex<R.width&&ey<R.height,covered:false}; }), boxes:[]};
      for(const b of document.querySelectorAll('.lz-box.on:not(.wait)')){
        const t=norm(b.textContent), ids=T.lines.map((l,j)=>t.includes(norm(l.text))?j:-1).filter(j=>j>=0); if(!ids.length) continue;
        let X0=1e9,Y0=1e9,X1=-1e9,Y1=-1e9; for(const j of ids){ const l=T.lines[j]; X0=Math.min(X0,l.x0); Y0=Math.min(Y0,l.y0); X1=Math.max(X1,l.x1); Y1=Math.max(Y1,l.y1); row.lines[j].covered=true; }
        const [ex,ey]=scr((X0+X1)/2,(Y0+Y1)/2), r=b.getBoundingClientRect(), m=new DOMMatrix(getComputedStyle(b).transform);
        const l0=T.lines[ids[0]], ew=(ids.length>1?X1-X0:Math.hypot(l0.x1-l0.x0,0)*(l0.rot?Math.cos(l0.rot):1))*z*k*sc;
        row.boxes.push({text:b.textContent, sign:l0.sign, n:ids.length, err:Math.hypot(r.left+r.width/2-ex, r.top+r.height/2-ey), size:b.offsetWidth*Math.hypot(m.a,m.b)/ew,
          angErr:Math.abs(Math.atan2(m.b,m.a)-(l0.rot+rot))*180/Math.PI});
      }
      out.push(row); };
    setTimeout(()=>check(0),0);
  }
  v.requestVideoFrameCallback(cb);
})
"""
with sync_playwright() as p:
    A=["--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream",f"--use-file-for-fake-video-capture={OUT}/{name}.mjpeg"]
    b=p.chromium.launch(channel="chromium", args=["--enable-gpu","--use-angle=metal","--ignore-gpu-blocklist"]+A) if "gpu" in sys.argv else p.chromium.launch(args=A)
    pg=b.new_page(viewport={"width":390,"height":844}); errs=[]
    pg.on("pageerror",lambda e:errs.append(str(e))); pg.on("console",lambda m: m.type in("error","warning") and not m.text.startswith("Estimating") and errs.append(m.text))
    # test only: take the fake camera's frames as they are (a phone held upright gives upright frames)
    pg.add_init_script("{const g=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices); navigator.mediaDevices.getUserMedia=c=>g({audio:false,video:true});}")
    pg.goto(BASE+"/lens", wait_until="load")
    pg.evaluate("window.__lens=Lens.open({from:'en',to:'es',translate:async l=>{ await new Promise(r=>setTimeout(r,600)); return l.map(x=>x.split('\\n').map(y=>'ES: '+y).join('\\n')); }})")
    t=time.time()
    while time.time()-t<90 and not pg.evaluate("document.querySelectorAll('.lz-box.on:not(.wait)').length"): pg.wait_for_timeout(300)
    print("first translation on screen after", round(time.time()-t,1),"s")
    rows=pg.evaluate(MEASURE, {**truth, "ms":secs*1000})
    pg.screenshot(path=f"{OUT}/{name}-end.png")
    st=pg.evaluate("(()=>{const s=__lens._st; return {reads:s.reads, epoch:s.epoch, frameMs:+s.ms.toFixed(1), videoFrame:s.vfOk!==false}})()")
    print("state", st, "| samples", len(rows), "| distinct frames", len({r['i'] for r in rows}))
    for phase,f in (("still",lambda r:r['t']<.2),("moving",lambda r:r['t']>=.2)):
        R=[r for r in rows if f(r)]
        if not R: continue
        cov=[]
        for j,l in enumerate(truth['lines']):
            on=[r for r in R if r['lines'][j]['on']]; cov.append(f"{l['text'][:12]} {sum(r['lines'][j]['covered'] for r in on)}/{len(on)}")
        print(f"[{phase}] lines covered:", "; ".join(cov))
        for sign in ("menu","street","door"):
            B=[b for r in R for b in r['boxes'] if b['sign']==sign]
            if not B: print(f"   {sign:6}: no boxes"); continue
            e=sorted(b['err'] for b in B)
            print(f"   {sign:6}: centre error px median {S.median(e):.1f} p90 {e[int(len(e)*.9)]:.1f} max {e[-1]:.1f} | size ratio {S.median(b['size'] for b in B):.2f} | angle err {S.median(b['angErr'] for b in B):.1f}°")
    json.dump(rows,open(f"{OUT}/{name}-rows.json","w"))
    print("errors", errs[:5]); b.close()
