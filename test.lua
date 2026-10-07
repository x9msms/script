local function killAC(char)
    local Humanoid = char:WaitForChild("Humanoid", 10)
    local HRP = char:WaitForChild("HumanoidRootPart", 10)
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
                if pcall(function() c:Disable() end) then killed = killed + 1 end
            end
        end
    end

    local ok, conns = pcall(getconnections, char.DescendantAdded)
    if ok then
        for _, c in ipairs(conns) do
            local fn = c.Function
            local consts = {}
            pcall(function()
                local k = debug.getconstants(fn)
                if k then for _, v in pairs(k) do if type(v) == "string" then table.insert(consts, v) end end end
            end)
            local isAC = false
            for _, v in ipairs(consts) do
                if v == "BodyGyro" or v == "BodyVelocity" then isAC = true end
            end
            if isAC then
                if pcall(function() c:Disable() end) then killed = killed + 1 end
            else
                pcall(function() c:Enable() end)
            end
        end
    end
    print(("[AC-kill] %d killed"):format(killed))

end

local LocalPlayer = game.Players.LocalPlayer

if LocalPlayer.Character then

    killAC(LocalPlayer.Character)

end

getgenv()._acKillConn = LocalPlayer.CharacterAdded:Connect(function(c)

    task.wait(1)

    killAC(c)

end)


-- ============================================================
-- Lupin Generator + Monster Evasion System (PRO NOCLIP)
-- ============================================================

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players:GetPlayers()[1]

-- =========================
-- CONFIG
-- =========================
local THREAT_DISTANCE = 45
local CHECK_MONSTER_INTERVAL = 0.3
local TP_COOLDOWN = 1
local FIRE_COOLDOWN = 0.3
local BUSY_TIMEOUT = 15
local NOCLIP_CHECK_INTERVAL = 0.1
local NOCLIP_SPEED = 25

-- =========================
-- STATE
-- =========================
local isBusy = false
local currentTarget = nil
local lastTpTime = 0
local lastFireTime = 0
local busyStartTime = 0
local lastMonsterCheck = 0
local isEvading = false
local noclipActive = false
local noclipParts = {}

-- =========================
-- HELPERS
-- =========================
local function getCharacter()
    local char = player and player.Character
    if not char then return end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    return char, humanoid, root
end

local function getGeneratorPosition(generator)
    if generator.PrimaryPart then
        return generator.PrimaryPart.Position
    end
    return generator:GetPivot().Position
end

-- =========================
-- MONSTER DETECTION
-- =========================
local function getMyModel()
    local char, _, root = getCharacter()
    if char and char.Parent then
        return char
    end

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

local function distance(a, b)
    if not a or not b then
        return math.huge
    end
    return (a - b).Magnitude
end

-- 🔴 เช็คว่ามอนกำลังเล็งเราไหม
local function isMonsterChasingMe()
    local myModel = getMyModel()
    if not myModel then
        return false, nil
    end

    local currentRoom = workspace:FindFirstChild("CurrentRoom")
    if not currentRoom then
        return false, nil
    end

    for _, map in pairs(currentRoom:GetChildren()) do
        if map:IsA("Model") or map:IsA("Folder") then
            local monstersFolder = map:FindFirstChild("Monsters")
            if monstersFolder then
                for _, monster in pairs(monstersFolder:GetChildren()) do
                    if monster:IsA("Model") then
                        local chasingValue = monster:FindFirstChild("ChasingValue")
                        if chasingValue and chasingValue:IsA("ObjectValue") then
                            if chasingValue.Value == myModel then
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
    end

    return false, nil, nil
end

-- =========================
-- PRO NOCLIP SYSTEM
-- =========================
local function enableProNoclip()
    if noclipActive then return end
    noclipActive = true

    local char, _, root = getCharacter()
    if not char or not root then return end

    print("🚀 PRO NOCLIP เปิด")

    -- ปิด CanCollide ทั้งตัว
    noclipParts = {}
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            noclipParts[part] = part.CanCollide
            part.CanCollide = false
        end
    end

    -- ใส่ BodyVelocity ให้ root
    if not root:FindFirstChild("NoclipVelocity") then
        local bodyVel = Instance.new("BodyVelocity")
        bodyVel.Name = "NoclipVelocity"
        bodyVel.Velocity = Vector3.zero
        bodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bodyVel.Parent = root
    end
