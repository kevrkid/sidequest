/* Live Translate: point the phone's camera at text (signs, menus, labels) and read it in another language, drawn
   right over the picture. Self-contained so any web app can use it: Side Quest opens it from Scout, and lens.html
   runs it on its own page.
     Lens.open({to:'es', from:'en', translate, onClose, standalone})
   - The text is read on the device by tesseract.js (vendor/tesseract/, next to this file); each language's reading
     data (2-15 MB) downloads the first time it's used and stays cached in the browser.
   - translate(paragraphs, from, to) → Promise<string[]> does the translating; by default it POSTs
     {lines, from, to} to /api/translate (lens.rb). Only the text goes there, never the picture. */
(function(){
'use strict';
const BASE = new URL('.', document.currentScript?.src || location.href).href;
// code, name in that language, English name, tesseract's reading data, speech voice
const LANGS = [
  ['en','English','English','eng','en-US'], ['es','Español','Spanish','spa','es-US'], ['fr','Français','French','fra','fr-FR'],
  ['de','Deutsch','German','deu','de-DE'], ['it','Italiano','Italian','ita','it-IT'], ['pt','Português','Portuguese','por','pt-BR'],
  ['zh','中文','Chinese','chi_sim','zh-CN'], ['ja','日本語','Japanese','jpn','ja-JP'], ['ko','한국어','Korean','kor','ko-KR'],
  ['ar','العربية','Arabic','ara','ar-SA'], ['hi','हिन्दी','Hindi','hin','hi-IN'], ['ru','Русский','Russian','rus','ru-RU'],
  ['vi','Tiếng Việt','Vietnamese','vie','vi-VN']];
const L = Object.fromEntries(LANGS.map(l=>[l[0],l]));
const CSS = `
.lz{position:fixed;inset:0;z-index:3000;background:#000;color:#fff;font:15px/1.35 system-ui,-apple-system,sans-serif;overflow:hidden;touch-action:manipulation}
.lz video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.lz-layer{position:absolute;inset:0;pointer-events:none}
.lz-box{position:absolute;box-sizing:border-box;background:rgba(255,255,255,.97);color:#111;border-radius:4px;padding:1px 3px;white-space:pre-line;
  overflow:hidden;pointer-events:auto;box-shadow:0 1px 4px rgba(0,0,0,.35);font-weight:600;line-height:1.15;word-break:break-word}
.lz-box.wait{background:rgba(255,255,255,.55);color:#333}
.lz-box.orig{background:rgba(255,236,150,.95)}
.lz-top,.lz-bot{position:absolute;left:0;right:0;display:flex;align-items:center;gap:8px;padding:10px 12px;
  background:linear-gradient(rgba(0,0,0,.72),rgba(0,0,0,0))}
.lz-top{top:0;padding-top:max(10px,env(safe-area-inset-top))}
.lz-bot{bottom:0;flex-direction:column;align-items:stretch;background:linear-gradient(rgba(0,0,0,0),rgba(0,0,0,.78));padding-bottom:max(12px,env(safe-area-inset-bottom))}
.lz button,.lz select{font:inherit;color:#fff;background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.25);border-radius:999px;padding:8px 12px;min-height:40px}
.lz select{flex:1;min-width:0;appearance:none;-webkit-appearance:none;text-align:center}
.lz select option{color:#000}
.lz .lz-x{width:40px;padding:0;flex:none;font-size:18px}
.lz .lz-sw{flex:none;width:40px;padding:0}
.lz-msg{text-align:center;font-size:14px;min-height:20px;text-shadow:0 1px 3px #000}
.lz-row{display:flex;gap:10px;justify-content:center}
.lz .lz-go{min-width:120px;font-weight:700;background:#2ec5ff;color:#04121c;border-color:#2ec5ff}
.lz-sheet{position:absolute;left:0;right:0;bottom:0;max-height:60%;overflow:auto;background:#15171c;border-radius:16px 16px 0 0;padding:12px 14px 24px;z-index:2}
.lz-sheet h3{margin:0 0 8px;font-size:16px;display:flex;justify-content:space-between;align-items:center}
.lz-item{border-top:1px solid #2a2d35;padding:10px 0;display:flex;gap:10px;align-items:flex-start}
.lz-item div{flex:1;white-space:pre-line} .lz-item small{display:block;color:#9aa0aa;margin-bottom:3px}
.lz .lz-say{flex:none;width:40px;padding:0}
.lz-hint{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:70%;max-width:340px;aspect-ratio:3/2;border:2px dashed rgba(255,255,255,.5);border-radius:14px;pointer-events:none}
`;
let ui=null;   // one translator open at a time

const pick = (o, k, d) => { try{ return JSON.parse(localStorage.getItem('lens')||'{}')[k] ?? o[k] ?? d; }catch(e){ return o[k] ?? d; } };
const remember = st => { try{ localStorage.setItem('lens', JSON.stringify({from:st.from, to:st.to})); }catch(e){} };
const esc = s => String(s).replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const norm = s => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu,' ').trim();
// OCR reads the same sign a little differently frame to frame: treat close-enough text as the same
function similar(a, b){
  if(a===b) return true; if(Math.abs(a.length-b.length)>Math.max(a.length,b.length)*.25) return false;
  const A=new Set(a.split(' ')), B=new Set(b.split(' ')); let n=0; A.forEach(w=>{ if(B.has(w)) n++; });
  return n/Math.max(A.size,B.size) >= .7;
}
function loadTesseract(){
  if(window.Tesseract) return Promise.resolve();
  return loadTesseract.p ||= new Promise((ok,no)=>{ const s=document.createElement('script'); s.src=BASE+'vendor/tesseract/tesseract.min.js';
    s.onload=ok; s.onerror=()=>{ loadTesseract.p=null; no(new Error("Couldn't load the text reader.")); }; document.head.appendChild(s); });
}
async function defaultTranslate(lines, from, to){
  const r = await fetch('/api/translate',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:JSON.stringify({lines,from,to})});
  const j = await r.json().catch(()=>({error:`Server error (${r.status})`}));
  if(r.status===401) throw Object.assign(new Error('Sign in to translate.'),{auth:true});
  if(j.error) throw new Error(j.error);
  return j.translations;
}

