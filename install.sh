#!/usr/bin/env bash
# Symlink the tools into ~/.local/bin so edits in this repo take effect at once.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${HOME}/.local/bin"

mkdir -p "$BIN"
for tool in lenovo-power lenovo-power-gui; do
  ln -sfn "$REPO/bin/$tool" "$BIN/$tool"
  echo "linked $BIN/$tool -> $REPO/bin/$tool"
done

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo; echo "warning: $BIN is not on your PATH" ;;
esac

echo
echo "Next: run 'lenovo-power install-perms' once so the sysfs knobs are"
echo "writable without sudo, then 'lenovo-power' to see current state."
