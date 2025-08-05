---@diagnostic disable: undefined-global
setDefaultTab("Main")
-- Proteção por MAC
local allowedMacs = {
  "0023085d90210000", -- Tadala
  "d843ae4f90350000", -- Baxero
  "c23532a210d90000",  -- Eo Grilo
  "00e04cd125600000", -- RednasKram
  "00e57ff410be0000", -- RednasKrma
  "305a3a9e37690000" -- Farmacia
}

local function isMacAuthorized()
  for _, mac in pairs(modules.client.g_platform.getMacAddresses()) do
    if table.find(allowedMacs, mac) then
      return true
    end
  end
  return false
end

if not isMacAuthorized() then
  warn("🚫 Tadala Push: MAC não autorizado. Acesso bloqueado.")
  return
end


local lastPushTime = 0
local pushCooldown = 550 -- tempo mínimo entre pushes (em ms)

local panelName = "pushmax"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('PUSHMAX')

  Button
    id: push
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

if not storage[panelName] then
  storage[panelName] = {}
end

-- defaults
if storage[panelName].enabled == nil then storage[panelName].enabled = true end
storage[panelName].pushDelay = storage[panelName].pushDelay or 1060
storage[panelName].pushMaxRuneId = storage[panelName].pushMaxRuneId or 3188
storage[panelName].mwallBlockId = storage[panelName].mwallBlockId or 2128
storage[panelName].calibrationMode = false
storage[panelName].autoTargetMarkEnabled = storage[panelName].autoTargetMarkEnabled or true

-- ✅ NOVOS DELAYS SEPARADOS
storage[panelName].pushDelayMove = storage[panelName].pushDelayMove or 1060
storage[panelName].pushDelayField = storage[panelName].pushDelayField or 1060
storage[panelName].fullPushMode = storage[panelName].fullPushMode or false

local config = storage[panelName]

-- ✅ Função global para atualizar texto do botão de calibração
function updateCalibrationButton()
  if not pushWindow or not pushWindow.calibrationToggle then return end
  local stateText = config.calibrationMode and "ON" or "OFF"
  pushWindow.calibrationToggle:setText("Calibration: " .. stateText)
end

function updateAutoTargetButton()
  if not pushWindow or not pushWindow.autoTargetToggle then return end
  local stateText = config.autoTargetMarkEnabled and "ON" or "OFF"
  pushWindow.autoTargetToggle:setText("Auto Target Mark: " .. stateText)
end


ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

ui.push.onClick = function(widget)
  pushWindow:show()
  pushWindow:raise()
  pushWindow:focus()
end


rootWidget = g_ui.getRootWidget()
if rootWidget then
  pushWindow = UI.createWindow('PushMaxWindow', rootWidget)
  pushWindow:hide()

  pushWindow.closeButton.onClick = function(widget)
    pushWindow:hide()
  end

  -- ✅ Push Delay (Move)
  local updateDelayMoveText = function()
    pushWindow.delayMoveText:setText("Push Delay (Move): " .. config.pushDelayMove)
  end

  updateDelayMoveText()
  pushWindow.delayMove.onValueChange = function(scroll, value)
    config.pushDelayMove = value
    updateDelayMoveText()
  end
  pushWindow.delayMove:setValue(config.pushDelayMove)

  -- ✅ Push Delay (Field)
  local updateDelayFieldText = function()
    pushWindow.delayFieldText:setText("Push Delay (Field): " .. config.pushDelayField)
  end

  updateDelayFieldText()
  pushWindow.delayField.onValueChange = function(scroll, value)
    config.pushDelayField = value
    updateDelayFieldText()
  end
  pushWindow.delayField:setValue(config.pushDelayField)

  -- ✅ Rune Id Setup
  pushWindow.runeId.onItemChange = function(widget)
    config.pushMaxRuneId = widget:getItemId()
  end
  pushWindow.runeId:setItemId(config.pushMaxRuneId)

  -- ✅ MW Adjust (já existia)
  config.mwAdjust = config.mwAdjust or 0
  pushWindow.mwAdjust.onValueChange = function(scroll, value)
    config.mwAdjust = value / 10  -- converte de décimos para segundos
    pushWindow.mwLabel:setText(string.format("MW Adjust: %.1f s", config.mwAdjust))
  end
  pushWindow.mwAdjust:setValue(config.mwAdjust * 10)
  pushWindow.mwLabel:setText(string.format("MW Adjust: %.1f s", config.mwAdjust))

  -- ✅ Calibration Toggle
  pushWindow.calibrationToggle.onClick = function()
    config.calibrationMode = not config.calibrationMode
    updateCalibrationButton()
  end
  updateCalibrationButton()
end

-- ✅ Auto Target Toggle (já existia)
updateAutoTargetButton()
pushWindow.autoTargetToggle.onClick = function()
  config.autoTargetMarkEnabled = not config.autoTargetMarkEnabled
  updateAutoTargetButton()
end

-- ✅ Full Push Toggle
pushWindow.fullPushToggle.onClick = function()
  config.fullPushMode = not config.fullPushMode
  updateFullPushButton()
end

