local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local CONFIG = {
    webhook = getgenv().webhook or "",
    targetPets = getgenv().PetNames or {},
    maxHopsBeforeReset = 50,
    maxTeleportRetries = 3,
    checkInterval = 2,
    espUpdateRate = 1,
    teleportDelay = 1.5,
    petDetectionDelay = 0.25
}

local State = {
    visitedJobIds = {[game.JobId] = true},
    hops = 0,
    teleportFails = 0,
    detectedPets = {},
    webhookSent = false,
    stopHopping = false,
    isSearching = true,
    espObjects = {},
    lastCheck = 0,
    isHopping = false
}

local function safeWait(duration)
    local start = tick()
    while tick() - start < duration and State.isSearching do
        task.wait(0.1)
    end
end

local function logMessage(message, level)
    level = level or "INFO"
    local timestamp = os.date("%H:%M:%S")
    local prefix = level == "ERROR" and "❌" or level == "WARN" and "⚠️" or level == "SUCCESS" and "✅" or "🔍"
    print(string.format("[%s] %s %s", timestamp, prefix, message))
end

local function showNotification(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

local function waitForPlayer()
    local attempts = 0
    local maxAttempts = 30
    
    while not Players.LocalPlayer and attempts < maxAttempts do
        task.wait(0.5)
        attempts += 1
    end
    
    if not Players.LocalPlayer then
        logMessage("Failed to get LocalPlayer after 15 seconds", "ERROR")
        return false
    end
    
    return true
end

if not waitForPlayer() then
    return
end

local LocalPlayer = Players.LocalPlayer

local function createESP(targetModel, petName)
    if not targetModel or not targetModel.Parent or targetModel:FindFirstChild("PetESP") or State.espObjects[targetModel] then 
        return 
    end
    
    local success = pcall(function()
        local Billboard = Instance.new("BillboardGui")
        Billboard.Name = "PetESP"
        Billboard.Adornee = targetModel
        Billboard.Size = UDim2.new(0, 120, 0, 50)
        Billboard.StudsOffset = Vector3.new(0, 3, 0)
        Billboard.AlwaysOnTop = true
        Billboard.Parent = targetModel

        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, 0, 1, 0)
        Frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        Frame.BackgroundTransparency = 0.3
        Frame.BorderSizePixel = 0
        Frame.Parent = Billboard
        
        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 8)
        Corner.Parent = Frame

        local NameLabel = Instance.new("TextLabel")
        NameLabel.Size = UDim2.new(1, 0, 0.6, 0)
        NameLabel.Position = UDim2.new(0, 0, 0, 0)
        NameLabel.BackgroundTransparency = 1
        NameLabel.Text = "🎯 " .. (petName or targetModel.Name)
        NameLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        NameLabel.TextStrokeTransparency = 0
        NameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        NameLabel.Font = Enum.Font.SourceSansBold
        NameLabel.TextScaled = true
        NameLabel.Parent = Frame

        local StatusLabel = Instance.new("TextLabel")
        StatusLabel.Size = UDim2.new(1, 0, 0.4, 0)
        StatusLabel.Position = UDim2.new(0, 0, 0.6, 0)
        StatusLabel.BackgroundTransparency = 1
        StatusLabel.Text = "TARGET FOUND"
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        StatusLabel.TextStrokeTransparency = 0
        StatusLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        StatusLabel.Font = Enum.Font.SourceSans
        StatusLabel.TextScaled = true
        StatusLabel.Parent = Frame

        State.espObjects[targetModel] = Billboard
        
        local connection
        connection = targetModel.AncestryChanged:Connect(function()
            if not targetModel.Parent then
                if State.espObjects[targetModel] then
                    State.espObjects[targetModel] = nil
                end
                connection:Disconnect()
            end
        end)
    end)
    
    if not success then
        logMessage("Failed to create ESP for " .. tostring(targetModel), "WARN")
    end
end

