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
- **V3 layout: the map is the app** (branch `v3`, folder `~/claude/sidequest-v3`). The Leaflet map (`#v-map`) fills the
  screen and is never hidden. Over it: a **drawer** (`#drawer`) and under that a 5-button **dock** (`#dock`: Explore ·
  For you · ＋ · Chats · You; `data-dock`). The drawer has three stops, `peek` (search box + chips + one "glance" line),
  `half`, `full` (`setDrawer(at)`, `drawerStops()`, `DRW.at`); drag it by its top, flick, or drag anywhere in it until
  it's full; a mouse drags the handle and the wheel opens/closes it; dragging the map drops a half drawer to peek
  (`mapWantsRoom`). Every screen is a `.view` inside the drawer: `tab(t, at)` shows `#v-<t>` and sets the stop
  (`home` = Explore, default half; `map` = Explore at peek; feed/meet/me/live/search = full). `--dvis` on `#app` is how
  much of the screen the drawer + dock cover, so map overlays (Scout button, LIVE pill, Leaflet attribution, popup
  autopan) sit above it. ≥900px wide (`WIDE()`): the drawer is a fixed panel on the left, always open.
  - Top, floating: the name (`#logo`, back to the map at peek) and the bell; guests also get an orange "Sign up" pill
    (`#meChip`, hidden for members: You is in the dock, whose avatar gets a green ring when online). Right side: layers
    and locate (SVG icons from the `<symbol id="i-…">` sprite at the top of `#app`; `svgI(name)`). Location sharing
    (ghost) is a row in You and at the top of the Layers sheet (`data-yshare` → `openShareSheet()`). At `full` the top
    becomes a solid bar and the map buttons/credit hide.
  - **Search** (`#qIn`, `openSearchView`, `renderSearch`, `searchGo`): one box for places (PL.all + parks/lakes/trails
    + sights, nearest first), events, people, groups; "Find it on menus" (`openDishes`), "Search posts and the feed"
    (`runSearch`), and "Ask Scout" (questions go straight to Scout, `isQuestion`). Recent searches in `S.recentQ`.
    The old Search sheet still exists as `openSearchSheet()`; `openSearch()` now focuses the box.
  - **Chips** (`#mapChips`, `EX_CHIPS`, `exploreCat(k, sub)`, `EXC`): Food, Events, Nightlife, Outdoors, Sights,
    Friends, Hot spots. A chip turns the map to just that (`EX_LAYERS`; the previous layers are kept in `S.exPrev` and
    put back by tapping it again (it shows a ✕) / back, `exploreClear`), always at half, and lists it in the drawer
    (`#exCat`, `renderExCat`) under sub-chips (`EX_SUBS`, `data-exsub`; food and nightlife start with a "● Open now"
    toggle, `data-exopen`). Rows are `.xrow` `data-xgo="pl|id"` etc. → `searchGo` → focusPlace / focusSight / mapGo /
    focusOnMap (`evmap`; search results use `ev` = the event page). `exAfter(el, pts, fresh)` scrolls the picked sub-chip
    into view and, when just picked, flies the map to frame the results above the drawer.
    Hot spots: the sub-chips are the neighborhoods (`PL.hot`); picking one flies the map there and lists
    `/api/places?zone=` (tap it again for all of them). Explore's "Busy right now" cards open the same.
  - **Pin cards** (`POP`, `popToDrawer` / `popClosed` on Leaflet's popupopen/close): every map popup's content node is
    moved into `#exPop` (the drawer, at a `half` sized to the card) and the bubble is hidden (`.leaflet-popup.indrawer`);
    later `setContent` calls still land there. A ring marks the pin (`.popring`); ✕ (`data-popclose`) / back / another
    pin closes it and the drawer goes back where it was (or to the chip's list). Leaflet's autopan is off; we
    `panInside` above the drawer. Tests should look in `#exPop`, not `.leaflet-popup`.
  - **Press and hold** the map (`contextmenu`, `mapHold`): a card with the nearest place/sight within 150 m, 📣 Flare
    here (`data-holdflare`: compose with that place), the place, Directions.
  - **Explore** (`#v-home`, `renderHome`): Up next, Friends out, Tonight near you, Happy hour now (`happyRail`), Open
    near you (`openRail`, `/api/places?open=1`, every 10 min), Busy right now (`hotRail`), This weekend (`weekendRail`).
    Stories are at the top of For you (`#feedStories`); `#homeStories` and `#quickBar` are hidden in V3 (level/coins
    are on You). `renderGlance` writes the peek line (hidden while a chip or search is open).
  - The map starts calm (`S.v3map` once): events, flares, friends, live, parks/water, markets; food, nightlife, hot
    spot zones, trails and sights come with their chip or the layers sheet.
  - **Chats** = the old Meet screen (`#v-meet`), tabs Messages · Friends · Groups · Meet (swipe), Messages first
    (`meetTab='msgs'`); an open chat takes the whole drawer (`.inthread`). Dock badge = unread + friend requests.
  - **You** (`#v-me`, `renderYou`): picture, Online switch (`#presBtn` moved here), one level/coins/streak line and a
    friends count (`#youStats`), a list (My plans, Saved, Quests & rewards, Invite, Location sharing, Edit profile,
    Settings & privacy, Español; `data-menu` / `data-quick` / `data-yedit` / `data-yshare`). The old four profile tabs
    sit in `#meEdit`, hidden until Edit profile / Settings (or any `showMeSec()`); the dock's You hides them again.
    The name menu (`#meMenu`) is gone; `data-menu` still works anywhere.
  - **For you**: title + Happening | Posts (`#feedMode`, beside the title) + map/filter icons, one chip row (a 📅 chip cycles the time window,
    `data-fwhen`; `#feedWhen` is hidden), the meta line only when something narrows it, no live cards (the map's LIVE
    pill has them). "Scout is picking…" (never "Claude").
  - **Event page** (`renderEventSheet`): one "I'm going" with ❤️ / 🔗 / map icon buttons (`.evmain`), Directions ·
    Calendar · Tickets (`.evrow3`), "With friends" Invite · Plan it · Send (`.evfriends`), Eat after / menu; Check in only
    when within 250 m while it's on; compact header without a photo (`.evhero.noimg`). "Interested" is only on feed cards.
  - LIVE pill: small, top-left of the map (`.maplive`). Hot spot labels are "🔥 name · N open"; tapping a zone opens it
    in the drawer. Guests get one "Create account" in Chats → Messages. The Create sheet uses calm dark tiles.
  - **Search page** before typing: Ask Scout (opens voice), Scout ideas by time of day (`askIdeas()`), recent, try.
  - Back (`closeTopOverlay`): sheet → map popup → chip list → lower the drawer. Scout's tour, targets (`SC_T`) and
    offline answers (`SC_FAQ`) point at the V3 places; `scout_knowledge.md` describes the V3 screen.
- **Story viewer** (`#storyView`, `renderReel()`): TikTok-style vertical scroll-snap feed of every story; the one ≥60%
  in view plays (IntersectionObserver), 🔇/🔊 for all, single tap pauses a video, double-tap = ❤️ (`/api/story/like`;
  the app only gets counts + your own like; demo stories' likes stay on the phone), right rail: like, reply (DM,
  friends only), share (native share / copy), 📍 map, ⋯ report. Keep `#storyView`, `.media` and the tag buttons:
  e2e relies on them.
- **Plans** (`openPlans()`; You → My plans, Explore's "📅 My plans"): saved itineraries (`/api/plans`, `d['plans'][h]`, only
  yours, max 20) as timelines with walking times, per-stop Directions, Map (dashed route), Calendar (.ics with one
  event per stop), Share; plus the events you're going to. "Plan my night / Saturday / outdoors / dinner and drinks"
  asks Scout: questions matching `PLAN_RE` use the smart model, get a spread of nearby food / bars / clubs, and may
  return `plan` (title, day, 2-6 stops); `scout_plan()` keeps only stops whose `ref` is an event, flare or place id
  Scout was sent. The plan shows as a card in Scout's chat with 💾 Save. The ‹ back button Back closes the top sheet first, then returns to the previous screen; it's wired to
  browser history (Android back works) and a swipe in from the left edge (left to Safari itself in
  non-installed iPhone Safari, which already does that).
- **Search sheet** (V2; in V3 only `openSearchSheet()`, the drawer's search box replaced it): "What are you looking to do?", tiles by section (Sports, Entertainment, Going out,
  Outdoors & more) with live counts, a Tonight/Weekend/Week switch, free-text search, plus
  **Food & drink** (late-night eats, early morning, bars, clubs, coffee, tacos, BBQ, pizza, burgers,
  Asian, sweets, food trucks) with an **Open now** switch, and **Hot spots** tiles with live "open now" counts.
  Results list: nearest first with open spots on top, status ("Open till 2 AM", "Opens at 7 AM",
  "Hours unknown"), menu/website links when OpenStreetMap has them, and a "may be out of date" note.
- **Feed**: ranked list of real events, flares, group posts, people and groups, with reasons
  ("You're into comedy · 2 friends going"). Customizable (content types, categories, sort, distance).
  "Map it" sends the list to the map. Sorted "For you" (default), the top shows "Tonight's picks for
  you" (`renderPicks()` → `#fyStrip`: Claude's `/api/picks` when signed in, else `rulePicks()`);
  Home's "Picks for you" opens it. (The old separate For you screen and "Ask the engine" box are gone;
  Scout answers questions.)
- **Map layers**: `MAP_CATS` (events, night, zones, outdoors, friends, food, sights) are the Layers sheet's groups; in V3
  the chips under the search box are `EX_CHIPS` (one category at a time, see V3 layout). The layers button (right side) opens the Layers sheet: quick picks
  (`MAP_PRESETS`: Night out, Outdoors day, Friends, Everything, Clear), each category with its own switches
  (`S.mapL`: events · clubs, bars, zones · parks, water, trails, spots · posts, live, stories · food, openonly), event
  time window (`S.mapWhen`) and types (folded), and the color key. The arrow recenters on you (V2's 🔍 map search,
  `openMapSearch()`, is replaced by the drawer's search box). `mapHint()` shows a short pill after a change when a layer has nothing in
  view ("Zoom in to see bars", "No events in view tonight · This week →"). Live streams sit in a "LIVE 3 streaming"
  pill that opens into the strip (`S.liveOpen`). Map attributes use `data-mlcat` / `data-ml` (Meet's filter already
  uses `data-mcat`). `mapFilter` is now only 'feed' (after Map it, with a ✕ chip) or 'all'. **Nightlife**:
  OpenStreetMap clubs + Google's (`/api/places/nightclubs`: searchNearby, includedPrimaryTypes night_club, basic
  fields, ~2 km cells, `SQ_GOOGLE_NIGHT_DAILY` 100/day, strip clubs dropped, nothing stored), overlapping clubs merge
  into a numbered bubble (tap = zoom in); bars only at zoom ≥16. Food dots skip bars/clubs and show closed/unknown
  spots only at zoom ≥15; hot-spot names only at zoom ≥15. **Outdoors** (🌲): park / greenbelt / preserve outlines
  in green and lake / river outlines in blue (real shapes, simplified), drawn in a pane under everything, with activity
  tags (hiking, nature, fishing, paddleboard, kayak, canoe), real rivers as blue lines (creeks only with a launch
  or rental), named hike & bike trails as dashed lines (yellow = bikes allowed, orange = foot), and, from zoom 13, rentals 🛶, ramps / put-ins ⚓, fishing
  spots 🎣 and trailheads 🥾. Data: `fetch_outdoors.rb` (OpenStreetMap, Round Rock to San Marcos) → `data/outdoors.json`,
  served by `/api/outdoors` (`SQ_OUTDOORS_FILE` for tests).
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
  goals, interests, new to Austin, from my groups, online now). Tabs: Swipe · Friends (requests,
  friends with 💬 Message, "people you'd probably click with" + 🧠 Ask Claude via `/api/match`;
  `friendsHtml()`) · Chats (friends-only messages) · Groups. The old People / Party screen
  (party slots, party chat, invites) was retired: it only ever worked with demo people.
