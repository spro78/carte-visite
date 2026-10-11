#!/usr/bin/env bash
# Vérification complète hors Studio :
#   1. construit la place avec Rojo
#   2. vérifie les types avec luau-lsp et les définitions de l'API Roblox
#   3. lance la simulation de test (tools/sim/test.luau)
# Usage : tools/check.sh            (tout)
#         tools/check.sh types      (types seulement)
#         tools/check.sh sim        (simulation seulement)
#         tools/check.sh preview    (rendus 3D dans tools/preview/out)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=tools/bin
mkdir -p "$BIN"

fetch() { # nom url
  if [ ! -x "$BIN/$1" ]; then
    echo "-> téléchargement de $1"
    local tmp; tmp=$(mktemp -d)
    curl -sSL --retry 3 -o "$tmp/a.zip" "$2"
    unzip -q -o "$tmp/a.zip" -d "$tmp"
    mv "$tmp/$1" "$BIN/$1"; chmod +x "$BIN/$1"; rm -rf "$tmp"
  fi
}
fetch rojo "https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip"
fetch lune "https://github.com/lune-org/lune/releases/download/v0.8.9/lune-0.8.9-linux-x86_64.zip"
fetch luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip"
[ -f "$BIN/globalTypes.d.luau" ] || curl -sSL -o "$BIN/globalTypes.d.luau" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

what=${1:-all}
"$BIN/rojo" sourcemap default.project.json -o sourcemap.json >/dev/null

if [ "$what" = all ] || [ "$what" = types ]; then
  echo "== Types (luau-lsp + API Roblox)"
  "$BIN/rojo" build default.project.json -o "$BIN/HuntOrHide.rbxl" >/dev/null
  if "$BIN/luau-lsp" analyze --definitions="$BIN/globalTypes.d.luau" --sourcemap=sourcemap.json \
      --ignore="tools/**" src; then echo "types OK"; else echo "ERREURS DE TYPES"; exit 1; fi
fi

if [ "$what" = all ] || [ "$what" = sim ]; then
  echo "== Simulation"
  "$BIN/lune" run tools/sim/test.luau sourcemap.json
fi

if [ "$what" = preview ]; then
  echo "== Rendus"
  mkdir -p tools/preview/out
  "$BIN/lune" run tools/sim/scenes.luau sourcemap.json tools/preview/out/scenes.json "${2:-all}"
  (cd tools/preview && [ -d node_modules ] || npm install --no-audit --no-fund >/dev/null; node render.mjs out/scenes.json --out out)
fi
