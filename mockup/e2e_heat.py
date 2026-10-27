"""Heat map and hot spots: always on the map (whatever chip or layers are picked), the vibe check on place cards,
and Sign in with Google paused (no button).

  SQ_BASE=http://localhost:8851 python e2e_heat.py <shot-dir>

Run against a test server with real places (data/places.json) so the heat map has something to show.
"""
import os, sys
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-heat"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:200]}]" if detail and not ok else ""))


HEAT_STATE = """()=>({rows:HEAT.rows.length, live:HEAT.rows.filter(p=>p.live).length,
  drawn:HEAT.layer?HEAT.layer.getLayers().length:0, badges:HEAT.badges?HEAT.badges.getLayers().length:0,
  zones:PL.zones?PL.zones.getLayers().length:0, pane:!!document.querySelector('.leaflet-heat-pane canvas'),
  pe:getComputedStyle(document.querySelector('.leaflet-heat-pane')).pointerEvents})"""

with sync_playwright() as pw:
    browser = getattr(pw, os.environ.get("SQ_BROWSER", "chromium")).launch()
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True,
                              geolocation={"latitude": 30.2671, "longitude": -97.7395}, permissions=["geolocation"])
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u, lambda r: r.abort())
    pg = ctx.new_page()
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.on("console", lambda m: m.type == "error" and "Failed to load resource" not in m.text and errors.append(m.text))
    pg.goto(BASE, wait_until="load"); pg.wait_for_timeout(2500)
    pg.evaluate("()=>{ const o=document.querySelector('#onbBg'); if(o) o.hidden=true; S.toured=true; return 1 }")
    pg.evaluate("()=>{ tab('map'); map.setView([30.2675,-97.7405],14); }"); pg.wait_for_timeout(2500)

    st = pg.evaluate(HEAT_STATE)
    check("heat map loads for a guest and draws glows", st["rows"] > 0 and st["drawn"] > 0 and st["pane"], st)
    check("the heat canvas never takes taps meant for the map", st["pe"] == "none", st)
    check("hot spot zones show from the start (the calm V3 map no longer hides them)", st["zones"] > 0, st)
    pg.screenshot(path=f"{OUT}/1-map.png")

    pg.click('[data-excat="food"]'); pg.wait_for_timeout(1500)
    st = pg.evaluate(HEAT_STATE)
    check("with the Food chip on, heat and hot spots still show", st["drawn"] > 0 and st["zones"] > 0, st)
    pg.screenshot(path=f"{OUT}/2-food-chip.png")
    pg.click('[data-excat="food"]'); pg.wait_for_timeout(800)

    pg.evaluate("()=>{ S.mapL.zones=false; S.mapL.heat=false; refreshMapLayers(); }"); pg.wait_for_timeout(800)
    st = pg.evaluate(HEAT_STATE)
    check("old 'off' switches can't hide them", st["drawn"] > 0 and st["zones"] > 0, st)

    pg.evaluate("()=>openMapLayers()"); pg.wait_for_timeout(500)
    txt = pg.inner_text("#placesSheet")
    check("Layers sheet: hot spots & heat say Always on (no switch)", "Always on" in txt and "Hot spots & heat" in txt, txt[:300])
    pg.screenshot(path=f"{OUT}/3-layers.png")
    pg.evaluate("()=>{ $('#placesBg').hidden=true }")

    pid = pg.evaluate("()=>HEAT.rows[0]&&HEAT.rows[0].id")
    pg.evaluate("([id,ll])=>placePopup(id,ll)", [pid, pg.evaluate("()=>[HEAT.rows[0].lat,HEAT.rows[0].lng]")])
    pg.wait_for_timeout(2500)
    card = pg.evaluate("()=>{ const e=document.querySelector('#exPop .pvibe'); return e?e.innerText:'' }")
    check("tapping a hot place shows its vibe check", "Vibe check" in card, card[:200])
    pg.screenshot(path=f"{OUT}/4-vibe-card.png")

    pg.evaluate("()=>{ closeTopOverlay&&closeTopOverlay(); needAccount('post'); }"); pg.wait_for_timeout(1200)
    check("sign-up sheet has no Google button while it's paused", pg.evaluate("()=>!document.querySelector('#gsiBtn')"))
    pg.screenshot(path=f"{OUT}/5-signup.png")

    check("no page errors", not errors, errors[:3])
    browser.close()

bad = [n for ok, n in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} passed")
sys.exit(1 if bad else 0)
