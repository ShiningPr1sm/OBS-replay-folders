obs = obslua

function script_description()
    return [[Saves replays to sub-folders using the current fullscreen video game executable name.

Author: redraskal, modified by ShiningPr1sm (Now includes custom names from "custom_names.txt")
+ "Replay saved!" overlay notification (green box, top-right)]]
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
-- "Replay saved!" overlay (green box, top-right of the canvas)
-- =====================================================================

local sort_by_game = true       -- move replays into folders organized by game
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

            local folder = rename_game_title(original_folder)

            if path ~= nil and folder ~= nil then
                move(path, folder)
            else
                print("Replay not moved. path=" .. tostring(path) .. ", game=" .. tostring(folder) ..
                      " (game not detected as fullscreen?)")
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
    local max = len - 4
    local i = max
    while i > 1 do
        local char = result:sub(i, i)
        if char == "\\" or char == "/" then
            break
        end
        i = i - 1
    end
    return result:sub(i + 1, max)
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
    else
        print("Failed to move replay (code " .. tostring(result) .. "): " .. path .. " -> " .. adjusted_path)
    end
end