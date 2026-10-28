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
    check("dock: Explore · Feed · ＋ · Social · You", p.eval_on_selector_all("#dock [data-dock]", "b=>b.map(x=>x.dataset.dock)") == ["home", "feed", "create", "meet", "me"]
          and p.inner_text("#dock [data-dock='feed']").strip() == "Feed" and p.inner_text("#dock [data-dock='meet']").strip() == "Social")
    check("map starts calm: no food dots or nightlife (hot spots and heat are always on)", p.evaluate("!S.mapL.food&&!S.mapL.clubs&&!S.mapL.bars&&S.mapL.events"))
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

    # dock: Feed, Social, You, ＋
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
    check("You: online switch, stats, profile / personality / about you / privacy first, then plans / saved / quests / invite / sharing",
          p.locator("#presBtn").is_visible()
          and all(x in rows for x in ["Profile", "Personality", "About you", "Privacy", "My plans", "Saved", "Quests", "Invite", "On friends' maps"])
          and rows.index("Profile") < rows.index("My plans") and "friends" in p.inner_text("#youStats") and p.locator("#meTabs").is_hidden())
    p.click("#youList [data-yedit='settings']"); p.wait_for_timeout(300)
    check("You → Privacy opens straight to the privacy page, at the top, with ‹ You",
          p.locator("[data-mepane='settings']").is_visible() and p.locator("#meBack").is_visible() and p.locator("#youList").is_hidden()
          and p.evaluate("$('#v-me').scrollTop") < 40)
    p.evaluate("goBack()"); p.wait_for_timeout(300)
    check("back from a profile page returns to the You list", p.locator("#youList").is_visible() and p.locator("#meTabs").is_hidden())
    p.click("#meTitle"); p.wait_for_timeout(300)
    check("tapping your name opens your profile", p.locator("[data-mepane='profile']").is_visible())
    p.click("#meBack [data-youhub]"); p.wait_for_timeout(300)
    check("‹ You goes back to the list", p.locator("#youList").is_visible())
    p.click("#youList [data-yedit='profile']"); p.wait_for_timeout(300)
    check("You → Profile shows the profile tabs", p.locator("#meTabs").is_visible())
    p.click("[data-dock='me']"); p.wait_for_timeout(300)
    p.click("#youList [data-menu='quests']"); p.wait_for_selector("#questSheet .lvlcard", timeout=8000)
    check("You → Quests opens the quests", p.locator("#questBg").is_visible())
    p.evaluate("closeTopOverlay()")
    p.click("[data-dock='create']")
    check("＋ opens Create: story, post, hangout, event, group, live",
          p.eval_on_selector_all("#createBg [data-create]", "b=>b.map(x=>x.dataset.create)") == ["story", "post", "flare", "event", "group", "live"]
          and "Hangout" in p.inner_text("#createBg") and "Flare" not in p.inner_text("#createBg"))
    p.click("[data-create='post']"); p.wait_for_timeout(500)
    check("Create → Post lands on the posts composer", at()[0] == "feed" and p.evaluate("FEED_MODE.m") == "posts" and p.locator("#wText").is_visible())
    p.click("#logo"); p.wait_for_timeout(300)
    check("the name at the top goes back to the map", at() == ["home", "peek"])

    # Find a spot: where you're going and what you want there
    p.click("#qIn"); p.wait_for_selector("#searchOut .sfhead [data-sfa='6th Street']", timeout=8000)
    check("the search page opens with Find a spot: where, what, music, vibe",
          all(x in p.inner_text("#searchOut .sfhead") for x in ["Near me", "6th Street", "Live music", "DJ", "Jazz", "Brewery", "Rooftop"]))
    p.click("#searchOut [data-sfa='6th Street']"); p.wait_for_timeout(900)
    check("picking an area opens the list over the map, half way up", at() == ["home", "half"] and p.evaluate("EXC.k") == "find"
          and "6th Street" in p.inner_text("#exCat .exlh"))
    p.locator("#exCat .sfcompact [data-sfexp]").last.click(); p.wait_for_timeout(300)
    p.click("#exCat [data-sfh='drinks']"); p.wait_for_timeout(800)
    names = p.eval_on_selector_all("#exCat .xrow b", "b=>b.map(x=>x.textContent)")
    check("6th Street + Drinks: its bar and club, and pins for them on the map", "Sixth Street Saloon" in names and "Late Owl Club" in names
          and "Sunrise Coffee" not in names and p.locator(".sfpin").count() == len(names), names)
    p.click("#exCat [data-sft='dive']"); p.wait_for_timeout(600)
    names = p.eval_on_selector_all("#exCat .xrow b", "b=>b.map(x=>x.textContent)")
    check("…a vibe narrows it (Dive & honky-tonk: the saloon, not the club)", names == ["Sixth Street Saloon"], names)
    p.click("#exCat [data-sfreset]"); p.wait_for_timeout(300)
    p.locator("#exCat .sfcompact [data-sfexp]").last.click() if p.locator("#exCat .sfcompact").count() else None
    p.click("#exCat [data-sfm='jazz']"); p.click("#exCat [data-sfw='week']"); p.wait_for_timeout(800)
    rows = p.eval_on_selector_all("#exCat .xrow", "r=>r.map(x=>x.innerText)")
    check("Jazz this week: only shows that say jazz (or rooms known for it)", all("Jazz" in r for r in rows) and (rows or "Nothing listed" in p.inner_text("#exCat")), rows[:3])
    p.go_back(); p.wait_for_timeout(500)
    check("back closes it and takes its pins off the map", p.evaluate("EXC.k") is None and p.locator(".sfpin").count() == 0)
    p.evaluate("S.sf=null; save()")

    # Scout finds your spot: tap the vibe under Scout, or say it
    p.evaluate("S.sf=null; save(); openScoutVoice(true)"); p.wait_for_selector("#scFind [data-sfa='6th Street']", timeout=8000)
    check("Scout has Find my spot: one spot or a few stops, and the vibe options", p.locator("#scFind [data-scmode='few']").count() == 1
          and p.locator("#scFind [data-sfh='dj']").count() == 1 and p.locator("#scFind [data-scfind]").is_disabled())
    p.click("#scFind [data-sfa='6th Street']"); p.click("#scFind [data-sfh='drinks']")
    check("…tapping options picks them without leaving Scout", p.locator("#scoutBg").is_visible() and p.evaluate("S.sf.area==='6th Street'&&S.sf.has.includes('drinks')"))
    p.click("#scFind [data-scmode='few']"); p.click("#scFind [data-scfind]"); p.wait_for_selector("#exCat .scpick", timeout=8000)
    pick = p.eval_on_selector_all("#exCat .scpick .xrow .grow>b", "b=>b.map(x=>x.textContent)")
    check("…Plan my stops: a short walk of stops on top of the list, numbered on the map", set(pick) == {"Sixth Street Saloon", "Late Owl Club"}
          and "min walk" in p.inner_text("#exCat .scpick") and p.locator(".sfpin").count() >= 2, pick)
    p.go_back(); p.wait_for_timeout(400)
    p.evaluate("S.sf=null; save(); scoutAsk('a dive bar on 6th street with drinks tonight')"); p.wait_for_selector("#exCat .scpick", timeout=10000)
    check("…or say it: Scout hears the vibe and picks one spot", p.evaluate("S.sf.area==='6th Street'&&S.sf.theme.includes('dive')")
          and p.eval_on_selector_all("#exCat .scpick .xrow .grow>b", "b=>b.map(x=>x.textContent)") == ["Sixth Street Saloon"])
    p.go_back(); p.wait_for_timeout(400); p.evaluate("S.sf=null; save()")

    # Bars: serves food? kitchen till when? Unknown until someone who's been says (or its menu does)
    p.evaluate("focusPlace('n1002')"); p.wait_for_selector("#exPop .barfood", timeout=8000)
    check("a bar's card says when food isn't known yet and asks", "Not known yet" in p.inner_text("#exPop .barfood"))
    p.click("#exPop [data-bfask]"); p.click("#exPop [data-bfans='yes']"); p.click("#exPop [data-bfsend][data-c='23:00']"); p.wait_for_timeout(800)
    check("…telling it: serves food, kitchen closes at 11", "Serves food" in p.inner_text("#exPop .barfood") and "11 PM" in p.inner_text("#exPop .barfood"),
          p.inner_text("#exPop .barfood"))
    p.click("[data-popclose]"); p.wait_for_timeout(400)
    p.click("#mapChips [data-excat='night']"); p.wait_for_timeout(500); p.click("#exCat [data-exsub='barfood']"); p.wait_for_timeout(1200)
    names = p.eval_on_selector_all("#exCat .xrow b", "b=>b.map(x=>x.textContent)")
    check("Nightlife → Bars with food lists it, with when food stops", names == ["Sixth Street Saloon"] and "food till ~11 PM" in p.inner_text("#exCat"), names)
    p.click("#mapChips [data-excat='night']"); p.wait_for_timeout(300)

    # Shared around town: real photos and videos only; a nudge until there are some
    check("Explore: Shared around town says how to share the first one", "Shared around town" in p.inner_text("#exMedia")
          and p.locator("#exMedia .mcard").count() == 0 and p.locator("#exMedia [data-mshare]").count() == 1)
    jpg = p.evaluate("()=>{ const c=document.createElement('canvas'); c.width=c.height=64; const x=c.getContext('2d'); x.fillStyle='#f80'; x.fillRect(0,0,64,64); return c.toDataURL('image/jpeg',.8) }")
    r = p.evaluate("([img])=>api('/api/wall/post',{t:'Sunset from the patio',img,vis:'everyone',place:{name:'Sixth Street Saloon',lat:30.26718,lng:-97.7399,id:'n1002'}})", [jpg])
    p.evaluate("loadWall(true).then(()=>renderHome())"); p.wait_for_timeout(800)
    check("…a photo someone posts at a place shows up there, with the place's name", p.locator("#exMedia .mcard").count() == 1
          and "Sixth Street Saloon" in p.inner_text("#exMedia .mcard"), r)
    p.click("#exMedia .mcard"); p.wait_for_timeout(800)
    check("…tapping it opens the post", p.locator("#chatBg").is_visible() and "Sunset from the patio" in p.inner_text("#chatSheet"))
    p.evaluate("closeTopOverlay()"); p.wait_for_timeout(200)

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
