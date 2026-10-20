local imgui = require('imgui')

local ui = {}
ui.show = { true }
ui.shift_held = false

-- The /vana window's palette (addons/vanacore/vana/draw.lua). Hex until drawn.
local HEX = {
    bg = '#161822', border = '#2A2E3E', line = '#242838', well = '#0E1017',
    hover = '#1F2334', white = '#FFFFFF', text = '#E8EAF1', text2 = '#BDC1D0',
    dim = '#7B8095', faint = '#4E536A', accent = '#7AA2F7', accent2 = '#A9C1FF',
    accent_lo = '#3E5CB3', teal = '#5FD3B3', amber = '#E8B45C', rose = '#EE6F78',
    off = '#2B2F42', popup = '#0F1118',
}

local function rgba(hex, alpha)
    return {
        tonumber(hex:sub(2, 3), 16) / 255,
        tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255,
        alpha or 1,
    }
end

local function u32(hex, alpha)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    local a = math.floor(math.max(0, math.min(1, alpha or 1)) * 255 + 0.5)
    return ((a * 256 + b) * 256 + g) * 256 + r
end

local function mix(a, b, t)
    t = math.max(0, math.min(1, t or 0))
    local out = '#'
    for i = 2, 6, 2 do
        local x = tonumber(a:sub(i, i + 1), 16)
        local y = tonumber(b:sub(i, i + 1), 16)
        out = out .. string.format('%02X', math.floor(x + (y - x) * t + 0.5))
    end
    return out
end

-- Same roles the quest rows already used, now in that palette.
-- grey_bar and dark_grey stay as sentinels for the meter (done, or not yet known).
local COLORS = {
    white     = rgba(HEX.text),
    green     = rgba(HEX.teal),
    link      = rgba(HEX.accent),
    orange    = rgba(HEX.amber),
    cyan      = rgba(HEX.accent2),
    grey_text = rgba(HEX.dim),
    grey_bar  = rgba(HEX.teal),
    dark_grey = rgba(HEX.off),
}

-- Screen height sets the size the way /vana does: 1440px tall is 1.1, held between 0.75 and 1.6.
local scale = 1
local function S(n)
    return math.floor(n * scale + 0.5)
end

local function update_scale()
    local h = 1080
    local ok, io = pcall(imgui.GetIO)
    if ok and io and io.DisplaySize then
        h = tonumber(io.DisplaySize.y) or h
    end
    scale = math.max(0.75, math.min(1.6, h / 1440)) * 1.1
end

local BODY, SMALL = 16, 13.5
local DYNAMIC = (tonumber(IMGUI_VERSION_NUM) or 0) >= 19200
local fonts = { tried = false, ready = false }
local fonts_pending = nil
local measured, measured_scale, measured_n = {}, nil, 0

local function fonts_begin()
    if fonts_pending then
        fonts.text = fonts_pending.text
        fonts.semi = fonts_pending.semi
        fonts.bold_italic = fonts_pending.bold_italic
        fonts_pending = nil
        fonts.ready = true
        measured, measured_n = {}, 0
    end
    if fonts.tried then
        return
    end
    fonts.tried = true
    if not DYNAMIC then
        local face = imgui.GetFont()
        fonts.text, fonts.semi, fonts.bold_italic = face, face, face
        fonts.ready = true
        return
    end
    local dir = ((os.getenv and os.getenv('WINDIR')) or 'C:\\Windows') .. '\\Fonts\\'
    local function add(file, fallback)
        local path = dir .. file
        local handle = io.open(path, 'rb')
        if not handle then
            return fallback
        end
        handle:close()
        local ok, face = pcall(imgui.AddFontFromFileTTF, path, 18)
        if ok and face then
            return face
        end
        return fallback
    end
    -- Usable from the next frame: ImGui cannot draw a font in the frame it was added.
    local text = add('segoeui.ttf', imgui.GetFont())
    local semi = add('seguisb.ttf', text)
    fonts_pending = {
        text = text,
        semi = semi,
        bold_italic = add('segoeuiz.ttf', semi),
    }
end

local function measure(str, font, size)
    str = tostring(str or '')
    if measured_scale ~= scale or measured_n > 4000 then
        measured, measured_scale, measured_n = {}, scale, 0
    end
    local key = tostring(font) .. '|' .. tostring(size) .. '|' .. str
    local found = measured[key]
    if not found then
        local w, h
        if DYNAMIC and fonts.ready and font then
            imgui.PushFont(font, S(size))
            w, h = imgui.CalcTextSize(str)
            imgui.PopFont()
        else
            w, h = imgui.CalcTextSize(str)
        end
        found = { w or 0, h or 0 }
        measured[key] = found
        measured_n = measured_n + 1
    end
    return found[1], found[2]
