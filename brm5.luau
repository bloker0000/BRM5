local getglobalenv = getgenv
local globalEnv = nil
local success, result = pcall(function()
    return getglobalenv and getglobalenv() or _G
end)

if success and typeof(result) == "table" then
    globalEnv = result
else
    globalEnv = _G
end

globalEnv.BRM5_ESP = globalEnv.BRM5_ESP or {}

local previousState = globalEnv.BRM5_ESP
local savedSettings
if typeof(previousState) == "table" then
    savedSettings = previousState.SavedSettings
end

print("BRM5 ESP Script Loading...")

if typeof(previousState) == "table" and previousState.Active then
    local prevCleanup = previousState.Cleanup
    if typeof(prevCleanup) == "function" then
        local ok, err = pcall(prevCleanup)
        if not ok then
            warn("Previous ESP cleanup failed:", err)
        else
            print("Previous ESP instance cleaned up")
        end
    end
    globalEnv.BRM5_ESP = {}
end

local DEFAULT_SETTINGS = {
    Enabled = true,
    ChamsEnabled = true,
    OutlineEnabled = true,
    ShowDistance = true,
    ShowHealth = true,
    ShowEntityType = true,
    Show2DBox = true,
    MaxDistance = 2000,
    FillTransparency = 0.35,
    OutlineTransparency = 0,
    PlayerFillColor = Color3.fromRGB(255, 180, 60),
    PlayerOutlineColor = Color3.fromRGB(255, 240, 210),
    ZombieFillColor = Color3.fromRGB(120, 220, 120),
    ZombieOutlineColor = Color3.fromRGB(210, 255, 210),
    HealthBarFillColor = Color3.fromRGB(110, 220, 110),
    HealthBarBackColor = Color3.fromRGB(40, 60, 40),
    UIToggleKey = "Insert",
    AimbotEnabled = false,
    AimbotKey = "MouseButton2",
    AimbotKeyMode = "Hold",
    AimbotTargetPart = "Head",
    AimbotFOV = 150,
    AimbotShowFOV = true,
    AimbotFOVColor = Color3.fromRGB(255, 255, 255),
    AimbotFOVSides = 60,
    AimbotFOVThickness = 1,
    AimbotFOVFilled = false,
    AimbotFOVTransparency = 0.7,
    AimbotSmoothing = 0.1,
    AimbotMaxDistance = 1000,
    AimbotVisibilityCheck = true,
    AimbotTargetPlayers = true,
    AimbotTargetZombies = true,
    AimbotPriority = "Closest",
    AimbotMinHealth = 0,
    AimbotPrediction = false,
    AimbotPredictionAmount = 0.1,
    AimbotStickyTarget = false,
    AimbotShowTargetInfo = true,
    AimbotYOffset = 53
}

local CONFIG_FILE = "BRM5_ESP_Config.json"

local mathFloor = math.floor
local mathClamp = math.clamp
local mathMin = math.min
local mathMax = math.max
local mathSqrt = math.sqrt
local mathHuge = math.huge
local tableInsert = table.insert
local tableRemove = table.remove
local tableClear = table.clear
local tableConcat = table.concat
local tableSort = table.sort

local function serializeColor(color)
    return {
        R = mathFloor(color.R * 255),
        G = mathFloor(color.G * 255),
        B = mathFloor(color.B * 255)
    }
end

local function deserializeColor(data)
    if type(data) == "table" and data.R and data.G and data.B then
        return Color3.fromRGB(data.R, data.G, data.B)
    end
    return nil
end

local ESPSettings

local function serializeSettings(settings)
    if not settings or type(settings) ~= "table" then
        return {}
    end
    local data = {}
    for key, value in pairs(settings) do
        if typeof(value) == "Color3" then
            data[key] = serializeColor(value)
        else
            data[key] = value
        end
    end
    return data
end

local function deserializeSettings(data)
    if type(data) ~= "table" then
        return nil
    end
    local settings = {}
    for key, defaultValue in pairs(DEFAULT_SETTINGS) do
        local value = data[key]
        if value ~= nil then
            if typeof(defaultValue) == "Color3" then
                local color = deserializeColor(value)
                settings[key] = color or defaultValue
            elseif type(value) == type(defaultValue) then
                settings[key] = value
            else
                settings[key] = defaultValue
            end
        else
            settings[key] = defaultValue
        end
    end
    return settings
end

local function saveConfigToFile()
    local success, err = pcall(function()
        if not writefile then
            warn("Config save not supported: writefile not available")
            return
        end
        local HttpService = game:GetService("HttpService")
        local data = serializeSettings(ESPSettings)
        local json = HttpService:JSONEncode(data)
        writefile(CONFIG_FILE, json)
    end)
    if not success then
        warn("BRM5 ESP: Failed to save config -", err)
    end
end

local function loadConfigFromFile()
    local success, result = pcall(function()
        if not readfile or not isfile then
            return nil
        end
        if not isfile(CONFIG_FILE) then
            return nil
        end
        local HttpService = game:GetService("HttpService")
        local json = readfile(CONFIG_FILE)
        local data = HttpService:JSONDecode(json)
        return deserializeSettings(data)
    end)
    if success and result then
        print("BRM5 ESP: Config loaded")
        return result
    end
    return nil
end

local function copySettings(source)
    local clone = {}
    if typeof(source) == "table" then
        for key, value in pairs(source) do
            clone[key] = value
        end
    end
    return clone
end

local function resolveSettings(source)
    local resolved = {}
    for key, defaultValue in pairs(DEFAULT_SETTINGS) do
        local candidate = source and source[key]
        if candidate ~= nil and typeof(candidate) == typeof(defaultValue) then
            resolved[key] = candidate
        else
            resolved[key] = defaultValue
        end
    end
    return resolved
end

local loadedConfig = loadConfigFromFile()
ESPSettings = loadedConfig or resolveSettings(savedSettings)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

local UPDATE_INTERVAL = 0.016
local MIN_DISTANCE = 8
local MIN_DISTANCE_SQ = MIN_DISTANCE * MIN_DISTANCE

local TrackedModels = {}

local Theme = {
    Border = Color3.fromRGB(90, 75, 45),
    TextPrimary = Color3.fromRGB(255, 245, 210)
}

local AimbotState = {
    Enabled = false,
    CurrentTarget = nil,
    CurrentTargetPart = nil,
    IsAiming = false,
    FOVCircle = nil,
    TargetIndicator = nil,
    LastTargetTime = 0
}

local function GetCamera()
    local customCam = LocalPlayer:FindFirstChild("WorldModel")
    if customCam then
        customCam = customCam:FindFirstChild("WorldModel")
        if customCam then
            customCam = customCam:FindFirstChild("Model")
            if customCam then
                customCam = customCam:FindFirstChild("Cam")
                if customCam then
                    customCam = customCam:FindFirstChild("CAM")
                    if customCam and customCam:IsA("Camera") then
                        return customCam
                    end
                end
            end
        end
    end
    return Workspace.CurrentCamera
end

local function GetMousePosition()
    return UserInputService:GetMouseLocation()
end

local function GetScreenCenter()
    local camera = GetCamera()
    if camera then
        return Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    end
    return Vector2.new(0, 0)
