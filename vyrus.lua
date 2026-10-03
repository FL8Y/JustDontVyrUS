local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

--//==================================================
--// GAME MODULES
--//==================================================

local UnitConfig = require(
    ReplicatedStorage.Framework.Features.Inventory.Kinds.Unit.UnitConfig
)

local FusingUtil = require(
    ReplicatedStorage.Framework.Features.Fusing.FusingUtil
)

local FuseRemote =
    ReplicatedStorage.Network.FusingService.RE.Fuse

local ResultRemote =
    ReplicatedStorage
        :WaitForChild("Network")
        :WaitForChild("FusingService")
        :WaitForChild("RE")
        :WaitForChild("Result")

local Entries = UnitConfig.entries

--//==================================================
--// SETTINGS
--//==================================================

local Settings = {
    Enabled = false,
    Delay = 1.5,

    From = 0,
    Below = math.huge,

    Order = "Rarest First",

    -- Fusion visual optimization
    SkipFusionEffects = false,

    -- Fusion controller research
    DisableFusionController = false,
}

local Stats = {
    Done = 0,
    Scans = 0,
}

--//==================================================
--// FUSION CONTROLLER STATE
--//==================================================

local DisabledConnections = {}
local IsControllerDisabled = false

--//==================================================
--// NUMBER SUFFIXES
--//==================================================

local suffixes = {
    {1e30, "no"},
    {1e27, "oc"},
    {1e24, "sp"},
    {1e21, "sx"},
    {1e18, "qi"},
    {1e15, "qd"},
    {1e12, "t"},
    {1e9, "b"},
    {1e6, "m"},
    {1e3, "k"},
}

local multipliers = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
    t = 1e12,
    qd = 1e15,
    qi = 1e18,
    sx = 1e21,
    sp = 1e24,
    oc = 1e27,
    no = 1e30,
}

--//==================================================
--// PARSE USER NUMBER
--//==================================================

local function parseNumber(value)

    if type(value) ~= "string" then
        return nil
    end

    value = value:lower()
    value = value:gsub(",", "")
    value = value:gsub("%s+", "")

    local number, suffix =
        value:match("^([%d%.]+)([a-z]+)$")

    if number and suffix then

        number = tonumber(number)

        local multiplier =
            multipliers[suffix]

        if number and multiplier then
            return number * multiplier
        end
    end

    return tonumber(value)
end

--//==================================================
--// FORMAT NUMBER
--//==================================================

local function formatNumber(value)

    if value == math.huge then
        return "∞"
    end

    for _, item in ipairs(suffixes) do

        local divisor = item[1]
        local suffix = item[2]

        if value >= divisor then

            local n = value / divisor

            if math.abs(
                n - math.floor(n)
            ) < 0.000001 then

                return tostring(
                    math.floor(n)
                ) .. suffix
            end

            local formatted =
                string.format("%.3f", n)

            formatted =
                formatted
                :gsub("0+$", "")
                :gsub("%.$", "")

            return formatted .. suffix
        end
    end

    return tostring(value)
end

--//==================================================
--// GUID
--//==================================================

local function isGUID(value)

    return type(value) == "string"
        and value:match(
            "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
        ) ~= nil
end

--//==================================================
--// FIND INVENTORY
--//==================================================

local function getInventory()

    local best = nil
    local bestSize = 0

    for _, value in pairs(getgc(true)) do

        if type(value) == "table" then

            local ok, inventory =
                pcall(rawget, value, "Inventory")

            if ok and type(inventory) == "table" then

                local size = 0

                for guid, data in pairs(inventory) do

                    if isGUID(guid)
                        and type(data) == "table"
                        and rawget(data, "name") then

                        size += 1
                    end
                end

                if size > bestSize then
                    bestSize = size
                    best = inventory
                end
            end
        end
    end

    return best, bestSize
end

--//==================================================
--// GET CHANCE
--//==================================================

