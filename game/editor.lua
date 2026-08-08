local Editor = {}
Editor.__index = Editor

local LEVELS_DIR = "levels"
local HUD_X, HUD_Y = 10, 10
local HUD_W = 160
local BUTTON_X = 18
local BUTTON_W = 144
local BUTTON_H = 24
local BUTTON_GAP = 28
local DROPDOWN_ITEM_H = 28
local DROPDOWN_MAX_VISIBLE = 8
local HUD_FONT_SIZE = 14

local hudFont

local function getHudFont()
  if not hudFont then
    hudFont = love.graphics.newFont("assets/fonts/PixelifySans-Regular.ttf", HUD_FONT_SIZE)
  end
  return hudFont
end

local function levelPath(index)
  return LEVELS_DIR .. "/level" .. index .. ".txt"
end

local function levelLabel(index)
  return "level" .. index
end

local function sourceLevelsDir()
  if love.filesystem.isFused() then
    return nil
  end
  local source = love.filesystem.getSource()
  if not source or source == "" then
    return nil
  end
  return source .. "/" .. LEVELS_DIR
end

local function ensureLevelsDir()
  love.filesystem.createDirectory(LEVELS_DIR)
  local dir = sourceLevelsDir()
  if dir then
    os.execute(string.format('mkdir -p %q', dir))
  end
end

