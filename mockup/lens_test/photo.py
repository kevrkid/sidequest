import os
# Detect + photos: the language found by itself, a photo from the phone (a sign, a 45-line menu), a photo with no camera.
# Server with the fake Claude (see README): $FAKE_LANG_FILE holds the language it says the picture is in.
import sys, time
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw, ImageFont
D=os.path.dirname(os.path.abspath(__file__)); OUT=os.path.join(D,"out"); BASE=os.environ.get("SQ_BASE","http://localhost:8798"); O=OUT+"/shots"
os.makedirs(O, exist_ok=True)
FONT="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
def picture(path, lines, size=(1200,1600), fs=44, gap=1.5, top=80):
    im=Image.new("RGB",size,(250,246,236)); dr=ImageDraw.Draw(im); f=ImageFont.truetype(FONT,fs)
    for i,t in enumerate(lines): dr.text((70,top+i*fs*gap),t,font=f,fill=(30,30,30))
    im.save(path,"JPEG",quality=92); return path
RUN=str(int(time.time())%9000+1000)   # a new number each run, so the server's cache doesn't answer for it
SIGN=picture(OUT+"/sign.jpg",["CAFÉ DE LA GARE","Fermé le lundi","Entrée libre "+RUN],(1400,900),80,1.8,140)
DISHES=["Tacos","Soup","Salad","Burger","Pizza","Pasta","Steak","Fish","Rice","Beans","Chips","Salsa","Flan","Churros","Coffee"]
MENU=picture(OUT+"/menu.jpg",[f"{DISHES[i%15]} plate number {i+1}  ${(i%9)+4}.50" for i in range(45)],(1300,2900),40,1.55,60)
r=[]; errs=[]
def ok(name, cond, extra=""): r.append(("PASS" if cond else "FAIL", name, extra))
def shown(pg): return pg.evaluate("[...document.querySelectorAll('.lz-box.on:not(.wait)')].map(b=>b.textContent.trim())")
def until(pg, pred, secs=60):
    t=time.time()
    while time.time()-t<secs:
        if pred(): return round(time.time()-t,1)
        pg.wait_for_timeout(250)
    return None
