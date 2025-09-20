task.wait(1) -- ⏳ รอ 1 วินาทีก่อนเริ่มสคริปต์ทั้งหมด

-- ✅ โหลด config จาก GitHub ก่อนอื่น
pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/SDsfwqq/Auto-Mob/main/config.lua"))()
end)

pcall(function()
    local mobRemote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    if mobRemote then
        local target = mobRemote:FindFirstChild("MobDamageRemote")
        if target then
            target:Destroy()
            print("")
        end
    end
end)

if getgenv then
    if getgenv().__autofarm_loaded then return else getgenv().__autofarm_loaded = true end
end

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

-- ✅ ใช้ config จาก GitHub หรือใช้ค่า default
local config = getgenv().AutoFarmConfig or {}

local ATTACKS_PER_TARGET = config.ATTACKS_PER_TARGET or 10
local TELEPORT_DISTANCE_THRESHOLD = config.TELEPORT_DISTANCE_THRESHOLD or 12
local TARGET_RECHECK_DELAY = config.TARGET_RECHECK_DELAY or 1.25
local ATTACK_INTERVAL = config.ATTACK_INTERVAL or 0.15
local priorityMobs = config.priorityMobs or { "EliteKappa", "EliteKitsuneFox", "EliteWanyudo", "Kappa", "KiriFogGhost", "KitsuneFox", "Wanyudo" }
local mobNames = config.mobNames or { "EliteKappa", "EliteKitsuneFox", "EliteWanyudo", "Kappa", "KiriFogGhost", "KitsuneFox", "Wanyudo" }

-- ✅ ใช้ targetResources จาก config หรือค่า default
local targetResources = config.targetResources or {
    Bacon = 100,
    Meat = 100,
    Ashes = 100,
    Fossil = 100,
}

-- ✅ ใช้ teleportWorlds จาก config หรือค่า default
local teleportWorlds = config.teleportWorlds or {
    ["Undercity"] = 4601778915,
    ["Origins"] = 3475397644,
    ["Grassland"] = 3475419198,
    ["Jungle"] = 3475422608,
    ["Volcano"] = 3487210751,
    ["Tundra"] = 3623549100,
    ["Ocean"] = 3737848045,
    ["Desert"] = 3752680052,
    ["Fantasy"] = 4174118306,
    ["Wasteland"] = 4728805070,
    ["Prehistoric"] = 125804922932357,
}

local WORLD_FARM = 125804922932357
local WORLD_ORIGINS = 3475397644
local OTHER_WORLDS = { 4601778915, 3475419198, 3475422608, 3487210751, 3623549100, 3737848045, 3752680052, 4174118306, 4728805070 }

local lastTarget, lastAttackTime, lastTargetSwitchTime = nil, 0, 0
local autoEnabled, teleported = false, false
local farmLoop = nil

-- ======================== CORE FUNCTIONS ========================

local function getMountedDragon()
    local char = Player.Character or Player.CharacterAdded:Wait()
    local dragons = char:FindFirstChild("Dragons")
    if not dragons then return end
    for _, d in ipairs(dragons:GetChildren()) do
        local seat = d:FindFirstChildWhichIsA("VehicleSeat") or d:FindFirstChild("Seat")
        if seat and seat.Occupant == char:FindFirstChildOfClass("Humanoid") then return d end
    end
end

local function teleportTo(target)
    local pos = target:IsA("BasePart") and target.Position
        or (target.PrimaryPart and target.PrimaryPart.Position)
        or (target:FindFirstChild("HumanoidRootPart") and target.HumanoidRootPart.Position)
        or (target:FindFirstChildWhichIsA("BasePart") and target:FindFirstChildWhichIsA("BasePart").Position)

    if Player.Character and Player.Character.PrimaryPart and typeof(pos) == "Vector3" then
        local dist = (Player.Character.PrimaryPart.Position - pos).Magnitude
        if dist > TELEPORT_DISTANCE_THRESHOLD then
            local angle = math.rad(math.random(0, 360))
            local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 15
            local safePos = pos + offset + Vector3.new(0, 3, 0)
            pcall(function()
                Player.Character:SetPrimaryPartCFrame(CFrame.new(safePos))
            end)
        end
    end
end

local function hyperAttack(target, dragon)
    local remote = dragon:FindFirstChild("Remotes") and dragon.Remotes:FindFirstChild("PlaySoundRemote")
    if not remote then return end
    for i = 1, ATTACKS_PER_TARGET do
        if not target or not target:FindFirstChild("Health") or target.Health.Value <= 0 then break end
        remote:FireServer("Breath", "Mobs", target)
        task.wait(ATTACK_INTERVAL)
    end
end

