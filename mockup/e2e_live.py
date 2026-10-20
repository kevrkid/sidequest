"""Live video end to end on the phone-to-phone path (no LiveKit): one streamer and three viewers, each with
their own account and browser, then Report while watching and the admin's End stream.

Start a server without SQ_LIVEKIT_* and with an admin token, on a copy so your data is untouched, e.g.
  SQ_DEMO=0 SQ_MODERATE=0 SQ_ADMIN_TOKEN=test PORT=8796 SQ_PLACES_FILE=test_places.json ruby server.rb
then:  SQ_BASE=http://localhost:8796 SQ_ADMIN_TOKEN=test python e2e_live.py <shot-dir>
"""
import json
import os
import random
import sys
import time
import urllib.request

from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
ADMIN = os.environ.get("SQ_ADMIN_TOKEN", "")
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
VIEWERS = int(os.environ.get("SQ_VIEWERS", "3"))
SUFFIX = random.randint(100, 999)
STREAMER = f"test_live{SUFFIX}"
results, errors = [], []


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""))


def admin(body=None):
    req = urllib.request.Request(BASE + "/api/admin", data=json.dumps(body).encode() if body else None,
                                 headers={"X-Admin-Token": ADMIN, "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))


def person(browser, h):
    """A brand-new account in its own browser, signed in, on Home."""
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, permissions=["camera", "microphone"])
    ctx.route(lambda u: "fonts.g" in u or "tile.openstreetmap.org" in u, lambda r: r.abort())
    page = ctx.new_page()
    page.on("pageerror", lambda e: errors.append(f"{h}: {e}"))
    page.goto(BASE)
    page.evaluate("""h => fetch('/api/signup', {method: 'POST', headers: {'Content-Type': 'application/json'},
                       body: JSON.stringify({h, pw: 'correct horse 9', adult: true, terms: true})})""", h)
    page.reload()
    page.wait_for_function("AUTHED === true", timeout=15000)
    return page


def playing(page):
    """The viewer's video has real frames and keeps moving."""
    try:
        page.wait_for_function("WATCHV.videoWidth > 0 && WATCHV.currentTime > 0", timeout=25000)
        t = page.evaluate("WATCHV.currentTime"); time.sleep(1.5)
        return page.evaluate("WATCHV.currentTime") > t
    except Exception:
        return False


with sync_playwright() as pw:
    browser = pw.chromium.launch(args=["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"])
    s = person(browser, STREAMER)
    viewers = [person(browser, f"test_view{SUFFIX}{i}") for i in range(VIEWERS)]

    # streamer: Live → Go live → phone camera (Chrome's fake camera here) → title → Go live
    s.click("[data-home='live']"); s.click("[data-golive]"); s.click("[data-camon]")
    s.wait_for_function("LIVE.stream && PREVIEW.videoWidth > 0", timeout=15000)
    s.fill("#lvTitle", "Test stream from the e2e run")
    check("location delay defaults to 5 minutes", s.evaluate("LIVE.draft.delay") == 5)
    s.click("[data-startlive]")
    check("streamer is live", s.evaluate("LIVE.on") is True)
    sid = s.evaluate("LIVE.my.id")
    s.screenshot(path=f"{OUT}/live-1-streamer.png")

    # viewers: the stream shows up in Live, and each one watches it
    for i, v in enumerate(viewers):
        v.click("[data-home='live']")
        watch = f"#v-live [data-watch='{sid}']"   # the same button also sits in the map's live strip and Home
        v.wait_for_selector(watch, timeout=15000)
        if i == 0:
            st = v.evaluate("id => LIVE.remote[id]", sid)
            check("viewers see the stream under the streamer's real handle", st["u"] == STREAMER, st["u"])
            check("the spot stays hidden during the location delay", st.get("v") is None, str(st.get("v")))
        v.click(watch)
    ok = [playing(v) for v in viewers]
    check(f"{VIEWERS} viewers watch the camera at once", all(ok), str(ok))
    time.sleep(1.5)
    n = s.evaluate("Object.keys(PCS).length")
    if s.evaluate("!!CFG.livekit"):   # one upload to LiveKit, which fans out; nobody on the direct path
        lk = [v.evaluate("!!LK.view") for v in viewers]
        check(f"through LiveKit: streamer uploads once, all {VIEWERS} viewers on the relay",
              s.evaluate("!!LK.room") and n == 0 and all(lk), f"{n} direct connections, relay viewers {lk}")
    else:
        check(f"streamer sends to {VIEWERS} viewers (one copy each on this path)", n == VIEWERS, f"{n} connections")
    stat = s.locator("#lvStat").inner_text()
    check("streamer's viewer count is real", stat.startswith(f"👁 {VIEWERS} "), stat)
    viewers[0].screenshot(path=f"{OUT}/live-2-viewer.png")

    # Report while watching: ⋯ next to the streamer → a reason
    v = viewers[0]
    v.click(f"[data-more='stream|{sid}|{STREAMER}']")
    check("watch screen has Report / Block", "Report this stream" in v.locator("#actSheet").inner_text())
    v.screenshot(path=f"{OUT}/live-3-report.png")
    v.click(f"[data-report='stream|{sid}|Harassment']")
    v.wait_for_selector("#actBg", state="hidden", timeout=5000)
    rep = next((r for r in admin()["reports"] if r["target"] == sid), None)
    check("the report reaches the admin page, naming the streamer", rep and rep.get("about") == STREAMER, str(rep))
    check("admin sees who is live", any(x["h"] == STREAMER for x in admin()["live"]))

    # admin: End stream
    admin({"action": "end_stream", "h": STREAMER})
    try:
        s.wait_for_function("LIVE.on === false", timeout=10000); stopped = True
    except Exception:
        stopped = False
    check("End stream stops the streamer's app and says why", stopped and "moderator" in s.locator("#toasts").inner_text().lower())
    gone = []
    for v in viewers:
        try:
            v.wait_for_function("id => !LIVE.remote[id] && LIVE.watch === null && !WATCHV.srcObject", arg=sid, timeout=10000); gone.append(True)
        except Exception:
            gone.append(False)
    check("every viewer is dropped", all(gone), str(gone))
    s.screenshot(path=f"{OUT}/live-4-stopped.png")
    s.click("[data-golive]") if s.locator("[data-golive]").count() else None
    if s.locator("[data-camon]").count():
        s.click("[data-camon]"); s.wait_for_function("LIVE.stream && PREVIEW.videoWidth > 0", timeout=15000)
        s.click("[data-startlive]")
        try:
            s.wait_for_function("LIVE.on === false", timeout=8000); relock = True
        except Exception:
            relock = False
        check("they can't go straight back live", relock)

    # A streamer ends their own stream: viewers are told and dropped (this message was commented out before V2)
    s2, w2 = viewers[1], viewers[2] if len(viewers) > 2 else viewers[0]
    s2.evaluate("tab('live'); LIVE.mode='list'; renderLive()"); s2.click("[data-golive]"); s2.click("[data-camon]")
    s2.wait_for_function("LIVE.stream && PREVIEW.videoWidth > 0", timeout=15000)
    s2.fill("#lvTitle", "Second test stream"); s2.click("[data-startlive]")
    sid2 = s2.evaluate("LIVE.my.id")
    w2.evaluate("tab('live'); LIVE.mode='list'; renderLive()"); w2.wait_for_selector(f"#v-live [data-watch='{sid2}']", timeout=15000); w2.click(f"#v-live [data-watch='{sid2}']")
    w2.wait_for_function("id => LIVE.watch === id", arg=sid2, timeout=10000)
    s2.click("[data-endlive]")
    try:
        w2.wait_for_function("id => LIVE.watch === null && !LIVE.remote[id]", arg=sid2, timeout=10000); dropped = True
    except Exception:
        dropped = False
    check("ending your own stream tells viewers it ended", dropped and "stream ended" in w2.locator("#toasts").inner_text().lower())
    browser.close()

real_errors = [e for e in errors if "Failed to load resource" not in e]
print("\nJS errors:", real_errors or "none")
passed = sum(1 for ok, *_ in results if ok)
print(f"{passed}/{len(results)} passed")
sys.exit(0 if passed == len(results) and not real_errors else 1)
