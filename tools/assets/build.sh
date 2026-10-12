#!/usr/bin/env bash
# Construit le kit d'assets avec Blender en module Python (bpy), sans fenêtre.
# Installe bpy dans tools/bin/blender-env au premier lancement (environ 400 Mo).
# Usage : tools/assets/build.sh [--only A,B] [--sheet] [--no-export]
set -euo pipefail
cd "$(dirname "$0")/../.."
ENV=tools/bin/blender-env
if [ ! -x "$ENV/bin/python" ]; then
  echo "-> installation de Blender (bpy 5.2.2, Python 3.13)"
  uv venv "$ENV" --python 3.13 -q
  uv pip install --python "$ENV/bin/python" -q bpy==5.2.2
fi
exec "$ENV/bin/python" tools/assets/build_kit.py "$@"
