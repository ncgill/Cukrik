--[[
	Header Module
  Parented to client tool script in tool object
	-------------
	Provides a small helper object for first-person/over-the-shoulder weapon handling:
	- Loads and configures equip/hold animation tracks.
	- Stores references to the player's character, camera, and upper-body joints.
	- Exposes helpers to:
	  * spawn a neon laser Part (Laser),
	  * apply lean/rotation to waist and neck based on mouse delta (Tilt),
	  * position the camera behind/above the character (FollowCamera),
	  * scope in with a short camera zoom toward the current aim ray (ScopeIn).

	Construction:
	- Header.new(tool: Instance, player: Player) -> Header
	- The module is callable: require(Header)(tool, player) == Header.new(tool, player)

	Fields (selected):
	- Player, playerChar, Camera
	- equipAnim, holdAnim, equipAnimTrack, holdAnimTrack
	- waist, neck, origWaist, origNeck
	- offset (Part or Attachment providing a CFrame for scoped camera offset)
	- LASER_PROP (table of default Part properties for the laser)
	- MAX_LEAN, MIN_LEAN, MAX_ROT, MIN_ROT (radians)
]]

local Header = {}
Header.__index = Header

--- Construct a new Header helper object for the given tool and player.
-- Loads animations, caches character/camera/joints, and sets aiming limits.
-- @param tool Instance The tool instance owning assets like animations and offset.
-- @param player Player The local player this header will control.
-- @return table Header instance with helper methods and cached references.
function Header.new(tool: Instance, player: Player)
	local self = setmetatable({}, Header)

	self.Player = player
	self.playerChar = player.Character or player.CharacterAdded:Wait()
	self.Camera = workspace.CurrentCamera
	local hum = self.playerChar:WaitForChild("Humanoid")
	
	-- Animations
	self.equipAnim = tool:WaitForChild("EquipAnim")
	self.holdAnim  = tool:WaitForChild("EquipHold")
	self.equipAnimTrack = hum:LoadAnimation(self.equipAnim)
	self.equipAnimTrack.Priority = Enum.AnimationPriority.Action4
	self.holdAnimTrack  = hum:LoadAnimation(self.holdAnim)
	self.holdAnimTrack.Priority = Enum.AnimationPriority.Action4
	self.holdAnimTrack.Looped = true 

	-- Aiming limits (radians)
	self.MAX_LEAN = math.rad(45)
	self.MIN_LEAN = math.rad(-10)
	self.MIN_ROT  = math.rad(-45)
	self.MAX_ROT  = math.rad(45)

	-- Default properties for laser part
	self.LASER_PROP = {
		Size         = Vector3.new(.5, .5, .5),
		Shape        = Enum.PartType.Block,
		BrickColor   = BrickColor.new("Bright red"),
		Anchored     = true,
		CanCollide   = false,
		Transparency = .7,
		Material     = Enum.Material.Neon,
	}
	
	-- Character joints and camera offset source
	self.waist = self.playerChar["UpperTorso"]["Waist"] 
	self.neck = self.playerChar["Head"]["Neck"]
	self.offset = tool:WaitForChild("Offset")

	-- Original joint transforms (for restoration)
	self.origWaist = self.playerChar["UpperTorso"]["Waist"].C0
	self.origNeck = self.playerChar["Head"]["Neck"].C0
	
	--- Create a neon laser Part using LASER_PROP and parent it to the tool.
	-- @return Part A newly created, configured laser part parented to the tool.
	self.Laser = function()
		local laser = Instance.new("Part")
		for k, v in pairs(self.LASER_PROP) do
			laser[k] = v
		end
		laser.Parent = tool
		return laser
	end
	
	--- Apply incremental leaning/rotation to waist and neck based on mouse delta.
	-- Keeps angles within MIN/MAX bounds and returns updated accumulators.
	-- @param mouseDelta Vector2 The per-frame mouse delta (X,Y).
	-- @param currentLean number Current accumulated pitch (radians).
	-- @param currentRot number Current accumulated yaw (radians).
	-- @return number, number Updated (currentLean, currentRot) in radians.
	self.Tilt = function(mouseDelta, currentLean, currentRot)
		local currentLean = math.clamp(currentLean - mouseDelta.Y * 0.005, self.MIN_LEAN, self.MAX_LEAN)
		local currentRot = math.clamp(currentRot - mouseDelta.X * .005, self.MIN_ROT, self.MAX_ROT)
		self.waist.C0 = CFrame.new(self.waist.C0.Position) * CFrame.Angles(currentLean, currentRot, 0)
		self.neck.C0 = CFrame.new(self.neck.C0.Position) * CFrame.Angles(currentLean, currentRot, 0)
		return currentLean, currentRot
	end
	
	--- Position the camera slightly above/behind the character, facing forward.
	-- @param hrpCF CFrame The character's HumanoidRootPart CFrame.
	self.FollowCamera = function(hrpCF)
		local world = hrpCF:VectorToWorldSpace(Vector3.new(0,4,0)) 
		local origin = hrpCF.Position + hrpCF.LookVector * -5
		self.Camera.CFrame = CFrame.lookAt(
			(origin + world),
			(origin + world + hrpCF.LookVector)
		)			
	end
	
	--- Scope in with a short zoom animation toward the current aim direction.
	-- Eases the camera position toward self.offset while looking along the given ray.
	-- @param hrpCF CFrame The character's HumanoidRootPart CFrame at scope start.
	-- @param ray Ray The current view ray (Origin, Direction).
	-- @param deb any Unused argument preserved for compatibility.
	self.ScopeIn = function(hrpCF, ray, deb)
		local world = hrpCF:VectorToWorldSpace(Vector3.new(0,3,0)) 
		local origin = hrpCF.Position + hrpCF.LookVector * -4
		self.Camera.CFrame = CFrame.lookAt(
			(origin + world),
			(origin + world + hrpCF.LookVector)
		)
		local zoom 
		local elapsed = 0 
		local zoomTime = .75
		local endPos = origin + ray.Direction.Unit * 200
		
		zoom = game:GetService("RunService").RenderStepped:Connect(function(dt)
			elapsed += dt
			local difference = self.Camera.CFrame.Position - (origin + world)
			local current = self.Camera.CFrame.Position:Lerp(self.offset.CFrame.Position, elapsed / zoomTime)
			self.Camera.CFrame = CFrame.lookAt(current, endPos)
			if elapsed >= zoomTime then return true end 
		end)
		zoom:Disconnect()
	end

	return self
end

-- Keep module callable: require(Header)(tool, player) → Header.new(tool, player)
setmetatable(Header, {
	__call = function(_, tool: Instance, player: Player)
		return Header.new(tool, player)
	end
})

return Header
