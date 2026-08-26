#!/bin/bash

# Installs the browser half of Yeet: for each supported browser found
# (Brave, Chromium) a native host manifest pointing at this checkout's host
# script, plus the extension itself via --load-extension in that browser's
# flags file (the same mechanism Omarchy uses for its own bundled
# extensions — no developer mode, no Load unpacked), plus the optional
# Nautilus right-click extension. The extension ID comes from the "key"
# already committed in extension/manifest.json, so the normal path writes
# nothing inside the checkout — which keeps it clean when it lives in
# ~/.config/omarchy/plugins/ and `omarchy plugin update` runs git pull.
# Usage: ./install.sh [--uninstall]

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_NAME="com.costa.yeet"
NAUTILUS_EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"
EXT_DIR="$PROJECT_DIR/extension"

# name|binary|host-manifest dir|flags file. Keep in sync with the manifest
# probe lists in scripts/plugin-status and nautilus/yeet.py. Chrome is
# absent deliberately: branded Chrome removed --load-extension in 2025, so
# it has no automated install path. Chromium kept the flag, and Arch's
# launcher reads chromium-flags.conf just like Brave reads brave-flags.conf.
BROWSERS=(
  "Brave|brave|$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts|$HOME/.config/brave-flags.conf"
  "Chromium|chromium|$HOME/.config/chromium/NativeMessagingHosts|$HOME/.config/chromium-flags.conf"
)

# Where the extension lives when installed as an Omarchy plugin. Uninstall
# strips this from the flags files too, so a checkout's --uninstall still
# cleans up after `omarchy plugin remove` already deleted the plugin dir
# (and the install.sh inside it).
PLUGIN_EXT_DIR="$HOME/.config/omarchy/plugins/costafot.yeet/extension"

remove_flag_entry() {
  local flags_file=$1 ext_dir=$2
  [[ -f $flags_file ]] || return 0
  grep -qF -- "$ext_dir" "$flags_file" || return 0
  sed -i \
    -e "s|,$ext_dir||" \
    -e "s|=$ext_dir,|=|" \
    -e "\|^--load-extension=$ext_dir\$|d" \
    "$flags_file"
  echo "Removed $ext_dir from $flags_file"
}

if [[ ${1:-} == "--uninstall" ]]; then
  for entry in "${BROWSERS[@]}"; do
    IFS='|' read -r _ _ hosts_dir flags_file <<<"$entry"
    if [[ -f $hosts_dir/$HOST_NAME.json ]]; then
      rm -f "$hosts_dir/$HOST_NAME.json"
      echo "Removed $hosts_dir/$HOST_NAME.json"
    fi
    remove_flag_entry "$flags_file" "$EXT_DIR"
    remove_flag_entry "$flags_file" "$PLUGIN_EXT_DIR"
  done
  if [[ -L $NAUTILUS_EXT_DIR/yeet.py ]]; then
    rm -f "$NAUTILUS_EXT_DIR/yeet.py"
    echo "Removed $NAUTILUS_EXT_DIR/yeet.py (restart Files: nautilus -q)"
  fi
  echo "Restart the browser and the extension is gone."
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

# Per detected browser: the host manifest, then the extension the way
# Omarchy loads its own bundled ones — the --load-extension flag in the
# browser's flags file, read at every start. The pinned key means the ID
# stays the same regardless of the load path. Append to an existing
# --load-extension line (a second line would override the first — last flag
# wins), or add the line if there is none.
configured=()
for entry in "${BROWSERS[@]}"; do
  IFS='|' read -r name binary hosts_dir flags_file <<<"$entry"
  command -v "$binary" >/dev/null 2>&1 || continue

  mkdir -p "$hosts_dir"
  sed "s|__HOST_PATH__|$PROJECT_DIR/host/yeet-host|; s|__EXTENSION_ID__|$EXT_ID|" \
    host/$HOST_NAME.json.template > "$hosts_dir/$HOST_NAME.json"
  echo "Installed native host manifest: $hosts_dir/$HOST_NAME.json"

  if grep -qF -- "$EXT_DIR" "$flags_file" 2>/dev/null; then
    echo "Extension already in $flags_file"
  elif grep -q -- '--load-extension=' "$flags_file" 2>/dev/null; then
    sed -i "s|^--load-extension=.*|&,$EXT_DIR|" "$flags_file"
    echo "Appended extension to --load-extension in $flags_file"
  else
    printf -- '--load-extension=%s\n' "$EXT_DIR" >> "$flags_file"
    echo "Added --load-extension to $flags_file"
  fi
  configured+=("$name")
done

if [[ ${#configured[@]} -eq 0 ]]; then
  echo "No supported browser found (Brave, Chromium) — skipped the browser half." >&2
fi

# Nautilus right-click "Share to ..." (needs the nautilus-python package).
# Symlinked so the repo stays the source of truth; the extension reads the
# host path from a manifest installed above, so it needs no configuration.
if [[ -e /usr/lib/nautilus/extensions-4/libnautilus-python.so ]]; then
  mkdir -p "$NAUTILUS_EXT_DIR"
  ln -sfT "$PROJECT_DIR/nautilus/yeet.py" "$NAUTILUS_EXT_DIR/yeet.py"
  echo "Installed Nautilus extension: $NAUTILUS_EXT_DIR/yeet.py (restart Files: nautilus -q)"
fi

if [[ ${#configured[@]} -gt 0 ]]; then
  browsers="${configured[*]}"
  echo
  echo "Extension ID: $EXT_ID"
  echo
  echo "Restart ${browsers// / and } and you're done — check brave://extensions if curious."
fi
