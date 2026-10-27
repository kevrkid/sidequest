"""End-to-end test of Side Quest: two brand-new users on phone-sized screens."""
import json
import random
import sys
import urllib.error
import urllib.request

from playwright.sync_api import sync_playwright

import os
BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
ADMIN = os.environ.get("SQ_ADMIN_TOKEN", "")
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SUFFIX = random.randint(100, 999)
TEX, AMY = f"test_tex{SUFFIX}", f"test_amy{SUFFIX}"
errors, results = [], []
BLANK_TILE = __import__("base64").b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
SCOUT_FACES = ["happy", "thinking", "surprised", "laughing", "confused", "excited", "calm"]


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""))


def wait_until(fn, secs=20):
    """Posts are screened by Claude before they're saved, so give them a few seconds."""
    import time
    end = time.time() + secs
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(0.4)
    return fn()


def me_sec(page, sec):
    """The profile is split into tabs: profile, personality, about, settings (V3: behind You → Edit profile)."""
    if page.locator("#meTabs").is_hidden():
        page.click("#youList [data-yedit='profile']")
    if page.locator(f"[data-mepane='{sec}']").is_hidden():
        page.click(f"#meTabs [data-mesec='{sec}']")


def dismiss_tour(page):
    """New people get offered a Scout tour a moment after the welcome sheet; say not now."""
    try:
        page.wait_for_selector("#scoutTour", state="visible", timeout=3000)
        page.click("#scoutTour [data-sc='tourend']")
    except Exception:
        pass


def open_life(page, key):
    """About-you questions are grouped in collapsible sections; open the one holding `key`."""
    me_sec(page, "about")
    sec = page.evaluate("k=>LIFE.find(f=>f.k===k).sec", key)
    if page.evaluate("lifeOpen") != sec:
        page.click(f"[data-lifesec='{sec}']")


def state():
    return json.load(urllib.request.urlopen(BASE + "/api/state"))


def nav(page, where):
    """Move around the way a person would (V3): the bar at the bottom, and the name at the top for the map."""
    if where == "me":                        # You, in the bottom bar; guests get the sign-up sheet
        page.click("[data-dock='me']")
        return
    if where == "feed":
        page.click("[data-dock='feed']")
    elif where == "friends":                  # Chats → Friends
        page.click("[data-dock='meet']"); page.click("[data-mt='friends']")
    elif where == "groups":                   # Chats → Groups
        page.click("[data-dock='meet']"); page.click("[data-mt='groups']")
    else:                                     # home / map: the name at the top goes back to the map
        page.click("#logo")


def feed_search(page, q):
    """V3: searching starts in the drawer's box; "Search posts and the feed" narrows the feed (its box then shows it)."""
    if not page.locator("#qIn").is_visible():
        page.click("[data-dock='home']")
    if page.locator("#exPop [data-popclose]").is_visible():   # a pin's card has the drawer: close it first
        page.click("#exPop [data-popclose]"); page.wait_for_timeout(300)
    page.click("#qIn"); page.fill("#qIn", q); page.wait_for_timeout(300)
    page.click("#searchOut [data-xgo^='feed|']")


def feed_clear(page):
    if page.locator("#feedQ").is_visible():
        page.fill("#feedQ", ""); page.dispatch_event("#feedQ", "input")


def new_user(browser, label):
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2,
                              geolocation={"latitude": 30.2671, "longitude": -97.7395}, permissions=["geolocation"])
    # don't wait on the internet: skip web fonts, and answer map tiles with a blank local image
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u, lambda r: r.abort())
    ctx.route(lambda u: "tile.openstreetmap.org" in u, lambda r: r.fulfill(status=200, content_type="image/png", body=BLANK_TILE))
    page = ctx.new_page()
    page.on("pageerror", lambda e: errors.append(f"{label}: {e}"))
    page.on("response", lambda r: r.status >= 400 and errors.append(f"{label} {r.status} {r.request.method} {r.url.replace(BASE, '')}"))
    page.goto(BASE)
    page.wait_for_selector("[data-onbguest]", timeout=10000)
    return ctx, page


def onboard(page, handle, interests):
    """Explore as a guest first, hit a gated action, then create the account from there."""
    if page.locator("[data-onbmore]").count():      # the welcome shows a dozen first
        page.click("[data-onbmore]")
    for i in interests:
        page.click(f"[data-onbi='{i}']")
    page.click("[data-onbguest]")
    dismiss_tour(page)
    check(f"{handle}: can look around without an account", "Sign up" in page.locator("#meChip").inner_text()
          and page.locator("#v-home").is_visible())
    page.wait_for_function("EV.loaded", timeout=20000)
    rid = page.evaluate("EV.list.filter(e=>e.te>Date.now()).at(-1).id")   # something far off, not tonight's top pick
    page.evaluate("id=>rsvp(id,'going')", rid)          # guests can RSVP; it's kept on the device
    page.click("[data-dock='create']"); page.click("[data-create='flare']")
    page.fill("#cText", "test flare as a guest")
    page.click("#compose button.primary")
    gate = page.locator("#onb").inner_text()
    check(f"{handle}: posting asks for a free account", "Create a free account to post a flare" in gate)
    page.click("#onb [data-onbmode='signup']")
    page.fill("#onbH", "Bad Handle!"); page.fill("#onbP", "correct horse 9")
    page.click("[data-onbnext]")
    check(f"{handle}: rejects an invalid handle", "3–20" in page.locator("#onb").inner_text())
    page.fill("#onbH", handle); page.fill("#onbP", "short")
    page.check("#onbAdult"); page.check("#onbTerms")
    page.click("[data-onbnext]")
    check(f"{handle}: requires an 8+ character password", "8 characters" in page.locator("#onb").inner_text())
    page.fill("#onbH", "nitro_nate"); page.fill("#onbP", "correct horse 9")
    page.click("[data-onbnext]")
    page.wait_for_function("!ONB.busy")
    check(f"{handle}: rejects a taken handle", "taken" in page.locator("#onb").inner_text())
    page.fill("#onbH", handle); page.fill("#onbP", "correct horse 9")
    page.click("[data-onbc='#3ddc97']")
    page.fill("#onbH", handle); page.fill("#onbP", "correct horse 9")
    page.check("#onbAdult"); page.check("#onbTerms")
    page.click("[data-onbnext]")
    page.wait_for_selector("#onbBg", state="hidden")
    check(f"{handle}: account created on the server", any(u["h"] == handle for u in state()["users"]))
    check(f"{handle}: lands back on the flare they were writing", page.locator("#sheetBg").is_visible()
          and page.eval_on_selector("#cText", "e=>e.value") == "test flare as a guest")
    page.wait_for_timeout(500)
    check(f"{handle}: guest RSVP carried into the account", state()["rsvps"].get(rid, {}).get(handle) == "going")
    page.click("#closeSheet")