end

local function WorldToScreen(position)
    local camera = GetCamera()
    if not camera then
        return nil, false
    end
    local screenPos, onScreen = camera:WorldToScreenPoint(position)
    if screenPos.Z < 0 then
        return nil, false
    end
    return Vector2.new(screenPos.X, screenPos.Y), onScreen
end

local function GetDistanceFromMouseSq(screenPos)
    local mousePos = GetMousePosition()
    local dx = screenPos.X - mousePos.X
    local dy = screenPos.Y - mousePos.Y
    return dx * dx + dy * dy
end

local function GetDistanceFromMouse(screenPos)
    return mathSqrt(GetDistanceFromMouseSq(screenPos))
end

local function IsInFOV(screenPos, fovSq)
    return GetDistanceFromMouseSq(screenPos) <= fovSq
end

local function GetTargetPart(model)
    local partName = ESPSettings.AimbotTargetPart
    local part = model:FindFirstChild(partName)
    if part and part:IsA("BasePart") then
        return part
    end
    if partName == "Head" then
        part = model:FindFirstChild("Head")
        if part then
            return part
        end
    end
    part = model:FindFirstChild("HumanoidRootPart")
    if part then
        return part
    end
    part = model:FindFirstChild("Root")
    if part then
        return part
    end
    part = model:FindFirstChild("Torso")
    if part then
        return part
    end
    part = model:FindFirstChild("UpperTorso")
    if part then
        return part
    end
    return model.PrimaryPart
end

local CachedRayParams = RaycastParams.new()
CachedRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function IsTargetVisible(origin, targetPosition, targetModel)
    if not ESPSettings.AimbotVisibilityCheck then
        return true
    end

    local direction = (targetPosition - origin)
    local distance = direction.Magnitude

    if distance < 1 then
        return true
    end

    local ignoreList = {}
    local char = LocalPlayer.Character
    if char then
        ignoreList[1] = char
    end
    if targetModel then
        tableInsert(ignoreList, targetModel)
    end
    CachedRayParams.FilterDescendantsInstances = ignoreList

    local rayResult = Workspace:Raycast(origin, direction.Unit * (distance - 0.5), CachedRayParams)

    if rayResult then
        if targetModel and rayResult.Instance:IsDescendantOf(targetModel) then
            return true
        end
        return false
    end

    return true
end

