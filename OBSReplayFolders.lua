obs = obslua

function script_description()
    return [[Saves replays to sub-folders using the current fullscreen video game executable name.

Author: redraskal, modified by ShiningPr1sm (Now includes custom names from "custom_names.txt")
+ "Replay saved!" overlay notification (green box, top-right)
+ Non-game windows: focused program name as folder (Discord...), system/shell windows -> Desktop]]
end

-- =====================================================================
-- Custom names
-- =====================================================================

local custom_names = {}

function load_custom_names()
    local path = script_path() .. "custom_names.txt"
    local file = io.open(path, "r")

    if file then
        print("Loading custom names from: " .. path)
        for line in file:lines() do
            local original, custom = line:match("^(%S+)%s*=%s*(.+)$")
            if original and custom then
                custom_names[original] = custom:match("^%s*(.-)%s*$")
            end
        end
        file:close()
    else
        print("Custom names file (custom_names.txt) not found. Using default names.")
    end
end

function rename_game_title(original_title)
    local new_title = custom_names[original_title]

    if new_title ~= nil and new_title ~= "" then
        return new_title
    else
        return original_title
    end
end

-- =====================================================================
-- Programs that are never treated as a game (optional file: ignored_programs.txt)
-- =====================================================================

local fallback_folder = "Desktop"   -- folder for clips when no game is detected ("" = do not move)

local ignored_exes = {}

local function load_ignored_programs()
    -- built-in list: windows that often look like a "fullscreen game" to detect_game.dll
    local defaults = {
        "ms-teams", "teams", "msedgewebview2", "microsoftstartfeedprovider",
        "widgets", "widgetservice", "searchhost", "startmenuexperiencehost",
        "shellexperiencehost", "textinputhost", "applicationframehost",
        "gamebar", "xboxgamebarwidgets", "explorer", "systemsettings", "lockapp",
        "obs64", "obs32", "obs",
    }
    for _, name in ipairs(defaults) do
        ignored_exes[name] = true
    end

    local path = script_path() .. "ignored_programs.txt"
    local file = io.open(path, "r")
    if file then
        print("Loading ignored programs from: " .. path)
        for line in file:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 1) ~= ";" then
                line = line:gsub("%.[eE][xX][eE]$", ""):lower()
                ignored_exes[line] = true
            end
        end
        file:close()
    end
end

-- =====================================================================
-- "Replay saved!" overlay (green box, top-right of the canvas)
-- =====================================================================

local sort_by_game = true       -- move replays into folders organized by game
local use_active_program = true -- no game detected: name the folder after the focused program (Discord, Chrome...); system stuff -> fallback_folder
local overlay_enabled = true
local overlay_duration = 3      -- seconds
local overlay_margin = 20       -- px from top/right edge
local overlay_font_size = 16
local overlay_back_opacity = 90 -- % of green background opacity
local overlay_text = "Replay saved!"
local overlay_mode = "screen"   -- "screen" (topmost OS window) | "canvas" (inside OBS) | "both"

local overlay_source = nil
local overlay_sceneitem = nil
local overlay_font_size_applied = nil

local function make_color(r, g, b, a)
    local bit = require("bit")
    return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r)
end

local function overlay_create_source()
    local s = obs.obs_data_create()
    obs.obs_data_set_string(s, "text", overlay_text)

    local font = obs.obs_data_create()
    obs.obs_data_set_string(font, "face", "Segoe UI")
    obs.obs_data_set_int(font, "size", overlay_font_size)
    obs.obs_data_set_int(font, "flags", 16) -- bold
    obs.obs_data_set_obj(s, "font", font)
    obs.obs_data_release(font)

    -- green rectangle behind the text: RGB(46, 204, 113)
    local a = math.floor(255 * overlay_back_opacity / 100 + 0.5)
    obs.obs_data_set_int(s, "back_color", make_color(46, 204, 113, a))

    -- white text
    obs.obs_data_set_int(s, "color", make_color(255, 255, 255, 255))
    obs.obs_data_set_bool(s, "outline", false)

    overlay_source = obs.obs_source_create("text_gdiplus", "replay_saved_overlay", s, nil)
    obs.obs_data_release(s)
    overlay_font_size_applied = overlay_font_size
end