end

local function disableProNoclip()
    if not noclipActive then return end
    noclipActive = false

    print("✅ PRO NOCLIP ปิด")

    local char, _, root = getCharacter()

    -- ลบ BodyVelocity
    if root then
        local bodyVel = root:FindFirstChild("NoclipVelocity")
        if bodyVel then bodyVel:Destroy() end
    end

    -- คืนค่า CanCollide
    for part, canCollide in pairs(noclipParts) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
    noclipParts = {}
end

-- หนีเข้าไปในกำแพง (Pro Version)
local function escapeIntoWallPro()
    local char, humanoid, root = getCharacter()
    if not char or not root or not humanoid then
        return
    end

    local _, monster, dist = isMonsterChasingMe()
    if not monster then
        return
    end

    print("⚠️ มอนไล่มา! ระยะ:", dist, "-> หนีเข้าไปในกำแพง")

    enableProNoclip()

    local myPos = root.Position
    local monRoot = monster:FindFirstChild("HumanoidRootPart")

    local escapeDir = Vector3.new(0, 0, 1)
    if monRoot then
        escapeDir = (myPos - monRoot.Position).Unit
    end

    local safeTime = 0
    local safeThreshold = 2

    while noclipActive do
        task.wait(NOCLIP_CHECK_INTERVAL)

        local isChasingNow, _, distNow = isMonsterChasingMe()

        if not isChasingNow or distNow > THREAT_DISTANCE then
            safeTime = safeTime + NOCLIP_CHECK_INTERVAL
        else
            safeTime = 0
        end

        if safeTime >= safeThreshold then
            print("✅ ปลอดภัย " .. safeThreshold .. "วิแล้ว -> ออกจากกำแพง")
            disableProNoclip()
            return
        end

        if root then
            local bodyVel = root:FindFirstChild("NoclipVelocity")
            if bodyVel then
                bodyVel.Velocity = escapeDir * NOCLIP_SPEED
            end
        end
    end
end

-- =========================
-- STOP INTERACTING
-- =========================
local function stopInteracting(generator)
    if not generator or not generator.Parent then
        return
    end

    local stats = generator:FindFirstChild("Stats")
    if not stats then
        return
    end

    local stopEvent = stats:FindFirstChild("StopInteracting")
    if stopEvent and stopEvent:IsA("RemoteEvent") then
        print("🛑 ส่ง StopInteracting ->", generator.Name)
        pcall(function()
            stopEvent:FireServer("Stop")
        end)
    end
end

-- =========================
-- GENERATOR FUNCTIONS
-- =========================
local function getClosestGenerator()
    local _, _, root = getCharacter()
    local room = workspace:FindFirstChild("CurrentRoom")

    if not root or not room then
        return nil
    end

    local closest
    local minDist = math.huge

    for _, model in ipairs(room:GetChildren()) do
        if model:IsA("Model") or model:IsA("Folder") then
            local folder = model:FindFirstChild("Generators")
            if folder then
                for _, generator in ipairs(folder:GetChildren()) do
                    if generator:IsA("Model") then
                        local stats = generator:FindFirstChild("Stats")
                        local completed = stats and stats:FindFirstChild("Completed")
                        if completed and completed:IsA("BoolValue") and not completed.Value then
                            local d = (root.Position - getGeneratorPosition(generator)).Magnitude
                            if d < minDist then
                                minDist = d
                                closest = generator
                            end
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
    if not room then
        return false
    end

    local foundAny = false
    for _, model in ipairs(room:GetChildren()) do
        if model:IsA("Model") or model:IsA("Folder") then
            local folder = model:FindFirstChild("Generators")
            if folder then
                for _, generator in ipairs(folder:GetChildren()) do
                    if generator:IsA("Model") then
                        local stats = generator:FindFirstChild("Stats")
                        local completed = stats and stats:FindFirstChild("Completed")
                        if completed and completed:IsA("BoolValue") then
                            foundAny = true
                            if not completed.Value then
                                return false
                            end
                        end
                    end
                end
            end
        end
    end
    return foundAny