with sync_playwright() as pw:
    browser = pw.chromium.launch()

    # ---------------- user 1: sign up, quizzes, profile, feed, RSVP, map, group ----------------
    ctx1, p1 = new_user(browser, TEX)
    onboard(p1, TEX, ["comedy", "live shows", "pickup games", "soccer"])
    p1.screenshot(path=f"{OUT}/01-signup-done.png")

    # V3: the map is the app; a drawer (search box + chips) and the bottom bar sit over it
    p1.wait_for_selector("#v-home:not([hidden])")
    p1.wait_for_function("EV.loaded", timeout=20000)
    p1.screenshot(path=f"{OUT}/00-home.png")
    chips = p1.eval_on_selector_all("#mapChips [data-excat]", "ns=>ns.map(n=>n.dataset.excat)")
    dock = p1.eval_on_selector_all("#dock [data-dock]", "ns=>ns.map(n=>n.dataset.dock)")
    check("map first: the map, a search box, the chips and the five-button bar", p1.locator("#map .leaflet-tile-loaded").count() > 0 and p1.locator("#qIn").is_visible()
          and chips == ["food", "events", "night", "outdoors", "sights", "friends", "zones"] and dock == ["home", "feed", "create", "meet", "me"], f"{chips} {dock}")
    pos = p1.evaluate("ME_POS")
    check("uses the device's real location", abs(pos[0] - 30.2671) < 0.001 and abs(pos[1] + 97.7395) < 0.001, str(pos))
    p1.click("#qIn"); p1.fill("#qIn", "comedy"); p1.wait_for_timeout(400)
    sr = p1.locator("#searchOut").inner_text()
    check("one search box: events, places, people and groups as you type", "EVENTS" in sr.upper() and "Find" in sr and "Ask Scout" in sr, sr[:200].replace("\n", " | "))
    p1.screenshot(path=f"{OUT}/00-search.png")
    p1.click("#searchOut [data-xgo^='feed|']")
    check("…and it can narrow the feed to it", p1.locator("#v-feed").is_visible() and p1.evaluate("feedQ") == "comedy" and p1.input_value("#feedQ") == "comedy")
    feed_clear(p1)
    p1.click("[data-dock='meet']"); p1.click("[data-mt='swipe']")
    kinds = p1.evaluate("[...new Set(deckItems().slice(0,12).map(x=>x.k))]")
    check("Meet deck mixes people, events, groups and flares", {"person", "event", "group", "post"} <= set(kinds), ",".join(kinds))
    p1.screenshot(path=f"{OUT}/00-meet.png")
    p1.click("[data-mtype='event']")
    top_ev = p1.locator(".mcard.top").get_attribute("data-id")
    p1.click("[data-swipe='right']"); p1.wait_for_timeout(500)
    check("swiping right on an event marks you going", p1.evaluate("id=>myRsvp(id)", top_ev) == "going")
    p1.evaluate("id=>rsvp(id,'going')", top_ev); p1.wait_for_timeout(300)        # undo, keeps later checks simple
    p1.click("[data-meetfilter]"); p1.click("[data-mcat='comedy']"); p1.click("#mWhen [data-v='today']")
    cats = p1.evaluate("[...new Set(deckItems().map(x=>x.it.cat))]")
    check("filters narrow the deck (comedy, tonight)", cats in (["comedy"], []), ",".join(map(str, cats)))
    p1.click("#actSheet [data-meetreset]"); p1.click("[data-actclose]")
    p1.click("[data-mtype='group']")
    p1.click("[data-swipe='right']"); p1.wait_for_timeout(600)
    check("swiping right on a group joins it", p1.evaluate("allGroups().some(g=>isMember(g.id))"))
    p1.click("[data-mtype='']")
    p1.click("[data-mt='groups']")
    gm = p1.locator("#meetBody").inner_text()
    check("Groups tab: your groups, find a group, start one", "Your groups" in gm and "Find a group" in gm and "Start a group" in gm)
    p1.click("[data-gsec='0']")
    gm = p1.locator("#meetBody").inner_text()
    find = gm.split("Find a group", 1)[-1]           # "Your groups" above may list anything already joined
    check("Find a group filters by section", ("ATX Pickup Soccer" in find or "ATX Pickup Soccer" in gm) and "Comedy Night Owls" not in find)
    p1.click("[data-mt='swipe']")
    p1.click("[data-dock='home']"); p1.wait_for_timeout(400)
    check("Explore brings the map back, drawer half way", p1.evaluate("curTab") == "home" and p1.evaluate("DRW.at") == "half" and p1.locator(".leaflet-tile-loaded").count() > 0)
    p1.click("[data-dock='create']")
    p1.screenshot(path=f"{OUT}/00-create.png")
    p1.click("[data-create='event']")
    check("Create → Event offers a date/time", p1.locator("#cAt").is_visible())
    p1.click("#closeSheet")

    # ---- food & drink (test places file: 24/7 tacos on Rainey, a 24h bar on 6th, a morning cafe, ...)
    nav(p1, "home"); p1.click("#mapChips [data-excat='zones']"); p1.wait_for_selector("#exCat .xrow", timeout=10000)
    check("🔥 Hot spots chip lists the hot spots", "Rainey Street" in p1.locator("#exCat").inner_text())
    p1.click("#mapChips [data-excat='food']"); p1.wait_for_selector("#exCat [data-exsub='tacos']", timeout=10000)
    check("🍔 Food chip: smaller chips and an Open now switch", all(p1.locator(f"#exCat [data-exsub='{k}']").count() == 1 for k in ["happy", "late", "coffee", "tacos", "bbq"])
          and p1.locator("#exCat [data-exopen]").count() == 1 and p1.evaluate("S.mapL.food && !S.mapL.events"))
    p1.screenshot(path=f"{OUT}/70-food-search.png")
    p1.click("#exCat [data-exsub='tacos']"); p1.wait_for_selector("#exCat .xrow", timeout=10000)
    pl = p1.locator("#exCat").inner_text()
    check("tacos open now: the 24/7 taco truck, with hours and distance", "Taco Test Trailer" in pl and "Open 24 hours" in pl and " mi" in pl, pl[:120].replace("\n", " | "))
    p1.click("#exCat [data-exsub='bbq']"); p1.wait_for_timeout(800)
    open_bbq = p1.locator("#exCat").inner_text()
    p1.click("#exCat [data-exopen]"); p1.wait_for_selector("#exCat .xrow", timeout=10000); p1.wait_for_timeout(500)
    check("Open now switch: off shows closed spots with when they open", "Brisket Barn" in p1.locator("#exCat").inner_text()
          and ("Brisket Barn" not in open_bbq or "Open till" in open_bbq))
    p1.click("#exCat [data-exopen]"); p1.wait_for_timeout(500)          # back on for later
    p1.click("#exCat [data-exsub='tacos']"); p1.wait_for_selector("#exCat .xrow", timeout=10000)
    p1.click("#exCat .xrow >> nth=0"); p1.wait_for_selector(".leaflet-popup-content [data-pmenu]", timeout=10000)
    check("tapping a row flies to it on the map; its card (with Menu) opens in the drawer", p1.evaluate("DRW.at") == "half" and "Taco Test Trailer" in p1.locator("#exPop").inner_text())
    p1.click("#exPop [data-popclose]"); p1.wait_for_timeout(400)
    check("closing the card goes back to the list", p1.locator("#exCat .xrow").first.is_visible() and p1.evaluate("DRW.at") == "half")
    p1.click("#mapChips .chip.on")      # the picked chip (✕) closes its list
    check("✕ puts the map back the way it was", p1.evaluate("!EXC.k && S.mapL.events"))
    check("✕ leaves the map calm: no food dots or hot spot zones until you ask", p1.evaluate("!S.mapL.food && !S.mapL.zones"))
    # map: dots + hot spot zones (the Layers switches)
    nav(p1, "map"); p1.wait_for_function("PL.all && PL.hot", timeout=15000)
    p1.evaluate("S.mapL.food=S.mapL.zones=S.mapL.clubs=S.mapL.bars=S.mapL.trails=S.mapL.spots=true; refreshMapLayers()")   # the Layers switches
    p1.evaluate("map.setView([30.2650,-97.7390],15)"); p1.wait_for_timeout(800)
    dots = p1.evaluate("({open: Object.values(PL.cores).filter(l=>l.options.fillColor==='#3ddc97').length, all: Object.keys(PL.cores).length})")
    check("green open-now dots on the map", dots["open"] >= 2 and dots["all"] >= 4, json.dumps(dots))
    check("8 glowing hot-spot zones with labels", p1.locator("path.hotzone").count() == 8 and "6th Street" in p1.locator(".hotlabel").all_inner_texts().__str__())
    # events off for this check: the day's real events can land on the test bar, and events win the spot
    p1.evaluate("S.mapL.events=false; refreshMapLayers()"); p1.wait_for_timeout(400)
    clubs15, bars15 = p1.locator(".npin.club").count(), p1.locator(".npin.bar").count()
    p1.evaluate("void map.setView([30.2670,-97.7395],16)"); p1.wait_for_timeout(600)
    check("Nightlife layer: clubs, and bars only at street level (zoom 16)", clubs15 >= 1 and bars15 == 0 and p1.locator(".npin.bar").count() >= 1,
          f"zoom 15: {clubs15} clubs, {bars15} bars; zoom 16: {p1.locator('.npin.bar').count()} bars")
    p1.evaluate("S.mapL.events=true; refreshMapLayers()")
    p1.evaluate("void map.setView([30.2650,-97.7390],15)"); p1.wait_for_timeout(500)
    p1.evaluate("void map.setView([30.2625,-97.760],13)"); p1.wait_for_timeout(1200)
    od = "[...OD.on.values()].flatMap(l=>l.getLayers?l.getLayers():[l])"   # drawn on a canvas: check the shapes themselves
    check("Outdoors: green nature and blue water outlines (not circles)", p1.evaluate(f"{od}.some(l=>l instanceof L.Polygon&&l.options.fillColor==='#3ddc97')&&{od}.some(l=>l instanceof L.Polygon&&l.options.fillColor==='#2ec5ff')"))
    check("Outdoors: hike & bike trails as dashed lines", p1.evaluate(f"{od}.some(l=>l instanceof L.Polyline&&!(l instanceof L.Polygon)&&!!l.options.dashArray&&!!l._map)"))
    check("Outdoors: rental and trailhead pins up close", p1.locator(".opin.rental").count() >= 1 and p1.locator(".opin.trailhead").count() >= 1)
    p1.evaluate("areaPopup(OD.data.areas.find(a=>a.kind==='water'), L.latLng(30.2625,-97.744))"); p1.wait_for_timeout(300)
    pop = p1.locator(".leaflet-popup-content").last.inner_text()
    check("tapping water lists what you can do there", all(x in pop for x in ["Test Lake", "Fishing", "Paddleboard", "Kayak", "Test Paddle Rentals"]), pop[:80].replace("\n", " | "))
    p1.evaluate("map.closePopup()"); p1.click("#mapChips [data-excat='outdoors']"); p1.wait_for_timeout(500)
    check("the Outdoors chip: only outdoors on the map, and a list of them", p1.evaluate("S.mapL.parks&&S.mapL.water&&!S.mapL.events&&!S.mapL.zones") and "Test Lake" in p1.locator("#exCat").inner_text())
    p1.click("#mapChips [data-excat='outdoors']"); p1.wait_for_timeout(300)
    check("tapping it again puts the other layers back", p1.evaluate("!EXC.k&&S.mapL.events&&S.mapL.friendlocs&&S.mapL.parks"))
    p1.evaluate("void map.setView([30.2650,-97.7390],15)"); p1.wait_for_timeout(500)
    p1.click("[data-mlayers]"); p1.click("#mfWhen [data-v='week']"); p1.wait_for_timeout(300)
    check("Layers sheet: events this week", p1.evaluate("S.mapWhen") == "week")
    p1.click("#mfWhen [data-v='tonight']")
    p1.click("#placesSheet [data-mpreset='outdoors']"); p1.wait_for_timeout(500)
    check("quick pick 'Outdoors day' sets several layers at once",
          p1.evaluate("S.mapL.parks && S.mapL.trails && !S.mapL.clubs && !S.mapL.events"))
    check("Sights are off until you turn them on (too busy by default)", p1.evaluate("!S.mapL.landmarks && !S.mapL.markers && !S.mapL.art") and p1.locator(".sgpin").count() == 0)
    p1.click("#placesSheet [data-mpreset='all']"); p1.wait_for_timeout(300); p1.evaluate("S.mapL.stories=false; refreshMapLayers()")
    p1.click("#placesSheet [data-pclose]")
    p1.screenshot(path=f"{OUT}/71-map-food.png")
    p1.evaluate("PL.zones.getLayers().find(l=>l.hotId==='rainey').fire('click')")
    p1.wait_for_selector("#placesSheet .prow", timeout=10000)
    check("tapping a hot spot lists what's open there", "Rainey Street" in p1.locator("#placesSheet").inner_text() and "Taco Test Trailer" in p1.locator("#placesSheet").inner_text())
    # back: closes the sheet first, then goes to the previous screen
    p1.go_back(); p1.wait_for_timeout(300)            # the phone's back (Android button / swipe) while a sheet is open
    check("back closes the open sheet first", p1.locator("#placesBg").is_hidden() and p1.locator("#v-map").is_visible())
    p1.evaluate("setDrawer('half')"); p1.evaluate("goBack()"); p1.wait_for_timeout(300)
    check("back again lowers the drawer onto the map", p1.evaluate("DRW.at") == "peek", p1.evaluate("DRW.at"))
    nav(p1, "feed"); p1.wait_for_timeout(200)
    p1.evaluate("""()=>{ const app=document.querySelector('#app'), r=app.getBoundingClientRect();
      const mk=(type,x)=>{ const t=new Touch({identifier:1,target:app,clientX:r.left+x,clientY:400}); app.dispatchEvent(new TouchEvent(type,{touches:type==='touchend'?[]:[t],changedTouches:[t],bubbles:true})); };
      mk('touchstart',8); mk('touchmove',60); mk('touchmove',140); mk('touchend',140); }""")
    p1.wait_for_timeout(400)
    check("swipe in from the left edge goes back", p1.evaluate("curTab") != "feed", p1.evaluate("curTab"))
    p1.evaluate("""()=>{ const app=document.querySelector('#app'), r=app.getBoundingClientRect();
      const mk=(type,x)=>{ const t=new Touch({identifier:1,target:app,clientX:r.right-x,clientY:400}); app.dispatchEvent(new TouchEvent(type,{touches:type==='touchend'?[]:[t],changedTouches:[t],bubbles:true})); };
      mk('touchstart',8); mk('touchmove',60); mk('touchmove',140); mk('touchend',140); }""")
    p1.wait_for_timeout(400)
    check("swipe in from the right edge goes forward again", p1.evaluate("curTab") == "feed", p1.evaluate("curTab"))
    # sights & history: landmarks, Texas historical markers (with the plaque text), a story per tap
    nav(p1, "map"); p1.wait_for_timeout(700); p1.evaluate("void map.setView([30.2700,-97.7410],15)"); p1.wait_for_timeout(900)
    marks15, lands15 = p1.locator(".sgpin.markers").count(), p1.locator(".sgpin.landmarks").count()
    # crowded spots thin out zoomed out, fill in up close (centered between the two test markers, ~330 m apart;
    # events off, since a test event sits on the Ferry Landing marker and events win the spot)
    p1.evaluate("S.mapL.events=false; refreshMapLayers(); void map.setView([30.2675,-97.7410],17)"); p1.wait_for_timeout(900)
    check("Sights layer: landmarks and historical markers on the map, more as you zoom in",
          lands15 >= 1 and p1.locator(".sgpin.markers").count() >= 2 and p1.locator(".sgpin.markers").count() >= marks15,
          f"{lands15} landmarks at 15, {p1.locator('.sgpin.markers').count()} markers, zoom {p1.evaluate('map.getZoom()')}, {p1.evaluate('JSON.stringify([S.mapL.markers,S.mapL.landmarks])')}")
    p1.evaluate("S.mapL.events=true; refreshMapLayers()")
    p1.evaluate("sightPopup('m9001')"); p1.wait_for_selector("[data-sgtell='m9001']", timeout=10000)
    pop = p1.locator(".leaflet-popup-content").last.inner_text()
    check("tapping a marker shows its plaque text, year and credit", "moonlight towers" in pop and "1970" in pop and "Texas Historical Commission" in pop, pop[:90].replace("\n", " | "))
    p1.screenshot(path=f"{OUT}/72-map-sight.png")
    p1.evaluate("map.closePopup()"); p1.click("#mapChips [data-excat='sights']"); p1.wait_for_timeout(500)
    check("the Sights chip lists sights nearest the middle of the map", "Ferry Landing" in p1.locator("#exCat").inner_text() or "moonlight" in p1.locator("#exCat").inner_text().lower(), p1.locator("#exCat").inner_text()[:150])
    p1.click("#mapChips .chip.on"); p1.wait_for_timeout(200)      # the picked chip (✕) closes its list
    p1.click("[data-mlayers]"); p1.wait_for_timeout(300)
    p1.evaluate("""()=>{ const s=document.querySelector('#placesSheet'), r=s.getBoundingClientRect();
      const mk=(type,y)=>{ const t=new Touch({identifier:2,target:s,clientX:r.left+150,clientY:r.top+y}); s.dispatchEvent(new TouchEvent(type,{touches:type==='touchend'?[]:[t],changedTouches:[t],bubbles:true,cancelable:true})); };
      mk('touchstart',10); mk('touchmove',40); mk('touchmove',120); mk('touchmove',200); mk('touchend',200); }""")
    p1.wait_for_timeout(500)
    check("pulling a sheet down closes it", p1.locator("#placesBg").is_hidden())
    # eat after the club: food within a walk that's still open when it closes (2 AM)
    trucks = p1.evaluate("fetch('/api/places?cat=trucks&limit=10').then(r=>r.json()).then(j=>j.places.map(p=>p.name))")
    check("Food trucks tile lists only trucks", trucks == ["Taco Test Trailer"], str(trucks))
    nav(p1, "map"); p1.evaluate("placePopup('n1003',[30.267,-97.738])")
    p1.wait_for_selector("[data-pafter='n1003']", timeout=10000); p1.click("[data-pafter='n1003']")
    p1.wait_for_selector("#placesSheet .prow", timeout=10000)
    af = p1.locator("#placesSheet").inner_text()
    check("Eat after a club: closing time, nearby food open then, walk time",
          "Eat after Late Owl Club" in af and "Closes at 2 AM" in af and "Night Noodle House" in af and "Open till 4 AM" in af and "min walk" in af
          and "Brisket Barn" not in af, af.replace("\n", " | ")[:200])
    p1.screenshot(path=f"{OUT}/73-eat-after.png")
    p1.click("#placesSheet [data-pclose]")
    # Scout finds tacos and lights the place up
    p1.evaluate("scoutAsk('find me tacos that are open right now')")
    p1.wait_for_function("!SCT.busy", timeout=60000)
    said = p1.evaluate("scS().log.slice(-1)[0].text")
    check("Scout answers a food question from the real list", "Taco Test Trailer" in said, said[:140])
    check("Scout lights the place up on the map", p1.evaluate("!!SCT.placeInfo && !!SCT.placeInfo['n1001']"))
    p1.wait_for_timeout(2500)
    p1.screenshot(path=f"{OUT}/72-scout-food.png")
    if p1.locator("#placesBg").is_visible():      # Scout may also have opened a Food & drink list
        p1.click("#placesSheet [data-pclose]")
    nav(p1, "me")
    me_sec(p1, "personality")
    S_quiz = p1.locator("#startQuiz")
    S_quiz.click()
    p1.wait_for_selector("[data-q='0']")
    # Lean extravert / intuitive / feeling / perceiving: agree with + keyed E,N items, disagree with T,J.
    keys = ["E", "N", "T", "J"] * 5
    signs = [1] * 4 + [-1] * 4 + [1] * 4 + [-1] * 4 + [1] * 4
    want = {"E": 1, "N": 1, "T": -1, "J": -1}
    for i, (k, sgn) in enumerate(zip(keys, signs)):
        p1.click(f"[data-q='{i}'][data-a='{5 if sgn * want[k] > 0 else 1}']")
    p1.click("#finishQuiz")
    t = p1.locator(".type-big").inner_text()
    check("16-type quiz scores correctly", t == "ENFP", t)

    p1.click("#astroT")
    p1.fill("#bday", "1995-11-02")
    p1.dispatch_event("#bday", "change")
    check("birthday works out the sun sign", p1.eval_on_selector("#zodiac", "e=>e.value") == "Scorpio")
    p1.fill("#btime", "15:30"); p1.dispatch_event("#btime", "change")
    p1.fill("#bcity", "Austin, Texas"); p1.click("#bcityForm button")
    p1.wait_for_selector("[data-bplace]", timeout=20000); p1.click("[data-bplace='0']"); p1.wait_for_timeout(300)
    ch = p1.evaluate("({...myChart(), chinese:S.me.chinese, tz:S.me.birth.tz})")
    check("full chart from birth date, time and city", all(ch.get(k) for k in ["sun", "moon", "rising", "mercury", "venus", "mars", "jupiter", "saturn"])
          and ch["chinese"] == "Pig" and ch["tz"] == "America/Chicago", json.dumps(ch)[:150])
    check("chart card shows on the profile", "Your chart" in p1.locator("#chartCard").inner_text() and "Rising:" in p1.locator("#chartCard").inner_text())
    p1.click("[data-amatter='A lot']")
    p1.screenshot(path=f"{OUT}/02a-chart.png")
    p1.select_option("#moon", "Leo")

    me_sec(p1, "about")
    p1.fill("[data-lifetext='hometown']", "El Paso, TX")
    p1.dispatch_event("[data-lifetext='hometown']", "change")
    for k, v in [("grewUp", "Big city"), ("siblings", "3"), ("birthOrder", "Oldest"), ("kidWas", "Sporty one"),
                 ("kidActivities", "Sports team"), ("schedule", "Night owl"), ("music", "Latin"), ("music", "Rock"),
                 ("weekend", "Up early, outdoors"), ("goals", "Teammates"), ("friendLang", "Doing things together"),
                 ("values", "Loyalty"), ("drinks", "Socially")]:
        open_life(p1, k)
        p1.click(f"[data-life='{k}'][data-opt='{v}']")
    open_life(p1, "hometown")
    for k, tab_ in (("hometown", "about"), ("interests", "profile")):   # match-only -> friends -> everyone
        me_sec(p1, tab_)
        p1.click(f"[data-vis='{k}']")
        p1.click(f"[data-vis='{k}']")
    open_life(p1, "drinks")
    p1.click("[data-vis='drinks']")
    p1.click("[data-vis='drinks']")
    p1.click("[data-vis='drinks']")           # -> only me
    p1.evaluate("openProfile('nitro_nate')")
    pr = p1.locator("#actSheet").inner_text()
    check("profile view: astro compatibility card", "Astrological compatibility" in pr and "How you vibe" in pr and "Emotional connection" in pr)
    check("matching uses the deeper questions", "Both night owls" in pr and "sporty one as kids" in pr and "doing things together" in pr, pr[:0])
    p1.screenshot(path=f"{OUT}/02b-profile-view.png", full_page=False)
    p1.click("[data-actclose]")
    me_sec(p1, "profile")
    prof = p1.locator("#profCard").inner_text()
    check("public preview shows only public answers", "El Paso" in prof and "Socially" not in prof and "Big city" not in prof)
    p1.screenshot(path=f"{OUT}/02-profile.png", full_page=False)
    for _ in range(30):                        # sync is debounced, then screened by Claude
        p1.wait_for_timeout(500)
        u = next(x for x in state()["users"] if x["h"] == TEX)
        if u["public"].get("hometown"): break
    check("server got the public profile", u["public"].get("hometown") == "El Paso, TX" and "drinks" not in u["public"],
          json.dumps(u["public"])[:120])

    # Feed
    nav(p1, "feed")
    p1.wait_for_function("document.querySelectorAll('#feedList [data-rsvp]').length>0", timeout=20000)
    meta = p1.evaluate("document.querySelector('#feedMeta').textContent")   # (shown only once something narrows the feed)
    check("feed loads real events", "event" in meta, meta)
    first = p1.locator("#feedList .card").first.inner_text()
    p1.screenshot(path=f"{OUT}/03-feed.png")
    reasons = p1.locator("#feedList").inner_text()
    check("feed explains picks from interests/profile", "You're into" in reasons or "You love" in reasons or "here for" in reasons)

    feed_search(p1, "comedy")
    p1.wait_for_timeout(300)
    n_comedy = p1.locator("#feedList [data-rsvp][data-st='going']").count()
    check("search filters the feed", n_comedy > 0, f"{n_comedy} matches for 'comedy'")
    feed_clear(p1)
    p1.click("[data-ffocus='pickup']")
    pick_meta = p1.locator("#feedMeta").inner_text()
    check("category chip narrows the feed", "event" in pick_meta, pick_meta)
    p1.click("[data-ffocus='']")
    p1.click("[data-fcustom]")
    p1.click("#fSort [data-v='soon']")
    p1.click("[data-fshow='people']")
    p1.screenshot(path=f"{OUT}/04-customize.png")
    p1.click("[data-fclose]")
    times = p1.eval_on_selector_all("#feedList [data-rsvp][data-st='going']",
                                    "bs=>bs.map(b=>EV.byId[b.dataset.rsvp].ts)")
    check("sort by soonest", times == sorted(times), f"{len(times)} events")
    p1.click("[data-fcustom]")
    p1.click("#fSort [data-v='foryou']")
    p1.click("[data-fshow='people']")
    p1.click("[data-fclose]")

    # RSVP
    btn = p1.locator("#feedList [data-rsvp][data-st='going']").first
    ev_id = btn.get_attribute("data-rsvp")
    ev_title = p1.evaluate("id=>EV.byId[id].title", ev_id)
    btn.click()
    p1.wait_for_timeout(500)
    check("RSVP saved on the server", state()["rsvps"].get(ev_id, {}).get(TEX) == "going", ev_title)
    check("'Your plans' shows the event", ev_title in p1.locator("#feedList .card").first.inner_text())
    second = p1.locator("#feedList [data-rsvp][data-st='interested']").nth(2)
    second_id = second.get_attribute("data-rsvp")
    second.click()
    p1.wait_for_timeout(400)
    check("'interested' saved", state()["rsvps"].get(second_id, {}).get(TEX) == "interested")

    # Map
    p1.locator(f"#feedList .card").first.locator("[data-map]").first.click()
    # wait for this event's own popup: an older one can still be fading out for a moment
    p1.wait_for_function("t => [...document.querySelectorAll('.leaflet-popup-content')].some(e => e.innerText.includes(t))", arg=ev_title[:20], timeout=5000)
    pop = next(t for t in p1.locator(".leaflet-popup-content").all_inner_texts() if ev_title[:20] in t)
    check("event shows on the map with RSVP state", ev_title[:20] in pop and "Going" in pop,
          pop[:60] + " | " + str(p1.evaluate("""() => { const c=document.querySelector('#feedList .card [data-map]'); const id=c&&c.dataset.map, e=EV.byId[id];
            return {id, onMap: !!markers[id], lat: e&&e.lat, endsInMin: e&&Math.round((e.te-Date.now())/60000), title: e&&e.title.slice(0,30)}; }""")))
    p1.screenshot(path=f"{OUT}/05-map-event.png")
    nav(p1, "feed")
    p1.click("#feedMapBtn")
    p1.wait_for_timeout(500)
    pins = p1.locator(".pin.ev").count()
    check("'Map it' puts the feed on the map", pins > 5, f"{pins} event pins")
    p1.screenshot(path=f"{OUT}/06-map-feed.png")

    # Groups + posting
    nav(p1, "groups")
    p1.click("[data-gsec='']")                                           # all sections
    if p1.locator("#meetBody [data-gopen='g1'] [data-gjoin]").count():   # the group swipe may have joined it already
        p1.click("#meetBody [data-gopen='g1'] [data-gjoin]")
    p1.wait_for_timeout(400)
    check("joined a group (server)", TEX in state()["members"].get("g1", []))
    p1.click("#meetBody [data-gopen='g1'] .grow")
    p1.click("[data-gpost='g1']")
    p1.fill("#cText", "7v7 pickup at Zilker Saturday 10am, need 4 more, all levels")
    p1.select_option("#cKind", "pickup")
    p1.click("#compose button.primary")
    posts = wait_until(lambda: [x for x in state()["posts"] if x["u"] == TEX])
    check("group post saved on the server", posts and posts[0].get("group") == "g1")

    # Story: photo + event + group + person tags
    nav(p1, "home")
    p1.click("[data-dock='create']")
    p1.click("[data-create='story']")
    p1.set_input_files("#storyFile", f"{OUT}/00-home.png")
    p1.wait_for_selector(".shot img")
    p1.fill("#scCap", "Front row at the show tonight!")
    p1.select_option("#scEvent", index=1)
    story_ev = p1.eval_on_selector("#scEvent", "s=>s.value")
    p1.click("[data-scgroup='g1']")
    p1.fill("#scQ", "nitro")
    p1.click("#scCands [data-scperson='nitro_nate']")
    p1.screenshot(path=f"{OUT}/08-story-compose.png")
    p1.click("[data-scpost]")
    st = wait_until(lambda: [x for x in state()["stories"] if x["u"] == TEX])
    check("story saved with photo and tags", st and st[0]["img"] and st[0]["event"] == story_ev and st[0]["groups"] == ["g1"]
          and st[0]["people"] == ["nitro_nate"], json.dumps(st[0] if st else {})[:140])
    img = urllib.request.urlopen(BASE + st[0]["img"])
    check("story photo is served as a JPEG", img.headers["Content-Type"] == "image/jpeg" and len(img.read()) > 1000)
    try:
        urllib.request.urlopen(BASE + "/data/app.json"); leaked = True
    except urllib.error.HTTPError as e:
        leaked = e.code != 404
    check("private data file is not downloadable", not leaked)

    hist = p1.evaluate("S.log.map(e=>e.a)")
    check("activity history recorded", {"rsvp", "group", "post"} <= set(hist), ",".join(hist))

    # ---------------- user 2: sees user 1's activity ----------------
    ctx2, p2 = new_user(browser, AMY)
    onboard(p2, AMY, ["soccer", "pickup games", "running"])
    nav(p2, "feed")
    p2.wait_for_function("document.querySelectorAll('#feedList [data-rsvp]').length>0", timeout=20000)
    feed_search(p2, "Zilker Saturday")
    p2.wait_for_timeout(300)
    check("2nd user sees the group post", "need 4 more" in p2.locator("#feedList").inner_text())
    feed_clear(p2)
    going = p2.evaluate("id=>goingList(EV.byId[id])", ev_id)
    check("2nd user sees 1st user's RSVP", TEX in going, ",".join(going))
    nav(p2, "friends")
    sug = p2.locator("#suggestList").inner_text()
    check("1st user is suggested to the 2nd", TEX in sug)
    p2.screenshot(path=f"{OUT}/07-amy-people.png")
    feed_search(p2, "Zilker Saturday")
    p2.locator(f"#feedList [data-down='{posts[0]['id']}']").click()
    p2.wait_for_timeout(400)
    check("2nd user said 'I'm down' to the post", AMY in next(x for x in state()["posts"] if x["id"] == posts[0]["id"])["downs"])

    nav(p2, "map")
    check("map layers start with stories off (less clutter)", p2.locator("#map .sbub").count() == 0 and p2.evaluate("S.mapL.friendlocs && S.mapL.posts"))
    p2.click("[data-mlayers]")
    p2.click("#placesSheet [data-ml='stories']")      # one switch under Friends turns on just stories
    p2.wait_for_timeout(400)
    check("stories show as bubbles on the map", p2.locator("#map .sbub").count() >= 3, f"{p2.locator('.sbub').count()} bubbles")
    p2.click("#placesSheet [data-ml='stories']")
    p2.wait_for_timeout(300); p2.click("#placesSheet [data-pclose]")
    check("tapping Stories again hides them, the rest stays", p2.locator("#map .sbub").count() == 0 and p2.locator(".lthumb:not(.sm)").count() >= 3)
    n_live = p2.locator(".lthumb:not(.sm)").count()
    check("live streamers show preview thumbnails on the map", n_live >= 3, f"{n_live} thumbnails")
    p2.screenshot(path=f"{OUT}/09-map-stories.png")
    nav(p2, "feed")
    feed_clear(p2)
    p2.click(f"#feedStories [data-stuser='{TEX}']")
    p2.wait_for_selector("#storyView:not([hidden]) .media")
    sv = p2.locator("#storyView").inner_text()
    check("story viewer shows caption and all tags", "Front row" in sv and "@nitro_nate" in sv and "ATX Pickup Soccer" in sv, sv.replace("\n", " | ")[:120])
    p2.screenshot(path=f"{OUT}/10-story-view.png")
    p2.locator("#storyView [data-stev]").first.dispatch_event("click")   # tap in place: auto-scrolling a snapping feed can land elsewhere
    p2.wait_for_selector(".leaflet-popup-content", timeout=5000)
    check("tapping the event tag opens it on the map", p2.locator("#v-map").is_visible())
    # tag user 1 back in a text story
    nav(p2, "home")
    p2.click("[data-dock='create']")
    p2.click("[data-create='story']")
    p2.fill("#scCap", "Who's coming to pickup Saturday?")
    p2.fill("#scQ", TEX[:8])
    p2.click(f"#scCands [data-scperson='{TEX}']")
    p2.click("[data-scpost]")
    wait_until(lambda: [x for x in state()["stories"] if x["u"] == AMY])
    p1.evaluate("loadState().then(()=>{ renderSocial(); notifyTags(); })")
    p1.wait_for_timeout(500)
    check("tagged person gets notified", "tagged you" in p1.locator("#toasts").inner_text())

    # Meet: wave both ways → friends → message
    nav(p2, "home"); p2.click("[data-dock='meet']"); p2.click("[data-mt='swipe']"); p2.click("[data-mtype='person']")
    p2.evaluate("h=>wave(h)", TEX)
    p2.wait_for_timeout(500)
    st = state()
    p1.evaluate("loadState().then(()=>{ meetTab='swipe'; renderMeet(); })"); p1.wait_for_timeout(400)
    nav(p1, "home"); p1.click("[data-dock='meet']"); p1.click("[data-mt='swipe']"); p1.click("[data-mtype='person']")
    top = p1.locator(".mcard.top").get_attribute("data-id")
    check("someone who waved at you comes first", top == "u:" + AMY, top or "")
    box = wait_until(lambda: p1.locator(".mcard.top").bounding_box(), 5)   # the deck can re-render mid-step
    p1.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2); p1.mouse.down()
    p1.mouse.move(box["x"] + box["width"] / 2 + 180, box["y"] + box["height"] / 2, steps=8); p1.mouse.up()
    p1.wait_for_timeout(900)
    check("swiping right on each other makes you friends", "You and @" + AMY in p1.locator("#toasts").inner_text())
    p1.locator("#toasts button", has_text="Say hi").first.click()
    p1.wait_for_selector("#dmIn")
    p1.fill("#dmIn", "Hey! Pickup Saturday?"); p1.press("#dmIn", "Enter")
    p1.wait_for_timeout(500)
    p2.evaluate("loadState().then(loadThreads).then(()=>{ meetTab='msgs'; DM.open=null; renderMeet(); })"); p2.wait_for_timeout(500)
    nav(p2, "home"); p2.click("[data-dock='meet']"); p2.click("[data-mt='msgs']")
    check("message arrives with an unread count", "Pickup Saturday" in p2.locator("#meetBody").inner_text() and p2.locator(".dmn").inner_text() == "1")
    p2.click(f"[data-thread='{TEX}']")
    p2.fill("#dmIn", "yes!! count me in"); p2.press("#dmIn", "Enter"); p2.wait_for_timeout(500)
    p2.screenshot(path=f"{OUT}/11-messages.png")
    check("reply saved", any(m["t"] == "yes!! count me in" for m in json.loads(p2.evaluate("fetch('/api/dm?with=" + TEX + "').then(r=>r.text())"))["msgs"]))
    # Scout, the in-app guide: guest FAQ + pointing, the look builder, driving mode
    ctx3, g = new_user(browser, "guest")
    g.click("[data-onbguest]")
    g.click("#scoutBtn"); g.wait_for_selector("#scoutBg", state="visible")
    check("Scout opens for guests", "Guest mode" in g.locator("#scoutLeft").inner_text())
    check("Scout panel: customize beside Scout, big translate button, no chip row",
          g.locator(".sc-top [data-sc='look']").is_visible() and g.locator(".scvoice [data-sc=lens]").is_visible() and g.locator(".scvoice [data-sc=identify]").is_visible() and g.locator("#scoutChips").count() == 0)
    g.evaluate("$('#scoutForm').hidden=false"); g.fill("#scoutIn", "How do I send a flare?"); g.press("#scoutIn", "Enter")
    g.wait_for_selector("#scoutRing", state="visible", timeout=5000)
    check("guest Scout answers from the FAQ and points at where flares are",
          "flare" in g.locator("#scoutBubble").inner_text().lower() and "Flare" in g.locator("#scoutTag").inner_text())
    g.screenshot(path=f"{OUT}/12-scout-point.png")
    g.evaluate("openLook()"); g.click("[data-lk='hat|crown']"); g.click("[data-lk='body|purple']")
    check("look builder changes the assistant", g.evaluate("scS().look.hat==='crown'&&scS().look.body==='purple'") and g.locator("#lookPrev svg").count() == 1)
    g.screenshot(path=f"{OUT}/13-scout-look.png")
    g.click("[data-sc='lookdone']")
    g.evaluate("scoutDrive(true)")
    check("driving mode covers the app", g.locator("#driveView").is_visible())
    g.screenshot(path=f"{OUT}/14-scout-driving.png")
    g.click("[data-sc='driveoff']")
    check("driving mode turns off", not g.locator("#driveView").is_visible())
    g.click("#scoutBtn"); g.click(".sc-top [data-sc='tourgo']")
    g.wait_for_selector("#scoutRing", state="visible", timeout=5000)
    check("Scout tour starts from the panel and points at the search box",
          "1/7" in g.locator("#scoutTour").inner_text() and "Search" in g.locator("#scoutTag").inner_text())
    g.screenshot(path=f"{OUT}/15-scout-tour.png")
    for _ in range(6):
        g.click("#scoutTour [data-sc='tournext']"); g.wait_for_timeout(450)
    last = g.locator("#scoutTour").inner_text()
    g.click("#scoutTour [data-sc='tournext']")
    check("tour walks all 7 steps and finishes", "7/7" in last and not g.locator("#scoutTour").is_visible()
          and g.evaluate("S.toured===true"), last.replace("\n", " ")[:80])
    ctx3.close()
    # signed-in Scout: Claude, or the friendly fallback if Claude can't be reached
    r = p1.evaluate("api('/api/scout',{q:'how do I edit my interests?',targets:scoutTargets(),context:scoutContext(),history:[]})")
    check("signed-in Scout answers", bool(r.get("say")) and r.get("expression") in SCOUT_FACES, r.get("say", "")[:80])
    targets = p1.evaluate("Object.keys(SC_T)")
    check("Scout only points at real buttons", all(a["type"] != "point" or a["target"] in targets for a in r.get("actions", [])))
    r2 = p1.evaluate("api('/api/scout',{q:'where is the flare button?',driving:true,targets:scoutTargets(),context:{},history:[]})")
    check("driving-mode answers never point at the screen", all(a["type"] in ("map", "place", "directions") for a in r2.get("actions", [])))
    # Scout doing things: an RSVP needs a tap, directions open the phone's Maps, a flare is only a draft
    ev2 = p1.evaluate("EV.list.find(e=>e.lat&&e.te>Date.now()&&myRsvp(e.id)!=='going').id")
    p1.evaluate("id=>scoutDo([{type:'rsvp',target:id}],'Want me to put you down?')", ev2)
    p1.wait_for_selector("#scoutTour [data-scard='0']", timeout=3000)
    check("Scout's RSVP waits for a tap", p1.evaluate("id=>myRsvp(id)", ev2) != "going")
    p1.click("#scoutTour [data-scard='0']"); p1.wait_for_timeout(500)
    check("tapping yes RSVPs you", p1.evaluate("id=>myRsvp(id)", ev2) == "going")
    p1.evaluate("id=>rsvp(id,'going')", ev2); p1.wait_for_timeout(300)        # undo, keeps later checks simple
    p1.evaluate("id=>scoutDo([{type:'directions',target:id}],'Here you go.')", ev2)
    p1.wait_for_selector("#scoutTour a[data-scard='0']", timeout=3000)
    href = p1.get_attribute("#scoutTour a[data-scard='0']", "href") or ""
    check("Scout directions hand off to the phone's Maps app", "maps.apple.com/?daddr=" in href or "google.com/maps/dir/" in href, href[:60])
    p1.screenshot(path=f"{OUT}/16-scout-directions.png")
    p1.click("#scoutTour button[data-scard]")                                 # 🗺: show it on the map
    n_before = len([x for x in state()["posts"] if x["u"] == TEX])
    p1.evaluate("scoutDo([{type:'flare',target:'Anyone down for pool at 9?'}],'Here is a draft.')"); p1.wait_for_timeout(600)
    check("Scout opens a flare draft without posting it", p1.locator("#sheetBg").is_visible()
          and p1.eval_on_selector("#cText", "e=>e.value") == "Anyone down for pool at 9?"
          and len([x for x in state()["posts"] if x["u"] == TEX]) == n_before)
    p1.click("#closeSheet")
    # report
    p2.click("#meetBody [data-more]"); p2.click("[data-report^='user']")
    p2.wait_for_timeout(400)
    if ADMIN:
        req = urllib.request.Request(BASE + "/api/admin", headers={"X-Admin-Token": ADMIN})
        adm = json.load(urllib.request.urlopen(req))
        check("report reaches the admin page", any(r["target"] == TEX for r in adm["reports"]))
    browser.close()

print("\nJS errors:", errors or "none")
failed = [r for r in results if not r[0]]
print(f"{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed or errors else 0)
