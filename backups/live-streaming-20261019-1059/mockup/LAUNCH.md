# Side Quest: public beta checklist

## Done in the app (tested: 63-check two-user browser test + 10 beta-mode checks)

- **Try before signing up.** Guests browse events, the map, stories, Search and Meet, RSVP, and take the quiz. Anything that reaches other people (post, story, wave, message, join a group, go live, report) asks for a free account, then drops them back where they were. Guest RSVPs and answers carry into the account.
- **Real accounts.** Handle + password (hashed), 30-day sign-in sessions, 18+ checkbox, Terms/Privacy acceptance, optional invite codes, sign out, delete account.
- **The server decides who sees what.** Friends-only posts and stories are filtered on the server; blocks hide both ways; nobody can act as someone else.
- **Two-way friends.** A wave both ways on Meet (or accepting a request) makes you friends; only friends can message.
- **Safety.** Posts, story captions, group names and public profile text are screened by Claude; phone numbers and emails are blocked from public posts; ⋯ on any post, story, person or group to report or block; safety tips at sign-up and in messages.
- **Admin page** at `/admin`: open reports, anything that needs a human look (every photo story), feedback, people, with remove / suspend / delete.
- **Limits** on sign-ups, logins, posts, stories, messages and Claude features, so nobody can spam or drain your usage.
- **Locked down.** Only the app's own pages are served (code and the data folder return 404); cross-site requests are refused; standard security headers.
- **Demo content off in beta.** No made-up people, streams, stories or "going" counts. The 8 starter groups stay, with no fake members.
- **In-app feedback** (💬 on Home and in Me) goes to the admin page.
- **Installable.** Add to Home Screen on iPhone, Install on Android/Chrome: full-screen with the GO! icon.

## Run it

```sh
openssl rand -hex 24          # make an admin token
cat > ~/.sidequest.env <<'X'
SQ_INVITES="austin-beta"
SQ_ADMIN_TOKEN="paste-token-here"
X
./beta.sh                     # public beta mode
~/claude/live/serve.sh        # events service (separate terminal)
```

## Only you can do these before inviting strangers

1. **Claude billing.** Serving other people from your personal Claude subscription is very likely outside Anthropic's consumer terms. For the public beta, get an API key at console.anthropic.com and add `SQ_USE_API_KEY=1` and `ANTHROPIC_API_KEY=...` to `~/.sidequest.env`. The events scraper (`~/claude/live`) should follow suit.
2. **Put it on the Hetzner server** with a real domain and HTTPS. Caddy in front of the app gives automatic certificates; run the app with `SQ_BIND=127.0.0.1` behind it. Run both services under systemd so they restart on reboot, and back up `data/` nightly.
3. **Lawyer review** of `terms.html` and `privacy.html` (both marked DRAFT), and add a contact email.
4. **Moderation plan.** Photos aren't machine-checked: someone has to open `/admin` daily during the beta. Decide who.
5. **App stores (later).** The installable web app is enough for a beta. A store listing needs a native wrapper, developer accounts ($99/yr Apple, $25 Google) and store review.

## Before it grows past a few hundred people

- Move `data/app.json` to a real database (Postgres) and story photos to object storage.
- Add password reset by email (needs an email provider).
- Two-step sign-in for the admin page instead of a shared token.
- An ingest server for live streaming from cameras (MediaMTX), plus a TURN server so phone video works across mobile networks.
