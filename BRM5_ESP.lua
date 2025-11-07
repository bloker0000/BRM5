local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local ESP = {}
ESP.__index = ESP

function ESP.new()
    local self = setmetatable({}, ESP)
    
    self.PlayerESPEnabled = false
    self.ZombieESPEnabled = false
    
    self.PlayerChamsEnabled = false
    self.ZombieChamsEnabled = false
    
    self.PlayerTransparency = 0.5
    self.ZombieTransparency = 0.5
    
    self.PlayerColor = Color3.fromRGB(0, 255, 0)
    self.ZombieColor = Color3.fromRGB(255, 0, 0)
    
    self.PlayerOutlineEnabled = true
    self.ZombieOutlineEnabled = true
    
    self.PlayerMaxDistance = 1000
    self.ZombieMaxDistance = 1000
    
    self.TrackedPlayers = {}
    self.TrackedZombies = {}
    
    self.UpdateConnection = nil
    
    self:StartTracking()
    
    return self
end

function ESP:CreateHighlight(model, color, transparency, outline)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPHighlight"
    highlight.Adornee = model
    highlight.FillColor = color
    highlight.FillTransparency = transparency
    highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
    highlight.OutlineTransparency = outline and 0 or 1
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = model
    
    return highlight
end

function ESP:CreateChams(model, color, transparency, outline)
    local chams = {}
    
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") or part:IsA("MeshPart") then
            local chamClone = part:Clone()
            chamClone.Name = "ChamPart"
            chamClone.CanCollide = false
            chamClone.Anchored = false
            chamClone.Massless = true
            chamClone.CastShadow = false
            chamClone.Material = Enum.Material.ForceField
            chamClone.Color = color
            chamClone.Transparency = transparency
            
            for _, child in ipairs(chamClone:GetChildren()) do
                if not child:IsA("SpecialMesh") then
                    child:Destroy()
                end
            end
            
            local weld = Instance.new("Weld")
            weld.Part0 = part
            weld.Part1 = chamClone
            weld.C0 = CFrame.new()
            weld.C1 = CFrame.new()
            weld.Parent = chamClone
            
            chamClone.Parent = part
            
            table.insert(chams, chamClone)
            
            if outline then
                local selectionBox = Instance.new("SelectionBox")
                selectionBox.Name = "ChamOutline"
                selectionBox.Adornee = chamClone
                selectionBox.LineThickness = 0.05
                selectionBox.Color3 = Color3.fromRGB(0, 0, 0)
                selectionBox.Transparency = 0.5
                selectionBox.Parent = chamClone
            end
        end
    end
    
    return chams
end

function ESP:RemoveESP(model)
    for _, child in ipairs(model:GetDescendants()) do
        if child.Name == "ESPHighlight" then
            child:Destroy()
        elseif child.Name == "ChamPart" then
            child:Destroy()
        end
    end
end

function ESP:UpdatePlayerESP(model)
    if not model or not model:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local hrp = model.HumanoidRootPart
    local distance = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
    
    if distance > self.PlayerMaxDistance then
        self:RemoveESP(model)
        return
    end
    
    if self.PlayerChamsEnabled then
        if not model:FindFirstChild("ChamPart", true) then
            self:CreateChams(model, self.PlayerColor, self.PlayerTransparency, self.PlayerOutlineEnabled)
        else
            for _, part in ipairs(model:GetDescendants()) do
                if part.Name == "ChamPart" then
                    part.Color = self.PlayerColor
                    part.Transparency = self.PlayerTransparency
                    
                    local outline = part:FindFirstChild("ChamOutline")
                    if outline then
                        outline.Transparency = self.PlayerOutlineEnabled and 0.5 or 1
                    elseif self.PlayerOutlineEnabled then
                        local selectionBox = Instance.new("SelectionBox")
                        selectionBox.Name = "ChamOutline"
                        selectionBox.Adornee = part
                        selectionBox.LineThickness = 0.05
                        selectionBox.Color3 = Color3.fromRGB(0, 0, 0)
                        selectionBox.Transparency = 0.5
                        selectionBox.Parent = part
                    end
                end
            end
        end
    else
        for _, part in ipairs(model:GetDescendants()) do
            if part.Name == "ChamPart" then
                part:Destroy()
            end
        end
        
        local highlight = model:FindFirstChild("ESPHighlight")
        if not highlight then
            highlight = self:CreateHighlight(model, self.PlayerColor, self.PlayerTransparency, self.PlayerOutlineEnabled)
        else
            highlight.FillColor = self.PlayerColor
            highlight.FillTransparency = self.PlayerTransparency
            highlight.OutlineTransparency = self.PlayerOutlineEnabled and 0 or 1
        end
    end
