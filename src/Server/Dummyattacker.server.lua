--!strict
-- ============================================================
--  DummyAttacker | AbyssalBlood
--  Script de TEST uniquement - R6
-- ============================================================

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services        = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local SurvivalService = require(Services:WaitForChild("SurvivalService"))

while not _G.GameServer do task.wait(0.1) end
local GameServer = _G.GameServer

local rig         = workspace:WaitForChild("Rig")
local rigHumanoid = rig:WaitForChild("Humanoid") :: Humanoid
local rigRoot     = rig:WaitForChild("HumanoidRootPart") :: BasePart

rigHumanoid.BreakJointsOnDeath = false

-- R6 : valeurs normales
local R6_WALK_SPEED = 16
local R6_JUMP_POWER = 50

print("[DummyAttacker] Rig prêt !")

local ATTACK_RANGE    = 5
local ATTACK_DAMAGE   = 5
local ATTACK_INTERVAL = 2
local PARRY_WINDOW    = 0.25
local lastAttack      = 0
local dt              = 0.5

local isDowned    = false
local isDead      = false
local reviveTimer = 0
local REVIVE_TIME = 20
local REVIVE_HP   = 40

GameServer.RegisterNPC(rig, {
    onExecute = function()
        print("[DummyAttacker] Dummy achevé par un joueur !")
        isDead   = true
        isDowned = false
        rigHumanoid.BreakJointsOnDeath = true
        rigHumanoid.Health = 0
    end,
    onCarry = function(carrier: Player)
        print("[DummyAttacker] " .. carrier.Name .. " porte le Dummy !")
        local carrierChar = carrier.Character
        if not carrierChar then return end
        local carrierRoot = carrierChar:FindFirstChild("HumanoidRootPart") :: BasePart
        if not carrierRoot then return end

        rigHumanoid.PlatformStand = true
        rigHumanoid.WalkSpeed = 0
        rigHumanoid.JumpPower = 0

        for _, part in ipairs(rig:GetDescendants()) do
            if part:IsA("BasePart") and part ~= rigRoot then
                part.Massless = true
            end
        end

        local old = carrierRoot:FindFirstChild("DummyCarryWeld")
        if old then old:Destroy() end

        local weld = Instance.new("WeldConstraint")
        weld.Name   = "DummyCarryWeld"
        weld.Part0  = carrierRoot
        weld.Part1  = rigRoot
        weld.Parent = carrierRoot

        -- R6 : position sur l'épaule ajustée pour R6
        rigRoot.CFrame = carrierRoot.CFrame * CFrame.new(0.8, 1.2, -0.3) * CFrame.Angles(0, math.pi, 0)
    end,
    onCarryCancel = function()
        print("[DummyAttacker] Portage annulé — Dummy lâché !")
        for _, p in ipairs(Players:GetPlayers()) do
            local char = p.Character
            if not char then continue end
            local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
            if root then
                local weld = root:FindFirstChild("DummyCarryWeld")
                if weld then weld:Destroy() end
            end
        end
        rigHumanoid.PlatformStand = false
        rigHumanoid.WalkSpeed = R6_WALK_SPEED
        rigHumanoid.JumpPower = R6_JUMP_POWER
    end,
})

local Remotes            = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local NotifyHit          = Remotes:WaitForChild("NotifyHit")
local NotifyParrySuccess = Remotes:WaitForChild("NotifyParrySuccess")
local RequestBlock       = Remotes:WaitForChild("RequestBlock")

local playerBlockState: { [Player]: { isBlocking: boolean, isParrying: boolean, parryTimer: number } } = {}

RequestBlock.OnServerEvent:Connect(function(player: Player, isBlocking: boolean)
    if not playerBlockState[player] then
        playerBlockState[player] = { isBlocking = false, isParrying = false, parryTimer = 0 }
    end
    playerBlockState[player].isBlocking = isBlocking
    if isBlocking then
        playerBlockState[player].isParrying = true
        playerBlockState[player].parryTimer = PARRY_WINDOW
    else
        playerBlockState[player].isParrying = false
    end
end)