local function getChance(data)

    local ok, result =
        pcall(
            FusingUtil.GetChance,
            data
        )

    if ok and type(result) == "number" then
        return result
    end

    return nil
end

--//==================================================
--// SCAN INVENTORY
--//==================================================

local function scan()

    local inventory, inventorySize =
        getInventory()

    if not inventory then
        return nil
    end

    local groups = {}

    for guid, data in pairs(inventory) do

        if isGUID(guid)
            and type(data) == "table" then

            local name =
                rawget(data, "name")

            if name and Entries[name] then

                local chance =
                    getChance(data)

                if chance then

                    local groupKey =
                        formatNumber(chance)

                    groups[groupKey] =
                        groups[groupKey] or {}

                    table.insert(
                        groups[groupKey],
                        {
                            guid = guid,
                            name = name,
                            chance = chance,
                        }
                    )

                    print(
                        "[Auto Fuse]",
                        name,
                        "| Raw Chance:",
                        chance,
                        "| Display:",
                        "1 in " .. groupKey
                    )
                end
            end
        end
    end

    return {
        inventorySize = inventorySize,
        groups = groups,
    }
end

--//==================================================
--// FIND CANDIDATES
--//==================================================

local function getCandidates(scanData)

    local candidates = {}

    for groupKey, units in pairs(
        scanData.groups
    ) do

        if #units >= 3 then

            local chance =
                units[1].chance

            if chance >= Settings.From
                and chance < Settings.Below then

                table.insert(
                    candidates,
                    {
                        key = groupKey,
                        chance = chance,
                        units = units,
                        count = #units,
                    }
                )
            end
        end
    end

    if Settings.Order == "Rarest First" then

        table.sort(
            candidates,
            function(a, b)

                if a.chance ~= b.chance then
                    return a.chance > b.chance
                end

                return a.count > b.count
            end
        )

    elseif Settings.Order == "Most Copies First" then

        table.sort(
            candidates,
            function(a, b)

                if a.count ~= b.count then
                    return a.count > b.count
                end

                return a.chance > b.chance
            end
        )

    elseif Settings.Order == "Lowest Value First" then

        table.sort(
            candidates,
            function(a, b)
                return a.chance < b.chance
            end
        )
    end

    return candidates
end

--//==================================================
--// WINDOW
--//==================================================

local Window = Rayfield:CreateWindow({

    Name = "Anime Dice | Auto Fuse",

    LoadingTitle = "Auto Fuse",

    LoadingSubtitle = "Fusion Animation Research",

    ConfigurationSaving = {
        Enabled = false,
    },

    Discord = {
        Enabled = false,
    },

    KeySystem = false,
})

local Tab =
    Window:CreateTab(
        "Fusing",
        nil
    )

local ResearchTab =
    Window:CreateTab(
        "Animation Test",
        nil
    )

--//==================================================
--// STATUS
--//==================================================

local StatusLabel =
    Tab:CreateLabel(
        "Fuse: Idle"
    )

local TargetLabel =
    Tab:CreateLabel(
        "Target: None"
    )

local InventoryLabel =
    Tab:CreateLabel(
        "Inventory: 0"
    )

local DoneLabel =
    Tab:CreateLabel(
        "Done: 0"
    )

local ScanLabel =
    Tab:CreateLabel(
        "Scans: 0"
    )

--//==================================================
--// FUSION EFFECT SUPPRESSOR
--//==================================================

local FusionEffectConnection = nil

local function handleFusionObject(obj)

    if not Settings.SkipFusionEffects then
        return
    end

    if obj:IsA("ParticleEmitter")
        or obj:IsA("Beam")
        or obj:IsA("Trail") then

        obj.Enabled = false
        return
    end

    if obj.Name == "CutsceneBlackFade"
        and obj:IsA("ScreenGui") then

        obj.Enabled = false
        return
    end

    if obj.Name == "Frame"
        and obj.Parent
        and obj.Parent.Name == "CutsceneBlackFade"
        and obj:IsA("GuiObject") then

        obj.Visible = false
    end
