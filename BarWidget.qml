import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "lib/shortcuts" as Shortcuts
import "lib/UpdateInterval.js" as UpdateInterval

Panel {
  id: root
  moduleName: "ilyazar.btop"
  ipcTarget: moduleName

  property string page: "main"
  property int mainIndex: 0
  property int settingsIndex: 0
  property string customIconDraft: ""
  property string customIconError: ""
  property bool customIconLoadFailed: false
  property string updateDraft: "2000"
  property bool updateEditing: false
  property string pendingLaunch: ""
  property bool configSynced: false

  readonly property var activity: bar && bar.shell
    ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string iconStyle: String(setting("iconStyle", "CPU"))
  readonly property string iconGlyph: iconStyle === "CPU" ? "󰍛" : ""
  readonly property string customIconPath: String(setting("customIconPath", ""))
  readonly property string customIconUrl: resolveIconPath(customIconPath)
  readonly property string keybindingsScript: localPath(
    Qt.resolvedUrl("open-keybindings.sh"))
  readonly property string windowMode: String(setting("windowMode", "Floating"))
  readonly property int updateMs: intSetting(
    "updateMs", 2000, UpdateInterval.minimum, UpdateInterval.maximum)
  readonly property var updateDraftValue: UpdateInterval.parse(updateDraft)
  readonly property bool updateDraftInvalid: updateEditing
    && updateDraftValue === null
  readonly property bool updateAvailable: activity && activity.configReady
    && !activity.configBusy
  readonly property string procSorting:
    String(setting("procSorting", "cpu lazy"))
  readonly property bool procTree: setting("procTree", false) === true
  readonly property string btopAppId: windowMode === "Tiled"
    ? "org.omarchy.btop_tiled" : "org.omarchy.btop"
  readonly property bool customIconInvalid: iconStyle === "Custom"
    && (customIconUrl === "" || customIconLoadFailed)
  readonly property string cpuTemperatureSuffix:
    activity && activity.cpuTemperature >= 0
      ? " • " + Math.round(activity.cpuTemperature) + "°C" : ""
  readonly property string gpuUsageText:
    activity && activity.gpuUsage >= 0
      ? Math.round(activity.gpuUsage) + "%" : "--"
  readonly property bool gpuTemperatureAvailable:
    activity && activity.gpuTemperature >= 0
  readonly property string gpuTemperatureText: gpuTemperatureAvailable
    ? Math.round(activity.gpuTemperature) + "°C" : "<unavailable>"
  readonly property string tooltip: styledTooltip(alignedTooltip(
    customIconInvalid ? "Custom icon" : (activity && activity.available
      ? "RAM: " + Math.round(activity.memoryUsage) + "%" : "RAM: --"),
    customIconInvalid ? "Unavailable" : (activity && activity.available
      ? "CPU: " + Math.round(activity.cpuUsage) + "%" + cpuTemperatureSuffix
      : "CPU: --"),
    "GPU: " + gpuUsageText + " • " + gpuTemperatureText
  ))
  readonly property var sortingChoices: [
    "cpu lazy", "cpu direct", "memory", "program"
  ]
  readonly property int customPathIndex: iconStyle === "Custom" ? 1 : -1
  readonly property int keybindingsIndex: iconStyle === "Custom" ? 2 : 1
  readonly property int windowModeIndex: keybindingsIndex + 1
  readonly property int updateIndex: windowModeIndex + 1
  readonly property int sortingIndex: updateIndex + 1
  readonly property int treeIndex: updateIndex + 2
  readonly property int backIndex: updateIndex + 3
  readonly property int settingsCount: backIndex + 1

  Shortcuts.HyprlandBinding {
    id: activityBinding
    actionDescription: "Activity"
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function padLeft(value, width) {
    var text = String(value)
    while (text.length < width) text = " " + text
    return text
  }

  function padRight(value, width) {
    var text = String(value)
    while (text.length < width) text += " "
    return text
  }

  function alignedTooltip(firstMetric, secondMetric, thirdMetric) {
    return padRight(firstMetric, 27) + "    "
      + padLeft("Left click: btop", 17)
      + "\n" + padRight(secondMetric, 27) + "    "
      + padLeft("Right click: menu", 17)
      + "\n" + padRight(thirdMetric, 48)
  }

  function styledTooltip(value) {
    if (gpuTemperatureAvailable) return value
    var escaped = String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
    return "<pre>" + escaped.replace(
      "&lt;unavailable&gt;",
      "<font color=\"" + String(Qt.darker(Color.tooltip.text, 1.7))
        + "\">&lt;unavailable&gt;</font>"
    ) + "</pre>"
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }

  function resolveIconPath(path) {
    var value = String(path || "").trim()
    if (value.indexOf("~/") === 0)
      value = Quickshell.env("HOME") + value.substring(1)
    if (value.indexOf("file://") === 0) return value
    if (value.indexOf("/") === 0) {
      var parts = value.split("/")
      for (var i = 0; i < parts.length; i++)
        parts[i] = encodeURIComponent(parts[i])
      return "file://" + parts.join("/")
    }
    return ""
  }

  function launchWhenConfigReady(action) {
    if (!activity) return
    if (!activity.configExists) {
      pendingLaunch = action
      configSynced = false
      syncBtopConfig()
      return
    }
    pendingLaunch = ""
    if (action === "help") execBtopHelp()
    else execBtop()
  }

  function execBtop() {
    Quickshell.execDetached([
      "omarchy-launch-or-focus-tui", "--app-id=" + btopAppId,
      "btop", "--config", activity.configPath
    ])
  }

  function execBtopHelp() {
    if (!activity) return
    Quickshell.execDetached([
      "bash", "-lc",
      "omarchy-launch-or-focus-tui --app-id=" + btopAppId
        + " btop --config " + shellQuote(activity.configPath) + " "
        + ">/dev/null 2>&1 & "
        + "for _ in {1..30}; do "
        + "if hyprctl clients -j | jq -e "
        + "'.[] | select(.class == \"" + btopAppId + "\")' "
        + ">/dev/null; then "
        + "sleep 0.6; "
        + "hyprctl dispatch "
        + "'hl.dsp.send_key_state({ mods = \"SHIFT\", key = \"slash\", "
        + "state = \"down\", window = \"class:" + btopAppId + "\" })' "
        + ">/dev/null; sleep 0.05; hyprctl dispatch "
        + "'hl.dsp.send_key_state({ mods = \"SHIFT\", key = \"slash\", "
        + "state = \"up\", window = \"class:" + btopAppId + "\" })' "
        + ">/dev/null; "
        + "exit; fi; sleep 0.1; done"
    ])
  }

  function launchBtop() {
    close()
    launchWhenConfigReady("btop")
  }

  function launchBtopHelp() {
    close()
    launchWhenConfigReady("help")
  }

  function launchKeybindings() {
    close()
    Quickshell.execDetached(["bash", keybindingsScript])
  }

  function showSettings() {
    page = "settings"
    settingsIndex = 0
    customIconDraft = customIconPath
    customIconError = ""
    updateDraft = String(updateMs)
    updateEditing = false
    activityBinding.refresh()
  }

  function showMain() {
    page = "main"
    mainIndex = 0
  }

  function persistPluginSetting(name, value) {
    if (!bar || !bar.shell
        || typeof bar.shell.updateEntryInline !== "function") return
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry[name] = value
    settings = entry
    bar.shell.updateEntryInline(moduleName, entry)
  }

  function applyUpdateValue(value) {
    var parsed = UpdateInterval.parse(value)
    if (parsed === null) return false
    updateDraft = String(parsed)
    if (parsed !== updateMs) persistPluginSetting("updateMs", parsed)
    return true
  }

  function startUpdateEditing() {
    if (!updateAvailable) return
    updateDraft = String(updateMs)
    updateEditing = true
    updateField.forceActiveFocus()
    updateField.selectAll()
  }

  function finishUpdateEditing(apply, restoreFocus) {
    if (!updateEditing) return
    var parsed = UpdateInterval.parse(updateDraft)
    updateEditing = false
    if (apply && parsed !== null) applyUpdateValue(parsed)
    else updateDraft = String(updateMs)
    updateField.focus = false
    if (restoreFocus) keyCatcher.forceActiveFocus()
  }

  function currentUpdateDraft() {
    var parsed = UpdateInterval.parse(updateDraft)
    return parsed === null ? updateMs : parsed
  }

  function nudgeUpdateDraft(direction) {
    updateDraft = String(UpdateInterval.nudge(currentUpdateDraft(), direction))
    updateField.selectAll()
  }

  function ladderUpdateDraft(direction) {
    updateDraft = String(UpdateInterval.ladder(currentUpdateDraft(), direction))
    updateField.selectAll()
  }

  function clickUpdateLadder(direction) {
    var next = UpdateInterval.ladder(currentUpdateDraft(), direction)
    applyUpdateValue(next)
    if (updateEditing) {
      updateField.forceActiveFocus()
      updateField.selectAll()
    }
  }

  function syncBtopConfig() {
    if (!activity || configSynced || activity.configBusy) return
    configSynced = true
    if (!activity.setConfig(updateMs, procSorting, procTree))
      configSynced = false
  }

  function applyWindowMode(mode) {
    var action = mode === "Tiled" ? "tile" : "float"
    var appIds = ["org.omarchy.btop", "org.omarchy.btop_tiled"]
    for (var i = 0; i < appIds.length; i++) {
      var window = "class:" + appIds[i]
      var command = "hl.dispatch(hl.dsp.window.float({ action = \""
        + action + "\", window = \"" + window + "\" }))"
      if (mode === "Floating") {
        command += "; hl.dispatch(hl.dsp.window.resize({ x = 875, y = 600, "
          + "relative = false, window = \"" + window + "\" }))"
          + "; hl.dispatch(hl.dsp.window.center({ window = \""
          + window + "\" }))"
      }
      Quickshell.execDetached([
        "hyprctl", "eval", command
      ])
    }
  }

  function saveCustomIconPath() {
    var value = customIconDraft.trim()
    if (resolveIconPath(value) === "") {
      customIconError = "Use an absolute path, ~/path, or file:// URL."
      return
    }
    customIconError = ""
    customIconLoadFailed = false
    persistPluginSetting("customIconPath", value)
    customIconField.focus = false
    keyCatcher.forceActiveFocus()
  }

  function nextChoice(choices, current, direction) {
    var index = choices.indexOf(current)
    if (index < 0) return direction > 0 ? choices[0] : choices[choices.length - 1]
    return choices[(index + direction + choices.length) % choices.length]
  }

  function cycleSetting(index, direction) {
    if (index === 0) {
      persistPluginSetting(
        "iconStyle",
        nextChoice(["Meters", "CPU", "Pulse", "Custom"], iconStyle, direction)
      )
      return
    }
    if (index === windowModeIndex) {
      var mode = nextChoice(["Floating", "Tiled"], windowMode, direction)
      applyWindowMode(mode)
      persistPluginSetting("windowMode", mode)
      return
    }
    if (!activity || activity.configBusy) return
    if (index === updateIndex) {
      if (!updateAvailable) return
      applyUpdateValue(UpdateInterval.ladder(updateMs, direction))
    } else if (index === sortingIndex) {
      persistPluginSetting(
        "procSorting", nextChoice(sortingChoices, procSorting, direction)
      )
    } else if (index === treeIndex) {
      persistPluginSetting("procTree", !procTree)
    }
  }

  function moveCursor(dx, dy) {
    if (page === "main") {
      if (dy !== 0) mainIndex = (mainIndex + dy + 3) % 3
      return
    }
    if (dy !== 0)
      settingsIndex = (settingsIndex + dy + settingsCount) % settingsCount
    if (dx !== 0 && settingsIndex !== customPathIndex
        && settingsIndex !== keybindingsIndex
        && settingsIndex < backIndex)
      cycleSetting(settingsIndex, dx > 0 ? 1 : -1)
  }

  function activateCursor() {
    if (page === "main") {
      if (mainIndex === 0) launchBtop()
      else if (mainIndex === 1) showSettings()
      else launchBtopHelp()
      return
    }
    if (settingsIndex === backIndex) showMain()
    else if (settingsIndex === keybindingsIndex) launchKeybindings()
    else if (settingsIndex === customPathIndex)
      customIconField.forceActiveFocus()
    else if (settingsIndex === updateIndex) startUpdateEditing()
    else cycleSetting(settingsIndex, 1)
  }

  function closeOrBack() {
    if (page === "settings") showMain()
    else close()
  }

  function sortingLabel(value) {
    if (value === "cpu lazy") return "CPU (lazy)"
    if (value === "cpu direct") return "CPU (direct)"
    if (value === "memory") return "Memory"
    if (value === "program") return "Program"
    return value
  }

  onCustomIconPathChanged: if (!customIconField.activeFocus)
    customIconDraft = customIconPath
  onUpdateMsChanged: {
    if (!updateEditing) updateDraft = String(updateMs)
    configSynced = false
    syncBtopConfig()
  }
  onProcSortingChanged: {
    configSynced = false
    syncBtopConfig()
  }
  onProcTreeChanged: {
    configSynced = false
    syncBtopConfig()
  }
  onActivityChanged: {
    configSynced = false
    syncBtopConfig()
  }

  Connections {
    target: root.activity
    function onConfigBusyChanged() {
      Qt.callLater(root.syncBtopConfig)
    }
    function onConfigExistsChanged() {
      if (root.pendingLaunch !== "" && root.activity && root.activity.configExists)
        root.launchWhenConfigReady(root.pendingLaunch)
    }
  }
  Component.onCompleted: Qt.callLater(root.syncBtopConfig)
  onOpenedChanged: {
    if (opened) {
      showMain()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else if (updateEditing) {
      finishUpdateEditing(true, false)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    tooltipText: root.tooltip
    iconComponent: Component {
      Item {
        ActivityIcon {
          anchors.centerIn: parent
          visible: root.iconStyle === "Meters"
          iconSize: Style.space(14)
          cpuUsage: root.activity ? root.activity.cpuUsage : 0
          memoryUsage: root.activity ? root.activity.memoryUsage : 0
          color: root.foreground
          opacity: root.activity && root.activity.available ? 1 : 0.4
        }

        Image {
          anchors.centerIn: parent
          visible: root.iconStyle === "Custom" && root.customIconUrl !== ""
          width: Style.space(14)
          height: width
          source: root.customIconUrl
          sourceSize.width: 32
          sourceSize.height: 32
          fillMode: Image.PreserveAspectFit
          smooth: true
          onSourceChanged: root.customIconLoadFailed = false
          onStatusChanged: {
            if (status === Image.Error) root.customIconLoadFailed = true
            else if (status === Image.Ready) root.customIconLoadFailed = false
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.iconStyle === "CPU" || root.iconStyle === "Pulse"
          text: root.iconGlyph
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        Text {
          anchors.centerIn: parent
          visible: root.customIconInvalid
          text: "!"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          font.bold: true
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.launchBtop()
      else if (buttonCode === Qt.RightButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: customIconField.activeFocus || updateField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.closeOrBack()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (key === "b") root.launchBtop()
        else if (key === "s") root.showSettings()
        else if (key === "?") root.launchBtopHelp()
      }

      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: function(eventPoint) {
          if (!root.updateEditing) return
          var point = updateRow.mapFromItem(
            keyCatcher, eventPoint.position.x, eventPoint.position.y)
          if (!updateRow.contains(point))
            root.finishUpdateEditing(true, true)
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: root.page === "main" ? "btop" : "btop Settings"
          meta: root.page === "main"
            ? "CPU " + Math.round(root.activity ? root.activity.cpuUsage : 0)
              + "% · RAM "
              + Math.round(root.activity ? root.activity.memoryUsage : 0)
              + "% · GPU " + root.gpuUsageText
            : "Private btop.conf"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            ActivityIcon {
              iconSize: Style.font.display
              cpuUsage: root.activity ? root.activity.cpuUsage : 0
              memoryUsage: root.activity ? root.activity.memoryUsage : 0
              color: root.foreground
            }
          }
        }

        Column {
          visible: root.page === "main"
          width: parent.width
          spacing: Style.space(6)

          MenuRow {
            label: "Start btop"
            iconText: "󰍛"
            hasCursor: root.mainIndex === 0
            onHovered: function(on) { if (on) root.mainIndex = 0 }
            onClicked: root.launchBtop()
          }

          MenuRow {
            label: "Settings"
            iconText: ""
            value: "›"
            hasCursor: root.mainIndex === 1
            onHovered: function(on) { if (on) root.mainIndex = 1 }
            onClicked: root.showSettings()
          }

          PanelSeparator { foreground: root.foreground }

          MenuRow {
            label: "Help"
            iconText: "?"
            hasCursor: root.mainIndex === 2
            onHovered: function(on) { if (on) root.mainIndex = 2 }
            onClicked: root.launchBtopHelp()
          }
        }

        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "PLUGIN"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          MenuRow {
            label: "Tray icon"
            value: root.iconStyle
            hasCursor: root.settingsIndex === 0
            onHovered: function(on) { if (on) root.settingsIndex = 0 }
            onClicked: root.cycleSetting(0, 1)
          }

          Column {
            visible: root.iconStyle === "Custom"
            width: parent.width
            spacing: Style.space(4)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: customIconField
                Layout.fillWidth: true
                text: root.customIconDraft
                placeholderText: "/path/to/icon.svg"
                foreground: root.foreground
                font.family: root.fontFamily
                hasCursor: !activeFocus
                  && root.settingsIndex === root.customPathIndex
                onTextChanged: root.customIconDraft = text
                onHoveredChanged: if (hovered)
                  root.settingsIndex = root.customPathIndex
                onAccepted: root.saveCustomIconPath()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    focus = false
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              Button {
                text: "Save"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.customIconDraft.trim() !== ""
                onClicked: root.saveCustomIconPath()
              }
            }

            Text {
              visible: root.customIconError !== ""
                || root.customIconLoadFailed
              width: parent.width
              text: root.customIconError !== ""
                ? root.customIconError : "The custom icon could not be loaded."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          MenuRow {
            label: "Keybindings"
            value: activityBinding.label
            hasCursor: root.settingsIndex === root.keybindingsIndex
            onHovered: function(on) {
              if (on) root.settingsIndex = root.keybindingsIndex
            }
            onClicked: root.launchKeybindings()
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "APPEARANCE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          MenuRow {
            label: "Hyprland window mode"
            value: root.windowMode
            hasCursor: root.settingsIndex === root.windowModeIndex
            onHovered: function(on) {
              if (on) root.settingsIndex = root.windowModeIndex
            }
            onClicked: root.cycleSetting(root.windowModeIndex, 1)
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "BTOP"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          CursorSurface {
            id: updateRow
            width: parent.width
            implicitHeight: Style.space(52)
            foreground: root.foreground
            opacity: root.updateAvailable ? 1 : 0.55
            hasCursor: root.settingsIndex === root.updateIndex

            MouseArea {
              anchors.fill: parent
              enabled: root.updateAvailable
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.settingsIndex = root.updateIndex
              onClicked: root.startUpdateEditing()
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.rightMargin: Style.spacing.rowPaddingX
              spacing: Style.space(6)

              Text {
                text: "Update interval"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: updateRow.hasCursor
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }

              TextField {
                id: updateField
                Layout.preferredWidth: Style.space(94)
                Layout.alignment: Qt.AlignVCenter
                text: root.updateDraft
                enabled: root.updateAvailable
                foreground: root.updateDraftInvalid
                  ? root.urgent : root.foreground
                accent: root.updateDraftInvalid ? root.urgent : Color.accent
                font.family: root.fontFamily
                horizontalAlignment: Qt.AlignHCenter
                inputMethodHints: Qt.ImhDigitsOnly
                hasCursor: !activeFocus && updateRow.hasCursor
                onTextChanged: root.updateDraft = text
                onHoveredChanged: if (hovered)
                  root.settingsIndex = root.updateIndex
                onActiveFocusChanged: {
                  if (activeFocus && !root.updateEditing) {
                    root.updateDraft = String(root.updateMs)
                    root.updateEditing = true
                    selectAll()
                  } else if (!activeFocus && root.updateEditing) {
                    root.finishUpdateEditing(true, false)
                  }
                }
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  var text = String(event.text || "").toLowerCase()
                  if (event.key === Qt.Key_Escape || text === "q") {
                    root.finishUpdateEditing(false, true)
                  } else if (event.key === Qt.Key_Return
                      || event.key === Qt.Key_Enter) {
                    root.finishUpdateEditing(true, true)
                  } else if (event.key === Qt.Key_Left || text === "h") {
                    root.nudgeUpdateDraft(-1)
                  } else if (event.key === Qt.Key_Right || text === "l") {
                    root.nudgeUpdateDraft(1)
                  } else if (event.key === Qt.Key_Up || text === "k") {
                    root.ladderUpdateDraft(1)
                  } else if (event.key === Qt.Key_Down || text === "j") {
                    root.ladderUpdateDraft(-1)
                  } else {
                    return
                  }
                  event.accepted = true
                }
              }

              Text {
                text: "ms"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.alignment: Qt.AlignVCenter
              }

              Column {
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                PanelActionButton {
                  iconText: "^"
                  tooltipText: "Next preset"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  size: Style.space(20)
                  enabled: root.updateAvailable
                  onHovered: function(on) {
                    if (on) root.settingsIndex = root.updateIndex
                  }
                  onClicked: root.clickUpdateLadder(1)
                }

                PanelActionButton {
                  iconText: "v"
                  tooltipText: "Previous preset"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  size: Style.space(20)
                  enabled: root.updateAvailable
                  onHovered: function(on) {
                    if (on) root.settingsIndex = root.updateIndex
                  }
                  onClicked: root.clickUpdateLadder(-1)
                }
              }
            }
          }

          Text {
            visible: root.updateDraftInvalid
            width: parent.width
            text: "Use a whole number from " + UpdateInterval.minimum
              + " to " + UpdateInterval.maximum + " ms."
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          MenuRow {
            label: "Process sorting"
            value: root.activity && root.activity.configReady
              ? root.sortingLabel(root.procSorting) : "Loading…"
            enabled: root.activity && !root.activity.configBusy
            hasCursor: root.settingsIndex === root.sortingIndex
            onHovered: function(on) {
              if (on) root.settingsIndex = root.sortingIndex
            }
            onClicked: root.cycleSetting(root.sortingIndex, 1)
          }

          MenuRow {
            label: "Process tree"
            value: root.activity && root.activity.configReady
              ? (root.procTree ? "On" : "Off") : "Loading…"
            enabled: root.activity && !root.activity.configBusy
            hasCursor: root.settingsIndex === root.treeIndex
            onHovered: function(on) {
              if (on) root.settingsIndex = root.treeIndex
            }
            onClicked: root.cycleSetting(root.treeIndex, 1)
          }

          Text {
            visible: root.activity && root.activity.configError !== ""
            width: parent.width
            text: root.activity ? root.activity.configError : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.updateEditing
              ? "h/l or Left/Right: 1 ms; k/j or Up/Down: presets"
              : "Changes apply to running btop sessions."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          MenuRow {
            label: "Back"
            iconText: "‹"
            hasCursor: root.settingsIndex === root.backIndex
            onHovered: function(on) {
              if (on) root.settingsIndex = root.backIndex
            }
            onClicked: root.showMain()
          }
        }
      }
    }
  }

  component MenuRow: CursorSurface {
    id: row

    property string label: ""
    property string value: ""
    property string iconText: ""
    property bool enabled: true

    signal clicked()
    signal hovered(bool isHovered)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(44)
    foreground: root.foreground
    opacity: enabled ? 1 : 0.55

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Text {
        visible: row.iconText !== ""
        text: row.iconText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.hasCursor
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: row.value !== ""
        text: row.value
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: row.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: row.hovered(true)
      onExited: row.hovered(false)
      onPressed: if (root.updateEditing)
        root.finishUpdateEditing(true, true)
      onClicked: row.clicked()
    }
  }
}
