.pragma library

var modifiers = [
  { mask: 64, label: "Super" },
  { mask: 1, label: "Shift" },
  { mask: 4, label: "Ctrl" },
  { mask: 8, label: "Alt" },
  { mask: 16, label: "Mod2" },
  { mask: 32, label: "Mod3" },
  { mask: 128, label: "Mod5" }
]

function friendlyKey(value) {
  var key = String(value || "").trim()
  var aliases = {
    "RETURN": "Enter",
    "ESCAPE": "Escape",
    "BACKSPACE": "Backspace",
    "DELETE": "Delete",
    "SCROLL_LOCK": "Scroll Lock",
    "SPACE": "Space",
    "TAB": "Tab"
  }

  if (aliases[key.toUpperCase()]) return aliases[key.toUpperCase()]
  return key.length === 1 ? key.toUpperCase() : key
}

function bindingLabel(binding) {
  if (!binding) return ""

  var mask = Number(binding.modmask || 0)
  var parts = []
  for (var index = 0; index < modifiers.length; index++) {
    var modifier = modifiers[index]
    if ((mask & modifier.mask) !== 0) parts.push(modifier.label)
  }

  var key = friendlyKey(binding.key)
  if (!key && Number(binding.keycode || 0) > 0)
    key = "Keycode " + String(binding.keycode)
  if (key) parts.push(key)

  return parts.join("+")
}

function findBinding(bindings, description) {
  if (!Array.isArray(bindings)) return null

  var expected = String(description || "")
  for (var index = 0; index < bindings.length; index++) {
    var binding = bindings[index]
    if (binding && String(binding.description || "") === expected)
      return binding
  }

  return null
}

function groupOptionFrom(options) {
  return String(options || "").split(",").map(function(option) {
    return option.trim()
  }).find(function(option) {
    return option.startsWith("grp:")
  }) || ""
}

function friendlyXkbDescription(value) {
  return String(value || "")
    .replace(/\bBoth Alts together\b/g, "Both Alt keys")
    .replace(/\bBoth Ctrls together\b/g, "Both Ctrl keys")
    .replace(/\bBoth Shifts together\b/g, "Both Shift keys")
    .replace(/\bWin\b/g, "Super")
    .replace(/\s*\+\s*/g, " + ")
}

function describeGroupOption(option, descriptions) {
  if (!option) return "Not configured"

  var lines = String(descriptions || "").split("\n")
  for (var index = 0; index < lines.length; index++) {
    var match = lines[index].match(/^\s*(grp:\S+)\s+(.+)$/)
    if (match && match[1] === option)
      return friendlyXkbDescription(match[2])
  }

  return option
    .substring(4)
    .replace(/_toggle(?:_bidir)?$/, "")
    .replace(/_/g, " ")
}
