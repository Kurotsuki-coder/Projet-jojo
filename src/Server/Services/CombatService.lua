--!strict
-- ============================================================
--  CombatService | AbyssalBlood
--  Gère : Combat Tag, Posture, Perfect Block, Hitbox Raycast
--  LOGIQUE POSTURE (style Deepwoken) :
--    - Posture commence à 0
--    - Bloquer (F maintenu) sans perfect block → posture MONTE
--    - Posture pleine (100) → Guard Break → étourdi
--    - Perfect Block (F au bon timing) → posture NE MONTE PAS + contre
--    - Hors combat → posture redescend à 0 progressivement
--  Auteur  : Membre A
--  Version : 4.0.0
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local SurvivalService   = require(script.Parent.SurvivalService)

local Remotes              = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local RequestAttack        = Remotes:WaitForChild("RequestAttack")
local RequestBlock         = Remotes:WaitForChild("RequestBlock")
local NotifyHit            = Remotes:WaitForChild("NotifyHit")
local NotifyParrySuccess   = Remotes:WaitForChild("NotifyParrySuccess")

-- ============================================================
--  CONFIGURATION
-- ============================================================
local CONFIG = {
    COMBAT_TAG_DURATION     = 120,
    MAX_POSTURE             = 100,
    POSTURE_DRAIN_RATE      = 12,
    POSTURE_FILL_ON_BLOCK   = 22,
    POSTURE_BREAK_STUN      = 3,
    PARRY_WINDOW            = 0.25,
    PARRY_COUNTER_DAMAGE    = 15,
    LIGHT_ATTACK_DAMAGE     = 12,
    HEAVY_ATTACK_DAMAGE     = 28,
    ATTACK_COOLDOWN         = 0.4,
    HITBOX_RANGE            = 4.5,
}

local combatData: { [Player]: any } = {}

-- ============================================================
--  UTILITAIRES
-- ============================================================
local function clamp(v: number, min: number, max: number): number
    return math.max(min, math.min(max, v))
end

local function setCombatTag(player: Player)
    local data = combatData[player]
    if not data then return end
    local wasInCombat = data.inCombat
    data.inCombat    = true
    data.combatTimer = CONFIG.COMBAT_TAG_DURATION
    if not wasInCombat then
        print("[Combat] " .. player.Name .. " est entré en combat !")
    end
end

