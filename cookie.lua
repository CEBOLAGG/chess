
local HttpService = game:GetService("HttpService")
local plr = game:GetService("Players").LocalPlayer
local scriptPath = plr.PlayerGui:WaitForChild("Client")

print("[INIT] Chess Bot Assistant - Iniciando...")

local pieces = {
	["Pawn"] = "p",
	["Knight"] = "n",
	["Bishop"] = "b",
	["Rook"] = "r",
	["Queen"] = "q",
	["King"] = "k"
}

-- Desativa error logger
if game:GetService("ReplicatedStorage").Connections:FindFirstChild("ReportClientError") then
    game:GetService("ReplicatedStorage").Connections.ReportClientError:Destroy()
    for _,v in pairs(getconnections(game:GetService("ScriptContext").Error)) do
        v:Disable()
    end
end

-- Procura client
local client = nil
for _,v in pairs(getreg()) do
    if type(v) == "function" then
        for _, v in pairs(getupvalues(v)) do
            if type(v) == "table" and v.processRound then
                client = v
            end
        end
    end
end
assert(client, "failed to find client")

print("[INIT] Client encontrado!")

-- ========================================
-- FUNÇÕES AUXILIARES
-- ========================================

-- Função para pintar uma casa (funciona com BasePart E Model)
local function paintTile(tile, color)
    if not tile then return 0 end
    
    local partsPainted = 0
    
    if tile:IsA("BasePart") then
        -- Casa é uma Part normal
        pcall(function()
            tile.Color = color
            partsPainted = 1
        end)
    elseif tile:IsA("Model") then
        -- Casa é um Model (skin customizada)
        -- Pinta TODOS os BaseParts dentro do Model
        for _, child in pairs(tile:GetChildren()) do
            pcall(function()
                if child:IsA("BasePart") then
                    child.Color = color
                    partsPainted = partsPainted + 1
                end
            end)
        end
        
        for _, descendant in pairs(tile:GetDescendants()) do
            pcall(function()
                if descendant:IsA("BasePart") then
                    descendant.Color = color
                end
            end)
        end
    end
    
    return partsPainted
end

-- Board from client
function getBoard()
    for _,v in pairs(debug.getupvalues(client.processRound)) do
        if type(v) == "table" and v.tiles then
            return v
        end
    end
    return nil
end

-- Gets client's team (white/black)
function getLocalTeam(board)
    if board.players[false] == plr and board.players[true] == plr then
        return "w"
    end
    
    for i, v in pairs(board.players) do
        if v == plr then
            if i then
                return "w"
            else
                return "b"
            end
        end
    end
    return nil
end

function willCauseDesync(board)
    if board.players[false] == plr and board.players[true] == plr then
        return board.activeTeam == false
    end

    for i,v in pairs(board.players) do
        if v == plr then
            return not (board.activeTeam == i)
        end
    end
    return true
end

-- Converts board table to sensible format
function createBoard(board)
    local newBoard = {}
    for _,v in pairs(board.whitePieces) do
        if v and v.position then
            local x, y = v.position[1], v.position[2]
            if not newBoard[x] then
                newBoard[x] = {}
            end
            newBoard[x][y] = string.upper(pieces[v.object.Name])
        end
    end
    for _,v in pairs(board.blackPieces) do
        if v and v.position then
            local x, y = v.position[1], v.position[2]
            if not newBoard[x] then
                newBoard[x] = {}
            end
            newBoard[x][y] = pieces[v.object.Name]
        end
    end
    return newBoard
end

-- Board to FEN encoding
function board2fen(board, forceColor)
    local result = ""
    local boardPieces = createBoard(board)
    for y = 8, 1, -1 do
        local empty = 0
        for x = 8, 1, -1 do
            if not boardPieces[x] then boardPieces[x] = {} end
            local piece = boardPieces[x][y]
            if piece then
                if empty > 0 then
                    result = result .. tostring(empty)
                    empty = 0
                end
                result = result .. piece
            else
                empty += 1
            end
        end
        if empty > 0 then
            result = result .. tostring(empty)
        end
        if not (y == 1) then
            result = result .. "/"
        end
    end
    
    -- Se forceColor for especificado, usa ele. Senão usa getLocalTeam
    if forceColor then
        result = result .. " " .. forceColor
    else
        result = result .. " " .. getLocalTeam(board)
    end
    
    return result
end

