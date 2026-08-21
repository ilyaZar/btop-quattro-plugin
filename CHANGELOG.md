# Changelog

Notable changes to btop Activity are documented here.

## Unreleased

## 0.2.0 - 2026-08-21

- Rename the GitHub repository to `omarchy-btop-activity` while keeping the
  plugin ID stable (@ilyazar).
- Replace the per-cell release separators with a normal compact table
  (@ilyazar).

## 0.1.10 - 2026-08-21

- Allow any btop-supported update interval while keeping the preset ladder on
  mouse and keyboard controls (@ilyazar).
- Restore a pre-existing runtime btop config when disabling or removing the
  plugin (@ilyazar).
- Add native Intel and NVIDIA GPU telemetry backends with a narrow setup helper
  (@ilyazar).
- Follow the transparent bar's adaptive foreground color so the btop widget
  stays legible (@nate0m, @namilton-ship-it).

## 0.1.9 - 2026-08-15

- Add live GPU usage and temperature to the bar tooltip and menu, with a clear
  fallback when temperature is unavailable.
- Recognize Scroll Lock in formatted shortcuts.

## 0.1.8 - 2026-08-14

- Add a demo of btop launch, floating and tiled modes, live refresh changes,
  and keybinding updates.

## 0.1.7 - 2026-08-14

- Refresh the preview and clarify how to open and override the Activity
  shortcut.

## 0.1.6 - 2026-08-14

- Show the effective Activity shortcut in settings, including its unbound
  state.
- Keep custom icon controls next to the tray icon selection and share the
  Hyprland shortcut helpers.

## 0.1.5 - 2026-08-14

- Open the Omarchy user bindings file directly from the plugin settings.
- Persist btop options without reloading the plugin and create missing runtime
  configs from Omarchy's packaged defaults.

## 0.1.4 - 2026-08-13

- Keep settings responsive after private btop config initialization.
- Apply floating and tiled modes to open windows and restore centered floating
  geometry.
- Add a 250 ms update interval.

## 0.1.3 - 2026-08-13

- Seed the private btop config from Omarchy's packaged defaults so the current
  theme is preserved.

## 0.1.2 - 2026-08-12

- Isolate plugin settings from the normal user btop config and remove them
  with the plugin.

## 0.1.1 - 2026-08-12

- Add CPU temperature to the hover details and use the selected btop interval
  for all hover stats.
- Default fresh installs to the CPU tray icon.

## 0.1.0 - 2026-08-12

- Initial release.
