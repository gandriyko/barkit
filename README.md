<div align="center">

<img src="BarKit/AppIcon-source.png" width="128" alt="BarKit icon">

# BarKit

**Small Mac tweaks, one menu bar icon.**

Pin your microphone, adjust volume and brightness, and keep your Mac awake, all from the menu bar.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 5](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![Universal](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-4C6EF5)
![No dependencies](https://img.shields.io/badge/dependencies-none-34C759)

</div>

---

## Features

| | Feature | What it does |
|---|---|---|
| 🎙️ | **Pin Input** | Keeps the microphone you picked as the system default, even when macOS switches it or the device reconnects |
| 🔊 | **Volume** | Separate sliders for microphone input level and output volume |
| ☀️ | **Brightness** | Controls the built-in display and DDC/CI external monitors independently |
| ☕ | **Keep Awake** | Prevents idle sleep for 30 min, 1, 2, 3 or 5 hours, or until you turn it off |
| 🔌 | **Awake on Power** | Turns Keep Awake on when the power adapter is connected and off when it is removed |
| 🚀 | **Launch at Login** | Starts with your Mac via `SMAppService` |

BarKit records no audio, never changes the default output device, and asks for no microphone, accessibility or screen-recording permission.

## Quick start

> **Requirements:** macOS 13 Ventura or newer and the Apple Command Line Tools (`xcode-select --install`). A full Xcode install is not needed.

```zsh
git clone https://github.com/gandriyko/barkit.git && cd barkit
./Scripts/install.sh
```

This builds BarKit, quits any running copy, installs it to `/Applications/BarKit.app` and launches it.

<details>
<summary><b>Install options</b></summary>

| Command | Result |
|---|---|
| `./Scripts/install.sh` | Build, install to `/Applications` and launch |
| `./Scripts/install.sh --no-launch` | Build and install without launching |
| `INSTALL_DIR=~/Applications ./Scripts/install.sh` | Install to another folder |
| `./Scripts/build.sh` | Build only, to `build/Release/BarKit.app` |

If you get a permission error writing to `/Applications`, run the install with `sudo` or use `INSTALL_DIR=~/Applications`.

</details>

## Usage

Click the <img src="docs/menu-icons/wrench.and.screwdriver.png" width="18" alt=""> BarKit icon in the menu bar. A badge appears on it while Keep Awake is on.

### Menu at a glance

| | Item | What it does |
|:-:|---|---|
| <img src="docs/menu-icons/pin.png" width="18" alt=""> | **Pin Input** | Keeps the chosen microphone as the system default |
| <img src="docs/menu-icons/mic.png" width="18" alt=""> | **Input Device** | Lists microphones; choosing one also turns on Pin Input |
| <img src="docs/menu-icons/waveform.png" width="18" alt=""> | **Microphone Volume** | Input level slider for the current microphone |
| <img src="docs/menu-icons/speaker.wave.2.png" width="18" alt=""> | **Output Volume** | Volume slider for the current output device |
| <img src="docs/menu-icons/sun.max.png" width="18" alt=""> | **Display Brightness** | A slider for each display |
| <img src="docs/menu-icons/cup.and.saucer.png" width="18" alt=""> | **Keep Mac Awake** | Shows the time left while a timed session runs |
| <img src="docs/menu-icons/moon.zzz.png" width="18" alt=""> | &nbsp;&nbsp;Off | Lets the Mac sleep normally |
| <img src="docs/menu-icons/timer.png" width="18" alt=""> | &nbsp;&nbsp;30 Minutes … 5 Hours | Stays awake for the chosen time |
| <img src="docs/menu-icons/infinity.png" width="18" alt=""> | &nbsp;&nbsp;Until Turned Off | Stays awake until you turn it off or quit BarKit |
| <img src="docs/menu-icons/display.png" width="18" alt=""> | &nbsp;&nbsp;Keep Display On | Also stops the display from sleeping |
| <img src="docs/menu-icons/powerplug.png" width="18" alt=""> | &nbsp;&nbsp;Turn On When Connected to Power | Starts Keep Awake on the adapter, ends it on battery |
| <img src="docs/menu-icons/power.png" width="18" alt=""> | **Launch at Login** | Starts BarKit with your Mac |
| <img src="docs/menu-icons/rectangle.portrait.and.arrow.right.png" width="18" alt=""> | **Quit BarKit** | <kbd>⌘</kbd> <kbd>Q</kbd> |

### Details

- **Pin Input** switches back to your device whenever macOS changes the default input. A disconnected device shows as <img src="docs/menu-icons/exclamationmark.triangle.png" width="18" alt=""> *Unavailable* and is restored when it reconnects. Turn Pin Input off to let macOS choose the input again.
- Devices without an adjustable volume level show as unavailable.
- Brightness for external monitors uses DDC/CI. Support depends on the monitor, cable, adapter or dock.
- A manually started Keep Awake session ends when BarKit quits and does not resume on relaunch.
- **Launch at Login** works most reliably when BarKit runs from `/Applications`.

## Development

```
BarKit/            Swift sources, Info.plist, app icon
Scripts/
  build.sh         Compile a universal, ad-hoc signed app with swiftc
  install.sh       Build and install to /Applications
  make-icon.sh     Regenerate BarKit.icns from AppIcon.svg
  render-menu-icons.swift   Render the menu SF Symbols used in this README
docs/menu-icons/   Menu icon images for this README
```

The app is built directly with `swiftc`, without an Xcode project build, and uses only system frameworks: AppKit, CoreAudio, CoreGraphics, IOKit and ServiceManagement.

**App icon.** The source is `BarKit/AppIcon.svg`. After editing it, run `./Scripts/make-icon.sh` to regenerate `BarKit.icns` and `AppIcon-source.png`.

## Migrating from InputPin

On first launch BarKit copies the pin setting and saved device from the legacy `com.inputpin.app` preferences and leaves the old ones unchanged. If InputPin was a login item, disable it and turn on **Launch at Login** in BarKit so the two apps don't start together.
