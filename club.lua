local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local plr = Players.LocalPlayer

print("[INIT] Chess Bot - Starting...")

-- ========================================
-- VARIÁVEIS GLOBAIS
-- ========================================

local autoPlayEnabled = false
local analysisDepth = 25 -- Profundidade da análise (padrão: 25)
local currentTable = nil
local lastFEN = nil
local isRunning = false
local lastEvalFEN = nil   -- Para tracking da eval bar
local lastEvalScore = nil -- Para tracking da avaliação anterior

-- ========================================
-- FUNÇÕES DE DETECÇÃO DE PARTIDA (NOVA LÓGICA)
-- ========================================

-- Encontra a mesa ativa do jogador
function getPlayerTable()
    -- Primeiro tenta encontrar mesa com o nome do jogador
    for _, chessTable in pairs(Workspace:GetChildren()) do
        if chessTable.Name == "ChessTableset" then
            -- Verifica componentes necessários
            if not chessTable:FindFirstChild("WhitePlayer") then continue end
            if not chessTable:FindFirstChild("BlackPlayer") then continue end
            if not chessTable:FindFirstChild("FEN") then continue end
            if not chessTable:FindFirstChild("IsGameActive") then continue end

            local whiteName = chessTable.WhitePlayer.Value
            local blackName = chessTable.BlackPlayer.Value

            -- Verifica se o jogador está nesta mesa
            if whiteName == plr.Name or blackName == plr.Name then
                -- Verifica se o jogo está ativo
                if chessTable.IsGameActive.Value == true then
                    return chessTable
                end
            end
        end
    end

    -- Se não encontrou mesa com o jogador, procura qualquer mesa ativa
    -- (caso o jogador tenha entrado mas ainda não foi registrado)
    for _, chessTable in pairs(Workspace:GetChildren()) do
        if chessTable.Name == "ChessTableset" then
            if not chessTable:FindFirstChild("IsGameActive") then continue end
            if not chessTable:FindFirstChild("WhitePlayer") then continue end
            if not chessTable:FindFirstChild("BlackPlayer") then continue end
            if not chessTable:FindFirstChild("FEN") then continue end

            -- Verifica se está ativo
            if chessTable.IsGameActive.Value == true then
                local whiteName = chessTable.WhitePlayer.Value
                local blackName = chessTable.BlackPlayer.Value

                -- Verifica se o jogador está nesta mesa
                if whiteName == plr.Name or blackName == plr.Name then
                    return chessTable
                end
            end
        end
    end

    return nil
end

-- Verifica se está em partida válida
function isInValidGame()
    local chessTable = getPlayerTable()

    if not chessTable then
        return false, "Table not found or game inactive"
    end

    if not chessTable:FindFirstChild("IsGameActive") then
        return false, "Table without IsGameActive"
    end

    if chessTable.IsGameActive.Value ~= true then
        return false, "Game not active"
    end

    if not chessTable:FindFirstChild("FEN") then
        return false, "Table without FEN"
    end

    local fen = chessTable.FEN.Value

    if fen == "" or fen == nil then
        return false, "Empty FEN"
    end

    if string.len(fen) < 10 then
        return false, "Invalid FEN"
    end

    -- Verifica se o jogador está registrado na mesa
    local whiteName = chessTable.WhitePlayer.Value
    local blackName = chessTable.BlackPlayer.Value

    if whiteName ~= plr.Name and blackName ~= plr.Name then
        return false, "Player not in this table"
    end

    return true, chessTable
end

-- Identifica o time do jogador
function getLocalTeam(chessTable)
    if not chessTable then return nil end
    if not chessTable:FindFirstChild("WhitePlayer") then return nil end
    if not chessTable:FindFirstChild("BlackPlayer") then return nil end

    if chessTable.WhitePlayer.Value == plr.Name then
        return "w"
    elseif chessTable.BlackPlayer.Value == plr.Name then
        return "b"
    end
    return nil
end

-- Verifica se é a vez do jogador
function isPlayerTurn(chessTable)
    if not chessTable then return false end
    if not chessTable:FindFirstChild("FEN") then return false end

    local fen = chessTable.FEN.Value
    local team = getLocalTeam(chessTable)

    if not team then return false end

    local fenParts = {}
    for part in fen:gmatch("%S+") do
        table.insert(fenParts, part)
    end

    if #fenParts >= 2 then
        return fenParts[2] == team
    end

    return false
