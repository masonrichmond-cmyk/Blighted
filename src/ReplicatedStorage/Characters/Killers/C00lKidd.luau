local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Character = require(ReplicatedStorage.Classes.Character)
local Ability = require(ReplicatedStorage.Classes.Ability)
local Hitbox = require(ReplicatedStorage.Classes.Hitbox)
local Projectile = require(ReplicatedStorage.Classes.Projectile)
local Types = require(ReplicatedStorage.Classes.Types)
local Utils = require(ReplicatedStorage.Modules.Utils)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

local function GetHumanoid(character: Model): Humanoid?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function GetRootPart(character: Model): BasePart?
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function GetCorruptionStacks(target: Model): number
	if not target then
		return 0
	end
	return tonumber(target:GetAttribute("C00lKiddCorruptionStacks")) or 0
end

local function GetCorruptionTotal(target: Model): number
	if not target then
		return 0
	end
	return tonumber(target:GetAttribute("C00lKiddCorruptionTotal")) or 0
end

local function ApplyCorruption(target: Model, amount: number): number
	if not target then
		return 0
	end

	local total = GetCorruptionTotal(target) + amount
	target:SetAttribute("C00lKiddCorruptionTotal", total)
	target:SetAttribute("C00lKiddCorruptionExpiresAt", os.clock() + 40)

	local stacks = math.clamp(total, 0, 3)
	target:SetAttribute("C00lKiddCorruptionStacks", stacks)
	target:SetAttribute("C00lKiddCorruptionWeakness", math.min(15, stacks * 5))

	if total >= 4 and target:GetAttribute("C00lKiddCorruptionReeled") ~= true then
		target:SetAttribute("C00lKiddCorruptionReeled", true)
	end

	return stacks
end

local function ResetCorruption(target: Model)
	if not target then
		return
	end
	target:SetAttribute("C00lKiddCorruptionStacks", 0)
	target:SetAttribute("C00lKiddCorruptionTotal", 0)
	target:SetAttribute("C00lKiddCorruptionWeakness", 0)
	target:SetAttribute("C00lKiddCorruptionReeled", false)
end

local function ForEachVictimInRadius(origin: Vector3, radius: number, callback: (Model) -> ())
	local loadedPlayers = ReplicatedStorage:FindFirstChild("LoadedPlayers")
	if not loadedPlayers then
		return
	end

	for _, folder in ipairs(loadedPlayers:GetChildren()) do
		local victim = folder:FindFirstChild("Character")
		if not victim or victim == workspace then
			continue
		end
		local root = GetRootPart(victim)
		if root and (root.Position - origin).Magnitude <= radius then
			callback(victim)
		end
	end
end

local function TriggerWaveFreeze(victim: Model, duration: number)
	if not victim then
		return
	end
	local humanoid = GetHumanoid(victim)
	local root = GetRootPart(victim)
	if not humanoid or not root then
		return
	end
	victim:SetAttribute("C00lKiddFrozen", true)
	humanoid.WalkSpeed = math.max(0.1, humanoid.WalkSpeed * 0.15)
	task.delay(duration, function()
		if victim and victim.Parent then
			victim:SetAttribute("C00lKiddFrozen", false)
			if humanoid.Parent then
				humanoid.WalkSpeed = 16
			end
		end
	end)
end

local function MakeProjectileTemplate(name: string, color: Color3, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Material = Enum.Material.Neon
	part.BrickColor = BrickColor.new(color)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Anchored = true
	part.Transparency = 0.15
	return part
end

local function PlayHitStun(victim: Model, force: number, upward: number)
	if not victim then
		return
	end
	local root = GetRootPart(victim)
	if not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, upward, root.AssemblyLinearVelocity.Z) + Vector3.new(force, 0, 0)
end

local function HighlightSurvivor(victim: Model, duration: number)
	if not victim then
		return
	end
	victim:SetAttribute("C00lKiddHighlighted", true)
	task.delay(duration, function()
		if victim and victim.Parent then
			victim:SetAttribute("C00lKiddHighlighted", false)
		end
	end)
end

