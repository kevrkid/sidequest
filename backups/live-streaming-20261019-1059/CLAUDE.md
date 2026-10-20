# Side Quest

A social app for Austin / Central Texas that answers **"what's the move tonight, and who's coming?"**
It mixes real local events, people's own posts, and friend-matching so people meet through shared
activities: pickup games, shows, comedy, bars, groups. **Not a dating app.** Owner: Kevin (kevrkid@gmail.com).

Status: working beta prototype, tested end to end, not yet deployed. Target: public invite-only beta
at `sidequest.cc.middlematter.com` on the owner's Hetzner box.

## What a user can do

- **Try it without an account.** Guests browse everything and RSVP; anything that reaches other
  people (post, wave, message, join, go live, report) opens a "create a free account" gate, then
  returns them to what they were doing. Guest data carries into the account.
- **Home**: 4 colored quadrants + a center circle. Meet (purple, with a 💬 messages shortcut),
  Search (blue), Create (green), Live (orange), and **GO!** (a see-through live mini-map with an
  Apple-style blue location dot; tap opens the full map). A short quick-button row on top that only
  shows what's useful now (Tonight; My plans / New messages when there are some; quiz, chart, about me
  until done; the rest lives in the quadrants) and a "Picks for you" bar. Search puts events first,
  Food & drink + Hot spots first from 10 PM to 10 AM. The Scout button nudges itself up off any
  button or text box under it (`scoutDock()`).
  No bottom bar: Home is the hub; header has profile (top-left) + Online/Offline switch + logo (→ Home)
  + a ‹ back button. Back closes the top sheet first, then returns to the previous screen; it's wired to
  browser history (Android back works) and a swipe in from the left edge (left to Safari itself in
  non-installed iPhone Safari, which already does that).
- **Search**: "What are you looking to do?", tiles by section (Sports, Entertainment, Going out,
  Outdoors & more) with live counts, a Tonight/Weekend/Week switch, free-text search, plus
  **Food & drink** (late-night eats, early morning, bars, clubs, coffee, tacos, BBQ, pizza, burgers,
  Asian, sweets, food trucks) with an **Open now** switch, and **Hot spots** tiles with live "open now" counts.
  Results list: nearest first with open spots on top, status ("Open till 2 AM", "Opens at 7 AM",
  "Hours unknown"), menu/website links when OpenStreetMap has them, and a "may be out of date" note.
- **Feed**: ranked list of real events, flares, group posts, people and groups, with reasons
  ("You're into comedy · 2 friends going"). Customizable (content types, categories, sort, distance).
  "Map it" sends the list to the map.
- **Map**: OpenStreetMap tiles, event pins, flares, story bubbles, live-stream thumbnail bubbles,
  a live strip along the bottom, your location dot. Food & drink dots (canvas layer, zoom ≥ 13,
  "🍔 Food & drink" chip): green glowing = open, amber = opens within the hour, grey = closed/unknown;
  tap for hours, distance, address, menu/website/directions. Austin hot spots (6th St, Rainey St,
  Red River, West 6th, SoCo, East Austin, The Domain, Old Downtown Round Rock) are glowing orange
  zones labeled on their top edge; tap one for what's open there.
  **Eat after**: a bar/club popup or event popup has "🌙 Eat after": food within 0.5 mi still open
  when it closes (unknown bar hours = 2 AM last call) or the event ends (`Places.after`,
  `/api/places/after`); Scout uses it for "food after <venue>" (`venue_key()` in server.rb).
- **Meet**: one swipe deck for people (right = wave; a wave both ways = friends), events (right =
  going), groups (right = join), flares (right = I'm down). Sort + filters (activity, when, distance,
  goals, interests, new to Austin, from my groups, online now). Tabs: Swipe · Messages · Groups.
  Messages are friends-only.
- **Create**: Story (photo or text, 24h, tag an event / groups / people), Flare ("who's down?" now),
  Event (date/time), Group, Go live.
- **Live**: stream from the phone camera (front/back, flip mid-stream), USB webcam mode, Bluetooth
  pairing for GoPro/Insta360/DJI, Wi-Fi/RTMP instructions. Viewers send requests (visit a place / do
  a task, with play-money tips); Claude screens every request for safety.
- **Me / profile**: interests, a 20-question 16-type personality quiz, full astrology (birth date +
  optional time + city → Sun, Moon, Rising, Mercury–Saturn, Chinese zodiac, computed on-device),
  39 "about you" questions in 4 sections (Growing up, Life now, Friendship & values, Just for fun).
  **Every answer has its own visibility**: Matching only (default, never shown) · Friends · Everyone ·
  Only me. Activity/location history (opt-in, venue-level only), export, delete account.
