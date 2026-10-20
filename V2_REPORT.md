# Side Quest V2: implementation report

Written by Claude, 2026-10-20 (overnight session). Brief: `V2_PROMPT.md` (ChatGPT's sections 21-25 rewritten
against the real codebase).

## A. Backup and recovery

| What | Where |
|---|---|
| Full copy of V1, as it was before V2 started (01:49) | `~/claude/sidequest-v1-backup-2026-10-20/` |
| Same, as an archive | `~/claude/backups/sidequest-v1-2026-10-20.tar.gz` (942 entries) |
| Checksums of every V1 file | `~/claude/backups/sidequest-v1-2026-10-20.sha256` (926 files; re-verified at the end: 0 mismatches) |
| Events service (code + SQLite databases, no virtualenv) | `~/claude/backups/live-events-v1-2026-10-20.tar.gz` |

- Included: all code, docs, deploy kit, `mockup/data/` (app.json with real accounts, places, outdoors, sights + their
  download cache, stories, avatars). Not included: Python virtualenvs (reinstallable), your `~/.sidequest-*.env` key
  files (left where they are; never copied).
- **V1 is untouched and still runs**: `~/claude/sidequest` (ports 8787 / 8443). Other Claude sessions keep working there.
  The only V1 edits after the backup were two one-line fixes from tonight's earlier sights work (sight popup width on
  small phones, and jumping to a sight without animation so the popup isn't cut off).
- **V2 is a separate folder with its own git repo**: `~/claude/sidequest-v2`, branch `v2`. Branch `v1-baseline` = the
  untouched V1 copy (commit `2a5cf6a`). `git log --oneline v1-baseline..v2` lists every V2 change; `git diff
  v1-baseline..v2` shows all of it.
- **Going back**: V1 never changed, so just keep using `~/claude/sidequest`. To restore V1 from the backup:
  `rm -rf ~/claude/sidequest && cp -Rp ~/claude/sidequest-v1-backup-2026-10-20 ~/claude/sidequest` (or untar the archive),
  then check with `cd ~/claude/sidequest && shasum -a 256 -c ../backups/sidequest-v1-2026-10-20.sha256`.

## B. What changed

### New features (all working, all tested)
1. **🔔 Notifications**: a bell in the header with an unread badge and an inbox. Covers:
   - waves, new friends, and friends going to the same event as you;
   - replies in event and group chats, people down for your flare, group joins;
   - story tags and likes, quest wins;
   - **a reminder 2 hours before** things you're going to;
   - **a Monday "last week" recap** that nudges you toward the quest you're closest to finishing.

   Blocks are respected, repeats within an hour fold into one entry, and tapping a notification takes you to the thing.
2. **📱 Real phone push** (notifications with the app closed): standard Web Push written in plain Ruby, no service
   account or fees.
   - The encryption matches the RFC's official example byte for byte.
   - Subscriptions can only point at real push services, so the feature can't be used to make the server call other addresses (SSRF).
   - Expired phones are dropped automatically.
   - iPhone needs Side Quest added to the Home Screen (iOS 16.4+), and the app tells people so.
3. **🎟️ Event details page**:
   - hero photo, when, where and price;
   - Going, Interested, 🔖 Save, 💌 Invite (sends chosen friends a message with the link), 🔗 Share;
   - Calendar, Directions, Map, Eat after, Tickets;
   - the full description, and who's going with friends first;
   - "More like this", and check-in while the event is on;
   - **a discussion thread** for people going: moderated, with ⋯ to report or block.

   It opens from feed cards, map pins, Home, notifications and shared links.
4. **🏆 Quests**, the app's namesake. There are 12 quests: History buff, Culture hound, Taco crawl, Touch grass, Live and loud, Night owl, Explorer, Squad up, Light a flare, Storyteller, Bring a friend, Regular.
   - You earn XP and levels, keep a weekly streak, and collect badges.
   - A friends-only leaderboard (you can leave it).
   - **Check-ins** at sights, food spots, parks and events: the phone checks you're within 150 m, and the server only learns which place, never your location.
   - Your level shows on Home, on your profile, and to your friends.
5. **🔖 Saved** events, places and sights, listed in My plans → Saved.
   **Quest of the week** (1.5× XP, rotates weekly) and opt-in **Friends out now**: friends who choose to share their
   check-ins show on Home for 3 hours, place name only (off by default).
   **Scout** can open event pages and the new screens ("show me my quests", "how do I invite my friend").
