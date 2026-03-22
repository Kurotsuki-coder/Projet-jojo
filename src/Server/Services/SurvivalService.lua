--!strict
-- ============================================================
--  SurvivalService | AbyssalBlood
--  Version : 3.1.0 (R6)
--  Downed State complet :
--    - 20 sec pour se relever (7% HP)
--    - Si tapé → timer reset
--    - Si sang à 0 → mort en 2 sec
--    - V = Porter | B = Achever
-- ============================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes          = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local UpdateSurvivalUI = Remotes:WaitForChild("UpdateSurvivalUI")

-- R6 : WalkSpeed normal = 16, JumpPower = 50
local R6_WALK_SPEED = 16
local R6_JUMP_POWER = 50

local CONFIG = {
    MAX_HUNGER  = 100,
    MAX_THIRST  = 100,
    MAX_BLOOD   = 100,

    HUNGER_DRAIN_RATE = 0.5 / 60,
    THIRST_DRAIN_RATE = 0.8 / 60,
    BLOOD_DRAIN_RATE  = 0,

    GRACE_PERIOD   = 120,
    HP_DAMAGE_RATE = 2,
    TICK_RATE      = 1,

    BLOOD_LOSS_HIT   = 8,
    BLOOD_LOSS_BLOCK = 3,

    DOWNED_REVIVE_TIME  = 20,
    DOWNED_REVIVE_HP    = 7,
    DOWNED_BLEED_RATE   = 5,
    DOWNED_DEATH_DELAY  = 2,
}

local playerData: { [Player]: any } = {}

local function clamp(v: number, min: number, max: number): number
    return math.max(min, math.min(max, v))
end

local function syncClient(player: Player)
    local data = playerData[player]
    if not data then return end
    UpdateSurvivalUI:FireClient(player, {
        hunger      = data.hunger,
        thirst      = data.thirst,
        blood       = data.blood,
        hp          = data.hp,
        isDowned    = data.isDowned,
        reviveTimer = data.reviveTimer,
    })
end

-- ============================================================
--  INITIALISATION
-- ============================================================
local function initPlayer(player: Player)
    playerData[player] = {
        hunger          = CONFIG.MAX_HUNGER,
        thirst          = CONFIG.MAX_THIRST,
        blood           = CONFIG.MAX_BLOOD,
        hp              = 100,
        graceTimers     = { hunger = 0, thirst = 0, blood = 0 },
        isDowned        = false,
        isDead          = false,
        reviveTimer     = 0,
        deathDelayTimer = nil,
        carriedBy       = nil,
    }
    print("[SurvivalService] Joueur initialisé :", player.Name)
    syncClient(player)
end

-- ============================================================
--  MORT
-- ============================================================
local function killPlayer(player: Player)
    local data = playerData[player]
    if not data or data.isDead then return end

    data.isDead   = true
    data.isDowned = false

    print("[SurvivalService] MORT DÉFINITIVE :", player.Name)

    -- Vérifier que le joueur est encore connecté
    if not player:IsDescendantOf(game) then return end

    player:LoadCharacter()
    initPlayer(player)
end

local function downPlayer(player: Player)
    local data = playerData[player]
    if data.isDowned or data.isDead then return end

    data.isDowned    = true
    data.hp          = 0
    data.reviveTimer = CONFIG.DOWNED_REVIVE_TIME

    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.BreakJointsOnDeath = false
            humanoid.Health    = 1
            -- R6 : désactiver le mouvement
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end
    end

    print("[SurvivalService] DOWNED :", player.Name)
    syncClient(player)
end

-- ============================================================
--  BOUCLE PRINCIPALE
-- ============================================================
local tickAccumulator = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
    tickAccumulator += deltaTime
    if tickAccumulator < CONFIG.TICK_RATE then return end
    tickAccumulator = 0

    for player, data in pairs(playerData) do
        if data.isDead then continue end

        data.hunger = clamp(data.hunger - CONFIG.HUNGER_DRAIN_RATE * CONFIG.TICK_RATE, 0, CONFIG.MAX_HUNGER)
        data.thirst = clamp(data.thirst - CONFIG.THIRST_DRAIN_RATE * CONFIG.TICK_RATE, 0, CONFIG.MAX_THIRST)
        data.blood  = clamp(data.blood  - CONFIG.BLOOD_DRAIN_RATE  * CONFIG.TICK_RATE, 0, CONFIG.MAX_BLOOD)

        local takingDamage = false
        if data.hunger <= 0 then
            data.graceTimers.hunger += CONFIG.TICK_RATE
            if data.graceTimers.hunger >= CONFIG.GRACE_PERIOD then takingDamage = true end
        else data.graceTimers.hunger = 0 end

        if data.thirst <= 0 then
            data.graceTimers.thirst += CONFIG.TICK_RATE
            if data.graceTimers.thirst >= CONFIG.GRACE_PERIOD then takingDamage = true end
        else data.graceTimers.thirst = 0 end

        if data.blood <= 0 then
            data.graceTimers.blood += CONFIG.TICK_RATE
            if data.graceTimers.blood >= CONFIG.GRACE_PERIOD then takingDamage = true end
        else data.graceTimers.blood = 0 end

        if takingDamage and not data.isDowned then
            data.hp = clamp(data.hp - CONFIG.HP_DAMAGE_RATE, 0, 100)
            if data.hp <= 0 then downPlayer(player) end
        end

        if data.isDowned then
            data.reviveTimer -= CONFIG.TICK_RATE

            if data.blood <= 0 then
                if not data.deathDelayTimer then
                    data.deathDelayTimer = CONFIG.DOWNED_DEATH_DELAY
                    print("[SurvivalService] " .. player.Name .. " saigne à mort !")
                else
                    data.deathDelayTimer -= CONFIG.TICK_RATE
                    if data.deathDelayTimer <= 0 then
                        killPlayer(player)
                        continue
                    end
                end
            else
                data.deathDelayTimer = nil
            end

            if data.reviveTimer <= 0 then
                data.isDowned    = false
                data.reviveTimer = 0
                data.hp          = CONFIG.DOWNED_REVIVE_HP

                local character = player.Character
                if character then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        -- R6 : restaurer le mouvement
                        humanoid.WalkSpeed = R6_WALK_SPEED
                        humanoid.JumpPower = R6_JUMP_POWER
                        humanoid.Health    = CONFIG.DOWNED_REVIVE_HP
                    end
                end
                print("[SurvivalService] " .. player.Name .. " s'est relevé (7% HP)")
            end
        end

        syncClient(player)
    end
