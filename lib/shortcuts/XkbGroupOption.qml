import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "ShortcutFormat.js" as ShortcutFormat

Item {
  id: root

  property string effectiveOptions: ""
  property string xkbOptionDescriptions: ""
  property bool refreshPending: false
  readonly property string option:
    ShortcutFormat.groupOptionFrom(effectiveOptions)
  readonly property string label: ShortcutFormat.describeGroupOption(
    option, xkbOptionDescriptions)

  visible: false
  width: 0
  height: 0

  function refresh() {
    if (optionsProcess.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    optionsProcess.running = true
  }

  function updateOptions(raw) {
    try {
      root.effectiveOptions = String(JSON.parse(raw || "{}").str || "")
    } catch (error) {
      root.effectiveOptions = ""
    }
  }

  Component.onCompleted: Qt.callLater(root.refresh)

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name || "") === "configreloaded")
        root.refresh()
    }
  }

  Process {
    id: optionsProcess
    command: ["hyprctl", "-j", "getoption", "input:kb_options"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateOptions(text)
    }
    onExited: if (root.refreshPending) Qt.callLater(root.refresh)
  }

  FileView {
    path: "/usr/share/X11/xkb/rules/evdev.lst"
    printErrors: false
    onLoaded: root.xkbOptionDescriptions = text()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
