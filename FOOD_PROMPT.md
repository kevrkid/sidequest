# Prompt: food, bars, "open now" and Scout

Paste the text below into Claude Code from the `sidequest` folder, on a steady connection
(home Wi-Fi). CLAUDE.md is read automatically, so the house rules come along with it.

---

Finish the paused "Food & drink + hot spots" work from CLAUDE.md, and teach Scout to use it, so I can
ask Scout things like "find me tacos that are open right now", "what bars are open near Rainey St?",
"where's live music tonight?" or "what kind of food does that place serve?". Follow every rule in
CLAUDE.md: no add-on libraries, mobile first (390px and 360px), privacy defaults, server-side work,
the guest gate, safe Claude calls. Work in phases and test each one.

## 1. Get the places (OpenStreetMap)
- Download Austin / Central Texas restaurants, bars, pubs, nightclubs, cafes, food trucks, bakeries,
  ice cream and late-night spots from the OpenStreetMap Overpass API, from Round Rock to South Austin.
- My internet can be slow (a phone hotspot cut off two earlier downloads), so:
  - Split the area into small tiles and download them one at a time, saving each as it finishes
    so an interrupted run picks up where it left off. Retry with backoff, use short timeouts,
    and print progress.
  - Never download when someone opens the app. Do it with a script I run (and a weekly refresh),
    and save the result to a data file the server reads.
- Keep, for each place: name, type (restaurant, bar, pub, club, cafe, food truck…), cuisine tags
  (bbq, tex-mex, tacos, pizza, coffee…), opening hours, address, venue-level position, and the
  website and menu link when OpenStreetMap has them. Skip places with no name.
- Tell me how many places came in, and how many have opening hours.

## 2. "Open now"
- Write a small opening-hours reader by hand (no libraries) that handles the common OpenStreetMap
  formats: day ranges, several time ranges, past-midnight closing (e.g. "Fr-Sa 17:00-02:00"),
  "24/7", "off", and holidays treated as unknown. Use Austin time.
- Results: open now (and until when), opening soon (and when), closed, or hours unknown.
  Never guess: unknown stays unknown, and the app says so.
- Test it with a list of real examples, including late-night and overnight hours.

## 3. In the app
- Map: green glowing "open now" dots for food and drink, dimmer dots for closed or unknown, and a
  map chip to show or hide them. Tap a dot for name, type, cuisine, open/closed until when,
  distance, and the website/menu link if there is one.
- Austin hot spots as soft glowing zones: 6th St, Rainey St, Red River, West 6th, SoCo,
  East Austin, The Domain, Old Downtown Round Rock. Tapping a zone lists what's open in it now.
- Search: a Food & drink section with tiles (late-night eats, early morning, bars, clubs, coffee,
  plus popular cuisines) and an "Open now" switch. Results sorted by distance and open status.
- Finish the back button and swipe-back navigation listed in the same open item.

## 4. Scout uses it
- When someone asks about food, drinks, bars, coffee, a cuisine, "open now" or a hot spot, send
  Scout the matching nearby places (about 15, already filtered and sorted on the server,
  with open status, closing time, cuisine, distance in miles and hot-spot name). Keep the list
  small to keep costs down.
- Add a `place` action so Scout can pulse a place on the map, like it does for events. The server
  only allows place ids that were in the list it sent.
- Scout answers like a local friend: "Veracruz on East Cesar Chavez is open till 3, about a mile
  away. Get the migas taco." It may only mention dishes or details that are in the data. When it
  doesn't know the menu, it says so and offers the menu link or website if there is one.
- Scout mixes in events and live music when they fit ("there's live blues at Antone's at 9, and
  three taco spots open nearby after").
- Driving mode: spoken answers with name, distance and closing time only. Places it finds are
  saved for when the car stops, like events.
- Update `mockup/scout_knowledge.md` so Scout knows these features exist now, and add guest FAQ
  answers ("food", "bar", "open now", "coffee").

## 5. Honest limits
- OpenStreetMap doesn't have full menus or prices. Don't scrape restaurant websites. Show a menu
  link when one exists, and list "full menus" in CLAUDE.md as a later idea (e.g. a paid places API).
- Opening hours can be out of date. Add a small "hours from OpenStreetMap; may be out of date" note.

## Done means
- `ruby -c server.rb` passes and the inline script syntax-checks.
- The opening-hours tests pass.
- The e2e test passes (reset `data/app.json` to `{}` before and after). Use a small fixture
  file of places so the test doesn't need the internet. New checks: open-now dots on the map,
  the Food & drink section in Search, the open-now switch, a hot-spot zone, back/swipe-back, and
  Scout answering "find me tacos open now" with a `place` action.
- Screenshots at 390px and 360px of the map with dots and zones, Food & drink search, and Scout
  answering a food question.
- CLAUDE.md updated: the feature moves out of "Open items", and the download script and data
  file are documented.
