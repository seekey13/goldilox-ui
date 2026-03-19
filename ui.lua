local imgui = require('imgui')

local ui = {}
ui.show = { true }
ui.shift_held = false

-- Shared color palette
local COLORS = {
    white       = { 1.0, 1.0, 1.0, 1.0 },
    green       = { 0.0, 1.0, 0.0, 0.25 },
    link        = { 0.0, 1.0, 0.0, 1.0 },
    orange      = { 1.0, 0.6, 0.0, 1.0 },
    cyan        = { 0.2, 0.8, 1.0, 1.0 },
    grey_text   = { 0.5, 0.5, 0.5, 1.0 },
    grey_bar    = { 0.4, 0.4, 0.4, 1.0 },
    dark_grey   = { 0.3, 0.3, 0.3, 1.0 },
}

local SPACING = 10

-- Draw a collapsible section header (grey style)
-- Returns true if the section is expanded
local function draw_section_header(text)
    imgui.PushStyleColor(ImGuiCol_Header,        COLORS.dark_grey)
    imgui.PushStyleColor(ImGuiCol_HeaderHovered,  COLORS.grey_bar)
    imgui.PushStyleColor(ImGuiCol_HeaderActive,   COLORS.grey_text)
    local expanded = imgui.CollapsingHeader(text, ImGuiTreeNodeFlags_DefaultOpen)
    imgui.PopStyleColor(3)
    return expanded
end

-- Draw a progress bar with count right-justified; returns bar rect for overlay
-- fraction:   0.0 – 1.0
-- count_text: e.g. "4/17", shown on the right
-- bar_color:  optional RGBA table; if provided, overrides the default bar color
local function draw_progress_bar(fraction, count_text, bar_color)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, bar_color or COLORS.green)
    imgui.ProgressBar(fraction, { -1, 0 }, "")  -- empty overlay; we draw text manually
    imgui.PopStyleColor(1)

    local min_x, min_y = imgui.GetItemRectMin()
    local max_x, max_y = imgui.GetItemRectMax()
    local draw_list = imgui.GetWindowDrawList()
    -- Grey count text for grey bars, white otherwise
    local text_color = (bar_color == COLORS.grey_bar) and 0xFF808080 or 0xFFFFFFFF
    local pad = 4
    local text_y = min_y + ((max_y - min_y) - imgui.GetTextLineHeight()) * 0.5
    -- Right-justify count_text
    local count_width = imgui.CalcTextSize(count_text)
    draw_list:AddText({ max_x - count_width - pad, text_y }, text_color, count_text)

    return min_x, min_y, max_x, max_y
end

-- Position the imgui cursor inside a bar rect for overlaying linked widgets
local function begin_bar_overlay(min_x, min_y, max_y)
    local pad = 4
    local text_y = min_y + ((max_y - min_y) - imgui.GetTextLineHeight()) * 0.5
    imgui.SetCursorScreenPos({ min_x + pad, text_y })
end

-- Draw a progress bar with content overlaid on top.
-- content_fn receives (min_x, min_y, max_x, max_y) bar rect for advanced positioning.
-- Pass add_spacing = false to suppress the default post-bar spacing.
local function draw_bar_with_overlay(fraction, count_text, bar_color, content_fn, add_spacing)
    local bx, by, bx2, by2 = draw_progress_bar(fraction, count_text, bar_color)
    local after_x, after_y = imgui.GetCursorScreenPos()
    begin_bar_overlay(bx, by, by2)
    if content_fn then
        content_fn(bx, by, bx2, by2)
    end
    imgui.SetCursorScreenPos({ after_x, after_y })
    if add_spacing ~= false then
        imgui.Spacing(SPACING)
    end
end

-- Convenience: draw a static (grey, empty) bar with overlaid content
local function draw_static_bar(content_fn, add_spacing)
    draw_bar_with_overlay(0, "", COLORS.dark_grey, content_fn, add_spacing)
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

-- Draw colored, underlined text that opens a URL on click
local function draw_link(text, color, url, tooltip)
    imgui.TextColored(color, text)
    -- Underline beneath the text
    local min_x, min_y = imgui.GetItemRectMin()
    local max_x, max_y = imgui.GetItemRectMax()
    local draw_list = imgui.GetWindowDrawList()
    local a = math.floor((color[4] or 1.0) * 255)
    local b = math.floor((color[3] or 0) * 255)
    local g = math.floor((color[2] or 0) * 255)
    local r = math.floor((color[1] or 0) * 255)
    local col_u32 = bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r)
    draw_list:AddLine({ min_x, max_y }, { max_x, max_y }, col_u32, 1.0)
    if imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip or ("Open FFXI Wiki: " .. text))
    end
    if imgui.IsItemClicked(0) then
        os.execute('start "" "' .. url .. '"')
    end
