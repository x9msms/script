-- ============================================================
-- AC Kill
-- ============================================================
local function killAC(char)
    local Humanoid = char:WaitForChild("Humanoid", 10)
    local HRP      = char:WaitForChild("HumanoidRootPart", 10)
    if not Humanoid or not HRP then return end

    local killed = 0

    for _, sig in ipairs({
        Humanoid:GetPropertyChangedSignal("WalkSpeed"),
        Humanoid:GetPropertyChangedSignal("HipHeight"),
        HRP:GetPropertyChangedSignal("CanCollide"),
    }) do
        local ok, conns = pcall(getconnections, sig)
        if ok then
            for _, c in ipairs(conns) do
                if pcall(function() c:Disable() end) then killed += 1 end
            end
        end
    end

    local ok, conns = pcall(getconnections, char.DescendantAdded)
    if ok then
        for _, c in ipairs(conns) do
            local fn     = c.Function
            local consts = {}
            pcall(function()
                local k = debug.getconstants(fn)
                if k then for _, v in pairs(k) do
                    if type(v) == "string" then table.insert(consts, v) end
                end end
            end)
            local isAC = false
            for _, v in ipairs(consts) do
                if v == "BodyGyro" or v == "BodyVelocity" then isAC = true end
            end
            if isAC then
                if pcall(function() c:Disable() end) then killed += 1 end
            else
                pcall(function() c:Enable() end)
            end
        end
    end

    print(("[AC-kill] %d killed"):format(killed))
end

local LocalPlayer = game.Players.LocalPlayer

if LocalPlayer.Character then killAC(LocalPlayer.Character) end

getgenv()._acKillConn = LocalPlayer.CharacterAdded:Connect(function(c)
    task.wait(1)
    killAC(c)
end)

-- ============================================================
-- Lupin Auto — Noclip + Hide v3 (Full Body Check)
-- ============================================================

local Players    = game:GetService("Players")

local player = Players:GetPlayers()[1]

-- =========================
-- CONFIG
-- =========================
local THREAT_DISTANCE        = 45
local TP_COOLDOWN            = 1
local FIRE_COOLDOWN          = 0.3
local BUSY_TIMEOUT           = 15
local HIDE_CHECK_INTERVAL    = 0.01
local WALL_PENETRATION_SPEED = 30
local NOCLIP_SPEED           = 30
local NOCLIP_ARRIVE_DIST     = 8
local NOCLIP_TICK            = 0.1

-- =========================
-- STATE
-- =========================
local isBusy        = false
local currentTarget = nil
local lastTpTime    = 0
local lastFireTime  = 0
local busyStartTime = 0
local isEvading     = false
local hideActive    = false
local hideParts     = {}

-- =========================
-- HELPERS
-- =========================
local function getCharacter()
    local char = player and player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root     = char:FindFirstChild("HumanoidRootPart")
    return char, humanoid, root
end

local function getGeneratorPosition(generator)
    if generator.PrimaryPart then return generator.PrimaryPart.Position end
    return generator:GetPivot().Position
end

local function distance(a, b)
    if not a or not b then return math.huge end
    return (a - b).Magnitude
end

-- =========================
-- NOCLIP HELPERS (movement)
-- =========================
local _moveNoclipParts = {}

local function noclipEnable(char)
    _moveNoclipParts = {}
    for _, p in pairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            _moveNoclipParts[p] = p.CanCollide
            p.CanCollide = false
        end
    end
end

local function noclipDisable()
    for p, v in pairs(_moveNoclipParts) do
        if p and p.Parent then p.CanCollide = v end
    end
    _moveNoclipParts = {}
end

local function setBodyVel(root, vel)
    local bv = root:FindFirstChild("_NoclipBV")
    if not bv then
        bv          = Instance.new("BodyVelocity")
        bv.Name     = "_NoclipBV"
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Parent   = root
    end
    bv.Velocity = vel
end

local function clearBodyVel(root)
    local bv = root:FindFirstChild("_NoclipBV")
    if bv then bv:Destroy() end
end

-- =========================
-- MONSTER DETECTION
-- =========================
local function getMyModel()
    local char = player and player.Character
    if char and char.Parent then return char end
    local inGame = workspace:FindFirstChild("InGamePlayers")
    if inGame then
        for _, obj in pairs(inGame:GetChildren()) do
            if obj:IsA("Model") and obj:GetAttribute("UserId") == player.UserId then
                return obj
            end
        end
    end
    return nil