end

local function text_mid(dl, x, cy, str, hex, font, size, alpha)
    local _, h = measure(str, font, size)
    local y = cy - h / 2
    if DYNAMIC and fonts.ready then
        y = y - math.floor(h * 0.06 + 0.5)
    end
    if DYNAMIC and fonts.ready and font then
        imgui.PushFont(font, S(size))
        dl:AddText({ x, y }, u32(hex, alpha), str)
        imgui.PopFont()
    else
        dl:AddText({ x, y }, u32(hex, alpha), str)
    end
end

local function text_right(dl, right, cy, str, hex, font, size, alpha)
    local w = measure(str, font, size)
    text_mid(dl, right - w, cy, str, hex, font, size, alpha)
end

local function fill(dl, x, y, w, h, hex, radius, alpha, corners)
    if w <= 0 or h <= 0 then
        return
    end
    local col = u32(hex, alpha)
    if corners then
        dl:AddRectFilled({ x, y }, { x + w, y + h }, col, radius or 0, corners)
    else
        dl:AddRectFilled({ x, y }, { x + w, y + h }, col, radius or 0)
    end
end

local function outline(dl, x, y, w, h, hex, radius, alpha)
    if w <= 0 or h <= 0 then
        return
    end
    dl:AddRect({ x, y }, { x + w, y + h }, u32(hex, alpha), radius or 0)
end

local function content_width()
    local a = imgui.GetContentRegionAvail()
    if type(a) == 'table' then
        return a.x or a[1] or 0
    end
    return a or 0
end

local anim, last_clock, frame_dt = {}, nil, 0
local function tick()
    local now = os.clock()
    frame_dt = last_clock and math.max(0, math.min(0.1, now - last_clock)) or 0
    last_clock = now
end

local function ease(id, target)
    local v = anim[id]
    if v == nil then
        v = target
    else
        v = v + (target - v) * math.min(1, frame_dt * 18)
        if math.abs(v - target) < 0.004 then
            v = target
        end
    end
    anim[id] = v
    return v
end

local function face(which)
    return fonts[which] or imgui.GetFont()
end

-- A chevron or an × drawn with lines, so no icon font is required.
local function glyph(dl, kind, cx, cy, hex)
    local k = S(11) / 24
    local col = u32(hex)
    local thickness = math.max(1, 2 * k)
    local function p(px, py)
        return { cx + (px - 12) * k, cy + (py - 12) * k }
    end
    if kind == 'right' then
        dl:AddLine(p(9, 5), p(16, 12), col, thickness)
        dl:AddLine(p(16, 12), p(9, 19), col, thickness)
    elseif kind == 'close' then
        dl:AddLine(p(6, 6), p(18, 18), col, thickness)
        dl:AddLine(p(18, 6), p(6, 18), col, thickness)
    else
        dl:AddLine(p(5, 9), p(12, 16), col, thickness)
        dl:AddLine(p(12, 16), p(19, 9), col, thickness)
    end
end

local folded = {}

-- A section heading: chevron, bold-italic title, hairline. Click folds the rows.
-- Returns true while the section is open.
local function draw_section_header(text)
    local w = math.max(content_width(), S(200))
    local h = S(36)
    local x, y = imgui.GetCursorScreenPos()
    imgui.InvisibleButton('##fold.' .. text, { w, h })
    local hovered = imgui.IsItemHovered()
    local clicked = imgui.IsItemClicked(0)
    if clicked then
        folded[text] = not folded[text] or nil
    end
    local open = folded[text] ~= true
    local t = ease('fold.' .. text, hovered and 1 or 0)
    local dl = imgui.GetWindowDrawList()
    local cy = y + h / 2 + S(2)
    glyph(dl, open and 'down' or 'right', x + S(8), cy, hovered and HEX.text or HEX.faint)
    local title_font = face('bold_italic')
    local title_size = BODY + 5
    text_mid(dl, x + S(22), cy, text, mix(HEX.white, HEX.accent2, t * 0.35), title_font, title_size)
    local title_w = measure(text, title_font, title_size)
    local line_x = x + S(22) + title_w + S(8)
    if x + w - S(4) > line_x then
        dl:AddLine({ line_x, cy }, { x + w - S(4), cy }, u32(HEX.line), 1)
    end
    return open
end

