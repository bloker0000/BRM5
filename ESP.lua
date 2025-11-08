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
if previousState.Active then
	local prevCleanup = previousState.Cleanup
	if typeof(prevCleanup) == "function" then
		local ok, err = pcall(prevCleanup)
		if not ok then
			warn("Previous ESP cleanup failed:", err)
		end
	end
	globalEnv.BRM5_ESP = {}
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

local UPDATE_INTERVAL = 0.05
local MIN_DISTANCE = 15

local ESPSettings = {
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
}

local Theme = {
	Background = Color3.fromRGB(26, 22, 16),
	Panel = Color3.fromRGB(32, 26, 18),
	Header = Color3.fromRGB(45, 36, 24),
	Border = Color3.fromRGB(120, 94, 52),
	TextPrimary = Color3.fromRGB(255, 236, 190),
	TextSecondary = Color3.fromRGB(240, 215, 160),
	ControlBackground = Color3.fromRGB(54, 42, 26),
	ControlBorder = Color3.fromRGB(94, 74, 42),
	ToggleOn = Color3.fromRGB(255, 210, 90),
	ToggleOff = Color3.fromRGB(110, 82, 46),
	Accent = Color3.fromRGB(255, 196, 72),
	AccentDark = Color3.fromRGB(210, 150, 50),
	Shadow = Color3.fromRGB(18, 14, 10),
}

local state = {
	Connections = {},
	Active = true,
}

globalEnv.BRM5_ESP = state

local TrackedModels = {}
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
	highlight.OutlineTransparency = ESPSettings.OutlineEnabled and math.clamp(ESPSettings.OutlineTransparency, 0, 1) or 1
	highlight.Enabled = true
end

local function CreateHighlight(model)
	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = CoreGui
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
	infoLabel.BackgroundColor3 = Theme.Header
	infoLabel.BackgroundTransparency = 0.15
	infoLabel.BorderSizePixel = 0
	infoLabel.Text = ""
	infoLabel.TextColor3 = Theme.TextPrimary
	infoLabel.Font = Enum.Font.Arcade
	infoLabel.TextScaled = true
	infoLabel.Visible = false
	infoLabel.ZIndex = 42
	infoLabel.Parent = overlayFrame

	local infoPadding = Instance.new("UIPadding")
	infoPadding.PaddingLeft = UDim.new(0, 6)
	infoPadding.PaddingRight = UDim.new(0, 6)
	infoPadding.Parent = infoLabel

	local infoConstraint = Instance.new("UITextSizeConstraint")
	infoConstraint.MinTextSize = 10
	infoConstraint.MaxTextSize = 22
	infoConstraint.Parent = infoLabel

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
		InfoConstraint = infoConstraint,
		HealthFrame = healthFrame,
		HealthFill = healthFill,
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
	if entry.InfoConstraint then
		entry.InfoConstraint.MaxTextSize = 22
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

	local offsets = {
		Vector3.new(-half.X, -half.Y, -half.Z),
		Vector3.new(-half.X, -half.Y, half.Z),
		Vector3.new(-half.X, half.Y, -half.Z),
		Vector3.new(-half.X, half.Y, half.Z),
		Vector3.new(half.X, -half.Y, -half.Z),
		Vector3.new(half.X, -half.Y, half.Z),
		Vector3.new(half.X, half.Y, -half.Z),
		Vector3.new(half.X, half.Y, half.Z),
	}

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

	if not processed or not anyVisible or minX == math.huge or minY == math.huge or maxX == -math.huge or maxY == -math.huge then
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
		Height = height,
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
		if highlight.Adornee ~= model then
			highlight.Adornee = model
		end
		ApplyHighlightSettings(highlight, data.EntityType)
	end

	if not overlayEntry then
		return true
	end

	local showOverlay = ESPSettings.Show2DBox or ESPSettings.ShowDistance or ESPSettings.ShowHealth or ESPSettings.ShowEntityType
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

	local minBoxWidth = 36
	local minBoxHeight = 60

	if boxWidth < minBoxWidth then
		local delta = (minBoxWidth - boxWidth) * 0.5
		boxX = boxX - delta
		boxWidth = minBoxWidth
	end

	if boxHeight < minBoxHeight then
		local delta = (minBoxHeight - boxHeight) * 0.5
		boxY = boxY - delta
		boxHeight = minBoxHeight
	end

	overlayEntry.Overlay.Visible = true
	overlayEntry.Overlay.Position = UDim2.fromOffset(boxX, boxY)
	overlayEntry.Overlay.Size = UDim2.fromOffset(boxWidth, boxHeight)

	local boxFrame = overlayEntry.BoxFrame
	if boxFrame then
		boxFrame.Visible = ESPSettings.Show2DBox
		boxFrame.BorderColor3 = Theme.Border
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
			local infoHeight = math.clamp(boxHeight * 0.22, 14, 24)
			infoLabel.Visible = true
			infoLabel.Size = UDim2.fromOffset(boxWidth, infoHeight)
			infoLabel.Position = UDim2.new(0, 0, 0, -math.floor(infoHeight + 6))
			infoLabel.Text = infoText
			infoLabel.TextColor3 = Theme.TextPrimary
			infoLabel.BackgroundColor3 = Theme.Header
			infoLabel.BackgroundTransparency = 0.15
			infoLabel.TextXAlignment = Enum.TextXAlignment.Center
			infoLabel.TextYAlignment = Enum.TextYAlignment.Center
			if overlayEntry.InfoConstraint then
				overlayEntry.InfoConstraint.MaxTextSize = math.max(12, math.floor(infoHeight * 0.75))
			end
		else
			infoLabel.Visible = false
		end
	end

	local healthFrame = overlayEntry.HealthFrame
	local healthFill = overlayEntry.HealthFill
	if healthFrame and healthFill then
		if ESPSettings.ShowHealth then
			healthFrame.Visible = true
			local healthWidth = 8
			local spacing = 6
			local preferredX = -healthWidth - spacing
			if boxX + preferredX < 0 then
				preferredX = boxWidth + spacing
			elseif viewportSize and (boxX + preferredX + healthWidth) > viewportSize.X then
				preferredX = boxWidth + spacing
			end
			healthFrame.Position = UDim2.new(0, preferredX, 0, 2)
			healthFrame.Size = UDim2.new(0, healthWidth, 1, -4)
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

	local entityType = DetermineEntityType(model)
	local highlight = CreateHighlight(model)
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
		OverlayEntry = overlayEntry,
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
				overlayEntry.InfoLabel.BackgroundColor3 = Theme.Header
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