end

local function isMonsterChasingMe()
    local myModel = getMyModel()
    if not myModel then return false, nil, nil end

    local currentRoom = workspace:FindFirstChild("CurrentRoom")
    if not currentRoom then return false, nil, nil end

    for _, map in pairs(currentRoom:GetChildren()) do
        if map:IsA("Model") or map:IsA("Folder") then
            local monstersFolder = map:FindFirstChild("Monsters")
            if monstersFolder then
                for _, monster in pairs(monstersFolder:GetChildren()) do
                    if monster:IsA("Model") then
                        local cv = monster:FindFirstChild("ChasingValue")
                        if cv and cv:IsA("ObjectValue") and cv.Value == myModel then
                            local monRoot = monster:FindFirstChild("HumanoidRootPart")
                            if monRoot then
                                local myRoot = myModel:FindFirstChild("HumanoidRootPart")
                                if myRoot then
                                    local dist = distance(myRoot.Position, monRoot.Position)
                                    if dist < THREAT_DISTANCE then
                                        return true, monster, dist
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false, nil, nil
end

-- =========================
-- WALL CONTAINMENT CHECK
-- true = ทั้งตัวอยู่ในกำแพงแล้ว
-- =========================
local function isFullyInsideWall(char, root)
    local params = OverlapParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Exclude

    -- root ต้องอยู่ในก่อน
    if #workspace:GetPartsInPart(root, params) == 0 then
        return false
    end

    -- เช็ค head + torso ด้วย
    local head  = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")

    for _, part in ipairs({head, torso}) do
        if part and part:IsA("BasePart") then
            if #workspace:GetPartsInPart(part, params) == 0 then
                return false
            end
        end
    end

    return true
end

-- =========================
-- HIDE IN WALL v3
-- push เข้าจนทั้งตัวในกำแพง → หยุด
-- force CanCollide=false ทุก tick
-- push กลับถ้าหลุดออก
-- ออกแค่ตอนมอนเปลี่ยนเป้า หรือ timeout
-- =========================
local function enableHide(char, root)
    if hideActive then return end
    hideActive = true
    hideParts  = {}
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            hideParts[part] = part.CanCollide
            part.CanCollide = false
        end
    end
    if not root:FindFirstChild("HideVelocity") then
        local bv       = Instance.new("BodyVelocity")
        bv.Name        = "HideVelocity"
        bv.Velocity    = Vector3.zero
        bv.MaxForce    = Vector3.new(math.huge, math.huge, math.huge)
        bv.Parent      = root
    end
    print("🪨 enableHide — noclip ON")
end

local function disableHide(root)
    if not hideActive then return end
    hideActive = false
    if root then
        local bv = root:FindFirstChild("HideVelocity")
        if bv then bv:Destroy() end
    end
    for part, canCollide in pairs(hideParts) do
        if part and part.Parent then part.CanCollide = canCollide end
    end
    hideParts = {}
    print("✅ disableHide — noclip OFF")
end

local function hideInWall()
    local char, humanoid, root = getCharacter()
    if not char or not root or not humanoid then return end

    local _, monster, dist = isMonsterChasingMe()
    if not monster then return end

    print("⚠️ มอนไล่! ระยะ:", dist, "-> เข้ากำแพง")

    enableHide(char, root)

    local monRoot   = monster:FindFirstChild("HumanoidRootPart")
    local escapeDir = Vector3.new(0, 0, 1)
    if monRoot then
        local d = root.Position - monRoot.Position
        if d.Magnitude > 0 then escapeDir = d.Unit end
    end

    local hideWait = 0

    while hideActive do
        task.wait(HIDE_CHECK_INTERVAL)
        hideWait += HIDE_CHECK_INTERVAL

        -- force CanCollide=false ทุก tick — AC กลับมาไม่ได้
        for part in pairs(hideParts) do
            if part and part.Parent then
                part.CanCollide = false
            end
        end

        -- timeout
        if hideWait > 45 then
            print("⏱️ timeout 45s -> ออก")
            break
        end

        -- มอนเปลี่ยนเป้าแล้ว → ออก
        if not isMonsterChasingMe() then
            print("✅ มอนเปลี่ยนเป้า (" .. string.format("%.1f", hideWait) .. "s) -> ออก")
            break
        end

        -- เช็คทั้งตัวอยู่ในกำแพงหรือยัง
        local bv = root:FindFirstChild("HideVelocity")
        if bv then
            if isFullyInsideWall(char, root) then
                bv.Velocity = Vector3.zero
            else
                bv.Velocity = escapeDir * WALL_PENETRATION_SPEED
            end
        end
    end

    disableHide(root)