Players.PlayerAdded:Connect(function(player)
    playerBlockState[player] = { isBlocking = false, isParrying = false, parryTimer = 0 }
end)
Players.PlayerRemoving:Connect(function(player)
    playerBlockState[player] = nil
end)

local function getNearestPlayer(): (Player?, BasePart?)
    local nearest: Player?       = nil
    local nearestPart: BasePart? = nil
    local nearestDist            = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if SurvivalService.IsDowned(player) then continue end
        local character = player.Character
        if not character then continue end
        local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
        if not root then continue end
        local dist = (rigRoot.Position - root.Position).Magnitude
        if dist < nearestDist then
            nearestDist = dist
            nearest     = player
            nearestPart = root
        end
    end
    return nearest, nearestPart
end

local function attackPlayer(player: Player)
    local blockState = playerBlockState[player]

    if blockState and blockState.isParrying then
        print("[DummyAttacker] PERFECT BLOCK ! Contre-attaque sur le Rig !")
        NotifyParrySuccess:FireClient(player, { attackerName = "Dummy" })
        rigHumanoid.Health -= 40
        return
    end

    if blockState and blockState.isBlocking then
        local reducedDamage = math.floor(ATTACK_DAMAGE * 0.25)
        print(string.format("[DummyAttacker] %s bloque ! Degats reduits : %d", player.Name, reducedDamage))
        SurvivalService.TakeDamage(player, reducedDamage)
        SurvivalService.TakeBlood(player, true)
        NotifyHit:FireClient(player, { damage = reducedDamage, attackType = "light", guardBreak = false })
        return
    end

    print(string.format("[DummyAttacker] Coup normal sur %s ! (%d degats)", player.Name, ATTACK_DAMAGE))
    SurvivalService.TakeDamage(player, ATTACK_DAMAGE)
    SurvivalService.TakeBlood(player, false)
    NotifyHit:FireClient(player, { damage = ATTACK_DAMAGE, attackType = "light", guardBreak = false })
end

while true do
    task.wait(dt)

    if isDead then
        print("[DummyAttacker] Dummy définitivement mort.")
        GameServer.UnregisterNPC(rig)
        break
    end

    if isDowned then
        reviveTimer -= dt
        if reviveTimer <= 0 then
            isDowned = false
            GameServer.SetNPCDowned(rig, false)
            rigHumanoid.BreakJointsOnDeath = false
            rigHumanoid.Health    = REVIVE_HP
            rigHumanoid.WalkSpeed = R6_WALK_SPEED
            rigHumanoid.JumpPower = R6_JUMP_POWER
            print("[DummyAttacker] Dummy se relève ! (" .. REVIVE_HP .. " HP)")
        end
        continue
    end

    if rigHumanoid.Health <= 1 and not isDowned and not isDead then
        isDowned      = true
        reviveTimer   = REVIVE_TIME
        GameServer.SetNPCDowned(rig, true)
        rigHumanoid.BreakJointsOnDeath = false
        rigHumanoid.Health    = 1
        rigHumanoid.WalkSpeed = 0
        rigHumanoid.JumpPower = 0
        rigHumanoid:ChangeState(Enum.HumanoidStateType.Dead)
        print("[DummyAttacker] Dummy est DOWN ! Appuie V pour porter ou B pour achever !")
        continue
    end

    for player, state in pairs(playerBlockState) do
        if state.isParrying then
            state.parryTimer -= dt
            if state.parryTimer <= 0 then
                state.isParrying = false
            end
        end
    end

    local player, playerRoot = getNearestPlayer()
    if not player or not playerRoot then continue end
    if SurvivalService.IsDowned(player) then continue end

    local dist = (rigRoot.Position - playerRoot.Position).Magnitude

    rigRoot.CFrame = CFrame.lookAt(rigRoot.Position, Vector3.new(
        playerRoot.Position.X,
        rigRoot.Position.Y,
        playerRoot.Position.Z
    ))

    if dist <= ATTACK_RANGE then
        local now = tick()
        if now - lastAttack >= ATTACK_INTERVAL then
            lastAttack = now
            attackPlayer(player)
        end
    else
        rigHumanoid:MoveTo(playerRoot.Position)
    end
end