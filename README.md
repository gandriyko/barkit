# BarKit

BarKit is a lightweight native macOS menu-bar application that keeps a selected audio input device as the system default, controls display brightness, and can prevent idle sleep. It uses native macOS frameworks directly and has no third-party dependencies.

## Requirements

- macOS 13 Ventura or newer
- Apple Command Line Tools (`xcode-select --install`)
- No full Xcode installation is required

## Build

```zsh
./Scripts/build.sh
```

The script creates an ad-hoc signed Universal application for both Apple Silicon and Intel:

```text
build/Release/BarKit.app
```

Run it with:

```zsh
open "build/Release/BarKit.app"
```

## Install in Applications

Quit any running copy of BarKit, then copy the built application into `/Applications`:

```zsh
/usr/bin/ditto "build/Release/BarKit.app" "/Applications/BarKit.app"
```

If macOS reports a permission error, run the same command with administrator privileges:

```zsh
sudo /usr/bin/ditto "build/Release/BarKit.app" "/Applications/BarKit.app"
```

Launch the installed copy:

```zsh
open "/Applications/BarKit.app"
```

Use the copy in `/Applications` when enabling **Launch at Login**. After rebuilding BarKit, quit the running application and repeat the `ditto` command to update the installed copy.

## Usage

- Click the microphone icon in the menu bar.
- Select an item under **Input Device**. Selecting a device also enables pinning and persists its CoreAudio UID.
- While **Pin Input** is enabled, BarKit restores the saved device if macOS changes the default input.
- If the pinned device is disconnected, BarKit keeps its UID and restores it after reconnect.
- Disable **Pin Input** to let macOS change the input without intervention.
- Use **Microphone Volume** to adjust the input level of the current system microphone. Devices that do not expose an adjustable input level are shown as unavailable.
- Use **Output Volume** to adjust the output level of the current system sound device.
- Use **Display Brightness** to adjust the built-in display and compatible DDC/CI external monitors independently.
- Displays that do not expose hardware brightness control are shown as unavailable. DDC/CI support can depend on the monitor, cable, adapter, or dock.
- Use **Keep Mac Awake** to prevent idle sleep for 30 minutes, 1 hour, or until you turn it off. The display can still sleep normally. The setting ends when BarKit quits and is not restored on relaunch.
- **Launch at Login** uses `SMAppService.mainApp`. Install `BarKit.app` in `/Applications` before enabling it for reliable registration.

BarKit never changes the default output device, records no audio, and requests no microphone, accessibility, or screen-recording permission.

## Migrating from InputPin

On its first launch, BarKit copies the saved input-pin setting and device identity from the legacy `com.inputpin.app` preferences. The old preferences are left unchanged. If InputPin was registered as a login item, disable it and enable **Launch at Login** from the installed BarKit copy so both applications do not start together.
