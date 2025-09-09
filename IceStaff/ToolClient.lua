--[[
    Fire Staff Client Controller
    ----------------------------
    Plays a wrist/hand aiming sequence toward the mouse cursor, then signals the
    server to fire an ice orb. When the server replies with a target and distance,
    this client animates the orb's flight and handles impact burst VFX.
]]

-- Services
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local fireStaffRE = game:GetService("ReplicatedStorage"):WaitForChild("fireStaffRE")
local Camera = workspace.CurrentCamera

-- Tool / Parts
local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local particles = tool:WaitForChild("iceParticles")
local iceParticles = tool:WaitForChild("iceParticles")

-- Player / Character
local player = game.Players.LocalPlayer
local humanoid = player.Character:WaitForChild("Humanoid")
local BASE_GRIP = tool.Grip
local hand = nil
local hrp = player.Character:WaitForChild("HumanoidRootPart")

-- Animation Track
local fireStaffTrack = humanoid:LoadAnimation(fireStaffAnim)
local fireStaffAnim = Instance.new("Animation")
fireStaffAnim.AnimationId = "rbxassetid://76027817760585"

-- Constants / Configuration
local ORB_PROPERTIES = {
	["Shape"] = "Ball",
	["Size"] = Vector3.new(2,2,2),
	["Material"] = "Marble",
	["BrickColor"] = BrickColor.new("Pastel light blue"),
	["CanTouch"] = true,
	["CanCollide"] = true,
	["Anchored"] = false,
	["Transparency"] = 1
}

-- Runtime State
local frameReached = nil 
local animMarkers = {}
local debounce = false 


-- Helpers 
--- Check whether a tween completed and optionally play a follow-up tween.
-- @param playbackState Enum.PlaybackState The tween's final state from Completed.
-- @param nextTween Tween? Optional tween to start when the current tween completes.
-- @return boolean True if tween completed and there is no follow-up
function checkTweenCompleted(playbackState, nextTween)
	if playbackState ~= Enum.PlaybackState.Completed then 
		return false 
	elseif nextTween ~= nil then
		nextTween:Play()
	else
		return true
	end
end

--- Spawn an orb part at the tool handle with default properties and ice particles.
-- @return Part The created orb instance parented to the player's character.
function SpawnOrb()
	local orb = Instance.new("Part")
	iceParticles:Clone().Parent = orb
	orb.Name = player.Name.."Orb"
	orb.Parent = player.Character
	orb.CFrame = tool:WaitForChild("Handle").CFrame
	for property, v in pairs(ORB_PROPERTIES) do orb[property] = v end
	return orb
end

--- Emit a brief high-intensity particle burst from the given orb.
-- @param orb Part The orb from which to emit the burst.
function Burst(orb)
	local burstParticles = Instance.new("ParticleEmitter")
	burstParticles.Rate = 0
	burstParticles.Lifetime = NumberRange.new(0.75, 0.75)
	burstParticles.Speed = NumberRange.new(20, 20)
	burstParticles.SpreadAngle = Vector2.new(-120, 120)
	burstParticles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)  
	})

	burstParticles.Texture = "rbxassetid://140534197119077"
	burstParticles.Parent = orb
	burstParticles:Emit(100)
end


-- Input / Activation
-- Triggered when the tool is activated (e.g., mouse click while equipped).
-- Orients the character toward the mouse, plays wrist tweens + animation, and sends a server fire request with a ray derived from the current mouse position.
tool.Activated:Connect(function()

	if debounce then print("No") return false end 
	debounce = true 
	local currTween
	local nextTween
	local mouse = player:GetMouse()
	local mouseHit = mouse.Hit.Position

	hand = player.Character:WaitForChild("RightHand")

	hrp.CFrame = CFrame.new(hrp.CFrame.Position, mouseHit)

	local wrist = player.Character:WaitForChild("RightHand"):WaitForChild("RightWrist")
	local base = wrist.C0

	local tweenPoints = {

		{C0 = wrist.C0 * CFrame.new(0,-2,-2) * CFrame.Angles(math.rad(0), math.rad(0), math.rad(0))},
		{C0 = wrist.C0 * CFrame.new(0,-4,0) * CFrame.Angles(math.rad(0), math.rad(90), math.rad(0))},

	}

	local TWEEN_TIME = .4
	local TWEEN_INFO = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local goalCF = CFrame.lookAt(handle.Position, mouseHit, base.UpVector)
	local hum = player.Character:FindFirstChild("Humanoid")

	if goalCF then 
		table.insert(tweenPoints, {C0 = hand.CFrame:Inverse() * goalCF})
	end

	if hum then hum.WalkSpeed = 0 end

	local DURATION = (TWEEN_TIME * (#tweenPoints))
	local SPEED_FACTOR = ((fireStaffTrack.Length) / DURATION)

	local playAnim = true

	--- Plays the staff animation while stepping tweens; fires the server when ready.
	-- @return boolean Always false (loop exit sentinel), preserving original behavior.
	local function runShoot()

		local playAnim = task.spawn(function()
			fireStaffTrack:Play()
			fireStaffTrack:AdjustSpeed(SPEED_FACTOR)
		end)

		hand.Transparency = 1 
		local mouseLoc = UIS:GetMouseLocation()
		local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)

		while playAnim do 
			for i = 1, #tweenPoints, 1 do

				if i > #tweenPoints then break end
				currTween = TS:Create(wrist, TWEEN_INFO, tweenPoints[i])

				if tweenPoints[i + 1] then 
					nextTween = TS:Create(wrist, TWEEN_INFO, tweenPoints[i + 1])
				end

				if currTween then currTween:Play() end
				currTween.Completed:Wait()

				if playAnim then 
					if nextTween and i < #tweenPoints then 
						nextTween:Play()	
					else
						nextTween = nil 
						fireStaffRE:FireServer("fire", tool, ray)
					end
					if nextTween then nextTween.Completed:Wait() end
				end
			end
			break	
		end
		return false
	end

	while runShoot() do 
		task.wait()
	end

	currTween = TS:Create(wrist, TWEEN_INFO, {C0 = base})
	currTween:Play()
	currTween.Completed:Wait()
	wrist.C0 = base
	hum.WalkSpeed = 16
	task.wait(2)
	debounce = false 
end)

-- Remote Response: Orb flight and impact VFX
-- Responds to the server with a target Vector3 and travel distance.
-- Spawns an orb, eases it toward the target using RenderStepped, then performs impact cleanup and a particle burst on arrival.
fireStaffRE.OnClientEvent:Connect(function(target, distance)
	local elapsed = 0 
	local timer = distance / 150

	local orb = SpawnOrb()
	particles = iceParticles:Clone()
	particles.Parent = orb 

	local shooting; shooting = RS.RenderStepped:Connect(function(dt)

		elapsed += dt
		local alpha = math.clamp(elapsed / timer, 0, 1)
		orb.CFrame = CFrame.new(tool.Handle.CFrame.Position:Lerp(target, alpha))

		if alpha >= 1 then	
			orb.Anchored = true
			particles.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),  
				NumberSequenceKeypoint.new(1, 1)   
			})
			particles.Enabled = false 
			particles.Rate = 0
			Burst(orb)

			task.delay(3, function() orb:Destroy() end)

			shooting:Disconnect()
		end		
	end)
end)
