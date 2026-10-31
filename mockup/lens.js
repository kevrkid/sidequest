/* Live Translate: point the phone's camera at text (signs, menus, labels) and read it in another language, drawn
   right over the words and pinned to them as the camera moves. Self-contained so any web app can use it: Side Quest
   opens it from Scout, and lens.html runs it on its own page.
     Lens.open({to:'es', from:'auto', translate, detect, onClose, standalone, mode, identify, onPlace, onSight, lang})
   - Two modes, switched above the shutter: Translate, and Identify ("what is this?"): the shutter takes one photo and
     identify(jpegDataUrl, {lat, lng, heading, lang}) says what's in it (default: POST /api/lens/identify, identify.rb).
     onPlace(place, 'menu'|'info') and onSight(sight) let the app open what it found; without them it shows links.
   - The text is read on the device by tesseract.js (vendor/tesseract/, next to this file); each language's reading
     data (2-15 MB) downloads the first time it's used and stays cached in the browser.
   - Reading takes about a second, so between reads the camera's motion is tracked every frame (corners followed
     with Lucas-Kanade, one move/zoom/turn fitted with RANSAC) and the translations move with the picture.
   - translate(texts, from, to) → Promise<string[]> does the translating (a text can be several lines: each line's
     translation comes back on its own line); by default it POSTs
     {lines, from, to} to /api/translate (lens.rb). Only the text goes there, never the picture.
   - from:'auto' (Detect, the default) finds the language itself: detect(jpegDataUrl) → Promise<code|''|'other'> looks at
     one small picture (default: POST /api/lens/lang, lens.rb) and the reader switches to that language's data.
   - 🖼 translates a photo from the phone instead of the camera (only the text read from it leaves the phone). */
(function(){
'use strict';
const BASE = (()=>{ try{ return new URL('.', document.currentScript?.src || location.href).href; }catch(e){ return '/'; } })();
// code, name in that language, English name, tesseract's reading data, speech voice
const LANGS = [
  ['en','English','English','eng','en-US'], ['es','Español','Spanish','spa','es-US'], ['fr','Français','French','fra','fr-FR'],
  ['de','Deutsch','German','deu','de-DE'], ['it','Italiano','Italian','ita','it-IT'], ['pt','Português','Portuguese','por','pt-BR'],
  ['zh','中文','Chinese','chi_sim','zh-CN'], ['ja','日本語','Japanese','jpn','ja-JP'], ['ko','한국어','Korean','kor','ko-KR'],
  ['ar','العربية','Arabic','ara','ar-SA'], ['hi','हिन्दी','Hindi','hin','hi-IN'], ['ru','Русский','Russian','rus','ru-RU'],
  ['vi','Tiếng Việt','Vietnamese','vie','vi-VN']];
const L = Object.fromEntries(LANGS.map(l=>[l[0],l]));
const RTL = new Set(['ar']);
const LATIN = new Set(['en','es','fr','de','it','pt','vi']);   // the English reader gets these roughly right while the language is found
const CSS = `
.lz{position:fixed;inset:0;z-index:3000;background:#000;color:#fff;font:15px/1.35 system-ui,-apple-system,"Segoe UI",sans-serif;overflow:hidden;
  touch-action:manipulation;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}
.lz button{font:inherit;color:#fff;cursor:pointer}
.lz [hidden]{display:none!important}
.lz video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.lz-still{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;background:#000}
.lz.photo video{visibility:hidden}
.lz-layer{position:absolute;inset:0;pointer-events:none;overflow:hidden}
.lz-box{position:absolute;left:0;top:0;transform-origin:0 0;box-sizing:border-box;display:flex;align-items:center;padding:0 .2em;border-radius:.16em;
  white-space:pre-line;overflow:hidden;line-height:1.12;font-weight:650;letter-spacing:-.01em;pointer-events:auto;opacity:0;
  transition:opacity .3s,background-color .5s,color .5s}
.lz-box.on{opacity:1}
.lz-box.wait{background:linear-gradient(100deg,rgba(255,255,255,.06) 30%,rgba(255,255,255,.34) 50%,rgba(255,255,255,.06) 70%) 0 0/250% 100%;
  box-shadow:0 0 0 1.5px rgba(255,255,255,.7);animation:lz-sh 1.2s linear infinite;color:transparent}
.lz-box.orig{box-shadow:0 0 0 2px #ffd54a}
.lz-glass{background:rgba(26,28,34,.55);-webkit-backdrop-filter:blur(16px) saturate(1.4);backdrop-filter:blur(16px) saturate(1.4);border:1px solid rgba(255,255,255,.14)}
.lz-top{position:absolute;top:0;left:0;right:0;display:flex;align-items:center;gap:10px;padding:max(12px,env(safe-area-inset-top)) 14px 26px;
  background:linear-gradient(rgba(0,0,0,.5),rgba(0,0,0,0));pointer-events:none}
.lz-top>*{pointer-events:auto}   /* the fade under the bar lets taps through to the translations */
.lz .lz-ib{width:44px;height:44px;border-radius:50%;display:grid;place-items:center;font-size:18px;flex:none;padding:0}
.lz-langs{flex:1;min-width:0;display:flex;align-items:center;height:44px;border-radius:22px;padding:0 4px;box-sizing:border-box}
.lz-langs label{flex:1;min-width:0;position:relative}
.lz-langs select{width:100%;height:40px;border:0;background:transparent;color:#fff;font:600 15px system-ui,-apple-system,sans-serif;text-align:center;
  text-align-last:center;appearance:none;-webkit-appearance:none;padding:0 20px 0 10px;text-overflow:ellipsis;outline:none}
.lz-langs label::after{content:'';position:absolute;right:9px;top:50%;width:6px;height:6px;border:solid rgba(255,255,255,.7);border-width:0 2px 2px 0;
  transform:translateY(-75%) rotate(45deg);pointer-events:none}
.lz-langs select option{color:#000}
.lz .lz-sw{width:34px;height:34px;border-radius:50%;border:0;background:rgba(255,255,255,.14);font-size:16px;flex:none;padding:0;transition:transform .35s}
.lz .lz-sw.spin{transform:rotate(180deg)}
.lz-stat{position:absolute;left:50%;top:calc(max(12px,env(safe-area-inset-top)) + 58px);transform:translateX(-50%);display:flex;align-items:center;gap:8px;
  max-width:calc(100% - 32px);box-sizing:border-box;padding:7px 14px;border-radius:999px;font-size:13.5px;font-weight:600;white-space:nowrap;transition:opacity .3s;
  pointer-events:none}   /* only says things: taps go through to the translation under it */
.lz-stat span:last-child{overflow:hidden;text-overflow:ellipsis}
.lz-stat.off{opacity:0}
.lz-dot{width:8px;height:8px;border-radius:50%;background:#34d399;flex:none;animation:lz-pulse 1.8s ease-out infinite}
.lz-dot.err{background:#ff5a5f;animation:none}
.lz-spin{width:12px;height:12px;border-radius:50%;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;animation:lz-rot .8s linear infinite;flex:none}
.lz-aim{position:absolute;left:50%;top:47%;width:74%;max-width:360px;aspect-ratio:4/3;transform:translate(-50%,-50%);pointer-events:none;transition:opacity .35s}
.lz-aim.off{opacity:0}
.lz-aim i{position:absolute;width:30px;height:30px;border:0 solid #fff;filter:drop-shadow(0 1px 3px rgba(0,0,0,.5))}
.lz-aim i:nth-child(1){left:0;top:0;border-width:3px 0 0 3px;border-top-left-radius:14px}
.lz-aim i:nth-child(2){right:0;top:0;border-width:3px 3px 0 0;border-top-right-radius:14px}
.lz-aim i:nth-child(3){left:0;bottom:0;border-width:0 0 3px 3px;border-bottom-left-radius:14px}
.lz-aim i:nth-child(4){right:0;bottom:0;border-width:0 3px 3px 0;border-bottom-right-radius:14px}
.lz-aim b{position:absolute;left:6%;right:6%;height:2px;top:10%;border-radius:2px;background:linear-gradient(90deg,transparent,#2ec5ff,transparent);
  box-shadow:0 0 14px 2px rgba(46,197,255,.7);animation:lz-scan 2.4s ease-in-out infinite}
.lz-bot{position:absolute;left:0;right:0;bottom:0;display:flex;align-items:center;justify-content:space-between;
  padding:30px 26px max(18px,env(safe-area-inset-bottom));background:linear-gradient(rgba(0,0,0,0),rgba(0,0,0,.55));pointer-events:none}
.lz-bot>*{pointer-events:auto}
.lz .lz-side{width:64px;display:flex;flex-direction:column;align-items:center;gap:5px;background:none;border:0;font-size:12px;font-weight:600;padding:0;
  text-shadow:0 1px 3px rgba(0,0,0,.6)}
.lz-side span{width:48px;height:48px;border-radius:50%;display:grid;place-items:center;font-size:18px;font-weight:700;transition:background .2s,color .2s}
.lz-side.on span{background:#fff;color:#111}
.lz .lz-shut{width:78px;height:78px;border-radius:50%;border:4px solid #fff;background:rgba(255,255,255,.2);display:grid;place-items:center;padding:0;
  box-shadow:0 4px 18px rgba(0,0,0,.35);transition:transform .12s,background .2s}
.lz .lz-shut:active{transform:scale(.92)}
.lz-shut i{width:22px;height:24px;background:linear-gradient(90deg,#fff 0 34%,transparent 34% 66%,#fff 66%)}
.lz-shut.frozen{background:#fff}
.lz-shut.frozen i{width:24px;background:#111;clip-path:polygon(18% 0,100% 50%,18% 100%);margin-left:5px}
.lz .lz-zoom{position:absolute;left:50%;bottom:calc(max(18px,env(safe-area-inset-bottom)) + 100px);transform:translateX(-50%);min-width:44px;height:32px;
  border-radius:16px;font-size:13px;font-weight:700;padding:0 10px}
.lz-sheet{position:absolute;left:0;right:0;bottom:0;max-height:64%;overflow:auto;background:rgba(18,20,26,.94);-webkit-backdrop-filter:blur(20px);
  backdrop-filter:blur(20px);border-radius:22px 22px 0 0;padding:6px 16px max(20px,env(safe-area-inset-bottom));z-index:3;animation:lz-up .25s ease-out;
  -webkit-user-select:text;user-select:text;box-sizing:border-box}
.lz-grab{width:40px;height:5px;border-radius:3px;background:rgba(255,255,255,.25);margin:4px auto 8px}
.lz-head{margin:0 0 4px;font-size:17px;font-weight:700;display:flex;justify-content:space-between;align-items:center}
.lz-head small{display:block;font-size:12.5px;color:#9aa0aa;font-weight:500}
.lz-card{background:rgba(255,255,255,.07);border-radius:14px;padding:12px 12px 12px 14px;margin-top:10px;display:flex;gap:8px;align-items:flex-start}
.lz-card div{flex:1;min-width:0}
.lz-card .t{font-size:17px;font-weight:600;white-space:pre-line;overflow-wrap:anywhere}
.lz-card small{display:block;color:#9aa0aa;font-size:13px;white-space:pre-line;margin-bottom:6px;overflow-wrap:anywhere}
.lz .lz-mini{width:38px;height:38px;border-radius:50%;border:0;background:rgba(255,255,255,.1);flex:none;padding:0;font-size:16px}
.lz-empty{color:#9aa0aa;text-align:center;padding:24px 0}
.notr .lz-modes{display:none!important}
.lz-modes{position:absolute;left:50%;bottom:calc(max(18px,env(safe-area-inset-bottom)) + 98px);transform:translateX(-50%);display:flex;padding:3px;border-radius:999px}
.lz .lz-modes button{border:0;background:none;border-radius:999px;padding:7px 14px;font-size:13.5px;font-weight:700;color:rgba(255,255,255,.8);white-space:nowrap}
.lz .lz-modes button.on{background:#fff;color:#111}
.lz.look .lz-langs,.lz.look .lz-layer,.lz.look .lz-bot .lz-side,.lz.look [data-a="photo"]{visibility:hidden}
.lz-title{flex:1;text-align:center;font-weight:700;font-size:16px;display:none}
.lz.look .lz-title{display:block}
.lz.look .lz-langs{display:none}
.lz.look .lz-shut i{width:58px;height:58px;border-radius:50%;background:#fff}
.lz.look .lz-shut.frozen i{width:22px;height:22px;border-radius:0;background:#111;clip-path:polygon(50% 0,100% 40%,82% 100%,18% 100%,0 40%);margin:0}
.lz-look p{margin:6px 0 0;font-size:15.5px;line-height:1.45;color:#e8eaef}
.lz-look ul{margin:10px 0 0;padding-left:20px;color:#d5d8df;font-size:14.5px;line-height:1.45}
.lz-look li{margin-top:4px}
.lz-pl{background:rgba(255,255,255,.07);border-radius:14px;padding:12px 14px;margin-top:12px}
.lz-pl b{font-size:16px} .lz-pl small{display:block;color:#9aa0aa;font-size:13px;margin-top:2px}
.lz-acts{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.lz .lz-acts a,.lz .lz-acts button{display:inline-flex;align-items:center;gap:6px;min-height:40px;padding:0 14px;border-radius:999px;border:0;
  background:rgba(255,255,255,.12);color:#fff;font:600 14px system-ui,-apple-system,sans-serif;text-decoration:none}
.lz .lz-acts .pri{background:#2ec5ff;color:#04121c}
@keyframes lz-sh{from{background-position:100% 0}to{background-position:-150% 0}}
@keyframes lz-rot{to{transform:rotate(360deg)}}
@keyframes lz-pulse{0%{box-shadow:0 0 0 0 rgba(52,211,153,.6)}100%{box-shadow:0 0 0 8px rgba(52,211,153,0)}}
@keyframes lz-scan{0%,100%{top:10%}50%{top:88%}}
@keyframes lz-up{from{transform:translateY(40px);opacity:0}}
@media (prefers-reduced-motion:reduce){.lz-aim b,.lz-box.wait,.lz-dot{animation:none}}
`;
let ui=null;   // one translator open at a time

const pick = (o, k, d) => { try{ return JSON.parse(localStorage.getItem('lens')||'{}')[k] ?? o[k] ?? d; }catch(e){ return o[k] ?? d; } };
const remember = st => { try{ localStorage.setItem('lens', JSON.stringify({from:st.from, to:st.to})); }catch(e){} };
const esc = s => String(s).replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const norm = s => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu,' ').trim();
// OCR reads the same sign a little differently frame to frame: compare text by shared letter pairs (0..1)
function sim(a, b){
  if(a===b) return 1; if(!a||!b) return 0;
  const pairs = s => { const m=new Map(); for(let i=0;i<s.length-1;i++){ const p=s.substr(i,2); m.set(p,(m.get(p)||0)+1); } return m; };
  const A=pairs(a), B=pairs(b); let n=0, tot=0;
  A.forEach((c,p)=>{ n+=Math.min(c,B.get(p)||0); tot+=c; }); B.forEach(c=>tot+=c);
  return tot ? 2*n/tot : 0;
}
// the numbers in a line (prices, times, dish numbers): two readings that differ there are different lines
const nums = n => (n.match(/\d+/g)||[]).join(' ');
const same = (a, b, t) => sim(a,b)>=t && nums(a)===nums(b);
function loadTesseract(){
  if(window.Tesseract) return Promise.resolve();
  return loadTesseract.p ||= new Promise((ok,no)=>{ const s=document.createElement('script'); s.src=BASE+'vendor/tesseract/tesseract.min.js';
    s.onload=ok; s.onerror=()=>{ loadTesseract.p=null; no(new Error("Couldn't load the text reader.")); }; document.head.appendChild(s); });
}
async function defaultIdentify(img, ctx){
  const r=await fetch('/api/lens/identify', {method:'POST', credentials:'same-origin', headers:{'Content-Type':'application/json'},
    body:JSON.stringify({img, lat:ctx.lat, lng:ctx.lng, heading:ctx.heading, lang:ctx.lang})});
  const j=await r.json().catch(()=>({}));
  if(r.status===401) throw new Error('Sign in to Side Quest to use Identify.');
  if(!r.ok||j.error) throw new Error(j.error||"Couldn't tell what that is. Try again.");
  return j;
}
async function defaultDetect(img){
  const r=await fetch('/api/lens/lang', {method:'POST', credentials:'same-origin', headers:{'Content-Type':'application/json'}, body:JSON.stringify({img})});
  const j=await r.json().catch(()=>({}));
  if(r.status===401) throw Object.assign(new Error('Sign in to translate.'),{auth:true});
  if(!r.ok||j.error) throw new Error(j.error||"Couldn't tell the language.");
  return j.lang||'';
}
async function defaultTranslate(lines, from, to){
  const r = await fetch('/api/translate',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:JSON.stringify({lines,from,to})});
  const j = await r.json().catch(()=>({error:`Server error (${r.status})`}));
  if(r.status===401) throw Object.assign(new Error('Sign in to translate.'),{auth:true});
  if(j.error) throw new Error(j.error);
  return j.translations;
}