- **Create & share**: Photo or video story (24h; videos ≤60 s / 60 MB upload raw to `/api/media`, then the
  story points at them; served from `/story-vid/` with byte ranges, which iPhone Safari needs; a frame grabbed
  on the phone is the cover), tagged with "Where was this?" (places from your history, then nearby food &
  drink and venues; shown at that venue or fuzzed), an event, groups, people. Flare ("who's down?" now),
  Event (date/time), Group, Go live.
- **Live**: stream from the phone camera (front/back, flip mid-stream), USB webcam mode, Bluetooth
  pairing for GoPro/Insta360/DJI, Wi-Fi/RTMP instructions. Viewers send requests (visit a place / do
  a task, with play-money tips); Claude screens every request for safety. Video goes through
  **LiveKit** when `SQ_LIVEKIT_URL/_KEY/_SECRET` are set (local: `~/.sidequest-livekit.env`): the server
  mints 10-min tokens (`livekit_token()`, `/api/live/token`), streamers publish only to `live-<handle>`,
  blocked viewers are refused; `vendor/livekit-client.js` (2.22.0) loads only on Live. Unset or failing =
  the old phone-to-phone WebRTC over `/api/relay`. Stream announcements/requests always use the relay.
  The server stamps announcements with the real handle and room, lets only the owner announce/end, holds
  back the venue until the location delay (default 5 min) passes, hides streams across blocks both ways,
  and gives viewers anonymous LiveKit ids. **Kill switch**: admin "📺 Live now" → End stream / Suspend
  deletes the LiveKit room via its server API (`livekit_stop()`, repeated until the last pass expires),
  drops viewers, stops the streamer's app and locks them out of going live for 30 min. ⋯ on the watch
  screen = Report / Block. TURN comes from LiveKit (Cloud, or `deploy/livekit.yaml` self-hosted).
  **Action cameras / OBS** (`/api/live/ingress`): with LiveKit on, the Wi-Fi (RTMP) panel gives each
  streamer one permanent LiveKit Ingress address + key (id kept as `users[h].ingress`, key shown only to
  them, "New key" rotates) publishing into `live-<h>` as `<h>~cam`; Go live lights up once the camera's
  feed arrives (no phone camera needed). **YouTube / TikTok copy-out** (`/api/live/restream`): while live,
  the streamer pastes stream keys (kept in their browser only, passed straight to LiveKit, never stored on
  the server) and LiveKit RoomComposite Egress pushes the room to those RTMP addresses (billed per minute).
  Ending the stream stops the copy-out; a moderator stop also deletes the camera key. The status reply
  uses `problem`, not `error`: `api()` treats any `error` field as a failed request.
  (V1 gaps closed in V2: requests and titles are now screened on the server, and accepted visit requests stay hidden
  during the delay.)