- **Profiles of others**: match %, "what you have in common", Snapchat-style astrological
  compatibility card, their shared answers.
- **Safety**: report/block on everything, Claude moderation of posts/captions/group names/public
  profile text, phone/email filter, admin page (`/admin`), 18+ and Terms acceptance at sign-up,
  rate limits, invite codes in beta.
- **Scout** (bottom-left button): an animated guide that answers how-to and "what's the move" questions,
  points at buttons (ring + label) and pulses spots on the map, talks via the browser's own speech
  (🎤 in, 🔊 out), and has a voice-only 🚗 driving mode (auto-on at ~16 mph). Each user can design its
  look and name (🎨 builder, a description Claude maps to parts, or their photo, kept on-device only).
  Guests get a built-in FAQ (incl. food, bars, coffee, open now); signed-in users get Claude.
  Food & drink questions: the server picks ~15 matching places (`scout_places()` in server.rb,
  widening zone → nearby → closed-with-opening-time and telling Scout what it did), and Scout may
  light one up with a `place` action, allowed only for ids it was sent; it never invents menus. Personality: `mockup/scout_personality.md`;
  app knowledge: `mockup/scout_knowledge.md` (keep it current; never served). Spec: `SCOUT_PROMPT.md`.
- **Installable** as a home-screen app (PWA manifest + icons).

## Architecture

Two services, deliberately dependency-light.

| Part | Where | Tech |
|---|---|---|
| App server + UI | `mockup/server.rb`, `mockup/index.html` | Ruby 2.6 stdlib + WEBrick (no gems); one HTML file with inline JS/CSS, no framework, no build step |
| Events service | `~/claude/live/` (`centex_events`) | Python 3.9, FastAPI, SQLite; scrapes ~45 Central Texas sources every 6h |
| Food & drink places | `mockup/fetch_places.rb` → `mockup/data/places.json` | Ruby stdlib; OpenStreetMap Overpass, Round Rock to South Austin |
| AI | `run_claude()` in server.rb: the Anthropic Messages API over Net::HTTP when `SQ_USE_API_KEY=1` + `ANTHROPIC_API_KEY` (server), else the Claude Code CLI headless (local, subscription) | Sonnet 5.5 for picks/matching, Haiku 5.5 for screening/Scout |

- **index.html**: all screens are `<section class="view" id="v-…">`; `tab(name)` switches.
  State lives in `S` (localStorage key `sq-mock-v1`), server state in `SV`, events in `EV`.
  One delegated click handler dispatches on `data-*` attributes. Render functions per area
  (`renderHome`, `renderFeed`, `renderMeet`, `renderMap`, `renderMe`, …). Key logic:
  `matchPerson()` (friend matching + reasons), `scoreEvent()` / `feedItems()` (feed ranking),
  `deckItems()` (Meet deck), `chart()` / `astroCompat()` (astrology), `needAccount()` (guest gate).
- **server.rb**: JSON routes under `/api/*`; data in `mockup/data/app.json` (written atomically) and
  story photos in `mockup/data/stories/`. Sessions = HttpOnly cookie, passwords = PBKDF2.
  Friends-only content, blocks and bans are enforced **server-side** in `state_for()`.
  Only whitelisted files are served (`PUBLIC_FILES`). Food & drink routes allow guests; Claude
  routes don't.
- **Food & drink**: `fetch_places.rb` downloads 130 small tiles one at a time into
  `data/places_tiles/` (resumable after a dropped connection; retries with backoff; 3 Overpass
  mirrors), then writes `data/places.json` (name, kind, cuisine, hours, address, position, website,
  menu link). **Local first**: national chains are dropped at build time (`chain_of()`: a brand with a
  Wikidata id, or an untagged place sharing its name, unless on the `AUSTIN`, `TEXAS` or `KEEP`
  lists); kept places get `chain: texas|national`, and search ranks them as if 0.5 / 1.5 mi farther.
  Edit the lists, then `--merge`. `--fresh` re-downloads everything (weekly cron on the server), `--merge` rebuilds the
  JSON from saved tiles without downloading. The app never downloads on its own. `hours.rb` reads
  OpenStreetMap opening_hours by hand into weekly minute ranges (overnight hours, `24/7`, `off`,
  rule overrides; months/sunset/`10:00+`/holidays → unknown, never guessed); `test_hours.rb` covers
  it. `places.rb` loads the file (auto-reloads when it changes), works out open/soon/closed/unknown
  in Austin time (server sets `TZ=America/Chicago`), searches by category/cuisine/hot spot/open-now,
  and defines the hot spots. The map gets compact weekly ranges and colors dots in the browser.
  Locations sent to the server are rounded to ~1 km. About 45% of places have hours; ~98% of those
  are readable.
