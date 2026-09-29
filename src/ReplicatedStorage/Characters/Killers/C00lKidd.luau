local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Character = require(ReplicatedStorage.Classes.Character)
local Ability = require(ReplicatedStorage.Classes.Ability)
local Hitbox = require(ReplicatedStorage.Classes.Hitbox)
local Projectile = require(ReplicatedStorage.Classes.Projectile)
local Types = require(ReplicatedStorage.Classes.Types)
local Utils = require(ReplicatedStorage.Modules.Utils)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

--============================================================
-- C00lKidd Configuration
--============================================================
local C00LKIDD_CONFIG = {
	Stats = {
		Health = 2014,
		BaseSpeed = 12,
		SprintSpeedMultiplier = 26 / 12,
		StaminaDrain = 9.5,
		StaminaRegen = 12,
	},
	M1 = {
		Cooldown = 2,
		Damage = 20,
		HitboxSize = Vector3.new(5, 6, 4.5),
		HitboxOffset = CFrame.new(0, 0, -2.5),
		Delay = 0.1,
		Duration = 0.4,
	},
	FollowUp = {
		Cooldown = 0.8,
		Damage = 8,
		BurningDamage = 7,
		HitboxSize = Vector3.new(3, 3, 2),
		HitboxOffset = CFrame.new(0, 0, -2),
		Slowness = 2,
		SlownessDuration = 3,
		MissDuration = 2,
	},
	C00GuiCreation = {
		Cooldown = 27,
		ProjectileSpeed = 110,
		ProjectileLifetime = 2.4,
		ProjectileDamage = 0,
		TeleportDistance = 60,
		FlingForce = 120,
		FlingUpward = 55,
	},
	ScriptWave = {
		Cooldown = 35,
		WaveDamage = 10,
		WaveFreezeDuration = 2,
		SlownessDuration = 1,
		SlownessLevel = 1,
		FlingForce = 75,
		FlingUpward = 35,
	},
	Inject = {
		Cooldown = 12,
		ProjectileSpeed = 90,
		ProjectileLifetime = 0.75,
		ProjectileDamage = 5,
		ProjectileSize = Vector3.new(2, 2, 3),
		ProjectileOffset = CFrame.new(0, 1, -2),
		CorruptionDuration = 40,
		CorruptionStackMax = 3,
		WeaknessPerStack = 5,
		WeaknessMax = 15,
		ReelInForce = 90,
		ReelInUpward = 35,
	},
	StackOverflow = {
		Cooldown = 40,
		ExplosionDamage = 15,
		ExplosionRadius = 8,
		BlastRadius = 9,
		SpeedBoost = 4,
		SpeedBoostDuration = 5,
		HighlightDuration = 5,
		SlowSpeed = 8,
	},
}

--============================================================
-- Corruption Manager Class
--============================================================
local CorruptionManager = {}
CorruptionManager.__index = CorruptionManager

function CorruptionManager.new(killerCharacter: Model): CorruptionManager
	local self = setmetatable({
		_killerCharacter = killerCharacter,
		_victimCorruption = {},
	}, CorruptionManager)
	return self
end

function CorruptionManager:ApplyCorruption(victim: Model, stacksToAdd: number): number
	if not victim or not victim.Parent then
		return 0
	end

	local currentStacks = self:GetStacks(victim)
	local newStacks = math.clamp(currentStacks + stacksToAdd, 0, C00LKIDD_CONFIG.Inject.CorruptionStackMax)
	local weakness = math.min(C00LKIDD_CONFIG.Inject.WeaknessMax, newStacks * C00LKIDD_CONFIG.Inject.WeaknessPerStack)

	victim:SetAttribute("C00lKiddCorruptionStacks", newStacks)
	victim:SetAttribute("C00lKiddCorruptionWeakness", weakness)
	victim:SetAttribute("C00lKiddCorruptionExpiresAt", os.clock() + C00LKIDD_CONFIG.Inject.CorruptionDuration)

	return newStacks
end

function CorruptionManager:GetStacks(victim: Model): number
	if not victim then
		return 0
	end
	return tonumber(victim:GetAttribute("C00lKiddCorruptionStacks")) or 0