local function GetEntityHealth(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid.Health, humanoid.MaxHealth
    end
    return 100, 100
end

local function GetEntityVelocity(model)
    local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart.AssemblyLinearVelocity or rootPart.Velocity or Vector3.zero
    end
    return Vector3.zero
end

local function PredictPosition(currentPos, velocity, predictionAmount)
    if not ESPSettings.AimbotPrediction then
        return currentPos
    end
    return currentPos + (velocity * predictionAmount)
end

local function GetValidTargets()
    local targets = {}
    local camera = GetCamera()
    local stickyTarget = nil

    if not camera then
        return targets, stickyTarget
    end

    local origin = camera.CFrame.Position
    local maxDistSq = ESPSettings.AimbotMaxDistance * ESPSettings.AimbotMaxDistance
    local fovSq = ESPSettings.AimbotFOV * ESPSettings.AimbotFOV
    local targetPlayers = ESPSettings.AimbotTargetPlayers
    local targetZombies = ESPSettings.AimbotTargetZombies
    local minHealth = ESPSettings.AimbotMinHealth
    local checkVisibility = ESPSettings.AimbotVisibilityCheck
    local stickyEnabled = ESPSettings.AimbotStickyTarget
    local currentTarget = AimbotState.CurrentTarget
    local localChar = LocalPlayer.Character

    for model, data in pairs(TrackedModels) do
        if model.Parent and model ~= localChar then
            local entityType = data.EntityType
            local shouldProcess = (entityType == "Player" and targetPlayers) or 
                                  (entityType == "Zombie" and targetZombies)

            if shouldProcess then
                local health, maxHealth = GetEntityHealth(model)
                if health > minHealth then
                    local targetPart = GetTargetPart(model)
                    if targetPart then
                        local targetPos = targetPart.Position
                        local delta = targetPos - origin
                        local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z

                        if distSq <= maxDistSq then
                            local distance = mathSqrt(distSq)
                            local velocity = GetEntityVelocity(model)
                            local predictedPos = PredictPosition(targetPos, velocity,
                                ESPSettings.AimbotPredictionAmount)

                            local screenPos, onScreen = WorldToScreen(predictedPos)
                            if screenPos then
                                local isVisible = not checkVisibility or
                                                      IsTargetVisible(origin, predictedPos, model)
                                
                                if isVisible then
                                    local isStickyTarget = stickyEnabled and currentTarget == model
                                    local fovDistSq = GetDistanceFromMouseSq(screenPos)
                                    local inFOV = fovDistSq <= fovSq
                                    
                                    if isStickyTarget then
                                        stickyTarget = {
                                            Model = model,
                                            Part = targetPart,
                                            Position = predictedPos,
                                            ScreenPosition = screenPos,
                                            Distance = distance,
                                            Health = health,
                                            MaxHealth = maxHealth,
                                            HealthPercent = health / maxHealth,
                                            FOVDistance = mathSqrt(fovDistSq),
                                            EntityType = entityType,
                                            OnScreen = onScreen
                                        }
                                    elseif inFOV then
                                        tableInsert(targets, {
                                            Model = model,
                                            Part = targetPart,
                                            Position = predictedPos,
                                            ScreenPosition = screenPos,
                                            Distance = distance,
                                            Health = health,
                                            MaxHealth = maxHealth,
                                            HealthPercent = health / maxHealth,
                                            FOVDistance = mathSqrt(fovDistSq),
                                            EntityType = entityType,
                                            OnScreen = onScreen
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return targets, stickyTarget
end

local function SelectTarget(targets, stickyTarget)
    if stickyTarget then
        return stickyTarget
    end
    
    if #targets == 0 then
        return nil
    end

    local priority = ESPSettings.AimbotPriority
    
    if priority == "Closest" then
        tableSort(targets, function(a, b) return a.Distance < b.Distance end)
    elseif priority == "Lowest Health" then
        tableSort(targets, function(a, b) return a.Health < b.Health end)
    elseif priority == "Highest Health" then
        tableSort(targets, function(a, b) return a.Health > b.Health end)
    else
        tableSort(targets, function(a, b) return a.FOVDistance < b.FOVDistance end)
    end

    return targets[1]
end

local function AimAt(targetPart)
    if not targetPart or not targetPart.Parent then
        return
    end
    
    local camera = GetCamera()
    if not camera then
        return
    end
    
    local partCenter = targetPart.Position
    local screenPos3D = camera:WorldToScreenPoint(partCenter)
    
    if screenPos3D.Z <= 0 then
        return
    end
    
    local screenPos = Vector2.new(screenPos3D.X, screenPos3D.Y)
    local viewportSize = camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
    
    local deltaX = screenPos.X - screenCenter.X
    local deltaY = (screenPos.Y + ESPSettings.AimbotYOffset) - screenCenter.Y

    local distance = mathSqrt(deltaX * deltaX + deltaY * deltaY)
    
    if distance < 1 then
        return
    end

    local smoothing = mathClamp(ESPSettings.AimbotSmoothing, 0.01, 1)
    
    local maxMovePerFrame = 15 + (85 * smoothing)
    local minMoveThreshold = 0.5
    
    local speedFactor
    if distance < 50 then
        speedFactor = (distance / 50) * smoothing
    else
        speedFactor = smoothing
    end
    
    local moveAmount = mathMin(distance * speedFactor, maxMovePerFrame)
    
    if moveAmount < minMoveThreshold then
        return
    end
    
    local dirX = deltaX / distance
    local dirY = deltaY / distance
    
    local moveX = dirX * moveAmount
    local moveY = dirY * moveAmount

    pcall(function()
        mousemoverel(moveX, moveY)
    end)
end

local function CreateFOVCircle()
    if AimbotState.FOVCircle then
        return AimbotState.FOVCircle
    end

    local circle = Drawing.new("Circle")
    circle.Visible = false
    circle.Radius = ESPSettings.AimbotFOV
    circle.Color = ESPSettings.AimbotFOVColor
    circle.Thickness = ESPSettings.AimbotFOVThickness
    circle.NumSides = ESPSettings.AimbotFOVSides
    circle.Filled = ESPSettings.AimbotFOVFilled
    circle.Transparency = 1 - ESPSettings.AimbotFOVTransparency

    AimbotState.FOVCircle = circle
    return circle
end

local function CreateTargetIndicator()
    if AimbotState.TargetIndicator then
        return AimbotState.TargetIndicator
    end

    local indicator = Drawing.new("Text")
    indicator.Visible = false
    indicator.Color = Color3.fromRGB(255, 100, 100)
    indicator.Size = 14
    indicator.Center = true
    indicator.Outline = true
    indicator.OutlineColor = Color3.fromRGB(0, 0, 0)
    indicator.Font = 2

    AimbotState.TargetIndicator = indicator
    return indicator
end

local function UpdateFOVCircle()
    local circle = AimbotState.FOVCircle
    if not circle then
        circle = CreateFOVCircle()
    end

    if not ESPSettings.AimbotEnabled or not ESPSettings.AimbotShowFOV then
        circle.Visible = false
        return
    end

    local mousePos = GetMousePosition()
    circle.Position = mousePos
    circle.Radius = ESPSettings.AimbotFOV
    circle.Color = ESPSettings.AimbotFOVColor
    circle.Thickness = ESPSettings.AimbotFOVThickness
    circle.NumSides = ESPSettings.AimbotFOVSides
    circle.Filled = ESPSettings.AimbotFOVFilled
    circle.Transparency = 1 - ESPSettings.AimbotFOVTransparency
    circle.Visible = true
end

local function UpdateTargetIndicator(target)
    local indicator = AimbotState.TargetIndicator
    if not indicator then
        indicator = CreateTargetIndicator()
    end

    if not ESPSettings.AimbotEnabled or not ESPSettings.AimbotShowTargetInfo or not target then
        indicator.Visible = false
        return
    end

    local screenPos = target.ScreenPosition
    if not screenPos or not target.OnScreen then
        indicator.Visible = false
        return
    end

    indicator.Position = Vector2.new(screenPos.X, screenPos.Y - 25)
    indicator.Text = string.format("[TARGET] %s | %d HP | %dm", target.EntityType, mathFloor(target.Health),
        mathFloor(target.Distance))
    indicator.Visible = true
end

local function CleanupAimbot()
    if AimbotState.FOVCircle then
        AimbotState.FOVCircle:Remove()
        AimbotState.FOVCircle = nil
    end
    if AimbotState.TargetIndicator then
        AimbotState.TargetIndicator:Remove()
        AimbotState.TargetIndicator = nil
    end
    AimbotState.CurrentTarget = nil
    AimbotState.CurrentTargetPart = nil
    AimbotState.IsAiming = false
end

local function GetCustomCamera()
    local customCam = LocalPlayer:FindFirstChild("WorldModel")
    if customCam then
        customCam = customCam:FindFirstChild("WorldModel")
        if customCam then
            customCam = customCam:FindFirstChild("Model")
            if customCam then
                customCam = customCam:FindFirstChild("Cam")
                if customCam then
                    customCam = customCam:FindFirstChild("CAM")
                    if customCam and customCam:IsA("Camera") then
                        return customCam
                    end
                end
            end
        end
    end
    return nil
end

local function GetCameraController()
    local worldModel = LocalPlayer:FindFirstChild("WorldModel")
    if worldModel then
        worldModel = worldModel:FindFirstChild("WorldModel")
        if worldModel then
            local model = worldModel:FindFirstChild("Model")
            if model then
                return model:FindFirstChild("Cam")
            end
        end
    end
    return nil
end

local function UpdateAimbot()
    if not ESPSettings.AimbotEnabled then
        if AimbotState.FOVCircle then
            AimbotState.FOVCircle.Visible = false
        end
        if AimbotState.TargetIndicator then
            AimbotState.TargetIndicator.Visible = false
        end
        AimbotState.CurrentTarget = nil
        return
    end

    UpdateFOVCircle()

    if not AimbotState.IsAiming then
        UpdateTargetIndicator(nil)
        AimbotState.CurrentTarget = nil
        AimbotState.CurrentTargetPart = nil
        return
    end

    local targets, stickyTarget = GetValidTargets()
    local bestTarget = SelectTarget(targets, stickyTarget)

    if bestTarget then
        AimbotState.CurrentTarget = bestTarget.Model
        AimbotState.CurrentTargetPart = bestTarget.Part
        UpdateTargetIndicator(bestTarget)
        AimAt(bestTarget.Part)
    else
        AimbotState.CurrentTarget = nil
        AimbotState.CurrentTargetPart = nil
        UpdateTargetIndicator(nil)
    end
end

local function GetInputEnum(keyName)
    local successKeyCode, keyCodeResult = pcall(function()
        return Enum.KeyCode[keyName]
    end)
    if successKeyCode and keyCodeResult then
        return keyCodeResult, "KeyCode"
    end

    local successInputType, inputTypeResult = pcall(function()
        return Enum.UserInputType[keyName]
    end)
    if successInputType and inputTypeResult then
        return inputTypeResult, "UserInputType"
    end

    return Enum.UserInputType.MouseButton2, "UserInputType"
end

local function IsAimbotKeyDown(input)
    local keyEnum, keyType = GetInputEnum(ESPSettings.AimbotKey)
    if keyType == "KeyCode" then
        return input.KeyCode == keyEnum
    else
        return input.UserInputType == keyEnum
    end
end

local state = {
    Connections = {},
    Active = true,
    SavedSettings = copySettings(ESPSettings)
}

globalEnv.BRM5_ESP = state

local OverlayPool = {}
local ColorDisplays = {}
local LastUpdate = 0
local OverlayRoot = nil

state.TrackedModels = TrackedModels
state.OverlayPool = OverlayPool
state.ColorDisplays = ColorDisplays
state.OverlayRoot = nil

local function TrackConnection(connection)
    if connection then
        tableInsert(state.Connections, connection)
    end
    return connection
end

local function DetermineEntityType(model)
    local owner = Players:GetPlayerFromCharacter(model)
    if owner and owner ~= LocalPlayer then
        return "Player"
    end
    if model.Name == "Male" then
        return "Player"
    end
    return "Zombie"
end

local function ApplyHighlightSettings(highlight, entityType)
    if not highlight then
        return
    end
    if not ESPSettings.Enabled or not (ESPSettings.ChamsEnabled or ESPSettings.OutlineEnabled) then
        highlight.Enabled = false
        return
    end

    local isZombie = entityType == "Zombie"
    local fillColor = isZombie and ESPSettings.ZombieFillColor or ESPSettings.PlayerFillColor
    local outlineColor = isZombie and ESPSettings.ZombieOutlineColor or ESPSettings.PlayerOutlineColor

    highlight.FillColor = fillColor
    highlight.OutlineColor = outlineColor
    highlight.FillTransparency = ESPSettings.ChamsEnabled and mathClamp(ESPSettings.FillTransparency, 0, 1) or 1
    highlight.OutlineTransparency = ESPSettings.OutlineEnabled and mathClamp(ESPSettings.OutlineTransparency, 0, 1) or 1
    highlight.Enabled = true
end

local function CreateHighlight(model)
    if not model or not model:IsA("Model") then
        warn("CreateHighlight: Invalid model provided")
        return nil
    end

    local success, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.Adornee = model
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = CoreGui
        return h
    end)

    if not success then
        warn("CreateHighlight failed for model:", model.Name, "Error:", highlight)
        return nil
    end

    return highlight
end

local function EnsureOverlayRoot()
    if OverlayRoot and OverlayRoot.Parent then
        return OverlayRoot
    end
    if ScreenGuiRef and ScreenGuiRef.Parent then
        local existing = ScreenGuiRef:FindFirstChild("OverlayRoot")
        if not existing then
            existing = Instance.new("Frame")
            existing.Name = "OverlayRoot"
            existing.Size = UDim2.new(1, 0, 1, 0)
            existing.BackgroundTransparency = 1
            existing.BorderSizePixel = 0
            existing.Active = false
            existing.ClipsDescendants = false
            existing.ZIndex = 0
            existing.Parent = ScreenGuiRef
        end
        if existing and existing:IsA("Frame") then
            OverlayRoot = existing
            state.OverlayRoot = existing
            return existing
        end
    end
    return nil
end

local function GetOrCreateOverlayEntry()
    if #OverlayPool > 0 then
        return tableRemove(OverlayPool)
    end

    local overlayFrame = Instance.new("Frame")
    overlayFrame.Name = "Overlay"
    overlayFrame.BackgroundTransparency = 1
    overlayFrame.BorderSizePixel = 0
    overlayFrame.Visible = false
    overlayFrame.ZIndex = 40
    overlayFrame.Active = false
    overlayFrame.ClipsDescendants = false

    local boxFrame = Instance.new("Frame")
    boxFrame.Name = "Box"
    boxFrame.BackgroundTransparency = 1
    boxFrame.BorderSizePixel = 1
    boxFrame.BorderColor3 = Theme.Border
    boxFrame.Size = UDim2.new(1, 0, 1, 0)
    boxFrame.ZIndex = 41
    boxFrame.Parent = overlayFrame

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "Info"
    infoLabel.AnchorPoint = Vector2.new(0, 1)
    infoLabel.BackgroundTransparency = 1
    infoLabel.BorderSizePixel = 0
    infoLabel.Text = ""
    infoLabel.TextColor3 = Theme.TextPrimary
    infoLabel.Font = Enum.Font.Arcade
    infoLabel.TextScaled = false
    infoLabel.TextSize = 16
    infoLabel.Visible = false
    infoLabel.ZIndex = 42
    infoLabel.Parent = overlayFrame

    local infoPadding = Instance.new("UIPadding")
    infoPadding.PaddingLeft = UDim.new(0, 6)
    infoPadding.PaddingRight = UDim.new(0, 6)
    infoPadding.Parent = infoLabel

    local healthFrame = Instance.new("Frame")
    healthFrame.Name = "Health"
    healthFrame.BackgroundColor3 = ESPSettings.HealthBarBackColor
    healthFrame.BorderSizePixel = 0
    healthFrame.Visible = false
    healthFrame.ZIndex = 41
    healthFrame.Parent = overlayFrame

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 3)
    healthCorner.Parent = healthFrame

    local healthFill = Instance.new("Frame")
    healthFill.Name = "Fill"
    healthFill.AnchorPoint = Vector2.new(0, 1)
    healthFill.Position = UDim2.new(0, 0, 1, 0)
    healthFill.Size = UDim2.new(1, 0, 0, 0)
    healthFill.BackgroundColor3 = ESPSettings.HealthBarFillColor
    healthFill.BorderSizePixel = 0
    healthFill.ZIndex = 42
    healthFill.Parent = healthFrame

    local healthFillCorner = Instance.new("UICorner")
    healthFillCorner.CornerRadius = UDim.new(0, 3)
    healthFillCorner.Parent = healthFill

    return {
        Overlay = overlayFrame,
        BoxFrame = boxFrame,
        InfoLabel = infoLabel,
        HealthFrame = healthFrame,
        HealthFill = healthFill
    }
end

local function ReturnOverlayEntry(entry)
    if not entry then
        return
    end

    local overlay = entry.Overlay
    if overlay then
        overlay.Visible = false
        overlay.Parent = nil
        overlay.Position = UDim2.new()
        overlay.Size = UDim2.new()
    end

    if entry.InfoLabel then
        entry.InfoLabel.Text = ""
        entry.InfoLabel.Visible = false
    end

    if entry.HealthFrame then
        entry.HealthFrame.Visible = false
    end

    if entry.HealthFill then
        entry.HealthFill.Size = UDim2.new(1, 0, 0, 0)
    end

    tableInsert(OverlayPool, entry)
end

local function GetModelHealth(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid.Health, humanoid.MaxHealth
    end
    return 100, 100
end

local function ComputeScreenBounds(model, camera)
    if not model or not camera then
        return nil
    end

    local pivotCFrame, size = model:GetBoundingBox()
    if not pivotCFrame or not size then
        return nil
    end

    local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
    if hx <= 0 or hy <= 0 or hz <= 0 then
        return nil
    end

    local minX, minY = mathHuge, mathHuge
    local maxX, maxY = -mathHuge, -mathHuge
    local anyVisible = false

    local cornerOffsets = {
        {-hx, -hy, -hz}, {-hx, -hy, hz}, {-hx, hy, -hz}, {-hx, hy, hz},
        {hx, -hy, -hz}, {hx, -hy, hz}, {hx, hy, -hz}, {hx, hy, hz}
    }
    
    for i = 1, 8 do
        local c = cornerOffsets[i]
        local worldPoint = pivotCFrame:PointToWorldSpace(Vector3.new(c[1], c[2], c[3]))
        local screenPos, onScreen = camera:WorldToScreenPoint(worldPoint)
        if screenPos.Z > 0 then
            local sx, sy = screenPos.X, screenPos.Y
            if sx < minX then minX = sx end
            if sy < minY then minY = sy end
            if sx > maxX then maxX = sx end
            if sy > maxY then maxY = sy end
            anyVisible = anyVisible or onScreen
        end
    end

    if not anyVisible or minX == mathHuge then
        return nil
    end

    local width = maxX - minX
    local height = maxY - minY
    if width < 2 or height < 2 then
        return nil
    end

    return {
        MinX = minX,
        MinY = minY,
        MaxX = maxX,
        MaxY = maxY,
        Width = width,
        Height = height
    }
end

local RemoveESP

local function UpdateESP(model, data)
    if not model.Parent then
        return false
    end
    if model == LocalPlayer.Character then
        return false
    end

    local highlight = data.Highlight
    local overlayEntry = data.OverlayEntry

    if not ESPSettings.Enabled then
        if highlight then
            highlight.Enabled = false
        end
        if overlayEntry and overlayEntry.Overlay then
            overlayEntry.Overlay.Visible = false
        end
        return true
    end

    local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
    if not rootPart then
        if highlight then
            highlight.Enabled = false
        end
        if overlayEntry and overlayEntry.Overlay then
            overlayEntry.Overlay.Visible = false
        end
        return false
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return true
    end

    local distance = (camera.CFrame.Position - rootPart.Position).Magnitude
    if distance < MIN_DISTANCE or distance > ESPSettings.MaxDistance then
        if highlight then
            highlight.Enabled = false
        end
        if overlayEntry and overlayEntry.Overlay then
            overlayEntry.Overlay.Visible = false
        end
        return true
    end

    if highlight then
        local adorneeSuccess = pcall(function()
            if highlight.Adornee ~= model then
                highlight.Adornee = model
            end
        end)
        if not adorneeSuccess then
            warn("Failed to set Highlight.Adornee for model:", model.Name)
            return false
        end
        ApplyHighlightSettings(highlight, data.EntityType)
    end

    if not overlayEntry then
        return true
    end

    local showOverlay = ESPSettings.Show2DBox or ESPSettings.ShowDistance or ESPSettings.ShowHealth or
                            ESPSettings.ShowEntityType
    if not showOverlay then
        overlayEntry.Overlay.Visible = false
        return true
    end

    local overlayParent = EnsureOverlayRoot()
    if not overlayParent then
        overlayEntry.Overlay.Visible = false
        return true
    end

    if overlayEntry.Overlay.Parent ~= overlayParent then
        overlayEntry.Overlay.Parent = overlayParent
    end

    local bounds = ComputeScreenBounds(model, camera)
    if not bounds then
        overlayEntry.Overlay.Visible = false
        return true
    end

    local boxWidth = bounds.Width
    local boxHeight = bounds.Height
    local boxX = bounds.MinX
    local boxY = bounds.MinY
    local viewportSize = camera.ViewportSize

    local minBoxWidth = 24
    local minBoxHeight = 40
    local maxBoxHeight = 260
    local maxBoxWidth = 220

    if boxWidth < minBoxWidth then
        local delta = (minBoxWidth - boxWidth) * 0.5
        boxX = boxX - delta
        boxWidth = minBoxWidth
    elseif boxWidth > maxBoxWidth then
        local delta = (boxWidth - maxBoxWidth) * 0.5
        boxX = boxX + delta
        boxWidth = maxBoxWidth
    end

    if boxHeight < minBoxHeight then
        local delta = (minBoxHeight - boxHeight) * 0.5
        boxY = boxY - delta
        boxHeight = minBoxHeight
    elseif boxHeight > maxBoxHeight then
        local delta = (boxHeight - maxBoxHeight) * 0.5
        boxY = boxY + delta
        boxHeight = maxBoxHeight
    end

    overlayEntry.Overlay.Visible = true
    overlayEntry.Overlay.Position = UDim2.fromOffset(boxX, boxY)
    overlayEntry.Overlay.Size = UDim2.fromOffset(boxWidth, boxHeight)

    local boxFrame = overlayEntry.BoxFrame
    if boxFrame then
        boxFrame.Visible = ESPSettings.Show2DBox
        boxFrame.BorderColor3 = Theme.Border
        boxFrame.BorderSizePixel = mathClamp(mathFloor(boxHeight / 140) + 1, 1, 3)
        boxFrame.Size = UDim2.new(1, 0, 1, 0)
    end

    local infoLabel = overlayEntry.InfoLabel
    if infoLabel then
        local showType = ESPSettings.ShowEntityType
        local showDist = ESPSettings.ShowDistance
        local infoText
        if showType and showDist then
            infoText = data.EntityType .. " | " .. mathFloor(distance + 0.5) .. " st"
        elseif showType then
            infoText = data.EntityType
        elseif showDist then
            infoText = mathFloor(distance + 0.5) .. " st"
        else
            infoText = nil
        end
        
        if infoText then
            local infoHeight = mathClamp(boxHeight * 0.2, 10, 30)
            infoLabel.Visible = true
            infoLabel.Size = UDim2.fromOffset(boxWidth, infoHeight)
            local labelOffset = mathMax(4, mathFloor(infoHeight * 0.5))
            infoLabel.Position = UDim2.new(0, 0, 0, -labelOffset - infoHeight)
            infoLabel.Text = infoText
            infoLabel.TextColor3 = Theme.TextPrimary
            infoLabel.BackgroundTransparency = 1
            infoLabel.TextXAlignment = Enum.TextXAlignment.Center
            infoLabel.TextYAlignment = Enum.TextYAlignment.Center
            infoLabel.TextSize = mathClamp(mathFloor(infoHeight * 0.7), 11, 26)
        else
            infoLabel.Visible = false
        end
    end

    local healthFrame = overlayEntry.HealthFrame
    local healthFill = overlayEntry.HealthFill
    if healthFrame and healthFill then
        if ESPSettings.ShowHealth then
            healthFrame.Visible = true
            local healthWidth = mathClamp(mathFloor(boxHeight * 0.08), 4, 12)
            local spacing = mathClamp(mathFloor(boxWidth * 0.06), 4, 14)
            local verticalPadding = mathClamp(mathFloor(boxHeight * 0.06), 2, 12)
            local preferredX = -healthWidth - spacing
            if boxX + preferredX < 0 then
                preferredX = boxWidth + spacing
            elseif viewportSize and (boxX + preferredX + healthWidth) > viewportSize.X then
                preferredX = boxWidth + spacing
            end
            healthFrame.Position = UDim2.new(0, preferredX, 0, verticalPadding)
            healthFrame.Size = UDim2.new(0, healthWidth, 1, -verticalPadding * 2)
            healthFrame.BackgroundColor3 = ESPSettings.HealthBarBackColor

            local health, maxHealth = GetModelHealth(model)
            local percent = 0
            if maxHealth and maxHealth > 0 then
                percent = mathClamp(health / maxHealth, 0, 1)
            end
            healthFill.Size = UDim2.new(1, 0, percent, 0)
            healthFill.BackgroundColor3 = ESPSettings.HealthBarFillColor
        else
            healthFrame.Visible = false
        end
    end

    return true
end

local function AddESP(model)
    if TrackedModels[model] then
        return
    end
    if not model:IsA("Model") then
        return
    end
    if model == LocalPlayer.Character then
        return
    end
    if not model:IsDescendantOf(Workspace) then
        return
    end

    local isTarget = model.Name == "Male" or model.Name == "Zombie"
    if not isTarget then
        return
    end
    if Players:GetPlayerFromCharacter(model) == LocalPlayer then
        return
    end

    -- Validate model has essential structure
    local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
    if not rootPart or not rootPart:IsA("BasePart") then
        return -- Skip models without valid root parts
    end

    local entityType = DetermineEntityType(model)
    local highlight = CreateHighlight(model)
    if not highlight then
        return -- Failed to create highlight
    end
    local overlayEntry = GetOrCreateOverlayEntry()
    local overlayParent = EnsureOverlayRoot()
    if overlayParent and overlayEntry.Overlay.Parent ~= overlayParent then
        overlayEntry.Overlay.Parent = overlayParent
    end
    overlayEntry.Overlay.Visible = false

    local data = {
        Model = model,
        EntityType = entityType,
        Highlight = highlight,
        OverlayEntry = overlayEntry
    }

    data.AncestryConn = model.AncestryChanged:Connect(function(_, parent)
        if not parent then
            RemoveESP(model)
        end
    end)

    TrackedModels[model] = data

    ApplyHighlightSettings(highlight, entityType)
    UpdateESP(model, data)
end

RemoveESP = function(model)
    local data = TrackedModels[model]
    if not data then
        return
    end

    if data.AncestryConn then
        data.AncestryConn:Disconnect()
    end
    if data.Highlight then
        data.Highlight:Destroy()
    end
    if data.OverlayEntry then
        ReturnOverlayEntry(data.OverlayEntry)
        data.OverlayEntry = nil
    end

    TrackedModels[model] = nil
end

local function RefreshAllVisuals()
    for _, data in pairs(TrackedModels) do
        if data.Highlight then
            ApplyHighlightSettings(data.Highlight, data.EntityType)
        end
        local overlayEntry = data.OverlayEntry
        if overlayEntry then
            if overlayEntry.BoxFrame then
                overlayEntry.BoxFrame.BorderColor3 = Theme.Border
            end
            if overlayEntry.HealthFrame then
                overlayEntry.HealthFrame.BackgroundColor3 = ESPSettings.HealthBarBackColor
            end
            if overlayEntry.HealthFill then
                overlayEntry.HealthFill.BackgroundColor3 = ESPSettings.HealthBarFillColor
            end
            if overlayEntry.InfoLabel then
                overlayEntry.InfoLabel.TextColor3 = Theme.TextPrimary
                overlayEntry.InfoLabel.BackgroundTransparency = 1
            end
        end
    end

    for property, entry in pairs(ColorDisplays) do
        local currentColor = ESPSettings[property]
        if entry.Swatch and entry.Swatch.Parent then
            entry.Swatch.BackgroundColor3 = currentColor
        end
        if entry.HexLabel and entry.HexLabel.Parent then
            entry.HexLabel.Text = "#" .. string.upper(currentColor:ToHex())
        end
    end
end

local function ScanWorkspace()
    for model in pairs(TrackedModels) do
        if not model.Parent then
            RemoveESP(model)
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name == "Male" or obj.Name == "Zombie") then
            AddESP(obj)
        end
    end
end

local function CleanupTrackedModels()
    for model in pairs(TrackedModels) do
        RemoveESP(model)
    end
    tableClear(TrackedModels)
end

local ScreenGuiRef
local library

local function CreateGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ESPOverlayGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = false
    screenGui.Parent = CoreGui

    local overlayRoot = Instance.new("Frame")
    overlayRoot.Name = "OverlayRoot"
    overlayRoot.Size = UDim2.new(1, 0, 1, 0)
    overlayRoot.BackgroundTransparency = 1
    overlayRoot.BorderSizePixel = 0
    overlayRoot.Active = false
    overlayRoot.ClipsDescendants = false
    overlayRoot.ZIndex = 0
    overlayRoot.Parent = screenGui

    OverlayRoot = overlayRoot
    state.OverlayRoot = overlayRoot
    ScreenGuiRef = screenGui
    state.ScreenGui = screenGui

    local libSuccess, libResult = pcall(function()
        return loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/bloker0000/MultyUI/refs/heads/main/MultyUI.luau"))()
    end)
    
    if not libSuccess or not libResult then
        warn("BRM5 ESP: Failed to load UI library -", libResult)
        return nil
    end
    
    library = libResult

    local window = library:window({
        name = "BRM5",
        suffix = "ESP",
        gameInfo = "Blackout Roleplay Modded V"
    })

    window:seperator({name = "ESP"})
    local espVisibility, espSettings, espColors = window:tab({
        name = "ESP",
        tabs = {"Visibility", "Settings", "Colors"}
    })

    local visibilityCol = espVisibility:column({})
    local visibilitySection = visibilityCol:section({name = "Visibility", default = true})

    visibilitySection:toggle({
        name = "ESP Enabled",
        flag = "ESP_Enabled",
        default = ESPSettings.Enabled,
        seperator = true,
        callback = function(value)
            ESPSettings.Enabled = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    visibilitySection:toggle({
        name = "Chams",
        flag = "ESP_Chams",
        default = ESPSettings.ChamsEnabled,
        seperator = true,
        callback = function(value)
            ESPSettings.ChamsEnabled = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    visibilitySection:toggle({
        name = "Outline",
        flag = "ESP_Outline",
        default = ESPSettings.OutlineEnabled,
        seperator = true,
        callback = function(value)
            ESPSettings.OutlineEnabled = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    visibilitySection:toggle({
        name = "2D Box",
        flag = "ESP_2DBox",
        default = ESPSettings.Show2DBox,
        seperator = true,
        callback = function(value)
            ESPSettings.Show2DBox = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    visibilitySection:toggle({
        name = "Show Distance",
        flag = "ESP_Distance",
        default = ESPSettings.ShowDistance,
        seperator = true,
        callback = function(value)
            ESPSettings.ShowDistance = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    visibilitySection:toggle({
        name = "Health Bar",
        flag = "ESP_Health",
        default = ESPSettings.ShowHealth,
        seperator = true,
        callback = function(value)
            ESPSettings.ShowHealth = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    visibilitySection:toggle({
        name = "Entity Label",
        flag = "ESP_EntityType",
        default = ESPSettings.ShowEntityType,
        callback = function(value)
            ESPSettings.ShowEntityType = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    local settingsCol = espSettings:column({})
    local settingsSection = settingsCol:section({name = "Settings", default = true})

    settingsSection:slider({
        name = "Max Distance",
        flag = "ESP_MaxDistance",
        min = 100,
        max = 5000,
        default = ESPSettings.MaxDistance,
        interval = 50,
        suffix = " studs",
        seperator = true,
        callback = function(value)
            ESPSettings.MaxDistance = value
            saveConfigToFile()
        end
    })

    settingsSection:slider({
        name = "Fill Opacity",
        flag = "ESP_FillOpacity",
        min = 0,
        max = 100,
        default = mathFloor((1 - ESPSettings.FillTransparency) * 100),
        interval = 1,
        suffix = "%",
        seperator = true,
        callback = function(value)
            ESPSettings.FillTransparency = 1 - (value / 100)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    settingsSection:slider({
        name = "Outline Opacity",
        flag = "ESP_OutlineOpacity",
        min = 0,
        max = 100,
        default = mathFloor((1 - ESPSettings.OutlineTransparency) * 100),
        interval = 1,
        suffix = "%",
        callback = function(value)
            ESPSettings.OutlineTransparency = 1 - (value / 100)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    local colorsCol = espColors:column({})
    local entityColorsSection = colorsCol:section({name = "Entity Colors", default = true})

    entityColorsSection:toggle({
        name = "Player Fill",
        flag = "ESP_PlayerFillToggle",
        default = true,
        seperator = true
    }):colorpicker({
        flag = "ESP_PlayerFillColor",
        color = ESPSettings.PlayerFillColor,
        callback = function(color)
            ESPSettings.PlayerFillColor = color
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    entityColorsSection:toggle({
        name = "Player Outline",
        flag = "ESP_PlayerOutlineToggle",
        default = true,
        seperator = true
    }):colorpicker({
        flag = "ESP_PlayerOutlineColor",
        color = ESPSettings.PlayerOutlineColor,
        callback = function(color)
            ESPSettings.PlayerOutlineColor = color
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    entityColorsSection:toggle({
        name = "Zombie Fill",
        flag = "ESP_ZombieFillToggle",
        default = true,
        seperator = true
    }):colorpicker({
        flag = "ESP_ZombieFillColor",
        color = ESPSettings.ZombieFillColor,
        callback = function(color)
            ESPSettings.ZombieFillColor = color
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    entityColorsSection:toggle({
        name = "Zombie Outline",
        flag = "ESP_ZombieOutlineToggle",
        default = true
    }):colorpicker({
        flag = "ESP_ZombieOutlineColor",
        color = ESPSettings.ZombieOutlineColor,
        callback = function(color)
            ESPSettings.ZombieOutlineColor = color
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    local colorsCol2 = espColors:column({})
    local healthColorsSection = colorsCol2:section({name = "Health Bar Colors", default = true})

    healthColorsSection:toggle({
        name = "Health Fill",
        flag = "ESP_HealthFillToggle",
        default = true,
        seperator = true
    }):colorpicker({
        flag = "ESP_HealthFillColor",
        color = ESPSettings.HealthBarFillColor,
        callback = function(color)
            ESPSettings.HealthBarFillColor = color
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    healthColorsSection:toggle({
        name = "Health Background",
        flag = "ESP_HealthBackToggle",
        default = true
    }):colorpicker({
        flag = "ESP_HealthBackColor",
        color = ESPSettings.HealthBarBackColor,
        callback = function(color)
            ESPSettings.HealthBarBackColor = color
            RefreshAllVisuals()
            saveConfigToFile()
        end
    })

    window:seperator({name = "Aimbot"})
    local aimbotMain, aimbotTargets, aimbotFOV = window:tab({
        name = "Aimbot",
        tabs = {"Main", "Targets", "FOV"}
    })

    local aimbotCol = aimbotMain:column({})
    local aimbotSection = aimbotCol:section({name = "Aimbot Settings", default = true})

    aimbotSection:toggle({
        name = "Aimbot Enabled",
        flag = "Aimbot_Enabled",
        default = ESPSettings.AimbotEnabled,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotEnabled = value
            if not value then
                AimbotState.IsAiming = false
                AimbotState.CurrentTarget = nil
            end
            saveConfigToFile()
        end
    })

    local savedAimbotKey = ESPSettings.AimbotKey
    local aimbotKeyEnum
    local successKC, kcResult = pcall(function()
        return Enum.KeyCode[savedAimbotKey]
    end)
    local successIT, itResult = pcall(function()
        return Enum.UserInputType[savedAimbotKey]
    end)
    if successKC and kcResult then
        aimbotKeyEnum = kcResult
    elseif successIT and itResult then
        aimbotKeyEnum = itResult
    else
        aimbotKeyEnum = Enum.UserInputType.MouseButton2
    end

    aimbotSection:keybind({
        name = "Aimbot Key",
        flag = "Aimbot_Key",
        default = aimbotKeyEnum,
        mode = "Hold",
        seperator = true,
        callback = function(active)
            if ESPSettings.AimbotKeyMode == "Hold" then
                AimbotState.IsAiming = active
            end
        end
    })

    aimbotSection:dropdown({
        name = "Key Mode",
        flag = "Aimbot_KeyMode",
        items = {"Hold", "Toggle"},
        default = ESPSettings.AimbotKeyMode,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotKeyMode = value
            if value == "Hold" then
                AimbotState.IsAiming = false
            end
            saveConfigToFile()
        end
    })

    aimbotSection:dropdown({
        name = "Target Part",
        flag = "Aimbot_TargetPart",
        items = {"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "LeftArm", "RightArm", "LeftLeg", "RightLeg"},
        default = ESPSettings.AimbotTargetPart,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotTargetPart = value
            saveConfigToFile()
        end
    })

    aimbotSection:dropdown({
        name = "Priority",
        flag = "Aimbot_Priority",
        items = {"Closest to Crosshair", "Closest", "Lowest Health", "Highest Health"},
        default = ESPSettings.AimbotPriority,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotPriority = value
            saveConfigToFile()
        end
    })

    aimbotSection:slider({
        name = "Smoothing",
        flag = "Aimbot_Smoothing",
        min = 0.01,
        max = 1,
        default = ESPSettings.AimbotSmoothing,
        interval = 0.01,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotSmoothing = value
            saveConfigToFile()
        end
    })

    aimbotSection:slider({
        name = "Max Distance",
        flag = "Aimbot_MaxDistance",
        min = 100,
        max = 5000,
        default = ESPSettings.AimbotMaxDistance,
        interval = 50,
        suffix = " studs",
        callback = function(value)
            ESPSettings.AimbotMaxDistance = value
            saveConfigToFile()
        end
    })

    local aimbotCol2 = aimbotMain:column({})
    local predictionSection = aimbotCol2:section({name = "Prediction", default = true})

    predictionSection:toggle({
        name = "Enable Prediction",
        flag = "Aimbot_Prediction",
        default = ESPSettings.AimbotPrediction,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotPrediction = value
            saveConfigToFile()
        end
    })

    predictionSection:slider({
        name = "Prediction Amount",
        flag = "Aimbot_PredictionAmount",
        min = 0.01,
        max = 0.5,
        default = ESPSettings.AimbotPredictionAmount,
        interval = 0.01,
        suffix = "s",
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotPredictionAmount = value
            saveConfigToFile()
        end
    })

    predictionSection:slider({
        name = "Y Offset (Calibration)",
        flag = "Aimbot_YOffset",
        min = -100,
        max = 100,
        default = ESPSettings.AimbotYOffset - 53,
        interval = 1,
        suffix = "px",
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotYOffset = value + 53
            saveConfigToFile()
        end
    })

    predictionSection:toggle({
        name = "Show Target Info",
        flag = "Aimbot_ShowTargetInfo",
        default = ESPSettings.AimbotShowTargetInfo,
        callback = function(value)
            ESPSettings.AimbotShowTargetInfo = value
            saveConfigToFile()
        end
    })

    local targetCol = aimbotTargets:column({})
    local targetSection = targetCol:section({name = "Target Filters", default = true})

    targetSection:toggle({
        name = "Target Players",
        flag = "Aimbot_TargetPlayers",
        default = ESPSettings.AimbotTargetPlayers,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotTargetPlayers = value
            saveConfigToFile()
        end
    })

    targetSection:toggle({
        name = "Target Zombies",
        flag = "Aimbot_TargetZombies",
        default = ESPSettings.AimbotTargetZombies,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotTargetZombies = value
            saveConfigToFile()
        end
    })

    targetSection:toggle({
        name = "Visibility Check",
        flag = "Aimbot_VisibilityCheck",
        default = ESPSettings.AimbotVisibilityCheck,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotVisibilityCheck = value
            saveConfigToFile()
        end
    })

    targetSection:toggle({
        name = "Sticky Target",
        flag = "Aimbot_StickyTarget",
        default = ESPSettings.AimbotStickyTarget,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotStickyTarget = value
            saveConfigToFile()
        end
    })

    targetSection:slider({
        name = "Min Health Threshold",
        flag = "Aimbot_MinHealth",
        min = 0,
        max = 100,
        default = ESPSettings.AimbotMinHealth,
        interval = 1,
        suffix = " HP",
        callback = function(value)
            ESPSettings.AimbotMinHealth = value
            saveConfigToFile()
        end
    })

    local fovCol = aimbotFOV:column({})
    local fovSection = fovCol:section({name = "FOV Settings", default = true})

    fovSection:toggle({
        name = "Show FOV Circle",
        flag = "Aimbot_ShowFOV",
        default = ESPSettings.AimbotShowFOV,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotShowFOV = value
            saveConfigToFile()
        end
    })

    fovSection:slider({
        name = "FOV Radius",
        flag = "Aimbot_FOV",
        min = 10,
        max = 500,
        default = ESPSettings.AimbotFOV,
        interval = 5,
        suffix = "px",
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotFOV = value
            saveConfigToFile()
        end
    })

    fovSection:toggle({
        name = "FOV Color",
        flag = "Aimbot_FOVColorToggle",
        default = true,
        seperator = true
    }):colorpicker({
        flag = "Aimbot_FOVColor",
        color = ESPSettings.AimbotFOVColor,
        callback = function(color)
            ESPSettings.AimbotFOVColor = color
            saveConfigToFile()
        end
    })

    fovSection:slider({
        name = "FOV Thickness",
        flag = "Aimbot_FOVThickness",
        min = 1,
        max = 5,
        default = ESPSettings.AimbotFOVThickness,
        interval = 0.5,
        suffix = "px",
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotFOVThickness = value
            saveConfigToFile()
        end
    })

    fovSection:slider({
        name = "FOV Sides",
        flag = "Aimbot_FOVSides",
        min = 12,
        max = 120,
        default = ESPSettings.AimbotFOVSides,
        interval = 6,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotFOVSides = value
            saveConfigToFile()
        end
    })

    fovSection:toggle({
        name = "FOV Filled",
        flag = "Aimbot_FOVFilled",
        default = ESPSettings.AimbotFOVFilled,
        seperator = true,
        callback = function(value)
            ESPSettings.AimbotFOVFilled = value
            saveConfigToFile()
        end
    })

    fovSection:slider({
        name = "FOV Transparency",
        flag = "Aimbot_FOVTransparency",
        min = 0,
        max = 100,
        default = ESPSettings.AimbotFOVTransparency * 100,
        interval = 5,
        suffix = "%",
        callback = function(value)
            ESPSettings.AimbotFOVTransparency = value / 100
            saveConfigToFile()
        end
    })

    window:seperator({name = "Config"})
    local configTab = window:tab({
        name = "Config",
        tabs = {"Settings"}
    })

    local configCol = configTab:column({})
    local configSection = configCol:section({name = "Configuration", default = true})

    configSection:button({
        name = "Save Config",
        callback = function()
            saveConfigToFile()
            library.notifications:create_notification({
                name = "Config Saved",
                info = "Your settings have been saved.",
                lifetime = 3
            })
        end
    })

    local configCol2 = configTab:column({})
    local uiSection = configCol2:section({name = "UI Settings", default = true})

    uiSection:button({
        name = "Unload Script",
        callback = function()
            CleanupResources()
            library:unload_menu()
        end
    })

    library:init_config(window)

    state.Library = library
    return screenGui
end

local guiSuccess, guiError = pcall(CreateGUI)
if not guiSuccess then
    warn("ESP GUI creation failed:", guiError)
else
    print("BRM5 ESP GUI loaded successfully")
end

local scanSuccess, scanError = pcall(ScanWorkspace)
if not scanSuccess then
    warn("ESP workspace scan failed:", scanError)
end

TrackConnection(Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") and (obj.Name == "Male" or obj.Name == "Zombie") then
        if obj ~= LocalPlayer.Character then
            task.defer(function()
                if obj.Parent then
                    AddESP(obj)
                end
            end)
        end
    end
end))

TrackConnection(Workspace.DescendantRemoving:Connect(function(obj)
    if TrackedModels[obj] then
        RemoveESP(obj)
    end
end))

TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if IsAimbotKeyDown(input) then
        if ESPSettings.AimbotKeyMode == "Hold" then
            AimbotState.IsAiming = true
        elseif ESPSettings.AimbotKeyMode == "Toggle" then
            AimbotState.IsAiming = not AimbotState.IsAiming
        end
    end
end))

TrackConnection(UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if IsAimbotKeyDown(input) then
        if ESPSettings.AimbotKeyMode == "Hold" then
            AimbotState.IsAiming = false
        end
    end
end))

local ToRemoveBuffer = {}

TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
    local now = time()
    if now - LastUpdate < UPDATE_INTERVAL then
        return
    end
    LastUpdate = now

    local removeCount = 0
    for model, data in pairs(TrackedModels) do
        if not UpdateESP(model, data) then
            removeCount = removeCount + 1
            ToRemoveBuffer[removeCount] = model
        end
    end

    for i = 1, removeCount do
        RemoveESP(ToRemoveBuffer[i])
        ToRemoveBuffer[i] = nil
    end

    UpdateAimbot()
end))

TrackConnection(LocalPlayer.CharacterRemoving:Connect(function()
    CleanupTrackedModels()
end))

TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
    task.defer(ScanWorkspace)
end))

local function CleanupResources()
    CleanupAimbot()

    for model in pairs(TrackedModels) do
        RemoveESP(model)
    end

    for _, entry in ipairs(OverlayPool) do
        if entry.Overlay then
            entry.Overlay:Destroy()
        end
    end
    tableClear(OverlayPool)
    OverlayRoot = nil
    state.OverlayRoot = nil
    LastUpdate = 0

    for _, connection in ipairs(state.Connections) do
        if connection.Disconnect then
            connection:Disconnect()
        end
    end
    tableClear(state.Connections)

    if ScreenGuiRef then
        ScreenGuiRef:Destroy()
        ScreenGuiRef = nil
    end
    state.ScreenGui = nil
    tableClear(ColorDisplays)

    if library then
        pcall(function()
            library:unload_menu()
        end)
        library = nil
    end
    state.Library = nil

    state.Active = false
end

state.Cleanup = CleanupResources