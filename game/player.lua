local Player = {}
Player.__index = Player

local Perspective = require "game.perspective"

local MOVE_DURATION = 0.14
local ICE_MOVE_DURATION = MOVE_DURATION / 1.25
local SMASH_SPEED_FACTOR = 1.05
local PLAYER_FRAME_SIZE = 128
local PLAYER_FRAME_DURATION = 1 / 12
local MELT_TIME = 40

local PLAYER_SHEET_PATHS = {
  idle = "assets/player-sheet.png",
  down = "assets/player-down.png",
  up = "assets/player-up.png",
  side = "assets/player-side.png",
}

local PLAYER_FRAME_COUNTS = {
  idle = 18,
  down = 26,
  up = 26,
  side = 25,
}
local playerAnimations = {}

local function getPlayerAnimation(key)
  local cached = playerAnimations[key]
  if cached then
    return cached
  end

  local path = PLAYER_SHEET_PATHS[key] or PLAYER_SHEET_PATHS.idle
  local image = love.graphics.newImage(path)
  image:setFilter("linear", "linear")
  local maxFrames = math.floor(image:getWidth() / PLAYER_FRAME_SIZE)
  local frameCount = math.min(PLAYER_FRAME_COUNTS[key] or maxFrames, maxFrames)
  local frames = {}
  for index = 1, frameCount do
    frames[index] = love.graphics.newQuad(
      (index - 1) * PLAYER_FRAME_SIZE,
      0,
      PLAYER_FRAME_SIZE,
      PLAYER_FRAME_SIZE,
      image:getDimensions()
    )
  end

  local animation = { image = image, frames = frames, frameCount = frameCount }
  playerAnimations[key] = animation
  return animation
end

local function pickPlayerAnimation(mode, facingDx, facingDy, isMoving)
  if not isMoving then
    return "idle", false
  end
  if mode == "side" then
    return "side", facingDx < 0
  end
  if facingDy < 0 then
    return "up", false
  end
  if facingDy > 0 then
    return "down", false
  end
  if facingDx ~= 0 then
    return "side", facingDx < 0
  end
  return "down", false
end

function Player.drawSprite(x, y, size, time, mode, facingDx, facingDy, isMoving)
  time = time or ((love.timer and love.timer.getTime()) or 0)
  mode = mode or Perspective.mode
  facingDx = facingDx or 0
  facingDy = facingDy or 1
  if isMoving == nil then
    isMoving = false
  end

  local key, flip = pickPlayerAnimation(mode, facingDx, facingDy, isMoving)
  local animation = getPlayerAnimation(key)
  local frameIndex = math.floor(time / PLAYER_FRAME_DURATION) % animation.frameCount + 1
  local mirror = flip and -1 or 1

  if mode == "side" then
    -- Stand the ice-cube sprite on the floor with a tiny depth cue.
    local body = size
    local depth = size * 0.16
    local right = x + body * 0.42
    local top = y - body
    local bottom = y

    love.graphics.setColor(0.42, 0.70, 0.90, 0.55)
    love.graphics.polygon(
      "fill",
      right, top + 4,
      right + depth, top - depth * 0.35,
      right + depth, bottom - depth * 0.35,
      right, bottom - 2
    )

    local scale = body / PLAYER_FRAME_SIZE
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      animation.image,
      animation.frames[frameIndex],
      x,
      y,
      0,
      scale * mirror,
      scale,
      PLAYER_FRAME_SIZE / 2,
      PLAYER_FRAME_SIZE
    )
    return
  end

  local scale = size / PLAYER_FRAME_SIZE
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    animation.image,
    animation.frames[frameIndex],
    x,
    y,
    0,
    scale * mirror,
    scale,
    PLAYER_FRAME_SIZE / 2,
    PLAYER_FRAME_SIZE / 2
  )
end

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