- **Your picture**: 📸 Take a photo (in-app camera: front camera in a round preview, shutter / retake / use,
  480 px square JPEG; no camera access → the phone's own camera via `capture="user"`) or a chosen photo (`/api/me/photo`, shrunk on the phone, served at `/avatar/<h>.jpg?v=`,
  flagged `pic_unreviewed` until photo screening has looked at it), an emoji avatar (`pic: "emoji:🦊"` via
  `/api/profile`) or your initial, on a chosen colour; `av()` draws all three everywhere.
- **Me / profile**: four tabs (`showMeSec()`, `[data-mepane]`): Profile (preview + interests),
  Personality (quiz + astrology), About you, Privacy (location, delay, data, account). Interests, a 20-question 16-type personality quiz, full astrology (birth date +
  optional time + city → Sun, Moon, Rising, Mercury–Saturn, Chinese zodiac, computed on-device),
  39 "about you" questions in 4 sections (Growing up, Life now, Friendship & values, Just for fun).
  **Every answer has its own visibility**: Matching only (default, never shown) · Friends · Everyone ·
  Only me. Activity/location history (opt-in, venue-level only), export, delete account.
- **Profiles of others**: match %, "what you have in common", Snapchat-style astrological
  compatibility card, their shared answers.
- **Safety**: report/block on everything, Claude moderation of posts/captions/group names/public
  profile text, phone/email filter, admin page (`/admin`), 18+ and Terms acceptance at sign-up,
  rate limits, invite codes in beta.
- **Scout** (round button riding on the drawer's top edge, left; also the 🎤 in the search box): an animated guide that answers how-to and "what's the move" questions,
  points at buttons (ring + label) and pulses spots on the map, talks via the browser's own speech
  (🎤 in, 🔊 out), and has a voice-only 🚗 driving mode (auto-on at ~16 mph). Each user can design its
  look and name (🎨 builder, a description Claude maps to parts, or their photo, kept on-device only).
  Guests get a built-in FAQ (incl. food, bars, coffee, open now); signed-in users get Claude.
  **Do it for me**: Scout actions `search`, `food`, `rsvp` (confirm card), `flare` (draft in the compose
  sheet), `chat` (opens a friend's thread with a draft), `directions` (card with rough distance/time/
  leave-by + Apple/Google Maps links; one big button in driving mode). `scout_actions()` in server.rb
  only lets through actions on what the user was sent (their events/flares, friend handles, places);
  `ruby test_api.rb` covers it. Nothing posts or sends without a tap. General questions get a brief
  general-knowledge answer; no live weather/traffic.
  A 7-step **tour** of Home (`SC_TOUR`, `scoutTour()`) is offered once after the welcome sheet or
  sign-up, and any time from the panel's "Take the tour" chip or "give me a tour" (no Claude call).
  Food & drink questions: the server picks ~15 matching places (`scout_places()` in server.rb,
  widening zone → nearby → closed-with-opening-time and telling Scout what it did), and Scout may
  light one up with a `place` action, allowed only for ids it was sent; it never invents menus.
  Scout also answers general questions from Claude's own knowledge (Austin history, how-tos, outdoors tips),
  and when someone asks about a place by name ("is Franklin open?"), `scout_google()` looks it up live on Google
  (rating, price, open now, today's hours; nothing stored; counts against `SQ_GOOGLE_DAILY`) and passes it as
  "Google info". **Voice**: `/api/scout/voice` speaks with Google Text-to-Speech Chirp 3 HD voices (Puck default;
  Aoede, Kore, Charon in the 🎨 builder) using `SQ_GOOGLE_TTS_KEY`, a server key; cached, capped by
  `SQ_TTS_DAILY_CHARS`; falls back to the browser's voice. The first tap anywhere unlocks audio on phones. Personality: `mockup/scout_personality.md`;
  app knowledge: `mockup/scout_knowledge.md` (keep it current; never served). Spec: `SCOUT_PROMPT.md`.
- **Scout is voice-first**: tapping Scout (or its bubble) opens the panel and starts listening; a big 🎤 is the main
  control, "⌨️ Type instead" shows the text box. Scout only talks when talked to: spoken questions get spoken answers,
  typed ones stay quiet unless 🔊 (`S.scout.voice`) is on; driving mode that switches itself on shows a toast instead
  of speaking. Scout calls run at low effort (`run_claude(..., effort: 'low')` → CLI `--effort low` / API `output_config.effort`): Haiku
  5.5 otherwise thinks ~500 tokens first; this saves 1-2 s. The CLI itself adds ~1.5 s per call; the API engine is faster.
  Long answers are spoken ~200 characters at a time (first words in ~1 s) and never fall back to the
  browser's robot voice while Google's voice exists; 10 Chirp 3 HD voices (`SCOUT_VOICES`) in the 🎨 builder. When you're idle on
  Home or the map it waves 👋 with a bubble ("Need help? Talk to me!"); at most 3 a visit, 3 min apart, never while
  driving or with a sheet open; two ✕ in a day silences it till tomorrow (`scoutNudge()`).
- **Español**: You → 🌐 Español (or the welcome sheet). `T('English', {n})` + the `ES` table translate the
  visible app (header, name menu, Home, map chips / Layers / hints / search, stories viewer, plans, Scout panel);
  static labels use `data-t` / `data-tp` and `applyLang()`. Scout listens (`es-US`), answers in Spanish (server
  prompt) and speaks with the es-US Chirp 3 HD voices. Still English: Search, Meet, Me/profile questions,
  onboarding text, Create sheets, toasts, the guests' built-in FAQ (Spanish guests get a "make an account" reply).
- **Sights & history** (🏛️ Sights chip; Layers: landmarks & museums / historical markers / statues, murals & views;
  "🏛️ Sightseeing" preset): `fetch_sights.rb` → `data/sights.json` (~1,650): all 666 Texas Historical Commission markers
  from Round Rock to San Marcos with their full plaque text (THC Atlas GIS download + one Atlas page per marker, cached in
  `data/sights_cache/`), National Register places, Wikipedia articles about places (intro + photo, CC BY-SA, geosearch
  grid), OpenStreetMap museums / viewpoints / monuments / art; duplicates merged by name within 250 m. `sights.rb` loads
  it; `/api/sights` = dots, `/api/sight?id=` = the story. Landmarks show from zoom 12 (big ones) / 14, markers from 15,
  art from 14. Popup: photo, story (More), marker location, 🔊 Tell me the story (asks Scout, spoken), Read more,
  Directions, credit line. Scout: history / sightseeing questions (`SIGHT_Q`) get matching sights (`Sights.search`,
  aliases like ACL, Muny, capitol, bat bridge) with their real text, a `sight` action, and sights can be plan stops.
  `--merge` rebuilds from the cache; `SQ_SIGHTS_FILE` for tests (`test_sights.json`).
- **Gestures**: swipe in from the left edge = back, from the right edge = forward (`NAVFWD`, only after going back),
  pull any sheet down to close it (`.sheet-bg>.sheet`, from its top or once scrolled to the top; grab handle drawn by
  CSS), flick the name menu to close it. iPhone Safari outside the home-screen app keeps its own edge swipes.
- **Real photos in lists**: rows on screen ask `/api/place/thumb` for one 240-px Google photo of the business /
  venue / park (by our place id, Google id, or name near a spot; `loose=1` for city-level events) via `data-thumb`
  + an IntersectionObserver (`watchThumbs()`); max 40 a visit, then the server's daily caps; the emoji stays when
  there's none. Food & drink / hot spot / eat-after rows, feed event cards, plan stops, map search; park, lake and
  trail popups get 3 photos (`areaPhotos()`).
- **Hot spots** have their own chip (🔥) and glow by live activity (`zoneActivity()`: open places + events now or
  within 2 h ×3 + live streams / flares ×4): busy zones pulse brighter, quiet ones fade to a dashed outline with 💤;
  refreshed every 5 minutes while the map is open.
- **Photos on places and events**: Side Quest story photos/videos posted there come first (`storiesAt()`, tap →
  story feed), then Google's (credited): place popups get 3 with the Google details (`photos` field), event popups
  look up the venue by name within ~550 m (`/api/place/photos`). Photo URLs aren't stored (Google's terms);
  `SQ_GOOGLE_PHOTOS_DAILY` (300) caps them. Some event venues are geocoded wrong by the events scraper (e.g. Cap City
  Comedy Club placed downtown, really at the Domain), so they get no photos.
- **Installable** as a home-screen app (PWA manifest + icons). Logo: the SQ mark (`mockup/logo.png` in the
  header, `icon-512/192/180.png`), cut from the tile in `~/Downloads/Side Quest Compass Logo.png` (1254 px; cream SQ + compass)
  and padded square on `#070b18`; ≤370px wide the header shows the mark without the name.

## V2 (this folder: `~/claude/sidequest-v2`, git branch `v2`; V1 lives untouched in `~/claude/sidequest`)

Brief: `V2_PROMPT.md`. Report: `V2_REPORT.md`. Server side in `mockup/v2.rb` (+ `mockup/webpush.rb`), mounted by
server.rb (`mount_v2`, `v2_background`); client in one block in index.html ("Side Quest V2"). New data keys in app.json
only (`notifs`, `quest`, `saves`, `ev_chat`, `push`, `reminded`, `recap`); analytics in `data/stats.json`; the VAPID key
in `data/vapid.json` (secret, 0600, git-ignored; back it up with the data or every phone must re-subscribe).

- **🔔 Notifications** (`notify!` in v2.rb; header bell `#bellBtn`, inbox `#notifBg`): waves, new friends, friends going
  to the same event, event / group chat replies, downs on your flare, group joins, story tags and likes, quest wins,
  2-hour event reminders (`remind_due!`, every 5 min), a Monday recap (`weekly_recap!`). Never across blocks; same
  thing within an hour folds into one; max 120 each. Unread count rides on `/api/state` (`SV.v2.unread`). Kinds can be
  muted per person (`users[h].mute`, "What to tell me about" in the inbox).
- **Phone push**: real Web Push (`webpush.rb`: RFC 8291 aes128gcm + RFC 8292 VAPID with Ruby's OpenSSL; macOS's
  LibreSSL can't do AES-GCM through Ruby, so there's a hand-written GCM that `test_webpush.rb` checks against the RFC's
  example byte for byte). The inbox's "Phone notifications" switch subscribes (`/api/push`, max 5 devices, endpoints
  must be a real push service: no SSRF); `notify!` queues `PUSH_Q`, a thread delivers, 404/410 drops the device.
  `sw.js` shows it and opens the right screen (`/?ev=`, `/?g=`, `/?inbox=1`, `/?quests=1`). iPhone needs the app on
  the Home Screen (iOS 16.4+). `SQ_PUSH_CONTACT` = the VAPID contact (mailto).
