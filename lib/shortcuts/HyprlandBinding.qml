import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "ShortcutFormat.js" as ShortcutFormat

Item {
  id: root

  property string actionDescription: ""
  property string loadingLabel: "..."
  property string notConfiguredLabel: "Unbound"
  property string resolvedLabel: ""
  property bool resolved: false
  property bool refreshPending: false
  property bool componentReady: false
  readonly property string label: !resolved
    ? loadingLabel
    : (resolvedLabel !== "" ? resolvedLabel : notConfiguredLabel)

  visible: false
  width: 0
  height: 0

  function refresh() {
    if (bindingsProcess.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    bindingsProcess.running = true
  }

  function updateBindings(raw) {
    try {
      var bindings = JSON.parse(raw || "[]")
      var binding = ShortcutFormat.findBinding(
        bindings, root.actionDescription)
      root.resolvedLabel = ShortcutFormat.bindingLabel(binding)
    } catch (error) {
      root.resolvedLabel = ""
    }
    root.resolved = true
  }

  onActionDescriptionChanged: if (componentReady) root.refresh()
  Component.onCompleted: {
    componentReady = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name || "") === "configreloaded")
        root.refresh()
    }
  }

  Process {
    id: bindingsProcess
    command: ["hyprctl", "-j", "binds"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBindings(text)
    }
    onExited: if (root.refreshPending) Qt.callLater(root.refresh)
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