end

local function startFusionEffectSuppressor()

    if FusionEffectConnection then
        return
    end

    local PlayerGui =
        LocalPlayer:WaitForChild("PlayerGui")

    FusionEffectConnection =
        PlayerGui.DescendantAdded:Connect(
            handleFusionObject
        )

    print(
        "[Fusion FPS] Effect listener started."
    )
end

local function stopFusionEffectSuppressor()

    if FusionEffectConnection then

        FusionEffectConnection:Disconnect()

        FusionEffectConnection = nil

        print(
            "[Fusion FPS] Effect listener stopped."
        )
    end
end

--//==================================================
--// FUSION FPS TOGGLE
--//==================================================

Tab:CreateToggle({

    Name = "Skip Fusion Effects",

    CurrentValue = false,

    Flag = "SkipFusionEffects",

    Callback = function(value)

        Settings.SkipFusionEffects =
            value

        if value then

            startFusionEffectSuppressor()

            Rayfield:Notify({
                Title = "Fusion FPS",
                Content = "Effect suppression enabled.",
                Duration = 3
            })

        else

            stopFusionEffectSuppressor()

            Rayfield:Notify({
                Title = "Fusion FPS",
                Content = "Effect suppression disabled.",
                Duration = 3
            })
        end
    end,
})

--//==================================================
--// FUSING CONTROLLER RESEARCH
--//==================================================

local function getControllerConnection()

    if not getconnections then

        warn(
            "[Fusion Research] getconnections is not supported."
        )

        return nil
    end

    for _, connection in ipairs(
        getconnections(ResultRemote.OnClientEvent)
    ) do

        local fn = connection.Function

        if fn then

            local info =
                debug.getinfo(fn)

            if info and info.source then

                if tostring(info.source):find(
                    "FusingController",
                    1,
                    true
                ) then

                    return connection
                end
            end
        end
    end

    return nil
end

local function disableController()

    if IsControllerDisabled then

        warn(
            "[Fusion Research] Controller listener already disabled."
        )

        return
    end

    local connection =
        getControllerConnection()

    if not connection then

        warn(
            "[Fusion Research] FusingController connection NOT FOUND."
        )

        Rayfield:Notify({
            Title = "Fusion Research",
            Content = "FusingController connection was not found.",
            Duration = 4
        })

        return
    end

    DisabledConnections[1] =
        connection

    local success, err =
        pcall(function()
            connection:Disable()
        end)

    if not success then

        table.clear(
            DisabledConnections
        )

        warn(
            "[Fusion Research] Failed to disable:",
            err
        )

        return
    end

    IsControllerDisabled = true

    warn("================================")
    warn("FUSING CONTROLLER DISABLED")
    warn("Result RemoteEvent remains active")
    warn("Perform ONE fusion now.")
    warn("================================")

    Rayfield:Notify({
        Title = "Fusion Research",
        Content = "Controller disabled. Perform ONE fusion.",
        Duration = 4
    })
end

local function enableController()

    if not IsControllerDisabled then

        warn(
            "[Fusion Research] Controller is already enabled."
        )

        return
    end

    for _, connection in ipairs(
        DisabledConnections
    ) do

        pcall(function()
            connection:Enable()
        end)
    end

    table.clear(
        DisabledConnections
    )

    IsControllerDisabled = false

    warn("================================")
    warn("FUSING CONTROLLER RESTORED")
    warn("================================")

    Rayfield:Notify({
        Title = "Fusion Research",
        Content = "FusingController restored.",
        Duration = 3
    })
end

--//==================================================
--// CONTROLLER TOGGLE
--//==================================================

ResearchTab:CreateToggle({

    Name = "Disable Fusion Result Controller",

    CurrentValue = false,

    Flag = "DisableFusionController",

    Callback = function(value)

        Settings.DisableFusionController =
            value

        if value then
            disableController()
        else
            enableController()
        end
    end,
})