end

function ESP:UpdateZombieESP(model)
    if not model or not model:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local hrp = model.HumanoidRootPart
    local distance = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
    
    if distance > self.ZombieMaxDistance then
        self:RemoveESP(model)
        return
    end
    
    if self.ZombieChamsEnabled then
        if not model:FindFirstChild("ChamPart", true) then
            self:CreateChams(model, self.ZombieColor, self.ZombieTransparency, self.ZombieOutlineEnabled)
        else
            for _, part in ipairs(model:GetDescendants()) do
                if part.Name == "ChamPart" then
                    part.Color = self.ZombieColor
                    part.Transparency = self.ZombieTransparency
                    
                    local outline = part:FindFirstChild("ChamOutline")
                    if outline then
                        outline.Transparency = self.ZombieOutlineEnabled and 0.5 or 1
                    elseif self.ZombieOutlineEnabled then
                        local selectionBox = Instance.new("SelectionBox")
                        selectionBox.Name = "ChamOutline"
                        selectionBox.Adornee = part
                        selectionBox.LineThickness = 0.05
                        selectionBox.Color3 = Color3.fromRGB(0, 0, 0)
                        selectionBox.Transparency = 0.5
                        selectionBox.Parent = part
                    end
                end
            end
        end
    else
        for _, part in ipairs(model:GetDescendants()) do
            if part.Name == "ChamPart" then
                part:Destroy()
            end
        end
        
        local highlight = model:FindFirstChild("ESPHighlight")
        if not highlight then
            highlight = self:CreateHighlight(model, self.ZombieColor, self.ZombieTransparency, self.ZombieOutlineEnabled)
        else
            highlight.FillColor = self.ZombieColor
            highlight.FillTransparency = self.ZombieTransparency
            highlight.OutlineTransparency = self.ZombieOutlineEnabled and 0 or 1
        end
    end
end

function ESP:FindPlayers()
    local players = {}
    
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name == "Male" and obj:IsA("Model") and obj:FindFirstChild("Humanoid") then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if obj ~= LocalPlayer.Character then
                    table.insert(players, obj)
                end
            end
        end
    end
    
    return players
end

function ESP:FindZombies()
    local zombies = {}
    
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name == "Zombie" and obj:IsA("Model") and obj:FindFirstChild("Humanoid") then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                table.insert(zombies, obj)
            end
        end
    end
    
    return zombies
end

