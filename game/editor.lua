local Editor = {}
Editor.__index = Editor

local SAVE_FILE = "level.txt"

function Editor.new(spawnCol, spawnRow)
  return setmetatable({
    active = false,
    tool = "ground",
    spawnCol = spawnCol,
    spawnRow = spawnRow,
    status = "",
    panSpeed = 260,
  }, Editor)
end

function Editor:setActive(active)
  self.active = active
  self.status = active and "Editor enabled" or ""
end

function Editor:isOverHud(x, y)
  return x >= 10 and x <= 330 and y >= 70 and y <= 238
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

function Editor:applyTool(tool, col, row, grid)
  if not col or (col == self.spawnCol and row == self.spawnRow) then
    if col then
      self.status = "The spawn tile is protected"
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

function Editor:mousepressed(x, y, button, grid, camera)
  if button ~= 1 and button ~= 2 then
    return
  end

  if button == 1 and x >= 24 and x <= 316 then
    if y >= 112 and y <= 136 then
      self.tool = "ground"
      return
    elseif y >= 140 and y <= 164 then
      self.tool = "fire"
      return
    elseif y >= 168 and y <= 192 then
      self.tool = "erase"
      return
    end
  end
  self:paintAt(x, y, button, grid, camera)
end

function Editor:keypressed(key, grid)
  if key == "1" then
    self.tool = "ground"
  elseif key == "2" then
    self.tool = "fire"
  elseif key == "3" then
    self.tool = "erase"
  elseif key == "c" then
    grid:clear()
    self:protectSpawn(grid)
    self.status = "Level cleared"
  elseif key == "f" then
    for row = 1, grid.rows do
      for col = 1, grid.columns do
        grid:setGround(col, row)
      end
    end
    self.status = "Ground filled"
  elseif key == "s" then
    local success, message = love.filesystem.write(SAVE_FILE, grid:serialize())
    self.status = success and "Saved as " .. SAVE_FILE or "Save failed: " .. tostring(message)
  elseif key == "l" then
    if love.filesystem.getInfo(SAVE_FILE) then
      local contents, message = love.filesystem.read(SAVE_FILE)
      if contents then
        grid:load(contents)
        self:protectSpawn(grid)
        self.status = "Loaded " .. SAVE_FILE
      else
        self.status = "Load failed: " .. tostring(message)
      end
    else
      self.status = "No saved level found"
    end
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
  local dx, dy = 0, 0
  if love.keyboard.isDown("left", "a") then dx = dx - 1 end
  if love.keyboard.isDown("right", "d") then dx = dx + 1 end
  if love.keyboard.isDown("up", "w") then dy = dy - 1 end
  if love.keyboard.isDown("down", "s") then dy = dy + 1 end
  camera.x = camera.x + dx * self.panSpeed * dt / camera.zoom
  camera.y = camera.y + dy * self.panSpeed * dt / camera.zoom
  self:clampCamera(grid, camera)

  local x, y = love.mouse.getPosition()
  if love.mouse.isDown(1) then
    self:paintAt(x, y, 1, grid, camera)
  elseif love.mouse.isDown(2) then
    self:paintAt(x, y, 2, grid, camera)
  end
end

function Editor:wheelmoved(y, grid, camera)
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
  love.graphics.rectangle("fill", 10, 70, 320, 168, 6, 6)
  love.graphics.setColor(0.92, 0.97, 1)
  love.graphics.print("LEVEL EDITOR", 24, 82)

  local tools = {
    { key = "1", name = "ground", label = "Ground" },
    { key = "2", name = "fire", label = "Fire" },
    { key = "3", name = "erase", label = "Erase" },
  }
  for index, tool in ipairs(tools) do
    local y = 112 + (index - 1) * 28
    if self.tool == tool.name then
      love.graphics.setColor(0.18, 0.58, 0.86, 0.8)
    else
      love.graphics.setColor(0.10, 0.20, 0.31, 0.9)
    end
    love.graphics.rectangle("fill", 24, y, 292, 24, 4, 4)
    love.graphics.setColor(0.92, 0.97, 1)
    love.graphics.print(tool.key .. "  " .. tool.label, 34, y + 4)
  end

  love.graphics.setColor(0.58, 0.75, 0.9)
  love.graphics.print("Drag to paint · Right-click erase", 24, 202)
  love.graphics.print("WASD pan · Wheel zoom · E play", 24, 218)
  love.graphics.print("S save · L load · C clear · F fill", 350, 18)
  if self.status ~= "" then
    love.graphics.print(self.status, 350, 38)
  end
end

return Editor
