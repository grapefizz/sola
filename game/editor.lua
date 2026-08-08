local Editor = {}
Editor.__index = Editor

local LEVELS_DIR = "levels"
local HUD_X, HUD_Y = 10, 10
local HUD_W = 160
local HUD_H = 192
local BUTTON_X = 18
local BUTTON_W = 144
local BUTTON_H = 24
local BUTTON_GAP = 28
local DROPDOWN_ITEM_H = 28
local DROPDOWN_MAX_VISIBLE = 8
local HUD_FONT_SIZE = 14
local NAME_MAX_LEN = 24

local hudFont

local function getHudFont()
  if not hudFont then
    hudFont = love.graphics.newFont("assets/fonts/PixelifySans-Regular.ttf", HUD_FONT_SIZE)
  end
  return hudFont
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

local function sanitizeLevelName(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("[^%w%-%_ ]", "")
  name = name:gsub("%s+", " ")
  if #name > NAME_MAX_LEN then
    name = name:sub(1, NAME_MAX_LEN)
  end
  return name
end

local function levelPath(name)
  return LEVELS_DIR .. "/" .. name .. ".txt"
end

local function listLevelNames()
  ensureLevelsDir()
  local seen = {}
  local names = {}

  local function addName(filename)
    local name = filename:match("^(.+)%.txt$")
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  for _, filename in ipairs(love.filesystem.getDirectoryItems(LEVELS_DIR)) do
    addName(filename)
  end

  local dir = sourceLevelsDir()
  if dir then
    local handle = io.popen(string.format('ls -1 %q 2>/dev/null', dir))
    if handle then
      for filename in handle:lines() do
        addName(filename)
      end
      handle:close()
    end
  end

  table.sort(names, function(a, b)
    return a:lower() < b:lower()
  end)

  return names
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

local function nextDefaultName(existing)
  local used = {}

  for _, name in ipairs(existing) do
    used[name:lower()] = true
  end

  local n = 1
  while used["level" .. n] do
    n = n + 1
  end

  return "level" .. n
end

function Editor.listLevelNames()
  return listLevelNames()
end

function Editor.readLevelContents(name)
  return readLevelFile(levelPath(name))
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
    currentLevelName = nil,
    loadDropdownOpen = false,
    loadDropdownScroll = 0,
    loadOptions = {},
    paintingButton = nil,
    namingOpen = false,
    namingText = "",
    namingCursorBlink = 0,
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
  self:closeNaming()
end

function Editor:closeNaming()
  self.namingOpen = false
  self.namingText = ""
  self.namingCursorBlink = 0

  if love.keyboard.setTextInput then
    love.keyboard.setTextInput(false)
  end
end

function Editor:openNaming()
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self:refreshLoadOptions()
  self.namingOpen = true
  self.namingText = self.currentLevelName or nextDefaultName(self.loadOptions)
  self.namingCursorBlink = 0

  if love.keyboard.setTextInput then
    love.keyboard.setTextInput(true)
  end
end

function Editor:refreshLoadOptions()
  self.loadOptions = listLevelNames()
  self.loadDropdownScroll = math.max(
    0,
    math.min(self:maxDropdownScroll(), self.loadDropdownScroll)
  )
end

function Editor:maxDropdownScroll()
  return math.max(0, #self.loadOptions - DROPDOWN_MAX_VISIBLE)
end

function Editor:scrollDropdown(delta)
  self.loadDropdownScroll = math.max(
    0,
    math.min(
      self:maxDropdownScroll(),
      self.loadDropdownScroll + delta
    )
  )
end

function Editor:getDropdownRect()
  local slots = 1

  if #self.loadOptions > 0 then
    slots = math.min(DROPDOWN_MAX_VISIBLE, #self.loadOptions)
  end

  local x = HUD_X + HUD_W + 6
  local y = buttonY(6)
  local w = 168
  local h = 8 + slots * DROPDOWN_ITEM_H

  return x, y, w, h
end

function Editor:getNamingRect()
  local width, height = love.graphics.getDimensions()
  local w, h = 320, 126
  local x = math.floor((width - w) * 0.5)
  local y = math.floor((height - h) * 0.5)

  return x, y, w, h
end

function Editor:isOverDropdown(x, y)
  if not self.loadDropdownOpen then
    return false
  end

  local dx, dy, dw, dh = self:getDropdownRect()

  return x >= dx
    and x <= dx + dw
    and y >= dy
    and y <= dy + dh
end

function Editor:isOverNaming(x, y)
  if not self.namingOpen then
    return false
  end

  local nx, ny, nw, nh = self:getNamingRect()

  return x >= nx
    and x <= nx + nw
    and y >= ny
    and y <= ny + nh
end

function Editor:isOverHud(x, y)
  if self:isOverNaming(x, y) or self.namingOpen then
    return true
  end

  if self:isOverDropdown(x, y) then
    return true
  end

  return x >= HUD_X
    and x <= HUD_X + HUD_W
    and y >= HUD_Y
    and y <= HUD_Y + HUD_H
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
  grid:removeSnowflake(self.spawnCol, self.spawnRow)
end

function Editor:beginSave()
  self:openNaming()
end

function Editor:confirmSave(grid)
  local name = sanitizeLevelName(self.namingText)

  if name == "" then
    self:setStatus("Enter a level name")
    return
  end

  local path = levelPath(name)
  local data = grid:serialize()

  self:closeNaming()

  local success, message = writeLevelFile(path, data)

  if success then
    self.currentLevelName = name
    self:setStatus("Saved")
    self:refreshLoadOptions()
  else
    self:setStatus("Save failed: " .. tostring(message))
  end
end

function Editor:loadLevel(grid, name)
  local path = levelPath(name)
  local contents, message = readLevelFile(path)

  if not contents then
    self:setStatus(
      "Load failed: " ..
      tostring(message or ("missing " .. path))
    )
    return
  end

  grid:load(contents)
  self:protectSpawn(grid)
  self.currentLevelName = name
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self:setStatus("Loaded " .. name)
end

function Editor:toggleLoadDropdown()
  if self.namingOpen then
    return
  end

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
    grid:removeSnowflake(col, row)

  elseif tool == "fire" then
    grid:addFire(col, row)
    grid:removeSnowflake(col, row)

  elseif tool == "snowflake" then
    grid:addSnowflake(col, row)

  elseif tool == "erase" then
    grid:erase(col, row)
  end
end

function Editor:paintAt(x, y, button, grid, camera)
  if self:isOverHud(x, y) then
    return
  end

  local col, row = self:getTileAt(x, y, grid, camera)

  self:applyTool(
    button == 2 and "erase" or self.tool,
    col,
    row,
    grid
  )
end

function Editor:hitDropdownItem(x, y)
  if not self:isOverDropdown(x, y) or #self.loadOptions == 0 then
    return nil
  end

  local dx, dy, dw = self:getDropdownRect()
  local listW = dw - (
    (#self.loadOptions > DROPDOWN_MAX_VISIBLE)
    and 14
    or 0
  )

  if x > dx + listW then
    return nil
  end

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

  for i = 1, 6 do
    local y0 = buttonY(i)

    if y >= y0 and y <= y0 + BUTTON_H then
      return i
    end
  end

  return nil
end

function Editor:hitNamingButton(x, y)
  if not self.namingOpen then
    return nil
  end

  local nx, ny, nw = self:getNamingRect()
  local saveX, saveY = nx + 16, ny + 82
  local cancelX = nx + nw - 16 - 90

  if x >= saveX
    and x <= saveX + 90
    and y >= saveY
    and y <= saveY + 28 then
    return "save"
  end

  if x >= cancelX
    and x <= cancelX + 90
    and y >= saveY
    and y <= saveY + 28 then
    return "cancel"
  end

  return nil
end

function Editor:mousepressed(x, y, button, grid, camera)
  if button ~= 1 and button ~= 2 then
    return
  end

  self.paintingButton = nil

  if self.namingOpen then
    if button == 1 then
      local action = self:hitNamingButton(x, y)

      if action == "save" then
        self:confirmSave(grid)
      elseif action == "cancel" then
        self:closeNaming()
      end
    end

    return
  end

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
      self.tool = "snowflake"
      return

    elseif toolButton == 4 then
      self.loadDropdownOpen = false
      self.tool = "erase"
      return

    elseif toolButton == 5 then
      self:beginSave()
      return

    elseif toolButton == 6 then
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

function Editor:textinput(text)
  if not self.namingOpen then
    return
  end

  text = text:gsub("[\r\n\t]", "")

  if text == "" then
    return
  end

  local nextText = sanitizeLevelName(self.namingText .. text)
  self.namingText = nextText
end

function Editor:keypressed(key, grid)
  if self.namingOpen then
    if key == "return" or key == "kpenter" then
      self:confirmSave(grid)

    elseif key == "escape" then
      self:closeNaming()

    elseif key == "backspace" then
      local text = self.namingText

      if #text > 0 then
        self.namingText = text:sub(1, #text - 1)
      end
    end

    return
  end

  if self.loadDropdownOpen then
    if key == "up" then
      self:scrollDropdown(-1)
      return

    elseif key == "down" then
      self:scrollDropdown(1)
      return

    elseif key == "escape" then
      self.loadDropdownOpen = false
      return
    end
  end

  if key == "1" then
    self.tool = "ground"
    self.loadDropdownOpen = false

  elseif key == "2" then
    self.tool = "fire"
    self.loadDropdownOpen = false

  elseif key == "3" then
    self.tool = "snowflake"
    self.loadDropdownOpen = false

  elseif key == "4" then
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
    self:beginSave()

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
  local halfWidth = math.min(
    worldWidth / 2,
    width / camera.zoom / 2
  )
  local halfHeight = math.min(
    worldHeight / 2,
    height / camera.zoom / 2
  )

  camera.x = math.max(
    halfWidth,
    math.min(worldWidth - halfWidth, camera.x)
  )

  camera.y = math.max(
    halfHeight,
    math.min(worldHeight - halfHeight, camera.y)
  )
end

function Editor:update(dt, grid, camera)
  if self.statusTimer > 0 then
    self.statusTimer = self.statusTimer - dt

    if self.statusTimer <= 0 then
      self.status = ""
      self.statusTimer = 0
    end
  end

  if self.namingOpen then
    self.namingCursorBlink = self.namingCursorBlink + dt
    self.paintingButton = nil
    return
  end

  local dx, dy = 0, 0

  if love.keyboard.isDown("left", "a") then
    dx = dx - 1
  end

  if love.keyboard.isDown("right", "d") then
    dx = dx + 1
  end

  if love.keyboard.isDown("up", "w") then
    dy = dy - 1
  end

  if love.keyboard.isDown("down") then
    dy = dy + 1
  end

  camera.x = camera.x + dx * self.panSpeed * dt / camera.zoom
  camera.y = camera.y + dy * self.panSpeed * dt / camera.zoom

  self:clampCamera(grid, camera)

  if self.paintingButton and love.mouse.isDown(self.paintingButton) then
    local x, y = love.mouse.getPosition()
    self:paintAt(
      x,
      y,
      self.paintingButton,
      grid,
      camera
    )
  else
    self.paintingButton = nil
  end
end

function Editor:wheelmoved(y, grid, camera)
  if self.namingOpen then
    return
  end

  if self.loadDropdownOpen then
    self:scrollDropdown(-y)
    return
  end

  camera.zoom = math.max(
    1,
    math.min(3, camera.zoom + y * 0.25)
  )

  self:clampCamera(grid, camera)
end

function Editor:draw(grid, camera)
  local mouseX, mouseY = love.mouse.getPosition()
  local col, row = self:getTileAt(
    mouseX,
    mouseY,
    grid,
    camera
  )

  if col and not self:isOverHud(mouseX, mouseY) then
    local worldX, worldY = grid:tileCenter(col, row)
    local x, y = camera:worldToScreen(worldX, worldY)
    local size = grid.size * camera.zoom

    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)

    love.graphics.rectangle(
      "line",
      x - size / 2,
      y - size / 2,
      size,
      size
    )
  end

  local spawnX, spawnY = grid:tileCenter(
    self.spawnCol,
    self.spawnRow
  )

  spawnX, spawnY = camera:worldToScreen(
    spawnX,
    spawnY
  )

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
  love.graphics.rectangle(
    "fill",
    HUD_X,
    HUD_Y,
    HUD_W,
    HUD_H,
    6,
    6
  )

  local previousFont = love.graphics.getFont()
  local font = getHudFont()

  love.graphics.setFont(font)

  local textY = math.floor(
    (BUTTON_H - font:getHeight()) * 0.5
  )

  local tools = {
    { name = "ground", label = "Ground" },
    { name = "fire", label = "Fire" },
    { name = "snowflake", label = "Snowflake" },
    { name = "erase", label = "Erase" },
    { name = "save", label = "Save" },
    { name = "load", label = "Load" },
  }

  for index, tool in ipairs(tools) do
    local y = buttonY(index)

    if self.tool == tool.name
      or (tool.name == "load" and self.loadDropdownOpen) then

      if tool.name == "snowflake" then
        love.graphics.setColor(
          0.20,
          0.55,
          0.90,
          0.9
        )
      else
        love.graphics.setColor(
          0.18,
          0.58,
          0.86,
          0.8
        )
      end
    else
      love.graphics.setColor(
        0.10,
        0.20,
        0.31,
        0.9
      )
    end

    love.graphics.rectangle(
      "fill",
      BUTTON_X,
      y,
      BUTTON_W,
      BUTTON_H,
      4,
      4
    )

    love.graphics.setColor(0.92, 0.97, 1)
    love.graphics.print(
      tool.label,
      28,
      y + textY
    )
  end

  if self.loadDropdownOpen then
    local dx, dy, dw, dh = self:getDropdownRect()

    local listW = dw - (
      (#self.loadOptions > DROPDOWN_MAX_VISIBLE)
      and 14
      or 0
    )

    love.graphics.setColor(
      0.025,
      0.05,
      0.09,
      0.98
    )

    love.graphics.rectangle(
      "fill",
      dx,
      dy,
      dw,
      dh,
      6,
      6
    )

    love.graphics.setColor(
      0.18,
      0.58,
      0.86,
      0.7
    )

    love.graphics.setLineWidth(1)

    love.graphics.rectangle(
      "line",
      dx,
      dy,
      dw,
      dh,
      6,
      6
    )

    local itemTextY = math.floor(
      (DROPDOWN_ITEM_H - 2 - font:getHeight()) * 0.5
    )

    local visible = math.min(
      DROPDOWN_MAX_VISIBLE,
      #self.loadOptions
    )

    for i = 1, visible do
      local optionIndex = i + self.loadDropdownScroll
      local levelName = self.loadOptions[optionIndex]
      local itemY = dy + 4 + (i - 1) * DROPDOWN_ITEM_H

      local hovered =
        mouseX >= dx
        and mouseX <= dx + listW
        and mouseY >= itemY
        and mouseY < itemY + DROPDOWN_ITEM_H

      if levelName == self.currentLevelName then
        love.graphics.setColor(
          0.18,
          0.58,
          0.86,
          0.9
        )
      elseif hovered then
        love.graphics.setColor(
          0.14,
          0.36,
          0.55,
          0.95
        )
      else
        love.graphics.setColor(
          0.10,
          0.20,
          0.31,
          0.95
        )
      end

      love.graphics.rectangle(
        "fill",
        dx + 4,
        itemY,
        listW - 8,
        DROPDOWN_ITEM_H - 2,
        3,
        3
      )

      love.graphics.setColor(0.92, 0.97, 1)

      love.graphics.print(
        levelName,
        dx + 12,
        itemY + itemTextY
      )
    end

    local maxScroll = self:maxDropdownScroll()

    if maxScroll > 0 then
      local trackX = dx + dw - 10
      local trackY = dy + 6
      local trackH = dh - 12

      love.graphics.setColor(
        0.08,
        0.14,
        0.2,
        1
      )

      love.graphics.rectangle(
        "fill",
        trackX,
        trackY,
        5,
        trackH,
        2,
        2
      )

      local thumbH = math.max(
        16,
        trackH * (
          DROPDOWN_MAX_VISIBLE /
          #self.loadOptions
        )
      )

      local thumbY = trackY

      if maxScroll > 0 then
        thumbY = trackY
          + (trackH - thumbH)
          * (self.loadDropdownScroll / maxScroll)
      end

      love.graphics.setColor(
        0.35,
        0.7,
        0.95,
        0.95
      )

      love.graphics.rectangle(
        "fill",
        trackX,
        thumbY,
        5,
        thumbH,
        2,
        2
      )
    end
  end

  if self.status ~= "" and not self.namingOpen then
    love.graphics.setColor(
      0.025,
      0.05,
      0.09,
      0.9
    )

    love.graphics.rectangle(
      "fill",
      10,
      202,
      280,
      24,
      4,
      4
    )

    love.graphics.setColor(
      0.85,
      0.93,
      1
    )

    love.graphics.print(
      self.status,
      18,
      202 + textY
    )
  end

  if self.namingOpen then
    local nx, ny, nw, nh = self:getNamingRect()

    love.graphics.setColor(
      0,
      0,
      0,
      0.45
    )

    love.graphics.rectangle(
      "fill",
      0,
      0,
      love.graphics.getDimensions()
    )

    love.graphics.setColor(
      0.025,
      0.05,
      0.09,
      0.98
    )

    love.graphics.rectangle(
      "fill",
      nx,
      ny,
      nw,
      nh,
      8,
      8
    )

    love.graphics.setColor(
      0.18,
      0.58,
      0.86,
      0.8
    )

    love.graphics.setLineWidth(2)

    love.graphics.rectangle(
      "line",
      nx,
      ny,
      nw,
      nh,
      8,
      8
    )

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      "Name this level",
      nx + 16,
      ny + 14
    )

    local fieldX, fieldY, fieldW, fieldH =
      nx + 16,
      ny + 42,
      nw - 32,
      28

    love.graphics.setColor(
      0.08,
      0.16,
      0.24,
      1
    )

    love.graphics.rectangle(
      "fill",
      fieldX,
      fieldY,
      fieldW,
      fieldH,
      4,
      4
    )

    love.graphics.setColor(
      0.25,
      0.55,
      0.8,
      0.9
    )

    love.graphics.rectangle(
      "line",
      fieldX,
      fieldY,
      fieldW,
      fieldH,
      4,
      4
    )

    local display = self.namingText

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      display,
      fieldX + 8,
      fieldY + math.floor(
        (fieldH - font:getHeight()) * 0.5
      )
    )

    if math.floor(self.namingCursorBlink * 2) % 2 == 0 then
      local cursorX =
        fieldX + 8 + font:getWidth(display)

      love.graphics.rectangle(
        "fill",
        cursorX,
        fieldY + 6,
        2,
        fieldH - 12
      )
    end

    local saveX, saveY = nx + 16, ny + 82
    local cancelX = nx + nw - 16 - 90

    local saveHovered =
      mouseX >= saveX
      and mouseX <= saveX + 90
      and mouseY >= saveY
      and mouseY <= saveY + 28

    local cancelHovered =
      mouseX >= cancelX
      and mouseX <= cancelX + 90
      and mouseY >= saveY
      and mouseY <= saveY + 28

    love.graphics.setColor(
      saveHovered and 0.22 or 0.18,
      saveHovered and 0.66 or 0.58,
      saveHovered and 0.92 or 0.86,
      0.95
    )

    love.graphics.rectangle(
      "fill",
      saveX,
      saveY,
      90,
      28,
      4,
      4
    )

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      "Save",
      saveX + 28,
      saveY + 6
    )

    love.graphics.setColor(
      cancelHovered and 0.28 or 0.16,
      cancelHovered and 0.28 or 0.22,
      cancelHovered and 0.34 or 0.30,
      0.95
    )

    love.graphics.rectangle(
      "fill",
      cancelX,
      saveY,
      90,
      28,
      4,
      4
    )

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      "Cancel",
      cancelX + 20,
      saveY + 6
    )
  end

  love.graphics.setFont(previousFont)
end

return Editor