lang=os.environ["FAKE_LANG_FILE"]; prompts=os.environ["LENS_PROMPT_FILE"]
def say(l): open(lang,"w").write(l)
with sync_playwright() as p:
    b=p.chromium.launch(args=["--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream",f"--use-file-for-fake-video-capture={OUT}/cam.mjpeg"])
    ctx=b.new_context(viewport={"width":390,"height":844}, device_scale_factor=2); pg=ctx.new_page()
    pg.on("pageerror",lambda e:errs.append(str(e))); pg.on("console",lambda m: m.type=="error" and not any(x in m.text for x in ("diacritics","boxClip","pixScan","400 (Bad Request)")) and errs.append(m.text))
    ctx.add_init_script("{const g=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices); navigator.mediaDevices.getUserMedia=c=>g({audio:false,video:true});}")
    pg.goto(BASE+"/lens", wait_until="load")
    pg.evaluate("""(async()=>{ const j=b=>({method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}), me={h:'lensphoto1',pw:'password123'};
      const r=await fetch('/api/signup',j({...me,adult:true,terms:true})); if(!r.ok) await fetch('/api/login',j(me)); })()""")
    pg.wait_for_timeout(500); pg.evaluate("localStorage.removeItem('lens')"); pg.reload(wait_until="load")
    say("en"); open(prompts,"w").write("")
    pg.click("#go")
    ok("Detect is the first-time choice", pg.input_value("[data-k=from]")=="auto")
    s=until(pg, lambda: pg.evaluate("document.querySelector('[data-k=from] option[value=auto]').textContent")=="✨ English", 60)
    ok("live camera: the language is found", s is not None, f"{s}s")
    s=until(pg, lambda: sum(x.startswith("ES:") for x in shown(pg))>=4, 90)
    ok("live camera: translated after detecting", s is not None, f"{s}s")
    n=open(prompts).read().count("imgs=1"); pg.wait_for_timeout(5000)
    ok("no more language checks while text is in view", open(prompts).read().count("imgs=1")==n, f"{n} -> {open(prompts).read().count('imgs=1')}")
    pg.screenshot(path=O+"/p1-detected.png")
    # a French sign from the phone's photos
    say("fr")
    with pg.expect_file_chooser() as fc: pg.click("[data-a=photo]")
    fc.value.set_files(SIGN); open(prompts,"w").write("")
    until(pg, lambda: pg.evaluate("document.querySelector('.lz').classList.contains('photo')"), 10)
    s=until(pg, lambda: sum(x.startswith("ES:") for x in shown(pg))>=3, 90)
    v=shown(pg); ok("photo: its lines translated", s is not None, f"{s}s {v}")
    ok("photo: shown, the camera's picture hidden", pg.evaluate("!document.querySelector('.lz-still').hidden && document.querySelector('.lz').classList.contains('photo')"))
    ok("photo: the language is found again", pg.evaluate("document.querySelector('[data-k=from] option[value=auto]').textContent")=="✨ Français")
    ok("photo: translated from French", "from French" in open(prompts).read())
    ok("photo: accents read", any("CAF" in x and "GARE" in x for x in v), str(v))
    box=pg.evaluate("(()=>{const b=[...document.querySelectorAll('.lz-box.on')].find(x=>x.textContent.includes('GARE')); if(!b) return null; const r=b.getBoundingClientRect(), c=document.querySelector('.lz-still').getBoundingClientRect(); return [r.left,r.top,r.right,r.bottom,c.width,c.height]})()")
    # the sign is shown whole: 1400x900 scaled to the screen's width, centred; its first line's letters start at (70, ~150)
    k=box and box[4]/1400; ex,ey=box and (70*k, (box[5]-900*k)/2+150*k)
    ok("photo: the box sits on its line", box and abs(box[0]-ex)<10 and abs(box[1]-ey)<10, f"{box} want ~({ex:.0f},{ey:.0f})" if box else "none")
    ok("photo: the stat says what to do", "Tap a translation" in pg.inner_text(".lz-stat"), pg.inner_text(".lz-stat"))
    pg.screenshot(path=O+"/p2-photo.png")
    # a whole menu: more than one request's worth of lines
    say("en")
    with pg.expect_file_chooser() as fc: pg.click("[data-a=photo]")
    fc.value.set_files(MENU)
    until(pg, lambda: not any("GARE" in x for x in shown(pg)), 10)
    s=until(pg, lambda: sum(x.startswith("ES:") for x in shown(pg))>=42, 120)
    ok("menu photo: 42+ of 45 lines translated", s is not None, f"{s}s {sum(x.startswith('ES:') for x in shown(pg))}")
    import re
    bad=[x for x in shown(pg) if (m:=re.search(r"number (\d+) \$(\d+)",x)) and int(m.group(2))!=(int(m.group(1))-1)%9+4]
    ok("menu photo: every line keeps its own number and price", not bad, str(bad[:4]))
    pg.click("[data-a=list]"); pg.wait_for_timeout(300); txt=pg.inner_text(".lz-sheet")
    ok("menu photo: the text list has them", txt.count("ES:")>=42, str(txt.count("ES:")))
    pg.screenshot(path=O+"/p3-menu-list.png"); pg.click(".lz-sheet [data-a=list]")
    pg.screenshot(path=O+"/p3-menu.png")
    # back to the camera
    pg.click("[data-a=freeze]"); pg.wait_for_timeout(300)
    ok("back to the camera", pg.evaluate("document.querySelector('.lz-still').hidden && !document.querySelector('.lz video').paused && !document.querySelector('.lz').classList.contains('photo')"))
    s=until(pg, lambda: sum(x.startswith("ES:") for x in shown(pg))>=4, 60)
    ok("camera translates again", s is not None, f"{s}s")
    # picking a language by hand: no language checks
    pg.select_option("[data-k=from]","en"); n=open(prompts).read().count("imgs=1"); pg.wait_for_timeout(4000)
    ok("a chosen language: no checks", open(prompts).read().count("imgs=1")==n)
    ok("remembered", pg.evaluate("localStorage.getItem('lens')")=='{"from":"en","to":"es"}')
    pg.select_option("[data-k=from]","auto"); pg.click("[data-a=swap]"); pg.wait_for_timeout(200)
    ok("swap from Detect: the detected/default language becomes the target", pg.input_value("[data-k=from]")=="es" and pg.input_value("[data-k=to]")=="en", pg.input_value("[data-k=from]")+">"+pg.input_value("[data-k=to]"))
    pg.select_option("[data-k=from]","auto"); pg.select_option("[data-k=to]","es")
    b.close()
    # no camera at all: a photo still works
    b=p.chromium.launch(); c3=b.new_context(viewport={"width":390,"height":844}); h=c3.new_page(); h.on("pageerror",lambda e:errs.append("nocam: "+str(e)))
    h.goto(BASE+"/lens"); h.evaluate("fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({h:'lensphoto1',pw:'password123'})})"); h.wait_for_timeout(500)
    h.evaluate("navigator.mediaDevices.getUserMedia=()=>Promise.reject(Object.assign(new Error('x'),{name:'NotAllowedError'})); Lens.open()"); h.wait_for_timeout(500)
    ok("camera blocked: says so", "Allow the camera" in h.inner_text(".lz-stat"))
    say("fr")
    with h.expect_file_chooser() as fc: h.click("[data-a=photo]")
    fc.value.set_files(SIGN)
    s=until(h, lambda: sum(x.startswith("ES:") for x in shown(h))>=3, 90)
    ok("camera blocked: a photo still translates", s is not None, f"{s}s {shown(h)}")
    h.screenshot(path=O+"/p4-nocam.png"); b.close()
for x in r: print(*x)
print("errors", errs)
print(sum(x[0]=="PASS" for x in r), "/", len(r))