/* ---- Following the camera ----
   A pose maps a point on the world (the scene as first seen) to where it is in the current frame:
   frame = [a -b; b a]·world + t, i.e. a move, a zoom and a turn. */
const comp = (m,p) => ({a:m.a*p.a-m.b*p.b, b:m.a*p.b+m.b*p.a, tx:m.a*p.tx-m.b*p.ty+m.tx, ty:m.b*p.tx+m.a*p.ty+m.ty});
const inv = p => { const d=p.a*p.a+p.b*p.b, a=p.a/d, b=-p.b/d; return {a, b, tx:-(a*p.tx-b*p.ty), ty:-(b*p.tx+a*p.ty)}; };
const app = (p,x,y) => [p.a*x-p.b*y+p.tx, p.b*x+p.a*y+p.ty];
const PLAN = [[960,0],[1280,.14],[1440,0],[1280,-.14]];   // live reads: long side in px, turn in radians
const R = 4, WIN = (2*R+1)**2, LEVELS = 3, MAXPTS = 72;   // 9×9 windows, 3 pyramid levels
const tI=new Float32Array(WIN), tX=new Float32Array(WIN), tY=new Float32Array(WIN), tJ=new Float32Array(WIN);
function toGray(d, n, g=new Float32Array(n)){ for(let i=0,j=0;i<n;i++,j+=4) g[i]=d[j]*.299+d[j+1]*.587+d[j+2]*.114; return g; }
function blur(g, w, h, t, o){   // 1-2-1 both ways: takes the edge off camera noise
  for(let y=0;y<h;y++){ const r=y*w; t[r]=g[r]; t[r+w-1]=g[r+w-1]; for(let x=1;x<w-1;x++) t[r+x]=(g[r+x-1]+2*g[r+x]+g[r+x+1])*.25; }
  for(let x=0;x<w;x++){ o[x]=t[x]; o[(h-1)*w+x]=t[(h-1)*w+x]; }
  for(let y=1;y<h-1;y++){ const r=y*w; for(let x=0;x<w;x++) o[r+x]=(t[r+x-w]+2*t[r+x]+t[r+x+w])*.25; }
  return o;
}
function level(g, w, h, gx, gy){
  for(let y=1;y<h-1;y++) for(let x=1,i=y*w+1;x<w-1;x++,i++){ gx[i]=(g[i+1]-g[i-1])*.5; gy[i]=(g[i+w]-g[i-w])*.5; }
  return {g, gx, gy, w, h};
}
// Buffers are kept between frames (two sets of pyramids, this frame's and the last), so following the camera makes no garbage
const buf = (T, k, n, A=Float32Array) => { const b=T.bufs[k]; return b&&b.length===n ? b : (T.bufs[k]=new A(n)); };
function pyramid(T, gray, w, h, set){
  const n=w*h, P=[level(blur(gray,w,h,buf(T,'t',n),buf(T,set+'g0',n)),w,h,buf(T,set+'x0',n),buf(T,set+'y0',n))];
  for(let l=1;l<LEVELS;l++){ const p=P[l-1], W=p.w>>1, H=p.h>>1, o=buf(T,set+'g'+l,W*H);
    for(let y=0;y<H;y++) for(let x=0;x<W;x++){ const i=2*y*p.w+2*x; o[y*W+x]=(p.g[i]+p.g[i+1]+p.g[i+p.w]+p.g[i+p.w+1])*.25; }
    P.push(level(o,W,H,buf(T,set+'x'+l,W*H),buf(T,set+'y'+l,W*H))); }
  return P;
}
function bil(a, w, x, y){ const x0=x|0, y0=y|0, fx=x-x0, fy=y-y0, i=y0*w+x0;
  return (a[i]+(a[i+1]-a[i])*fx)*(1-fy)+(a[i+w]+(a[i+w+1]-a[i+w])*fx)*fy; }