end

function CorruptionManager:GetWeakness(victim: Model): number
	if not victim then
		return 0
	end
	return tonumber(victim:GetAttribute("C00lKiddCorruptionWeakness")) or 0
end

function CorruptionManager:ResetCorruption(victim: Model)
	if not victim then
		return
	end
	victim:SetAttribute("C00lKiddCorruptionStacks", 0)
	victim:SetAttribute("C00lKiddCorruptionWeakness", 0)
	victim:SetAttribute("C00lKiddCorruptionExpiresAt", 0)
end

--============================================================
-- M1 Attack Handler Class
--============================================================
local M1Attack = {}
M1Attack.__index = M1Attack

function M1Attack.new(ability: Types.Ability): M1Attack
	return setmetatable({
		_ability = ability,
		_lastInjectTime = 0,
	}, M1Attack)
end

function M1Attack:_playSound()
	local hrp = self._ability.OwnerProperties.HRP
	Sounds.PlaySound(self._ability.UseSound, { Parent = hrp })
end

function M1Attack:_executeHitbox(damage: number, hitboxSize: Vector3, hitboxOffset: CFrame, reason: string, effectsToApply: any)
	local owner = self._ability.Owner
	task.delay(C00LKIDD_CONFIG.M1.Delay, function()
		Hitbox.New(owner, {
			CFrameOffset = hitboxOffset,
			Size = hitboxSize,
			Time = C00LKIDD_CONFIG.M1.Duration,
			Damage = damage,
			Reason = reason,
			ExecuteOnKill = true,
			EffectsToApply = effectsToApply,
		})
	end)
end

function M1Attack:execute()
	self:_playSound()

	local character = self._ability.OwnerProperties.Character
	local currentTime = os.clock()
	local timeSinceInject = currentTime - self._lastInjectTime

	if timeSinceInject <= C00LKIDD_CONFIG.FollowUp.Cooldown then
		-- Follow-up swing
		self:_executeHitbox(
			C00LKIDD_CONFIG.FollowUp.Damage,
			C00LKIDD_CONFIG.FollowUp.HitboxSize,
			C00LKIDD_CONFIG.FollowUp.HitboxOffset,
			"C00lKidd Sword Follow-up",
			{
				{ Name = "Burning", Level = 7, Duration = 3 },
				{ Name = "Slowness", Level = C00LKIDD_CONFIG.FollowUp.Slowness, Duration = C00LKIDD_CONFIG.FollowUp.SlownessDuration },
			}
		)
	else
		-- Normal swing
		self:_executeHitbox(
			C00LKIDD_CONFIG.M1.Damage,
			C00LKIDD_CONFIG.M1.HitboxSize,
			C00LKIDD_CONFIG.M1.HitboxOffset,
			"C00lKidd M1 Attack",
			nil
		)
	end
end

function M1Attack:markInjectTime()
	self._lastInjectTime = os.clock()
end

--============================================================
-- C00Gui Creation Ability Handler Class
--============================================================
local C00GuiAbility = {}
C00GuiAbility.__index = C00GuiAbility

function C00GuiAbility.new(ability: Types.Ability): C00GuiAbility
	return setmetatable({
		_ability = ability,
	}, C00GuiAbility)
end

function C00GuiAbility:_slowCharacter(duration: number)
	local humanoid = self._ability.OwnerProperties.Humanoid
	if not humanoid then
		return
	end

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 7
	task.delay(duration, function()
		if humanoid.Parent then
			humanoid.WalkSpeed = originalSpeed
		end
	end)
end

