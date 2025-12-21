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

local function serializeColor(color)
    return {
        R = math.floor(color.R * 255),
        G = math.floor(color.G * 255),
        B = math.floor(color.B * 255)
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

local function GetDistanceFromMouse(screenPos)
    local mousePos = GetMousePosition()
    return (screenPos - mousePos).Magnitude
end

local function IsInFOV(screenPos)
    local distance = GetDistanceFromMouse(screenPos)
    return distance <= ESPSettings.AimbotFOV
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

local function IsTargetVisible(origin, targetPosition, targetModel)
    if not ESPSettings.AimbotVisibilityCheck then
        return true
    end

    local direction = (targetPosition - origin)
    local distance = direction.Magnitude

    if distance < 1 then
        return true
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local ignoreList = {}
    if LocalPlayer.Character then
        table.insert(ignoreList, LocalPlayer.Character)
    end
    if targetModel then
        table.insert(ignoreList, targetModel)
    end
    rayParams.FilterDescendantsInstances = ignoreList

    local rayResult = Workspace:Raycast(origin, direction.Unit * (distance - 0.5), rayParams)

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

    if not camera then
        return targets
    end

    local origin = camera.CFrame.Position

    for model, data in pairs(TrackedModels) do
        if model.Parent then
            if model == LocalPlayer.Character then
                -- Skip: standard character check
            elseif Players:GetPlayerFromCharacter(model) == LocalPlayer then
                -- Skip: player owns this character
            else
                local entityType = data.EntityType
                local shouldProcess = true

                if entityType == "Player" and not ESPSettings.AimbotTargetPlayers then
                    shouldProcess = false
                elseif entityType == "Zombie" and not ESPSettings.AimbotTargetZombies then
                    shouldProcess = false
                end

                if shouldProcess then
                    local health, maxHealth = GetEntityHealth(model)
                    if health > ESPSettings.AimbotMinHealth then
                        local targetPart = GetTargetPart(model)
                        if targetPart then
                            local targetPos = targetPart.Position
                            local distance = (targetPos - origin).Magnitude

                            if distance <= ESPSettings.AimbotMaxDistance then
                                local velocity = GetEntityVelocity(model)
                                local predictedPos = PredictPosition(targetPos, velocity,
                                    ESPSettings.AimbotPredictionAmount)

                                local screenPos, onScreen = WorldToScreen(predictedPos)
                                if screenPos then
                                    local inFOV = IsInFOV(screenPos)
                                    if inFOV then
                                        local isVisible = not ESPSettings.AimbotVisibilityCheck or
                                                              IsTargetVisible(origin, predictedPos, model)
                                        if isVisible then
                                            table.insert(targets, {
                                                Model = model,
                                                Part = targetPart,
                                                Position = predictedPos,
                                                ScreenPosition = screenPos,
                                                Distance = distance,
                                                Health = health,
                                                MaxHealth = maxHealth,
                                                HealthPercent = health / maxHealth,
                                                FOVDistance = GetDistanceFromMouse(screenPos),
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
    end

    return targets
end

local function SelectTarget(targets)
    if #targets == 0 then
        return nil
    end

    if ESPSettings.AimbotStickyTarget and AimbotState.CurrentTarget then
        for _, target in ipairs(targets) do
            if target.Model == AimbotState.CurrentTarget then
                return target
            end
        end
    end

    local priority = ESPSettings.AimbotPriority

    table.sort(targets, function(a, b)
        if priority == "Closest" then
            return a.Distance < b.Distance
        elseif priority == "Lowest Health" then
            return a.Health < b.Health
        elseif priority == "Highest Health" then
            return a.Health > b.Health
        elseif priority == "Closest to Crosshair" then
            return a.FOVDistance < b.FOVDistance
        else
            return a.FOVDistance < b.FOVDistance
        end
    end)

    return targets[1]
end

local function AimAt(screenPos)
    if not screenPos then
        return
    end

    local screenCenter = GetScreenCenter()
    local deltaX = screenPos.X - screenCenter.X
    local deltaY = (screenPos.Y + ESPSettings.AimbotYOffset) - screenCenter.Y

    local smoothing = math.clamp(ESPSettings.AimbotSmoothing, 0.01, 1)
    local moveX = deltaX * smoothing
    local moveY = deltaY * smoothing

    if math.abs(moveX) < 0.5 and math.abs(moveY) < 0.5 then
        return
    end

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
    indicator.Text = string.format("[TARGET] %s | %d HP | %dm", target.EntityType, math.floor(target.Health),
        math.floor(target.Distance))
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
        if not ESPSettings.AimbotStickyTarget then
            AimbotState.CurrentTarget = nil
        end
        return
    end

    local targets = GetValidTargets()
    local bestTarget = SelectTarget(targets)

    if bestTarget then
        AimbotState.CurrentTarget = bestTarget.Model
        AimbotState.CurrentTargetPart = bestTarget.Part
        UpdateTargetIndicator(bestTarget)
        AimAt(bestTarget.ScreenPosition)
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
        table.insert(state.Connections, connection)
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

    local fillColor = entityType == "Zombie" and ESPSettings.ZombieFillColor or ESPSettings.PlayerFillColor
    local outlineColor = entityType == "Zombie" and ESPSettings.ZombieOutlineColor or ESPSettings.PlayerOutlineColor

    highlight.FillColor = fillColor
    highlight.OutlineColor = outlineColor
    highlight.FillTransparency = ESPSettings.ChamsEnabled and math.clamp(ESPSettings.FillTransparency, 0, 1) or 1
    highlight.OutlineTransparency = ESPSettings.OutlineEnabled and math.clamp(ESPSettings.OutlineTransparency, 0, 1) or
                                        1
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
        return table.remove(OverlayPool)
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

    table.insert(OverlayPool, entry)
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

    local half = size * 0.5
    if half.X <= 0 or half.Y <= 0 or half.Z <= 0 then
        return nil
    end

    local offsets = {Vector3.new(-half.X, -half.Y, -half.Z), Vector3.new(-half.X, -half.Y, half.Z),
                     Vector3.new(-half.X, half.Y, -half.Z), Vector3.new(-half.X, half.Y, half.Z),
                     Vector3.new(half.X, -half.Y, -half.Z), Vector3.new(half.X, -half.Y, half.Z),
                     Vector3.new(half.X, half.Y, -half.Z), Vector3.new(half.X, half.Y, half.Z)}

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false
    local processed = false

    for _, offset in ipairs(offsets) do
        local worldPoint = pivotCFrame:PointToWorldSpace(offset)
        local screenPos, onScreen = camera:WorldToScreenPoint(worldPoint)
        processed = true
        if screenPos.Z > 0 then
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
            anyVisible = anyVisible or onScreen
        end
    end

    if not processed or not anyVisible or minX == math.huge or minY == math.huge or maxX == -math.huge or maxY ==
        -math.huge then
        return nil
    end

    local width = math.max(0, maxX - minX)
    local height = math.max(0, maxY - minY)
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
        boxFrame.BorderSizePixel = math.clamp(math.floor(boxHeight / 140) + 1, 1, 3)
        boxFrame.Size = UDim2.new(1, 0, 1, 0)
    end

    local infoLabel = overlayEntry.InfoLabel
    if infoLabel then
        local segments = {}
        if ESPSettings.ShowEntityType then
            table.insert(segments, data.EntityType)
        end
        if ESPSettings.ShowDistance then
            table.insert(segments, string.format("%d st", math.floor(distance + 0.5)))
        end
        local infoText = table.concat(segments, " | ")
        if infoText ~= "" then
            local infoHeight = math.clamp(boxHeight * 0.2, 10, 30)
            infoLabel.Visible = true
            infoLabel.Size = UDim2.fromOffset(boxWidth, infoHeight)
            local labelOffset = math.max(4, math.floor(infoHeight * 0.5))
            infoLabel.Position = UDim2.new(0, 0, 0, -labelOffset - infoHeight)
            infoLabel.Text = infoText
            infoLabel.TextColor3 = Theme.TextPrimary
            infoLabel.BackgroundTransparency = 1
            infoLabel.TextXAlignment = Enum.TextXAlignment.Center
            infoLabel.TextYAlignment = Enum.TextYAlignment.Center
            infoLabel.TextSize = math.clamp(math.floor(infoHeight * 0.7), 11, 26)
        else
            infoLabel.Visible = false
        end
    end

    local healthFrame = overlayEntry.HealthFrame
    local healthFill = overlayEntry.HealthFill
    if healthFrame and healthFill then
        if ESPSettings.ShowHealth then
            healthFrame.Visible = true
            local healthWidth = math.clamp(math.floor(boxHeight * 0.08), 4, 12)
            local spacing = math.clamp(math.floor(boxWidth * 0.06), 4, 14)
            local verticalPadding = math.clamp(math.floor(boxHeight * 0.06), 2, 12)
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
                percent = math.clamp(health / maxHealth, 0, 1)
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
    table.clear(TrackedModels)
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

    library = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/weakhoes/Roblox-UI-Libs/refs/heads/main/Venus%20Lib/Venus%20Lib%20Source.lua"))()

    local main = library:Load{
        Name = "BlackCock",
        SizeX = 550,
        SizeY = 500,
        Theme = "Midnight",
        Extension = "json",
        Folder = "BRM5_Cheat"
    }

    local espTab = main:Tab("ESP")

    local visibilitySection = espTab:Section{
        Name = "Visibility",
        Side = "Left"
    }

    visibilitySection:Toggle{
        Name = "ESP Enabled",
        Flag = "ESP_Enabled",
        Default = ESPSettings.Enabled,
        Callback = function(value)
            ESPSettings.Enabled = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    visibilitySection:Toggle{
        Name = "Chams",
        Flag = "ESP_Chams",
        Default = ESPSettings.ChamsEnabled,
        Callback = function(value)
            ESPSettings.ChamsEnabled = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    visibilitySection:Toggle{
        Name = "Outline",
        Flag = "ESP_Outline",
        Default = ESPSettings.OutlineEnabled,
        Callback = function(value)
            ESPSettings.OutlineEnabled = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    visibilitySection:Toggle{
        Name = "2D Box",
        Flag = "ESP_2DBox",
        Default = ESPSettings.Show2DBox,
        Callback = function(value)
            ESPSettings.Show2DBox = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    visibilitySection:Toggle{
        Name = "Show Distance",
        Flag = "ESP_Distance",
        Default = ESPSettings.ShowDistance,
        Callback = function(value)
            ESPSettings.ShowDistance = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    visibilitySection:Toggle{
        Name = "Health Bar",
        Flag = "ESP_Health",
        Default = ESPSettings.ShowHealth,
        Callback = function(value)
            ESPSettings.ShowHealth = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    visibilitySection:Toggle{
        Name = "Entity Label",
        Flag = "ESP_EntityType",
        Default = ESPSettings.ShowEntityType,
        Callback = function(value)
            ESPSettings.ShowEntityType = value
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    local settingsSection = espTab:Section{
        Name = "Settings",
        Side = "Right"
    }

    settingsSection:Slider{
        Name = "Max Distance",
        Text = "[value] studs",
        Default = ESPSettings.MaxDistance,
        Min = 100,
        Max = 5000,
        Float = 50,
        Flag = "ESP_MaxDistance",
        Callback = function(value)
            ESPSettings.MaxDistance = value
            saveConfigToFile()
        end
    }

    settingsSection:Slider{
        Name = "Fill Opacity",
        Text = "[value]%",
        Default = math.floor((1 - ESPSettings.FillTransparency) * 100),
        Min = 0,
        Max = 100,
        Float = 1,
        Flag = "ESP_FillOpacity",
        Callback = function(value)
            ESPSettings.FillTransparency = 1 - (value / 100)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    settingsSection:Slider{
        Name = "Outline Opacity",
        Text = "[value]%",
        Default = math.floor((1 - ESPSettings.OutlineTransparency) * 100),
        Min = 0,
        Max = 100,
        Float = 1,
        Flag = "ESP_OutlineOpacity",
        Callback = function(value)
            ESPSettings.OutlineTransparency = 1 - (value / 100)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    local playerColorsSection = espTab:Section{
        Name = "Player Colors",
        Side = "Left"
    }

    playerColorsSection:ColorPicker{
        Name = "Player Fill Color",
        Default = ESPSettings.PlayerFillColor,
        Flag = "ESP_PlayerFillColor",
        Callback = function(color)
            ESPSettings.PlayerFillColor = Color3.new(color.R, color.G, color.B)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    playerColorsSection:ColorPicker{
        Name = "Player Outline Color",
        Default = ESPSettings.PlayerOutlineColor,
        Flag = "ESP_PlayerOutlineColor",
        Callback = function(color)
            ESPSettings.PlayerOutlineColor = Color3.new(color.R, color.G, color.B)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    local zombieColorsSection = espTab:Section{
        Name = "Zombie Colors",
        Side = "Right"
    }

    zombieColorsSection:ColorPicker{
        Name = "Zombie Fill Color",
        Default = ESPSettings.ZombieFillColor,
        Flag = "ESP_ZombieFillColor",
        Callback = function(color)
            ESPSettings.ZombieFillColor = Color3.new(color.R, color.G, color.B)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    zombieColorsSection:ColorPicker{
        Name = "Zombie Outline Color",
        Default = ESPSettings.ZombieOutlineColor,
        Flag = "ESP_ZombieOutlineColor",
        Callback = function(color)
            ESPSettings.ZombieOutlineColor = Color3.new(color.R, color.G, color.B)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    local healthColorsSection = espTab:Section{
        Name = "Health Bar Colors",
        Side = "Left"
    }

    healthColorsSection:ColorPicker{
        Name = "Health Fill Color",
        Default = ESPSettings.HealthBarFillColor,
        Flag = "ESP_HealthFillColor",
        Callback = function(color)
            ESPSettings.HealthBarFillColor = Color3.new(color.R, color.G, color.B)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    healthColorsSection:ColorPicker{
        Name = "Health Background",
        Default = ESPSettings.HealthBarBackColor,
        Flag = "ESP_HealthBackColor",
        Callback = function(color)
            ESPSettings.HealthBarBackColor = Color3.new(color.R, color.G, color.B)
            RefreshAllVisuals()
            saveConfigToFile()
        end
    }

    local aimbotTab = main:Tab("Aimbot")

    local aimbotSection = aimbotTab:Section{
        Name = "Aimbot Settings",
        Side = "Left"
    }

    aimbotSection:Toggle{
        Name = "Aimbot Enabled",
        Flag = "Aimbot_Enabled",
        Default = ESPSettings.AimbotEnabled,
        Callback = function(value)
            ESPSettings.AimbotEnabled = value
            if not value then
                AimbotState.IsAiming = false
                AimbotState.CurrentTarget = nil
            end
            saveConfigToFile()
        end
    }

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

    aimbotSection:Keybind{
        Name = "Aimbot Key",
        Flag = "Aimbot_Key",
        Default = aimbotKeyEnum,
        Callback = function(key, fromsetting)
            if fromsetting then
                ESPSettings.AimbotKey = key.Name
                saveConfigToFile()
            end
        end
    }

    aimbotSection:Dropdown{
        Name = "Key Mode",
        Flag = "Aimbot_KeyMode",
        Default = ESPSettings.AimbotKeyMode,
        Content = {"Hold", "Toggle"},
        Callback = function(value)
            ESPSettings.AimbotKeyMode = value
            if value == "Hold" then
                AimbotState.IsAiming = false
            end
            saveConfigToFile()
        end
    }

    aimbotSection:Dropdown{
        Name = "Target Part",
        Flag = "Aimbot_TargetPart",
        Default = ESPSettings.AimbotTargetPart,
        Content = {"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "LeftArm", "RightArm", "LeftLeg",
                   "RightLeg"},
        Callback = function(value)
            ESPSettings.AimbotTargetPart = value
            saveConfigToFile()
        end
    }

    aimbotSection:Dropdown{
        Name = "Priority",
        Flag = "Aimbot_Priority",
        Default = ESPSettings.AimbotPriority,
        Content = {"Closest to Crosshair", "Closest", "Lowest Health", "Highest Health"},
        Callback = function(value)
            ESPSettings.AimbotPriority = value
            saveConfigToFile()
        end
    }

    aimbotSection:Slider{
        Name = "Smoothing",
        Text = "[value]",
        Default = ESPSettings.AimbotSmoothing,
        Min = 0.01,
        Max = 1,
        Float = 0.01,
        Flag = "Aimbot_Smoothing",
        Callback = function(value)
            ESPSettings.AimbotSmoothing = value
            saveConfigToFile()
        end
    }

    aimbotSection:Slider{
        Name = "Max Distance",
        Text = "[value] studs",
        Default = ESPSettings.AimbotMaxDistance,
        Min = 100,
        Max = 5000,
        Float = 50,
        Flag = "Aimbot_MaxDistance",
        Callback = function(value)
            ESPSettings.AimbotMaxDistance = value
            saveConfigToFile()
        end
    }

    local targetSection = aimbotTab:Section{
        Name = "Target Filters",
        Side = "Left"
    }

    targetSection:Toggle{
        Name = "Target Players",
        Flag = "Aimbot_TargetPlayers",
        Default = ESPSettings.AimbotTargetPlayers,
        Callback = function(value)
            ESPSettings.AimbotTargetPlayers = value
            saveConfigToFile()
        end
    }

    targetSection:Toggle{
        Name = "Target Zombies",
        Flag = "Aimbot_TargetZombies",
        Default = ESPSettings.AimbotTargetZombies,
        Callback = function(value)
            ESPSettings.AimbotTargetZombies = value
            saveConfigToFile()
        end
    }

    targetSection:Toggle{
        Name = "Visibility Check",
        Flag = "Aimbot_VisibilityCheck",
        Default = ESPSettings.AimbotVisibilityCheck,
        Callback = function(value)
            ESPSettings.AimbotVisibilityCheck = value
            saveConfigToFile()
        end
    }

    targetSection:Toggle{
        Name = "Sticky Target",
        Flag = "Aimbot_StickyTarget",
        Default = ESPSettings.AimbotStickyTarget,
        Callback = function(value)
            ESPSettings.AimbotStickyTarget = value
            saveConfigToFile()
        end
    }

    targetSection:Slider{
        Name = "Min Health Threshold",
        Text = "[value] HP",
        Default = ESPSettings.AimbotMinHealth,
        Min = 0,
        Max = 100,
        Float = 1,
        Flag = "Aimbot_MinHealth",
        Callback = function(value)
            ESPSettings.AimbotMinHealth = value
            saveConfigToFile()
        end
    }

    local predictionSection = aimbotTab:Section{
        Name = "Prediction",
        Side = "Right"
    }

    predictionSection:Toggle{
        Name = "Enable Prediction",
        Flag = "Aimbot_Prediction",
        Default = ESPSettings.AimbotPrediction,
        Callback = function(value)
            ESPSettings.AimbotPrediction = value
            saveConfigToFile()
        end
    }

    predictionSection:Slider{
        Name = "Prediction Amount",
        Text = "[value]s",
        Default = ESPSettings.AimbotPredictionAmount,
        Min = 0.01,
        Max = 0.5,
        Float = 0.01,
        Flag = "Aimbot_PredictionAmount",
        Callback = function(value)
            ESPSettings.AimbotPredictionAmount = value
            saveConfigToFile()
        end
    }

    predictionSection:Slider{
        Name = "Y Offset (Calibration)",
        Text = "[value]px",
        Default = ESPSettings.AimbotYOffset - 53,
        Min = -100,
        Max = 100,
        Float = 1,
        Flag = "Aimbot_YOffset",
        Callback = function(value)
            ESPSettings.AimbotYOffset = value + 53
            saveConfigToFile()
        end
    }

    local fovSection = aimbotTab:Section{
        Name = "FOV Settings",
        Side = "Right"
    }

    fovSection:Toggle{
        Name = "Show FOV Circle",
        Flag = "Aimbot_ShowFOV",
        Default = ESPSettings.AimbotShowFOV,
        Callback = function(value)
            ESPSettings.AimbotShowFOV = value
            saveConfigToFile()
        end
    }

    fovSection:Slider{
        Name = "FOV Radius",
        Text = "[value]px",
        Default = ESPSettings.AimbotFOV,
        Min = 10,
        Max = 500,
        Float = 5,
        Flag = "Aimbot_FOV",
        Callback = function(value)
            ESPSettings.AimbotFOV = value
            saveConfigToFile()
        end
    }

    fovSection:ColorPicker{
        Name = "FOV Color",
        Default = ESPSettings.AimbotFOVColor,
        Flag = "Aimbot_FOVColor",
        Callback = function(color)
            ESPSettings.AimbotFOVColor = Color3.new(color.R, color.G, color.B)
            saveConfigToFile()
        end
    }

    fovSection:Slider{
        Name = "FOV Thickness",
        Text = "[value]px",
        Default = ESPSettings.AimbotFOVThickness,
        Min = 1,
        Max = 5,
        Float = 0.5,
        Flag = "Aimbot_FOVThickness",
        Callback = function(value)
            ESPSettings.AimbotFOVThickness = value
            saveConfigToFile()
        end
    }

    fovSection:Slider{
        Name = "FOV Sides",
        Text = "[value]",
        Default = ESPSettings.AimbotFOVSides,
        Min = 12,
        Max = 120,
        Float = 6,
        Flag = "Aimbot_FOVSides",
        Callback = function(value)
            ESPSettings.AimbotFOVSides = value
            saveConfigToFile()
        end
    }

    fovSection:Toggle{
        Name = "FOV Filled",
        Flag = "Aimbot_FOVFilled",
        Default = ESPSettings.AimbotFOVFilled,
        Callback = function(value)
            ESPSettings.AimbotFOVFilled = value
            saveConfigToFile()
        end
    }

    fovSection:Slider{
        Name = "FOV Transparency",
        Text = "[value]%",
        Default = ESPSettings.AimbotFOVTransparency * 100,
        Min = 0,
        Max = 100,
        Float = 5,
        Flag = "Aimbot_FOVTransparency",
        Callback = function(value)
            ESPSettings.AimbotFOVTransparency = value / 100
            saveConfigToFile()
        end
    }

    local visualSection = aimbotTab:Section{
        Name = "Visuals",
        Side = "Right"
    }

    visualSection:Toggle{
        Name = "Show Target Info",
        Flag = "Aimbot_ShowTargetInfo",
        Default = ESPSettings.AimbotShowTargetInfo,
        Callback = function(value)
            ESPSettings.AimbotShowTargetInfo = value
            saveConfigToFile()
        end
    }

    local configTab = main:Tab("Config")

    local configSection = configTab:Section{
        Name = "Configuration",
        Side = "Left"
    }

    configSection:Button{
        Name = "Save Config",
        Callback = function()
            saveConfigToFile()
        end
    }

    local uiSection = configTab:Section{
        Name = "UI Settings",
        Side = "Right"
    }

    local savedToggleKey
    local successToggle, toggleResult = pcall(function()
        return ESPSettings.UIToggleKey and Enum.KeyCode[ESPSettings.UIToggleKey]
    end)
    if successToggle and toggleResult then
        savedToggleKey = toggleResult
    else
        savedToggleKey = Enum.KeyCode.Insert
    end
    uiSection:Keybind{
        Name = "Toggle UI",
        Flag = "UI_Toggle",
        Default = savedToggleKey,
        Blacklist = {Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3},
        Callback = function(key, fromsetting)
            if fromsetting then
                ESPSettings.UIToggleKey = key.Name
                saveConfigToFile()
            else
                library:Close()
            end
        end
    }

    uiSection:Button{
        Name = "Unload Script",
        Callback = function()
            CleanupResources()
            library:Unload()
        end
    }

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

TrackConnection(RunService.RenderStepped:Connect(function()
    local now = time()
    if now - LastUpdate < UPDATE_INTERVAL then
        return
    end
    LastUpdate = now

    local toRemove = {}
    for model, data in pairs(TrackedModels) do
        if not UpdateESP(model, data) then
            table.insert(toRemove, model)
        end
    end

    for _, model in ipairs(toRemove) do
        RemoveESP(model)
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
    table.clear(OverlayPool)
    OverlayRoot = nil
    state.OverlayRoot = nil
    LastUpdate = 0

    for _, connection in ipairs(state.Connections) do
        if connection.Disconnect then
            connection:Disconnect()
        end
    end
    table.clear(state.Connections)

    if ScreenGuiRef then
        ScreenGuiRef:Destroy()
        ScreenGuiRef = nil
    end
    state.ScreenGui = nil
    table.clear(ColorDisplays)

    if library then
        pcall(function()
            library:Unload()
        end)
        library = nil
    end
    state.Library = nil

    state.Active = false
end

state.Cleanup = CleanupResources