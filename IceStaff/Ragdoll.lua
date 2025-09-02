-- Provides functionality for cloning player characters into ragdoll-like corpses.
-- This module script is parented to the Server side script in ServerScriptService

local corpseModule = {}
local serverStorage = game:GetService("ServerStorage")

-- Classes to remove from the clone
local delete = {
	["Animator"] = true,
	["LocalScript"] = true,
	["Script"] = true
}

-- Body parts to exclude from ragdoll conversion.
local avoidParts = {
	["RightHand"] = true,
	["LeftHand"] = true, 
	["LowerTorso"] = true,
	["UpperTorso"] = true,
	["RightFoot"] = true,
	["LeftFoot"] = true
}

--- Make a ragdoll-ready clone of a player character.
-- @param player Character to clone
-- @return Model Cloned corpse model
function corpseModule.Clone(player)

	player.Archivable = true

	-- Clone the player character and rename it.
	local playerCorpse = player:Clone()
	playerCorpse.Name = player.Name.."Corpse"
	playerCorpse.Parent = game.Workspace

	local playerParts = playerCorpse:GetDescendants()
	local humanoid = playerCorpse:WaitForChild("Humanoid")
	local rootPart = playerCorpse:WaitForChild("HumanoidRootPart")

	local humanoidChildren = humanoid:GetChildren()

	-- Strip Humanoid children (e.g., Animator, states) for clean physics.
	for i=1,#humanoidChildren do 
		humanoidChildren[i]:Destroy()
	end

	-- Force ragdoll behavior (no get-up, no auto-break).
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)

	-- (Reserved) Attachment bookkeeping if needed later.
	local attachmentTable = {}

	for i=1,#playerParts do 

		-- Server owns physics to avoid client jitter.
		local success, err = pcall(function()
			playerParts[i]:SetNetworkOwner(nil)
		end)

		local part = playerParts[i]
		local partClass = part.ClassName

		-- Remove unwanted classes from the clone.
		if delete[partClass] == true then 
			part:Destroy()
			continue
		end

		-- Convert eligible Motor6Ds into BallSocketConstraints.
		if part:IsA("Motor6D") and part.Name ~= "Neck" and avoidParts[part.Parent.Name] ~= true then 

			-- BallSocket with limits + friction for natural motion.
			local socket = Instance.new("BallSocketConstraint")
			socket.LimitsEnabled = true            
			socket.UpperAngle = 60               
			socket.TwistLimitsEnabled = true       
			socket.TwistLowerAngle = -45           
			socket.TwistUpperAngle = 45
			socket.MaxFrictionTorque = 200  

			local part0 = part.Part0
			local part1 = part.Part1
			local jointName = part.Name
			local parent = part.Parent

			-- Use rig or generic attachments for the new constraint.
			local attachment0 = parent:FindFirstChild(jointName.."RigAttachment") or parent:FindFirstChild(jointName.."Attachment")
			local attachment1 = part0:FindFirstChild(jointName.."RigAttachment") or parent:FindFirstChild(jointName.."Attachment")
			-- Small upward impulse so the corpse settles visibly.
			local hrp = playerCorpse:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp:ApplyImpulse(Vector3.new(0, 50, 0))
			end

			-- Bind attachments to socket and remove original Motor6D.
			if attachment0 and attachment1 then 
				socket.Attachment0,socket.Attachment1 = attachment0, attachment1
				socket.Parent = part.Parent
				part:Destroy() -- Remove original Motor6D
			end
		end
	end

	return playerCorpse
end

--- Freeze and fade the corpse after creation.
-- Anchors parts, then gradually increases transparency.
-- @param playerCorpse The corpse model
function corpseModule.onDied(playerCorpse)
	local corpseParts = playerCorpse:GetDescendants()
	for i = 1,#corpseParts do 
		local part = corpseParts[i]
		if part:IsA("Part") or part:IsA("MeshPart") then 
			part.Anchored = true
		end
		playerCorpse.Archivable = false 
	end
	-- Delay before fade-out begins.
	task.wait(2)
	-- Heartbeat-driven linear fade over `timer` seconds.
	local timer = 1.5
	local elap = 0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		elap += dt
		for _, part in pairs(playerCorpse:GetChildren()) do 
			local success, _err = pcall(function()
				part.Transparency = elap / timer
			end)
			continue
		end
	end)
end

return corpseModule
