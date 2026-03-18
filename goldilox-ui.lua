addon.name      = 'Goldilox-ui'
addon.author    = 'Dewin & Seekey'
addon.version   = '1.2'
addon.desc      = 'Keeps track of Goblin dailies.  Exclusively for CatsEye XI.'
addon.link      = 'https://github.com/dewiniaid/ffxi-ashita-goldilox'

require('common')
local chat = require('chat')
local settings = require('settings')
local goldilox_ui = require('ui')

local current_character_id = nil  -- Detect character changes

local default_status = T{
    offset = (60 * 60 * 9),    -- JST is 9 hours ahead of UTC.  Used for calculating time until Japanese midnight.
    deadline = 0,              -- Deadline to complete current dailies.  Reset all data if deadline passes.
    version = 1,               -- Nuke all stored data if version mismatches.
    dailies = {},              -- Storage for dailies.
    palalumin_quests = {}      -- Storage for palalumin quests.
}

local status = nil

-- local ZONE_ALTAIEU = 33
local ZONE_LOWERJEUNO = 245
local ZONE_HUXZOI = 34

local DIAMOND = "\129\158"
local FULL_DIAMOND = "\129\159"

-- Get the name of the player's current target (extracted from targets.lua logic)
local function get_current_target_name()
    local target = AshitaCore:GetMemoryManager():GetTarget()
    if target == nil then return nil end
    local idx
    if target:GetIsSubTargetActive() == 0 then
        idx = target:GetTargetIndex(0)
    else
        idx = target:GetTargetIndex(1)
    end
    local ent = GetEntity(idx)
    if ent == nil then return nil end
    return ent.Name
end

local function update_status()
    local player = AshitaCore:GetMemoryManager():GetParty()
    local char_id = player:GetMemberServerId(0)
    if current_character_id ~= char_id then
        current_character_id = char_id
        status = settings.load(default_status)
    end
    if status == nil then
        status = settings.load(default_status)
    end

    local now = os.time()
    local deadline = math.floor((now + default_status.offset) / 86400) * 86400 + 86400 - default_status.offset

    if status.version ~= default_status.version then
        status = settings.load(default_status)
        status.deadline = deadline
        settings.save()
    elseif status.deadline ~= deadline then
        -- print(chat.header('Goldilox') .. 'Previous state was for a different day, resetting for today.')
        status.dailies = {}
        status.palalumin_quests = {}
        status.deadline = deadline
        settings.save()
    end
end

local goblin_order = { "Fishstix", "Murdox", "Mistrix", "Saltlix", "Beetrix" }  -- Left to Right as being approached from the Lower Jeuno AH
local palalumin_quest_order = {"Find flux", "Item request", "Defeat mobs"}      -- Order listed when talked to
local handlers = {
    --[[
        Fishstix : Go to Yughott Grotto, find and open my Secret Treasure Chest!
        Murdox : Go to Bhaflau Thickets and kill 20 Treants!
        Mistrix : Craft me up a signed serving of goblin stir-fry and trade it to me!
        Saltlix : Go to Dangruf Wadi and kill Teporingo!
        Beetrix : Go to Gusgen Mines, get a Gusgen Clay and trade it to me!
    --]]
    Fishstix = {
        talk = function(data, prev)
            data.zone = string.match(data.message, "Go to (.-),")
        end,
        status = function(data)
            return "Secret chest at " .. data.zone
        end,
    },
    Murdox = {
        talk = function(data, prev)
            data.count = string.match(data.message, "kill (%d+)")
            data.target = string.match(data.message, "%d+ (.+)!")
            data.zone = string.match(data.message, "Go to (.+) and")
            if prev and prev.remaining then
                data.remaining = prev.remaining
            end
        end,
        status = function(data)
            local r = data.remaining or data.count
            return (
                "Kill " .. r .. " more " .. data.target .. " at " .. data.zone
                .. " " .. chat.color1(6, "(" .. data.count .. " total)")
            )
        end,
    },
    Mistrix = {
        talk = function(data, prev)
            data.item = string.match(data.message, "Craft me up %a+ signed (.+) and trade it to me!")
        end,
        status = function(data)
            return "Trade a signed " .. data.item
        end,
    },
    Saltlix = {
        talk = function(data, prev)
            data.target = string.match(data.message, "kill (.+)!")
            data.zone = string.match(data.message, "Go to (.+) and")
        end,
        status = function(data)
            return "Kill " .. data.target .. " at " .. data.zone
        end,
    },
    Beetrix = {
        talk = function(data, prev)
            data.zone = string.match(data.message, "Go to (.-),")
            data.item = string.match(data.message, "get %a+ (.+) and trade")
        end,
        status = function(data)
            return "Trade " .. data.item .. " found at " .. data.zone
        end,
    },
}

