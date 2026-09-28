local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Character = require(ReplicatedStorage.Classes.Character)
local Ability = require(ReplicatedStorage.Classes.Ability)
local Hitbox = require(ReplicatedStorage.Classes.Hitbox)
local Types = require(ReplicatedStorage.Classes.Types)
local Utils = require(ReplicatedStorage.Modules.Utils)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

-- Constants
local JOHN_DOE_CONFIG = {
	M1 = {
		Cooldown = 2.2,
		Damage = 26,
		HitboxSize = Vector3.new(4, 5, 7),
		HitboxOffset = CFrame.new(0, 0, -3.5),
		Delay = 0.1,
		Duration = 0.4,
	},
	Counter = {
		Cooldown = 50,
		FlingForce = 150,
		SearchRadius = 50,
	},
	Trail = {
		Lifetime = 4,
		SpawnInterval = 0.2,
		SegmentSize = 1.2,
		SpeedBoost = 1.05, -- 5%
		CheckInterval = 0.2,
	},
}

--============================================================
-- Trail Segment Class
--============================================================
local TrailSegment = {}
TrailSegment.__index = TrailSegment

function TrailSegment.new(position: Vector3, template: Instance?): TrailSegment?
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		workspace:FindFirstChild("Debris"),
		workspace:FindFirstChild("Effects"),
	}

	local rayResult = workspace:Raycast(
		position + Vector3.new(0, 2, 0),
		Vector3.new(0, -50, 0),
		raycastParams
	)

	if not rayResult then
		return nil
	end

	local self = setmetatable({
		_part = nil,
		_lifetime = JOHN_DOE_CONFIG.Trail.Lifetime,
		_spawnTime = os.clock(),
	}, TrailSegment)

	self:_createPart(rayResult.Position, rayResult.Normal, template)
	return self
end

function TrailSegment:_createPart(floorPosition: Vector3, floorNormal: Vector3, template: Instance?)
	local part: BasePart

	if template and template:IsA("BasePart") then
		part = template:Clone()
	else
		part = Instance.new("Part")
		part.Name = "CorruptTrailSegment"
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(
			JOHN_DOE_CONFIG.Trail.SegmentSize,
			0.3,
			JOHN_DOE_CONFIG.Trail.SegmentSize
		)
		part.Material = Enum.Material.Neon
		part.BrickColor = BrickColor.new("Dark indigo")
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = true
		part.CastShadow = false
		part.Transparency = 0.6
	end

	-- Build stable orientation from floor normal
	local up = floorNormal
	local forward = Vector3.new(0, 0, -1)

	if math.abs(up:Dot(forward)) > 0.99 then
		forward = Vector3.new(1, 0, 0)
	end

	local right = forward:Cross(up).Unit
	forward = up:Cross(right).Unit

	part.CFrame = CFrame.fromMatrix(
		floorPosition + floorNormal * (part.Size.Y / 2),
		right,
		up,
		-forward
	)

	part.Parent = workspace
	self._part = part
end

function TrailSegment:isAlive(): boolean
	return self._part and self._part.Parent ~= nil and (os.clock() - self._spawnTime) < self._lifetime
end

function TrailSegment:destroy()
	if self._part then
		self._part:Destroy()
	end
end

function TrailSegment:getPosition(): Vector3?
	return self._part and self._part.Position or nil
end

--============================================================
-- Corrupt Trail Manager
--============================================================
local CorruptTrail = {}
CorruptTrail.__index = CorruptTrail

function CorruptTrail.new(ability: Types.Ability): CorruptTrail
	local self = setmetatable({
		_ability = ability,
		_segments = {},
		_lastSpawnTime = os.clock(),
		_lastCheckTime = os.clock(),
		_connections = {},
	}, CorruptTrail)

	if RunService:IsServer() then
		self:_startTrailLoop()
	end

	return self
end

function CorruptTrail:_startTrailLoop()
	local hrp = self._ability.OwnerProperties.HRP
	local character = self._ability.OwnerProperties.Character

	table.insert(self._connections, RunService.Heartbeat:Connect(function()
		if not hrp or not hrp.Parent then
			return
		end

		local now = os.clock()

		-- Spawn trail segments
		if now - self._lastSpawnTime >= JOHN_DOE_CONFIG.Trail.SpawnInterval then
			self._lastSpawnTime = now
			self:_spawnSegment(hrp.Position)
		end

		-- Check for survivors
		if now - self._lastCheckTime >= JOHN_DOE_CONFIG.Trail.CheckInterval then
			self._lastCheckTime = now
			self:_checkSurvivorsInTrail()
		end

		-- Clean dead segments
		self:_cleanDeadSegments()
	end))
