local Grid = {}
Grid.__index = Grid

function Grid.new(size, columns, rows, fillGround)
  local self = setmetatable({
    size = size,
    columns = columns,
    rows = rows,
    groundTiles = {},
    waterTiles = {},
    fireTiles = {},
    fireRadius = 1,
  }, Grid)

  if fillGround ~= false then
    for row = 1, rows do
      for col = 1, columns do
        self:setGround(col, row)
      end
    end
  end
  return self
end

function Grid:key(col, row)
  return col .. "," .. row
end

function Grid:isInside(col, row)
  return col >= 1 and col <= self.columns and row >= 1 and row <= self.rows
end

function Grid:clamp(col, row)
  return math.max(1, math.min(self.columns, col)),
    math.max(1, math.min(self.rows, row))
end

function Grid:tileCenter(col, row)
  return (col - 0.5) * self.size, (row - 0.5) * self.size
end

function Grid:setGround(col, row)
  if self:isInside(col, row) then
    self.groundTiles[self:key(col, row)] = { col = col, row = row }
  end
end

function Grid:hasGround(col, row)
  return self.groundTiles[self:key(col, row)] ~= nil
end

function Grid:erase(col, row)
  local key = self:key(col, row)
  self.groundTiles[key] = nil
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
end

function Grid:clear()
  self.groundTiles = {}
  self.waterTiles = {}
  self.fireTiles = {}
end

function Grid:clearWater()
  self.waterTiles = {}
end

function Grid:addWater(col, row)
  if self:hasGround(col, row) and not self:isInFireZone(col, row) then
    self.waterTiles[self:key(col, row)] = { col = col, row = row }
  end
end

function Grid:hasWater(col, row)
  return self.waterTiles[self:key(col, row)] ~= nil
end

function Grid:addFire(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  self.waterTiles[self:key(col, row)] = nil
  self.fireTiles[self:key(col, row)] = { col = col, row = row }
end

function Grid:removeFire(col, row)
  self.fireTiles[self:key(col, row)] = nil
end

function Grid:isFireTile(col, row)
  return self.fireTiles[self:key(col, row)] ~= nil
end

function Grid:isInFireZone(col, row)
  for _, fire in pairs(self.fireTiles) do
    if math.abs(col - fire.col) <= self.fireRadius
      and math.abs(row - fire.row) <= self.fireRadius then
      return true
    end
  end
  return false
end

function Grid:getMoveCost(col, row)
  if self:isInFireZone(col, row) then
    return 2
  end
  return self:hasWater(col, row) and 0 or 1
end

function Grid:serialize()
  local lines = {}
  for row = 1, self.rows do
    local cells = {}
    for col = 1, self.columns do
      if self:isFireTile(col, row) then
        cells[col] = "F"
      elseif self:hasGround(col, row) then
        cells[col] = "#"
      else
        cells[col] = "."
      end
    end
    lines[row] = table.concat(cells)
  end
  return table.concat(lines, "\n")
end

function Grid:load(serialized)
  self:clear()
  local row = 1
  for line in serialized:gmatch("[^\r\n]+") do
    if row > self.rows then
      break
    end
    for col = 1, math.min(#line, self.columns) do
      local cell = line:sub(col, col)
      if cell == "#" then
        self:setGround(col, row)
      elseif cell == "F" then
        self:addFire(col, row)
      end
    end
    row = row + 1
  end
end

function Grid:draw(zoom)
  local width = self.columns * self.size
  local height = self.rows * self.size

  love.graphics.setColor(0.025, 0.05, 0.09)
  love.graphics.rectangle("fill", 0, 0, width, height)

  for _, tile in pairs(self.groundTiles) do
    local x = (tile.col - 1) * self.size
    local y = (tile.row - 1) * self.size
    love.graphics.setColor(0.06, 0.16, 0.27)
    love.graphics.rectangle("fill", x + 1, y + 1, self.size - 2, self.size - 2)
  end

  for _, fire in pairs(self.fireTiles) do
    love.graphics.setColor(0.65, 0.20, 0.06, 0.24)
    for row = fire.row - self.fireRadius, fire.row + self.fireRadius do
      for col = fire.col - self.fireRadius, fire.col + self.fireRadius do
        if self:hasGround(col, row) then
          local x = (col - 1) * self.size
          local y = (row - 1) * self.size
          love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
        end
      end
    end
  end

  love.graphics.setLineWidth(1 / zoom)
  for _, tile in pairs(self.waterTiles) do
    local x = (tile.col - 1) * self.size
    local y = (tile.row - 1) * self.size
    love.graphics.setColor(0.10, 0.48, 0.72, 0.75)
    love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
    love.graphics.setColor(0.40, 0.78, 0.95, 0.65)
    love.graphics.line(x + 8, y + 13, x + self.size - 8, y + 13)
  end

  love.graphics.setColor(0.13, 0.32, 0.47)
  for col = 0, self.columns do
    local x = col * self.size
    love.graphics.line(x, 0, x, height)
  end
  for row = 0, self.rows do
    local y = row * self.size
    love.graphics.line(0, y, width, y)
  end

  for _, fire in pairs(self.fireTiles) do
    local centerX, centerY = self:tileCenter(fire.col, fire.row)
    love.graphics.setColor(0.95, 0.24, 0.04)
    love.graphics.polygon(
      "fill",
      centerX, centerY - 15,
      centerX + 12, centerY + 12,
      centerX - 12, centerY + 12
    )
    love.graphics.setColor(1.00, 0.76, 0.12)
    love.graphics.polygon(
      "fill",
      centerX, centerY - 6,
      centerX + 6, centerY + 10,
      centerX - 6, centerY + 10
    )
  end
end

return Grid