function ESP:StartTracking()
    self.UpdateConnection = RunService.RenderStepped:Connect(function()
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            return
        end
        
        if self.PlayerESPEnabled then
            local players = self:FindPlayers()
            
            for _, player in ipairs(players) do
                if not self.TrackedPlayers[player] then
                    self.TrackedPlayers[player] = true
                end
                self:UpdatePlayerESP(player)
            end
            
            for trackedPlayer, _ in pairs(self.TrackedPlayers) do
                if not trackedPlayer.Parent then
                    self.TrackedPlayers[trackedPlayer] = nil
                elseif not table.find(players, trackedPlayer) then
                    self:RemoveESP(trackedPlayer)
                    self.TrackedPlayers[trackedPlayer] = nil
                end
            end
        else
            for player, _ in pairs(self.TrackedPlayers) do
                self:RemoveESP(player)
            end
            self.TrackedPlayers = {}
        end
        
        if self.ZombieESPEnabled then
            local zombies = self:FindZombies()
            
            for _, zombie in ipairs(zombies) do
                if not self.TrackedZombies[zombie] then
                    self.TrackedZombies[zombie] = true
                end
                self:UpdateZombieESP(zombie)
            end
            
            for trackedZombie, _ in pairs(self.TrackedZombies) do
                if not trackedZombie.Parent then
                    self.TrackedZombies[trackedZombie] = nil
                elseif not table.find(zombies, trackedZombie) then
                    self:RemoveESP(trackedZombie)
                    self.TrackedZombies[trackedZombie] = nil
                end
            end
        else
            for zombie, _ in pairs(self.TrackedZombies) do
                self:RemoveESP(zombie)
            end
            self.TrackedZombies = {}
        end
    end)
end

function ESP:SetPlayerESPEnabled(enabled)
    self.PlayerESPEnabled = enabled
    if not enabled then
        for player, _ in pairs(self.TrackedPlayers) do
            self:RemoveESP(player)
        end
        self.TrackedPlayers = {}
    end
end

function ESP:SetZombieESPEnabled(enabled)
    self.ZombieESPEnabled = enabled
    if not enabled then
        for zombie, _ in pairs(self.TrackedZombies) do
            self:RemoveESP(zombie)
        end
        self.TrackedZombies = {}
    end
end

function ESP:SetPlayerChamsEnabled(enabled)
    self.PlayerChamsEnabled = enabled
    for player, _ in pairs(self.TrackedPlayers) do
        self:RemoveESP(player)
    end
end

function ESP:SetZombieChamsEnabled(enabled)
    self.ZombieChamsEnabled = enabled
    for zombie, _ in pairs(self.TrackedZombies) do
        self:RemoveESP(zombie)
    end
end

function ESP:SetPlayerTransparency(value)
    self.PlayerTransparency = value
end

function ESP:SetZombieTransparency(value)
    self.ZombieTransparency = value
end

function ESP:SetPlayerColor(color)
    self.PlayerColor = color
end

function ESP:SetZombieColor(color)
    self.ZombieColor = color
end

function ESP:SetPlayerOutlineEnabled(enabled)
    self.PlayerOutlineEnabled = enabled
end

function ESP:SetZombieOutlineEnabled(enabled)
    self.ZombieOutlineEnabled = enabled
end

function ESP:SetPlayerMaxDistance(distance)
    self.PlayerMaxDistance = distance
end

function ESP:SetZombieMaxDistance(distance)
    self.ZombieMaxDistance = distance
end

function ESP:Cleanup()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
    end
    
    for player, _ in pairs(self.TrackedPlayers) do
        self:RemoveESP(player)
    end
    
    for zombie, _ in pairs(self.TrackedZombies) do
        self:RemoveESP(zombie)
    end
    
    self.TrackedPlayers = {}
    self.TrackedZombies = {}
end

local GUI = {}
GUI.__index = GUI

function GUI.new(espInstance)
    local self = setmetatable({}, GUI)
    self.ESP = espInstance
    self.ScreenGui = nil
    self.MainFrame = nil
    self.IsVisible = true
    self.IsDragging = false
    self.DragStart = nil
    self.StartPos = nil
    self.Notifications = {}
    
    return self
end