function Player.new(col, row, timeLimit)
  timeLimit = tonumber(timeLimit) or MELT_TIME
  timeLimit = math.max(0, math.min(999, math.floor(timeLimit)))
  return setmetatable({
    col = col,
    row = row,
    timeRemaining = timeLimit,
    maxTime = timeLimit,
    startSize = 42,
    dead = false,
    won = false,
    heldItem = nil, 
    facingDx = 0,
    facingDy = -1,
    jumpFacingDx = 1,
    movement = {
      active = false,
      elapsed = 0,
      duration = MOVE_DURATION,
      fromCol = col,
      fromRow = row,
      toCol = col,
      toRow = row,
      timeCost = 0,
      deadly = false,
      jumping = false,
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

function Player:sizeRatio()
  if self.maxTime <= 0 then
    return 0
  end
  return math.max(0, self.timeRemaining / self.maxTime)
end

function Player:isMelted()
  return self.timeRemaining <= 0 and not self.dead
end

function Player:trySmashWallAhead(grid, col, row)
  col, row = grid:clamp(col, row)
  if (col == self.col and row == self.row)
    or not grid:isCrackedWall(col, row)
    or not self:canSmash(grid)
    or not grid:hasGround(col, row)
    or self.dead
    or self.won
    or self:isMelted() then
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
    or self.won
    or self:isMelted() then
    return false
  end
  return grid:breakBoulder(col, row)
end

function Player:canStepTo(grid, col, row)
  col, row = grid:clamp(col, row)
  local sizeRatio = self:sizeRatio()
  if (col == self.col and row == self.row)
    or not grid:hasGround(col, row)
    or grid:isBlocking(col, row, sizeRatio) then
    return false
  end
  if self.dead or self.won or self:isMelted() then
    return false
  end
  local deadly = grid:isFireTile(col, row)
  return true, col, row, deadly
end

-- Solid obstacles you cannot vault over (or land on) with a jump.
function Player:isJumpBlocked(grid, col, row)
  if grid:isBoulderTile(col, row) then
    return true
  end
  if not grid:isWallTile(col, row) then
    return false
  end
  local wall = grid.wallTiles[grid:key(col, row)]
  if wall.texture == "side" then
    return true
  end
  if wall.half or wall.depth == "behind" then
    return false
  end
  return true
end

-- Landing tile after skipping one block (must be walkable ground).
function Player:canJumpLand(grid, col, row)
  col, row = grid:clamp(col, row)
  if (col == self.col and row == self.row)
    or not grid:hasGround(col, row)
    or self.dead
    or self.won
    or self:isMelted()
    or self:isJumpBlocked(grid, col, row) then
    return false
  end
  local deadly = grid:isFireTile(col, row)
  return true, col, row, deadly
end

function Player:canJumpOver(grid, col, row)
  if not grid:isInside(col, row) then
    return false
  end
  return not self:isJumpBlocked(grid, col, row)
end

function Player:applyTimeDelta(delta)
  if delta == 0 then
    return 0
  end
  local applied = delta
  if delta < 0 then
    applied = -math.min(-delta, self.maxTime - self.timeRemaining)
  else
    applied = math.min(delta, self.timeRemaining)
  end
  self.timeRemaining = self.timeRemaining - applied
  return applied
end

function Player:beginStep(grid, col, row, deadly, jumping)
  local timeCost = 0
  if not deadly then
    timeCost = self:applyTimeDelta(grid:getTimeDelta(col, row))
  end

  local movement = self.movement
  movement.active = true
  movement.elapsed = 0
  local base = grid:isIceTile(col, row) and ICE_MOVE_DURATION or MOVE_DURATION
  movement.duration = jumping and (base * 1.25) or base
  movement.fromCol = self.col
  movement.fromRow = self.row
  movement.toCol = col
  movement.toRow = row
  movement.timeCost = timeCost
  movement.deadly = deadly
  movement.jumping = jumping and true or false

  self.col = col
  self.row = row
end

function Player:inSideView(grid)
  if next(grid.sideViewTiles) then
    return grid:isSideView(self.col, self.row)
  end
  return Perspective.isSide()
end

function Player:tryJump(grid)
  if self.dead or self.won or self:isMelted() or self.movement.active then
    return false
  end
  if not self:inSideView(grid) then
    return false
  end

  local dx = self.jumpFacingDx
  if dx ~= 1 and dx ~= -1 then
    dx = (self.facingDx == -1) and -1 or 1
  end

  local overCol = self.col + dx
  local overRow = self.row
  if not self:canJumpOver(grid, overCol, overRow) then
    return false
  end

  local candidates = {
    { col = self.col + dx * 2, row = self.row - 1, needArc = true },
    { col = self.col + dx * 2, row = self.row, needArc = false },
  }

  local landCol, landRow, deadly
  for _, candidate in ipairs(candidates) do
    if candidate.needArc and not self:canJumpOver(grid, overCol, self.row - 1) then
    
    else
      local ok, col, row, tileDeadly = self:canJumpLand(grid, candidate.col, candidate.row)
      if ok then
        landCol, landRow, deadly = col, row, tileDeadly
        break
      end
    end
  end

  if not landCol then
    return false
  end

  self.facingDx = dx
  self.facingDy = 0
  self.jumpFacingDx = dx

  self:stopSlide()
  self:beginStep(grid, landCol, landRow, deadly, true)
  if grid:isIceTile(landCol, landRow) then
    local slide = self.slide
    slide.active = true
    slide.dx = dx
    slide.dy = 0
  else
    self:stopSlide()
  end
  return true
end

function Player:continueSlide(grid)
  local slide = self.slide
  if not slide.active or self.dead or self:isMelted() or self.movement.active then
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

  self:beginStep(grid, col, row, deadly, false)
  if not grid:isIceTile(col, row) then
    self:stopSlide()
  end
end

function Player:update(dt, grid)
  grid:updatePressurePlates(self.col, self.row, self:sizeRatio())
  if not self.dead and not self.won and self.timeRemaining > 0 then
    self.timeRemaining = math.max(0, self.timeRemaining - dt)
  end

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

    -- Pick up a puzzle piece if hands are empty; deposit into canvas if holding one.
    if self.heldItem == nil and grid:isPuzzlePiece(movement.toCol, movement.toRow) then
      if grid:consumePuzzlePiece(movement.toCol, movement.toRow) then
        self.heldItem = "puzzle_piece"
      end
    elseif self.heldItem == "puzzle_piece" and grid:isPuzzleCanvas(movement.toCol, movement.toRow) then
      if grid:tryDepositPuzzlePiece(movement.toCol, movement.toRow) then
        self.heldItem = nil
      end
    end

    if movement.deadly then
      self.dead = true
      self.timeRemaining = 0
      self:stopSlide()
    elseif grid:isTeaTile(movement.toCol, movement.toRow) then
      if grid:isTeaUnlocked() then
        self.won = true
        self:stopSlide()
      end
    end
    grid:updatePressurePlates(self.col, self.row, self:sizeRatio())
    movement.active = false
    if self.slide.active and not self.dead and not self.won and not self:isMelted() then
      self:continueSlide(grid)
    end
  end
end


function Player:keypressed(key, grid)
  if self.dead or self.won or self:isMelted() then
    return
  end

  if key == "space" then
    if self.movement.active or self.slide.active then
      return
    end
    self:tryJump(grid)
    return
  end

  local dx, dy = directionFromKey(key)
  if not dx then
    return
  end

  self.facingDx = dx
  self.facingDy = dy
  if dx ~= 0 then
    self.jumpFacingDx = dx
  end

  -- Locked in until the slide hits something.
  if self.movement.active or self.slide.active then
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

  self:beginStep(grid, col, row, deadly, false)

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
  local displayedTime = self.timeRemaining
  local col, row = self.col, self.row
  if movement.active then
    displayedTime = displayedTime + movement.timeCost * (1 - easedProgress)
    col = movement.fromCol + (movement.toCol - movement.fromCol) * easedProgress
    row = movement.fromRow + (movement.toRow - movement.fromRow) * easedProgress
  end

  local hop = 0
  if movement.active and movement.jumping then
    hop = math.sin(easedProgress * math.pi)
  end

  local sizeRatio = self.maxTime > 0 and (displayedTime / self.maxTime) or 0
  return col, row, self.startSize * math.max(0, sizeRatio), hop
end


function Player:draw(grid, camera)
  local col, row, size, hop = self:getDrawState()
  if size <= 0 then
    return
  end

  local sampleCol = math.floor(col + 0.5)
  local sampleRow = math.floor(row + 0.5)
  local mode
  if next(grid.sideViewTiles) then
    mode = grid:isSideView(sampleCol, sampleRow) and "side" or "topdown"
  else
    mode = Perspective.mode
  end

  local worldX, worldY = Perspective.tileCenter(col, row, grid.size, mode)
  if hop and hop > 0 then
    worldY = worldY - hop * grid.size * 0.75
  end

  local x, y = camera:worldToScreen(worldX, worldY)
  local screenSize = size * camera.zoom

  local facingDx = (mode == "side") and self.jumpFacingDx or self.facingDx
  local isMoving = self.movement.active or self.slide.active
  Player.drawSprite(x, y, screenSize, nil, mode, facingDx, self.facingDy, isMoving)

  if self.heldItem == "puzzle_piece" then
    local pieceSize = math.max(10, screenSize * 0.55)
    local ox = mode == "side" and screenSize * 0.55 or screenSize * 0.55
    local oy = mode == "side" and -screenSize * 0.55 or -screenSize * 0.35
    local px, py = x + ox, y + oy
    local s = pieceSize * 0.42
    love.graphics.setColor(0.08, 0.08, 0.10, 0.98)
    love.graphics.polygon(
      "fill",
      px - s, py - s * 0.55,
      px - s * 0.22, py - s * 0.55,
      px - s * 0.22, py - s,
      px + s * 0.22, py - s,
      px + s * 0.22, py - s * 0.55,
      px + s, py - s * 0.55,
      px + s, py + s * 0.15,
      px + s * 0.55, py + s * 0.15,
      px + s * 0.55, py + s * 0.55,
      px + s, py + s * 0.55,
      px + s, py + s,
      px - s, py + s
    )
  end
end


function Player:drawHud(grid)
  love.graphics.setColor(0.92, 0.97, 1)
  love.graphics.print("Ice Cube", 18, 14)
  love.graphics.setColor(0.58, 0.75, 0.9)
  if self.won then
    love.graphics.print("Iced tea reached! Level complete.", 18, 38)
  elseif self.dead then
    love.graphics.print("The ice cube burned up!", 18, 38)
  elseif self.timeRemaining > 0 then
    local seconds = math.ceil(self.timeRemaining)
    local line = "Time until melted: " .. seconds .. "s"
    if grid and self:inSideView(grid) then
      line = line .. "  ·  Space to jump"
    end
    if self.heldItem == "puzzle_piece" then
      line = line .. "  ·  Holding puzzle piece"
    end
    love.graphics.print(line, 18, 38)
    if grid and grid:hasPuzzleCanvas() and not grid:isTeaUnlocked() then
      love.graphics.setColor(0.75, 0.72, 0.55)
      love.graphics.print("Find puzzle pieces and place them on the canvas.", 18, 58)
    elseif grid and grid:isTeaTile(self.col, self.row) and not grid:isTeaUnlocked() then
      love.graphics.setColor(0.85, 0.65, 0.45)
      love.graphics.print("Complete the puzzle to unlock the iced tea.", 18, 58)
    end
  else
    love.graphics.print("The ice cube has melted!", 18, 38)
  end
end


return Player
