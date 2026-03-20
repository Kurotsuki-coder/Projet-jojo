--!strict
-- ============================================================
--  RemoteSetup | AbyssalBlood
--  Crée tous les RemoteEvents/Functions au démarrage
--  DOIT être le premier script lancé (ServerScriptService)
--  Auteur  : Membre A
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Créer le dossier Shared/Remotes s'il n'existe pas
local Shared = ReplicatedStorage:FindFirstChild("Shared")
    or Instance.new("Folder", ReplicatedStorage)
Shared.Name = "Shared"

local Remotes = Shared:FindFirstChild("Remotes")
    or Instance.new("Folder", Shared)
Remotes.Name = "Remotes"

-- ============================================================
--  LISTE DE TOUS LES REMOTES DU JEU
--  Ajoute ici chaque nouveau Remote quand tu codes un système
-- ============================================================
local remoteEvents = {
    -- Survie
    "UpdateSurvivalUI",     -- Serveur -> Client : Sync barres

    -- Combat (Étape 2)
    "RequestAttack",        -- Client -> Serveur : Le joueur attaque
    "RequestParry",         -- Client -> Serveur : Le joueur tente un parry
    "NotifyHit",            -- Serveur -> Client : Confirme qu'un coup a touché
    "NotifyParrySuccess",   -- Serveur -> Client : Parry validé

    -- Stands (Étape 3)
    "RequestSummonStand",   -- Client -> Serveur
    "UpdateStandState",     -- Serveur -> Client

    -- Purgatoire (Étape 5)
    "EnterPurgatory",       -- Serveur -> Client
    "PurgatoryResult",      -- Client -> Serveur (Rédemption réussie/échouée)
}

-- Créer chaque RemoteEvent automatiquement
for _, name in ipairs(remoteEvents) do
    if not Remotes:FindFirstChild(name) then
        local remote = Instance.new("RemoteEvent")
        remote.Name  = name
        remote.Parent = Remotes
    end
end

print("[RemoteSetup] Tous les RemoteEvents sont prêts.")