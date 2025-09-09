--[[
	Mover Module
	Parented to main script in ServerScriptService

	A lightweight action runner for character-driven movement tasks (e.g., grappling),
	with helper utilities for humanoid/HRP lookup and a rope visual that shrinks
	as the player moves toward a target.

	Design notes:
	- Public API:
		- Mover.new()
		- Mover:Register(name, fn)
		- Mover:Add(name, fn), Mover:Remove(name)
		- Mover:Init() self (registers built-in tasks)
		- Mover:Run(tasks) (executes a list of named tasks with args)
	- Task callbacks are stored in self._movers[name] and are invoked by name.
]]

local Mover = {

}

Mover.__index = Mover

local RS = game:GetService("RunService")

local SPEED = 50 
local PARAMS = RaycastParams.new()
PARAMS.FilterType = Enum.RaycastFilterType.Exclude

--- Safely obtain the Humanoid from a character model.
-- @param character Instance? The candidate character model.
-- @return Humanoid? The first Humanoid found, or nil if not present/invalid.
function getHumanoid(character: Instance): Humanoid?
	if not character then return nil end 
	return character:FindFirstChildOfClass("Humanoid")
end

--- Safely obtain the HumanoidRootPart (HRP) from a character model.
-- @param character Instance? The candidate character model.
-- @return BasePart? The HRP if found, otherwise nil.
function getHRP(character: Instance): BasePart? 
	if not character then return nil end 
	return character:FindFirstChild("HumanoidRootPart")
end

--- Move the HRP toward a target and visually shrink a rope between a barrel and the target.
-- Anchors the HRP while interpolating position toward 'target' based on 'factor',
-- and scales/reorients the 'rope' Part so it appears to retract from 'barrel' to 'target'.
-- @param hrp BasePart The player's HumanoidRootPart to move.
-- @param target Vector3 The world-space target to approach.
-- @param factor number Normalized progress [0,1] along the path from original to target.
-- @param original Vector3 The starting HRP world position.
-- @param rope Rope Part to scale/orient during movement.
-- @param barrel BasePart The origin reference for the rope (e.g., grappling barrel).
function MoveAndShrinkRope(hrp, target, factor, original, rope, barrel)
	hrp.Anchored = true 
	local distance = (target - original).Magnitude
	local lerp = original:Lerp(target, factor)
	local moved = hrp.Position - lerp
	if rope then
		local totalDistance = (target - barrel.CFrame.Position).Magnitude
		local currentLength = totalDistance * (1 - factor)

		local dir = (target - barrel.CFrame.Position).Unit
		local newTarget = barrel.CFrame.Position + dir * currentLength
		local mid = (barrel.CFrame.Position + newTarget) / 2

		-- Update rope to stretch from barrel to newTarget
		rope.Size = Vector3.new(0.15, 0.15, currentLength)
		rope.CFrame = CFrame.lookAt(mid, newTarget)
	end
	
	if hrp and target then 
		print()
		local curr = hrp.Position 
		hrp.CFrame = CFrame.new(
			lerp, target
		) 
	end
end

--- Add a task callback under a given name.
-- The callback is invoked later via Mover:Run or direct __call usage.
-- @param name string task name.
-- @param fn function The function to store for this task.
function Mover:Add(name: string, fn: (any) -> any)	
	self._movers[name] = fn 		
end	

--- Remove a previously registered task by name.
-- @param name string The task name to delete.
function Mover:Remove(name: string)
	self._movers[name] = nil 
end

--- Construct a new Mover object with a callable metatable.
-- Calling the object like obj("taskName", ...) invokes the stored task function.
-- @return Mover A new Mover instance with an empty task registry.
function Mover.new()
	local self = setmetatable({
		_movers = {}
	}, Mover)
	return setmetatable(self, {
		__index = Mover.__index,
		__call = function(t, name, ...)
			local fn = t._movers[name]
			if not fn then
				return nil 
			end
			return fn(...)
		end
	})
end

--- Register a task callback under a given name.
-- @param name string task name.
-- @param fn function The function to store for this task.
function Mover:Register(name, fn)
	self._movers[name] = fn
end

--- Initialize built-in tasks on the mover instance.
-- Registers:
--   - "wait": yields for a given time (in seconds).
--   - "spawn_hook": creates and grows a rope part from the barrel toward the ray target.
--   - "move_to": moves the player HRP toward a ray position while shrinking the rope.
--   - "orient_player": orients the player relative to the target and ray normal.
-- @return Mover Returns self for fluent chaining.
function Mover:Init()
	
	self:Register("wait", function(t)
		print("Wait")
		wait(t)
	end)
	
	self:Register("spawn_hook", function(self, player, barrel, ray)
		print("Spawning")
		if barrel then 
			local barrelPos = barrel.Position
			local target = ray.Position
			local distance = (target - barrel.Position).Magnitude
			local dir = (target - barrelPos).Unit      
			local distance = (target - barrelPos).Magnitude

			local part = Instance.new("Part")
			part.Anchored = true; 
			part.CanCollide = false; 
			part.Parent = barrel; 
			part.Name = "Rope"

			local elap = 0 
			local factor = 0 
			local speed = .1

			local spawning; spawning = RS.Heartbeat:Connect(function(dt)

				elap += dt

				local factor = math.clamp(elap / speed, 0, 1)
				local currentLength = distance * factor
				local mid = barrelPos + dir * (currentLength / 2)

				part.Size = Vector3.new(0.15, 0.15, currentLength)
				part.CFrame = CFrame.lookAt(mid, mid + dir)

				if elap >= .5 then spawning:Disconnect() end
			end)
		end
		return true 
	end)
	
	self:Register("move_to", function(self, player, barrel, ray)
		local hum = getHumanoid(player.Character)
		local hrp = getHRP(player.Character)
		if ray then 
			local original = hrp.Position
			local target = ray.Position
			local distance = (target - hrp.Position).Magnitude
			local timeToMove = distance / SPEED 
			local elapsed = 0
			
			local rope = barrel:FindFirstChild("Rope") or nil 
			
			while elapsed <= timeToMove do 
				elapsed += RS.Heartbeat:Wait()
				MoveAndShrinkRope(hrp, target, elapsed / timeToMove, original, rope, barrel)
				if elapsed >= timeToMove then elapsed = 0 break end
			end
		end
		return true 
	end)
	
	self:Register("orient_player", function(self, player, barrel, ray)
		print("Orienting")
		local target = ray.Position
		player.Character["HumanoidRootPart"].CFrame = CFrame.new(target + (player.Character:GetExtentsSize() * ray.Normal))
		return true 
	end)
	
	return self
end

--- Execute a list of tasks with retry-on-fail semantics.
-- Each task element is expected to be a table with:
--   { Name = "<taskName>", Args = { ... } }
-- For each task, the registered function is called repeatedly until it returns truthy
-- or 3 seconds elapse (accumulated via Heartbeat). If not found, the task is skipped.
-- @param tasks table Array of task tables to run in order.
function Mover:Run(tasks)
	print(#tasks)
	for _, current in ipairs(tasks) do
		local fn = self._movers[current.Name]
		if fn then
			local waited = 0
			local success = false
			while not success and waited <= 3 do 
				waited += RS.Heartbeat:Wait()
				success = fn(current.Name, table.unpack(current.Args))
				if success then success = false waited = 0 break end 
			end
		else
			continue
		end
	end
end

return Mover
