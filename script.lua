if game.PlaceId ~= 129852792970565 then
	return
end

if getgenv().AutoEquipHub and getgenv().AutoEquipHub.Unload then
	getgenv().AutoEquipHub.Unload()
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local RequestEquipBest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestEquipBest")

local alive = true
local autoEquip = false
local interval = 0.5
local walkSpeedEnabled = false
local walkSpeed = 16
local gameWalkSpeed = nil
local speedBeforeBoost = nil
local acceptWalkToggle = false
local antiRagdoll = false
local returnOnEgg = false
local autoPath = false
local eggsBeforeReturn = 5
local pathToken = 0
local autoPlace = false
local autoHatch = false
local autoSell = false
local autoClaimIndex = false
local autoBat = false
local nextBatSwing = 0
local nextClaimAt = 0
local nextSellAt = 0
local sellRarities = {
	Common = true,
	Rare = true,
}
local savedCameraShake = nil
local cameraShakeHeld = false
local carryConnection = nil
local ragdollOriginals = {}
local notifyOriginals = {}
local ragdollStates = {
	Enum.HumanoidStateType.Physics,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.FallingDown,
}

local function resetWalkSpeed()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and speedBeforeBoost then
		humanoid.WalkSpeed = speedBeforeBoost
	end
	speedBeforeBoost = nil
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

local BASE_FALLBACK = {
	[1] = CFrame.new(-282, 6, 250),
	[2] = CFrame.new(-282, 6, 310),
	[3] = CFrame.new(-282, 6, 370),
	[4] = CFrame.new(-282, 6, 430),
	[5] = CFrame.new(-282, 6, 490),
	[6] = CFrame.new(-282, 6, 550),
	[7] = CFrame.new(-240, 6, 238),
	[8] = CFrame.new(-240, 6, 562),
}

local savedBaseCFrames = {}
local returningHome = false

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

local function rememberBase(base)
	if not base:IsA("Model") then
		return
	end

	local cf = baseReturnCFrame(base)
	local index = base:GetAttribute("BaseIndex")
	if type(index) == "number" then
		savedBaseCFrames[index] = cf
	end
	if base:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
		savedBaseCFrames.mine = cf
	end
end

local function refreshSavedBases()
	for _, inst in CollectionService:GetTagged("Base") do
		rememberBase(inst)
	end

	local bases = workspace:FindFirstChild("Bases")
	if not bases then
		return
	end

	for _, child in bases:GetChildren() do
		local index = tonumber(string.match(child.Name, "^Base(%d+)$"))
		if index and child:IsA("Model") then
			savedBaseCFrames[index] = savedBaseCFrames[index] or baseReturnCFrame(child)
			rememberBase(child)
		end
	end
end

local function goalCFrame()
	refreshSavedBases()
	if savedBaseCFrames.mine then
		return savedBaseCFrames.mine
	end

	local slot = LocalPlayer:GetAttribute("PlotSlot")
	if type(slot) == "number" then
		return savedBaseCFrames[slot] or BASE_FALLBACK[slot]
	end

	return nil
end

local GUARD_SPEED = {
	[1] = 14,
	[2] = 28.5,
	[3] = 54,
	[4] = 78,
	[5] = 110.5,
	[6] = 136,
}

local guardSamples = {}

local function chasingGuard()
	local runtime = workspace:FindFirstChild("Runtime")
	local guards = runtime and runtime:FindFirstChild("Guards")
	if not guards then
		return nil
	end

	local zone = LocalPlayer:GetAttribute("ZoneIndex")
	local fallback = nil
	for _, child in guards:GetChildren() do
		if child:GetAttribute("TargetUserId") == LocalPlayer.UserId then
			if child:GetAttribute("ZoneIndex") == zone then
				return child
			end
			fallback = fallback or child
		end
	end

	return fallback
end

local function guardPosition(guard)
	local root = guard:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	if guard:IsA("Model") then
		return guard:GetPivot().Position
	end
	if guard:IsA("BasePart") then
		return guard.Position
	end
	return nil
end

local function guardChaseSpeed(guard)
	local position = guardPosition(guard)
	if not position then
		return nil
	end

	local now = os.clock()
	local previous = guardSamples[guard]
	guardSamples[guard] = {
		position = position,
		time = now,
	}
	if not previous then
		return nil
	end

	local elapsed = now - previous.time
	if elapsed < 0.05 then
		return nil
	end

	local delta = position - previous.position
	local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / elapsed
	if speed ~= speed or speed < 2 or speed > 400 then
		return nil
	end

	return speed
