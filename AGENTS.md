# omarchy-yeet — agent notes

Yeet: share to Telegram/Viber on Omarchy. ("Yeet" is the app name only —
all user-facing copy says "Share to …", so future messengers slot in.) Three halves: an Omarchy shell
bar-widget plugin (the repo root IS the plugin), a thin MV3 extension
(context menus + X/Twitter, Instagram, and TikTok content scripts), and a
bash native-messaging host that does all real work. Modeled on Omarchy's own
`/usr/share/omarchy/bin/omarchy-chromium-ytdlp-host` — read that for the
canonical idioms (framing, ack, detach, notifications).

## Architecture

- `manifest.json` + `BarWidget.qml` + `Panel.qml` — the Omarchy shell plugin
  (kind `bar-widget`, id `costafot.yeet`). `omarchy plugin add
  <repo> --enable` clones the whole repo into
  `~/.config/omarchy/plugins/costafot.yeet/`, so the bash host
  ships inside the plugin dir and the bar half needs no install.sh.
  BarWidget is a one-glyph button (modeled on agx.screen-time's — panel
  shape contract + IpcHandler so `omarchy-shell costafot.yeet
  toggle` works from a keybinding). The IpcHandler also exposes
  `share <telegram|viber> <clipboard|file|video>` and
  `send <telegram|viber> <text|file|video> <payload>` (headless runs of
  `scripts/plugin-share`; args validated in QML because execDetached
  swallows the script's stderr; two functions because Quickshell IPC
  arity is strict — no optional args). Panel is a `qs.Ui` KeyboardPanel:
  Telegram/Viber sections × Clipboard / File… / Video-from-copied-link rows,
  each row `Quickshell.execDetached`-ing `scripts/plugin-share`. Rows are
  filtered by `scripts/plugin-status` (JSON probe re-run on every open):
  missing app hides its section, missing yt-dlp hides video rows, no host
  manifest in any supported browser adds a "Set up browser sharing…" row
  that runs install.sh in a floating terminal.
- `scripts/plugin-share <app> <clipboard|text|file|video> [payload]` —
  builds the same framed JSON the extension sends (python3 one-liner for
  the 4-byte LE frame) and pipes it into the bundled host. Clipboard mode
  prefers an `image/*` clipboard type (screenshots) via the host's `blob`
  path; file mode uses `omarchy-file-select`; video mode validates an
  `https://` URL off the clipboard. With a payload (a message, a path, a
  URL) every mode runs non-interactively — the scripting/agent surface;
  errors then go to stderr AND a toast, exit 1.

- `extension/background-N.js` — builds 4 context-menu items, resolves the
  click payload, sends `{app, kind, ...}` over
  `chrome.runtime.sendNativeMessage('com.costa.yeet', ...)`.
  Images are fetched IN the extension (cookies via `host_permissions:
  <all_urls>`) and streamed to the host as base64 (`kind: blob`).
- `extension/twitter-tweet-url.js` — content script on x.com/twitter.com
  (`run_at: document_start`). Tracks the tweet under each right-click and
  answers the background's `{type: 'get-tweet-url'}` message with its
  `/status/` URL; also suppresses X's custom video context menu. See the
  X/Twitter constraint below for the why.
- `extension/instagram-post-url.js` — same idea for Instagram's home feed:
  answers `{type: 'get-post-url'}` with the `/p/<shortcode>/` permalink of
  the post under the right-click. See the Instagram constraint below.
- `extension/tiktok-video-url.js` — same idea for TikTok's For You feed:
  answers `{type: 'get-tiktok-url'}` with the `/@user/video/<id>` permalink,
  and suppresses TikTok's custom video context menu. See the TikTok
  constraint below.
- `host/yeet-host` — bash. Reads one framed message (4-byte LE
  length + JSON), acks `\x02\x00\x00\x00{}` immediately, dispatches.
  Kinds: `text` (clipboard + focus app), `file` (path on disk), `blob`
  (base64 → write to `$SHARE_DIR`, uniquify browser-style), `video`
  (yt-dlp in a detached systemd unit), `error` (toast only).
- `nautilus/yeet.py` — nautilus-python extension (modeled on the
  localsend.py it sits next to): "Share to Telegram/Viber" on a single
  selected file, piping a `kind: file` framed message into the host. Finds
  the host via the first browser host manifest's `path` field (no baked-in
  paths); items hide when no manifest exists. Single-file only: Telegram's
  forward picker and Viber's clipboard don't stack across a multi-selection.
  Installed as a symlink by `install.sh` (removed by `--uninstall`);
  Nautilus loads extensions at startup, so changes need `nautilus -q`.
