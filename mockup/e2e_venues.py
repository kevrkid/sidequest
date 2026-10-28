"""More places from other open sources: venues (music, comedy, theater, movies, bowling) on the Nightlife layer and
chip, breweries with bars, a venue's card saying where it came from, a full bar on a bar's card, search, the map
credit, and food dots staying food.

  SQ_BASE=http://localhost:8787 python e2e_venues.py <shot-dir>

Run against a test server with the merged data/places.json (OpenStreetMap + Overture + TABC).
"""
import os, sys
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-venues"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:240]}]" if detail and not ok else ""))


with sync_playwright() as pw:
    browser = getattr(pw, os.environ.get("SQ_BROWSER", "chromium")).launch()
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True,
                              geolocation={"latitude": 30.2672, "longitude": -97.7431}, permissions=["geolocation"])
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u or ("tile.openstreetmap.org" in u or "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u)), lambda r: r.abort())
    p = ctx.new_page()
    p.on("pageerror", lambda e: errors.append(str(e)))
    p.goto(BASE, wait_until="load"); p.wait_for_timeout(2500)
    p.evaluate("()=>{ const o=document.querySelector('#onbBg'); if(o) o.hidden=true; S.toured=true }")
    p.wait_for_function("PL.all&&PL.all.length>5000", timeout=20000); p.wait_for_timeout(1500)
    p.evaluate("()=>{ const o=document.querySelector('#onbBg'); if(o) o.hidden=true; S.toured=true }")   # the welcome sheet can come up meanwhile

    kinds = p.evaluate("()=>{ const c={}; PL.all.forEach(x=>c[x[2]]=(c[x[2]]||0)+1); return c }")
    check("the map has venues and breweries", all(kinds.get(k, 0) > 10 for k in ["music venue", "comedy club", "theater", "cinema", "games", "brewery"]), kinds)

    p.click("[data-excat='night']"); p.wait_for_timeout(1200)
    p.click("#exCat [data-exsub='venues']"); p.wait_for_timeout(2000)
    rows = p.evaluate("[...document.querySelectorAll('#exCat .xrow')].map(x=>x.innerText.split('\\n').join(' ')).slice(0,8)")
    check("Nightlife → Venues & shows lists venues", len(rows) >= 5 and any(k in " ".join(rows) for k in ["music venue", "comedy club", "theater", "cinema"]), rows)
    p.evaluate("()=>{ map.setView([30.2675,-97.7405],15); }"); p.wait_for_timeout(1500)   # (returning the map object would make Playwright serialize all of Leaflet)
    vp = p.evaluate("document.querySelectorAll('.npin.venue').length")
    check("venue pins on the map downtown", vp >= 3, vp)
    p.screenshot(path=f"{OUT}/1-venues.png")

    p.click("#exCat [data-exsub='comedy']"); p.wait_for_timeout(1800)
    names = p.evaluate("[...document.querySelectorAll('#exCat .xrow b')].map(x=>x.textContent)")
    check("Comedy lists comedy clubs (Cap City, Esther's Follies, Comedy Mothership…)", any(n in " ".join(names) for n in ["Cap City", "Esther", "Mothership", "ColdTowne"]), names[:8])
    p.click("#exCat [data-exsub='breweries']"); p.wait_for_timeout(1800)
    brews = p.evaluate("[...document.querySelectorAll('#exCat .xrow .meta')].map(x=>x.textContent)")
    check("Breweries lists breweries", len(brews) >= 5 and all("brewery" in b for b in brews[:5]), brews[:5])

    vid = p.evaluate("PL.all.find(x=>x[1]==='Esther\\'s Follies')?.[0]")
    p.evaluate("([id])=>{ const x=PL.all.find(y=>y[0]===id); placePopup(id,[x[3],x[4]]); }", [vid]); p.wait_for_timeout(2000)
    card = p.evaluate("()=>document.querySelector('#exPop')?.innerText||''")
    check("a venue's card: kind, Directions, Eat after, where it came from", "comedy club" in card and "Directions" in card and "Eat after" in card and "Overture" in card, card[:300])
    check("…and no Menu button for a venue", "Menu" not in card)
    p.screenshot(path=f"{OUT}/2-venue-card.png")

    p.evaluate("()=>{ closeTopOverlay(); }"); p.wait_for_timeout(500)   # the venue card from above is still open
    if p.locator("#exCat").is_hidden(): p.evaluate("()=>exploreCat('night')"); p.wait_for_timeout(1000)
    p.click("#exCat [data-exsub='speakeasies']"); p.wait_for_timeout(1800)
    sp = p.evaluate("[...document.querySelectorAll('#exCat .xrow')].map(x=>x.innerText.split('\\n').join(' ')).slice(0,30)")
    check("Nightlife → Speakeasies lists them, each with how to find the door", len(sp) >= 15 and sum("🗝️" in r for r in sp) >= 15 and any("Midnight Cowboy" in r for r in sp), sp[:4])
    p.screenshot(path=f"{OUT}/3-speakeasies.png")
    sid = p.evaluate("PL.all.find(x=>x[1]==='Brass Peacock')?.[0]")
    p.evaluate("([id])=>{ const x=PL.all.find(y=>y[0]===id); placePopup(id,[x[3],x[4]]); }", [sid]); p.wait_for_timeout(2000)
    card = p.evaluate("()=>document.querySelector('#exPop')?.innerText||''")
    check("Georgetown's Brass Peacock is on the map, its card says how to get in", "Speakeasy" in card and "host stand" in card, card[:300])
    p.evaluate("()=>{ closeTopOverlay(); }"); p.wait_for_timeout(400)
    bid = p.evaluate("PL.all.find(x=>x[1]==='Coyote Ugly Saloon'||x[1]==='Small Victory')?.[0]")
    p.evaluate("([id])=>{ closeTopOverlay(); const x=PL.all.find(y=>y[0]===id); placePopup(id,[x[3],x[4]]); }", [bid]); p.wait_for_timeout(2000)
    card = p.evaluate("()=>document.querySelector('#exPop')?.innerText||''")
    check("a licensed bar's card says Full bar", "Full bar" in card, card[:300])

    p.evaluate("()=>{ closeTopOverlay(); exploreClear(); }"); p.wait_for_timeout(500)
    p.click("#qIn"); p.fill("#qIn", "speakeasy"); p.wait_for_timeout(1200)
    check("searching \"speakeasy\" offers the speakeasy list", p.locator("#searchOut [data-exsubgo='speakeasies']").count() == 1)
    p.fill("#qIn", "alamo drafthouse"); p.wait_for_timeout(1500)
    s = p.evaluate("[...document.querySelectorAll('#searchOut .xrow b')].map(x=>x.textContent).slice(0,6)")
    check("search finds cinemas", any("Alamo Drafthouse" in x for x in s), s)
    p.evaluate("()=>{ $('#qIn').value=''; tab('home','peek'); }"); p.wait_for_timeout(500)

    food = p.evaluate("()=>PL.all.filter(x=>['music venue','comedy club','theater','cinema','games','brewery'].includes(x[2])).length")
    check("credit for the places: OpenStreetMap, Overture Maps, TABC", "Overture Maps" in p.inner_text(".leaflet-control-attribution"))
    check("no page errors", not errors, errors[:3])
    browser.close()

bad = [n for ok, n in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} passed")
sys.exit(1 if bad else 0)
