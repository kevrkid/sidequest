"""Pulse in Spanish: the vibe check on a bar's card and "Your move" on Explore, with the server's English facts and
reasons put into Spanish on the phone (pulse.js `tx`). Run against a test server with real places (data/places.json):

  SQ_BASE=http://localhost:8835 python e2e_pulse_es.py <shot-dir>
"""
import os, re, sys
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-pulse-es"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []
# English the server writes; none of it should reach a Spanish screen
ENGLISH = re.compile(r"Busiest|Get there by|Quietest|Last call|visits seen|places like this|busier than|min walk|Right here|Your kind of place|"
                     r"Good for \d|whole night|\b(Quiet|Chill|Lively|Busy|Packed) now|Vibe check|Your move|Forecast from")


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:300]}]" if detail and not ok else ""))


with sync_playwright() as pw:
    browser = pw.chromium.launch()
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True,
                              geolocation={"latitude": 30.2671, "longitude": -97.7395}, permissions=["geolocation"])
    ctx.route(lambda u: "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u), lambda r: r.abort())
    pg = ctx.new_page()
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(BASE, wait_until="load")
    try:
        pg.wait_for_function("()=>ONB.step==='welcome' && !document.querySelector('#onbBg').hidden", timeout=15000)
    except Exception:
        pass
    pg.evaluate("()=>{ document.querySelector('#onbBg').hidden=true; S.toured=true; setLang('es'); ME_POS=[30.2671,-97.7395]; tab('home'); }")

    # Explore: Your move, with its reasons
    pg.wait_for_function("()=>Pulse.state.pick && document.querySelector('.pumove')", timeout=30000)
    pg.evaluate("()=>renderHome()"); pg.wait_for_timeout(500)
    move = pg.inner_text(".pumove")
    head = pg.evaluate("()=>[...document.querySelectorAll('.tnhead b')].map(b=>b.textContent).join(' | ')")
    check("Explore: 'Tu plan para…' and Spanish choices", "Tu plan para" in head and "Relajado" in move and "Comida" in move, [head, move[:200]])
    why = pg.evaluate("()=>[...document.querySelectorAll('.puwhy, .puplanb')].map(e=>e.textContent).join(' | ')")
    check("the pick's reasons are in Spanish", why and not ENGLISH.search(why) and re.search(r"ahora|a pie|Aquí mismo|ahí|Bien por|Sigue bien|mi\b", why), why)
    pg.screenshot(path=f"{OUT}/1-move.png")

    # a bar's card: vibe check, facts, forecast note
    bar = pg.evaluate("()=>{ const p=PL.all.filter(p=>p[2]==='bar' && p[3]).sort((a,b)=>km(ME_POS,[a[3],a[4]])-km(ME_POS,[b[3],b[4]]))[0]; return p&&p[0] }")
    pg.evaluate("id=>{ const d=document.createElement('div'); d.id='pv_'+id; document.body.appendChild(d); Pulse.card(id); }", bar)
    pg.wait_for_function("id=>{ const e=document.getElementById('pv_'+id); return e && e.querySelector('.pvl') }", arg=bar, timeout=20000)
    card = pg.inner_text(f"#pv_{bar}")
    check("vibe check card: Spanish label, facts and source line", "Ambiente" in card and "Pronóstico según" in card and not ENGLISH.search(card), card[:400])
    check("the busy-hours facts are translated", re.search(r"Más lleno|Llega antes|Más tranquilo|Última ronda", card) or "<li>" not in pg.inner_html(f"#pv_{bar}"), card[:400])
    pg.screenshot(path=f"{OUT}/2-card.png")

    # back to English: the same text as the server sent it
    pg.evaluate("()=>{ setLang('en'); renderHome(); }"); pg.wait_for_timeout(400)
    check("English still shows the server's words", "Your move" in pg.inner_text("body"))
    check("no page errors", not errors, errors[:3])
    browser.close()

bad = [n for ok, n in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} passed")
sys.exit(1 if bad else 0)
