--!strict
-- ============================================================
--  SurvivalController | AbyssalBlood
--  CÔTÉ CLIENT uniquement
--  Reçoit les données du serveur et met à jour l'interface
--  Auteur  : Membre A (Lead Script)
--  Version : 1.0.0
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player      = Players.LocalPlayer
local playerGui   = player:WaitForChild("PlayerGui")

-- Attendre que les Remotes soient prêts
local Remotes         = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local UpdateSurvivalUI = Remotes:WaitForChild("UpdateSurvivalUI")

-- ============================================================
--  RÉFÉRENCES À L'UI (à connecter quand le GUI sera créé)
--  Ces lignes seront activées quand le Membre B créera le GUI
-- ============================================================
-- local gui        = playerGui:WaitForChild("HUD")
-- local hungerBar  = gui.SurvivalFrame.HungerBar
-- local thirstBar  = gui.SurvivalFrame.ThirstBar
-- local bloodBar   = gui.SurvivalFrame.BloodBar
-- local hpBar      = gui.SurvivalFrame.HPBar

-- ============================================================
--  RÉCEPTION DES DONNÉES DU SERVEUR
-- ============================================================
UpdateSurvivalUI.OnClientEvent:Connect(function(data: {
    hunger   : number,
    thirst   : number,
    blood    : number,
    hp       : number,
    isDowned : boolean,
})
    -- DEBUG : Affiche les valeurs dans la console pendant le dev
    -- Retire ces lignes quand l'UI sera terminée
    print(string.format(
        "[HUD] HP: %.0f | Faim: %.0f | Soif: %.0f | Sang: %.0f | Downed: %s",
        data.hp, data.hunger, data.thirst, data.blood,
        tostring(data.isDowned)
    ))

    -- --------------------------------------------------------
    --  MISE À JOUR DES BARRES (activer quand le GUI est prêt)
    -- --------------------------------------------------------
    -- hungerBar.Size  = UDim2.new(data.hunger / 100, 0, 1, 0)
    -- thirstBar.Size  = UDim2.new(data.thirst / 100, 0, 1, 0)
    -- bloodBar.Size   = UDim2.new(data.blood  / 100, 0, 1, 0)
    -- hpBar.Size      = UDim2.new(data.hp     / 100, 0, 1, 0)

    -- --------------------------------------------------------
    --  ÉTAT DOWNED : cacher le HUD et afficher "K.O."
    -- --------------------------------------------------------
    -- if data.isDowned then
    --     gui.KOFrame.Visible = true
    -- else
    --     gui.KOFrame.Visible = false
    -- end
end)