// Good points to follow: the strongest corner in each cell of a grid (Shi-Tomasi), so they spread over the picture
function corners(T, p, want){
  const {w,h,gx,gy}=p, W=w+1, n=W*(h+1), ixx=buf(T,'ixx',n,Float64Array), iyy=buf(T,'iyy',n,Float64Array), ixy=buf(T,'ixy',n,Float64Array);
  for(let y=0;y<h;y++){ let a=0,b=0,c=0; for(let x=0;x<w;x++){ const i=y*w+x, X=gx[i], Y=gy[i]; a+=X*X; b+=Y*Y; c+=X*Y;
    const k=(y+1)*W+x+1; ixx[k]=ixx[k-W]+a; iyy[k]=iyy[k-W]+b; ixy[k]=ixy[k-W]+c; } }
  const r=3, box=(I,x,y)=>I[(y+r+1)*W+x+r+1]-I[(y-r)*W+x+r+1]-I[(y+r+1)*W+x-r]+I[(y-r)*W+x-r];
  const m=10, cols=Math.max(3,Math.round(Math.sqrt(want*w/h))), rows=Math.max(3,Math.round(want/cols)), out=[]; let top=0;
  for(let cy=0;cy<rows;cy++) for(let cx=0;cx<cols;cx++){
    const x0=Math.max(m,cx*w/cols|0), x1=Math.min(w-m,(cx+1)*w/cols|0), y0=Math.max(m,cy*h/rows|0), y1=Math.min(h-m,(cy+1)*h/rows|0);
    let best=0, bx=0, by=0;
    for(let y=y0;y<y1;y+=2) for(let x=x0;x<x1;x+=2){ const a=box(ixx,x,y), c=box(iyy,x,y), b=box(ixy,x,y);
      const l=(a+c)/2-Math.sqrt((a-c)*(a-c)/4+b*b); if(l>best){ best=l; bx=x; by=y; } }
    if(best>0){ out.push([bx,by,best]); if(best>top) top=best; }
  }
  return out.filter(c=>c[2]>Math.max(top*.03,400)).map(c=>[c[0],c[1]]);
}
// Pyramidal Lucas-Kanade: where did (x,y) of P go in Q? (ux,uy) is a guess. Returns [dx,dy,error] or null.
function lk(P, Q, x, y, ux, uy){
  const top=P.length-1; let dx=ux/2**top, dy=uy/2**top, err=0;
  for(let l=top;l>=0;l--){
    const p=P[l], q=Q[l], w=p.w, s=2**l, px=x/s, py=y/s;
    if(px<R+1||py<R+1||px>w-R-2||py>p.h-R-2) return null;
    let a=0, b=0, c=0, mi=0, k=0;
    for(let j=-R;j<=R;j++) for(let i=-R;i<=R;i++,k++){ const X=bil(p.gx,w,px+i,py+j), Y=bil(p.gy,w,px+i,py+j), I=bil(p.g,w,px+i,py+j);
      tX[k]=X; tY[k]=Y; tI[k]=I; mi+=I; a+=X*X; b+=X*Y; c+=Y*Y; }
    mi/=WIN;
    const det=a*c-b*b, lmin=(a+c)/2-Math.sqrt((a-c)*(a-c)/4+b*b);
    if(lmin<WIN*.5||det<=0) return null;   // flat or a plain edge: can't tell where it went
    for(let it=0;it<10;it++){
      const qx=px+dx, qy=py+dy; if(qx<R+1||qy<R+1||qx>w-R-2||qy>q.h-R-2) return null;
      let mj=0; k=0;
      for(let j=-R;j<=R;j++) for(let i=-R;i<=R;i++,k++){ const J=bil(q.g,w,qx+i,qy+j); tJ[k]=J; mj+=J; }
      mj/=WIN; let ex=0, ey=0; err=0;
      for(k=0;k<WIN;k++){ const e=(tI[k]-mi)-(tJ[k]-mj); ex+=e*tX[k]; ey+=e*tY[k]; err+=Math.abs(e); }   // means removed: brightness changes don't throw it
      const sx=(c*ex-b*ey)/det, sy=(a*ey-b*ex)/det; dx+=sx; dy+=sy;
      if(sx*sx+sy*sy<1e-3) break;
    }
    if(l){ dx*=2; dy*=2; }
  }
  return [dx, dy, err/WIN];
}
// One move/zoom/turn that most of the points agree on (RANSAC on pairs, then least squares on the agreeing ones)
function fitSim(src, dst, thr){
  const n=src.length; if(n<5) return null;
  let seed=n*7919+13; const rnd=()=>(seed=(seed*1103515245+12345)&0x7fffffff)/0x7fffffff;
  const agree=m=>{ const k=[]; for(let i=0;i<n;i++){ const [x,y]=app(m,src[i][0],src[i][1]); if(Math.hypot(x-dst[i][0],y-dst[i][1])<thr) k.push(i); } return k; };
  const ls=k=>{ let sx=0,sy=0,ux=0,uy=0; for(const i of k){ sx+=src[i][0]; sy+=src[i][1]; ux+=dst[i][0]; uy+=dst[i][1]; }
    sx/=k.length; sy/=k.length; ux/=k.length; uy/=k.length; let p=0,q=0,d=0;
    for(const i of k){ const x=src[i][0]-sx, y=src[i][1]-sy, u=dst[i][0]-ux, v=dst[i][1]-uy; p+=x*u+y*v; q+=x*v-y*u; d+=x*x+y*y; }
    const a=p/d, b=q/d; return {a, b, tx:ux-(a*sx-b*sy), ty:uy-(b*sx+a*sy)}; };
  let best=null;
  for(let t=0;t<80;t++){ const i=rnd()*n|0, j=rnd()*n|0; if(i===j) continue;
    const sx=src[j][0]-src[i][0], sy=src[j][1]-src[i][1], ux=dst[j][0]-dst[i][0], uy=dst[j][1]-dst[i][1], d=sx*sx+sy*sy; if(d<100) continue;
    const a=(sx*ux+sy*uy)/d, b=(sx*uy-sy*ux)/d, s=Math.hypot(a,b); if(s<.8||s>1.25) continue;
    const k=agree({a, b, tx:dst[i][0]-(a*src[i][0]-b*src[i][1]), ty:dst[i][1]-(b*src[i][0]+a*src[i][1])});
    if(!best||k.length>best.length) best=k; }
  if(!best||best.length<5) return null;
  let m=ls(best); for(let r=0;r<2;r++){ const k=agree(m); if(k.length<5) return null; m=ls(k); best=k; }
  const s=Math.hypot(m.a,m.b); if(s<.8||s>1.25) return null;
  return Object.assign(m, {inl:best.length, n});
}
// The whole picture's shift at the coarsest level, searched around a guess: catches fast pans too big for LK on its own
function shift(p, q, gx, gy){
  const {w,h}=p, S=6, ox0=Math.round(gx), oy0=Math.round(gy), m=Math.max(Math.abs(ox0),Math.abs(oy0))+S+1; let best=1e18, bx=ox0, by=oy0;
  if(w-2*m<8||h-2*m<8) return [gx,gy];
  for(let dy=-S;dy<=S;dy++) for(let dx=-S;dx<=S;dx++){ const ox=ox0+dx, oy=oy0+dy; let e=0;
    for(let y=m;y<h-m;y+=2) for(let x=m,i=y*w+x,j=(y+oy)*w+x+ox;x<w-m;x+=2,i+=2,j+=2){ const d=p.g[i]-q.g[j]; e+=d<0?-d:d; }
    if(e<best){ best=e; bx=ox; by=oy; } }
  return [bx,by];
}
function newTracker(){ return {P:null, pts:[], v:null, bufs:{}, set:'a', age:0}; }
// Feed one grayscale frame. → {m} the motion since the last frame, {lost:true} when it couldn't be followed, or {} with nothing to follow.
function track(T, gray, w, h){
  T.set=T.set==='a'?'b':'a'; const Q=pyramid(T,gray,w,h,T.set); let out={}, keep=null;
  if(T.P&&T.P[0].w===w&&T.P[0].h===h&&T.pts.length>=6){
    const src=[], dst=[], v=T.v, top=Q.length-1, s=2**top;
    // guess: it keeps moving the way it was, corrected by where the whole picture went
    const [cx,cy]=v?app(v,w/2,h/2):[w/2,h/2], pdx=cx-w/2, pdy=cy-h/2, [sx,sy]=shift(T.P[top],Q[top],pdx/s,pdy/s), kx=sx*s-pdx, ky=sy*s-pdy;
    for(const [x,y] of T.pts){
      const [gx,gy]=v?app(v,x,y):[x,y], r=lk(T.P,Q,x,y,gx-x+kx,gy-y+ky);
      if(r&&r[2]<20){ src.push([x,y]); dst.push([x+r[0],y+r[1]]); } }
    const m=fitSim(src,dst,1.25);
    out = m&&m.inl>=Math.max(6,T.pts.length*.3) ? {m} : {lost:true};
    // keep following the points that agreed, and look for fresh ones when they thin out
    if(out.m){ const e=12; keep=dst.filter((d,i)=>{ const [x,y]=app(m,src[i][0],src[i][1]); return Math.hypot(x-d[0],y-d[1])<1.25&&d[0]>e&&d[1]>e&&d[0]<w-e&&d[1]<h-e; }); }
  }
  T.v=out.m||null; T.P=Q;
  T.pts = keep&&keep.length>=T.n0*.7&&++T.age<20 ? keep : (T.age=0, corners(T,Q[0],MAXPTS));
  if(!T.age) T.n0=T.pts.length;
  return out;
}

