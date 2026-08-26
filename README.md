# Yeet

<img src="assets/modern-solutions.jpg" width="300" alt="the architecture diagram">

Share to **Telegram** and **Viber** on [Omarchy](https://omarchy.org): a bar
widget for your clipboard, files, and video links, plus right-click share in
Brave and Files. Replaces the download → open folder → find window →
drag-drop routine with one click.

## The bar widget

<img src="preview.png" width="410" alt="the share panel">

```bash
omarchy plugin add https://github.com/CostaFot/omarchy-yeet --enable
```

That puts a 󰒊 icon in the bar. Click it (or `omarchy-shell
costafot.yeet toggle` from a keybinding) and pick a row:

| Row | What happens |
|---|---|
| **Clipboard** | Text/link: the app is focused, paste in a chat — it's already on your clipboard. An image (screenshots): saved and sent like any image share |
| **File…** | File chooser opens, pick one, it's handed to the app |
| **Video from copied link** | yt-dlp grabs the video (mp4, ≤720p) from the URL you copied, with live progress in the Omarchy OSD, then hands it off |

Rows only show for apps you actually have installed. The **Set up browser
sharing…** row at the bottom appears until the Brave half below is installed,
and runs the installer for you.

Every row is also a command, so you can skip the panel entirely from a
keybinding or script:

```bash
omarchy-shell costafot.yeet share telegram clipboard
omarchy-shell costafot.yeet share viber video   # yt-dlp on the copied link
```

`share <telegram|viber> <clipboard|file|video>` — same actions as the rows.

And `send` takes the payload right on the command line — no picker, no
clipboard — so scripts and AI agents can drive shares end to end:

```bash
omarchy-shell costafot.yeet send telegram text "meeting moved to 3pm"
omarchy-shell costafot.yeet send telegram file ~/Downloads/report.pdf
omarchy-shell costafot.yeet send viber video https://x.com/i/status/123456
```

`send <telegram|viber> <text|file|video> <payload>`. The same works
without the shell: `scripts/plugin-share <app> <mode> [payload]`.

Telegram takes files through its native chat picker — pick the friend, done.
Viber has no command line and its input **only** accepts pasted images, so
non-image files (videos mostly) get a Files window opened next to Viber with
the file pre-selected — drag it into the chat. I don't make the rules.

## From Brave

<img src="assets/context-menu.png" width="700" alt="the context menu on an X video">

| Right-click on | Menu item | What happens |
|---|---|---|
| Anything | **Share to Telegram / Viber** | Link/text lands on your clipboard, app is focused — Ctrl+V in a chat |
| An image | **Share to Telegram / Viber** | Image is fetched with your login cookies, then: Telegram opens its "Forward to…" chat picker; Viber gets it on your clipboard — Ctrl+V |
| A video or its page | **Download video → Telegram / Viber** | Same yt-dlp flow as the bar widget |

## From Files (Nautilus)

<img src="assets/files-menu.png" width="360" alt="the Files context menu">

The same two items show up when you right-click a file in Files —
`install.sh` sets this up automatically if `nautilus-python` is installed.
Same rules as above: Telegram opens its chat picker, Viber takes images via
clipboard and everything else via drag. One file at a time.

## Requirements

Omarchy (uses `omarchy-launch-or-focus`, `omarchy-notification-send`,
`omarchy-osd`, `omarchy-clipboard-paste-file`, `omarchy-file-select`),
`telegram-desktop` and/or `viber`, `yt-dlp`, `wl-clipboard`, `jq`. Optional:
Brave for the right-click share, `nautilus-python` for the Files right-click.

## Install

The plugin route above is the whole install for the bar widget — the share
backend is bundled in the plugin.

The Brave + Files half needs one more step, either from the panel's **Set up
browser sharing…** row or by hand:

```bash
~/.config/omarchy/plugins/costafot.yeet/install.sh
```

Then restart Brave. That's it — no developer mode, no Load unpacked.

`install.sh` writes three things outside the repo: the Brave native-host
manifest in `~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/`,
a `--load-extension` entry in `~/.config/brave-flags.conf` (the same
mechanism Omarchy uses to ship its own browser extensions — the extension
shows up in `brave://extensions` on the next start), and a symlink for the
Files extension in `~/.local/share/nautilus-python/extensions/` (restart
Files with `nautilus -q` to pick it up). No sudo, nothing system-wide. Not
on Omarchy's plugin system? A plain `git clone` + `./install.sh` works the
same, minus the bar widget.

## Uninstall

```bash
~/.config/omarchy/plugins/costafot.yeet/install.sh --uninstall
omarchy plugin remove costafot.yeet
```

Then restart Brave — the extension unloads with the flag.

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
- Both are overridable in `~/.config/omarchy-yeet/config`
  (plain shell, sourced by the host — takes effect on the next share):

  ```sh
  YEET_DIR="$HOME/Videos/shares"
  YEET_MAX_HEIGHT=1080
  ```
- Downloads run as a transient systemd user unit — closing Brave mid-download
  doesn't kill them.
- Images with `blob:` URLs can't be fetched and show a "Share failed"
  notification (rare).
- Heads up for the security-minded: the browser extension talks to a
  native-messaging host — a bash script on your machine that Brave is allowed
  to start. That's the entire mechanism, it's ~200 lines, and it's in
  [`host/yeet-host`](host/yeet-host). Read it before
  installing; that's what it's there for.