end

-- ========================================
-- UI MODERNA
-- ========================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChessAssistantUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = plr.PlayerGui

-- Frame principal
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 420, 0, 335)
mainFrame.Position = UDim2.new(0.5, -210, 0.3, -140)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
header.BorderSizePixel = 0
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 12)
headerCorner.Parent = header

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 20)
headerFix.Position = UDim2.new(0, 0, 1, -20)
headerFix.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -75, 1, 0)
title.Position = UDim2.new(0, 15, 0, 0)
title.BackgroundTransparency = 1
title.Text = "♟️ Chess Bot"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- Evaluation Bar Container (Dentro da UI)
local evalBarContainer = Instance.new("Frame")
evalBarContainer.Name = "EvalBarContainer"
evalBarContainer.Size = UDim2.new(0, 50, 1, -50)
evalBarContainer.Position = UDim2.new(0, 10, 0, 45)
evalBarContainer.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
evalBarContainer.BorderSizePixel = 0
evalBarContainer.Parent = mainFrame

-- Background interno da barra (quadrado)
local evalBarBg = Instance.new("Frame")
evalBarBg.Name = "EvalBarBg"
evalBarBg.Size = UDim2.new(1, -8, 1, -8)
evalBarBg.Position = UDim2.new(0, 4, 0, 4)
evalBarBg.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
evalBarBg.BorderSizePixel = 0
evalBarBg.Parent = evalBarContainer

-- Barra preta (background fixo)
local blackBar = Instance.new("Frame")
blackBar.Name = "BlackBar"
blackBar.Size = UDim2.new(1, 0, 1, 0)
blackBar.Position = UDim2.new(0, 0, 0, 0)
blackBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
blackBar.BorderSizePixel = 0
blackBar.Parent = evalBarBg

-- Barra branca (animada)
local whiteBar = Instance.new("Frame")
whiteBar.Name = "WhiteBar"
whiteBar.Size = UDim2.new(1, 0, 0.5, 0)
whiteBar.Position = UDim2.new(0, 0, 0, 0)
whiteBar.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
whiteBar.BorderSizePixel = 0
whiteBar.ZIndex = 2
whiteBar.Parent = evalBarBg

-- Linha divisória no meio
local centerLine = Instance.new("Frame")
centerLine.Name = "CenterLine"
centerLine.Size = UDim2.new(1, 0, 0, 2)
centerLine.Position = UDim2.new(0, 0, 0.5, -1)
centerLine.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
centerLine.BorderSizePixel = 0
centerLine.ZIndex = 3
centerLine.Parent = evalBarBg

-- Evaluation Text
local evalText = Instance.new("TextLabel")
evalText.Name = "EvalText"
evalText.BackgroundTransparency = 1
evalText.Size = UDim2.new(1, 0, 0, 35)
evalText.Position = UDim2.new(0, 0, 0.5, -17.5)
evalText.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
evalText.BorderSizePixel = 0
evalText.Text = "0.0"
evalText.TextColor3 = Color3.fromRGB(255, 255, 255)
evalText.TextSize = 13
evalText.Font = Enum.Font.GothamBold
evalText.ZIndex = 4
evalText.Parent = evalBarBg

local evalTextStroke = Instance.new("UIStroke")
evalTextStroke.Color = Color3.fromRGB(60, 60, 60)
evalTextStroke.Thickness = 1
evalTextStroke.Parent = evalText

-- Botão minimize
-- Depth Controls
local depthContainer = Instance.new("Frame")
depthContainer.Size = UDim2.new(0, 120, 0, 30)
depthContainer.Position = UDim2.new(0, 225, 0, 5)
depthContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
depthContainer.BorderSizePixel = 0
depthContainer.Parent = header

local depthContainerCorner = Instance.new("UICorner")
depthContainerCorner.CornerRadius = UDim.new(0, 6)
depthContainerCorner.Parent = depthContainer

