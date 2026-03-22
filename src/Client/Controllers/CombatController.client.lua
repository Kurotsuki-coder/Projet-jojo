--!strict
-- ============================================================
--  CombatController | AbyssalBlood
--  CÔTÉ CLIENT uniquement
--  Clic Gauche = Attaque légère
--  R           = Attaque lourde
--  F (maintenu)= Block / Perfect Block
--  V           = Porter / Annuler portage
--  B           = Exécuter (timer 4 sec)
--  Auteur  : Membre A
--  Version : 9.0.0 (R6)
-- ============================================================

print("[DEBUG] CombatController chargé !")

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid") :: Humanoid
local animator  = humanoid:WaitForChild("Animator") :: Animator

humanoid.BreakJointsOnDeath = false

local Remotes            = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local RequestAttack      = Remotes:WaitForChild("RequestAttack")
local RequestBlock       = Remotes:WaitForChild("RequestBlock")
local RequestCarry       = Remotes:WaitForChild("RequestCarry")
local RequestExecute     = Remotes:WaitForChild("RequestExecute")
local NotifyHit          = Remotes:WaitForChild("NotifyHit")
local NotifyParrySuccess = Remotes:WaitForChild("NotifyParrySuccess")
local NotifyExecuteState = Remotes:WaitForChild("NotifyExecuteState")
local NotifyCarry        = Remotes:WaitForChild("NotifyCarry")

-- ============================================================
--  WALK / RUN ANIMATION IDs (R6)
-- ============================================================
local WALK_ANIM_ID = "rbxassetid://106656923074147"
local PUNCH_ANIM_ID = "rbxassetid://84486299502302"
local BLOCK_ANIM_ID = "rbxassetid://180435571"

-- ============================================================
--  REMPLACEMENT DES ANIMS WALK/RUN DANS LE SCRIPT ANIMATE R6
-- ============================================================
local function replaceWalkAnim(char: Model)
    local animateScript = char:WaitForChild("Animate", 5)
    if not animateScript then
        print("[CombatController] Script Animate introuvable !")
        return
    end

    local walkFolder = animateScript:WaitForChild("walk", 5)
    if walkFolder then
        local walkAnim = walkFolder:WaitForChild("WalkAnim", 5)
        if walkAnim then
            walkAnim.AnimationId = WALK_ANIM_ID
            print("[CombatController] Animation walk remplacée !")
        end
    end

    local runFolder = animateScript:FindFirstChild("run")
    if runFolder then
        local runAnim = runFolder:FindFirstChild("RunAnim")
        if runAnim then
            runAnim.AnimationId = WALK_ANIM_ID
            print("[CombatController] Animation run remplacée !")
        end
    end
end

task.spawn(function()
    replaceWalkAnim(character)
end)

-- ============================================================
--  ANIMATIONS COMBAT
-- ============================================================
local blockTrack: AnimationTrack? = nil
local punchTrack: AnimationTrack? = nil

local function loadAnimations(anim: Animator)
    local blockAnim = Instance.new("Animation")
    blockAnim.AnimationId = BLOCK_ANIM_ID
    local bTrack = anim:LoadAnimation(blockAnim)
    bTrack.Priority = Enum.AnimationPriority.Action
    bTrack.Looped   = true

    local punchAnim = Instance.new("Animation")
    punchAnim.AnimationId = PUNCH_ANIM_ID
    local pTrack = anim:LoadAnimation(punchAnim)
    pTrack.Priority = Enum.AnimationPriority.Action
    pTrack.Looped   = false

    return bTrack, pTrack
end

blockTrack, punchTrack = loadAnimations(animator)

-- ============================================================
--  RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    humanoid  = newCharacter:WaitForChild("Humanoid") :: Humanoid
    task.wait(0.1)
    animator  = humanoid:WaitForChild("Animator") :: Animator
    humanoid.BreakJointsOnDeath = false
    blockTrack, punchTrack = loadAnimations(animator)
    task.spawn(function()
        task.wait(0.5)
        replaceWalkAnim(newCharacter)
    end)
end)

-- ============================================================
--  ANTI-SPAM
-- ============================================================
local lastAttackTime = 0
local ATTACK_COOLDOWN = 0.3

local function canAttack(): boolean
    local now = tick()
    if now - lastAttackTime >= ATTACK_COOLDOWN then
        lastAttackTime = now
        return true
    end
    return false
end