function updateFullPushButton()
  if not pushWindow or not pushWindow.fullPushToggle then return end
  local stateText = config.fullPushMode and "ON" or "OFF"
  pushWindow.fullPushToggle:setText("Full-Push: " .. stateText)
end

updateFullPushButton()

-- variables
local fieldTable = {2118, 105, 2122, 2119, 21465}
local targetTile
local pushTarget
local lastClick = 0

local function getNextStepTowards(fromPos, toPos)
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  local stepX = dx ~= 0 and (dx > 0 and 1 or -1) or 0
  local stepY = dy ~= 0 and (dy > 0 and 1 or -1) or 0
  return { x = fromPos.x + stepX, y = fromPos.y + stepY, z = fromPos.z }
end

local resetData = function()
  for _, tile in pairs(g_map.getTiles(posz())) do
    if tile:getText() == "Tadala" or tile:getText() == "dest" then
      tile:setText('')
    end
  end
  if pushTarget then
    pushTarget:setText('')
    pushTarget:setMarked('none')
  end
  pushTarget = nil
  targetTile = nil
end

local flowerIds = {9013, 9015, 8763, 2988, 649, 2983, 2981, 3661, 2984, 3655, 2985,}
local disintegrateRuneId = 3197
local wildGrowthId = 2130      -- Wild Growth
local macheteId     = 3308     -- Machete


local isOk = function(a, b) return getDistanceBetween(a, b) == 1 end
local isNotOk = function(list, tile)
  return table.find(list, tile:getTopUseThing():getId()) ~= nil
end

local function samePosition(pos1, pos2)
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

-- Mouse scroll
local gamePanel = modules.game_interface.gameMapPanel

gamePanel.onMouseWheel = function(self, mousePos, direction)
  if not config.enabled or direction ~= 2 then return end

  local tile = getTileUnderCursor()
  if not tile then return end

  local creature = tile:getCreatures()[1]

  -- Se ainda não marcou um pushTarget (criatura), e tem uma criatura sob o cursor
  if not pushTarget and creature then
    pushTarget = creature
    pushTarget:setText("Tadala")
    return
  end

  -- Se já tem um pushTarget, o próximo scroll deve definir o destino (mesmo com criatura em cima)
  if pushTarget then
    -- Limpa destino anterior, se for diferente
    if targetTile and not samePosition(tile:getPosition(), targetTile:getPosition()) then
      targetTile:setText('')
    end

    tile:setText('dest')
    targetTile = tile
  end
end


onCreaturePositionChange(function(creature, newPos, oldPos)
  if not config.enabled then return end
  if pushTarget and creature:getId() == pushTarget:getId() then
    if not config.fullPushMode then
      if targetTile then
        targetTile:setText('')
        targetTile = nil
      end
    else
    end
  end
end) 

