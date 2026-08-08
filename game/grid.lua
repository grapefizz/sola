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
    iceTiles = {},
    snowflakeTiles = {},
    teaTiles = {},
    wallTiles = {},
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
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.wallTiles[key] = nil
end



function Grid:clear()
  self.groundTiles = {}
  self.waterTiles = {}
  self.fireTiles = {}
  self.iceTiles = {}
  self.snowflakeTiles = {}
  self.teaTiles = {}
  self.wallTiles = {}
end



function Grid:clearWater()
  self.waterTiles = {}
end



function Grid:addWater(col, row)
  if self:hasGround(col, row)
    and not self:isInFireZone(col, row)
    and not self:isIceTile(col, row)
    and not self:isTeaTile(col, row)
    and not self:isWallTile(col, row)
  then
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
  local key = self:key(col, row)
  self.waterTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.wallTiles[key] = nil
  self.fireTiles[key] = { col = col, row = row }
end



function Grid:removeFire(col, row)
  self.fireTiles[self:key(col, row)] = nil
end



function Grid:isFireTile(col, row)
  return self.fireTiles[self:key(col, row)] ~= nil
end

function Grid:addIce(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.waterTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.wallTiles[key] = nil
  self.iceTiles[key] = { col = col, row = row }
end

function Grid:removeIce(col, row)
  self.iceTiles[self:key(col, row)] = nil
end

function Grid:isIceTile(col, row)
  return self.iceTiles[self:key(col, row)] ~= nil
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

function Grid:addSnowflake(col, row)
  if not self:isInside(col, row) then
    return
  end
  if self:isInFireZone(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.teaTiles[key] = nil
  self.wallTiles[key] = nil
  self.snowflakeTiles[key] = { col = col, row = row }
end

function Grid:removeSnowflake(col, row)
  self.snowflakeTiles[self:key(col, row)] = nil
end

function Grid:consumeSnowflake(col, row)
  local key = self:key(col, row)
  if self.snowflakeTiles[key] then
    self.snowflakeTiles[key] = nil
    return true
  end
  return false
end

function Grid:hasSnowflake(col, row)
  return self.snowflakeTiles[self:key(col, row)] ~= nil
end

function Grid:isSnowflakeTile(col, row)
  return self.snowflakeTiles[self:key(col, row)] ~= nil
end

function Grid:addTea(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.wallTiles[key] = nil
  self.teaTiles[key] = { col = col, row = row }
end

function Grid:removeTea(col, row)
  self.teaTiles[self:key(col, row)] = nil
end

function Grid:isTeaTile(col, row)
  return self.teaTiles[self:key(col, row)] ~= nil
end

function Grid:addWall(col, row, texture, lean, options)
  if not self:isInside(col, row) then
    return
  end
  options = options or {}
  if texture ~= "side" and texture ~= "front" then
    texture = "front"
  end
  if lean ~= "left" and lean ~= "right" then
    lean = "left"
  end

  self:setGround(col, row)
  local key = self:key(col, row)
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.wallTiles[key] = {
    col = col,
    row = row,
    texture = texture,
    lean = texture == "side" and lean or nil,
    creased = options.creased and true or false,
  }
end

function Grid:removeWall(col, row)
  self.wallTiles[self:key(col, row)] = nil
end

function Grid:isWallTile(col, row)
  return self.wallTiles[self:key(col, row)] ~= nil
end

function Grid:getWallTexture(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  return wall and wall.texture or nil
end

function Grid:isSideWallTexture(col, row)
  return self:getWallTexture(col, row) == "side"
end

function Grid:isFrontWallTexture(col, row)
  return self:getWallTexture(col, row) == "front"
end

function Grid:getWallDrawKind(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  if not wall then
    return nil
  end
  if wall.texture == "side" then
    return "side", wall.creased and true or false
  end
  return "front", false
end

function Grid:getWallLean(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  if wall and wall.lean then
    return wall.lean
  end

  local hasLeft = self:isWallTile(col - 1, row)
  local hasRight = self:isWallTile(col + 1, row)

  if hasRight and not hasLeft then
    return "right"
  end
  if hasLeft and not hasRight then
    return "left"
  end

  local leftHits, rightHits = self:getWallColumnContacts(col, row)

  if rightHits > leftHits then
    return "right"
  end
  if leftHits > rightHits then
    return "left"
  end

  return "left"
end

function Grid:getWallColumnContacts(col, row)
  local leftHits, rightHits = 0, 0
  local scanRow = row

  while self:isWallTile(col, scanRow - 1) do
    scanRow = scanRow - 1
  end

  while self:isWallTile(col, scanRow) do
    if self:isWallTile(col - 1, scanRow) then
      leftHits = leftHits + 1
    end
    if self:isWallTile(col + 1, scanRow) then
      rightHits = rightHits + 1
    end
    scanRow = scanRow + 1
  end

  return leftHits, rightHits
end

function Grid:getSideWallStrip(col, row)
  local x = (col - 1) * self.size
  local stripW = self.size * 0.5
  local lean = self:getWallLean(col, row)
  local stripX = lean == "right" and (x + self.size - stripW) or x
  return stripX, stripW, stripX + stripW
end

function Grid:getConnectedSideWallFurthestRight(col, row)
  local furthest = nil
  local neighbors = {
    { col - 1, row },
    { col + 1, row },
    { col, row - 1 },
    { col, row + 1 },
  }

  for i = 1, #neighbors do
    local nc, nr = neighbors[i][1], neighbors[i][2]
    local wall = self.wallTiles[self:key(nc, nr)]
    if wall and wall.texture == "side" and not wall.creased then
      local _, _, right = self:getSideWallStrip(nc, nr)
      if not furthest or right > furthest then
        furthest = right
      end
    end
  end

  return furthest
end

function Grid:getMoveCost(col, row)
  if self:isSnowflakeTile(col, row) then
    return -1
  end
  if self:isIceTile(col, row) then
    return 0
  end
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
      elseif self:isTeaTile(col, row) then
        cells[col] = "T"
      elseif self:isIceTile(col, row) then
        cells[col] = "I"
      elseif self:isSnowflakeTile(col, row) then
        cells[col] = "S"
      elseif self:isWallTile(col, row) then
        local wall = self.wallTiles[self:key(col, row)]
        local lean = wall.lean or "left"
        if wall.texture == "front" then
          cells[col] = "W"
        elseif wall.creased then
          cells[col] = lean == "right" and "D" or "C"
        else
          cells[col] = lean == "right" and "E" or "V"
        end
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
      elseif cell == "I" then
        self:addIce(col, row)
      elseif cell == "S" then
        self:addSnowflake(col, row)
      elseif cell == "T" then
        self:addTea(col, row)
      elseif cell == "W" then
        self:addWall(col, row, "front", nil, { silent = true })
      elseif cell == "V" then
        self:addWall(col, row, "side", "left", { silent = true })
      elseif cell == "E" then
        self:addWall(col, row, "side", "right", { silent = true })
      elseif cell == "C" then
        self:addWall(col, row, "side", "left", { silent = true, creased = true })
      elseif cell == "D" then
        self:addWall(col, row, "side", "right", { silent = true, creased = true })
      end
    end
    row = row + 1
  end
end



function Grid:draw(zoom, camera)
  local width = self.columns * self.size
  local height = self.rows * self.size
  local minCol, maxCol = 1, self.columns
  local minRow, maxRow = 1, self.rows

  if camera then
    local screenWidth, screenHeight = love.graphics.getDimensions()
    local halfWidth = screenWidth / (camera.zoom * 2)
    local halfHeight = screenHeight / (camera.zoom * 2)
    minCol = math.max(1, math.floor((camera.x - halfWidth) / self.size) + 1)
    maxCol = math.min(self.columns, math.floor((camera.x + halfWidth) / self.size) + 1)
    minRow = math.max(1, math.floor((camera.y - halfHeight) / self.size) + 1)
    maxRow = math.min(self.rows, math.floor((camera.y + halfHeight) / self.size) + 1)
  end

  local function isVisible(tile, padding)
    padding = padding or 0
    return tile.col >= minCol - padding
      and tile.col <= maxCol + padding
      and tile.row >= minRow - padding
      and tile.row <= maxRow + padding
  end



  love.graphics.setColor(0.025, 0.05, 0.09)
  love.graphics.rectangle("fill", 0, 0, width, height)



  love.graphics.setColor(0.06, 0.16, 0.27)
  for row = minRow, maxRow do
    local runStart = nil
    for col = minCol, maxCol + 1 do
      if col <= maxCol and self:hasGround(col, row) then
        runStart = runStart or col
      elseif runStart then
        local x = (runStart - 1) * self.size
        local y = (row - 1) * self.size
        love.graphics.rectangle("fill", x + 1, y + 1, (col - runStart) * self.size - 2, self.size - 2)
        runStart = nil
      end
    end
  end

  for _, ice in pairs(self.iceTiles) do
    if isVisible(ice) then
    local x = (ice.col - 1) * self.size
    local y = (ice.row - 1) * self.size
    love.graphics.setColor(0.55, 0.82, 0.98, 0.55)
    love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
    love.graphics.setColor(0.85, 0.95, 1.0, 0.7)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.line(x + 8, y + 10, x + self.size - 14, y + self.size - 12)
    love.graphics.line(x + 12, y + 8, x + self.size - 10, y + self.size - 14)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.circle("fill", x + 11, y + 11, 2)
    end
  end

  for _, fire in pairs(self.fireTiles) do
    if isVisible(fire, self.fireRadius) then
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
  end

  for _, snowflake in pairs(self.snowflakeTiles) do
    if isVisible(snowflake) then
    local x = (snowflake.col - 1) * self.size
    local y = (snowflake.row - 1) * self.size
    love.graphics.setColor(0.08, 0.24, 0.42, 0.30)
    love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
    end
  end

  love.graphics.setLineWidth(1 / zoom)
  for _, tile in pairs(self.waterTiles) do
    if isVisible(tile) then
    local x = (tile.col - 1) * self.size
    local y = (tile.row - 1) * self.size
    love.graphics.setColor(0.10, 0.48, 0.72, 0.75)
    love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
    love.graphics.setColor(0.40, 0.78, 0.95, 0.65)
    love.graphics.line(x + 8, y + 13, x + self.size - 8, y + 13)
    end
  end

  for _, snowflake in pairs(self.snowflakeTiles) do
    if isVisible(snowflake) then
    local centerX, centerY = self:tileCenter(snowflake.col, snowflake.row)
    local halfWidth = self.size * 0.35
    local halfHeight = self.size * 0.25
    love.graphics.setColor(0.12, 0.48, 0.90, 0.9)
    love.graphics.polygon(
      "fill",
      centerX, centerY - halfHeight,
      centerX + halfWidth, centerY,
      centerX, centerY + halfHeight,
      centerX - halfWidth, centerY
    )
    love.graphics.setColor(0.55, 0.85, 1.0, 0.95)
    love.graphics.polygon(
      "fill",
      centerX, centerY - halfHeight * 0.5,
      centerX + halfWidth * 0.5, centerY,
      centerX, centerY + halfHeight * 0.5,
      centerX - halfWidth * 0.5, centerY
    )
    end
  end


  for _, tea in pairs(self.teaTiles) do
    if isVisible(tea) then
      local centerX, centerY = self:tileCenter(tea.col, tea.row)
      love.graphics.setColor(0.16, 0.08, 0.03, 0.35)
      love.graphics.ellipse("fill", centerX, centerY + 13, 13, 4)
      love.graphics.setColor(0.72, 0.34, 0.08, 0.95)
      love.graphics.polygon(
        "fill",
        centerX - 10, centerY - 10,
        centerX + 10, centerY - 10,
        centerX + 7, centerY + 13,
        centerX - 7, centerY + 13
      )
      love.graphics.setColor(0.78, 0.94, 1, 0.9)
      love.graphics.setLineWidth(1.5 / zoom)
      love.graphics.polygon(
        "line",
        centerX - 10, centerY - 10,
        centerX + 10, centerY - 10,
        centerX + 7, centerY + 13,
        centerX - 7, centerY + 13
      )
      love.graphics.ellipse("line", centerX, centerY - 10, 10, 3)
      love.graphics.setColor(0.76, 0.94, 1, 0.9)
      love.graphics.rectangle("fill", centerX - 5, centerY - 5, 5, 5, 1, 1)
      love.graphics.rectangle("fill", centerX + 2, centerY + 1, 4, 4, 1, 1)
      love.graphics.setColor(0.95, 0.35, 0.34)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(centerX + 4, centerY - 8, centerX + 10, centerY - 20)
    end
  end

  for _, wall in pairs(self.wallTiles) do
    if isVisible(wall) then
      local kind, creased = self:getWallDrawKind(wall.col, wall.row)
      if kind == "front" then
        local x = (wall.col - 1) * self.size
        local y = (wall.row - 1) * self.size
        love.graphics.setColor(0.55, 0.38, 0.28, 0.95)
        love.graphics.rectangle(
          "fill",
          x + 1,
          y + 1,
          self.size - 2,
          self.size - 2,
          2,
          2
        )
        love.graphics.setColor(0.78, 0.58, 0.42, 0.9)
        love.graphics.setLineWidth(1 / zoom)
        love.graphics.rectangle(
          "line",
          x + 1,
          y + 1,
          self.size - 2,
          self.size - 2,
          2,
          2
        )
      end
    end
  end

  -- Side walls (placed + front walls auto-converted where they touch a side wall)
  for _, wall in pairs(self.wallTiles) do
    if isVisible(wall) then
      local kind, creased = self:getWallDrawKind(wall.col, wall.row)
      if kind == "side" then
        local x = (wall.col - 1) * self.size
        local y = (wall.row - 1) * self.size
        local stripW = self.size * 0.5
        local stripX

        if creased then
          local furthestRight = self:getConnectedSideWallFurthestRight(wall.col, wall.row)
          if furthestRight then
            stripX = furthestRight - stripW
            stripX = math.max(x, math.min(x + self.size - stripW, stripX))
          else
            local lean = self:getWallLean(wall.col, wall.row)
            stripX = lean == "right" and (x + self.size - stripW) or x
          end
        else
          local lean = self:getWallLean(wall.col, wall.row)
          stripX = lean == "right" and (x + self.size - stripW) or x
        end

        love.graphics.setColor(0.32, 0.48, 0.62, 0.95)
        love.graphics.rectangle(
          "fill",
          stripX,
          y + 1,
          stripW,
          self.size - 2,
          2,
          2
        )
        love.graphics.setColor(0.55, 0.72, 0.88, 0.85)
        love.graphics.setLineWidth(1 / zoom)
        love.graphics.rectangle(
          "line",
          stripX,
          y + 1,
          stripW,
          self.size - 2,
          2,
          2
        )

        if creased then
          local creaseX = stripX + stripW
          local furthestRight = self:getConnectedSideWallFurthestRight(wall.col, wall.row)
          if furthestRight then
            creaseX = math.max(x + 1, math.min(x + self.size - 1, furthestRight))
          end
          love.graphics.setColor(0.16, 0.24, 0.34, 0.95)
          love.graphics.setLineWidth(2.5 / zoom)
          love.graphics.line(creaseX, y + 2, creaseX, y + self.size - 2)
          love.graphics.setColor(0.70, 0.84, 0.96, 0.55)
          love.graphics.setLineWidth(1 / zoom)
          love.graphics.line(creaseX - 2, y + 3, creaseX - 2, y + self.size - 3)
        end
      end
    end
  end

  love.graphics.setColor(0.13, 0.32, 0.47)
  for col = minCol - 1, maxCol do
    local x = col * self.size
    love.graphics.line(x, 0, x, height)
  end
  for row = minRow - 1, maxRow do
    local y = row * self.size
    love.graphics.line(0, y, width, y)
  end



  for _, fire in pairs(self.fireTiles) do
    if isVisible(fire) then
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
end



return Grid