local function show_tooltip(text)
    if text == nil or text == '' then
        return
    end
    imgui.PushStyleColor(ImGuiCol_PopupBg, rgba(HEX.popup, 0.97))
    imgui.PushStyleColor(ImGuiCol_Border, rgba(HEX.border))
    imgui.PushStyleColor(ImGuiCol_Text, rgba(HEX.text))
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { S(9), S(6) })
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, S(4))
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, S(4))
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1)
    local pushed = false
    if DYNAMIC and fonts.ready and fonts.text then
        imgui.PushFont(fonts.text, S(SMALL + 0.5))
        pushed = true
    end
    if imgui.BeginTooltip() then
        imgui.TextUnformatted(text)
        imgui.EndTooltip()
    end
    if pushed then
        imgui.PopFont()
    end
    imgui.PopStyleVar(4)
    imgui.PopStyleColor(3)
end

-- A sunken row. fraction nil draws no meter (a location or a line of text).
-- bar_color COLORS.grey_bar is done (teal); COLORS.dark_grey is not yet known.
local function draw_progress_bar(fraction, count_text, bar_color)
    local has_meter = fraction ~= nil
    local h = S(has_meter and 44 or 34)
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy({ -1, h })
    local max_x, max_y = imgui.GetItemRectMax()
    local row_w = math.max(1, max_x - x)
    local dl = imgui.GetWindowDrawList()
    local radius = S(5)
    fill(dl, x, y, row_w, h, HEX.well, radius, 1)
    outline(dl, x, y, row_w, h, HEX.line, radius, 1)
    if has_meter then
        local mx = x + S(8)
        local mw = row_w - S(16)
        local mh = math.max(2, S(4))
        local my = max_y - S(8) - mh / 2
        fill(dl, mx, my, mw, mh, HEX.off, mh / 2, 1)
        local frac = math.max(0, math.min(1, fraction or 0))
        if frac > 0 and mw > 0 then
            local meter = HEX.accent
            if bar_color == COLORS.grey_bar then
                meter = HEX.teal
            elseif bar_color == COLORS.dark_grey then
                meter = HEX.accent_lo
            end
            fill(dl, mx, my, math.max(mh, mw * frac), mh, meter, mh / 2, 1)
        end
    end
    if count_text and count_text ~= '' then
        local count_hex = (bar_color == COLORS.grey_bar) and HEX.dim or HEX.text2
        local band_bottom = has_meter and (max_y - S(12)) or max_y
        local cy = y + (band_bottom - y) / 2
        text_right(dl, x + row_w - S(8), cy, count_text, count_hex, face('text'), SMALL)
    end
    return x, y, x + row_w, y + h, has_meter
end

local function begin_bar_overlay(min_x, min_y, max_y, has_meter)
    local bottom = has_meter and (max_y - S(12)) or max_y
    local text_y = min_y + ((bottom - min_y) - imgui.GetTextLineHeight()) * 0.5
    imgui.SetCursorScreenPos({ min_x + S(8), text_y })
end

-- Draw a row with content overlaid on top.
-- content_fn receives (min_x, min_y, max_x, max_y).
-- Pass add_spacing = false to keep only the window's item spacing after the row.
local function draw_bar_with_overlay(fraction, count_text, bar_color, content_fn, add_spacing)
    local bx, by, bx2, by2, has_meter = draw_progress_bar(fraction, count_text, bar_color)
    local after_x, after_y = imgui.GetCursorScreenPos()
    begin_bar_overlay(bx, by, by2, has_meter)
    if content_fn then
        content_fn(bx, by, bx2, by2)
    end
    imgui.SetCursorScreenPos({ after_x, after_y })
    if add_spacing ~= false then
        imgui.Dummy({ 0, S(2) })
    end
end

-- A line with no meter: a location, a signed item, fallback text.
local function draw_static_bar(content_fn, add_spacing)
    draw_bar_with_overlay(nil, '', nil, content_fn, add_spacing)
end

-- Amber or teal callout: a wash, a stripe down the left, the line in that colour.
local function draw_notice(text, hex)
    local h = S(30)
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy({ -1, h })
    local row_w = math.max(1, select(1, imgui.GetItemRectMax()) - x)
    local dl = imgui.GetWindowDrawList()
    local top, height = y + S(3), h - S(6)
    fill(dl, x, top, row_w, height, hex, S(3), 0.12)
    local left = ImDrawFlags_RoundCornersLeft or ImDrawCornerFlags_Left
    fill(dl, x, top, S(3), height, hex, S(2), 1, left)
    text_mid(dl, x + S(12), y + h / 2, text, hex, face('text'), BODY - 1)
end

local STYLE_COLORS = nil

