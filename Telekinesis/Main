--[[
    Telekinesis Server Controller
    -----------------------------
    Handles server-side telekinesis interactions:
      - Receives a client ray and animation, validates a target part named "Telekinetic".
      - Applies a looping float motion within a bounded region while "holding" is true.
      - Listens for EndFloat to release the target, stop the animation, and clean up VFX.
]]

----------------------------------------------------------------------------------------------------
-- Services (cached)
----------------------------------------------------------------------------------------------------
local RS = game:GetService("RunService")

----------------------------------------------------------------------------------------------------
-- Remotes / Network
----------------------------------------------------------------------------------------------------
local teleRE = game:GetService("ReplicatedStorage"):WaitForChild("telekinRE")
local EndFloatRE = teleRE:WaitForChild("EndFloat")

----------------------------------------------------------------------------------------------------
-- Runtime State
----------------------------------------------------------------------------------------------------
local charging
local charge
-- 'holding' is referenced later exactly as in the original script (intentionally not declared here).

----------------------------------------------------------------------------------------------------
-- Constants / Tuning
----------------------------------------------------------------------------------------------------
local MOVE_TIME  = 2
local MAX_CHARGE = 3
local BUFFER     = 4

----------------------------------------------------------------------------------------------------
-- Random Generator
----------------------------------------------------------------------------------------------------
local rng = Random.new(tick())

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

--- Float a target part within a randomized bounded region near the original CFrame.
-- Moves the target toward a random position and rotation, interpolated over MOVE_TIME,
-- so long as 'holding' remains true (as in the original script).
-- @param originalCF CFrame The original CFrame used as a reference for bounds.
-- @param target BasePart The telekinetic target to float.
-- @return boolean Always true when one float segment completes.
function Float(originalCF, target)

	local cX, cY, cZ = originalCF.X, originalCF.Y, originalCF.Z

	local min = Vector3.new(cX - BUFFER, cY + 3, cZ - BUFFER)
	local max = Vector3.new(cX + BUFFER, cY + 6, cZ + BUFFER)

	local bounds = Region3.new(min, max)

	local randRot = function()
		local rot = Vector3.new(
			math.rad(
				rng:NextInteger(-360, 360)),
			math.rad(
				rng:NextInteger(-360, 360)),
			math.rad(
				rng:NextInteger(-360, 360))
		)
		return CFrame.Angles(rot.X, rot.Y, rot.Z)
	end

	local randPos = function(bounds)
		local pos = Vector3.new(
			rng:NextNumber(min.X, max.X),
			rng:NextNumber(min.Y, max.Y),
			rng:NextNumber(min.Z, max.Z)
		)
		return Vector3.new(
			math.clamp(pos.X, min.X, max.X),
			math.clamp(pos.Y, cY, max.Y),
			math.clamp(pos.Z, min.Z, max.Z)
		)
	end

	local currCF = target.CFrame
	local goalCF = CFrame.new(randPos()) * randRot()
	local elap = 0
	while elap < MOVE_TIME and holding do
		local dt = RS.Heartbeat:Wait()
		elap += dt
		target.CFrame = (currCF:Lerp(goalCF, elap / MOVE_TIME))
	end

	return true
end

----------------------------------------------------------------------------------------------------
-- Connections / Runtime
----------------------------------------------------------------------------------------------------

-- Receives the client ray + animation and begins telekinetic float if a "Telekinetic" part is hit.
teleRE.OnServerEvent:Connect(function(player, ray, anim)
	local tool = player.Character:WaitForChild("telekinesis")

	if ray and player and tool then

		anim = player.Character["Humanoid"]:LoadAnimation(anim)
		anim.Looped = true
		anim:AdjustSpeed(4)
		anim:Play()

		local RayParams = RaycastParams.new()
		RayParams.FilterType = Enum.RaycastFilterType.Exclude
		RayParams.FilterDescendantsInstances = {player, player.Character}

		local result = workspace:Raycast(ray.Origin, ray.Direction * 50, RayParams)
		local target

		if result and result.Instance.Name == "Telekinetic" then
			local smoke = tool:WaitForChild("Smoke"):Clone()
			holding = true
			target = result.Instance
			target.Anchored = true
			smoke.Parent = target
			smoke.Size = target.Size.X
			smoke.Enabled = true

		else holding = false; return false end

		local originalCF = target.CFrame

		local endFloat; endFloat = EndFloatRE.OnServerEvent:Connect(function(player)
			if holding then
				holding = false
				if anim.isPlaying == true then anim:Stop() end
				target.Anchored = false
				if target:FindFirstChild("Smoke") then target["Smoke"]:Destroy() end
			end
		end)

		while holding do Float(originalCF, target) end
	end
end)