local depthLabel = Instance.new("TextLabel")
depthLabel.Size = UDim2.new(0, 50, 1, 0)
depthLabel.Position = UDim2.new(0, 35, 0, 0)
depthLabel.BackgroundTransparency = 1
depthLabel.Text = "Depth: " .. analysisDepth
depthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
depthLabel.TextSize = 12
depthLabel.Font = Enum.Font.GothamMedium
depthLabel.Parent = depthContainer

local depthDecreaseBtn = Instance.new("TextButton")
depthDecreaseBtn.Size = UDim2.new(0, 25, 0, 22)
depthDecreaseBtn.Position = UDim2.new(0, 5, 0, 4)
depthDecreaseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
depthDecreaseBtn.Text = "−"
depthDecreaseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
depthDecreaseBtn.TextSize = 16
depthDecreaseBtn.Font = Enum.Font.GothamBold
depthDecreaseBtn.Parent = depthContainer

local depthDecreaseCorner = Instance.new("UICorner")
depthDecreaseCorner.CornerRadius = UDim.new(0, 4)
depthDecreaseCorner.Parent = depthDecreaseBtn

local depthIncreaseBtn = Instance.new("TextButton")
depthIncreaseBtn.Size = UDim2.new(0, 25, 0, 22)
depthIncreaseBtn.Position = UDim2.new(1, -30, 0, 4)
depthIncreaseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
depthIncreaseBtn.Text = "+"
depthIncreaseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
depthIncreaseBtn.TextSize = 14
depthIncreaseBtn.Font = Enum.Font.GothamBold
depthIncreaseBtn.Parent = depthContainer

local depthIncreaseCorner = Instance.new("UICorner")
depthIncreaseCorner.CornerRadius = UDim.new(0, 4)
depthIncreaseCorner.Parent = depthIncreaseBtn

-- Event listeners para os botões de depth
depthDecreaseBtn.MouseButton1Click:Connect(function()
    if analysisDepth > 5 then
        analysisDepth = analysisDepth - 1
        depthLabel.Text = "Depth: " .. analysisDepth
        updateStatus("Depth: " .. analysisDepth, Color3.fromRGB(150, 200, 255))
    end
end)

depthIncreaseBtn.MouseButton1Click:Connect(function()
    if analysisDepth < 30 then
        analysisDepth = analysisDepth + 1
        depthLabel.Text = "Depth: " .. analysisDepth
        updateStatus("Depth: " .. analysisDepth, Color3.fromRGB(150, 200, 255))
    end
end)

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
minimizeBtn.Position = UDim2.new(1, -70, 0, 5)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 20
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.Parent = header

local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 6)
minimizeCorner.Parent = minimizeBtn

-- Botão unload
local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(0, 30, 0, 30)
unloadBtn.Position = UDim2.new(1, -35, 0, 5)
unloadBtn.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
unloadBtn.Text = "X"
unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadBtn.TextSize = 18
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Parent = header

local unloadCorner = Instance.new("UICorner")
unloadCorner.CornerRadius = UDim.new(0, 6)
unloadCorner.Parent = unloadBtn

-- Content Frame
local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -80, 1, -50)
contentFrame.Position = UDim2.new(0, 70, 0, 45)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

-- Game Status
local gameStatusLabel = Instance.new("TextLabel")
gameStatusLabel.Name = "GameStatus"
gameStatusLabel.Size = UDim2.new(1, 0, 0, 25)
gameStatusLabel.Position = UDim2.new(0, 0, 0, 0)
gameStatusLabel.BackgroundTransparency = 1
gameStatusLabel.Text = "Not in game"
gameStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
gameStatusLabel.TextSize = 13
gameStatusLabel.Font = Enum.Font.Gotham
gameStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
gameStatusLabel.Parent = contentFrame

-- Status Label
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, 0, 0, 25)
statusLabel.Position = UDim2.new(0, 0, 0, 30)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Waiting..."
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.TextSize = 14
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = contentFrame

-- Move Label
local moveLabel = Instance.new("TextLabel")
moveLabel.Name = "Move"
moveLabel.Size = UDim2.new(1, 0, 0, 30)
moveLabel.Position = UDim2.new(0, 0, 0, 60)
moveLabel.BackgroundTransparency = 1
moveLabel.Text = "Move: ---"
moveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
moveLabel.TextSize = 16
moveLabel.Font = Enum.Font.GothamBold
moveLabel.TextXAlignment = Enum.TextXAlignment.Left
moveLabel.Parent = contentFrame