function GUI:CreateNotification(title, message, duration)
    duration = duration or 3
    
    if not self.ScreenGui then
        return
    end
    
    local notif = Instance.new("Frame")
    notif.Name = "Notification"
    notif.Size = UDim2.new(0, 300, 0, 80)
    notif.Position = UDim2.new(1, -320, 1, 100)
    notif.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    notif.BorderColor3 = Color3.fromRGB(60, 60, 60)
    notif.BorderSizePixel = 2
    notif.Parent = self.ScreenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = notif
    
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 25)
    titleBar.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = notif
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 6)
    titleCorner.Parent = titleBar
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -10, 1, 0)
    titleLabel.Position = UDim2.new(0, 5, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.CodeBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar
    
    local messageLabel = Instance.new("TextLabel")
    messageLabel.Size = UDim2.new(1, -10, 1, -30)
    messageLabel.Position = UDim2.new(0, 5, 0, 28)
    messageLabel.BackgroundTransparency = 1
    messageLabel.Text = message
    messageLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    messageLabel.TextSize = 11
    messageLabel.Font = Enum.Font.Code
    messageLabel.TextXAlignment = Enum.TextXAlignment.Left
    messageLabel.TextYAlignment = Enum.TextYAlignment.Top
    messageLabel.TextWrapped = true
    messageLabel.Parent = notif
    
    table.insert(self.Notifications, notif)
    
    local targetY = 1 - (#self.Notifications * 90) - 20
    notif:TweenPosition(
        UDim2.new(1, -320, 0, targetY),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Back,
        0.5,
        true
    )
    
    task.delay(duration, function()
        notif:TweenPosition(
            UDim2.new(1, 20, 0, targetY),
            Enum.EasingDirection.In,
            Enum.EasingStyle.Back,
            0.3,
            true,
            function()
                notif:Destroy()
                local index = table.find(self.Notifications, notif)
                if index then
                    table.remove(self.Notifications, index)
                end
                
                for i, n in ipairs(self.Notifications) do
                    local newY = 1 - (i * 90) - 20
                    n:TweenPosition(
                        UDim2.new(1, -320, 0, newY),
                        Enum.EasingDirection.Out,
                        Enum.EasingStyle.Quad,
                        0.3,
                        true
                    )
                end
            end
        )
    end)
end

function GUI:CreateScreenGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BRM5_ESP_GUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    local success = pcall(function()
        if gethui then
            screenGui.Parent = gethui()
        elseif syn and syn.protect_gui then
            syn.protect_gui(screenGui)
            screenGui.Parent = CoreGui
        else
            screenGui.Parent = CoreGui
        end
    end)
    
    if not success then
        screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    end
    
    return screenGui
end

function GUI:CreateMainFrame()
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 450, 0, 350)
    mainFrame.Position = UDim2.new(0.5, -225, 0.5, -175)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    mainFrame.BorderColor3 = Color3.fromRGB(60, 60, 60)
    mainFrame.BorderSizePixel = 2
    mainFrame.Active = true
    mainFrame.Draggable = false
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = mainFrame
    
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 4)
    titleCorner.Parent = titleBar
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -40, 1, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "BRM5 ESP - by Multyply"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.Code
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar
    
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 25, 0, 25)
    closeButton.Position = UDim2.new(1, -30, 0, 2.5)
    closeButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeButton.BorderSizePixel = 0
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextSize = 14
    closeButton.Font = Enum.Font.CodeBold
    closeButton.Parent = titleBar
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 3)
    closeCorner.Parent = closeButton
    
    closeButton.MouseButton1Click:Connect(function()
        self:ToggleVisibility()
    end)
    
    self:MakeDraggable(titleBar, mainFrame)
    
    return mainFrame
end

function GUI:MakeDraggable(handle, frame)
    local dragging = false
    local dragInput
    local dragStart
    local startPos
    
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

function GUI:CreateTabContainer()
    local tabContainer = Instance.new("Frame")
    tabContainer.Name = "TabContainer"
    tabContainer.Size = UDim2.new(1, -10, 0, 30)
    tabContainer.Position = UDim2.new(0, 5, 0, 35)
    tabContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    tabContainer.BorderSizePixel = 0
    tabContainer.Parent = self.MainFrame
    
    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 4)
    tabCorner.Parent = tabContainer
    
    return tabContainer
