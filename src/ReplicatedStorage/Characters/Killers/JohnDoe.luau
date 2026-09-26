local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Character = require(ReplicatedStorage.Classes.Character)
local Ability = require(ReplicatedStorage.Classes.Ability)
local Hitbox = require(ReplicatedStorage.Classes.Hitbox)
local Types = require(ReplicatedStorage.Classes.Types)
local Utils = require(ReplicatedStorage.Modules.Utils)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

--============================================================
-- JOHN DOE - CHARACTER DESIGN
--============================================================
-- Health: 31,815 (well above standard)
-- Speed: 1.5 studs faster than survivor
-- M1 Damage: 26 (high)
-- M1 Hitbox: Large forward reach (extended Z depth, not width)
--
-- Passive #1 - Bulky Arm:
--   Trade-off: Longer M1 cooldown in exchange for extended forward hitbox reach
--
-- Passive #2 - Counter Ability:
--   When stunned during an ability, enters counter animation and flings stunner away
--   Cooldown: 50 seconds
--
-- Passive #3 - Corrupt Trail:
--   Continuously spawns a trail that lasts 4 seconds
--   Survivor interaction: Steps in trail -> highlighted + John Doe gets 5% speed boost
--============================================================

local M1_BASE_COOLDOWN = 2.2        -- increased from standard 2s due to Bulky Arm passive
local M1_DAMAGE = 26
local M1_HITBOX_SIZE = Vector3.new(4, 5, 7)    -- narrower width, extended forward reach (Z)
local COUNTER_COOLDOWN = 50
local TRAIL_LIFETIME = 4
local TRAIL_SPEED_BOOST = 1.05      -- 5% speed boost
local FLING_FORCE = 150             -- force for counter fling effect
local TRAIL_CHECK_INTERVAL = 0.2    -- how often to check for survivors in trail

--============================================================
-- Corrupt Trail Management
--============================================================
local function SpawnTrailEffect(Position: Vector3, CustomTrailModel: Model?)
	-- If a custom trail model is provided, clone and use it
	-- Otherwise use the default visual placeholder
	
	local TrailEffect
	
	if CustomTrailModel then
		TrailEffect = CustomTrailModel:Clone()
		TrailEffect.Parent = workspace
		TrailEffect:SetPrimaryPartCFrame(CFrame.new(Position))
	else
		-- Default placeholder trail effect
		TrailEffect = Instance.new("Part")
		TrailEffect.Name = "CorruptTrail"
		TrailEffect.Shape = Enum.PartType.Ball
		TrailEffect.Size = Vector3.new(3, 0.5, 3)
		TrailEffect.CanCollide = false
		TrailEffect.CanQuery = false
		TrailEffect.CanTouch = true
		TrailEffect.CastShadow = false
		TrailEffect.Transparency = 0.7
		TrailEffect.BrickColor = BrickColor.new("Dark indigo")
		TrailEffect.CFrame = CFrame.new(Position)
		TrailEffect.Parent = workspace
	end
	
	return TrailEffect
end

