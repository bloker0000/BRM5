local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local GITHUB_REPO = "https://raw.githubusercontent.com/bloker0000/rblx-stuff/main/"

local function loadModule(moduleName)
    local success, result = pcall(function()
        return loadstring(game:HttpGet(GITHUB_REPO .. moduleName .. ".lua"))()
    end)
    
    if not success then
        warn("Failed to load module: " .. moduleName)
        warn("Error: " .. tostring(result))
        return nil
    end
    
    return result
end

print("BRM5 ESP - Created by Multyply")
print("Loading modules...")

local GUI = loadModule("modules/gui")
local ESP = loadModule("modules/esp")

if not GUI or not ESP then
    warn("Failed to load required modules!")
    return
end

print("Modules loaded successfully!")

local espInstance = ESP.new()
local guiInstance = GUI.new(espInstance)

guiInstance:Initialize()

print("BRM5 ESP initialized successfully!")