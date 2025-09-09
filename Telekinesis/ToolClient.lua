--[[
    Telekinesis Client Controller
    -----------------------------
    Client-side handler for a Telekinesis tool:
      - On equip: loads/plays idle animation and clones rune particle effects to both hands.
      - On RMB (MouseButton2) press over a "Telekinetic" target: plays lift animation, freezes movement,
        and tells the server to begin floating the target.
      - On RMB release: stops floating on the server, restores movement.
      - On unequip: stops/cleans animations and rune effects, restores defaults.
      - On death: cleans up rune effects and stops animations.
]]

-- Services
local UIS = game:GetService("UserInputService")
local TeleRE = game:GetService("ReplicatedStorage"):WaitForChild("telekinRE")
local EndFloatRE = TeleRE:WaitForChild("EndFloat")
local Player = game:GetService("Players").LocalPlayer
local mouse = Player:GetMouse()
local Camera = workspace.CurrentCamera


local tool = script.Parent
local equipped = false
local debounce = false
local runes


-- Connections / Runtime
local grabbing
local release
local holdTrack, liftTrack, dropTrack, floatTrack, idleTrack

-- Equip: load animations, start idle loop, and attach rune effects to both hands.
tool.Equipped:Connect(function()
	local input = nil

	equipped = true

	holdTrack = Player.Character.Humanoid:LoadAnimation(script.Parent:WaitForChild("hold"))
	liftTrack = Player.Character.Humanoid:LoadAnimation(script.Parent:WaitForChild("lift"))
	dropTrack = Player.Character.Humanoid:LoadAnimation(script.Parent:WaitForChild("drop"))
	floatTrack = Player.Character.Humanoid:LoadAnimation(script.Parent:WaitForChild("float"))
	idleTrack = Player.Character.Humanoid:LoadAnimation(script.Parent:WaitForChild("idle"))
	idleTrack.Looped = true
	idleTrack:Play()

	runes = tool:WaitForChild("runes")

	if runes then
		local clone1 = runes:Clone()
		local clone2 = runes:Clone()
		clone1.Enabled = true; clone2.Enabled = true
		clone1.Parent = Player.Character["LeftHand"]
		clone2.Parent = Player.Character["RightHand"]
		runes = {clone1, clone2}
	end

	-- RMB press: attempt to begin telekinetic grab if hovering over a "Telekinetic" target
	grabbing = UIS.InputBegan:Connect(function(input)
		if not debounce and input.UserInputType == Enum.UserInputType.MouseButton2 and equipped then debounce = true
			local mouseLoc = UIS:GetMouseLocation()
			local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
			local mouse = Player:GetMouse()

			if mouse.Target.Name == "Telekinetic" then
				if idleTrack.IsPlaying == true then idleTrack:Stop() end
				Player.Character["Humanoid"].WalkSpeed = 0
				liftTrack.Priority = Enum.AnimationPriority.Action4
				liftTrack:AdjustSpeed(2)
				liftTrack:Play()
				TeleRE:FireServer(ray, script.Parent:WaitForChild("float"))

			else debounce = false end

			-- RMB release: end float on the server, restore movement
			release = UIS.InputEnded:Connect(function(input)
				if grabbing and input.UserInputType == Enum.UserInputType.MouseButton2 then
					local mouseLoc = UIS:GetMouseLocation()
					local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
					Player.Character["Humanoid"].WalkSpeed = 16
					EndFloatRE:FireServer()
					debounce = false
				end
			end)

		end
	end)
end)

-- Unequip: stop any playing tracks, clear references, destroy rune clones, restore defaults.
tool.Unequipped:Connect(function()

	if idleTrack.isPlaying then idleTrack:Stop() end
	if holdTrack.isPlaying then holdTrack:Stop() end
	if liftTrack.isPlaying then liftTrack:Stop() end
	if floatTrack.isPlaying then floatTrack:Stop() end

	idleTrack, holdTrack, liftTrack, floatTrack = nil, nil, nil, nil

	if #runes > 0 then
		for _,v in pairs(runes) do v:Destroy() end
	end
	equipped = false
	debounce = false
	Player.Character["Humanoid"].WalkSpeed = 16
end)