local function CheckSurvivorsInTrail(TrailEffect: Instance, JohnDoe: Model, Ability: Types.Ability)
	-- Get all survivors currently in the game
	local LoadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
	if not LoadedPlayers then
		return
	end
	
	-- Check each survivor for intersection with trail
	for _, PlayerFolder in pairs(LoadedPlayers:GetChildren()) do
		local SurvivorCharacter = PlayerFolder:FindFirstChild("Character")
		if not SurvivorCharacter or not SurvivorCharacter.PrimaryPart then
			continue
		end
		
		-- Calculate distance between trail and survivor
		local Distance = (SurvivorCharacter.PrimaryPart.Position - TrailEffect.Position).Magnitude
		local CheckRadius = (TrailEffect.Size.X + TrailEffect.Size.Z) / 2 + 3 -- radius of trail effect
		
		if Distance <= CheckRadius then
			-- Survivor is in the trail
			-- Apply highlight
			local Humanoid = SurvivorCharacter:FindFirstChildOfClass("Humanoid")
			if Humanoid and not SurvivorCharacter:GetAttribute("JohnDoeTrailHighlighted") then
				SurvivorCharacter:SetAttribute("JohnDoeTrailHighlighted", true)
				
				-- TODO: Implement highlighting visual (outline, glow, etc.)
				-- Example: Add highlight object or modify character appearance
				
				-- Apply speed boost to John Doe
				if Ability then
					Ability.OwnerProperties.Character:SetAttribute("JohnDoeTrailSpeedActive", true)
				end
				
				-- Remove highlight after trail lifetime expires
				task.delay(TRAIL_LIFETIME, function()
					if SurvivorCharacter and SurvivorCharacter.Parent then
						SurvivorCharacter:SetAttribute("JohnDoeTrailHighlighted", false)
						-- TODO: Remove highlighting visual
					end
				end)
			end
		end
	end
end

local function UpdateCorruptTrail(self: Types.Ability)
	if not RunService:IsServer() then
		return
	end

	local HRP = self.OwnerProperties.HRP
	local Character = self.OwnerProperties.Character
	local TrailSpawnInterval = 0.3 -- spawn a trail effect every 0.3 seconds
	local LastTrailSpawn = os.clock()
	
	-- Check for survivors in trail periodically
	local LastSurvivorCheck = os.clock()
	
	self:AddConnection(RunService.Heartbeat:Connect(function()
		if not HRP or not HRP.Parent then
			return
		end
		
		local Now = os.clock()
		
		-- Spawn trail effects at intervals
		if Now - LastTrailSpawn >= TrailSpawnInterval then
			LastTrailSpawn = Now
			
			-- Spawn trail slightly behind John Doe
			local TrailPosition = HRP.Position - HRP.CFrame.LookVector * 3
			local TrailEffect = SpawnTrailEffect(TrailPosition, self.CustomTrailModel)
			
			-- Store trail in ability for reference
			if not self.ActiveTrails then
				self.ActiveTrails = {}
			end
			table.insert(self.ActiveTrails, TrailEffect)
			
			-- Destroy trail after lifetime
			task.delay(TRAIL_LIFETIME, function()
				if TrailEffect and TrailEffect.Parent then
					TrailEffect:Destroy()
				end
			end)
		end
		
		-- Check for survivors in recent trails
		if Now - LastSurvivorCheck >= TRAIL_CHECK_INTERVAL then
			LastSurvivorCheck = Now
			
			if self.ActiveTrails then
				for _, TrailEffect in pairs(self.ActiveTrails) do
					if TrailEffect and TrailEffect.Parent then
						CheckSurvivorsInTrail(TrailEffect, Character, self)
					end
				end
			end
		end
	end))
end