end

local function returnSpeed(guard)
	local zone = (guard and guard:GetAttribute("ZoneIndex")) or LocalPlayer:GetAttribute("ZoneIndex")
	local base = type(zone) == "number" and GUARD_SPEED[zone] or nil
	if zone == 6 and base then
		local measured = guard and guardChaseSpeed(guard)
		local speed = base * 1.12
		if measured then
			speed = math.max(speed, measured * 1.04)
		end
		return math.min(speed, base * 1.2)
	end
	if not base then
		return gameWalkSpeed or 18
	end

	local speed = base * 1.08
	local measured = guard and guardChaseSpeed(guard)
	if measured then
		speed = math.max(speed, measured * 1.08)
	end
	return speed
end

local function teleportToBase()
	if returningHome then
		return
	end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root then
		return
	end

	local goal = goalCFrame()
	if not goal then
		Rayfield:Notify({
			Title = "Egg Return",
			Content = "Could not find your base.",
			Duration = 3,
		})
		return
	end

	returningHome = true
	if LocalPlayer.ReplicationFocus then
		LocalPlayer.ReplicationFocus = nil
	end
	root.Anchored = false
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = returnSpeed(chasingGuard())
		humanoid:MoveTo(goal.Position)
	end
	local leftover = workspace:FindFirstChild("EggReturnFocus")
	if leftover then
		leftover:Destroy()
	end

	task.spawn(function()
		local target = goal.Position
		while alive and root.Parent and (root.Position - target).Magnitude > 6 do
			if not isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg")) then
				break
			end

			if humanoid and humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid.WalkSpeed = returnSpeed(chasingGuard())
				humanoid:MoveTo(target)
			end

			task.wait(0.1)
		end

		if humanoid and humanoid.Parent and gameWalkSpeed then
			humanoid.WalkSpeed = gameWalkSpeed
		end
		returningHome = false
	end)
end

local function myBase()
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
		return bases:FindFirstChild("Base" .. tostring(slot))
	end
	return nil
end

local function homePosition()
	local base = myBase()
	local floor = base and base:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return (floor.CFrame * CFrame.new(0, floor.Size.Y / 2 + 3, 0)).Position
	end

	local goal = goalCFrame()
	if goal then
		return goal.Position
	end
	return nil
end

local pendingPlaces = {}
local placementApi = nil

local function getPlacement()
	if placementApi ~= nil then
		return placementApi or nil
	end

	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local util = shared and shared:FindFirstChild("Util")
	local moduleScript = util and util:FindFirstChild("Placement")
	if not moduleScript then
		placementApi = false
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	placementApi = ok and result or false
	return placementApi or nil
end

local function eggItemIds()
	local ids = {}
	local seen = {}
	local function scan(container)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("ItemKind") == "Egg" then
				local id = child:GetAttribute("ItemId")
				if type(id) == "string" and id ~= "" and not seen[id] then
					seen[id] = true
					table.insert(ids, id)
				end
			end
		end
	end
	scan(LocalPlayer:FindFirstChild("Backpack"))
	scan(LocalPlayer.Character)
	return ids
end

