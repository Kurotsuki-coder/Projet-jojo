--!strict
-- ============================================================
--  SurvivalService | AbyssalBlood
--  Gère : Faim, Soif, Sang + Dégâts progressifs + Mort
--  Auteur  : Membre A (Lead Script)
--  Version : 1.0.0
-- ============================================================

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes (créés ici, écoutés côté Client)
local Remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local UpdateSurvivalUI = Remotes:WaitForChild("UpdateSurvivalUI") -- RemoteEvent

-- ============================================================
--  CONSTANTES DE CONFIGURATION
--  Modifie ces valeurs pour équilibrer le jeu facilement
-- ============================================================
local CONFIG = {
    -- Valeurs max de chaque barre
    MAX_HUNGER  = 100,
    MAX_THIRST  = 100,
    MAX_BLOOD   = 100,

    -- Vitesse de déclin par seconde (en jeu)
    HUNGER_DRAIN_RATE  = 0.5 / 60,   -- vide en ~3h20 de jeu
    THIRST_DRAIN_RATE  = 0.8 / 60,   -- vide en ~2h de jeu
    BLOOD_DRAIN_RATE   = 0,   -- vide en ~5h de jeu (perd du sang naturellement)

    -- Délai avant dégâts quand une barre est à 0 (en secondes)
    GRACE_PERIOD = 120, -- 2 minutes

    -- Dégâts par seconde quand le timer de grâce est écoulé
    HP_DAMAGE_RATE = 2, -- 2 PV/sec

    -- Délai avant mort définitive quand HP = 0 (en secondes)
    DEATH_TIMER = 30,

    -- Fréquence de mise à jour du serveur (en secondes)
    TICK_RATE = 1,
}

-- ============================================================
--  STOCKAGE DES ÉTATS PAR JOUEUR
-- ============================================================
-- Structure par joueur :
-- playerData[player] = {
--   hunger         : number  (0-100)
--   thirst         : number  (0-100)
--   blood          : number  (0-100)
--   hp             : number  (0-100)
--   graceTimers    : { hunger=number, thirst=number, blood=number }
--   deathTimer     : number | nil  (countdown avant mort)
--   isDowned       : boolean
--   isDead         : boolean
-- }

local playerData: { [Player]: any } = {}

-- ============================================================
--  FONCTIONS UTILITAIRES
-- ============================================================

local function clamp(value: number, min: number, max: number): number
    return math.max(min, math.min(max, value))
end

-- Envoie l'état au client pour mettre à jour l'UI
local function syncClient(player: Player)
    local data = playerData[player]
    if not data then return end

    UpdateSurvivalUI:FireClient(player, {
        hunger     = data.hunger,
        thirst     = data.thirst,
        blood      = data.blood,
        hp         = data.hp,
        isDowned   = data.isDowned,
    })
end

-- ============================================================
--  INITIALISATION D'UN JOUEUR
-- ============================================================
local function initPlayer(player: Player)
    playerData[player] = {
        hunger      = CONFIG.MAX_HUNGER,
        thirst      = CONFIG.MAX_THIRST,
        blood       = CONFIG.MAX_BLOOD,
        hp          = 100,
        graceTimers = { hunger = 0, thirst = 0, blood = 0 },
        deathTimer  = nil,
        isDowned    = false,
        isDead      = false,
    }
    print("[SurvivalService] Joueur initialisé :", player.Name)
    syncClient(player)
end

-- ============================================================
--  LOGIQUE DE MORT (DOWNED STATE)
-- ============================================================

-- Le joueur tombe (Down State) - HP = 0
local function downPlayer(player: Player)
    local data = playerData[player]
    if data.isDowned or data.isDead then return end

    data.isDowned   = true
    data.hp         = 0
    data.deathTimer = CONFIG.DEATH_TIMER

    -- Bloquer les mouvements du personnage
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed   = 0
            humanoid.JumpPower   = 0
            humanoid:ChangeState(Enum.HumanoidStateType.Dead) -- animation de chute
        end
    end

    print("[SurvivalService] DOWNED :", player.Name)
    syncClient(player)
end

-- Mort définitive du joueur (Wipe ou Purgatoire check)
local function killPlayer(player: Player)
    local data = playerData[player]
    if data.isDead then return end

    data.isDead   = true
    data.isDowned = false

    print("[SurvivalService] MORT DÉFINITIVE :", player.Name)

    -- TODO (Étape 3) : Déclencher le système de Purgatoire ici
    -- PurgatoryService:HandleDeath(player)

    -- Reset basique pour l'instant : Respawn
    player:LoadCharacter()
    initPlayer(player) -- Remet les barres à 100 après respawn
end