local function sendWebhook(foundPets, jobId)
    if CONFIG.webhook == "" then
        logMessage("Webhook URL not configured", "WARN")
        return false
    end

    local petCounts = {}
    for _, pet in ipairs(foundPets) do
        if pet and pet ~= "" then
            petCounts[pet] = (petCounts[pet] or 0) + 1
        end
    end

    local formattedPets = {}
    for petName, count in pairs(petCounts) do
        table.insert(formattedPets, count > 1 and string.format("%s (x%d)", petName, count) or petName)
    end

    if #formattedPets == 0 then
        logMessage("No valid pets to send in webhook", "WARN")
        return false
    end

    local embed = {
        ["title"] = "🎯 Pet Detection Alert",
        ["description"] = "Target pet(s) found in server!",
        ["fields"] = {
            {
                ["name"] = "👤 Player",
                ["value"] = LocalPlayer.Name,
                ["inline"] = true
            },
            {
                ["name"] = "🐾 Pet(s) Found",
                ["value"] = table.concat(formattedPets, "\n"),
                ["inline"] = true
            },
            {
                ["name"] = "🆔 Server Job ID",
                ["value"] = "```" .. jobId .. "```",
                ["inline"] = false
            },
            {
                ["name"] = "🕐 Detection Time",
                ["value"] = os.date("%Y-%m-%d %H:%M:%S UTC"),
                ["inline"] = true
            },
            {
                ["name"] = "📊 Servers Checked",
                ["value"] = tostring(State.hops + 1),
                ["inline"] = true
            }
        },
        ["color"] = 0x00FF00,
        ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
        ["footer"] = {
            ["text"] = "NotifyBot • 1.0 Version"
        }
    }

    local success, jsonData = pcall(function()
        return HttpService:JSONEncode({
            ["username"] = "NotifyBot",
            ["avatar_url"] = "https://i.postimg.cc/8PLg2H9S/file-00000000c9bc62308340df6809d63f45.png",
            ["content"] = "🚨 **TARGET PET DETECTED!**",
            ["embeds"] = {embed}
        })
    end)

    if not success then
        logMessage("Failed to encode webhook data: " .. tostring(jsonData), "ERROR")
        return false
    end

    local req = http_request or request or (syn and syn.request)
    if not req then
        logMessage("HTTP requests not supported by executor", "ERROR")
        return false
    end

    local webhookSuccess, response = pcall(function()
        return req({
            Url = CONFIG.webhook,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = jsonData
        })
    end)

    if webhookSuccess then
        logMessage("Webhook sent successfully", "SUCCESS")
        showNotification("NotifyBot", "Webhook sent successfully!", 3)
        return true
    else
        logMessage("Failed to send webhook: " .. tostring(response), "ERROR")
        return false
    end
end

local function isTargetPet(petName)
    if not petName or petName == "" then
        return false
    end
    
    local nameLower = string.lower(petName)
    for _, target in pairs(CONFIG.targetPets) do
        if target and target ~= "" then
            local targetLower = string.lower(target)
            if string.find(nameLower, targetLower) or string.find(targetLower, nameLower) then
                return true, target
            end
        end
    end
    return false
end

local function scanForPets()
    local found = {}
    local newDetections = 0
    
    local success = pcall(function()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name and obj.Name ~= "" and obj.Parent then
                local isTarget, matchedTarget = isTargetPet(obj.Name)
                if isTarget and not State.detectedPets[obj.Name] then
                    State.detectedPets[obj.Name] = true
                    createESP(obj, matchedTarget)
                    table.insert(found, obj.Name)
                    newDetections += 1
                    logMessage(string.format("New target pet detected: %s", obj.Name), "SUCCESS")
                end
            end
        end
    end)
    
    if not success then
        logMessage("Error during pet scanning", "ERROR")
    end
    
    if newDetections > 0 then
        State.stopHopping = true
        showNotification("NotifyBot", string.format("Found %d target pet(s)!", newDetections), 5)
    end
    
    return found
end

local function getServerList()
    local servers = {}
    local cursor = nil
    local attempts = 0
    local maxAttempts = 3
    
    while attempts < maxAttempts do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
            game.PlaceId
        )
        if cursor then
            url = url .. "&cursor=" .. cursor
        end
        
        local success, response = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)
        
        if success and response and response.data then
            for _, server in ipairs(response.data) do
                local playing = tonumber(server.playing) or 0
                local maxPlayers = tonumber(server.maxPlayers) or 1
                
                if playing < maxPlayers 
                   and server.id ~= game.JobId 
                   and not State.visitedJobIds[server.id] then
                    table.insert(servers, {
                        id = server.id,
                        playing = playing,
                        maxPlayers = maxPlayers
                    })
                end
            end
            
            cursor = response.nextPageCursor
            if not cursor then break end
        else
            attempts += 1
            logMessage(string.format("Failed to fetch servers (attempt %d/%d)", attempts, maxAttempts), "WARN")
            task.wait(1)
        end
    end
    
    table.sort(servers, function(a, b)
        return a.playing < b.playing
    end)
    
    return servers
end