local function overlay_refresh_source()
    if overlay_source == nil then
        return
    end
    if overlay_font_size_applied ~= overlay_font_size then
        local s = obs.obs_data_create()
        obs.obs_data_set_string(s, "text", overlay_text)
        local font = obs.obs_data_create()
        obs.obs_data_set_string(font, "face", "Segoe UI")
        obs.obs_data_set_int(font, "size", overlay_font_size)
        obs.obs_data_set_int(font, "flags", 16)
        obs.obs_data_set_obj(s, "font", font)
        obs.obs_data_release(font)
        local a = math.floor(255 * overlay_back_opacity / 100 + 0.5)
        obs.obs_data_set_int(s, "back_color", make_color(46, 204, 113, a))
        obs.obs_data_set_int(s, "color", make_color(255, 255, 255, 255))
        obs.obs_source_update(overlay_source, s)
        obs.obs_data_release(s)
        overlay_font_size_applied = overlay_font_size
    end
end

local function overlay_hide()
    obs.timer_remove(overlay_hide)
    if overlay_sceneitem ~= nil then
        obs.obs_sceneitem_remove(overlay_sceneitem)
        obs.obs_sceneitem_release(overlay_sceneitem)
        overlay_sceneitem = nil
    end
end

function overlay_show_canvas()
    -- (re)create the source on first use
    if overlay_source == nil then
        overlay_create_source()
    else
        overlay_refresh_source()
    end

    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then
        return
    end

    -- make sure it is not shown in some other scene already
    local already = overlay_sceneitem ~= nil
    if already then
        overlay_hide()
        scene_source = obs.obs_frontend_get_current_scene()
        if scene_source == nil then
            return
        end
    end

    local scene = obs.obs_scene_from_source(scene_source)
    overlay_sceneitem = obs.obs_scene_add(scene, overlay_source)
    obs.obs_source_release(scene_source)

    -- position: top-right corner with a margin
    local cx, cy = 1920, 1080
    local ovi = obs.obs_video_info()
    if obs.obs_get_video_info(ovi) then
        cx, cy = ovi.base_width, ovi.base_height
    end

    local w = obs.obs_source_get_width(overlay_source)
    local h = obs.obs_source_get_height(overlay_source)

    local pos = obs.vec2()
    pos.x = cx - w - overlay_margin
    pos.y = overlay_margin
    obs.obs_sceneitem_set_pos(overlay_sceneitem, pos)

    -- show for N seconds, then hide
    obs.timer_remove(overlay_hide)
    obs.timer_add(overlay_hide, math.max(1, overlay_duration) * 1000)
end

local winapi_ready = false
local function winapi_init()
    if winapi_ready then return end
    local ffi = require("ffi")
    ffi.cdef[[
        typedef struct {
            uint32_t cb;
            uint16_t* lpReserved;
            uint16_t* lpDesktop;
            uint16_t* lpTitle;
            uint32_t dwX, dwY, dwXSize, dwYSize;
            uint32_t dwXCountChars, dwYCountChars, dwFillAttribute;
            uint32_t dwFlags;
            uint16_t wShowWindow, cbReserved2;
            uint8_t* lpReserved2;
            void* hStdInput;
            void* hStdOutput;
            void* hStdError;
        } STARTUPINFOW_L;

        typedef struct {
            void* hProcess;
            void* hThread;
            uint32_t dwProcessId;
            uint32_t dwThreadId;
        } PROCESS_INFORMATION_L;

        int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char* s, int n, uint16_t* out, int outn);
        int CreateProcessW(const uint16_t* app, uint16_t* cmd, void* pa, void* ta, int inherit,
                           uint32_t flags, void* env, const uint16_t* cwd,
                           STARTUPINFOW_L* si, PROCESS_INFORMATION_L* pi);
        int CloseHandle(void* h);

        typedef struct { int32_t left, top, right, bottom; } RECT_L;
        typedef struct { uint32_t cbSize; RECT_L rcMonitor; RECT_L rcWork; uint32_t dwFlags; } MONITORINFO_L;

        void* GetForegroundWindow(void);
        void* GetTopWindow(void* hwnd);
        void* GetWindow(void* hwnd, uint32_t cmd);
        int IsWindowVisible(void* hwnd);
        int IsIconic(void* hwnd);
        int GetWindowRect(void* hwnd, RECT_L* r);
        void* MonitorFromWindow(void* hwnd, uint32_t flags);
        int GetMonitorInfoW(void* mon, MONITORINFO_L* mi);
        uint32_t GetWindowThreadProcessId(void* hwnd, uint32_t* pid);
        void* OpenProcess(uint32_t access, int inherit, uint32_t pid);
        int QueryFullProcessImageNameW(void* proc, uint32_t flags, uint16_t* buf, uint32_t* size);
        int WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t* ws, int n,
                                char* out, int outn, const char* def, int* used);
        int RemoveDirectoryW(const uint16_t* path);
        int32_t GetWindowLongW(void* hwnd, int idx);
        int32_t DwmGetWindowAttribute(void* hwnd, uint32_t attr, void* pv, uint32_t cb);
    ]]
    winapi_ready = true
