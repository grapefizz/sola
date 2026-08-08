local Player = {}
Player.__index = Player

local MOVE_DURATION = 0.14
local ICE_MOVE_DURATION = MOVE_DURATION / 1.25 -- 25% faster on ice
-- Cracked walls break when approaching at least this much faster than a normal step.
local SMASH_SPEED_FACTOR = 1.05

local function directionFromKey(key)
  if key == "left" or key == "a" then
    return -1, 0
  elseif key == "right" or key == "d" then
    return 1, 0
  elseif key == "up" or key == "w" then
    return 0, -1
  elseif key == "down" or key == "s" then
    return 0, 1
  end
  return nil, nil
end

function Player.new(col, row)
  return setmetatable({
    col = col,
    row = row,
    movesRemaining = 20,
    maxMoves = 20,
    startSize = 30,
    dead = false,
    won = false,
    movement = {
      active = false,
      elapsed = 0,
      duration = MOVE_DURATION,
      fromCol = col,
      fromRow = row,
      toCol = col,
      toRow = row,
      moveCost = 0,
      deadly = false,
    },
    slide = {
      active = false,
      dx = 0,
      dy = 0,
    },
  }, Player)
end

function Player:stopSlide()
  local slide = self.slide
  slide.active = false
  slide.dx = 0
  slide.dy = 0
end

function Player:currentSpeedFactor()
  local movement = self.movement
  if movement.active and movement.duration > 0 then
    return MOVE_DURATION / movement.duration
  end
  if self.slide.active then
    return MOVE_DURATION / ICE_MOVE_DURATION
  end
  return 1
end

function Player:canSmash(grid)
  if grid:isIceTile(self.col, self.row) then
    return true
  end
  return self:currentSpeedFactor() >= SMASH_SPEED_FACTOR
end

function Player:trySmashWallAhead(grid, col, row)
  col, row = grid:clamp(col, row)
  if (col == self.col and row == self.row)
    or not grid:isCrackedWall(col, row)
    or not self:canSmash(grid)
    or not grid:hasGround(col, row)
    or self.dead
    or self.won then
    return false
  end
  local deadly = grid:isFireTile(col, row)
  if not deadly and self.movesRemaining <= 0 and grid:getMoveCost(col, row) > 0 then
    return false
  end
  return grid:breakWall(col, row)
end

-- Cracked boulders smash under the same speed/ice rules, but the cube stops
-- on impact instead of continuing onto the cleared tile.
function Player:trySmashBoulderAhead(grid, col, row)
  col, row = grid:clamp(col, row)
  if (col == self.col and row == self.row)
    or not grid:isCrackedBoulder(col, row)
    or not self:canSmash(grid)
    or self.dead
    or self.won then
    return false
  end
  return grid:breakBoulder(col, row)
end

function Player:canStepTo(grid, col, row)
  col, row = grid:clamp(col, row)
  if (col == self.col and row == self.row)
    or not grid:hasGround(col, row)
    or grid:isBlocking(col, row) then
    return false
  end
  if self.dead or self.won then
    return false
  end
  local deadly = grid:isFireTile(col, row)
  if not deadly and self.movesRemaining <= 0 and grid:getMoveCost(col, row) > 0 then
    return false
  end
  return true, col, row, deadly
end

function Player:beginStep(grid, col, row, deadly)
  local rawCost = grid:getMoveCost(col, row)
  local moveCost = 0
  if not deadly then
    if rawCost < 0 then
      moveCost = -math.min(-rawCost, self.maxMoves - self.movesRemaining)
    else
      moveCost = math.min(rawCost, self.movesRemaining)
    end
  end

  local movement = self.movement
  movement.active = true
  movement.elapsed = 0
  movement.duration = grid:isIceTile(col, row) and ICE_MOVE_DURATION or MOVE_DURATION
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

function Player:continueSlide(grid)
  local slide = self.slide
  if not slide.active or self.dead or self.movement.active then
    return
  end

  if not grid:isIceTile(self.col, self.row) then
    self:stopSlide()
    return
  end

  local nextCol = self.col + slide.dx
  local nextRow = self.row + slide.dy
  if self:trySmashBoulderAhead(grid, nextCol, nextRow) then
    self:stopSlide()
    return
  end
  self:trySmashWallAhead(grid, nextCol, nextRow)
  local ok, col, row, deadly = self:canStepTo(grid, nextCol, nextRow)
  if not ok then
    self:stopSlide()
    return
  end

  self:beginStep(grid, col, row, deadly)
  if not grid:isIceTile(col, row) then
    self:stopSlide()
  end
end

function Player:update(dt, grid)
  local movement = self.movement
  if not movement.active then
    if self.slide.active then
      self:continueSlide(grid)
    end
    return
  end


  movement.elapsed = math.min(movement.elapsed + dt, movement.duration)
  if movement.elapsed >= movement.duration then
    grid:addWater(movement.toCol, movement.toRow)
    grid:consumeSnowflake(movement.toCol, movement.toRow)
    if movement.deadly then
      self.dead = true
      self.movesRemaining = 0
      self:stopSlide()
    elseif grid:isTeaTile(movement.toCol, movement.toRow) then
      self.won = true
      self:stopSlide()
    end
    movement.active = false
    if self.slide.active and not self.dead and not self.won then
      self:continueSlide(grid)
    end
  end
end


function Player:keypressed(key, grid)
  if self.dead or self.won then
    return
  end

  local dx, dy = directionFromKey(key)
  if not dx then
    return
  end

  -- Locked in until the slide hits something.
  if self.movement.active or self.slide.active then
    return
  end

  if self.movesRemaining == 0 then
    return
  end

  local nextCol, nextRow = self.col + dx, self.row + dy
  if self:trySmashBoulderAhead(grid, nextCol, nextRow) then
    self:stopSlide()
    return
  end
  self:trySmashWallAhead(grid, nextCol, nextRow)
  local ok, col, row, deadly = self:canStepTo(grid, nextCol, nextRow)
  if not ok then
    return
  end

  self:beginStep(grid, col, row, deadly)

  if grid:isIceTile(col, row) then
    local slide = self.slide
    slide.active = true
    slide.dx = dx
    slide.dy = dy
  else
    self:stopSlide()
  end
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
  if self.won then
    love.graphics.print("Iced tea reached! Level complete.", 18, 38)
  elseif self.dead then
    love.graphics.print("The ice cube burned up! Press R to restart.", 18, 38)
  elseif self.movesRemaining > 0 then
    love.graphics.print("Moves until melted: " .. self.movesRemaining, 18, 38)
  else
    love.graphics.print("The ice cube has melted!", 18, 38)
  end
end


return Player
