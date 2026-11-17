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
local DEFAULT_DATE_PATTERN = "{DD}_{MM}_{YYYY}"
local date_pattern = DEFAULT_DATE_PATTERN -- derived from the date folder name the user typed ("" = no date folder)
local folder_order = "game_date"        -- "game_date" (Game/Date) | "date_game" (Date/Game)
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
    if overlay_source == nil then
        overlay_create_source()
    else
        overlay_refresh_source()
    end

    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then
        return
    end

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
-- Helpers: verify that the game really has a visible fullscreen window
-- ---------------------------------------------------------------------

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
-- Date folder (computer's local time, user-editable name)
-- =====================================================================

-- The user types the folder name exactly as it should look for today's date
-- (e.g. 17.11.2026). The script finds the day / month / year inside that text
-- and stores a pattern like "{DD}.{MM}.{YYYY}", so the name updates every day.

local function pad2(n)
    return string.format("%02d", n)
end

local function date_key(t)
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function parse_date_key(str)
    local y, m, d = (str or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y == nil then
        return nil
    end
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }
end

local function render_date_pattern(pattern, t)
    local values = {
        DD = pad2(t.day), D = tostring(t.day),
        MM = pad2(t.month), M = tostring(t.month),
        YYYY = string.format("%04d", t.year), YY = pad2(t.year % 100),
    }
    return (pattern:gsub("{(%u+)}", function(k) return values[k] end))
end

local function date_token_field(token)
    return token:sub(1, 1) -- DD/D -> D, MM/M -> M, YYYY/YY -> Y
end

-- text: what the user typed; ref: the date this text was written for;
-- hint: previous pattern (only used to resolve ambiguity, e.g. day == month)
local function derive_date_pattern(text, ref, hint)
    local hint_tokens = {}
    for token in (hint or ""):gmatch("{(%u+)}") do
        hint_tokens[#hint_tokens + 1] = token
    end

    local out, used, count, pos = {}, {}, 0, 1
    while pos <= #text do
        local s_, e_ = text:find("%d+", pos)
        if s_ == nil then
            break
        end
        out[#out + 1] = text:sub(pos, s_ - 1)
        local g = text:sub(s_, e_)
        local n = tonumber(g)

        local cands = {}
        if #g == 4 and n == ref.year then
            cands[#cands + 1] = "YYYY"
        elseif #g == 2 then
            if g == pad2(ref.day) then cands[#cands + 1] = "DD" end
            if g == pad2(ref.month) then cands[#cands + 1] = "MM" end
            if g == pad2(ref.year % 100) then cands[#cands + 1] = "YY" end
        elseif #g == 1 then
            if g == tostring(ref.day) then cands[#cands + 1] = "D" end
            if g == tostring(ref.month) then cands[#cands + 1] = "M" end
        end

        local pick = nil
        local want = hint_tokens[count + 1]
        for _, c in ipairs(cands) do
            if c == want and not used[date_token_field(c)] then
                pick = c
            end
        end
        if pick == nil then
            for _, c in ipairs(cands) do
                if not used[date_token_field(c)] then
                    pick = c
                    break
                end
            end
        end

        if pick ~= nil then
            out[#out + 1] = "{" .. pick .. "}"
            used[date_token_field(pick)] = true
            count = count + 1
        else
            out[#out + 1] = g
        end
        pos = e_ + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

local function sanitize_folder_name(name)
    name = name:gsub('[<>:"/\\|?*%c]', "_")
    name = name:gsub("[%s%.]+$", "") -- Windows strips trailing spaces/dots
    return (name:match("^%s*(.-)$"))
end

local function sync_date_settings(settings)
    local today = os.date("*t")
    local pattern = obs.obs_data_get_string(settings, "date_pattern")
    local text = obs.obs_data_get_string(settings, "date_example")
    local ref_key = obs.obs_data_get_string(settings, "date_example_for")
    local ref = parse_date_key(ref_key)
    if ref == nil then
        ref = today
        ref_key = date_key(today)
    end

    if text ~= render_date_pattern(pattern, ref) then
        pattern = derive_date_pattern(text, ref, pattern)
        obs.obs_data_set_string(settings, "date_pattern", pattern)
        obs.obs_data_set_string(settings, "date_example_for", ref_key)
    elseif ref_key ~= date_key(today) then
        obs.obs_data_set_string(settings, "date_example", render_date_pattern(pattern, today))
        obs.obs_data_set_string(settings, "date_example_for", date_key(today))
    end
    date_pattern = pattern
end

local function order_preview(order, date_name)
    local game = "Game"
    if date_name == nil then
        return "Preview: invalid date folder"
    end
    if date_name == "" then
        return "Preview: " .. game .. " (no date folder)"
    end
    if order == "date_game" then
        return "Preview: " .. date_name .. " > " .. game
    end
    return "Preview: " .. game .. " > " .. date_name
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
    obs.obs_data_set_default_string(settings, "date_pattern", DEFAULT_DATE_PATTERN)
    obs.obs_data_set_default_string(settings, "date_example", render_date_pattern(DEFAULT_DATE_PATTERN, os.date("*t")))
    obs.obs_data_set_default_string(settings, "folder_order", "game_date")
    obs.obs_data_set_default_bool(settings, "ov_enabled", true)
    obs.obs_data_set_default_int(settings, "ov_duration", 3)
    obs.obs_data_set_default_int(settings, "ov_margin", 20)
    obs.obs_data_set_default_int(settings, "ov_font_size", 16)
    obs.obs_data_set_default_int(settings, "ov_back_opacity", 90)
    obs.obs_data_set_default_string(settings, "ov_text", "Replay saved!")
    obs.obs_data_set_default_string(settings, "ov_mode", "screen")
end

function script_update(settings)
    sync_date_settings(settings)
    sort_by_game = obs.obs_data_get_bool(settings, "sort_by_game")
    fallback_folder = obs.obs_data_get_string(settings, "fallback_folder")
    use_active_program = obs.obs_data_get_bool(settings, "use_active_program")
    folder_order = obs.obs_data_get_string(settings, "folder_order")
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

    local folders = obs.obs_properties_create()

    local order = obs.obs_properties_add_list(folders, "folder_order", "Folder order",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(order, "Game > Date", "game_date")
    obs.obs_property_list_add_string(order, "Date > Game", "date_game")

    local date_prop = obs.obs_properties_add_text(folders, "date_example", "Date folder name", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_long_description(date_prop,
        "Filled with today's date from your computer. Write it however you like (17.11.2026, 2026-11-17, Clips 17.11...). Day, month and year update automatically every day. Empty = no date folder.")
    local preview_prop = obs.obs_properties_add_text(folders, "date_preview", "", obs.OBS_TEXT_INFO)
    obs.obs_property_set_description(preview_prop, order_preview(folder_order, sanitize_folder_name(render_date_pattern(date_pattern, os.date("*t")))))

    local function refresh_preview(p, _, settings)
        local txt = obs.obs_data_get_string(settings, "date_example")
        local ord = obs.obs_data_get_string(settings, "folder_order")
        local pp = obs.obs_properties_get(p, "date_preview")
        obs.obs_property_set_description(pp, order_preview(ord, sanitize_folder_name(txt)))
        return true
    end
    obs.obs_property_set_modified_callback(date_prop, refresh_preview)
    obs.obs_property_set_modified_callback(order, refresh_preview)

    local active_prop = obs.obs_properties_add_bool(folders, "use_active_program", "Use focused app name")
    obs.obs_property_set_long_description(active_prop,
        "No game detected: name the folder after the focused program (Discord, Chrome...). System windows and Explorer always go to the folder below.")

    local fallback_prop = obs.obs_properties_add_text(folders, "fallback_folder", "System / unknown folder", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_long_description(fallback_prop,
        "Folder for clips made from Explorer, system windows or unknown programs. Empty = don't move such clips.")

    obs.obs_properties_add_group(props, "sort_by_game", "Sort replays into game / date folders", obs.OBS_GROUP_CHECKABLE, folders)

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

    local file_name = path:match("([^/]+)$")
    local base_dir = root_dir
    folder = folder:gsub('[<>:"/\\|?*]', "_")

    local new_date = sanitize_folder_name(render_date_pattern(date_pattern, os.date("*t")))

    local levels = {}
    if folder_order == "date_game" then
        if new_date ~= "" then table.insert(levels, new_date) end
        table.insert(levels, folder)
    else
        table.insert(levels, folder)
        if new_date ~= "" then table.insert(levels, new_date) end
    end

    local new_root = base_dir
    for _, level in ipairs(levels) do
        new_root = new_root .. "/" .. level
        if not obs.os_file_exists(new_root) then
            obs.os_mkdir(new_root)
        end
    end
    local adjusted_path = new_root .. "/" .. file_name

    local result = obs.os_rename(path, adjusted_path)
    if result == 0 then
        print("Moved replay to: " .. adjusted_path)
    else
        print("Failed to move replay (code " .. tostring(result) .. "): " .. path .. " -> " .. adjusted_path)
    end
end