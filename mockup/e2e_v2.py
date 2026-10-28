"""End-to-end test of the V2 features: two new people on phone-sized screens, one invited by the other.

  SQ_BASE=http://localhost:8798 SQ_ADMIN_TOKEN=test python e2e_v2.py <shot-dir>

Server: SQ_SIGHTS_FILE=test_sights.json SQ_PLACES_FILE=test_places.json SQ_OUTDOORS_FILE=test_outdoors.json, empty
data/app.json, the events service running (real events are used for the event checks).
"""
import json
import os
import random
import sys
import urllib.request

from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8798")
ADMIN = os.environ.get("SQ_ADMIN_TOKEN", "")
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
N = random.randint(100, 999)
AMY, BO = f"v2_amy{N}", f"v2_bo{N}"
MARKER = {"latitude": 30.2690, "longitude": -97.7420, "accuracy": 15}   # test_sights.json m9001
results, errors = [], []
BLANK_TILE = __import__("base64").b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""))


def new_page(browser, label, url="/", geo=None):
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2,
                              geolocation={"accuracy": 15, **(geo or {"latitude": 30.2671, "longitude": -97.7395})}, permissions=["geolocation"])
    ctx.route(lambda u: "fonts.googleapis.com" in u or "fonts.gstatic.com" in u or ("tile.openstreetmap.org" in u or "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u)), lambda r: r.abort())
    ctx.route(lambda u: ("tile.openstreetmap.org" in u or "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u)), lambda r: r.fulfill(status=200, content_type="image/png", body=BLANK_TILE))
    page = ctx.new_page()
    page.on("pageerror", lambda e: errors.append(f"{label}: {e}"))
    page.goto(BASE + url)
    page.wait_for_selector("[data-onbguest]", timeout=10000)
    return ctx, page


def sign_up(page, handle):
    if page.locator("[data-onbmore]").count():   # the welcome shows a dozen first
        page.click("[data-onbmore]")
    for i in ("music", "comedy", "outdoors"):
        page.click(f"[data-onbi='{i}']")
    page.click("[data-onbguest]")
    try:
        page.wait_for_selector("#scoutTour", state="visible", timeout=2500); page.click("#scoutTour [data-sc='tourend']")
    except Exception:
        pass
    page.evaluate("needAccount('try V2')")
    if page.locator("#onb [data-onbmode='signup']").count():
        page.click("#onb [data-onbmode='signup']")
    page.fill("#onbH", handle); page.fill("#onbP", "correct horse 9")
    page.check("#onbAdult"); page.check("#onbTerms")
    page.click("[data-onbnext]")
    page.wait_for_selector("#onbBg", state="hidden", timeout=15000)
    page.wait_for_function("EV.loaded && SV.v2", timeout=20000)


def close_sheets(page):
    page.evaluate("document.querySelectorAll('.sheet-bg').forEach(x=>x.hidden=true)")


def notifs(page):
    return page.evaluate("api('/api/notifs',{}).then(j=>j.notifs)")


with sync_playwright() as pw:
    browser = pw.chromium.launch()
    actx, a = new_page(browser, "amy", geo=MARKER)
    sign_up(a, AMY)
    check("bell shows in the header once signed in", a.is_visible("#bellBtn"))
    a.evaluate("tab('me')"); a.wait_for_timeout(300)
    check("You: no row of zeros for someone new (level shows once there is something)", ("Lv 1" in a.inner_text("#youStats")) == bool(a.evaluate("(SV.v2?.coins||0)>0||(SV.v2?.day_streak||0)>0")))
    a.evaluate("tab('home','peek')")
    check("Home: 'Tonight near you' strip with events", a.locator("#homeTonight .tncard").count() >= 1 or a.evaluate(
        "!EV.list.some(e=>e.te>Date.now()&&e.ts<new Date().setHours(28,0,0,0)&&!e.tba&&e.lat)"))
    a.screenshot(path=f"{OUT}/v2-01-home.png")

    # ---- invite link: Bo arrives through Amy's link and becomes her friend at sign-up
    code = a.evaluate("SV.v2.invite")
    share = urllib.request.urlopen(f"{BASE}/i/{AMY}/{code}").read().decode()
    check("invite link page has a link preview", f"@{AMY} invited you" in share and 'og:title' in share)
    bctx, b = new_page(browser, "bo", url=f"/i/{AMY}/{code}")
    check("invite link opens the app and remembers who invited", b.evaluate("S.ref") == AMY, b.evaluate("S.ref"))
    if b.locator("[data-onbmore]").count():      # the welcome shows a dozen first
        b.click("[data-onbmore]")
    for i in ("music", "food", "art"):
        b.click(f"[data-onbi='{i}']")
    b.click("[data-onbguest]")
    b.evaluate("needAccount('try V2')")
    if b.locator("#onb [data-onbmode='signup']").count():
        b.click("#onb [data-onbmode='signup']")
    check("sign-up offers 'be friends with whoever invited you' (on by default)", b.is_checked("#onbRef"))
    b.fill("#onbH", BO); b.fill("#onbP", "correct horse 9"); b.check("#onbAdult"); b.check("#onbTerms")
    b.click("[data-onbnext]"); b.wait_for_selector("#onbBg", state="hidden", timeout=15000)
    b.wait_for_function("EV.loaded && SV.v2", timeout=20000)
    check("…and they're friends right away", AMY in b.evaluate("SV.friends.list"))
    a.evaluate("loadState().then(renderSocial)"); a.wait_for_timeout(600)
    check("the inviter's bell lights up", a.inner_text("#bellN") not in ("", "0"), a.inner_text("#bellN"))
    a.click("#bellBtn"); a.wait_for_selector("#notifSheet .nrow")
    check("inbox: 'joined from your invite'", "joined from your invite" in a.inner_text("#notifSheet"))
    a.screenshot(path=f"{OUT}/v2-02-inbox.png")
    a.wait_for_timeout(1600); a.evaluate("loadState().then(renderBell)"); a.wait_for_timeout(400)
    check("opening the inbox marks it read", a.inner_text("#bellN") == "")
    close_sheets(a)

    # ---- event details
    ev = a.evaluate("(EV.list.find(e=>e.lat&&e.geo_precise&&e.te>Date.now()&&!e.tba)||EV.list.find(e=>e.lat&&e.te>Date.now())).id")
    title = a.evaluate("id=>EV.byId[id].title", ev)
    a.evaluate("tab('feed')"); a.wait_for_timeout(400)
    a.evaluate("id=>openEvent(id)", ev); a.wait_for_selector("#evSheet .evtitle")
    check("event details: title, when, actions", title in a.inner_text("#evSheet") and a.locator("#evSheet [data-evinvite]").count() == 1)
    a.click("#evSheet [data-rsvp][data-st='going']"); a.wait_for_timeout(700)
    check("going from the details sheet", a.evaluate("id=>myRsvp(id)", ev) == "going" and "Going" in a.inner_text("#evSheet .evmain"))
    a.click("#evSheet [data-v2save]"); a.wait_for_timeout(600)
    check("favorite an event", a.evaluate("id=>isSaved('event',id)", ev) and "❤️" in a.inner_text("#evSheet .evmain"))
    a.fill("#evChatIn", "Who wants to meet at the door at 7?"); a.click("#evChatForm button")
    a.wait_for_function("document.querySelector('#evChat')?.innerText.includes('meet at the door')", timeout=40000)   # screened by Claude first
    check("post in the event's discussion", "meet at the door" in a.inner_text("#evChat"))
    a.screenshot(path=f"{OUT}/v2-03-event.png")
    close_sheets(a)

    b.evaluate("id=>openEvent(id)", ev); b.wait_for_selector("#evSheet .evtitle")
    try: b.wait_for_function("document.querySelector('#evChat')?.innerText.includes('meet at the door')", timeout=8000)
    except Exception: pass
    check("the other person sees the discussion", "meet at the door" in b.inner_text("#evChat"))
    b.click("#evChat [data-more]"); b.wait_for_selector("#actSheet [data-report]")
    b.click("#actSheet [data-report*='Harassment']"); b.wait_for_timeout(600)
    check("report a chat message from its ⋯ menu", "Thanks for reporting" in b.inner_text("#toasts"))
    b.evaluate("$('#actBg').hidden=true")
    b.click("#evSheet [data-rsvp][data-st='going']"); b.wait_for_timeout(700)
    b.wait_for_function("SV.rsvps && true"); a.evaluate("loadState().then(renderSocial)"); a.wait_for_timeout(500)
    a.evaluate("id=>openEvent(id)", ev); a.wait_for_timeout(500)
    check("friends going show by name on the sheet", BO in a.inner_text("#evSheet .evwho"))
    close_sheets(a)
    check("a friend going to the same event gets a heads-up", any(n["t"] == "going" and BO in n["text"] for n in notifs(a)))
    b.click("#evSheet [data-evinvite]"); b.wait_for_selector("#invList")
    b.check(f"#invList input[value='{AMY}']"); b.click("[data-invsend]"); b.wait_for_timeout(800)
    dm = a.evaluate(f"fetch('/api/dm?with={BO}').then(r=>r.json()).then(j=>j.msgs.map(m=>m.t))")
    check("invite a friend: they get a message with the event link", any("/e/" in m for m in dm), dm)
    check("…and an 'invited you' notification", any(n["t"] == "invite" for n in notifs(a)))
    close_sheets(b)

    # ---- share link → link preview → opens the sheet
    uid = ev.split(":", 1)[1]
    page = urllib.request.urlopen(f"{BASE}/e/{uid}").read().decode()
    check("event share page has Open Graph tags", 'property="og:title"' in page and "Side Quest" in page)
    b.goto(f"{BASE}/e/{uid}"); b.wait_for_selector("#evSheet .evtitle", timeout=20000)
    check("opening a shared link lands on the event", title in b.inner_text("#evSheet .evtitle") and "?" not in b.url, b.url)
    close_sheets(b)

    # ---- favorites on the profile (My plans links there)
    a.evaluate("openPlans()"); a.wait_for_selector("#plansSheet [data-quick='favs']", timeout=8000)
    a.click("#plansSheet [data-quick='favs']"); a.wait_for_selector("#favCard .prow", timeout=8000)
    check("My plans → My favorites: the profile lists it", title[:20] in a.inner_text("#favCard") and not a.is_hidden("#v-me"))
    a.click("#favCard [data-v2save]"); a.wait_for_timeout(700)
    check("remove from favorites", a.locator("#favCard .prow").count() == 0)
    close_sheets(a)

    # ---- check in at a historical marker → XP → quest progress
    a.evaluate("tab('map'); startLocating(true)"); a.wait_for_function("ME_FIX>0", timeout=10000)
    a.evaluate("sightPopup('m9001')"); a.wait_for_selector("#exPop [data-checkin2]", timeout=10000)
    a.click("#exPop [data-checkin2]"); a.wait_for_timeout(900)
    check("check in at a marker you're standing at: +XP", "XP" in a.inner_text("#toasts"), a.inner_text("#toasts")[:80])
    a.evaluate("map.closePopup(); sightPopup('m9002')"); a.wait_for_selector("#exPop [data-checkin2]")
    bctx2 = None
    actx.set_geolocation({"latitude": 30.20, "longitude": -97.80, "accuracy": 15}); a.wait_for_timeout(1500)
    a.click("#exPop [data-checkin2]"); a.wait_for_timeout(700)
    check("too far away: no check-in, says how far", "away" in a.inner_text("#toasts"))
    a.evaluate("map.closePopup(); openQuests()"); a.wait_for_selector("#questSheet .qcard"); a.wait_for_selector("#lbRows .lbrow")   # the board loads on its own
    qs = a.inner_text("#questSheet")
    check("quests: level, XP and the History buff at 1/5", "LEVEL" in qs and "1/5" in qs)
    check("friends leaderboard lists both", AMY in qs and BO in qs)
    a.screenshot(path=f"{OUT}/v2-04-quests.png")
    a.click("#questSheet [data-sharetoggle]"); a.wait_for_timeout(700)
    close_sheets(a)
    b.evaluate("loadState().then(()=>{ document.querySelectorAll('.sheet-bg').forEach(x=>x.hidden=true); tab('home'); renderHome(); })"); b.wait_for_timeout(800)
    check("a friend who shares check-ins shows under 'Friends out now' on Home", AMY in b.inner_text("#homeTonight") and "Test Moonlight Tower" in b.inner_text("#homeTonight"),
          b.inner_text("#homeTonight")[:120])

    a.evaluate("loadState().then(()=>{ tab('me'); showMeSec('profile'); renderMe(); })"); a.wait_for_timeout(600)
    check("your own profile shows your level and XP", a.is_visible("#myQuest") and "XP" in a.inner_text("#myQuest"))
    a.evaluate("tab('home')")

    # ---- group chat (members only)
    gid = b.evaluate("api('/api/group/create',{n:'V2 Test Runners',d:'Easy 5k loops',e:'🏃',cat:'sports'}).then(j=>j.group.id)")
    b.evaluate("loadState()"); b.wait_for_timeout(500)
    b.evaluate(f"openGroup('{gid}')"); b.click("[data-gtab='chat']"); b.wait_for_selector("#gChatForm")   # the chat has its own tab
    b.fill("#gChatIn", "Saturday 8am at the bridge?"); b.click("#gChatForm button")
    b.wait_for_function("document.querySelector('#gChat')?.innerText.includes('8am at the bridge')", timeout=40000)
    check("group chat: members can talk", True)
    a.evaluate("loadState()"); a.wait_for_timeout(500); a.evaluate(f"openGroup('{gid}')"); a.wait_for_timeout(500)
    check("…non-members don't see the chat until they join", a.locator("#gChat").count() == 0 and a.locator("[data-gtab='chat']").count() == 0)
    close_sheets(a); close_sheets(b)

    # ---- profile badges between friends
    b.evaluate("loadState()"); b.wait_for_timeout(400); b.evaluate(f"openProfile('{AMY}')"); b.wait_for_timeout(300)
    check("a friend's profile shows their quest level", "Lv" in b.inner_text("#actSheet"))
    close_sheets(b)

    # ---- analytics
    if ADMIN:
        g = json.loads(urllib.request.urlopen(urllib.request.Request(f"{BASE}/api/admin/growth", headers={"X-Admin-Token": ADMIN})).read())
        check("admin growth: today's actives and tracked events", g["dau"][-1] >= 2 and g["events"].get("event_open", 0) >= 2, g["events"])
        adm = json.loads(urllib.request.urlopen(urllib.request.Request(f"{BASE}/api/admin", headers={"X-Admin-Token": ADMIN})).read())
        rep = [r for r in adm["reports"] if r["kind"] == "chat"]
        check("admin: the chat report shows who wrote it and what it said", rep and rep[0].get("about") == AMY and "meet at the door" in rep[0].get("note", ""), rep[:1])
    else:
        check("admin growth (skipped: no SQ_ADMIN_TOKEN)", True)

    # ---- map: decluttered, markets on weekends, no guessed event spots
    a.evaluate("tab('map'); applyPreset('all'); $('#placesBg').hidden=true; S.mapWhen='week'; refreshMapLayers()"); a.wait_for_timeout(1200)
    a.evaluate("void map.setView([30.2680,-97.7420],16,{animate:false})"); a.wait_for_timeout(1200)
    boxes = a.evaluate("[...document.querySelectorAll('.mlabel')].map(e=>{const r=e.getBoundingClientRect();return [r.left,r.top,r.right,r.bottom]})")
    over = sum(1 for i, p in enumerate(boxes) for q in boxes[i+1:] if p[0] < q[2]-1 and q[0] < p[2]-1 and p[1] < q[3]-1 and q[1] < p[3]-1)
    check("map names never sit on top of each other", len(boxes) >= 1 and over == 0, f"{len(boxes)} names, {over} overlaps")
    n16 = a.evaluate("SG.layer.getLayers().length + Object.keys(PL.cores).length")
    a.evaluate("void map.setView([30.2680,-97.7420],14,{animate:false})"); a.wait_for_timeout(1200)
    n14 = a.evaluate("SG.layer.getLayers().length + Object.keys(PL.cores).length")
    check("zoomed out never shows more spots than up close", n14 <= n16, f"zoom 14: {n14}, zoom 16: {n16}")
    check("events without a real spot get no pin (not dropped on downtown)",
          a.evaluate("EV.list.filter(e=>e.geo_none).every(e=>!e.lat&&!markers[e.id])"))
    a.evaluate("austinMow=()=>5*1440+8*60; FM.list=[{id:'fmT',name:'Test Farmers Market',hours:'Sa 09:00-13:00',lat:30.30,lng:-97.70,week:[[7740,7980]]}]; void map.setView([30.30,-97.74],11,{animate:false})")
    a.wait_for_timeout(1200)
    check("Saturday morning: the farmers market shows big from zoomed out, with its hours",
          a.locator(".fmpin.soon").count() >= 1 and any("Sat 9 AM" in t for t in a.locator(".mlabel.market").all_inner_texts()),
          a.evaluate("JSON.stringify({pins:document.querySelectorAll('.fmpin').length, on:S.mapL.markets, z:map.getZoom(), soon:FM.list.map(fmSoon), labels:[...document.querySelectorAll('.mlabel.market')].map(e=>e.innerText)})"))
    a.locator(".fmpin.soon").first.click(); a.wait_for_timeout(300)
    check("tapping a market shows its day, hours and directions", "Sat 9 AM–1 PM" in a.locator(".leaflet-popup-content").last.inner_text())

    check("no JavaScript errors", not errors, errors[:3])
    browser.close()

ok = sum(1 for r in results if r[0])
print(f"\n{ok}/{len(results)} passed")
sys.exit(0 if ok == len(results) else 1)