--//==================================================
--// INSPECT RESULT CONNECTIONS
--//==================================================

ResearchTab:CreateButton({

    Name = "Inspect Result Connections",

    Callback = function()

        warn("================================")
        warn("RESULT CONNECTION INSPECTION")
        warn("================================")

        if not getconnections then

            warn(
                "getconnections unavailable"
            )

            return
        end

        local connections =
            getconnections(
                ResultRemote.OnClientEvent
            )

        warn(
            "Connections:",
            #connections
        )

        for i, connection in ipairs(
            connections
        ) do

            local fn =
                connection.Function

            if fn then

                local info =
                    debug.getinfo(fn)

                warn(
                    "#" .. i,
                    "SOURCE =",
                    info and info.source or "unknown",
                    "LINE =",
                    info and info.currentline or "unknown"
                )
            end
        end

        warn("================================")
    end,
})

--//==================================================
--// RESEARCH STATUS
--//==================================================

ResearchTab:CreateSection(
    "Fusion Animation Isolation"
)

ResearchTab:CreateLabel(
    "Effect suppressor: Particles / Beams / Trails / Fade"
)

ResearchTab:CreateLabel(
    "Controller test: FusingController Result callback"
)

ResearchTab:CreateLabel(
    "Use one test at a time when comparing frame behavior."
)

ResearchTab:CreateLabel(
    "If controller is disabled, Result RemoteEvent stays active."
)

--//==================================================
--// FROM INPUT
--//==================================================

Tab:CreateInput({

    Name = "Fuse from 1 in",

    PlaceholderText = "650qd",

    RemoveTextAfterFocusLost = false,

    CurrentValue = "",

    Callback = function(value)

        if value == "" then
            Settings.From = 0
            return
        end

        local parsed =
            parseNumber(value)

        if parsed then
            Settings.From = parsed
        end
    end,
})

--//==================================================
--// BELOW INPUT
--//==================================================

Tab:CreateInput({

    Name = "Fuse below 1 in",

    PlaceholderText = "1sx",

    RemoveTextAfterFocusLost = false,

    CurrentValue = "",

    Callback = function(value)

        if value == "" then
            Settings.Below = math.huge
            return
        end

        local parsed =
            parseNumber(value)

        if parsed then
            Settings.Below = parsed
        end
    end,
})

--//==================================================
--// ORDER
--//==================================================

Tab:CreateDropdown({

    Name = "Order",

    Options = {
        "Rarest First",
        "Most Copies First",
        "Lowest Value First",
    },

    CurrentOption = {
        "Rarest First"
    },

    Callback = function(option)

        if type(option) == "table" then
            option = option[1]
        end

        Settings.Order = option
    end,
})

--//==================================================
--// FUSE THREE UNITS
--//==================================================

local function fuseSelected(selected)

    if not selected then
        return false
    end

    local a = selected.units[1]
    local b = selected.units[2]
    local c = selected.units[3]

    if not a or not b or not c then
        return false
    end

    local unitNames =
        tostring(a.name)
        .. " + "
        .. tostring(b.name)
        .. " + "
        .. tostring(c.name)

    local chanceText =
        formatNumber(selected.chance)

    StatusLabel:Set(
        "Fusing: " .. unitNames
    )

    TargetLabel:Set(
        "1 in "
        .. chanceText
        .. " | "
        .. unitNames
    )

    print("==============================")
    print("[AUTO FUSE]")
    print("Unit 1:", a.name, "|", a.chance)
    print("Unit 2:", b.name, "|", b.chance)
    print("Unit 3:", c.name, "|", c.chance)
    print("Display Chance: 1 in " .. chanceText)
    print("==============================")

    local success, err =
        pcall(function()

            FuseRemote:FireServer(
                a.guid,
                b.guid,
                c.guid
            )
        end)

    if success then

        Stats.Done += 1

        DoneLabel:Set(
            "Done: " .. Stats.Done
        )

        StatusLabel:Set(
            "Fused: " .. unitNames
        )

        TargetLabel:Set(
            "1 in "
            .. chanceText
            .. " | "
            .. unitNames
        )

        print(
            "[Auto Fuse] Fused:",
            unitNames
        )

        print(
            "[Auto Fuse] Chance: 1 in "
            .. chanceText
        )

        return true

    else

        StatusLabel:Set(
            "Fuse Error"
        )

        warn(
            "[Auto Fuse] Error:",
            err
        )

        return false
    end