local palalumin_quests = {
    ["Find flux"] = {
        talk = function(data)
            data.zone = data.message
        end,
        status = function(data)
            return "Find flux in " .. data.zone
        end,
    },
    ["Item request"] = {
        talk = function(data)
            data.items = data.message
        end,
        status = function(data)
            return "Trade " .. data.items
        end,
    },
    ["Defeat mobs"] = {
        talk = function(data)
            if data.completed then
                return
            end
            data.target, data.zone, data.killed, data.total = string.match(data.message, "(.+) %((.+)%) (%d+)/(%d+)")
            data.killed = tonumber(data.killed)
            data.total = tonumber(data.total)
        end,
        status = function(data)
            return (
                "Kill " .. (data.total - data.killed) .. " more " .. data.target .. " at " .. data.zone
                .. " " .. chat.color1(6, "(" .. data.total .. " total)")
            )
        end
    },
}

--[[

Goblin message modes:  vvvv always seems to be 0009
Beetrix : Go to Gusgen Mines, get a Gusgen Clay and trade it to me!
--]]

local function handle_gobbie_dialogue(e)  -- Sent under mode 9
    --[[
    Fishstix : Go to Yughott Grotto, find and open my Secret Treasure Chest!
    Murdox : Go to Bhaflau Thickets and kill 20 Treants!
    --]]

    local npc, message = string.match(e.message, ".-(%a+).-:.-(%a+.*)\n")
    if message == nil then
        return
    end
    if handlers[npc] == nil then
        return
    end
    update_status()
    local data = {message = message}
    if handlers[npc].talk then
        handlers[npc].talk(data, status.dailies[npc])
    end
    status.dailies[npc] = data
    settings.save()
end

local function handle_daily_quest_updates(e)  -- Sent under mode 121
    -- "You've killed enough Olden Treants, please return to Murdox to claim your reward!"
    -- "You've killed Teporingo, please return to Saltlix to claim your reward!"
    local return_npc = string.match(e.message, "please return to (%a+) to claim your reward")
    if return_npc then
        update_status()
        if status.dailies[return_npc] then
            status.dailies[return_npc].status = 'return'
            settings.save()
        end
        return
    end

    -- Handle individual goblin quest completion
    local complete_npc = string.match(e.message, "(%a+).*quest complete")
    if complete_npc and handlers[complete_npc] then
        update_status()
        if status.dailies[complete_npc] then
            status.dailies[complete_npc].status = 'complete'
            settings.save()
        end
        return
    end

    -- Handle Murdox kill count updates
    local kills = string.match(e.message, "(%d+) .+ remaining")
    if kills then
        update_status()
        if status.dailies.Murdox then
            status.dailies.Murdox.remaining = kills
            settings.save()
        end
        return
    end

    -- Defeat Mobs 1/10 (Zdei in Grand Palace of HuXzoi)
    local pala_killed, pala_total, pala_target, pala_zone = string.match(e.message, "Defeat Mobs (%d+)/(%d+) %((.+) in (.+)%)")
    if pala_killed then
        update_status()
        if not status.palalumin_quests then
            status.palalumin_quests = {}
        end
        status.palalumin_flagged = true
        local pala = status.palalumin_quests["Defeat mobs"]
        if not pala then
            pala = { message = "" }
            status.palalumin_quests["Defeat mobs"] = pala
        end
        pala.killed = tonumber(pala_killed)
        pala.total = tonumber(pala_total)
        pala.target = pala_target
        pala.zone = pala_zone
        settings.save()
        return
    end

    --[[
        ◇ Quest Completed  (after trading items or interacting with flux)
        Determine which quest by checking the player's current target:
          Lumorian Flux  -> Find flux
          Palalumin      -> Item request
    ]]
    if string.match(e.message, "Quest Completed") then
        update_status()
        if status.palalumin_quests then
            local target_name = get_current_target_name()
            if target_name == "Lumorian Flux" then
                if status.palalumin_quests["Find flux"] then
                    status.palalumin_quests["Find flux"].completed = true
                    settings.save()
                end
            elseif target_name == "Palalumin" then
                if status.palalumin_quests["Item request"] then
                    status.palalumin_quests["Item request"].completed = true
                    settings.save()
                end
                local defeat = status.palalumin_quests["Defeat mobs"]
                if defeat and not defeat.completed and defeat.killed and defeat.total and defeat.killed >= defeat.total then
                    defeat.completed = true
                    settings.save()
                end
            end
        end
        return
    end

    if string.match(e.message, "Dice roll!.*rolls.*%(.*%)") then
        update_status()
        status.goldilox_time = status.deadline
        settings.save()
    end