local function performBiteAndBreath()
    local dragon = getMountedDragon()
    if not dragon then return end
    local breath = dragon:FindFirstChild("Remotes") and dragon.Remotes:FindFirstChild("BreathFireRemote")
    if breath then breath:FireServer(true) end
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
end

local function findTarget()
    local global = workspace:FindFirstChild("Interactions")
    global = global and global:FindFirstChild("Nodes")
    global = global and global:FindFirstChild("Mobs")
    global = global and global:FindFirstChild("ActiveMobs")
    global = global and global:FindFirstChild("Global")
    if global then
        for _, name in ipairs(priorityMobs) do
            local mob = global:FindFirstChild(name)
            if mob and mob:FindFirstChild("Health") and mob.Health.Value > 0 then return mob end
        end
    end
    local folder = workspace:FindFirstChild("MobFolder")
    if folder then
        for _, wrapper in ipairs(folder:GetChildren()) do
            for _, name in ipairs(mobNames) do
                local mob = wrapper:FindFirstChild(name)
                if mob and mob:FindFirstChild("Health") and mob.Health.Value > 0 then return mob end
            end
        end
    end
end

-- 🔍 ดึงจำนวนผู้เล่นในเซิร์ฟเวอร์ของแต่ละโลก
local function getServerWithFewPlayers(placeId)
    local request = (syn and syn.request) or request or http_request
    if not request then
        warn("❌ Executor ของคุณไม่รองรับ HTTP request")
        return nil
    end

    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
    local response = request({ Url = url, Method = "GET" })

    if response and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        for _, server in ipairs(data.data) do
            if server.playing <= 1 then
                return placeId
            end
        end
    end

    return nil
end

