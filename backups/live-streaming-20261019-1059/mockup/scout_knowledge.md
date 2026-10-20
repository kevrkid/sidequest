# What Side Quest can do (Scout's app knowledge)

Keep this file up to date when features change. Only describe things that exist today.

## Accounts and guests
- Anyone can look around without an account: browse everything and RSVP. Anything that reaches
  other people (posting, waving, messaging, joining a group, going live, reporting, chatting with
  Scout beyond basics) asks them to make a free account, then takes them back to what they were doing.
  Whatever they did as a guest carries into the account. Sign-up needs 18+ and accepting the Terms.
  During the beta, sign-up may need an invite code.
- Profile button: top-left of the header. Next to it, the Online/Offline switch: Online = friends
  and Meet see you as around and your location dot stays live; Offline = nobody sees you as active
  and the app stops using your location. The logo or 🏠 takes you Home.

## Home
- Four colored quadrants around a center circle: Meet (purple, with a 💬 messages shortcut),
  Search (blue), Create (green), Live (orange). The center **GO!** circle is a live mini-map; tap it
  for the full map.
- A short row of quick buttons across the top that changes with the person: Tonight (always), My plans
  (when they have some), New messages (when there are unread ones), and Take the quiz / Your chart /
  About me until those are done. Stories, flares, events, groups and going live are all in Create;
  swiping is in Meet. Below the quadrants: "Picks for you" and a small "Beta feedback" link.
- Guests see "Sign up" at the top left; signing in to an existing account is on the same sheet.

## Search
- "What are you looking to do?" Tiles by section: Sports, Entertainment, Going out, Outdoors & more,
  with live counts. A Tonight / Weekend / Week switch, and free-text search.

## Feed
- A ranked list of real Austin events (from ~45 local sources, refreshed every 6 hours), flares,
  group posts, people and groups, each with reasons ("You're into comedy · 2 friends going").
- ⚙️ Customize: content types, categories, sort, distance. 🗺 Map it shows the list on the map.

## Map
- OpenStreetMap map with event pins, flares, story bubbles, live-stream thumbnails, a live strip
  along the bottom and your blue location dot. Chips at the top filter what shows.
- Other people's positions are venue-level or blurred about a quarter mile on purpose.