- **Service worker** (`sw.js`, registered on https/localhost, not under automation): app shell offline, static files
  cache-first, never caches `/api`, stories, avatars or config. Bump `CACHE` when the shell list changes.
- **Event details** (`openEvent(id)`, `#evBg`): hero photo, when/where/price, Going / Interested / 🔖 Save / 💌 Invite
  (`/api/event/invite`: DMs friends a link) / 🔗 Share (`/e/<uid>`), Calendar, Directions, Map, Eat after, Tickets,
  description, who's going (friends first), More like this, check-in while it's on, and a discussion
  (`/api/event/chat`, moderated, ⋯ to report/block). Opened from feed cards (`data-evopen`), map pins (Details), Home,
  notifications and links.
- **Quests** (`QUESTS` in v2.rb, `openQuests()`, `#questBg`): 12 quests, XP, levels (`level_of`), weekly streak, badges,
  friends-only leaderboard (`/api/quests`, opt out with `lb_hidden`). Check-ins (`/api/checkin` k = sight / place /
  area / event): the phone checks it's within 150 m (+ accuracy); the server only gets the id, looks the place up
  itself, counts it once per place per day, events only while on; max 40 a day. Friends see level + badges
  (`SV.badges`); your own card on Me → Profile (`#myQuest`).
- **Saved** (`/api/saves`, 🔖 on events / places / sights; My plans → Saved).
- **Quest of the week** (`featured_quest`, rotates weekly through the check-in quests, 1.5x XP). **Friends out now**:
  friends who switched on "Show friends where I check in" (`users[h].share_checkins`, off by default) appear on Home for
  3 hours after a check-in, place name only (`friends_out`).