- `install.sh` — the extension ID is pinned by the `key` field COMMITTED in
  `extension/manifest.json` (public key only; ID = sha256 of DER pubkey,
  first 32 hex chars mapped 0-9a-f→a-p → `oehfaclnoafdfecmghpojgolkdheebmk`).
  The normal path therefore writes nothing inside the checkout — critical,
  because `omarchy plugin update` runs git pull in the plugin dir. It only
  writes, per detected browser (the `BROWSERS` table: Brave, Chromium —
  detection is `command -v` on the binary), the host manifest into that
  browser's `NativeMessagingHosts/` dir and the `--load-extension` flag
  entry into its flags file, plus the nautilus symlink. The browser config
  paths live in THREE files that must stay in sync: install.sh (`BROWSERS`),
  scripts/plugin-status (probe list), nautilus/yeet.py (`HOST_MANIFESTS`).
  The old generate-key.pem-and-inject path survives as a fallback for forks
  that strip the key. Everything user-level, no sudo.
  **The extension installs with no manual browser steps** (verified
  2026-08 on Brave): install.sh appends the extension dir to the
  `--load-extension=` line in `~/.config/brave-flags.conf` /
  `~/.config/chromium-flags.conf` — the exact mechanism Omarchy uses for
  its own bundled extensions (copy-url, yt-dlp, whatsapp-slim live on the
  brave-flags.conf line; never disturb their entries). Google Chrome
  removed --load-extension from branded builds in 2025 — that's why Chrome
  is NOT in the BROWSERS table (its only path is manual Load-unpacked or
  Web Store publishing); Brave explicitly kept the flag and open-source
  Chromium never lost it (Arch's chromium launcher reads
  chromium-flags.conf). A second `--load-extension=` line would override
  the first (last flag wins), so install.sh appends to the existing line.
  The pinned key keeps the ID stable regardless of load path, so every
  host manifest's allowed_origins always matches. "Load unpacked" is dead
  as the install path; loading the same dir both ways is harmless (same
  ID).

Files land in `SHARE_DIR="${YEET_DIR:-$HOME/Downloads}"`. User
overrides live in `~/.config/omarchy-yeet/config` (plain shell,
sourced by the host near the top, so both the framed-message path and the
`--download` worker re-entry see it); env vars still work for CLI testing but
the browser doesn't inherit the user's shell env, so the config file is the
user-facing mechanism.

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
- **X/Twitter videos** (all verified live 2026-08): video `src` is `blob:` or
  empty, timeline `pageUrl` is `/home` — the only yt-dlp-able URL is the tweet's
  `/status/` URL. `extension/twitter-tweet-url.js` (content script, x.com +
  twitter.com) records the status URL of the tweet under each right-click via
  the timestamp link `a[href*="/status/"]:has(time)`; promoted tweets have no
  timestamp link, only `/status/<id>/analytics`, which the regex trims. X also
  replaces the native context menu on playing videos with its own
  ("Copy video address / Post Video") — the content script suppresses it with a
  capture-phase `stopImmediatePropagation()` at document level inside
  `[data-testid="videoPlayer"]`/`videoComponent`; X's handler is delegated, so
  document-capture wins even when registered late. yt-dlp resolves x.com
  status URLs anonymously (no cookies) and follows quote-tweets to the quoted
  video.
- **Instagram videos** (verified live 2026-08): same shape as X — video `src`
  is `blob:`, home-feed `pageUrl` is bare `instagram.com/`. yt-dlp resolves
  posts and reels anonymously (no cookies) at `/p/<code>`, `/reel/<code>`,
  `/reels/<code>`, and user-scoped variants; everything normalizes to
  `/p/<shortcode>/`. The reels viewer needs no content script — Instagram
  rewrites the URL to `/reels/<id>/` per reel as you scroll, so `pageUrl`
  works. The home feed does not: feed videos are wrapped in their permalink
  anchor (`<a href="/reels/<id>/">`), so right-clicks there are a **link**
  context and `page`/`video` menu items never show — hence the link-scoped
  `tg/vb-video-link` twins (`targetUrlPatterns` on instagram post/reel
  hrefs), with `info.linkUrl` as the primary URL source.
  `extension/instagram-post-url.js` is the fallback: it records the post
  permalink under each right-click via the article's timestamp link
  (`a[href*="/p/"]:has(time)`); `/reels/audio/…` and profile `/user/reels/`
  links are decoys the shortcode regex must reject. Unlike X, Instagram keeps
  the native context menu on videos — no suppression needed. Stories are not
  handled (login-gated in yt-dlp).
- **TikTok videos** (all verified live 2026-08): video `src` is `blob:`,
  home-feed `pageUrl` is bare `tiktok.com/` and is never rewritten while
  scrolling (like X, unlike IG reels). TikTok replaces the native context
  menu on its player with its own (Speed/Quality/Download video/Share) on
  every surface — feed, detail pages, even explore-card previews — so
  without suppression our items never show; same document-capture
  `stopImmediatePropagation()` trick as X, scoped to
  `[id^="xgwrapper-"]`/`video`/`[data-e2e="feed-video"]` (their handler is
  not on document-capture, so ours wins regardless of registration order).
  URL recovery: explore/profile grid cards are wrapped in absolute
  `/@user/video/<id>` anchors (link context → the `-video-link` twins,
  `info.linkUrl`); feed items have NO permalink anchor at all — the player
  wrapper id embeds the video id (`xgwrapper-<n>-<videoid>`) and the
  article's author anchor gives the username, from which
  `tiktok-video-url.js` reconstructs the permalink. yt-dlp resolves TikTok
  anonymously and by id alone — a placeholder username
  (`tiktok.com/@_/video/<id>`) works — and the detail page's own `pageUrl`
  needs no content script. Photo carousels (`/photo/<id>`) are not
  yt-dlp-able: the link twins target only `*/video/*`, and carousel images
  go through the normal image share. When a feed video is paused long
  enough to unmount, its poster `<img>` (regional `tiktokcdn-*.com` CDN)
  takes its place — that right-click is an image context and shares the
  poster frame; accepted edge case.