local function listLevelIndices()
  ensureLevelsDir()
  local seen = {}
  local indices = {}

  local function addName(name)
    local index = name:match("^level(%d+)%.txt$")
    if index then
      index = tonumber(index)
      if not seen[index] then
        seen[index] = true
        indices[#indices + 1] = index
      end
    end
  end

  for _, name in ipairs(love.filesystem.getDirectoryItems(LEVELS_DIR)) do
    addName(name)
  end

  local dir = sourceLevelsDir()
  if dir then
    local handle = io.popen(string.format('ls -1 %q 2>/dev/null', dir))
    if handle then
      for name in handle:lines() do
        addName(name)
      end
      handle:close()
    end
  end

  table.sort(indices)
  return indices
end

local function nextLevelIndex()
  local indices = listLevelIndices()
  if #indices == 0 then
    return 1
  end
  return indices[#indices] + 1
end

local function writeLevelFile(path, contents)
  ensureLevelsDir()

  local dir = sourceLevelsDir()
  if dir then
    local file, err = io.open(dir .. "/" .. path:match("[^/]+$"), "w")
    if not file then
      return false, err
    end
    file:write(contents)
    file:close()
    return true
  end

  return love.filesystem.write(path, contents)
end

local function readLevelFile(path)
  local contents, message = love.filesystem.read(path)
  if contents then
    return contents
  end

  local dir = sourceLevelsDir()
  if dir then
    local file, err = io.open(dir .. "/" .. path:match("[^/]+$"), "r")
    if file then
      local data = file:read("*a")
      file:close()
      return data
    end
    return nil, err or message
  end

  return nil, message
end

local function buttonY(index)
  return 18 + (index - 1) * BUTTON_GAP
end

function Editor.new(spawnCol, spawnRow)
  return setmetatable({
    active = false,
    tool = "ground",
    spawnCol = spawnCol,
    spawnRow = spawnRow,
    status = "",
    statusTimer = 0,
    panSpeed = 260,
    loadCursor = 0,
    loadDropdownOpen = false,
    loadDropdownScroll = 0,
    loadOptions = {},
    paintingButton = nil,
  }, Editor)
end

function Editor:setStatus(text)
  self.status = text or ""
  self.statusTimer = (text and text ~= "") and 3 or 0
end

function Editor:setActive(active)
  self.active = active
  self:setStatus(active and "Editor enabled" or "")
  self.loadDropdownOpen = false
  self.paintingButton = nil
end

function Editor:refreshLoadOptions()
  self.loadOptions = listLevelIndices()
  local maxScroll = math.max(0, #self.loadOptions - DROPDOWN_MAX_VISIBLE)
  self.loadDropdownScroll = math.max(0, math.min(maxScroll, self.loadDropdownScroll))
end

function Editor:getDropdownRect()
  local count = math.max(1, math.min(DROPDOWN_MAX_VISIBLE, #self.loadOptions))
  -- Float to the right of the tool panel so it never covers buttons/status.
  local x = HUD_X + HUD_W + 6
  local y = buttonY(5)
  local w = 132
  local h = 8 + count * DROPDOWN_ITEM_H
  return x, y, w, h
end

function Editor:isOverDropdown(x, y)
  if not self.loadDropdownOpen then
    return false
  end
  local dx, dy, dw, dh = self:getDropdownRect()
  return x >= dx and x <= dx + dw and y >= dy and y <= dy + dh
end

function Editor:isOverHud(x, y)
  if self:isOverDropdown(x, y) then
    return true
  end
  return x >= HUD_X and x <= HUD_X + HUD_W and y >= HUD_Y and y <= HUD_Y + 164
end

function Editor:getTileAt(x, y, grid, camera)
  local worldX, worldY = camera:screenToWorld(x, y)
  local col = math.floor(worldX / grid.size) + 1
  local row = math.floor(worldY / grid.size) + 1
  if not grid:isInside(col, row) then
    return nil, nil
  end
  return col, row
end

function Editor:protectSpawn(grid)
  grid:setGround(self.spawnCol, self.spawnRow)
  grid:removeFire(self.spawnCol, self.spawnRow)
end

function Editor:saveLevel(grid)
  self.loadDropdownOpen = false
  local index = nextLevelIndex()
  local path = levelPath(index)
  local success, message = writeLevelFile(path, grid:serialize())
  if success then
    self.loadCursor = index
    self:setStatus("Saved " .. path)
    self:refreshLoadOptions()
  else
    self:setStatus("Save failed: " .. tostring(message))
  end
end

function Editor:loadLevel(grid, index)
  local path = levelPath(index)
  local contents, message = readLevelFile(path)
  if not contents then
    self:setStatus("Load failed: " .. tostring(message or ("missing " .. path)))
    return
  end

  grid:load(contents)
  self:protectSpawn(grid)
  self.loadCursor = index
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self:setStatus("Loaded " .. path)
end

function Editor:toggleLoadDropdown()
  self:refreshLoadOptions()
  if #self.loadOptions == 0 then
    self.loadDropdownOpen = false
    self:setStatus("No levels in " .. LEVELS_DIR)
    return
  end
  self.loadDropdownOpen = not self.loadDropdownOpen
end

function Editor:applyTool(tool, col, row, grid)
  if not col or (col == self.spawnCol and row == self.spawnRow) then
    if col then
      self:setStatus("The spawn tile is protected")
    end
    return
  end

  if tool == "ground" then
    grid:setGround(col, row)
    grid:removeFire(col, row)
  elseif tool == "fire" then
    grid:addFire(col, row)
  elseif tool == "erase" then
    grid:erase(col, row)
  end
end

function Editor:paintAt(x, y, button, grid, camera)
  if self:isOverHud(x, y) then
    return
  end
  local col, row = self:getTileAt(x, y, grid, camera)
  self:applyTool(button == 2 and "erase" or self.tool, col, row, grid)
end

function Editor:hitDropdownItem(x, y)
  if not self:isOverDropdown(x, y) or #self.loadOptions == 0 then
    return nil
  end

  local dx, dy = self:getDropdownRect()
  local localY = y - (dy + 4)
  if localY < 0 then
    return nil
  end

  local row = math.floor(localY / DROPDOWN_ITEM_H) + 1
  local index = row + self.loadDropdownScroll
  if index < 1 or index > #self.loadOptions then
    return nil
  end
  return self.loadOptions[index]
end

function Editor:hitToolButton(x, y)
  if x < BUTTON_X or x > BUTTON_X + BUTTON_W then
    return nil
  end
  for i = 1, 5 do
    local y0 = buttonY(i)
    if y >= y0 and y <= y0 + BUTTON_H then
      return i
    end
  end
  return nil
end

function Editor:mousepressed(x, y, button, grid, camera)
  if button ~= 1 and button ~= 2 then
    return
  end

  self.paintingButton = nil

  if button == 1 then
    if self.loadDropdownOpen then
      local chosen = self:hitDropdownItem(x, y)
      if chosen then
        self:loadLevel(grid, chosen)
        return
      end
    end

    local toolButton = self:hitToolButton(x, y)
    if toolButton == 1 then
      self.loadDropdownOpen = false
      self.tool = "ground"
      return
    elseif toolButton == 2 then
      self.loadDropdownOpen = false
      self.tool = "fire"
      return
    elseif toolButton == 3 then
      self.loadDropdownOpen = false
      self.tool = "erase"
      return
    elseif toolButton == 4 then
      self:saveLevel(grid)
      return
    elseif toolButton == 5 then
      self:toggleLoadDropdown()
      return
    end

    if self.loadDropdownOpen then
      self.loadDropdownOpen = false
      if self:isOverHud(x, y) then
        return
      end
    end
  end

  if self:isOverHud(x, y) then
    return
  end

  self.paintingButton = button
  self:paintAt(x, y, button, grid, camera)
end

function Editor:mousereleased(_, _, button)
  if self.paintingButton == button then
    self.paintingButton = nil
  end
end

function Editor:keypressed(key, grid)
  if key == "1" then
    self.tool = "ground"
    self.loadDropdownOpen = false
  elseif key == "2" then
    self.tool = "fire"
    self.loadDropdownOpen = false
  elseif key == "3" then
    self.tool = "erase"
    self.loadDropdownOpen = false
  elseif key == "c" then
    grid:clear()
    self:protectSpawn(grid)
    self.loadDropdownOpen = false
    self:setStatus("Level cleared")
  elseif key == "f" then
    for row = 1, grid.rows do
      for col = 1, grid.columns do
        grid:setGround(col, row)
      end
    end
    self.loadDropdownOpen = false
    self:setStatus("Ground filled")
  elseif key == "s" then
    self:saveLevel(grid)
  elseif key == "l" then
    self:toggleLoadDropdown()
  elseif key == "escape" and self.loadDropdownOpen then
    self.loadDropdownOpen = false
  end
end

function Editor:clampCamera(grid, camera)
  local width, height = love.graphics.getDimensions()
  local worldWidth = grid.columns * grid.size
  local worldHeight = grid.rows * grid.size
  local halfWidth = math.min(worldWidth / 2, width / camera.zoom / 2)
  local halfHeight = math.min(worldHeight / 2, height / camera.zoom / 2)
  camera.x = math.max(halfWidth, math.min(worldWidth - halfWidth, camera.x))
  camera.y = math.max(halfHeight, math.min(worldHeight - halfHeight, camera.y))
end

function Editor:update(dt, grid, camera)
  if self.statusTimer > 0 then
    self.statusTimer = self.statusTimer - dt
    if self.statusTimer <= 0 then
      self.status = ""
      self.statusTimer = 0
    end
  end

  local dx, dy = 0, 0
  if love.keyboard.isDown("left", "a") then dx = dx - 1 end
  if love.keyboard.isDown("right", "d") then dx = dx + 1 end
  if love.keyboard.isDown("up", "w") then dy = dy - 1 end
  if love.keyboard.isDown("down") then dy = dy + 1 end
  camera.x = camera.x + dx * self.panSpeed * dt / camera.zoom
  camera.y = camera.y + dy * self.panSpeed * dt / camera.zoom
  self:clampCamera(grid, camera)

  if self.paintingButton and love.mouse.isDown(self.paintingButton) then
    local x, y = love.mouse.getPosition()
    self:paintAt(x, y, self.paintingButton, grid, camera)
  else
    self.paintingButton = nil
  end
end

function Editor:wheelmoved(y, grid, camera)
  local mouseX, mouseY = love.mouse.getPosition()
  if self.loadDropdownOpen and self:isOverDropdown(mouseX, mouseY) then
    local maxScroll = math.max(0, #self.loadOptions - DROPDOWN_MAX_VISIBLE)
    self.loadDropdownScroll = math.max(0, math.min(maxScroll, self.loadDropdownScroll - y))
    return
  end
  camera.zoom = math.max(1, math.min(3, camera.zoom + y * 0.25))
  self:clampCamera(grid, camera)
end

function Editor:draw(grid, camera)
  local mouseX, mouseY = love.mouse.getPosition()
  local col, row = self:getTileAt(mouseX, mouseY, grid, camera)
  if col and not self:isOverHud(mouseX, mouseY) then
    local worldX, worldY = grid:tileCenter(col, row)
    local x, y = camera:worldToScreen(worldX, worldY)
    local size = grid.size * camera.zoom
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x - size / 2, y - size / 2, size, size)
  end

  local spawnX, spawnY = grid:tileCenter(self.spawnCol, self.spawnRow)
  spawnX, spawnY = camera:worldToScreen(spawnX, spawnY)
  local spawnSize = grid.size * camera.zoom
  love.graphics.setColor(0.35, 1, 0.55, 0.9)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle(
    "line",
    spawnX - spawnSize / 2 + 3,
    spawnY - spawnSize / 2 + 3,
    spawnSize - 6,
    spawnSize - 6
  )

  love.graphics.setColor(0.025, 0.05, 0.09, 0.94)
  love.graphics.rectangle("fill", HUD_X, HUD_Y, HUD_W, 164, 6, 6)

  local previousFont = love.graphics.getFont()
  local font = getHudFont()
  love.graphics.setFont(font)
  local textY = math.floor((BUTTON_H - font:getHeight()) * 0.5)

  local tools = {
    { name = "ground", label = "Ground" },
    { name = "fire", label = "Fire" },
    { name = "erase", label = "Erase" },
    { name = "save", label = "Save" },
    { name = "load", label = "Load" },
  }
  for index, tool in ipairs(tools) do
    local y = buttonY(index)
    if self.tool == tool.name or (tool.name == "load" and self.loadDropdownOpen) then
      love.graphics.setColor(0.18, 0.58, 0.86, 0.8)
    else
      love.graphics.setColor(0.10, 0.20, 0.31, 0.9)
    end
    love.graphics.rectangle("fill", BUTTON_X, y, BUTTON_W, BUTTON_H, 4, 4)
    love.graphics.setColor(0.92, 0.97, 1)
    love.graphics.print(tool.label, 28, y + textY)
  end

  if self.loadDropdownOpen then
    local dx, dy, dw, dh = self:getDropdownRect()
    love.graphics.setColor(0.025, 0.05, 0.09, 0.98)
    love.graphics.rectangle("fill", dx, dy, dw, dh, 6, 6)
    love.graphics.setColor(0.18, 0.58, 0.86, 0.7)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", dx, dy, dw, dh, 6, 6)

    local itemTextY = math.floor((DROPDOWN_ITEM_H - 2 - font:getHeight()) * 0.5)
    local visible = math.min(DROPDOWN_MAX_VISIBLE, #self.loadOptions)
    for i = 1, visible do
      local optionIndex = i + self.loadDropdownScroll
      local levelIndex = self.loadOptions[optionIndex]
      local itemY = dy + 4 + (i - 1) * DROPDOWN_ITEM_H
      local hovered = mouseX >= dx and mouseX <= dx + dw
        and mouseY >= itemY and mouseY < itemY + DROPDOWN_ITEM_H

      if levelIndex == self.loadCursor then
        love.graphics.setColor(0.18, 0.58, 0.86, 0.9)
      elseif hovered then
        love.graphics.setColor(0.14, 0.36, 0.55, 0.95)
      else
        love.graphics.setColor(0.10, 0.20, 0.31, 0.95)
      end
      love.graphics.rectangle("fill", dx + 4, itemY, dw - 8, DROPDOWN_ITEM_H - 2, 3, 3)
      love.graphics.setColor(0.92, 0.97, 1)
      love.graphics.print(levelLabel(levelIndex), dx + 12, itemY + itemTextY)
    end
  end

  if self.status ~= "" then
    love.graphics.setColor(0.025, 0.05, 0.09, 0.9)
    love.graphics.rectangle("fill", 10, 182, 280, 24, 4, 4)
    love.graphics.setColor(0.85, 0.93, 1)
    love.graphics.print(self.status, 18, 182 + textY)
  end

  love.graphics.setFont(previousFont)
end

return Editor