- **Scout** V2 actions: `event` (open an event's page), `open` (quests / inbox / plans / saved / invite).
- **Scout knows your taste** (v2.rb `remember_taste!` / `taste_for` / `taste_events`): going / interested, saves and
  check-ins are kept in `d['taste'][h]` (name, type, venue, food; 120 max; un-RSVP / unsave removes; seeded once from
  existing RSVPs, saves and check-ins). Every Scout question gets a weighted summary (event types, venues, food,
  sights, recent; older fades by half every 2 months); recommendation / plan questions also get the coming week's
  events that fit it (marked `fits`, merged into the allowed events). Deleted with the account.
- **Scout settings** (🎨 Design your assistant): a Voice box with read-every-answer on/off (`S.scout.voice`, on by
  default since `voiceV4`), male / female Chirp voices with a spoken sample, speed (`S.scout.rate`: audio playbackRate).
  The mic is a toggle (tap on, talk through pauses, tap off to send; `scoutMicOff`); any way of closing Scout cancels it.
- **Scout's ears**: browser SpeechRecognition (one phrase per session, chained) where it works; on iPhones, or when it
  shows no life in 4 s (`S.micRec`), `listenRec` records (MediaRecorder) and `/api/scout/hear` transcribes with
  whisper.cpp + ffmpeg on the server (`hear`, model `/opt/sidequest/whisper/ggml-base-q5_1.bin`, `-ac` sized to the
  clip, one at a time, partials every 2.5 s). On/off tones (`micBeep`); stats `mic_*` show outcomes per day. The mic
  must start inside the tap (iOS); a mic "denied" with no prompt is the phone's per-app or per-site setting.
- **Live Translate** (`lens.js` + `lens.rb` + `lens.html` at `/lens`): self-contained camera translator, also usable
  by other apps (`Lens.open({to, from, translate})`). tesseract.js 6.0.1 (vendor/tesseract) reads text on the phone,
  language data from jsDelivr; `/api/translate` translates paragraphs with haiku, cached per line. Opened from the
  big Live Translate button under Scout's mic or by asking Scout to "translate this menu/sign". 13 languages.
  Translations are pinned to the words AR-style: every camera frame (WebCodecs `VideoFrame` luma, canvas fallback)
  goes through a small tracker in lens.js (Shi-Tomasi corners, pyramidal Lucas-Kanade, coarse whole-frame shift,
  RANSAC similarity → `st.pose`, world → frame), and each read is placed through the pose of the frame it read.
  Items are LINES (tesseract groups lines into paragraphs differently each read); a paragraph is translated as one
  text and its lines handed back one per line (`solo` fallback when the counts differ). Reads cycle `PLAN` (960 px,
  1440 px, and ±8° turned ones that only count for tilted text); tesseract must run PSM 3 (its default 6 reads walls
  as text). Overlay colours are the sign's own (Otsu split, medians). **✨ Detect** (`from:'auto'`, the default): one
  ~768 px JPEG to `/api/lens/lang` (haiku vision, ~1 s, $0.0004; 120/hour) names the language, then the reader switches
  to it (`st.det`, `rlang()`; the English reader runs meanwhile and Latin-script lines are kept). Asked when the camera
  settles, again only after 6 s without text (backing off to once a minute). **🖼 Photo** (top right): a picture from the
  phone shown whole (`st.photo`, `.lz-still`, contain instead of cover), read once at 2200 px, up to 90 lines (live: 30);
  works with the camera blocked. Cached translations match a slightly different reading only when its numbers are the
  same (`same()`): before, menu lines that differed only in price borrowed each other's translations. Moving-camera test kit (fake camera with frame
  numbers + per-line ground truth, gen.py/track_live.py/flow.py; photo.py for Detect + photos) is in `mockup/lens_test/`
  (its out/ isn't committed).
- **What is this?** (lens.js Identify mode + `identify.rb`): the camera's second mode (switch above the shutter; Scout's
  orange "🔍 What is this?" button, or asking Scout "what is this building"). The shutter sends one ~1024 px JPEG
  with GPS + compass heading to `/api/lens/identify`; sonnet (`SQ_LOOK_MODEL`, effort low, ~5-7 s) sees the photo
  with our places within 300 m and sights within 1.2 km (distance + ahead/left/right/behind) and names a candidate
  only when the photo shows it. The card links to the place (menu, hours/phone/photos popup) or the sight's story,
  plus web search and Google Maps. Photo never stored. Images reach Claude via `run_claude(images:)` (CLI:
  stream-json input; API: image blocks). 30/hour per person.
