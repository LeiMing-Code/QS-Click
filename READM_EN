# QS Click

Quick screenshots for Windows: select an area, then immediately annotate and save it or copy it to the clipboard.

The app is designed for anyone who regularly takes and annotates screenshots: developers, QA engineers, technical support staff, and documentation authors.

## Features

- Capture a region with the mouse, the active window, the entire desktop, or an individual monitor.
- Built-in editor: arrows and lines, text labels, rectangles and ellipses, highlighter, blur, crop, and numbering tool.
- Copy to the clipboard or save as PNG/JPEG.
- Global hotkeys with customizable combinations.
- Runs from the notification area, starts with Windows, and enforces a single application instance.
- Multi-monitor support, including monitors with different DPI scaling.

## Quick Start

Clone the repository and build the project in Delphi.

```powershell
git clone https://github.com/<your-account>/<repository>.git
```

Then, in Delphi 13:

1. Install **Delphi 13 (RAD Studio)** with the **FireMonkey** platform for Windows.
2. Open the `QS_Click.dproj` project.
3. Select the **Windows 32-bit** or **Windows 64-bit** platform.
4. Run `Project → Build`, then `Run → Run` (or press `F9`).

After the build, `QS_Click.exe` will appear in the `Win32\Release\` directory — run it.

> **Optional dependency:** the About page on Win32 uses the `Markdown4D.Fmx` Markdown viewer. If the package is not installed, add the `QS_NO_MARKDOWN4D` conditional symbol to the project and remove `Markdown4D.Fmx` from Runtime Packages — the About page will fall back to a plain `TMemo`, and nothing else will change.

## Usage

After launch, the app runs in the notification area. Default capture hotkeys:

| Shortcut | Result |
|---|---|
| `Ctrl+Shift+1` | capture a region — select the desired area with the mouse |
| `Ctrl+Shift+2` | capture the active window |
| `Ctrl+Shift+3` | capture the entire desktop |

The resulting screenshot opens in the editor. Editor controls:

| Action | Result |
|---|---|
| `Ctrl+S` | save to a file |
| `Ctrl+C` | copy to the clipboard |
| `Ctrl+Z` / `Ctrl+Y` | undo / redo |
| `Ctrl+0` | zoom to 1:1 |
| `Esc` | close the editor |

Expected result: the QS Click icon appears in the tray, the hotkeys are active, and launching the app again does not create a second window but shows the instance that is already running.

## Configuration

No environment variables are required. The app stores its settings in `settings.ini` (in the `%USERPROFILE%\QS Click` folder), and they can be edited from the app's Settings window.

| Setting | Default |
|---|---|
| Save format | PNG |
| JPEG quality | 92 |
| Capture hotkeys | `Ctrl+Shift+1`, `Ctrl+Shift+2`, `Ctrl+Shift+3` |
| Open editor after capture | yes |
| Start with Windows | disabled |
| Editor tool settings | persisted in the `[Editor]` section of `settings.ini` |

The About page text comes from `about.md`, located next to the executable and created automatically (hidden and read-only). You can include a ready-made file in the distribution — the app will not overwrite it, but it will set the hidden and read-only attributes on first launch.

## Structure

```text
QS PROJECT/
├─ QS_Click.dpr / QS_Click.dproj  — entry point and Delphi project (Win32/Win64, FMX)
├─ u_main_qs.pas / u_main_qs.fmx  — main window and capture launch
├─ u_qs_capture.pas               — screen and window capture, clipboard, saving
├─ u_qs_select.pas                — interactive area selection window
├─ u_qs_editor.pas                — screenshot editor
├─ u_qs_settings.pas              — settings, INI, autostart, hotkeys,
│                                   Settings window and About page
├─ u_qs_tray.pas                  — tray icon and global hotkeys
├─ u_qs_instance.pas              — second-instance guard
├─ about.md                       — About page text (for distribution)
└─ LICENSE                        — MIT license (source code)
```

## Contributing

- The application source code is provided AS IS, and no development support is planned.
- The code is provided for building your own applications, exploring its features, and practicing with Delphi 13 CE.

## License

- **Source code** in this repository is distributed under the **MIT** license — see [LICENSE](LICENSE).
- **Ready-made distribution** (installer and executable) is distributed free of charge under the terms of the [EULA](LICENSE.txt) (freeware); details are available at leiming.ru.
