#!/usr/bin/env python3
"""Every 5 minutes (cron, as root): is Side Quest up, and is everything behind it still working?

systemd already restarts a service that crashes; this catches what it can't see: a service that's running but no
longer answers (restarted after 2 failed checks in a row), the public site down (Caddy, certificate), the event scraper
gone quiet, a full disk, a missed nightly backup, a places refresh that lost most places. Problems go to the system log
(journalctl -t sidequest-health) and to app/data/health.json, which the admin page shows as a banner.

  python3 /opt/sidequest/deploy/health.py [--dry]     (--dry: check and print, restart nothing, write nothing)
"""
import glob, json, os, shutil, subprocess, sys, time, urllib.request
from datetime import datetime, timezone

ROOT = os.environ.get("SQ_ROOT", "/opt/sidequest")
OUT = f"{ROOT}/app/data/health.json"
STATE = os.environ.get("SQ_HEALTH_STATE", "/var/lib/sidequest-health")
BACKUPS = os.environ.get("SQ_BACKUPS", "/var/backups/sidequest")
DRY = "--dry" in sys.argv
problems, restarted = [], []


def get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.loads(r.read())


def env(key):
    try:
        for line in open("/etc/sidequest/env"):
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return ""


def fails(name, failed):
    """Count failures in a row for one check (kept across runs)."""
    os.makedirs(STATE, exist_ok=True)
    f = f"{STATE}/{name}"
    n = (int(open(f).read() or 0) if os.path.exists(f) else 0) + 1 if failed else 0
    if not DRY:
        open(f, "w").write(str(n))
    return n


def service(name, unit, url, ok):
    try:
        good = ok(get(url))
    except Exception:
        good = False
    n = fails(name, not good)
    if good:
        return
    if n >= 2 and not DRY:
        subprocess.run(["systemctl", "restart", unit], check=False)
        restarted.append(unit)
        problems.append(f"{unit} stopped answering; restarted it")
        open(f"{STATE}/{name}", "w").write("0")
    else:
        problems.append(f"{unit} didn't answer ({'will restart if it still does not in 5 min' if n < 2 else 'dry run'})")


service("app", "sidequest", "http://127.0.0.1:8787/api/health", lambda j: j.get("ok") is True)
service("events", "sidequest-events", "http://127.0.0.1:8788/health", lambda j: j.get("ok") is True)

# the scraper runs every 6 h: nothing new in 13 h means it's stuck or failing
try:
    run = get("http://127.0.0.1:8788/health").get("last_run") or {}   # in memory: a restart starts a fresh scrape
    hours = lambda t: (datetime.now(timezone.utc) - datetime.fromisoformat(t)).total_seconds() / 3600 if t else None
    fin, began = hours(run.get("finished")), hours(run.get("started"))
    running = began is not None and (fin is None or began < fin) and began < 2
    if not running and (fin is None or fin > 13):
        problems.append(f"Event scraper last finished {f'{fin:.0f} h ago' if fin is not None else 'never'} (runs every 6 h)")
except Exception:
    pass  # the service check above already says so

domain = env("SQ_DOMAIN")
if domain:
    try:
        if get(f"https://{domain}/api/health", timeout=15).get("ok") is not True:
            raise ValueError
    except Exception:
        if fails("public", True) >= 2:
            problems.append(f"https://{domain} isn't reachable from the server (Caddy or its certificate?)")
    else:
        fails("public", False)

du = shutil.disk_usage("/")
if du.used / du.total > 0.85:
    problems.append(f"Disk {du.used / du.total:.0%} full ({du.free // 2**30} GB left)")

kept = sorted(glob.glob(f"{BACKUPS}/sidequest-*.tgz"), key=os.path.getmtime)
if not kept or time.time() - os.path.getmtime(kept[-1]) > 26 * 3600:
    problems.append("No nightly backup in the last 26 h (deploy/backup.sh, 4:15 AM)")

try:
    n = len(json.load(open(f"{ROOT}/app/data/places.json"))["places"])
    if n < 5000:
        problems.append(f"Only {n} places on the map (usually ~10,000): did the weekly refresh lose the Overture / TABC files?")
except Exception as e:
    problems.append(f"Can't read places.json ({e.__class__.__name__})")

out = {"at": int(time.time()), "problems": problems, "restarted": restarted}
if DRY:
    print(json.dumps(out, indent=1))
    sys.exit(0)
for p in problems:
    subprocess.run(["logger", "-t", "sidequest-health", p], check=False)
tmp = OUT + ".tmp"
with open(tmp, "w") as f:
    json.dump(out, f)
os.chmod(tmp, 0o644)
os.replace(tmp, OUT)