local function push_window_style()
    if STYLE_COLORS == nil then
        STYLE_COLORS = {
            { ImGuiCol_Text, rgba(HEX.text) },
            { ImGuiCol_TextDisabled, rgba(HEX.faint) },
            { ImGuiCol_WindowBg, rgba(HEX.bg) },
            { ImGuiCol_ChildBg, rgba(HEX.bg) },
            { ImGuiCol_PopupBg, rgba(HEX.popup) },
            { ImGuiCol_Border, rgba(HEX.border) },
            { ImGuiCol_Separator, rgba(HEX.line) },
            { ImGuiCol_ScrollbarBg, rgba(HEX.bg, 0) },
            { ImGuiCol_ScrollbarGrab, rgba('#3A4158') },
            { ImGuiCol_ScrollbarGrabHovered, rgba('#4A5270') },
            { ImGuiCol_ScrollbarGrabActive, rgba(HEX.accent_lo) },
        }
    end
    for _, entry in ipairs(STYLE_COLORS) do
        imgui.PushStyleColor(entry[1], entry[2])
    end
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { S(16), S(12) })
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, S(5))
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, S(4))
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, S(5))
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { S(6), S(6) })
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, S(6))
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, S(3))
end

local function pop_window_style()
    imgui.PopStyleVar(9)
    imgui.PopStyleColor(#STYLE_COLORS)
end

local function draw_title()
    local h = S(36)
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy({ -1, h })
    local max_x = select(1, imgui.GetItemRectMax())
    local dl = imgui.GetWindowDrawList()
    local cy = y + h / 2
    local title_font = face('semi')
    text_mid(dl, x, cy, 'Goldilox', HEX.white, title_font, BODY + 3)
    local title_w = measure('Goldilox', title_font, BODY + 3)
    text_mid(dl, x + title_w + S(10), cy, 'Daily quests', HEX.faint, face('text'), SMALL)
    -- The hit box stays inside the row so it does not stretch the window.
    local cx = max_x - S(14)
    local restore_x, restore_y = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ cx - S(10), cy - S(10) })
    imgui.InvisibleButton('##goldilox.close', { S(20), S(20) })
    local close_hover = imgui.IsItemHovered()
    if imgui.IsItemClicked(0) then
        ui.show[1] = false
    end
    imgui.SetCursorScreenPos({ restore_x, restore_y })
    glyph(dl, 'close', cx, cy, close_hover and HEX.rose or HEX.dim)
    local wx = imgui.GetWindowPos()
    local ww = imgui.GetWindowSize()
    dl:AddLine({ wx + S(12), y + h }, { wx + ww - S(12), y + h }, u32(HEX.border), 1)
end

local function draw_shadow()
    local ok, dl = pcall(imgui.GetBackgroundDrawList)
    if not ok or dl == nil then
        return
    end
    local x, y = imgui.GetWindowPos()
    local w, h = imgui.GetWindowSize()
    dl:AddRectFilled({ x - S(1), y + S(1) }, { x + w + S(1), y + h + S(3) }, u32('#000000', 0.35), S(6))
end

-- Palalumin zone name fixups: in-game names lack apostrophes that the wiki URLs need
local PALALUMIN_ZONE_FIXUPS = {
    ["HuXzoi"]  = "Hu'Xzoi",
    ["AlTaieu"] = "Al'Taieu",
    ["RuHmet"]  = "Ru'Hmet",
}

-- Convert a display name to a bg-wiki URL-safe path segment
-- Preserves original casing from game data (e.g. "The Garden of Ru'Hmet")
local function to_wiki_path(name)
    return name:gsub(" ", "_"):gsub("'", "%%27")
end

-- Title-case variant for items / mobs whose game data may be lowercase
local function to_wiki_path_titled(name)
    local titled = name:gsub("(%a)([%w]*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return titled:gsub(" ", "_"):gsub("'", "%%27")
end

-- Singularize a mob name for wiki Category links (strip trailing 's')
local function singularize_mob(name)
    if #name > 1 and name:sub(-1) == "s" then
        return name:sub(1, -2)
    end
    return name
end

-- Shared helper: render underlined, interactive colored text.
-- tooltip_text is shown on hover; on_click_fn is called on left click.
local function draw_interactive_text(text, color, tooltip_text, on_click_fn)
    imgui.TextColored(color, text)
    local min_x, min_y = imgui.GetItemRectMin()
    local max_x, max_y = imgui.GetItemRectMax()
    local hovered = imgui.IsItemHovered()
    local draw_list = imgui.GetWindowDrawList()
    local hot = hovered and color == COLORS.link
    if hot then
        draw_list:AddText({ min_x, min_y }, u32(HEX.accent2), text)
    end
    local a = math.floor((color[4] or 1.0) * 255)
    local b = math.floor((color[3] or 0) * 255)
    local g = math.floor((color[2] or 0) * 255)
    local r = math.floor((color[1] or 0) * 255)
    local col_u32 = hot and u32(HEX.accent2) or bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r)
    draw_list:AddLine({ min_x, max_y }, { max_x, max_y }, col_u32, 1.0)
    if hovered then
        show_tooltip(tooltip_text)
    end
    if imgui.IsItemClicked(0) then
        on_click_fn()
    end