-- ============================================================
--  HITBOX RAYCAST
-- ============================================================
local function performHitbox(attacker: Player): { any }
    local character = attacker.Character
    if not character then return {} end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
    if not rootPart then return {} end

    local hits = {}
    local hitParams = RaycastParams.new()
    hitParams.FilterDescendantsInstances = { character }
    hitParams.FilterType = Enum.RaycastFilterType.Exclude

    -- Rayons horizontaux en éventail
    local rayAngles = { -20, -10, 0, 10, 20 }
    -- Hauteurs multiples pour détecter même si le joueur est accroupi ou grand
    local rayHeights = { 0, 1.5, -1 }

    for _, angle in ipairs(rayAngles) do
        for _, heightOffset in ipairs(rayHeights) do
            local origin = rootPart.Position + Vector3.new(0, heightOffset, 0)
            local dir    = CFrame.Angles(0, math.rad(angle), 0) * rootPart.CFrame.LookVector
            local result = workspace:Raycast(origin, dir * CONFIG.HITBOX_RANGE, hitParams)

            if result and result.Instance then
                local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
                if hitModel then
                    local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
                    if humanoid and hitModel ~= character then
                        local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
                        local target = hitPlayer or hitModel
                        local alreadyHit = false
                        for _, h in ipairs(hits) do
                            if h == target then alreadyHit = true break end
                        end
                        if not alreadyHit then table.insert(hits, target) end
                    end
                end
            end
        end
    end

    print("[DEBUG SERVEUR] Attaque reçue - hits détectés : " .. #hits)
    return hits
end

-- ============================================================
--  LOGIQUE D'ATTAQUE
-- ============================================================
local function processAttack(attacker: Player, attackType: string)
    local data = combatData[attacker]
    if not data then return end

    local now = tick()
    if now - data.lastAttackTime < CONFIG.ATTACK_COOLDOWN then return end
    if data.isStunned then return end

    data.lastAttackTime = now
    setCombatTag(attacker)

    local damage = attackType == "heavy"
        and CONFIG.HEAVY_ATTACK_DAMAGE
        or  CONFIG.LIGHT_ATTACK_DAMAGE

    local hits = performHitbox(attacker)

    for _, target in ipairs(hits) do
        local targetPlayer   = if typeof(target) == "Instance" and target:IsA("Player") then target else nil
        local targetModel    = if targetPlayer then targetPlayer.Character else target :: Model
        local targetHumanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")

        if not targetHumanoid then continue end

        local targetData = targetPlayer and combatData[targetPlayer]
        if targetPlayer then setCombatTag(targetPlayer) end

        -- ------------------------------------------------
        --  CAS 1 : PERFECT BLOCK
        --  → Pas de perte de sang, contre-attaque sur l'attaquant
        -- ------------------------------------------------
        if targetData and targetData.isParrying then
            print(string.format("[Combat] PERFECT BLOCK ! %s pare %s", targetPlayer.Name, attacker.Name))
            SurvivalService.TakeDamage(attacker, CONFIG.PARRY_COUNTER_DAMAGE)
            -- PAS de TakeBlood ici → perfect block = aucune perte de sang
            NotifyParrySuccess:FireClient(targetPlayer, { attackerName = attacker.Name })
            NotifyParrySuccess:FireClient(attacker, { parried = true })

        -- ------------------------------------------------
        --  CAS 2 : BLOCK NORMAL
        --  → Posture monte + petite perte de sang
        -- ------------------------------------------------
        elseif targetData and targetData.isBlocking then
            print(string.format("[Combat] Block normal de %s", targetPlayer.Name))
            targetData.posture = clamp(targetData.posture + CONFIG.POSTURE_FILL_ON_BLOCK, 0, CONFIG.MAX_POSTURE)
            SurvivalService.TakeDamage(targetPlayer, damage * 0.25)
            SurvivalService.TakeBlood(targetPlayer, true)  -- Perte de sang réduite (3 pts)

            if targetData.posture >= CONFIG.MAX_POSTURE then
                targetData.isStunned  = true
                targetData.stunTimer  = CONFIG.POSTURE_BREAK_STUN
                targetData.isBlocking = false
                targetData.posture    = CONFIG.MAX_POSTURE
                print(string.format("[Combat] GUARD BREAK sur %s !", targetPlayer.Name))
                NotifyHit:FireClient(targetPlayer, { damage = damage, attackType = attackType, guardBreak = true })
            else
                NotifyHit:FireClient(targetPlayer, { damage = math.floor(damage * 0.25), attackType = attackType, guardBreak = false })
            end

        -- ------------------------------------------------
        --  CAS 3 : COUP NORMAL
        --  → Dégâts pleins + perte de sang normale
        -- ------------------------------------------------
        else
            if targetPlayer then
                if SurvivalService.IsDowned(targetPlayer) then
                    print(string.format("[Combat] %s tape %s au sol !", attacker.Name, targetPlayer.Name))
                    SurvivalService.HitDowned(targetPlayer)
                else
                    print(string.format("[Combat] Coup sur joueur %s (%d degats)", targetPlayer.Name, damage))
                    SurvivalService.TakeDamage(targetPlayer, damage)
                    SurvivalService.TakeBlood(targetPlayer, false)
                    NotifyHit:FireClient(targetPlayer, { damage = damage, attackType = attackType, guardBreak = false })
                    -- Interrompre l'exécution si le joueur reçoit un coup
                    if _G.GameServer then
                        _G.GameServer.InterruptExecution(targetPlayer)
                    end
                end
            else
                print(string.format("[Combat] Coup sur Dummy/PNJ (%d degats)", damage))
                targetHumanoid.Health -= damage
            end
        end
    end
end

-- ============================================================
--  LOGIQUE DU BLOCK
-- ============================================================
local function startBlock(player: Player)
    local data = combatData[player]
    if not data or data.isStunned then return end
    data.isBlocking = true
    data.isParrying = true
    data.parryTimer = CONFIG.PARRY_WINDOW
end

local function stopBlock(player: Player)
    local data = combatData[player]
    if not data then return end
    data.isBlocking = false
    data.isParrying = false
end

-- ============================================================
--  BOUCLE PRINCIPALE
-- ============================================================
local tickAccumulator = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
    tickAccumulator += deltaTime
    if tickAccumulator < 0.1 then return end
    local dt = tickAccumulator
    tickAccumulator = 0

    for player, data in pairs(combatData) do
        if data.inCombat then
            data.combatTimer -= dt
            if data.combatTimer <= 0 then
                data.inCombat = false
            end
        end

        if not data.inCombat and data.posture > 0 then
            data.posture = clamp(data.posture - CONFIG.POSTURE_DRAIN_RATE * dt, 0, CONFIG.MAX_POSTURE)
        end

        if data.isParrying then
            data.parryTimer -= dt
            if data.parryTimer <= 0 then
                data.isParrying = false
            end
        end

        if data.isStunned then
            data.stunTimer -= dt
            if data.stunTimer <= 0 then
                data.isStunned = false
                data.posture   = 0
            end
        end
    end
end)

-- ============================================================
--  RÉCEPTION DES INPUTS
-- ============================================================
RequestAttack.OnServerEvent:Connect(function(player: Player, attackType: string)
    if attackType ~= "light" and attackType ~= "heavy" then return end
    processAttack(player, attackType)
end)

RequestBlock.OnServerEvent:Connect(function(player: Player, isBlocking: boolean)
    if isBlocking then startBlock(player)
    else stopBlock(player) end
end)

-- ============================================================
--  ANTI COMBAT LOG
-- ============================================================
Players.PlayerRemoving:Connect(function(player: Player)
    local data = combatData[player]
    if data and data.inCombat then
        print(string.format("[CombatLog] %s quitté en combat -> MORT", player.Name))
        SurvivalService.Execute(player)
    end
    combatData[player] = nil
end)

-- ============================================================
--  INITIALISATION
-- ============================================================
local function initPlayer(player: Player)
    combatData[player] = {
        inCombat        = false,
        combatTimer     = 0,
        posture         = 0,
        isBlocking      = false,
        isParrying      = false,
        parryTimer      = 0,
        isStunned       = false,
        stunTimer       = 0,
        lastAttackTime  = 0,
    }
    print("[CombatService] Initialisé pour :", player.Name)
end

Players.PlayerAdded:Connect(initPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    initPlayer(player)
end

-- ============================================================
--  API PUBLIQUE
-- ============================================================
local CombatService = {}

function CombatService.IsInCombat(player: Player): boolean
    local data = combatData[player]
    return data and data.inCombat or false
end

function CombatService.GetPosture(player: Player): number
    local data = combatData[player]
    return data and data.posture or 0
end

return CombatService

-- ============================================================
--  CARRY & EXECUTE (V et B)
--  Ajout en bas du fichier - connecter après le return
-- ============================================================