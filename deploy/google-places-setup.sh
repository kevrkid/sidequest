#!/bin/bash
# Sets up Google Places for Side Quest with the gcloud CLI, so nobody has to click through the Cloud console:
# a project, billing linked, the Places API (New) turned on, an API key that can only call Places, a $10/month
# budget alert, and the key saved to ~/.sidequest-google.env (chmod 600). The key is never printed.
#
#   deploy/google-places-setup.sh login       # once: sign in to Google in your browser
#   deploy/google-places-setup.sh             # or: deploy/google-places-setup.sh <project-id> [budget-usd]
#
# Also a browser key for Google's map tiles (Map Tiles API), locked to the app's web addresses (SQ_MAP_ORIGINS).
# Safe to run again: it reuses the project, keys and budget it made before and rewrites the key file.
set -euo pipefail

# gcloud needs Python 3.10+; macOS ships 3.9, so use the standalone one in ~/.local/python-gcloud if it's there
[ -x "$HOME/.local/python-gcloud/bin/python3" ] && export CLOUDSDK_PYTHON="${CLOUDSDK_PYTHON:-$HOME/.local/python-gcloud/bin/python3}"
command -v gcloud >/dev/null || PATH="$HOME/google-cloud-sdk/bin:$PATH"
if [ "${1:-}" = "login" ]; then exec gcloud auth login --brief; fi

FORCE=0; [ "${1:-}" = "--force" ] && { FORCE=1; shift; }
PROJECT="${1:-sidequest-places}"
BUDGET="${2:-10}"
KEY_NAME="Side Quest places"
OUT="$HOME/.sidequest-google.env"

say() { printf '\n== %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

command -v gcloud >/dev/null || die "gcloud isn't installed. See https://cloud.google.com/sdk/docs/install"
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
[ -n "$ACCOUNT" ] || die "Not signed in. Run: deploy/google-places-setup.sh login"
echo "Signed in as $ACCOUNT"

say "Project $PROJECT"
if gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
  echo "Already exists; using it."
else
  # project ids are global: if the plain name is taken, add a short random suffix
  gcloud projects create "$PROJECT" --name="Side Quest" >/dev/null 2>&1 || {
    PROJECT="$PROJECT-$(openssl rand -hex 3)"   # (tr|head under pipefail would kill the script silently)
    gcloud projects create "$PROJECT" --name="Side Quest" >/dev/null
  }
  echo "Created $PROJECT"
fi

say "Billing"
LINKED=$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName.basename())' 2>/dev/null || true)
if [ -n "$LINKED" ]; then
  BILLING="$LINKED"; echo "Already linked to billing account $BILLING"
else
  ACCOUNTS=$(gcloud billing accounts list --filter=open=true --format='value(name.basename())')
  [ -n "$ACCOUNTS" ] || die "No open billing account. Add one at https://console.cloud.google.com/billing (a card is required even for the free allowance), then run this again."
  BILLING=$(echo "$ACCOUNTS" | head -1)
  [ "$(echo "$ACCOUNTS" | wc -l)" -gt 1 ] && echo "Several billing accounts; using the first ($BILLING)."
  gcloud billing projects link "$PROJECT" --billing-account="$BILLING" >/dev/null
  echo "Linked to billing account $BILLING"
fi

say "Turning on the Places API (New)"
gcloud services enable places.googleapis.com apikeys.googleapis.com --project="$PROJECT"

say "API key \"$KEY_NAME\" (Places API only)"
KEY_ID=$(gcloud services api-keys list --project="$PROJECT" --filter="displayName=\"$KEY_NAME\"" --format='value(name)' | head -1)
if [ -n "$KEY_ID" ]; then
  echo "Reusing the existing key."
else
  gcloud services api-keys create --project="$PROJECT" --display-name="$KEY_NAME" \
    --api-target=service=places.googleapis.com >/dev/null 2>&1
  KEY_ID=$(gcloud services api-keys list --project="$PROJECT" --filter="displayName=\"$KEY_NAME\"" --format='value(name)' | head -1)
  [ -n "$KEY_ID" ] || die "The key wasn't created. Check the Credentials page of $PROJECT."
  echo "Created."
fi
say "Map key \"Side Quest map tiles\" (browser key: Map Tiles API, only from the app's own addresses)"
# This key sits in the web page, so it's locked to the app's addresses and to map tiles only.
ORIGINS="${SQ_MAP_ORIGINS:-http://localhost:8787/*,https://localhost:8443/*,https://192.168.0.160:8443/*,https://sidequest.cc.middlematter.com/*}"
gcloud services enable tile.googleapis.com --project="$PROJECT"
MAP_ID=$(gcloud services api-keys list --project="$PROJECT" --filter='displayName="Side Quest map tiles"' --format='value(name)' 2>/dev/null | head -1)
if [ -n "$MAP_ID" ]; then
  gcloud services api-keys update "$MAP_ID" --allowed-referrers="$ORIGINS" >/dev/null 2>&1 || true
  echo "Reusing it; allowed addresses: $ORIGINS"
