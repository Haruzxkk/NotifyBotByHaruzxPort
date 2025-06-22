local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local webhookURL     = getgenv().webhook or ""
local baseTargetPets = getgenv().TargetPetNames or {}

local LocalPlayer
local visitedJobIds  = {}
local hops           = 0
local detectedPets   = {}
local teleportFails  = 0
local webhookSent    = false
local stopHopping    = false

local MAX_HOPS_BEFORE_RESET = 50
local MAX_TELEPORT_RETRIES  = 3

repeat LocalPlayer = Players.LocalPlayer task.wait() until LocalPlayer
visitedJobIds[game.JobId] = true

local function getPetRarity(fullName)
    local rarities = { "Rainbow", "Gold", "Diamond" }
    for _, r in ipairs(rarities) do
        if fullName:lower():find("^" .. r:lower()) then
            return r
        end
    end
    return "Normal"
end

local function getPetBaseName(fullName)
    local rarities = { "Rainbow", "Gold", "Diamond" }
    for _, r in ipairs(rarities) do
        if fullName:lower():find("^" .. r:lower()) then
            return fullName:sub(#r + 2)
        end
    end
    return fullName
end

local function makeEmbed(foundPets, jobId)
    local petCounts = {}
    for _, pet in ipairs(foundPets) do
        petCounts[pet] = (petCounts[pet] or 0) + 1
    end
    local formattedPets = {}
    for name, count in pairs(petCounts) do
        table.insert(formattedPets, count > 1 and (name .. " x" .. count) or name)
    end
    return {
        title       = "🎯 Pet Detection Alert",
        description = "Target pet(s) found in server!",
        fields = {
            { name = "👤 Player",        value = LocalPlayer.Name,           inline = true },
            { name = "🐾 Pet(s) Found",  value = table.concat(formattedPets, "\n"), inline = true },
            { name = "🆔 Server Job ID", value = "```" .. jobId .. "```",          inline = false },
            { name = "🕐 Detection Time",value = os.date("%Y-%m-%d %H:%M:%S UTC"), inline = true },
            { name = "📊 Servers Checked",value = tostring(hops + 1),             inline = true }
        },
        color     = 0x00FF00,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
        footer    = { text = "NotifyBot • 1.0 Version" }
    }
end

local function sendWebhook(foundPets, jobId)
    if webhookURL == "" then return end
    local embed = makeEmbed(foundPets, jobId)
    local payload = {
        username   = "NotifyBot",
        avatar_url = "https://i.postimg.cc/8PLg2H9S/file-00000000c9bc62308340df6809d63f45.png",
        content    = "@everyone 🚨 **TARGET PET DETECTED!**",
        embeds     = { embed }
    }
    local jsonData = HttpService:JSONEncode(payload)
    local req = http_request or request or (syn and syn.request)
    if not req then return end
    pcall(function()
        req({ Url = webhookURL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = jsonData })
        webhookSent = true
    end)
end

local function addESP(targetModel)
    if targetModel:FindFirstChild("PetESP") then return end
    local billboard = Instance.new("BillboardGui", targetModel)
    billboard.Name        = "PetESP"
    billboard.Adornee     = targetModel
    billboard.Size        = UDim2.new(0, 150, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true

    local rarityLabel = Instance.new("TextLabel", billboard)
    rarityLabel.Size               = UDim2.new(1, 0, 0.5, 0)
    rarityLabel.Position           = UDim2.new(0, 0, 0, 0)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Text               = getPetRarity(targetModel.Name)
    rarityLabel.TextColor3         = Color3.fromRGB(255, 215, 0)
    rarityLabel.TextStrokeTransparency = 0.5
    rarityLabel.Font               = Enum.Font.SourceSansBold
    rarityLabel.TextScaled         = true

    local nameLabel = Instance.new("TextLabel", billboard)
    nameLabel.Size               = UDim2.new(1, 0, 0.5, 0)
    nameLabel.Position           = UDim2.new(0, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text               = getPetBaseName(targetModel.Name)
    nameLabel.TextColor3         = Color3.fromRGB(255, 0, 0)
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.Font               = Enum.Font.SourceSansBold
    nameLabel.TextScaled         = true
end

local function isTargetPet(fullName)
    local base = getPetBaseName(fullName):lower()
    for _, target in ipairs(baseTargetPets) do
        if base == target:lower() then
            return true
        end
    end
    return false
end

local function checkForPets()
    local found = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and isTargetPet(obj.Name) and not obj:FindFirstChild("PetESP") then
            addESP(obj)
            table.insert(found, obj.Name)
            stopHopping = true
        end
    end
    return found
end

TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    if result == Enum.TeleportResult.Unauthorized then
        visitedJobIds[game.JobId] = true
    end
    if teleportFails >= MAX_TELEPORT_RETRIES then
        teleportFails = 0
        task.wait(1)
        TeleportService:Teleport(game.PlaceId)
    else
        task.wait(1)
        serverHop()
    end
end)

workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.25)
    if obj:IsA("Model") and isTargetPet(obj.Name) and not detectedPets[obj.Name] then
        detectedPets[obj.Name] = true
        addESP(obj)
        stopHopping = true
        if not webhookSent then
            sendWebhook({ obj.Name }, game.JobId)
        end
    end
end)

function serverHop()
    if stopHopping then return end
    task.wait(1.5)
    hops += 1
    if hops >= MAX_HOPS_BEFORE_RESET then
        visitedJobIds = { [game.JobId] = true }
        hops = 0
    end

    local cursor, tries = nil, 0
    while tries < 3 do
        local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s")
            :format(game.PlaceId, cursor and ("&cursor="..cursor) or "")
        local ok, resp = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)
        if ok and resp and resp.data then
            local servers = {}
            for _, s in ipairs(resp.data) do
                if tonumber(s.playing) < tonumber(s.maxPlayers) and not visitedJobIds[s.id] then
                    table.insert(servers, s.id)
                end
            end
            if #servers > 0 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(#servers)])
                return
            end
            cursor = resp.nextPageCursor
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

task.wait(6)
local initialPets = checkForPets()
if #initialPets > 0 then
    for _, name in ipairs(initialPets) do
        detectedPets[name] = true
    end
    sendWebhook(initialPets, game.JobId)
else
    task.delay(1.5, serverHop)
end