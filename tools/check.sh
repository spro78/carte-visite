#!/usr/bin/env bash
# Vérification complète hors Studio :
#   1. construit la place avec Rojo (dist/HuntOrHide.rbxl, à ouvrir dans Studio)
#      et contrôle son contenu (tools/check_place.luau)
#   2. vérifie les types avec luau-lsp et les définitions de l'API Roblox
#   3. lance les simulations (tools/sim/test*.luau)
# Usage : tools/check.sh            (tout)
#         tools/check.sh place      (place Roblox dist/HuntOrHide.rbxl seulement)
#         tools/check.sh types      (types seulement)
#         tools/check.sh sim        (simulation seulement)
#         tools/check.sh preview [groupe] [map]   (rendus simulés dans tools/preview/out)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=tools/bin
mkdir -p "$BIN"

fetch() { # nom url [version attendue]
  # Un binaire d'une autre version est remplacé (voir lune ci-dessous)
  if [ -x "$BIN/$1" ] && [ -n "${3:-}" ] && ! "$BIN/$1" --version 2>/dev/null | grep -qF "$3"; then
    rm -f "$BIN/$1"
  fi
  if [ ! -x "$BIN/$1" ]; then
    echo "-> téléchargement de $1"
    local tmp; tmp=$(mktemp -d)
    curl -sSL --retry 3 -o "$tmp/a.zip" "$2"
    unzip -q -o "$tmp/a.zip" -d "$tmp"
    mv "$tmp/$1" "$BIN/$1"; chmod +x "$BIN/$1"; rm -rf "$tmp"
  fi
}
fetch rojo "https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip"
# Lune 0.10.4 : la 0.8.9 se figeait parfois (un cœur à 100 %, aucune sortie)
# sur une lecture de fichier quand la mémoire était déjà remplie, donc au
# chargement des sources d'une simulation (jusqu'à 1 lancement sur 4 sous charge)
fetch lune "https://github.com/lune-org/lune/releases/download/v0.10.4/lune-0.10.4-linux-x86_64.zip" "lune 0.10.4"
fetch luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip"
[ -f "$BIN/globalTypes.d.luau" ] || curl -sSL -o "$BIN/globalTypes.d.luau" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

what=${1:-all}
"$BIN/rojo" sourcemap default.project.json -o sourcemap.json >/dev/null

if [ "$what" = all ] || [ "$what" = place ]; then
  echo "== Place Roblox (dist/HuntOrHide.rbxl)"
  mkdir -p dist
  "$BIN/rojo" build default.project.json -o dist/HuntOrHide.rbxl >/dev/null
  "$BIN/lune" run tools/check_place.luau dist/HuntOrHide.rbxl || { echo "PLACE INCOMPLÈTE"; exit 1; }
fi

if [ "$what" = all ] || [ "$what" = types ]; then
  echo "== Types (luau-lsp + API Roblox)"
  if "$BIN/luau-lsp" analyze --definitions="$BIN/globalTypes.d.luau" --sourcemap=sourcemap.json \
      --ignore="tools/**" src; then echo "types OK"; else echo "ERREURS DE TYPES"; exit 1; fi
fi

if [ "$what" = all ] || [ "$what" = sim ]; then
  echo "== Simulation"
  status=0
  for t in tools/sim/test*.luau; do
    echo "-- $t"
    # Délai maximal : un blocage devient un échec visible au lieu d'attendre sans fin
    timeout 900 "$BIN/lune" run "$t" sourcemap.json || { rc=$?; [ $rc -eq 124 ] && echo "BLOCAGE : $t dépasse 15 minutes"; status=1; }
  done
  [ $status -eq 0 ] || { echo "ÉCHEC DE LA SIMULATION"; exit 1; }
fi

if [ "$what" = preview ]; then
  echo "== Rendus"
  mkdir -p tools/preview/out
  "$BIN/lune" run tools/sim/scenes.luau sourcemap.json tools/preview/out/scenes.json "${2:-all}" ${3:-}
  (cd tools/preview && [ -d node_modules ] || npm install --no-audit --no-fund >/dev/null; node render.mjs out/scenes.json --out out)
fi
