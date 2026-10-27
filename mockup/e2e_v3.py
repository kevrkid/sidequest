"""V3 shell: the map is the app. Checks the drawer (stops, drag, flick), the chips (map + list together, ✕ puts the
map back), the one search box, back, the dock, You, Scout's tour targets and the desktop panel.

  SQ_BASE=http://localhost:8796 python e2e_v3.py <shot-dir>
  SQ_BROWSER=webkit ...                  # the same in WebKit (Safari's engine)

Run against a test server (test_places.json etc., empty data) like e2e_test.py.
"""
import os, sys, json
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-v3"
os.makedirs(OUT, exist_ok=True)
results, errors = [], []


TOUCH = [True]


def drag(page, *a):
    """Touch-drag; False (and the checks that need it are skipped) where the browser can't fake touches."""
    TOUCH[0] = page.evaluate(DRAG, list(a)) is not False
    return TOUCH[0]


def tcheck(name, ok, detail=""):
    if TOUCH[0]:
        check(name, ok, detail)
    else:
        print("SKIP " + name + "  (no synthetic touch in this browser)")


def check(name, ok, detail=""):
    results.append((bool(ok), name, str(detail)[:200]))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail and not ok else ""))


DRAG = """([sel,y1,y2,steps,ms])=>new Promise(ok=>{ try{ new Touch({identifier:1,target:document.body}); }catch(e){ return ok(false); }   // WebKit: no synthetic touches
  const el=document.querySelector(sel), r=el.getBoundingClientRect(), x=r.left+r.width/2;
  const mk=(type,y)=>{ const t=new Touch({identifier:7,target:el,clientX:x,clientY:y}); el.dispatchEvent(new TouchEvent(type,{touches:type==='touchend'?[]:[t],changedTouches:[t],bubbles:true,cancelable:true})); };
  mk('touchstart',y1); let i=0; const tm=setInterval(()=>{ i++; mk('touchmove',y1+(y2-y1)*i/steps); if(i>=steps){ clearInterval(tm); mk('touchend',y2); setTimeout(()=>ok(true),450); } }, ms); })"""


def user(browser, w=390, h=844):
    ctx = browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=2, has_touch=True,
                              geolocation={"latitude": 30.2671, "longitude": -97.7395}, permissions=["geolocation"])
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u, lambda r: r.abort())
    pg = ctx.new_page()
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(BASE, wait_until="load")
    pg.evaluate("h=>fetch('/api/signup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({h,pw:'password123',adult:true,terms:true})})",
                f"v3t{w}{os.getpid() % 1000}")
    pg.wait_for_timeout(800); pg.reload(wait_until="load"); pg.wait_for_timeout(2500)
    pg.evaluate("()=>{ document.querySelector('#onbBg').hidden=true; S.toured=true; return 1 }")
    return ctx, pg