-- ✅ Macro com suporte a modo de calibração
macro(50, function()
  if not config.enabled or not pushTarget or not targetTile then return end
  if not isMacAuthorized () then return end
  
  -- Proteção contra pushTarget inválido
  if type(pushTarget.getPosition) ~= "function" or type(pushTarget.isCreature) ~= "function" then
    resetData()
    return
  end
  
  -- Evita erro ao mudar de andar
  local playerPos = pos()
  local targetPos = pushTarget:getPosition()
  local tilePos = targetTile:getPosition()
  
  if not targetPos or not tilePos or targetPos.z ~= playerPos.z or tilePos.z ~= playerPos.z then
    resetData()
    return
  end
  
  if not pushTarget:isCreature() then
    resetData()
    return
  end
  

  -- ✅ PRIORIDADE: usar disintegrate assim que possível
do
  local playerPos = pos()
  if getDistanceBetween(playerPos, targetTile:getPosition()) == 1 then
    local topThing = targetTile:getTopUseThing()
    local mwallIds = {2129, 46928, 46926, 46927, 46915, 2128}
    local hasMW = topThing and table.find(mwallIds, topThing:getId())
    local flowerItem

    -- Procura a flower na tile (mesmo que esteja coberta por MW)
    for _, item in ipairs(targetTile:getItems()) do
      if table.find(flowerIds, item:getId()) then
        flowerItem = item
        break
      end
    end

    -- ⚡ Usa disintegrate imediatamente quando MW sair
    if flowerItem and not hasMW then
      return useWith(disintegrateRuneId, flowerItem)
    end
    -- Se tiver MW, continua macro normalmente (push etc.)
  end
end

-- ✅ PRIORIDADE 2: usar machete para cortar Wild Growth rapidamente
do
  local playerPos = pos()
  if getDistanceBetween(playerPos, targetTile:getPosition()) == 1 then
    local topThing = targetTile:getTopUseThing()
    if topThing and topThing:getId() == wildGrowthId then
      return useWith(macheteId, topThing) -- corta e encerra este ciclo
    end
  end
end


  -- ✅ Se estiver em modo calibração, aguarda movimento do TARGET
  if config.calibrationMode then
    if not samePosition(pushTarget:getPosition(), targetTile:getPosition()) then
      local rawDelay = targetTile:getTimer()
      local ping = g_game.getPing() or 100
      local finalDelay = math.max(600, rawDelay - math.floor(ping / 2))
  
      -- ⚙️ Atualiza delays no config
      config.pushDelayMove = finalDelay
      config.pushDelayField = finalDelay
  
      -- ⏫ Atualiza sliders da UI se existirem
      if pushWindow then
        if pushWindow.delayMove then
          pushWindow.delayMove:setValue(finalDelay)
        end
        if pushWindow.delayField then
          pushWindow.delayField:setValue(finalDelay)
        end
  
        -- Atualiza os textos se quiser feedback instantâneo
        if pushWindow.delayMoveText then
          pushWindow.delayMoveText:setText("Push Delay (Move): " .. finalDelay)
        end
        if pushWindow.delayFieldText then
          pushWindow.delayFieldText:setText("Push Delay (Field): " .. finalDelay)
        end
      end
  
      -- Finaliza modo calibração
      config.calibrationMode = false
      updateCalibrationButton()
    end
    return
  end
  

  local pushDelay = config.pushDelay
  local rune = config.pushMaxRuneId
  local mwallIds = {2129, 46928, 46926, 46927, 46915, 2128}
  local topItem = targetTile:getTopUseThing()
  local finalDestPos = targetTile:getPosition()
  local currentPos = pushTarget:getPosition()
  local nextPos = getNextStepTowards(currentPos, finalDestPos)
  local tilePos = nextPos


  if samePosition(currentPos, finalDestPos) then
    if config.fullPushMode then
      targetTile:setText('')
      targetTile = nil
      return
    else
      resetData()
      return
    end
  end
  

  if getDistanceBetween(currentPos, tilePos) ~= 1 then return end
  local playerPos = pos()


  if targetTile:canShoot() then
    for _, item in ipairs(targetTile:getItems()) do
      if table.find(fieldTable, item:getId()) then
        return useWith(3148, item)
      end
    end
  end
  

  if not isOk(tilePos, currentPos) then return end

  local tileOfTarget = g_map.getTile(currentPos)
  if not tileOfTarget then return end
  

  local topThing = targetTile:getTopUseThing()
  if topThing then
  else
  end
  
  local items = targetTile:getItems()
  if #items == 0 then
  else
    for i, item in ipairs(items) do
    end
  end
  
  

  local topThing = targetTile:getTopUseThing()
  local topId = topThing and topThing:getId()
    
  if topId and table.find(mwallIds, topId) then
    -- Detecta se o push será de field (useWith) ou move (g_game.move)
    local isFieldPush = false
    local tileOfTarget = g_map.getTile(currentPos)
    local targetTop = tileOfTarget and tileOfTarget:getTopUseThing()
    if targetTop and not targetTop:isNotMoveable() and targetTile:getTimer() < config.pushDelayField + 500 then
      isFieldPush = true
    end
  
    -- Usa o delay correto com base no tipo
    local selectedDelay = isFieldPush and config.pushDelayField or config.pushDelayMove
    local mwExtra = (config.mwAdjust or 0) * 1000
    local totalDelay = selectedDelay + mwExtra
    local timer = targetTile:getTimer()
  
  
    if timer > totalDelay then
      return
    else
      if not vBot.isUsing then
        vBot.isUsing = true
        schedule(totalDelay + 700, function()
          vBot.isUsing = false
        end)
      end
    end
  end
  
  local targetTop = tileOfTarget:getTopUseThing()
  local targetTop = tileOfTarget:getTopUseThing()
  local pushDelayToUse
  
  -- Decide qual delay usar (field push ou move push)
  if targetTop and not targetTop:isNotMoveable() and targetTile:getTimer() < config.pushDelayField + 500 then
    pushDelayToUse = config.pushDelayField
    -- Field push (useWith)
    return useWith(rune, pushTarget)
  else
    pushDelayToUse = config.pushDelayMove
  end
  
  local distanceToTarget = getDistanceBetween(pos(), pushTarget:getPosition())
  local now = now
  
  if config.fullPushMode then
    if distanceToTarget > 1 then
      -- Sem delay se player está longe do target
      lastPushTime = now
    else
      -- Respeita o cooldown se estiver perto
      if now - lastPushTime < pushCooldown then return end
      lastPushTime = now
    end
  else
    -- Modo normal com cooldown sempre
    if now - lastPushTime < pushCooldown then return end
    lastPushTime = now
  end
  
  
  -- Push normal (g_game.move)
  g_game.move(pushTarget, tilePos)
  

  -- DEBUG: imprime hora exata que o push está sendo executado
  local hora = os.date("%H:%M:%S")

  g_game.move(pushTarget, tilePos)

end) 

onKeyDown(function(keys)
  if keys == "Escape" then
    resetData()
  end
end)

local lastTarget

macro(100, function()
  if not config.enabled or not config.autoTargetMarkEnabled then return end

  local creature = g_game.getAttackingCreature()
  if not creature or not creature:isCreature() then return end

  if pushTarget and lastTarget and creature:getId() == lastTarget:getId() then return end

  if lastTarget then
    lastTarget:setText('')
    lastTarget:setMarked('none')
  end

  pushTarget = creature
  lastTarget = creature
  pushTarget:setText("Tadala")
end)