end

--//==================================================
--// PERFORM FUSION
--//==================================================

local function performFusion()

    Stats.Scans += 1

    ScanLabel:Set(
        "Scans: " .. Stats.Scans
    )

    local data =
        scan()

    if not data then

        StatusLabel:Set(
            "Fuse: Inventory not found"
        )

        TargetLabel:Set(
            "Target: None"
        )

        InventoryLabel:Set(
            "Inventory: 0"
        )

        return false
    end

    InventoryLabel:Set(
        "Inventory: "
        .. data.inventorySize
    )

    local candidates =
        getCandidates(data)

    if #candidates == 0 then

        StatusLabel:Set(
            "Fuse: Nothing eligible"
        )

        TargetLabel:Set(
            "Target: None"
        )

        return false
    end

    local selected =
        candidates[1]

    print(
        "[Auto Fuse] Candidate:",
        selected.key,
        "| Copies:",
        selected.count
    )

    return fuseSelected(selected)
end

--//==================================================
--// FIND NEXT FUSION
--//==================================================

Tab:CreateButton({

    Name = "Find Next Fusion",

    Callback = function()
        performFusion()
    end,
})

--//==================================================
--// AUTO FUSE
--//==================================================

Tab:CreateToggle({

    Name = "Auto Fuse",

    CurrentValue = false,

    Flag = "AutoFuseToggle",

    Callback = function(value)

        Settings.Enabled = value

        if not value then

            StatusLabel:Set(
                "Fuse: Idle"
            )

            TargetLabel:Set(
                "Target: None"
            )

            return
        end

        StatusLabel:Set(
            "Fuse: Scanning..."
        )

        task.spawn(function()

            while Settings.Enabled do

                performFusion()

                task.wait(
                    Settings.Delay
                )
            end
        end)
    end,
})

--//==================================================
--// DELAY
--//==================================================

Tab:CreateSlider({

    Name = "Fuse Delay",

    Range = {
        0.5,
        5
    },

    Increment = 0.5,

    Suffix = "s",

    CurrentValue = 1.5,

    Flag = "FuseDelaySlider",

    Callback = function(value)

        Settings.Delay = value
    end,
})

--//==================================================
--// INFORMATION
--//==================================================

Tab:CreateSection(
    "Fusion FPS Optimization"
)

Tab:CreateLabel(
    "Skip Fusion Effects disables newly-created effects."
)

Tab:CreateLabel(
    "Uses an event listener instead of constant GUI scanning."
)

Tab:CreateLabel(
    "Targets ParticleEmitters, Beams, Trails and cutscene fade."
)

Tab:CreateSection(
    "How It Selects"
)

Tab:CreateLabel(
    "Groups units by displayed 1 in X chance."
)

Tab:CreateLabel(
    "Only groups with 3+ copies are eligible."
)

Tab:CreateLabel(
    "From / Below control the chance range."
)

Tab:CreateLabel(
    "Rarest First selects the highest chance."
)

Tab:CreateLabel(
    "Exactly 3 units are selected."
)

--//==================================================
--// CLEANUP
--//==================================================

game:GetService("Players").LocalPlayer.CharacterRemoving:Connect(
    function()
        if IsControllerDisabled then
            enableController()
        end

        stopFusionEffectSuppressor()
    end
)

--//==================================================
--// LOADED
--//==================================================

Rayfield:Notify({
    Title = "Auto Fuse",
    Content = "Auto Fuse + Fusion Animation Research loaded.",
    Duration = 4
})
