local Grid = {}
Grid.__index = Grid

function Grid.new(size, columns, rows)
  return setmetatable({
    size = size,
    columns = columns,
    rows = rows,
    waterTiles = {},
  }, Grid)
end

function Grid:key(col, row)
  return col .. "," .. row
end

function Grid:addWater(col, row)
  self.waterTiles[self:key(col, row)] = { col = col, row = row }
end

function Grid:hasWater(col, row)
  return self.waterTiles[self:key(col, row)] ~= nil
end

function Grid:clamp(col, row)
  return math.max(1, math.min(self.columns, col)),
    math.max(1, math.min(self.rows, row))
end

function Grid:tileCenter(col, row)
  return (col - 0.5) * self.size, (row - 0.5) * self.size
end

function Grid:draw(zoom)
  local width = self.columns * self.size
  local height = self.rows * self.size

  love.graphics.setColor(0.06, 0.16, 0.27)
  love.graphics.rectangle("fill", 0, 0, width, height)

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
end

return Grid