end

local function run_hidden(cmdline)
    winapi_init()
    local ffi = require("ffi")
    local C = ffi.C

    local n = C.MultiByteToWideChar(65001, 0, cmdline, -1, nil, 0) -- CP_UTF8
    local wbuf = ffi.new("uint16_t[?]", n)
    C.MultiByteToWideChar(65001, 0, cmdline, -1, wbuf, n)

    local si = ffi.new("STARTUPINFOW_L")
    si.cb = ffi.sizeof(si)
    si.dwFlags = 1      -- STARTF_USESHOWWINDOW
    si.wShowWindow = 0  -- SW_HIDE
    local pi = ffi.new("PROCESS_INFORMATION_L")

    -- CREATE_NO_WINDOW = 0x08000000
    local ok = C.CreateProcessW(nil, wbuf, nil, nil, 0, 0x08000000, nil, nil, si, pi)
    if ok ~= 0 then
        C.CloseHandle(pi.hProcess)
        C.CloseHandle(pi.hThread)
        return true
    end
    return false
end


-- ---------------------------------------------------------------------
-- Helpers: remove empty folder, verify that the game really has a
-- visible fullscreen window
-- ---------------------------------------------------------------------

local function to_wide(str)
    local ffi = require("ffi")
    local n = ffi.C.MultiByteToWideChar(65001, 0, str, -1, nil, 0)
    local buf = ffi.new("uint16_t[?]", n)
    ffi.C.MultiByteToWideChar(65001, 0, str, -1, buf, n)
    return buf
end

-- RemoveDirectory fails on a non-empty folder, so this is safe:
-- only an EMPTY folder gets deleted.
local function remove_dir_if_empty(dir)
    winapi_init()
    local ffi = require("ffi")
    local wdir = to_wide((dir:gsub("/", "\\")))
    return ffi.C.RemoveDirectoryW(wdir) ~= 0
end

local function exe_basename(path)
    local name = path:match("([^\\/]+)$")
    if name == nil then return nil end
    return name:lower()
end

local function window_exe_path(hwnd)
    local ffi = require("ffi")
    local C = ffi.C
    local pid = ffi.new("uint32_t[1]")
    C.GetWindowThreadProcessId(hwnd, pid)
    local proc = C.OpenProcess(0x1000, 0, pid[0]) -- PROCESS_QUERY_LIMITED_INFORMATION
    if proc == nil then
        return nil
    end
    local buf = ffi.new("uint16_t[1024]")
    local size = ffi.new("uint32_t[1]", 1024)
    local ok = C.QueryFullProcessImageNameW(proc, 0, buf, size)
    C.CloseHandle(proc)
    if ok == 0 then
        return nil
    end
    local out = ffi.new("char[2048]")
    local n = C.WideCharToMultiByte(65001, 0, buf, size[0], out, 2048, nil, nil)
    if n <= 0 then
        return nil
    end
    return ffi.string(out, n)
end

local dwm_lib = nil
local function window_is_cloaked(hwnd)
    local ffi = require("ffi")
    if dwm_lib == nil then
        local ok, lib = pcall(ffi.load, "dwmapi")
        dwm_lib = ok and lib or false
    end
    if not dwm_lib then
        return false
    end
    local v = ffi.new("int[1]")
    local hr = dwm_lib.DwmGetWindowAttribute(hwnd, 14, v, 4) -- DWMWA_CLOAKED
    return hr == 0 and v[0] ~= 0
end

