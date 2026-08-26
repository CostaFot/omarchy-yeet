#!/bin/bash

# Installs the browser half of Yeet: the Brave native host
# manifest pointing at this checkout's host script, the extension itself via
# --load-extension in ~/.config/brave-flags.conf (the same mechanism Omarchy
# uses for its own bundled extensions — no developer mode, no Load unpacked),
# plus the optional Nautilus right-click extension. The extension ID comes
# from the "key" already committed in extension/manifest.json, so the normal
# path writes nothing inside the checkout — which keeps it clean when it
# lives in ~/.config/omarchy/plugins/ and `omarchy plugin update` runs
# git pull.
# Usage: ./install.sh [--uninstall]

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_NAME="com.costa.yeet"
BRAVE_HOSTS_DIR="$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
NAUTILUS_EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"
FLAGS_FILE="$HOME/.config/brave-flags.conf"
EXT_DIR="$PROJECT_DIR/extension"

remove_flag_entry() {
  [[ -f $FLAGS_FILE ]] || return 0
  grep -qF -- "$EXT_DIR" "$FLAGS_FILE" || return 0
  sed -i \
    -e "s|,$EXT_DIR||" \
    -e "s|=$EXT_DIR,|=|" \
    -e "\|^--load-extension=$EXT_DIR\$|d" \
    "$FLAGS_FILE"
  echo "Removed $EXT_DIR from $FLAGS_FILE"
}

if [[ ${1:-} == "--uninstall" ]]; then
  rm -f "$BRAVE_HOSTS_DIR/$HOST_NAME.json"
  echo "Removed $BRAVE_HOSTS_DIR/$HOST_NAME.json"
  remove_flag_entry
  if [[ -L $NAUTILUS_EXT_DIR/yeet.py ]]; then
    rm -f "$NAUTILUS_EXT_DIR/yeet.py"
    echo "Removed $NAUTILUS_EXT_DIR/yeet.py (restart Files: nautilus -q)"
  fi
  echo "Restart Brave and the extension is gone."
  exit 0
fi

cd "$PROJECT_DIR"

# Stable extension ID: derived from the public key pinned in the manifest.
# Chromium takes the first 16 bytes of the SHA-256 of the DER-encoded public
# key, hex mapped 0-9a-f -> a-p. Forks that strip the key get a fresh one
# generated and injected, same as the original install flow.
PUB_DER_B64=$(jq -r '.key // empty' extension/manifest.json)
if [[ -z $PUB_DER_B64 ]]; then
  [[ -f key.pem ]] || openssl genrsa -out key.pem 2048 2>/dev/null
  PUB_DER_B64=$(openssl rsa -in key.pem -pubout -outform DER 2>/dev/null | base64 -w0)
  jq --arg k "$PUB_DER_B64" '.key = $k' extension/manifest.json > extension/manifest.json.tmp
  mv extension/manifest.json.tmp extension/manifest.json
fi
EXT_ID=$(base64 -d <<<"$PUB_DER_B64" | sha256sum | head -c32 | tr '0-9a-f' 'a-p')

chmod +x host/yeet-host

mkdir -p "$BRAVE_HOSTS_DIR"
sed "s|__HOST_PATH__|$PROJECT_DIR/host/yeet-host|; s|__EXTENSION_ID__|$EXT_ID|" \
  host/$HOST_NAME.json.template > "$BRAVE_HOSTS_DIR/$HOST_NAME.json"

echo "Installed native host manifest: $BRAVE_HOSTS_DIR/$HOST_NAME.json"

# Load the extension the way Omarchy loads its own bundled ones: the
# --load-extension flag in brave-flags.conf, read at every Brave start.
# The pinned key means the ID stays the same regardless of the load path.
# Append to an existing --load-extension line (a second line would override
# the first — last flag wins), or add the line if there is none.
if grep -qF -- "$EXT_DIR" "$FLAGS_FILE" 2>/dev/null; then
  echo "Extension already in $FLAGS_FILE"
elif grep -q -- '--load-extension=' "$FLAGS_FILE" 2>/dev/null; then
  sed -i "s|^--load-extension=.*|&,$EXT_DIR|" "$FLAGS_FILE"
  echo "Appended extension to --load-extension in $FLAGS_FILE"
else
  printf -- '--load-extension=%s\n' "$EXT_DIR" >> "$FLAGS_FILE"
  echo "Added --load-extension to $FLAGS_FILE"
fi

# Nautilus right-click "Share to ..." (needs the nautilus-python package).
# Symlinked so the repo stays the source of truth; the extension reads the
# host path from the manifest installed above, so it needs no configuration.
if [[ -e /usr/lib/nautilus/extensions-4/libnautilus-python.so ]]; then
  mkdir -p "$NAUTILUS_EXT_DIR"
  ln -sfT "$PROJECT_DIR/nautilus/yeet.py" "$NAUTILUS_EXT_DIR/yeet.py"
  echo "Installed Nautilus extension: $NAUTILUS_EXT_DIR/yeet.py (restart Files: nautilus -q)"
fi
echo
echo "Extension ID: $EXT_ID"
echo
echo "Restart Brave and you're done — check brave://extensions if curious."