local C00lKidd: Types.Killer = Character.CreateKiller({
	Config = {
		Name = "C00lKidd",
		Quote = "Corruption is the only language I know.",
		Render = "rbxassetid://0",
		Price = -1,

		Origin = {
			TooltipText = "C00lkidd:)",
			Icon = "rbxassetid://0",
		},

		AnimationIDs = {
			IdleAnimation = "rbxassetid://73546288362576",
			WalkAnimation = "rbxassetid://115621394601470",
			RunAnimation = "rbxassetid://102981744469535",
		},
	},

	GameplayConfig = {
		Health = 2014,
		BaseSpeed = 12.5,
		SprintSpeedMultiplier = 26 / 12.5,
		StaminaProperties = {
			MaxStamina = 100,
			StaminaDrain = 9.5,
			StaminaGain = 12,
		},
		Abilities = {
			Slash = Ability.New({
				Name = "Slash",
				InputName = "Slash",
				Cooldown = 2,
				Duration = 0.4,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://12222200",
				UICorner = true,
				Delay = 0.1,
				HitboxSize = Vector3.new(5, 6, 4.5),
				HitboxOffset = CFrame.new(0, 0, -2.5),
				PlayUseAnimationOnUse = false,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end

					local ownerCharacter = self.OwnerProperties.Character
					local root = self.OwnerProperties.HRP
					if not ownerCharacter or not root then
						return
					end

					local injectionTime = ownerCharacter:GetAttribute("C00lKiddInjectAt") or -999
					local queuedFollowUp = os.clock() - injectionTime <= 0.8

					local damage = 20
					local hitboxSize = Vector3.new(5, 6, 4.5)
					local hitboxOffset = CFrame.new(0, 0, -2.5)
					local reason = "C00lKidd Slash"
					local effectTable = nil

					if ownerCharacter:GetAttribute("C00lKiddInjected") then
						damage += 8
						ownerCharacter:SetAttribute("C00lKiddInjected", false)
						reason = "C00lKidd Injection Buff"
					end

					if queuedFollowUp then
						damage = 8
						hitboxSize = Vector3.new(3, 3, 2)
						hitboxOffset = CFrame.new(0, 0, -2)
						reason = "C00lKidd Sword Follow-up"
						effectTable = {
							{ Name = "Burning", Level = 7, Duration = 3 },
							{ Name = "Slowness", Level = 2, Duration = 3 },
						}
					end

					task.delay(self.Delay or 0.1, function()
						Hitbox.New(self.Owner, {
							CFrameOffset = hitboxOffset,
							Size = hitboxSize,
							Time = 0.25,
							Damage = damage,
							Reason = reason,
							ExecuteOnKill = true,
							EffectsToApply = effectTable,
						})
					end)
				end,
			}),

			C00GuiCreation = Ability.New({
				Name = "C00Gui Creation",
				InputName = "FirstAbility",
				Cooldown = 27,
				Duration = 0.5,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end

					local character = self.OwnerProperties.Character
					local root = self.OwnerProperties.HRP
					if not character or not root then
						return
					end

					local humanoid = GetHumanoid(character)
					if humanoid then
						humanoid.WalkSpeed = 7
						task.delay(0.8, function()
							if humanoid.Parent then
								humanoid.WalkSpeed = 16
							end
						end)
					end

					local origin = root.CFrame * CFrame.new(0, 0.5, -4)
					local shot = MakeProjectileTemplate("C00GuiArrow", Color3.fromRGB(90, 255, 140), Vector3.new(1.5, 1.5, 3))
					shot.CFrame = origin
					shot.Parent = workspace

					local targetHit = false
					local projectileInfo = Projectile.New({
						SourcePlayer = self.Owner,
						Model = shot,
						StartingCFrame = origin,
						Speed = 110,
						Lifetime = 2.4,
						ThrowType = "Forward",
						DestroyOnCollision = true,
						HitboxSettings = {
							Size = Vector3.new(2.4, 2.4, 3.2),
							Shape = Enum.PartType.Ball,
							Damage = 0,
							Reason = "C00Gui Creation",
							HitMultiple = false,
							Connections = {
								Hit = function(hitInfo)
									if targetHit then
										return
									end
									targetHit = true
									local hitTarget = hitInfo and hitInfo.HumanoidsHit and hitInfo.HumanoidsHit[1]
									if not hitTarget or not hitTarget.Parent then
										return
									end
									local victimRoot = GetRootPart(hitTarget.Parent)
									if not victimRoot then
										return
									end
									local killerRoot = root
									local away = (killerRoot.Position - victimRoot.Position)
									local dir = away.Unit
									local teleportPosition = victimRoot.Position + dir * 60
									character:PivotTo(CFrame.new(teleportPosition, victimRoot.Position))
									local flingVector = (victimRoot.Position - killerRoot.Position).Unit * 120 + Vector3.new(0, 55, 0)
									victimRoot.AssemblyLinearVelocity = flingVector
								end,
							},
						},
					})

					if projectileInfo then
						projectileInfo:Destroy()
					end
				end,
			}),

			ScriptWave = Ability.New({
				Name = "Script Wave",
				InputName = "SecondAbility",
				Cooldown = 35,
				Duration = 0.8,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end

					local character = self.OwnerProperties.Character
					local root = self.OwnerProperties.HRP
					if not character or not root then
						return
					end

					local humanoid = GetHumanoid(character)
					if humanoid then
						humanoid.WalkSpeed = 8
						task.delay(0.8, function()
							if humanoid.Parent then
								humanoid.WalkSpeed = 16
							end
						end)
					end

					for offset = -2, 2, 2 do
						local forward = root.CFrame * CFrame.new(offset * 2, 0, -12)
						local zone = Instance.new("Part")
						zone.Name = "ScriptWaveZone"
						zone.Anchored = true
						zone.CanCollide = false
						zone.Size = Vector3.new(7, 1, 12)
						zone.CFrame = forward
						zone.Material = Enum.Material.Neon
						zone.BrickColor = BrickColor.new("Electric blue")
						zone.Transparency = 0.5
						zone.Parent = workspace

						task.delay(0.15, function()
							if zone.Parent then
								zone:Destroy()
							end
						end)

						local pulse = Hitbox.New(self.Owner, {
							CFrameOffset = CFrame.new(offset * 2, 0, -12),
							Size = Vector3.new(7, 4, 12),
							Time = 0.35,
							Damage = 10,
							Reason = "Script Wave",
							ExecuteOnKill = true,
							Connections = {
								Hit = function(hitInfo)
									local target = hitInfo and hitInfo.HumanoidsHit and hitInfo.HumanoidsHit[1]
									if not target or not target.Parent then
										return
									end
									local victimRoot = GetRootPart(target.Parent)
									if victimRoot then
										victimRoot.AssemblyLinearVelocity = (victimRoot.Position - root.Position).Unit * 75 + Vector3.new(0, 35, 0)
										TriggerWaveFreeze(target.Parent, 2)
									end
								end,
							},
						})
						if pulse then
							pulse.Cancel = pulse.Cancel or function() end
						end
					end
				end,
			}),

			Inject = Ability.New({
				Name = "Script Injection",
				InputName = "FourthAbility",
				Cooldown = 12,
				Duration = 0.5,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UseAnimation = "rbxassetid://0",
				PlayUseAnimationOnUse = false,
				ProjectileModel = MakeProjectileTemplate("ScriptInjection", Color3.fromRGB(120, 255, 80), Vector3.new(1.6, 1.6, 1.6)),
				ProjectileSpeed = 90,
				ProjectileLifetime = 0.75,
				ProjectileSize = Vector3.new(2, 2, 3),
				ProjectileOffset = CFrame.new(0, 1, -2),
				ProjectileDamage = 5,
				BuffDuration = 12,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end

					local character = self.OwnerProperties.Character
					local root = self.OwnerProperties.HRP
					if not character or not root then
						return
					end

					character:SetAttribute("C00lKiddInjectAt", os.clock())
					local projectile = Projectile.New({
						SourcePlayer = self.Owner,
						Model = self.ProjectileModel,
						StartingCFrame = root.CFrame * self.ProjectileOffset,
						Speed = self.ProjectileSpeed,
						Lifetime = self.ProjectileLifetime,
						ThrowType = "Forward",
						DestroyOnCollision = true,
						HitboxSettings = {
							Size = self.ProjectileSize,
							Shape = Enum.PartType.Ball,
							Damage = self.ProjectileDamage,
							Reason = "Script Injection",
							HitMultiple = false,
							Connections = {
								Hit = function(hitInfo)
									local target = hitInfo and hitInfo.HumanoidsHit and hitInfo.HumanoidsHit[1]
									if not target or not target.Parent then
										return
									end

									local victim = target.Parent
									local currentStacks = GetCorruptionStacks(victim)
									local total = GetCorruptionTotal(victim)
									local nextTotal = total + 1
									victim:SetAttribute("C00lKiddCorruptionTotal", nextTotal)
									victim:SetAttribute("C00lKiddCorruptionExpiresAt", os.clock() + 40)
									local stackCount = math.clamp(nextTotal, 0, 3)
									victim:SetAttribute("C00lKiddCorruptionStacks", stackCount)
									victim:SetAttribute("C00lKiddCorruptionWeakness", math.min(15, stackCount * 5))

									if nextTotal >= 4 then
										local victimRoot = GetRootPart(victim)
										local killerRoot = GetRootPart(character)
										if victimRoot and killerRoot then
											local pullDir = (killerRoot.Position - victimRoot.Position).Unit
											victimRoot.AssemblyLinearVelocity = pullDir * 90 + Vector3.new(0, 35, 0)
										end
									end

									character:SetAttribute("C00lKiddInjected", true)
									task.delay(1, function()
										if character and character.Parent then
											character:SetAttribute("C00lKiddInjected", false)
										end
									end)
								end,
							},
						},
					})
				end,
			}),

			StackOverflow = Ability.New({
				Name = "Stack Overflow",
				InputName = "ThirdAbility",
				Cooldown = 40,
				Duration = 1,
				RenderImage = "rbxassetid://0",
				UseSound = "rbxassetid://0",
				UICorner = true,
				Behaviour = function(self: Types.Ability)
					if not RunService:IsServer() then
						return
					end

					local character = self.OwnerProperties.Character
					local humanoid = GetHumanoid(character)
					if not character or not humanoid then
						return
					end

					humanoid.WalkSpeed = 8
					local spawns = {}
					for _, instance in ipairs(workspace:GetDescendants()) do
						if instance:IsA("SpawnLocation") then
							table.insert(spawns, instance)
						elseif instance:IsA("Part") and instance.Name:lower():find("spawn") then
							table.insert(spawns, instance)
						end
					end

					for _, spawn in ipairs(spawns) do
						local explosion = Instance.new("Explosion")
						explosion.Position = spawn.Position
						explosion.BlastRadius = 8
						explosion.BlastPressure = 0
						explosion.Parent = workspace
						for _, victim in ipairs(workspace:GetChildren()) do
							if victim:IsA("Model") and victim:FindFirstChildOfClass("Humanoid") then
								local root = GetRootPart(victim)
								if root and (root.Position - spawn.Position).Magnitude <= 9 then
									HighlightSurvivor(victim, 5)
									local victimHumanoid = GetHumanoid(victim)
									if victimHumanoid then
										victimHumanoid:TakeDamage(15)
									end
								end
							end
						end
						task.wait(0.08)
					end

					local randomSpawn = spawns[math.random(1, #spawns)]
					if randomSpawn then
						character:PivotTo(CFrame.new(randomSpawn.Position + Vector3.new(0, 5, 0)))
					end
					task.delay(0.4, function()
						if humanoid.Parent then
							humanoid.WalkSpeed = 16 + 4
						end
					end)
					task.delay(5, function()
						if humanoid.Parent then
							humanoid.WalkSpeed = 16
						end
					end)
				end,
			}),
		},
	},
})

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
		Text = "Health: 2014 | Stamina Drain: 9.5 | Stamina Regen: 12 | Speed: +2 studs faster than normal | M1 Damage: 20 | Normal M1 hitbox: 5 studs",
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
		Text = "A victim with corruption stacks takes 5% M1 weakness per stack, up to 15%. The corruption remains after the injected M1 buff is consumed, but the damage boost is removed after a single M1 hit.",
	},
	{
		Type = "Header",
		Text = "SWORD FOLLOW-UP",
	},
	{
		Type = "Text",
		Text = "If Script Injection is used within 0.8 seconds of an M1, the next attack becomes a lunge follow-up: 8 damage plus 7 burning. Hitting applies Slowness II for 3 seconds; missing applies Slowness III for 2 seconds.",
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
		Text = "C00lKidd slows down, pulls out a mechanical bow, and fires a projectile. If it hits, he teleports 60 studs away from the victim and flings them backward with a sword slash.",
	},
	{
		Type = "Header",
		Text = "SCRIPT WAVE",
	},
	{
		Type = "Text",
		Text = "C00lKidd slams the ground and fires three waves in front of him. Each wave deals 10 damage, the zone between them freezes survivors, and any frozen target can be ragdolled or launched if hit by another move.",
	},
	{
		Type = "Header",
		Text = "SCRIPT INJECTION",
	},
	{
		Type = "Text",
		Text = "C00lKidd throws a fast projectile for 5 damage and applies corruption stacks for 40 seconds. Corruption amplifies his M1 damage once per stack and stays active after the buff cycle ends. If a survivor reaches 3 stacks and he lands a fourth injection, C00lKidd reels them in with his chain and hook.",
	},
	{
		Type = "Header",
		Text = "STACK OVERFLOW",
	},
	{
		Type = "Text",
		Text = "C00lKidd rushes through every spawn point in rapid succession, leaving explosions dealing 15 burning damage. A random spawn gets selected for his exit, and he gains Speed IV for 5 seconds after leaving the final one.",
	},
}

return C00lKidd
