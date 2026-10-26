#!/usr/bin/env bash
# Sukuria naują Arkados žaidimą iš šablono ir įregistruoja jį meniu.
#
#   ios/scripts/new_game.sh <SwiftVardas> "<Pavadinimas>"
#   pvz.: ios/scripts/new_game.sh SpalvuGaudynes "Spalvų gaudynės"
#
# SwiftVardas – be lietuviškų raidžių, PascalCase (tampa vardų erdve ir aplanko vardu).
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Naudojimas: $0 <SwiftVardas> \"<Pavadinimas>\"" >&2
  exit 1
fi

NAME="$1"
TITLE="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Arkada.swiftpm"
TEMPLATE="$ROOT/templates/GameTemplate"
DEST="$APP/Games/$NAME"
REGISTRY="$APP/Core/GameRegistry.swift"

if [[ ! "$NAME" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "Klaida: '$NAME' turi būti PascalCase, tik A–Z, a–z, 0–9 (pvz. SpalvuGaudynes)." >&2
  exit 1
fi
if [[ -e "$DEST" ]]; then
  echo "Klaida: $DEST jau egzistuoja." >&2
  exit 1
fi
if grep -rqwE "(enum|struct|class) $NAME" "$APP"; then
  echo "Klaida: tipas '$NAME' jau naudojamas projekte." >&2
  exit 1
fi

# SpalvuGaudynes -> spalvu-gaudynes
ID="$(echo "$NAME" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
# Escape'iname pavadinimą sed'ui ir Swift eilutei.
TITLE_ESC="$(printf '%s' "$TITLE" | sed -e 's/[\\"]/\\\\&/g' -e 's/[&|]/\\&/g')"

cp -R "$TEMPLATE" "$DEST"
find "$DEST" -name '*__NAME__*' | while read -r f; do
  mv "$f" "${f//__NAME__/$NAME}"
done
find "$DEST" -type f -name '*.swift' -print0 | while IFS= read -r -d '' f; do
  sed -i.bak -e "s|__NAME__|$NAME|g" -e "s|__ID__|$ID|g" -e "s|__TITLE__|$TITLE_ESC|g" "$f"
  rm -f "$f.bak"
done

# Įrašome į registrą virš „// @registry“ žymės.
awk -v line="        $NAME.info," '/\/\/ @registry/ { print line } { print }' "$REGISTRY" > "$REGISTRY.tmp"
mv "$REGISTRY.tmp" "$REGISTRY"

echo "✓ Sukurta: Games/$NAME (id: $ID)"
echo "✓ Įregistruota: Core/GameRegistry.swift"
echo "Toliau: atidaryk ios/Arkada.swiftpm Xcode'e ir paleisk."
