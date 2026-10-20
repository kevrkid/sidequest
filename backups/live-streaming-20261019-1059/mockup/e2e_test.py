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


def open_life(page, key):
    """About-you questions are grouped in collapsible sections; open the one holding `key`."""
    sec = page.evaluate("k=>LIFE.find(f=>f.k===k).sec", key)
    if page.evaluate("lifeOpen") != sec:
        page.click(f"[data-lifesec='{sec}']")


def state():
    return json.load(urllib.request.urlopen(BASE + "/api/state"))


def nav(page, where):
    """Move around the way a person would: Home quadrants, the header, and GO!."""
    if where == "me":
        page.click("#meChip"); return
    if not page.locator("#v-home").is_visible():
        page.click("#logo")                   # the logo goes Home; the ‹ button goes back
    if where == "feed":                       # Search menu → Everything
        page.click("[data-home='search']"); page.click("[data-sfocus='']")
    elif where == "party":                    # Meet → Groups → Friends & party
        page.click("[data-home='meet']"); page.click("[data-mt='groups']"); page.click("[data-gpeople]")
    elif where == "map":
        page.click("[data-home='go']")


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
    for i in interests:
        page.click(f"[data-onbi='{i}']")
    page.click("[data-onbguest]")
    check(f"{handle}: can look around without an account", "Sign up" in page.locator("#meChip").inner_text()
          and page.locator("#v-home").is_visible())
    page.wait_for_function("EV.loaded", timeout=20000)
    rid = page.evaluate("EV.list.filter(e=>e.te>Date.now()).at(-1).id")   # something far off, not tonight's top pick
    page.evaluate("id=>rsvp(id,'going')", rid)          # guests can RSVP; it's kept on the device
    page.click("[data-home='create']"); page.click("[data-create='flare']")
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

    # Home: four quadrants + GO!
    p1.wait_for_selector("#v-home:not([hidden]) .go")
    p1.wait_for_function("document.querySelector('#hsSearch').textContent.includes('events')", timeout=20000)
    p1.screenshot(path=f"{OUT}/00-home.png")
    labels = p1.eval_on_selector_all(".q4 .nm", "ns=>ns.map(n=>n.firstChild.textContent)")
    check("home has Meet/Search/Create/Live + GO!", labels == ["Meet", "Search", "Create", "Live"] and p1.locator(".go b").inner_text() == "GO!", str(labels))
    p1.wait_for_function("document.querySelectorAll('#goMap .leaflet-tile-loaded').length>0", timeout=15000)
    check("GO! shows a live map with your blue dot", p1.locator(".go .loc").is_visible())
    pos = p1.evaluate("ME_POS")
    check("uses the device's real location", abs(pos[0] - 30.2671) < 0.001 and abs(pos[1] + 97.7395) < 0.001, str(pos))
    p1.click("[data-home='search']")
    menu = p1.locator("#searchSheet").inner_text()
    check("Search asks what you want to do, by section", "What are you looking to do" in menu and all(x in menu for x in ["Sports", "Entertainment", "Going out", "Outdoors"]))
    p1.screenshot(path=f"{OUT}/00-search-menu.png")
    p1.click("[data-sfocus='comedy']")
    check("a Search tile opens the feed on that activity", p1.locator("#v-feed").is_visible() and "Comedy" in p1.locator("#feedCats .chip.on").inner_text())
    nav(p1, "home")
    p1.click("[data-home='meet']")
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
    nav(p1, "home")
    nav(p1, "home")
    p1.click("[data-home='go']")
    p1.wait_for_timeout(400)
    check("GO! pulls up the map", p1.locator("#v-map").is_visible() and p1.locator(".leaflet-tile-loaded").count() > 0)
    nav(p1, "home")
    p1.click("[data-home='create']")
    p1.screenshot(path=f"{OUT}/00-create.png")
    p1.click("[data-create='event']")
    check("Create → Event offers a date/time", p1.locator("#cAt").is_visible())
    p1.click("#closeSheet")

    # ---- food & drink (test places file: 24/7 tacos on Rainey, a 24h bar on 6th, a morning cafe, ...)
    nav(p1, "home"); p1.click("[data-home='search']")
    sm = p1.locator("#searchSheet").inner_text()
    check("Search has a Food & drink section with an Open now switch", "Food & drink" in sm and "Late-night eats" in sm
          and p1.locator("#searchSheet [data-popen]").count() == 1 and "Hot spots" in sm and "Rainey Street" in sm)
    p1.screenshot(path=f"{OUT}/70-food-search.png")
    p1.click("[data-pcat='tacos']"); p1.wait_for_selector("#placesSheet .prow", timeout=10000)
    pl = p1.locator("#placesSheet").inner_text()
    check("tacos open now: the 24/7 taco truck, with hours and distance", "Taco Test Trailer" in pl and "Open 24 hours" in pl and " mi" in pl, pl[:120].replace("\n", " | "))
    check("menu link and the OpenStreetMap hours note", p1.locator("#placesSheet a", has_text="Menu").count() == 1 and "may be out of date" in pl)
    p1.click("#placesSheet [data-pclose]"); p1.click("[data-pcat='bbq']"); p1.wait_for_timeout(800)
    open_bbq = p1.locator("#placesSheet").inner_text()
    p1.click("#placesSheet [data-popen]"); p1.wait_for_selector("#placesSheet .prow", timeout=10000)
    check("Open now switch: off shows closed spots with when they open", "Brisket Barn" in p1.locator("#placesSheet").inner_text()
          and ("Brisket Barn" not in open_bbq or "Open till" in open_bbq))
    p1.click("#placesSheet [data-popen]"); p1.wait_for_timeout(500)          # back on for later
    p1.click("#placesSheet [data-pclose]"); p1.click("[data-sclose]")
    # map: dots + hot spot zones
    nav(p1, "map"); p1.wait_for_function("PL.all && PL.hot", timeout=15000)
    p1.evaluate("map.setView([30.2650,-97.7390],15)"); p1.wait_for_timeout(800)
    dots = p1.evaluate("({open: Object.values(PL.cores).filter(l=>l.options.fillColor==='#3ddc97').length, all: Object.keys(PL.cores).length})")
    check("green open-now dots on the map", dots["open"] >= 2 and dots["all"] >= 4, json.dumps(dots))
    check("8 glowing hot-spot zones with labels", p1.locator("path.hotzone").count() == 8 and "6th Street" in p1.locator(".hotlabel").all_inner_texts().__str__())
    p1.screenshot(path=f"{OUT}/71-map-food.png")
    p1.evaluate("PL.zones.getLayers().find(l=>l.hotId==='rainey').fire('click')")
    p1.wait_for_selector("#placesSheet .prow", timeout=10000)
    check("tapping a hot spot lists what's open there", "Rainey Street" in p1.locator("#placesSheet").inner_text() and "Taco Test Trailer" in p1.locator("#placesSheet").inner_text())
    # back: closes the sheet first, then goes to the previous screen
    p1.go_back(); p1.wait_for_timeout(300)            # the phone's back (Android button / swipe) while a sheet is open
    check("back closes the open sheet first", p1.locator("#placesBg").is_hidden() and p1.locator("#v-map").is_visible())
    p1.click("#homeBtn"); p1.wait_for_timeout(300)
    check("back again returns to the previous screen", p1.evaluate("curTab") != "map", p1.evaluate("curTab"))
    nav(p1, "feed"); p1.wait_for_timeout(200)
    p1.evaluate("""()=>{ const app=document.querySelector('#app'), r=app.getBoundingClientRect();
      const mk=(type,x)=>{ const t=new Touch({identifier:1,target:app,clientX:r.left+x,clientY:400}); app.dispatchEvent(new TouchEvent(type,{touches:type==='touchend'?[]:[t],changedTouches:[t],bubbles:true})); };
      mk('touchstart',8); mk('touchmove',60); mk('touchmove',140); mk('touchend',140); }""")
    p1.wait_for_timeout(400)
    check("swipe in from the left edge goes back", p1.evaluate("curTab") != "feed", p1.evaluate("curTab"))
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
    nav(p1, "me")
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

    p1.fill("[data-lifetext='hometown']", "El Paso, TX")
    p1.dispatch_event("[data-lifetext='hometown']", "change")
    for k, v in [("grewUp", "Big city"), ("siblings", "3"), ("birthOrder", "Oldest"), ("kidWas", "Sporty one"),
                 ("kidActivities", "Sports team"), ("schedule", "Night owl"), ("music", "Latin"), ("music", "Rock"),
                 ("weekend", "Up early, outdoors"), ("goals", "Teammates"), ("friendLang", "Doing things together"),
                 ("values", "Loyalty"), ("drinks", "Socially")]:
        open_life(p1, k)
        p1.click(f"[data-life='{k}'][data-opt='{v}']")
    open_life(p1, "hometown")
    for k in ("hometown", "interests"):          # match-only -> friends -> everyone
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
    meta = p1.locator("#feedMeta").inner_text()
    check("feed loads real events", "event" in meta, meta)
    first = p1.locator("#feedList .card").first.inner_text()
    p1.screenshot(path=f"{OUT}/03-feed.png")
    reasons = p1.locator("#feedList").inner_text()
    check("feed explains picks from interests/profile", "You're into" in reasons or "You love" in reasons or "here for" in reasons)

    p1.fill("#feedQ", "comedy")
    p1.wait_for_timeout(300)
    n_comedy = p1.locator("#feedList [data-rsvp][data-st='going']").count()
    check("search filters the feed", n_comedy > 0, f"{n_comedy} matches for 'comedy'")
    p1.fill("#feedQ", "")
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
    p1.wait_for_selector(".leaflet-popup-content", timeout=5000)
    pop = p1.locator(".leaflet-popup-content").inner_text()
    check("event shows on the map with RSVP state", ev_title[:20] in pop and "Going" in pop, pop[:60])
    p1.screenshot(path=f"{OUT}/05-map-event.png")
    nav(p1, "feed")
    p1.click("#feedMapBtn")
    p1.wait_for_timeout(500)
    pins = p1.locator(".pin.ev").count()
    check("'Map it' puts the feed on the map", pins > 5, f"{pins} event pins")
    p1.screenshot(path=f"{OUT}/06-map-feed.png")

    # Groups + posting
    nav(p1, "party")
    if p1.locator("#groupList [data-gopen='g1'] [data-gjoin]").count():   # the group swipe may have joined it already
        p1.click("#groupList [data-gopen='g1'] [data-gjoin]")
    p1.wait_for_timeout(400)
    check("joined a group (server)", TEX in state()["members"].get("g1", []))
    p1.click("#groupList [data-gopen='g1'] .grow")
    p1.click("[data-gpost='g1']")
    p1.fill("#cText", "7v7 pickup at Zilker Saturday 10am, need 4 more, all levels")
    p1.select_option("#cKind", "pickup")
    p1.click("#compose button.primary")
    posts = wait_until(lambda: [x for x in state()["posts"] if x["u"] == TEX])
    check("group post saved on the server", posts and posts[0].get("group") == "g1")

    # Story: photo + event + group + person tags
    nav(p1, "home")
    p1.click("[data-home='create']")
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
    p2.fill("#feedQ", "Zilker Saturday")
    p2.wait_for_timeout(300)
    check("2nd user sees the group post", "need 4 more" in p2.locator("#feedList").inner_text())
    p2.fill("#feedQ", "")
    going = p2.evaluate("id=>goingList(EV.byId[id])", ev_id)
    check("2nd user sees 1st user's RSVP", TEX in going, ",".join(going))
    nav(p2, "party")
    sug = p2.locator("#suggestList").inner_text()
    check("1st user is suggested to the 2nd", TEX in sug)
    p2.screenshot(path=f"{OUT}/07-amy-people.png")
    nav(p2, "feed")
    p2.fill("#feedQ", "Zilker Saturday")
    p2.locator(f"#feedList [data-down='{posts[0]['id']}']").click()
    p2.wait_for_timeout(400)
    check("2nd user said 'I'm down' to the post", AMY in next(x for x in state()["posts"] if x["id"] == posts[0]["id"])["downs"])

    nav(p2, "map")
    p2.click("[data-mf='stories']")
    p2.wait_for_timeout(400)
    check("stories show as bubbles on the map", p2.locator(".sbub").count() >= 3, f"{p2.locator('.sbub').count()} bubbles")
    p2.click("[data-mf='all']")
    p2.wait_for_timeout(300)
    n_live = p2.locator(".lthumb:not(.sm)").count()
    check("live streamers show preview thumbnails on the map", n_live >= 3, f"{n_live} thumbnails")
    p2.screenshot(path=f"{OUT}/09-map-stories.png")
    nav(p2, "feed")
    p2.fill("#feedQ", "")
    p2.click(f"#feedList [data-stuser='{TEX}']")
    p2.wait_for_selector("#storyView:not([hidden]) .media")
    sv = p2.locator("#storyView").inner_text()
    check("story viewer shows caption and all tags", "Front row" in sv and "@nitro_nate" in sv and "ATX Pickup Soccer" in sv, sv.replace("\n", " | ")[:120])
    p2.screenshot(path=f"{OUT}/10-story-view.png")
    p2.click("#storyView [data-stev]")
    p2.wait_for_selector(".leaflet-popup-content", timeout=5000)
    check("tapping the event tag opens it on the map", p2.locator("#v-map").is_visible())
    # tag user 1 back in a text story
    nav(p2, "home")
    p2.click("[data-home='create']")
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
    nav(p2, "home"); p2.click("[data-home='meet']"); p2.click("[data-mt='swipe']"); p2.click("[data-mtype='person']")
    p2.evaluate("h=>wave(h)", TEX)
    p2.wait_for_timeout(500)
    st = state()
    p1.evaluate("loadState().then(()=>{ meetTab='swipe'; renderMeet(); })"); p1.wait_for_timeout(400)
    nav(p1, "home"); p1.click("[data-home='meet']"); p1.click("[data-mtype='person']")
    top = p1.locator(".mcard.top").get_attribute("data-id")
    check("someone who waved at you comes first", top == "u:" + AMY, top or "")
    box = p1.locator(".mcard.top").bounding_box()
    p1.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2); p1.mouse.down()
    p1.mouse.move(box["x"] + box["width"] / 2 + 180, box["y"] + box["height"] / 2, steps=8); p1.mouse.up()
    p1.wait_for_timeout(900)
    check("swiping right on each other makes you friends", "You and @" + AMY in p1.locator("#toasts").inner_text())
    p1.locator("#toasts button", has_text="Say hi").first.click()
    p1.wait_for_selector("#dmIn")
    p1.fill("#dmIn", "Hey! Pickup Saturday?"); p1.press("#dmIn", "Enter")
    p1.wait_for_timeout(500)
    p2.evaluate("loadState().then(loadThreads).then(()=>{ meetTab='msgs'; DM.open=null; renderMeet(); })"); p2.wait_for_timeout(500)
    nav(p2, "home"); p2.click("[data-home='meet']"); p2.click("[data-mt='msgs']")
    check("message arrives with an unread dot", "Pickup Saturday" in p2.locator("#meetBody").inner_text() and p2.locator(".dot-unread").count() == 1)
    p2.click(f"[data-thread='{TEX}']")
    p2.fill("#dmIn", "yes!! count me in"); p2.press("#dmIn", "Enter"); p2.wait_for_timeout(500)
    p2.screenshot(path=f"{OUT}/11-messages.png")
    check("reply saved", any(m["t"] == "yes!! count me in" for m in json.loads(p2.evaluate("fetch('/api/dm?with=" + TEX + "').then(r=>r.text())"))["msgs"]))
    # Scout, the in-app guide: guest FAQ + pointing, the look builder, driving mode
    ctx3, g = new_user(browser, "guest")
    g.click("[data-onbguest]")
    g.click("#scoutBtn"); g.wait_for_selector("#scoutBg", state="visible")
    check("Scout opens for guests", "Guest mode" in g.locator("#scoutLeft").inner_text())
    g.click("[data-scq='How do I send a flare?']")
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
    ctx3.close()
    # signed-in Scout: Claude, or the friendly fallback if Claude can't be reached
    r = p1.evaluate("api('/api/scout',{q:'how do I edit my interests?',targets:scoutTargets(),context:scoutContext(),history:[]})")
    check("signed-in Scout answers", bool(r.get("say")) and r.get("expression") in SCOUT_FACES, r.get("say", "")[:80])
    targets = p1.evaluate("Object.keys(SC_T)")
    check("Scout only points at real buttons", all(a["type"] != "point" or a["target"] in targets for a in r.get("actions", [])))
    r2 = p1.evaluate("api('/api/scout',{q:'where is the flare button?',driving:true,targets:scoutTargets(),context:{},history:[]})")
    check("driving-mode answers never point at the screen", all(a["type"] == "map" for a in r2.get("actions", [])))
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