end

-- =========================
-- STOP INTERACTING
-- =========================
local function stopInteracting(generator)
    if not generator or not generator.Parent then return end
    local stats = generator:FindFirstChild("Stats")
    if not stats then return end
    local ev = stats:FindFirstChild("StopInteracting")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function() ev:FireServer("Stop") end)
    end
end

-- =========================
-- GENERATOR QUERIES
-- =========================
local function getClosestGenerator()
    local _, _, root = getCharacter()
    local room       = workspace:FindFirstChild("CurrentRoom")
    if not root or not room then return nil end
    local closest, minDist = nil, math.huge
    for _, model in ipairs(room:GetChildren()) do
        if model:IsA("Model") or model:IsA("Folder") then
            local folder = model:FindFirstChild("Generators")
            if folder then
                for _, gen in ipairs(folder:GetChildren()) do
                    if gen:IsA("Model") then
                        local stats     = gen:FindFirstChild("Stats")
                        local completed = stats and stats:FindFirstChild("Completed")
                        if completed and completed:IsA("BoolValue") and not completed.Value then
                            local d = (root.Position - getGeneratorPosition(gen)).Magnitude
                            if d < minDist then minDist = d; closest = gen end
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function allGeneratorsCompleted()
    local room = workspace:FindFirstChild("CurrentRoom")
    if not room then return false end
    local foundAny = false
    for _, model in ipairs(room:GetChildren()) do
        if model:IsA("Model") or model:IsA("Folder") then
            local folder = model:FindFirstChild("Generators")
            if folder then
                for _, gen in ipairs(folder:GetChildren()) do
                    if gen:IsA("Model") then
                        local stats     = gen:FindFirstChild("Stats")
                        local completed = stats and stats:FindFirstChild("Completed")
                        if completed and completed:IsA("BoolValue") then
                            foundAny = true
                            if not completed.Value then return false end
                        end
                    end
                end
            end
        end
    end
    return foundAny
end

local function isGeneratorCompleted(generator)
    if not generator or not generator.Parent then return true end
    local stats     = generator:FindFirstChild("Stats")
    local completed = stats and stats:FindFirstChild("Completed")
    if completed and completed:IsA("BoolValue") then return completed.Value end
    return false
end

-- =========================
-- TELEPORT ARRIVE
-- =========================
local function teleportInFront(target, dist)
    local _, _, root = getCharacter()
    if not root then return false end
    if tick() - lastTpTime < TP_COOLDOWN then return false end
    lastTpTime = tick()
    dist = dist or 5
    local ok, pivot = pcall(function() return target:GetPivot() end)
    if not ok or not pivot then return false end
    local d = pivot.Position - root.Position
    d = d.Magnitude > 0 and d.Unit or pivot.LookVector
    root.CFrame = CFrame.new(pivot.Position - d * dist + Vector3.new(0, 3, 0))
    task.wait(0.2)
    return true
end