local function placeOneEgg()
	local placement = getPlacement()
	local base = myBase()
	local floor = base and base:FindFirstChild("Floor")
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not placement or not floor or not floor:IsA("BasePart") or not root then
		return
	end
	if (root.Position - floor.Position).Magnitude > 60 then
		return
	end

	local area = placement.Decode(base:GetAttribute("PlacementArea"))
	if not area then
		return
	end

	local frame = placement.BaseFrame(floor)
	local occupied = {}
	local eggCount = 0
	local now = os.clock()
	for index = #pendingPlaces, 1, -1 do
		if now - pendingPlaces[index].time > 3 then
			table.remove(pendingPlaces, index)
		end
	end

	for _, inst in CollectionService:GetTagged("Placed") do
		if inst:IsA("BasePart") then
			local localX, localZ = placement.ToLocal(frame, inst.Position)
			local radius = inst:GetAttribute("Radius")
			table.insert(occupied, {
				X = localX,
				Z = localZ,
				R = type(radius) == "number" and radius or 1.75,
				Id = inst:GetAttribute("ItemId"),
			})
			if inst:GetAttribute("OwnerUserId") == LocalPlayer.UserId and inst:GetAttribute("ItemKind") == "Egg" then
				eggCount = eggCount + 1
			end
		end
	end
	for _, pending in pendingPlaces do
		table.insert(occupied, {
			X = pending.x,
			Z = pending.z,
			R = 1.75,
			Id = pending.itemId,
		})
	end
	if eggCount >= 10 then
		return
	end

	local ids = eggItemIds()
	local itemId = ids[1]
	if not itemId then
		return
	end

	local remote = ReplicatedStorage:FindFirstChild("Remotes")
	remote = remote and remote:FindFirstChild("RequestPlaceAt")
	if not remote then
		return
	end

	local origin = frame:PointToObjectSpace(root.Position)
	local spotX, spotZ = placement.FindFree(area, origin.X, origin.Z, 1.75, occupied, itemId)
	if spotX == nil or spotZ == nil then
		return
	end

	local world = placement.ToWorld(frame, spotX, spotZ, 0).Position
	if (world - root.Position).Magnitude > 60 then
		return
	end

	remote:FireServer({
		itemId = itemId,
		x = spotX,
		z = spotZ,
		yaw = 0,
	})
	table.insert(pendingPlaces, {
		x = spotX,
		z = spotZ,
		itemId = itemId,
		time = now,
	})
end

local function setHatchCamera(enabled)
	if enabled then
		if not cameraShakeHeld then
			savedCameraShake = LocalPlayer:GetAttribute("Set_CameraShake")
			cameraShakeHeld = true
		end
		LocalPlayer:SetAttribute("Set_CameraShake", false)

		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local kit = shared and shared:FindFirstChild("Kit")
		local fovModule = kit and kit:FindFirstChild("CameraFov")
		local shakeModule = kit and kit:FindFirstChild("CameraShake")
		if fovModule then
			pcall(function()
				require(fovModule).Set("Hatch", 0)
			end)
		end
		if shakeModule then
			pcall(function()
				local shake = require(shakeModule)
				if shake.Stop then
					shake.Stop()
				end
			end)
		end
	elseif cameraShakeHeld then
		LocalPlayer:SetAttribute("Set_CameraShake", savedCameraShake)
		cameraShakeHeld = false
	end
end

local BAT_REACH = 11

local function nearestBatTarget(root)
	local nearest = nil
	local nearestDistance = BAT_REACH
	for _, player in Players:GetPlayers() do
		if player ~= LocalPlayer and player.Character then
			local otherRoot = player.Character:FindFirstChild("HumanoidRootPart")
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and humanoid and humanoid.Health > 0 then
				local offset = otherRoot.Position - root.Position
				local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if math.abs(offset.Y) <= 6 and flatDistance >= 0.5 and flatDistance <= nearestDistance then
					nearest = otherRoot
					nearestDistance = flatDistance
				end
			end
		end
	end
	return nearest
end

