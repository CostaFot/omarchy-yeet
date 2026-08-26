import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Bar widget: one share icon whose popup (Panel.qml) lists the share actions
// for Telegram and Viber. All real work happens in scripts/plugin-share,
// which pipes the same framed messages the browser extension sends into the
// bundled native-messaging host (host/yeet-host).
BarWidget {
  id: root
  moduleName: "costafot.yeet"

  readonly property string glyph: "󰒊"

  readonly property string pluginDir: {
    var dir = Qt.resolvedUrl(".").toString()
    return dir.replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  // ---- Panel shape contract for shell.summon/hide/toggle routing ---------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // execDetached swallows plugin-share's stderr, so validate here where the
  // caller sees the reply. IPC arity is strict (no optional args), hence the
  // share/send split below.
  function runShare(app, kind, payload) {
    if (app !== "telegram" && app !== "viber"
        || kind !== "clipboard" && kind !== "text"
           && kind !== "file" && kind !== "video"
        || kind === "text" && payload === ""
        || kind === "clipboard" && payload !== "")
      return "usage: share <telegram|viber> <clipboard|file|video>\n"
           + "       send <telegram|viber> <text|file|video> <payload>"
    var cmd = [root.pluginDir + "/scripts/plugin-share", app, kind]
    if (payload !== "") cmd.push(payload)
    Quickshell.execDetached(cmd)
    return "sharing " + kind + " to " + app
  }

  // Direct IPC target, so a Hyprland keybinding can summon the panel:
  //   omarchy-shell costafot.yeet toggle
  // and share actions work headless, without opening the panel:
  //   omarchy-shell costafot.yeet share telegram clipboard
  //   omarchy-shell costafot.yeet send telegram file /path/to/report.pdf
  IpcHandler {
    target: "costafot.yeet"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }

    // The interactive modes the panel rows run (file picker, clipboard).
    function share(app: string, kind: string): string {
      return root.runShare(app, kind, "")
    }
    // Explicit payload — a message, a path, a URL — so scripts and AI
    // agents can share without a human at the picker or the clipboard.
    function send(app: string, kind: string, payload: string): string {
      return root.runShare(app, kind, payload)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: "Share to…"
    onPressed: root.togglePanel()
  }
}
