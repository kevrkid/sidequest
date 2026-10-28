/* Pulse (pulse.rb): the vibe check on every place card, "Your move tonight" (one place for the whole night, with
   a Plan B a short walk away), places rising right now, and stories / live streams worth watching before you go.
   Uses the app's own helpers ($, esc, T, api, km, ME_POS, AUTHED, needAccount, focusPlace, openStories, allStories). */
(function(){
const PU = {pick:null, pickAt:0, pickKey:'', busy:{}, near:null, nearAt:0, feed:null, feedAt:0, place:{}};
const css = `
.pvibe{margin:10px 0 4px;padding:10px 12px;border-radius:14px;background:rgba(255,122,24,.07);border:1px solid rgba(255,122,24,.22)}
.pvibe .pvh{display:flex;align-items:center;gap:10px}.pvibe .pve{font-size:26px;line-height:1}
.pvibe .pvl{font-weight:700;font-size:15px}.pvibe .pvs{font-size:12px;color:var(--muted,#9aa3b8)}
.pvibe .pvhot{margin-top:6px;font-size:12px;color:var(--accent,#ff7a18);font-weight:600}
.pvwords{display:flex;flex-wrap:wrap;gap:5px;margin-top:7px}.pvwords span{font-size:11px;padding:3px 8px;border-radius:99px;background:rgba(255,255,255,.07)}
.pvbars{display:flex;align-items:flex-end;gap:2px;height:44px;margin:10px 0 2px}.pvbars i{flex:1;border-radius:3px 3px 0 0;background:rgba(255,122,24,.35);min-height:2px}
.pvbars i.now{background:var(--accent,#ff7a18)}.pvbars i.off{background:rgba(255,255,255,.06)}
.pvax{display:flex;justify-content:space-between;font-size:10px;color:var(--muted,#9aa3b8)}
.pvfacts{margin:8px 0 0;padding:0;list-style:none;font-size:12.5px;line-height:1.55}.pvfacts li::before{content:'• ';color:var(--accent,#ff7a18)}
.pvproof{display:flex;gap:6px;margin-top:8px;overflow-x:auto}.pvproof button{flex:none;width:64px;height:84px;border-radius:10px;border:0;padding:0;overflow:hidden;
  background:#1b2236 center/cover no-repeat;position:relative;color:#fff;font-size:10px}
.pvproof button span{position:absolute;left:4px;bottom:4px;right:4px;text-align:left;text-shadow:0 1px 3px #000}
.pvproof button em{position:absolute;inset:6px 5px auto;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;font-style:normal;font-weight:700;font-size:10.5px;line-height:1.25;overflow:hidden;text-align:left;text-shadow:0 1px 3px #000}
.pvproof .onair{position:absolute;top:4px;left:4px}
.pvask{margin-top:10px}.pvask .pvq{font-size:12px;margin-bottom:6px;color:var(--muted,#9aa3b8)}
.pvbtns{display:grid;grid-template-columns:repeat(4,1fr);gap:6px}.pvbtns button{padding:8px 0;border-radius:10px;border:1px solid rgba(255,255,255,.12);
  background:rgba(255,255,255,.04);color:inherit;font-size:12px}.pvbtns button b{display:block;font-size:18px}
.pvtags{display:flex;flex-wrap:wrap;gap:5px;margin-top:6px}.pvtags button{font-size:11px;padding:4px 9px;border-radius:99px;border:1px solid rgba(255,255,255,.14);background:none;color:inherit}
.pvtags button.on,.pvbtns button.on{border-color:var(--accent,#ff7a18);background:rgba(255,122,24,.16)}
.pvsrc{font-size:10px;color:var(--muted,#9aa3b8);margin-top:6px}
.pumove{margin:6px 0 4px;padding:12px;border-radius:16px;background:linear-gradient(145deg,rgba(255,122,24,.16),rgba(221,36,118,.12));border:1px solid rgba(255,122,24,.3)}
.pumove .puwant{display:flex;gap:6px;flex-wrap:wrap;margin:6px 0 10px}.pumove .puwant button{font-size:12px;padding:5px 10px;border-radius:99px;border:1px solid rgba(255,255,255,.16);background:none;color:inherit}
.pumove .puwant button.on{background:var(--accent,#ff7a18);border-color:var(--accent,#ff7a18);color:#111;font-weight:700}
.pupick{display:flex;gap:10px;align-items:flex-start;text-align:left;width:100%;background:none;border:0;color:inherit;padding:0}
.pupick .pue{font-size:28px;line-height:1}.pupick b{font-size:16px}.pupick .puwhy{font-size:12px;color:var(--muted,#9aa3b8);margin-top:3px;line-height:1.45}
.puplanb{margin-top:10px;padding-top:9px;border-top:1px dashed rgba(255,255,255,.14);font-size:12px;display:flex;gap:8px;align-items:center;background:none;border-left:0;border-right:0;border-bottom:0;color:inherit;width:100%;text-align:left}
`;
document.head.insertAdjacentHTML('beforeend', `<style>${css}</style>`);

const get = async (path) => { const r=await fetch(path,{credentials:'same-origin'}); const j=await r.json(); if(j.error) throw new Error(j.error); return j; };
const ago = (at) => { const m=Math.max(1,Math.round((Date.now()-at)/6e4)); return m<60?T('{n} min ago',{n:m}):T('{n} h ago',{n:Math.round(m/60)}); };
const night = () => { const h=new Date().getHours(); return h>=17||h<4; };
const safeBg = (bg) => /^(linear-gradient\([#0-9a-f(),.% a-z-]+\)|#[0-9a-f]{3,8})$/i.test(bg||'') ? bg : 'linear-gradient(145deg,#3a1c71,#d76d77)';
const tileBg = (m) => m.img ? `background-image:url('${esc(m.img)}')` : `background:${safeBg(m.bg)}`;
// The server writes facts and reasons in English; in Spanish these patterns put them into Spanish (times stay "9 PM").
const DAY_ES = {Monday:'lunes',Tuesday:'martes',Wednesday:'miércoles',Thursday:'jueves',Friday:'viernes',Saturday:'sábado',Sunday:'domingo'};
const LV_ES = {Quiet:'Tranquilo',Chill:'Relajado',Lively:'Animado',Busy:'Lleno',Packed:'A reventar'};
const ES_PAT = [
  [/^Busiest (.+)–(.+)$/, (m,a,b)=>`Más lleno de ${a} a ${b}`],
  [/^Get there by (.+) to beat the crowd$/, (m,t)=>`Llega antes de las ${t} para evitar la multitud`],
  [/^Quietest around (.+)$/, (m,t)=>`Más tranquilo hacia las ${t}`],
  [/^Last call ~(.+)$/, (m,t)=>`Última ronda ~${t}`],
  [/^(\d+) visits seen here$/, (m,n)=>`${n} visitas vistas aquí`],
  [/^what places like this are usually like$/, ()=>'cómo suelen estar los lugares así'],
  [/^(Way|Much) busier than a usual (\w+)( night)?$/, (m,w,d,n)=>`${w==='Way'?'Muchísimo':'Mucho'} más lleno que un ${DAY_ES[d]||d}${n?' por la noche':''} normal`],
  [/^(.+) (are|is) there$/, (m,who,v)=>`${who} ${v==='are'?'están':'está'} ahí`],
  [/^(\S+) (Quiet|Chill|Lively|Busy|Packed) now( \(usually\))?$/, (m,e,l,u)=>`${e} ${LV_ES[l]} ahora${u?' (normalmente)':''}`],
  [/^Stays (?:\w+ )?good your whole night$/, ()=>'Sigue bien toda tu noche'],
  [/^Good for (\d+) hours$/, (m,n)=>`Bien por ${n} horas`],
  [/^Your kind of place$/, ()=>'Tu tipo de lugar'],
  [/^Right here$/, ()=>'Aquí mismo'],
  [/^(\d+) min walk$/, (m,n)=>`${n} min a pie`],
];
const tx = (s) => { if(S.lang!=='es'||typeof s!=='string') return s; for(const [re,f] of ES_PAT){ const m=s.match(re); if(m) return f(...m); } return s; };
const H12 = (h) => h===0?'12a':h<12?h+'a':h===12?'12p':(h-12)+'p';

function sureText(v){
  if(v.reports) return T('Said by people there {t}',{t:ago(v.at-60000)});
  if(v.sure==='high') return v.people?T('{n} people here on Side Quest now',{n:v.people}):T('Lots going on here right now');
  if(v.sure==='some') return T('A little activity here lately');
  return v.open===false?T('Closed right now'):T('What it\'s usually like now');
}
function bars(f){
  if(!f.hours) return '';
  const now=new Date().getHours(), top=Math.max(.05,...f.hours.map(x=>x.v));
  return `<div class="pvbars" aria-label="${esc(T('How busy it usually gets today'))}">${f.hours.map(x=>`<i class="${x.h===now?'now':x.v?'':'off'}" style="height:${Math.max(4,Math.round(x.v/top*100))}%" title="${H12(x.h)}"></i>`).join('')}</div>
    <div class="pvax"><span>5a</span><span>11a</span><span>5p</span><span>11p</span><span>4a</span></div>`;
}
function proofHtml(list){
  if(!list?.length) return '';
  return `<div class="pvproof">${list.map(m=>{
    if(m.t==='live') return `<button data-watch="${esc(m.id)}" style="background:#3b0d1a"><span class="onair">LIVE</span><span>@${esc(m.by)}</span></button>`;
    return `<button data-pvst="${esc(m.id)}" data-pvt="${esc(m.t)}" style="${tileBg(m)}">${!m.img&&m.cap?`<em>${esc(m.cap)}</em>`:m.vid&&!m.img?'🎬':''}<span>@${esc(m.by)} · ${esc(ago(m.at))}</span></button>`; }).join('')}</div>`;
}
const VOTES=[['dead','💤','Dead'],['chill','😌','Chill'],['lively','🔥','Lively'],['packed','🚫','Packed']];
const TAGS=[['line','Line'],['cover','Cover'],['music','Live music'],['dj','DJ'],['dancing','Dancing'],['patio','Patio'],['sports','Sports on'],['loud','Loud'],['quiet','Quiet']];
function askHtml(p){
  const here = p.lat!=null && km(ME_POS,[p.lat,p.lng])<=0.2 && (typeof ME_FIX==='undefined' || Date.now()-ME_FIX<10*6e4);
  if(!here) return '';
  const tags=PU.tags?.[p.id]||[];
  return `<div class="pvask"><div class="pvq">${T('You\'re here: how is it right now?')}</div>
    <div class="pvbtns">${VOTES.map(([k,e,l])=>`<button data-pvvote="${k}" data-pvid="${esc(p.id)}"><b>${e}</b>${T(l)}</button>`).join('')}</div>
    <div class="pvtags">${TAGS.map(([k,l])=>`<button data-pvtag="${k}" data-pvid="${esc(p.id)}" class="${tags.includes(k)?'on':''}">${T(l)}</button>`).join('')}</div></div>`;
}
function cardHtml(j){
  const v=j.vibe, f=j.facts||{};
  const facts=[f.peak, f.arrive, f.last_call, f.quiet].filter(Boolean);
  const ev=(j.events||[]).map(e=>`🎶 ${e.title}`);
  return `<div class="pvhead"><div class="pvh"><span class="pve">${v.e}</span><div><div class="pvl">${T('Vibe check')}: ${esc(T(v.label))}</div><div class="pvs">${esc(sureText(v))}</div></div></div>
    ${v.hot?`<div class="pvhot">📈 ${esc(tx(v.hot))}</div>`:''}
    ${v.words?.length?`<div class="pvwords">${v.words.map(w=>`<span>${esc(T(w))}</span>`).join('')}</div>`:''}</div>
    ${proofHtml(j.proof)}
    ${bars(f)}
    ${facts.length||ev.length?`<ul class="pvfacts">${[...ev,...facts].map(x=>`<li>${esc(tx(x))}</li>`).join('')}</ul>`:''}
    ${askHtml(j)}
    <div class="pvsrc">${esc(T('Forecast from'))} ${esc(tx(f.based_on||''))}${v.sure!=='usual'?' · '+esc(T('live from check-ins, posts and streams')):''}</div>`;
}

// The vibe check box on a place card (placePopup leaves a <div id="pv_<id>"> for it).
async function card(id){
  const el=document.getElementById('pv_'+id); if(!el) return;
  el.className='pvibe'; el.innerHTML=`<p class="skel">${T('Checking the vibe…')}</p>`;
  try{ const j=await get(`/api/pulse/place?id=${encodeURIComponent(id)}`); PU.place[id]=j;
    const el2=document.getElementById('pv_'+id); if(el2) el2.innerHTML=cardHtml(j);
  }catch(e){ el.remove(); }
}

async function vote(id, v){
  if(!AUTHED){ needAccount('tell people how it is'); return; }
  // the server checks you're there too: your spot rounded to ~100 m
  try{ const r=await api('/api/pulse/vibe',{id, v, tags:PU.tags?.[id]||[], lat:+ME_POS[0].toFixed(3), lng:+ME_POS[1].toFixed(3)});
    toast(`${r.vibe.e} ${T('Thanks! People deciding where to go will see it.')}`);
    const j=PU.place[id]; if(j){ j.vibe=r.vibe; const el=document.getElementById('pv_'+id); if(el) el.innerHTML=cardHtml(j); }
    PU.pickAt=0; PU.nearAt=0;
  }catch(e){ toast(esc(e.message),'err'); }
}

// ---- Explore: your move tonight, rising now, see it before you go ----
function want(){ return S.pulseWant || (night()?'lively':'chill'); }
function kindNow(){ return S.pulseKind || (night()?'bars':'food'); }
function refresh(){ if(curTab==='home'&&!EXC.k&&!POP.p) renderHome(); }
function loadPick(){
  const key=[want(),kindNow(),ME_POS.map(x=>x.toFixed(2)).join(',')].join('|');
  if(PU.busy.pick || (PU.pickKey===key && Date.now()-PU.pickAt<3*6e4)) return;
  PU.busy.pick=true;
  api('/api/pulse/pick',{lat:+ME_POS[0].toFixed(2), lng:+ME_POS[1].toFixed(2), want:want(), kind:kindNow(), hours:night()?3:2})
    .then(j=>{ PU.pick=j; PU.pickKey=key; PU.pickAt=Date.now(); }).catch(()=>{ PU.pickAt=Date.now(); })
    .finally(()=>{ PU.busy.pick=false; refresh(); });
}
function loadNear(){
  if(PU.busy.near || Date.now()-PU.nearAt<2*6e4) return; PU.busy.near=true;
  const q=`lat=${ME_POS[0].toFixed(2)}&lng=${ME_POS[1].toFixed(2)}`;
  Promise.all([get(`/api/pulse?${q}&km=8`), get(`/api/pulse/feed?${q}`)])
    .then(([n,f])=>{ PU.near=n; PU.feed=f; }).catch(()=>{}).finally(()=>{ PU.nearAt=Date.now(); PU.busy.near=false; refresh(); });
}
const KIND_E={bar:'🍸',pub:'🍺','beer garden':'🍻',club:'🪩',cafe:'☕'};
function rail(){
  if(!location.protocol.startsWith('http')) return '';
  loadPick(); loadNear();
  const p=PU.pick?.pick, b=PU.pick?.plan_b;
  const wants=[['chill','😌 Chill'],['lively','🔥 Lively'],['party','🪩 Party']], kinds=[['bars','🍸 Drinks'],['clubs','🪩 Clubs'],['food','🍽️ Food']];
  const move=`<div class="tnhead"><b>🎯 ${T(night()?'Your move tonight':'Your move now')}</b></div><div class="pumove">
    <div class="meta">${T('One spot that stays good, so you\'re not bar hopping all night.')}</div>
    <div class="puwant">${wants.map(([k,l])=>`<button data-puwant="${k}" class="${want()===k?'on':''}">${T(l)}</button>`).join('')}
      ${kinds.map(([k,l])=>`<button data-pukind="${k}" class="${kindNow()===k?'on':''}">${T(l)}</button>`).join('')}</div>
    ${p?`<button class="pupick" data-xgo="pl|${esc(p.id)}"><span class="pue">${KIND_E[p.kind]||'🍽️'}</span><span class="grow"><b>${esc(p.name)}</b>
        <div class="puwhy">${p.why.slice(0,4).map(x=>esc(tx(x))).join(' · ')}</div></span></button>
      ${b?`<button class="puplanb" data-xgo="pl|${esc(b.id)}">🅱️ <span><b>${T('Plan B')}:</b> ${esc(b.name)} · ${esc(tx(b.why.find(x=>/walk|Right here|mi$/.test(x))||''))} · ${b.vibe.e} ${esc(T(b.vibe.label))}</span></button>`:''}`
      : `<p class="meta skel">${PU.pick?T('Nothing open that fits. Try another vibe.'):T('Finding your spot…')}</p>`}</div>`;
  const hot=(PU.near?.trending||[]).slice(0,8);
  const rising=hot.length?`<div class="tnhead"><b>📈 ${T('Rising right now')}</b></div><div class="tnrail">${hot.map(x=>
    `<button class="tncard" data-xgo="pl|${esc(x.id)}" style="width:190px"><span class="cat thumb" style="background:linear-gradient(145deg,#ff512f,#dd2476)">${x.vibe.e}</span><span class="tnt"><b>${esc(x.name)}</b><span class="meta">${esc(tx(x.vibe.hot)||T(x.vibe.label))}</span></span></button>`).join('')}</div>`:'';
  const media=(PU.feed?.items||[]).filter(m=>m.place).slice(0,10);
  const watch=media.length?`<div class="tnhead"><b>👀 ${T('See it before you go')}</b></div><div class="pvproof" style="padding:0 2px 6px">${media.map(m=>
    m.type==='live'?`<button data-watch="${esc(m.id)}" style="width:96px;height:128px;background:#3b0d1a"><span class="onair">LIVE</span><span>${esc(m.place)}</span></button>`
    :`<button data-pvst="${esc(m.id)}" data-pvt="${esc(m.type)}" data-pvpid="${esc(m.pid)}" style="width:96px;height:128px;${tileBg(m)}">${!m.img&&m.cap?`<em>${esc(m.cap)}</em>`:m.vid&&!m.img?'🎬':''}<span>${esc(m.place)}<br>@${esc(m.u)}</span></button>`).join('')}</div>`:'';
  return move+rising+watch;
}

document.addEventListener('click', e=>{
  const t=e.target.closest('[data-pvvote],[data-pvtag],[data-pvst],[data-puwant],[data-pukind]'); if(!t) return;
  e.stopPropagation();
  if(t.dataset.pvvote) return vote(t.dataset.pvid, t.dataset.pvvote);
  if(t.dataset.pvtag){ const id=t.dataset.pvid, k=t.dataset.pvtag; PU.tags ||= {}; const L=PU.tags[id] ||= [];
    L.includes(k) ? L.splice(L.indexOf(k),1) : L.length<3 && L.push(k); t.classList.toggle('on', L.includes(k)); return; }
  if(t.dataset.puwant){ S.pulseWant=t.dataset.puwant; save?.(); PU.pickAt=0; return refresh(); }
  if(t.dataset.pukind){ S.pulseKind=t.dataset.pukind; save?.(); PU.pickAt=0; return refresh(); }
  if(t.dataset.pvst){
    if(t.dataset.pvt==='story'){ const ss=allStories(), i=ss.findIndex(x=>x.id===t.dataset.pvst); if(i>=0) return openStories(ss,i); }
    if(t.dataset.pvpid) return focusPlace(t.dataset.pvpid);
  }
}, true);

window.Pulse = {card, rail, vote, state:PU};
})();