function C00GuiAbility:_createProjectile()
	local hrp = self._ability.OwnerProperties.HRP
	local killerCharacter = self._ability.OwnerProperties.Character

	local projectile = Instance.new("Part")
	projectile.Name = "C00GuiArrow"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.5, 1.5, 3)
	projectile.Material = Enum.Material.Neon
	projectile.BrickColor = BrickColor.new("Sea green")
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.CanTouch = false
	projectile.CastShadow = false
	projectile.Anchored = true

	local origin = hrp.CFrame * CFrame.new(0, 0.5, -4)
	projectile.CFrame = origin

	local targetHit = false
	Projectile.New({
		SourcePlayer = self._ability.Owner,
		Model = projectile,
		StartingCFrame = origin,
		Speed = C00LKIDD_CONFIG.C00GuiCreation.ProjectileSpeed,
		Lifetime = C00LKIDD_CONFIG.C00GuiCreation.ProjectileLifetime,
		ThrowType = "Forward",
		DestroyOnCollision = true,
		HitboxSettings = {
			Size = Vector3.new(2.4, 2.4, 3.2),
			Shape = Enum.PartType.Ball,
			Damage = C00LKIDD_CONFIG.C00GuiCreation.ProjectileDamage,
			Reason = "C00Gui Creation",
			HitMultiple = false,
			Connections = {
				Hit = function()
					if targetHit then
						return
					end
					targetHit = true
					self:_onProjectileHit(hrp, killerCharacter)
				end,
			},
		},
	})
end

function C00GuiAbility:_onProjectileHit(killerHrp: BasePart, killerCharacter: Model)
	local loadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
	if not loadedPlayers then
		return
	end

	-- Find closest survivor
	local closestSurvivor = nil
	local closestDistance = math.huge
	for _, folder in ipairs(loadedPlayers:GetChildren()) do
		local victim = folder:FindFirstChild("Character")
		if victim and victim.PrimaryPart then
			local dist = (victim.PrimaryPart.Position - killerHrp.Position).Magnitude
			if dist < closestDistance then
				closestDistance = dist
				closestSurvivor = victim
			end
		end
	end

	if not closestSurvivor or not closestSurvivor.PrimaryPart then
		return
	end

	local victimRoot = closestSurvivor.PrimaryPart
	local teleportDir = (killerHrp.Position - victimRoot.Position).Unit
	local teleportPos = victimRoot.Position + teleportDir * C00LKIDD_CONFIG.C00GuiCreation.TeleportDistance

	killerCharacter:PivotTo(CFrame.new(teleportPos, victimRoot.Position))

	local flingVector = (victimRoot.Position - killerHrp.Position).Unit * C00LKIDD_CONFIG.C00GuiCreation.FlingForce
		+ Vector3.new(0, C00LKIDD_CONFIG.C00GuiCreation.FlingUpward, 0)
	victimRoot.AssemblyLinearVelocity = flingVector
end

function C00GuiAbility:execute()
	self:_slowCharacter(0.8)
	self:_createProjectile()
end

--============================================================
-- Script Wave Ability Handler Class
--============================================================
local ScriptWaveAbility = {}
ScriptWaveAbility.__index = ScriptWaveAbility

function ScriptWaveAbility.new(ability: Types.Ability): ScriptWaveAbility
	return setmetatable({
		_ability = ability,
	}, ScriptWaveAbility)
end

function ScriptWaveAbility:_slowCharacter(duration: number)
	local humanoid = self._ability.OwnerProperties.Humanoid
	if not humanoid then
		return
	end

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 8
	task.delay(duration, function()
		if humanoid.Parent then
			humanoid.WalkSpeed = originalSpeed
		end
	end)
end

function ScriptWaveAbility:_createWaveZone(position: CFrame)
	local zone = Instance.new("Part")
	zone.Name = "ScriptWaveZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.Size = Vector3.new(7, 1, 12)
	zone.CFrame = position
	zone.Material = Enum.Material.Neon
	zone.BrickColor = BrickColor.new("Electric blue")
	zone.Transparency = 0.5
	zone.Parent = workspace

	task.delay(0.15, function()
		if zone.Parent then
			zone:Destroy()
		end
	end)
end