end

function GUI:CreateTab(name, parent, position)
    local tab = Instance.new("TextButton")
    tab.Name = name .. "Tab"
    tab.Size = UDim2.new(0, 100, 0, 25)
    tab.Position = UDim2.new(0, position, 0, 2.5)
    tab.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    tab.BorderSizePixel = 0
    tab.Text = name
    tab.TextColor3 = Color3.fromRGB(200, 200, 200)
    tab.TextSize = 12
    tab.Font = Enum.Font.Code
    tab.Parent = parent
    
    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 3)
    tabCorner.Parent = tab
    
    return tab
end

function GUI:CreateContentFrame(name)
    local content = Instance.new("ScrollingFrame")
    content.Name = name .. "Content"
    content.Size = UDim2.new(1, -10, 1, -75)
    content.Position = UDim2.new(0, 5, 0, 70)
    content.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 6
    content.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.Visible = false
    content.Parent = self.MainFrame
    
    local contentCorner = Instance.new("UICorner")
    contentCorner.CornerRadius = UDim.new(0, 4)
    contentCorner.Parent = content
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 5)
    listLayout.Parent = content
    
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        content.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
    end)
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 5)
    padding.PaddingLeft = UDim.new(0, 5)
    padding.PaddingRight = UDim.new(0, 5)
    padding.PaddingBottom = UDim.new(0, 5)
    padding.Parent = content
    
    return content
end

function GUI:CreateToggle(name, parent, callback, defaultValue)
    local toggleFrame = Instance.new("Frame")
    toggleFrame.Name = name .. "Toggle"
    toggleFrame.Size = UDim2.new(1, -10, 0, 25)
    toggleFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    toggleFrame.BorderSizePixel = 0
    toggleFrame.Parent = parent
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 4)
    toggleCorner.Parent = toggleFrame
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -35, 1, 0)
    label.Position = UDim2.new(0, 5, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextSize = 12
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = toggleFrame
    
    local toggleButton = Instance.new("TextButton")
    toggleButton.Name = "Button"
    toggleButton.Size = UDim2.new(0, 20, 0, 20)
    toggleButton.Position = UDim2.new(1, -25, 0, 2.5)
    toggleButton.BackgroundColor3 = defaultValue and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(180, 80, 80)
    toggleButton.BorderSizePixel = 0
    toggleButton.Text = ""
    toggleButton.Parent = toggleFrame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 3)
    buttonCorner.Parent = toggleButton
    
    local enabled = defaultValue or false
    
    toggleButton.MouseButton1Click:Connect(function()
        enabled = not enabled
        toggleButton.BackgroundColor3 = enabled and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(180, 80, 80)
        callback(enabled)
    end)
    
    return toggleFrame, function() return enabled end
end

function GUI:CreateSlider(name, parent, min, max, default, callback)
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Name = name .. "Slider"
    sliderFrame.Size = UDim2.new(1, -10, 0, 40)
    sliderFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    sliderFrame.BorderSizePixel = 0
    sliderFrame.Parent = parent
    
    local sliderCorner = Instance.new("UICorner")
    sliderCorner.CornerRadius = UDim.new(0, 4)
    sliderCorner.Parent = sliderFrame
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -10, 0, 15)
    label.Position = UDim2.new(0, 5, 0, 2)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. tostring(default)
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextSize = 11
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = sliderFrame
    
    local sliderBg = Instance.new("Frame")
    sliderBg.Name = "SliderBg"
    sliderBg.Size = UDim2.new(1, -20, 0, 18)
    sliderBg.Position = UDim2.new(0, 10, 0, 20)
    sliderBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = sliderFrame
    
    local sliderBgCorner = Instance.new("UICorner")
    sliderBgCorner.CornerRadius = UDim.new(0, 3)
    sliderBgCorner.Parent = sliderBg
    
    local sliderFill = Instance.new("Frame")
    sliderFill.Name = "SliderFill"
    sliderFill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    sliderFill.BackgroundColor3 = Color3.fromRGB(80, 150, 220)
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderBg
    
    local sliderFillCorner = Instance.new("UICorner")
    sliderFillCorner.CornerRadius = UDim.new(0, 3)
    sliderFillCorner.Parent = sliderFill
    
    local value = default
    local dragging = false
    
    local function updateSlider(input)
        local pos = (input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X
        pos = math.clamp(pos, 0, 1)
        value = math.floor(min + (max - min) * pos)
        sliderFill.Size = UDim2.new(pos, 0, 1, 0)
        label.Text = name .. ": " .. tostring(value)
        callback(value)
    end
    
    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateSlider(input)
        end
    end)
    
    sliderBg.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlider(input)
        end
    end)
    
    return sliderFrame, function() return value end