else
  gcloud services api-keys create --project="$PROJECT" --display-name="Side Quest map tiles" \
    --api-target=service=tile.googleapis.com --allowed-referrers="$ORIGINS" >/dev/null 2>&1
  MAP_ID=$(gcloud services api-keys list --project="$PROJECT" --filter='displayName="Side Quest map tiles"' --format='value(name)' | head -1)
  [ -n "$MAP_ID" ] || die "The map key wasn't created. Check the Credentials page of $PROJECT."
  echo "Created; allowed addresses: $ORIGINS"
fi

say "Voice key \"Side Quest voice\" (server key: Text-to-Speech only, for Scout's voice)"
gcloud services enable texttospeech.googleapis.com --project="$PROJECT"
TTS_ID=$(gcloud services api-keys list --project="$PROJECT" --filter='displayName="Side Quest voice"' --format='value(name)' 2>/dev/null | head -1)
if [ -n "$TTS_ID" ]; then echo "Reusing it."; else
  gcloud services api-keys create --project="$PROJECT" --display-name="Side Quest voice" --api-target=service=texttospeech.googleapis.com >/dev/null 2>&1
  TTS_ID=$(gcloud services api-keys list --project="$PROJECT" --filter='displayName="Side Quest voice"' --format='value(name)' | head -1)
  [ -n "$TTS_ID" ] || die "The voice key wasn't created. Check the Credentials page of $PROJECT."
  echo "Created."
fi

CLIENT_ID=$(grep -s '^SQ_GOOGLE_CLIENT_ID=' "$OUT" | cut -d= -f2-)
umask 077
{
  echo "# Google keys for Side Quest (project $PROJECT). Made by deploy/google-places-setup.sh."
  echo "SQ_GOOGLE_PLACES_KEY=$(gcloud services api-keys get-key-string "$KEY_ID" --format='value(keyString)')"
  echo "SQ_GOOGLE_DAILY=300"
  echo "# Browser key: shown to every visitor's browser, so it only works for map tiles from the addresses above."
  echo "SQ_GOOGLE_MAPS_BROWSER_KEY=$(gcloud services api-keys get-key-string "$MAP_ID" --format='value(keyString)')"
  echo "# Server key for Scout's voice (Text-to-Speech only)."
  echo "SQ_GOOGLE_TTS_KEY=$(gcloud services api-keys get-key-string "$TTS_ID" --format='value(keyString)')"
  [ -n "$CLIENT_ID" ] && echo "SQ_GOOGLE_CLIENT_ID=$CLIENT_ID"   # Sign in with Google (made by hand in the console)
} > "$OUT"
chmod 600 "$OUT"
echo "Saved to $OUT (only you can read it)."

say "Budget alert: \$$BUDGET a month"
if gcloud billing budgets list --billing-account="$BILLING" --billing-project="$PROJECT" --format='value(displayName)' 2>/dev/null | grep -qx "Side Quest Places"; then
  echo "Already set."
else
  gcloud services enable billingbudgets.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true
  if gcloud billing budgets create --billing-account="$BILLING" --display-name="Side Quest Places" \
       --budget-amount="${BUDGET}USD" --filter-projects="projects/$PROJECT" \
       --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
       --billing-project="$PROJECT" >/dev/null 2>&1; then
    echo "Emails go to the billing account's admins at 50%, 90% and 100%."
  else
    echo "Couldn't set it from here (some accounts need it done by hand): https://console.cloud.google.com/billing/$BILLING/budgets"
  fi
fi

say "Checking the key works"
. "$OUT"
for i in 1 2 3 4 5 6; do   # a new key can take a minute to start working
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST https://places.googleapis.com/v1/places:searchText \
    -H 'Content-Type: application/json' -H "X-Goog-Api-Key: $SQ_GOOGLE_PLACES_KEY" -H 'X-Goog-FieldMask: places.id' \
    -d '{"textQuery":"Franklin Barbecue, Austin TX","maxResultCount":1}')
  [ "$CODE" = 200 ] && { echo "Google answered. Places is ready."; break; }
  echo "Not yet (HTTP $CODE); trying again in 15 s…"; sleep 15
done
[ "$CODE" = 200 ] || echo "Still not answering. Wait a few minutes and restart the app; new keys can be slow to switch on."

say "Done"
echo "Restart Side Quest (mockup/start.sh or phone.sh) and tap a place on the map to see Google's rating and hours."