function ScriptWaveAbility:_createWave(offset: number)
	local hrp = self._ability.OwnerProperties.HRP
	local forward = hrp.CFrame * CFrame.new(offset * 2, 0, -12)

	self:_createWaveZone(forward)

	Hitbox.New(self._ability.Owner, {
		CFrameOffset = CFrame.new(offset * 2, 0, -12),
		Size = Vector3.new(7, 4, 12),
		Time = 0.35,
		Damage = C00LKIDD_CONFIG.ScriptWave.WaveDamage,
		Reason = "Script Wave",
		ExecuteOnKill = true,
		Connections = {
			Hit = function(hitInfo)
				if not hitInfo or not hitInfo.HumanoidsHit or #hitInfo.HumanoidsHit == 0 then
					return
				end
				local target = hitInfo.HumanoidsHit[1]
				if not target or not target.Parent then
					return
				end
				self:_onWaveHit(target.Parent, hrp)
			end,
		},
	})
end

function ScriptWaveAbility:_onWaveHit(victim: Model, killerHrp: BasePart)
	local victimRoot = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
	if not victimRoot then
		return
	end

	local flingDir = (victimRoot.Position - killerHrp.Position).Unit
	local flingVector = flingDir * C00LKIDD_CONFIG.ScriptWave.FlingForce
		+ Vector3.new(0, C00LKIDD_CONFIG.ScriptWave.FlingUpward, 0)
	victimRoot.AssemblyLinearVelocity = flingVector

	-- Apply freeze
	victim:SetAttribute("C00lKiddFrozen", true)
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local originalSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0.1
		task.delay(C00LKIDD_CONFIG.ScriptWave.WaveFreezeDuration, function()
			if humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
				victim:SetAttribute("C00lKiddFrozen", false)
			end
		end)
	end
end

function ScriptWaveAbility:execute()
	self:_slowCharacter(0.8)

	for offset = -2, 2, 2 do
		self:_createWave(offset)
	end
end

--============================================================
-- Inject Ability Handler Class
--============================================================
local InjectAbility = {}
InjectAbility.__index = InjectAbility

function InjectAbility.new(ability: Types.Ability, corruptionManager: CorruptionManager, m1Attack: M1Attack): InjectAbility
	return setmetatable({
		_ability = ability,
		_corruptionManager = corruptionManager,
		_m1Attack = m1Attack,
	}, InjectAbility)
end

function InjectAbility:_createProjectile()
	local hrp = self._ability.OwnerProperties.HRP
	local killerCharacter = self._ability.OwnerProperties.Character

	local projectile = Instance.new("Part")
	projectile.Name = "ScriptInjection"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.6, 1.6, 1.6)
	projectile.Material = Enum.Material.Neon
	projectile.BrickColor = BrickColor.new("Lime green")
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.CanTouch = false
	projectile.CastShadow = false
	projectile.Anchored = true
	projectile.Transparency = 0.15

	local origin = hrp.CFrame * C00LKIDD_CONFIG.Inject.ProjectileOffset

	Projectile.New({
		SourcePlayer = self._ability.Owner,
		Model = projectile,
		StartingCFrame = origin,
		Speed = C00LKIDD_CONFIG.Inject.ProjectileSpeed,
		Lifetime = C00LKIDD_CONFIG.Inject.ProjectileLifetime,
		ThrowType = "Forward",
		DestroyOnCollision = true,
		HitboxSettings = {
			Size = C00LKIDD_CONFIG.Inject.ProjectileSize,
			Shape = Enum.PartType.Ball,
			Damage = C00LKIDD_CONFIG.Inject.ProjectileDamage,
			Reason = "Script Injection",
			HitMultiple = false,
			Connections = {
				Hit = function(hitInfo)
					if not hitInfo or not hitInfo.HumanoidsHit or #hitInfo.HumanoidsHit == 0 then
						return
					end
					local target = hitInfo.HumanoidsHit[1]
					if not target or not target.Parent then
						return
					end
					self:_onProjectileHit(target.Parent, hrp, killerCharacter)
				end,
			},
		},
	})
end

function InjectAbility:_onProjectileHit(victim: Model, killerHrp: BasePart, killerCharacter: Model)
	local stacks = self._corruptionManager:ApplyCorruption(victim, 1)
	self._m1Attack:markInjectTime()

	if stacks >= C00LKIDD_CONFIG.Inject.CorruptionStackMax then
		-- Reel in
		local victimRoot = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
		if victimRoot then
			local pullDir = (killerHrp.Position - victimRoot.Position).Unit
			local pullVector = pullDir * C00LKIDD_CONFIG.Inject.ReelInForce
				+ Vector3.new(0, C00LKIDD_CONFIG.Inject.ReelInUpward, 0)
			victimRoot.AssemblyLinearVelocity = pullVector
		end
	end
