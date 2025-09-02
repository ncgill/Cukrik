--[[
	Client Grapple Controller
	-------------------------
	Handles the client-side flow for a Grapple tool:
	  - Equips tool, loads/plays animations, prepares helper module (Header).
	  - RMB (scope): enters scoped camera offset and draws a laser from the barrel toward the cursor.
	  - Mouse movement while scoped: tilts/leans the weapon via Header.Tilt.
	  - LMB (shoot): fires a ray to the server, plays hold animation, and resets state.
	  - Remote ack from server: restores camera/mouse, re-enables character animations.
	  - Unequip: stops all running connections, restores character/camera defaults.

	Notes:
	- Variable names and runtime logic are preserved exactly.
	- Only top-level declarations are grouped for clarity (services → remotes → player/camera → tool → state).
	- Added professional-style docstrings/comments; no functional changes.
]]

----------------------------------------------------------------------------------------------------
-- Services (cached)
----------------------------------------------------------------------------------------------------
local RepStorage = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local Players    = game:GetService("Players")
local RS         = game:GetService("RunService")

----------------------------------------------------------------------------------------------------
-- Remotes / Network
----------------------------------------------------------------------------------------------------
local FireGrappleEvent = game:GetService("ReplicatedStorage"):WaitForChild("FireGrapple")

----------------------------------------------------------------------------------------------------
-- Player / Camera Context
----------------------------------------------------------------------------------------------------
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

----------------------------------------------------------------------------------------------------
-- Tool / Parts
----------------------------------------------------------------------------------------------------
local tool   = script.Parent
local handle = script.Parent:WaitForChild("Handle")
local barrel = handle:WaitForChild("Barrel")
local laser  = nil
local playerChar = Player.Character

----------------------------------------------------------------------------------------------------
-- Runtime State / Connections
----------------------------------------------------------------------------------------------------
local equipped, scoped, shoot, tilt, ended
local running = {}
local ub = false
local H = nil

--- Stop all running connections and restore pose/walk speed.
-- Expects a list of RBXScriptConnection objects. Safely resets waist/neck C0 using Header fields.
-- @param tasks table Array of connections to disconnect.
function Stop(tasks)
	local stopped, err = pcall(function(tasks)
		H.waist.C0 = H.origWaist
		H.neck.C0  = H.origNeck
		for _, t in ipairs(tasks) do
			print("Disconnected")
			t:Disconnect()
		end
	end)
	if stopped then
		tool.Grip = CFrame.new(Vector3.new(-.5, .2, .5)) * CFrame.Angles(math.rad(0), math.rad(-60), math.rad(0))
		if playerChar and playerChar["Humanoid"] then
			playerChar.Humanoid.WalkSpeed = 20
		end
	end
end

--- Scope the camera and update a laser beam to the mouse ray.
-- Positions the camera at the provided offset; stretches a thin part from barrel to a fixed-length cursor ray.
-- @param offset CFrame provider (Header.offset) used to position the camera.
-- @param laser Part|nil Optional beam part to resize/reposition as a laser.
function Scoping(offset, laser)
	Camera.CFrame = offset.CFrame * CFrame.Angles(0, math.rad(-90), 0)

	local mouse = Player:GetMouse()

	if mouse.Target then
		local mouseLoc = UIS:GetMouseLocation()
		local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
		local origin = barrel.Position
		local endPos = origin + ray.Direction.Unit * 200 -- fixed length
		local dist = (endPos - origin).Magnitude

		if laser then
			laser.Size = Vector3.new(0.1, 0.1, dist)
			laser.CFrame = CFrame.new(origin, endPos) * CFrame.new(0, 0, -dist/2)
		end
	else
		laser.Size = Vector3.new(0, 0, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- Equip: prepare Header, animations, grip, and scope interaction
----------------------------------------------------------------------------------------------------
equipped = tool.Equipped:Connect(function()
	H = require(script:WaitForChild("Header"))(tool, Player)

	local playerChar = H.playerChar
	local humanoid   = H.playerChar:WaitForChild("Humanoid")
	local charSize   = H.playerChar:GetExtentsSize()

	H.equipAnimTrack.Priority = Enum.AnimationPriority.Action4;
	H.equipAnimTrack:Play();
	H.holdAnimTrack.Looped    = true;
	H.holdAnimTrack.Priority  = Enum.AnimationPriority.Action4
	H.holdAnimTrack:Play();

	tool.Grip = CFrame.new(Vector3.new(-.5, .2, .5)) *
		CFrame.Angles(math.rad(0), math.rad(-60), math.rad(0))

	if playerChar then
		local hrp   = playerChar:WaitForChild("HumanoidRootPart")
		local hrpCF = hrp.CFrame

		local handleCFrame = handle.CFrame + Vector3.new(-2,0,0)

		local debScope, debShoot, debEnd = false, false, false

		-- Right mouse button: enter scoped mode and start laser/camera updates
		scoped = UIS.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and not debScope then running[#running + 1] = scoped

				UIS.MouseBehavior = Enum.MouseBehavior.LockCenter; Camera.CameraType = Enum.CameraType.Scriptable

				local mouseLoc = UIS:GetMouseLocation()
				local finished = H.ScopeIn(hrp.CFrame, Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y))

				local laser = H.Laser(hrp.CFrame); laser.Parent = tool

				local scoping = RS:BindToRenderStep("Scoping", Enum.RenderPriority.Camera.Value,
					function() Scoping(H.offset, laser) end)

				playerChar["Humanoid"].WalkSpeed = 0
				playerChar["Animate"].Enabled = false

				local currentLean, currentRot = 0, 0
				local finished = false
				debScope = true
				tilt = UIS.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement then
						local mouseDelta = input.Delta
						if mouseDelta.X ~= 0 or mouseDelta.Y ~= 0 then
							currentLean, currentRot = H.Tilt(mouseDelta, currentLean, currentRot)
						end
					end
					UIS.InputEnded:Connect(function(input)
						if input == Enum.UserInputType.MouseButton2 then debScope = false tilt:Disconnect() end
					end)
				end)
				--RS:BindToRenderStep("moving_camera", Enum.RenderPriority.Camera.Value,	--function() H.FollowCamera(playerChar["HumanoidRootPart"].CFrame) end)
			end
		end)
	end
end)

----------------------------------------------------------------------------------------------------
-- Shoot: left mouse while scoped → send ray to server and stop local scoping
----------------------------------------------------------------------------------------------------
local debounce = false
shoot = UIS.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and scoped and not debounce then

		print("Shot")

		RS:UnbindFromRenderStep("Scoping")

		local mouseLoc = UIS:GetMouseLocation()
		local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)

		H.holdAnimTrack.Priority = Enum.AnimationPriority.Action4
		H.holdAnimTrack:Play()
		H.holdAnimTrack.Looped = true;

		FireGrappleEvent:FireServer(ray, barrel, debounce)
		debounce = true
		Stop(running)
	end
end)

----------------------------------------------------------------------------------------------------
-- Server Acknowledgement: restore camera/mouse modes and re-enable an
