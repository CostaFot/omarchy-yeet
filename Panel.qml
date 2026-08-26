import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Popup for the Yeet bar widget: clipboard / file / video rows
// per messenger, plus a setup row for the optional browser right-click half.
// Every action closes the panel and hands off to scripts/plugin-share; the
// panel itself never talks to Telegram or Viber.
Panel {
  id: root
  moduleName: "costafot.yeet"

  property var anchorItem: null
  property var hostWidget: null
  // The bar tracks the widget mounted in its slot — BarWidget.qml — so the
  // popout coordinator and panel switching must identify us by that widget.
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: {
    var dir = Qt.resolvedUrl(".").toString()
    return dir.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string omarchyBin: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin"

  // Environment probe (scripts/plugin-status): which messengers exist,
  // whether yt-dlp is there for the video rows, and whether the browser
  // half is installed. Re-probed on every open so a just-installed app
  // shows up without a shell restart.
  property var status: ({ telegram: true, viber: true, ytdlp: true, extension: true })

  property int selectedIndex: -1

  readonly property var rows: {
    var s = root.status
    var out = []
    var apps = []
    if (s.telegram) apps.push({ key: "telegram", label: "Telegram" })
    if (s.viber) apps.push({ key: "viber", label: "Viber" })
    for (var i = 0; i < apps.length; i++) {
      if (i > 0) out.push({ type: "sep" })
      out.push({ type: "header", label: apps[i].label })
      out.push({ type: "action", icon: "󰅍", label: "Clipboard",
                 app: apps[i].key, mode: "clipboard" })
      out.push({ type: "action", icon: "󰈔", label: "File…",
                 app: apps[i].key, mode: "file" })
      if (s.ytdlp)
        out.push({ type: "action", icon: "󰕧", label: "Video from copied link",
                   detail: "Runs yt-dlp on the link you copied",
                   app: apps[i].key, mode: "video" })
    }
    if (apps.length === 0)
      out.push({ type: "note", label: "No messenger to share to",
                 detail: "Install Telegram (telegram-desktop) or Viber, then reopen this panel." })
    if (!s.extension) {
      out.push({ type: "sep" })
      out.push({ type: "action", icon: "󰖟", label: "Set up browser sharing…",
                 detail: "Right-click share in the browser and Files",
                 action: "setup" })
    }
    return out
  }

  function firstActionIndex() {
    for (var i = 0; i < rows.length; i++) if (rows[i].type === "action") return i
    return -1
  }

  onRowsChanged: selectedIndex = firstActionIndex()

  function moveCursor(dy) {
    var actionable = []
    for (var i = 0; i < rows.length; i++) if (rows[i].type === "action") actionable.push(i)
    if (actionable.length === 0) return
    var pos = actionable.indexOf(selectedIndex)
    if (pos === -1) pos = dy > 0 ? -1 : 0
    pos = (pos + dy + actionable.length) % actionable.length
    selectedIndex = actionable[pos]
  }

  function activate(row) {
    if (!row || row.type !== "action") return
    root.close()
    if (row.action === "setup")
      Quickshell.execDetached([root.omarchyBin + "/omarchy-launch-floating-terminal-with-presentation",
                               root.pluginDir + "/install.sh"])
    else
      Quickshell.execDetached([root.pluginDir + "/scripts/plugin-share", row.app, row.mode])
  }

  onOpenedChanged: {
    if (opened) {
      statusProc.running = true
      selectedIndex = firstActionIndex()
    }
  }

  Component.onCompleted: statusProc.running = true

  Process {
    id: statusProc
    command: [root.pluginDir + "/scripts/plugin-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.status = JSON.parse(text) } catch (e) {
          console.warn("costafot.yeet: bad status probe output:", text)
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      clip: true
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activate(root.rows[root.selectedIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.rows

          delegate: Item {
            id: rowItem
            required property var modelData
            required property int index

            readonly property bool isAction: modelData.type === "action"
            readonly property bool hasCursor: isAction && index === root.selectedIndex
            readonly property bool twoLine: !!modelData.detail

            width: contentColumn.width
            height: modelData.type === "sep" ? Style.space(11)
              : modelData.type === "header" ? headerLabel.implicitHeight + Style.space(8)
              : modelData.type === "note" ? noteColumn.implicitHeight + Style.space(12)
              : twoLine ? Style.space(44) : Style.space(32)

            PanelSeparator {
              visible: rowItem.modelData.type === "sep"
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.contentForeground
            }

            PanelSectionHeader {
              id: headerLabel
              visible: rowItem.modelData.type === "header"
              text: rowItem.modelData.type === "header" ? rowItem.modelData.label : ""
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(2)
            }

            Column {
              id: noteColumn
              visible: rowItem.modelData.type === "note"
              width: parent.width
              spacing: Style.space(3)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                width: parent.width
                text: rowItem.modelData.label || ""
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }

              Text {
                width: parent.width
                text: rowItem.modelData.detail || ""
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }

            Rectangle {
              visible: rowItem.isAction
              anchors.fill: parent
              radius: Style.space(4)
              color: rowItem.hasCursor ? Color.menu.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(9)

                Text {
                  width: Style.space(18)
                  height: parent.height
                  text: rowItem.modelData.icon || ""
                  color: rowItem.hasCursor ? Color.menu.selectedText : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }

                Column {
                  width: parent.width - Style.space(18) - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: rowItem.modelData.label || ""
                    color: rowItem.hasCursor ? Color.menu.selectedText : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: rowItem.twoLine
                    width: parent.width
                    text: rowItem.modelData.detail || ""
                    color: rowItem.hasCursor
                      ? Qt.darker(Color.menu.selectedText, 1.25)
                      : Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.selectedIndex = rowItem.index
                onClicked: root.activate(rowItem.modelData)
              }
            }
          }
        }
      }
    }
  }
}