function open(opts={}){
  if(ui) return ui.api;
  if(!document.getElementById('lz-css')){ const st=document.createElement('style'); st.id='lz-css'; st.textContent=CSS; document.head.appendChild(st); }
  const st = { from: pick(opts,'from','en'), to: pick(opts,'to', /^es/.test(navigator.language)?'en':'es'),
    live:true, busy:false, wp:null, wlang:null, stream:null, items:[], cache:new Map(), seen:new Map(), inflight:false, closed:false, timer:0 };
  if(!L[st.from]) st.from='en'; if(!L[st.to]) st.to='es';
  const translate = opts.translate || defaultTranslate;
  const root=document.createElement('div'); root.className='lz'; root.setAttribute('role','dialog'); root.setAttribute('aria-label','Live Translate');
  const opt = sel => LANGS.map(l=>`<option value="${l[0]}"${l[0]===sel?' selected':''}>${esc(l[1])}</option>`).join('');
  root.innerHTML = `<video playsinline muted autoplay></video><div class="lz-hint"></div><div class="lz-layer"></div>
    <div class="lz-top">${opts.standalone?'':'<button class="lz-x" data-a="close" aria-label="Close">✕</button>'}
      <select data-k="from" aria-label="From">${opt(st.from)}</select><button class="lz-sw" data-a="swap" aria-label="Swap languages">⇄</button>
      <select data-k="to" aria-label="To">${opt(st.to)}</select></div>
    <div class="lz-bot"><div class="lz-msg" aria-live="polite"></div>
      <div class="lz-row"><button data-a="list">📋 Text</button><button class="lz-go" data-a="freeze">⏸ Freeze</button></div></div>`;
  document.body.appendChild(root);
  const $=s=>root.querySelector(s), video=$('video'), layer=$('.lz-layer'), grab=document.createElement('canvas');
  const say = t => { $('.lz-msg').textContent=t; };
  ui = {root, st};

  // The text reader for the "from" language (one at a time; switching language starts a new one)
  function reader(){
    const lang=L[st.from][3];
    if(st.wlang===lang&&st.wp) return st.wp;
    const old=st.wp; st.wlang=lang; old?.then(w=>w?.terminate()).catch(()=>{});
    say(`Getting ready to read ${L[st.from][2]}… (the first time takes a moment)`);
    return st.wp = loadTesseract().then(()=>Tesseract.createWorker(lang, 1, { workerPath:BASE+'vendor/tesseract/worker.min.js', corePath:BASE+'vendor/tesseract/' }))
      .then(w=>{ if(st.closed||st.wlang!==lang){ w.terminate(); return null; } return w; })
      .catch(e=>{ if(st.wlang===lang){ st.wp=null; st.wlang=null; } throw e; });
  }
  async function camera(){
    try{ st.stream = await navigator.mediaDevices.getUserMedia({audio:false, video:{facingMode:{ideal:'environment'}, width:{ideal:1920}, height:{ideal:1080}}}); }
    catch(e){ say(/NotAllowed|Security/.test(e.name) ? 'Camera blocked. Allow the camera for this site in your browser or phone settings, then try again.'
                                                      : "Couldn't start the camera. Is another app using it?"); return false; }
    if(st.closed){ st.stream.getTracks().forEach(t=>t.stop()); return false; }
    video.srcObject=st.stream; await video.play().catch(()=>{}); return true;
  }
  // One look: read the frame, group it into paragraphs, translate what's new, draw it over the picture
  async function look(full){
    if(st.busy||st.closed||!video.videoWidth) return;
    st.busy=true;
    try{
      const w=await reader(); if(!w) return;
      const max=full?2000:1280, k=Math.min(1, max/Math.max(video.videoWidth,video.videoHeight));
      grab.width=Math.round(video.videoWidth*k); grab.height=Math.round(video.videoHeight*k);
      grab.getContext('2d').drawImage(video,0,0,grab.width,grab.height);
      if(!full&&!st.live) return;
      const {data} = await w.recognize(grab, {}, {blocks:true, text:false});
      if(st.closed||(!full&&!st.live)) return;
      const paras=[];
      for(const b of data.blocks||[]) for(const p of b.paragraphs||[]){
        const lines=(p.lines||[]).filter(l=>l.confidence>=50 && (l.text.match(/\p{L}/gu)||[]).length>=2).map(l=>l.text.trim());
        if(!lines.length) continue;
        const text=lines.join('\n'), n=norm(text); if(n.length<2) continue;
        paras.push({text, n, lines:lines.length, box:{x0:p.bbox.x0/k, y0:p.bbox.y0/k, x1:p.bbox.x1/k, y1:p.bbox.y1/k}});
      }
      st.items=paras.slice(0,24);
      $('.lz-hint').hidden = st.items.length>0;
      draw();
      if(!st.items.length){ say(full?'No text found here. Get a little closer, hold steady, and try again.':'Point the camera at some text'); return; }
      fill(full);
    }catch(e){ say(e.message||'Something went wrong reading the text.'); }
    finally{ st.busy=false; }
  }
  const key = n => st.from+'>'+st.to+':'+n;
  function known(n){
    const hit=st.cache.get(key(n)); if(hit!=null) return hit;
    for(const [kk,v] of st.cache) if(kk.startsWith(st.from+'>'+st.to+':')&&similar(kk.slice(kk.indexOf(':')+1),n)) return v;
    return null;
  }
  // Translate the paragraphs we don't know yet. While live, only ones seen twice in a row (steady, not a blur).
  async function fill(now){
    const seen=new Map(st.items.map(p=>[p.n,(st.seen.get(p.n)||0)+1])); st.seen=seen;
    const need=st.items.filter(p=>known(p.n)==null&&(now||seen.get(p.n)>=2));
    if(!need.length||st.inflight){ if(!need.length) say(st.live?'Hold steady over the text, or tap Freeze to read it calmly':'Tap any box to see the original'); return; }
    st.inflight=true; say('Translating…');
    const from=st.from, to=st.to;
    try{
      const out=await translate(need.map(p=>p.text), from, to);
      need.forEach((p,i)=>st.cache.set(from+'>'+to+':'+p.n, (out[i]||'').trim()));
      if(st.cache.size>400) st.cache.delete(st.cache.keys().next().value);
      say(st.live?'Hold steady over the text, or tap Freeze to read it calmly':'Tap any box to see the original');
    }catch(e){ say(e.auth ? 'Sign in first, then open the translator again.' : e.message||"Couldn't translate right now."); }
    finally{ st.inflight=false; }
    if(!st.closed) draw();
  }
  // Paragraph boxes from camera pixels to screen pixels (the video fills the screen, cropped like object-fit: cover)
  function draw(){
    const W=root.clientWidth, H=root.clientHeight, vw=video.videoWidth, vh=video.videoHeight; if(!vw) return;
    const s=Math.max(W/vw,H/vh), ox=(W-vw*s)/2, oy=(H-vh*s)/2, rtl=['ar'].includes(st.to);
    layer.innerHTML = st.items.map((p,i)=>{
      const t=known(p.n), x=p.box.x0*s+ox, y=p.box.y0*s+oy, w=(p.box.x1-p.box.x0)*s, h=(p.box.y1-p.box.y0)*s;
      // kept on screen even when the text runs past the edge of the picture
      const l=Math.max(6,Math.min(x,W-60)), bw=Math.max(60,Math.min(x+w,W-6)-l), fs=Math.max(11,Math.min(30,h/p.lines*.7));
      const show=p.orig||t==null||t==='' ? p.text : t;
      return `<div class="lz-box${t==null?' wait':''}${p.orig?' orig':''}" data-i="${i}" data-h="${h.toFixed(0)}" dir="${rtl&&!p.orig&&t?'rtl':'auto'}"
        style="left:${l.toFixed(0)}px;top:${Math.max(56,y).toFixed(0)}px;width:${bw.toFixed(0)}px;min-height:${Math.min(h,H*.5).toFixed(0)}px;font-size:${fs.toFixed(0)}px">${esc(show)}</div>`;
    }).join('');
    // shrink each box's text until it fits its width and roughly the height of what it covers
    layer.querySelectorAll('.lz-box').forEach(b=>{ let fs=parseFloat(b.style.fontSize); const maxH=Math.max(+b.dataset.h*1.25,40);
      while(fs>11&&(b.scrollWidth>b.clientWidth+1||b.scrollHeight>maxH)){ fs-=1; b.style.fontSize=fs+'px'; } });
    if(root.querySelector('.lz-sheet')) list(true);
  }
  function list(refresh){
    let sh=root.querySelector('.lz-sheet');
    if(!refresh&&sh){ sh.remove(); return; }
    if(!sh){ sh=document.createElement('div'); sh.className='lz-sheet'; root.appendChild(sh); }
    const rows=st.items.filter(p=>known(p.n));
    sh.innerHTML=`<h3>Text in view <button data-a="list" aria-label="Close list">✕</button></h3>` + (rows.length ? rows.map(p=>`<div class="lz-item">
      <div><small>${esc(p.text)}</small>${esc(known(p.n))}</div><button class="lz-say" data-say="${esc(known(p.n))}" aria-label="Read aloud">🔊</button></div>`).join('')
      : '<p style="color:#9aa0aa">Nothing translated yet. Point the camera at some text.</p>');
  }
  function loop(){ clearTimeout(st.timer); if(st.closed) return;
    st.timer=setTimeout(async()=>{ if(st.live&&!document.hidden) await look(false); loop(); }, 700); }
  function freeze(on){
    st.live=!on; const b=$('[data-a="freeze"]'); b.textContent=on?'▶ Live':'⏸ Freeze';
    if(on){ video.pause(); say('Reading…'); (function go(){ st.busy ? setTimeout(go,100) : look(true); })(); }   // the picture stops now; a closer read once the current one is done
    else { st.items.forEach(p=>p.orig=false); video.play().catch(()=>{}); say('Point the camera at some text'); }
  }
  function close(){
    if(st.closed) return; st.closed=true; clearTimeout(st.timer);
    st.stream?.getTracks().forEach(t=>t.stop()); st.wp?.then(w=>w?.terminate()).catch(()=>{});
    try{ speechSynthesis.cancel(); }catch(e){}
    removeEventListener('resize',draw); root.remove(); ui=null; opts.onClose?.();
  }
  root.addEventListener('click',e=>{
    const a=e.target.closest('[data-a]')?.dataset.a;
    if(a==='close') return close();
    if(a==='freeze') return freeze(st.live);
    if(a==='list') return list();
    if(a==='swap'){ [st.from,st.to]=[st.to,st.from]; $('[data-k="from"]').value=st.from; $('[data-k="to"]').value=st.to; remember(st); st.seen.clear();
      if(!st.live) look(true); return; }
    const sp=e.target.closest('[data-say]'); if(sp&&'speechSynthesis' in window){ const u=new SpeechSynthesisUtterance(sp.dataset.say); u.lang=L[st.to][4]; speechSynthesis.cancel(); speechSynthesis.speak(u); return; }
    const bx=e.target.closest('.lz-box'); if(bx){ const p=st.items[+bx.dataset.i]; if(p){ p.orig=!p.orig; draw(); } }
  });
  root.addEventListener('change',e=>{ const k=e.target.dataset.k; if(!k) return; st[k]=e.target.value; remember(st); st.seen.clear();
    if(!st.live){ k==='from' ? look(true) : (draw(), fill(true)); } });
  addEventListener('resize',draw);
  (async()=>{ say('Starting the camera…'); if(!(await camera())) return; say('Point the camera at some text');
    reader().then(()=>{ if(!st.closed) say('Point the camera at some text'); }).catch(e=>say(e.message)); loop(); })();
  ui.api = {close, freeze, root};
  return ui.api;
}
window.Lens = {open, LANGS: LANGS.map(l=>({code:l[0], name:l[1], english:l[2]}))};
})();