end

local function handle_palalumin_dialogue(e)
    -- Try matching filled diamond first (completed quest)
    local quest, objective = string.match(e.message, "\129\159 (.-): (.+)\n")
    local is_completed = quest ~= nil
    -- Try matching open diamond (incomplete quest)
    if not quest then
        quest, objective = string.match(e.message, "\129\158 (.-): (.+)\n")
    end
    local handler = palalumin_quests[quest]
    if not handler then
        return
    end
    objective = objective:trim()
    update_status()
    status.palalumin_flagged = true
    if not status.palalumin_quests then
        status.palalumin_quests = {}
    end
    local data = {message = objective}
    if is_completed then
        data.completed = true
    end
    status.palalumin_quests[quest] = data
    palalumin_quests[quest].talk(data)
    -- print(palalumin_quests[quest].status(data))
    settings.save()
end

ashita.events.register('text_in', 'text_in_cb', function (e)
    -- Early exit for injected messages
    if e.injected then
        return
    end

    local channel = bit.band(e.mode, 0xFF)

    -- Only process channels we care about: 9 (NPC dialogue) and 121 (system/quest updates)
    if channel ~= 9 and channel ~= 121 then
        return
    end

    if channel == 121 then
        return handle_daily_quest_updates(e)
    end

    -- channel == 9: only process in zones we care about
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    if zone == ZONE_LOWERJEUNO then
        return handle_gobbie_dialogue(e)
    elseif zone == ZONE_HUXZOI then
        return handle_palalumin_dialogue(e)
    end
end)

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then
        return
    end

    local cmd = string.lower(args[1])
    if (cmd ~= '/goldilox' and cmd ~= '/dailies') then
        return
    end

    -- Handle 'ui' subcommand to toggle the imgui window
    if (#args >= 2 and string.lower(args[2]) == 'ui') then
        goldilox_ui.toggle()
        return
    end

    update_status()
    local completed = 0
    local preamble, handler, daily
    for _, npc in ipairs(goblin_order) do
        handler = handlers[npc]
        preamble = chat.header(addon.name) .. npc .. ": "
        daily = status.dailies[npc]
        if daily == nil then
            print(preamble .. chat.color1(68, "Not talked to today."))
        elseif daily.status == 'complete' then
            print(preamble .. chat.color1(72, "Complete!"))
            completed = completed + 1
        elseif daily.status == 'return' then
            print(preamble .. chat.color1(2, "Return to " .. npc .. "."))
        elseif handler.status ~= nil then
            print(preamble .. daily.message)
        end
    end
    if completed > 0 then
        preamble = chat.header(addon.name) .."Goldilox: "
        if status.goldilox_time == status.deadline then
            print(preamble .. chat.color1(72, "Complete!"))
        else
            print(preamble .. chat.color1(68, "Reward not collected."))
        end
    end
    if status.palalumin_flagged then
        local flagged = 0
        for _, quest in ipairs(palalumin_quest_order) do
            handler = palalumin_quests[quest]
            daily = status.palalumin_quests[quest]
            if daily and not daily.completed then
                flagged = flagged + 1
                if flagged == 1 then  -- First palalumin quest
                    print(chat.header(addon.name) .. "Palalumin quests:")
                end
                print(chat.header(addon.name) .. DIAMOND .. " " .. handler.status(daily))
                -- for k, v in pairs(data) do
                --     print(k .. "=" .. v)
                -- end
            end
        end
    end
end)

-- Returns true if the player is not yet fully loaded (no valid level data)
local function is_loading()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then return true end
    local level = player:GetMainJobLevel()
    return not level or level == 0
end

-- ImGui rendering
ashita.events.register('d3d_present', 'goldilox_ui_cb', function()
    if is_loading() then return end
    if status == nil then
        update_status()
    end
    goldilox_ui.render(status, goblin_order, handlers, palalumin_quest_order, palalumin_quests)
end)

-- Track Shift key state for window dragging
ashita.events.register('key', 'goldilox_key_cb', function(e)
    if e.wparam == 0x10 then -- VK_SHIFT
        goldilox_ui.shift_held = not (bit.band(e.lparam, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10))
    end
end)