#!/bin/bash
# One-command installer for the cclight Mac agent:
#
#   curl -fsSL https://raw.githubusercontent.com/kellyxiepei/cclight/main/bootstrap.sh | bash
#
# Fetches the repo (git clone, or tarball if git is missing) into a temp
# dir and runs cclight-mac/install.sh, which deploys to ~/.cclight-mac
# and wires up the Claude Code hooks.
set -euo pipefail

REPO_URL="${CCLIGHT_REPO:-https://github.com/kellyxiepei/cclight.git}"
TARBALL_URL="https://github.com/kellyxiepei/cclight/archive/refs/heads/main.tar.gz"

TMP_DIR="$(mktemp -d /tmp/cclight-bootstrap.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> fetching cclight"
if command -v git >/dev/null 2>&1; then
    git clone --quiet --depth 1 "$REPO_URL" "$TMP_DIR/cclight"
else
    echo "    git not found, downloading tarball instead"
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMP_DIR"
    mv "$TMP_DIR"/cclight-* "$TMP_DIR/cclight"
fi

echo "==> running installer"
bash "$TMP_DIR/cclight/cclight-mac/install.sh"