end

local function isGeneratorCompleted(generator)
    if not generator or not generator.Parent then
        return true
    end
    local stats = generator:FindFirstChild("Stats")
    local completed = stats and stats:FindFirstChild("Completed")
    if completed and completed:IsA("BoolValue") then
        return completed.Value
    end
    return false
end

-- =========================
-- PATHFINDING + MOVEMENT
-- =========================
local function teleportInFront(target, distance)
    local _, humanoid, root = getCharacter()
    if not humanoid or not root then
        return false
    end

    if tick() - lastTpTime < TP_COOLDOWN then
        return false
    end
    lastTpTime = tick()

    distance = distance or 5

    local ok, pivot = pcall(function()
        return target:GetPivot()
    end)

    if not ok or not pivot then
        return false
    end

    local dir = (pivot.Position - root.Position)
    if dir.Magnitude > 0 then
        dir = dir.Unit
    else
        dir = pivot.LookVector
    end

    local tpPos = pivot.Position - dir * distance + Vector3.new(0, 3, 0)
    root.CFrame = CFrame.new(tpPos)
    task.wait(0.2)
    return true
end

local function moveToTarget(target, label)
    local _, humanoid, root = getCharacter()
    if not humanoid or not root then
        return "fail"
    end

    -- 🔴 เช็คมอนก่อนเดิน
    local isChasingNow = isMonsterChasingMe()
    if isChasingNow then
        print("⚠️ มอนมาแล้ว! ปล่อย + หนี")
        stopInteracting(currentTarget)
        isEvading = true
        escapeIntoWallPro()
        isEvading = false
        return "threat"
    end

    local targetPos
    if typeof(target) == "Vector3" then
        targetPos = target
    else
        targetPos = getGeneratorPosition(target)
    end

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentJumpHeight = 5,
        AgentMaxSlope = 80,
        WaypointSpacing = 8,
    })

    local pathOk = pcall(function()
        path:ComputeAsync(root.Position, targetPos)
    end)

    if not pathOk or path.Status ~= Enum.PathStatus.Success then
        return "fail"
    end

    local waypoints = path:GetWaypoints()

    for i = 2, #waypoints do
        -- 🔴 เช็คมอนขณะเดิน
        local isChasingNow2 = isMonsterChasingMe()
        if isChasingNow2 then
            print("⚠️ มอนตามมากลางทาง! ปล่อย + หนี")
            stopInteracting(currentTarget)
            isEvading = true
            escapeIntoWallPro()
            isEvading = false
            return "threat"
        end

        -- เช็คเป้าเปลี่ยน
        if typeof(target) ~= "Vector3" and isGeneratorCompleted(target) then
            return "changed"
        end

        -- เช็คระยะ
        if typeof(target) ~= "Vector3" then
            local distToTarget = (root.Position - targetPos).Magnitude
            if distToTarget <= 10 then
                teleportInFront(target, 5)
                return "reached"
            end
        end

        local wp = waypoints[i]
        if wp.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end

        humanoid:MoveTo(wp.Position)

        local reached = false
        local conn
        conn = humanoid.MoveToFinished:Connect(function(ok)
            reached = ok
        end)

        local elapsed = 0
        while not reached and elapsed < 3 do
            task.wait(0.1)
            elapsed += 0.1

            -- 🔴 เช็คมอนกลางเดิน
            local isChasingNow3 = isMonsterChasingMe()
            if isChasingNow3 then
                conn:Disconnect()
                humanoid:MoveTo(root.Position)
                print("⚠️ มอนตามมา -> หยุด + หนี")
                stopInteracting(currentTarget)
                isEvading = true
                escapeIntoWallPro()
                isEvading = false
                return "threat"
            end

            if typeof(target) ~= "Vector3" and isGeneratorCompleted(target) then
                conn:Disconnect()
                humanoid:MoveTo(root.Position)
                return "changed"
            end

            if typeof(target) ~= "Vector3" then
                local d = (root.Position - targetPos).Magnitude
                if d <= 10 then
                    conn:Disconnect()
                    teleportInFront(target, 5)
                    return "reached"
                end
            end
        end
        conn:Disconnect()
    end

    return "reached"
