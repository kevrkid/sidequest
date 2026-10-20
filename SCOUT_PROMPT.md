# Prompt: build Scout, Side Quest's AI guide

Paste this into Claude Code from the `sidequest` folder. CLAUDE.md is read automatically, so the
app details and house rules come along with it.

---

Build Scout, an animated AI guide inside Side Quest. Follow every rule in CLAUDE.md (no add-on
libraries, mobile first at 390px and 360px, privacy defaults, server-side filtering, the guest gate,
safe Claude calls). Work in phases and test each one.

## Who Scout is
- A small explorer with big eyes, a little backpack and a compass badge that glows while thinking.
- Adventurous, curious, upbeat, a bit quirky. Catchphrase "Let's go explore!", used sparingly.
  Calls nearby events "discoveries".
- A light joke about one answer in five. Never when someone is frustrated or upset, or on safety,
  reporting or account topics. Never about looks, age or identity.
- Helpful first, funny second: 1-3 short sentences that sound natural read aloud.
- Not a dating app: Scout never frames anyone as a date or romantic interest.
- Personality goes in `mockup/scout_personality.md`. App knowledge goes in
  `mockup/scout_knowledge.md`, written from CLAUDE.md. Neither file is served to browsers, and the
  server re-reads them on every question so they can be edited without a restart.
- Scout only describes features that exist. Paused work (food & drink, open-now dots, hot spots,
  back/swipe navigation) is "coming soon", never described as live.

## What Scout does
- Answers "how do I…" questions about every screen (Home, Search, Feed, Map, Meet, Create, Live,
  profile, safety) and recommends what to do tonight from real events and flares.
- Points at things: highlights a button or screen element with a pulsing ring and a short label,
  switching screens first if needed. Shows events and flares on the map with a pulsing marker.
- Talks: speech-to-text for the mic and text-to-speech for answers, using the browser's built-in
  speech (free, no libraries). A 🔊 toggle; voice is off by default except in driving mode.
- Animated face drawn in inline SVG: blinks, moves its mouth while talking, and has expressions:
  happy, thinking, surprised, laughing, confused, excited, calm.
- A floating Scout button at the bottom left opens the Scout panel. After pointing, the panel gets
  out of the way and a speech bubble by the button shows what Scout said.

## Custom assistant looks (each user designs their own)
- Every user can design how their assistant looks and rename it (default "Scout").
- Three ways, offered as an optional step right after sign-up and any time from the Scout panel (🎨):
  1. Builder: tap to pick body color, accent color, shape, eyes, hat, glasses, ears, an extra
     (scarf, bow tie, backpack) and cheeks.
  2. Describe it: type something like "a cowboy armadillo in sunglasses called Tex". Claude maps the
     description to those same parts plus a name (structured output with enums only).
  3. Photo: the user's own photo becomes the face inside the animated frame, which still bounces
     while talking and changes its ring color and expression badge. The photo is shrunk and kept
     only on the device (never uploaded), so no photo storage or photo moderation is needed.
- Looks are private to each user: saved on their device, never shown to anyone else.

## Driving mode
- Voice only: a full-screen, tap-anywhere-to-talk view with a big face and large text. No pointing,
  no screen changes, no typing, messaging, swiping or going live. Spoken answers of 1-2 sentences,
  distances in miles.
- Turns on automatically when location is on and the phone moves at driving speed (about 16 mph
  for two readings), with an "I'm a passenger" button. Turns off after a couple of minutes stopped.
  Also a manual 🚗 toggle. (Browsers can't detect car Bluetooth.)
- Map suggestions made while driving are saved and shown once the car stops.

## Server (server.rb)
- `POST /api/scout`: signed-in only, 30-second timeout, structured JSON out:
  `say`, `expression`, and up to 3 `actions` (`point` at a whitelisted target id, `go` to a view,
  `map` an event or flare id). The server drops any action that isn't allowed, and drops all
  visual actions in driving mode.
- `POST /api/scout/look`: turns a description into look parts. Signed-in only.
- The client sends the current view, the list of pointable targets, the last 6 messages and a small
  context: upcoming events and flares the user can already see, in miles, plus profile basics.
  Other people's text is marked as untrusted data in the prompt.
- Fail safe: if Claude is slow or down, Scout gives a friendly in-character "try again" answer and
  it doesn't count against the user's limit.
- Guests: no Claude. A small built-in FAQ answers the basics and points at buttons, then offers a
  free account for full Scout.

## Costs and limits
- Per user: `SQ_SCOUT_DAILY` questions per day (default 30) and `SQ_SCOUT_HOURLY` per hour
  (default 15). At the limit Scout says so in character ("I've explored a LOT with you today!").
- Daily budget for everyone, `SQ_SCOUT_BUDGET_USD` (default $10). Past it, Scout pauses until
  tomorrow and the server logs a warning.
- Use Haiku (`SQ_SCOUT_MODEL`) for how-to questions and Sonnet (`SQ_SCOUT_SMART_MODEL`) only for
  "what should I do tonight" questions. Keep the context small and history short.
- Voice uses the free built-in browser speech, so it costs nothing.
- Log questions and cost per user per day (kept 30 days) in `data/app.json`. The admin page shows the
  last 7 days, the top users, the budget, and a Pause / Resume Scout button.

## Privacy and safety
- Scout only sees what the app already shows that user (server-side filtered). Never exact GPS of
  anyone: positions stay venue-level or blurred.
- Scout won't help anyone track, find, follow or harass someone; it points to Block and Report.
- Now and then, a meeting-up safety tip: meet in public, tell a friend.
- Users can close, mute or ignore Scout at any time.

## Done means
- Inline script syntax-checks, `ruby -c server.rb` passes.
- The e2e test still passes (reset `data/app.json` to `{}` before and after), with new checks for:
  opening Scout, a guest FAQ answer that points at a button, a signed-in answer (Claude or the
  fallback), the look builder, and driving mode on/off.
- Screenshots at 390px and 360px of the Scout panel, a pointing highlight, the look builder and
  driving mode.
- `scout_knowledge.md` is updated whenever a feature changes.
