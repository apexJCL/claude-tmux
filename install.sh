#!/usr/bin/env bash
# Symlink bin/* into ~/.local/bin, so the repo is what tmux and Claude Code run.
# tmux.conf and the statusLine setting already point at those paths; see README.
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)/bin
dest=${1:-$HOME/.local/bin}
mkdir -p "$dest"
for f in "$src"/*; do
  ln -sfn "$f" "$dest/$(basename "$f")"
  echo "$dest/$(basename "$f") -> $f"
done