function serverHop()
    if State.stopHopping or not State.isSearching or State.isHopping then 
        return 
    end
    
    State.isHopping = true
    logMessage("Searching for new server...", "INFO")
    safeWait(CONFIG.teleportDelay)
    
    State.hops += 1
    if State.hops >= CONFIG.maxHopsBeforeReset then
        State.visitedJobIds = {[game.JobId] = true}
        State.hops = 0
        logMessage("Reset visited servers list", "INFO")
    end
    
    local servers = getServerList()
    
    if #servers > 0 then
        local targetServer = servers[math.random(1, math.min(5, #servers))]
        State.visitedJobIds[targetServer.id] = true
        
        logMessage(string.format("Teleporting to server %s (%d/%d players)", 
                  targetServer.id, targetServer.playing, targetServer.maxPlayers), "INFO")
        
        State.teleportFails = 0
        
        local teleportSuccess = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer.id)
        end)
        
        if not teleportSuccess then
            logMessage("Failed to initiate teleport", "ERROR")
            State.isHopping = false
        end
    else
        logMessage("No suitable servers found, using random teleport", "WARN")
        
        local teleportSuccess = pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
        
        if not teleportSuccess then
            logMessage("Failed to initiate random teleport", "ERROR")
            State.isHopping = false
        end
    end
end

TeleportService.TeleportInitFailed:Connect(function(_, result)
    State.teleportFails += 1
    State.isHopping = false
    
    local errorMessages = {
        [Enum.TeleportResult.GameFull] = "Server is full",
        [Enum.TeleportResult.Unauthorized] = "Server is private/unauthorized",
        [Enum.TeleportResult.Flooded] = "Too many teleport requests",
        [Enum.TeleportResult.IsTeleporting] = "Already teleporting"
    }
    
    local message = errorMessages[result] or "Unknown teleport error: " .. tostring(result)
    logMessage(message, "ERROR")
    
    if State.teleportFails >= CONFIG.maxTeleportRetries then
        logMessage("Max teleport retries reached, forcing fresh start", "WARN")
        State.teleportFails = 0
        State.visitedJobIds = {}
        safeWait(2)
        
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    else
        safeWait(1)
        if State.isSearching then
            task.spawn(serverHop)
        end
    end
end)

workspace.DescendantAdded:Connect(function(obj)
    if not State.isSearching then return end
    
    task.spawn(function()
        task.wait(CONFIG.petDetectionDelay)
        
        if obj and obj.Parent and obj:IsA("Model") and obj.Name and obj.Name ~= "" then
            local isTarget, matchedTarget = isTargetPet(obj.Name)
            if isTarget and not State.detectedPets[obj.Name] then
                State.detectedPets[obj.Name] = true
                createESP(obj, matchedTarget)
                
                logMessage(string.format("Live detection: %s appeared!", obj.Name), "SUCCESS")
                State.stopHopping = true
                
                if not State.webhookSent then
                    State.webhookSent = true
                    task.spawn(function()
                        sendWebhook({obj.Name}, game.JobId)
                    end)
                end
            end
        end
    end)
end)

local function cleanup()
    State.isSearching = false
    
    for model, esp in pairs(State.espObjects) do
        if esp and esp.Parent then
            esp:Destroy()
        end
    end
    State.espObjects = {}
    
    logMessage("NotifyBot stopped and cleaned up", "INFO")
end

local function startPerformanceMonitor()
    task.spawn(function()
        while State.isSearching do
            safeWait(30)
            
            local memoryUsage = collectgarbage("count")
            if memoryUsage > 50000 then
                logMessage(string.format("High memory usage: %.2f MB", memoryUsage / 1024), "WARN")
                collectgarbage("collect")
            end
        end
    end)
end

local function main()
    logMessage("NotifyBot Enhanced v2.0 Started", "SUCCESS")
    
    if #CONFIG.targetPets == 0 then
        logMessage("No target pets configured! Please set getgenv().PetNames", "ERROR")
        return
    end
    
    logMessage(string.format("Searching for pets: %s", table.concat(CONFIG.targetPets, ", ")), "INFO")
    
    startPerformanceMonitor()
    
    safeWait(6)
    
    local initialPets = scanForPets()
    if #initialPets > 0 then
        logMessage(string.format("Found %d target pet(s) on initial scan!", #initialPets), "SUCCESS")
        
        if not State.webhookSent then
            State.webhookSent = true
            task.spawn(function()
                sendWebhook(initialPets, game.JobId)
            end)
        end
        
        showNotification("NotifyBot", "Target pets found in this server!", 10)
    else
        logMessage("No target pets found, starting server hopping...", "INFO")
        showNotification("NotifyBot", "Searching for pets...", 3)
        task.delay(CONFIG.teleportDelay, serverHop)
    end
    
    task.spawn(function()
        while State.isSearching and not State.stopHopping do
            safeWait(CONFIG.checkInterval)
            if tick() - State.lastCheck >= CONFIG.checkInterval then
                scanForPets()
                State.lastCheck = tick()
            end
        end
    end)
end

main()