-- =========================
-- NOCLIP MOVE
-- บินตรงเป้า เช็คมอนทุก tick
-- returns: "reached" | "threat" | "changed" | "fail"
-- =========================
local function moveToTarget(target)
    local char, humanoid, root = getCharacter()
    if not char or not humanoid or not root then return "fail" end

    if isMonsterChasingMe() then
        stopInteracting(currentTarget)
        isEvading = true; hideInWall(); isEvading = false
        return "threat"
    end

    local function getTargetPos()
        if typeof(target) == "Vector3" then return target end
        return getGeneratorPosition(target)
    end

    noclipEnable(char)

    while true do
        task.wait(NOCLIP_TICK)

        -- force noclip ทุก tick ระหว่างบิน
        for p in pairs(_moveNoclipParts) do
            if p and p.Parent then p.CanCollide = false end
        end

        if isMonsterChasingMe() then
            clearBodyVel(root)
            noclipDisable()
            humanoid:MoveTo(root.Position)
            stopInteracting(currentTarget)
            isEvading = true; hideInWall(); isEvading = false
            return "threat"
        end

        if typeof(target) ~= "Vector3" and isGeneratorCompleted(target) then
            clearBodyVel(root)
            noclipDisable()
            humanoid:MoveTo(root.Position)
            return "changed"
        end

        local targetPos = getTargetPos()
        local delta     = targetPos - root.Position
        local dist      = delta.Magnitude

        if dist <= NOCLIP_ARRIVE_DIST then
            clearBodyVel(root)
            noclipDisable()
            humanoid:MoveTo(root.Position)
            if typeof(target) ~= "Vector3" then teleportInFront(target, 5) end
            return "reached"
        end

        setBodyVel(root, delta.Unit * NOCLIP_SPEED)
    end
end

-- =========================
-- PROMPT FIRING
-- =========================
local function getAttachmentAndPrompt(generator)
    for _, obj in ipairs(generator:GetDescendants()) do
        if obj:IsA("Attachment") then
            local p = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
            if p then return obj, p end
        end
    end
    return nil, nil
end

local function fireGeneratorPrompt(generator)
    if tick() - lastFireTime < FIRE_COOLDOWN then return false end
    lastFireTime = tick()

    local attachment, prompt = getAttachmentAndPrompt(generator)
    if not prompt then return false end

    if isMonsterChasingMe() then
        isEvading = true; hideInWall(); isEvading = false
        return false
    end

    local _, _, root = getCharacter()
    if root then
        local promptPos = attachment and attachment.WorldPosition or getGeneratorPosition(generator)
        local maxDist   = prompt.MaxActivationDistance or 10
        if (root.Position - promptPos).Magnitude > maxDist then return false end
    end

    if prompt.HoldDuration and prompt.HoldDuration > 0 then
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration)
        prompt:InputHoldEnd()
    else
        if fireproximityprompt then
            fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
        end
    end

    return true
end

-- =========================
-- ELEVATOR
-- =========================
local function getElevator()
    return workspace:FindFirstChild("Elevators")
        and workspace.Elevators:FindFirstChild("Elevator")
end

-- =========================
-- MAIN LOOP
-- =========================
while true do
    task.wait(0.2)

    if isBusy and (tick() - busyStartTime) > BUSY_TIMEOUT then
        warn("⚠️ isBusy timeout -> reset")
        isBusy = false; currentTarget = nil
    end

    if isBusy or isEvading then continue end

    if allGeneratorsCompleted() then
        print("🎉 Generator ครบ -> Elevator")
        local elevator = getElevator()
        if elevator then
            isBusy = true; busyStartTime = tick(); currentTarget = elevator
            moveToTarget(elevator)
            print("✅ ถึง Elevator")
            isBusy = false; currentTarget = nil
        end
        task.wait(2)
        continue
    end

    local generator = getClosestGenerator()
    if not generator then task.wait(1); continue end
    if currentTarget == generator and isBusy then continue end

    print("🎯 เป้า:", generator.Name)
    isBusy = true; busyStartTime = tick(); currentTarget = generator

    local result = moveToTarget(generator)

    if result ~= "reached" then
        print("🔁 ->", result)
        isBusy = false; currentTarget = nil
        task.wait(result == "fail" and 0.5 or 0.1)
        continue
    end

    local stats     = generator:FindFirstChild("Stats")
    local completed = stats and stats:FindFirstChild("Completed")

    if completed and completed:IsA("BoolValue") then
        print("⏳ Fire ->", generator.Name)

        while generator.Parent and not completed.Value do
            if isMonsterChasingMe() then
                stopInteracting(generator)
                isEvading = true; hideInWall(); isEvading = false
                break
            end

            local ok = fireGeneratorPrompt(generator)
            task.wait(0.2)

            if completed.Value then
                print("✅", generator.Name, "done!")
                break
            end

            if not ok then
                warn("fire ไม่สำเร็จ -> re-approach")
                moveToTarget(generator)
            end

            task.wait(0.3)
        end
    end

    isBusy = false; currentTarget = nil
end
