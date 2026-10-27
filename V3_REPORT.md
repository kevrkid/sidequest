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
