#!/usr/bin/env bash
# Viena komanda: sukompiliuoja Arkadą ir įdiegia į laidu (ar Wi‑Fi) prijungtą iPhone.
#
#   ios/scripts/install_iphone.sh            # į prijungtą iPhone
#   ios/scripts/install_iphone.sh --sim      # tik patikrinti, ar kompiliuojasi (simuliatoriui, be parašo)
#   ios/scripts/install_iphone.sh --only laisvas-kaklas   # meniu – tik vienas žaidimas (pagal jo id)
#   ios/scripts/install_iphone.sh --app LaisvasKaklas     # atskira programa (project.yml taikinys)
#   ios/scripts/install_iphone.sh --app NaktinisGreitkelis
#
# Reikia: Mac su Xcode (prisijungta prie Apple ID: Xcode → Settings → Accounts) ir
# iPhone su įjungtu Kūrėjo režimu. XcodeGen įdiegiamas automatiškai per Homebrew.
# Komanda (Team ID) randama automatiškai; jei ne – ARKADA_TEAM=XXXXXXXXXX ios/scripts/install_iphone.sh
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DD="$IOS_DIR/build/DerivedData"
cd "$IOS_DIR"

SIM=0
ONLY=""
TARGET="Arkada"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim) SIM=1 ;;
    --only) ONLY="${2:-}"; shift ;;
    --app) TARGET="${2:-}"; shift ;;
    *) printf '\n✗ Nežinomas argumentas: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

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

case "$TARGET" in
  Arkada) BUNDLE_ID="lt.barons.arkada" ;;
  LaisvasKaklas) BUNDLE_ID="lt.barons.laisvaskaklas" ;;
  NaktinisGreitkelis) BUNDLE_ID="lt.barons.naktinisgreitkelis" ;;
  *) die "Nežinoma programa „${TARGET}“. Galimos: Arkada, LaisvasKaklas, NaktinisGreitkelis." ;;
esac

if [[ -n "$ONLY" ]]; then
  grep -rq "static let id = \"$ONLY\"" Arkada.swiftpm/Games || die "Nėra žaidimo su id „${ONLY}“."
  say "Meniu – tik žaidimas „${ONLY}“."
fi

if [[ $SIM -eq 1 ]]; then
  say "Kompiliuojama simuliatoriui (patikra)…"
  xcodebuild -project Arkada.xcodeproj -scheme "$TARGET" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" \
    ARKADA_ONLY_GAME="$ONLY" CODE_SIGNING_ALLOWED=NO build
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
    # Simuliatoriai irgi „paired“, todėl tikriname, kad įrenginys fizinis.
    return (hw.get("platform") == "iOS" and hw.get("deviceType") == "iPhone"
            and hw.get("reality") == "physical" and cp.get("pairingState") == "paired")
for d in sorted(devs, key=lambda d: d.get("connectionProperties", {}).get("transportType") != "wired"):
    if ok(d):
        print(d["identifier"]); break
PY
)"
rm -f "$DEV_JSON"
[[ -n "$DEVICE_ID" ]] || die "Neradau iPhone. Prijunk laidu, atrakink, paspausk „Pasitikėti“ ir įjunk Nustatymai → Privatumas ir saugumas → Kūrėjo režimas."

# --- Kompiliavimas ir pasirašymas ---
say "Kompiliuojama ir pasirašoma (pirmą kartą gali užtrukti)…"
xcodebuild -project Arkada.xcodeproj -scheme "$TARGET" -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic ARKADA_ONLY_GAME="$ONLY" \
  build
APP="$DD/Build/Products/Debug-iphoneos/$TARGET.app"
[[ -d "$APP" ]] || die "Nerastas sukompiliuotas $APP"

# --- Įdiegimas ir paleidimas ---
say "Diegiama į iPhone…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
say "Paleidžiama…"
if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "Jei telefone rodo „Nepatikimas kūrėjas“: Nustatymai → Bendrieji → VPN ir įrenginių valdymas → pasitikėti, tada atidaryk programą."
fi
say "✓ $TARGET įdiegta į iPhone."