end

-- Draw colored, underlined text that opens a URL on click
local function draw_link(text, color, url, tooltip)
    draw_interactive_text(text, color, tooltip or ("Open FFXI Wiki: " .. text), function()
        os.execute('start "" "' .. url .. '"')
    end)
end

-- Draw colored, underlined text that sends a game command on click
local function draw_command_link(text, color, command, tooltip)
    draw_interactive_text(text, color, tooltip or command, function()
        AshitaCore:GetChatManager():QueueCommand(1, command)
    end)
end

-- Draw a zone name as a clickable bg-wiki link
local function draw_zone_link(zone_name, color, is_palalumin)
    local wiki_name = zone_name
    if is_palalumin then
        for pattern, replacement in pairs(PALALUMIN_ZONE_FIXUPS) do
            wiki_name = wiki_name:gsub(pattern, replacement)
        end
    end
    local url = "https://www.bg-wiki.com/ffxi/" .. to_wiki_path(wiki_name)
    draw_link(zone_name, color, url)
end

-- Draw a mob name as a clickable bg-wiki Category link (for generic mob types)
local function draw_mob_link(mob_name, color)
    local singular = singularize_mob(mob_name)
    local url = "https://www.bg-wiki.com/ffxi/Category:" .. to_wiki_path_titled(singular)
    draw_link(mob_name, color, url)
end

-- Draw an NM (notorious monster) name as a clickable bg-wiki link (no Category:, no singularization)
local function draw_nm_link(nm_name, color)
    local url = "https://www.bg-wiki.com/ffxi/" .. to_wiki_path_titled(nm_name)
    draw_link(nm_name, color, url)
end

-- Draw an item name as a clickable bg-wiki link
local function draw_item_link(item_name, color)
    local url = "https://www.bg-wiki.com/ffxi/" .. to_wiki_path_titled(item_name)
    draw_link(item_name, color, url)
end

-- Draw "Kill <target> at <zone>" with colored, linked highlights
-- opts.mob_link: use Category-style mob link instead of NM link
-- opts.palalumin: pass through to zone link for apostrophe fixups
local function draw_kill_at(target, zone, label_color, highlight_color, opts)
    opts = opts or {}
    imgui.TextColored(label_color, "Kill ")
    imgui.SameLine()
    if opts.mob_link then
        draw_mob_link(target, highlight_color)
    else
        draw_nm_link(target, highlight_color)
    end
    imgui.SameLine()
    imgui.TextColored(label_color, " at ")
    imgui.SameLine()
    draw_zone_link(zone, highlight_color, opts.palalumin)
    imgui.SameLine()
    imgui.TextColored(COLORS.white, "     ")
end

-- Pick label / highlight colors based on completion state
-- Returns label_color, highlight_color
local function progress_colors(is_done)
    if is_done then
        return COLORS.grey_text, COLORS.grey_text
    end
    return COLORS.white, COLORS.link
end

-- Strip Ashita chat color escape sequences from a string
local function strip_colors(s)
    s = s:gsub("\x1E.-\x1E", ""):gsub("\x1F.-\x1F", "")
    s = s:gsub("\30.", ""):gsub("\31.", "")
    return s
end

-- Count how many of a given item the player has in their inventory
-- Checks container: Inventory(0) only
-- Returns: number of items found, or nil if inventory not accessible
-- Resolve an item id without letting a bad lookup abort the frame.
-- Language id varies by client, so try the common Ashita indexes.
local function lookup_item_id(item_name)
    local ok_rm, resources = pcall(function()
        return AshitaCore:GetResourceManager()
    end)
    if not ok_rm or not resources then
        return nil
    end
    for _, lang in ipairs({ 0, 1, 2, 3 }) do
        local ok, id = pcall(function()
            local item = resources:GetItemByName(item_name, lang)
            if item == nil then return nil end
            return item.Id
        end)
        if ok and type(id) == 'number' and id > 0 then
            return id
        end
    end
    return nil
end