-- 🎲 วาร์ปไปโลกสุ่มจาก OTHER_WORLDS
local function teleportToRandomWorld()
    local randomWorld = OTHER_WORLDS[math.random(1, #OTHER_WORLDS)]
    print("🌍 วาร์ปไปโลกสุ่ม:", randomWorld)
    task.wait(3)
    ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(randomWorld, {})
end

-- 🎲 วาร์ปไปโลกที่ว่างจริงจาก OTHER_WORLDS
local function teleportToNextEmptyWorld()
    for _, world in ipairs(OTHER_WORLDS) do
        local found = getServerWithFewPlayers(world)
        if found then
            print("🌍 วาร์ปไปโลกสุ่มที่ว่างจริง:", found)
            task.wait(3)
            ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(found, {})
            return true
        end
    end
    
    -- ถ้าไม่เจอโลกว่าง ให้สุ่มไปโลกใดโลกหนึ่ง
    print("❌ ไม่มีโลกไหนในรายการที่ว่างเลย - สุ่มไปโลกใดโลกหนึ่ง")
    teleportToRandomWorld()
    return true
end

local function checkAndHandlePlayers()
    local currentPlace = game.PlaceId

    if currentPlace == WORLD_FARM then
        if #Players:GetPlayers() > 1 then
            print("👥 โลกฟาร์มมีผู้เล่นอื่น → ไปหาที่ว่างในโลกสุ่ม...")
            teleportToNextEmptyWorld()
            return true
        else
            print("✅ โลกฟาร์มมีแค่เรา → เริ่มฟาร์มต่อได้เลย")
            return false -- อยู่โลกฟาร์มคนเดียว ไม่ต้องวาร์ป
        end
    elseif currentPlace == WORLD_ORIGINS then
        if #Players:GetPlayers() > 1 then
            print("🏪 โลก Origins มีผู้เล่นอื่น → ไปโลกสุ่ม...")
            teleportToRandomWorld()
            return true
        end
    elseif table.find(OTHER_WORLDS, currentPlace) then
        if #Players:GetPlayers() > 1 then
            print("⛔ โลกสุ่มนี้มีคนอื่น → วาร์ปไปโลกสุ่มอื่น...")
            teleportToNextEmptyWorld()
            return true
        else
            print("✅ โลกสุ่มว่าง → กลับไปโลกฟาร์ม")
            task.wait(3)
            ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(WORLD_FARM, {})
            return true
        end
    end

    return false
end

-- ======================== ENHANCED GUI CREATION ========================

-- ลบ GUI เก่าก่อน
pcall(function()
    if game.CoreGui:FindFirstChild("DragonFarmUI") then
        game.CoreGui:FindFirstChild("DragonFarmUI"):Destroy()
    end
end)

local gui = Instance.new("ScreenGui", game.CoreGui)
gui.Name = "DragonFarmUI"
gui.ResetOnSpawn = false

-- 🎨 Enhanced Main Container - ย่อได้
local mainContainer = Instance.new("Frame", gui)
mainContainer.Size = UDim2.new(0, 450, 0, 650)
mainContainer.Position = UDim2.new(0.5, -225, 0.5, -325)
mainContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mainContainer.BorderSizePixel = 0
mainContainer.ClipsDescendants = false

-- เพิ่ม Corner Radius และ Shadow
local corner = Instance.new("UICorner", mainContainer)
corner.CornerRadius = UDim.new(0, 15)

-- Enhanced Shadow Effect
local shadow = Instance.new("Frame", gui)
shadow.Size = mainContainer.Size + UDim2.new(0, 20, 0, 20)
shadow.Position = mainContainer.Position - UDim2.new(0, 10, 0, 10)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.6
shadow.ZIndex = -1
local shadowCorner = Instance.new("UICorner", shadow)
shadowCorner.CornerRadius = UDim.new(0, 25)

-- 🎯 Enhanced Header with Drag Handle
local header = Instance.new("Frame", mainContainer)
header.Size = UDim2.new(1, 0, 0, 65)
header.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
local headerCorner = Instance.new("UICorner", header)
headerCorner.CornerRadius = UDim.new(0, 15)

-- Drag Handle Visual
local dragHandle = Instance.new("Frame", header)
dragHandle.Size = UDim2.new(1, -40, 0, 4)
dragHandle.Position = UDim2.new(0, 20, 0, 5)
dragHandle.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
dragHandle.BorderSizePixel = 0
local handleCorner = Instance.new("UICorner", dragHandle)
handleCorner.CornerRadius = UDim.new(0, 2)

local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(1, -100, 1, -10)
title.Position = UDim2.new(0, 15, 0, 15)
title.Text = "NEXON HUB / MOB"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(120, 220, 255)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize Button
local minimizeBtn = Instance.new("TextButton", header)
minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
minimizeBtn.Position = UDim2.new(1, -40, 0, 17.5)
minimizeBtn.Text = "−"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 20
minimizeBtn.TextColor3 = Color3.new(1, 1, 1)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
local minCorner = Instance.new("UICorner", minimizeBtn)
minCorner.CornerRadius = UDim.new(0, 6)

-- Content Container (สำหรับย่อขยาย)
local contentContainer = Instance.new("Frame", mainContainer)
contentContainer.Size = UDim2.new(1, 0, 1, -65)
contentContainer.Position = UDim2.new(0, 0, 0, 65)
contentContainer.BackgroundTransparency = 1

-- 🎮 Enhanced Controls Section
local controlsFrame = Instance.new("Frame", contentContainer)
controlsFrame.Size = UDim2.new(1, -20, 0, 90)
controlsFrame.Position = UDim2.new(0, 10, 0, 10)
controlsFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
local controlsCorner = Instance.new("UICorner", controlsFrame)
controlsCorner.CornerRadius = UDim.new(0, 10)

local controlsTitle = Instance.new("TextLabel", controlsFrame)
controlsTitle.Size = UDim2.new(1, -15, 0, 30)
controlsTitle.Position = UDim2.new(0, 10, 0, 5)
controlsTitle.Text = "⚡ Controls"
controlsTitle.Font = Enum.Font.GothamBold
controlsTitle.TextSize = 16
controlsTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
controlsTitle.BackgroundTransparency = 1
controlsTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Enhanced Start/Stop Button
local toggleButton = Instance.new("TextButton", controlsFrame)
toggleButton.Size = UDim2.new(0, 140, 0, 45)
toggleButton.Position = UDim2.new(0, 10, 0, 35)
toggleButton.Text = "START FARM"
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.TextColor3 = Color3.new(1, 1, 1)
toggleButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
local toggleCorner = Instance.new("UICorner", toggleButton)
toggleCorner.CornerRadius = UDim.new(0, 8)

-- Enhanced Status Label
local statusLabel = Instance.new("TextLabel", controlsFrame)
statusLabel.Size = UDim2.new(1, -160, 0, 45)
statusLabel.Position = UDim2.new(0, 160, 0, 35)
statusLabel.Text = "Stopped"
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 16
statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment = Enum.TextXAlignment.Left


local currencyFrame = Instance.new("Frame", contentContainer)
currencyFrame.Size = UDim2.new(1, -20, 0, 70)
currencyFrame.Position = UDim2.new(0, 10, 0, 110)
currencyFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
local currencyCorner = Instance.new("UICorner", currencyFrame)
currencyCorner.CornerRadius = UDim.new(0, 10)

local currencyTitle = Instance.new("TextLabel", currencyFrame)
currencyTitle.Size = UDim2.new(0.5, 0, 0, 30)
currencyTitle.Position = UDim2.new(0, 10, 0, 5)
currencyTitle.Text = "Currency"
currencyTitle.Font = Enum.Font.GothamBold
currencyTitle.TextSize = 16
currencyTitle.TextColor3 = Color3.fromRGB(255, 220, 100)
currencyTitle.BackgroundTransparency = 1
currencyTitle.TextXAlignment = Enum.TextXAlignment.Left

local coinLabel = Instance.new("TextLabel", currencyFrame)
coinLabel.Size = UDim2.new(1, -20, 0, 35)
coinLabel.Position = UDim2.new(0, 10, 0, 30)
coinLabel.Text = "Coins: Loading..."
coinLabel.Font = Enum.Font.GothamMedium
coinLabel.TextSize = 18
coinLabel.TextColor3 = Color3.fromRGB(255, 255, 150)
coinLabel.BackgroundTransparency = 1
coinLabel.TextXAlignment = Enum.TextXAlignment.Left


local resourcesFrame = Instance.new("Frame", contentContainer)
resourcesFrame.Size = UDim2.new(1, -20, 0, 200)
resourcesFrame.Position = UDim2.new(0, 10, 0, 190)
resourcesFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
local resourcesCorner = Instance.new("UICorner", resourcesFrame)
resourcesCorner.CornerRadius = UDim.new(0, 10)

local resourcesTitle = Instance.new("TextLabel", resourcesFrame)
resourcesTitle.Size = UDim2.new(1, -15, 0, 30)
resourcesTitle.Position = UDim2.new(0, 10, 0, 5)
resourcesTitle.Text = "Resources & Goals"
resourcesTitle.Font = Enum.Font.GothamBold
resourcesTitle.TextSize = 16
resourcesTitle.TextColor3 = Color3.fromRGB(100, 255, 150)
resourcesTitle.BackgroundTransparency = 1
resourcesTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Enhanced Resource Boxes
local resourceBoxes = {}
local resourceIcons = { Bacon = "🥓", Meat = "🍖", Ashes = "🧱", Fossil = "🦴" }

local yPos = 40
for name, goal in pairs(targetResources) do
    -- Enhanced Resource Display
    local resourceBox = Instance.new("Frame", resourcesFrame)
    resourceBox.Size = UDim2.new(0.6, -5, 0, 35)
    resourceBox.Position = UDim2.new(0, 10, 0, yPos)
    resourceBox.BackgroundColor3 = Color3.fromRGB(45, 45, 70)
    local boxCorner = Instance.new("UICorner", resourceBox)
    boxCorner.CornerRadius = UDim.new(0, 6)

    local resourceLabel = Instance.new("TextLabel", resourceBox)
    resourceLabel.Size = UDim2.new(1, -15, 1, 0)
    resourceLabel.Position = UDim2.new(0, 10, 0, 0)
    resourceLabel.Text = (resourceIcons[name] or "📦") .. " " .. name .. ": Loading..."
    resourceLabel.Font = Enum.Font.GothamMedium
    resourceLabel.TextSize = 14
    resourceLabel.TextColor3 = Color3.new(1, 1, 1)
    resourceLabel.BackgroundTransparency = 1
    resourceLabel.TextXAlignment = Enum.TextXAlignment.Left

    resourceBoxes[name] = resourceLabel

  
    local goalInput = Instance.new("TextBox", resourcesFrame)
    goalInput.Size = UDim2.new(0.35, -5, 0, 35)
    goalInput.Position = UDim2.new(0.65, 0, 0, yPos)
    goalInput.Text = tostring(goal)
    goalInput.PlaceholderText = "Goal Amount"
    goalInput.Font = Enum.Font.GothamMedium
    goalInput.TextSize = 14
    goalInput.TextColor3 = Color3.new(1, 1, 1)
    goalInput.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
    local inputCorner = Instance.new("UICorner", goalInput)
    inputCorner.CornerRadius = UDim.new(0, 6)

    goalInput.FocusLost:Connect(function()
        local value = tonumber(goalInput.Text)
        if value and value >= 0 then
            targetResources[name] = value
        else
            goalInput.Text = tostring(targetResources[name])
        end
    end)

    yPos = yPos + 40
end

-- 🌍 Enhanced World Teleport Section
local teleportFrame = Instance.new("Frame", contentContainer)
teleportFrame.Size = UDim2.new(1, -20, 0, 120)
teleportFrame.Position = UDim2.new(0, 10, 0, 400)
teleportFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
local teleportCorner = Instance.new("UICorner", teleportFrame)
teleportCorner.CornerRadius = UDim.new(0, 10)

local teleportTitle = Instance.new("TextLabel", teleportFrame)
teleportTitle.Size = UDim2.new(1, -15, 0, 30)
teleportTitle.Position = UDim2.new(0, 10, 0, 5)
teleportTitle.Text = "World Teleport"
teleportTitle.Font = Enum.Font.GothamBold
teleportTitle.TextSize = 16
teleportTitle.TextColor3 = Color3.fromRGB(150, 150, 255)
teleportTitle.BackgroundTransparency = 1
teleportTitle.TextXAlignment = Enum.TextXAlignment.Left

-- Enhanced Dropdown Button
local dropdownButton = Instance.new("TextButton", teleportFrame)
dropdownButton.Size = UDim2.new(1, -20, 0, 40)
dropdownButton.Position = UDim2.new(0, 10, 0, 40)
dropdownButton.Text = "Select World ▼"
dropdownButton.Font = Enum.Font.GothamMedium
dropdownButton.TextSize = 15
dropdownButton.TextColor3 = Color3.new(1, 1, 1)
dropdownButton.BackgroundColor3 = Color3.fromRGB(60, 60, 100)
local dropdownCorner = Instance.new("UICorner", dropdownButton)
dropdownCorner.CornerRadius = UDim.new(0, 8)

-- Enhanced Dropdown Menu
local dropdownMenu = Instance.new("Frame", gui)
dropdownMenu.Size = UDim2.new(0, 430, 0, 220)
dropdownMenu.Position = UDim2.new(0.5, -215, 0.5, 50)
dropdownMenu.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
dropdownMenu.Visible = false
local menuCorner = Instance.new("UICorner", dropdownMenu)
menuCorner.CornerRadius = UDim.new(0, 12)

local scrollFrame = Instance.new("ScrollingFrame", dropdownMenu)
scrollFrame.Size = UDim2.new(1, -10, 1, -10)
scrollFrame.Position = UDim2.new(0, 5, 0, 5)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 8
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 180)

local listLayout = Instance.new("UIListLayout", scrollFrame)
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.Padding = UDim.new(0, 3)

-- สร้างปุ่มโลกที่สวยงาม
for worldName, placeId in pairs(teleportWorlds) do
    local worldButton = Instance.new("TextButton", scrollFrame)
    worldButton.Size = UDim2.new(1, -15, 0, 35)
    worldButton.Text = "" .. worldName
    worldButton.Font = Enum.Font.GothamMedium
    worldButton.TextSize = 14
    worldButton.TextColor3 = Color3.new(1, 1, 1)
    worldButton.BackgroundColor3 = Color3.fromRGB(70, 70, 110)
    worldButton.TextXAlignment = Enum.TextXAlignment.Left
    
    local worldCorner = Instance.new("UICorner", worldButton)
    worldCorner.CornerRadius = UDim.new(0, 6)

    -- Enhanced Hover Effects with Tween
    worldButton.MouseEnter:Connect(function()
        local tween = TweenService:Create(worldButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(90, 90, 140),
            TextColor3 = Color3.fromRGB(200, 200, 255)
        })
        tween:Play()
    end)
    
    worldButton.MouseLeave:Connect(function()
        local tween = TweenService:Create(worldButton, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(70, 70, 110),
            TextColor3 = Color3.new(1, 1, 1)
        })
        tween:Play()
    end)

    worldButton.MouseButton1Click:Connect(function()
        dropdownMenu.Visible = false
        dropdownButton.Text = "Teleporting to " .. worldName .. "..."
        ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(placeId, {})
        task.wait(2)
        dropdownButton.Text = "Select World ▼"
    end)
