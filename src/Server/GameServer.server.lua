--!strict
-- ============================================================
--  GameServer | AbyssalBlood
--  Script principal côté serveur
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Shared = ReplicatedStorage:FindFirstChild("Shared") or Instance.new("Folder", ReplicatedStorage)
Shared.Name = "Shared"
local Remotes = Shared:FindFirstChild("Remotes") or Instance.new("Folder", Shared)
Remotes.Name = "Remotes"

local remoteEvents = {
    "UpdateSurvivalUI",
    "RequestAttack",
    "RequestBlock",
    "RequestParry",
    "NotifyHit",
    "NotifyParrySuccess",
    "RequestSummonStand",
    "UpdateStandState",
    "EnterPurgatory",
    "PurgatoryResult",
    "RequestCarry",
    "RequestExecute",
    "UpdateCombatUI",
    "NotifyExecuteState",
    "NotifyCarry",       -- Serveur → Client : portage visuel
}

for _, name in ipairs(remoteEvents) do
    if not Remotes:FindFirstChild(name) then
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = Remotes
    end
end

print("[Main] Remotes créés.")

local Services = script.Parent.Services
local SurvivalService = require(Services.SurvivalService)
print("[Main] SurvivalService chargé.")

require(Services.CombatService)
print("[Main] CombatService chargé.")

print("[Main] Tous les services sont prêts !")

local NotifyExecuteState = Remotes:WaitForChild("NotifyExecuteState")
local NotifyCarry        = Remotes:WaitForChild("NotifyCarry")

-- ============================================================
--  REGISTRE DES PNJ DOWNED
-- ============================================================
local npcDownedRegistry: { [Model]: {
    isDowned      : boolean,
    onExecute     : () -> (),
    onCarry       : (carrier: Player) -> (),
    onCarryCancel : () -> (),
}} = {}

local GameServer = {}

function GameServer.RegisterNPC(npc: Model, callbacks: {
    onExecute     : () -> (),
    onCarry       : (carrier: Player) -> (),
    onCarryCancel : () -> (),
})
    npcDownedRegistry[npc] = {
        isDowned      = false,
        onExecute     = callbacks.onExecute,
        onCarry       = callbacks.onCarry,
        onCarryCancel = callbacks.onCarryCancel,
    }
    print("[GameServer] PNJ enregistré : " .. npc.Name)
end

function GameServer.SetNPCDowned(npc: Model, state: boolean)
    if npcDownedRegistry[npc] then
        npcDownedRegistry[npc].isDowned = state
    end
end

function GameServer.UnregisterNPC(npc: Model)
    npcDownedRegistry[npc] = nil
end

function GameServer.InterruptExecution(player: Player)
    -- Géré ci-dessous via cancelExecution
end

function GameServer.NotifyCarryToClient(carrier: Player, targetName: string, carrying: boolean)
    NotifyCarry:FireClient(carrier, { carrying = carrying, targetName = targetName })
end

_G.GameServer = GameServer

-- ============================================================
--  ÉTATS PAR JOUEUR
-- ============================================================
local carryState: { [Player]: { target: Player?, targetNPC: Model?, targetName: string?, isNPC: boolean } } = {}
local executeState: { [Player]: { target: Player?, targetNPC: Model?, isNPC: boolean, active: boolean } } = {}

local INTERACT_RANGE = 6
local EXECUTE_TIME   = 4

-- ============================================================
--  TROUVER LA CIBLE LA PLUS PROCHE
-- ============================================================
local function getNearestDownedTarget(from: Player): (Player?, Model?)
    local fromChar = from.Character
    if not fromChar then return nil, nil end
    local fromRoot = fromChar:FindFirstChild("HumanoidRootPart") :: BasePart
    if not fromRoot then return nil, nil end

    local nearestPlayer: Player? = nil
    local nearestNPC: Model?     = nil
    local nearestDist            = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player == from then continue end
        if not SurvivalService.IsDowned(player) then continue end
        local char = player.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
        if not root then continue end
        local dist = (fromRoot.Position - root.Position).Magnitude
        if dist < nearestDist then
            nearestDist   = dist
            nearestPlayer = player
            nearestNPC    = nil
        end
    end

    for npc, data in pairs(npcDownedRegistry) do
        if not data.isDowned then continue end
        local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
        if not root then continue end
        local dist = (fromRoot.Position - root.Position).Magnitude
        if dist < nearestDist then
            nearestDist   = dist
            nearestPlayer = nil
            nearestNPC    = npc
        end
    end

    if nearestDist > INTERACT_RANGE then return nil, nil end
    return nearestPlayer, nearestNPC
end

-- ============================================================
--  V = Porter / Annuler
-- ============================================================
local RequestCarry = Remotes:WaitForChild("RequestCarry")

