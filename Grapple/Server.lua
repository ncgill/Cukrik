--[[
	Server Grapple Controller
	-------------------------
	Listens for client "FireGrapple" events, validates the shot with a server-side
	raycast, and then orchestrates a sequence of player movement tasks via the Mover module:
	  1) spawn_hook     – creates/extends a visible rope from the weapon barrel,
	  2) move_to        – pulls the player toward the impact point while shrinking the rope,
	  3) orient_player  – orients the character relative to the surface normal at impact.

	Networking:
	- RemoteEvent: ReplicatedStorage.FireGrapple
	  • Client → Server payload: (player, ray, barrel, debounce)
	  • Server → Client payload: () acknowledgement for any client-side cleanup/effects.
]]

local RepStorage = game:GetService("ReplicatedStorage")
local ServStorage = game:GetService("ServerStorage")
local FireGrappleEvent = RepStorage:WaitForChild("FireGrapple")
local RS = game:GetService("RunService")

local Mover = require(script:WaitForChild("Move"))

-- Local placeholders (preserved from original)
local player
local grapple
local barrel

-- Raycast configuration
local PARAMS = RaycastParams.new()
PARAMS.FilterType = Enum.RaycastFilterType.Exclude

--- Handle a grapple fire request from the client.
-- Validates the ray against the world, then runs the Mover task pipeline to
-- visualize and move the player toward the hit point. Finally, notifies the client.
--
-- @param player Player        The firing player.
-- @param ray    Ray           Camera ray constructed on the client (Origin, Direction).
-- @param barrel any           Client-provided; server re-resolves authoritative barrel from the tool.
-- @param debounce boolean     Client-side guard to limit repeated triggers; server still validates.
FireGrappleEvent.OnServerEvent:Connect(function(player, ray, barrel, debounce)

	local playerChar = player.Character
	local barrel = playerChar:WaitForChild("Grapple")["Handle"]["Barrel"]

	-- Fallback end position (visual aid); actual hit confirmed via Raycast below
	local hitPos = ray.Origin + ray.Direction * 200
	
	-- Exclude the player and their tool from intersection tests
	PARAMS.FilterDescendantsInstances = { playerChar, barrel.Parent}
	local testRay = workspace:Raycast(ray.Origin, ray.Direction * 200, PARAMS)

	-- Guard checks: valid character, barrel, hit, and not debounced
	if playerChar and barrel and testRay and not debounce then 
		
		-- Create and initialize a task runner for the grapple sequence
		local Mover = Mover.new()
		Mover:Init()
		
		-- Execute rope spawn, movement, and orientation tasks in order
		Mover:Run(
			{
				{ Name = "spawn_hook", Args = {player, barrel, testRay}},
				{ Name = "move_to", Args = {player, barrel, testRay}},
				{ Name = "orient_player", Args = {player, barrel, testRay}}
			}
		)
		
		-- Acknowledge to the firing client (e.g., for local cleanup/UI updates)
		FireGrappleEvent:FireClient(player)	
	end	
end)