local function CreateGUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ESPGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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
	table.clear(ColorDisplays)

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 280, 0, 388)
	mainFrame.Position = UDim2.new(0.03, 0, 0.24, 0)
	mainFrame.BackgroundColor3 = Theme.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Active = true
	mainFrame.Draggable = true
	mainFrame.ZIndex = 200
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 10)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Thickness = 1
	mainStroke.Color = Theme.Border
	mainStroke.Parent = mainFrame

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 34)
	titleBar.BackgroundColor3 = Theme.Header
	titleBar.BorderSizePixel = 0
	titleBar.Parent = mainFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0.75, 0, 1, 0)
	titleLabel.Position = UDim2.new(0.05, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.Arcade
	titleLabel.TextSize = 20
	titleLabel.TextColor3 = Theme.TextPrimary
	titleLabel.Text = "BRM5 ESP"
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleButton"
	toggleButton.Size = UDim2.new(0, 26, 0, 26)
	toggleButton.Position = UDim2.new(1, -34, 0.12, 0)
	toggleButton.AutoButtonColor = false
	toggleButton.BackgroundColor3 = Theme.ControlBackground
	toggleButton.BorderSizePixel = 0
	toggleButton.Font = Enum.Font.Arcade
	toggleButton.TextSize = 18
	toggleButton.TextColor3 = Theme.TextPrimary
	toggleButton.Text = "-"
	toggleButton.Parent = titleBar

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 6)
	toggleCorner.Parent = toggleButton

	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "ContentFrame"
	contentFrame.Size = UDim2.new(1, -16, 1, -52)
	contentFrame.Position = UDim2.new(0, 8, 0, 42)
	contentFrame.BackgroundColor3 = Theme.Panel
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 4
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.ClipsDescendants = true
	contentFrame.Parent = mainFrame

	local contentCorner = Instance.new("UICorner")
	contentCorner.CornerRadius = UDim.new(0, 8)
	contentCorner.Parent = contentFrame

	local contentStroke = Instance.new("UIStroke")
	contentStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	contentStroke.Color = Theme.ControlBorder
	contentStroke.Thickness = 1
	contentStroke.Parent = contentFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = contentFrame

	local function CreateToggle(name, property, order, callback)
		local toggleFrame = Instance.new("Frame")
		toggleFrame.Name = name
		toggleFrame.Size = UDim2.new(1, -8, 0, 26)
		toggleFrame.BackgroundTransparency = 1
		toggleFrame.LayoutOrder = order
		toggleFrame.Parent = contentFrame

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.7, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.TextSize = 16
		label.TextColor3 = Theme.TextPrimary
		label.Text = name
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = toggleFrame

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 54, 0, 24)
		button.Position = UDim2.new(1, -60, 0.5, -12)
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Font = Enum.Font.Arcade
		button.TextSize = 16
		button.Parent = toggleFrame

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button

		local function applyToggleVisual(state)
			button.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
			button.TextColor3 = state and Theme.Shadow or Theme.TextPrimary
			button.Text = state and "ON" or "OFF"
		end

		applyToggleVisual(ESPSettings[property])

		TrackConnection(button.MouseButton1Click:Connect(function()
			ESPSettings[property] = not ESPSettings[property]
			applyToggleVisual(ESPSettings[property])
			if callback then
				callback()
			end
		end))
	end

	local function CreateSlider(name, property, minValue, maxValue, order, formatter, callback)
		local sliderFrame = Instance.new("Frame")
		sliderFrame.Name = name
		sliderFrame.Size = UDim2.new(1, -8, 0, 46)
		sliderFrame.BackgroundTransparency = 1
		sliderFrame.LayoutOrder = order
		sliderFrame.Parent = contentFrame

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.TextSize = 15
		label.TextColor3 = Theme.TextSecondary
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = name .. ": " .. (formatter and formatter(ESPSettings[property]) or tostring(ESPSettings[property]))
		label.Parent = sliderFrame

		local sliderBack = Instance.new("Frame")
		sliderBack.Size = UDim2.new(1, 0, 0, 18)
		sliderBack.Position = UDim2.new(0, 0, 0, 24)
		sliderBack.BackgroundColor3 = Theme.ControlBackground
		sliderBack.BorderSizePixel = 0
		sliderBack.Parent = sliderFrame

		local sliderCorner = Instance.new("UICorner")
		sliderCorner.CornerRadius = UDim.new(0, 8)
		sliderCorner.Parent = sliderBack

		local sliderStroke = Instance.new("UIStroke")
		sliderStroke.Color = Theme.ControlBorder
		sliderStroke.Thickness = 1
		sliderStroke.Parent = sliderBack

		local sliderFill = Instance.new("Frame")
		sliderFill.Size = UDim2.new((ESPSettings[property] - minValue) / (maxValue - minValue), 0, 1, 0)
		sliderFill.BackgroundColor3 = Theme.Accent
		sliderFill.BorderSizePixel = 0
		sliderFill.Parent = sliderBack

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 8)
		fillCorner.Parent = sliderFill

		local dragging = false

		local function UpdateSlider(inputX)
			local ratio = math.clamp((inputX - sliderBack.AbsolutePosition.X) / sliderBack.AbsoluteSize.X, 0, 1)
			local value = minValue + (maxValue - minValue) * ratio
			if property == "FillTransparency" or property == "OutlineTransparency" then
				value = math.floor(value * 100 + 0.5) / 100
			else
				value = math.floor(value + 0.5)
			end
			ESPSettings[property] = value
			sliderFill.Size = UDim2.new((value - minValue) / (maxValue - minValue), 0, 1, 0)
			label.Text = name .. ": " .. (formatter and formatter(value) or tostring(value))
			if callback then
				callback()
			end
		end

		TrackConnection(sliderBack.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				UpdateSlider(input.Position.X)
			end
		end))

		TrackConnection(sliderBack.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end))

		TrackConnection(UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				UpdateSlider(input.Position.X)
			end
		end))
	end

	local colorPickerModal = {
		Frame = nil,
		Hue = 0,
		Saturation = 0,
		Value = 0,
		InitialColor = nil,
		Property = nil,
		Entry = nil,
		ActiveSlider = nil,
		Preview = nil,
		HexPreview = nil,
		HueHandle = nil,
		SaturationHandle = nil,
		ValueHandle = nil,
		HueGradient = nil,
		SaturationGradient = nil,
		ValueGradient = nil,
		HueValueLabel = nil,
		SaturationValueLabel = nil,
		ValueValueLabel = nil,
	}

	local function updateHSVValueLabels()
		if colorPickerModal.HueValueLabel then
			colorPickerModal.HueValueLabel.Text = string.format("%3d°", math.floor(colorPickerModal.Hue * 360 + 0.5))
		end
		if colorPickerModal.SaturationValueLabel then
			colorPickerModal.SaturationValueLabel.Text = string.format("%d%%", math.floor(colorPickerModal.Saturation * 100 + 0.5))
		end
		if colorPickerModal.ValueValueLabel then
			colorPickerModal.ValueValueLabel.Text = string.format("%d%%", math.floor(colorPickerModal.Value * 100 + 0.5))
		end
	end

	local function updateHSVHandles()
		if colorPickerModal.HueHandle then
			colorPickerModal.HueHandle.Position = UDim2.new(colorPickerModal.Hue, 0, 0.5, 0)
		end
		if colorPickerModal.SaturationHandle then
			colorPickerModal.SaturationHandle.Position = UDim2.new(colorPickerModal.Saturation, 0, 0.5, 0)
		end
		if colorPickerModal.ValueHandle then
			colorPickerModal.ValueHandle.Position = UDim2.new(colorPickerModal.Value, 0, 0.5, 0)
		end
	end

	local function updateHSVGradients()
		if colorPickerModal.HueGradient then
			colorPickerModal.HueGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			})
		end
		if colorPickerModal.SaturationGradient then
			local brightness = math.max(colorPickerModal.Value, 0.05)
			colorPickerModal.SaturationGradient.Color = ColorSequence.new(
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(colorPickerModal.Hue, 1, brightness))
			)
		end
		if colorPickerModal.ValueGradient then
			local vivid = Color3.fromHSV(colorPickerModal.Hue, colorPickerModal.Saturation, 1)
			colorPickerModal.ValueGradient.Color = ColorSequence.new(
				ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
				ColorSequenceKeypoint.new(1, vivid)
			)
		end
	end

	local function applyColorFromHSV(applySettings)
		local newColor = Color3.fromHSV(colorPickerModal.Hue, colorPickerModal.Saturation, colorPickerModal.Value)
		if colorPickerModal.Preview then
			colorPickerModal.Preview.BackgroundColor3 = newColor
		end
		if colorPickerModal.HexPreview then
			colorPickerModal.HexPreview.Text = "#" .. string.upper(newColor:ToHex())
		end
		if applySettings and colorPickerModal.Property then
			ESPSettings[colorPickerModal.Property] = newColor
			RefreshAllVisuals()
		end
	end

	local function setHue(value, applySettings)
		colorPickerModal.Hue = math.clamp(value, 0, 1)
		updateHSVHandles()
		updateHSVGradients()
		updateHSVValueLabels()
		applyColorFromHSV(applySettings)
	end

	local function setSaturation(value, applySettings)
		colorPickerModal.Saturation = math.clamp(value, 0, 1)
		updateHSVHandles()
		updateHSVGradients()
		updateHSVValueLabels()
		applyColorFromHSV(applySettings)
	end

	local function setValue(value, applySettings)
		colorPickerModal.Value = math.clamp(value, 0, 1)
		updateHSVHandles()
		updateHSVGradients()
		updateHSVValueLabels()
		applyColorFromHSV(applySettings)
	end

	local function ensureColorPickerModal()
		if colorPickerModal.Frame then
			return
		end

		local modalFrame = Instance.new("Frame")
		modalFrame.Name = "ColorPicker"
		modalFrame.Size = UDim2.new(0, 252, 0, 244)
		modalFrame.Position = UDim2.new(0, 14, 0, 222)
		modalFrame.BackgroundColor3 = Theme.Panel
		modalFrame.BorderSizePixel = 0
		modalFrame.Visible = false
		modalFrame.ZIndex = 50
		modalFrame.Parent = mainFrame

		local modalCorner = Instance.new("UICorner")
		modalCorner.CornerRadius = UDim.new(0, 10)
		modalCorner.Parent = modalFrame

		local modalStroke = Instance.new("UIStroke")
		modalStroke.Color = Theme.ControlBorder
		modalStroke.Thickness = 1
		modalStroke.Parent = modalFrame

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Size = UDim2.new(1, -48, 0, 24)
		titleLabel.Position = UDim2.new(0, 16, 0, 10)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.Arcade
		titleLabel.TextSize = 18
		titleLabel.TextColor3 = Theme.TextPrimary
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Text = "Color Picker"
		titleLabel.ZIndex = 51
		titleLabel.Parent = modalFrame

		local closeButton = Instance.new("TextButton")
		closeButton.Size = UDim2.new(0, 26, 0, 26)
		closeButton.Position = UDim2.new(1, -34, 0, 8)
		closeButton.BackgroundColor3 = Theme.ControlBackground
		closeButton.AutoButtonColor = false
		closeButton.BorderSizePixel = 0
		closeButton.Font = Enum.Font.Arcade
		closeButton.TextSize = 16
		closeButton.TextColor3 = Theme.TextPrimary
		closeButton.Text = "X"
		closeButton.ZIndex = 51
		closeButton.Parent = modalFrame

		local closeCorner = Instance.new("UICorner")
		closeCorner.CornerRadius = UDim.new(0, 6)
		closeCorner.Parent = closeButton

		local previewFrame = Instance.new("Frame")
		previewFrame.Size = UDim2.new(0, 74, 0, 74)
		previewFrame.Position = UDim2.new(0, 16, 0, 46)
		previewFrame.BackgroundColor3 = Theme.Accent
		previewFrame.BorderSizePixel = 0
		previewFrame.ZIndex = 51
		previewFrame.Parent = modalFrame

		local previewCorner = Instance.new("UICorner")
		previewCorner.CornerRadius = UDim.new(0, 10)
		previewCorner.Parent = previewFrame

		local hexLabel = Instance.new("TextLabel")
		hexLabel.Size = UDim2.new(0, 120, 0, 20)
		hexLabel.Position = UDim2.new(0, 102, 0, 56)
		hexLabel.BackgroundTransparency = 1
		hexLabel.Font = Enum.Font.Code
		hexLabel.TextSize = 14
		hexLabel.TextXAlignment = Enum.TextXAlignment.Left
		hexLabel.TextColor3 = Theme.TextPrimary
		hexLabel.Text = "#FFFFFF"
		hexLabel.ZIndex = 51
		hexLabel.Parent = modalFrame

		local infoLabel = Instance.new("TextLabel")
		infoLabel.Size = UDim2.new(0, 120, 0, 16)
		infoLabel.Position = UDim2.new(0, 102, 0, 78)
		infoLabel.BackgroundTransparency = 1
		infoLabel.Font = Enum.Font.Arcade
		infoLabel.TextSize = 13
		infoLabel.TextColor3 = Theme.TextSecondary
		infoLabel.TextXAlignment = Enum.TextXAlignment.Left
		infoLabel.Text = "click + drag"
		infoLabel.ZIndex = 51
		infoLabel.Parent = modalFrame

		local function createHSVSlider(displayName, order)
			local wrapper = Instance.new("Frame")
			wrapper.Size = UDim2.new(1, -32, 0, 40)
			wrapper.Position = UDim2.new(0, 16, 0, 124 + (order - 1) * 44)
			wrapper.BackgroundTransparency = 1
			wrapper.ZIndex = 51
			wrapper.Parent = modalFrame

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.32, 0, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.Arcade
			nameLabel.TextSize = 14
			nameLabel.TextColor3 = Theme.TextSecondary
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = displayName
			nameLabel.ZIndex = 51
			nameLabel.Parent = wrapper

			local valueLabel = Instance.new("TextLabel")
			valueLabel.Size = UDim2.new(0, 60, 1, 0)
			valueLabel.Position = UDim2.new(1, -60, 0, 0)
			valueLabel.BackgroundTransparency = 1
			valueLabel.Font = Enum.Font.Code
			valueLabel.TextSize = 13
			valueLabel.TextColor3 = Theme.TextPrimary
			valueLabel.TextXAlignment = Enum.TextXAlignment.Right
			valueLabel.Text = ""
			valueLabel.ZIndex = 51
			valueLabel.Parent = wrapper

			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0.56, 0, 0, 16)
			bar.Position = UDim2.new(0.36, 0, 0.5, -8)
			bar.BackgroundColor3 = Theme.ControlBackground
			bar.BorderSizePixel = 0
			bar.ZIndex = 51
			bar.Parent = wrapper

			local barCorner = Instance.new("UICorner")
			barCorner.CornerRadius = UDim.new(0, 8)
			barCorner.Parent = bar

			local barStroke = Instance.new("UIStroke")
			barStroke.Color = Theme.ControlBorder
			barStroke.Thickness = 1
			barStroke.Parent = bar

			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 0
			gradient.Parent = bar

			local handle = Instance.new("Frame")
			handle.Size = UDim2.new(0, 8, 1.2, 0)
			handle.AnchorPoint = Vector2.new(0.5, 0.5)
			handle.Position = UDim2.new(0, 0, 0.5, 0)
			handle.BackgroundColor3 = Theme.TextPrimary
			handle.BorderSizePixel = 0
			handle.ZIndex = 52
			handle.Parent = bar

			local handleCorner = Instance.new("UICorner")
			handleCorner.CornerRadius = UDim.new(0, 3)
			handleCorner.Parent = handle

			return bar, handle, gradient, valueLabel
		end

		colorPickerModal.HueGradient = nil
		colorPickerModal.SaturationGradient = nil
		colorPickerModal.ValueGradient = nil
		colorPickerModal.HueHandle = nil
		colorPickerModal.SaturationHandle = nil
		colorPickerModal.ValueHandle = nil

		local hueBar, hueHandle, hueGradient, hueValueLabel = createHSVSlider("Hue", 1)
		local satBar, satHandle, satGradient, satValueLabel = createHSVSlider("Saturation", 2)
		local valBar, valHandle, valGradient, valValueLabel = createHSVSlider("Value", 3)

		colorPickerModal.HueGradient = hueGradient
		colorPickerModal.SaturationGradient = satGradient
		colorPickerModal.ValueGradient = valGradient
		colorPickerModal.HueHandle = hueHandle
		colorPickerModal.SaturationHandle = satHandle
		colorPickerModal.ValueHandle = valHandle
		colorPickerModal.HueValueLabel = hueValueLabel
		colorPickerModal.SaturationValueLabel = satValueLabel
		colorPickerModal.ValueValueLabel = valValueLabel

		local function attachSlider(bar, setter)
			TrackConnection(bar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					colorPickerModal.ActiveSlider = {
						Bar = bar,
						Setter = setter,
					}
					if bar.AbsoluteSize.X > 0 then
						local ratio = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
						setter(ratio, true)
					end
				end
			end))

			TrackConnection(bar.InputEnded:Connect(function(input)
				if colorPickerModal.ActiveSlider and colorPickerModal.ActiveSlider.Bar == bar and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					colorPickerModal.ActiveSlider = nil
				end
			end))
		end

		attachSlider(hueBar, setHue)
		attachSlider(satBar, setSaturation)
		attachSlider(valBar, setValue)

		TrackConnection(UserInputService.InputChanged:Connect(function(input)
			if not colorPickerModal.ActiveSlider then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local bar = colorPickerModal.ActiveSlider.Bar
			if not bar or bar.AbsoluteSize.X <= 0 then
				return
			end
			local ratio = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			colorPickerModal.ActiveSlider.Setter(ratio, true)
		end))

		TrackConnection(UserInputService.InputEnded:Connect(function(input)
			if colorPickerModal.ActiveSlider and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				colorPickerModal.ActiveSlider = nil
			end
		end))

		local applyButton = Instance.new("TextButton")
		applyButton.Size = UDim2.new(0.45, 0, 0, 28)
		applyButton.Position = UDim2.new(0.05, 0, 1, -36)
		applyButton.BackgroundColor3 = Theme.Accent
		applyButton.AutoButtonColor = false
		applyButton.BorderSizePixel = 0
		applyButton.Font = Enum.Font.Arcade
		applyButton.TextSize = 16
		applyButton.TextColor3 = Theme.Shadow
		applyButton.Text = "Apply"
		applyButton.ZIndex = 51
		applyButton.Parent = modalFrame

		local applyCorner = Instance.new("UICorner")
		applyCorner.CornerRadius = UDim.new(0, 8)
		applyCorner.Parent = applyButton

		local cancelButton = Instance.new("TextButton")
		cancelButton.Size = UDim2.new(0.45, 0, 0, 28)
		cancelButton.Position = UDim2.new(0.5, 0, 1, -36)
		cancelButton.BackgroundColor3 = Theme.ControlBackground
		cancelButton.AutoButtonColor = false
		cancelButton.BorderSizePixel = 0
		cancelButton.Font = Enum.Font.Arcade
		cancelButton.TextSize = 16
		cancelButton.TextColor3 = Theme.TextPrimary
		cancelButton.Text = "Cancel"
		cancelButton.ZIndex = 51
		cancelButton.Parent = modalFrame

		local cancelCorner = Instance.new("UICorner")
		cancelCorner.CornerRadius = UDim.new(0, 8)
		cancelCorner.Parent = cancelButton

		colorPickerModal.Frame = modalFrame
		colorPickerModal.Preview = previewFrame
		colorPickerModal.HexPreview = hexLabel

		TrackConnection(closeButton.MouseButton1Click:Connect(function()
			if colorPickerModal.Property then
				ESPSettings[colorPickerModal.Property] = colorPickerModal.InitialColor
				RefreshAllVisuals()
			end
			colorPickerModal.Property = nil
			colorPickerModal.Entry = nil
			colorPickerModal.ActiveSlider = nil
			colorPickerModal.InitialColor = nil
			modalFrame.Visible = false
		end))

		TrackConnection(cancelButton.MouseButton1Click:Connect(function()
			if colorPickerModal.Property then
				ESPSettings[colorPickerModal.Property] = colorPickerModal.InitialColor
				RefreshAllVisuals()
			end
			colorPickerModal.Property = nil
			colorPickerModal.Entry = nil
			colorPickerModal.ActiveSlider = nil
			colorPickerModal.InitialColor = nil
			modalFrame.Visible = false
		end))

		TrackConnection(applyButton.MouseButton1Click:Connect(function()
			colorPickerModal.Property = nil
			colorPickerModal.Entry = nil
			colorPickerModal.ActiveSlider = nil
			colorPickerModal.InitialColor = nil
			modalFrame.Visible = false
		end))
	end

	local function openColorPicker(property, entry)
		ensureColorPickerModal()
		colorPickerModal.Property = property
		colorPickerModal.Entry = entry
		colorPickerModal.InitialColor = ESPSettings[property]
		colorPickerModal.Frame.Visible = true
		colorPickerModal.Frame.ZIndex = 50
		colorPickerModal.ActiveSlider = nil
		local frameHeight = colorPickerModal.Frame.Size.Y.Offset
		local parentHeight = mainFrame.AbsoluteSize.Y
		local yOffset = math.max(40, parentHeight - frameHeight - 20)
		colorPickerModal.Frame.Position = UDim2.new(0, 14, 0, yOffset)

		local h, s, v = ESPSettings[property]:ToHSV()
		setHue(h, false)
		setSaturation(s, false)
		setValue(v, false)
		updateHSVHandles()
		updateHSVGradients()
		updateHSVValueLabels()
		applyColorFromHSV(false)
	end

	local function CreateColorPicker(name, property, order, _)
		local pickerFrame = Instance.new("Frame")
		pickerFrame.Name = name
		pickerFrame.Size = UDim2.new(1, -8, 0, 54)
		pickerFrame.BackgroundTransparency = 1
		pickerFrame.LayoutOrder = order
		pickerFrame.Parent = contentFrame

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.6, 0, 0, 22)
		label.Position = UDim2.new(0, 0, 0, 2)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.TextSize = 15
		label.TextColor3 = Theme.TextSecondary
		label.Text = name
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = pickerFrame

		local hexLabel = Instance.new("TextLabel")
		hexLabel.Size = UDim2.new(0.6, 0, 0, 20)
		hexLabel.Position = UDim2.new(0, 0, 0, 28)
		hexLabel.BackgroundTransparency = 1
		hexLabel.Font = Enum.Font.Code
		hexLabel.TextSize = 13
		hexLabel.TextColor3 = Theme.TextPrimary
		hexLabel.TextXAlignment = Enum.TextXAlignment.Left
		hexLabel.Text = "#" .. string.upper(ESPSettings[property]:ToHex())
		hexLabel.Parent = pickerFrame

		local swatchButton = Instance.new("TextButton")
		swatchButton.Size = UDim2.new(0, 66, 0, 38)
		swatchButton.Position = UDim2.new(1, -70, 0.5, -19)
		swatchButton.AutoButtonColor = false
		swatchButton.BackgroundColor3 = ESPSettings[property]
		swatchButton.BorderSizePixel = 0
		swatchButton.Text = ""
		swatchButton.Parent = pickerFrame

		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(0, 10)
		swatchCorner.Parent = swatchButton

		local swatchStroke = Instance.new("UIStroke")
		swatchStroke.Color = Theme.ControlBorder
		swatchStroke.Thickness = 1
		swatchStroke.Parent = swatchButton

		local entry = {
			Swatch = swatchButton,
			HexLabel = hexLabel,
		}
		ColorDisplays[property] = entry

		TrackConnection(swatchButton.MouseButton1Click:Connect(function()
			openColorPicker(property, entry)
		end))
	end

	CreateToggle("ESP Enabled", "Enabled", 1, RefreshAllVisuals)
	CreateToggle("Chams", "ChamsEnabled", 2, RefreshAllVisuals)
	CreateToggle("Outline", "OutlineEnabled", 3, RefreshAllVisuals)
	CreateToggle("2D Box", "Show2DBox", 4, RefreshAllVisuals)
	CreateToggle("Distance", "ShowDistance", 5, RefreshAllVisuals)
	CreateToggle("Health Bar", "ShowHealth", 6, RefreshAllVisuals)
	CreateToggle("Entity Label", "ShowEntityType", 7, RefreshAllVisuals)

	CreateSlider("Max Distance", "MaxDistance", 100, 5000, 8, function(value)
		return string.format("%d st", value)
	end, nil)

	CreateSlider("Fill Transparency", "FillTransparency", 0, 1, 9, function(value)
		return string.format("%.2f", value)
	end, RefreshAllVisuals)

	CreateSlider("Outline Transparency", "OutlineTransparency", 0, 1, 10, function(value)
		return string.format("%.2f", value)
	end, RefreshAllVisuals)

	CreateColorPicker("Player Fill", "PlayerFillColor", 11, RefreshAllVisuals)
	CreateColorPicker("Player Outline", "PlayerOutlineColor", 12, RefreshAllVisuals)
	CreateColorPicker("Zombie Fill", "ZombieFillColor", 13, RefreshAllVisuals)
	CreateColorPicker("Zombie Outline", "ZombieOutlineColor", 14, RefreshAllVisuals)
	CreateColorPicker("Health Fill", "HealthBarFillColor", 15, RefreshAllVisuals)
	CreateColorPicker("Health Back", "HealthBarBackColor", 16, RefreshAllVisuals)

	local isMinimized = false
	TrackConnection(toggleButton.MouseButton1Click:Connect(function()
		isMinimized = not isMinimized
		contentFrame.Visible = not isMinimized
		mainFrame.Size = isMinimized and UDim2.new(0, 280, 0, 48) or UDim2.new(0, 280, 0, 388)
		if colorPickerModal.Frame then
			colorPickerModal.Frame.Visible = not isMinimized and colorPickerModal.Property ~= nil
		end
		toggleButton.Text = isMinimized and "+" or "-"
		toggleButton.BackgroundColor3 = isMinimized and Theme.Accent or Theme.ControlBackground
		toggleButton.TextColor3 = isMinimized and Theme.Shadow or Theme.TextPrimary
	end))

	return screenGui
end

CreateGUI()
ScanWorkspace()

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
end))

TrackConnection(LocalPlayer.CharacterRemoving:Connect(function()
	CleanupTrackedModels()
end))

TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
	task.defer(ScanWorkspace)
end))

local function CleanupResources()
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

	state.Active = false
end

state.Cleanup = CleanupResources