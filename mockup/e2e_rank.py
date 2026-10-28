"""🏆 Best of Austin: Explore's row, the chip, the sheet (groups, lists, sort, New to me, why + sources), the guest gate,
ratings and "would go back", suggestions, sharing, Map, back, deep links (/r/<list>, /?rank=). Needs data/rankings.json
(fetch_rankings.rb) with at least the pizza list.

  SQ_BASE=http://localhost:8783 python e2e_rank.py <shot-dir>
"""
import os, sys, json, time
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-rank"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:240]}]" if detail and not ok else ""))


def until(pg, js, secs=15):
    t = time.time()
    while time.time() - t < secs:
        if pg.evaluate(js):
            return True
        pg.wait_for_timeout(150)
    return False


with sync_playwright() as p:
    b = p.chromium.launch()
    for vw in (390, 360):
        ctx = b.new_context(viewport={"width": vw, "height": 844}, device_scale_factor=2, geolocation={"latitude": 30.2672, "longitude": -97.7431}, permissions=["geolocation"])
        ctx.route(lambda u: ("tile.openstreetmap.org" in u or "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u)), lambda r: r.abort())   # nothing from other sites: map tiles, event posters (slow sites stall the load event)
        pg = ctx.new_page()
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.on("console", lambda m: m.type == "error" and "Failed to load resource" not in m.text and errors.append(m.text))
        pg.goto(BASE, wait_until="load")
        # the welcome steps can come up on their own a moment later: keep them out of the way (except to check the gate)
        pg.evaluate("()=>{ S.toured=true; const o=document.querySelector('#onbBg'); o.hidden=true; new MutationObserver(()=>{ if(!o.hidden&&!window.__gate) o.hidden=true; }).observe(o,{attributes:true}); }")
        if vw == 360:   # the narrow phone: just the look of the sheet
            pg.evaluate("openRankings('cocktails')"); until(pg, "document.querySelectorAll('#rankSheet .rkc').length>2", 20)
            pg.wait_for_timeout(400); pg.screenshot(path=f"{OUT}/rank-360.png")
            check("360 px: nothing wider than the screen", pg.evaluate("document.querySelector('#rankSheet').scrollWidth<=document.querySelector('#rankSheet').clientWidth+1"))
            ctx.close(); continue
        # Explore: a row of lists
        ok = until(pg, "document.querySelectorAll('#exBest .rkcard').length>=3", 20)
        check("Explore shows a Best of Austin row", ok, pg.inner_text("#exBest") if ok else "")
        check("each card names its #1", pg.evaluate("[...document.querySelectorAll('#exBest .rkcard')].every(c=>c.textContent.includes('#1'))"))
        pg.evaluate("document.querySelector('#exBest').scrollIntoView()"); pg.wait_for_timeout(300)
        pg.screenshot(path=f"{OUT}/rank-1-explore.png")
        # the chip opens the sheet
        pg.click("[data-excat=best]")
        check("🏆 chip opens the sheet", until(pg, "!document.querySelector('#rankBg').hidden && document.querySelectorAll('#rankSheet .rkc').length>=3", 20))
        check("the map's layers didn't change (it isn't a map chip)", pg.evaluate("!EXC.k"))
        # pizza
        pg.click("[data-rkgroup=food]"); pg.wait_for_timeout(200); pg.click("[data-rkcat=pizza]")
        until(pg, "document.querySelector('#rankSheet .rkc .rkh b')?.textContent && Rank._R.list?.k==='pizza'", 15)
        names = pg.evaluate("[...document.querySelectorAll('#rankSheet .rkc .rkh b:not(.x)')].map(b=>b.textContent).filter(t=>!/^\\d+$/.test(t))")
        check("pizza list, best first", len(names) >= 5, names[:5])
        scores = pg.evaluate("[...document.querySelectorAll('#rankSheet .rks b')].map(b=>+b.textContent)")
        check("scores go down the list", scores == sorted(scores, reverse=True) and scores[0] <= 100, scores)
        check("every spot shows its reasons", pg.evaluate("[...document.querySelectorAll('#rankSheet .rkc')].every(c=>c.querySelector('.rktag:not(.new):not(.been):not(.why)'))"))
        check("#1 has what to order", pg.evaluate("!!document.querySelector('#rankSheet .rkc .rko')"))
        pg.click("#rankSheet .rkc details.rkwhy summary"); pg.wait_for_timeout(200)
        links = pg.evaluate("[...document.querySelectorAll('#rankSheet .rkc details[open] a')].map(a=>a.href)")
        check("Why it ranks here: the sources, as links", len(links) >= 1 and all(l.startswith("http") for l in links), links[:3])
        pg.screenshot(path=f"{OUT}/rank-2-pizza.png")
        # sort / filters
        pg.click("[data-rksort=near]"); pg.wait_for_timeout(200)
        mi = pg.evaluate("Rank._R.list.items.filter(x=>x.mi!=null).length")
        shown = pg.evaluate("document.querySelectorAll('#rankSheet .rkc').length")
        check("Near me: only spots with a place, nearest first", shown == mi and mi > 0, f"{shown} vs {mi}")
        pg.click("[data-rksort=top]"); pg.wait_for_timeout(150)
        pg.click("[data-rkfresh]"); pg.wait_for_timeout(150)
        check("New to me (nothing visited yet): the whole list", pg.evaluate("document.querySelectorAll('#rankSheet .rkc').length") == len(names))
        pg.click("[data-rkfresh]")
        # guests can't rate
        pg.evaluate("window.__gate=true"); pg.click("#rankSheet .rkc [data-rkrate]"); pg.wait_for_timeout(300)
        check("a guest who taps Rate gets the sign-up gate", pg.evaluate("!document.querySelector('#onbBg').hidden"))
        pg.evaluate("window.__gate=false; document.querySelector('#onbBg').hidden=true")
        # back closes it
        pg.evaluate("closeTopOverlay()"); pg.wait_for_timeout(150)
        check("back closes the sheet", pg.evaluate("document.querySelector('#rankBg').hidden"))
        # sign up, then a deep link straight to a list
        pg.evaluate("h=>fetch('/api/signup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({h,pw:'password123',adult:true,terms:true})})", "rank" + str(int(time.time()) % 100000))
        pg.goto(BASE + "/?rank=pizza", wait_until="load")
        pg.evaluate("()=>{ S.toured=true; const o=document.querySelector('#onbBg'); o.hidden=true; new MutationObserver(()=>{ if(!o.hidden&&!window.__gate) o.hidden=true; }).observe(o,{attributes:true}); }")
        check("/?rank=pizza opens that list", until(pg, "!document.querySelector('#rankBg').hidden && Rank._R.list?.k==='pizza' && document.querySelectorAll('#rankSheet .rkc').length>2", 20))
        first = pg.evaluate("Rank._R.list.items[0].id")
        pg.click(f"[data-rkrate='{first}']"); pg.wait_for_timeout(200)
        check("Rate opens the stars", pg.evaluate("!!document.querySelector('.rkrate')"))
        pg.click(f"[data-rkstar='{first}|4']")
        until(pg, "Rank._R.list.items[0].mine?.stars===4", 8)
        v = pg.evaluate("Rank._R.list.items[0].votes")
        check("4 stars saved: 1 rating, average 4", v.get("n") == 1 and v.get("avg") == 4, v)
        pg.click(f"[data-rkback='{first}|1']"); until(pg, "Rank._R.list.items[0].mine?.back===true", 8)
        check("would go back: yes", pg.evaluate("Rank._R.list.items[0].votes.back") == 1)
        pg.screenshot(path=f"{OUT}/rank-3-rated.png")
        j = pg.evaluate(f"fetch('/api/rankings/cat?k=pizza').then(r=>r.json()).then(j=>j.items.find(x=>x.id==='{first}'))")
        check("the server counts it (reasons say so)", any("Side Quest" in r for r in j["reasons"]) and j["mine"]["stars"] == 4, j["reasons"])
        pg.click(f"[data-rkstar='{first}|0']"); until(pg, "!Rank._R.list.items[0].mine", 8)
        check("take my rating back", pg.evaluate("Rank._R.list.items[0].votes.n") == 0)
        # suggest a spot
        pg.evaluate("document.querySelector('[data-rksugbox]').open=true")
        pg.fill("#rkSugName", "Test Pizza Truck"); pg.fill("#rkSugWhy", "the vodka slice"); pg.click("[data-rksug]")
        check("suggestion sent", until(pg, "document.body.innerText.includes('look into Test Pizza Truck')", 6))
        # share: a link to /r/pizza
        pg.evaluate("window.__shared=null; navigator.share=d=>{ window.__shared=d; return Promise.resolve(); }")
        pg.click("[data-rkshare=pizza]"); pg.wait_for_timeout(200)
        sh = pg.evaluate("window.__shared")
        check("share the list: /r/pizza with the top 3", sh and sh["url"].endswith("/r/pizza") and "#1" in sh["text"], sh)
        r = pg.evaluate("fetch('/r/pizza').then(r=>r.text())")
        check("/r/pizza has a preview and opens the app on the list", 'og:title' in r and '/?rank=pizza' in r)
        # Map: closes the sheet, the place's card in the drawer
        withp = pg.evaluate("Rank._R.list.items.find(x=>x.place)?.id")
        pg.click(f"[data-rkmap='{withp}']")
        check("Map: sheet closes, the place's card opens", until(pg, "document.querySelector('#rankBg').hidden && document.querySelector('#exPop') && !document.querySelector('#exPop').hidden && document.querySelector('#exPop').textContent.length>10", 10))
        pg.screenshot(path=f"{OUT}/rank-4-map.png")
        # the DJ list, when it's been researched: weekly nights
        if pg.evaluate("fetch('/api/rankings').then(r=>r.json()).then(j=>j.groups.some(g=>g.cats.some(c=>c.k==='dj_nights')))"):
            pg.evaluate("openRankings('dj_nights')")
            until(pg, "Rank._R.list?.k==='dj_nights' && document.querySelectorAll('#rankSheet .rkc').length>2", 15)
            check("DJ nights: a weekly schedule", pg.evaluate("document.querySelectorAll('#rankSheet .rknight').length") >= 1)
            pg.screenshot(path=f"{OUT}/rank-5-dj.png")
        ctx.close()
    b.close()
print("errors:", errors[:5])
print(f"{sum(r[0] for r in results)} / {len(results)}")