end

function CorruptTrail:_spawnSegment(position: Vector3)
	local segment = TrailSegment.new(position, self._ability.CustomTrailSegmentTemplate)

	if segment then
		table.insert(self._segments, segment)

		-- Schedule destruction
		task.delay(JOHN_DOE_CONFIG.Trail.Lifetime, function()
			segment:destroy()
		end)
	end
end

function CorruptTrail:_checkSurvivorsInTrail()
	local loadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
	if not loadedPlayers then
		return
	end

	for _, playerFolder in pairs(loadedPlayers:GetChildren()) do
		local survivorCharacter = playerFolder:FindFirstChild("Character")
		if not survivorCharacter or not survivorCharacter.PrimaryPart then
			continue
		end

		for _, segment in pairs(self._segments) do
			if segment:isAlive() then
				self:_checkSurvivorInSegment(survivorCharacter, segment)
			end
		end
	end
end

function CorruptTrail:_checkSurvivorInSegment(survivorCharacter: Model, segment: TrailSegment)
	local segmentPos = segment:getPosition()
	if not segmentPos then
		return
	end

	local distance = (survivorCharacter.PrimaryPart.Position - segmentPos).Magnitude
	local checkRadius = (segment._part.Size.X + segment._part.Size.Z) / 2 + 2

	if distance <= checkRadius and not survivorCharacter:GetAttribute("JohnDoeTrailHighlighted") then
		survivorCharacter:SetAttribute("JohnDoeTrailHighlighted", true)

		-- Apply speed boost to John Doe
		self._ability.OwnerProperties.Character:SetAttribute("JohnDoeTrailSpeedActive", true)

		-- Remove after trail lifetime
		task.delay(JOHN_DOE_CONFIG.Trail.Lifetime, function()
			if survivorCharacter and survivorCharacter.Parent then
				survivorCharacter:SetAttribute("JohnDoeTrailHighlighted", false)
			end
		end)
	end
end

function CorruptTrail:_cleanDeadSegments()
	for i = #self._segments, 1, -1 do
		if not self._segments[i]:isAlive() then
			table.remove(self._segments, i)
		end
	end
end

function CorruptTrail:destroy()
	for _, segment in pairs(self._segments) do
		segment:destroy()
	end
	for _, connection in pairs(self._connections) do
		connection:Disconnect()
	end
	self._segments = {}
	self._connections = {}
end

--============================================================
-- Counter Ability Manager
--============================================================
local CounterAbility = {}
CounterAbility.__index = CounterAbility

function CounterAbility.new(ability: Types.Ability): CounterAbility
	local self = setmetatable({
		_ability = ability,
		_nextAllowedAt = os.clock(),
		_wasStunnedLastFrame = false,
		_connection = nil,
	}, CounterAbility)

	if RunService:IsServer() then
		self:_startCounterLoop()
	end

	return self
end

function CounterAbility:_startCounterLoop()
	local character = self._ability.OwnerProperties.Character
	local hrp = self._ability.OwnerProperties.HRP

	self._connection = RunService.Heartbeat:Connect(function()
		if not hrp or not hrp.Parent then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local isStunned = humanoid:GetState() == Enum.HumanoidStateType.Stunned

		if isStunned and not self._wasStunnedLastFrame then
			self:_onStunned(character, hrp)
		end

		self._wasStunnedLastFrame = isStunned
	end)
end

function CounterAbility:_onStunned(character: Model, hrp: BasePart)
	local now = os.clock()

	if now < self._nextAllowedAt then
		return
	end

	self._nextAllowedAt = now + JOHN_DOE_CONFIG.Counter.Cooldown

	local closestSurvivor = self:_findClosestSurvivor(hrp)
	if closestSurvivor then
		self:_executeFling(character, hrp, closestSurvivor)
	end
end