end)

-- ============================================================
--  API PUBLIQUE
-- ============================================================
local SurvivalService = {}

function SurvivalService.TakeDamage(player: Player, amount: number)
    local data = playerData[player]
    if not data or data.isDead then return end

    data.hp = clamp(data.hp - amount, 0, 100)
    if data.hp <= 0 and not data.isDowned then
        downPlayer(player)
    end
    syncClient(player)
end

function SurvivalService.TakeBlood(player: Player, isBlocking: boolean)
    local data = playerData[player]
    if not data or data.isDead then return end

    local loss = isBlocking and CONFIG.BLOOD_LOSS_BLOCK or CONFIG.BLOOD_LOSS_HIT
    data.blood = clamp(data.blood - loss, 0, CONFIG.MAX_BLOOD)
    syncClient(player)
end

function SurvivalService.HitDowned(player: Player)
    local data = playerData[player]
    if not data or not data.isDowned or data.isDead then return end

    data.reviveTimer = CONFIG.DOWNED_REVIVE_TIME
    print("[SurvivalService] " .. player.Name .. " tapé au sol → timer reset !")

    data.blood = clamp(data.blood - CONFIG.DOWNED_BLEED_RATE, 0, CONFIG.MAX_BLOOD)
    print(string.format("[SurvivalService] Sang de %s : %.0f", player.Name, data.blood))

    syncClient(player)
end

function SurvivalService.CarryPlayer(carrier: Player, target: Player)
    local targetData = playerData[target]
    if not targetData or not targetData.isDowned then return end

    targetData.carriedBy = carrier
    print(string.format("[SurvivalService] %s porte %s", carrier.Name, target.Name))

    local carrierChar = carrier.Character
    local targetChar  = target.Character
    if not carrierChar or not targetChar then return end

    local carrierRoot = carrierChar:FindFirstChild("HumanoidRootPart") :: BasePart
    local targetRoot  = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart
    if not carrierRoot or not targetRoot then return end

    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
    if targetHumanoid then
        targetHumanoid.PlatformStand = true
    end

    local weld = Instance.new("WeldConstraint")
    weld.Name  = "CarryWeld"
    weld.Part0 = carrierRoot
    weld.Part1 = targetRoot
    weld.Parent = carrierRoot

    -- R6 : position sur l'épaule ajustée
    targetRoot.CFrame = carrierRoot.CFrame * CFrame.new(0.8, 0.5, -0.5)

    syncClient(target)
end

function SurvivalService.CancelCarry(target: Player)
    local targetData = playerData[target]
    if not targetData then return end

    targetData.carriedBy = nil

    local targetChar = target.Character
    if not targetChar then return end

    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart
    if targetRoot then
        for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
            local char = p.Character
            if not char then continue end
            local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
            if root then
                local w = root:FindFirstChild("CarryWeld")
                if w then w:Destroy() end
            end
        end
    end

    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
    if targetHumanoid then
        targetHumanoid.PlatformStand = false
    end

    print("[SurvivalService] Portage annulé")
    syncClient(target)
end

function SurvivalService.Execute(target: Player)
    local data = playerData[target]
    if not data then return end
    print("[SurvivalService] EXÉCUTION de :", target.Name)
    killPlayer(target)
end

function SurvivalService.IsDowned(player: Player): boolean
    local data = playerData[player]
    return data and data.isDowned or false
end

function SurvivalService.Consume(player: Player, itemType: string, amount: number)
    local data = playerData[player]
    if not data then return end

    if itemType == "food" then
        data.hunger = clamp(data.hunger + amount, 0, CONFIG.MAX_HUNGER)
    elseif itemType == "water" then
        data.thirst = clamp(data.thirst + amount, 0, CONFIG.MAX_THIRST)
    elseif itemType == "blood" then
        data.blood  = clamp(data.blood  + amount, 0, CONFIG.MAX_BLOOD)
    elseif itemType == "heal" then
        data.hp = clamp(data.hp + amount, 0, 100)
        if data.isDowned and data.hp >= 1 then
            data.isDowned    = false
            data.reviveTimer = 0
            data.carriedBy   = nil
            local character = player.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    -- R6 : restaurer le mouvement
                    humanoid.WalkSpeed = R6_WALK_SPEED
                    humanoid.JumpPower = R6_JUMP_POWER
                end
            end
        end
    end

    syncClient(player)
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
    playerData[player] = nil
end)

return SurvivalService