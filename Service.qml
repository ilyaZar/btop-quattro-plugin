import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property real cpuUsage: 0
  property real cpuTemperature: -1
  property real gpuUsage: -1
  property real gpuTemperature: -1
  property real memoryUsage: 0
  property bool available: false
  property string temperaturePath: ""
  property string gpuUsagePath: ""
  property string gpuTemperaturePath: ""
  property real previousIdle: -1
  property real previousTotal: -1

  property int updateMs: 2000
  property bool configExists: false
  property bool configReady: false
  property string configError: ""
  property var _pendingConfig: null
  property bool _savingConfig: false
  property string _savingText: ""
  property bool _reloadAfterSave: false
  property string _defaultConfigOutput: ""
  property string _defaultConfigError: ""
  property bool _creatingConfig: false
  property bool _usingDefaultConfigFallback: false

  readonly property bool configBusy: _pendingConfig !== null
    || _savingConfig
    || _creatingConfig
    || defaultConfigProcess.running
  readonly property string configPath: Quickshell.env("XDG_RUNTIME_DIR")
    + "/ilyazar-btop.conf"
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
    if (gpuUsagePath !== "") gpuUsageFile.reload()
    if (gpuTemperaturePath !== "") gpuTemperatureFile.reload()
  }

  function validatedConfig(interval, sorting, tree) {
    var update = parseInt(String(interval), 10)
    var order = String(sorting)
    if (!isFinite(update) || update < 100 || update > 86400000)
      throw new Error("Invalid btop update interval")
    if (sortingValues.indexOf(order) < 0)
      throw new Error("Invalid btop process sorting")
    if (tree !== true && tree !== false)
      throw new Error("Invalid btop process tree value")
    return { updateMs: update, procSorting: order, procTree: tree }
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

  function setConfig(interval, sorting, tree) {
    if (configBusy) return false
    try {
      var next = validatedConfig(interval, sorting, tree)
      updateMs = next.updateMs
      _pendingConfig = next
      configError = ""
      configFile.reload()
      return true
    } catch (error) {
      configError = String(error)
      return false
    }
  }

  function handleConfigLoaded(raw, createFile) {
    var text = String(raw || "")
    var current = text
    if (!createFile) configExists = true
    if (_pendingConfig === null) {
      configReady = true
      configError = ""
      return
    }

    var values = _pendingConfig
    _pendingConfig = null
    text = patchConfig(text, "update_ms", String(values.updateMs))
    text = patchConfig(text, "proc_sorting", JSON.stringify(values.procSorting))
    text = patchConfig(text, "proc_tree", String(values.procTree))
    if (!createFile && text === current) {
      configReady = true
      configError = ""
      return
    }
    saveConfig(text, true)
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
    configReady = true
    configError = ""
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
    if (_pendingConfig !== null) {
      handleConfigLoaded(text, true)
      return
    }
    saveConfig(text, false)
  }

  function failConfig(message) {
    _pendingConfig = null
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

  function applyGpuUsage(raw) {
    var percentage = Number(String(raw || "").trim())
    gpuUsage = isFinite(percentage) && percentage >= 0
      ? clamp(percentage, 0, 100) : -1
  }

  function applyGpuTemperature(raw) {
    var millidegrees = Number(String(raw || "").trim())
    gpuTemperature = isFinite(millidegrees) && millidegrees > 0
      ? millidegrees / 1000 : -1
  }

  function applySensorPaths(raw) {
    var lines = String(raw || "").trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields[0] === "cpu") temperaturePath = fields[1] || ""
      else if (fields[0] === "gpu") gpuUsagePath = fields[1] || ""
      else if (fields[0] === "gpu_temperature")
        gpuTemperaturePath = fields[1] || ""
    }
  }

  property FileView configFile: FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: root.handleConfigLoaded(text(), false)
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        root.configExists = false
        if (root._pendingConfig !== null) root.createConfig()
        else {
          root.configReady = true
          root.configError = ""
        }
      }
      else root.failConfig("Could not read btop settings: "
        + FileViewError.toString(error))
    }
    onSaved: root.finishConfigSave()
    onSaveFailed: function(error) {
      root.failConfig("Could not save btop settings: "
        + FileViewError.toString(error))
    }
  }

  property FileView temperatureFile: FileView {
    id: temperatureFile
    path: root.temperaturePath
    printErrors: false
    onLoaded: root.applyTemperature(text())
    onLoadFailed: root.cpuTemperature = -1
  }

  property FileView gpuUsageFile: FileView {
    path: root.gpuUsagePath
    printErrors: false
    onLoaded: root.applyGpuUsage(text())
    onLoadFailed: root.gpuUsage = -1
  }

  property FileView gpuTemperatureFile: FileView {
    path: root.gpuTemperaturePath
    printErrors: false
    onLoaded: root.applyGpuTemperature(text())
    onLoadFailed: root.gpuTemperature = -1
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

  property Process sensorPathProcess: Process {
    running: true
    command: [
      "sh", "-c",
      "for d in /sys/class/hwmon/hwmon*; do "
        + "[ -r \"$d/name\" ] || continue; "
        + "read -r name < \"$d/name\"; "
        + "case \"$name\" in coretemp|k10temp|zenpower|cpu_thermal) "
        + "for f in \"$d\"/temp*_input; do "
        + "[ -r \"$f\" ] || continue; "
        + "printf 'cpu\\t%s\\n' \"$f\"; break 2; "
        + "done;; esac; done; "
        + "for d in /sys/class/drm/card*/device; do "
        + "[ -r \"$d/gpu_busy_percent\" ] || continue; "
        + "printf 'gpu\\t%s\\n' \"$d/gpu_busy_percent\"; "
        + "for h in \"$d\"/hwmon/hwmon*; do "
        + "[ -d \"$h\" ] || continue; fallback=; "
        + "for f in \"$h\"/temp*_input; do "
        + "[ -r \"$f\" ] || continue; "
        + "[ -n \"$fallback\" ] || fallback=\"$f\"; "
        + "label=\"${f%_input}_label\"; "
        + "[ -r \"$label\" ] || continue; read -r name < \"$label\"; "
        + "[ \"$name\" = edge ] || continue; fallback=\"$f\"; break; "
        + "done; [ -n \"$fallback\" ] && "
        + "printf 'gpu_temperature\\t%s\\n' \"$fallback\"; break; "
        + "done; break; done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySensorPaths(text)
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

  property Timer refreshTimer: Timer {
    interval: root.updateMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