-- detect_game.dll only looks at window SIZE, so a hidden/minimized/cloaked window
-- of a tray app (Teams, etc.) can be reported as a "game".
-- Here we check that this exe has a really visible window covering its monitor.
-- If anything goes wrong in the check, we trust the DLL (old behaviour).
local function game_has_fullscreen_window(game_path)
    local ok, res = pcall(function()
        winapi_init()
        local ffi = require("ffi")
        local C = ffi.C

        local target = exe_basename(game_path)
        if target == nil or target:find("[\128-\255]") then
            return true -- non-ASCII name: cannot compare reliably, trust the DLL
        end

        local bit = require("bit")
        local rect = ffi.new("RECT_L")
        local mi = ffi.new("MONITORINFO_L")
        mi.cbSize = ffi.sizeof(mi)

        local h = C.GetTopWindow(nil)
        local guard = 0
        while h ~= nil and guard < 5000 do
            guard = guard + 1
            -- skip overlay-like windows: NOACTIVATE (0x08000000), TRANSPARENT (0x20), TOOLWINDOW (0x80)
            local ex = C.GetWindowLongW(h, -20) -- GWL_EXSTYLE
            local is_overlay = bit.band(ex, 0x08000000) ~= 0 or bit.band(ex, 0x20) ~= 0 or bit.band(ex, 0x80) ~= 0

            if not is_overlay and C.IsWindowVisible(h) ~= 0 and C.IsIconic(h) == 0 and not window_is_cloaked(h) then
                if C.GetWindowRect(h, rect) ~= 0 then
                    local mon = C.MonitorFromWindow(h, 2) -- MONITOR_DEFAULTTONEAREST
                    if mon ~= nil and C.GetMonitorInfoW(mon, mi) ~= 0 then
                        local m = mi.rcMonitor
                        if rect.left <= m.left and rect.top <= m.top
                            and rect.right >= m.right and rect.bottom >= m.bottom then
                            local exe = window_exe_path(h)
                            if exe ~= nil and exe_basename(exe) == target then
                                return true
                            end
                        end
                    end
                end
            end
            h = C.GetWindow(h, 2) -- GW_HWNDNEXT
        end
        return false
    end)

    if not ok then
        print("Fullscreen check failed (" .. tostring(res) .. "), trusting detect_game.dll")
        return true
    end
    return res
end

-- ---------------------------------------------------------------------
-- Program classification: "real program" (folder = its name) vs
-- "system/shell stuff" (folder = fallback, e.g. Desktop)
-- ---------------------------------------------------------------------

local function program_name_from_path(path)
    local base = path:match("([^\\/]+)$")
    if base == nil then return nil end
    return (base:gsub("%.[eE][xX][eE]$", ""))
end

-- Anything that lives inside the Windows folder or is a built-in Windows
-- shell package (Start feed, widgets, search, Game Bar...) is never a game/app.
-- Games from the Microsoft Store (WindowsApps\Microsoft.Minecraft..., XboxGames) are NOT affected.
local function is_system_path(path)
    local p = path:gsub("/", "\\"):lower()
    local win = ((os.getenv("SystemRoot") or "C:\\Windows"):gsub("/", "\\"):lower()) .. "\\"
    if p:sub(1, #win) == win then
        return true
    end
    local patterns = {
        "\\windowsapps\\microsoftwindows%.",
        "\\windowsapps\\microsoft%.windows%.",
        "\\windowsapps\\microsoft%.xboxgamingoverlay",
        "\\windowsapps\\microsoft%.xbox%.tcui",
    }
    for _, pat in ipairs(patterns) do
        if p:find(pat) then
            return true
        end
    end
    return false
end

local function is_ignored_program(path, name)
    if is_system_path(path) then
        return true, "system path"
    end
    if name ~= nil and ignored_exes[name:lower()] then
        return true, "ignored programs list"
    end
    return false
end

-- Program that currently has focus (Discord, Chrome, ...). nil when focus is on
-- Explorer / desktop / taskbar / OBS itself / any system or ignored process.
local function get_foreground_program_title()
    local ok, res = pcall(function()
        winapi_init()
        local ffi = require("ffi")
        local hwnd = ffi.C.GetForegroundWindow()
        if hwnd == nil then
            return nil
        end
        local exe = window_exe_path(hwnd)
        if exe == nil then
            return nil
        end
        local name = program_name_from_path(exe)
        if name == nil or name == "" then
            return nil
        end
        local ignored, why = is_ignored_program(exe, name)
        if ignored then
            print("Active program '" .. name .. "' ignored (" .. why .. ")")
            return nil
        end
        return name
    end)
    if not ok then
        print("Active program check failed: " .. tostring(res))
        return nil
    end
    return res
end

local function launch_screen_overlay()
    local dir = (script_path() .. "saved_notification/"):gsub("/", "\\")
    local ps = (os.getenv("SystemRoot") or "C:\\Windows") ..
        "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    local text = overlay_text:gsub('"', '\\"')
    local cmd = string.format(
        '"%s" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%soverlay.ps1" -Text "%s" -Duration %d -Margin %d -FontSize %d',
        ps, dir, text, math.max(1, overlay_duration), overlay_margin, overlay_font_size)
    if not run_hidden(cmd) then
        print("Failed to launch overlay process")
    end
end

function overlay_show()
    if not overlay_enabled then
        return
    end

    if overlay_mode == "canvas" or overlay_mode == "both" then
        overlay_show_canvas()
    end
    if overlay_mode == "screen" or overlay_mode == "both" then
        launch_screen_overlay()
    end
end

-- =====================================================================
-- Game detection / folder logic
-- =====================================================================

function script_load(settings)
    ffi = require("ffi")
    ffi.cdef[[
        int get_running_fullscreen_game_path(char* buffer, int bufferSize)
    ]]
    detect_game = ffi.load(script_path() .. "detect_game.dll")

    load_custom_names()
    load_ignored_programs()

    -- optional extra hotkey: saves the replay buffer (event + overlay follow automatically)
    hotkey_id = obs.obs_hotkey_register_frontend("replay_save_hotkey", "Save replay buffer (ReplayFolders script)", function(pressed)
        if pressed then
            obs.obs_frontend_replay_buffer_save()
        end
    end)
    local hotkey_arr = obs.obs_data_get_array(settings, "replay_save_hotkey")
    obs.obs_hotkey_load(hotkey_id, hotkey_arr)
    obs.obs_data_array_release(hotkey_arr)

    obs.obs_frontend_add_event_callback(obs_frontend_callback)
end

function script_save(settings)
    local hotkey_arr = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "replay_save_hotkey", hotkey_arr)
    obs.obs_data_array_release(hotkey_arr)