-- Your Move Classification
local yourMoveLabel = Instance.new("TextLabel")
yourMoveLabel.Name = "YourMove"
yourMoveLabel.Size = UDim2.new(1, 0, 0, 22)
yourMoveLabel.Position = UDim2.new(0, 0, 0, 92)
yourMoveLabel.BackgroundTransparency = 1
yourMoveLabel.Text = "You: ---"
yourMoveLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
yourMoveLabel.TextSize = 13
yourMoveLabel.Font = Enum.Font.GothamBold
yourMoveLabel.TextXAlignment = Enum.TextXAlignment.Left
yourMoveLabel.Visible = false
yourMoveLabel.Parent = contentFrame

-- Opponent Move Classification
local oppMoveLabel = Instance.new("TextLabel")
oppMoveLabel.Name = "OppMove"
oppMoveLabel.Size = UDim2.new(1, 0, 0, 22)
oppMoveLabel.Position = UDim2.new(0, 0, 0, 114)
oppMoveLabel.BackgroundTransparency = 1
oppMoveLabel.Text = "Opponent: ---"
oppMoveLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
oppMoveLabel.TextSize = 13
oppMoveLabel.Font = Enum.Font.GothamBold
oppMoveLabel.TextXAlignment = Enum.TextXAlignment.Left
oppMoveLabel.Visible = false
oppMoveLabel.Parent = contentFrame

-- Depth Label
local depthLabel = Instance.new("TextLabel")
depthLabel.Size = UDim2.new(1, 0, 0, 20)
depthLabel.Position = UDim2.new(0, 0, 0, 140)
depthLabel.BackgroundTransparency = 1
depthLabel.Text = "Depth: ---"
depthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
depthLabel.TextSize = 12
depthLabel.Font = Enum.Font.Gotham
depthLabel.TextXAlignment = Enum.TextXAlignment.Left
depthLabel.Visible = false
depthLabel.Parent = contentFrame

-- Score Label
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Size = UDim2.new(1, 0, 0, 20)
scoreLabel.Position = UDim2.new(0, 0, 0, 160)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Text = "Evaluation: ---"
scoreLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
scoreLabel.TextSize = 12
scoreLabel.Font = Enum.Font.Gotham
scoreLabel.TextXAlignment = Enum.TextXAlignment.Left
scoreLabel.Visible = false
scoreLabel.Parent = contentFrame

-- Mate Alert
local mateAlert = Instance.new("Frame")
mateAlert.Size = UDim2.new(1, 0, 0, 50)
mateAlert.Position = UDim2.new(0, 0, 0, 185)
mateAlert.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
mateAlert.BorderSizePixel = 0
mateAlert.Visible = false
mateAlert.Parent = contentFrame

local mateCorner = Instance.new("UICorner")
mateCorner.CornerRadius = UDim.new(0, 8)
mateCorner.Parent = mateAlert

local mateText = Instance.new("TextLabel")
mateText.Size = UDim2.new(1, -20, 1, -10)
mateText.Position = UDim2.new(0, 10, 0, 5)
mateText.BackgroundTransparency = 1
mateText.Text = "MATE IN 3"
mateText.TextColor3 = Color3.fromRGB(255, 255, 255)
mateText.TextSize = 14
mateText.Font = Enum.Font.GothamBold
mateText.TextXAlignment = Enum.TextXAlignment.Center
mateText.TextYAlignment = Enum.TextYAlignment.Center
mateText.Parent = mateAlert

-- AutoPlay Button
local autoPlayBtn = Instance.new("TextButton")
autoPlayBtn.Size = UDim2.new(1, 0, 0, 40)
autoPlayBtn.Position = UDim2.new(0, 0, 0, 240)
autoPlayBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
autoPlayBtn.Text = "AutoPlay: OFF"
autoPlayBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoPlayBtn.TextSize = 15
autoPlayBtn.Font = Enum.Font.GothamBold
autoPlayBtn.Parent = contentFrame

local autoPlayCorner = Instance.new("UICorner")
autoPlayCorner.CornerRadius = UDim.new(0, 8)
autoPlayCorner.Parent = autoPlayBtn

