/* 🏆 Best of Austin: the rankings (rankings.rb, research by fetch_rankings.rb), loaded by index.html after the first
   paint. Rank.rail(el) draws Explore's row of lists; Rank.open(k) opens the sheet on a list (or the last one seen).
   Uses the app's own helpers (T, esc, api, needAccount, toast, focusPlace, openMenu, favBtn, mapsUrl, shareLink,
   sendToChat, thumbAttr, placeE, ME_POS, track) and its CSS (sheet, chip, btn, tnrail/tncard). */
(function(){
'use strict';
const R = {idx:null, idxP:null, k:null, g:null, list:null, sort:'top', fresh:false, rate:null, open:null, seq:0};
const DAYS = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const CSS = `
#rankBg .sheet{height:92%;max-height:92%;padding-top:12px}
.rkhd{display:flex;align-items:center;gap:8px} .rkhd h2{margin:0;font-size:20px;flex:1}
.rksub{margin:2px 0 10px;font-size:12.5px}
.rkgroups{display:flex;gap:6px;overflow-x:auto;scrollbar-width:none;margin:0 -16px;padding:0 16px 8px} .rkgroups::-webkit-scrollbar,.rkcats::-webkit-scrollbar{display:none}
.rkcats{display:flex;gap:6px;overflow-x:auto;scrollbar-width:none;margin:0 -16px;padding:2px 16px 10px;position:sticky;top:-12px;background:var(--panel);z-index:2}
.rkcats .chip{font-size:13px;padding:7px 11px} .rkgroups .chip{flex:none;font-size:13.5px;padding:8px 13px}
.rkbar{display:flex;gap:6px;align-items:center;margin:0 -16px 10px;padding:0 16px;overflow-x:auto;scrollbar-width:none} .rkbar::-webkit-scrollbar{display:none}
.rkbar .chip{font-size:12px;flex:none} .rkbar .grow{flex:1;min-width:4px}
.rkc{background:var(--panel2);border:1px solid var(--line);border-radius:16px;padding:12px;margin-bottom:10px}
.rkc.top1{border-color:#ffc94a66;box-shadow:0 0 0 1px #ffc94a33,0 8px 28px -14px #ffc94a88}
.rkh{display:flex;gap:10px;align-items:center}
.rkn{flex:none;width:30px;height:30px;border-radius:50%;display:grid;place-items:center;font-weight:900;font-size:14px;background:var(--line);color:var(--text)}
.top1 .rkn{background:linear-gradient(135deg,#ffd76a,#f0a020);color:#2a1800} .top2 .rkn{background:linear-gradient(135deg,#e8edf7,#a8b2c8);color:#1b2030} .top3 .rkn{background:linear-gradient(135deg,#f2b27a,#b8692e);color:#2a1300}
.rkth{flex:none;width:52px;height:52px;border-radius:12px;display:grid;place-items:center;font-size:24px;background:var(--panel) center/cover no-repeat}
.rkh b{display:block;font-size:16px;line-height:1.2} .rkh .meta{font-size:12px;margin-top:2px}
.rks{flex:none;text-align:center;min-width:44px} .rks b{font-size:20px;color:var(--accent)} .rks small{display:block;font-size:10px;color:var(--muted);font-weight:700;letter-spacing:.03em}
.rktags{display:flex;flex-wrap:wrap;gap:5px;margin-top:8px}
.rktag{font-size:11.5px;font-weight:700;border-radius:99px;padding:3px 8px;background:#ffffff0f;color:var(--text)}
.rktag.new{background:#2ec5ff22;color:#7fdcff} .rktag.been{background:#3ddc9722;color:#7ff0bf} .rktag.why{background:none;color:var(--muted);padding:3px 2px;font-weight:600}
.rkk{margin:8px 0 0;font-size:14px;line-height:1.4}
.rko{margin-top:6px;font-size:13px;color:var(--text)} .rko i{font-style:normal;color:var(--muted);font-weight:700}
.rkhype{margin-top:8px;font-size:13.5px;font-weight:550;color:#ffd9b0;border-left:3px solid var(--accent);padding-left:8px}
.rknights{margin-top:8px;display:flex;flex-direction:column;gap:5px}
.rknight{display:flex;gap:8px;align-items:baseline;font-size:12.5px;background:#ffffff08;border-radius:10px;padding:6px 8px}
.rknight b{flex:none;width:34px;color:var(--accent2)} .rknight.today{background:#2ec5ff18} .rknight a{color:var(--accent2)}
.rkacts{display:flex;gap:6px;margin-top:10px;overflow-x:auto;scrollbar-width:none} .rkacts::-webkit-scrollbar{display:none} .rkacts .btn{flex:none}
.rkwhy{margin-top:8px;font-size:12.5px} .rkwhy summary{cursor:pointer;color:var(--muted);font-weight:700;list-style:none} .rkwhy summary::-webkit-details-marker{display:none}
.rkwhy ul{margin:6px 0 0;padding-left:18px;line-height:1.5} .rkwhy a{color:var(--accent2);text-decoration:none} .rkwhy .meta{font-size:12px}
.rkrate{margin-top:10px;background:var(--panel);border-radius:12px;padding:10px;text-align:center}
.rkstars{display:flex;justify-content:center;gap:4px} .rkstars button{font-size:28px;background:none;border:0;padding:2px 4px;filter:grayscale(1) opacity(.45);transition:transform .1s}
.rkstars button.on{filter:none} .rkstars button:active{transform:scale(1.2)}
.rkback{display:flex;gap:6px;justify-content:center;margin-top:8px;align-items:center;font-size:13px}
.rkback .chip.on{background:var(--good);border-color:var(--good);color:#04140c}
.rkfoot{margin:14px 0 6px;font-size:12.5px;line-height:1.5}
.rkfoot a{color:var(--accent2)}
.rksug{display:flex;flex-direction:column;gap:6px;margin-top:8px} .rksug input{margin:0}
.rkcard{width:176px;flex-direction:column;align-items:flex-start;gap:6px;padding:10px}
.rkcard .rke{font-size:26px;line-height:1} .rkcard b{font-size:14px} .rkcard .meta{font-size:12px;line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.rkcard .rk1{color:#ffd76a;font-weight:800}
.rkempty{text-align:center;padding:30px 10px}
`;
const $ = s => document.querySelector(s);
const tr = (s, o) => typeof T==='function' ? T(s, o) : s;
const fmtMiles = m => m==null ? '' : m<0.1 ? '0.1 mi' : m<10 ? m.toFixed(1)+' mi' : Math.round(m)+' mi';
const DRINKY = /^(cocktails|drink_menus|margaritas|agave|beer|wine|happy_hour|rooftops|patios|dive_bars)$/;

function boot(){
  if(!$('#rkcss')){ const s=document.createElement('style'); s.id='rkcss'; s.textContent=CSS; document.head.appendChild(s); }
  if(!$('#rankBg')){
    const bg=document.createElement('div'); bg.className='sheet-bg'; bg.id='rankBg'; bg.hidden=true; bg.style.zIndex='734';
    bg.innerHTML='<div class="sheet" id="rankSheet"></div>';
    ($('#menuBg')?.parentNode||document.body).appendChild(bg);
    bg.addEventListener('click', e=>{ if(e.target===bg) close(); });
    if(typeof OVERLAYS!=='undefined'&&!OVERLAYS.includes('rankBg')) OVERLAYS.push('rankBg');   // back closes it
  }
}
function index(){
  return R.idxP ||= fetch('/api/rankings',{credentials:'same-origin'}).then(r=>r.json()).then(j=>{ if(j.error) throw new Error(j.error); return R.idx=j; })
    .catch(e=>{ R.idxP=null; throw e; });
}
const allCats = () => (R.idx?.groups||[]).flatMap(g=>g.cats.map(c=>({...c, g:g.k})));

// Explore's row: the lists that fit the hour first (coffee and breakfast tacos in the morning, cocktails and DJs at night)
function hourOrder(){
  const h=new Date().getHours(), dow=new Date().getDay(), wk=dow===0||dow===6;
  if(h<11) return ['coffee','breakfast_tacos','brunch','tacos','bbq'];
  if(h<16) return wk ? ['brunch','bbq','patios','tacos','beer','game_day'] : ['tacos','bbq','pizza','ramen','happy_hour','coffee'];
  if(h<21) return ['happy_hour','cocktails','drink_menus','pizza','sushi','sports_bars','live_music','patios'];
  return ['dj_nights','late_night','cocktails','live_music','dive_bars','karaoke'];
}
async function rail(el){
  if(!el) return; boot();
  try{ await index(); }catch(e){ el.innerHTML=''; return; }
  const cats=allCats(); if(!cats.length){ el.innerHTML=''; return; }
  const want=hourOrder(), seen=new Set(), L=[];
  want.forEach(k=>{ const c=cats.find(x=>x.k===k); if(c){ L.push(c); seen.add(k); } });
  cats.forEach(c=>{ if(!seen.has(c.k)) L.push(c); });
  el.innerHTML = `<div class="tnhead"><b>🏆 ${tr('Best of Austin')}</b><button class="linkbtn" data-rkopen="">${tr('See all')} ›</button></div>
    <div class="tnrail">${L.slice(0,14).map(c=>`<button class="tncard rkcard" data-rkopen="${c.k}"><span class="rke">${c.e}</span><b>${esc(tr(c.title))}</b>
      <span class="meta">${c.top?`<span class="rk1">#1</span> ${esc(c.top)}`:''}</span></button>`).join('')}</div>`;
}

async function open(k){
  boot(); $('#rankBg').hidden=false; try{ track('rank_open'); }catch(e){}
  const sh=$('#rankSheet');
  if(!R.idx) sh.innerHTML=`<p class="skel">${tr('Loading the lists…')}</p>`;
  try{ await index(); }catch(e){ sh.innerHTML=head()+`<p class="meta rkempty">${tr("Couldn't load the lists.")} ${esc(e.message||'')}</p>`; return; }
  const cats=allCats();
  if(!cats.length){ sh.innerHTML=head()+`<p class="meta rkempty">${tr('The lists are still being put together. Check back soon.')}</p>`; return; }
  const c=cats.find(x=>x.k===k) || cats.find(x=>x.k===R.k) || cats.find(x=>x.k===hourOrder()[0]) || cats[0];
  await pick(c.k);
}
function close(){ $('#rankBg').hidden=true; R.rate=null; }
function head(){
  return `<div class="rkhd"><h2>🏆 ${tr('Best of Austin')}</h2>
    ${R.k?`<button class="xbtn" data-rkshare="${R.k}" aria-label="${tr('Share this list')}">🔗</button>`:''}
    <button class="xbtn" data-rkclose aria-label="${tr('Close')}"><svg class="ic" aria-hidden="true"><use href="#i-x"/></svg></button></div>
    <p class="meta rksub">${tr('Ranked from local best-of lists, awards, Reddit, videos, and people on Side Quest who went.')}</p>`;
}
async function pick(k){
  R.k=k; R.g=allCats().find(c=>c.k===k)?.g; R.rate=null; R.open=null; const seq=++R.seq;
  draw(true);
  const p=new URLSearchParams({k});
  if(typeof ME_POS!=='undefined'&&ME_POS) { p.set('lat',(+ME_POS[0]).toFixed(3)); p.set('lng',(+ME_POS[1]).toFixed(3)); }   // ~100 m is plenty for "how far"
  try{ const r=await fetch('/api/rankings/cat?'+p,{credentials:'same-origin'}); const j=await r.json(); if(j.error) throw new Error(j.error);
    if(seq!==R.seq) return; R.list=j; }
  catch(e){ if(seq===R.seq){ R.list={k, err:e.message}; } }
  draw(false); try{ track('rank_list'); }catch(e){}
}
function groupsHtml(){
  return `<div class="rkgroups">${R.idx.groups.map(g=>`<button class="chip ${g.k===R.g?'on':''}" data-rkgroup="${g.k}">${g.e} ${esc(tr(g.title))}</button>`).join('')}</div>
    <div class="rkcats">${(R.idx.groups.find(g=>g.k===R.g)?.cats||[]).map(c=>`<button class="chip ${c.k===R.k?'on':''}" data-rkcat="${c.k}">${c.e} ${esc(tr(c.title))}</button>`).join('')}</div>`;
}
function items(){
  let L=[...(R.list?.items||[])];
  if(R.fresh) L=L.filter(x=>!x.been);
  if(R.sort==='near') L=L.filter(x=>x.mi!=null).sort((a,b)=>a.mi-b.mi);
  if(R.sort==='open') L=L.filter(x=>x.place?.state==='open'||x.place?.state==='soon');
  return L;
}
function draw(loading){
  const sh=$('#rankSheet'); if(!sh||!R.idx) return;
  const top=sh.scrollTop, same=sh.dataset.k===R.k&&!loading;
  const j=R.list&&R.list.k===R.k?R.list:null;
  let body;
  if(loading||!j) body=`<p class="skel" style="margin-top:6px">${tr('Ranking…')}</p>`;
  else if(j.err) body=`<p class="meta rkempty">${esc(j.err)}</p>`;
  else {
    const L=items();
    const bar=`<div class="rkbar">${[['top','🏆 Top'],['near','📍 Near me'],['open','● Open now']].map(([v,l])=>`<button class="chip ${R.sort===v?'on':''}" data-rksort="${v}">${tr(l)}</button>`).join('')}
      <span class="grow"></span><button class="chip ${R.fresh?'on':''}" data-rkfresh aria-pressed="${R.fresh}">✨ ${tr('New to me')}</button></div>`;
    const want=j.want?`<p class="meta" style="margin:-4px 0 10px;font-size:12.5px">${tr('What people want to know')}: ${esc(j.want)}</p>`:'';
    const sched=j.k==='dj_nights'||j.items.some(x=>x.nights)?schedule(j):'';
    body = bar + want + sched + (L.map(card).join('') || `<p class="meta rkempty">${R.fresh?tr("You've been to every spot on this list. Turn off New to me to see them all."):R.sort==='open'?tr('None of these are open right now (or their hours are unknown).'):tr('No spots with a known location on this list.')}</p>`)
      + foot(j);
  }
  sh.innerHTML = head() + groupsHtml() + body; sh.dataset.k=R.k;
  if(same) sh.scrollTop=top;
  const on=sh.querySelector('.rkcats .chip.on'); if(on){ const row=on.parentNode; row.scrollLeft=Math.max(0,on.offsetLeft-row.clientWidth/2+on.offsetWidth/2); }
  try{ watchThumbs(); }catch(e){}
}
// DJ / weekly nights: this week at a glance, today first
function schedule(j){
  const today=new Date().getDay(), rows=[];
  j.items.forEach(x=>(x.nights||[]).forEach(n=>{ const d=DAYS.findIndex(D=>new RegExp('^'+D,'i').test(n.day||'')); rows.push({x,n,d}); }));
  if(!rows.length) return '';
  rows.sort((a,b)=>((a.d<0?9:(a.d-today+7)%7)-(b.d<0?9:(b.d-today+7)%7))||a.x.rank-b.x.rank);
  return `<details class="rkwhy" open style="margin:0 0 12px"><summary>🗓️ ${tr('Weekly nights')} (${rows.length}) ▾</summary><div class="rknights">${rows.slice(0,24).map(({x,n,d})=>nightRow(x,n,d===today)).join('')}</div></details>`;
}
const nightRow = (x, n, today) => `<div class="rknight ${today?'today':''}"><b>${esc((n.day||'').slice(0,3)||'—')}</b><span class="grow">${today?`<span class="rktag new">${tr('Tonight')}</span> `:''}<span>${esc(n.name||n.music||'')}</span>${x?` · <b style="width:auto;color:var(--text)">${esc(x.name)}</b>`:''}${n.time?` · ${esc(n.time)}`:''}${n.music&&n.name?` · ${esc(n.music)}`:''}${n.djs?.length?`<br><span class="meta">🎧 ${esc(n.djs.join(', '))}</span>`:''}${n.instagram?` <a href="https://www.instagram.com/${encodeURIComponent(n.instagram)}/" target="_blank" rel="noopener">@${esc(n.instagram)}</a>`:''}</span>
  <button class="btn sm" data-rknshare="${esc(JSON.stringify({v:x?.name||'',n:n.name||n.music||'',d:n.day||'',t:n.time||''}))}" aria-label="${tr('Share this night')}">🔗</button></div>`;
function card(x){
  const p=x.place, near=x.mi!=null?fmtMiles(x.mi):'', st=p?.status?`<span class="pst ${p.state}" style="font-size:11px;padding:1px 7px">${esc(p.status)}</span>`:'';
  const e=typeof placeE==='function'?placeE(p?.kind||'', x.name, p?.cuisine||[]):'📍';
  const th=typeof thumbAttr==='function'?(p?thumbAttr({id:p.id}):x.lat!=null?thumbAttr({name:x.name,lat:x.lat,lng:x.lng}):''):'';
  const tags=[x.been?`<span class="rktag been">✓ ${tr("You've been")}</span>`:R.list.items.length>3?`<span class="rktag new">✨ ${tr('New to you')}</span>`:'',
    ...(x.reasons||[]).map(r=>`<span class="rktag">${esc(r)}</span>`)].filter(Boolean).join('');
  const ord=(x.order||[]).length?`<div class="rko"><i>${DRINKY.test(R.k)?'🍸 '+tr('Try'):'🍽️ '+tr('Get')}:</i> ${x.order.map(esc).join(' · ')}</div>`:'';
  const why=`<details class="rkwhy" ${R.open===x.id?'open':''} data-rkwhy="${x.id}"><summary>${tr('Why it ranks here')} · ${x.score}/100 ▾</summary>
    <p class="meta" style="margin:6px 0 0">${tr('From the web')}: ${x.parts.web}/100${x.parts.people!=null?` · ${tr('From Side Quest people')}: ${x.parts.people}/100`:''}${x.vibe?` · ${tr('Vibe')}: ${esc(x.vibe)}`:''}${x.best_time?`<br>⏰ ${esc(x.best_time)}`:''}</p>
    <ul>${(x.sources||[]).map(s=>`<li><a href="${esc(s.url)}" target="_blank" rel="noopener nofollow">${s.kind==='video'?'▶️ ':s.kind==='award'?'🏆 ':s.kind==='reddit'?'💬 ':''}${esc(s.outlet)}</a> <span class="meta">${esc(s.title||'')}${s.year?' · '+s.year:''}</span></li>`).join('')}</ul></details>`;
  const nights=(x.nights||[]).length&&R.k!=='dj_nights'?`<div class="rknights">${x.nights.slice(0,3).map(n=>nightRow(null,n,DAYS.findIndex(D=>new RegExp('^'+D,'i').test(n.day||''))===new Date().getDay())).join('')}</div>`:'';
  const dir=x.lat!=null?`<a class="btn sm" href="${mapsUrl(x.lat,x.lng)}" target="_blank" rel="noopener">↗ ${tr('Directions')}</a>`
    :`<a class="btn sm" href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(x.name+' '+(x.addr||'Austin TX'))}" target="_blank" rel="noopener">↗ ${tr('Directions')}</a>`;
  const foody=p&&/restaurant|fast food|cafe|bar|pub|bakery|ice cream|food truck|club|food hall|truck park|beer garden/.test(p.kind||'');
  const mine=x.mine?.stars;
  return `<div class="rkc top${x.rank<=3?x.rank:''}" data-rkid="${x.id}">
    <div class="rkh"><span class="rkn">${x.rank}</span><span class="rkth thumb"${th}>${e}</span>
      <div class="grow"><b>${esc(x.name)}</b><div class="meta">${[x.area,x.price,near].filter(Boolean).map(esc).join(' · ')} ${st}</div></div>
      <div class="rks"><b>${x.score}</b><small>${tr('SCORE')}</small></div></div>
    <div class="rktags">${tags}${x.votes?.n?'':`<span class="rktag why">${tr('Been? Rate it')} ⭐</span>`}</div>
    ${x.known_for?`<p class="rkk">${esc(x.known_for)}</p>`:''}${ord}
    ${x.hype?`<div class="rkhype">${esc(x.hype)}</div>`:''}${nights}${why}
    ${R.rate===x.id?rateBox(x):''}
    <div class="rkacts">${x.lat!=null?`<button class="btn sm" data-rkmap="${x.id}">📍 ${tr('Map')}</button>`:''}
      ${foody?`<button class="btn sm" data-rkmenu="${x.id}">🍽️ ${tr('Menu')}</button>`:''}${dir}
      <button class="btn sm" data-rkrate="${x.id}">${mine?'⭐'.repeat(mine):'⭐ '+tr('Rate')}</button>
      ${p&&typeof favBtn==='function'?favBtn('place',p.id,x.name):''}
      ${x.ig?`<a class="btn sm" href="https://www.instagram.com/${encodeURIComponent(x.ig)}/" target="_blank" rel="noopener">📸 @${esc(x.ig)}</a>`:x.web_url?`<a class="btn sm" href="${esc(x.web_url)}" target="_blank" rel="noopener">🌐 ${tr('Website')}</a>`:''}
      <button class="btn sm" data-rkspot="${x.id}" aria-label="${tr('Share')}">🔗</button></div></div>`;
}
function rateBox(x){
  const s=x.mine?.stars||0, b=x.mine?.back;
  return `<div class="rkrate"><b>${tr('How was {name}?',{name:esc(x.name)})}</b>
    <div class="rkstars" role="radiogroup" aria-label="${tr('Stars')}">${[1,2,3,4,5].map(n=>`<button class="${n<=s?'on':''}" data-rkstar="${x.id}|${n}" aria-label="${n} ${tr('stars')}">⭐</button>`).join('')}</div>
    <div class="rkback">${tr('Would you go back?')} <button class="chip ${b===true?'on':''}" data-rkback="${x.id}|1">👍 ${tr('Yes')}</button><button class="chip ${b===false?'on':''}" data-rkback="${x.id}|0">👎 ${tr('No')}</button></div>
    ${x.votes?.n?`<p class="meta" style="margin:8px 0 0;font-size:12px">⭐ ${x.votes.avg} · ${x.votes.n} ${tr(x.votes.n===1?'rating':'ratings')}${x.votes.said_back?` · 🔁 ${x.votes.back}/${x.votes.said_back} ${tr('would go back')}`:''}</p>`:''}
    ${s?`<button class="linkbtn" data-rkstar="${x.id}|0" style="margin-top:6px;font-size:12px">${tr('Take my rating back')}</button>`:''}</div>`;
}
function foot(j){
  const src=(j.sources||[]).slice(0,8);
  return `<div class="rkfoot meta"><details class="rkwhy"><summary>ℹ️ ${tr('How we rank')} ▾</summary>
    <p style="margin:6px 0 0">${tr('Each spot gets points for every independent source that names it: awards and editors’ best-of lists count most, then guides and reviews, then Reddit threads and videos; newer and higher on the list counts more. Ratings from Side Quest people count more as more people rate (up to 40%). For drink lists, a long drink menu and a happy hour add a little. Every link was checked when the list was made.')}</p>
    ${src.length?`<p style="margin:6px 0 0">${tr('Main sources')}: ${src.map(s=>`<a href="${esc(s.url)}" target="_blank" rel="noopener nofollow">${esc(s.outlet||s.title)}</a>`).join(' · ')}</p>`:''}
    ${j.at?`<p style="margin:6px 0 0">${tr('Researched')} ${esc(new Date(j.at).toLocaleDateString())}</p>`:''}</details>
    <details class="rkwhy" style="margin-top:8px" data-rksugbox><summary>➕ ${tr('Missing a spot? Tell us')} ▾</summary>
    <div class="rksug"><input id="rkSugName" maxlength="80" placeholder="${tr('Name of the spot')}"><input id="rkSugWhy" maxlength="200" placeholder="${tr("Why it belongs (what to get, which night…)")}">
      <button class="btn sm" data-rksug>${tr('Send')}</button><span class="meta">${tr('We check it against the web next time this list is researched.')}</span></div></details></div>`;
}

async function vote(id, body){
  if(typeof needAccount==='function'&&needAccount('rate spots')) return;
  const x=R.list.items.find(i=>i.id===id); if(!x) return;
  const was={...(x.mine||{})};
  const stars=body.stars ?? x.mine?.stars ?? 0;
  if(!stars&&body.back!=null){ return toast(tr('Pick the stars first.'),'',[],2000); }
  try{ const j=await api('/api/rankings/vote',{k:R.k, id, stars, back:body.back ?? x.mine?.back ?? null});
    x.votes=j.votes; x.mine=j.mine; if(!j.mine) R.rate=null;
    if(!was.stars&&j.mine) toast(`⭐ ${tr('Thanks! Your rating helps the list.')}`,'green',[],2200);
    try{ track('rank_vote'); }catch(e){} }
  catch(e){ toast(esc(e.message),'orange'); }
  draw(false);
}
function shareList(k){
  const c=allCats().find(x=>x.k===k), top=(R.list?.k===k?R.list.items:[]).slice(0,3).map((x,i)=>`#${i+1} ${x.name}`).join(' · ');
  shareLink(`${location.origin}/r/${k}`, `Best ${c?.title||''} in Austin`, `${c?.e||'🏆'} Best ${(c?.title||'').toLowerCase()} in Austin on Side Quest${top?': '+top:''}`);
}
function shareSpot(x){
  if(x.place&&typeof sendToChat==='function'&&typeof AUTHED!=='undefined'&&AUTHED){
    return toast(`🔗 ${tr('Share {name}',{name:esc(x.name)})}`,'',[{l:'💬 '+tr('In a chat'),cls:'blue',f:()=>sendToChat({k:'place',id:x.place.id,name:x.name.slice(0,80),sub:`#${x.rank} ${R.list.title} · Best of Austin`.slice(0,80),e:'🏆'})},
      {l:'🔗 '+tr('Link'),f:()=>shareLink(`${location.origin}/r/${R.k}`, x.name, `#${x.rank} for ${R.list.title.toLowerCase()} in Austin: ${x.name}${x.order?.[0]?' (get the '+x.order[0]+')':''}`)}],6000);
  }
  shareLink(`${location.origin}/r/${R.k}`, x.name, `#${x.rank} for ${R.list.title.toLowerCase()} in Austin: ${x.name}${x.order?.[0]?' (get the '+x.order[0]+')':''}`);
}

document.addEventListener('click', e=>{
  const t=e.target.closest('[data-rkopen],[data-rkclose],[data-rkgroup],[data-rkcat],[data-rksort],[data-rkfresh],[data-rkrate],[data-rkstar],[data-rkback],[data-rkmap],[data-rkmenu],[data-rkspot],[data-rkshare],[data-rknshare],[data-rksug]');
  if(!t) return; const d=t.dataset;
  if(d.rkopen!=null) return open(d.rkopen||undefined);
  if(d.rkclose!=null) return close();
  if(d.rkgroup){ const g=R.idx.groups.find(x=>x.k===d.rkgroup); if(g?.cats[0]) pick(g.cats[0].k); return; }
  if(d.rkcat) return pick(d.rkcat);
  if(d.rksort){ R.sort=d.rksort; return draw(false); }
  if(d.rkfresh!=null){ R.fresh=!R.fresh; return draw(false); }
  if(d.rkrate){ if(typeof needAccount==='function'&&needAccount('rate spots')) return; R.rate=R.rate===d.rkrate?null:d.rkrate; return draw(false); }
  if(d.rkstar){ const [id,n]=d.rkstar.split('|'); return vote(id,{stars:+n}); }
  if(d.rkback){ const [id,b]=d.rkback.split('|'); return vote(id,{back:b==='1'}); }
  const x=R.list?.items?.find(i=>i.id===(d.rkmap||d.rkmenu||d.rkspot));
  if(d.rkmap&&x){ close();
    if(x.place) return focusPlace(x.place.id);
    tab('map'); setTimeout(()=>{ map.setView([x.lat,x.lng],17); L.popup().setLatLng([x.lat,x.lng]).setContent(`<b>${esc(x.name)}</b><br><span class="meta">#${x.rank} ${esc(R.list.title)}</span>`).openOn(map); },150); return; }
  if(d.rkmenu&&x?.place){ return openMenu(x.place.id, x.name); }
  if(d.rkspot&&x) return shareSpot(x);
  if(d.rkshare) return shareList(d.rkshare);
  if(d.rknshare){ const n=JSON.parse(d.rknshare); return shareLink(`${location.origin}/r/${R.k}`, n.n||n.v, `${n.d} ${n.t}: ${[n.n,n.v].filter(Boolean).join(' at ')} · found on Side Quest`.trim()); }
  if(d.rksug!=null){
    if(typeof needAccount==='function'&&needAccount('suggest a spot')) return;
    const name=$('#rkSugName').value.trim(), why=$('#rkSugWhy').value.trim(); if(name.length<2) return $('#rkSugName').focus();
    api('/api/rankings/suggest',{k:R.k, name, why}).then(()=>{ $('#rkSugName').value=$('#rkSugWhy').value=''; toast(`🙌 ${tr('Thanks! We\'ll look into {name}.',{name:esc(name)})}`,'green',[],2600); })
      .catch(err=>toast(esc(err.message),'orange'));
  }
});
document.addEventListener('toggle', e=>{ const w=e.target.closest?.('[data-rkwhy]'); if(w) R.open=w.open?w.dataset.rkwhy:R.open===w.dataset.rkwhy?null:R.open; }, true);

window.Rank = {open, rail, close, _R:R};
})();
