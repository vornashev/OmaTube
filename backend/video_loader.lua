local mp = require "mp"

local frames = { "◴", "◷", "◶", "◵" }
local frame = 1
local visible = false
local hovered = false
local active_token = ""
local requested = false
local seeking = false
local paused_for_cache = false
local core_idle = false
local paused = true
local overlay = mp.create_osd_overlay("ass-events")

local function render()
    if not visible then
        overlay:remove()
        return
    end

    local width, height = mp.get_osd_size()
    if width <= 0 or height <= 0 then
        return
    end

    local center_x = math.floor(width / 2)
    local center_y = math.floor(height / 2)
    overlay.res_x = width
    overlay.res_y = height
    overlay.data = string.format(
        "{\\an5\\pos(%d,%d)\\fs48\\bord2\\shad0\\1c&HFFFFFF&\\3c&H28232E&}%s",
        center_x, center_y, frames[frame]
    )
    if hovered then
        overlay.data = overlay.data .. string.format(
            "{\\an8\\pos(%d,%d)\\fs18\\bord3\\shad0\\1c&HFFFFFF&\\3c&H28232E&}%s",
            center_x, center_y + 58,
            paused_for_cache and "Буферизуем видео…"
                or ((seeking or (core_idle and not paused)) and "Перематываем и загружаем…"
                    or "Загружаем видео…")
        )
    end
    overlay:update()
end

local function update_hover()
    if not visible then
        return false
    end
    local x, y = mp.get_mouse_pos()
    local width, height = mp.get_osd_size()
    local next_hovered = x ~= nil and y ~= nil
        and math.abs(x - width / 2) <= 42
        and math.abs(y - height / 2) <= 42
    if next_hovered == hovered then
        return false
    end
    hovered = next_hovered
    return true
end

local timer = mp.add_periodic_timer(0.12, function()
    update_hover()
    frame = frame % #frames + 1
    render()
end)
timer:kill()

local function set_visible(next_visible)
    if visible == next_visible then
        return
    end
    visible = next_visible
    hovered = false
    frame = 1
    if visible then
        timer:resume()
        render()
    else
        timer:kill()
        overlay:remove()
    end
end

local function refresh_visibility()
    set_visible(requested or seeking or paused_for_cache or (core_idle and not paused))
end

mp.register_script_message("omatube-loader", function(action, token)
    token = token or ""
    if action == "show" then
        active_token = token
        requested = true
    elseif token == active_token then
        requested = false
        active_token = ""
    end
    refresh_visibility()
end)

mp.observe_property("seeking", "bool", function(_, value)
    seeking = value == true
    refresh_visibility()
end)

mp.observe_property("paused-for-cache", "bool", function(_, value)
    paused_for_cache = value == true
    refresh_visibility()
end)

mp.observe_property("core-idle", "bool", function(_, value)
    core_idle = value == true
    refresh_visibility()
end)

mp.observe_property("pause", "bool", function(_, value)
    paused = value == true
    refresh_visibility()
end)

mp.add_forced_key_binding("MOUSE_MOVE", "omatube-loader-hover", function()
    if update_hover() then
        render()
    end
end)

mp.add_forced_key_binding("MOUSE_LEAVE", "omatube-loader-leave", function()
    if hovered then
        hovered = false
        render()
    end
end)
