local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Wait for LocalPlayer to initialize
local LocalPlayer
repeat
    LocalPlayer = Players.LocalPlayer
    task.wait()
until LocalPlayer

--// User Configuration from loader
local webhooks = getgenv().webhooks or {}
local targetPets = getgenv().TargetPetNames or {}

-- Debug print
print("🔧 NotifyBot initialized with", #webhooks, "webhooks and", #targetPets, "target pets")

--// Visited Job Tracking
local visitedJobIds = {[game.JobId] = true}
local hops = 0
local maxHopsBeforeReset = 50

--// Teleport Fail Handling
local teleportFails = 0
local maxTeleportRetries = 3

--// Found Pet Cache
local detectedPets = {}
local webhookSent = false
local stopHopping = false

-- Error handling for teleport failures
TeleportService.TeleportInitFailed:Connect(function(_, result)
    teleportFails += 1
    if result == Enum.TeleportResult.GameFull then
        warn("⚠️ Game full. Retrying teleport...")
    elseif result == Enum.TeleportResult.Unauthorized then
        warn("❌ Unauthorized/private server. Blacklisting and retrying...")
        visitedJobIds[game.JobId] = true
    else
        warn("❌ Other teleport error:", result)
    end

    if teleportFails >= maxTeleportRetries then  
        warn("⚠️ Too many teleport fails. Forcing fresh server...")  
        teleportFails = 0  
        task.wait(1)  
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    else  
        task.wait(1)  
        pcall(serverHop)
    end
end)

--// ESP Function with error handling
local function addESP(targetModel)
    pcall(function()
        if not targetModel or not targetModel.Parent then return end
        if targetModel:FindFirstChild("PetESP") then return end
        
        local Billboard = Instance.new("BillboardGui")
        Billboard.Name = "PetESP"
        Billboard.Adornee = targetModel
        Billboard.Size = UDim2.new(0, 100, 0, 30)
        Billboard.StudsOffset = Vector3.new(0, 3, 0)
        Billboard.AlwaysOnTop = true
        Billboard.Parent = targetModel

        local Label = Instance.new("TextLabel")  
        Label.Size = UDim2.new(1, 0, 1, 0)  
        Label.BackgroundTransparency = 1  
        Label.Text = "🎯 Target Pet"  
        Label.TextColor3 = Color3.fromRGB(255, 0, 0)  
        Label.TextStrokeTransparency = 0.5  
        Label.Font = Enum.Font.SourceSansBold  
        Label.TextScaled = true  
        Label.Parent = Billboard
    end)
end

--// Enhanced Webhook Function with better error handling
local function sendWebhook(foundPets, jobId)
    if #webhooks == 0 then
        warn("⚠️ No webhooks configured, skipping notification.")
        return
    end

    local success, result = pcall(function()
        local petCounts = {}  
        for _, pet in ipairs(foundPets) do  
            if pet then  
                petCounts[pet] = (petCounts[pet] or 0) + 1  
            end  
        end  

        local formattedPets = {}  
        for petName, count in pairs(petCounts) do  
            table.insert(formattedPets, count > 1 and petName .. " x" .. count or petName)  
        end  

        local petListText = table.concat(formattedPets, "\n")  

        local embed = {  
            ["title"] = "🚨 Pet Alert",  
            ["description"] = "**A secret/target pet was found in a server!**\nCheck details below.\n\n🔗 [Join Our Official Server](https://discord.gg/5UGc3m7Nnc)",  
            ["color"] = 0xFF00FF,  
            ["fields"] = {  
                {  
                    ["name"] = "👤 Player",  
                    ["value"] = LocalPlayer.Name or "Unknown",  
                    ["inline"] = true  
                },  
                {  
                    ["name"] = "🚀 Pet(s) Detected",  
                    ["value"] = petListText,  
                    ["inline"] = true  
                },  
                {  
                    ["name"] = "🌐 Server JobId",  
                    ["value"] = "`" .. tostring(jobId) .. "`"  
                },  
                {  
                    ["name"] = "⏰ Detection Time",  
                    ["value"] = "<t:" .. os.time() .. ":F>"  
                },
                {
                    ["name"] = "🎮 Server Official",
                    ["value"] = "[Click here to join our Discord!](https://discord.gg/5UGc3m7Nnc)",
                    ["inline"] = false
                }
            },  
            ["footer"] = {  
                ["text"] = "NotifyBot - 1.2 Version"  
            }  
        }  

        local payload = {  
            username = "NotifyBot",  
            avatar_url = "https://i.postimg.cc/8PLg2H9S/file-00000000c9bc62308340df6809d63f45.png",  
            content = "🎯 **PET DETECTED!**",  
            embeds = { embed }  
        }  

        local jsonData = HttpService:JSONEncode(payload)  

        -- Send to all webhooks simultaneously
        local req = http_request or request or (syn and syn.request)  
        if req then  
            for i, webhook in ipairs(webhooks) do
                if webhook and webhook ~= "" then
                    spawn(function()
                        local webhookSuccess, webhookErr = pcall(function()  
                            req({  
                                Url = webhook,  
                                Method = "POST",  
                                Headers = { ["Content-Type"] = "application/json" },  
                                Body = jsonData  
                            })  
                        end)  
                        if webhookSuccess then  
                            print("✅ Webhook #" .. i .. " sent successfully.")  
                        else  
                            warn("❌ Failed to send webhook #" .. i .. ":", webhookErr)  
                        end
                    end)
                end
            end
        else  
            warn("❌ Executor doesn't support HTTP requests.")  
        end
    end)
    
    if not success then
        warn("❌ Error in sendWebhook function:", result)
    end
end

--// Pet Detection Function with improved error handling
local function checkForPets()
    local found = {}
    pcall(function()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj and obj:IsA("Model") and obj.Name then
                local nameLower = string.lower(obj.Name)
                for _, target in pairs(targetPets) do
                    if target and string.find(nameLower, string.lower(target)) and not obj:FindFirstChild("PetESP") then
                        addESP(obj)
                        table.insert(found, obj.Name)
                        stopHopping = true
                        break
                    end
                end
            end
        end
    end)
    return found
end

--// Server Hop Function with enhanced error handling
function serverHop()
    if stopHopping then return end
    
    local success, result = pcall(function()
        task.wait(1.5)

        local cursor = nil  
        local PlaceId, JobId = game.PlaceId, game.JobId  
        local tries = 0  

        hops += 1  
        if hops >= maxHopsBeforeReset then  
            visitedJobIds = {[JobId] = true}  
            hops = 0  
            print("♻️ Resetting visited JobIds.")  
        end  

        while tries < 3 do  
            local url = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"  
            if cursor then url = url .. "&cursor=" .. cursor end  

            local httpSuccess, response = pcall(function()  
                return HttpService:JSONDecode(game:HttpGet(url))  
            end)  

            if httpSuccess and response and response.data then  
                local servers = {}  
                for _, server in ipairs(response.data) do  
                    if tonumber(server.playing or 0) < tonumber(server.maxPlayers or 1)  
                        and server.id ~= JobId  
                        and not visitedJobIds[server.id] then  
                            table.insert(servers, server.id)  
                    end  
                end  

                if #servers > 0 then  
                    local picked = servers[math.random(1, #servers)]  
                    print("✅ Hopping to server:", picked)  
                    teleportFails = 0  
                    TeleportService:TeleportToPlaceInstance(PlaceId, picked)  
                    return  
                end  

                cursor = response.nextPageCursor  
                if not cursor then  
                    tries += 1  
                    cursor = nil  
                    task.wait(0.5)  
                end  
            else  
                warn("⚠️ Failed to fetch server list. Retrying...")  
                tries += 1  
                task.wait(0.5)  
            end  
        end  

        warn("❌ No valid servers found. Forcing random teleport...")  
        TeleportService:Teleport(PlaceId)
    end)
    
    if not success then
        warn("❌ Error in serverHop function:", result)
        task.wait(2)
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    end
end

--// Live Detection for Pets with error handling
workspace.DescendantAdded:Connect(function(obj)
    pcall(function()
        task.wait(0.25)
        if obj and obj:IsA("Model") and obj.Name then
            local nameLower = string.lower(obj.Name)
            for _, target in pairs(targetPets) do
                if target and string.find(nameLower, string.lower(target)) and not obj:FindFirstChild("PetESP") then
                    if not detectedPets[obj.Name] then
                        detectedPets[obj.Name] = true
                        addESP(obj)
                        print("🎯 New pet appeared:", obj.Name)
                        stopHopping = true
                        if not webhookSent then
                            sendWebhook({obj.Name}, game.JobId)
                            webhookSent = true
                        end
                    end
                    break
                end
            end
        end
    end)
end)

--// Start with error handling
pcall(function()
    task.wait(6)
    print("🔍 Starting pet detection...")
    local petsFound = checkForPets()
    if #petsFound > 0 then
        for _, name in ipairs(petsFound) do
            detectedPets[name] = true
        end
        if not webhookSent then
            print("🎯 Found pet(s):", table.concat(petsFound, ", "))
            sendWebhook(petsFound, game.JobId)
            webhookSent = true
        end
    else
        print("🔍 No target pets found. Hopping to next server...")
        task.delay(1.5, serverHop)
    end
end)