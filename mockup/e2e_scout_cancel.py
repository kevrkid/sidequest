"""Scout on / off like Siri, and cancelling: ✕ Cancel while it thinks (the request is aborted and a late answer
ignored), the orb tapped while it works, spoken "never mind" / "scratch that" / "cancel" (nothing is sent), and
questions that only sound like it ("the closest bus stop") still going through.

  SQ_BASE=http://localhost:8787 python e2e_scout_cancel.py <shot-dir>

/api/scout is answered by the test (held until it says so), so no Claude calls are made.
"""
import json, os, sys
from playwright.sync_api import sync_playwright

BASE = os.environ.get("SQ_BASE", "http://localhost:8787")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sq-scout-cancel"
os.makedirs(OUT, exist_ok=True)
results, errors, held, asked = [], [], [], []


def check(name, ok, detail=""):
    results.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{str(detail)[:240]}]" if detail and not ok else ""))


def scout_route(route):
    asked.append(json.loads(route.request.post_data or "{}").get("q"))
    held.append(route)   # answered later (or never: cancelled)


ANSWER = json.dumps({"say": "Here are some tacos!", "expression": "happy", "actions": [], "left": 99})

with sync_playwright() as pw:
    browser = getattr(pw, os.environ.get("SQ_BROWSER", "chromium")).launch()
    ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True)
    ctx.route(lambda u: "fonts.g" in u or "/img/ev" in u or not ("127.0.0.1" in u or "localhost" in u), lambda r: r.abort())
    p = ctx.new_page()
    p.on("pageerror", lambda e: errors.append(str(e)))
    p.goto(BASE, wait_until="load")
    p.evaluate("h=>fetch('/api/signup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({h,pw:'password123',adult:true,terms:true})})",
               f"scc{os.getpid() % 10000}")
    p.wait_for_timeout(800); p.reload(wait_until="load"); p.wait_for_timeout(2000)
    try:   # the app shows a guest the welcome sheet once /api/state is back (slower on a cold server): wait for it, then hide it
        p.wait_for_function("()=>(typeof AUTHED!=='undefined'&&AUTHED)||S.welcomed||(ONB.step==='welcome'&&!document.querySelector('#onbBg').hidden)", timeout=15000)
    except Exception:
        pass
    p.evaluate("()=>{ const o=document.querySelector('#onbBg'); if(o) o.hidden=true; S.toured=true; S.scout.voice=false }")
    p.route("**/api/scout", scout_route)
    p.evaluate("()=>openScoutVoice(true)"); p.wait_for_timeout(400)
    check("no Cancel button when Scout is idle", p.locator("#scCancel").is_hidden())

    # 1. ✕ Cancel while it's thinking
    p.evaluate("()=>{ scoutAsk('tacos near me'); }"); p.wait_for_timeout(500)
    check("thinking: a Cancel button shows", p.locator("#scCancel").is_visible() and p.evaluate("SCT.busy"))
    p.screenshot(path=f"{OUT}/1-thinking.png")
    p.click("#scCancel"); p.wait_for_timeout(300)
    check("Cancel stops it: not busy, says so, button gone",
          not p.evaluate("SCT.busy") and "Cancelled" in p.inner_text("#scMicL") and p.locator("#scCancel").is_hidden(), p.inner_text("#scMicL"))
    held[-1].fulfill(status=200, content_type="application/json", body=ANSWER) if held else None   # the answer arrives late…
    p.wait_for_timeout(500)
    check("…and a late answer is ignored", "Here are some tacos" not in p.inner_text("#scoutBg"))
    p.screenshot(path=f"{OUT}/2-cancelled.png")

    # 2. the orb tapped while it works = stop (like Siri)
    n = len(asked)
    p.evaluate("()=>{ scoutAsk('bars on rainey'); }"); p.wait_for_timeout(400)
    p.evaluate("()=>document.querySelector('#scoutBtn').click()"); p.wait_for_timeout(300)
    check("tapping the orb while Scout thinks cancels it", not p.evaluate("SCT.busy") and len(asked) == n + 1)

    # 3. a normal question still gets its answer
    p.evaluate("()=>{ scoutAsk('coffee'); }"); p.wait_for_timeout(400)
    held[-1].fulfill(status=200, content_type="application/json", body=ANSWER); p.wait_for_timeout(600)
    check("an uncancelled question gets its answer", "Here are some tacos" in p.inner_text("#scoutBg") and not p.evaluate("SCT.busy"))

    # 4. spoken cancels: what the mic heard goes through micDone
    said = lambda text: p.evaluate("t=>{ const m=SCT.mic={send:true,want:false}; micDone(m,t,''); }", text)
    for phrase in ["find me tacos on sixth never mind", "best brunch spot scratch that", "cancel", "never mind", "stop", "nope", "olvídalo"]:
        n = len(asked); said(phrase); p.wait_for_timeout(250)
        check(f'saying "{phrase}" cancels (nothing sent)', len(asked) == n and "Cancelled" in p.inner_text("#scMicL"), [phrase, asked[n:]])
    for phrase in ["where's the closest bus stop", "is there a cancel culture comedy show tonight"]:
        n = len(asked); said(phrase); p.wait_for_timeout(300)
        ok = len(asked) == n + 1
        if held: held[-1].fulfill(status=200, content_type="application/json", body=ANSWER); p.wait_for_timeout(300)
        check(f'"{phrase}" is a real question and is sent', ok, asked[n:])

    # 5. tapping the mic while it thinks: that question is dropped and it listens again (or would, with a mic)
    p.evaluate("()=>{ scoutAsk('pizza'); }"); p.wait_for_timeout(300)
    p.evaluate("()=>{ try{ scoutListen() }catch(e){} }"); p.wait_for_timeout(400)
    check("tapping the mic while it thinks drops that question", not p.evaluate("SCT.busy"))
    p.evaluate("()=>scoutCancel(true)")

    check("no page errors", not errors, errors[:3])
    browser.close()

bad = [n for ok, n in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} passed")
sys.exit(1 if bad else 0)