local function faceTarget(root, target)
	local flat = Vector3.new(target.Position.X - root.Position.X, 0, target.Position.Z - root.Position.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
end

local function swingBat()
	if os.clock() < nextBatSwing then
		return
	end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root then
		return
	end

	local target = nearestBatTarget(root)
	if not target then
		return
	end

	faceTarget(root, target)

	local bat = character:FindFirstChild("Bat")
	if not bat then
		local backpack = LocalPlayer:FindFirstChild("Backpack")
		bat = backpack and backpack:FindFirstChild("Bat")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if bat and humanoid then
			humanoid:EquipTool(bat)
			task.defer(function()
				local stillThere = nearestBatTarget(root)
				if bat.Parent == character and stillThere then
					faceTarget(root, stillThere)
					bat:Activate()
					nextBatSwing = os.clock() + 0.65
				end
			end)
		end
		return
	end

	if bat:IsA("Tool") then
		bat:Activate()
		nextBatSwing = os.clock() + 0.65
	end
end

local function claimIndex()
	if os.clock() < nextClaimAt then
		return
	end

	local remote = ReplicatedStorage:FindFirstChild("Remotes")
	remote = remote and remote:FindFirstChild("RequestIndexClaim")
	if not remote then
		return
	end

	remote:FireServer({})
	nextClaimAt = os.clock() + 1
end

local function sellSelected()
	if os.clock() < nextSellAt then
		return
	end

	local remote = ReplicatedStorage:FindFirstChild("Remotes")
	remote = remote and remote:FindFirstChild("RequestSell")
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not remote or not backpack then
		return
	end

	local carrying = LocalPlayer:GetAttribute("CarryingEgg")
	local itemIds = {}
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") then
			local itemId = child:GetAttribute("ItemId")
			local rarity = child:GetAttribute("Rarity")
			if type(itemId) == "string" and itemId ~= carrying and type(rarity) == "string" and sellRarities[rarity] then
				table.insert(itemIds, itemId)
				if #itemIds >= 100 then
					break
				end
			end
		end
	end
	if #itemIds == 0 then
		return
	end

	remote:FireServer({
		itemIds = itemIds,
	})
	nextSellAt = os.clock() + 0.7
end

local function hatchOneEgg()
	if typeof(fireproximityprompt) ~= "function" then
		return
	end
	for _, inst in CollectionService:GetTagged("Placed") do
		if inst:GetAttribute("OwnerUserId") == LocalPlayer.UserId
			and inst:GetAttribute("ItemKind") == "Egg"
			and inst:GetAttribute("State") == "Ready"
		then
			for _, descendant in inst:GetDescendants() do
				if descendant:IsA("ProximityPrompt") and descendant.Name == "HatchPrompt" then
					fireproximityprompt(descendant)
					return
				end
			end
		end
	end
end

local function isBestToast(...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if type(value) == "string" and string.find(value, "Already your best", 1, true) then
			return true
		end
		if type(value) == "table" then
			for _, field in value do
				if type(field) == "string" and string.find(field, "Already your best", 1, true) then
					return true
				end
			end
		end
	end
	return false
end

local function hookBestToast(event)
	if typeof(getconnections) ~= "function" or typeof(hookfunction) ~= "function" then
		return
	end

	for _, connection in getconnections(event.OnClientEvent) do
		local callback = connection.Function
		if typeof(callback) == "function" and notifyOriginals[callback] == nil then
			local old
			local ok, original = pcall(function()
				old = hookfunction(callback, function(...)
					if autoEquip and isBestToast(...) then
						return
					end
					return old(...)
				end)
				return old
			end)
			if ok and typeof(original) == "function" then
				notifyOriginals[callback] = original
			end
		end
	end
end

local function hideBestBanners()
	if not autoEquip then
		return
	end

	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	for _, descendant in playerGui:GetDescendants() do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
			and string.find(descendant.Text, "Already your best", 1, true)
		then
			descendant.Visible = false
			local parent = descendant.Parent
			if parent and parent:IsA("GuiObject") then
				parent.Visible = false
			end
		end
	end
end

local function restoreNotifyHooks()
	if typeof(hookfunction) ~= "function" then
		table.clear(notifyOriginals)
		return
	end

	for callback, original in notifyOriginals do
		pcall(hookfunction, callback, original)
	end
	table.clear(notifyOriginals)
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

local ZONE_REQUIRED_SPEED = {
	[1] = 10,
	[2] = 900,
	[3] = 10000,
	[4] = 170000,
	[5] = 2500000,
	[6] = 18000000,
}

local RARITY_RANK = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
	Relic = 6,
	Exotic = 7,
	Ascendant = 8,
	Secret = 9,
	SuperSecret = 10,
	Divine = 11,
	Exclusive = 12,
}

local pathRarities = {
	Common = true,
	Rare = true,
	Epic = true,
	Legendary = true,
	Mythic = true,
	Relic = true,
	Exotic = true,
	Ascendant = true,
	Secret = true,
	SuperSecret = true,
	Divine = true,
	Exclusive = true,
}

local function worldEggPosition(inst)
	if inst:IsA("Model") then
		local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.Position
		end
		return inst:GetPivot().Position
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function bestReachableEgg()
	local speed = tonumber(LocalPlayer:GetAttribute("Speed")) or 0
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg")) then
		return nil
	end

	local bestRank = -1
	local bestDistance = math.huge
	local bestPosition = nil
	local bestInstance = nil
	for _, inst in CollectionService:GetTagged("WorldEgg") do
		local carriedBy = inst:GetAttribute("CarriedBy")
		if type(carriedBy) == "number" and carriedBy ~= 0 then
			continue
		end

		local zone = inst:GetAttribute("Zone")
		if type(zone) ~= "number" then
			zone = inst:GetAttribute("ZoneIndex")
		end
		local required = type(zone) == "number" and ZONE_REQUIRED_SPEED[zone] or nil
		if not required or speed < required then
			continue
		end

		local rarity = inst:GetAttribute("Rarity")
		if type(rarity) ~= "string" or not pathRarities[rarity] then
			continue
		end
		local rank = RARITY_RANK[rarity] or 0
		local position = worldEggPosition(inst)
		if not position then
			continue
		end

		local distance = (position - root.Position).Magnitude
		if rank > bestRank or (rank == bestRank and distance < bestDistance) then
			bestRank = rank
			bestDistance = distance
			bestPosition = position
			bestInstance = inst
		end
	end

	return bestInstance, bestPosition
end

local pathLine = Instance.new("Folder")
pathLine.Name = "AutoPathLine"
pathLine.Parent = workspace

local function clearPathLine()
	pathLine:ClearAllChildren()
end

local function drawPathLine(points)
	clearPathLine()
	local previousAttachment = nil
	for _, position in points do
		local part = Instance.new("Part")
		part.Name = "PathNode"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Position = position + Vector3.new(0, 1.5, 0)
		part.Parent = pathLine

		local attachment = Instance.new("Attachment")
		attachment.Parent = part
		if previousAttachment then
			local beam = Instance.new("Beam")
			beam.Attachment0 = previousAttachment
			beam.Attachment1 = attachment
			beam.Width0 = 0.4
			beam.Width1 = 0.4
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 196, 60))
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.Parent = previousAttachment.Parent
		end
		previousAttachment = attachment
	end
