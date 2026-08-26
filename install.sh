#!/bin/bash

# Installs the Messenger Share native host manifest for Brave and pins the
# extension ID by injecting a stable "key" into extension/manifest.json.
# Usage: ./install.sh [--uninstall]

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_NAME="com.costa.messenger_share"
BRAVE_HOSTS_DIR="$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
NAUTILUS_EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"

if [[ ${1:-} == "--uninstall" ]]; then
  rm -f "$BRAVE_HOSTS_DIR/$HOST_NAME.json"
  echo "Removed $BRAVE_HOSTS_DIR/$HOST_NAME.json"
  if [[ -L $NAUTILUS_EXT_DIR/messenger-share.py ]]; then
    rm -f "$NAUTILUS_EXT_DIR/messenger-share.py"
    echo "Removed $NAUTILUS_EXT_DIR/messenger-share.py (restart Files: nautilus -q)"
  fi
  echo "Now remove the extension in brave://extensions."
  exit 0
fi

cd "$PROJECT_DIR"

# Stable extension ID: pin a key in the manifest so the ID is independent of
# the load path. Chromium derives the ID from the first 16 bytes of the
# SHA-256 of the DER-encoded public key, hex mapped 0-9a-f -> a-p.
[[ -f key.pem ]] || openssl genrsa -out key.pem 2048 2>/dev/null
PUB_DER_B64=$(openssl rsa -in key.pem -pubout -outform DER 2>/dev/null | base64 -w0)
EXT_ID=$(openssl rsa -in key.pem -pubout -outform DER 2>/dev/null | sha256sum | head -c32 | tr '0-9a-f' 'a-p')

jq --arg k "$PUB_DER_B64" '.key = $k' extension/manifest.json > extension/manifest.json.tmp
mv extension/manifest.json.tmp extension/manifest.json

chmod +x host/messenger-share-host

mkdir -p "$BRAVE_HOSTS_DIR"
sed "s|__HOST_PATH__|$PROJECT_DIR/host/messenger-share-host|; s|__EXTENSION_ID__|$EXT_ID|" \
  host/$HOST_NAME.json.template > "$BRAVE_HOSTS_DIR/$HOST_NAME.json"

echo "Installed native host manifest: $BRAVE_HOSTS_DIR/$HOST_NAME.json"

# Nautilus right-click "Share to ..." (needs the nautilus-python package).
# Symlinked so the repo stays the source of truth; the extension reads the
# host path from the manifest installed above, so it needs no configuration.
if [[ -e /usr/lib/nautilus/extensions-4/libnautilus-python.so ]]; then
  mkdir -p "$NAUTILUS_EXT_DIR"
  ln -sfT "$PROJECT_DIR/nautilus/messenger-share.py" "$NAUTILUS_EXT_DIR/messenger-share.py"
  echo "Installed Nautilus extension: $NAUTILUS_EXT_DIR/messenger-share.py (restart Files: nautilus -q)"
fi
echo
echo "Extension ID: $EXT_ID"
echo
echo "Next steps:"
echo "  1. Open brave://extensions, enable Developer mode"
echo "  2. Load unpacked -> select $PROJECT_DIR/extension"
echo "  3. Verify the extension ID shown matches the one above"
echo "  4. Restart Brave once (native host manifests are read at startup)"
