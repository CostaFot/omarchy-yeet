# omarchy-messenger-share

<img src="assets/modern-solutions.jpg" width="300" alt="the architecture diagram">

Right-click share links, images, selected text, and videos from Brave straight
to **Telegram** and **Viber** on [Omarchy](https://omarchy.org). Replaces the
download → open folder → find window → drag-drop routine with one menu click.

## Menu items

<img src="assets/context-menu.png" width="700" alt="the context menu on an X video">

| Right-click on | Menu item | What happens |
|---|---|---|
| Anything | **Share to Telegram / Viber** | Link/text lands on your clipboard, app is focused — Ctrl+V in a chat |
| An image | **Share to Telegram / Viber** | Image is fetched with your login cookies, then: Telegram opens its "Forward to…" chat picker; Viber gets it on your clipboard — Ctrl+V |
| A video or its page | **Download video → Telegram / Viber** | yt-dlp grabs the video (mp4, ≤720p) to `~/Downloads` with live progress in the Omarchy OSD, then hands it off |

Telegram takes files through its native chat picker — pick the friend, done.
Viber has no command line and its input **only** accepts pasted images, so
non-image files (videos mostly) get a Files window opened next to Viber with
the file pre-selected — drag it into the chat. I don't make the rules.

## From Files (Nautilus)

<img src="assets/files-menu.png" width="360" alt="the Files context menu">

The same two items show up when you right-click a file in Files —
`install.sh` sets this up automatically if `nautilus-python` is installed.
Same rules as above: Telegram opens its chat picker, Viber takes images via
clipboard and everything else via drag. One file at a time.

## Requirements

Omarchy (uses `omarchy-launch-or-focus`, `omarchy-notification-send`,
`omarchy-osd`, `omarchy-clipboard-paste-file`), Brave, `telegram-desktop`,
`viber`, `yt-dlp`, `wl-clipboard`, `jq`, `openssl`. Optional:
`nautilus-python` for the Files right-click.

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

`install.sh` generates a local `key.pem` (gitignored) that pins the extension
ID, and writes two things outside the repo: the Brave native-host manifest in
`~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/` and a symlink
for the Files extension in `~/.local/share/nautilus-python/extensions/`
(restart Files with `nautilus -q` to pick it up). No sudo, nothing
system-wide.

## Uninstall

```bash
./install.sh --uninstall
```

Then remove the extension in `brave://extensions` and delete this folder.

## Notes

- Video downloads work anywhere yt-dlp does. Tested daily: YouTube, X/Twitter,
  Instagram, TikTok.
- On X/Twitter, right-click a video or anywhere on its tweet — the extension
  figures out which tweet you clicked, even from the timeline. X's own video
  menu is suppressed so the browser menu can show.
- Instagram works from the home feed, the reels viewer, and open posts.
  Stories are login-gated and not supported.
- TikTok works from the For You feed, the explore and profile grids, and open
  videos. TikTok's own right-click menu (Speed / Quality / Download…) is
  suppressed the same way. Photo carousels aren't videos — share those as
  images.
- On YouTube, the first right-click on the player shows YouTube's own menu;
  right-click a second time for the browser menu.
- Videos are capped at 720p because Viber passes files through nearly
  unchanged — every extra pixel is bytes your friends download — and the apps'
  own compression tops out around 720p anyway.
- Downloaded media stays in `~/Downloads`.
- Both are overridable in `~/.config/omarchy-messenger-share/config`
  (plain shell, sourced by the host — takes effect on the next share):

  ```sh
  MESSENGER_SHARE_DIR="$HOME/Videos/shares"
  MESSENGER_SHARE_MAX_HEIGHT=1080
  ```
- Downloads run as a transient systemd user unit — closing Brave mid-download
  doesn't kill them.
- Images with `blob:` URLs can't be fetched and show a "Share failed"
  notification (rare).