end

-- อัปเดตขนาด ScrollFrame
task.defer(function()
    local totalHeight = 0
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            totalHeight = totalHeight + child.Size.Y.Offset + listLayout.Padding.Offset
        end
    end
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end)

-- ======================== ENHANCED DRAGGING SYSTEM ========================

local function makeEnhancedDraggable(frame)
    local dragging = false
    local dragInput, mousePos, framePos
    local dragConnection
    
    -- ใช้ header ทั้งหมดสำหรับการลาก
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mousePos = input.Position
            framePos = frame.Position
            
            -- เพิ่มเอฟเฟกต์เมื่อเริ่มลาก
            local tween = TweenService:Create(frame, TweenInfo.new(0.1), {
                Size = frame.Size + UDim2.new(0, 5, 0, 5)
            })
            tween:Play()
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    -- คืนขนาดเดิม
                    local tween2 = TweenService:Create(frame, TweenInfo.new(0.1), {
                        Size = frame.Size - UDim2.new(0, 5, 0, 5)
                    })
                    tween2:Play()
                end
            end)
        end
    end)
    
    header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            local newPos = UDim2.new(
                framePos.X.Scale, 
                framePos.X.Offset + delta.X, 
                framePos.Y.Scale, 
                framePos.Y.Offset + delta.Y
            )
            
            -- จำกัดไม่ให้ลากออกนอกหน้าจอ
            local screenSize = workspace.CurrentCamera.ViewportSize
            local frameSize = frame.AbsoluteSize
            
            if newPos.X.Offset < 0 then
                newPos = UDim2.new(0, 0, newPos.Y.Scale, newPos.Y.Offset)
            elseif newPos.X.Offset + frameSize.X > screenSize.X then
                newPos = UDim2.new(0, screenSize.X - frameSize.X, newPos.Y.Scale, newPos.Y.Offset)
            end
            
            if newPos.Y.Offset < 0 then
                newPos = UDim2.new(newPos.X.Scale, newPos.X.Offset, 0, 0)
            elseif newPos.Y.Offset + frameSize.Y > screenSize.Y then
                newPos = UDim2.new(newPos.X.Scale, newPos.X.Offset, 0, screenSize.Y - frameSize.Y)
            end
            
            frame.Position = newPos
            shadow.Position = newPos - UDim2.new(0, 10, 0, 10)
        end
    end)
