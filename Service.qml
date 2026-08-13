import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property real cpuUsage: 0
  property real cpuTemperature: -1
  property real memoryUsage: 0
  property bool available: false
  property string temperaturePath: ""
  property real previousIdle: -1
  property real previousTotal: -1

  property int updateMs: 2000
  property string procSorting: "cpu lazy"
  property bool procTree: false
  property bool configExists: false
  property bool configReady: false
  property string configError: ""
  property string _pendingKey: ""
  property string _pendingValue: ""
  property bool _savingConfig: false
  property string _savingText: ""
  property bool _reloadAfterSave: false
  property string _defaultConfigOutput: ""
  property string _defaultConfigError: ""
  property bool _creatingConfig: false
  property bool _usingDefaultConfigFallback: false

  readonly property bool configBusy: _pendingKey !== ""
    || _savingConfig
    || _creatingConfig
    || defaultConfigProcess.running
  readonly property string configPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/ilyazar.btop/.btop.conf"
  readonly property string omarchyConfigPath:
    "/usr/share/omarchy/config/btop/btop.conf"
  readonly property var sortingValues: [
    "pid", "program", "arguments", "threads", "user", "memory",
    "cpu lazy", "cpu direct"
  ]

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  function refresh() {
    if (!statsProcess.running) statsProcess.running = true
    if (temperaturePath !== "") temperatureFile.reload()
  }

  function loadConfig() {
    configFile.reload()
  }

  function configValue(raw, key) {
    var pattern = new RegExp(
      "^\\s*" + key
        + "\\s*=\\s*(\"(?:\\\\.|[^\"])*\"|[^\\s#]+)",
      "m"
    )
    var match = pattern.exec(String(raw || ""))
    if (!match) return undefined
    var value = match[1]
    if (value.length >= 2 && value[0] === "\"") {
      try { return JSON.parse(value) } catch (error) { return undefined }
    }
    return value
  }

  function applyConfig(raw) {
    var interval = parseInt(configValue(raw, "update_ms"), 10)
    var sorting = String(configValue(raw, "proc_sorting") || "cpu lazy")
    var tree = String(configValue(raw, "proc_tree") || "false").toLowerCase()

    updateMs = isFinite(interval) && interval >= 100 && interval <= 86400000
      ? interval : 2000
    procSorting = sortingValues.indexOf(sorting) >= 0 ? sorting : "cpu lazy"
    procTree = tree === "true"
    configReady = true
    configError = ""
  }

  function serializeConfigValue(key, value) {
    if (key === "update_ms") {
      var interval = parseInt(String(value), 10)
      if (!isFinite(interval) || interval < 100 || interval > 86400000)
        throw new Error("Invalid btop update interval")
      return String(interval)
    }
    if (key === "proc_sorting") {
      var sorting = String(value)
      if (sortingValues.indexOf(sorting) < 0)
        throw new Error("Invalid btop process sorting")
      return JSON.stringify(sorting)
    }
    if (key === "proc_tree") {
      var tree = String(value).toLowerCase()
      if (tree !== "true" && tree !== "false")
        throw new Error("Invalid btop process tree value")
      return tree
    }
    throw new Error("Unsupported btop setting")
  }

  function patchConfig(raw, key, value) {
    var text = String(raw || "")
    var trailingNewline = text.endsWith("\n")
    var lines = text.split("\n")
    if (trailingNewline) lines.pop()

    var pattern = new RegExp(
      "^(\\s*" + key
        + "\\s*=\\s*)(\"(?:\\\\.|[^\"])*\"|[^\\s#]+)"
        + "(\\s*(?:#.*)?)$"
    )
    var changed = false
    for (var i = 0; i < lines.length; i++) {
      var match = pattern.exec(lines[i])
      if (!match) continue
      lines[i] = match[1] + value + match[3]
      changed = true
    }
    if (!changed) lines.push(key + " = " + value)
    return lines.join("\n") + "\n"
  }

  function setConfig(key, value) {
    if (configBusy) return
    try {
      _pendingValue = serializeConfigValue(key, value)
      _pendingKey = key
      configError = ""
      configFile.reload()
    } catch (error) {
      configError = String(error)
    }
  }

  function handleConfigLoaded(raw) {
    var text = String(raw || "")
    configExists = true
    if (_pendingKey === "") {
      applyConfig(text)
      return
    }

    var next = patchConfig(text, _pendingKey, _pendingValue)
    _pendingKey = ""
    _pendingValue = ""
    saveConfig(next, true)
  }

  function saveConfig(text, reloadAfterSave) {
    _savingConfig = true
    _savingText = text
    _reloadAfterSave = reloadAfterSave
    try {
      configFile.setText(text)
    } catch (error) {
      failConfig(String(error))
    }
  }

  function finishConfigSave() {
    if (!_savingConfig) return
    var text = _savingText
    var shouldReload = _reloadAfterSave
    _savingConfig = false
    _savingText = ""
    _reloadAfterSave = false
    configExists = true
    applyConfig(text)
    if (shouldReload) reloadBtop()
  }

  function createConfig() {
    if (_creatingConfig || defaultConfigProcess.running) return
    _defaultConfigOutput = ""
    _defaultConfigError = ""
    _creatingConfig = true
    _usingDefaultConfigFallback = false
    omarchyConfigFile.reload()
  }

  function useDefaultConfig() {
    _creatingConfig = false
    _usingDefaultConfigFallback = true
    defaultConfigProcess.running = true
  }

  function finishDefaultConfig() {
    var text = String(_defaultConfigOutput || "")
    if (text.trim() === "") {
      failConfig(_defaultConfigError || "btop returned an empty default config")
      return
    }
    if (_pendingKey !== "") {
      handleConfigLoaded(text)
      return
    }
    saveConfig(text, false)
  }

  function failConfig(message) {
    _pendingKey = ""
    _pendingValue = ""
    _savingConfig = false
    _savingText = ""
    _reloadAfterSave = false
    _creatingConfig = false
    _usingDefaultConfigFallback = false
    configReady = false
    configError = String(message || "Could not update btop settings")
  }

  function reloadBtop() {
    if (reloadProcess.running) return
    var user = Quickshell.env("USER")
    reloadProcess.command = user
      ? ["pkill", "-USR2", "-u", user, "-x", "btop"]
      : ["pkill", "-USR2", "-x", "btop"]
    reloadProcess.running = true
  }

  function applyStats(raw) {
    var nextIdle = -1
    var nextTotal = -1
    var nextMemory = -1
    var lines = String(raw || "").trim().split("\n")

    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].trim().split(/\s+/)
      if (fields[0] === "cpu" && fields.length >= 3) {
        nextIdle = Number(fields[1])
        nextTotal = Number(fields[2])
      } else if (fields[0] === "memory" && fields.length >= 2) {
        nextMemory = Number(fields[1])
      }
    }

    if (isFinite(nextMemory) && nextMemory >= 0)
      memoryUsage = clamp(nextMemory, 0, 100)

    if (previousTotal >= 0 && nextTotal > previousTotal) {
      var totalDelta = nextTotal - previousTotal
      var idleDelta = nextIdle - previousIdle
      cpuUsage = clamp((1 - idleDelta / totalDelta) * 100, 0, 100)
    }

    if (nextIdle >= 0 && nextTotal >= 0) {
      previousIdle = nextIdle
      previousTotal = nextTotal
      available = nextMemory >= 0
    }
  }

  function applyTemperature(raw) {
    var millidegrees = Number(String(raw || "").trim())
    cpuTemperature = isFinite(millidegrees) && millidegrees > 0
      ? millidegrees / 1000 : -1
  }

  property FileView configFile: FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: root.handleConfigLoaded(text())
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        root.configExists = false
        if (root._pendingKey !== "") root.createConfig()
        else root.applyConfig("")
      }
      else root.failConfig("Could not read btop settings: "
        + FileViewError.toString(error))
    }
    onSaved: root.finishConfigSave()
    onSaveFailed: function(error) {
      root.failConfig("Could not save btop settings: "
        + FileViewError.toString(error))
    }
    onFileChanged: configReloadTimer.restart()
  }

  property FileView temperatureFile: FileView {
    id: temperatureFile
    path: root.temperaturePath
    printErrors: false
    onLoaded: root.applyTemperature(text())
    onLoadFailed: root.cpuTemperature = -1
  }

  property FileView omarchyConfigFile: FileView {
    id: omarchyConfigFile
    path: root.omarchyConfigPath
    printErrors: false
    onLoaded: {
      if (!root._creatingConfig) return
      root._defaultConfigOutput = text()
      root._creatingConfig = false
      root.finishDefaultConfig()
    }
    onLoadFailed: if (root._creatingConfig) root.useDefaultConfig()
  }

  property Process statsProcess: Process {
    id: statsProcess
    command: ["omarchy-system-stats", "--bar-widget"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStats(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.available = false
    }
  }

  property Process temperaturePathProcess: Process {
    running: true
    command: [
      "sh", "-c",
      "for d in /sys/class/hwmon/hwmon*; do "
        + "[ -r \"$d/name\" ] || continue; "
        + "read -r name < \"$d/name\"; "
        + "case \"$name\" in coretemp|k10temp|zenpower|cpu_thermal) "
        + "for f in \"$d\"/temp*_input; do "
        + "[ -r \"$f\" ] || continue; printf '%s\\n' \"$f\"; exit; "
        + "done;; esac; done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.temperaturePath = String(text).trim()
    }
  }

  property Process defaultConfigProcess: Process {
    id: defaultConfigProcess
    running: false
    command: ["btop", "--default-config"]
    stdout: StdioCollector {
      id: defaultConfigStdout
      waitForEnd: true
      onStreamFinished: root._defaultConfigOutput = text
    }
    stderr: StdioCollector {
      id: defaultConfigStderr
      waitForEnd: true
      onStreamFinished: root._defaultConfigError = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        if (root._usingDefaultConfigFallback)
          root._defaultConfigOutput = patchConfig(
            root._defaultConfigOutput,
            "color_theme",
            JSON.stringify("current")
          )
        root.finishDefaultConfig()
      }
      else root.failConfig(
        defaultConfigStderr.text || root._defaultConfigError
          || "Could not generate btop's default config"
      )
    }
  }

  property Process reloadProcess: Process {
    id: reloadProcess
    running: false
    command: []
  }

  property Timer configReloadTimer: Timer {
    id: configReloadTimer
    interval: 120
    repeat: false
    onTriggered: root.loadConfig()
  }

  property Timer refreshTimer: Timer {
    interval: root.updateMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