end

local SPEED_KNOTS = {
	{ 10, 18 },
	{ 550, 25 },
	{ 2500, 55 },
	{ 25000, 70 },
	{ 250000, 100 },
	{ 2500000, 135 },
	{ 25000000, 170 },
	{ 100000000, 195 },
	{ 1000000000, 197 },
	{ 10000000000, 199 },
	{ 1000000000000, 200 },
}

local function gameMoveSpeed()
	local stat = math.max(tonumber(LocalPlayer:GetAttribute("Speed")) or 10, 1)
	local first = SPEED_KNOTS[1]
	local last = SPEED_KNOTS[#SPEED_KNOTS]
	local walk = last[2]
	if stat <= first[1] then
		walk = first[2]
	elseif stat < last[1] then
		for index = 1, #SPEED_KNOTS - 1 do
			local left = SPEED_KNOTS[index]
			local right = SPEED_KNOTS[index + 1]
			if stat <= right[1] then
				local blend = (math.log10(stat) - math.log10(left[1])) / (math.log10(right[1]) - math.log10(left[1]))
				walk = left[2] + (right[2] - left[2]) * blend
				break
			end
		end
	end
	if isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg")) then
		walk = walk * 0.9
	end
	return walk
end

local function playerSteering()
	return UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.A)
		or UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.D)
		or UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)
		or UserInputService:IsKeyDown(Enum.KeyCode.Left)
		or UserInputService:IsKeyDown(Enum.KeyCode.Right)
end

local function closestWaypoint(waypoints, position)
	local closest = 1
	local closestDistance = math.huge
	for index, waypoint in waypoints do
		local distance = (waypoint.Position - position).Magnitude
		if distance < closestDistance then
			closestDistance = distance
			closest = index
		end
	end
	return closest
end

local stealEgg