- **Modes (env vars)**: local default = demo content on (8 fake people, streams, stories), open
  sign-up. `SQ_BETA=1` = demo off, guests allowed, `SQ_INVITES` codes, `SQ_ADMIN_TOKEN` for /admin.
  `SQ_USE_API_KEY=1` + `ANTHROPIC_API_KEY` = call the Anthropic API directly (required before serving
  the public); see `run_claude_api` in server.rb. `SQ_ENGINE=cli|api` forces an engine.
  `SQ_BEHIND_PROXY=1` behind Caddy. `SQ_MODERATE=0` turns off Claude screening.
  `SQ_PLACES_FILE` points at another places file (the e2e test uses `test_places.json`).
  Scout: `SQ_SCOUT_DAILY` (30/person/day), `SQ_SCOUT_HOURLY` (15), `SQ_SCOUT_BUDGET_USD` (10/day for
  everyone, then Scout pauses), `SQ_SCOUT_MODEL` (haiku, how-to) / `SQ_SCOUT_SMART_MODEL` (sonnet, recommendations).

## Run and test

```sh
~/claude/live/serve.sh                 # events service on :8788
cd mockup && ./start.sh                # app on http://localhost:8787
./phone.sh                             # + HTTPS on the LAN for phones (self-signed cert)
./beta.sh                              # public-beta mode (needs ~/.sidequest.env)
ruby fetch_places.rb                   # download/resume food & drink places (slow links: just rerun)
ruby test_hours.rb                     # opening-hours reader tests
ruby test_api.rb                       # Anthropic API engine against a fake API (no key needed)
SQ_PLACES_FILE=test_places.json ruby server.rb   # server for the e2e test (no internet needed for places)
python e2e_test.py <shot-dir>          # Playwright: two brand-new users, 89 checks
```

The end-to-end test needs Playwright (installed in a scratch venv during development). It signs up
two users from guest mode and covers quiz, chart, profile visibility, feed, RSVP, map, Meet swipes,
friends, messages, stories, reports, groups, food & drink (Search, open-now switch, map dots, hot
spot zones, Scout finding tacos), back + swipe-back. **Stop the server and reset `data/app.json` to `{}`
before and after test runs** (the server keeps data in memory and will overwrite file edits).

Deployment kit: `deploy/` (systemd units, Caddyfile for `sidequest.cc.middlematter.com`,
`install.sh`, `push.sh`, nightly `backup.sh`, `env.example`). Launch checklist: `mockup/LAUNCH.md`.

## Conventions and constraints

- Keep it dependency-free: no npm, no gems, no frameworks. Vendor small libs into `mockup/vendor/`
  (Leaflet 1.9.4 lives there) and add them to `PUBLIC_FILES`.
- Mobile first: design for a 390px-wide phone; check 360px. Dark theme tokens in `:root`
  (`--bg #070b18`, `--panel`, `--accent` orange, `--accent2` cyan, `--party` purple, `--good` green).
- Privacy by default: new profile answers default to "Matching only"; exact GPS, birth date/time/place
  never leave the device; map positions are venue-level or blurred ~400 m; live location can be delayed.
- Anything visible to other users must be filtered on the server, never just hidden in the browser.
- Anything a guest can't do goes through `needAccount('<verb phrase>')`.
- Claude calls must be signed-in only, rate-limited per user, short-timeout, and fail safe
  (e.g. moderation failure = post goes up flagged for human review).
- Plain-language UI copy; every Claude-ranked item shows its reasons.
- After a change: syntax-check the inline script, run the e2e test, look at screenshots.

## Open items

- Food & drink limits: OpenStreetMap has no full menus or prices and hours can be stale. Later
  idea: a paid places API (e.g. Google Places / Foursquare) for menus, prices, ratings and fresher
  hours. Don't scrape restaurant websites.
- Deployment: needs a GitHub repo for the server session to pull from, an Anthropic API key in the
  server env file, and a lawyer pass on `terms.html` / `privacy.html` (both marked DRAFT).
- Later: Postgres instead of the JSON file, password reset by email, photo moderation, an RTMP
  ingest server (MediaMTX) and TURN server for live video, native app-store wrapper.