end


local isMinimized = false
local originalSize = mainContainer.Size

local function toggleMinimize()
    if isMinimized then
        -- ขยาย
        isMinimized = false
        minimizeBtn.Text = "−"
        
        local expandTween = TweenService:Create(mainContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = originalSize
        })
        local shadowTween = TweenService:Create(shadow, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = originalSize + UDim2.new(0, 20, 0, 20)
        })
        
        expandTween:Play()
        shadowTween:Play()
        
        -- แสดง content
        contentContainer.Visible = true
        local contentTween = TweenService:Create(contentContainer, TweenInfo.new(0.2), {
            BackgroundTransparency = 0
        })
        contentTween:Play()
        
    else
        -- ย่อ
        isMinimized = true
        minimizeBtn.Text = "+"
        
        -- ซ่อน content ก่อน
        local hideTween = TweenService:Create(contentContainer, TweenInfo.new(0.1), {
            BackgroundTransparency = 1
        })
        hideTween:Play()
        
        hideTween.Completed:Connect(function()
            contentContainer.Visible = false
        end)
        
        -- ย่อขนาด
        local minimizeTween = TweenService:Create(mainContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, 450, 0, 65)
        })
        local shadowMinTween = TweenService:Create(shadow, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, 470, 0, 85)
        })
        
        minimizeTween:Play()
        shadowMinTween:Play()
    end
