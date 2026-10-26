#!/usr/bin/env bash
# Viena komanda: sukompiliuoja Arkadą ir įdiegia į laidu (ar Wi‑Fi) prijungtą iPhone.
#
#   ios/scripts/install_iphone.sh            # į prijungtą iPhone
#   ios/scripts/install_iphone.sh --sim      # tik patikrinti, ar kompiliuojasi (simuliatoriui, be parašo)
#
# Reikia: Mac su Xcode (prisijungta prie Apple ID: Xcode → Settings → Accounts) ir
# iPhone su įjungtu Kūrėjo režimu. XcodeGen įdiegiamas automatiškai per Homebrew.
# Komanda (Team ID) randama automatiškai; jei ne – ARKADA_TEAM=XXXXXXXXXX ios/scripts/install_iphone.sh
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DD="$IOS_DIR/build/DerivedData"
BUNDLE_ID="lt.barons.arkada"
cd "$IOS_DIR"

say() { printf '\n▶ %s\n' "$*"; }
die() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || die "Nerastas Xcode. Įdiek jį iš App Store ir atidaryk vieną kartą."
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || die "Reikia Homebrew (https://brew.sh) arba įdiek XcodeGen rankomis."
  say "Diegiamas XcodeGen…"
  brew install xcodegen
fi

say "Generuojamas Arkada.xcodeproj…"
xcodegen generate --quiet

if [[ "${1:-}" == "--sim" ]]; then
  say "Kompiliuojama simuliatoriui (patikra)…"
  xcodebuild -project Arkada.xcodeproj -scheme Arkada -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=NO build
  say "✓ Kompiliuojasi."
  exit 0
fi

# --- Komanda (Team ID) ---
TEAM="${ARKADA_TEAM:-}"
if [[ -z "$TEAM" ]]; then
  # Iš „Apple Development“ sertifikato (OU = Team ID) – tas pats, kuriuo pasirašytas b-finance.
  CERTS="$(mktemp -d)"
  security find-certificate -a -c "Apple Development" -p > "$CERTS/all.pem" 2>/dev/null || true
  awk -v d="$CERTS" '/BEGIN CERTIFICATE/{n++} n{print > (d "/c" n ".pem")}' "$CERTS/all.pem"
  for f in "$CERTS"/c*.pem; do
    [[ -e "$f" ]] || continue
    openssl x509 -in "$f" -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p'
  done > "$CERTS/teams"
  TEAM="$(head -n1 "$CERTS/teams")"
  rm -rf "$CERTS"
fi
[[ -n "$TEAM" ]] || die "Neradau Apple Development sertifikato. Xcode → Settings → Accounts → pasirink Apple ID → Manage Certificates → + Apple Development. Arba: ARKADA_TEAM=<Team ID> $0"
say "Komanda (Team ID): $TEAM"

# --- iPhone ---
say "Ieškomas prijungtas iPhone…"
DEV_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1 || true
DEVICE_ID="$(python3 - "$DEV_JSON" <<'PY'
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devs = []
def ok(d):
    hw = d.get("hardwareProperties", {})
    cp = d.get("connectionProperties", {})
    return hw.get("platform") == "iOS" and hw.get("deviceType") == "iPhone" and cp.get("pairingState") == "paired"
for d in sorted(devs, key=lambda d: d.get("connectionProperties", {}).get("transportType") != "wired"):
    if ok(d):
        print(d["identifier"]); break
PY
)"
rm -f "$DEV_JSON"
[[ -n "$DEVICE_ID" ]] || die "Neradau iPhone. Prijunk laidu, atrakink, paspausk „Pasitikėti“ ir įjunk Nustatymai → Privatumas ir saugumas → Kūrėjo režimas."

# --- Kompiliavimas ir pasirašymas ---
say "Kompiliuojama ir pasirašoma (pirmą kartą gali užtrukti)…"
xcodebuild -project Arkada.xcodeproj -scheme Arkada -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  build
APP="$DD/Build/Products/Debug-iphoneos/Arkada.app"
[[ -d "$APP" ]] || die "Nerastas sukompiliuotas $APP"

# --- Įdiegimas ir paleidimas ---
say "Diegiama į iPhone…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
say "Paleidžiama…"
if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "Jei telefone rodo „Nepatikimas kūrėjas“: Nustatymai → Bendrieji → VPN ir įrenginių valdymas → pasitikėti, tada atidaryk Arkadą."
fi
say "✓ Arkada įdiegta į iPhone."