- **Menus** (`menus.rb`, `/api/place/menu?id=`): 🍽️ Menu on every food & drink row, popup, Identify card and event
  venue that is one of our places → a big readable sheet (sections as chips, dish search, prices, where it came from).
  Lookup: the place's own pages first (OSM menu link, website, Google's websiteUri; follows menu links, JSON-LD,
  PDFs when `pdftotext` exists) read by haiku; then the website's menu pictures (`menu_photos`, one per read, haiku);
  15+ items, half priced = done; else haiku with WebSearch/WebFetch
  (`run_claude(web: true)`) tries online ordering, menu sites and delivery apps and notes caveats. Signed-in only
  (it's Claude); runs in a thread while the app polls; 2 at a time, 15/hour per person, 150/day; kept in
  `data/menus/<id>.json` 14 days (misses 2 days). `menu_get` refuses private addresses. Pictures + web results merge
  (`menu_merge`: pictures first, the web adds missing items). Images reach Claude as JPEG or PNG.
  **Speed**: pages fetched in parallel (`menu_pages`), lines repeated across pages dropped (`menu_dedupe`), text read
  in ~2,000-char parts in parallel (`menu_parts` → `menu_join`, about 10 parts at most), all menu calls at effort low
  through `menu_slot` (`SQ_MENU_PAR` 5 at once; each CLI is ~110 MB). Menu answers are plain lines (`MENU_LINES`:
  `## Section` / `name | price | desc` / `SOURCE:` / `NOTE:`, parsed by `menu_lines`; `run_claude(..., nil)` = plain
  text): a third of the tokens and one turn instead of structured output's two, 2-3x faster; website menu pictures one per read with haiku, Google photos 3 per read with sonnet, only
  if the website's weren't enough; the web search starts alongside the pictures. Each finished part is shown at once
  (`MENU_JOBS[:partial]` → `pending` + `menu`; the app polls every 1 s and shows "Reading the rest of the menu…").
  Opening a place popup warms its menu (`warm=1`, 40/hour). Expired menus are still shown while a new read runs.
  **Menu sheet**: sticky top with 📍 Google Maps (the place itself: `query_place_id` when `d['gplace']` has it, else
  name + address; its photos include the menu, so no Google photos are fetched or read), Website, 📞 Call (from the
  answer's `info`), dish search (debounced, item count), section chips that follow the scroll (IntersectionObserver).
  The website's menu pictures are saved with the menu (`pics`, up to 4) and shown above it, shrunk by `/img/menu?id=&i=`
  (only ever a saved one). Sections use `content-visibility:auto` (so tests read `textContent`, not `innerText`).
  **Warm-up** (`menu_prewarm`, on with SQ_BETA or `SQ_MENU_PREWARM=1`): one place at a time, best-known first, only
  while no one is waiting, website only (no Google, no web search), `SQ_MENU_PREWARM_DAILY` 300; places with no menu on
  their site go in `data/menus/_tried.json` for 14 days.
- **❤️ Favorites** (were "Saved", same `/api/saves`, `d['saves']`): 🤍/❤️ `favBtn(k,id,name)` on events (sheet), places
  (list rows, popups, markets), sights and every dish on a menu (`k: dish`, id `<place id>.<8 hex of the dish name>`
  from `dishId()`, name `dish · place`; a dish counts as liking its place for Scout's taste). Listed on Me → Profile
  (`#favCard`, `renderFavs()`, filter chips by kind; a dish opens its menu with the search on it: `openMenu(id, name,
  retry, dish)`). My plans has a "❤️ My favorites" button there. Private (only you). Max 300.
- **🍻 Happy hours** (`menu_finds.rb`): every menu read asks for a `HAPPY:` line (OpenStreetMap opening_hours + deals,
  kept only if `Hours.parse` reads it: `happy_clean`); old menus got a one-off look at their happy-hour sections at
  start (`happy_backfill`, `happy_checked`). `MenuIndex` keeps an index of data/menus (re-reads changed files, 30 s).
  `/api/places/happy` → on now first; Search → Food & drink "🍻 Happy hour" tile (`openHappy()`), Home quick button
  while any are on (`HH`, refreshed every 10 min), a banner on the menu sheet (`hhWhen()` formats the hours).
- **🍴 Find a dish**: `/api/dishes?q=` (`MenuIndex.dishes`: all words in name/desc/section, "under $X", "open";
  2 per place; own name, open now, near first). Search → Food & drink box (`#dishQ`, `openDishes()`); Menu opens the
  place's menu at the dish. Scout: "happy hour" questions (`HAPPY_Q`) and "where can I get…" (`DISH_Q`) get these.
- **🌆 Tonight picks** (`tonight_push!` in v2.rb, 5:00-5:15 PM, once a day): up to 3 of tonight's events fitting each
  person's taste (types, venues, friends going ×3); notification kind `tonight` (mutable), push opens `/?tonight=1`.
  `ruby test_tonight.rb` (6).
- **📍 Add location** (`spots.rb`, `/api/spots`; like Instagram's): one picker (`openPlacePicker(cur, cb)`, sheet
  `#ppBg`) for stories, flares, live and "visit a place" requests, replacing the old dropdowns (flares and live used
  the 8 demo `VENUES`; stories only food & drink). Lists: 📷 where the photo was taken (JPEG EXIF GPS, `photoGps`),
  🎉 events on now within 2 km, 🕘 recent picks (`S.recentSpots`) and history, 📍 near you (fresh GPS fix on open,
  `freshFix()`; your neighborhood first). Search covers food & drink, sights, parks/lakes/trails, markets and
  neighborhoods (~4,700); "Search everywhere" = OpenStreetMap Nominatim (tap only, 1/s, cached); "➕ Add …" = your own
  name at your spot (±100 m). Composers show it as `locFieldHtml(f)` with one-tap suggestion chips (`LOCF` per field).
  A picked place travels as `v: {name, lat, lng, id, e, kind}` (flares, live) or story `place/lat/lng`; `venue(x)`
  takes an id or that object; the server cleans it (`spot_ref`) and moderates a typed name with the text. Phones send
  ~100 m positions here. `ruby test_spots.rb` (15).
- **💬 Chats, Messenger-style** (`chats.rb`, replaces the old 3 DM routes; client block "messages, Messenger-style"):
  1:1 with friends (`d['dms']["a|b"]`, as before) and group chats (`d['chats'][id]`, thread `c:<id>`, you + 2-30 friends,
  rename / add / leave, system lines `sys`). Tap a bubble → react (6 emoji, one per person, `rx`), reply (`re` quote),
  copy, unsend (`gone`, files deleted). 📷 photos (JPEG ≤600 KB → `data/dm/i….jpg`, `/dm-img/`), 🎤 voice notes
  (MediaRecorder → `/api/dm/voice` raw → `aud` id claimed once by its uploader; `/dm-aud/` serves ranges for iPhone),
  cards (`card {k: event|place|story|flare}`) from 💬 Send on event sheets, place pages and stories (`sendToChat`).
  Seen = `d['dm_read'][h][thread]` (POST `/api/dm/read`); typing is memory-only (`DM_TYPING`, 6 s). Thread poll 3 s
  redraws only `#thread` (`renderThreadMsgs`). Notification kind `dm` (mutable), push → `/?dm=<thread>`.
  Media files need a signed-in cookie. Tests in test_v2.rb ("chat: …", 9).
- **🏘️ Group pages, Facebook-Groups-style** (`groups.rb`; client "A group's page"): cover photo, 🌐/🔒, Join / Ask to
  join / Requested, Invite (a `group` card into chats), rules, tabs Posts · Events · Chat · Members · ⚙️ Manage.
  Wall `d['gposts'][gid]`: text + photo (`/group-img/`, private groups' photos to members only), 📊 polls (2-6, one
  vote each unless `multi`), 📅 events (time, place via the location picker `LOCF.gp`, going list), 👍 likes,
  comments, 📌 pinned first. `/api/group/feed|post|act|admin`. Roles: owner + `g['admins']` pin/remove/approve/kick
  and edit (about, rules, privacy, cover); only the owner picks admins. Private (`g['priv']`): join → `d['greqs']`,
  outsiders see name/count/friends in it only (state hides members, `mcount`; private groups' flares stay inside).
  Notification kind `group`. Report kind `gpost`. Tests in test_v2.rb (6); demo groups keep the simple page.
- **🧑‍🤝‍🧑 Friends on the map, Snap-Map-style** (`friendmap.rb`; client "friends on the map"): 👻 button on the map →
  share sheet: Ghost (default) / All friends / Only… (picked friends), Exact or ~500 m squares (default), pause 1/3/8 h.
  Phones POST `/api/loc` at most ~1/min while open (`sendMyLoc`, from `setMyPos` + a 30 s timer); positions are in
  memory only (`FMAP`, gone after 8 h or a restart), never in app.json. `/api/loc/friends` → friends sharing with you
  (faces `.fpin`, layer `friendlocs`; tap → Chat / Profile / Go). Story heat: layer `heat`, ≥2 stories in ~1 km →
  a glow you tap to watch them. Tests in test_v2.rb ("friend map", 3).
- **📸 Stories, Instagram/TikTok parts** (`stories_plus.rb`; client "story editor"): ✏️ Text & stickers on a photo
  (`#stEditor`: Aa text with colors / background, emoji, 📍 place, 🕐 time; drag, ➕➖, 🗑; Done draws them into the
  JPEG, `SC.imgOrig` + `SC.layers` kept for re-editing). 📊 poll sticker (`st.poll`, 2 choices, `/api/story/vote`,
  counts + your vote in state; who voted only to the author). 👁 viewers: phones batch `/api/story/seen`; author's
  👁 N on the rail → `/api/story/viewers` (likes, votes). 💚 Close friends: `vis: 'close'`, list `/api/close`
  (`SV.me.close`), green ring. ▶ Watch (V2: "For you") in the story rail: everyone's stories ranked (`forYouStories`). Photos show
  whole over a blurred copy (`.media.photo`). 💬 Reply opens the chat with the story attached (`DM.stCard`, shown in
  `#dmReBar`); the first message carries it as a `story` card with the photo. Tests in test_v2.rb (2).
- **🗳️ Plans with friends** (`mount_plans` in chats.rb; client "plans with friends"): 📅 Make plans (Chats), 🗳️ Plan it
  (event sheet), Plan with friends (place page) → sheet: title, 1-6 options (event / place via picker / idea), up to 4
  times, friends → `/api/hangout/new` makes a group chat (`c['plan']`) with the vote pinned on top (`#planCard`).
  `/api/hangout/act`: vote (options and times, as many as work), add, lock (organizer: top pick), unlock, going.
  Locked → "It's on" + chat line + notification, 📅 .ics download (`planIcs`), Google Calendar link, directions.
  `plan_remind!` (every 5 min, with event reminders): ⏰ `remind` to the going list 2 h before (`pl['reminded']`,
  cleared on re-lock), and a nudge to the organizer when a vote with ≥2 voters has sat open a day (`pl['nudged']`).
  Tests in test_v2.rb ("plans", 2). (Separate from `/api/plans`, which are your own saved itineraries.)
- **📝 Public posts** (`wall.rb`; client "public posts"): Feed has ✨ For you | 📝 Posts (`#feedMode`). A post = text and/or
  photo (`/wall-img/`, friends-only photos to friends only) + optional place (`LOCF.wp`), 🌐 everyone / 👥 friends; likes,
  comments, delete, 🚀 boost (40 🪙, first near it for 6 h). `/api/wall?scope=all|friends|near|user` ranks on the server;
  the best 6 are woven into For you; profiles show a posts grid; 💬 Send as a `post` card; report kind `wall`.
- **🪙 Rewards** (`rewards.rb`): coins kept on the server (`d['quest'][h]['coins']`), earned for check-ins, posts, stories,
  flares, locked-in plans (daily caps `COIN_CAP`), quests (half their XP), invites (+25), daily streak (`days`, +2/day per
  day in a row, up to +20). All XP goes through `xp_add!` (weekly totals `wk`). Weekly Austin challenge (`WEEKLY`, rotates
  by ISO week, +coins +100 XP). Spend: profile frames (`FRAMES`, buy once, wear any: `.av.fr-*`), boosts, live tips
  (`/api/coins/tip` hold → pay / refund; unclaimed back after 2 days). Quests sheet: rewards card + leaderboard tabs
  (`/api/leaderboard?scope=friends|week|all`, Friends first if you have friends; `lb_hidden` opts out of all).
- **🛡️ Photo screening** (`photocheck.rb`): every public photo (wall posts, stories, group posts, profile pictures; video
  stories as 3 ffmpeg frames) is queued (`photo_check!`, `PHOTO_Q`, one worker, 200 max) right after it's saved and shown
  to `SCREEN_MODEL` with `PHOTO_SYSTEM`. Block → taken down (file deleted), owner gets a `mod` notification with the
  reason, logged in `d['photo_blocks']` (admin "Photos taken down automatically"). Pass → off the review list, unless
  its text already failed (`text_ok`). Claude unreachable or the queue full → stays `unreviewed` for a person. On with
  moderation (`SQ_PHOTO_SCREEN=0|1` overrides). Chat photos aren't screened. Admin "Needs a human look" also lists
  public posts, group posts and profile pictures (kinds `wall`, `gpost`, `pic`). Tests in test_v2.rb ("photos", 2;
  the fake Claude blocks images containing BADPHOTO).
- **📍 Place pages** (`openSpot(x)`, `#spotBg`): tap 📍 on a story or a flare card → stories there (24 h, grid),
  flares, live, coming-up events (by name or within ~150 m), Directions, Map, Menu (food & drink), Post / Flare here.
- **Business info**: Google details now also give phone (📞 Call) and address (same Enterprise call, no extra
  charge), 4 photos; event sheets have "🏢 Venue phone & hours" (Google by venue name, on tap). OSM `phone` is
  fetched by fetch_places.rb from the next refresh.
- **Meet search** (`#meetQ`, `meetQ`, `qHit`): one box under Meet's tabs that narrows the open tab: Swipe cards,
  Friends (your friends + "People": everyone matching name, hometown, interests, goals, with + Add), Chats, Groups.
  Cleared on tab switch.
- **Group chat** for members of real groups (`/api/group/chat`, stored as `ev_chat["g:<id>"]`).
- **Growth**: share pages with Open Graph previews `/e/<uid>`, `/s/<sight id>`, `/i/<handle>` (invite; sign-up offers
  "be friends with @them", `users[h].ref`, Bring a friend quest); Home "Tonight near you" strip + "Up next" countdown;
  welcome nudge to quests after sign-up.
- **Analytics** (`track(name)` → `/api/t`, `TRACK_EVENTS` whitelist; `active!` per account per day): admin
  "📈 Growth" panel (`/api/admin/growth`: DAU, WAU, 7-day retention, sign-ups, RSVPs, check-ins, quests, top taps).
  No content, locations or device ids.
- **Live safety on the server**: `/api/screen` signs a 10-minute pass for the exact request text; the relay refuses
  requests without one (when moderation is on) and applies the hard rules itself (`LIVE_HARD_NO`); stream titles show
  only after a check (`live_title`); accepted visit requests hide the place while the location delay is on.
- **Map decluttering** (2026-10-20, after the V2 night): Google-Maps-style. `rank_popular.rb` → `data/popular.json`
  (0-100 per place / sight: Wikipedia readers over 12 months, a hand list of Austin institutions, listing
  completeness; chains and news-story "sights" pushed down), served as the last element of `/api/places/map` and
  `/api/sights` rows (`popular.rb`; unranked counts as 40 on the client). Client: `spaced(items, px, layerKey)` keeps
  the best-known first and skips anything within px of a kept pin, seeded with the pins of more important layers
  (`DC_ORDER`: markets, events, night, sights, food, outdoors); events folded away show `+n` on the one kept.
  Names go through one placer (`setLabels(key, pins, names)` → `placeLabels`): best first, never overlapping, never on
  other pins (food dots excepted), about one per 9,000 px², with a `short` fallback. `over` names (hot spots, today's
  markets) may sit on ordinary pins but never on people's (flares, stories, live). One `moveend` handler
  (`redrawMapLayers`) redraws the layers in priority order. The old permanent tooltips (`sglabel`, `odlabel`,
  `hotlabel` as tooltips) are gone; hot spot names keep the `hotlabel` class.
- **No kids' activities** (`event_filter.rb`, `EventFilter.clean` runs before `Geofix.fix_body` on every events load):
  storytimes, toddler / homeschool / kids' classes, trunk-or-treats and the like are dropped (kids words in the title
  or the first 160 characters of the description; "family" category only with "Family" in the title). Grown-up
  events that only sound like it stay ("Cry Baby Tour", "Faith & Family Night", "teen slasher script").
- **Event spots** (`geofix.rb`): events the scraper couldn't place (all dropped on downtown) get their spot from the
  venue / a park named in the title (our parks, sights, places; chains by exact name only), then OpenStreetMap's
  geocoder (1/s, answers must match house number + street or share a real word; cached in `data/geofix.json`).
  Still unknown → `geo_none`: the client drops lat/lng, so no pin, no distance, no Map button.
- **Farmers markets** (`fetch_markets.rb` → `data/markets.json`, `/api/markets`): a hand-kept list checked against
  each market's listing (Oct 2026). Today's / this weekend's markets show from zoom 9 with big glowing 🧺 pins and
  their hours (`fmSoon`); otherwise ordinary pins from zoom 13. Layer key `markets` under Food.
- **Scout and areas** (`areas.rb`, `data/areas.json` from `fetch_areas.rb`: 60 neighborhoods, main streets and nearby
  towns with a centre and radius): "a local business in Hyde Park" now gets that area's best-known places
  (`Places.best_in`: popularity first, national chains well behind, `known` score passed to Scout). Triggered by an area
  name plus a business / recommend word (`BIZ_Q`), not only food words; a named hot spot still wins. Scout is told the
  app only has food & drink, sights and parks, so for shops it says so and answers from memory, flagged as memory.
- `start_v2.sh --voice`: only Scout's Google voice (capped by SQ_TTS_DAILY_CHARS, default 30,000 a day); no Places,
  tiles or LiveKit. Without it Scout falls back to the phone's built-in voice.
- Fixed a V1 bug carried into V2: `endLive` had its `bc({t:'end'})` behind a `//`, so viewers were never told a stream
  ended (V1 still has it). `e2e_live.py` needs `SQ_DEMO=0` (demo mode pads the viewer count).
- **Speed** (2026-10-24, from a measured audit): map moves no longer freeze (one cached `Intl.DateTimeFormat` per zone
  in `tzOffsetMs`, `austinMow` worked out every 10 s, outdoors drawn on a canvas and each shape made once and only
  added / removed as it enters / leaves the view (`OD.made`, `OD.on`), food glow on its own canvas every 250 ms and
  paused while the map moves). Events are fetched as the page starts (`EV_PRE`) and the last list is kept on the phone
  (`localStorage` `sq-ev`, 12 h); `/api/events` has an ETag (304) and 2-min cache. Hidden screens aren't drawn
  (`lazyView` for feed / me / map; `tab()` runs the owed draw). The 15-s refresh skips redraws when `/api/state` and
  threads are unchanged, and pauses in background tabs. Event pictures go through `/img/ev?u=&w=480|960` (only
  pictures in the current events list, magic-byte checked, ffmpeg-resized once, kept a week in `data/img/`; without
  ffmpeg a redirect). Google strip photos are 400 px and fetched in parallel. `/api/places/map` and `/api/sights` are
  cacheable (15 min / 1 h).
- **Static files**: ETag + 304 for repeat visits, gzip for text over 1 KB (`GZ_CACHE`; Caddy also compresses in production).
- **Admin**: Growth panel, flagged event/group chat under "Needs a human look", chat reports with author + text.
- Run V2: `cd mockup && ./start_v2.sh` (http://localhost:8797, phones https://<Wi-Fi IP>:8444; `--keys` adds the paid
  Google / LiveKit keys). Same host as V1, so the browser shares the login cookie between ports.
- Tests (all against throwaway copies): `ruby test_v2.rb` (30), `ruby test_webpush.rb` (6), `e2e_v2.py` (36) on a server
  with the test files + `SQ_ADMIN_TOKEN=test`, plus every V1 suite (e2e_test 109, e2e_live 13, test_live 14,
  test_google 17, test_api, test_hours).

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
  Locations sent to the server are rounded to ~1 km. **Google Places** (`SQ_GOOGLE_PLACES_KEY`, local:
  `~/.sidequest-google.env`): tapping a place on the map adds Google's rating, price level, open now and
  week's hours (`/api/place/google`). Google's terms allow storing only place ids (`d['gplace']`: OSM id →
  Google id, '' = no match), so details are fetched per tap; the match search asks for ids only (free);
  `SQ_GOOGLE_DAILY` (300) caps paid detail lookups per day; show the "Rating, price and hours: Google" credit.
- **Other Google pieces**: Directions buttons open Google Maps (`mapsUrl()`, universal link → the app if
  installed); 📅 on events → Google Calendar's template page or an .ics for Apple/Outlook (`addToCalendar()`).
  **Map tiles**: with `SQ_GOOGLE_MAPS_BROWSER_KEY` (a browser key locked to the app's origins + tile.googleapis.com)
  both maps use Google's Map Tiles API, dark-styled (`GMAP_STYLE`), with Google's viewport copyright and logo;
  tiles must load with `crossOrigin` or Chrome's ORB blocks them; no key / errors → OpenStreetMap.
  **Sign in with Google** (`SQ_GOOGLE_CLIENT_ID`, Google Identity Services button on the sign-up sheet): the
  server checks the ID token with Google's tokeninfo (aud, iss, exp, verified email); a known `sub` signs in,
  a new one gets a 15-min HMAC ticket to pick a handle + 18+/Terms with no password (`users[h].google`,
  `d['google_ids']` sub → handle; no email stored). Google won't run the button on an IP origin, so test it on
  localhost or the real domain. Keep `Referrer-Policy: strict-origin-when-cross-origin`: with `same-origin` the
  button request carries no referrer and Google answers "origin not allowed" even when the origins are right. About 45% of places have hours; ~98% of those
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
ruby test_live.rb                      # live-video rules, camera ingest, copy-out vs a fake LiveKit (:8795)
ruby test_google.rb                    # Google Places details vs a fake Google API (own copy on :8794)
../deploy/google-places-setup.sh [login|<project>]  # gcloud: project, billing, Places API, Places-only key → ~/.sidequest-google.env,
                                       # $10 budget alert (project sidequest-512123). gcloud lives in ~/google-cloud-sdk and
                                       # needs the standalone Python in ~/.local/python-gcloud (macOS has 3.9; gcloud needs 3.10+)
SQ_PLACES_FILE=test_places.json SQ_OUTDOORS_FILE=test_outdoors.json SQ_SIGHTS_FILE=test_sights.json ruby server.rb   # e2e server (no internet needed)
ruby fetch_sights.rb                   # history markers, landmarks, Wikipedia, museums → data/sights.json (~15 min first run)
ruby fetch_outdoors.rb                 # parks, greenbelts, lakes, rivers + rentals, ramps, fishing, trailheads → data/outdoors.json
python e2e_test.py <shot-dir>          # Playwright: two brand-new users, 95 checks
SQ_BASE=http://localhost:8796 SQ_ADMIN_TOKEN=test python e2e_live.py <shot-dir>
                                       # 1 streamer + 3 viewers, report, End stream (13 checks); server
                                       # on :8796 with SQ_DEMO=0 SQ_MODERATE=0 SQ_ADMIN_TOKEN=test
```

Other Claude sessions often work here at the same time, each with a test server on its own port. Run
the e2e tests against a copy of `mockup/` (empty `data/app.json`) on a spare port, and stop servers by
PID or port, never `pkill -f "ruby server.rb"` (that kills everyone's).

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
- Later: Postgres instead of the JSON file, password reset by email, an RTMP
  ingest (WHIP/RTMP through LiveKit) for action cameras, simulcast to YouTube/TikTok, native app-store wrapper.
