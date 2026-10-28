"""About you: Music & interests first, pick-many questions with your own words, written lists, old pick-one answers
kept, and matching on any shared answer (your own words too). Also: You → About you opens straight to it.

  SQ_BASE=http://localhost:8787 python e2e_about.py <shot-dir>
"""
import os, sys, json
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-about"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:240]}]" if detail and not ok else ""))


with sync_playwright() as pw:
    browser = getattr(pw, os.environ.get("SQ_BROWSER", "chromium")).launch()
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True)
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u or ("tile.openstreetmap.org" in u or "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u)), lambda r: r.abort())
    p = ctx.new_page()
    p.on("pageerror", lambda e: errors.append(str(e)))
    p.goto(BASE, wait_until="load")
    h = f"about{os.getpid() % 10000}"
    p.evaluate("h=>fetch('/api/signup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({h,pw:'password123',adult:true,terms:true})})", h)
    p.wait_for_timeout(800)
    # an answer saved before these became pick-many (a plain string) must survive the reload
    p.evaluate("()=>{ S.me.p.groupSize='Small group'; S.me.p.weekend='Up early, outdoors'; save(); }")
    p.reload(wait_until="load"); p.wait_for_timeout(2500)
    try:   # the app shows a guest the welcome sheet once /api/state is back (slower on a cold server): wait for it, then hide it
        p.wait_for_function("()=>(typeof AUTHED!=='undefined'&&AUTHED)||S.welcomed||(ONB.step==='welcome'&&!document.querySelector('#onbBg').hidden)", timeout=15000)
    except Exception:
        pass
    p.evaluate("()=>{ const o=document.querySelector('#onbBg'); if(o) o.hidden=true; S.toured=true }")
    got = p.evaluate("JSON.stringify([S.me.p.groupSize,S.me.p.weekend])")
    check("old pick-one answers become lists, nothing lost", json.loads(got) == [["Small group"], ["Up early, outdoors"]], got)

    p.click("[data-dock='me']"); p.wait_for_timeout(400)
    p.click("#youList [data-yedit='about']"); p.wait_for_timeout(400)
    check("You → About you opens straight to it", p.locator("[data-mepane='about']").is_visible() and p.locator("#youList").is_hidden())
    first = p.locator("#lifeCard [data-lifesec]").first.inner_text()
    check("Music & interests is the first section, and it's open", "Music & interests" in first and p.locator("[data-life='music']").count() > 20, first)

    p.click("[data-life='music'][data-opt='Hip-hop']"); p.click("[data-life='music'][data-opt='Tejano']")
    p.click("[data-life='sportsPlay'][data-opt='Pickleball']")
    check("pick as many as you like", p.evaluate("S.me.p.music") == ["Hip-hop", "Tejano"], p.evaluate("S.me.p.music"))
    check("pick-many questions say so", p.locator("#lifeCard >> text=Pick as many as you like").count() >= 5)

    own = "[data-lifeown='hobbies']"
    p.fill(own, "  Pottery   class "); p.press(own, "Enter"); p.wait_for_timeout(200)
    p.fill(own, "board GAMES"); p.press(own, "Enter"); p.wait_for_timeout(200)   # matches the built-in option
    hob = p.evaluate("S.me.p.hobbies")
    check("your own words are added (trimmed), and typing a listed one picks it", hob == ["Pottery class", "Board games"], hob)
    check("your own answer shows as a chip you can remove", p.locator("[data-life='hobbies'][data-opt='Pottery class']").count() == 1)
    p.click("[data-life='hobbies'][data-opt='Pottery class']")
    check("tapping it removes it", p.evaluate("S.me.p.hobbies") == ["Board games"])
    p.fill(own, "Pottery class"); p.press(own, "Enter"); p.wait_for_timeout(200)

    p.fill("[data-lifetext='artists']", "Leon Bridges, Bad Bunny; Willie Nelson")
    p.dispatch_event("[data-lifetext='artists']", "change")
    p.screenshot(path=f"{OUT}/about-taste.png", full_page=False)
    p.click("[data-lifesec='values']"); p.wait_for_timeout(300)
    p.click("[data-life='groupSize'][data-opt='One-on-one']")
    check("a converted question takes a second pick", p.evaluate("S.me.p.groupSize") == ["Small group", "One-on-one"], p.evaluate("S.me.p.groupSize"))
    p.screenshot(path=f"{OUT}/about-values.png", full_page=False)

    # matching: shared picks, shared own words, a shared artist from a written list; partial words don't count
    m = p.evaluate("""()=>{ const u={h:'pal', i:[], t:null, haunts:[], p:{music:['tejano','Rock'], hobbies:['pottery CLASS'],
        artists:'bad bunny / Taylor Swift', groupSize:'One-on-one', sportsPlay:['Pickleball'], weekend:['Couch & games']}};
      const a=matchPerson(u); const b=matchPerson({h:'no', i:[], t:null, haunts:[], p:{artists:'Bad', hobbies:['Pottery']}});
      return {r:a.r, s:a.s, r2:b.r}; }""")
    want = ["Both love Tejano", "Both into pottery class", "Both have Bad Bunny on repeat", "Both like one-on-one hangouts", "Both play pickleball"]
    check("matching uses shared picks, your own words and written lists", all(any(w in x for x in m["r"]) for w in want), m["r"])
    check("no match on part of a word (\"Bad\", \"Pottery\") or a different answer (Rock, Saturday)",
          m["r2"] == [] and not any("Rock" in x or "Saturday" in x for x in m["r"]), m)

    # the server keeps answers bounded
    r = p.evaluate("""async()=>{ const big={}; for(let i=0;i<120;i++) big['k'+i]=Array(90).fill('x'.repeat(500));
      const res=await fetch('/api/profile',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({public:{}, match:big})});
      const me=await (await fetch('/api/me')).json(); const pr=me.profile||{}; const ks=Object.keys(pr);
      return {ok:res.ok, keys:ks.length, items:ks.length?pr[ks[0]].length:0, len:ks.length?pr[ks[0]][0].length:0}; }""")
    check("server caps answers (80 keys, 60 items, 200 characters)", r["ok"] and r["keys"] == 80 and r["items"] == 60 and r["len"] == 200, r)

    check("no page errors", not errors, errors[:3])
    browser.close()

bad = [n for ok, n in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} passed")
sys.exit(1 if bad else 0)
