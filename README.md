# omarchy-messenger-share

Right-click share links, images, selected text, and videos from Brave straight to **Telegram** and **Viber** on [Omarchy](https://omarchy.org).

No more download → open folder → drag-drop. Right-click, pick a target, done.

## What each menu item does

| Right-click on | Menu item | What happens |
|---|---|---|
| Anything | **Share to Telegram** | Link/text lands on your clipboard and Telegram is focused — paste with Ctrl+V |
| Anything | **Share to Viber** | Same, with Viber focused |
| An image | **Share to Telegram / Viber** | Image is downloaded via the browser (works behind logins), then: Telegram opens its "Forward to…" chat picker with the file; Viber gets the image on your clipboard — Ctrl+V in a chat |
| A video or its page | **Download video → Telegram / Viber** | yt-dlp downloads the video (mp4, ≤1080p) to `~/Downloads` with live progress in the Omarchy OSD, then hands it off the same way |

Telegram file shares open the native chat picker — pick the friend and it sends.
Viber has no command-line interface at all, so files/images are placed on the
clipboard and the app is focused; you press Ctrl+V in the chat.

## Requirements

Omarchy (uses `omarchy-launch-or-focus`, `omarchy-notification-send`, `omarchy-osd`,
`omarchy-clipboard-paste-file`), Brave, `telegram-desktop`, `viber`, `yt-dlp`,
`wl-clipboard`, `jq`, `openssl`.

## Install

```bash
git clone https://github.com/CostaFot/omarchy-messenger-share.git
cd omarchy-messenger-share
./install.sh
```

Then:

1. Open `brave://extensions`, enable **Developer mode**
2. **Load unpacked** → select the `extension/` folder
3. Check the extension ID matches the one `install.sh` printed
4. Restart Brave once (native-host manifests are read at startup)

`install.sh` generates a local `key.pem` (gitignored) that pins the extension ID,
and writes one file outside the repo:
`~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.costa.messenger_share.json`.
No sudo, nothing system-wide.

## Uninstall

```bash
./install.sh --uninstall
```

Then remove the extension in `brave://extensions` and delete this folder.

## Notes

- Downloaded media stays in `~/Downloads` (override with `MESSENGER_SHARE_DIR` —
  set it in the environment Brave inherits, e.g. via uwsm env).
- On YouTube, the first right-click on the player shows YouTube's own menu;
  right-click a second time for the browser menu. Right-clicking the page
  outside the player works too.
- On X/Twitter, right-click a video (or anywhere on its tweet) and pick
  **Download video** — the extension figures out which tweet you clicked, even
  from the timeline. X's own video menu is suppressed so the browser menu shows.
- Video downloads run as a transient systemd user unit, so closing Brave
  mid-download doesn't kill them.
- Images with `blob:` URLs can't be fetched and will show a "Share failed"
  notification (rare).
- If Viber rejects a Ctrl+V paste (e.g. for video files), the file is already in
  `~/Downloads` — attach it manually with the paperclip.

## How it works

`extension/` is a Manifest V3 extension that only builds the context menus and
hands `{app, kind, payload}` to `host/messenger-share-host` over Chrome native
messaging. The host (bash, modeled on Omarchy's own `omarchy-chromium-*-host`
scripts) does everything else: clipboard, window focus, yt-dlp, notifications.
