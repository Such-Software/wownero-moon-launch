#!/usr/bin/env bash
# One-time setup on the Linux render host (run ON the host, e.g. `ssh deb 'bash -s' < this`).
# Installs the headless rendering stack + Godot 4.6.1 so xvfb-run can render Movie
# Maker videos with NO physical display. Idempotent. Reusable for any of our Godot
# games -- this is the company "render farm" node.
#
# Software rendering: mesa-vulkan-drivers provides lavapipe (software Vulkan) for the
# default forward+ renderer; libgl1-mesa-dri provides llvmpipe (software GL) for the
# gl_compatibility fallback (--rendering-driver opengl3). No GPU required.
set -euo pipefail

GODOT_VER="${GODOT_VER:-4.6.1}"
GODOT_DIR="$HOME/godot"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VER}-stable_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip"

echo "[deb-setup] installing apt deps (xvfb, mesa software-render, ffmpeg, rsync)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  xvfb mesa-vulkan-drivers libgl1-mesa-dri libglu1-mesa \
  ffmpeg rsync unzip wget ca-certificates fontconfig libfontconfig1

if [ ! -x "$GODOT_BIN" ]; then
  echo "[deb-setup] downloading Godot ${GODOT_VER} (linux x86_64)..."
  mkdir -p "$GODOT_DIR"; cd "$GODOT_DIR"
  wget -qO godot.zip "$URL"
  unzip -o godot.zip >/dev/null
  rm -f godot.zip
  chmod +x "$GODOT_BIN"
else
  echo "[deb-setup] Godot already present: $GODOT_BIN"
fi

echo "[deb-setup] smoke test (version under xvfb):"
xvfb-run -a "$GODOT_BIN" --version || echo "[deb-setup] WARN: --version failed (check deps)"
echo "[deb-setup] DONE. Render binary: $GODOT_BIN"