-- Limpa cores do tabuleiro
function clearBoardColors()
    pcall(function()
        if not workspace:FindFirstChild("Board") then return end
        
        for _, tile in pairs(workspace.Board:GetChildren()) do
            pcall(function()
                local coords = string.split(tile.Name, ",")
                if coords and #coords == 2 then
                    local x = tonumber(coords[1])
                    local y = tonumber(coords[2])
                    
                    if x and y then
                        local defaultColor
                        if (x + y) % 2 == 0 then
                            defaultColor = Color3.fromRGB(240, 217, 181)
                        else
                            defaultColor = Color3.fromRGB(181, 136, 99)
                        end
                        
                        paintTile(tile, defaultColor)
                    end
                end
            end)
        end
    end)
end

-- Destaca movimento
function highlightMove(fromSquare, toSquare)
    clearBoardColors()
    
    pcall(function()
        if not workspace:FindFirstChild("Board") then return end
        
        local fromTile = workspace.Board:FindFirstChild(fromSquare)
        if fromTile then
            paintTile(fromTile, Color3.fromRGB(128, 0, 128)) -- Roxo
        end
        
        local toTile = workspace.Board:FindFirstChild(toSquare)
        if toTile then
            paintTile(toTile, Color3.fromRGB(0, 255, 0)) -- Verde
        end
    end)
end

-- Destaca movimento do oponente (vermelho)
function highlightOpponentMove(fromSquare, toSquare)
    clearBoardColors()
    
    pcall(function()
        if not workspace:FindFirstChild("Board") then return end
        
        local fromTile = workspace.Board:FindFirstChild(fromSquare)
        if fromTile then
            paintTile(fromTile, Color3.fromRGB(200, 0, 0)) -- Vermelho escuro
        end
        
        local toTile = workspace.Board:FindFirstChild(toSquare)
        if toTile then
            paintTile(toTile, Color3.fromRGB(255, 50, 50)) -- Vermelho claro
        end
    end)
end

-- Converte notação algébrica para workspace
function convertToWorkspaceNotation(algebraic)
    local chars = {}
    for c in algebraic:gmatch(".") do
	    table.insert(chars, c)
    end
    
    local x = 9 - (string.byte(chars[1]) - 96)
    local y = tonumber(chars[2])
    
    return tostring(x) .. "," .. tostring(y)
end

-- Gera hash do tabuleiro
function getBoardHash(board)
    return board2fen(board)
end

-- ========================================
-- UI
-- ========================================

print("[INIT] Criando UI...")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChessAssistantUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = plr.PlayerGui

-- Frame principal
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 260)
mainFrame.Position = UDim2.new(0.5, -175, 0.3, -125)
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
title.Name = "Title"
title.Size = UDim2.new(1, -110, 1, 0)
title.Position = UDim2.new(0, 15, 0, 0)
title.BackgroundTransparency = 1
title.Text = "♟️ Chess Assistant"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- Botão toggle opponent move
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleBtn"
toggleBtn.Size = UDim2.new(0, 30, 0, 30)
toggleBtn.Position = UDim2.new(1, -105, 0, 5)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
toggleBtn.Text = "👁"
toggleBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
toggleBtn.TextSize = 16
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Parent = header

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleBtn

-- Botão minimize
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name = "MinimizeBtn"
minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
minimizeBtn.Position = UDim2.new(1, -70, 0, 5)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 20
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.Parent = header

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = minimizeBtn

-- Botão unload
local unloadBtn = Instance.new("TextButton")
unloadBtn.Name = "UnloadBtn"
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

-- Barra de Avaliação
local evalBarContainer = Instance.new("Frame")
evalBarContainer.Name = "EvalBarContainer"
evalBarContainer.Size = UDim2.new(0, 20, 1, -50)
evalBarContainer.Position = UDim2.new(0, 10, 0, 45)
evalBarContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
evalBarContainer.BorderSizePixel = 0
evalBarContainer.ClipsDescendants = true
evalBarContainer.Parent = mainFrame

local evalBarCorner = Instance.new("UICorner")
evalBarCorner.CornerRadius = UDim.new(0, 4)
evalBarCorner.Parent = evalBarContainer

-- Parte branca da barra
local whiteBar = Instance.new("Frame")
whiteBar.Name = "WhiteBar"
whiteBar.Size = UDim2.new(1, 0, 0.5, 0)
whiteBar.Position = UDim2.new(0, 0, 1, 0)
whiteBar.AnchorPoint = Vector2.new(0, 1)
whiteBar.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
whiteBar.BorderSizePixel = 0
whiteBar.Parent = evalBarContainer

