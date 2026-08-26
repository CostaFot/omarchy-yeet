# omarchy-messenger-share — agent notes

Right-click share from Brave to Telegram/Viber on Omarchy. Two halves:
a thin MV3 extension (context menus only) and a bash native-messaging host
that does all real work. Modeled on Omarchy's own
`/usr/share/omarchy/bin/omarchy-chromium-ytdlp-host` — read that for the
canonical idioms (framing, ack, detach, notifications).

## Architecture

- `extension/background-N.js` — builds 4 context-menu items, resolves the
  click payload, sends `{app, kind, ...}` over
  `chrome.runtime.sendNativeMessage('com.costa.messenger_share', ...)`.
  Images are fetched IN the extension (cookies via `host_permissions:
  <all_urls>`) and streamed to the host as base64 (`kind: blob`).
- `host/messenger-share-host` — bash. Reads one framed message (4-byte LE
  length + JSON), acks `\x02\x00\x00\x00{}` immediately, dispatches.
  Kinds: `text` (clipboard + focus app), `file` (path on disk), `blob`
  (base64 → write to `$SHARE_DIR`, uniquify browser-style), `video`
  (yt-dlp in a detached systemd unit), `error` (toast only).
- `install.sh` — generates `key.pem` (gitignored), pins the extension ID
  by injecting `key` into the manifest, computes the ID
  (sha256 of DER pubkey, first 32 hex chars mapped 0-9a-f→a-p), writes the
  host manifest to `~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/`.
  Everything user-level, no sudo.

Files land in `SHARE_DIR="${MESSENGER_SHARE_DIR:-$HOME/Downloads}"`.

## Hard-won constraints — do not re-litigate without re-testing

- **Brave ignores `saveAs: false`**: with "ask where to save each file"
  enabled, `chrome.downloads.download` always prompts. That's why images go
  fetch→base64→host instead of through the downloads API.
- **Service-worker cache**: after editing the background script, bump the
  filename suffix AND the manifest reference (`background-3.js` → `-4.js`).
  A plain reload can keep serving the old worker.
- **Telegram** (`telegram-desktop`, Wayland class `org.telegram.desktop`):
  `Telegram -- <file>` opens the "Forward to…" chat picker in the running
  instance. There is NO `-sendpath` and NO `tg://msg_url` in this build —
  links/text go clipboard+focus by design.
- **Viber**: no CLI at all. Its input accepts pasted `image/*` data ONLY.
  `text/uri-list` pastes as literal text; raw `video/mp4` data does nothing
  (all verified by driving the real app). Non-image files therefore use:
  focus Viber + `setsid -f nautilus --select <file>` + "drag it in" toast.
- **cgroup kills**: the video worker runs under
  `systemd-run --user --collect -p KillMode=process`. Without KillMode,
  unit cleanup reaps forked helpers — the wl-copy serving the clipboard
  died before the user could paste. Related: `uwsm-app` may run the app as
  a direct foreground child (nautilus blocked the host for 120s), so
  detach non-daemonizing apps with `setsid -f`.
- Keep launches synchronous where the target daemonizes/forwards
  (`uwsm-app -- Telegram -- file`, `omarchy-launch-or-focus`); detach with
  `setsid -f` only what stays in the foreground.

## Testing without the browser

Pipe a framed message straight into the host:

```bash
python3 -c 'import struct,sys,json; m=json.dumps({"app":"telegram","kind":"text","text":"hi"}).encode(); sys.stdout.buffer.write(struct.pack("<I",len(m))+m)' \
  | ./host/messenger-share-host | od -c   # expect \x02\0\0\0{}
```

Same shape for `file`/`blob`/`video`. Verify visually with
`grim -g "$(hyprctl clients -j | jq -r '...')"` screenshots; drive paste
tests with `wtype -M ctrl -k v -m ctrl`. Test video:
`https://www.youtube.com/watch?v=jNQXAC9IVRw` (19s). Extension changes need
a reload in `brave://extensions`; host-manifest changes need a Brave
restart; host-script changes apply on next right-click.

## Deferred / ideas

- Nautilus right-click "Share to…" — clone
  `~/.local/share/nautilus-python/extensions/localsend.py`, reuse this host's
  dispatch functions.
- Omarchy Share menu rows (`trigger.share.*` in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`) for clipboard/file-picker
  sharing outside the browser.
- `viber://forward?text=...` deep link might beat clipboard+focus for
  text/links to Viber — untested.
- Marketplace listing (omarchyplugins.com): would need conversion to a
  QML shell plugin or stays a standalone repo; submission is via GitHub
  issue on HANCORE-linux/omarchy-plugin-marketplace.
