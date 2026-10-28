# Side Quest (V3)

Side Quest is a social meetup and city-discovery app for Austin and Central Texas. It answers one question:
**"what's the move tonight, and who's coming?"** It mixes real local events, people's own posts and hangouts,
food and drink, sights, rankings and friend-matching, so people meet through shared activities (pickup games,
shows, comedy, bars, groups). It is **not** a dating app.

It is an installable web app (PWA) with no build step and no third-party packages: a Ruby standard-library
WEBrick server (`mockup/server.rb` plus feature modules), one large HTML file for the whole UI
(`mockup/index.html`), and an AI guide called **Scout** backed by Claude.

> Branch `v3`, folder `~/claude/sidequest-v3`, latest commit `3165edd` (2026-10-27). This is the current line of
> development. `V3_REPORT.md` (written 2026-10-26) says the Hetzner server was still running V2 at that point.
> Check the server's `/api/health` before assuming which version is deployed.

---

## Contents

1. [Feature areas](#feature-areas)
2. [Repository layout](#repository-layout)
3. [Architecture](#architecture)
4. [Server modules](#server-modules)
5. [Data storage](#data-storage)
6. [Front end (`index.html`)](#front-end-indexhtml)
7. [PWA, service worker and push](#pwa-service-worker-and-push)
8. [Scout and Claude](#scout-and-claude)
9. [External services and environment variables](#external-services-and-environment-variables)
10. [HTTP API](#http-api)
11. [Data-ingest scripts](#data-ingest-scripts)
12. [Running locally](#running-locally)
13. [Testing](#testing)
14. [Deploying](#deploying)
15. [Sibling folders and branches](#sibling-folders-and-branches)
16. [Known limitations and risks](#known-limitations-and-risks)
17. [Conventions](#conventions)

---

## Feature areas

| Area | What it is |
|---|---|
| **Map-first shell (V3)** | A full-screen Leaflet map that never goes away. A three-stop drawer (peek / half / full) and a 5-button dock (Explore · Feed · ＋ · Social · You) sit on top of it. On screens 900 px or wider, the drawer becomes a fixed left panel. |
| **Liquid Glass look** | iOS-style frosted glass in `glass.css`, with light and dark variants. It only overrides other styles, and all of them are scoped under `#app.v3`. Remove the `<link>` to get the old look back. |
| **Explore / search / chips** | One search box covers places, parks, sights, events, people, groups, dishes and posts. A question typed there goes to Scout. Category chips (Events, Food, Friends, Nightlife, Hot spots, Outdoors, Sights, Best of) filter the map and the list together. "Find a spot" filters by area, kind, music and vibe. |
| **Events** | Real events from a separate scraper service (`~/claude/live`), including the new ice-rink drop-in hockey and stick & puck sessions. Kids' activities are filtered out, and venues the scraper couldn't place are geocoded again. Each event has a page with RSVP, a discussion, calendar export and Directions. |
| **Food & drink** | About 4,700 OpenStreetMap places with open-now status worked out in Austin time. Also: hot-spot zones, Google details on tap (optional), full menus read by Claude, a dish search, happy hours, bar food and kitchen hours, and "eat after" a show. |
| **🏆 Best of Austin** | 47 ranked lists (pizza, cocktails, DJ nights, sports bars, and so on). Claude researches them offline from the web, every source link is checked, and community ratings are blended in live. |
| **Social** | Two-way friends, Messenger-style chats (1:1 and group, with photos, voice notes, reactions and cards), Facebook-style groups, stories with stickers, polls and close friends, public posts, hangouts ("flares"), plans with friends (voting), and friends on the map (opt-in, held in memory only). |
| **Gamification** | Quests, check-ins, XP and levels, coins, streaks, a weekly challenge, leaderboards and profile frames. |
| **Live video** | Streaming from a phone or action camera through LiveKit, with a fallback to phone-to-phone WebRTC over a polling relay. Viewer requests are screened by Claude, and there is a moderator kill switch. |
| **Scout** | An animated, voice-first guide. It has memory across visits, five personalities, a setup interview, the "find my spot" action, plan building, and limited "do it for me" actions. |
| **Camera tools** | Live Translate (`lens.js`: OCR on the phone, translation on the server) and "What is this?" identification. |
| **Safety** | Server-side visibility rules, report and block everywhere, Claude moderation of public text and photos, an admin page, rate limits and a guest gate. |
| **Notifications** | An in-app inbox plus real Web Push (VAPID, written by hand in Ruby). |
| **Español** | Most screens are translated, and Scout answers and speaks in Spanish. |

Recent work (Oct 26–27, 2026): the full-screen map UI, Liquid Glass, Best of Austin (`rankings.rb`,
`fetch_rankings.rb`, `rankings.js`), Scout "find my spot", the location on/off row in You, ice-rink sessions (in the
events service), open sign-up, and Scout memory and personalities (`scout_mind.rb`, `scout_self.md`).

On open sign-up: the server reads invite codes from `SQ_INVITES`. When that variable is empty or unset, sign-up is
open. The code path for invite codes is still there.

---

## Repository layout

```
sidequest-v3/                    git worktree of the repo whose main checkout is ../sidequest-v2 (branch v3)
├── CLAUDE.md                    developer notes (very detailed, feature by feature)
├── V2_REPORT.md, V3_REPORT.md   what each version changed, how it was tested
├── V2_PROMPT.md, SCOUT_PROMPT.md, FOOD_PROMPT.md   original briefs
├── deploy/                      systemd units, Caddy snippet, install/push/backup scripts, env.example, LiveKit config
├── backups/                     old local snapshot(s)
└── mockup/                      the app (despite the name, this is production code)
    ├── server.rb                WEBrick server: config, Claude engine, auth, core routes, Scout, admin, relay
    ├── *.rb                     feature modules (see below), mounted by server.rb
    ├── fetch_*.rb, rank_popular.rb   offline data builders → mockup/data/*.json
    ├── index.html               the entire UI: HTML + CSS + ~7,000 lines of inline JS
    ├── glass.css                V3 Liquid Glass overrides
    ├── rankings.js              Best of Austin sheet (lazy-loaded)
    ├── lens.js, lens.html       Live Translate / Identify camera (lazy-loaded; also standalone at /lens)
    ├── sw.js, manifest.webmanifest, icon-*.png, logo.png   PWA
    ├── admin.html, terms.html, privacy.html
    ├── scout_personality.md, scout_self.md, scout_knowledge.md   Scout's system prompt (never served)
    ├── vendor/                  Leaflet 1.9.4, livekit-client 2.22.0, tesseract.js 6.0.1
    ├── data/                    runtime + map data (see Data storage)
    ├── test_*.rb, test_*.json   Ruby unit/integration tests and small fixtures
    ├── e2e_*.py                 Playwright end-to-end tests
    ├── lens_test/               moving-camera test kit for Live Translate
    └── start*.sh, beta.sh, phone.sh   launchers
```

---

## Architecture

### Process model

There are two long-running services, and optionally a third:

1. **App server**: `ruby mockup/server.rb`. One Ruby process running WEBrick, which gives each request its own
   thread. It binds `127.0.0.1:$PORT` (default 8787; `SQ_BIND` changes the address). When `SQ_LAN=1` it also
   starts a second, self-signed HTTPS server on every interface (`SQ_LAN_PORT`, default 8443) so phones on the same
   Wi-Fi can use the camera and microphone. Every server instance gets the same routes.
2. **Events service**: `centex_events`, a Python FastAPI + SQLite app in `~/claude/live` (not in this repo). It listens
   on `127.0.0.1:8788` and scrapes about 45 Central Texas sources every 6 hours. The app server proxies and caches it
   at `/api/events` (`SQ_EVENTS_API`).
3. **LiveKit** (optional): LiveKit Cloud, or a self-hosted `livekit-server` (`deploy/livekit.yaml`).

Background threads inside the app server:

- **Push worker**: `PUSH_Q` → `WebPush.deliver`.
- **Scheduler loop** (every 60 s): flushes stats; every 5 minutes it sends event and plan reminders; Monday morning
  the weekly recap; 5:00–5:15 PM the "tonight" picks.
- **Photo-screening worker** (`photocheck.rb`).
- **Menu jobs and menu pre-warm** (`menus.rb`).
- **LiveKit stop/restream helpers**.

In production, Caddy terminates TLS and reverse-proxies to `127.0.0.1:8787` (`SQ_BEHIND_PROXY=1` makes the server
trust `X-Forwarded-For` / `-Proto`).

### Diagram

```
                 Phone / desktop browser (PWA)
   ┌──────────────────────────────────────────────────────────┐
   │ index.html (inline JS, state S / SV / EV) + glass.css     │
   │ lazy: rankings.js, lens.js, vendor/livekit-client.js      │
   │ sw.js: app-shell cache, Web Push display                  │
   └───────┬───────────────────────────┬──────────────┬───────┘
           │ fetch JSON /api/*         │ WebRTC/WS    │ tiles, fonts,
           │ (cookie sq_s)             │              │ tesseract lang data
           ▼                           ▼              ▼
   ┌─────────────── Caddy (prod: TLS, gzip, 2 MB body cap) ───────┐   OSM / Google Map Tiles,
   │   /livekit/* → :7880 (self-hosted LiveKit only)              │   Google Fonts, jsDelivr
   └───────┬──────────────────────────────────────────────────────┘
           ▼
   ┌──────────────────────── server.rb (WEBrick, threads) ─────────────────────────┐
   │ route()/claude_route(): same-origin check, session, JSON in/out, error→status │
   │ mount_app (static whitelist) · mount_routes (core, Scout, relay, admin)       │
   │ mount_v2 · chats · groups · wall · stories_plus · friendmap · rewards · spots │
   │ menus/menu_finds/barfood · rankings · lens · identify · scout_mind            │
   │                                                                               │
   │ STORE (one Mutex) ──► data/app.json (whole-file atomic rewrite)               │
   │ in-memory: RATE, PRESENCE, FMAP, RELAY, LIVE, MENU_JOBS, caches               │
   │ read-only data: Places / Sights / Areas / Popular / Rankings (auto-reload)    │
   │ threads: push worker, scheduler, photo screening, menu jobs                   │
   └──┬───────────┬───────────────┬──────────────┬──────────────┬───────────────────┘
      │           │               │              │              │
      ▼           ▼               ▼              ▼              ▼
  centex_events  Claude:         Google:        LiveKit       Web Push services
  :8788 (Py,     Anthropic API   Places (New),  RoomService,  (FCM, APNs, Mozilla…)
  SQLite)        or `claude -p`  TTS, tokeninfo Ingress,      via VAPID
                 CLI             Nominatim(OSM) Egress
```

### Request flow

Almost every API route is registered with `route(server, path, auth:, get:, raw:)` (`server.rb:1257`). This is a thin
wrapper over `WEBrick#mount_proc`:

1. It sets `Content-Type: application/json` and `Cache-Control: no-store`.
2. It rejects non-POST requests unless the route is `get: true`. A POST whose `Origin` host differs from `Host` gets a
   403 (CSRF guard; the cookie is also `SameSite=Lax`).
3. It resolves the session: the `sq_s` cookie is SHA-256-hashed and looked up in `d['sessions']`, and banned users are
   rejected. It returns 401 if `auth: true` and there is no user.
4. It parses the JSON body, unless the route is GET or `raw` (raw routes such as media uploads read `req.body`
   themselves).
5. It calls the block with `(body, handle, req, res)` and JSON-encodes the result.
6. It maps exceptions to statuses: `AuthError` → 401, `RateLimited` → 429, `Forbidden` → 403, bad JSON → 400, any
   other `RuntimeError` → 400 (its message is shown to the user), anything else → 500.

`claude_route` adds a per-user hourly limit on top of this. `limit!(key, max, window)` is an in-memory
sliding-window limiter.

A few paths use `mount_proc` directly because they stream files or HTML rather than JSON: `/`, `/config.js`,
`/avatar`, `/story-vid`, `/story-img`, `/img/ev`, `/img/menu`, `/api/events`, `/api/outdoors`, `/api/admin`,
`/api/relay`, `/group-img`, `/wall-img`, `/dm-img`, `/dm-aud`, and the share pages `/e`, `/s`, `/i`, `/r/`.

Static files are served only from the `PUBLIC_FILES` whitelist (`server.rb:92`). Code, Scout's prompt files and
`data/` are never served. Text files are gzipped and get an ETag. `/config.js` publishes the feature flags the client
needs: demo, beta, invite, LiveKit on/off, Google on/off, the map-tiles browser key, the OAuth client id,
voice/hear, and the VAPID public key.

Security headers on every response (`HEADERS`): HSTS on HTTPS, `nosniff`, `Referrer-Policy:
strict-origin-when-cross-origin`, `X-Frame-Options: DENY`, and a `Permissions-Policy` that allows camera, microphone,
geolocation and Bluetooth for the site itself only.

### How modules are wired

`server.rb` `require_relative`s every module at the top. Modules are plain Ruby files that share the server's
globals and helpers (`route`, `store`, `limit!`, `run_claude`, `moderate`, `notify!`, `blocked_between`, ...). They
are not classes with interfaces. At the bottom (`server.rb:2478`) each server instance calls:

```
mount_routes · mount_app · mount_v2 · mount_lens · mount_rankings · mount_identify · mount_menus (+ mount_menu_finds)
mount_barfood · mount_spots · mount_chats · mount_groups · mount_friendmap · mount_stories_plus · mount_plans
mount_rewards · mount_wall · mount_scout_mind
```

After that, `v2_background` starts the push worker and the scheduler once.

---

## Server modules

| File | Responsibility |
|---|---|
| `server.rb` | Config from env; the Claude engine (`run_claude` → Anthropic Messages API or the Claude Code CLI); auth (PBKDF2-SHA256 passwords, 30-day sessions, Sign in with Google); `STORE`; `state_for` (all visibility rules); moderation; LiveKit JWT, Ingress and Egress; Google Places, photos and nightlife; TTS and whisper.cpp; events proxy and image shrinker; core routes; Scout; live-request screening; the phone-to-phone relay; admin API; HTTP servers and the self-signed LAN certificate. |
| `v2.rb` | Notifications (`notify!`, mute, fold), VAPID key and push queue, quests and check-ins, saves/favorites, Scout taste memory (`remember_taste!`, `taste_for`), event and group chat, invites (signed per inviter), share pages with Open Graph, first-party analytics (`track!`, `data/stats.json`), reminders, weekly recap, 5 PM tonight picks, live-title and request screening helpers. |
| `webpush.rb` | Web Push encryption (RFC 8291 aes128gcm) and VAPID (RFC 8292) using only OpenSSL, with a hand-written AES-GCM fallback for LibreSSL. `valid_sub?` only allows known push-service hosts (SSRF guard). |
| `scout_mind.rb` | Scout's per-person memory (`d['scout_mem']`: conversation log of 40 turns, up to 60 notes, turn count), the 5 personalities and the automatic pick from the 16-type quiz, the setup-interview prompt and cleanup, place ratings and "what did you get" orders (`d['ratings']`, `d['orders']`), and the memory/forget/rate routes. |
| `chats.rb` | DMs and group chats (`d['dms']`, `d['chats']`): replies, reactions, unsend, photos, voice notes, cards, read marks, typing (in memory). Also **plans with friends** (`/api/hangout/*`: voting on options and times, lock-in, reminders). |
| `groups.rb` | Group pages: wall posts with photos, polls and group events, likes, comments, pins, admins, private groups and join requests. |
| `wall.rb` | Public posts (Posts feed): text and/or photo, place, visibility, likes, comments, coin boosts. Ranked on the server. |
| `stories_plus.rb` | Story viewers, the poll sticker, close-friends lists. |
| `friendmap.rb` | Snap-Map-style friend locations: ghost, all friends or chosen friends, exact or about 500 m. Positions are held only in memory (`FMAP`) and expire after 8 hours. |
| `rewards.rb` | Coins, daily streak, weekly challenge, leaderboards, profile frames, tips held and settled for live streams. All XP goes through `xp_add!`. |
| `photocheck.rb` | A background queue that shows every public photo (and three frames of each video story) to Claude. Blocked photos are taken down and the owner is notified. |
| `places.rb` | Loads `data/places.json`. Works out open/soon/closed in Austin time; search by category, cuisine, hot spot and open-now; defines `HOTSPOTS`; `after` (food still open after a venue closes); `best_in(area)`. Reloads automatically when the file changes. |
| `hours.rb` | A hand-written parser for OpenStreetMap `opening_hours` that produces weekly minute ranges. Anything uncertain comes back as unknown. |
| `areas.rb` | Neighborhoods, streets and towns from `data/areas.json`, used by Scout ("a spot in Hyde Park") and Find a spot. |
| `sights.rb` | Sights and history from `data/sights.json`: search, aliases, distance. |
| `popular.rb` | 0–100 fame score per place and sight from `data/popular.json`, used to declutter the map. |
| `spots.rb` | The "Add location" picker search across every place source, a Nominatim fallback, and `spot_ref` to clean a post's place. |
| `geofix.rb` | Re-places events the scraper dropped on a city center: our own data first, then Nominatim. Cached in `data/geofix.json`. |
| `event_filter.rb` | Drops kids' activities from the events feed, then calls `Geofix`. |
| `menus.rb` | Full menus: fetches the place's own pages (private addresses refused), PDFs through `pdftotext`, menu pictures, then a Claude web search. Parts are read in parallel. Results are cached in `data/menus/<id>.json` for 14 days. A background pre-warm reads menus ahead of time. |
| `menu_finds.rb` | `MenuIndex` over the menus already read: dish search (`/api/dishes`) and happy hours (`/api/places/happy`). |
| `barfood.rb` | Whether a bar serves food and when the kitchen closes, from people's reports, menus and OSM. |
| `rankings.rb` | Best of Austin: the 47 `RANK_CATS` lists, live scoring (weighted web sources + Bayesian community stars + data signals), routes, `/r/<list>` share page, `rank_for_scout`. |
| `lens.rb` | Live Translate: `/api/translate` (cached per line) and `/api/lens/lang` (language detection from a small image). |
| `identify.rb` | "What is this?": photo + GPS + compass heading → Claude, with nearby places and sights as candidates. The photo is never stored. |

Data builders (`fetch_*.rb`, `rank_popular.rb`) are covered in [Data-ingest scripts](#data-ingest-scripts).

---

## Data storage

There is no database. Everything lives under `mockup/data/`:

| Path | Format | Written by | In git? |
|---|---|---|---|
| `app.json` | One JSON object holding all user data | server (`store`) | no (ignored) |
| `stories/`, `media/`, `avatars/`, `dm/`, `groups/`, `wall/`, `img/` | JPEG / video / audio files, random ids | server | no |
| `menus/<placeid>.json`, `menus/_tried.json` | Claude-read menus (14-day cache) | `menus.rb` | no |
| `stats.json` | Daily analytics counters | `v2.rb` (flushed every minute) | no |
| `vapid.json` | **VAPID private key** (mode 0600, made on first start) | `v2.rb` | no (secret) |
| `places.json` (+ `places_tiles/`) | ~10,000+ food & drink places, breweries and venues (OpenStreetMap + Overture Maps + TABC licenses), San Marcos to Georgetown | `fetch_places.rb` (merges the two below) | json yes, tiles no |
| `overture.json`, `tabc.json`, `tabc_geo.json` | Raw Overture places; geocoded on-premise alcohol licenses (+ geocode cache) | `fetch_overture.py`, `fetch_tabc.rb` | no (inputs to the merge) |
| `outdoors.json` | Parks, water, trails, rentals and ramps | `fetch_outdoors.rb` | yes |
| `gyms.json` | Gyms, climbing, yoga, boxing, CrossFit, dance, ice rinks, rec centers | `fetch_gyms.rb` | yes |
| `sights.json` (+ `sights_cache/`) | ~1,650 markers, landmarks, art | `fetch_sights.rb` | json yes, cache no |
| `areas.json` | ~60 neighborhoods and towns | `fetch_areas.rb` | yes |
| `markets.json` | Farmers markets (hand-kept) | `fetch_markets.rb` | yes |
| `popular.json` | Fame scores and top lists | `rank_popular.rb` | no |
| `rankings.json`, `rank_geo.json` | Best of Austin lists and geocode cache | `fetch_rankings.rb` | rankings yes, geo no |
| `geofix.json` | Event venue geocode cache | `geofix.rb` | no |

**Top-level keys in `app.json`** (the code creates them as it needs them): `users`, `sessions` (stored as SHA-256 of
the token), `rsvps`, `groups`, `members`, `greqs`, `friends`, `freqs`, `dms`, `chats`, `dm_read`, `posts` (flares /
hangouts), `stories`, `wall`, `gposts`, `reports`, `feedback`, `plans`, `notifs`, `quest`, `saves`, `taste`, `push`,
`ev_chat`, `reminded`, `recap`, `tonight_sent`, `scout` (daily usage and cost), `scout_mem`, `ratings`, `orders`,
`rank_votes`, `rank_suggest`, `barfood`, `gplace` (OSM id → Google place id, the only Google data Google's terms let
us store), `google_ids`, `photo_blocks`, and `invite_key` (the HMAC secret for invite links; treat it as a secret).

**Persistence and concurrency** (`server.rb:745-771`):

- At startup the whole file is loaded into `STORE[:d]`.
- Every read or write goes through `store(write:) { |d| ... }`, which holds **one global `Mutex`**.
- A write serializes the **whole** object with `JSON.pretty_generate` to `app.json.tmp`, then `rename`s it over the
  original. The rename is atomic, so the file is never half-written.
- `store(write: false)` reads under the same lock.
- **The server keeps data in memory.** Editing `app.json` by hand while the server runs gets overwritten. Stop the
  server first.
- In-memory state that is lost on restart: rate limits (`RATE`), presence, friend locations (`FMAP`), the live relay
  queue, live-stream registry, typing indicators, menu jobs, the Google and TTS daily counters, and the Google
  sign-in ticket key.

Backups: `deploy/backup.sh` tars `app/data` and the events service's `data/` nightly and keeps 14 days.

---

## Front end (`index.html`)

`index.html` is about 8,300 lines and 800 KB, with no framework and no build step. The structure:

- **Head**: Leaflet, the manifest and icons, Inter from Google Fonts. All CSS is inline in one `<style>` (dark-theme
  tokens on `:root`), then `glass.css` overrides it.
- **Markup**: `#app.v3` holds:
  - `#v-map` (the Leaflet map, always visible);
  - `#drawer` (`data-at` = peek, half or full), containing `.view` sections: `#v-home` (Explore), `#v-search`,
    `#v-feed`, `#v-meet` (Social/Chats), `#v-live`, `#v-me` (You);
  - `#dock` (the 5-button bar);
  - about 30 bottom sheets (`.sheet-bg` > `.sheet`): Create, events, Scout, menus, places, quests, notifications,
    plans, rankings, the camera, sign-up (`#onbBg`), rate, and more.
- **Script**: one inline `<script>` (after `config.js`, which sets `window.SQ_CONFIG`) split into commented blocks:
  state, language, helpers, engine, birth chart, matching, server state, events, groups, feed, food & drink, plans,
  stories and the story editor, the place picker, sign-up, Meet, messages, plans with friends, public posts, rewards,
  report/block, render, map, friends on the map, interactions, the V3 drawer, Explore, Search, Find a spot, Scout
  finds your spot, You, live, map layers, Scout, Scout memory, then the V2 block (notifications, event page,
  favorites, quests, invites, Best of loader, Home).
- **State**:
  - `S`: device-local UI and profile state, saved to `localStorage` under `sq-mock-v1`;
  - `SV`: server state from `/api/state`;
  - `EV`: events (also cached in `localStorage` `sq-ev` for 12 hours);
  - smaller per-feature objects (`DRW`, `EXC`, `POP`, `PL`, `SG`, `DM`, `LIVE`, `SF`, `HH`, ...).
- **Navigation**: `tab(t, at)` shows `#v-<t>` and sets the drawer stop. `closeTopOverlay()` and the History API
  handle back. Edge swipes go back and forward.
- **Events**: one delegated click handler dispatches on `data-*` attributes.
- **Talking to the API**:
  - `api(path, body)` POSTs JSON with the same-origin cookie and throws on `{error}`. A 401 reopens login or the
    guest gate.
  - GETs use `fetch` directly.
  - Polling: `/api/state` and threads every 15 s (skipped when the tab is hidden, and nothing is redrawn when the
    response is byte-identical); friend locations and your own location every 30 s; events every 10 minutes; happy
    hours every 10 minutes; the live relay every few seconds while live.
- **Guest gate**: `needAccount('<verb>')` opens sign-up for anything that reaches other people.
- **Lazy assets**: `rankings.js` (after first paint), `lens.js` (first camera use), `vendor/livekit-client.js` (Live
  only).

Privacy rules the client follows: exact GPS, birth date and time never leave the device; locations sent to the server
are rounded (about 1 km for places search, about 100 m for "Add location").

---

## PWA, service worker and push

- **Manifest**: `manifest.webmanifest` (standalone, portrait, icons 180/192/512 including maskable).
- **Service worker** (`sw.js`, cache name `sq-shell-v3-8`; bump it whenever the shell changes):
  - Registered only on https or localhost, and not under automation (`navigator.webdriver`).
  - Pre-caches `/`, the logo, an icon, the manifest and Leaflet.
  - Navigations are network-first, with the cached `/` as the fallback.
  - `/vendor/*`, `.png` and `.webmanifest` are cache-first.
  - It never caches `/api/*`, `/config.js`, stories or avatars.
- **Push**:
  - The inbox's "Phone notifications" switch subscribes with the VAPID public key from `/config.js`, then POSTs the
    subscription to `/api/push` (at most 5 devices; endpoints must belong to a real push service).
  - `notify!` enqueues to `PUSH_Q`. The worker encrypts and sends. A 404 or 410 drops the device.
  - `sw.js` shows the notification and, on tap, focuses or opens a deep link (`/?ev=`, `/?g=`, `/?dm=`,
    `/?inbox=1`, `/?quests=1`, `/?tonight=1`).
  - iPhones need the app on the Home Screen (iOS 16.4+).
  - `SQ_PUSH_CONTACT` is the VAPID `sub`.
  - **Back up `data/vapid.json` with the data.** Losing it means every device has to subscribe again.

---

## Scout and Claude

### Engine

`run_claude(prompt, schema, system:, model:, timeout:, effort:, images:, web:)` (`server.rb:201`) is the single
entry point for every Claude call. It picks one of two engines:

- **API** (`SQ_USE_API_KEY=1` + `ANTHROPIC_API_KEY`, or `SQ_ENGINE=api`):
  - Calls the Anthropic Messages API directly with `Net::HTTP`.
  - Structured output via `output_config.format` (`json_schema`). Numeric, length and array limits are stripped from
    the schema for the API and enforced afterwards (`api_schema`, `api_enforce`).
  - The system prompt is cached (`cache_control: ephemeral`), effort is set per model, and non-Haiku models get the
    server-side fallback beta.
  - One retry on 429/5xx. Cost per call is computed from `API_PRICES`.
  - Model aliases: `haiku` → `claude-haiku-5-5`, `sonnet` → `claude-sonnet-5-5`, `opus` → `claude-opus-5-5`.
- **CLI** (the default when no API key is set):
  - Runs `claude -p --output-format json --json-schema ... --tools "" --strict-mcp-config --no-session-persistence`
    in a temp directory, so no project files leak into the call.
  - Images go in as stream-json; `web: true` allows only WebSearch and WebFetch.
  - It strips `ANTHROPIC_API_KEY` unless `SQ_USE_API_KEY=1`.
  - This bills the developer's personal subscription. Don't use it to serve the public (see `mockup/LAUNCH.md`).

Where Claude is used:

| Use | Model (default) | Notes |
|---|---|---|
| Scout | Haiku for how-to questions; `SQ_SCOUT_SMART_MODEL` (Sonnet) for recommendations, plans and the interview | Effort low, 30 s timeout |
| Picks (`/api/picks`), friend matching (`/api/match`) | `SQ_MODEL` (Sonnet) | |
| Text moderation, live-request screening | `SQ_SCREEN_MODEL` (Haiku) | |
| Photo screening | Haiku | |
| Menus | Haiku, with web search | |
| Translate / language detection | Haiku (`SQ_LENS_MODEL`) | |
| Identify | Sonnet (`SQ_LOOK_MODEL`) | |
| Scout look builder | Haiku | |
| Best of research | Sonnet through the CLI | Offline only, run by `fetch_rankings.rb` |

### Scout request (`POST /api/scout`, `server.rb:2259`)

1. **Gates**:
   - The global daily budget (`SQ_SCOUT_BUDGET_USD`, default $10; an admin can also pause Scout);
   - the per-person daily limit (`SQ_SCOUT_DAILY`, 100) and hourly limit (`SQ_SCOUT_HOURLY`, 40).
2. **Context assembly** (all on the server):
   - the conversation history kept on the server (newest 12 turns of `scout_mem`);
   - `scout_mind_prompt` (persona, turn count, notes, orders);
   - the on-screen `targets` the client can highlight;
   - client `context`: events, flares and friends the user can see, marked as untrusted data;
   - about 15 matching places from `scout_places` (widened zone → nearby → closed-with-opening-time);
   - an area's best-known places;
   - Best of lists for "best X" questions (`rank_for_scout`);
   - sights (`Sights.search`) for history questions;
   - live Google info for a place named in the question (`scout_google`, capped);
   - taste-based events (`taste_for`, `taste_events`);
   - the interview's still-open questions;
   - the check-in follow-up ("what did you get?").
3. **System prompt**: `scout_personality.md` + `scout_self.md` + `scout_knowledge.md`, read again on every call so
   they can be edited without a restart. They are never served to browsers.
4. **Output** (`SCOUT_SCHEMA`):
   - `say` and `expression`;
   - up to 3 `actions`: `point go map place sight search food rsvp flare chat directions event open find`;
   - an optional `plan` (2–6 stops), `remember` (up to 3 notes), `profile` (interview answers), `order`, `persona`.
5. **Server-side validation**:
   - `scout_actions` keeps only actions whose target is something the user was actually sent (their events and
     flares, friend handles, place, sight and food ids, known views), and nothing on screen while driving.
   - `scout_plan` keeps only stops whose `ref` is an id Scout was given.
   - `scout_profile_clean` and `Places.find` validate the profile and order.
   - Nothing posts or sends without a tap: `rsvp` asks for confirmation, and `flare` and `chat` are drafts.
6. **Memory**: `scout_remember!` appends the turn and new notes, filtering out anything that looks like a password,
   SSN or card number. People see and delete notes in You → Scout (`/api/scout/memory`, `/api/scout/forget`).
7. **Failure**: if Claude is unreachable, Scout replies with a friendly canned answer (`fallback: true`). Guests get a
   built-in FAQ on the client (`SC_FAQ`) with no Claude call.

There is no Anthropic tool use in Scout itself. Scout's "tools" are the action list above, which the client carries
out. Web tools are used only by menus (`web: true`) and the offline rankings research.

Voice: `/api/scout/voice` uses Google Cloud TTS (Chirp 3 HD voices, `SCOUT_VOICES`), cached, with a daily character
cap. `/api/scout/hear` uses whisper.cpp + ffmpeg on the server for phones whose browser speech recognition doesn't
work (`HEAR` is on only when the binaries and model exist).

---

## External services and environment variables

Only the variable names are listed here. `deploy/env.example` is the template, with comments for each. Secrets in
production live in `/etc/sidequest/env` (root, 0600). Locally they are sourced from `~/.sidequest.env`,
`~/.sidequest-google.env` and `~/.sidequest-livekit.env` by the start scripts.

| Service | Enables | Variables |
|---|---|---|
| Anthropic API | All Claude features (production) | `SQ_USE_API_KEY`, `ANTHROPIC_API_KEY`, `SQ_ENGINE`, `SQ_API_URL` (tests) |
| Claude Code CLI | Claude features locally; rankings research | `CLAUDE_BIN`, `SQ_ENGINE=cli` |
| Models and effort | | `SQ_MODEL`, `SQ_SCREEN_MODEL`, `SQ_SCOUT_MODEL`, `SQ_SCOUT_SMART_MODEL`, `SQ_LENS_MODEL`, `SQ_LOOK_MODEL`, `SQ_MENU_MODEL`, `SQ_RANK_MODEL`, `SQ_HAIKU_EFFORT`, `SQ_SONNET_EFFORT` |
| Claude limits | | `SQ_SCOUT_DAILY`, `SQ_SCOUT_HOURLY`, `SQ_SCOUT_BUDGET_USD`, `SQ_MENU_HOURLY`, `SQ_MENU_DAILY`, `SQ_MENU_PAR`, `SQ_MENU_PREWARM*`, `SQ_LENS_HOURLY`, `SQ_LENS_DETECT_HOURLY`, `SQ_LOOK_HOURLY`, `SQ_RANK_PAR` |
| Moderation | Claude text and photo screening | `SQ_MODERATE`, `SQ_PHOTO_SCREEN` |
| Google Places (New) | Ratings, hours, phone, photos, nightclubs, Scout's live lookups | `SQ_GOOGLE_PLACES_KEY`, `SQ_GOOGLE_DAILY`, `SQ_GOOGLE_PHOTOS_DAILY`, `SQ_GOOGLE_NIGHT_DAILY`, `SQ_GOOGLE_API_URL` (tests) |
| Google Map Tiles | Google basemap instead of OSM | `SQ_GOOGLE_MAPS_BROWSER_KEY` (browser key, sent to clients) |
| Google Identity | Continue with Google | `SQ_GOOGLE_CLIENT_ID`, `SQ_GOOGLE_TOKENINFO_URL` (tests) |
| Google Cloud TTS | Scout's voice | `SQ_GOOGLE_TTS_KEY`, `SQ_TTS_DAILY_CHARS`, `SQ_TTS_URL` (tests) |
| LiveKit | Live video relay, RTMP Ingress, YouTube/TikTok Egress | `SQ_LIVEKIT_URL`, `SQ_LIVEKIT_KEY`, `SQ_LIVEKIT_SECRET`, `SQ_LIVEKIT_API_URL`, `SQ_LIVEKIT_SELFHOST`, `SQ_DOMAIN` |
| Web Push | Phone notifications | `SQ_PUSH_CONTACT` (key itself: `data/vapid.json`), `SQ_PUSH_TEST_HOST` (tests) |
| whisper.cpp / ffmpeg | Server speech-to-text, video frames, image resize | `SQ_WHISPER_BIN`, `SQ_WHISPER_MODEL`, `SQ_FFMPEG_BIN`, `SQ_PDFTOTEXT` |
| Events service | Events | `SQ_EVENTS_API` |
| OpenStreetMap | Tiles, Overpass (ingest), Nominatim geocoding (1/s, cached) | none |
| Wikipedia / THC Atlas | Sights ingest | none |
| Server mode | | `PORT`, `SQ_BIND`, `SQ_LAN`, `SQ_LAN_PORT`, `SQ_BEHIND_PROXY`, `SQ_BETA`, `SQ_DEMO`, `SQ_INVITES`, `SQ_ADMIN_TOKEN`, `SQ_SIGNUPS_PER_HOUR`, `TZ` (defaults to America/Chicago) |
| Fixture overrides | Tests | `SQ_PLACES_FILE`, `SQ_OUTDOORS_FILE`, `SQ_SIGHTS_FILE`, `SQ_AREAS_FILE`, `SQ_MARKETS_FILE`, `SQ_POPULAR_FILE`, `SQ_RANKINGS_FILE`, `SQ_MENU_DIR` |

Modes:

- **Demo content is off by default.** `DEMO = ENV['SQ_DEMO'] == '1'`. The header comment in `server.rb` and an older
  CLAUDE.md line still say "demo on"; the code wins.
- `SQ_BETA=1` turns on menu pre-warm and the public-beta defaults.
- `SQ_ADMIN_TOKEN` empty means `/admin` is off.

---

## HTTP API

POST + JSON unless the route is marked GET. **Auth** means a signed-in session is required; *guest* means it works
without one. All routes return `{error}` with a 4xx status on failure.

### Static, pages and media

| Method | Path | Purpose |
|---|---|---|
| GET | `/`, `/<whitelisted file>`, `/admin`, `/lens` | App shell and whitelisted static files (ETag, gzip) |
| GET | `/config.js` | `window.SQ_CONFIG` feature flags and public keys |
| GET | `/api/health` | Engine, model, beta and demo status |
| GET | `/avatar/<h>.jpg` | Profile pictures |
| GET | `/story-img/…`, `/story-vid/…` | Story media (video with byte ranges, which iOS needs) |
| GET | `/img/ev?u=&w=` | Event posters shrunk with ffmpeg (only URLs in the current events list) |
| GET | `/img/menu?id=&i=` | Saved menu pictures, shrunk |
| GET | `/group-img/…`, `/wall-img/…` | Group and public post photos (visibility checked) |
| GET | `/dm-img/…`, `/dm-aud/…` | Chat photos and voice notes (signed-in only, byte ranges) |
| GET | `/e/<uid>`, `/s/<id>`, `/i/<handle>[/<key>]`, `/r/<list>` | Share pages with Open Graph previews for an event, a sight, an invite, a Best of list; they redirect into the app |

### Accounts, profile, social graph

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/me` | guest | Current handle + own matching profile |
| POST | `/api/signup` | guest | Handle + password (or Google ticket), 18+, Terms, optional invite code, referral |
| POST | `/api/login` | guest | Password login (rate-limited per IP and handle) |
| POST | `/api/google` | guest | Google ID token → sign in, or a 15-minute ticket to choose a handle. **Paused** unless `SQ_GOOGLE_SIGNIN=1` (refuses with 401) |
| POST | `/api/logout` | guest | End the session |
| POST | `/api/account/delete` | auth | Delete the account and its content (requires the password) |
| POST | `/api/profile` | auth | Public profile (moderated), matching answers, color, emoji avatar |
| POST | `/api/me/photo` | auth | Profile photo upload or removal (photo-screened) |
| GET | `/api/state` | guest | Everything this viewer may see: users, RSVPs, groups, posts, stories, plans, friends, V2 counters |
| POST | `/api/presence` | auth | Online / offline |
| POST | `/api/friend` | auth | Wave/request, accept, remove |
| POST | `/api/block` | auth | Block / unblock |
| POST | `/api/report` | auth | Report content or a person |
| POST | `/api/feedback` | auth | In-app feedback |
| POST | `/api/close` | auth | Close-friends list |

### Events, posts, stories, groups

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/events` | guest | Proxied events (5-minute server cache, ETag, kids' events filtered, geofixed) |
| POST | `/api/rsvp` | auth | Going / interested |
| POST | `/api/post` | auth | Create a hangout (flare) |
| POST | `/api/down` | auth | "I'm down" on a hangout |
| POST | `/api/media` | auth | Raw story video upload (≤60 MB) → id |
| POST | `/api/story` | auth | Create or remove a story (moderated, photo-screened) |
| POST | `/api/story/like`, `/api/story/seen`, `/api/story/vote` | auth | Like, view tracking, poll vote |
| POST | `/api/story/viewers` | auth | Author's viewer list |
| POST | `/api/group/create`, `/api/group/join` | auth | Create or join a group |
| POST | `/api/group/feed`, `/api/group/post`, `/api/group/act`, `/api/group/admin` | auth | Group wall, posting, like/comment/vote/going, admin actions |
| POST | `/api/group/chat`, `/api/event/chat` | auth | Group and event discussion |
| POST | `/api/event/invite` | auth | DM friends an event link |
| GET | `/api/wall`, `/api/wall/one` | guest | Public posts (ranked; scope all/friends/near/user) |
| POST | `/api/wall/post`, `/api/wall/act` | auth | Create; like, comment, delete, boost |

### Chats and plans

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/dm/threads`, `/api/dm` | auth | Thread list; one thread |
| POST | `/api/dm/send`, `/api/dm/react`, `/api/dm/unsend`, `/api/dm/read`, `/api/dm/typing` | auth | Messaging |
| POST | `/api/dm/voice` | auth | Raw voice-note upload |
| POST | `/api/chat/new`, `/api/chat/edit` | auth | Group chat create, rename, add, leave |
| POST | `/api/hangout/new`, `/api/hangout/act` | auth | Plans with friends: create; vote, add, lock, going |
| POST | `/api/plans` | auth | Your saved itineraries |

### Map data and places

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/places` | guest | Search food and drink (category, cuisine, zone, open now, near) |
| GET | `/api/places/map` | guest | Compact map rows (cacheable for 15 minutes) |
| GET | `/api/place` | guest | One place + bar food + Side Quest rating |
| GET | `/api/place/google` | guest | Google rating, price, hours, phone, photos (daily-capped) |
| GET | `/api/place/thumb`, `/api/place/photos` | guest | Google photo thumbnails and venue photos (capped) |
| GET | `/api/place/menu` | guest* | Menu (cached for guests; signed-in users start a Claude read) |
| POST | `/api/place/barfood` | auth | Report "serves food / kitchen closes at" |
| GET | `/api/places/after` | guest | Food still open after a venue or event ends |
| GET | `/api/places/nightclubs` | guest | Google nightclubs near a ~2 km cell (capped, not stored) |
| GET | `/api/places/hotspots` | guest | Hot-spot zones (always drawn on the map) |
| GET | `/api/pulse/heat?lat&lng&km` | guest | Heat map: busy food & drink places (live vibe level, else this hour's forecast), live first |
| GET | `/api/pulse?lat&lng&km` | guest | Pulse: notable places, trending, zones, events gaining RSVPs |
| GET | `/api/pulse/place?id=` | guest | A place's vibe check, facts, proof, events |
| POST | `/api/pulse/vibe` | auth | How it is right now `{id, v, tags, lat, lng}`; must be within 300 m |
| POST | `/api/pulse/pick` | guest | Your move tonight + Plan B |
| GET | `/api/pulse/feed` | guest | Stories / posts / live worth watching before you go |
| GET | `/api/places/happy` | guest | Happy hours from the menus already read |
| GET | `/api/dishes` | guest | Dish search across menus already read |
| GET | `/api/areas`, `/api/markets`, `/api/outdoors` | guest | Areas, farmers markets, parks/water/trails |
| GET | `/api/gyms` | guest | Gyms, climbing, yoga, boxing, CrossFit, dance, ice rinks, rec centers (`data/gyms.json`, with weekly hours) |
| GET | `/api/sights`, `/api/sight` | guest | Sight dots; one sight's story |
| GET | `/api/spots` | guest | "Add location" search |
| GET | `/api/geocode` | guest | Nominatim lookup (1/s, cached) |
| GET | `/api/rating` | guest | A place's average Side Quest stars |
| POST | `/api/rate` | auth | Stars + dish + note ("what did you get?") |

### Best of Austin

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/rankings` | guest | Index of groups and lists |
| GET | `/api/rankings/cat?k=&lat=&lng=` | guest | One ranked list with reasons, sources, distance, open now |
| POST | `/api/rankings/vote` | auth | ⭐ 1–5 (0 takes it back) + "would go back" |
| POST | `/api/rankings/suggest` | auth | "Missing a spot?" (10 a day) |

### Scout, AI and camera

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/scout` | auth | Ask Scout (see above) |
| GET | `/api/scout/memory` | auth | Notes, orders, recent conversation |
| POST | `/api/scout/forget` | auth | Forget one note, the chat, or everything |
| POST | `/api/scout/look` | auth | Describe the assistant's look → drawable parts |
| POST | `/api/scout/voice` | guest | Text → MP3 (Google TTS) |
| POST | `/api/scout/hear` | auth | Raw audio → text (whisper.cpp) |
| POST | `/api/picks` | auth | Claude ranks tonight's picks (20 an hour) |
| POST | `/api/match` | auth | Claude ranks likely friends (10 an hour) |
| POST | `/api/translate`, `/api/lens/lang` | auth | Live Translate; language detection |
| POST | `/api/lens/identify` | auth | "What is this?" |

### Live video

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/screen` | auth | Screen a viewer request (hard rules + Claude) → signed 10-minute pass |
| POST | `/api/live/token` | auth | LiveKit token (publish only to `live-<you>`) |
| POST | `/api/live/ingress` | auth | Permanent RTMP address/key for an action camera or OBS |
| POST | `/api/live/restream` | auth | Copy out to YouTube/TikTok RTMP (LiveKit Egress) |
| GET/POST | `/api/relay` | auth | Polling message relay: stream announcements, requests, WebRTC signalling |

### V2: notifications, quests, rewards, analytics

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/notifs` | auth | Inbox list, mark read, mute kinds |
| POST | `/api/push` | auth | Save or remove a Web Push subscription |
| GET | `/api/quests` | auth | Quests, XP, level, badges |
| POST | `/api/quests/board` | auth | Friends leaderboard / opt out |
| POST | `/api/checkin` | auth | Check in (sight, place, area, event; the server looks up the place) |
| POST | `/api/saves` | auth | Favorites (events, places, sights, dishes) |
| GET | `/api/leaderboard`, `/api/rewards` | auth | Leaderboards; coins, frames, challenge |
| POST | `/api/rewards/frame`, `/api/coins/tip` | auth | Buy/wear a frame; tip a streamer |
| GET | `/api/loc/friends` | auth | Friends' locations |
| POST | `/api/loc`, `/api/loc/settings` | auth | Send your location; sharing mode |
| POST | `/api/t` | guest | Analytics beacon (whitelisted event names only) |

### Admin (header `X-Admin-Token`)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/admin` | Reports, feedback, users, unreviewed content, photo takedowns, live streams |
| POST | `/api/admin` | Actions: `resolve`, `remove`, `approve`, `ban`, `delete_user`, `end_stream`, `scout_pause` |
| GET | `/api/admin/growth` | DAU/WAU, retention, sign-ups, top taps |

---

## Data-ingest scripts

Run these from `mockup/`. They write to `mockup/data/`, and the server reloads most of these files when they change.
None of them run on their own, except the weekly places refresh that `install.sh` puts in the server's crontab.

| Script | Fetches | Writes | When to run |
|---|---|---|---|
| `ruby fetch_places.rb` (`--blocks` when Overpass is slow, `--merge` to rebuild) | OSM Overpass, ~460 tiles or ~20 blocks (San Marcos to Georgetown, Lake Travis to Taylor), resumable, 3 mirrors; drops national chains; then merges Overture + TABC (duplicates, chains and junk dropped) | `places.json` | Weekly (`--fresh`) |
| `~/.sidequest-data/bin/python fetch_overture.py` | Overture Maps places (food & drink + venues) from the latest release on S3, via DuckDB (this Mac only; venv `~/.sidequest-data` with `duckdb`) | `overture.json` | Every month or two, then `--merge` |
| `ruby fetch_tabc.rb` | Active on-premise TABC licenses (Travis, Williamson, Hays), geocoded with the US Census batch geocoder | `tabc.json` | Monthly, then `--merge` |
| `ruby fetch_outdoors.rb` | OSM parks, greenbelts, lakes, rivers, trails, rentals, ramps, fishing, trailheads | `outdoors.json` | Rarely (seasonal) |
| `ruby fetch_gyms.rb` | OSM gyms and fitness (private, kids' and non-gym sports places dropped) + rinks OSM lacks, geocoded | `gyms.json` | Every few months (under a minute) |
| `ruby fetch_sights.rb` | Texas Historical Commission markers (Atlas), National Register, Wikipedia geosearch, OSM museums/art | `sights.json` (+ `sights_cache/`) | Rarely; ~15 minutes the first time. `--merge` rebuilds from the cache. |
| `ruby fetch_areas.rb` | Nominatim outlines for ~60 neighborhoods, streets and towns | `areas.json` | When the area list changes |
| `ruby fetch_markets.rb` | Hand-kept farmers-market list, geocoded | `markets.json` | Each season (recheck the hours) |
| `ruby rank_popular.rb` | Wikipedia page views + a hand list + listing completeness | `popular.json` | After the places or sights change. `--merge` reuses cached views. |
| `ruby fetch_rankings.rb [list…\|--all\|--relink\|--rematch]` | Claude (Sonnet, through the **CLI** with WebSearch/WebFetch, 4 in parallel) researches best-of lists; then every link is opened, dead ones dropped, and spots matched to our places or geocoded | `rankings.json`, `rank_geo.json` | Weekly. With no arguments it refreshes lists older than 7 days. About 2–4 minutes and roughly $0.30 per list. `--relink` and `--rematch` need no Claude. |

`geofix.rb` geocodes event venues on the fly (cached in `geofix.json`), so it has no script of its own.

`deploy/push.sh` copies `areas, markets, outdoors, places, popular, sights, geofix, rankings` JSON to the server with
`rsync --update`, so the server's newer weekly `places.json` is not rolled back.

---

## Running locally

Requirements:

- Ruby with WEBrick. macOS system Ruby 2.6 includes it; on Ruby 3.0 or later run `gem install webrick`.
- For the events: the `~/claude/live` service.
- Optional: the Claude Code CLI (`~/.local/bin/claude`) or an API key, `ffmpeg`, `pdftotext`, whisper.cpp.

```sh
~/claude/live/serve.sh            # events service on :8788 (separate terminal)

cd mockup
./start_v3.sh                     # V3 on http://localhost:8802 + https://<LAN IP>:8446 (self-signed), own data folder
./start_v3.sh --keys              # also loads Google + LiveKit keys from ~/.sidequest-google.env / ~/.sidequest-livekit.env
./start_v3.sh --voice             # only Scout's Google voice
./start.sh                        # plain: http://localhost:8787 with keys if present
./phone.sh                        # start.sh + LAN HTTPS (SQ_LAN=1)
./beta.sh                         # public-beta mode; needs SQ_ADMIN_TOKEN in ~/.sidequest.env
ruby server.rb                    # bare: :8787, no keys, demo off, CLI engine
```

Notes:

- Without an API key, Claude features shell out to the local Claude Code CLI. That bills the subscription; see
  LAUNCH.md.
- Without the events service, `/api/events` returns 502 and the app shows no events. Everything else still works.
- Several Claude sessions often run test servers on this machine at the same time. Stop servers **by PID or port**,
  never with `pkill -f "ruby server.rb"`.
- `start_v3.sh` uses `SQ_LAN=1`, which listens on every interface, and falls back to a fixed, guessable admin token
  if `SQ_ADMIN_TOKEN` isn't set. Set your own token on shared networks (see Known limitations).

---

## Testing

### Ruby tests (no internet, no Claude, no keys)

Each test that needs a server starts a throwaway copy with an empty data folder on its own port, so your data is
untouched. Run them from `mockup/`:

```sh
ruby test_hours.rb      # opening_hours parser
ruby test_webpush.rb    # RFC 8291/8292 vectors, SSRF guard            (6)
ruby test_geofix.rb     # event spots, popularity, markets, areas, kids filter (13)
ruby test_spots.rb      # Add-location search                          (15)
ruby test_menus.rb      # menu fetcher, parsing, dish search, happy hours (41)
ruby test_tonight.rb    # 5 PM picks                                   (6)
ruby test_api.rb        # Anthropic API engine vs a fake API on :9911
ruby test_google.rb     # Google Places + Sign in with Google vs fakes, server on :8794 (17)
ruby test_live.rb       # live safety, LiveKit ingress/egress vs fake LiveKit, server on :8795 (14)
ruby test_v2.rb         # V2 server features, chats, groups, stories, posts, photos, live, server on :8799 (64)
ruby test_pulse.rb      # Pulse engine: forecasts, heat, vibe, facts, picks, media (41, no server)
ruby test_pulse_api.rb  # Pulse routes incl. heat map, flares, live, remote reports refused (17, server on :8805)
ruby test_gyms.rb       # gyms file + hours, Scout's nearest-gym lookup by kind (11, no server)
ruby test_sources.rb    # Overture / TABC merge rules: kinds, chains, duplicates, junk, alcohol (19, no network)
```

**Last run: 2026-10-27, on this checkout at `3165edd`, all ten passed** (hours: all; webpush 6/6; geofix 13/13; spots
15/15; menus 41/41; tonight 6/6; api: all checks PASS; google 17/17; live 14/14; v2 64/64). Total time was about
25 seconds. `scout_mind.rb` (the memory routes, personalities, `/api/rate`) and `rankings.rb` have no Ruby unit tests
of their own yet. `/api/rankings*` is covered by `e2e_rank.py`.

### Playwright end-to-end tests (Python)

These need `pip install playwright && playwright install` (a scratch venv is fine) and a test server started on a
**copy** of `mockup/` with an empty `data/app.json` and the fixture files, for example:

```sh
SQ_PLACES_FILE=test_places.json SQ_OUTDOORS_FILE=test_outdoors.json SQ_SIGHTS_FILE=test_sights.json \
  SQ_ADMIN_TOKEN=test PORT=8796 ruby server.rb           # add SQ_DEMO=1 for suites written around demo people
SQ_BASE=http://localhost:8796 python e2e_test.py <shot-dir>   # two new users through the whole app (117)
SQ_BASE=http://localhost:8796 python e2e_v3.py <shot-dir>     # drawer, chips, search, dock, desktop (41; SQ_BROWSER=webkit: 36)
SQ_BASE=… SQ_ADMIN_TOKEN=test python e2e_v2.py <shot-dir>     # V2 features (41)
SQ_BASE=… python e2e_rank.py <shot-dir>                        # Best of Austin (24; needs data/rankings.json)
SQ_BASE=… python e2e_heat.py <shot-dir>                        # heat map + hot spots always on, vibe card, no Google button (9; real places)
SQ_BASE=… python e2e_gyms.py <shot-dir>                        # Gyms chip, kinds, open now, card, check-in, search, layers (16; data/gyms.json)
SQ_BASE=… python e2e_venues.py <shot-dir>                      # venues & breweries: Nightlife chip, pins, cards, alcohol, search, credit (11; merged places)
SQ_BASE=… python e2e_scout_cancel.py <shot-dir>                # Scout cancel: ✕ button, orb tap, spoken "never mind", late answers ignored (17)
SQ_DEMO=0 SQ_MODERATE=0 … python e2e_live.py <shot-dir>        # 1 streamer + 3 viewers (14)
```

The counts are from `V3_REPORT.md` and CLAUDE.md. They were **not** re-run for this README. Stop the test server and
reset its `data/app.json` to `{}` before and after a run.

---

## Deploying

Target: a Hetzner box running Ubuntu, Caddy (automatic HTTPS) for `sidequest.cc.middlematter.com`, and systemd. All
of the following is in `deploy/` (described here only; this README did not run any of it):

- **`push.sh user@host`**, run from the Mac:
  1. rsyncs `mockup/` to `/opt/sidequest/app` (`--delete`, excluding `data/`, `*.py`, `lens_test/`);
  2. pushes only the map/data JSON files with `--update` (never user data);
  3. rsyncs `~/claude/live` to `/opt/sidequest/events` (excluding `.venv`, `data/`);
  4. copies `deploy/`;
  5. runs `install.sh` over ssh.
- **`install.sh`**, run as root on the server; safe to re-run:
  - installs ruby, python3-venv, caddy and poppler-utils, plus the webrick gem;
  - creates the `sidequest` user and `/etc/sidequest/env` from `env.example`, and stops until `SQ_ADMIN_TOKEN` is set
    (it warns if `ANTHROPIC_API_KEY` is missing);
  - builds the events venv;
  - optionally installs whisper.cpp + ffmpeg and a model whose checksum it verifies;
  - installs and starts `sidequest.service` (`ruby server.rb`, `ReadWritePaths=app/data`) and
    `sidequest-events.service` (uvicorn on 127.0.0.1:8788);
  - downloads places the first time;
  - adds cron jobs: nightly `backup.sh` at 4:15 AM and the weekly `fetch_places.rb --fresh` on Monday at 4:30 AM;
  - with `SQ_LIVEKIT_SELFHOST=1`, installs a pinned, checksum-verified `livekit-server`, its keys file, TURN
    certificates from Caddy (`livekit-cert.sh`, daily cron), firewall ports, and `sidequest-livekit.service`;
  - finishes with `curl 127.0.0.1:8787/api/health`.
- **`Caddyfile.snippet`**: gzip, a 2 MB request-body cap, `/livekit/*` → 7880, everything else → 8787.
- **`backup.sh`**: a nightly tarball of app and events data in `/var/backups/sidequest`, keeping 14 days.
- **`google-places-setup.sh`**: uses gcloud to create the project, billing, APIs, restricted keys and a budget alert.
- **`env.example`**: every production variable, with comments.

Production checklist (from `mockup/LAUNCH.md`): set `SQ_USE_API_KEY=1` + `ANTHROPIC_API_KEY` (not the personal
subscription), `SQ_BEHIND_PROXY=1`, `SQ_BIND=127.0.0.1`, and `SQ_ADMIN_TOKEN`; have a lawyer review `terms.html` and
`privacy.html` (both marked DRAFT); have someone check `/admin` daily.

Note: `push.sh` excludes `*.py`, but it ships `test_*.rb` and the test fixtures. They are inert, because only
`PUBLIC_FILES` are served.

---

## Sibling folders and branches

The git repo is `github.com:kevrkid/sidequest`. The main checkout is `../sidequest-v2`, and this folder and
`../sidequest-v3-pulse` are `git worktree`s of it.

| Folder | Branch | What it is |
|---|---|---|
| `../sidequest` | not a git repo | **V1**, the original prototype (ports 8787/8443). Kept untouched; backup in `../sidequest-v1-backup-2026-10-20` and `../backups/`. Branch `v1-baseline` (`2a5cf6a`) is a copy of it. |
| `../sidequest-v2` | `v2` | **V2**: notifications, push, quests, event pages, chats, groups, stories+, posts, rewards, Live Translate, menus. Classic tabbed UI. `start_v2.sh` on 8797/8444. `v3` is 31 commits ahead of `v2` and `v2` has nothing `v3` lacks. |
| `sidequest-v3` (here) | `v3` | **V3**: everything in V2 plus the map-first shell, Liquid Glass, Best of Austin, Find a spot, Scout memory and personalities. `start_v3.sh` on 8802/8446, with its own data folder. |
| `../sidequest-v3-pulse` | `v3-pulse` | **Merged into v3 on 2026-10-27.** The branch that built **Pulse** (`pulse.rb` + `pulse.js`): live vibe heat, 168-hour per-place busy forecasts (`data/pulse.json`), trending places, `/api/pulse/pick` (one place tonight + Plan B), `/api/pulse/feed`, vibe reports. The worktree is kept for history; work on Pulse now happens in v3. |

---

## Known limitations and risks

**Scale**

- **Single JSON file, single lock.** Every write rewrites all of `app.json` (`pretty_generate`) while holding the one
  global mutex. Writes include frequent ones such as `/api/presence`, Scout billing, ratings and DM reads. Every
  session lookup takes the same lock.
- **`/api/state` cost.** Every client polls it every 15 s. `state_for` scans all users for blocks
  (`blocked_between`) and bans, and returns every user, post and story the viewer may see. This is O(users) per poll,
  so O(users²) per interval overall. LAUNCH.md already says to move to Postgres before "a few hundred people".
- **Single process, in-memory state.** You can't run two instances behind a load balancer. A restart loses rate
  limits, presence, friend locations, live streams and relay messages.
- The live relay is HTTP polling. LiveKit is needed for real audiences and mobile networks.
- `index.html` is an 800 KB single file with inline JS. It is hard to review, and every change invalidates the whole
  cached shell.
- `RATE[:hits]` keeps a key for every IP, handle and path it has ever seen (expired timestamps are dropped, keys are
  not), so it grows until restart.

**Safety, privacy and cost**

These are details from the code review; see the review notes for file and line numbers.

- `moderate()` sends only the first 600 characters to Claude. Wall posts allow 2,200 and group posts 2,000, so the
  rest is never screened. `/api/profile` ignores `moderate()`'s "unavailable" result, so profile text goes public
  unflagged when Claude is down. The size of the `public` profile hash is not bounded.
- Accounts created with Google have no password, but `/api/account/delete` requires one, so those users cannot
  delete their accounts. Sign in with Google is paused (2026-10-27, `SQ_GOOGLE_SIGNIN`), so no new ones are made, but
  existing Google-only accounts also can't sign in until it's turned back on or they get a password.
- Deleting an account leaves `rank_votes`, `barfood` and `rank_suggest` entries under the handle. Votes count again
  if someone later registers the same handle.
- `/api/picks` and `/api/match` (Sonnet, up to 60 KB of client-supplied context) have hourly limits but no daily cap,
  and they don't count toward Scout's dollar budget.
- `/api/scout/voice` is open to guests at 120 calls an hour per IP, 600 characters each. One IP can use up the global
  daily TTS cap (30,000 characters by default) in minutes.
- `/dm-img` and `/dm-aud` check only for *a* signed-in session, not chat membership. The 64-bit random filenames are
  the only protection.
- `start_v2.sh` and `start_v3.sh` fall back to a fixed, guessable admin token and listen on all interfaces.
- Moderation fails open for posts (they go up flagged `unreviewed`), and someone must check `/admin`. Chat photos are
  not screened.
- The CLI engine bills a personal Claude subscription. Use the API engine for any public use.
- Google's terms: only place ids are stored. Details and photos are fetched per tap and capped daily, so if the caps
  are hit, the app quietly falls back to OSM.

**Data quality and docs**

- OSM hours cover about 45% of places. Hours can be stale, and holidays are ignored.
- The events depend on an external scraper. Some venues are geocoded wrongly, and events with no usable address are
  left off the map.
- Best of Austin suggestions are saved in the **server's** `app.json`, but `fetch_rankings.rb` reads its local
  `data/app.json` and runs where the Claude CLI is (the Mac). `push.sh` only pushes, so production suggestions never
  reach the research unless the data is copied back.
- Docs drift: the `server.rb` header comment and part of CLAUDE.md say demo content is on by default. It is off
  (`SQ_DEMO=1` turns it on).
- The service worker pre-caches only `/` and a few assets. `glass.css`, `rankings.js` and `lens.js` aren't cached, so
  the offline shell loads without the glass styles.
- No password reset; the admin login is a shared token; Terms and Privacy are drafts.

---

## Conventions

These come from CLAUDE.md; keep to them.

- **No dependencies.** No npm, no gems (except webrick on Ruby 3 or later), no frameworks, no build step. Vendor
  small libraries into `mockup/vendor/` and add them to `PUBLIC_FILES`.
- **Mobile first.** Design for 390 px and check 360 px. Theme tokens live on `:root`; V3 overrides go in `glass.css`
  under `#app.v3`.
- **The server enforces visibility** (`state_for`, the per-route checks). Never rely on hiding something in the
  browser.
- **Guest gate.** Anything that reaches other people goes through `needAccount()`.
- **Claude calls** must be signed-in only, rate-limited, short-timeout and fail safe. Every Claude-ranked item shows
  its reasons. Scout may only act on ids it was sent.
- **Privacy by default.** Profile answers start as "Matching only", exact GPS and birth details stay on the device,
  and location sharing is opt-in and blurred.
- **Keep `scout_knowledge.md` current** when features change. Bump `CACHE` in `sw.js` when the shell changes.
- **After a change**, syntax-check the inline script, run the relevant `test_*.rb`, run the e2e suite against a copy,
  and look at the screenshots.