function open(opts={}){
  if(ui) return ui.api;
  if(!document.getElementById('lz-css')){ const s=document.createElement('style'); s.id='lz-css'; s.textContent=CSS; document.head.appendChild(s); }
  const st = { from:pick(opts,'from','auto'), to:pick(opts,'to',/^es/.test(navigator.language)?'en':'es'), live:true, closed:false,
    det:null, detBusy:false, detTry:0, detAt:0, detGap:3000, textAt:0, photo:null, rn:false, camErr:'',
    stream:null, cam:null, torch:false, zoom:1, zoomMax:1, wp:null, wlang:null, w:null, loadPct:null, readerFail:0,
    items:[], id:0, reads:0, ms:0, cache:new Map(), inflight:false, again:false, noTry:0, ocr:false, lastOcr:0, gen:0,
    pose:{a:1,b:0,tx:0,ty:0}, T:newTracker(), vel:null, fails:0, epoch:0, speed:0, vw:0, vh:0, sc:0,
    showOrig:false, err:'', errUntil:0, fatal:'', mode:opts.mode==='look'?'look':'tr', look:null, heading:null };
  if(st.from!=='auto'&&!L[st.from]) st.from='auto'; if(!L[st.to]) st.to='es';
  const translate = opts.translate || defaultTranslate, detect = opts.detect || defaultDetect;
  const rlang = () => st.from==='auto' ? st.det||'en' : st.from;   // the language the reader reads
  const root=document.createElement('div'); root.className='lz'+(opts.noTranslate?' notr':''); root.setAttribute('role','dialog'); root.setAttribute('aria-label',opts.noTranslate?'Identify':'Live Translate');   // noTranslate: Identify only, no switch
  const opt = (sel, auto) => (auto?`<option value="auto"${sel==='auto'?' selected':''}>✨ Detect</option>`:'')+LANGS.map(l=>`<option value="${l[0]}"${l[0]===sel?' selected':''}>${esc(l[1])}</option>`).join('');
  root.innerHTML = `<video playsinline muted autoplay></video><canvas class="lz-still" hidden></canvas><div class="lz-layer"></div>
    <div class="lz-aim"><i></i><i></i><i></i><i></i><b></b></div>
    <div class="lz-top">${opts.standalone?'<span class="lz-ib" aria-hidden="true"></span>':'<button class="lz-ib lz-glass" data-a="close" aria-label="Close">✕</button>'}
      <div class="lz-title">What is this?</div>
      <div class="lz-langs lz-glass"><label><select data-k="from" aria-label="Translate from">${opt(st.from,true)}</select></label>
        <button class="lz-sw" data-a="swap" aria-label="Swap languages">⇄</button>
        <label><select data-k="to" aria-label="Translate to">${opt(st.to)}</select></label></div>
      <button class="lz-ib lz-glass" data-a="torch" aria-label="Flashlight" hidden>🔦</button>
      <button class="lz-ib lz-glass" data-a="photo" aria-label="Translate a photo">🖼</button><input type="file" accept="image/*" hidden></div>
    <div class="lz-stat lz-glass off" role="status"><span></span><span></span></div>
    <button class="lz-zoom lz-glass" data-a="zoom" hidden style="bottom:calc(max(18px,env(safe-area-inset-bottom)) + 146px)">1×</button>
    <div class="lz-modes lz-glass" role="tablist"><button data-mode="tr" role="tab">🌐 Translate</button><button data-mode="look" role="tab">🔍 Identify</button></div>
    <div class="lz-bot"><button class="lz-side" data-a="list" aria-label="All the text in view"><span class="lz-glass">☰</span>Text</button>
      <button class="lz-shut" data-a="freeze" aria-label="Freeze the picture"><i></i></button>
      <button class="lz-side" data-a="orig" aria-label="Show the original text" aria-pressed="false"><span class="lz-glass">Aa</span>Original</button></div>`;
  document.body.appendChild(root);
  const $=s=>root.querySelector(s), video=$('video'), layer=$('.lz-layer'), still=$('.lz-still');
  const dims = () => st.photo ? [st.photo.w, st.photo.h] : [video.videoWidth, video.videoHeight];   // the picture being read: the camera's or a photo's
  const small=document.createElement('canvas'), sctx=small.getContext('2d');   // on the GPU: the frame is shrunk there and only the small copy is read back
  const grab=document.createElement('canvas'), gctx=grab.getContext('2d');
  ui = {root, st};

  const flash = m => { st.err=m; st.errUntil=performance.now()+4000; render(); setTimeout(()=>{ if(!st.closed) render(); }, 4100); };
  // A reader is put away only after the read it's doing (ending one mid-read trips up tesseract.js)
  const retire = wp => { const job=st.job; wp?.then(w=>Promise.resolve(job).catch(()=>{}).finally(()=>w?.terminate())).catch(()=>{}); };
  // The text reader for the "from" language (one at a time; switching language starts a new one)
  function reader(){
    const lang=L[rlang()][3];
    if(st.wlang===lang&&st.wp) return st.wp;
    retire(st.wp); st.wlang=lang; st.w=null; st.loadPct=null;
    return st.wp = loadTesseract().then(()=>Tesseract.createWorker(lang, 1, { workerPath:BASE+'vendor/tesseract/worker.min.js', corePath:BASE+'vendor/tesseract/',
        logger:m=>{ if(st.wlang===lang&&/language/.test(m.status)&&m.progress!=null) st.loadPct=Math.round(m.progress*100); } }))
      .then(async w=>{ await w.setParameters({tessedit_pageseg_mode:'3'});   // find the text blocks itself (the default reads the whole frame as one block, walls and all)
        if(st.closed||st.wlang!==lang){ w.terminate(); return null; } st.w=w; render(); if(!st.live) readNow(); return w; })
      .catch(e=>{ if(st.wlang===lang){ st.wp=null; st.wlang=null; st.readerFail=performance.now(); flash(e.message||"Couldn't load the text reader."); } return null; });
  }
  async function camera(){
    try{ st.stream = await navigator.mediaDevices.getUserMedia({audio:false, video:{facingMode:{ideal:'environment'}, width:{ideal:1920}, height:{ideal:1080}}}); }
    catch(e){ st.fatal = /NotAllowed|Security/.test(e.name) ? 'Camera blocked. Allow the camera for this site in your browser or phone settings.'
                                                            : "Couldn't start the camera. Is another app using it?";
      st.camErr=st.fatal; render(); return false; }   // 🖼 still works: a photo needs no camera
    if(st.closed){ st.stream.getTracks().forEach(t=>t.stop()); return false; }
    video.srcObject=st.stream; await video.play().catch(()=>{});
    st.cam=st.stream.getVideoTracks()[0]; const caps=st.cam?.getCapabilities?.()||{};
    if(caps.torch) $('[data-a="torch"]').hidden=false;
    if(caps.zoom&&caps.zoom.max>=2){ st.zoomMax=Math.min(caps.zoom.max,4); $('[data-a="zoom"]').hidden=false; }
    return true;
  }

  // ---- every camera frame: follow the motion, maybe start a read, move the translations ----
  const next = () => { if(st.closed) return; video.requestVideoFrameCallback ? video.requestVideoFrameCallback(frame) : requestAnimationFrame(frame); };
  let busy=false;
  function frame(now, md){
    next();
    if(busy) return;   // still on the last frame: let this one go
    busy=true; const t0=performance.now();
    step(md).catch(e=>console.warn('lens', e)).finally(()=>{ busy=false; st.ms=st.ms*.95+(performance.now()-t0)*.05; });   // st.ms: what a frame costs, for tuning
  }
  async function step(md){
    const vw=video.videoWidth, vh=video.videoHeight;
    if(!vw||!st.live||video.paused||st.mode==='look') return render();
    if(vw!==st.vw||vh!==st.vh){ st.vw=vw; st.vh=vh; st.T=newTracker(); st.pose={a:1,b:0,tx:0,ty:0}; clear(); }
    // the tracker works on a ~180 px wide grayscale copy of the frame
    const f=Math.max(1,Math.round(Math.min(vw,vh)/180)), tw=Math.floor(vw/f), th=Math.floor(vh/f), gray=buf(st.T,'gray',tw*th);
    let vf=null;
    if(st.vfOk!==false&&window.VideoFrame){ try{ vf=new VideoFrame(video); }catch(e){} }
    if(vf&&!(await fromFrame(vf,gray,tw,th,f,vw,vh).catch(()=>false))){ st.vfOk=false; vf.close(); vf=null; }
    if(!vf){
      if(small.width!==tw||small.height!==th){ small.width=tw; small.height=th; }
      sctx.drawImage(video,0,0,tw,th); toGray(sctx.getImageData(0,0,tw,th).data, tw*th, gray);
    }
    if(st.closed||!st.live){ vf?.close(); return; }
    const r=track(st.T, gray, tw, th);
    st.mt=md?.mediaTime;   // which camera frame the boxes are placed for
    if(r.m){
      const m={a:r.m.a, b:r.m.b, tx:r.m.tx*f, ty:r.m.ty*f};
      st.pose=comp(m,st.pose); st.vel=m; st.fails=0;
      const [cx,cy]=app(m,vw/2,vh/2), mv=Math.hypot(cx-vw/2,cy-vh/2)/Math.max(vw,vh)*100+Math.abs(Math.hypot(m.a,m.b)-1)*60+Math.abs(Math.atan2(m.b,m.a))*60;
      st.speed=st.speed*.6+mv*.4;   // % of the picture per frame
    }else if(r.lost){
      st.speed=Math.max(st.speed,3);
      if(++st.fails<=3&&st.vel) st.pose=comp(st.vel,st.pose);   // a blurred frame or two: keep gliding the way it was going
      else if(st.fails===4){ st.epoch++; st.items.forEach(it=>{ it.stale=true; }); }   // lost it: hide until the next read finds them again
    }else st.speed*=.6;
    if(!st.w&&!st.wp&&performance.now()-st.readerFail>5000) reader();
    if(st.from==='auto'&&st.speed<1&&wantDetect()) findLang(vf||video);
    if(st.w&&!st.ocr&&!document.hidden&&st.speed<1&&performance.now()-st.lastOcr>150) read(false, vf||video);   // reads this same frame
    vf?.close();
    render();
  }
  // The frame's own pixels without a canvas (WebCodecs): the brightness plane is the grayscale the tracker wants.
  // Only for frames laid out exactly like the picture on screen; anything else goes the canvas way.
  async function fromFrame(vf, g, tw, th, f, vw, vh){
    const fmt=vf.format||'', rect=vf.visibleRect;
    if(!rect||rect.width!==vw||rect.height!==vh||vf.rotation||vf.flip) return false;
    const yuv=/^(I4|NV12)/.test(fmt), bgr=/^BGR/.test(fmt); if(!yuv&&!/^(RGB|BGR)/.test(fmt)) return false;
    const b=buf(st.T,'vf',vf.allocationSize({rect}),Uint8Array), lay=await vf.copyTo(b,{rect}), o=lay[0].offset, s=lay[0].stride, h=f>>1, d=f>1?1:0;
    for(let y=0;y<th;y++){ const r0=o+(y*f+h-d)*s, r1=r0+d*s;   // the 2×2 pixels in the middle of each f×f block
      if(yuv) for(let x=0,c=h-d;x<tw;x++,c+=f) g[y*tw+x]=(b[r0+c]+b[r0+c+d]+b[r1+c]+b[r1+c+d])*.25;
      else for(let x=0,c=(h-d)*4;x<tw;x++,c+=f*4){ const R=bgr?2:0, B=bgr?0:2;
        g[y*tw+x]=(b[r0+c+R]+b[r1+c+R])*.1495+(b[r0+c+1]+b[r1+c+1])*.2935+(b[r0+c+B]+b[r1+c+B])*.057; } }
    return true;
  }

  // One read: grab the frame (with the pose at this exact moment), read it, and fold what it found into the translations
  async function read(full, src=st.photo?still:video){
    const w=st.w; if(!w||st.ocr) return; st.ocr=true;
    const pose={...st.pose}, epoch=st.epoch, gen=st.gen;
    try{
      // Live reads take turns: a quick small look (big text reads best there), a sharper one for small print, and two
      // turned ±8° (the reader misses lines tilted more than ~5°, which a hand-held phone often is)
      const [vw,vh]=dims(); if(!vw) return;   // no picture yet (the camera didn't start)
      const [len,phi]=full?[st.photo?2200:1600,0]:PLAN[st.reads++%PLAN.length];   // a photo: often a whole menu in small print
      const k=Math.min(1,len/Math.max(vw,vh)), cw=grab.width=Math.round(vw*k), ch=grab.height=Math.round(vh*k);
      if(phi){ gctx.fillStyle='#808080'; gctx.fillRect(0,0,cw,ch); gctx.setTransform(Math.cos(phi),Math.sin(phi),-Math.sin(phi),Math.cos(phi),cw/2,ch/2);
        gctx.drawImage(src,-cw/2,-ch/2,cw,ch); gctx.setTransform(1,0,0,1,0,0); }
      else gctx.drawImage(src,0,0,cw,ch);
      if(full) render();
      // a JPEG is much quicker to make and to unpack than the PNG tesseract.js would make from a canvas
      const jpg = await new Promise(ok=>grab.toBlob(ok,'image/jpeg',.92));
      if(st.closed||w!==st.w) return;   // put away meanwhile (closed, or another language)
      const {data} = await (st.job = w.recognize(jpg||grab, {}, {blocks:true, text:false}));
      if(st.closed||gen!==st.gen||epoch!==st.epoch||w!==st.w) return;
      const c=Math.cos(phi), sn=Math.sin(phi);   // back from the read's picture to the camera frame
      merge(lines(data).map(p=>{ const dx=p.x-cw/2, dy=p.y-ch/2;
        return {...p, x:(c*dx+sn*dy)/k+vw/2, y:(-sn*dx+c*dy)/k+vh/2, w:p.w/k, h:p.h/k, th:p.th-phi}; })
        .filter(p=>!phi||Math.abs(p.th+phi)<.07&&Math.abs(p.th)>.05), pose, full, k, phi);
      if(st.items.some(it=>!it.stale)) st.textAt=performance.now();   // a turned read only speaks for text tilted its way
    }catch(e){ if(!st.closed) flash(e.message||'Something went wrong reading the text.'); }
    finally{ st.ocr=false; st.lastOcr=performance.now(); if(!st.closed) render(); }
  }
  // one careful read of the still picture, as soon as the reader is free (asked for twice, it still reads once)
  function readNow(){ if(st.rn) return; st.rn=true;
    (function go(){ if(st.closed||st.live) return st.rn=false; if(st.ocr||!st.w||st.detBusy) return setTimeout(go,80); st.rn=false; read(true); })(); }
  // Every line the reader found, in the read's own pixels. Lines are what's tracked (the reader finds the same lines
  // read after read, but groups them into paragraphs differently); `para` says which lines it read as one paragraph.
  function lines(data){
    const out=[], pal=palette(); let para=0;
    for(const b of data.blocks||[]) for(const p of b.paragraphs||[]){
      para++;
      // each line from its confident words only, so stray marks on a busy wall don't stretch the box
      const ls=(p.lines||[]).map(l=>{ const ws=(l.words?.length?l.words:[l]).filter(w=>w.confidence>=45&&/[\p{L}\p{N}]/u.test(w.text));
          return {ws, text:ws.map(w=>w.text.trim()).join(' '), baseline:l.baseline, conf:l.confidence}; })
        .filter(l=>l.conf>=50&&(l.text.match(/\p{L}/gu)||[]).length>=2&&norm(l.text).length>=2);
      if(!ls.length) continue;
      // the tilt, one for the paragraph: for a line of several words, the line through the word centres (truer than
      // the baseline on short tilted signs)
      const angs=ls.map(l=>{
        if(l.ws.length>=2){ let sw=0,sx=0,sy=0,sxx=0,sxy=0; for(const w of l.ws){ const m=w.bbox.x1-w.bbox.x0, cx=(w.bbox.x0+w.bbox.x1)/2, cy=(w.bbox.y0+w.bbox.y1)/2;
            sw+=m; sx+=m*cx; sy+=m*cy; sxx+=m*cx*cx; sxy+=m*cx*cy; }
          const v=sxx-sx*sx/sw; if(v>0) return Math.atan((sxy-sx*sy/sw)/v); }
        return l.baseline&&Math.atan2(l.baseline.y1-l.baseline.y0,l.baseline.x1-l.baseline.x0); }).filter(a=>a!=null&&isFinite(a)).sort((a,b)=>a-b);
      const tilt=angs.length?angs[angs.length>>1]:0;
      for(const l of ls){
        let x0=1e9, y0=1e9, x1=-1e9, y1=-1e9;
        for(const w of l.ws){ x0=Math.min(x0,w.bbox.x0); y0=Math.min(y0,w.bbox.y0); x1=Math.max(x1,w.bbox.x1); y1=Math.max(y1,w.bbox.y1); }
        // tilted: turn the box to match, and work out its real size from the upright box around it
        let th=tilt, W=x1-x0, H=y1-y0;
        if(Math.abs(th)>.035&&Math.abs(th)<.45){ const c=Math.cos(th), s=Math.abs(Math.sin(th)), d=c*c-s*s, w2=(W*c-H*s)/d, h2=(H*c-W*s)/d;
          if(w2>0&&h2>H*.15){ W=w2; H=h2; } else th=0; } else th=0;
        const pad=H*.16, m=H*.3;   // covers the letters' edges; colours from a little around the words too
        out.push({text:l.text, n:norm(l.text), para, conf:l.conf, lines:1, x:(x0+x1)/2, y:(y0+y1)/2, w:W+2*pad+H*.3, h:H+2*pad, th, col:colors(pal,x0-m,y0-m,x1+m,y1+m)});
      }
    }
    return out.slice(0,st.live?40:90);
  }
  // The sign's own colors, so the translation looks printed on it: split the pixels in the box into light and dark,
  // the bigger group is the background and the other is the ink
  // (sampled from one small copy of the frame: a single read back from the GPU per read)
  const pal=document.createElement('canvas'), pctx=pal.getContext('2d',{willReadFrequently:true});
  function palette(){
    const q=Math.min(1,480/Math.max(grab.width,grab.height)); pal.width=Math.max(1,Math.round(grab.width*q)); pal.height=Math.max(1,Math.round(grab.height*q));
    pctx.drawImage(grab,0,0,pal.width,pal.height); return {d:pctx.getImageData(0,0,pal.width,pal.height).data, w:pal.width, h:pal.height, q};
  }
  function colors(P, x0, y0, x1, y1){
    const {d,q}=P; x0=Math.max(0,Math.floor(x0*q)); y0=Math.max(0,Math.floor(y0*q)); x1=Math.min(P.w,Math.ceil(x1*q)); y1=Math.min(P.h,Math.ceil(y1*q));
    const w=x1-x0, h=y1-y0; if(w<2||h<2) return null;
    const hist=new Float64Array(64), lum=[], idx=[];
    for(let y=y0;y<y1;y++) for(let x=x0;x<x1;x++){ const i=(y*P.w+x)*4, l=d[i]*.299+d[i+1]*.587+d[i+2]*.114; hist[l>>2]++; lum.push(l); idx.push(i); }
    let tot=lum.length, sum=0; for(let i=0;i<64;i++) sum+=i*hist[i];
    let wB=0, sB=0, best=-1, t=32;
    for(let i=0;i<64;i++){ wB+=hist[i]; if(!wB) continue; const wF=tot-wB; if(!wF) break; sB+=i*hist[i];
      const v=wB*wF*(sB/wB-(sum-sB)/wF)**2; if(v>best){ best=v; t=i; } }
    // each side's middle colour (the soft edges of the letters would muddy an average)
    const c=[[[],[],[]],[[],[],[]]];
    lum.forEach((l,j)=>{ const g=c[(l>>2)>t?1:0], i=idx[j]; g[0].push(d[i]); g[1].push(d[i+1]); g[2].push(d[i+2]); });
    const mid=g=>g[0].length?g.map(a=>a.sort((x,y)=>x-y)[a.length>>1]):[128,128,128];
    const [bg,fg]=c[1][0].length>=c[0][0].length?[mid(c[1]),mid(c[0])]:[mid(c[0]),mid(c[1])];
    return {bg, fg};
  }
  const Y = c => c[0]*.299+c[1]*.587+c[2]*.114;
  function paint(col){   // → css colors, with enough contrast to read
    if(!col) return {bg:'rgb(246,246,246)', fg:'#111'};
    let {bg,fg}=col; const lb=Y(bg);
    if(Math.abs(lb-Y(fg))<110) fg=lb>140?[18,18,18]:[255,255,255];
    else fg=fg.map((v,i)=>v+(v-bg[i])*.25);   // a touch crisper than the camera saw it
    const rgb=c=>`rgb(${c.map(v=>Math.max(0,Math.min(255,Math.round(v)))).join(',')})`;
    return {bg:rgb(bg), fg:rgb(fg)};
  }

  // Fold a read into what's on screen: the same text near the same spot is the same sign (it glides there, doesn't jump)
  function merge(ps, pose, full, k, phi){
    const P=inv(pose), s=Math.hypot(pose.a,pose.b), turn=Math.atan2(pose.b,pose.a), now=performance.now(), [vw,vh]=dims();
    const found=ps.map(p=>{ const [x,y]=app(P,p.x,p.y); return {...p, x, y, w:p.w/s, h:p.h/s, th:p.th-turn}; });
    const used=new Set(), paras=new Map();
    for(const f of found){
      let best=null, bd=1e9;
      for(const it of st.items){ if(used.has(it)) continue;
        // the same line: near where it was (the tracker keeps that close, and the next line is a line-height away) and
        // reading about the same; after losing track, the same words anywhere
        const d=Math.hypot(it.x-f.x,it.y-f.y), t=sim(it.n,f.n);
        const ok = it.stale ? t>=.6 : d<Math.max(it.h,f.h)*.8+Math.min(it.w,f.w)*.15 && (t>=.5||overlap(it,f)>.6);
        if(ok&&d<bd){ bd=d; best=it; } }
      // a piece of a line already up (the reader caught only its end, say) is that line, not a second box on top;
      // a fuller reading of it takes over
      const part=!best&&st.items.find(x=>!used.has(x)&&!x.stale&&overlap(x,f)>.5);
      if(part){ if(f.w>part.w*1.15){ part.stale=true; update(part,f,now); } else { part.miss=0; part.seen=now; } used.add(part); continue; }
      let it=best;
      if(it) update(it,f,now);
      else { it={id:++st.id, ...f, hits:1, miss:0, seen:now, tr:null, src:null, want:false, solo:false, group:null, stale:false, el:null, dirty:true, look:paint(f.col)};
        const k=known(f.n); if(k!=null){ it.tr=k; it.src=f.n; } st.items.push(it); }
      used.add(it); if(!paras.has(f.para)) paras.set(f.para,[]); paras.get(f.para).push(it);
    }
    paras.forEach(g=>g.forEach(it=>{ it.group=g; }));   // read as one paragraph this time: translated together
    st.items=st.items.filter(it=>{
      if(used.has(it)) return true;
      if(it.stale) return drop(it);
      const [x,y]=app(pose,it.x,it.y), inView=x>0&&y>0&&x<vw&&y<vh;
      // should have been seen and wasn't: gone. Live, a sign the reader catches only now and then is kept a few seconds
      // (the tracker keeps it in place); a read that found nothing at all is a bad read, not an empty scene.
      const legible=it.h*s*k/it.lines>=14&&Math.abs(it.th+turn+phi)<.07, counts=ps.length>0||full;   // big enough and level enough in this read to be seen
      if(inView&&legible&&counts&&++it.miss>=(full?1:3)&&(full||now-it.seen>5000)) return drop(it);
      if(!inView&&now-it.seen>15000) return drop(it);       // off to the side: kept a while in case the camera comes back
      return true;
    });
    const most=st.live?30:90;   // a still picture can be a whole menu
    if(st.items.length>most) st.items.sort((a,b)=>b.seen-a.seen).splice(most).forEach(drop);
    fill(full);
  }
  const overlap=(a,b)=>{ const ix=Math.max(0,Math.min(a.x+a.w/2,b.x+b.w/2)-Math.max(a.x-a.w/2,b.x-b.w/2)), iy=Math.max(0,Math.min(a.y+a.h/2,b.y+b.h/2)-Math.max(a.y-a.h/2,b.y-b.h/2));
    return ix*iy/Math.min(a.w*a.h,b.w*b.h); };
  function update(it, f, now){
    const snap=it.stale||Math.hypot(it.x-f.x,it.y-f.y)>f.h*2, a=snap?1:.5;
    it.x+=(f.x-it.x)*a; it.y+=(f.y-it.y)*a; it.th+=(f.th-it.th)*a;
    if(snap||Math.abs(f.w/it.w-1)>.06||Math.abs(f.h/it.h-1)>.06){ it.w+=(f.w-it.w)*a; it.h+=(f.h-it.h)*a; it.dirty=true; }
    if(f.col){ it.col=it.col&&!snap?{bg:it.col.bg.map((v,i)=>v*.6+f.col.bg[i]*.4), fg:it.col.fg.map((v,i)=>v*.6+f.col.fg[i]*.4)}:f.col; it.look=paint(it.col); }
    if(it.text!==f.text) it.dirty=true;
    it.text=f.text; it.n=f.n; it.conf=f.conf; it.hits++; it.miss=0; it.stale=false; it.seen=now;
    if(it.tr!=null&&!same(it.src,f.n,.6)){ const k=known(f.n); if(k!=null){ it.tr=k; it.src=f.n; it.dirty=true; } else it.want=true; }   // the words really changed
  }
  function drop(it){ it.el?.remove(); it.el=null; return false; }
  function clear(){ st.items.forEach(drop); st.items=[]; }
  const key = n => st.from+'>'+st.to+':'+n;
  function known(n){
    const hit=st.cache.get(key(n)); if(hit!=null) return hit;
    const pre=st.from+'>'+st.to+':';
    for(const [kk,v] of st.cache) if(kk.startsWith(pre)&&same(kk.slice(pre.length),n,.8)) return v;   // a slightly different reading of a line we have
    return null;
  }
  function setTr(it, t){ it.tr=t; it.src=it.n; it.want=false; it.dirty=true; }
  // Translate what's new. While live, only text read twice (steady, not a blur) unless it read clearly; a frozen
  // picture goes right away. A line goes with the rest of its paragraph (the sentence may run on) and its own line of
  // the answer comes back to it; if the answer's lines don't match up, those lines go one at a time.
  async function fill(now){
    if(st.inflight){ st.again=true; return; }
    if(performance.now()<st.noTry) return;
    for(const it of st.items) if(it.tr==null||it.want){ const k=known(it.n); if(k!=null) setTr(it,k); }
    const need=st.items.filter(it=>(it.tr==null||it.want)&&(now||it.hits>=2||it.conf>=85));
    if(!need.length) return render();
    const jobs=new Map();
    for(const it of need){ const g=it.solo||!it.group ? [it] : it.group.filter(x=>st.items.includes(x));
      const t=g.map(x=>x.text).join('\n'); if(!jobs.has(t)&&jobs.size<30) jobs.set(t,g); }
    if(need.some(it=>![...jobs.values()].some(g=>g.includes(it)))) st.again=true;   // more than one request's worth: the rest go next
    const texts=[...jobs.keys()], from=st.from==='auto'?st.det||'auto':st.from, to=st.to, gen=st.gen, pre=st.from+'>'+to+':';
    st.inflight=true; render();
    try{
      const out=await translate(texts, from, to);
      if(gen===st.gen) texts.forEach((t,i)=>{
        const g=jobs.get(t), tr=String(out[i]||'').trim(), parts=g.length===1?[tr.replace(/\s*\n\s*/g,' ')]:tr.split('\n').map(x=>x.trim());
        if(parts.length!==g.length){ g.forEach(x=>{ x.solo=true; }); st.again=true; return; }
        g.forEach((x,j)=>{ st.cache.set(pre+x.n, parts[j]); if(x.tr==null||x.want) setTr(x, parts[j]); });   // a line that has one keeps it: no flicker
      });
      while(st.cache.size>600) st.cache.delete(st.cache.keys().next().value);
    }catch(e){ st.noTry=performance.now()+4000; flash(e.auth?'Sign in first, then open the translator again.':e.message||"Couldn't translate right now."); }
    finally{ st.inflight=false; }
    if(st.closed) return;
    if(st.again){ st.again=false; fill(!st.live); }
    render();
  }

  // ---- drawing: each translation is a box placed with one transform from the world, through the pose, to the screen ----
  function fit(it, mode){
    const el=it.el, ew=it.w*st.sc, eh=it.h*st.sc, txt=mode==='orig'?it.text:mode==='tr'?it.tr:'';
    el.className='lz-box'+(mode==='wait'?' wait':'')+(mode==='orig'?' orig':'');
    el.textContent=txt; el.dir=mode==='tr'&&RTL.has(st.to)?'rtl':'auto';
    el.style.background=mode==='wait'?'':it.look.bg; el.style.color=mode==='wait'?'':it.look.fg;
    el.style.boxShadow=mode==='tr'?`0 0 .3em .12em ${it.look.bg}`:'';   // soft edges blend into the sign
    el.style.width=ew+'px'; el.style.height='auto'; el.style.minHeight=eh+'px';
    if(txt){
      const s=Math.hypot(st.pose.a,st.pose.b)||1, min=10/s; let fs=Math.max(min,Math.min(eh/it.lines*.78,eh*.9));
      el.style.fontSize=fs+'px';
      const over=()=>el.scrollWidth>el.clientWidth+1||el.offsetHeight>eh*1.06;
      if(over()) el.style.width=ew*1.35+'px';   // a longer translation may run a bit past the original line before it shrinks
      for(let i=0;i<40&&fs>min&&over();i++){ fs=Math.max(min,fs*.93); el.style.fontSize=fs+'px'; }
    }
    it.eh=el.offsetHeight; it.ew=el.offsetWidth; el.dataset.w=Math.round(ew); it.mode=mode; it.dirty=false;   // data-w: the original line's width (tests)
  }
  // where the box's own corner sits: the original line's start stays put and a wider box runs on the way the text reads
  const el0 = it => it.el.dir==='rtl' ? it.ew-it.w*st.sc/2 : it.w*st.sc/2;
  function render(){
    if(st.closed) return;
    const W=root.clientWidth, H=root.clientHeight, [vw,vh]=dims();
    let any=false;
    if(vw){
      const sc=(st.photo?Math.min:Math.max)(W/vw,H/vh), ox=(W-vw*sc)/2, oy=(H-vh*sc)/2, P=st.pose;   // a photo is shown whole, the camera fills the screen
      if(sc!==st.sc){ st.sc=sc; st.items.forEach(it=>{ it.dirty=true; }); }
      for(const it of st.items){
        const mode = it.stale ? '' : it.orig||st.showOrig ? 'orig' : it.tr ? 'tr' : it.tr==null ? 'wait' : '';
        if(!it.el){ it.el=document.createElement('div'); it.el.dataset.id=it.id; layer.appendChild(it.el); it.dirty=true; }
        if(it.dirty||it.mode!==mode) fit(it, mode);
        const c=Math.cos(it.th), s=Math.sin(it.th), ma=P.a*c-P.b*s, mb=P.a*s+P.b*c, [px,py]=app(P,it.x,it.y);
        const hw=el0(it), hh=it.eh/2, e=px*sc+ox-(ma*hw-mb*hh), f=py*sc+oy-(mb*hw+ma*hh);
        it.el.style.transform=`matrix(${ma.toFixed(5)},${mb.toFixed(5)},${(-mb).toFixed(5)},${ma.toFixed(5)},${e.toFixed(1)},${f.toFixed(1)})`;
        const on=!!mode; it.el.classList.toggle('on',on);
        if(on&&mode!=='wait') any=true;
      }
    }
    $('.lz-aim').classList.toggle('off', st.mode==='look' ? !!st.look||!st.stream||!!st.fatal : any||!st.live||!st.stream||!!st.fatal);
    status(any);
    if(st.mode==='tr'&&root.querySelector('.lz-sheet')) list(true);   // Identify's sheet is its answer, not the text list
  }
  // One line at the top saying what's going on
  function status(any){
    const now=performance.now(); let t='', k='';
    if(st.fatal){ t=st.fatal; k='err'; }
    else if(st.err&&now<st.errUntil){ t=st.err; k='err'; }
    else if(!st.stream&&!st.photo) { t='Starting the camera…'; k='busy'; }
    else if(st.mode==='look') { [t,k] = st.looking?['Looking…','busy']:st.look?['','']:['Point at a place, sign or dish and tap ◯','']; }
    else if(st.from==='auto'&&!st.det&&st.detBusy&&!any) { t='Finding the language…'; k='busy'; }
    else if(!st.w) { t=`Getting ready to read ${L[rlang()][2]}…`+(st.loadPct!=null&&st.loadPct<100?` ${st.loadPct}%`:''); k='busy'; }
    else if(st.inflight) { t='Translating…'; k='busy'; }
    else if(!st.live&&any&&!st.ocr&&!st.detBusy&&!st.inflight) { t=hint('Tap a translation to see the original'); }
    else if(!st.live) { t=st.ocr||st.detBusy?'Reading…':any?'':st.photo?'No text found in this photo.':'No text found. Get closer and try again.'; k=st.ocr||st.detBusy?'busy':''; }
    else if(any) { t='Live'; k='live'; }
    else if(st.speed>=1) t='Hold steady…';
    else { t='Point at a sign, menu or label'; }
    const el=$('.lz-stat'), sig=t+'|'+k; if(el.dataset.sig===sig) return; el.dataset.sig=sig;
    el.firstChild.className = k==='busy'?'lz-spin':k==='live'?'lz-dot':k==='err'?'lz-dot err':'';
    el.firstChild.hidden = !k; el.lastChild.textContent=t; el.classList.toggle('off',!t);
  }
  // a tip shows for a few seconds, then gets out of the way (on a menu it would sit on a line)
  function hint(t){ const now=performance.now(); if(st.hint!==t){ st.hint=t; st.hintAt=now; setTimeout(()=>{ if(!st.closed) render(); },4100); }
    return now-st.hintAt<4000 ? t : ''; }
  function list(refresh){
    let sh=root.querySelector('.lz-sheet');
    if(!refresh&&sh){ sh.remove(); return; }
    const done=new Set(), rows=[];   // lines read as one paragraph are listed together
    for(const it of st.items.filter(it=>it.tr&&!it.stale).sort((a,b)=>a.y-b.y||a.x-b.x)){ if(done.has(it)) continue;
      const g=(it.group||[]).filter(x=>x.tr&&!x.stale&&!done.has(x)&&st.items.includes(x)); if(!g.includes(it)) g.push(it);
      g.sort((a,b)=>a.y-b.y).forEach(x=>done.add(x)); rows.push({text:g.map(x=>x.text).join('\n'), tr:g.map(x=>x.tr).join('\n')}); }
    const html=`<div class="lz-grab"></div><div class="lz-head"><span>Text in view<small>${esc(L[rlang()][1])} → ${esc(L[st.to][1])}</small></span>
      <button class="lz-mini" data-a="list" aria-label="Close the list">✕</button></div>` + (rows.length ? rows.map(it=>`<div class="lz-card">
      <div><small>${esc(it.text)}</small><div class="t" dir="${RTL.has(st.to)?'rtl':'auto'}">${esc(it.tr)}</div></div>
      <button class="lz-mini" data-say="${esc(it.tr)}" aria-label="Read aloud">🔊</button><button class="lz-mini" data-copy="${esc(it.tr)}" aria-label="Copy">⧉</button></div>`).join('')
      : '<div class="lz-empty">Nothing translated yet. Point the camera at some text.</div>');
    if(!sh){ sh=document.createElement('div'); sh.className='lz-sheet'; root.appendChild(sh); }
    if(sh.dataset.html!==html){ sh.dataset.html=html; sh.innerHTML=html; }
  }
  function freeze(on){
    if(!on&&st.photo) unphoto();
    st.live=!on; st.hint=null; const b=$('[data-a="freeze"]'); b.classList.toggle('frozen',on); b.setAttribute('aria-label',on?'Back to live':'Freeze the picture');
    if(on){ video.pause(); try{ navigator.vibrate?.(12); }catch(e){} readNow(); }   // the picture stops now; a closer read once the current one is done
    else { st.items.forEach(it=>{ if(it.orig){ it.orig=false; it.dirty=true; } }); video.play().catch(()=>{}); }
    render();
  }
  function setLang(k, v){
    if(k==='swap'){ const was=st.from==='auto'?st.det||(st.to==='en'?'es':'en'):st.from; st.from=st.to; st.to=was===st.from?(st.from==='en'?'es':'en'):was;
      $('.lz-sw').classList.toggle('spin'); }
    else st[k]=v;
    if(k!=='to'){ st.det=null; st.detTry=0; detName(); }
    $('[data-k="from"]').value=st.from; $('[data-k="to"]').value=st.to; remember(st); st.gen++;
    if(k!=='to'){ clear(); reader(); if(!st.live) st.from==='auto'?findLang().then(readNow):readNow(); }
    else { st.items.forEach(it=>{ it.tr=null; it.src=null; it.want=false; it.dirty=true; }); fill(true); }
    render();
  }
  // ---- Detect: which language the text is in, from one small picture ----
  // Asked when the camera is steady and nothing's known yet, and again when the reader hasn't seen text for a while
  // (the camera moved on to something in another language); a picture with no text waits a few seconds before the next try
  function wantDetect(){
    const now=performance.now();
    if(st.detBusy||now<st.detTry||document.hidden) return false;
    return !st.det || now-st.textAt>6000&&now-st.detAt>10000;
  }
  async function findLang(src=st.photo?still:video){
    if(st.detBusy) return; st.detBusy=true; const gen=st.gen; render();
    try{
      const [vw,vh]=dims(); if(!vw) return;
      const c=document.createElement('canvas'), k=Math.min(1,768/Math.max(vw,vh)); c.width=Math.round(vw*k); c.height=Math.round(vh*k);
      c.getContext('2d').drawImage(src,0,0,c.width,c.height);
      const got=await detect(c.toDataURL('image/jpeg',.8));
      if(st.closed||gen!==st.gen||st.from!=='auto') return;
      const now=performance.now(); st.detAt=now;
      // nothing new (no text, or the same language): ask less and less often, up to once a minute
      if(!L[got]||got===st.det){ st.detTry=now+st.detGap; st.detGap=Math.min(60000,st.detGap*2);
        if(got==='other'&&!st.det) flash("That language isn't one I can read yet."); return; }
      st.detTry=now+2000; st.detGap=3000;
      const was=rlang(); st.det=got; detName();
      if(LATIN.has(was)!==LATIN.has(got)||!st.textAt) clear();   // another alphabet: what the old reader made of it is noise
      st.textAt=now; reader();
    }catch(e){ st.detTry=performance.now()+30000; if(!st.closed&&!st.det) flash(e.auth?'Sign in first, then open the translator again.':e.message); }
    finally{ st.detBusy=false; if(!st.closed) render(); }
  }
  function detName(){ const o=$('[data-k="from"] option[value="auto"]'); if(o) o.textContent=st.det?'✨ '+L[st.det][1]:'✨ Detect'; }

  // ---- 🖼 a photo from the phone instead of the camera: shown whole, read once, carefully ----
  async function photo(file){
    if(!file) return;
    const url=URL.createObjectURL(file), img=new Image();
    try{ img.src=url; await img.decode(); }catch(e){ URL.revokeObjectURL(url); return flash("Couldn't open that photo."); }
    if(st.closed) return URL.revokeObjectURL(url);
    const k=Math.min(1,2400/Math.max(img.naturalWidth,img.naturalHeight));
    still.width=Math.max(1,Math.round(img.naturalWidth*k)); still.height=Math.max(1,Math.round(img.naturalHeight*k));
    still.getContext('2d').drawImage(img,0,0,still.width,still.height); URL.revokeObjectURL(url);   // the phone's own way up (EXIF)
    root.querySelector('.lz-sheet')?.remove();
    st.photo={w:still.width, h:still.height}; still.hidden=false; root.classList.add('photo'); st.fatal='';
    if(!st.w&&!st.wp) reader();
    st.gen++; st.epoch++; clear(); st.pose={a:1,b:0,tx:0,ty:0}; st.textAt=0; st.hint=null;
    st.live=false; video.pause(); const b=$('[data-a="freeze"]'); b.classList.add('frozen'); b.setAttribute('aria-label','Back to the camera');
    render();
    if(st.from==='auto') await findLang(still);   // a new picture may be in another language
    readNow();
  }
  function unphoto(){
    st.photo=null; still.hidden=true; root.classList.remove('photo'); st.gen++; st.epoch++; clear(); st.fatal=st.camErr;
    st.T=newTracker(); st.pose={a:1,b:0,tx:0,ty:0}; st.vw=0;
  }

  // ---- Identify: one photo → what it is ----
  function setMode(m){
    if(m===st.mode) return; st.mode=m; root.classList.toggle('look',m==='look');
    root.querySelectorAll('[data-mode]').forEach(b=>{ b.classList.toggle('on',b.dataset.mode===m); b.setAttribute('aria-selected',b.dataset.mode===m); });
    root.querySelector('.lz-sheet')?.remove(); st.look=null;
    if(st.photo) unphoto();
    if(!st.live){ st.live=true; video.play().catch(()=>{}); $('[data-a="freeze"]').classList.remove('frozen'); }
    $('[data-a="freeze"]').setAttribute('aria-label', m==='look'?'Identify what is in the picture':'Freeze the picture');
    if(m==='look') compass(); else { clear(); st.T=newTracker(); st.pose={a:1,b:0,tx:0,ty:0}; }
    render();
  }
  function compass(){   // which way the phone faces helps tell which building it is (iPhone asks first, inside a tap)
    if(st.compass) return; st.compass=true;
    const on=()=>addEventListener('deviceorientationabsolute' in window?'deviceorientationabsolute':'deviceorientation', st.onOri=e=>{
      const h=e.webkitCompassHeading!=null?e.webkitCompassHeading:e.absolute&&e.alpha!=null?(360-e.alpha)%360:null; if(h!=null) st.heading=h; });
    try{ const ask=window.DeviceOrientationEvent?.requestPermission; ask ? ask().then(r=>{ if(r==='granted') on(); }).catch(()=>{}) : on(); }catch(e){}
  }
  const where = () => opts.where ? Promise.resolve(opts.where()).catch(()=>null) : new Promise(ok=>{
    if(!navigator.geolocation) return ok(null);
    navigator.geolocation.getCurrentPosition(p=>ok({lat:p.coords.latitude, lng:p.coords.longitude}), ()=>ok(null), {maximumAge:60000, timeout:4000, enableHighAccuracy:true}); });
  async function identify(){
    if(st.looking) return;
    if(st.look||!st.live){ st.look=null; root.querySelector('.lz-sheet')?.remove(); st.live=true; video.play().catch(()=>{}); $('[data-a="freeze"]').classList.remove('frozen'); return render(); }
    const vw=video.videoWidth, vh=video.videoHeight; if(!vw) return;
    const k=Math.min(1,1024/Math.max(vw,vh)); grab.width=Math.round(vw*k); grab.height=Math.round(vh*k); gctx.drawImage(video,0,0,grab.width,grab.height);
    video.pause(); st.live=false; $('[data-a="freeze"]').classList.add('frozen'); try{ navigator.vibrate?.(12); }catch(e){}
    st.looking=true; render();
    try{
      const img=grab.toDataURL('image/jpeg',.85), pos=await where();
      const r=await (opts.identify||defaultIdentify)(img, {...(pos||{}), heading:st.heading, lang:opts.lang});
      if(st.closed||st.mode!=='look'||st.live) return;
      st.look=r; lookSheet(r);
    }catch(e){ if(!st.closed){ flash(e.message||"Couldn't tell what that is."); st.live=true; video.play().catch(()=>{}); $('[data-a="freeze"]').classList.remove('frozen'); } }
    finally{ st.looking=false; if(!st.closed) render(); }
  }
  const KINDS={business:'Business', landmark:'Landmark', building:'Building', art:'Art', nature:'Nature', food:'Food', product:'Product', sign:'Sign', other:''};
  const FOODY=/restaurant|fast food|food truck|truck park|food hall|bakery|ice cream|cafe|bar|pub|beer garden|club/;
  function lookSheet(r){
    const p=r.place, g=s=>'https://www.google.com/search?q='+encodeURIComponent(s), maps='https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(p?`${p.name} ${p.addr||''}`:r.search||r.name);
    const html=`<div class="lz-grab"></div><div class="lz-look"><div class="lz-head"><span>${esc(r.name||'Not sure')}<small>${esc([KINDS[r.kind]||'',r.confidence==='low'?'best guess':''].filter(Boolean).join(' · '))}</small></span>
        <button class="lz-mini" data-a="again" aria-label="Look at something else">✕</button></div>
      ${r.summary?`<p>${esc(r.summary)}</p>`:''}${(r.facts||[]).length?`<ul>${r.facts.map(f=>`<li>${esc(f)}</li>`).join('')}</ul>`:''}
      ${p?`<div class="lz-pl"><b>${esc(p.name)}</b><small>${esc([p.kind,p.status,p.addr].filter(Boolean).join(' · '))}</small>
        <div class="lz-acts">${FOODY.test(p.kind||'')?`<button class="pri" data-place="menu">🍽️ Menu & prices</button>`:''}
          <button data-place="info">🕒 Hours, phone & photos</button>${p.phone?`<a href="tel:${esc(p.phone.replace(/[^\d+]/g,''))}">📞 Call</a>`:''}
          ${p.web?`<a href="${esc(p.web)}" target="_blank" rel="noopener">🌐 Website</a>`:''}</div></div>`:''}
      <div class="lz-acts">${r.sight&&opts.onSight?'<button class="pri" data-place="sight">📖 The story</button>':r.sight?.url?`<a class="pri" href="${esc(r.sight.url)}" target="_blank" rel="noopener">📖 Read more</a>`:''}
        <a href="${esc(g(r.search||r.name))}" target="_blank" rel="noopener">🔎 Search the web</a><a href="${esc(maps)}" target="_blank" rel="noopener">🗺 Google Maps</a>
        <button data-a="again">📷 Another</button></div></div>`;
    let sh=root.querySelector('.lz-sheet'); if(!sh){ sh=document.createElement('div'); sh.className='lz-sheet'; root.appendChild(sh); }
    sh.innerHTML=html;
  }
  function close(){
    if(st.closed) return; st.closed=true;
    if(st.onOri){ removeEventListener('deviceorientationabsolute',st.onOri); removeEventListener('deviceorientation',st.onOri); }
    st.stream?.getTracks().forEach(t=>t.stop()); retire(st.wp);
    try{ speechSynthesis.cancel(); }catch(e){}
    removeEventListener('resize',render); root.remove(); ui=null; opts.onClose?.();
  }
  root.addEventListener('click',e=>{
    const a=e.target.closest('[data-a]')?.dataset.a;
    if(a==='close') return close();
    if(a==='freeze') return st.mode==='look' ? identify() : freeze(st.live);
    if(a==='again') return identify();
    const md=e.target.closest('[data-mode]')?.dataset.mode; if(md) return setMode(md);
    const pl=e.target.closest('[data-place]')?.dataset.place;
    if(pl&&st.look){ const r=st.look;
      if(pl==='sight'){ close(); return opts.onSight?.(r.sight); }
      if(opts.onPlace){ close(); return opts.onPlace(r.place, pl); }
      return window.open('https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(`${r.place.name} ${r.place.addr||''}`),'_blank','noopener'); }
    if(a==='list') return list();
    if(a==='photo'){ const f=$('input[type=file]'); f.value=''; return f.click(); }
    if(a==='swap') return setLang('swap');
    if(a==='orig'){ st.showOrig=!st.showOrig; const b=$('[data-a="orig"]'); b.classList.toggle('on',st.showOrig); b.setAttribute('aria-pressed',st.showOrig); return render(); }
    if(a==='torch'){ st.torch=!st.torch; st.cam?.applyConstraints({advanced:[{torch:st.torch}]}).catch(()=>{}); $('[data-a="torch"]').classList.toggle('on',st.torch); return; }
    if(a==='zoom'){ st.zoom=st.zoom>=st.zoomMax?1:Math.min(st.zoomMax,st.zoom+1); st.cam?.applyConstraints({advanced:[{zoom:st.zoom}]}).catch(()=>{});
      $('[data-a="zoom"]').textContent=st.zoom+'×'; return; }
    const sp=e.target.closest('[data-say]'); if(sp&&'speechSynthesis' in window){ const u=new SpeechSynthesisUtterance(sp.dataset.say); u.lang=L[st.to][4]; speechSynthesis.cancel(); speechSynthesis.speak(u); return; }
    const cp=e.target.closest('[data-copy]'); if(cp){ navigator.clipboard?.writeText(cp.dataset.copy).then(()=>{ cp.textContent='✓'; setTimeout(()=>cp.textContent='⧉',1200); }).catch(()=>{}); return; }
    const bx=e.target.closest('.lz-box'); if(bx){ const it=st.items.find(x=>x.id===+bx.dataset.id); if(it){ it.orig=!it.orig; render(); } }
  });
  root.addEventListener('change',e=>{ if(e.target.type==='file') return photo(e.target.files[0]); const k=e.target.dataset.k; if(k) setLang(k, e.target.value); });
  addEventListener('resize',render);
  root.querySelectorAll('[data-mode]').forEach(b=>b.classList.toggle('on',b.dataset.mode===st.mode));
  if(st.mode==='look'){ root.classList.add('look'); compass(); $('[data-a="freeze"]').setAttribute('aria-label','Identify what is in the picture'); }
  detName();
  (async()=>{ render(); if(!(await camera())) return; render(); if(st.mode==='tr') reader(); next(); })();   // Identify needs no text reader
  ui.api = {close, freeze, root, _st:st};
  return ui.api;
}
window.Lens = {open, LANGS: LANGS.map(l=>({code:l[0], name:l[1], english:l[2]})), _track:{track, newTracker, fitSim, comp, inv, app}};
})();