RequestCarry.OnServerEvent:Connect(function(carrier: Player)
    local state = carryState[carrier]

    -- Si déjà en train de porter → annuler
    if state and (state.target or state.targetNPC) then
        print(string.format("[GameServer] %s annule le portage", carrier.Name))

        if state.isNPC and state.targetNPC then
            local data = npcDownedRegistry[state.targetNPC]
            if data then data.onCarryCancel() end
            -- Notifier le client d'arrêter le weld visuel
            NotifyCarry:FireClient(carrier, { carrying = false, targetName = state.targetName or "" })
        elseif state.target then
            SurvivalService.CancelCarry(state.target)
            NotifyCarry:FireClient(carrier, { carrying = false, targetName = "" })
        end

        carryState[carrier] = { target = nil, targetNPC = nil, targetName = nil, isNPC = false }
        return
    end

    -- Trouver une cible
    local targetPlayer, targetNPC = getNearestDownedTarget(carrier)

    if targetPlayer then
        carryState[carrier] = { target = targetPlayer, targetNPC = nil, targetName = targetPlayer.Name, isNPC = false }
        SurvivalService.CarryPlayer(carrier, targetPlayer)
        NotifyCarry:FireClient(carrier, { carrying = true, targetName = targetPlayer.Name, isPlayer = true })

    elseif targetNPC then
        local data = npcDownedRegistry[targetNPC]
        if data then
            carryState[carrier] = { target = nil, targetNPC = targetNPC, targetName = targetNPC.Name, isNPC = true }
            print(string.format("[GameServer] %s porte le PNJ %s", carrier.Name, targetNPC.Name))
            data.onCarry(carrier)
            -- Notifier le client pour le weld visuel
            NotifyCarry:FireClient(carrier, { carrying = true, targetName = targetNPC.Name, isPlayer = false })
        end
    else
        print("[GameServer] " .. carrier.Name .. " : aucune cible Downed à portée")
    end
end)

-- ============================================================
--  B = Exécuter avec timer 4 secondes
-- ============================================================
local RequestExecute = Remotes:WaitForChild("RequestExecute")

local function cancelExecution(killer: Player, reason: string)
    local state = executeState[killer]
    if not state or not state.active then return end
    state.active = false
    print(string.format("[GameServer] Exécution annulée (%s) pour %s", reason, killer.Name))
    NotifyExecuteState:FireClient(killer, { active = false, cancelled = true, reason = reason })
end

-- Rendre cancelExecution accessible depuis InterruptExecution
local executeCancelFunctions: { [Player]: (reason: string) -> () } = {}

function GameServer.InterruptExecution(player: Player)
    cancelExecution(player, "coup reçu")
    -- Annuler aussi le portage
    local carry = carryState[player]
    if carry and (carry.target or carry.targetNPC) then
        print(string.format("[GameServer] %s lâche sa cible (coup reçu)", player.Name))
        if carry.isNPC and carry.targetNPC then
            local data = npcDownedRegistry[carry.targetNPC]
            if data then data.onCarryCancel() end
            NotifyCarry:FireClient(player, { carrying = false, targetName = carry.targetName or "" })
        elseif carry.target then
            SurvivalService.CancelCarry(carry.target)
            NotifyCarry:FireClient(player, { carrying = false, targetName = "" })
        end
        carryState[player] = { target = nil, targetNPC = nil, targetName = nil, isNPC = false }
    end
end

RequestExecute.OnServerEvent:Connect(function(killer: Player)
    local state = executeState[killer]

    if state and state.active then
        cancelExecution(killer, "B appuyé à nouveau")
        return
    end

    local targetPlayer, targetNPC = getNearestDownedTarget(killer)

    local function startExec(tp: Player?, tn: Model?, isNPC: boolean)
        executeState[killer] = { target = tp, targetNPC = tn, isNPC = isNPC, active = true }
        print(string.format("[GameServer] %s commence une exécution (%d sec)...", killer.Name, EXECUTE_TIME))
        NotifyExecuteState:FireClient(killer, { active = true, duration = EXECUTE_TIME })

        task.spawn(function()
            task.wait(EXECUTE_TIME)
            local s = executeState[killer]
            if not s or not s.active then return end
            s.active = false

            if isNPC and tn then
                local data = npcDownedRegistry[tn]
                if data and data.isDowned then
                    print(string.format("[GameServer] %s achève le PNJ %s !", killer.Name, tn.Name))
                    data.isDowned = false
                    data.onExecute()
                end
            elseif tp then
                print(string.format("[GameServer] %s achève %s !", killer.Name, tp.Name))
                SurvivalService.Execute(tp)
            end

            NotifyExecuteState:FireClient(killer, { active = false, success = true })
        end)
    end

    if targetPlayer then
        startExec(targetPlayer, nil, false)
    elseif targetNPC then
        startExec(nil, targetNPC, true)
    else
        print("[GameServer] " .. killer.Name .. " : aucune cible Downed à portée")
    end
end)

-- ============================================================
--  INIT JOUEURS
-- ============================================================
Players.PlayerAdded:Connect(function(player)
    carryState[player]   = { target = nil, targetNPC = nil, targetName = nil, isNPC = false }
    executeState[player] = { target = nil, targetNPC = nil, isNPC = false, active = false }
end)
Players.PlayerRemoving:Connect(function(player)
    carryState[player]   = nil
    executeState[player] = nil
end)