end

function InjectAbility:execute()
	if not RunService:IsServer() then
		return
	end

	self:_createProjectile()
end

--============================================================
-- Stack Overflow Ability Handler Class
--============================================================
local StackOverflowAbility = {}
StackOverflowAbility.__index = StackOverflowAbility

function StackOverflowAbility.new(ability: Types.Ability): StackOverflowAbility
	return setmetatable({
		_ability = ability,
	}, StackOverflowAbility)
end

function StackOverflowAbility:_getSpawns(): { Instance }
	local spawns = {}
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("SpawnLocation") then
			table.insert(spawns, instance)
		elseif instance:IsA("Part") and instance.Name:lower():find("spawn") then
			table.insert(spawns, instance)
		end
	end
	return spawns
end

function StackOverflowAbility:_applyExplosion(spawn: Instance)
	local explosion = Instance.new("Explosion")
	explosion.Position = spawn.Position
	explosion.BlastRadius = 8
	explosion.BlastPressure = 0
	explosion.Parent = workspace

	for _, victim in ipairs(workspace:GetChildren()) do
		if victim:IsA("Model") and victim:FindFirstChildOfClass("Humanoid") then
			local victimRoot = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
			if victimRoot and (victimRoot.Position - spawn.Position).Magnitude <= C00LKIDD_CONFIG.StackOverflow.BlastRadius then
				victim:SetAttribute("C00lKiddHighlighted", true)
				task.delay(C00LKIDD_CONFIG.StackOverflow.HighlightDuration, function()
					if victim and victim.Parent then
						victim:SetAttribute("C00lKiddHighlighted", false)
					end
				end)

				local humanoid = victim:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:TakeDamage(C00LKIDD_CONFIG.StackOverflow.ExplosionDamage)
				end
			end
		end
	end
end

function StackOverflowAbility:_slowCharacter(duration: number)
	local humanoid = self._ability.OwnerProperties.Humanoid
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = C00LKIDD_CONFIG.StackOverflow.SlowSpeed
	task.delay(duration, function()
		if humanoid.Parent then
			humanoid.WalkSpeed = 16 + C00LKIDD_CONFIG.StackOverflow.SpeedBoost
		end
	end)
	task.delay(C00LKIDD_CONFIG.StackOverflow.SpeedBoostDuration, function()
		if humanoid.Parent then
			humanoid.WalkSpeed = 16
		end
	end)
end