--============================================================
-- Counter Ability - Stun Deflection (Passive #2)
--============================================================
local function InitializeCounterAbility(self: Types.Ability)
	if not RunService:IsServer() then
		return
	end
	
	local Character = self.OwnerProperties.Character
	local HRP = self.OwnerProperties.HRP
	self.NextCounterAllowedAt = os.clock()
	
	-- Monitor for stun status during ability use
	-- A stun is typically applied via Humanoid:ApplyDescription or SetStateEnabled
	self:AddConnection(RunService.Heartbeat:Connect(function()
		if not HRP or not HRP.Parent then
			return
		end
		
		local Humanoid = Character:FindFirstChildOfClass("Humanoid")
		if not Humanoid then
			return
		end
		
		local Now = os.clock()
		
		-- Check if currently stunned (Humanoid.State includes Stunned state)
		-- State 14 is Enum.HumanoidStateType.Stunned
		local IsCurrentlyStunned = Humanoid:GetState() == Enum.HumanoidStateType.Stunned
		
		-- Track previous stun state to detect the moment of stun
		if not self.WasStunnedLastFrame then
			self.WasStunnedLastFrame = false
		end
		
		-- Stun just applied
		if IsCurrentlyStunned and not self.WasStunnedLastFrame then
			self.WasStunnedLastFrame = true
			
			-- Check if counter is available
			if Now >= self.NextCounterAllowedAt then
				self.NextCounterAllowedAt = Now + COUNTER_COOLDOWN
				
				-- TODO: Find the survivor who stunned John Doe
				-- This requires tracking who applied the stun
				-- For now, we'll get nearby survivors
				
				local LoadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
				if LoadedPlayers then
					-- Find closest survivor to potentially fling
					local ClosestSurvivor = nil
					local ClosestDistance = 50 -- 50 stud search radius
					
					for _, PlayerFolder in pairs(LoadedPlayers:GetChildren()) do
						local SurvivorCharacter = PlayerFolder:FindFirstChild("Character")
						if SurvivorCharacter and SurvivorCharacter.PrimaryPart then
							local Distance = (SurvivorCharacter.PrimaryPart.Position - HRP.Position).Magnitude
							if Distance < ClosestDistance then
								ClosestDistance = Distance
								ClosestSurvivor = SurvivorCharacter
							end
						end
					end
					
					-- Execute counter if survivor found
					if ClosestSurvivor then
						ExecuteCounterFling(self, ClosestSurvivor)
					end
				end
			end
		elseif not IsCurrentlyStunned then
			self.WasStunnedLastFrame = false
		end
	end))
end

local function ExecuteCounterFling(self: Types.Ability, SurvivorCharacter: Model)
	if not SurvivorCharacter or not SurvivorCharacter.PrimaryPart then
		return
	end
	
	local HRP = self.OwnerProperties.HRP
	local SurvivorHRP = SurvivorCharacter.PrimaryPart
	
	-- Calculate direction away from John Doe
	local Direction = (SurvivorHRP.Position - HRP.Position).Unit
	
	-- Apply fling velocity to survivor
	local Humanoid = SurvivorCharacter:FindFirstChildOfClass("Humanoid")
	if Humanoid then
		-- Play counter animation on John Doe (TODO: Add animation ID)
		if self.CounterAnimationID and self.CounterAnimationID ~= "rbxassetid://0" then
			local CounterTrack = Utils.Character.LoadAnimationFromID(self.OwnerProperties.Character, self.CounterAnimationID)
			if CounterTrack then
				CounterTrack:Play()
			end
		end
		
		-- Apply fling force to survivor
		SurvivorHRP.AssemblyLinearVelocity = Direction * FLING_FORCE + Vector3.new(0, 50, 0)
	end
end

--============================================================
-- M1 Attack Setup
--============================================================
local function OnM1Attack(self: Types.Ability)
	local Character = self.OwnerProperties.Character
	local HRP = self.OwnerProperties.HRP
	
	Sounds.PlaySound(self.UseSound, {Parent = HRP})
	
	task.delay(self.Delay, function()
		Hitbox.New(self.Owner, {
			CFrameOffset = self.HitboxOffset,
			Size = self.HitboxSize or M1_HITBOX_SIZE,
			Time = self.Duration,
			Damage = M1_DAMAGE,
			Reason = "M1 Attack",
			ExecuteOnKill = true,
		})
	end)
end

--============================================================
-- Speed Boost Handler for Corrupt Trail
--============================================================
local function HandleTrailSpeedBoost(self: Types.Ability)
	if not RunService:IsServer() then
		return
	end
	
	local Character = self.OwnerProperties.Character
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	
	if not Humanoid then
		return
	end
	
	-- Monitor speed boost state
	self:AddConnection(RunService.Heartbeat:Connect(function()
		if not Humanoid or not Humanoid.Parent then
			return
		end
		
		-- Check if any survivors are highlighted by trail
		local ShouldBoost = false
		local LoadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
		
		if LoadedPlayers then
			for _, PlayerFolder in pairs(LoadedPlayers:GetChildren()) do
				local SurvivorCharacter = PlayerFolder:FindFirstChild("Character")
				if SurvivorCharacter and SurvivorCharacter:GetAttribute("JohnDoeTrailHighlighted") then
					ShouldBoost = true
					break
				end
			end
		end
		
		-- Apply or remove speed boost
		if ShouldBoost then
			Humanoid.WalkSpeed = Humanoid.WalkSpeed * TRAIL_SPEED_BOOST
		end
	end))
end

--============================================================
-- Ability Extra Initialization
--============================================================
local function M1ExtraInit(self: Types.Ability)
	if RunService:IsServer() then
		-- Initialize Corrupt Trail (Passive #3)
		UpdateCorruptTrail(self)
		
		-- Initialize Counter Ability (Passive #2)
		InitializeCounterAbility(self)
		
		-- Initialize speed boost handler
		HandleTrailSpeedBoost(self)
	end
end

--============================================================
-- Character Definition
--============================================================
local JohnDoe: Types.Killer = Character.CreateKiller({
	Config = {
		Name = "John Doe",
		Quote = "Everyone deserves a second chance.",
		Render = "rbxassetid://0", -- TODO: Add John Doe render
		Price = 1000, -- Placeholder price
		
		Origin = {
			TooltipText = "The Serial Killer",
			Icon = "rbxassetid://0", -- TODO: Add icon
		},
		
		-- TODO: Create custom movement animations or use engine defaults
		AnimationIDs = {
			IdleAnimation = "rbxassetid://73546288362576",
			WalkAnimation = "rbxassetid://115621394601470",
			RunAnimation = "rbxassetid://102981744469535",
		},
	},
	
	GameplayConfig = {
		-- John Doe stats
		Health = 31815,
		Speed = 1.5, -- 1.5 studs faster than survivor
		
		Abilities = {
			-- M1 Attack - High damage with extended forward reach, longer cooldown (Bulky Arm passive)
			M1 = Ability.New({
				Name = "M1",
				InputName = "Slash",
				Cooldown = M1_BASE_COOLDOWN, -- Bulky Arm: Increased cooldown
				Duration = 0.4,
				RenderImage = "rbxassetid://0", -- TODO: M1 icon
				UseSound = "rbxassetid://12222200",
				UICorner = true,
				Delay = 0.1,
				HitboxSize = M1_HITBOX_SIZE,
				HitboxOffset = CFrame.new(0, 0, -3.5), -- offset forward to match extended reach
				
				-- Counter Animation ID (TODO: Add counter animation asset ID)
				CounterAnimationID = "rbxassetid://0",
				
				-- Custom Trail Model (optional - set to a model in ReplicatedStorage for custom visuals)
				CustomTrailModel = nil, -- TODO: Assign a custom trail model from ReplicatedStorage
				
				ExtraInit = M1ExtraInit,
				Behaviour = OnM1Attack,
			}),
		},
	},
})

--============================================================
-- Description (UI text for killer selection)
--============================================================
local NameLabel = '<font color="rgb(255, 0, 0)">' .. JohnDoe.Config.Name .. "</font>"

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
		Text = "Extended forward reach on attacks in exchange for increased M1 cooldown (" .. tostring(M1_BASE_COOLDOWN) .. "s).",
	},
	{
		Type = "Header",
		Text = "COUNTER",
	},
	{
		Type = "Text",
		Text = "When stunned during an ability use, " .. NameLabel .. " automatically counters, entering an animation and flinging the stunner away. Cooldown: " .. tostring(COUNTER_COOLDOWN) .. "s.",
	},
	{
		Type = "Header",
		Text = "CORRUPT TRAIL",
	},
	{
		Type = "Text",
		Text = NameLabel .. " continuously spawns a corrupted trail that lasts " .. tostring(TRAIL_LIFETIME) .. " seconds. Survivors who step in the trail are highlighted for " .. tostring(TRAIL_LIFETIME) .. "s and grant " .. NameLabel .. " a 5% speed boost.",
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
