local Player = {}
Player.__index = Player


function Player.new(col, row)
  return setmetatable({
    col = col,
    row = row,
    movesRemaining = 20,
    maxMoves = 20,
    startSize = 30,
    dead = false,
    movement = {
      active = false,
      elapsed = 0,
      duration = 0.14,
      fromCol = col,
      fromRow = row,
      toCol = col,
      toRow = row,
      moveCost = 0,
      deadly = false,
    },
  }, Player)
end


function Player:update(dt, grid)
  local movement = self.movement
  if not movement.active then
    return
  end


  movement.elapsed = math.min(movement.elapsed + dt, movement.duration)
  if movement.elapsed >= movement.duration then
    grid:addWater(movement.toCol, movement.toRow)
    grid:removeSnowflake(movement.toCol, movement.toRow)
    if movement.deadly then
      self.dead = true
      self.movesRemaining = 0
    end
    movement.active = false
  end
end


function Player:keypressed(key, grid)
  if self.dead or self.movesRemaining == 0 or self.movement.active then
    return
  end


  local col, row = self.col, self.row
  if key == "left" or key == "a" then
    col = col - 1
  elseif key == "right" or key == "d" then
    col = col + 1
  elseif key == "up" or key == "w" then
    row = row - 1
  elseif key == "down" or key == "s" then
    row = row + 1
  else
    return
  end


  col, row = grid:clamp(col, row)
  if (col == self.col and row == self.row) or not grid:hasGround(col, row) then
    return
  end


  local deadly = grid:isFireTile(col, row)
  local moveCost = deadly and 0 or math.min(grid:getMoveCost(col, row), self.movesRemaining)
  local movement = self.movement
  movement.active = true
  movement.elapsed = 0
  movement.fromCol = self.col
  movement.fromRow = self.row
  movement.toCol = col
  movement.toRow = row
  movement.moveCost = moveCost
  movement.deadly = deadly


  self.col = col
  self.row = row
  self.movesRemaining = self.movesRemaining - moveCost
end


function Player:getDrawState()
  local movement = self.movement
  local progress = 1
  if movement.active then
    progress = movement.elapsed / movement.duration
  end


  local easedProgress = progress * progress * (3 - 2 * progress)
  local displayedMoves = self.movesRemaining
  local col, row = self.col, self.row
  if movement.active then
    displayedMoves = displayedMoves + movement.moveCost * (1 - easedProgress)
    col = movement.fromCol + (movement.toCol - movement.fromCol) * easedProgress
    row = movement.fromRow + (movement.toRow - movement.fromRow) * easedProgress
  end


  return col, row, self.startSize * (displayedMoves / self.maxMoves)
end


function Player:draw(grid, camera)
  local col, row, size = self:getDrawState()
  if size <= 0 then
    return
  end


  local worldX, worldY = grid:tileCenter(col, row)
  local x, y = camera:worldToScreen(worldX, worldY)
  local screenSize = size * camera.zoom
  local halfSize = screenSize / 2
  local cornerRadius = math.min(8, screenSize / 5)


  love.graphics.setColor(0.66, 0.92, 1)
  love.graphics.rectangle(
    "fill",
    x - halfSize,
    y - halfSize,
    screenSize,
    screenSize,
    cornerRadius,
    cornerRadius
  )
  love.graphics.setColor(0.18, 0.58, 0.86)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle(
    "line",
    x - halfSize,
    y - halfSize,
    screenSize,
    screenSize,
    cornerRadius,
    cornerRadius
  )
end


function Player:drawHud()
  love.graphics.setColor(0.92, 0.97, 1)
  love.graphics.print("Ice Cube", 18, 14)
  love.graphics.setColor(0.58, 0.75, 0.9)
  if self.dead then
    love.graphics.print("The ice cube burned up! Press R to restart.", 18, 38)
  elseif self.movesRemaining > 0 then
    love.graphics.print("Moves until melted: " .. self.movesRemaining, 18, 38)
  else
    love.graphics.print("The ice cube has melted!", 18, 38)
  end
end


return Player
