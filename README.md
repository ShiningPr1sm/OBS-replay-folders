<div align="center">
  
# 📂 / OBS Replay Folders

[![GitHub stars](https://img.shields.io/github/stars/ShiningPr1sm/OBS-replay-folders?style=flat-square)](https://github.com/ShiningPr1sm/OBS-replay-folders/stargazers)
[![GitHub last commit](https://img.shields.io/github/last-commit/ShiningPr1sm/OBS-replay-folders?label=last%20update&style=flat-square)](https://github.com/ShiningPr1sm/OBS-replay-folders/commits)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/ShiningPr1sm/OBS-replay-folders?label=version&style=flat-square)](https://github.com/ShiningPr1sm/OBS-replay-folders/releases)

<img width="800" height="450" alt="Preview_of_msg(1)" src="https://github.com/user-attachments/assets/b7c45bd6-4289-46e4-8fb6-c6d2dfa24d0f" />

</div>

An OBS Studio Lua script for **Windows** that:

- 📁 **Sorts saved replays into folders** named after the game you are playing, plus a **date folder** (`Game/17_11_2026/replay.mkv`).
- 🔀 Lets you choose the **folder order** (`Game > Date` or `Date > Game`) and the **look of the date folder name** (`17_11_2026`, `17.11.2026`, `2026-11-17`...).
- 🖥️ Names the folder after the **focused program** (Discord, Chrome...) when no game is running, and sends Explorer / system windows to a **`Desktop`** folder instead of a strange name like `MicrosoftStartFeedProvider`.
- ✏️ Lets you set **custom folder names** (`witcher3` → `The Witcher 3`).
- ✅ Shows a **"Replay saved!" notification** on screen, ShadowPlay-style: a small green square with a check mark that slides in from the right edge and slides out again.

The notification does not steal focus from your game, ignores mouse clicks and does not flash a console window.

> Based on the original *OBSReplayFolders* script by **redraskal**. Modified by **ShiningPr1sm**: custom names, "Replay saved!" notification, date folders, focused-program folders, settings panel.

---

## Installation

1. Put all files in a folder where you have write access, **not** in `C:\Program Files\...`.
   For example: `C:\Users\<you>\Documents\OBS_Scripts\ReplayFolders\`

2. The folder must look like this:

   ```
   ReplayFolders/
   ├── OBSReplayFolders.lua
   ├── detect_game.dll
   ├── custom_names.txt            (optional)
   ├── ignored_programs.txt        (optional)
   └── saved_notification/
       └── overlay.ps1
   ```

3. In OBS open **Tools → Scripts**, click **+** and select `OBSReplayFolders.lua`.

4. Set the recording filename format **without a sub-folder**.
   Go to **Settings → Advanced → Recording → Filename Formatting** and use only the file name, for example:

   ```
   %hh_%mm_%ss
   ```

   The script creates the game and date folders itself, **directly inside your recording folder**. Do **not** put a slash in the format (e.g. `%CCYY-%MM-%DD/%hh-%mm-%ss`): the script would treat that sub-folder as the recording folder and create the game folders inside it.

   > The filename format also applies to regular recordings, and the script only sorts **replays**. Regular recordings simply stay in the recording folder.

5. Enable the Replay Buffer in **Settings → Output → Replay Buffer**.


## Requirements

- Windows 10 / 11
- OBS Studio (with the **Replay Buffer** enabled)
- Windows PowerShell 5.1 (preinstalled on Windows 10/11)


## Usage

Save a replay the way you normally do. The script reacts to OBS's "replay buffer saved" event, so both of these work:

- the standard **Save Replay** hotkey from **Settings → Hotkeys**,
- the extra hotkey **Save replay buffer (ReplayFolders script)**, which appears in the same Hotkeys list once the script is loaded.

After the replay is saved, the script works out the folder name, moves the file there and shows the notification.

### Which folder does a replay go to?

1. **A fullscreen game is running** → the folder is named after the game (`witcher3`, or your custom name).
2. **No game, but a regular program has focus** (Discord, Chrome...) → the folder is named after that program. You can turn this off.
3. **Explorer, the desktop, the taskbar, system windows, OBS itself or an unknown program has focus** → the clip goes to the `Desktop` folder.

The date folder is added according to your settings (see below).


## Result

With sorting enabled and the order **Game > Date**:

```
HUB/
├── Witcher3/
│   └── 17_11_2026/
│       └── 12_30_05.mkv
├── Discord/
│   └── 17_11_2026/
│       └── 18_02_44.mkv
└── Desktop/
    └── 17_11_2026/
        └── 18_40_10.mkv
```

With the order **Date > Game**:

```
HUB/
└── 17_11_2026/
    ├── Witcher3/
    │   └── 12_30_05.mkv
    └── Desktop/
        └── 18_40_10.mkv
```

With sorting disabled, replays stay where OBS puts them:

```
HUB/
└── 12_30_05.mkv
```


## Settings

Open **Tools → Scripts** and select the script. Hover over a field to see a tooltip.

### Folders

The whole block is switched on and off with the checkbox in its title.

| Setting | Description |
|---|---|
| **Sort replays into game / date folders** | On: replays are moved into the folders below. Off: the file stays where OBS saved it. |
| **Folder order** | `Game > Date` → `HUB/Game/17_11_2026/file`. `Date > Game` → `HUB/17_11_2026/Game/file`. |
| **Date folder name** | Filled with **today's date from your computer**. Edit it however you like, the preview below the field shows the result. Empty = no date folder. See [Date folder name](#date-folder-name). |
| **Use focused app name** | On (default): if no game is detected, the folder is named after the focused program (Discord, Chrome...). Off: all non-game clips go to the folder below. |
| **System / unknown folder** | Folder for clips made while Explorer, a system window or an unknown program has focus. Default: `Desktop`. Empty = such clips are **not moved**. |

### Notification

| Setting | Description |
|---|---|
| **Show overlay on replay save** | Enables/disables the notification. |
| **Overlay mode** | `Screen` – topmost window over the desktop/game (default). `Canvas` – inside OBS (it will be **recorded**). `Both`. |
| **Text** | Notification text. Short text looks best. |
| **Show duration (seconds)** | How long the notification stays on screen. |
| **Edge margin (px)** | Distance from the top and right screen edges. |
| **Size** | Size of the square (side ≈ 7 × value, in px). Default: 16. |
| **Green background opacity (%)** | Used by `Canvas` mode. |
| **Test notification** | Shows the notification without saving a replay. |

Animation timings can be changed at the top of `saved_notification/overlay.ps1`: `$inMs`, `$outMs`, `$slideDist`.


## Date folder name

You do not write a format code. Just type the folder name **the way you want to see it for today's date**:

| You type (on 17 Nov 2026) | Folder name every day |
|---|---|
| `17_11_2026` (default) | `18_11_2026` tomorrow, and so on |
| `17.11.2026` | `18.11.2026` |
| `2026-11-17` | `2026-11-18` |
| `17-11-26` | `18-11-26` |
| `Clips 17.11.2026` | `Clips 18.11.2026` |

The script finds the day, month and year in the text, remembers where they are and fills in the new date automatically. Any other text and separators stay unchanged. The field shows today's date again each time the script loads.

Notes:

- The day and month are found by matching the numbers with today's date. If they are the same number (e.g. `11.11.2026`), the script keeps the previous order (day first, then month). It is better to change the name on a day when they differ.
- Month names written in words (`17 November`) are **not** recognized and stay as plain text.
- Characters that are not allowed in Windows folder names (`< > : " / \ | ? *`) are replaced with `_`.
- Leave the field empty if you don't want a date folder at all.


## Custom game names

By default the folder is named after the program's `.exe` file (without `.exe`).
To use your own names create `custom_names.txt` next to the script:

```
witcher3 = The Witcher 3
eldenring = Elden Ring
RocketLeague = Rocket League
Discord = Chat
```

Format: `exe_name_without_extension = Folder name`. One program per line. Custom names work both for games and for focused programs.
Characters that are not allowed in Windows folder names are replaced with `_`.

The file is read when the script loads. After editing it, reload the script in OBS (the reload button in the Scripts window).


## Ignored programs

Some windows look like a fullscreen game to the detection (tray apps, widgets, Start menu components...). The script ignores them automatically:

- everything located in the **Windows folder** (Explorer, search, shell experience hosts...),
- built-in Windows shell packages (Start feed, widgets, Game Bar...). **Microsoft Store / Xbox games are not affected.**
- a built-in list of known names (`teams`, `msedgewebview2`, `widgets`, `explorer`, `obs64`...),
- a window that has no really **visible, non-minimized fullscreen window** (such as a hidden tray app).

Ignored programs never get their own folder: their clips go to the `Desktop` folder.

To add your own, create `ignored_programs.txt` next to the script:

```
# one program per line, with or without .exe, case does not matter
SomeLauncher.exe
overwolf
; this is a comment too
```

The file is read when the script loads.


## How it works

1. `detect_game.dll` (loaded through LuaJIT FFI) returns the path of the running fullscreen game. The script drops it if it is a system or ignored program, or if that program has no visible window covering the monitor.
2. If there is no game, the script looks at the program that currently has focus (`GetForegroundWindow`). System windows, ignored programs and OBS itself are skipped. If nothing is left, the `System / unknown folder` is used.
3. When OBS fires `REPLAY_BUFFER_SAVED`, the script reads the path of the last replay and moves it to `<recording folder>/<game>/<date>/<file>` (or `<date>/<game>`). The date name is built from your pattern and the computer's local time.
4. The notification is launched with `CreateProcessW` + `CREATE_NO_WINDOW`, so no console window appears. `overlay.ps1` draws a non-activating, click-through, topmost window and animates it.


## Limitations

- **Windows only.**
- The recording filename format must have **no sub-folder** (see [Installation](#installation)).
- Only **replays** are sorted. Regular recordings and existing files are not touched.
- The game is detected by `detect_game.dll`. If it finds nothing, the focused program (or `Desktop`) is used. If you clear the `System / unknown folder` field, such clips are **not moved** and stay in the recording folder.
- The `Screen` notification is visible over borderless / windowed-fullscreen games.
  - It cannot be drawn over games running in true exclusive fullscreen mode. Use borderless mode or the `Canvas` mode.
- Month names in words are not supported in the date folder name.


## Troubleshooting

Open **Tools → Scripts → Script Log** and look for these messages:

| Message | Meaning |
|---|---|
| `Moved replay to: ...` | Everything works. |
| `Ignoring 'X' (system path)` / `(ignored programs list)` | `X` was detected as a game, but it is a system or ignored program. The clip goes to the `Desktop` folder. |
| `Ignoring '...': no visible fullscreen window (not a game)` | A hidden or minimized program was reported by the DLL. It is not treated as a game. |
| `Active program 'X' ignored (...)` | The focused program is a system or ignored one, so the `Desktop` folder is used. |
| `Replay not moved. ...` | No game and no program were found, and the `System / unknown folder` field is empty. |
| `Failed to move replay (code ...)` | The file could not be moved. Check the output folder permissions. |
| `Failed to launch overlay process` | PowerShell could not be started. Check that `saved_notification/overlay.ps1` exists. |
| `Custom names file ... not found` | Not an error. Create `custom_names.txt` if you want custom names. |

A folder with a wrong name appeared? Add that program to `ignored_programs.txt`, or give it a nicer name in `custom_names.txt`.

Game folders appear in a strange place (e.g. inside a date folder)? Check that the **Filename Formatting** in OBS has no `/`.

If you can't create or edit files in the script folder, move the whole folder out of `Program Files` (or another protected location).


## Credits

- Original script: **redraskal**
- Modifications (custom names, notification, date folders, focused-program folders, settings): **ShiningPr1sm**

## License

[MIT](LICENSE). Based on the original project by redraskal, which is also MIT-licensed; its copyright notice is kept in the `LICENSE` file.