-- Linha central
local centerLine = Instance.new("Frame")
centerLine.Name = "CenterLine"
centerLine.Size = UDim2.new(1, 0, 0, 2)
centerLine.Position = UDim2.new(0, 0, 0.5, -1)
centerLine.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
centerLine.BorderSizePixel = 0
centerLine.ZIndex = 2
centerLine.Parent = evalBarContainer

-- Content Frame
local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, -60, 1, -50)
contentFrame.Position = UDim2.new(0, 40, 0, 45)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

-- Status Label
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, 0, 0, 25)
statusLabel.Position = UDim2.new(0, 0, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "🟢 Aguardando turno..."
statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
statusLabel.TextSize = 14
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = contentFrame

-- Move Label
local moveLabel = Instance.new("TextLabel")
moveLabel.Name = "Move"
moveLabel.Size = UDim2.new(1, 0, 0, 30)
moveLabel.Position = UDim2.new(0, 0, 0, 30)
moveLabel.BackgroundTransparency = 1
moveLabel.Text = "Movimento: ---"
moveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
moveLabel.TextSize = 16
moveLabel.Font = Enum.Font.GothamBold
moveLabel.TextXAlignment = Enum.TextXAlignment.Left
moveLabel.Parent = contentFrame

-- Promotion Label (aparece quando há promoção)
local promotionLabel = Instance.new("TextLabel")
promotionLabel.Name = "Promotion"
promotionLabel.Size = UDim2.new(1, 0, 0, 25)
promotionLabel.Position = UDim2.new(0, 0, 0, 60)
promotionLabel.BackgroundTransparency = 1
promotionLabel.Text = "🔄 Promover para: RAINHA"
promotionLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
promotionLabel.TextSize = 14
promotionLabel.Font = Enum.Font.GothamBold
promotionLabel.TextXAlignment = Enum.TextXAlignment.Left
promotionLabel.Visible = false
promotionLabel.Parent = contentFrame

-- Depth Label
local depthLabel = Instance.new("TextLabel")
depthLabel.Name = "Depth"
depthLabel.Size = UDim2.new(1, 0, 0, 20)
depthLabel.Position = UDim2.new(0, 0, 0, 90)
depthLabel.BackgroundTransparency = 1
depthLabel.Text = "Profundidade: --"
depthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
depthLabel.TextSize = 12
depthLabel.Font = Enum.Font.Gotham
depthLabel.TextXAlignment = Enum.TextXAlignment.Left
depthLabel.Visible = false
depthLabel.Parent = contentFrame

-- Nodes Label
local nodesLabel = Instance.new("TextLabel")
nodesLabel.Name = "Nodes"
nodesLabel.Size = UDim2.new(1, 0, 0, 20)
nodesLabel.Position = UDim2.new(0, 0, 0, 110)
nodesLabel.BackgroundTransparency = 1
depthLabel.Text = "Nós analisados: --"
nodesLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
nodesLabel.TextSize = 12
nodesLabel.Font = Enum.Font.Gotham
nodesLabel.TextXAlignment = Enum.TextXAlignment.Left
nodesLabel.Visible = false
nodesLabel.Parent = contentFrame

-- Score Label
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Name = "Score"
scoreLabel.Size = UDim2.new(1, 0, 0, 20)
scoreLabel.Position = UDim2.new(0, 0, 0, 130)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Text = "Avaliação: --"
scoreLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
scoreLabel.TextSize = 12
scoreLabel.Font = Enum.Font.Gotham
scoreLabel.TextXAlignment = Enum.TextXAlignment.Left
scoreLabel.Visible = false
scoreLabel.Parent = contentFrame

-- Mate Alert
local mateAlert = Instance.new("Frame")
mateAlert.Name = "MateAlert"
mateAlert.Size = UDim2.new(1, 0, 0, 50)
mateAlert.Position = UDim2.new(0, 0, 0, 155)
mateAlert.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
mateAlert.BorderSizePixel = 0
mateAlert.Visible = false
mateAlert.Parent = contentFrame

local mateCorner = Instance.new("UICorner")
mateCorner.CornerRadius = UDim.new(0, 8)
mateCorner.Parent = mateAlert

local mateText = Instance.new("TextLabel")
mateText.Name = "MateText"
mateText.Size = UDim2.new(1, -20, 1, -10)
mateText.Position = UDim2.new(0, 10, 0, 5)
mateText.BackgroundTransparency = 1
mateText.Text = "MATE EM 3"
mateText.TextColor3 = Color3.fromRGB(255, 255, 255)
mateText.TextSize = 14
mateText.Font = Enum.Font.GothamBold
mateText.TextWrapped = true
mateText.TextXAlignment = Enum.TextXAlignment.Center
mateText.TextYAlignment = Enum.TextYAlignment.Center
mateText.Parent = mateAlert

-- Funcionalidade minimize
local isMinimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame:TweenSize(UDim2.new(0, 350, 0, 40), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        minimizeBtn.Text = "+"
        contentFrame.Visible = false
        evalBarContainer.Visible = false
    else
        mainFrame:TweenSize(UDim2.new(0, 350, 0, 250), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        minimizeBtn.Text = "−"
        contentFrame.Visible = true
        evalBarContainer.Visible = true
    end
end)

-- Funcionalidade toggle opponent move
local showOpponentMove = false
toggleBtn.MouseButton1Click:Connect(function()
    showOpponentMove = not showOpponentMove
    
    if showOpponentMove then
        toggleBtn.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
        toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        print("[TOGGLE] Mostrar movimento do oponente: ATIVADO")
    else
        toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        toggleBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
        clearBoardColors()
        print("[TOGGLE] Mostrar movimento do oponente: DESATIVADO")
    end
end)

-- Funcionalidade unload
unloadBtn.MouseButton1Click:Connect(function()
    print("[UNLOAD] Descarregando Chess Bot Assistant...")
    
    -- Limpa cores do tabuleiro
    clearBoardColors()
    
    -- Remove UI
    screenGui:Destroy()
    
    -- Remove script
    script:Destroy()
    
    print("[UNLOAD] Script removido com sucesso!")
end)

-- Formata números
local function formatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end

-- Atualiza barra de avaliação
local function updateEvalBar(score, mateInfo, playerColor)
    if not score then
        whiteBar:TweenSize(UDim2.new(1, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        return
    end
    
    -- Se houver mate detectado, mostra barra completa
    if mateInfo and mateInfo.isMate then
        -- Determina se VOCÊ está ganhando baseado na sua cor
        local youAreWinning = false
        
        if playerColor == "w" and mateInfo.mateForWhite then
            youAreWinning = true  -- Você é brancas e brancas ganham
        elseif playerColor == "b" and not mateInfo.mateForWhite then
            youAreWinning = true  -- Você é pretas e pretas ganham
        end
        
        if youAreWinning then
            -- VOCÊ está ganhando
            if playerColor == "w" then
                -- Você é brancas = barra 100% branca
                whiteBar:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.5, true)
            else
                -- Você é pretas = barra 0% branca (100% preta)
                whiteBar:TweenSize(UDim2.new(1, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.5, true)
            end
        else
            -- OPONENTE está ganhando
            if playerColor == "w" then
                -- Você é brancas, oponente (pretas) ganha = barra 0% branca
                whiteBar:TweenSize(UDim2.new(1, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.5, true)
            else
                -- Você é pretas, oponente (brancas) ganha = barra 100% branca
                whiteBar:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.5, true)
            end
        end
        return
    end
    
    local evaluation = 0
    
    if type(score) == "table" then
        if score.unit == "cp" then
            evaluation = score.value / 100
        elseif score.unit == "mate" then
            if score.value > 0 then
                evaluation = 10
            else
                evaluation = -10
            end
        end
    end
    
    -- IMPORTANTE: Inverte avaliação se você joga de pretas
    if playerColor == "b" then
        evaluation = -evaluation
    end
    
    evaluation = math.max(-10, math.min(10, evaluation))
    local whiteHeight = 0.5 + (evaluation / 20 * 0.5)
    whiteHeight = math.max(0.05, math.min(0.95, whiteHeight))
    
    whiteBar:TweenSize(UDim2.new(1, 0, whiteHeight, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
end

-- Atualiza UI
local function updateUI(data)
    if data.status then
        statusLabel.Text = data.status
        statusLabel.TextColor3 = data.statusColor or Color3.fromRGB(255, 255, 255)
    end
    
    if data.move then
        moveLabel.Text = "Movimento: " .. data.move
    end
    
    if data.promotion then
        promotionLabel.Text = data.promotion
        promotionLabel.Visible = true
    else
        promotionLabel.Visible = false
    end
    
    if data.depth then
        depthLabel.Text = "Profundidade: " .. tostring(data.depth)
        depthLabel.Visible = true
    end
    
    if data.nodes then
        nodesLabel.Text = "Nós analisados: " .. formatNumber(data.nodes)
        nodesLabel.Visible = true
    end
    
    if data.score then
        local scoreText = "Avaliação: "
        if type(data.score) == "table" then
            if data.score.unit == "cp" then
                local eval = data.score.value / 100
                scoreText = scoreText .. string.format("%+.2f", eval)
            elseif data.score.unit == "mate" then
                local mateValue = math.abs(data.score.value)
                scoreText = "MATE em " .. tostring(mateValue)
            end
        else
            scoreText = scoreText .. tostring(data.score)
        end
        scoreLabel.Text = scoreText
        scoreLabel.Visible = true
        
        -- Passa mateInfo E playerColor para updateEvalBar
        local mateInfo = nil
        if data.mate and data.mate.isMate then
            mateInfo = {
                isMate = true,
                mateForWhite = data.mate.mateForWhite or (data.score.unit == "mate" and data.score.value > 0)
            }
        end
        updateEvalBar(data.score, mateInfo, data.playerColor)
    end
    
    if data.mate then
        mateAlert.Visible = true
        mateText.Text = data.mateMessage or "MATE DETECTADO!"
        if data.mate.isWinning then
            mateAlert.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
        else
            mateAlert.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
        end
    else
        mateAlert.Visible = false
    end
    
    if data.clearData then
        depthLabel.Visible = false
        nodesLabel.Visible = false
        scoreLabel.Visible = false
        mateAlert.Visible = false
        promotionLabel.Visible = false
        updateEvalBar(nil, nil, nil)
    end
end

print("[INIT] UI criada!")

-- ========================================
-- GAME LOGIC
-- ========================================

function runGame()
    local board = getBoard()
    
    if willCauseDesync(board) then
        return false
    end

    updateUI({
        status = "🔄 Analisando...",
        statusColor = Color3.fromRGB(255, 200, 0)
    })

    local res = request({
        Url = "http://localhost:3000/api/analyze?fen=" .. HttpService:UrlEncode(board2fen(board)),
        Method = "GET"
    })
    
    local success, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)
    
    if not success then
        local result = res.Body
        if string.len(result) > 4 then
            error(result)
        end
        
        local fromSquare = string.sub(result, 1, 2)
        local toSquare = string.sub(result, 3, 4)
        local fromWorkspace = convertToWorkspaceNotation(fromSquare)
        local toWorkspace = convertToWorkspaceNotation(toSquare)
        
        highlightMove(fromWorkspace, toWorkspace)
        
        updateUI({
            status = "✅ Movimento pronto!",
            statusColor = Color3.fromRGB(100, 255, 100),
            move = fromWorkspace .. " → " .. toWorkspace,
            playerColor = getLocalTeam(board)
        })
        
        return true
    end
    
    local bestmove = data.bestmove
    
    -- Detecta promoção de peão (movimento tem 5 caracteres: e7e8q)
    local isPromotion = string.len(bestmove) == 5
    local promotionPiece = nil
    local promotionText = nil
    
    if isPromotion then
        -- Pega a letra da promoção
        local promotionChar = string.sub(bestmove, 5, 5)
        
        -- Mapeia para nome da peça
        local promotionMap = {
            ["q"] = "RAINHA ♛",
            ["r"] = "TORRE ♜",
            ["b"] = "BISPO ♝",
            ["n"] = "CAVALO ♞"
        }
        
        promotionPiece = promotionMap[promotionChar] or "RAINHA ♛"
        promotionText = "🔄 Promover para: " .. promotionPiece
        
        -- Remove o caractere de promoção para não dar erro
        bestmove = string.sub(bestmove, 1, 4)
    end
    
    local fromSquare = string.sub(bestmove, 1, 2)
    local toSquare = string.sub(bestmove, 3, 4)
    local fromWorkspace = convertToWorkspaceNotation(fromSquare)
    local toWorkspace = convertToWorkspaceNotation(toSquare)
    
    highlightMove(fromWorkspace, toWorkspace)
    
    local mateData = nil
    if data.mate and data.mate.isMate then
        local isWinning = data.mate.mateForWhite and getLocalTeam(board) == "w" or 
                          not data.mate.mateForWhite and getLocalTeam(board) == "b"
        
        local simpleMateMessage = "MATE EM " .. tostring(data.mate.movesToMate)
        
        mateData = {
            isWinning = isWinning,
            mateMessage = simpleMateMessage,
            isMate = true,
            mateForWhite = data.mate.mateForWhite
        }
    end
    
    updateUI({
        status = "✅ Movimento pronto!",
        statusColor = Color3.fromRGB(100, 255, 100),
        move = fromWorkspace .. " → " .. toWorkspace,
        promotion = promotionText,
        depth = data.depth,
        nodes = data.nodes,
        score = data.score,
        mate = mateData,
        playerColor = getLocalTeam(board)
    })
    
    return true
end

-- Detecta turno
function isMyTurn()
    local gameStatus = plr.PlayerGui:FindFirstChild("GameStatus")
    if not gameStatus then return false end
    
    local whiteInfo = gameStatus:FindFirstChild("White")
    local blackInfo = gameStatus:FindFirstChild("Black")
    
    if not whiteInfo or not blackInfo then return false end
    
    local whiteInfoText = whiteInfo:FindFirstChild("Info")
    local blackInfoText = blackInfo:FindFirstChild("Info")
    
    if not whiteInfoText or not blackInfoText then return false end
    
    local playerName = plr.Name
    
    if whiteInfo.Visible and string.find(whiteInfoText.Text, playerName) then
        return true
    end
    
    if blackInfo.Visible and string.find(blackInfoText.Text, playerName) then
        return true
    end
    
    return false
end

-- Loop principal
local isRunning = false
local lastBoardState = nil
local lastOpponentBoardState = nil

spawn(function()
    print("[LOOP] Loop iniciado")
    while wait(0.5) do
        if isMyTurn() and not isRunning then
            local board = getBoard()
            if not board then
                wait(0.5)
                continue
            end
            
            local currentBoardHash = getBoardHash(board)
            
            if currentBoardHash == lastBoardState then
                continue
            end
            
            isRunning = true
            lastBoardState = currentBoardHash
            
            local success, err = pcall(function()
                if runGame() then
                    -- Sucesso
                else
                    updateUI({
                        status = "⚠️ Não é possível executar agora",
                        statusColor = Color3.fromRGB(255, 100, 100)
                    })
                end
            end)
            
            if not success then
                updateUI({
                    status = "❌ Erro",
                    statusColor = Color3.fromRGB(255, 0, 0)
                })
            end
            
            wait(2)
            isRunning = false
        else
            -- Não é meu turno
            if not isMyTurn() then
                lastBoardState = nil
                
                -- Se toggle está ativo, mostra movimento do oponente
                if showOpponentMove and not isRunning then
                    local board = getBoard()
                    if board then
                        local currentOpponentHash = getBoardHash(board)
                        
                        if currentOpponentHash ~= lastOpponentBoardState then
                            lastOpponentBoardState = currentOpponentHash
                            
                            isRunning = true
                            pcall(function()
                                -- Determina a cor do oponente
                                local myTeam = getLocalTeam(board)
                                local opponentTeam = myTeam == "w" and "b" or "w"
                                
                                -- Faz request para análise DO PONTO DE VISTA DO OPONENTE
                                local res = request({
                                    Url = "http://localhost:3000/api/analyze?fen=" .. HttpService:UrlEncode(board2fen(board, opponentTeam)),
                                    Method = "GET"
                                })
                                
                                local success, data = pcall(function()
                                    return HttpService:JSONDecode(res.Body)
                                end)
                                
                                if success and data.bestmove then
                                    local bestmove = data.bestmove
                                    
                                    -- Detecta promoção (5 caracteres)
                                    if string.len(bestmove) == 5 then
                                        -- Remove o caractere de promoção
                                        bestmove = string.sub(bestmove, 1, 4)
                                    end
                                    
                                    if string.len(bestmove) == 4 then
                                        local fromSquare = string.sub(bestmove, 1, 2)
                                        local toSquare = string.sub(bestmove, 3, 4)
                                        local fromWorkspace = convertToWorkspaceNotation(fromSquare)
                                        local toWorkspace = convertToWorkspaceNotation(toSquare)
                                        
                                        highlightOpponentMove(fromWorkspace, toWorkspace)
                                        print("[OPPONENT] Melhor movimento do oponente:", fromWorkspace, "->", toWorkspace)
                                    end
                                end
                            end)
                            wait(2)
                            isRunning = false
                        end
                    end
                end
            end
        end
    end
end)

print("========================================")
print("♟️  Chess Bot Assistant CARREGADO!")
print("========================================")