<div align="center">
  
# 📂 / OBS Replay Folders

[![GitHub stars](https://img.shields.io/github/stars/ShiningPr1sm/OBS-replay-folders?style=flat-square)](https://github.com/ShiningPr1sm/OBS-replay-folders/stargazers)
[![GitHub last commit](https://img.shields.io/github/last-commit/ShiningPr1sm/OBS-replay-folders?label=last%20update&style=flat-square)](https://github.com/ShiningPr1sm/OBS-replay-folders/commits)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/ShiningPr1sm/OBS-replay-folders?label=version&style=flat-square)](https://github.com/ShiningPr1sm/OBS-replay-folders/releases)

<img width="800" height="450" alt="Preview_of_msg(1)" src="https://github.com/user-attachments/assets/b7c45bd6-4289-46e4-8fb6-c6d2dfa24d0f" />

</div>

An OBS Studio Lua script for **Windows** that:

- 📁 **Sorts saved replays into folders named after the game** you are playing (`Game/replay.mkv`).
- ✏️ Lets you set **custom folder names** for games (`witcher3` → `The Witcher 3`).
- ✅ Shows a **"Replay saved!" notification** on screen, ShadowPlay-style: a small green square with a check mark that slides in from the right edge and slides out again.

The notification does not steal focus from your game, ignores mouse clicks and does not flash a console window.

> Based on the original *OBSReplayFolders* script by **redraskal**. Modified by **ShiningPr1sm**: custom names, "Replay saved!" notification, settings panel.

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
   └── saved_notification/
       └── overlay.ps1
   ```

3. In OBS open **Tools → Scripts**, click **+** and select `OBSReplayFolders.lua`.

4. **Optional:** set the recording filename format so that the date is a **sub-folder**.
   Go to **Settings → Advanced → Recording → Filename Formatting** and use a slash, for example:

   ```
   %CCYY-%MM-%DD/%hh-%mm-%ss
   ```

   The script is designed for a filename format that puts the date in a sub-folder (%CCYY-%MM-%DD/%hh-%mm-%ss) and sorts files into {output}/{game}/{date}/{file}. If your format has no sub-folder, the folder name before the file is treated as the “date”, so the game folder is created one level above your output folder.

5. Enable the Replay Buffer in **Settings → Output → Replay Buffer**.


## Requirements

- Windows 10 / 11
- OBS Studio (with the **Replay Buffer** enabled)
- Windows PowerShell 5.1 (preinstalled on Windows 10/11)


## Usage

Save a replay the way you normally do. The script reacts to OBS's "replay buffer saved" event, so both of these work:

- the standard **Save Replay** hotkey from **Settings → Hotkeys**,
- the extra hotkey **Save replay buffer (ReplayFolders script)**, which appears in the same Hotkeys list once the script is loaded.

After the replay is saved, the script detects the fullscreen game, moves the file into `Game/date/` and shows the notification.


## Result

With the game sorting enabled:

```
HUB/
├── Witcher3/
│   └── 01_11_2026/
│       └── 12_30_05.mkv
└── Elden Ring/
    └── 01_11_2026/
        └── 18_02_44.mkv
```

With the game sorting disabled, replays stay where OBS puts them:

```
HUB/
└── 01_11_2026/
    └── 12_30_05.mkv
```


## Settings

Open **Tools → Scripts** and select the script.

| Setting | Description |
|---|---|
| **Sort replays into game folders** | On: `{game}/date/file`. Off: the file stays where OBS saved it. |
| **Show overlay on replay save** | Enables/disables the notification. |
| **Overlay mode** | `Screen` – topmost window over the desktop/game (default). `Canvas` – inside OBS (it will be **recorded**). `Both`. |
| **Text** | Notification text. Short text looks best. |
| **Show duration (seconds)** | How long the notification stays on screen. |
| **Edge margin (px)** | Distance from the top and right screen edges. |
| **Size** | Size of the square (side ≈ 7 × value, in px). Default: 16. |
| **Green background opacity (%)** | Used by `Canvas` mode. |
| **Test notification** | Shows the notification without saving a replay. |

Animation timings can be changed at the top of `saved_notification/overlay.ps1`: `$inMs`, `$outMs`, `$slideDist`.


## Custom game names

By default the folder is named after the game's `.exe` file (without `.exe`).
To use your own names create `custom_names.txt` next to the script:

```
witcher3 = The Witcher 3
eldenring = Elden Ring
RocketLeague = Rocket League
```

Format: `exe_name_without_extension = Folder name`. One game per line.
Characters that are not allowed in Windows folder names (`< > : " / \ | ? *`) are replaced with `_`.

The file is read when the script loads. After editing it, reload the script in OBS (the reload button in the Scripts window).


## How it works

1. `detect_game.dll` (loaded through LuaJIT FFI) returns the path of the running fullscreen game.
2. When OBS fires `REPLAY_BUFFER_SAVED`, the script reads the path of the last replay and moves it to `<root>/<game>/<date>/<file>`.
3. The notification is launched with `CreateProcessW` + `CREATE_NO_WINDOW`, so no console window appears. `overlay.ps1` draws a non-activating, click-through, topmost window and animates it.


## Limitations

- **Windows only.**
- The game is detected by `detect_game.dll`. If no fullscreen game is detected, the replay is **not moved** and stays in the date folder.
- The `Screen` notification is visible over borderless / windowed-fullscreen games.
  - It cannot be drawn over games running in true exclusive fullscreen mode. Use borderless mode or the `Canvas` mode.
- Only **new** replays are sorted. Existing files are not touched.


## Troubleshooting

Open **Tools → Scripts → Script Log** and look for these messages:

| Message | Meaning |
|---|---|
| `Moved replay to: ...` | Everything works. |
| `Replay not moved. ... game=nil` | No fullscreen game was detected. Try running the game in fullscreen / borderless mode. |
| `Failed to move replay (code ...)` | The file could not be moved. Check the output folder permissions. |
| `Failed to launch overlay process` | PowerShell could not be started. Check that `saved_notification/overlay.ps1` exists. |
| `Custom names file ... not found` | Not an error. Create `custom_names.txt` if you want custom names. |

If you can't create or edit files in the script folder, move the whole folder out of `Program Files` (or another protected location).


## Credits

- Original script: **redraskal**
- Modifications (custom names, notification, settings): **ShiningPr1sm**

## License

[MIT](LICENSE). Based on the original project by redraskal, which is also MIT-licensed; its copyright notice is kept in the `LICENSE` file.