6. **💬 Group chat** for members.
7. **Growth**:
   - share links with link previews (`/e/…` events, `/s/…` sights);
   - **personal invite links** that offer "be friends with whoever invited you". The links are signed, so nobody can fake one in someone else's name.
   - a "Bring a friend" quest;
   - a welcome nudge toward quests after sign-up.
8. **Home**: a swipeable "**Tonight near you**" strip, and "**Up next**" with a countdown, friends going and a Go button.
9. **📈 Analytics**: first-party and privacy-friendly. It records whitelisted tap names, daily totals and active days per account. There is no content, no location and no device ids.

   A new admin **Growth** panel shows daily and weekly actives, 7-day retention, sign-ups, RSVPs, check-ins, quests and top actions.
10. **Offline app shell** (service worker): the installed app opens instantly and still loads with no signal. It never caches live data, and shows offline / back-online notices.

### Improved existing features
- **Live safety** (both V1 gaps closed on the server):
  - viewer requests now need a signed pass from the server's safety check, and the server applies the hard rules itself;
  - stream titles appear only after they're checked;
  - accepted "visit" requests hide the destination during the location delay.
- **Admin**: flagged event and group chat appear under "Needs a human look", and chat reports show the author and the text.
- **Scout** knows about all of the above (notifications, events, quests, saved, invites), and can suggest quests.
- **Spanish** covers all the new screens.

### Backend and data
- **New files**: `mockup/v2.rb` (all V2 routes and logic), `mockup/webpush.rb` and `mockup/sw.js`.
- **New routes**: `/api/notifs`, `/api/quests`, `/api/quests/board`, `/api/checkin`, `/api/saves`, `/api/event/chat`, `/api/event/invite`, `/api/group/chat`, `/api/push`, `/api/t`, `/api/admin/growth`, and the pages `/e/<id>`, `/s/<id>`, `/i/<handle>/<code>`.
- **Small hooks in existing routes**: friend, rsvp, down, group join, story, like, post, signup, state, report, screen, relay, admin and account delete.
- **Data changes are additive only**: new keys in app.json (`notifs`, `quest`, `saves`, `ev_chat`, `push`, `reminded`, `recap`, `invite_key`). No existing key is renamed or removed, and old data loads as-is. Deleting an account also deletes its new data.
- **New files in `data/`**: `stats.json` (analytics) and `vapid.json` (the push signing key; secret, permissions 600, git-ignored, covered by the existing nightly backup).

### Security and privacy changes
- Invite links are signed per inviter.
- Notification texts use the server's own event titles, never text a browser sent.
- Push addresses are restricted to real push services, so no SSRF.
- The VAPID key never leaves the server.
- Chats are members-only for groups, screened by Claude, blockable and reportable.
- Check-ins never send GPS. The leaderboard is friends-only and you can opt out.
- Analytics stores no content or locations.

## C. Verification (all run tonight, against throwaway copies; real data never touched)