function CounterAbility:_findClosestSurvivor(hrp: BasePart): Model?
	local loadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
	if not loadedPlayers then
		return nil
	end

	local closestSurvivor = nil
	local closestDistance = JOHN_DOE_CONFIG.Counter.SearchRadius

	for _, playerFolder in pairs(loadedPlayers:GetChildren()) do
		local survivorCharacter = playerFolder:FindFirstChild("Character")
		if survivorCharacter and survivorCharacter.PrimaryPart then
			local distance = (survivorCharacter.PrimaryPart.Position - hrp.Position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestSurvivor = survivorCharacter
			end
		end
	end

	return closestSurvivor
end

function CounterAbility:_executeFling(johnDoe: Model, hrp: BasePart, survivorCharacter: Model)
	local survivorHrp = survivorCharacter.PrimaryPart
	if not survivorHrp then
		return
	end

	-- Play counter animation
	if self._ability.CounterAnimationID and self._ability.CounterAnimationID ~= "rbxassetid://0" then
		local track = Utils.Character.LoadAnimationFromID(johnDoe, self._ability.CounterAnimationID)
		if track then
			track:Play()
		end
	end

	-- Apply fling force
	local direction = (survivorHrp.Position - hrp.Position).Unit
	survivorHrp.AssemblyLinearVelocity = direction * JOHN_DOE_CONFIG.Counter.FlingForce
		+ Vector3.new(0, 50, 0)
end

function CounterAbility:destroy()
	if self._connection then
		self._connection:Disconnect()
	end
end

--============================================================
-- Speed Boost Manager
--============================================================
local SpeedBoostManager = {}
SpeedBoostManager.__index = SpeedBoostManager

function SpeedBoostManager.new(ability: Types.Ability): SpeedBoostManager
	local self = setmetatable({
		_ability = ability,
		_connection = nil,
	}, SpeedBoostManager)

	if RunService:IsServer() then
		self:_startBoostLoop()
	end

	return self
end

function SpeedBoostManager:_startBoostLoop()
	local character = self._ability.OwnerProperties.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return
	end

	self._connection = RunService.Heartbeat:Connect(function()
		if not humanoid or not humanoid.Parent then
			return
		end

		if self:_shouldApplyBoost() then
			humanoid.WalkSpeed = humanoid.WalkSpeed * JOHN_DOE_CONFIG.Trail.SpeedBoost
		end
	end)
end

function SpeedBoostManager:_shouldApplyBoost(): boolean
	local loadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")

	if not loadedPlayers then
		return false
	end

	for _, playerFolder in pairs(loadedPlayers:GetChildren()) do
		local survivorCharacter = playerFolder:FindFirstChild("Character")
		if survivorCharacter and survivorCharacter:GetAttribute("JohnDoeTrailHighlighted") then
			return true
		end
	end

	return false
end

function SpeedBoostManager:destroy()
	if self._connection then
		self._connection:Disconnect()
	end
end

--============================================================
-- M1 Attack Handler
--============================================================
local M1Attack = {}
M1Attack.__index = M1Attack

function M1Attack.new(ability: Types.Ability): M1Attack
	return setmetatable({ _ability = ability }, M1Attack)
end

function M1Attack:execute()
	local hrp = self._ability.OwnerProperties.HRP

	Sounds.PlaySound(self._ability.UseSound, { Parent = hrp })

	task.delay(JOHN_DOE_CONFIG.M1.Delay, function()
		Hitbox.New(self._ability.Owner, {
			CFrameOffset = self._ability.HitboxOffset,
			Size = self._ability.HitboxSize or JOHN_DOE_CONFIG.M1.HitboxSize,
			Time = JOHN_DOE_CONFIG.M1.Duration,
			Damage = JOHN_DOE_CONFIG.M1.Damage,
			Reason = "M1 Attack",
			ExecuteOnKill = true,
		})
	end)
end

--============================================================
-- M1 Ability Initialization
--============================================================
local function M1ExtraInit(ability: Types.Ability)
	if not RunService:IsServer() then
		return
	end

	-- Initialize all sub-systems
	local corruptTrail = CorruptTrail.new(ability)
	local counterAbility = CounterAbility.new(ability)
	local speedBoost = SpeedBoostManager.new(ability)

	-- Store for cleanup
	ability._johnDoePassives = {
		trail = corruptTrail,
		counter = counterAbility,
		speedBoost = speedBoost,
	}

	-- Cleanup connections when ability is destroyed
	ability:AddConnection(function()
		if ability._johnDoePassives then
			corruptTrail:destroy()
			counterAbility:destroy()
			speedBoost:destroy()
		end
	end)
end

local function OnM1Attack(ability: Types.Ability)
	local attack = M1Attack.new(ability)
	attack:execute()
end

--============================================================
-- Character Definition
--============================================================
local JohnDoe: Types.Killer = Character.CreateKiller({
	Config = {
		Name = "John Doe",
		Quote = "Everyone deserves a second chance.",
		Render = "rbxassetid://0",
		Price = 1000,

		Origin = {
			TooltipText = "The Serial Killer",
			Icon = "rbxassetid://0",
		},

		AnimationIDs = {
			IdleAnimation = "rbxassetid://73546288362576",
			WalkAnimation = "rbxassetid://115621394601470",
			RunAnimation = "rbxassetid://102981744469535",
		},
	},

	GameplayConfig = {
		Health = 31815,
		Speed = 1.5,

		Abilities = {
			M1 = Ability.New({
				Name = "M1",
				InputName = "Slash",
				Cooldown = JOHN_DOE_CONFIG.M1.Cooldown,
				Duration = JOHN_DOE_CONFIG.M1.Duration,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://12222200",
				UICorner = true,
				Delay = JOHN_DOE_CONFIG.M1.Delay,
				HitboxSize = JOHN_DOE_CONFIG.M1.HitboxSize,
				HitboxOffset = JOHN_DOE_CONFIG.M1.HitboxOffset,
				CounterAnimationID = "rbxassetid://0",
				CustomTrailSegmentTemplate = nil,
				ExtraInit = M1ExtraInit,
				Behaviour = OnM1Attack,
			}),
		},
	},
})

--============================================================
-- UI Description
--============================================================
local NameLabel = '<font color="rgb(255, 0, 0)">' .. JohnDoe.Config.Name .. "</font>"
local M1_DAMAGE = JOHN_DOE_CONFIG.M1.Damage
local M1_COOLDOWN = JOHN_DOE_CONFIG.M1.Cooldown
local COUNTER_COOLDOWN = JOHN_DOE_CONFIG.Counter.Cooldown
local TRAIL_SPAWN = JOHN_DOE_CONFIG.Trail.SpawnInterval
local TRAIL_LIFETIME = JOHN_DOE_CONFIG.Trail.Lifetime

JohnDoe.Config.Description = {
	{
		Type = "Separator",
		Text = "GENERAL INFO",
	},
	{
		Type = "Header",
		Text = JohnDoe.Config.Name:upper(),
	},
	{
		Type = "Quote",
		Text = '"' .. JohnDoe.Config.Quote .. '"',
	},
	{
		Type = "Text",
		Text = "A hulking killer with incredible durability and extended forward reach. His bulky frame comes at the cost of slower attacks, but his corruption leaves few survivors unscathed.",
	},
	{
		Type = "Separator",
		Text = "STATS",
	},
	{
		Type = "Text",
		Text = "Health: 31,815 | Speed: +1.5 studs | M1 Damage: " .. tostring(M1_DAMAGE),
	},
	{
		Type = "Separator",
		Text = "PASSIVES",
	},
	{
		Type = "Header",
		Text = "BULKY ARM",
	},
	{
		Type = "Text",
		Text = "Extended forward reach on attacks in exchange for increased M1 cooldown ("
			.. tostring(M1_COOLDOWN)
			.. "s).",
	},
	{
		Type = "Header",
		Text = "COUNTER",
	},
	{
		Type = "Text",
		Text = "When stunned during an ability use, "
			.. NameLabel
			.. " automatically counters, entering an animation and flinging the stunner away. Cooldown: "
			.. tostring(COUNTER_COOLDOWN)
			.. "s.",
	},
	{
		Type = "Header",
		Text = "CORRUPT TRAIL",
	},
	{
		Type = "Text",
		Text = NameLabel
			.. " leaves a trail of corruption behind him. Every "
			.. tostring(TRAIL_SPAWN)
			.. "s, a segment forms on the ground lasting "
			.. tostring(TRAIL_LIFETIME)
			.. "s. Survivors who step in it become highlighted and grant "
			.. NameLabel
			.. " a 5% speed boost.",
	},
	{
		Type = "Separator",
		Text = "ABILITIES",
	},
	{
		Type = "Header",
		Text = "M1 ATTACK",
	},
	{
		Type = "Text",
		Text = NameLabel .. " swings with devastating forward reach, dealing " .. tostring(M1_DAMAGE) .. " damage.",
	},
}

return JohnDoe