with sync_playwright() as pw:
    browser = getattr(pw, os.environ.get("SQ_BROWSER", "chromium")).launch()
    ctx, p = user(browser)
    at = lambda: p.evaluate("[curTab, DRW.at]")

    # the first screen: the map, the drawer down, five buttons
    check("opens on the map with the drawer down", at() == ["home", "peek"] and p.locator("#map").is_visible())
    check("members get no avatar at the top (You is in the dock); the map keeps just layers + locate",
          p.locator("#meChip").is_hidden() and p.eval_on_selector_all(".mapctl button", "b=>b.length") == 2)
    check("dock: Explore · For you · ＋ · Chats · You", p.eval_on_selector_all("#dock [data-dock]", "b=>b.map(x=>x.dataset.dock)") == ["home", "feed", "create", "meet", "me"])
    check("map starts calm: no food dots, nightlife or hot spot zones", p.evaluate("!S.mapL.food&&!S.mapL.clubs&&!S.mapL.bars&&!S.mapL.zones&&S.mapL.events"))
    p.wait_for_function("EV.loaded", timeout=20000); p.wait_for_timeout(300)
    check("the glance line says what's on tonight", "on tonight" in p.inner_text("#glance"), p.inner_text("#glance"))
    p.screenshot(path=f"{OUT}/v3-01-peek.png")

    # drag and flick
    drag(p, "#drawer .dhead", 700, 250, 12, 25)
    tcheck("drag the top up: the drawer opens", at()[1] == "full", at())
    drag(p, "#drawer .dgrab", 120, 140, 2, 20)
    tcheck("a quick nudge (20 px) doesn't move it to another stop", at()[1] == "full", at())
    drag(p, "#v-home", 200, 330, 3, 16)
    tcheck("flick down from the top of the list: it comes down a stop", at()[1] in ("half", "peek"), at())
    p.evaluate("setDrawer('half')"); p.wait_for_timeout(350)
    drag(p, "#v-home", 520, 470, 3, 16)
    tcheck("at half, pushing the list up opens it all the way", at()[1] == "full", at())
    p.evaluate("setDrawer('half')"); p.wait_for_timeout(350)
    p.evaluate("map.fire('dragstart')"); p.wait_for_timeout(350)
    check("moving the map drops the drawer out of the way", at()[1] == "peek", at())
    vis = p.evaluate("parseFloat(getComputedStyle(document.querySelector('#app')).getPropertyValue('--dvis'))")
    sc = p.evaluate("innerHeight-document.querySelector('#scoutBtn').getBoundingClientRect().bottom")
    check("Scout rides just above the drawer", 0 < sc - vis < 30, f"dvis {vis}, scout bottom gap {sc}")

    # chips: one thing on the map and in the list
    p.click("#mapChips [data-excat='food']"); p.wait_for_selector("#exCat .xrow", timeout=10000)
    check("Food chip: list in the drawer, half way up", at() == ["home", "half"] and p.locator("#exCat .xrow").count() >= 2)
    check("…and only food on the map", p.evaluate("S.mapL.food&&!S.mapL.events&&!S.mapL.friendlocs"))
    p.click("#exCat [data-exsub='tacos']"); p.wait_for_timeout(900)
    check("sub-chip narrows it (tacos)", "Taco Test Trailer" in p.inner_text("#exCat"), p.inner_text("#exCat")[:120])
    p.screenshot(path=f"{OUT}/v3-02-food.png")
    p.click("#mapChips [data-excat='events']"); p.wait_for_timeout(500)
    check("switching chips swaps the map and the list", p.evaluate("EXC.k==='events'&&S.mapL.events&&!S.mapL.food") and p.locator("#exCat [data-exsub='weekend']").count() == 1)
    p.click("#mapChips [data-excat='zones']"); p.wait_for_selector("#exCat [data-exsub='rainey']", timeout=10000)
    p.click("#exCat .subchips [data-exsub='rainey']"); p.wait_for_selector("#exCat .xrow[data-xgo]", timeout=10000); p.wait_for_timeout(900)
    c = p.evaluate("[map.getCenter().lat, map.getCenter().lng]")
    check("Hot spots → Rainey Street: the map flies there and lists its spots", "Taco Test Trailer" in p.inner_text("#exCat") and abs(c[0]-30.26) < .02, f"{c} {p.inner_text('#exCat')[:120]}")
    p.evaluate("goBack()"); p.wait_for_timeout(300)
    check("back closes the chip and puts the map back", p.evaluate("!EXC.k&&S.mapL.events&&S.mapL.friendlocs&&!S.mapL.food"))

    # search
    p.click("#qIn"); p.wait_for_timeout(300)
    check("tapping search opens it full, with a back arrow and ideas", at() == ["search", "full"] and p.locator("[data-qback]").is_visible() and "Ask Scout" in p.inner_text("#searchOut"))
    p.fill("#qIn", "taco"); p.wait_for_timeout(400)
    out = p.inner_text("#searchOut").upper()
    check("typing finds places, nearest first, plus menus and Scout", "PLACES" in out and "TACO TEST TRAILER" in out and "ON MENUS" in out, out[:160])
    p.locator("#qIn").press("End"); p.keyboard.type("x"); p.wait_for_timeout(200)
    p.click("[data-qclear]"); p.wait_for_timeout(300)
    check("the ✕ in the box clears it and shows the ideas again", p.input_value("#qIn") == "" and "Ask Scout anything" in p.inner_text("#searchOut"))
    p.fill("#qIn", "where should i get tacos tonight?"); p.wait_for_timeout(300)
    check("a question puts Ask Scout first", p.locator("#searchOut > :first-child").get_attribute("data-xgo", timeout=2000).startswith("scout|"))
    p.fill("#qIn", "taco"); p.wait_for_timeout(300)
    p.click("#searchOut [data-xgo^='pl|']"); p.wait_for_timeout(900)
    check("a place result flies there; its card opens in the drawer (not a bubble on the map)",
          at() == ["home", "half"] and "Taco Test Trailer" in p.inner_text("#exPop") and p.locator("#exPop [data-pmenu]").count() == 1
          and p.locator(".leaflet-popup.indrawer").count() == 1 and p.locator(".popring").count() == 1)
    p.screenshot(path=f"{OUT}/v3-02b-card.png")
    check("recent searches are remembered", p.evaluate("(S.recentQ||[])[0]") == "taco")
    p.evaluate("goBack()"); p.wait_for_timeout(500)
    check("back closes the card first, and the drawer goes back down", p.locator(".leaflet-popup").count() == 0 and p.locator("#exPop").is_hidden() and at()[1] == "peek",
          [p.locator(".leaflet-popup").count(), p.locator("#exPop").is_hidden(), at()])

    # press and hold the map: what's here, flare here
    p.evaluate("()=>{ map.setView([30.2592,-97.7389],17); map.fire('contextmenu',{latlng:L.latLng(30.2592,-97.7389)}); return 1 }"); p.wait_for_timeout(500)
    check("press and hold the map: a card with what's near and Flare here", "Near" in p.inner_text("#exPop") and p.locator("#exPop [data-holdflare]").count() == 1, p.inner_text("#exPop")[:80])
    p.click("#exPop [data-holdflare]"); p.wait_for_timeout(500)
    check("…Flare here opens the composer with that place", p.locator("#sheetBg").is_visible() and p.evaluate("!!CF.place&&!!CF.place.name"))
    p.evaluate("closeTopOverlay()")

    # dock: For you, Chats, You, ＋
    p.click("[data-dock='feed']"); p.wait_for_timeout(300)
    check("For you opens the feed full height; the search box steps aside", at() == ["feed", "full"] and not p.locator("#qIn").is_visible())
    drag(p, "#v-feed", 160, 700, 10, 20)
    tcheck("pulling a screen down shows the map again", at()[0] == "home", at())
    p.click("[data-dock='meet']"); p.wait_for_timeout(300)
    check("Chats opens on messages, tabs Messages · Friends · Groups · Meet",
          p.evaluate("meetTab") == "msgs" and p.eval_on_selector_all("#meetTabs [data-mt]", "b=>b.map(x=>x.dataset.mt)") == ["msgs", "friends", "groups", "swipe"])
    p.evaluate("openThread('riff_raff_rae')"); p.wait_for_timeout(600)
    box = p.locator("#dmIn").bounding_box(); dock = p.locator("#dock").bounding_box()
    check("an open chat fills the drawer, the box just above the dock", 0 <= dock["y"] - (box["y"] + box["height"]) < 40, f"{box} {dock}")
    p.click("[data-dock='me']"); p.wait_for_timeout(300)
    rows = p.locator("#youList").inner_text()
    check("You: online switch, stats, and plans / saved / quests / invite / sharing / edit / settings", p.locator("#presBtn").is_visible()
          and all(x in rows for x in ["My plans", "Saved", "Quests", "Invite", "On friends' maps", "Edit profile", "Settings"]) and "friends" in p.inner_text("#youStats")
          and p.locator("#meTabs").is_hidden())
    p.click("#youList [data-yedit='profile']"); p.wait_for_timeout(300)
    check("You → Edit profile shows the profile tabs", p.locator("#meTabs").is_visible())
    p.click("#youList [data-menu='quests']"); p.wait_for_selector("#questSheet .lvlcard", timeout=8000)
    check("You → Quests opens the quests", p.locator("#questBg").is_visible())
    p.evaluate("closeTopOverlay()")
    p.click("[data-dock='create']")
    check("＋ opens Create: story, post, flare, event, group, live",
          p.eval_on_selector_all("#createBg [data-create]", "b=>b.map(x=>x.dataset.create)") == ["story", "post", "flare", "event", "group", "live"])
    p.click("[data-create='post']"); p.wait_for_timeout(500)
    check("Create → Post lands on the posts composer", at()[0] == "feed" and p.evaluate("FEED_MODE.m") == "posts" and p.locator("#wText").is_visible())
    p.click("#logo"); p.wait_for_timeout(300)
    check("the name at the top goes back to the map", at() == ["home", "peek"])

    # Scout's tour points at things that exist
    missing = p.evaluate("SC_TOUR.map(t=>t[0]).filter(id=>!document.querySelector(SC_T[id][0]))")
    check("every tour stop points at something on screen", missing == [], missing)
    p.evaluate("scoutTour(1)"); p.wait_for_timeout(700)
    check("the tour can point at the chips without moving the screen", p.evaluate("document.querySelector('#app').scrollTop") == 0 and p.locator("#scoutRing").is_visible())
    p.evaluate("scoutTourEnd()")
    ctx.close()

    # a computer: map across the window, the drawer a panel on the left
    ctx, p = user(browser, 1400, 860)
    box = p.locator("#drawer").bounding_box()
    check("desktop: the drawer is a panel on the left, always open", box["x"] < 30 and 380 < box["width"] < 460 and p.evaluate("DRW.at") == "full")
    p.click("#mapChips [data-excat='food']"); p.wait_for_selector("#exCat .xrow", timeout=10000)
    check("desktop: chips list in the panel", p.locator("#exCat .xrow").first.is_visible())
    p.screenshot(path=f"{OUT}/v3-03-desktop.png")
    ctx.close()
    browser.close()

check("no page errors", not errors, errors[:3])
n = sum(ok for ok, _, _ in results)
print(f"{n}/{len(results)} passed")
sys.exit(0 if n == len(results) else 1)
