import json
import os
import struct

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, GLib, Nautilus

# The Brave host manifest is the single source of truth for where the host
# script lives — install.sh writes it, and reading it here means this file
# needs no path baked in at install time.
HOST_MANIFEST = os.path.join(
    GLib.get_user_config_dir(),
    "BraveSoftware/Brave-Browser/NativeMessagingHosts/com.costa.messenger_share.json",
)


class MessengerShareAction(GObject.GObject, Nautilus.MenuProvider):
    def _host_path(self):
        try:
            with open(HOST_MANIFEST) as f:
                path = json.load(f).get("path")
        except (OSError, ValueError):
            return None
        if path and os.access(path, os.X_OK):
            return path
        return None

    def _send(self, app, path):
        host = self._host_path()
        if not host:
            return

        # Same framing the browser uses: 4-byte LE length prefix + JSON.
        payload = json.dumps({"app": app, "kind": "file", "path": path}).encode()
        process = Gio.Subprocess.new(
            [host],
            Gio.SubprocessFlags.STDIN_PIPE
            | Gio.SubprocessFlags.STDOUT_SILENCE
            | Gio.SubprocessFlags.STDERR_SILENCE,
        )
        stdin = process.get_stdin_pipe()
        stdin.write_all(struct.pack("<I", len(payload)) + payload, None)
        stdin.close(None)

    def _selected_file(self, files):
        # Single files only: the host dispatches one file per message, and the
        # per-file flows (Telegram's forward picker, Viber's clipboard) don't
        # stack usefully across a multi-selection.
        if len(files) != 1:
            return None

        location = files[0].get_location()
        path = location.get_path() if location else None
        if path and os.path.isfile(path):
            return path
        return None

    def _make_item(self, name, label, icon, app, path):
        item = Nautilus.MenuItem(name=name, label=label, icon=icon)
        item.connect("activate", self._on_activate, app, path)
        return item

    def _on_activate(self, _menu, app, path):
        self._send(app, path)

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]
        path = self._selected_file(files)

        if not path or not self._host_path():
            return []

        return [
            self._make_item(
                "MessengerShare::telegram",
                "Share to Telegram",
                "org.telegram.desktop",
                "telegram",
                path,
            ),
            self._make_item(
                "MessengerShare::viber",
                "Share to Viber",
                "viber",
                "viber",
                path,
            ),
        ]
