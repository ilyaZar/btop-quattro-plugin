# btop Activity for Omarchy Quattro

Brings btop back to the Omarchy bar: live CPU, RAM, and GPU usage and
temperatures, with btop one click away.

![btop Activity on the Omarchy desktop](preview.png)

## Some features

- switches between floating and tiled btop and applies settings live
- preserves Omarchy's btop theme without touching the normal user `btop.conf`

## Quickstart

After installation:

- **left-click** bar icon to start/focus btop in the selected window mode
- **right-click** bar icon to open the plugin settings
  - choose **Settings** to change plugin and btop options
  - choose **Help** to open built-in help in the selected window mode
- **hover over it** to see RAM use, CPU use and temperature, and GPU use and
  temperature

## Install

```bash
omarchy plugin add https://github.com/ilyaZar/btop-quattro-plugin --enable
```

Omarchy includes btop by default. On AMD systems, btop's own GPU panel also
needs the distribution's ROCm SMI library (`rocm-smi-lib` on Arch).

## Use

The plugin reads GPU telemetry from the kernel driver. If that driver does not
publish a temperature sensor, the hover shows a dimmed `<unavailable>`. If
something fails here, GPU and driver combinations can be messy, so feel free
to file an issue.

AMD usage and temperature are read directly from DRM sysfs. NVIDIA uses NVML,
while Intel `i915` usage is sampled from the same Linux performance counters
used by btop. Install the plugin's narrow helper once to enable the native
backends:

```bash
~/.config/omarchy/plugins/ilyazar.btop/setup-gpu-helper.sh
```

The helper is built locally. On Intel it receives only `cap_perfmon`; NVIDIA
uses the driver-provided NVML library without elevated privileges. Intel
integrated GPUs commonly expose package temperature rather than a separate GPU
sensor, so temperature can remain unavailable even while usage is working.
Building requires a C compiler and `setcap` from `libcap`. NVIDIA monitoring
also requires the official driver-provided `libnvidia-ml` library, as btop does.

## Demo

See btop launch from the bar, switch between floating and tiled layouts, apply a
250 ms refresh interval live, and update its keybinding.

<https://github.com/user-attachments/assets/d8dde155-dd62-4afa-b586-2f4b95a61d4e>

## Settings

The plugin keeps a short list of useful controls before opening btop:

| Setting         | Choices                                      |
| --------------- | -------------------------------------------- |
| Tray icon       | Meters, CPU, Pulse, or a custom image        |
| Keybindings     | opens the Omarchy user bindings file         |
| Window mode     | floating or tiled                            |
| Update interval | any whole number from 100 ms to one day      |
| Process sorting | lazy CPU, direct CPU, memory, or program     |
| Process tree    | on or off                                    |

For the update interval, press Enter or click the value to edit it. Left/Right
(or `h`/`l`) change it by 1 ms. Up/Down (or `k`/`j`) move through 250, 500,
1000, 2000, and 5000 ms while still letting you type any value in btop's full
range. From a custom value, they jump to the next preset above or below it and
wrap around at the ends.

Edit `~/.config/hypr/bindings.lua` directly, or select **Keybindings** in the
plugin settings to open it. The button prefers Neovim, jumping to an existing
Activity override or to the end of the file; without Neovim, it uses Omarchy's
config editor.

Omarchy assigns `Super+Ctrl+T` to btop by default. To replace it, e.g. with
`Super+Ctrl+Alt+g`, add:

```lua
hl.unbind("SUPER + CTRL + T")
o.bind("SUPER + CTRL + ALT + G", "Activity", { tui = "btop" })
```

After Hyprland reloads, the settings row shows the effective shortcut, or
`Unbound` when no Activity binding remains.

Cycle **Tray icon** through **Meters**, **CPU**, **Pulse**, and **Custom**. The
default CPU icon follows the bar's normal foreground color. The custom path is
stored separately, so switching between styles does not discard it. **CPU** is
the default for new installations.

For **Custom**, enter an absolute path, a `~/path`, or a `file://` URL, then
press Enter or **Save**. SVG and PNG work well. The plugin renders the file
as-is and does not recolor it. An invalid path shows `!`.