end

minimizeBtn.MouseButton1Click:Connect(toggleMinimize)


minimizeBtn.MouseEnter:Connect(function()
    local tween = TweenService:Create(minimizeBtn, TweenInfo.new(0.2), {
        BackgroundColor3 = Color3.fromRGB(80, 80, 110),
        TextColor3 = Color3.fromRGB(255, 255, 255)
    })
    tween:Play()
end)

minimizeBtn.MouseLeave:Connect(function()
    local tween = TweenService:Create(minimizeBtn, TweenInfo.new(0.2), {
        BackgroundColor3 = Color3.fromRGB(60, 60, 90),
        TextColor3 = Color3.new(1, 1, 1)
    })
    tween:Play()
end)


makeEnhancedDraggable(mainContainer)


toggleButton.MouseEnter:Connect(function()
    local currentColor = toggleButton.BackgroundColor3
    local hoverColor = Color3.new(
        math.min(currentColor.R + 0.1, 1),
        math.min(currentColor.G + 0.1, 1),
        math.min(currentColor.B + 0.1, 1)
    )
    local tween = TweenService:Create(toggleButton, TweenInfo.new(0.2), {
        BackgroundColor3 = hoverColor,
        Size = UDim2.new(0, 145, 0, 47)
    })
    tween:Play()
end)

toggleButton.MouseLeave:Connect(function()
    local originalColor = autoEnabled and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(50, 180, 50)
    local tween = TweenService:Create(toggleButton, TweenInfo.new(0.2), {
        BackgroundColor3 = originalColor,
        Size = UDim2.new(0, 140, 0, 45)
    })
    tween:Play()
end)

-- เพิ่มเอฟเฟกต์สำหรับ dropdown button
dropdownButton.MouseEnter:Connect(function()
    local tween = TweenService:Create(dropdownButton, TweenInfo.new(0.2), {
        BackgroundColor3 = Color3.fromRGB(80, 80, 120),
        Size = UDim2.new(1, -18, 0, 42)
    })
    tween:Play()
end)

dropdownButton.MouseLeave:Connect(function()
    local tween = TweenService:Create(dropdownButton, TweenInfo.new(0.2), {
        BackgroundColor3 = Color3.fromRGB(60, 60, 100),
        Size = UDim2.new(1, -20, 0, 40)
    })
    tween:Play()
end)


dropdownButton.MouseButton1Click:Connect(function()
    if dropdownMenu.Visible then
        -- ปิด dropdown
        local tween = TweenService:Create(dropdownMenu, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, 430, 0, 0)
        })
        tween:Play()
        tween.Completed:Connect(function()
            dropdownMenu.Visible = false
            dropdownMenu.Size = UDim2.new(0, 430, 0, 220)
        end)
    else
        -- เปิด dropdown
        dropdownMenu.Visible = true
        dropdownMenu.Size = UDim2.new(0, 430, 0, 0)
        local tween = TweenService:Create(dropdownMenu, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, 430, 0, 220)
        })
        tween:Play()
    end
