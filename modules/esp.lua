local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

return ESP