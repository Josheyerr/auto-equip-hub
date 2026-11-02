if getgenv().AutoEquipHub and getgenv().AutoEquipHub.Unload then
	getgenv().AutoEquipHub.Unload()
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local CollectionService = game:GetService("CollectionService")
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
local antiRagdoll = false
local returnOnEgg = false
local carryConnection = nil
local ragdollOriginals = {}
local ragdollStates = {
	Enum.HumanoidStateType.Physics,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.FallingDown,
}

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

local function applyAntiRagdoll()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	for _, state in ragdollStates do
		humanoid:SetStateEnabled(state, false)
	end

	if humanoid.PlatformStand then
		humanoid.PlatformStand = false
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
	then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function restoreRagdollStates()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	for _, state in ragdollStates do
		humanoid:SetStateEnabled(state, true)
	end
end

local function hookRagdoll(event)
	if typeof(getconnections) ~= "function" or typeof(hookfunction) ~= "function" then
		return
	end

	for _, connection in getconnections(event.OnClientEvent) do
		local callback = connection.Function
		if typeof(callback) == "function" and ragdollOriginals[callback] == nil then
			local old
			local ok, original = pcall(function()
				old = hookfunction(callback, function(...)
					if antiRagdoll then
						return
					end
					return old(...)
				end)
				return old
			end)
			if ok and typeof(original) == "function" then
				ragdollOriginals[callback] = original
			end
		end
	end
end

local function isCarryingEgg(value)
	return type(value) == "string" and value ~= ""
end

local function findMyBase()
	local slot = LocalPlayer:GetAttribute("PlotSlot")
	local userId = LocalPlayer.UserId
	local slotted = nil

	for _, inst in CollectionService:GetTagged("Base") do
		if inst:IsA("Model") then
			if inst:GetAttribute("OwnerUserId") == userId then
				return inst
			end
			if type(slot) == "number" and inst:GetAttribute("BaseIndex") == slot then
				slotted = inst
			end
		end
	end

	if slotted then
		return slotted
	end

	local bases = workspace:FindFirstChild("Bases")
	if bases and type(slot) == "number" then
		local named = bases:FindFirstChild("Base" .. tostring(slot))
		if named and named:IsA("Model") then
			return named
		end
	end

	return nil
end

local function baseReturnCFrame(base)
	local spot = base:FindFirstChild("ReturnSpot", true)
	if spot and spot:IsA("Attachment") then
		return spot.WorldCFrame + Vector3.new(0, 3, 0)
	end
	if spot and spot:IsA("BasePart") then
		return spot.CFrame + Vector3.new(0, 3, 0)
	end

	local spawn = base:FindFirstChild("Spawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame + Vector3.new(0, 4, 0)
	end

	return base:GetPivot() + Vector3.new(0, 5, 0)
end

local function teleportToBase()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root then
		return
	end

	local base = findMyBase()
	if not base then
		Rayfield:Notify({
			Title = "Egg Return",
			Content = "Could not find your base.",
			Duration = 3,
		})
		return
	end

	character:PivotTo(baseReturnCFrame(base))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function restoreRagdollHooks()
	if typeof(hookfunction) ~= "function" then
		table.clear(ragdollOriginals)
		return
	end

	for callback, original in ragdollOriginals do
		pcall(hookfunction, callback, original)
	end
	table.clear(ragdollOriginals)
end

local function unload()
	alive = false
	autoEquip = false
	walkSpeedEnabled = false
	antiRagdoll = false
	returnOnEgg = false
	if carryConnection then
		carryConnection:Disconnect()
		carryConnection = nil
	end
	pcall(resetWalkSpeed)
	pcall(restoreRagdollStates)
	pcall(restoreRagdollHooks)
	getgenv().AutoEquipHub = nil
	pcall(function()
		Rayfield:Destroy()
	end)
end

getgenv().AutoEquipHub = {
	Unload = unload,
}

local VERSION = "2026-11-02.6"

local Window = Rayfield:CreateWindow({
	Name = "Auto Equip",
	LoadingTitle = "Auto Equip",
	LoadingSubtitle = VERSION,
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

Tab:CreateSection("Ragdoll")

Tab:CreateToggle({
	Name = "Anti Ragdoll",
	CurrentValue = false,
	Flag = "AntiRagdoll",
	Callback = function(value)
		antiRagdoll = value
		if value then
			applyAntiRagdoll()
		else
			restoreRagdollStates()
		end
	end,
})

Tab:CreateSection("Egg")

Tab:CreateToggle({
	Name = "Teleport Home On Egg",
	CurrentValue = false,
	Flag = "ReturnOnEgg",
	Callback = function(value)
		returnOnEgg = value
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
	local event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll")
	while alive do
		pcall(hookRagdoll, event)
		if antiRagdoll then
			pcall(applyAntiRagdoll)
		end
		task.wait(0.1)
	end
end)

do
	local lastCarry = LocalPlayer:GetAttribute("CarryingEgg")
	carryConnection = LocalPlayer:GetAttributeChangedSignal("CarryingEgg"):Connect(function()
		if not alive then
			return
		end

		local value = LocalPlayer:GetAttribute("CarryingEgg")
		local pickedUp = returnOnEgg and isCarryingEgg(value) and not isCarryingEgg(lastCarry)
		lastCarry = value
		if pickedUp then
			teleportToBase()
		end
	end)
end

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
