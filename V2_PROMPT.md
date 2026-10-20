# Side Quest V2: build brief

Written 2026-10-20 by Claude from the owner's request (a ChatGPT-drafted "V2" prompt, sections 21-25) plus what is
actually in the codebase today. This replaces the generic prompt with one grounded in the real app.

## What Side Quest is (V1, working, tested)

A social app for Austin / Central Texas that answers "what's the move tonight, and who's coming?". Real local events
(~45 scraped sources via the `~/claude/live` events service), people's own flares, groups, friend matching, stories,
live streaming (LiveKit), food & drink from OpenStreetMap + Google Places, outdoors (parks, lakes, trails), sights &
history (666 Texas historical markers with their text, National Register, Wikipedia), and **Scout**, a voice-first
Claude-powered guide that can search, RSVP (with a confirm), draft flares and messages, give directions and build
plans. Not a dating app. Ruby 2.6 stdlib server (`mockup/server.rb`, WEBrick, JSON file store) + one HTML file with
inline JS (`mockup/index.html`), no frameworks, no build step, no npm/gems. Playwright e2e test (109 checks).

## Constraints that stay

- Dependency-free: Ruby stdlib + vanilla JS. No build step. (So "build" = `ruby -c` + a JS syntax check.)
- Privacy by default: exact GPS never leaves the phone; venue-level only; per-answer visibility; friends-only content
  enforced on the server (`state_for()`).
- Claude calls signed-in only, rate-limited, short timeouts, fail safe.
- Everything a guest can't do goes through `needAccount()`.
- Other Claude sessions edit V1 (`~/claude/sidequest`) at the same time: V2 lives in its own folder and git repo
  (`~/claude/sidequest-v2`, branch `v2`, baseline commit = V1) and runs on its own port (8797).

## What V2 adds (in priority order)

1. **Event details**: a full sheet for any event (feed card, map pin, search, deep link): photo, when/where/price,
   description, friends going first then everyone, Going / Interested / Save, Invite friends (DM a link), Share link,
   calendar, directions, eat after, stories from there, and a short discussion thread for people going.
2. **Home that pulls you in**: "Next up" (your next event or plan stop with a countdown, directions and who's going)
   and "Tonight near you" (a swipeable strip of events with photos), above the quadrants.
3. **Notifications**: a 🔔 inbox in the header with a badge. Server-generated, per person, capped: friend requests and
   accepts, waves, someone down on your flare, friends going to an event you're going to, discussion replies, group
   joins, story tags and likes, quest completions, event reminders (2 h before). Optional browser notifications
   while the app is open or in the background (Notification API; real push needs VAPID keys, documented as next step).
4. **Quests** (the app's namesake): challenges that get people out: History buff (visit 5 historical markers), Taco
   crawl, Live music, Outdoors, Make friends, Night owl, Explorer (new neighborhoods)… Progress comes from check-ins
   (the phone checks you're within ~150 m; the server only gets the place id), RSVPs and social actions. XP, levels,
   badges on the profile (with the usual visibility choice), a weekly streak, and a friends-only leaderboard.
5. **Saved**: save events, places and sights; a Saved tab next to My plans.
6. **Growth**: share links with link previews (`/e/<id>`, `/s/<id>` server-rendered with Open Graph tags that open
   the app on that item), and personal invite links (`?ref=<handle>`) that make you friends after sign-up if the new
   person agrees.
7. **Analytics**: first-party, privacy-friendly counters (whitelisted event names, daily totals, unique users as
   salted daily hashes, no content, no locations) and an admin "Growth" panel: DAU/WAU, sign-ups, RSVPs, check-ins,
   quests, Scout use, 7-day retention.
8. **Safety**: live viewer requests and stream titles screened on the server (V1 only screened in the browser), and
   an accepted "visit" request doesn't reveal the destination before the location delay.

## Out of bounds without the owner

No deploys, no public publishing, no paid usage beyond the existing local caps, no credential changes, no deleting
user data, no destructive migrations (new keys in `app.json` only; old data read as-is).

## Definition of done

V1 preserved and verified (backup + checksums); V2 isolated; Ruby syntax + JS syntax checks clean; all existing test
suites pass on V2 plus new e2e checks for each feature; screenshots reviewed at phone width; honest report of what's
done, partial and next.