end)

-- ปิด dropdown เมื่อคลิกนอกพื้นที่
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if dropdownMenu.Visible then
            local mousePos = UserInputService:GetMouseLocation()
            local guiPos = dropdownMenu.AbsolutePosition
            local guiSize = dropdownMenu.AbsoluteSize
            
            if mousePos.X < guiPos.X or mousePos.X > guiPos.X + guiSize.X or
               mousePos.Y < guiPos.Y or mousePos.Y > guiPos.Y + guiSize.Y then
                local tween = TweenService:Create(dropdownMenu, TweenInfo.new(0.2), {
                    Size = UDim2.new(0, 430, 0, 0)
                })
                tween:Play()
                tween.Completed:Connect(function()
                    dropdownMenu.Visible = false
                    dropdownMenu.Size = UDim2.new(0, 430, 0, 220)
                end)
            end
        end
    end
end)



local function startFarm()
    if farmLoop then return end
    farmLoop = RunService.Heartbeat:Connect(function()
        if not autoEnabled then return end
        if game.PlaceId ~= WORLD_FARM then return end
        local now = tick()
        local dragon = getMountedDragon()
        if not dragon then return end

        if now - lastTargetSwitchTime > TARGET_RECHECK_DELAY or not lastTarget or (lastTarget:FindFirstChild("Health") and lastTarget.Health.Value <= 0) then
            lastTarget = findTarget()
            lastTargetSwitchTime = now
        end

        if lastTarget then
            teleportTo(lastTarget)
            if now - lastAttackTime > ATTACK_INTERVAL * ATTACKS_PER_TARGET then
                hyperAttack(lastTarget, dragon)
                performBiteAndBreath()
                lastAttackTime = now
            end
        end
    end)
end

-- Enhanced Toggle Button Logic
toggleButton.MouseButton1Click:Connect(function()
    if autoEnabled then
        if farmLoop then farmLoop:Disconnect() farmLoop = nil end
        autoEnabled = false
        lastTarget = nil
        toggleButton.Text = "🚀 START FARM"
        toggleButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        statusLabel.Text = "🔴 Stopped"
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        autoEnabled = true
        toggleButton.Text = "STOP FARM"
        toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        statusLabel.Text = "Running"
        statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        startFarm()
    end
end)

-- เริ่มต้นด้วยการฟาร์ม
autoEnabled = true
toggleButton.Text = "STOP FARM"
toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
statusLabel.Text = "Running"
statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
startFarm()



task.spawn(function()
    task.wait(5)

    -- ✅ ถ้าอยู่ในโลกฟาร์ม และมีแค่เรา → เริ่มฟาร์มทันที
    if game.PlaceId == WORLD_FARM and #Players:GetPlayers() == 1 then
        print("✅ เริ่มในโลกฟาร์ม และอยู่คนเดียว → เริ่มฟาร์มได้เลย")
        return
    end

    -- ✅ ถ้าอยู่โลกฟาร์มแต่มีหลายคน หรืออยู่นอกโลกที่กำหนด
    if game.PlaceId == WORLD_FARM or not table.find(OTHER_WORLDS, game.PlaceId) then
        print("เริ่มต้น: ไปโลกสุ่มก่อน...")
        teleportToRandomWorld()
    end
end)


task.spawn(function()
    while true do
        local blocked = checkAndHandlePlayers()

        if game.PlaceId == WORLD_FARM and not blocked then
            if _G.AutoFarm then
                local args = { [1] = getrenv()._G.Settings.Main.MobAura }
                task.wait(3)
                ReplicatedStorage.Remotes.Damage:FireServer(unpack(args))
            end
        end

        wait(1)
    end
end)


task.spawn(function()
    while true do
        task.wait(60)
        -- กดเมาส์ขวาลงเพื่อหมุนกล้อง
        VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, nil, 0)
        -- หมุนกล้องขวาเล็กน้อย
        for i = 1, 10 do
            VirtualInputManager:SendMouseMoveEvent(2, 0, 0, false)
            task.wait(0.01)
        end
        -- ปล่อยเมาส์ขวา
        VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, nil, 0)
    end
end)