local function get_item_count(item_name)
    local item_id = lookup_item_id(item_name)
    if not item_id then
        return nil
    end

    local ok_inv, inventory = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    if not ok_inv or not inventory then
        return nil
    end

    local total = 0
    -- Check inventory (container 0), max 80 slots
    for i = 0, 79 do
        local ok, count = pcall(function()
            local entry = inventory:GetContainerItem(0, i)
            if entry == nil or entry.Id ~= item_id then
                return 0
            end
            return entry.Count or 0
        end)
        if ok and type(count) == 'number' then
            total = total + count
        end
    end
    return total
end

-- Parse "Item Name xN" into item_name, needed_count
local function parse_item_requirement(text)
    local name, count = text:match("^(.+)%s+x(%d+)$")
    if name and count then
        return name, tonumber(count)
    end
    -- fallback: no count specified, assume 1
    return text, 1
end

-- Get plain-text quest status and color for imgui display
local function get_plain_status(npc, handler, daily)
    if daily == nil then
        return "Not talked to today.", COLORS.orange
    elseif daily.status == 'complete' then
        return "Complete!", COLORS.green
    elseif daily.status == 'return' then
        return "Return to " .. npc .. ".", COLORS.cyan
    elseif handler.status ~= nil then
        local s = handler.status(daily)
        if s then return strip_colors(s), COLORS.white end
        -- Quest is active even when the item or target has not been parsed yet.
        if daily.message then return strip_colors(daily.message), COLORS.white end
        return nil
    else
        return daily.message, COLORS.white
    end
end

-- Toggle the UI window visibility
function ui.toggle()
    ui.show[1] = not ui.show[1]
end