end

-- Draw colored, underlined text that sends a game command on click
local function draw_command_link(text, color, command, tooltip)
    imgui.TextColored(color, text)
    -- Underline beneath the text
    local min_x, min_y = imgui.GetItemRectMin()
    local max_x, max_y = imgui.GetItemRectMax()
    local draw_list = imgui.GetWindowDrawList()
    local a = math.floor((color[4] or 1.0) * 255)
    local b = math.floor((color[3] or 0) * 255)
    local g = math.floor((color[2] or 0) * 255)
    local r = math.floor((color[1] or 0) * 255)
    local col_u32 = bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r)
    draw_list:AddLine({ min_x, max_y }, { max_x, max_y }, col_u32, 1.0)
    if imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip or command)
    end
    if imgui.IsItemClicked(0) then
        AshitaCore:GetChatManager():QueueCommand(1, command)
    end
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
local function get_item_count(item_name)
    local ok_res, target_item = pcall(function()
        return AshitaCore:GetResourceManager():GetItemByName(item_name, 0)
    end)
    if not ok_res or not target_item then
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
        local ok, entry = pcall(function()
            return inventory:GetContainerItem(0, i)
        end)
        if ok and entry and entry.Id == target_item.Id then
            total = total + entry.Count
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

    -- Check if there's anything incomplete to display; hide UI if everything is done
    local has_incomplete = false

    -- Check goblin dailies: any non-complete quest means something to show
    for _, npc in ipairs(goblin_order) do
        local daily = status.dailies[npc]
        if daily ~= nil and daily.status ~= 'complete' then
            has_incomplete = true
            break
        end
    end

    -- Check Goldilox reward not collected
    if not has_incomplete then
        local goblin_completed = 0
        for _, npc in ipairs(goblin_order) do
            if status.dailies[npc] and status.dailies[npc].status == 'complete' then
                goblin_completed = goblin_completed + 1
            end
        end
        if goblin_completed > 0 and status.goldilox_time ~= status.deadline then
            has_incomplete = true
        end
    end

    -- Check palalumin quests: any non-completed quest means something to show
    if not has_incomplete and status.palalumin_flagged then
        for _, quest in ipairs(palalumin_quest_order) do
            local daily = status.palalumin_quests[quest]
            if daily and not daily.completed then
                has_incomplete = true
                break
            end
        end
    end

    if not has_incomplete then
        return
    end

    imgui.SetNextWindowSizeConstraints({ 0, 0 }, { FLT_MAX, FLT_MAX })
    -- Hold Shift to drag the window; otherwise it stays locked in place
    local shift_held = ui.shift_held
    local win_flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoTitleBar)
    if not shift_held then
        win_flags = bit.bor(win_flags, ImGuiWindowFlags_NoMove)
    end
    if imgui.Begin('Goldilox - Daily Quests', ui.show, win_flags) then

        -- Goblin dailies
        local has_goblin_dailies = false
        for _, npc in ipairs(goblin_order) do
            if status.dailies[npc] ~= nil then
                has_goblin_dailies = true
                break
            end
        end

        if has_goblin_dailies then
            if draw_section_header('Goblin Dailies  ') then

            local completed = 0
            for _, npc in ipairs(goblin_order) do
                local handler = handlers[npc]
                local daily = status.dailies[npc]
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
                        draw_bar_with_overlay(0, "", COLORS.dark_grey, function(bx, by, bx2, by2)
                            local right_text = daily.hint or "/huh motion"
                            local right_w = imgui.CalcTextSize(right_text)
                            local pad = 4
                            local clip_right = bx2 - right_w - pad * 2

                            -- Draw left content clipped so it can't overlap the right link
                            local draw_list = imgui.GetWindowDrawList()
                            draw_list:PushClipRect({ bx, by }, { clip_right, by2 }, true)
                            imgui.TextColored(COLORS.white, "Secret chest at ")
                            imgui.SameLine()
                            draw_zone_link(daily.zone, COLORS.link)
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
                        draw_static_bar(function()
                            imgui.TextColored(COLORS.white, "Trade ")
                            imgui.SameLine()
                            draw_item_link(daily.item, COLORS.link)
                            imgui.SameLine()
                            imgui.TextColored(COLORS.white, " found at ")
                            imgui.SameLine()
                            draw_zone_link(daily.zone, COLORS.link)
                            imgui.SameLine()
                            imgui.TextColored(COLORS.white, " ")
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
                imgui.Spacing()
                if status.goldilox_time == status.deadline then
                    imgui.TextColored(COLORS.green, 'Goldilox: Complete!')
                else
                    imgui.TextColored(COLORS.orange, 'Goldilox: Reward not collected.')
                end
            end
            end -- end collapsible goblin section
        end

        -- Palalumin quests
        if status.palalumin_flagged then
            local flagged = 0
            for _, quest in ipairs(palalumin_quest_order) do
                local handler = palalumin_quests[quest]
                local daily = status.palalumin_quests[quest]
                if daily and not daily.completed then
                    flagged = flagged + 1
                    if flagged == 1 then
                        imgui.Spacing()
                        if not draw_section_header('Palalumin Quests  ') then
                            break
                        end
                    end
                    -- For "Item request", show summary line with linked items, then progress bars
                    if quest == "Item request" and daily.items then
                        -- Collect parsed items for summary line and bars
                        local items = {}
                        for entry in daily.items:gmatch("([^,]+)") do
                            entry = entry:match("^%s*(.-)%s*$")
                            local item_name, needed = parse_item_requirement(entry)
                            local have = get_item_count(item_name)
                            table.insert(items, { name = item_name, needed = needed, have = have })
                        end

                        -- Check if all items are satisfied for summary line coloring
                        local all_satisfied = true
                        for _, item in ipairs(items) do
                            if not item.have or item.have < item.needed then
                                all_satisfied = false
                                break
                            end
                        end
                        local summary_label, summary_highlight = progress_colors(all_satisfied)

                        -- Summary line inside a progress bar container
                        draw_bar_with_overlay(all_satisfied and 1.0 or 0, "", all_satisfied and COLORS.grey_bar or COLORS.dark_grey, function()
                            imgui.TextColored(summary_label, "Trade ")
                            for i, item in ipairs(items) do
                                imgui.SameLine()
                                draw_item_link(item.name, summary_highlight)
                                imgui.SameLine()
                                local suffix = " x" .. item.needed
                                if i < #items then suffix = suffix .. "," end
                                imgui.TextColored(summary_label, suffix)
                                imgui.SameLine()
                                imgui.TextColored(summary_label, " ")
                            end
                        end, false)

                        -- Progress bars with white (non-linked) item text
                        for _, item in ipairs(items) do
                            local fraction, count_text, bar_color, label_color
                            if item.have == nil then
                                fraction = 0
                                count_text = string.format("?/%d", item.needed)
                                bar_color = COLORS.dark_grey
                                label_color = COLORS.white
                            elseif item.have >= item.needed then
                                fraction = 1.0
                                count_text = string.format("%d/%d", item.have, item.needed)
                                bar_color = COLORS.grey_bar
                                label_color = COLORS.grey_text
                            else
                                fraction = item.have / item.needed
                                count_text = string.format("%d/%d", item.have, item.needed)
                                bar_color = nil  -- default
                                label_color = COLORS.white
                            end

                            draw_bar_with_overlay(fraction, count_text, bar_color, function()
                                imgui.TextColored(label_color, item.name)
                            end, false)
                        end
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
                        draw_bar_with_overlay(0, "", COLORS.dark_grey, function(bx, by, bx2, by2)
                            imgui.TextColored(COLORS.white, "Find the Flux in ")
                            imgui.SameLine()
                            draw_zone_link(daily.zone, COLORS.link, true)
                            local discord_w = imgui.CalcTextSize("#sea")
                            local discord_y = by + ((by2 - by) - imgui.GetTextLineHeight()) * 0.5
                            imgui.SetCursorScreenPos({ bx2 - discord_w - 4, discord_y })
                            draw_link("#sea", COLORS.link, "https://discord.com/channels/696847769444548700/1359317001457242192", "Open CatsEyeXI Discord Channel #sea")
                        end, false)
                    else
                        local s = handler.status(daily)
                        if s then
                            draw_static_bar(function()
                                imgui.TextColored(COLORS.white, strip_colors(s))
                            end, false)
                        end
                    end
                    -- Blank lines after each quest group
                    imgui.Spacing()
                    imgui.Spacing()
                end
            end
        end
    end
    imgui.End()
end

return ui