end

-- =========================
-- PROMPT FIRING
-- =========================
local function getAttachmentAndPrompt(generator)
    for _, obj in ipairs(generator:GetDescendants()) do
        if obj:IsA("Attachment") then
            local p = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
            if p then
                return obj, p
            end
        end
    end
    return nil, nil
end

local function fireGeneratorPrompt(generator)
    if tick() - lastFireTime < FIRE_COOLDOWN then
        return false
    end
    lastFireTime = tick()

    local attachment, prompt = getAttachmentAndPrompt(generator)

    if not prompt then
        return false
    end

    -- 🔴 เช็คมอนก่อน fire
    local isChasingNow = isMonsterChasingMe()
    if isChasingNow then
        print("⚠️ มอนมา -> หยุด fire + หนี")
        isEvading = true
        escapeIntoWallPro()
        isEvading = false
        return false
    end

    local promptPos = attachment and attachment.WorldPosition
        or getGeneratorPosition(generator)

    local _, _, root = getCharacter()
    if root then
        local dist = (root.Position - promptPos).Magnitude
        local maxDist = prompt.MaxActivationDistance or 10
        if dist > maxDist then
            return false
        end
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

    -- กัน isBusy ค้าง
    if isBusy and (tick() - busyStartTime) > BUSY_TIMEOUT then
        warn("⚠️ isBusy timeout -> reset")
        isBusy = false
        currentTarget = nil
    end

    if isBusy or isEvading then
        continue
    end

    -- 1) Generator ครบ → Elevator
    if allGeneratorsCompleted() then
        print("🎉 Generator ครบ -> Elevator")

        local elevator = getElevator()
        if elevator then
            isBusy = true
            busyStartTime = tick()
            currentTarget = elevator

            moveToTarget(elevator, "Elevator")
            print("✅ ถึง Elevator")

            isBusy = false
            currentTarget = nil
        end

        task.wait(2)
        continue
    end

    -- 2) หา Generator เป้า
    local generator = getClosestGenerator()
    if not generator then
        task.wait(1)
        continue
    end

    if currentTarget == generator and isBusy then
        continue
    end

    print("🎯 เป้า:", generator.Name)

    isBusy = true
    busyStartTime = tick()
    currentTarget = generator

    local result = moveToTarget(generator, generator.Name)

    if result == "threat" then
        print("🔁 เหตุขัดขวาง -> หาเป้าใหม่")
        isBusy = false
        currentTarget = nil
        task.wait(0.5)
        continue
    end

    if result == "changed" then
        print("🔁 เป้าเปลี่ยน")
        isBusy = false
        currentTarget = nil
        task.wait(0.1)
        continue
    end

    if result == "fail" then
        isBusy = false
        currentTarget = nil
        task.wait(0.5)
        continue
    end

    -- 3) Fire prompt จนกว่า Completed = true
    local stats = generator:FindFirstChild("Stats")
    local completed = stats and stats:FindFirstChild("Completed")

    if completed and completed:IsA("BoolValue") then
        print("⏳ Fire prompt ->", generator.Name)

        while generator.Parent and not completed.Value do
            -- 🔴 เช็คมอนก่อน fire
            local isChasingNow = isMonsterChasingMe()
            if isChasingNow then
                print("⚠️ มอนมา -> หยุด fire + หนี")
                stopInteracting(generator)
                isEvading = true
                escapeIntoWallPro()
                isEvading = false
                break
            end

            local ok = fireGeneratorPrompt(generator)
            task.wait(0.2)

            if completed.Value then
                print("✅", generator.Name, "done!")
                break
            end

            if not ok then
                warn("fire ไม่สำเร็จ")
                moveToTarget(generator, generator.Name)
            end

            task.wait(0.3)
        end
    end

    isBusy = false
    currentTarget = nil
end
