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
-- M1 Hitbox: Large
--
-- Passive #1 - Bulky Arm:
--   Trade-off: Longer M1 cooldown in exchange for extended hitbox reach
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
local M1_HITBOX_SIZE = Vector3.new(6.5, 6.5, 5.5) -- larger than standard
local COUNTER_COOLDOWN = 50
local TRAIL_LIFETIME = 4
local TRAIL_SPEED_BOOST = 1.05      -- 5% speed boost
local FLING_FORCE = 150             -- force for counter fling effect

--============================================================
-- Corrupt Trail Management
--============================================================
local function UpdateCorruptTrail(self: Types.Ability)
	if not RunService:IsServer() then
		return
	end

	local HRP = self.OwnerProperties.HRP
	local Character = self.OwnerProperties.Character
	
	-- Create trail particles/effects at regular intervals
	self:AddConnection(RunService.Heartbeat:Connect(function()
		if not HRP or not HRP.Parent then
			return
		end
		
		-- TODO: Create visual trail effect at HRP position
		-- This should spawn a visible effect that lasts TRAIL_LIFETIME seconds
		-- and applies highlight/speed boost to survivors who step in it
		
		local TrailEffect = Instance.new("Part")
		TrailEffect.Name = "CorruptTrail"
		TrailEffect.Shape = Enum.PartType.Ball
		TrailEffect.Size = Vector3.new(3, 0.5, 3)
		TrailEffect.CanCollide = false
		TrailEffect.CanQuery = false
		TrailEffect.CanTouch = true
		TrailEffect.CastShadow = false
		TrailEffect.Transparency = 0.7
		TrailEffect.BrickColor = BrickColor.new("Dark indigo")
		TrailEffect.CFrame = HRP.CFrame - HRP.CFrame.LookVector * 3
		TrailEffect.Parent = workspace
		
		-- Touched event for survivor interaction
		local Touched = false
		TrailEffect.Touched:Connect(function(Hit)
			if Touched then return end
			
			-- TODO: Check if Hit is a survivor
			-- If survivor: highlight them and apply speed boost to John Doe
			Touched = true
		end)
		
		task.delay(TRAIL_LIFETIME, function()
			TrailEffect:Destroy()
		end)
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
	self.NextCounterAllowedAt = os.clock()
	
	-- Monitor for stun status
	self:AddConnection(RunService.Heartbeat:Connect(function()
		-- TODO: Check if character is being stunned during ability use
		-- If so and counter is available:
		--   1. Cancel the stun
		--   2. Play counter animation
		--   3. Fling the stunner away
		--   4. Set counter on cooldown
	end))
end

local function ExecuteCounterFling(self: Types.Ability, StunnerCharacter: Model)
	if not StunnerCharacter or not StunnerCharacter.PrimaryPart then
		return
	end
	
	local HRP = self.OwnerProperties.HRP
	local StunnerHRP = StunnerCharacter.PrimaryPart
	
	-- Calculate direction away from John Doe
	local Direction = (StunnerHRP.Position - HRP.Position).Unit
	
	-- Apply fling velocity to stunner
	local Humanoid = StunnerCharacter:FindFirstChildOfClass("Humanoid")
	if Humanoid then
		-- TODO: Play counter animation placeholder
		-- TODO: Apply fling force to stunner
		StunnerHRP.AssemblyLinearVelocity = Direction * FLING_FORCE
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
			-- M1 Attack - High damage with large hitbox, longer cooldown (Bulky Arm passive)
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
				HitboxOffset = CFrame.new(0, 0, -2.5),
				
				Behaviour = OnM1Attack,
			}),
		},
	},
})

--============================================================
-- Initialize Passives
--============================================================
-- This runs when the killer spawns
local function InitializeJohnDoe(self: Types.Killer)
	if not RunService:IsServer() then
		return
	end
	
	-- TODO: Initialize all three passives here
	-- Passive #1: Bulky Arm - Already implemented via M1 cooldown
	-- Passive #2: Counter - Initialize counter tracking
	-- Passive #3: Corrupt Trail - Start trail spawning
end

-- Placeholder for ability initialization
local function M1ExtraInit(self: Types.Ability)
	if RunService:IsServer() then
		-- TODO: Additional M1 setup if needed
	end
end

-- Update M1 ability with extra init
JohnDoe.GameplayConfig.Abilities.M1.ExtraInit = M1ExtraInit

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
		Text = "A hulking killer with incredible durability and a powerful reach. His bulky frame comes at the cost of slower attacks, but his corruption leaves few survivors unscathed.",
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
		Text = "Extended hitbox reach in exchange for increased M1 cooldown.",
	},
	{
		Type = "Header",
		Text = "COUNTER",
	},
	{
		Type = "Text",
		Text = "When stunned during an ability use, " .. NameLabel .. " enters a counter animation and flings the stunner away. Cooldown: " .. tostring(COUNTER_COOLDOWN) .. "s.",
	},
	{
		Type = "Header",
		Text = "CORRUPT TRAIL",
	},
	{
		Type = "Text",
		Text = NameLabel .. " continuously spawns a corrupted trail that lasts " .. tostring(TRAIL_LIFETIME) .. " seconds. Survivors who step in the trail are highlighted and grant " .. NameLabel .. " a 5% speed boost.",
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
		Text = NameLabel .. " swings with devastating force, dealing " .. tostring(M1_DAMAGE) .. " damage with a large hitbox.",
	},
}

return JohnDoe
