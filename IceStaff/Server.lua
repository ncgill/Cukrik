--[[
    Fire Staff Server Controller
    ----------------------------
    Listens for client fire requests, performs a server-side raycast, mirrors
    the projectile (orb) travel, detects hits, and applies ragdoll/respawn VFX.
]]

----------------------------------------------------------------------------------------------------
-- Services
----------------------------------------------------------------------------------------------------
local TS = game:GetService("TweenService")        
local RS = game:GetService("RunService")   

----------------------------------------------------------------------------------------------------
-- Constants / Tuning
----------------------------------------------------------------------------------------------------
local MAX_DISTANCE = 100   -- Maximum range

----------------------------------------------------------------------------------------------------
-- Modules
----------------------------------------------------------------------------------------------------
local RagDoll = require(script:WaitForChild("ragdoll")) 

----------------------------------------------------------------------------------------------------
-- Remotes / Network
----------------------------------------------------------------------------------------------------
local fireStaffRE = game:GetService("ReplicatedStorage"):WaitForChild("fireStaffRE", 5)


----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

--- Gradually re-show (fade-in) a target model, then clean up the orb.
-- Hides all target children (pcall-wrapped) and destroys the orb.
-- Then re-parents the target to Workspace and animates child Transparency
-- from fully hidden back to visible over 'timer' seconds on Heartbeat.
-- @param target Model The model to respawn/fade-in.
-- @param orb Part The projectile orb Part to destroy.
function respawn(target, orb)
	for i, v in ipairs(target:GetChildren()) do
		local success, err = pcall(function()
			v.Transparency = 1
		end)
	end

	orb:Destroy()

	target.Parent = game.Workspace
	local elap = 0
	local timer = 1.5
	local spawning; spawning = game:GetService("RunService").Heartbeat:Connect(function(dt)
		for i, v in ipairs(target:GetChildren()) do
			elap += dt
			local alpha = timer - elap
			local success, err = pcall(function()
				v.Transparency = alpha
			end)
			if elap <= 0 then spawning:Disconnect() return true end
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Connections / Runtime
----------------------------------------------------------------------------------------------------

-- Handles client fire requests:
-- 1) Creates a RemoteFunction (preserved from original, not invoked).
-- 2) Validates player/tool references and performs a raycast using the provided ray.
-- 3) Spawns a transparent orb and mirrors its travel toward the hit position.
-- 4) On touch with a humanoid (not belonging to the shooter), triggers ragdoll flow:
--    - Temporarily removes the target model from Workspace,
--    - Spawns a ragdoll corpse and runs onDied effects,
--    - Respawns (fade-in) the original target model,
--    - Cleans up corpse and connections.
fireStaffRE.OnServerEvent:Connect(function(player, action, tool, ray)

	local runShoot = Instance.new("RemoteFunction")
	runShoot.Parent = game:GetService("ReplicatedStorage")

	if player and player.Character:FindFirstChild("HumanoidRootPart") and tool:FindFirstChild("Handle") then

		local handle = tool:FindFirstChild("Handle")
		local handleLV = handle.CFrame.LookVector.Unit

		local rayP = RaycastParams.new()
		rayP.FilterType = Enum.RaycastFilterType.Exclude
		rayP.FilterDescendantsInstances = { player, player.Character }

		local ray = workspace:Raycast(ray.Origin, ray.Direction * 200, rayP)
		local orb = Instance.new("Part")
		orb.CFrame = CFrame.new(tool["Handle"].CFrame.Position)
		orb.Size = Vector3.new(3, 3, 3)
		orb.Parent = tool
		orb.Transparency = 1
		orb:SetNetworkOwner(player)

		if ray then
			fireStaffRE:FireClient(player, ray.Position, ray.Distance)

			local elapsed = 0
			local timer = ray.Distance / 150
			local shooting; shooting = RS.Heartbeat:Connect(function(dt)
				elapsed += dt
				local alpha = math.clamp(elapsed / timer, 0, 1)
				orb.CFrame = CFrame.new(tool.Handle.CFrame.Position:Lerp(ray.Position, alpha))
				if alpha >= 1 then
					shooting:Disconnect()
				end
			end)
		end

		local debounce = false
		local checkHit; checkHit = orb.Touched:Connect(function(touch)
			if not debounce and not touch:IsDescendantOf(player.Character) and touch.Parent:FindFirstChild("Humanoid") then
				debounce = true
				local target = touch:FindFirstAncestorOfClass("Model")
				target.Parent = nil
				local corpse = RagDoll.Clone(target)
				task.wait(2)
				local finished = RagDoll.onDied(corpse)
				task.wait(2)
				respawn(target, orb)
				corpse:Destroy()
				checkHit:Disconnect()
			end
		end)

	else
		return false
	end

end)