end

function script_unload()
    obs.hotkey_unregister(hotkey_id)
    obs.timer_remove(overlay_hide)
    overlay_hide()
    if overlay_source ~= nil then
        obs.obs_source_release(overlay_source)
        overlay_source = nil
    end
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "sort_by_game", true)
    obs.obs_data_set_default_string(settings, "fallback_folder", "Desktop")
    obs.obs_data_set_default_bool(settings, "use_active_program", true)
    obs.obs_data_set_default_bool(settings, "ov_enabled", true)
    obs.obs_data_set_default_int(settings, "ov_duration", 3)
    obs.obs_data_set_default_int(settings, "ov_margin", 20)
    obs.obs_data_set_default_int(settings, "ov_font_size", 16)
    obs.obs_data_set_default_int(settings, "ov_back_opacity", 90)
    obs.obs_data_set_default_string(settings, "ov_text", "Replay saved!")
    obs.obs_data_set_default_string(settings, "ov_mode", "screen")
end

function script_update(settings)
    sort_by_game = obs.obs_data_get_bool(settings, "sort_by_game")
    fallback_folder = obs.obs_data_get_string(settings, "fallback_folder")
    use_active_program = obs.obs_data_get_bool(settings, "use_active_program")
    overlay_enabled = obs.obs_data_get_bool(settings, "ov_enabled")
    overlay_duration = obs.obs_data_get_int(settings, "ov_duration")
    overlay_margin = obs.obs_data_get_int(settings, "ov_margin")
    overlay_font_size = obs.obs_data_get_int(settings, "ov_font_size")
    overlay_back_opacity = obs.obs_data_get_int(settings, "ov_back_opacity")
    overlay_text = obs.obs_data_get_string(settings, "ov_text")
    overlay_mode = obs.obs_data_get_string(settings, "ov_mode")
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "sort_by_game", "Sort replays into game folders  ({game}/{your_path_at_settings})")

    obs.obs_properties_add_bool(props, "use_active_program", "No game detected: use the focused program name as folder (Discord, Chrome...)")

    obs.obs_properties_add_text(props, "fallback_folder", "Folder for system windows / Explorer / unknown (empty = don't move)", obs.OBS_TEXT_DEFAULT)

    local overlay_group = obs.obs_properties_create()
    obs.obs_properties_add_bool(overlay_group, "ov_enabled", "Show overlay on replay save")
    local mode = obs.obs_properties_add_list(overlay_group, "ov_mode", "Overlay mode",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(mode, "Screen (topmost window, like ShadowPlay)", "screen")
    obs.obs_property_list_add_string(mode, "Canvas (inside OBS output)", "canvas")
    obs.obs_property_list_add_string(mode, "Both", "both")
    obs.obs_properties_add_text(overlay_group, "ov_text", "Text", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int_slider(overlay_group, "ov_duration", "Show duration (seconds)", 1, 15, 1)
    obs.obs_properties_add_int_slider(overlay_group, "ov_margin", "Edge margin (px)", 0, 300, 5)
    obs.obs_properties_add_int_slider(overlay_group, "ov_font_size", "Size (square side ≈ 7× this, px)", 8, 40, 1)
    obs.obs_properties_add_int_slider(overlay_group, "ov_back_opacity", "Green background opacity (%)", 0, 100, 1)
    obs.obs_properties_add_button(overlay_group, "ov_test", "Test notification", function()
        overlay_show()
        return true
    end)
    obs.obs_properties_add_group(props, "overlay_grp", "Replay saved notification", obs.OBS_GROUP_NORMAL, overlay_group)


    return props
end

function obs_frontend_callback(event)
    if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED then
        if sort_by_game then
            local path = get_replay_buffer_output()
            local original_folder = get_running_game_title()
            if original_folder == nil and use_active_program then
                original_folder = get_foreground_program_title()
            end

            local folder
            if original_folder ~= nil then
                folder = rename_game_title(original_folder)
            elseif fallback_folder ~= nil and fallback_folder ~= "" then
                folder = fallback_folder
            end

            if path ~= nil and folder ~= nil then
                move(path, folder)
            else
                print("Replay not moved. path=" .. tostring(path) .. ", game=" .. tostring(folder) ..
                      " (no game detected and no fallback folder set)")
            end
        end

        overlay_show()
    end
end

function get_replay_buffer_output()
    local replay_buffer = obs.obs_frontend_get_replay_buffer_output()
    local cd = obs.calldata_create()
    local ph = obs.obs_output_get_proc_handler(replay_buffer)
    obs.proc_handler_call(ph, "get_last_replay", cd)
    local path = obs.calldata_string(cd, "path")
    obs.calldata_destroy(cd)
    obs.obs_output_release(replay_buffer)
    return path
end

function get_running_game_title()
    local path = ffi.new("char[?]", 260)
    local result = detect_game.get_running_fullscreen_game_path(path, 260)
    if result ~= 0 then
        return nil
    end
    result = ffi.string(path)
    local len = #result
    if len == 0 then
        return nil
    end
    local name = program_name_from_path(result)
    if name == nil or name == "" then
        return nil
    end
    local ignored, why = is_ignored_program(result, name)
    if ignored then
        print("Ignoring '" .. name .. "' (" .. why .. ")")
        return nil
    end
    if not game_has_fullscreen_window(result) then
        print("Ignoring '" .. result .. "': no visible fullscreen window (not a game)")
        return nil
    end
    return name
end

function move(path, folder)
    path = path:gsub("\\", "/")

    local root_dir = path:match("^(.*)/")
    if root_dir == nil then
        print("move(): cannot parse path: " .. path)
        return
    end
    local date_folder = root_dir:match("([^/]+)/*$")
    local file_name = path:match("([^/]+)$")

    local base_dir = root_dir:sub(1, root_dir:len() - date_folder:len() - 1)

    folder = folder:gsub('[<>:"/\\|?*]', "_")

    local game_dir = base_dir .. "/" .. folder
    local new_root = game_dir .. "/" .. date_folder
    local adjusted_path = new_root .. "/" .. file_name

    if not obs.os_file_exists(game_dir) then
        obs.os_mkdir(game_dir)
    end
    if not obs.os_file_exists(new_root) then
        obs.os_mkdir(new_root)
    end

    local result = obs.os_rename(path, adjusted_path)
    if result == 0 then
        print("Moved replay to: " .. adjusted_path)
        -- the original date folder is now empty -> remove it (non-empty folders are never deleted)
        if root_dir ~= new_root and remove_dir_if_empty(root_dir) then
            print("Removed empty folder: " .. root_dir)
        end
    else
        print("Failed to move replay (code " .. tostring(result) .. "): " .. path .. " -> " .. adjusted_path)
    end
end