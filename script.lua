if getgenv().AutoEquipHub and getgenv().AutoEquipHub.Unload then
	getgenv().AutoEquipHub.Unload()
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local RequestEquipBest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestEquipBest")

local alive = true
local autoEquip = false
local interval = 0.5
local walkSpeedEnabled = false
local walkSpeed = 16
local defaultWalkSpeed = 16

local function resetWalkSpeed()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = defaultWalkSpeed
	end
end

local function copyCoordinates()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		Rayfield:Notify({
			Title = "Copy Coordinates",
			Content = "Character is not loaded yet.",
			Duration = 3,
		})
		return
	end

	local position = root.Position
	local text = string.format("%.2f, %.2f, %.2f", position.X, position.Y, position.Z)
	local clipboard = setclipboard or toclipboard
	if not clipboard then
		Rayfield:Notify({
			Title = "Copy Coordinates",
			Content = "Clipboard is not available in this executor.",
			Duration = 3,
		})
		return
	end

	clipboard(text)
	Rayfield:Notify({
		Title = "Coordinates Copied",
		Content = text,
		Duration = 3,
	})
end

local function unload()
	alive = false
	autoEquip = false
	walkSpeedEnabled = false
	pcall(resetWalkSpeed)
	getgenv().AutoEquipHub = nil
	pcall(function()
		Rayfield:Destroy()
	end)
end

getgenv().AutoEquipHub = {
	Unload = unload,
}

local Window = Rayfield:CreateWindow({
	Name = "Auto Equip",
	LoadingTitle = "Auto Equip",
	LoadingSubtitle = "RequestEquipBest",
	ConfigurationSaving = {
		Enabled = true,
		FileName = "AutoEquipBest",
	},
	KeySystem = false,
})

local Tab = Window:CreateTab("Main", 4483362458)

Tab:CreateSection("Auto Equip")

Tab:CreateToggle({
	Name = "Auto Equip Best",
	CurrentValue = false,
	Flag = "AutoEquipBest",
	Callback = function(value)
		autoEquip = value
	end,
})

Tab:CreateSlider({
	Name = "Equip Interval (seconds)",
	Range = {0.1, 5},
	Increment = 0.1,
	Suffix = "s",
	CurrentValue = 0.5,
	Flag = "EquipInterval",
	Callback = function(value)
		interval = value
	end,
})

Tab:CreateSection("Walk Speed")

Tab:CreateToggle({
	Name = "Set Walk Speed",
	CurrentValue = false,
	Flag = "WalkSpeedEnabled",
	Callback = function(value)
		walkSpeedEnabled = value
		if not value then
			resetWalkSpeed()
		end
	end,
})

Tab:CreateInput({
	Name = "Walk Speed",
	PlaceholderText = "Type a speed",
	CurrentValue = "16",
	Numeric = true,
	Finished = true,
	Flag = "WalkSpeedInput",
	Callback = function(text)
		local value = tonumber(text)
		if value then
			walkSpeed = value
		end
	end,
})

Tab:CreateSection("Coordinates")

Tab:CreateButton({
	Name = "Copy Coordinates",
	Callback = function()
		copyCoordinates()
	end,
})

Tab:CreateSection("Script")

Tab:CreateButton({
	Name = "Self Destruct",
	Callback = function()
		unload()
	end,
})

task.spawn(function()
	while alive do
		if autoEquip then
			local args = {
				{},
			}
			pcall(function()
				RequestEquipBest:FireServer(unpack(args))
			end)
		end
		task.wait(interval)
	end
end)

task.spawn(function()
	while alive do
		if walkSpeedEnabled then
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.WalkSpeed ~= walkSpeed then
				humanoid.WalkSpeed = walkSpeed
			end
		end
		task.wait(0.1)
	end
end)