| Check | Result |
|---|---|
| Ruby syntax (`ruby -c`) on every server file | OK |
| JavaScript syntax of the whole inline script + `sw.js` (JavaScriptCore) | OK |
| `e2e_test.py` (V1's full Playwright suite) **on V2** | **109/109** |
| `e2e_v2.py` (new: 2 people, invite link, inbox, event page, going, save, chat + report, invites, share link, saved list, check-in near/far, quests, leaderboard, friends out now, group chat, badges, admin growth + chat report) | **36/36** |
| `test_v2.rb` (new: notifications, push delivery decrypted from a fake push service, quests + quest of the week, check-ins, friends out now privacy, saves, chats, invites incl. a forged link, share pages + escaping, analytics, privacy, account deletion, live safety with screening on) | **29/29** |
| `test_webpush.rb` (RFC 8291 example byte for byte, VAPID signature, SSRF guard) | **6/6** |
| `e2e_live.py` (1 streamer + 3 viewers) on V2 | **13/13** |
| `test_live.rb`, `test_google.rb`, `test_api.rb`, `test_hours.rb` on V2 | 14/14, 17/17, all pass, all pass |
| V1's own `e2e_test.py` on V1 after tonight's two small V1 fixes | 109/109 |
| Scout with the real Claude CLI: "show me my quests", "how do I invite my friend" | opens Quests / the invite link |
| Phone 360 px + 390 px and desktop 1280 px screenshots (Home, event page, inbox, quests, sight popup) | Checked. Fixed: Home rows squeezed at 360 px, sight popup cut off on small phones |
| Console errors during the browser runs | none |
| Offline: load, go offline, reload | App shell loads, offline notice shows |
| `git diff v1-baseline..v2` reviewed for accidental deletions | 42 removed lines, all deliberate replacements |

**Not run, and why:**
- **No lint or type-check**: the project has no linter or type checker (plain Ruby and vanilla JS by design). Syntax checks stand in.
- **Real push to a real phone**: needs your phone. Encryption and delivery are verified end to end against a fake push service and the RFC vector.
- **Sign in with Google and the paid Google and LiveKit paths**: deliberately left off in V2's runs (no paid usage). Their V1 test suites pass on V2.

## D. Incomplete work / known limits
- **Quests trust the phone's "I'm here"**: the server never gets GPS, by design, so someone determined could fake check-ins through the API. Impact is limited: XP is cosmetic, the board is friends-only, there's a cap of 40 a day, and each place counts once a day.
- **No push on iPhone unless installed**: iPhone gets push only when Side Quest is added to the Home Screen (Apple's rule).
- **No email digest**: the recap is in-app and push only. Email would need an email provider.
- **Still in English**: some older screens (Search, Meet, Me questions, Create sheets). This is the same as V1.
- **Events placed at the wrong spot**: the events scraper sometimes geocodes a venue wrongly (e.g. Cap City Comedy). This is a V1 issue in `~/claude/live`.
- **Deployment needs** (unchanged from V1): an Anthropic API key on the server, a GitHub repo, and a lawyer pass on terms and privacy.
- **New privacy text**: Terms/Privacy should mention push notifications, check-ins and analytics before launch.
- **Shared login cookie**: V2 shares the login cookie with V1 (same host, different port). Signing in on one can sign you out of the other.

## E. How to run V2
```sh
cd ~/claude/sidequest-v2/mockup
./start_v2.sh            # http://localhost:8797 ; phones: https://<this Mac's Wi-Fi address>:8444 ; admin at /admin (token v2admin)
./start_v2.sh --keys     # same, plus your Google + LiveKit keys (paid calls count against V1's budgets)
~/claude/live/serve.sh   # the events service on :8788 (shared with V1)
```
- **Nothing to install.** It uses the Mac's Ruby and Python. Playwright for the browser tests lives in a scratch venv; for a fresh one: `python3 -m venv ~/sq-pw && ~/sq-pw/bin/pip install playwright && ~/sq-pw/bin/playwright install chromium`.
- **Tests** (each starts its own throwaway server; never use your real data):
  ```sh
  ruby test_v2.rb && ruby test_webpush.rb && ruby test_live.rb && ruby test_google.rb && ruby test_api.rb && ruby test_hours.rb
  # browser tests: start a copy with SQ_PLACES_FILE=test_places.json SQ_OUTDOORS_FILE=test_outdoors.json SQ_SIGHTS_FILE=test_sights.json
  #   SQ_ADMIN_TOKEN=test on a spare port with an empty data/app.json, then:
  SQ_BASE=http://localhost:<port> python e2e_test.py shots/ ; SQ_BASE=… SQ_ADMIN_TOKEN=test python e2e_v2.py shots/
  ```
- **Environment variables** (names only):
  - same as V1 (`SQ_GOOGLE_*`, `SQ_LIVEKIT_*`, `SQ_ADMIN_TOKEN`, `SQ_USE_API_KEY`, `ANTHROPIC_API_KEY`, …);
  - new: `SQ_PUSH_CONTACT` (mailto for push services);
  - tests only: `SQ_PUSH_TEST_HOST`.

## F. Recommended next steps
1. **Try V2 on your phone**: https://192.168.0.160:8444. Turn on Phone notifications in the 🔔 inbox, check in at a marker, invite a friend.
2. **Decide**: merge V2 into the main folder, or keep the two side by side for a while.
   - Merging means copying the V2 files over V1 (same structure). V2 reads V1's data file as-is.
3. **Before launch**:
   - add push, check-ins and analytics to the privacy policy;
   - set `SQ_PUSH_CONTACT`;
   - keep `data/vapid.json` in backups (it already is).
4. **Next features**:
   - an email digest;
   - quests tied to real events (e.g. "3 shows at Red River this month");
   - translate the remaining older screens.
5. **Fix the events scraper's venue geocoding** (wrong pins mean no photos and wrong distances).
