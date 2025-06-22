local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer
repeat
    LocalPlayer = Players.LocalPlayer
    task.wait()
until LocalPlayer

local webhook    = getgenv().webhook or ""
local targetPets = getgenv().TargetPetNames or {}

local visitedJobIds      = { [game.JobId] = true }
local hops               = 0
local maxHopsBeforeReset = 50

local teleportFails      = 0
local maxTeleportRetries = 3

local detectedPets = {}
local webhookSent  = false
local stopHopping  = false

TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    if result == Enum.TeleportResult.GameFull then
        warn("Game full. Retrying...")
    elseif result == Enum.TeleportResult.Unauthorized then
        warn("Unauthorized server. Blacklisting...")
        visitedJobIds[game.JobId] = true
    end

    if teleportFails >= maxTeleportRetries then
        teleportFails = 0
        task.wait(1)
        TeleportService:Teleport(game.PlaceId)
    else
        task.wait(1)
        serverHop()
    end
end)

local function addESP(model)
    if model:FindFirstChild("PetESP") then return end
    local gui = Instance.new("BillboardGui")
    gui.Name           = "PetESP"
    gui.Adornee        = model
    gui.Size           = UDim2.new(0, 120, 0, 30)
    gui.StudsOffset    = Vector3.new(0, 3, 0)
    gui.AlwaysOnTop    = true
    gui.Parent         = model

    local label = Instance.new("TextLabel")
    label.Size                = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text                = "Target (" .. model.Name .. ")"
    label.TextColor3          = Color3.fromRGB(255, 0, 0)
    label.TextStrokeTransparency = 0.5
    label.Font                = Enum.Font.SourceSansBold
    label.TextScaled          = true
    label.Parent              = gui
end

function sendWebhook(foundPets, jobId)
    if webhook == "" then return end

    local petCounts = {}
    for _, pet in ipairs(foundPets) do
        petCounts[pet] = (petCounts[pet] or 0) + 1
    end

    local formatted = {}
    for name, count in pairs(petCounts) do
        if count > 1 then
            table.insert(formatted, name .. " x" .. count)
        else
            table.insert(formatted, name)
        end
    end

    local embed = {
        title       = "🎯 Pet Detection Alert",
        description = "Target pet(s) found in server!",
        fields      = {
            { name = "👤 Player",         value = LocalPlayer.Name,                   inline = true  },
            { name = "🐾 Pet(s) Found",    value = table.concat(formatted, "\n"),      inline = true  },
            { name = "🆔 Server Job ID",   value = tostring(jobId),                    inline = false },
            { name = "🕐 Detection Time",  value = os.date("%Y-%m-%d %H:%M:%S UTC"),  inline = true  },
            { name = "📊 Servers Checked", value = tostring(hops + 1),                 inline = true  },
        },
        color     = 0x00FF00,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
        footer    = { text = "NotifyBot • 1.0 Version" }
    }

    if #foundPets > 1 then
        table.insert(embed.fields, {
            name   = "🔢 Total Targets",
            value  = tostring(#foundPets),
            inline = false
        })
    end

    local payload = {
        username   = "NotifyBot",
        avatar_url = "https://i.postimg.cc/8PLg2H9S/file-00000000c9bc62308340df6809d63f45.png",
        content    = "🚨 TARGET PET DETECTED!",
        embeds     = { embed }
    }

    local data = HttpService:JSONEncode(payload)
    local req  = http_request or request or (syn and syn.request)
    if req then
        pcall(function()
            req({
                Url     = webhook,
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = data
            })
        end)
    end
end

local function checkForPets()
    local found = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local lower = obj.Name:lower()
            for _, target in ipairs(targetPets) do
                if lower:find(target:lower()) and not obj:FindFirstChild("PetESP") then
                    addESP(obj)
                    table.insert(found, obj.Name)
                    stopHopping = true
                    break
                end
            end
        end
    end
    return found
end

function serverHop()
    if stopHopping then return end
    task.wait(1.5)

    hops += 1
    if hops >= maxHopsBeforeReset then
        visitedJobIds = { [game.JobId] = true }
        hops = 0
    end

    local cursor, tries = nil, 0
    while tries < 3 do
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor then url = url .. "&cursor=" .. cursor end

        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if ok and res and res.data then
            local servers = {}
            for _, s in ipairs(res.data) do
                if tonumber(s.playing) < tonumber(s.maxPlayers)
                   and s.id ~= game.JobId
                   and not visitedJobIds[s.id] then
                    table.insert(servers, s.id)
                end
            end

            if #servers > 0 then
                local pick = servers[math.random(#servers)]
                teleportFails = 0
                TeleportService:TeleportToPlaceInstance(game.PlaceId, pick)
                return
            end

            cursor = res.nextPageCursor
            if not cursor then
                tries += 1
                task.wait(0.5)
            end
        else
            tries += 1
            task.wait(0.5)
        end
    end

    TeleportService:Teleport(game.PlaceId)
end

workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.25)
    if obj:IsA("Model") then
        local lower = obj.Name:lower()
        for _, target in ipairs(targetPets) do
            if lower:find(target:lower()) and not obj:FindFirstChild("PetESP") then
                if not detectedPets[obj.Name] then
                    detectedPets[obj.Name] = true
                    addESP(obj)
                    stopHopping = true
                    if not webhookSent then
                        sendWebhook({ obj.Name }, game.JobId)
                        webhookSent = true
                    end
                end
                break
            end
        end
    end
end)

task.wait(6)
local initial = checkForPets()
if #initial > 0 then
    for _, n in ipairs(initial) do
        detectedPets[n] = true
    end
    if not webhookSent then
        sendWebhook(initial, game.JobId)
        webhookSent = true
    end
else
    task.delay(1.5, serverHop)
end