end

function GUI:CreateColorPicker(name, parent, defaultColor, callback)
    local pickerFrame = Instance.new("Frame")
    pickerFrame.Name = name .. "ColorPicker"
    pickerFrame.Size = UDim2.new(1, -10, 0, 25)
    pickerFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    pickerFrame.BorderSizePixel = 0
    pickerFrame.Parent = parent
    
    local pickerCorner = Instance.new("UICorner")
    pickerCorner.CornerRadius = UDim.new(0, 4)
    pickerCorner.Parent = pickerFrame
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -35, 1, 0)
    label.Position = UDim2.new(0, 5, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextSize = 12
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = pickerFrame
    
    local colorDisplay = Instance.new("Frame")
    colorDisplay.Name = "ColorDisplay"
    colorDisplay.Size = UDim2.new(0, 50, 0, 20)
    colorDisplay.Position = UDim2.new(1, -55, 0, 2.5)
    colorDisplay.BackgroundColor3 = defaultColor
    colorDisplay.BorderSizePixel = 0
    colorDisplay.Parent = pickerFrame
    
    local displayCorner = Instance.new("UICorner")
    displayCorner.CornerRadius = UDim.new(0, 3)
    displayCorner.Parent = colorDisplay
    
    local currentColor = defaultColor
    
    local colorButton = Instance.new("TextButton")
    colorButton.Size = UDim2.new(1, 0, 1, 0)
    colorButton.BackgroundTransparency = 1
    colorButton.Text = ""
    colorButton.Parent = colorDisplay
    
    colorButton.MouseButton1Click:Connect(function()
        callback(currentColor)
    end)
    
    return pickerFrame, colorDisplay, function(newColor)
        currentColor = newColor
        colorDisplay.BackgroundColor3 = newColor
    end
end

function GUI:CreateSection(name, parent)
    local section = Instance.new("Frame")
    section.Name = name .. "Section"
    section.Size = UDim2.new(1, -10, 0, 20)
    section.BackgroundTransparency = 1
    section.Parent = parent
    
    local sectionLabel = Instance.new("TextLabel")
    sectionLabel.Name = "Label"
    sectionLabel.Size = UDim2.new(1, 0, 1, 0)
    sectionLabel.BackgroundTransparency = 1
    sectionLabel.Text = "━━━ " .. name .. " ━━━"
    sectionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    sectionLabel.TextSize = 13
    sectionLabel.Font = Enum.Font.CodeBold
    sectionLabel.TextXAlignment = Enum.TextXAlignment.Center
    sectionLabel.Parent = section
    
    return section
end

function GUI:ToggleVisibility()
    self.IsVisible = not self.IsVisible
    self.MainFrame.Visible = self.IsVisible
end

function GUI:Initialize()
    local success, err = pcall(function()
        self.ScreenGui = self:CreateScreenGui()
        self.MainFrame = self:CreateMainFrame()
        self.MainFrame.Parent = self.ScreenGui
        
        local tabContainer = self:CreateTabContainer()
        local visualsTab = self:CreateTab("Visuals", tabContainer, 5)
        
        local visualsContent = self:CreateContentFrame("Visuals")
        visualsContent.Visible = true
        
        visualsTab.MouseButton1Click:Connect(function()
            visualsContent.Visible = true
            visualsTab.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        end)
        
        self:CreateSection("Player ESP", visualsContent)
        
        self:CreateToggle("Enable Player ESP", visualsContent, function(enabled)
            self.ESP:SetPlayerESPEnabled(enabled)
            if enabled then
                self:CreateNotification("Player ESP", "Player ESP enabled", 2)
            else
                self:CreateNotification("Player ESP", "Player ESP disabled", 2)
            end
        end, false)
        
        self:CreateToggle("Player Chams", visualsContent, function(enabled)
            self.ESP:SetPlayerChamsEnabled(enabled)
            if enabled then
                self:CreateNotification("Chams", "Player chams enabled", 2)
            else
                self:CreateNotification("Chams", "Player chams disabled", 2)
            end
        end, false)
        
        self:CreateSlider("Player Transparency", visualsContent, 0, 100, 50, function(value)
            self.ESP:SetPlayerTransparency(value / 100)
        end)
        
        local playerColorPicker, playerColorDisplay, setPlayerColor = self:CreateColorPicker("Player Color", visualsContent, Color3.fromRGB(0, 255, 0), function(color)
        end)
        
        self:CreateToggle("Player Outline", visualsContent, function(enabled)
            self.ESP:SetPlayerOutlineEnabled(enabled)
        end, true)
        
        self:CreateSlider("Player Max Distance", visualsContent, 0, 5000, 1000, function(value)
            self.ESP:SetPlayerMaxDistance(value)
        end)
        
        self:CreateSection("Zombie ESP", visualsContent)
        
        self:CreateToggle("Enable Zombie ESP", visualsContent, function(enabled)
            self.ESP:SetZombieESPEnabled(enabled)
            if enabled then
                self:CreateNotification("Zombie ESP", "Zombie ESP enabled", 2)
            else
                self:CreateNotification("Zombie ESP", "Zombie ESP disabled", 2)
            end
        end, false)
        
        self:CreateToggle("Zombie Chams", visualsContent, function(enabled)
            self.ESP:SetZombieChamsEnabled(enabled)
            if enabled then
                self:CreateNotification("Chams", "Zombie chams enabled", 2)
            else
                self:CreateNotification("Chams", "Zombie chams disabled", 2)
            end
        end, false)
        
        self:CreateSlider("Zombie Transparency", visualsContent, 0, 100, 50, function(value)
            self.ESP:SetZombieTransparency(value / 100)
        end)
        
        local zombieColorPicker, zombieColorDisplay, setZombieColor = self:CreateColorPicker("Zombie Color", visualsContent, Color3.fromRGB(255, 0, 0), function(color)
        end)
        
        self:CreateToggle("Zombie Outline", visualsContent, function(enabled)
            self.ESP:SetZombieOutlineEnabled(enabled)
        end, true)
        
        self:CreateSlider("Zombie Max Distance", visualsContent, 0, 5000, 1000, function(value)
            self.ESP:SetZombieMaxDistance(value)
        end)
        
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if not gameProcessed and input.KeyCode == Enum.KeyCode.Insert then
                self:ToggleVisibility()
            end
        end)
    end)
    
    if success then
        task.wait(0.5)
        self:CreateNotification("BRM5 ESP", "Loaded successfully! Press INSERT to toggle", 3)
    else
        warn("GUI initialization error: " .. tostring(err))
    end
end

local function Initialize()
    local success, err = pcall(function()
        task.wait(1)
        
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        
        local espInstance = ESP.new()
        local guiInstance = GUI.new(espInstance)
        
        guiInstance:Initialize()
    end)
    
    if not success then
        warn("BRM5 ESP Error: " .. tostring(err))
    end
end

Initialize()