local function followPath(humanoid, root, destination, token, stopIfCarrying, eggToSteal)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 12,
	})
	local computed = pcall(function()
		path:ComputeAsync(root.Position, destination)
	end)
	local waypoints = {}
	if computed and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
	else
		table.insert(waypoints, {
			Position = destination,
			Action = Enum.PathWaypointAction.Walk,
		})
	end

	local points = { root.Position }
	for _, waypoint in waypoints do
		table.insert(points, waypoint.Position)
	end
	drawPathLine(points)

	local index = closestWaypoint(waypoints, root.Position)
	while index <= #waypoints do
		if token ~= pathToken or not autoPath or not alive or not root.Parent then
			clearPathLine()
			return
		end

		local carrying = isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg"))
		if stopIfCarrying and (carrying or #eggItemIds() >= eggsBeforeReturn) then
			clearPathLine()
			return
		end
		if not stopIfCarrying and not carrying and (root.Position - destination).Magnitude > 45 then
			clearPathLine()
			return
		end
		if playerSteering() then
			while playerSteering() and token == pathToken and autoPath and alive do
				task.wait(0.05)
			end
			index = closestWaypoint(waypoints, root.Position)
			continue
		end

		local moveSpeed = gameMoveSpeed()
		if humanoid.WalkSpeed ~= moveSpeed then
			humanoid.WalkSpeed = moveSpeed
		end

		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)

		local arrived = false
		local reached = false
		local connection = humanoid.MoveToFinished:Connect(function(didReach)
			arrived = true
			reached = didReach
		end)
		local started = os.clock()
		while not arrived and os.clock() - started < 3 do
			if token ~= pathToken or not autoPath or not alive then
				connection:Disconnect()
				clearPathLine()
				return
			end
			local lostEggFarFromHome = not stopIfCarrying
				and not isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg"))
				and (root.Position - destination).Magnitude > 45
			if playerSteering() or lostEggFarFromHome then
				break
			end
			if stopIfCarrying and (isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg")) or #eggItemIds() >= eggsBeforeReturn) then
				break
			end
			if eggToSteal and root.Parent and (root.Position - destination).Magnitude <= 12 then
				stealEgg(eggToSteal)
			end
			task.wait(0.05)
		end
		connection:Disconnect()

		if playerSteering() or not reached then
			local nearest = closestWaypoint(waypoints, root.Position)
			if nearest == index and not playerSteering() then
				index = index + 1
			else
				index = nearest
			end
		else
			index = index + 1
		end
	end

	local approachStarted = os.clock()
	while root.Parent and (root.Position - destination).Magnitude > 5 and os.clock() - approachStarted < 8 do
		if token ~= pathToken or not autoPath or not alive or playerSteering() then
			break
		end
		local moveSpeed = gameMoveSpeed()
		if humanoid.WalkSpeed ~= moveSpeed then
			humanoid.WalkSpeed = moveSpeed
		end
		humanoid:MoveTo(destination)
		task.wait(0.15)
	end
	clearPathLine()
end

function stealEgg(egg)
	if typeof(fireproximityprompt) ~= "function" or not egg then
		return
	end
	for _, descendant in egg:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "StealPrompt" then
			fireproximityprompt(descendant)
			return
		end
	end
end

local function unload()
	alive = false
	autoEquip = false
	walkSpeedEnabled = false
	antiRagdoll = false
	returnOnEgg = false
	autoPath = false
	pathToken = pathToken + 1
	clearPathLine()
	pathLine:Destroy()
	autoPlace = false
	autoHatch = false
	autoSell = false
	autoClaimIndex = false
	autoBat = false
	setHatchCamera(false)
	returningHome = false
	if carryConnection then
		carryConnection:Disconnect()
		carryConnection = nil
	end
	pcall(resetWalkSpeed)
	pcall(restoreRagdollStates)
	pcall(restoreRagdollHooks)
	pcall(restoreNotifyHooks)
	getgenv().AutoEquipHub = nil
	pcall(function()
		Rayfield:Destroy()
	end)
end

getgenv().AutoEquipHub = {
	Unload = unload,
}

local VERSION = "2026-11-02.39"

local Window = Rayfield:CreateWindow({
	Name = "Raise a Cat Boy",
	LoadingTitle = "Raise a Cat Boy",
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
		if not acceptWalkToggle then
			return
		end

		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if value then
			if humanoid and not speedBeforeBoost then
				speedBeforeBoost = humanoid.WalkSpeed
			end
			walkSpeedEnabled = true
		else
			walkSpeedEnabled = false
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

Tab:CreateSection("Bat")

Tab:CreateToggle({
	Name = "Auto Bat",
	CurrentValue = false,
	Flag = "AutoBat",
	Callback = function(value)
		autoBat = value
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
	Name = "Auto Pathing",
	CurrentValue = false,
	Flag = "AutoPath",
	Callback = function(value)
		autoPath = value
		pathToken = pathToken + 1
		if not value then
			clearPathLine()
		end
	end,
})

Tab:CreateSlider({
	Name = "Eggs Before Return",
	Range = {1, 10},
	Increment = 1,
	Suffix = " eggs",
	CurrentValue = 5,
	Flag = "EggsBeforeReturn",
	Callback = function(value)
		eggsBeforeReturn = value
	end,
})

Tab:CreateDropdown({
	Name = "Path Rarities",
	Options = {
		"Common",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
		"Relic",
		"Exotic",
		"Ascendant",
		"Secret",
		"SuperSecret",
		"Divine",
		"Exclusive",
	},
	CurrentOption = {
		"Common",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
		"Relic",
		"Exotic",
		"Ascendant",
		"Secret",
		"SuperSecret",
		"Divine",
		"Exclusive",
	},
	MultipleOptions = true,
	Flag = "PathRarities",
	Callback = function(selected)
		table.clear(pathRarities)
		if type(selected) == "string" then
			pathRarities[selected] = true
		elseif type(selected) == "table" then
			for _, rarity in selected do
				if type(rarity) == "string" then
					pathRarities[rarity] = true
				end
			end
		end
	end,
})

Tab:CreateSection("Cafe")

Tab:CreateToggle({
	Name = "Auto Place",
	CurrentValue = false,
	Flag = "AutoPlace",
	Callback = function(value)
		autoPlace = value
	end,
})

Tab:CreateToggle({
	Name = "Auto Hatch",
	CurrentValue = false,
	Flag = "AutoHatch",
	Callback = function(value)
		autoHatch = value
		if not value then
			setHatchCamera(false)
		end
	end,
})

Tab:CreateToggle({
	Name = "Auto Claim Index",
	CurrentValue = false,
	Flag = "AutoClaimIndex",
	Callback = function(value)
		autoClaimIndex = value
	end,
})

Tab:CreateToggle({
	Name = "Auto Sell",
	CurrentValue = false,
	Flag = "AutoSell",
	Callback = function(value)
		autoSell = value
	end,
})

Tab:CreateDropdown({
	Name = "Sell Rarities",
	Options = {
		"Common",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
		"Relic",
		"Exotic",
		"Ascendant",
		"Secret",
		"SuperSecret",
		"Divine",
	},
	CurrentOption = { "Common", "Rare" },
	MultipleOptions = true,
	Flag = "SellRarities",
	Callback = function(selected)
		table.clear(sellRarities)
		if type(selected) == "string" then
			sellRarities[selected] = true
		elseif type(selected) == "table" then
			for _, rarity in selected do
				if type(rarity) == "string" then
					sellRarities[rarity] = true
				end
			end
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
	local event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")
	while alive do
		pcall(hookBestToast, event)
		if autoEquip then
			pcall(hideBestBanners)
		end
		task.wait(0.2)
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
			pathToken = pathToken + 1
		end
	end)
end

task.spawn(function()
	while alive do
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and walkSpeedEnabled and not returningHome then
			if humanoid.WalkSpeed ~= walkSpeed then
				humanoid.WalkSpeed = walkSpeed
			end
		elseif humanoid and not walkSpeedEnabled and not returningHome then
			gameWalkSpeed = humanoid.WalkSpeed
		end
		task.wait(0.1)
	end
end)

task.spawn(function()
	while alive do
		if autoPlace then
			pcall(placeOneEgg)
		end
		if autoHatch then
			setHatchCamera(true)
			pcall(hatchOneEgg)
		end
		if autoSell then
			pcall(sellSelected)
		end
		if autoClaimIndex then
			pcall(claimIndex)
		end
		task.wait(0.4)
	end
end)

task.spawn(function()
	while alive do
		if autoPath then
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root then
				pathToken = pathToken + 1
				local token = pathToken
				local carryingEgg = isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg"))
				local inventoryFull = #eggItemIds() >= eggsBeforeReturn
				if carryingEgg or inventoryFull then
					local home = homePosition()
					if home and (root.Position - home).Magnitude > 5 then
						followPath(humanoid, root, home, token, false)
					end
				else
					local egg, destination = bestReachableEgg()
					if egg and destination then
						followPath(humanoid, root, destination, token, true, egg)
						if token == pathToken and autoPath and isCarryingEgg(LocalPlayer:GetAttribute("CarryingEgg")) then
							local home = homePosition()
							if home then
								followPath(humanoid, root, home, token, false)
							end
						end
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

task.spawn(function()
	while alive do
		if autoBat then
			pcall(swingBat)
		end
		task.wait(0.1)
	end
end)

task.defer(function()
	walkSpeedEnabled = false
	acceptWalkToggle = true
end)
