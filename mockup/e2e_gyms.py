"""Gyms on the map: the 🏋️ Gyms chip (list + pins, by kind, open now), a gym's card with Check in, search, the Layers
sheet, and check-ins at a gym counting on the server.

  SQ_BASE=http://localhost:8787 python e2e_gyms.py <shot-dir>

Run against a test server with data/gyms.json (from fetch_gyms.rb).
"""
import os, sys
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-gyms"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:240]}]" if detail and not ok else ""))


with sync_playwright() as pw:
    browser = getattr(pw, os.environ.get("SQ_BROWSER", "chromium")).launch()
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True,
                              geolocation={"latitude": 30.2672, "longitude": -97.7431}, permissions=["geolocation"])
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u, lambda r: r.abort())
    p = ctx.new_page()
    p.on("pageerror", lambda e: errors.append(str(e)))
    p.goto(BASE, wait_until="load")
    p.evaluate("h=>fetch('/api/signup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({h,pw:'password123',adult:true,terms:true})})",
               f"gym{os.getpid() % 10000}")
    p.wait_for_timeout(800); p.reload(wait_until="load"); p.wait_for_timeout(2500)
    p.evaluate("()=>{ const o=document.querySelector('#onbBg'); if(o) o.hidden=true; S.toured=true }")

    n = p.evaluate("async()=>(await (await fetch('/api/gyms')).json()).gyms.length")
    check("the server has gyms", n > 100, n)
    check("the map starts without gym pins (calm map)", p.evaluate("!S.mapL.gyms"))

    p.click("[data-excat='gyms']"); p.wait_for_timeout(1500)
    rows = p.locator("#exCat .xrow").count()
    check("🏋️ Gyms chip lists gyms, nearest first", rows >= 10, rows)
    check("…and puts their pins on the map", p.evaluate("GYM.layer.getLayers().length") > 0)
    p.screenshot(path=f"{OUT}/1-chip.png")

    p.click("#exCat [data-exsub='climbing']"); p.wait_for_timeout(800)
    kinds = p.evaluate("[...document.querySelectorAll('#exCat .xrow .meta')].map(x=>x.textContent)")
    check("Climbing narrows the list", kinds and all("Climbing" in k for k in kinds), kinds[:3])
    check("…and the pins", p.evaluate("GYM.layer.getLayers().every(m=>m.getElement()?.textContent.includes('🧗')??true)"))

    p.click("#exCat [data-exsub='all']"); p.wait_for_timeout(500)
    first = p.evaluate("[...document.querySelectorAll('#exCat .xrow .pst')].map(x=>x.textContent)")
    check("all gyms at first, hours known or not (Open now starts off for gyms)", "Hours unknown" in first and not p.evaluate("!!S.gymOpen"), first[:4])
    p.click("#exCat [data-exopen]"); p.wait_for_timeout(800)
    opened = p.evaluate("[...document.querySelectorAll('#exCat .xrow .pst')].map(x=>x.textContent)")
    check("Open now shows only open ones", opened and all(t == "Open now" for t in opened), opened[:4])
    p.click("#exCat [data-exopen]"); p.wait_for_timeout(500)
    check("…and off again shows them all", "Hours unknown" in p.evaluate("[...document.querySelectorAll('#exCat .xrow .pst')].map(x=>x.textContent)"))

    p.locator("#exCat .xrow").first.click(); p.wait_for_timeout(1500)
    card = p.evaluate("()=>document.querySelector('#exPop')?.innerText||''")
    check("tapping one opens its card: kind, Directions, Check in", "Directions" in card and "Check in" in card and "OpenStreetMap" in card, card[:200])
    p.screenshot(path=f"{OUT}/2-card.png")

    gid = p.evaluate("GYM.list.find(g=>g.kind==='rink').id")
    r = p.evaluate("async id=>{ const r=await fetch('/api/checkin',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({k:'gym',id})}); return [r.status, await r.json()]; }", gid)
    check("checking in at a gym counts (server knows gyms)", r[0] == 200 and r[1].get("ok"), r)
    r = p.evaluate("async()=>{ const r=await fetch('/api/checkin',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({k:'gym',id:'gyNOPE'})}); return r.status; }")
    check("…but not at a made-up one", r == 400, r)

    p.evaluate("()=>{ closeTopOverlay(); exploreClear(); }"); p.wait_for_timeout(400)
    p.click("#qIn"); p.fill("#qIn", "bouldering"); p.wait_for_timeout(1500)
    s = p.evaluate("[...document.querySelectorAll('#searchOut [data-xgo^=\"gym|\"]')].length")
    p.fill("#qIn", "rink"); p.wait_for_timeout(800)
    s2 = p.evaluate("[...document.querySelectorAll('#searchOut [data-xgo^=\"gym|\"]')].map(x=>x.innerText.split('\\n')[0])")
    check("search finds gyms by kind (bouldering, rink)", s >= 1 and len(s2) >= 1, [s, s2])
    p.locator("#searchOut [data-xgo^='gym|']").first.click(); p.wait_for_timeout(1500)
    check("a search result opens the gym on the map", "Directions" in p.evaluate("()=>document.querySelector('#exPop')?.innerText||''") and p.evaluate("S.mapL.gyms"))

    p.evaluate("()=>openMapLayers()"); p.wait_for_timeout(500)
    check("Layers sheet has Gyms & fitness", "Gyms & fitness" in p.inner_text("#placesSheet"))
    p.evaluate("()=>{ $('#placesBg').hidden=true }")

    check("no page errors", not errors, errors[:3])
    browser.close()

bad = [n for ok, n in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} passed")
sys.exit(1 if bad else 0)