task.spawn(function()
    while true do
        local data = Player:FindFirstChild("Data")
        local res = data and data:FindFirstChild("Resources")
        local cur = data and data:FindFirstChild("Currency")

        -- อัปเดต Currency Display
        if cur and cur:FindFirstChild("Coins") then
            local coins = cur.Coins.Value
            coinLabel.Text = string.format("💎 Coins: %s", 
                coins >= 1000000 and string.format("%.1fM", coins/1000000) or
                coins >= 1000 and string.format("%.1fK", coins/1000) or
                tostring(coins)
            )
        end


        local reached = true
        for name, goal in pairs(targetResources) do
            local val = (res and res:FindFirstChild(name) and res[name].Value) or 0
            local icon = resourceIcons[name] or "📦"
            local color = val >= goal and Color3.fromRGB(100, 255, 100) or Color3.new(1, 1, 1)
            local percentage = goal > 0 and math.floor((val / goal) * 100) or 0
            
            resourceBoxes[name].Text = string.format("%s %s: %d/%d (%d%%)", icon, name, val, goal, percentage)
            resourceBoxes[name].TextColor3 = color
            
            if val < goal then reached = false end
        end

        if reached and not teleported and game.PlaceId == WORLD_FARM then
            teleported = true
            statusLabel.Text = "🟡 Going to sell..."
            statusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
            ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(WORLD_ORIGINS, {})
        end


        if game.PlaceId == WORLD_ORIGINS then
            statusLabel.Text = "💰 Selling items..."
            statusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
            
            -- ขายทุกอย่าง
            for name, _ in pairs(targetResources) do
                local r = res and res:FindFirstChild(name)
                if r and r.Value > 0 then
                    ReplicatedStorage.Remotes.SellItemRemote:FireServer({ ItemName = name, Amount = r.Value })
                    task.wait(0.2)
                end
            end
            
            task.wait(2)
            statusLabel.Text = "🔄 Returning to farm..."
            ReplicatedStorage.Remotes.WorldTeleportRemote:InvokeServer(WORLD_FARM, {})
            teleported = false
            
            task.wait(5)
            if autoEnabled then
                statusLabel.Text = "🟢 Running"
                statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            end
        end

        task.wait(0.5)
    end
end)


if config.enablePerformanceOptimization ~= false then
    task.spawn(function()
        local ws = workspace

        print("⚡ Applying performance optimizations...")
        
        for _, obj in ipairs(ws:GetDescendants()) do
            pcall(function()
                if obj:IsA("BasePart") then
                    obj.Material = Enum.Material.SmoothPlastic
                    obj.Reflectance = 0
                    obj.CastShadow = false
                    if config.hardcoreBoost then
                        obj.Color = Color3.new(0, 0, 0)
                    end
                elseif obj:IsA("Decal") or obj:IsA("Texture") then
                    obj.Transparency = 1
                elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                    obj.Enabled = false
                elseif obj:IsA("Light") then
                    obj.Enabled = false
                end
            end)
        end

        -- ปรับแต่ง Lighting
        pcall(function()
            for _, v in ipairs(game.Lighting:GetChildren()) do
                if not v:IsA("Sky") then v:Destroy() end
            end

            game.Lighting.GlobalShadows = false
            game.Lighting.FogEnd = 1e9
            game.Lighting.Brightness = 0
            game.Lighting.ClockTime = 14

            if config.hardcoreBoost then
                game.Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
            end
        end)

        -- ปรับ Rendering Settings
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level02
        end)

        -- ปรับ Terrain
        pcall(function()
            local terrain = ws:FindFirstChildOfClass("Terrain")
            if terrain then
                terrain.WaterWaveSize = 0
                terrain.WaterTransparency = 1
                terrain.WaterReflectance = 0
                terrain.WaterWaveSpeed = 0
            end
        end)

        print("⚡ Performance optimization completed!")
    end)
end


local toggleKey = Enum.KeyCode.RightControl
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == toggleKey then
        if gui.Enabled then
            -- ซ่อน GUI
            local tween = TweenService:Create(mainContainer, TweenInfo.new(0.3), {
                Position = mainContainer.Position - UDim2.new(0, 0, 0, 700)
            })
            tween:Play()
            tween.Completed:Connect(function()
                gui.Enabled = false
            end)
        else
            -- แสดง GUI
            gui.Enabled = true
            local tween = TweenService:Create(mainContainer, TweenInfo.new(0.3), {
                Position = mainContainer.Position + UDim2.new(0, 0, 0, 700)
            })
            tween:Play()
        end
    end
end)


local function addGlow(object, color)
    local glow = Instance.new("Frame")
    glow.Size = object.Size + UDim2.new(0, 4, 0, 4)
    glow.Position = object.Position - UDim2.new(0, 2, 0, 2)
    glow.BackgroundColor3 = color or Color3.fromRGB(100, 200, 255)
    glow.BackgroundTransparency = 0.8
    glow.ZIndex = object.ZIndex - 1
    glow.Parent = object.Parent
    
    local corner = Instance.new("UICorner", glow)
    corner.CornerRadius = UDim.new(0, 20)
    
    return glow
end


addGlow(mainContainer, Color3.fromRGB(80, 150, 255))