-- Funcionalidade minimize
local isMinimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame:TweenSize(UDim2.new(0, 420, 0, 40), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        minimizeBtn.Text = "+"
        contentFrame.Visible = false
        evalBarContainer.Visible = false
    else
        mainFrame:TweenSize(UDim2.new(0, 420, 0, 335), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        minimizeBtn.Text = "−"
        contentFrame.Visible = true
        evalBarContainer.Visible = true
    end
end)

-- Funcionalidade unload
unloadBtn.MouseButton1Click:Connect(function()
    print("[UNLOAD] Unloading Chess Bot...")
    screenGui:Destroy()
    script:Destroy()
    print("[UNLOAD] Bot removed!")
end)

-- Funcionalidade AutoPlay
autoPlayBtn.MouseButton1Click:Connect(function()
    autoPlayEnabled = not autoPlayEnabled
    if autoPlayEnabled then
        autoPlayBtn.Text = "AutoPlay: ON"
        autoPlayBtn.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
    else
        autoPlayBtn.Text = "AutoPlay: OFF"
        autoPlayBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
    end
end)

-- ========================================
-- FUNÇÕES DE ATUALIZAÇÃO DA UI
-- ========================================

function updateGameStatus(inGame, team)
    if inGame then
        local color = team == "w" and "White" or "Black"
        local teamName = team == "w" and "White" or "Black"
        gameStatusLabel.Text = "In game (" .. teamName .. ")"
        gameStatusLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
    else
        gameStatusLabel.Text = "Waiting for active game"
        gameStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    end
end

function updateStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color
end

function updateMove(move)
    moveLabel.Text = "Move: " .. (move or "---")
end

function updateDepth(depth)
    if depth then
        depthLabel.Text = "Depth: " .. tostring(depth)
        depthLabel.Visible = true
    else
        depthLabel.Visible = false
    end
end

function updateScore(score, mateIn)
    -- Esta função agora NÃO atualiza mais a eval bar
    -- Apenas mostra informações de mate no alert

    if mateIn then
        scoreLabel.Text = "MATE in " .. tostring(math.abs(mateIn))
        scoreLabel.Visible = true

        mateAlert.Visible = true
        mateText.Text = "MATE IN " .. tostring(math.abs(mateIn))

        if mateIn > 0 then
            mateAlert.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
        else
            mateAlert.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
        end
    else
        mateAlert.Visible = false
        if score then
            local eval = score / 100
            scoreLabel.Text = "Evaluation: " .. string.format("%+.2f", eval)
            scoreLabel.Visible = true
        else
            scoreLabel.Visible = false
        end
    end
end

function updateEvalBar(eval)
    -- Removida - não é mais usada
    -- A eval bar agora é atualizada APENAS pela porta 3001
end

-- ========================================
-- FUNÇÕES DE CLASSIFICAÇÃO DE MOVIMENTO
-- ========================================

function classifyMove(evalDiff)
    -- evalDiff = avaliação anterior - avaliação atual
    -- Positivo = melhorou, Negativo = piorou

    if evalDiff <= -2.0 then
        return "BLUNDER X", Color3.fromRGB(236, 99, 99)
    elseif evalDiff <= -1.5 then
        return "MISTAKE", Color3.fromRGB(255, 136, 77)
    elseif evalDiff <= -0.5 then
        return "INACCURACY", Color3.fromRGB(255, 204, 92)
    elseif evalDiff <= 1.0 then
        return "GOOD", Color3.fromRGB(162, 210, 145)
    elseif evalDiff <= 1.5 then
        return "EXCELLENT", Color3.fromRGB(107, 185, 146)
    elseif evalDiff <= 2.5 then
        return "GREAT MOVE !", Color3.fromRGB(67, 160, 230)
    else
        return "BRILLIANT !!", Color3.fromRGB(26, 188, 156)
    end
end

function updateYourMoveClassification(currentEval)
    if not lastEvalScore then
        yourMoveLabel.Visible = false
        return
    end

    -- Você acabou de jogar, calcula diferença
    local evalDiff = lastEvalScore - currentEval

    local classification, color = classifyMove(evalDiff)

    yourMoveLabel.Text = "You: " .. classification
    yourMoveLabel.TextColor3 = color
    yourMoveLabel.Visible = true
end

function updateOppMoveClassification(currentEval)
    if not lastEvalScore then
        oppMoveLabel.Visible = false
        return
    end

    -- Adversário acabou de jogar, calcula diferença
    local evalDiff = lastEvalScore - currentEval

    local classification, color = classifyMove(evalDiff)

    oppMoveLabel.Text = "Opponent: " .. classification
    oppMoveLabel.TextColor3 = color
    oppMoveLabel.Visible = true
end

-- ========================================
-- FUNÇÕES DE AVALIAÇÃO CONTÍNUA
-- ========================================

function updateEvalBarContinuous()
    local valid, result = isInValidGame()

    if not valid then
        -- Reset da barra quando não está em jogo
        whiteBar:TweenSize(UDim2.new(1, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        evalText.Text = "0.0"
        currentTable = nil
        lastEvalScore = nil
        yourMoveLabel.Visible = false
        oppMoveLabel.Visible = false
        return
    end

    local chessTable = result
    currentTable = chessTable
    local fen = chessTable.FEN.Value

    -- Evita re-análise do mesmo FEN
    if fen == lastEvalFEN then
        return
    end

    lastEvalFEN = fen

    -- Verifica se é SUA vez ou do ADVERSÁRIO
    local isMyTurn = isPlayerTurn(chessTable)

    -- Pega sua cor
    local myTeam = getLocalTeam(chessTable)

    -- Faz request para o servidor de avaliação (porta 3001)
    local success, res = pcall(function()
        return request({
            Url = "http://localhost:3001/api/evaluate?fen=" .. HttpService:UrlEncode(fen),
            Method = "GET"
        })
    end)

    if not success then
        return
    end

    local parseSuccess, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)

    if not parseSuccess then
        return
    end

    -- Atualiza a eval bar
    if data.score then
        local currentEval = nil

        if data.score.unit == "mate" then
            local mateIn = data.score.value

            -- Se é a vez do ADVERSÁRIO, inverte o sinal
            if not isMyTurn then
                mateIn = -mateIn
            end

            -- Converte mate para valor equivalente
            currentEval = mateIn > 0 and 100 or -100

            -- Determina qual barra cresce baseado na SUA COR
            if myTeam == "w" then
                -- Você é BRANCO - barra branca representa você
                if mateIn > 0 then
                    whiteBar:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
                else
                    whiteBar:TweenSize(UDim2.new(1, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
                end
            else
                -- Você é PRETO - barra preta representa você (inverte)
                if mateIn > 0 then
                    whiteBar:TweenSize(UDim2.new(1, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
                else
                    whiteBar:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
                end
            end

            evalText.Text = "M" .. tostring(math.abs(mateIn))
        else
            -- Score em centipawns
            local eval = data.score.value / 100

            -- Se é a vez do ADVERSÁRIO, inverte o sinal
            if not isMyTurn then
                eval = -eval
            end

            currentEval = eval

            -- Limita entre -10 e +10
            local clampedEval = math.clamp(eval, -10, 10)

            -- Converte para porcentagem baseado na SUA COR
            local percentage
            if myTeam == "w" then
                -- Você é BRANCO - positivo = barra branca cresce
                percentage = (clampedEval + 10) / 20
            else
                -- Você é PRETO - positivo = barra preta cresce (inverte)
                percentage = (-clampedEval + 10) / 20
            end

            -- Anima a barra
            whiteBar:TweenSize(
                UDim2.new(1, 0, percentage, 0),
                Enum.EasingDirection.Out,
                Enum.EasingStyle.Quad,
                0.3,
                true
            )

            -- Texto sempre mostra do SEU ponto de vista
            if math.abs(eval) < 0.05 then
                evalText.Text = "0.0"
            else
                evalText.Text = string.format("%+.1f", eval)
            end

            evalText.TextColor3 = Color3.fromRGB(200, 200, 200)
        end

        -- Classifica movimentos de ambos os jogadores
        if lastEvalScore and currentEval then
            if isMyTurn then
                -- Adversário acabou de jogar
                updateOppMoveClassification(currentEval)
            else
                -- Você acabou de jogar
                updateYourMoveClassification(currentEval)
            end
        end

        -- Sempre salva a avaliação atual para próxima comparação
        lastEvalScore = currentEval
    end
end

-- ========================================
-- LÓGICA PRINCIPAL DO JOGO
-- ========================================

function runGame()
    local valid, result = isInValidGame()

    if not valid then
        updateStatus(result, Color3.fromRGB(255, 200, 100))
        return false
    end

    local chessTable = result
    currentTable = chessTable

    if not isPlayerTurn(chessTable) then
        updateStatus("Not your turn", Color3.fromRGB(255, 200, 100))
        return false
    end

    local fen = chessTable.FEN.Value

    -- Evita re-análise da mesma posição
    if fen == lastFEN then
        return false
    end

    updateStatus("Analyzing...", Color3.fromRGB(100, 150, 255))

    local success, res = pcall(function()
        return request({
            Url = "http://localhost:3000/api/analyze?fen=" .. HttpService:UrlEncode(fen) .. "&depth=" .. analysisDepth,
            Method = "GET"
        })
    end)

    if not success then
        updateStatus("Connection error", Color3.fromRGB(255, 100, 100))
        return false
    end

    -- Parse da resposta JSON
    local parseSuccess, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)

    if not parseSuccess then
        updateStatus("Parsing error", Color3.fromRGB(255, 100, 100))
        print("[DEBUG] Server response:", res.Body)
        return false
    end

    local move = data.bestmove

    if not move then
        updateStatus("Move not found", Color3.fromRGB(255, 100, 100))
        return false
    end

    -- Remove promoção se houver (5 caracteres)
    if string.len(move) == 5 then
        move = string.sub(move, 1, 4)
    end

    if string.len(move) ~= 4 then
        updateStatus("Invalid move", Color3.fromRGB(255, 100, 100))
        return false
    end

    -- Atualiza UI
    updateMove(move)
    updateDepth(data.depth)

    -- Detecta mate
    local mateIn = nil
    if data.score and data.score.unit == "mate" then
        mateIn = data.score.value
    end
    updateScore(data.score and data.score.value, mateIn)

    -- Marca FEN atual antes de enviar movimento
    lastFEN = fen
    lastEvalFEN = fen -- Sincroniza com eval bar para evitar flickering

    -- Envia movimento
    local remote = ReplicatedStorage.Chess.SubmitMove
    local submitSuccess, submitResult = pcall(function()
        return remote:InvokeServer(move)
    end)

    if submitSuccess and submitResult then
        updateStatus("Move executed: " .. move, Color3.fromRGB(100, 255, 150))

        -- Aguarda um pouco para o tabuleiro atualizar
        wait(0.3)

        -- Força atualização da eval bar com novo FEN
        if currentTable and currentTable:FindFirstChild("FEN") then
            lastEvalFEN = currentTable.FEN.Value
        end

        return true
    else
        updateStatus("Failed to execute", Color3.fromRGB(255, 100, 100))
        return false
    end
end

-- ========================================
-- LOOPS DE MONITORAMENTO
-- ========================================

-- Monitor de status do jogo
spawn(function()
    while wait(1) do
        local valid, result = isInValidGame()

        if valid then
            local chessTable = result
            local team = getLocalTeam(chessTable)
            updateGameStatus(true, team)
        else
            updateGameStatus(false, nil)
            updateStatus("Waiting for game", Color3.fromRGB(200, 200, 200))
            lastFEN = nil
            lastEvalFEN = nil
        end
    end
end)

-- Loop de avaliação contínua (eval bar)
spawn(function()
    while wait(0.5) do -- Atualiza a cada 0.5 segundos
        updateEvalBarContinuous()
    end
end)

-- AutoPlay loop
spawn(function()
    while wait(0.5) do
        if autoPlayEnabled and not isRunning then
            local valid, result = isInValidGame()
            if valid then
                local chessTable = result
                if isPlayerTurn(chessTable) then
                    isRunning = true
                    runGame()
                    wait(1)
                    isRunning = false
                end
            end
        end
    end
end)

-- Bind de tecla E
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.E then
        if not isRunning then
            isRunning = true
            runGame()
            wait(0.5)
            isRunning = false
        end
    end
end)

print("========================================")
print("Chess Bot LOADED!")
print("Press E to play")
print("Waiting for active game (IsGameActive = true)")
print("========================================")