- **Video quality**: `-S "res:${MAX_HEIGHT},proto,ext:mp4"` (default 720,
  `YEET_MAX_HEIGHT` overrides). 720p because Viber sends files
  through nearly byte-identical (measured: 16.2 MB sent → 15.4 MB received),
  so source size IS the recipient's download; Telegram/Viber compression
  tops out ~720p so higher sources are wasted either way. `proto` prefers
  X's direct https mp4 over its HLS variant; sort-based `-S` never errors
  on sparse format lists (the 240p-only YouTube test video still resolves).

## Testing without the browser

Pipe a framed message straight into the host:

```bash
python3 -c 'import struct,sys,json; m=json.dumps({"app":"telegram","kind":"text","text":"hi"}).encode(); sys.stdout.buffer.write(struct.pack("<I",len(m))+m)' \
  | ./host/yeet-host | od -c   # expect \x02\0\0\0{}
```

Same shape for `file`/`blob`/`video`. Verify visually with
`grim -g "$(hyprctl clients -j | jq -r '...')"` screenshots; drive paste
tests with `wtype -M ctrl -k v -m ctrl`. Test video:
`https://www.youtube.com/watch?v=jNQXAC9IVRw` (19s). Extension changes need
a browser restart (the extension loads via `--load-extension`, read at
startup — and remember the service-worker cache constraint: bump the
background-N.js filename), plus a refresh of any open x.com/tiktok.com tabs
to re-inject the content scripts; host-manifest changes need a browser
restart; host-script changes apply on next right-click. Plugin changes:
see the dev loop in the plugin section below.

## Omarchy shell plugin — built 2026-08, all verified live

The `bar-widget` plugin shipped (see Architecture). Design decisions and
facts learned building it, don't re-derive:

- **bar-widget over menu-kind**: a bar icon + KeyboardPanel popup installs
  discoverable with zero keybind editing (`--enable` puts it in the bar,
  defaultSection right), matches every third-party plugin installed on this
  machine, and `omarchy-shell <id> toggle` still works for keybinds via the
  plugin's own IpcHandler. The menu-kind idea is superseded.
- Third-party QML CAN `import qs.Ui` / `qs.Commons` (costafot.autoduck
  proves it). Copy the widget↔panel wiring from
  `~/.config/omarchy/plugins/agx.screen-time/` — panel shape contract
  (opened/open/close/togglePanel/closeForPopoutSwitch), injectPanel(),
  KeyboardPanel + PanelKeyCatcher, owner: hostWidget for the popout
  coordinator.
- **Dev loop**: `rsync -a --delete --exclude .git --exclude key.pem . \
  ~/.config/omarchy/plugins/costafot.yeet/` then
  `omarchy-restart-shell`. The shell's inotify live-reload fires
  (`Local plugin changed, reloading` in journal) but the running panel kept
  serving the OLD component in testing — restart to be sure. Validate with
  `omarchy plugin validate .` (checks entry points exist, no symlinks
  anywhere in the folder — don't add any).
- `omarchy plugin add` clones the repo, so the plugin only ships what's
  COMMITTED — manifest.json/QML/scripts must be committed before a real
  `plugin add` test works (validation failed on the uncommitted tree,
  expected).
- id `costafot.yeet` (matches the published costafot.autoduck
  convention, not the io.github.* guess from earlier notes). Renamed from
  `costafot.messenger-share` pre-marketplace (2026-08); nothing published
  ever used the old id, but this machine's install did — migrating means
  removing the old plugin id, the old `com.costa.messenger_share.json`
  host manifest, the old `messenger-share.py` nautilus symlink, and the
  old plugin dir's entry on the `--load-extension` line, then re-adding
  the plugin and re-running install.sh.
- Marketplace (HANCORE-linux/omarchy-plugin-marketplace →
  omarchyplugins.com): submission is an issue form (category
  `Productivity`, 1–3 tags); repo needs root README + license (both present
  now) + preview.png (present); listings get an exact-commit security scan.
  Expect scrutiny: the bundled native-messaging host is browser-reachable
  code execution — the README's last Note discloses it deliberately.
  **Still to do: submit the listing.**
- On this machine the installed plugin is a git clone whose origin is the
  local checkout (`~/Work/omarchy-messenger-share`), so
  `omarchy plugin update costafot.yeet` pulls committed local
  work — handy for dev, but remember end users' clones point at GitHub.

## Deferred / ideas

- `viber://forward?text=...` deep link might beat clipboard+focus for
  text/links to Viber — untested.
- A settings `panel` kind (edit `~/.config/omarchy-yeet/config`
  from the shell) remains the stretch goal from the original plan.