-- ============================================================
--  BOUCLE PRINCIPALE (TICK) - Tourne toutes les 1 seconde
-- ============================================================
local tickAccumulator = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
    tickAccumulator += deltaTime
    if tickAccumulator < CONFIG.TICK_RATE then return end
    tickAccumulator = 0 -- Reset le timer

    for player, data in pairs(playerData) do
        -- Ne pas traiter les joueurs déjà morts ou en train de mourir
        if data.isDead then continue end

        -- ------------------------------------------------
        --  1. DÉCLINER LES BARRES DE SURVIE
        -- ------------------------------------------------
        data.hunger = clamp(data.hunger - CONFIG.HUNGER_DRAIN_RATE * CONFIG.TICK_RATE, 0, CONFIG.MAX_HUNGER)
        data.thirst = clamp(data.thirst - CONFIG.THIRST_DRAIN_RATE * CONFIG.TICK_RATE, 0, CONFIG.MAX_THIRST)
        data.blood  = clamp(data.blood  - CONFIG.BLOOD_DRAIN_RATE  * CONFIG.TICK_RATE, 0, CONFIG.MAX_BLOOD)

        -- ------------------------------------------------
        --  2. VÉRIFIER LES TIMERS DE GRÂCE
        -- ------------------------------------------------
        local takingDamage = false

        -- Faim
        if data.hunger <= 0 then
            data.graceTimers.hunger += CONFIG.TICK_RATE
            if data.graceTimers.hunger >= CONFIG.GRACE_PERIOD then
                takingDamage = true
            end
        else
            data.graceTimers.hunger = 0 -- Reset si le joueur mange
        end

        -- Soif
        if data.thirst <= 0 then
            data.graceTimers.thirst += CONFIG.TICK_RATE
            if data.graceTimers.thirst >= CONFIG.GRACE_PERIOD then
                takingDamage = true
            end
        else
            data.graceTimers.thirst = 0
        end

        -- Sang
        if data.blood <= 0 then
            data.graceTimers.blood += CONFIG.TICK_RATE
            if data.graceTimers.blood >= CONFIG.GRACE_PERIOD then
                takingDamage = true
            end
        else
            data.graceTimers.blood = 0
        end

        -- ------------------------------------------------
        --  3. APPLIQUER LES DÉGÂTS SUR LES HP
        -- ------------------------------------------------
        if takingDamage and not data.isDowned then
            data.hp = clamp(data.hp - CONFIG.HP_DAMAGE_RATE, 0, 100)

            if data.hp <= 0 then
                downPlayer(player)
            end
        end

        -- ------------------------------------------------
        --  4. TIMER DE MORT QUAND DOWNED
        -- ------------------------------------------------
        if data.isDowned and data.deathTimer then
            data.deathTimer -= CONFIG.TICK_RATE

            if data.deathTimer <= 0 then
                killPlayer(player)
                continue -- Passe au joueur suivant
            end
        end

        -- ------------------------------------------------
        --  5. SYNC CLIENT (mise à jour de l'UI)
        -- ------------------------------------------------
        syncClient(player)
    end
end)

-- ============================================================
--  FONCTIONS PUBLIQUES (Appelables par d'autres services)
-- ============================================================
local SurvivalService = {}

-- Nourrir / Hydrater / Donner du sang via un item
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
        data.hp     = clamp(data.hp     + amount, 0, 100)
        -- Si le joueur est Downed et reçoit des soins, il se relève
        if data.isDowned and data.hp >= 1 then
            data.isDowned   = false
            data.deathTimer = nil
            local character = player.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.WalkSpeed = 16 -- Valeur Roblox par défaut
                    humanoid.JumpPower = 50
                end
            end
        end
    end

    syncClient(player)
end

-- Appliquer des dégâts directs (combat, poison, etc.)
function SurvivalService.TakeDamage(player: Player, amount: number)
    local data = playerData[player]
    if not data or data.isDead then return end

    data.hp = clamp(data.hp - amount, 0, 100)

    if data.hp <= 0 and not data.isDowned then
        downPlayer(player)
    end

    syncClient(player)
end

-- Vérifier si un joueur est Down (pour le système Porter/Exécuter)
function SurvivalService.IsDowned(player: Player): boolean
    local data = playerData[player]
    return data and data.isDowned or false
end

-- Exécuter un joueur à terre (appelé par un autre joueur)
function SurvivalService.Execute(target: Player)
    local data = playerData[target]
    if not data or not data.isDowned then return end

    print("[SurvivalService] EXÉCUTION de :", target.Name)
    killPlayer(target)
end

-- ============================================================
--  CONNEXIONS JOUEURS
-- ============================================================
Players.PlayerAdded:Connect(initPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
    -- TODO (Étape 2) : Si le joueur quitte en mode In-Combat -> Mort
    -- CombatService:HandleCombatLog(player)
    playerData[player] = nil
end)

return SurvivalService