-- Render the imgui window
-- Params:
--   status            - the current status table (dailies, palalumin, etc.)
--   goblin_order      - ordered list of goblin NPC names
--   handlers          - goblin quest handler table
--   palalumin_quest_order - ordered list of palalumin quest names
--   palalumin_quests  - palalumin quest handler table
function ui.render(status, goblin_order, handlers, palalumin_quest_order, palalumin_quests)
    if not ui.show[1] then
        return
    end

    if status == nil then
        return
    end

    -- Hide the window only when nothing is still active.
    -- A flagged quest line with no stored item yet is still active.
    local has_incomplete = false
    local dailies = status.dailies or {}
    local pala_quests = status.palalumin_quests or {}

    for _, npc in ipairs(goblin_order) do
        local daily = dailies[npc]
        if daily ~= nil and daily.status ~= 'complete' then
            has_incomplete = true
            break
        end
    end

    -- Check Goldilox reward not collected
    if not has_incomplete then
        local goblin_completed = 0
        for _, npc in ipairs(goblin_order) do
            if dailies[npc] and dailies[npc].status == 'complete' then
                goblin_completed = goblin_completed + 1
            end
        end
        if goblin_completed > 0 and status.goldilox_time ~= status.deadline then
            has_incomplete = true
        end
    end

    -- Palalumin stays visible once flagged until every quest is known complete.
    -- Missing rows mean the quests are active and no item has been detected yet.
    if not has_incomplete and status.palalumin_flagged then
        local known = 0
        for _, quest in ipairs(palalumin_quest_order) do
            local daily = pala_quests[quest]
            if daily then
                known = known + 1
                if not daily.completed then
                    has_incomplete = true
                    break
                end
            end
        end
        if not has_incomplete and known < #palalumin_quest_order then
            has_incomplete = true
        end
    end

    if not has_incomplete then
        return
    end

    update_scale()
    tick()
    fonts_begin()

    imgui.SetNextWindowSizeConstraints({ S(460), 0 }, { FLT_MAX, FLT_MAX })
    -- Hold Shift to drag the window; otherwise it stays locked in place
    local shift_held = ui.shift_held
    local win_flags = bit.bor(
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoScrollWithMouse,
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoNavInputs
    )
    if not shift_held then
        win_flags = bit.bor(win_flags, ImGuiWindowFlags_NoMove)
    end
    push_window_style()
    local font_pushed = false
    if DYNAMIC and fonts.ready and fonts.text then
        imgui.PushFont(fonts.text, S(BODY))
        font_pushed = true
    end
    if imgui.Begin('Goldilox - Daily Quests', ui.show, win_flags) then
        draw_title()

        -- Goblin dailies
        local tracked_dailies = status.dailies or {}
        local has_goblin_dailies = false
        for _, npc in ipairs(goblin_order) do
            if tracked_dailies[npc] ~= nil then
                has_goblin_dailies = true
                break
            end
        end

        if has_goblin_dailies then
            if draw_section_header('Goblin Dailies') then

            local completed = 0
            for _, npc in ipairs(goblin_order) do
                local handler = handlers[npc]
                local daily = tracked_dailies[npc]
                if daily ~= nil then
                    if daily.status == 'complete' then
                        completed = completed + 1
                        draw_bar_with_overlay(1.0, "", COLORS.grey_bar, function()
                            imgui.TextColored(COLORS.grey_text, npc .. ": Complete!")
                        end)
                    elseif daily.status == 'return' then
                        draw_bar_with_overlay(1.0, "", COLORS.grey_bar, function()
                            imgui.TextColored(COLORS.grey_text, "Return to " .. npc .. ".")
                        end)
                    elseif npc == "Fishstix" and daily.zone then
                        draw_bar_with_overlay(nil, "", nil, function(bx, by, bx2, by2)
                            local right_text = daily.hint or "/huh motion"
                            local right_w = imgui.CalcTextSize(right_text)
                            local pad = S(8)
                            local clip_right = bx2 - right_w - pad * 2

                            -- Draw left content clipped so it can't overlap the right link
                            local draw_list = imgui.GetWindowDrawList()
                            draw_list:PushClipRect({ bx, by }, { clip_right, by2 }, true)
                            imgui.TextColored(COLORS.white, "Secret chest at ")
                            imgui.SameLine()
                            draw_zone_link(daily.zone, COLORS.link)
                            imgui.SameLine()
                            imgui.TextColored(COLORS.white, "            ")  -- reserve space for /huh motion
                            draw_list:PopClipRect()

                            -- Right-justified /huh link
                            local right_y = by + ((by2 - by) - imgui.GetTextLineHeight()) * 0.5
                            imgui.SetCursorScreenPos({ bx2 - right_w - pad, right_y })
                            draw_command_link(right_text, COLORS.link, "/huh motion", "Send /huh motion")
                        end)
                    elseif npc == "Murdox" and daily.count and daily.target and daily.zone then
                        local total = tonumber(daily.count) or 0
                        local remaining = tonumber(daily.remaining or daily.count) or 0
                        local killed = total - remaining
                        local is_done = (total > 0 and killed >= total)
                        local fraction = (total > 0) and (killed / total) or 0
                        local count_text = string.format("%d/%d", killed, total)
                        local label_color, highlight_color = progress_colors(is_done)
                        local bar_color = is_done and COLORS.grey_bar or nil

                        draw_bar_with_overlay(fraction, count_text, bar_color, function()
                            draw_kill_at(daily.target, daily.zone, label_color, highlight_color, { mob_link = true })
                        end)
                    elseif npc == "Mistrix" and daily.item then
                        draw_static_bar(function()
                            imgui.TextColored(COLORS.white, "Trade a signed ")
                            imgui.SameLine()
                            draw_item_link(daily.item, COLORS.link)
                            imgui.SameLine()
                            imgui.TextColored(COLORS.white, " ")
                        end)
                    elseif npc == "Saltlix" and daily.target and daily.zone then
                        draw_static_bar(function()
                            draw_kill_at(daily.target, daily.zone, COLORS.white, COLORS.link)
                        end)
                    elseif npc == "Beetrix" and daily.item and daily.zone then
                        local have = get_item_count(daily.item)
                        local has_item = have and have >= 1
                        local fraction = has_item and 1.0 or 0
                        local bar_color = has_item and COLORS.grey_bar or COLORS.dark_grey
                        local label_color, highlight_color = progress_colors(has_item)
                        local count_text = have and (tostring(math.min(have, 1)) .. "/1") or "?/1"
                        draw_bar_with_overlay(fraction, count_text, bar_color, function()
                            imgui.TextColored(label_color, "Trade ")
                            imgui.SameLine()
                            draw_item_link(daily.item, highlight_color)
                            imgui.SameLine()
                            imgui.TextColored(label_color, " found at ")
                            imgui.SameLine()
                            draw_zone_link(daily.zone, highlight_color)
                            imgui.SameLine()
                            imgui.TextColored(label_color, "    ")  -- reserve space for count
                        end)
                    else
                        -- Fallback for unrecognized state
                        local text, color = get_plain_status(npc, handler, daily)
                        if text then
                            draw_static_bar(function()
                                imgui.TextColored(color, text)
                            end)
                        end
                    end
                end
            end

            -- Goldilox reward status
            if completed > 0 then
                if status.goldilox_time == status.deadline then
                    draw_notice('Goldilox: Complete!', HEX.teal)
                else
                    draw_notice('Goldilox: Reward not collected.', HEX.amber)
                end
            end
            end -- end collapsible goblin section
        end

        -- Palalumin quests
        if status.palalumin_flagged then
            local flagged = 0
            local known = 0
            local pala_rows = status.palalumin_quests or {}
            for _, quest in ipairs(palalumin_quest_order) do
                local handler = palalumin_quests[quest]
                local daily = pala_rows[quest]
                if daily then
                    known = known + 1
                end
                if daily and not daily.completed then
                    flagged = flagged + 1
                    if flagged == 1 then
                        imgui.Spacing()
                        if not draw_section_header('Palalumin Quests') then
                            break
                        end
                    end
                    -- For "Item request", show summary line with linked items, then progress bars
                    if quest == "Item request" and daily.items then
                        -- Collect parsed items
                        local items = {}
                        for entry in daily.items:gmatch("([^,]+)") do
                            entry = entry:match("^%s*(.-)%s*$")
                            local item_name, needed = parse_item_requirement(entry)
                            local have = get_item_count(item_name)
                            table.insert(items, { name = item_name, needed = needed, have = have })
                        end

                        -- Compute totals (cap each item's have at its needed count)
                        local total_have = 0
                        local total_needed = 0
                        local any_unknown = false
                        for _, item in ipairs(items) do
                            total_needed = total_needed + item.needed
                            if item.have == nil then
                                any_unknown = true
                            else
                                total_have = total_have + math.min(item.have, item.needed)
                            end
                        end

                        local all_satisfied = (not any_unknown) and (total_have >= total_needed)
                        local fraction = (total_needed > 0) and (total_have / total_needed) or 0
                        local bar_color = all_satisfied and COLORS.grey_bar or (any_unknown and COLORS.dark_grey or nil)
                        local summary_label, summary_highlight = progress_colors(all_satisfied)

                        draw_bar_with_overlay(fraction, "", bar_color, function()
                            imgui.TextColored(summary_label, "Trade ")
                            for i, item in ipairs(items) do
                                imgui.SameLine()
                                draw_item_link(item.name, summary_highlight)
                                imgui.SameLine()
                                local have_str = item.have and tostring(item.have) or "?"
                                local suffix = " " .. have_str .. "/" .. item.needed
                                if i < #items then suffix = suffix .. "," end
                                imgui.TextColored(summary_label, suffix)
                            end
                            imgui.SameLine()
                            imgui.TextColored(summary_label, " ")
                        end, false)
                    elseif quest == "Defeat mobs" and (daily.killed and daily.total or daily.completed) then
                        -- Kill quest progress bar
                        local killed = daily.killed or 0
                        local total = daily.total or 0
                        local target = daily.target or "mobs"
                        local zone = daily.zone or "?"
                        local is_done = daily.completed or (total > 0 and killed >= total)
                        local fraction = (total > 0) and (killed / total) or (is_done and 1.0 or 0)
                        local count_text = (total > 0) and string.format("%d/%d", killed, total) or "Done"
                        local label_color, highlight_color = progress_colors(is_done)
                        local bar_color = is_done and COLORS.grey_bar or nil

                        draw_bar_with_overlay(fraction, count_text, bar_color, function()
                            draw_kill_at(target, zone, label_color, highlight_color, { mob_link = true, palalumin = true })
                        end, false)
                    elseif quest == "Find flux" and daily.zone then
                        draw_bar_with_overlay(nil, "", nil, function(bx, by, bx2, by2)
                            imgui.TextColored(COLORS.white, "Find the Flux in ")
                            imgui.SameLine()
                            draw_zone_link(daily.zone, COLORS.link, true)
                            imgui.SameLine()
                            imgui.TextColored(COLORS.white, "    ")  -- reserve space for #sea
                            local discord_w = imgui.CalcTextSize("#sea")
                            local discord_y = by + ((by2 - by) - imgui.GetTextLineHeight()) * 0.5
                            imgui.SetCursorScreenPos({ bx2 - discord_w - S(8), discord_y })
                            draw_link("#sea", COLORS.link, "https://discord.com/channels/696847769444548700/1359317001457242192", "Open CatsEyeXI Discord Channel #sea")
                        end, false)
                    else
                        local s = handler.status(daily)
                        if not s and daily.message then
                            s = daily.message
                        end
                        if s then
                            draw_static_bar(function()
                                imgui.TextColored(COLORS.white, strip_colors(s))
                            end, false)
                        end
                    end
                    imgui.Dummy({ 0, S(2) })
                end
            end
            -- Flagged for the day, but no objective row has been detected yet.
            if flagged == 0 and known < #palalumin_quest_order then
                imgui.Spacing()
                if draw_section_header('Palalumin Quests') then
                    draw_notice('Quests active', HEX.amber)
                end
            end
        end
        draw_shadow()
    end
    imgui.End()
    if font_pushed then
        imgui.PopFont()
    end
    pop_window_style()
end

return ui