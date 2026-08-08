local Player = {}
Player.__index = Player

local Perspective = require "game.perspective"

local MOVE_DURATION = 0.14
local ICE_MOVE_DURATION = MOVE_DURATION / 1.25 -- 25% faster on ice
-- Cracked walls break when approaching at least this much faster than a normal step.
local SMASH_SPEED_FACTOR = 1.05
local PLAYER_FRAME_SIZE = 128
local PLAYER_FRAME_COUNT = 18
local PLAYER_FRAME_DURATION = 1 / 12
local playerAnimation

local function getPlayerAnimation()
  if not playerAnimation then
    local image = love.graphics.newImage("assets/player-sheet.png")
    image:setFilter("linear", "linear")
    local frames = {}
    for index = 1, PLAYER_FRAME_COUNT do
      frames[index] = love.graphics.newQuad(
        (index - 1) * PLAYER_FRAME_SIZE,
        0,
        PLAYER_FRAME_SIZE,
        PLAYER_FRAME_SIZE,
        image:getDimensions()
      )
    end
    playerAnimation = { image = image, frames = frames }
  end
  return playerAnimation
end

function Player.drawSprite(x, y, size, time, mode)
  local animation = getPlayerAnimation()
  time = time or ((love.timer and love.timer.getTime()) or 0)
  local frameIndex = math.floor(time / PLAYER_FRAME_DURATION) % PLAYER_FRAME_COUNT + 1
  mode = mode or Perspective.mode

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
      scale,
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
    scale,
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

function Player.new(col, row)
  return setmetatable({
    col = col,
    row = row,
    movesRemaining = 20,
    maxMoves = 20,
    startSize = 30,
    dead = false,
    won = false,
    heldItem = nil, -- "puzzle_piece" or nil (one at a time)
    facingDx = 0,
    facingDy = -1,
    -- Last left/right facing used for side-view jumps.
    jumpFacingDx = 1,
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
  local sizeRatio = self.maxMoves > 0 and (self.movesRemaining / self.maxMoves) or 0
  if (col == self.col and row == self.row)
    or not grid:hasGround(col, row)
    or grid:isBlocking(col, row, sizeRatio) then
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
    or self:isJumpBlocked(grid, col, row) then
    return false
  end
  local deadly = grid:isFireTile(col, row)
  if not deadly and self.movesRemaining <= 0 and grid:getMoveCost(col, row) > 0 then
    return false
  end
  return true, col, row, deadly
end

-- Middle tile being vaulted: fire / ground / half-wall / gap OK; full walls & boulders block.
function Player:canJumpOver(grid, col, row)
  if not grid:isInside(col, row) then
    return false
  end
  return not self:isJumpBlocked(grid, col, row)
end

function Player:beginStep(grid, col, row, deadly, jumping)
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
  local base = grid:isIceTile(col, row) and ICE_MOVE_DURATION or MOVE_DURATION
  movement.duration = jumping and (base * 1.25) or base
  movement.fromCol = self.col
  movement.fromRow = self.row
  movement.toCol = col
  movement.toRow = row
  movement.moveCost = moveCost
  movement.deadly = deadly
  movement.jumping = jumping and true or false

  self.col = col
  self.row = row
  self.movesRemaining = self.movesRemaining - moveCost
end

function Player:inSideView(grid)
  if next(grid.sideViewTiles) then
    return grid:isSideView(self.col, self.row)
  end
  return Perspective.isSide()
end

-- Space jump: vault one block over; prefer landing one block higher when possible.
function Player:tryJump(grid)
  if self.dead or self.won or self.movement.active then
    return false
  end
  if not self:inSideView(grid) then
    return false
  end
  if self.movesRemaining == 0 then
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

  -- Prefer the big hop (two over, one up). Fall back to same-height vault.
  local candidates = {
    { col = self.col + dx * 2, row = self.row - 1, needArc = true },
    { col = self.col + dx * 2, row = self.row, needArc = false },
  }

  local landCol, landRow, deadly
  for _, candidate in ipairs(candidates) do
    if candidate.needArc and not self:canJumpOver(grid, overCol, self.row - 1) then
      -- Ceiling / wall in the arc — skip the high landing.
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

  self:beginStep(grid, col, row, deadly, false)
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
      self.movesRemaining = 0
      self:stopSlide()
    elseif grid:isTeaTile(movement.toCol, movement.toRow) then
      if grid:isTeaUnlocked() then
        self.won = true
        self:stopSlide()
      end
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
  local displayedMoves = self.movesRemaining
  local col, row = self.col, self.row
  if movement.active then
    displayedMoves = displayedMoves + movement.moveCost * (1 - easedProgress)
    col = movement.fromCol + (movement.toCol - movement.fromCol) * easedProgress
    row = movement.fromRow + (movement.toRow - movement.fromRow) * easedProgress
  end

  local hop = 0
  if movement.active and movement.jumping then
    hop = math.sin(easedProgress * math.pi)
  end

  return col, row, self.startSize * (displayedMoves / self.maxMoves), hop
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
  Player.drawSprite(x, y, screenSize, nil, mode)

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
    love.graphics.print("The ice cube burned up! Press R to restart.", 18, 38)
  elseif self.movesRemaining > 0 then
    local line = "Moves until melted: " .. self.movesRemaining
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
