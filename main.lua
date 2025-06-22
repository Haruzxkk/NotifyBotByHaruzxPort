-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Wait for LocalPlayer to initialize
local LocalPlayer
repeat
    LocalPlayer = Players.LocalPlayer
    task.wait()
until LocalPlayer

-- User Configuration
local webhook = getgenv().webhook or ""
local targetPets = getgenv().TargetPetNames or {}

-- State Tracking
local visitedJobIds = { [game.JobId] = true }
local hops = 0
local maxHopsBeforeReset = 50
local teleportFails = 0
local maxTeleportRetries = 3
local detectedPets = {}
local webhookSent = false
local stopHopping = false

-- Teleport Fail Handling
TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    if teleportFails >= maxTeleportRetries then
        teleportFails = 0
        task.wait(1)
        TeleportService:Teleport(game.PlaceId)
    else
        task.wait(1)
        serverHop()
    end
end)

-- ESP Function
local function addESP(targetModel)
    if targetModel:FindFirstChild("PetESP") then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PetESP"
    billboard.Adornee = targetModel
    billboard.Size = UDim2.new(0, 100, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = targetModel

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "🎯 Target (" .. targetModel.Name .. ")"
    label.TextColor3 = Color3.fromRGB(255, 0, 0)
    label.TextStrokeTransparency = 0.5
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.Parent = billboard
end

-- Webhook Function
local function sendWebhook(foundPets, jobId)
    if webhook == "" then return end

    -- Count occurrences
    local petCounts = {}
    for _, pet in ipairs(foundPets) do
        petCounts[pet] = (petCounts[pet] or 0) + 1
    end

    local formattedPets = {}
    for name, count in pairs(petCounts) do
        table.insert(formattedPets, count > 1 and (name .. " x" .. count) or name)
    end

    -- Build embed
    local embed = {
        title       = "🧠 Pet(s) Found!",
        description = "Brainrot-worthy pet detected in the server!",
        fields = {
            { name = "User",         value = LocalPlayer.Name },
            { name = "Found Pet(s)", value = table.concat(formattedPets, "\n") },
            { name = "Server JobId", value = jobId },
            { name = "Time",         value = os.date("%Y-%m-%d %H:%M:%S") }
        },
        color = 0xFF00FF
    }

    -- Build payload
    local payload = {
        username   = "NotifyBot",
        avatar_url = "https://i.postimg.cc/8PLg2H9S/file-00000000c9bc62308340df6809d63f45.png",
        content    = "🚨 TARGET PET DETECTED!",
        embeds     = { embed }
    }

    local json = HttpService:JSONEncode(payload)
    local req = http_request or request or (syn and syn.request)
    if req then
        pcall(function()
            req({
                Url     = webhook,
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = json
            })
        end)
    end
end

-- Pet Detection Function
local function checkForPets()
    local found = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local lowerName = obj.Name:lower()
            for _, target in ipairs(targetPets) do
                if lowerName:find(target:lower()) and not obj:FindFirstChild("PetESP") then
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

-- Server Hop Function
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
        local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100")
                        :format(game.PlaceId)
        if cursor then url = url .. "&cursor=" .. cursor end

        local success, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if success and res and res.data then
            local servers = {}
            for _, s in ipairs(res.data) do
                if tonumber(s.playing or 0) < tonumber(s.maxPlayers or 1)
                   and s.id ~= game.JobId
                   and not visitedJobIds[s.id] then
                    table.insert(servers, s.id)
                end
            end

            if #servers > 0 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(#servers)])
                return
            end

            cursor = res.nextPageCursor or nil
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

-- Live Detection
workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.25)
    if obj:IsA("Model") then
        local lowerName = obj.Name:lower()
        for _, target in ipairs(targetPets) do
            if lowerName:find(target:lower()) and not obj:FindFirstChild("PetESP") then
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

-- Startup
task.wait(6)
local pets = checkForPets()
if #pets > 0 then
    for _, name in ipairs(pets) do detectedPets[name] = true end
    if not webhookSent then
        sendWebhook(pets, game.JobId)
        webhookSent = true
    end
else
    task.delay(1.5, serverHop)
end