Depending on the installed icon themes, useful paths include:

- `/usr/share/icons/hicolor/scalable/apps/btop.svg`
- `/usr/share/icons/HighContrast/scalable/apps/utilities-system-monitor.svg`
- `/usr/share/icons/Yaru/scalable/apps/system-monitor-app-symbolic.svg`

Plugin choices are stored in Omarchy's `shell.json` and survive shell restarts.

Under **Appearance**, choose whether btop opens tiled or floating. The setting
applies to both left-click and Help. Floating is the default and restores
Omarchy's centered 875 x 600 window size when selected.

## Roadmap and releases

Planned work stays at the top. Shipped entries come from
[CHANGELOG.md](CHANGELOG.md), newest first.

| Release | State   | Date       | What changed                                           |
| ------- | ------- | ---------- | ------------------------------------------------------ |
| Next    | planned | TBD        | add details when the next release is planned           |
| 0.1.11  | shipped | 2026-08-21 | make the release table clean and easy to scan          |
| 0.1.10  | shipped | 2026-08-21 | choose any update interval or step through presets     |
|         |         |            | restore settings when disabling or removing the plugin |
|         |         |            | show Intel and NVIDIA GPU data after helper setup      |
|         |         |            | keep the widget readable on a transparent bar          |
| 0.1.9   | shipped | 2026-08-15 | show GPU use and temperature in the tooltip and menu   |
|         |         |            | show when GPU temperature is unavailable               |
|         |         |            | display Scroll Lock correctly in shortcuts             |
| 0.1.8   | shipped | 2026-08-14 | add a demo for launch, window modes, refresh, and keys |
| 0.1.7   | shipped | 2026-08-14 | update the preview and explain Activity shortcuts      |
| 0.1.6   | shipped | 2026-08-14 | show the current Activity shortcut or Unbound          |
|         |         |            | keep custom icon controls beside the icon choice       |
| 0.1.5   | shipped | 2026-08-14 | open the user bindings file from settings              |
|         |         |            | apply btop settings without reloading the plugin       |
|         |         |            | create the private btop config when it is missing      |
| 0.1.4   | shipped | 2026-08-13 | keep settings usable while the private config loads    |
|         |         |            | switch open btop windows between floating and tiled    |
|         |         |            | add the 250 ms interval                                |
| 0.1.3   | shipped | 2026-08-13 | start from Omarchy's btop config and current theme     |
| 0.1.2   | shipped | 2026-08-12 | keep plugin settings separate and remove them cleanly  |
| 0.1.1   | shipped | 2026-08-12 | show CPU temperature in the hover details              |
|         |         |            | refresh hover data at the chosen interval              |
|         |         |            | use the CPU icon by default for new installs           |
| 0.1.0   | shipped | 2026-08-12 | first release                                          |

## Config safety and troubleshooting

The plugin stores its choices in Omarchy's `shell.json` and generates a private
btop config under `$XDG_RUNTIME_DIR`. The normal user `btop.conf` is never read
or written.

The runtime file is created from Omarchy's packaged btop config. Quickshell
writes it atomically, and a running btop receives its supported config-reload
signal only after a successful change. Disabling or removing the plugin restores
a file that existed before the plugin was enabled, or removes the file it
created.

GPU temperature depends on driver support. If unavailable, the hover shows
`<unavailable>`. For AMD temperature monitoring in btop, install ROCm SMI:

```bash
sudo pacman -S rocm-smi-lib
```

Then restart btop. This can matter for AMD GPUs like the Radeon RX 6400.

## Remove

```bash
omarchy plugin remove ilyazar.btop
```

Removing the plugin removes its private btop settings. It does not remove btop
or change btop's normal configuration.

## Development

Link this repository into the local plugin folder and enable it:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/ilyazar.btop
omarchy-shell shell rescanPlugins
omarchy plugin enable ilyazar.btop --section right
```

`Service.qml` owns system sampling and the native Quickshell config bridge.
`BarWidget.qml` owns the bar icon, menu, and navigation.

## License

MIT