-- ============================================================
--  ATTAQUE VIA LA SOURIS
-- ============================================================
local mouse = player:GetMouse()

mouse.Button1Down:Connect(function()
    if canAttack() then
        RequestAttack:FireServer("light")
        if punchTrack then
            if punchTrack.IsPlaying then punchTrack:Stop() end
            punchTrack:Play()
        end
    end
end)

-- ============================================================
--  TOUCHES CLAVIER
-- ============================================================
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.R then
        if canAttack() then
            RequestAttack:FireServer("heavy")
            if punchTrack then
                if punchTrack.IsPlaying then punchTrack:Stop() end
                punchTrack:Play()
            end
        end

    elseif input.KeyCode == Enum.KeyCode.F then
        RequestBlock:FireServer(true)
        if blockTrack and not blockTrack.IsPlaying then
            blockTrack:Play()
        end

    elseif input.KeyCode == Enum.KeyCode.V then
        print("[Combat] Tentative de porter...")
        RequestCarry:FireServer()

    elseif input.KeyCode == Enum.KeyCode.B then
        print("[Combat] Tentative d'achever...")
        RequestExecute:FireServer()
    end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
    if input.KeyCode == Enum.KeyCode.F then
        RequestBlock:FireServer(false)
        if blockTrack and blockTrack.IsPlaying then
            blockTrack:Stop()
        end
    end
end)

-- ============================================================
--  PORTAGE VISUEL (Weld côté client)
-- ============================================================
local currentCarryWeld: WeldConstraint? = nil

NotifyCarry.OnClientEvent:Connect(function(data: {
    carrying   : boolean,
    targetName : string,
    isPlayer   : boolean?,
})
    local myChar = player.Character
    if not myChar then return end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart") :: BasePart
    if not myRoot then return end

    if data.carrying then
        local target = workspace:FindFirstChild(data.targetName)
        if not target then
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Name == data.targetName and p.Character then
                    target = p.Character
                    break
                end
            end
        end

        if not target then
            print("[CarryVisual] Cible introuvable : " .. data.targetName)
            return
        end

        local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart
        if not targetRoot then return end

        local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
        if targetHumanoid then
            targetHumanoid.PlatformStand = true
        end

        targetRoot.CFrame = myRoot.CFrame * CFrame.new(0.8, 0.5, -0.5)

        if currentCarryWeld then currentCarryWeld:Destroy() end
        local weld = Instance.new("WeldConstraint")
        weld.Name   = "CarryWeldClient"
        weld.Part0  = myRoot
        weld.Part1  = targetRoot
        weld.Parent = myRoot
        currentCarryWeld = weld

        print("[CarryVisual] Portage visuel actif : " .. data.targetName)

    else
        if currentCarryWeld then
            currentCarryWeld:Destroy()
            currentCarryWeld = nil
        end

        local weld = myRoot:FindFirstChild("CarryWeldClient")
        if weld then weld:Destroy() end

        local target = workspace:FindFirstChild(data.targetName)
        if target then
            local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
            if targetHumanoid then
                targetHumanoid.PlatformStand = false
            end
        end

        print("[CarryVisual] Portage visuel annulé")
    end
end)

-- ============================================================
--  FEEDBACKS SERVEUR
-- ============================================================
NotifyHit.OnClientEvent:Connect(function(data: {
    damage     : number,
    attackType : string,
    guardBreak : boolean,
})
    if data.guardBreak then
        print("⚠ GUARD BREAK ! Ta posture est pleine !")
    else
        print(string.format("Tu as reçu %d dégâts (%s)", data.damage, data.attackType))
    end
end)

NotifyParrySuccess.OnClientEvent:Connect(function(data: {
    attackerName : string?,
    parried      : boolean?,
})
    if data.attackerName then
        print(string.format("✅ PERFECT BLOCK sur %s !", data.attackerName))
    elseif data.parried then
        print("❌ Ton attaque a été parfaitement parée !")
    end
end)

NotifyExecuteState.OnClientEvent:Connect(function(data: {
    active    : boolean,
    duration  : number?,
    cancelled : boolean?,
    success   : boolean?,
    reason    : string?,
})
    if data.active then
        print(string.format("⚔ Exécution en cours... (%d sec)", data.duration or 4))
    elseif data.cancelled then
        print(string.format("❌ Exécution annulée (%s)", data.reason or ""))
    elseif data.success then
        print("✅ Exécution réussie !")
    end
end)