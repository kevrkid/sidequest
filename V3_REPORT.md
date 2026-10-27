# Side Quest V3: the map is the app

Branch `v3` (folder `~/claude/sidequest-v3`, a git worktree next to V2). Built 2026-10-26 in four one-hour
build → review rounds. Not deployed, not merged into `v2`: the live site still runs V2.

## What changed for a person using it

**One screen.** The map fills the phone, always. Everything else slides up over it in one drawer, and five
buttons sit at the bottom: **Explore · For you · ＋ · Chats · You**. The old home screen (7 big tiles, a GO! circle,
a Flare button, a name menu with 9 items, an Online switch in the header) is gone.

- **Drawer:** drag it up or down (three stops), flick it, or just touch the map and it gets out of the way.
- **One search box** at the top of the drawer: places, parks, lakes, trails, landmarks, events, people, groups,
  "find it on menus", "search posts", and questions go straight to Scout ("where's good tacos open late?").
- **Chips** under the search box: Food, Tonight, Nightlife, Outdoors, Sights, Friends, Hot spots. One tap shows
  just that on the map *and* lists it in the drawer, nearest first, with smaller chips to narrow it (Happy hour,
  Coffee, Tacos, Open now…). Tap the chip again to put the map back.
- **Tap a pin** and its card opens in the drawer (hours, Menu, Directions, Check in, Save), like Google Maps,
  instead of a small bubble on the map. **Press and hold** the map for "what's here" and "Flare here".
- **Explore** (drawer pulled up): Up next, friends out, tonight near you, happy hours on now, open near you,
  busy neighborhoods, this weekend.
- **For you:** stories on top, picks, then the ranked feed; one row of filters.
- **＋ Create:** story, post, flare, event, group, go live, all in one place.
- **Chats:** Messages · Friends · Groups · Meet (the swipe deck).
- **You:** your picture, online switch, level/coins/streak, then My plans, Saved, Quests, Invite, Location sharing,
  Edit profile, Settings, Español.
- **On a computer** the map fills the window and the drawer is a panel on the left.
- The map starts calm (events, friends, live, parks and lakes); food, nightlife, sights and hot spot glows come
  with their chip or the layers button.
- Scout's tour, its answers about where things are, and its built-in help all describe the new screen.

## How it was built
Four rounds of about an hour: build, then a hard review (screenshots of every screen, plus a separate reviewer who had
never seen the app grading it against your goal), then fixes. Each round ended with the whole test suite green.

## How it was checked
- Every existing test suite was updated to walk the new screens the way a person would (the bottom bar, the search
  box, the chips, cards in the drawer) and passes; a new `mockup/e2e_v3.py` covers the drawer, chips, search, cards,
  press-and-hold, the bottom bar, You, the tour and the desktop layout, in Chrome and in WebKit (Safari's engine).
- Final numbers are in the "Tests" section below.

## Decisions I made
- **Built V3 on its own branch and folder** (`git worktree`), so V2 and the live site were never touched.
- **Kept the engine; changed the screens.** Almost all of V3 is in `mockup/index.html` plus Scout's notes. The server
  only learned a few new analytics names (`search_open`, `chip_*`). Every V2 feature is still there, just in one
  place each.
- **One home per thing:** stories in For you, plans/level/quests/settings in You, messages/friends/groups/Meet in
  Chats, creating anything behind ＋, location sharing in You (and the layers sheet), live streams on the map.
- **Calm map by default.** Food dots, nightlife, hot spot glows, trails and sights appear with their chip or the
  layers sheet, not all at once.
- **Pin details in the drawer, not bubbles** (easier to read and tap, never under the map buttons).
- **Hidden, not deleted:** the old Search sheet, quick bar and name menu code is still there behind the new
  screen, so nothing that links to them breaks.

## Tests (final run, 2026-10-26 ~21:00)
| Suite | Result |
|---|---|
| e2e_test.py (two new people, the whole app) | 117/117 |
| e2e_v3.py (drawer, chips, search, cards, hold, dock, You, tour, desktop) | 41/41 in Chrome, 36/36 in WebKit (5 drag checks need Chrome) |
| e2e_v2.py (V2 features) | 41/41 |
| e2e_live.py (1 streamer, 3 viewers) | 14/14 |
| chats 19 · groups 16 · friend map 11 · stories 14 · plans 11 · posts 13 · add location 24 · features 10 | all pass |
| test_v2.rb 64 · spots 15 · menus 41 · tonight 6 · google 17 · webpush 6 · geofix 13 · live 14 · hours · api | all pass |

A fresh reviewer who had never seen the app graded it against your goal: the old V2 home **D+**, V3 **B-**
("Explore is now simple, polished and one-handed").

## Try it
On this Mac: `cd ~/claude/sidequest-v3/mockup && ./start_v3.sh`, then http://localhost:8802, or on your phone (same
Wi-Fi) https://192.168.0.160:8446 (accept the certificate warning; it's this Mac's own certificate). It uses its own
data, so nothing touches the live site.

## Left for later (worth doing next)
- For you and Chats still open as full pages over the map; a next step is For you at half height with its items lit
  up on the map.
- Meet (the swipe deck) could move out of Chats into the Friends chip.
- Pins: one style across layers, and pulling the selected pin out of its cluster.
- Real iPhone check of the drawer gestures (tested with simulated touches and WebKit, not a physical phone).
- Going live with V3 is your call: it means merging `v3` into `v2` (or deploying `v3`) on the Hetzner server.