function StackOverflowAbility:execute()
	if not RunService:IsServer() then
		return
	end

	local spawns = self:_getSpawns()
	if #spawns == 0 then
		return
	end

	self:_slowCharacter(0.4)

	for _, spawn in ipairs(spawns) do
		self:_applyExplosion(spawn)
		task.wait(0.08)
	end

	local randomSpawn = spawns[math.random(1, #spawns)]
	if randomSpawn then
		local character = self._ability.OwnerProperties.Character
		character:PivotTo(CFrame.new(randomSpawn.Position + Vector3.new(0, 5, 0)))
	end
end

--============================================================
-- Character Definition
--============================================================
local C00lKidd: Types.Killer = Character.CreateKiller({
	Config = {
		Name = "C00lKidd",
		Quote = "Corruption is the only language I know.",
		Render = "rbxassetid://73281933925265",
		Price = -1,

		Origin = {
			TooltipText = "C00lkidd:)",
			Icon = "rbxassetid://118316894840539",
		},

		AnimationIDs = {
			IdleAnimation = "rbxassetid://73546288362576",
			WalkAnimation = "rbxassetid://115621394601470",
			RunAnimation = "rbxassetid://102981744469535",
		},
	},

	GameplayConfig = {
		Health = C00LKIDD_CONFIG.Stats.Health,
		BaseSpeed = C00LKIDD_CONFIG.Stats.BaseSpeed,
		SprintSpeedMultiplier = C00LKIDD_CONFIG.Stats.SprintSpeedMultiplier,
		StaminaProperties = {
			MaxStamina = 100,
			StaminaDrain = C00LKIDD_CONFIG.Stats.StaminaDrain,
			StaminaGain = C00LKIDD_CONFIG.Stats.StaminaRegen,
		},

		Abilities = {
			Slash = Ability.New({
				Name = "Slash",
				InputName = "Slash",
				Cooldown = C00LKIDD_CONFIG.M1.Cooldown,
				Duration = C00LKIDD_CONFIG.M1.Duration,
				RenderImage = "rbxassetid://11218451110",
				UseSound = "rbxassetid://12222200",
				UICorner = true,
				Delay = C00LKIDD_CONFIG.M1.Delay,
				HitboxSize = C00LKIDD_CONFIG.M1.HitboxSize,
				HitboxOffset = C00LKIDD_CONFIG.M1.HitboxOffset,
				PlayUseAnimationOnUse = true,
				ExtraInit = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					self._m1Attack = M1Attack.new(self)
				end,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					if self._m1Attack then
						self._m1Attack:execute()
					end
				end,
			}),

			C00GuiCreation = Ability.New({
				Name = "C00Gui Creation",
				InputName = "FirstAbility",
				Cooldown = C00LKIDD_CONFIG.C00GuiCreation.Cooldown,
				Duration = 0.8,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				DisableOtherAbilitiesOnPerform = true,
				ExtraInit = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					self._c00GuiAbility = C00GuiAbility.new(self)
				end,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					if self._c00GuiAbility then
						self._c00GuiAbility:execute()
					end
				end,
			}),

			ScriptWave = Ability.New({
				Name = "Script Wave",
				InputName = "SecondAbility",
				Cooldown = C00LKIDD_CONFIG.ScriptWave.Cooldown,
				Duration = 0.8,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				DisableOtherAbilitiesOnPerform = true,
				ExtraInit = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					self._scriptWaveAbility = ScriptWaveAbility.new(self)
				end,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					if self._scriptWaveAbility then
						self._scriptWaveAbility:execute()
					end
				end,
			}),

			Inject = Ability.New({
				Name = "Script Injection",
				InputName = "FourthAbility",
				Cooldown = C00LKIDD_CONFIG.Inject.Cooldown,
				Duration = 0.5,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				DisableOtherAbilitiesOnPerform = false,
				ExtraInit = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					self._corruptionManager = CorruptionManager.new(self.OwnerProperties.Character)
					if self.OwnerProperties.Character:FindFirstChild("_m1Attack") then
						self._m1Attack = self.OwnerProperties.Character._m1Attack
					else
						self._m1Attack = M1Attack.new(self)
						self._m1Attack.Parent = self.OwnerProperties.Character
					end
					self._injectAbility = InjectAbility.new(self, self._corruptionManager, self._m1Attack)
				end,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					if self._injectAbility then
						self._injectAbility:execute()
					end
				end,
			}),

			StackOverflow = Ability.New({
				Name = "Stack Overflow",
				InputName = "ThirdAbility",
				Cooldown = C00LKIDD_CONFIG.StackOverflow.Cooldown,
				Duration = 1.5,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				DisableOtherAbilitiesOnPerform = true,
				ExtraInit = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					self._stackOverflowAbility = StackOverflowAbility.new(self)
				end,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end
					if self._stackOverflowAbility then
						self._stackOverflowAbility:execute()
					end
				end,
			}),
		},
	},
})

--============================================================
-- UI Description
--============================================================
local NameLabel = '<font color="rgb(0, 255, 0)">' .. C00lKidd.Config.Name .. "</font>"

C00lKidd.Config.Description = {
	{
		Type = "Separator",
		Text = "GENERAL INFO",
	},
	{
		Type = "Header",
		Text = C00lKidd.Config.Name:upper(),
	},
	{
		Type = "Quote",
		Text = '"' .. C00lKidd.Config.Quote .. '"',
	},
	{
		Type = "Text",
		Text = "C00lKidd is a corruption-driven killer built around pressure, denial, and burst repositioning. His core strength is turning basic M1 pressure into stack-based weakness, then collapsing a target with follow-up damage or a decisive hook-like reel-in.",
	},
	{
		Type = "Separator",
		Text = "STATS",
	},
	{
		Type = "Text",
		Text = "Health: " .. tostring(C00LKIDD_CONFIG.Stats.Health)
			.. " | Speed: +2 studs | Stamina Drain: " .. tostring(C00LKIDD_CONFIG.Stats.StaminaDrain)
			.. " | Stamina Regen: " .. tostring(C00LKIDD_CONFIG.Stats.StaminaRegen)
			.. " | M1 Damage: " .. tostring(C00LKIDD_CONFIG.M1.Damage),
	},
	{
		Type = "Separator",
		Text = "PASSIVES",
	},
	{
		Type = "Header",
		Text = "SCRIPT INJECTION",
	},
	{
		Type = "Text",
		Text = "A victim with corruption stacks takes " .. tostring(C00LKIDD_CONFIG.Inject.WeaknessPerStack)
			.. "% M1 weakness per stack, up to " .. tostring(C00LKIDD_CONFIG.Inject.WeaknessMax)
			.. "%. The corruption lasts " .. tostring(C00LKIDD_CONFIG.Inject.CorruptionDuration) .. " seconds.",
	},
	{
		Type = "Header",
		Text = "SWORD FOLLOW-UP",
	},
	{
		Type = "Text",
		Text = "If Script Injection is used within " .. tostring(C00LKIDD_CONFIG.FollowUp.Cooldown)
			.. "s of an M1, the next attack becomes a follow-up: " .. tostring(C00LKIDD_CONFIG.FollowUp.Damage)
			.. " damage plus " .. tostring(C00LKIDD_CONFIG.FollowUp.BurningDamage)
			.. " burning. Hitting applies Slowness II for " .. tostring(C00LKIDD_CONFIG.FollowUp.SlownessDuration)
			.. "s; missing applies Slowness III for " .. tostring(C00LKIDD_CONFIG.FollowUp.MissDuration) .. "s.",
	},
	{
		Type = "Separator",
		Text = "ABILITIES",
	},
	{
		Type = "Header",
		Text = "C00GUI CREATION",
	},
	{
		Type = "Text",
		Text = NameLabel .. " slows down, pulls out a mechanical bow, and fires a projectile. If it hits, he teleports " .. tostring(C00LKIDD_CONFIG.C00GuiCreation.TeleportDistance)
			.. " studs away and flings the survivor backward with force " .. tostring(C00LKIDD_CONFIG.C00GuiCreation.FlingForce) .. ".",
	},
	{
		Type = "Header",
		Text = "SCRIPT WAVE",
	},
	{
		Type = "Text",
		Text = NameLabel .. " slams the ground and fires three waves, each dealing " .. tostring(C00LKIDD_CONFIG.ScriptWave.WaveDamage)
			.. " damage. Survivors hit freeze for " .. tostring(C00LKIDD_CONFIG.ScriptWave.WaveFreezeDuration) .. "s and are flung with force "
			.. tostring(C00LKIDD_CONFIG.ScriptWave.FlingForce) .. ".",
	},
	{
		Type = "Header",
		Text = "SCRIPT INJECTION",
	},
	{
		Type = "Text",
		Text = NameLabel .. " throws a projectile for " .. tostring(C00LKIDD_CONFIG.Inject.ProjectileDamage) .. " damage and applies corruption stacks. If a survivor reaches "
			.. tostring(C00LKIDD_CONFIG.Inject.CorruptionStackMax) .. " stacks, the next injection reels them in with a chain and hook.",
	},
	{
		Type = "Header",
		Text = "STACK OVERFLOW",
	},
	{
		Type = "Text",
		Text = NameLabel .. " rushes through every spawn point, leaving explosions dealing " .. tostring(C00LKIDD_CONFIG.StackOverflow.ExplosionDamage)
			.. " damage. A random spawn is selected for exit, and he gains Speed IV for " .. tostring(C00LKIDD_CONFIG.StackOverflow.SpeedBoostDuration) .. "s.",
	},
}

return C00lKidd