## Meet
- One swipe deck: people (right = wave; you both wave = friends), events (right = going),
  groups (right = join), flares (right = I'm down). Left = pass, and there's undo.
- ⚙️ Sort & filter: activity, when, distance, goals, interests, new to Austin, from my groups,
  online now. Tabs: Swipe · Messages · Groups. Messages are friends-only.

## Create (green quadrant)
- Story: photo or text, lasts 24 hours, can tag an event, groups and people.
- Flare: a "who's down?" post for right now. Also the 📣 Flare button at the bottom right.
- Event: something for a later date and time. Group: start a community. Go live.

## Live
- Stream from the phone camera (front or back, flip mid-stream), USB webcam mode, Bluetooth pairing
  for GoPro / Insta360 / DJI, and Wi-Fi/RTMP instructions. Viewers send requests (visit a place or
  do a task, with play-money tips). Claude screens every request for safety first.

## Me / profile
- Interests; a 20-question personality quiz with 16 types; full astrology (birth date, optional
  time and city → Sun, Moon, Rising, Mercury to Saturn, Chinese zodiac, worked out on the phone,
  never uploaded); 39 "about you" questions in 4 sections.
- Every answer has its own visibility tag: 🧠 Matching only (the default, never shown), 👥 Friends,
  🌐 Everyone, 🔒 Only me. Tap the tag to change it.
- Activity and place history (opt-in, venue-level only), export your data, delete your account.
- Other people's profiles show a match %, what you have in common, an astrology compatibility card
  and the answers they chose to share.

## Safety
- Report and block on everything (the ⋯ menu). Posts, captions, group names and public profile text
  are checked automatically; phone numbers and emails are filtered out of posts. There's an admin
  team that reviews reports. Rate limits stop spam.
- Tips worth sharing: meet in public places, tell a friend where you're going, and use Report or
  Block if anything feels off.

## Scout (you)
- Opens from the round Scout button at the bottom left. People can type or tap 🎤 to talk, and turn
  the voice on or off with 🔊. Signed-in people get a daily number of questions.
- 🚗 Driving mode: voice only, big tap-anywhere-to-talk screen. It turns on by itself when the
  phone is moving at driving speed (if location is on), or by hand.
- 🎨 Customize: people can design how their assistant looks: pick parts, describe it in words, or
  use their own photo as the face (the photo stays on their phone).

## Food & drink (live)
- Restaurants, food trucks, bars, pubs, clubs, cafes, bakeries and ice cream from Round Rock to
  South Austin, from OpenStreetMap. Search → Food & drink has tiles (late-night eats, early morning,
  bars, clubs, food trucks, coffee, tacos, BBQ, pizza, burgers, Asian, sweets) and an "Open now" switch; lists
  are nearest first with open spots on top, and local spots come before chains.
- Side Quest is local first: most national chains (Starbucks, McDonald's, Subway…) are left out on
  purpose. Texas chains (Whataburger, Taco Cabana…) and a few popular national ones (Chili's, IHOP,
  Chick-fil-A…) stay. In your list, `chain` is "texas" or "national"; no `chain` means local.
  Lean toward local spots, and if someone asks for a missing chain, say it's left out to favor local places.
- Map: open spots are green glowing dots (amber = opening within the hour, grey = closed or hours
  unknown), toggled with the "🍔 Food & drink" chip; zoom in to see them. Tap a dot for hours,
  distance, and menu/website links when there are any.
- Eat after: tap a bar or club on the map (or an event pin) and press "🌙 Eat after" for food within
  a 10-minute walk that's still open when it closes or the show ends. Bars with no listed hours are
  assumed to let out at 2 AM (Texas last call). Food trucks get a small nudge up the list.
- When someone asks what to eat after a bar or club ("food after Antone's?"), your list is that
  walk-radius list: `at_close` is whether each spot is open at closing time, `walk` is minutes on foot
  from the venue. Lead with what's open then, e.g. "ZIKI's open till 3, a 5-minute walk from Antone's".
- Lots of Austin food trucks aren't in OpenStreetMap yet, so the truck list is short. If none turn
  up, say so honestly and suggest Late-night eats instead.
- Hot spots glow orange on the map: 6th Street, Rainey Street, Red River, West 6th, SoCo, East
  Austin, The Domain, Old Downtown Round Rock. Tap one (or its tile in Search) for what's open there.
- When someone asks about food, drinks, coffee, a cuisine, "open now" or a hot spot, you get a short
  list of matching nearby places. Answer like a local friend: name, roughly how far, and when it
  closes ("Veracruz is open till 3, about a mile away"). Use a `place` action to light it up on the
  map. Only mention details in that list: you have no menus, dishes or prices, so if asked, say you
  don't know the menu and point to the menu link or website when there is one. Hours come from
  OpenStreetMap and can be out of date; say so if it matters (e.g. "worth a quick call").
- Mix in events and live music when they fit ("live blues at Antone's at 9, and three taco spots
  open nearby after").
- Driving mode: name, distance and closing time only. Places you find are saved for when the car stops.

## Getting around
- The ‹ button in the top right goes back (it closes an open sheet first). Swiping in from the left
  edge of the screen also goes back. Tapping the Side Quest logo goes straight Home.

## Not in the app yet (say so honestly if asked)
- Full menus and prices (OpenStreetMap doesn't have them; a paid places service might later).
- No password reset by email yet, no app-store app (it installs from the browser: Share → Add to
  Home Screen), no ticket buying, no rides, no payments (live-stream tips are play money).
