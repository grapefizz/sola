local Grid = {}
Grid.__index = Grid

local Perspective = require "game.perspective"

local TEXTURE_GRID_SIZE = 1
local FIRE_FRAME_SIZE = 128
local FIRE_FRAME_COUNT = 9
local FIRE_FRAME_DURATION = 1 / 12
local DEFAULT_SNOWFLAKE_SECONDS = 3
local PUDDLE_FRAME_SIZE = 256
local PUDDLE_FRAME_COUNT = 15
local PUDDLE_FRAME_DURATION = 1 / 14
local PUDDLE_ANIMATION_DURATION = PUDDLE_FRAME_COUNT * PUDDLE_FRAME_DURATION
-- Extra linger after the last drippy pose so the dissolve finishes softly.
local PUDDLE_FADE_DURATION = 0.35
local PUDDLE_LIFETIME = PUDDLE_ANIMATION_DURATION + PUDDLE_FADE_DURATION
-- Visible water sits low in the source frame; keep it centered on the tile.
local PUDDLE_CONTENT_CENTER_Y = 216
local tileSprites

Grid.DEFAULT_SNOWFLAKE_SECONDS = DEFAULT_SNOWFLAKE_SECONDS
local groundQuadCache = {}
local iceQuadCache = {}
local mossQuadCache = {}
local wallQuadCache = {}

local function getTileSprites()
  if tileSprites then
    return tileSprites
  end

  tileSprites = {
    ground = love.graphics.newImage("assets/floor.png"),
    ice = love.graphics.newImage("assets/ice.png"),
    moss = love.graphics.newImage("assets/moss.png"),
    mossSide = love.graphics.newImage("assets/moss-side.png"),
    snowflake = love.graphics.newImage("assets/snowflake.png"),
    fire = love.graphics.newImage("assets/fire-sheet.png"),
    keyTop = love.graphics.newImage("assets/key-top.png"),
    keyDown = love.graphics.newImage("assets/key-down.png"),
    keyPieceTop = love.graphics.newImage("assets/key-piece-top.png"),
    keyPieceBottom = love.graphics.newImage("assets/key-piece-bottom.png"),
    keyPieceTopSide = love.graphics.newImage("assets/key-piece-top-side.png"),
    keyPieceBottomSide = love.graphics.newImage("assets/key-piece-bottom-side.png"),
    boulder = love.graphics.newImage("assets/rock.png"),
    boulder2 = love.graphics.newImage("assets/rock2.png"),
    crackedBoulder = love.graphics.newImage("assets/rockbroken.png"),
    buttonUnpressed = love.graphics.newImage("assets/Button unpressed.png"),
    buttonPressed = love.graphics.newImage("assets/PRESSED BUTTON FINA.png"),
    doorClosed = love.graphics.newImage("assets/door-closed.png"),
    doorOpen = love.graphics.newImage("assets/door-open.png"),
    wall = love.graphics.newImage("assets/wall.png"),
    brickEnd = love.graphics.newImage("assets/Brickend.png"),
    wallHalf2 = love.graphics.newImage("assets/wall-half2.png"),
    puddleLong = love.graphics.newImage("assets/puddlelong.png"),
    puddleDrag = love.graphics.newImage("assets/puddledrag-sheet.png"),
  }
  tileSprites.ground:setFilter("linear", "linear")
  tileSprites.ice:setFilter("linear", "linear")
  tileSprites.moss:setFilter("linear", "linear")
  tileSprites.mossSide:setFilter("linear", "linear")
  tileSprites.snowflake:setFilter("linear", "linear")
  tileSprites.fire:setFilter("linear", "linear")
  tileSprites.keyTop:setFilter("linear", "linear")
  tileSprites.keyDown:setFilter("linear", "linear")
  tileSprites.keyPieceTop:setFilter("linear", "linear")
  tileSprites.keyPieceBottom:setFilter("linear", "linear")
  tileSprites.keyPieceTopSide:setFilter("linear", "linear")
  tileSprites.keyPieceBottomSide:setFilter("linear", "linear")
  tileSprites.boulder:setFilter("linear", "linear")
  tileSprites.boulder2:setFilter("linear", "linear")
  tileSprites.crackedBoulder:setFilter("linear", "linear")
  tileSprites.buttonUnpressed:setFilter("linear", "linear")
  tileSprites.buttonPressed:setFilter("linear", "linear")
  tileSprites.doorClosed:setFilter("linear", "linear")
  tileSprites.doorOpen:setFilter("linear", "linear")
  tileSprites.wall:setFilter("linear", "linear")
  tileSprites.brickEnd:setFilter("linear", "linear")
  tileSprites.wallHalf2:setFilter("linear", "linear")
  tileSprites.puddleLong:setFilter("linear", "linear")
  tileSprites.puddleDrag:setFilter("linear", "linear")
  tileSprites.puddleDragFrames = {}
  for index = 1, PUDDLE_FRAME_COUNT do
    tileSprites.puddleDragFrames[index] = love.graphics.newQuad(
      (index - 1) * PUDDLE_FRAME_SIZE,
      0,
      PUDDLE_FRAME_SIZE,
      PUDDLE_FRAME_SIZE,
      tileSprites.puddleDrag:getDimensions()
    )
  end
  tileSprites.fireFrames = {}
  for index = 1, FIRE_FRAME_COUNT do
    tileSprites.fireFrames[index] = love.graphics.newQuad(
      (index - 1) * FIRE_FRAME_SIZE,
      0,
      FIRE_FRAME_SIZE,
      FIRE_FRAME_SIZE,
      tileSprites.fire:getDimensions()
    )
  end
  tileSprites.ground:setWrap("repeat", "repeat")
  tileSprites.ice:setWrap("repeat", "repeat")
  tileSprites.moss:setWrap("repeat", "repeat")
  tileSprites.mossSide:setWrap("repeat", "repeat")
  return tileSprites
end

local function drawWallTexture(image, x, y, width, height, tileSize, alpha, align)
  local imageWidth, imageHeight = image:getDimensions()
  local sourceWidth = math.max(1, imageWidth * math.min(1, width / tileSize))
  local sourceHeight = math.max(1, imageHeight * math.min(1, height / tileSize))
  local sourceX
  if align == "left" then
    sourceX = 0
  elseif align == "right" then
    sourceX = imageWidth - sourceWidth
  else
    sourceX = (imageWidth - sourceWidth) * 0.5
  end
  local sourceY = imageHeight - sourceHeight
  local key = table.concat({
    imageWidth,
    imageHeight,
    math.floor(sourceX + 0.5),
    math.floor(sourceY + 0.5),
    math.floor(sourceWidth + 0.5),
    math.floor(sourceHeight + 0.5),
  }, ":")
  local quad = wallQuadCache[key]
  if not quad then
    quad = love.graphics.newQuad(sourceX, sourceY, sourceWidth, sourceHeight, imageWidth, imageHeight)
    wallQuadCache[key] = quad
  end
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(image, quad, x, y, 0, width / sourceWidth, height / sourceHeight)
end

local function drawSideWallTexture(image, x, y, width, height, tileSize, alpha, lean)
  local imageWidth, imageHeight = image:getDimensions()
  local scaleX = width / imageWidth
  local scaleY = height / imageHeight
  love.graphics.setColor(1, 1, 1, alpha or 1)
  if lean == "left" then
    love.graphics.draw(image, x + width, y, 0, -scaleX, scaleY)
  else
    love.graphics.draw(image, x, y, 0, scaleX, scaleY)
  end
end

local function getTextureQuad(image, cache, col, row, length)
  local cellWidth = image:getWidth() / TEXTURE_GRID_SIZE
  local cellHeight = image:getHeight() / TEXTURE_GRID_SIZE
  local textureCol = (col - 1) % TEXTURE_GRID_SIZE
  local textureRow = (row - 1) % TEXTURE_GRID_SIZE
  local key = textureCol .. ":" .. textureRow .. ":" .. length

  if not cache[key] then
    cache[key] = love.graphics.newQuad(
      textureCol * cellWidth,
      textureRow * cellHeight,
      length * cellWidth,
      cellHeight,
      image:getDimensions()
    )
  end
  return cache[key], cellWidth, cellHeight
end



function Grid.new(size, columns, rows, fillGround)
  local self = setmetatable({
    size = size,
    columns = columns,
    rows = rows,
    spawnCol = math.ceil(columns / 2),
    spawnRow = math.ceil(rows / 2),
    groundTiles = {},
    puddleTiles = {},
    fireTiles = {},
    iceTiles = {},
    mossTiles = {},
    snowflakeTiles = {},
    teaTiles = {},
    fridgeTiles = {},
    puzzlePieceTiles = {}, -- key halves on the ground
    puzzleDoorTiles = {}, -- key doors (opened with a full key)
    pressureDoorTiles = {},
    pressurePlateTiles = {},
    pressureDoorOpen = false,
    wallTiles = {},
    boulderTiles = {},
    -- Painted zones: side-view presentation + jump. Default (absent) = top-down.
    sideViewTiles = {},
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

function Grid:isSpawnTile(col, row)
  return col == self.spawnCol and row == self.spawnRow
end



function Grid:isInside(col, row)
  return col >= 1 and col <= self.columns and row >= 1 and row <= self.rows
end



function Grid:clamp(col, row)
  return math.max(1, math.min(self.columns, col)),
    math.max(1, math.min(self.rows, row))
end



function Grid:tileCenter(col, row)
  local sampleCol = math.floor(col + 0.5)
  local sampleRow = math.floor(row + 0.5)
  local mode = self:isSideView(sampleCol, sampleRow) and "side" or "topdown"
  -- Editor / empty levels with no zones still honor the global preview toggle.
  if not next(self.sideViewTiles) then
    mode = Perspective.mode
  end
  return Perspective.tileCenter(col, row, self.size, mode)
end

function Grid:tileOrigin(col, row)
  return Perspective.tileOrigin(col, row, self.size)
end

function Grid:worldBounds()
  return Perspective.worldBounds(self.columns, self.rows, self.size)
end

-- Tight bounds around painted tiles (for previews / unculled draws).
function Grid:occupiedBounds(padding)
  padding = padding or 2
  local minCol, maxCol, minRow, maxRow

  local function consider(tiles)
    for _, tile in pairs(tiles) do
      if not minCol or tile.col < minCol then minCol = tile.col end
      if not maxCol or tile.col > maxCol then maxCol = tile.col end
      if not minRow or tile.row < minRow then minRow = tile.row end
      if not maxRow or tile.row > maxRow then maxRow = tile.row end
    end
  end

  consider(self.groundTiles)
  consider(self.fireTiles)
  consider(self.iceTiles)
  consider(self.mossTiles)
  consider(self.snowflakeTiles)
  consider(self.teaTiles)
  consider(self.fridgeTiles)
  consider(self.puzzlePieceTiles)
  consider(self.puzzleDoorTiles)
  consider(self.pressureDoorTiles)
  consider(self.pressurePlateTiles)
  consider(self.wallTiles)
  consider(self.boulderTiles)
  consider(self.sideViewTiles)

  if not minCol then
    return 1, self.columns, 1, self.rows
  end

  return math.max(1, minCol - padding),
    math.min(self.columns, maxCol + padding),
    math.max(1, minRow - padding),
    math.min(self.rows, maxRow + padding)
end

function Grid:visibleDrawRange(camera)
  if camera then
    return Perspective.visibleTileRange(
      camera,
      self.size,
      self.columns,
      self.rows
    )
  end
  return self:occupiedBounds(Perspective.isSide() and 4 or 2)
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
  local wall = self.wallTiles[key]
  if wall then
    -- A joined side wall is the top wall layer; reveal its half/front wall
    -- underneath and require another erase before touching the terrain.
    if wall.texture == "side" and wall.under then
      local under = wall.under
      self.wallTiles[key] = {
        col = col,
        row = row,
        texture = "front",
        lean = nil,
        creased = false,
        cracked = under.cracked and true or false,
        half = under.half and true or false,
        fill = under.fill,
        depth = under.depth or "behind",
        under = nil,
      }
    else
      self.wallTiles[key] = nil
    end
    return "wall"
  end

  local objectLayers = {
    { self.boulderTiles, "boulder" },
    { self.fireTiles, "fire" },
    { self.snowflakeTiles, "snowflake" },
    { self.teaTiles, "tea" },
    { self.fridgeTiles, "fridge" },
    { self.puzzlePieceTiles, "puzzle_piece" },
    { self.puzzleDoorTiles, "puzzle_door" },
    { self.pressureDoorTiles, "pressure_door" },
    { self.pressurePlateTiles, "pressure_plate" },
  }
  for _, layer in ipairs(objectLayers) do
    if layer[1][key] then
      layer[1][key] = nil
      return layer[2]
    end
  end

  if self.iceTiles[key] then
    self.iceTiles[key] = nil
    return "ice"
  end
  if self.mossTiles[key] then
    self.mossTiles[key] = nil
    return "moss"
  end
  if self.groundTiles[key] then
    self.groundTiles[key] = nil
    return "ground"
  end
  if self.sideViewTiles[key] then
    self.sideViewTiles[key] = nil
    return "perspective"
  end
  return nil
end



function Grid:clear()
  self.groundTiles = {}
  self.puddleTiles = {}
  self.fireTiles = {}
  self.iceTiles = {}
  self.mossTiles = {}
  self.snowflakeTiles = {}
  self.teaTiles = {}
  self.fridgeTiles = {}
  self.puzzlePieceTiles = {}
  self.puzzleDoorTiles = {}
  self.pressureDoorTiles = {}
  self.pressurePlateTiles = {}
  self.pressureDoorOpen = false
  self.wallTiles = {}
  self.boulderTiles = {}
  self.sideViewTiles = {}
end

function Grid:clearPuddles()
  self.puddleTiles = {}
end

function Grid:addPuddleTrail(col, row, targetCol, targetRow)
  -- Only the tile immediately behind the player owns the drag effect. A new
  -- step replaces an unfinished animation instead of leaving several behind.
  self.puddleTiles = {}
  if self:isInside(col, row) then
    self.puddleTiles[self:key(col, row)] = {
      col = col,
      row = row,
      age = 0,
      elapsed = 0,
      dx = (targetCol or col) - col,
      dy = (targetRow or row) - row,
      targetCol = targetCol or col,
      targetRow = targetRow or row,
    }
  end
end

function Grid:setPuddleTarget(col, row)
  for _, puddle in pairs(self.puddleTiles) do
    puddle.targetCol = col
    puddle.targetRow = row
  end
end

function Grid:updatePuddles(dt)
  for key, puddle in pairs(self.puddleTiles) do
    puddle.age = (puddle.age or 0) + dt
    puddle.elapsed = math.min(
      (puddle.elapsed or 0) + dt,
      PUDDLE_ANIMATION_DURATION
    )
    if puddle.age >= PUDDLE_LIFETIME then
      self.puddleTiles[key] = nil
    end
  end
end

local function puddleAlpha(puddle)
  local age = puddle.age or 0
  if age <= PUDDLE_ANIMATION_DURATION then
    return 1
  end
  local t = math.min(1, (age - PUDDLE_ANIMATION_DURATION) / PUDDLE_FADE_DURATION)
  return 1 - (t * t * (3 - 2 * t))
end

-- Crossfade between consecutive sheet frames for a seamless drip dissolve.
local function puddleFrameBlend(sprites, puddle)
  local elapsed = math.max(0, puddle.elapsed or 0)
  local pos = 1 + math.min(1, elapsed / PUDDLE_ANIMATION_DURATION)
    * (PUDDLE_FRAME_COUNT - 1)
  local index = math.min(PUDDLE_FRAME_COUNT, math.floor(pos))
  local frac = pos - index
  local fromQuad = sprites.puddleDragFrames[index]
  if index >= PUDDLE_FRAME_COUNT then
    return fromQuad, fromQuad, 0
  end
  local blend = frac * frac * (3 - 2 * frac)
  return fromQuad, sprites.puddleDragFrames[index + 1], blend
end

local function puddleMirror(puddle)
  -- Keep the art floor-oriented for every direction so up/down stays a puddle,
  -- not a rotated ribbon. Mirror so the drip fingers trail away from the player.
  if (puddle.dx or 0) > 0 then return -1 end
  if (puddle.dy or 0) > 0 then return -1 end
  return 1
end

local function puddleDirection(puddle)
  local dx = puddle.dx or 0
  local dy = puddle.dy or 0
  return dx == 0 and 0 or (dx > 0 and 1 or -1),
    dy == 0 and 0 or (dy > 0 and 1 or -1)
end

local function puddleScales(puddle, tileSize, frameWidth, frameHeight)
  local mirror = puddleMirror(puddle)
  local directionX, directionY = puddleDirection(puddle)
  -- Full tile coverage; floor-oriented band stays the natural puddle thickness.
  local scaleAlong = mirror * tileSize / frameWidth
  local scaleAcross = tileSize / frameHeight
  local contentShiftY = (PUDDLE_CONTENT_CENTER_Y / PUDDLE_FRAME_SIZE - 0.5)
    * frameHeight * scaleAcross
  return scaleAlong, scaleAcross, directionX, directionY, contentShiftY
end

local function drawPuddleDrag(sprites, puddle, x, y, scaleAlong, scaleAcross)
  local fromQuad, toQuad, blend = puddleFrameBlend(sprites, puddle)
  local alpha = puddleAlpha(puddle)
  local ox = PUDDLE_FRAME_SIZE * 0.5
  local oy = PUDDLE_FRAME_SIZE * 0.5
  if blend <= 0.001 then
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
      sprites.puddleDrag, fromQuad, x, y, 0, scaleAlong, scaleAcross, ox, oy
    )
    return
  end
  if blend < 0.999 then
    love.graphics.setColor(1, 1, 1, alpha * (1 - blend))
    love.graphics.draw(
      sprites.puddleDrag, fromQuad, x, y, 0, scaleAlong, scaleAcross, ox, oy
    )
  end
  love.graphics.setColor(1, 1, 1, alpha * blend)
  love.graphics.draw(
    sprites.puddleDrag, toQuad, x, y, 0, scaleAlong, scaleAcross, ox, oy
  )
end

local function eachPuddleBridgeTile(puddle, callback)
  local dx = (puddle.targetCol or puddle.col) - puddle.col
  local dy = (puddle.targetRow or puddle.row) - puddle.row
  local stepX = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local stepY = dy == 0 and 0 or (dy > 0 and 1 or -1)
  local distance = math.max(math.abs(dx), math.abs(dy))
  for step = 1, distance - 1 do
    callback(puddle.col + stepX * step, puddle.row + stepY * step)
  end
end

function Grid:addSideView(col, row)
  if not self:isInside(col, row) then
    return
  end
  self.sideViewTiles[self:key(col, row)] = { col = col, row = row }
end

function Grid:removeSideView(col, row)
  self.sideViewTiles[self:key(col, row)] = nil
end

function Grid:isSideView(col, row)
  return self.sideViewTiles[self:key(col, row)] ~= nil
end

function Grid:toggleSideView(col, row)
  if self:isSideView(col, row) then
    self:removeSideView(col, row)
    return false
  end
  self:addSideView(col, row)
  return true
end



function Grid:addFire(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.iceTiles[key] = nil
  self.mossTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
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
  self.mossTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  -- Keep transparent side / half wall overlays sitting on this ice.
  local wall = self.wallTiles[key]
  if wall and not (wall.texture == "side" or wall.half) then
    self.wallTiles[key] = nil
  end
  -- Keep boulder, puzzle pieces, and pressure plates so ice can sit under them.
  self.iceTiles[key] = { col = col, row = row }
end

function Grid:removeIce(col, row)
  self.iceTiles[self:key(col, row)] = nil
end

function Grid:isIceTile(col, row)
  return self.iceTiles[self:key(col, row)] ~= nil
end

function Grid:addMoss(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  local wall = self.wallTiles[key]
  if wall and not (wall.texture == "side" or wall.half) then
    self.wallTiles[key] = nil
  end
  -- Keep boulder, puzzle pieces, and pressure plates so moss can sit under them.
  self.mossTiles[key] = { col = col, row = row }
end

function Grid:removeMoss(col, row)
  self.mossTiles[self:key(col, row)] = nil
end

function Grid:isMossTile(col, row)
  return self.mossTiles[self:key(col, row)] ~= nil
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

function Grid:addSnowflake(col, row, seconds)
  if not self:isInside(col, row) then
    return
  end
  if self:isInFireZone(col, row) then
    return
  end
  seconds = tonumber(seconds) or DEFAULT_SNOWFLAKE_SECONDS
  seconds = math.max(1, math.min(99, math.floor(seconds)))
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.mossTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  local wall = self.wallTiles[key]
  if wall and not (wall.texture == "side" or wall.half) then
    self.wallTiles[key] = nil
  end
  self.boulderTiles[key] = nil
  self.snowflakeTiles[key] = { col = col, row = row, seconds = seconds }
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

function Grid:getSnowflakeSeconds(col, row)
  local flake = self.snowflakeTiles[self:key(col, row)]
  if not flake then
    return 0
  end
  return flake.seconds or DEFAULT_SNOWFLAKE_SECONDS
end

function Grid:addTea(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.mossTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.teaTiles[key] = { col = col, row = row }
end

function Grid:removeTea(col, row)
  self.teaTiles[self:key(col, row)] = nil
end

function Grid:isTeaTile(col, row)
  return self.teaTiles[self:key(col, row)] ~= nil
end

function Grid:addFridge(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.fridgeTiles[key] = { col = col, row = row }
end

function Grid:removeFridge(col, row)
  self.fridgeTiles[self:key(col, row)] = nil
end

function Grid:isFridgeTile(col, row)
  return self.fridgeTiles[self:key(col, row)] ~= nil
end

function Grid:getFirstFridge()
  local first
  for _, fridge in pairs(self.fridgeTiles) do
    if not first
      or fridge.row < first.row
      or (fridge.row == first.row and fridge.col < first.col) then
      first = fridge
    end
  end
  return first
end

-- Key half on the ground (serialized as J/q = top, M/m = down).
function Grid:addPuzzlePiece(col, row, variant)
  if not self:isInside(col, row) then
    return
  end
  if self:isInFireZone(col, row) then
    return
  end
  if variant ~= "down" then
    variant = "top"
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.puzzlePieceTiles[key] = { col = col, row = row, variant = variant }
end

function Grid:removePuzzlePiece(col, row)
  self.puzzlePieceTiles[self:key(col, row)] = nil
end

function Grid:consumePuzzlePiece(col, row)
  local key = self:key(col, row)
  local piece = self.puzzlePieceTiles[key]
  if piece then
    self.puzzlePieceTiles[key] = nil
    return true, piece.variant or "top"
  end
  return false
end

function Grid:isPuzzlePiece(col, row)
  return self.puzzlePieceTiles[self:key(col, row)] ~= nil
end

function Grid:getKeyVariant(col, row)
  local piece = self.puzzlePieceTiles[self:key(col, row)]
  return piece and (piece.variant or "top") or nil
end

-- Compatibility shims: canvas tool removed; old levels ignore "A" cells.
function Grid:removePuzzleCanvas(col, row)
end

function Grid:isPuzzleCanvas(col, row)
  return false
end

function Grid:hasKeyDoor()
  for _, door in pairs(self.puzzleDoorTiles) do
    if not door.open then
      return true
    end
  end
  return false
end

-- Tea locks only while key doors remain. Levels with no key doors stay unlocked.
function Grid:isTeaUnlocked()
  return not self:hasKeyDoor()
end

-- Key door (serialized as L). Opens when walked into while holding a full key.
function Grid:addPuzzleDoor(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.mossTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.puzzleDoorTiles[key] = { col = col, row = row, open = false }
end

function Grid:removePuzzleDoor(col, row)
  self.puzzleDoorTiles[self:key(col, row)] = nil
end

-- Closed key doors only (open doors stay drawn but are walkable).
function Grid:isPuzzleDoor(col, row)
  local door = self.puzzleDoorTiles[self:key(col, row)]
  return door ~= nil and not door.open
end

function Grid:openPuzzleDoor(col, row)
  local key = self:key(col, row)
  local door = self.puzzleDoorTiles[key]
  if door and not door.open then
    door.open = true
    return true
  end
  return false
end

function Grid:openPuzzleDoors()
  for _, door in pairs(self.puzzleDoorTiles) do
    door.open = true
  end
end

function Grid:addPressureDoor(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.pressureDoorTiles[key] = { col = col, row = row }
end

function Grid:removePressureDoor(col, row)
  self.pressureDoorTiles[self:key(col, row)] = nil
end

function Grid:isPressureDoor(col, row)
  return self.pressureDoorTiles[self:key(col, row)] ~= nil
end

function Grid:addPressurePlate(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.pressurePlateTiles[key] = { col = col, row = row, pressed = false }
end

function Grid:removePressurePlate(col, row)
  self.pressurePlateTiles[self:key(col, row)] = nil
end

function Grid:isPressurePlate(col, row)
  return self.pressurePlateTiles[self:key(col, row)] ~= nil
end

function Grid:updatePressurePlates(playerCol, playerRow, sizeRatio)
  for _, plate in pairs(self.pressurePlateTiles) do
    if not plate.pressed
      and plate.col == playerCol
      and plate.row == playerRow
      and (sizeRatio or 0) > 0.6 then
      plate.pressed = true
      self.pressureDoorOpen = true
    end
  end
end

function Grid:isPressureDoorOpen()
  return self.pressureDoorOpen
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

  local depth = options.depth == "behind" and "behind" or "front"
  -- Side walls always live on the front layer.
  if texture == "side" then
    depth = "front"
  end

  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil

  local fill = nil
  if options.half then
    fill = tonumber(options.fill) or 0.5
    fill = math.max(0.1, math.min(0.9, fill))
    fill = math.floor(fill * 10 + 0.5) / 10
    texture = "front"
  end

  -- Side / half walls are transparent overlays: keep floor props and boulders.
  local overlay = texture == "side" or options.half
  if not overlay then
    self.iceTiles[key] = nil
    self.mossTiles[key] = nil
    self.snowflakeTiles[key] = nil
    self.boulderTiles[key] = nil
  end

  local existing = self.wallTiles[key]
  local under = nil
  local align = nil
  if options.half and not options.half2 and options.align == "up" then
    align = "up"
  end
  local half2 = options.half and options.half2 and true or false
  local halfLean = nil
  if half2 then
    halfLean = lean == "right" and "right" or "left"
  end

  -- Side walls can share a cell with behind walls and half walls.
  if texture == "side" and existing then
    if existing.texture == "front" and (existing.depth == "behind" or existing.half) then
      under = {
        texture = "front",
        depth = "behind",
        cracked = existing.cracked and true or false,
        half = existing.half and true or false,
        fill = existing.fill,
        align = existing.align == "up" and "up" or nil,
        half2 = existing.half2 and true or false,
        lean = existing.half2 and (existing.lean == "right" and "right" or "left") or nil,
      }
    elseif existing.under then
      under = existing.under
    end
  end

  -- Painting a half wall over a side wall joins both in the same grid cell.
  if texture == "front" and (depth == "behind" or options.half) and existing and existing.texture == "side" then
    existing.under = {
      texture = "front",
      depth = "behind",
      cracked = options.cracked and true or false,
      half = options.half and true or false,
      fill = fill,
      align = align,
      half2 = half2,
      lean = halfLean,
    }
    return
  end

  self.wallTiles[key] = {
    col = col,
    row = row,
    texture = texture,
    lean = halfLean or (texture == "side" and lean or nil),
    creased = options.creased and true or false,
    cracked = options.cracked and true or false,
    half = options.half and true or false,
    fill = fill,
    align = align,
    half2 = half2,
    depth = depth,
    under = under,
  }
end

function Grid:removeWall(col, row)
  self.wallTiles[self:key(col, row)] = nil
end

function Grid:breakWall(col, row)
  local key = self:key(col, row)
  local wall = self.wallTiles[key]
  if not wall or not wall.cracked then
    return false
  end
  -- Breaking a cracked side wall may leave the behind under-wall.
  if wall.texture == "side" and wall.under then
    local under = wall.under
    self.wallTiles[key] = {
      col = col,
      row = row,
      texture = "front",
      lean = nil,
      creased = false,
      cracked = under.cracked and true or false,
      half = under.half and true or false,
      fill = under.fill,
      align = under.align == "up" and "up" or nil,
      half2 = under.half2 and true or false,
      lean = under.half2 and (under.lean == "right" and "right" or "left") or nil,
      depth = "behind",
      under = nil,
    }
    return true
  end
  self.wallTiles[key] = nil
  return true
end

function Grid:isWallTile(col, row)
  return self.wallTiles[self:key(col, row)] ~= nil
end

function Grid:isCrackedWall(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  return wall ~= nil and wall.cracked == true
end

function Grid:isHalfWall(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  if not wall then
    return false
  end
  if wall.half then
    return true
  end
  return wall.under ~= nil and wall.under.half == true and wall.texture ~= "side"
end

function Grid:getHalfWallFill(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  if wall and wall.half then
    return wall.fill or 0.5
  end
  return nil
end

-- "down" = slab on the bottom / floor; "up" = flipped to the top / ceiling.
function Grid:getHalfWallAlign(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  if not wall then
    return nil
  end
  if wall.half then
    return wall.align == "up" and "up" or "down"
  end
  if wall.under and wall.under.half then
    return wall.under.align == "up" and "up" or "down"
  end
  return nil
end

function Grid:getWallDepth(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  if not wall then
    return nil
  end
  return wall.depth or "front"
end

function Grid:getUnderWall(col, row)
  local wall = self.wallTiles[self:key(col, row)]
  return wall and wall.under or nil
end

-- sizeRatio is timeRemaining/maxTime (1 = full cube). Bigger fill = taller wall = smaller cube required.
-- Bottom half-walls used to be crawlable when melted; all wall tiles are solid now.
function Grid:canPassHalfWall(col, row, sizeRatio)
  return false
end

function Grid:addBoulder(col, row, options)
  if not self:isInside(col, row) then
    return
  end
  options = options or {}
  self:setGround(col, row)
  local key = self:key(col, row)
  self.fireTiles[key] = nil
  -- Keep ice so the boulder can sit on top of it.
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  local wall = self.wallTiles[key]
  if wall and not (wall.texture == "side" or wall.half) then
    self.wallTiles[key] = nil
  end
  self.boulderTiles[key] = {
    col = col,
    row = row,
    cracked = options.cracked and true or false,
    variant = options.variant == 2 and 2 or 1,
  }
end

function Grid:removeBoulder(col, row)
  self.boulderTiles[self:key(col, row)] = nil
end

function Grid:breakBoulder(col, row)
  local key = self:key(col, row)
  local boulder = self.boulderTiles[key]
  if not boulder or not boulder.cracked then
    return false
  end
  self.boulderTiles[key] = nil
  return true
end

function Grid:isBoulderTile(col, row)
  return self.boulderTiles[self:key(col, row)] ~= nil
end

function Grid:isCrackedBoulder(col, row)
  local boulder = self.boulderTiles[self:key(col, row)]
  return boulder ~= nil and boulder.cracked == true
end

-- Optional sizeRatio kept for callers; walls are always solid.
function Grid:isBlocking(col, row, sizeRatio)
  if self:isBoulderTile(col, row) then
    return true
  end
  if self:isPuzzleDoor(col, row) then
    return true
  end
  if self:isPressureDoor(col, row) and not self:isPressureDoorOpen() then
    return true
  end
  -- Side, half, top, behind, front — none are walkable.
  if self:isWallTile(col, row) then
    return true
  end
  return false
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

-- Seconds removed from the melt timer when entering this tile (negative = restore time).
function Grid:getTimeDelta(col, row)
  if self:isSnowflakeTile(col, row) then
    return -self:getSnowflakeSeconds(col, row)
  end
  if self:isInFireZone(col, row) then
    return 2
  end
  return 0
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
      elseif self:isPuzzleDoor(col, row) then
        cells[col] = "L"
      elseif self:isPressureDoor(col, row) then
        cells[col] = "R"
      elseif self:isPressurePlate(col, row) and self:isIceTile(col, row) then
        cells[col] = "r"
      elseif self:isPuzzlePiece(col, row) and self:isIceTile(col, row) then
        cells[col] = (self:getKeyVariant(col, row) == "down") and "m" or "q"
      elseif self:isPressurePlate(col, row) then
        cells[col] = "K"
      elseif self:isPuzzlePiece(col, row) then
        cells[col] = (self:getKeyVariant(col, row) == "down") and "M" or "J"
      elseif self:isBoulderTile(col, row) and self:isIceTile(col, row) then
        local boulder = self.boulderTiles[self:key(col, row)]
        if boulder.cracked then
          cells[col] = "Q"
        else
          -- s = boulder2 on ice (M/m reserved for key halves; a-i for half walls)
          cells[col] = boulder.variant == 2 and "t" or "O"
        end
      elseif self:isBoulderTile(col, row) and self:isMossTile(col, row) then
        local boulder = self.boulderTiles[self:key(col, row)]
        cells[col] = boulder.cracked and "p" or (boulder.variant == 2 and "u" or "n")
      elseif self:isIceTile(col, row) then
        cells[col] = "I"
      elseif self:isMossTile(col, row) then
        cells[col] = "o"
      elseif self:isSnowflakeTile(col, row) then
        cells[col] = "S"
      elseif self:isBoulderTile(col, row) then
        local boulder = self.boulderTiles[self:key(col, row)]
        if boulder.cracked then
          cells[col] = "P"
        else
          cells[col] = boulder.variant == 2 and "s" or "B"
        end
      elseif self:isWallTile(col, row) then
        local wall = self.wallTiles[self:key(col, row)]
        local lean = wall.lean or "left"
        local under = wall.under
        -- Side wall stacked on a behind front wall.
        if wall.texture == "side" and under then
          if under.cracked then
            cells[col] = lean == "right" and "H" or "G"
          else
            cells[col] = lean == "right" and "N" or "U"
          end
        elseif wall.half then
          local level = math.max(1, math.min(9, math.floor((wall.fill or 0.5) * 10 + 0.5)))
          if wall.depth == "behind" then
            cells[col] = string.char(string.byte("a") + level - 1)
          else
            cells[col] = tostring(level)
          end
        elseif wall.texture == "front" then
          if wall.depth == "behind" then
            cells[col] = wall.cracked and "x" or "w"
          else
            cells[col] = wall.cracked and "X" or "W"
          end
        elseif wall.cracked then
          cells[col] = lean == "right" and "Z" or "Y"
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

  local output = table.concat(lines, "\n")
  if next(self.sideViewTiles) then
    local sideLines = { output, "@side" }
    for row = 1, self.rows do
      local cells = {}
      for col = 1, self.columns do
        cells[col] = self:isSideView(col, row) and "#" or "."
      end
      sideLines[#sideLines + 1] = table.concat(cells)
    end
    output = table.concat(sideLines, "\n")
  end

  local joins = {}
  for _, wall in pairs(self.wallTiles) do
    if wall.texture == "side" and wall.under and wall.under.half then
      joins[#joins + 1] = table.concat({
        wall.col,
        wall.row,
        wall.under.fill or 0.5,
        wall.under.cracked and 1 or 0,
      }, ",")
    end
  end
  table.sort(joins)
  if #joins > 0 then
    output = output .. "\n@walljoins\n" .. table.concat(joins, "\n")
  end

  -- Half walls flipped to the top of the cell (default is bottom / down).
  local halfUps = {}
  for _, wall in pairs(self.wallTiles) do
    local up = (wall.half and wall.align == "up")
      or (wall.under and wall.under.half and wall.under.align == "up")
    if up then
      halfUps[#halfUps + 1] = wall.col .. "," .. wall.row
    end
  end
  table.sort(halfUps)
  if #halfUps > 0 then
    output = output .. "\n@halfup\n" .. table.concat(halfUps, "\n")
  end

  -- Half Wall 2: left/right vertical halves (halved full-wall texture).
  local halfTwos = {}
  for _, wall in pairs(self.wallTiles) do
    local target = nil
    if wall.half and wall.half2 then
      target = wall
    elseif wall.under and wall.under.half and wall.under.half2 then
      target = wall.under
    end
    if target then
      halfTwos[#halfTwos + 1] = table.concat({
        wall.col,
        wall.row,
        (target.lean == "right") and "right" or "left",
      }, ",")
    end
  end
  table.sort(halfTwos)
  if #halfTwos > 0 then
    output = output .. "\n@half2\n" .. table.concat(halfTwos, "\n")
  end

  -- Snowflake restore times that differ from the default (+3s).
  local snowflakeTimes = {}
  for _, flake in pairs(self.snowflakeTiles) do
    local seconds = flake.seconds or DEFAULT_SNOWFLAKE_SECONDS
    if seconds ~= DEFAULT_SNOWFLAKE_SECONDS then
      snowflakeTimes[#snowflakeTimes + 1] = table.concat({
        flake.col,
        flake.row,
        seconds,
      }, ",")
    end
  end
  table.sort(snowflakeTimes)
  if #snowflakeTimes > 0 then
    output = output .. "\n@snowflakes\n" .. table.concat(snowflakeTimes, "\n")
  end

  local fridges = {}
  for _, fridge in pairs(self.fridgeTiles) do
    fridges[#fridges + 1] = fridge.col .. "," .. fridge.row
  end
  table.sort(fridges)
  if #fridges > 0 then
    output = output .. "\n@fridges\n" .. table.concat(fridges, "\n")
  end

  local emptyUnderlays = {}
  local function recordEmpty(tiles)
    for _, tile in pairs(tiles) do
      if not self:hasGround(tile.col, tile.row)
        and not self:isIceTile(tile.col, tile.row)
        and not self:isMossTile(tile.col, tile.row) then
        emptyUnderlays[self:key(tile.col, tile.row)] = tile.col .. "," .. tile.row
      end
    end
  end
  recordEmpty(self.fireTiles)
  recordEmpty(self.snowflakeTiles)
  recordEmpty(self.teaTiles)
  recordEmpty(self.fridgeTiles)
  recordEmpty(self.puzzlePieceTiles)
  recordEmpty(self.puzzleDoorTiles)
  recordEmpty(self.pressureDoorTiles)
  recordEmpty(self.pressurePlateTiles)
  recordEmpty(self.wallTiles)
  recordEmpty(self.boulderTiles)
  local emptyLines = {}
  for _, line in pairs(emptyUnderlays) do
    emptyLines[#emptyLines + 1] = line
  end
  table.sort(emptyLines)
  if #emptyLines > 0 then
    output = output .. "\n@emptyunderlays\n" .. table.concat(emptyLines, "\n")
  end
  return output
end



function Grid:load(serialized)
  self:clear()
  local withoutEmpty, emptyUnderlaysPart = serialized:match("^(.-)\r?\n@emptyunderlays\r?\n(.*)$")
  if withoutEmpty then
    serialized = withoutEmpty
  end
  local fridgesPart
  local withoutFridges, fridgesBody = serialized:match("^(.-)\r?\n@fridges\r?\n(.*)$")
  if withoutFridges then
    serialized = withoutFridges
    fridgesPart = fridgesBody
  end
  local snowflakesPart
  local withoutSnowflakes, snowflakesBody = serialized:match("^(.-)\r?\n@snowflakes\r?\n(.*)$")
  if withoutSnowflakes then
    serialized = withoutSnowflakes
    snowflakesPart = snowflakesBody
  end
  local half2Part
  local withoutHalf2, half2Body = serialized:match("^(.-)\r?\n@half2\r?\n(.*)$")
  if withoutHalf2 then
    serialized = withoutHalf2
    half2Part = half2Body
  end
  local halfUpPart
  local withoutHalfUp, halfUpBody = serialized:match("^(.-)\r?\n@halfup\r?\n(.*)$")
  if withoutHalfUp then
    serialized = withoutHalfUp
    halfUpPart = halfUpBody
  end
  local basePart, wallJoinsPart = serialized:match("^(.-)\r?\n@walljoins\r?\n(.*)$")
  if basePart then
    serialized = basePart
  end
  local mapPart, sidePart = serialized:match("^(.-)\r?\n@side\r?\n(.*)$")
  if not mapPart then
    mapPart = serialized
    sidePart = nil
  end

  local row = 1
  for line in mapPart:gmatch("[^\r\n]+") do
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
      elseif cell == "o" then
        self:addMoss(col, row)
      elseif cell == "n" then
        self:addMoss(col, row)
        self:addBoulder(col, row)
      elseif cell == "u" then
        self:addMoss(col, row)
        self:addBoulder(col, row, { variant = 2 })
      elseif cell == "p" then
        self:addMoss(col, row)
        self:addBoulder(col, row, { cracked = true })
      elseif cell == "O" then
        self:addIce(col, row)
        self:addBoulder(col, row)
      elseif cell == "t" then
        self:addIce(col, row)
        self:addBoulder(col, row, { variant = 2 })
      elseif cell == "Q" then
        self:addIce(col, row)
        self:addBoulder(col, row, { cracked = true })
      elseif cell == "S" then
        self:addSnowflake(col, row)
      elseif cell == "T" then
        self:addTea(col, row)
      elseif cell == "J" then
        self:addPuzzlePiece(col, row, "top")
      elseif cell == "M" then
        self:addPuzzlePiece(col, row, "down")
      elseif cell == "A" then
        -- Legacy puzzle canvas: keep ground only.
        self:setGround(col, row)
      elseif cell == "L" then
        self:addPuzzleDoor(col, row)
      elseif cell == "K" then
        self:addPressurePlate(col, row)
      elseif cell == "R" then
        self:addPressureDoor(col, row)
      elseif cell == "r" then
        self:addIce(col, row)
        self:addPressurePlate(col, row)
      elseif cell == "q" then
        self:addIce(col, row)
        self:addPuzzlePiece(col, row, "top")
      elseif cell == "m" then
        self:addIce(col, row)
        self:addPuzzlePiece(col, row, "down")
      elseif cell == "B" then
        self:addBoulder(col, row)
      elseif cell == "s" then
        self:addBoulder(col, row, { variant = 2 })
      elseif cell == "P" then
        self:addBoulder(col, row, { cracked = true })
      elseif cell == "W" then
        self:addWall(col, row, "front", nil, { silent = true })
      elseif cell == "X" then
        self:addWall(col, row, "front", nil, { silent = true, cracked = true })
      elseif cell == "w" then
        self:addWall(col, row, "front", nil, { silent = true, depth = "behind" })
      elseif cell == "x" then
        self:addWall(col, row, "front", nil, { silent = true, cracked = true, depth = "behind" })
      elseif cell == "V" then
        self:addWall(col, row, "side", "left", { silent = true })
      elseif cell == "E" then
        self:addWall(col, row, "side", "right", { silent = true })
      elseif cell == "Y" then
        self:addWall(col, row, "side", "left", { silent = true, cracked = true })
      elseif cell == "Z" then
        self:addWall(col, row, "side", "right", { silent = true, cracked = true })
      elseif cell == "C" then
        self:addWall(col, row, "side", "left", { silent = true, creased = true })
      elseif cell == "D" then
        self:addWall(col, row, "side", "right", { silent = true, creased = true })
      elseif cell == "U" then
        self:addWall(col, row, "front", nil, { silent = true, depth = "behind" })
        self:addWall(col, row, "side", "left", { silent = true })
      elseif cell == "N" then
        self:addWall(col, row, "front", nil, { silent = true, depth = "behind" })
        self:addWall(col, row, "side", "right", { silent = true })
      elseif cell == "G" then
        self:addWall(col, row, "front", nil, { silent = true, cracked = true, depth = "behind" })
        self:addWall(col, row, "side", "left", { silent = true })
      elseif cell == "H" then
        self:addWall(col, row, "front", nil, { silent = true, cracked = true, depth = "behind" })
        self:addWall(col, row, "side", "right", { silent = true })
      elseif cell >= "1" and cell <= "9" then
        self:addWall(col, row, "front", nil, {
          silent = true,
          half = true,
          fill = tonumber(cell) / 10,
        })
      elseif cell >= "a" and cell <= "i" then
        self:addWall(col, row, "front", nil, {
          silent = true,
          half = true,
          fill = (string.byte(cell) - string.byte("a") + 1) / 10,
          depth = "behind",
        })
      end
    end
    row = row + 1
  end

  if sidePart then
    row = 1
    for line in sidePart:gmatch("[^\r\n]+") do
      if row > self.rows then
        break
      end
      for col = 1, math.min(#line, self.columns) do
        if line:sub(col, col) == "#" then
          self:addSideView(col, row)
        end
      end
      row = row + 1
    end
  end

  if wallJoinsPart then
    for line in wallJoinsPart:gmatch("[^\r\n]+") do
      local col, row, fill, cracked = line:match("^(%d+),(%d+),([%d%.]+),([01])$")
      col, row, fill = tonumber(col), tonumber(row), tonumber(fill)
      if col and row and fill then
        local wall = self.wallTiles[self:key(col, row)]
        if wall and wall.texture == "side" then
          wall.under = {
            texture = "front",
            depth = "behind",
            cracked = cracked == "1",
            half = true,
            fill = math.max(0.1, math.min(0.9, fill)),
          }
        end
      end
    end
  end

  if halfUpPart then
    for line in halfUpPart:gmatch("[^\r\n]+") do
      local col, row = line:match("^(%d+),(%d+)$")
      col, row = tonumber(col), tonumber(row)
      if col and row then
        local wall = self.wallTiles[self:key(col, row)]
        if wall then
          if wall.half then
            wall.align = "up"
          elseif wall.under and wall.under.half then
            wall.under.align = "up"
          end
        end
      end
    end
  end

  if half2Part then
    for line in half2Part:gmatch("[^\r\n]+") do
      local col, row, lean = line:match("^(%d+),(%d+),(%w+)$")
      if not col then
        col, row = line:match("^(%d+),(%d+)$")
        lean = "left"
      end
      col, row = tonumber(col), tonumber(row)
      if col and row then
        local wall = self.wallTiles[self:key(col, row)]
        if wall then
          local face = lean == "right" and "right" or "left"
          if wall.half then
            wall.half2 = true
            wall.lean = face
            wall.align = nil
          elseif wall.under and wall.under.half then
            wall.under.half2 = true
            wall.under.lean = face
            wall.under.align = nil
          end
        end
      end
    end
  end

  if snowflakesPart then
    for line in snowflakesPart:gmatch("[^\r\n]+") do
      local col, row, seconds = line:match("^(%d+),(%d+),(%d+)$")
      col, row, seconds = tonumber(col), tonumber(row), tonumber(seconds)
      if col and row and seconds and self:isInside(col, row) then
        local flake = self.snowflakeTiles[self:key(col, row)]
        if flake then
          flake.seconds = math.max(1, math.min(99, math.floor(seconds)))
        end
      end
    end
  end

  if fridgesPart then
    for line in fridgesPart:gmatch("[^\r\n]+") do
      local col, row = line:match("^(%d+),(%d+)$")
      col, row = tonumber(col), tonumber(row)
      if col and row and self:isInside(col, row) then
        self:addFridge(col, row)
      end
    end
  end

  if emptyUnderlaysPart then
    for line in emptyUnderlaysPart:gmatch("[^\r\n]+") do
      local col, row = line:match("^(%d+),(%d+)$")
      col, row = tonumber(col), tonumber(row)
      if col and row and self:isInside(col, row) then
        self.groundTiles[self:key(col, row)] = nil
      end
    end
  end
end



function Grid:draw(zoom, camera, showGrid)
  if next(self.sideViewTiles) then
    -- Mixed level: top-down cells and side-view cells drawn together.
    self:drawTopdown(zoom, camera, showGrid, "topdown")
    self:drawSide(zoom, camera, showGrid, "side")
  elseif Perspective.isSide() then
    self:drawSide(zoom, camera, showGrid)
  else
    self:drawTopdown(zoom, camera, showGrid)
  end
end

local function drawTeaCup(centerX, centerY, zoom, side)
  if side then
    -- Sit the cup on the floor line (centerY is floorTop).
    centerY = centerY - 14
  end
  love.graphics.setColor(0.16, 0.08, 0.03, 0.35)
  love.graphics.ellipse("fill", centerX, centerY + 13, 13, side and 3 or 4)
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

local function drawFridge(centerX, centerY, size, zoom, side)
  local width = size * 0.72
  local height = size * 0.92
  local x = centerX - width * 0.5
  local y = side and (centerY - height) or (centerY - height * 0.5)
  local radius = math.max(2, size * 0.07)

  love.graphics.setColor(0.06, 0.10, 0.20, 0.72)
  love.graphics.rectangle("fill", x + size * 0.05, y + size * 0.06, width, height, radius, radius)
  love.graphics.setColor(0.72, 0.90, 0.98, 1)
  love.graphics.rectangle("fill", x, y, width, height, radius, radius)
  love.graphics.setColor(0.40, 0.67, 0.86, 1)
  love.graphics.rectangle("fill", x + width * 0.08, y + height * 0.08, width * 0.84, height * 0.84, radius * 0.65, radius * 0.65)
  love.graphics.setColor(0.08, 0.13, 0.27, 1)
  love.graphics.setLineWidth(math.max(1, 2 / zoom))
  love.graphics.rectangle("line", x, y, width, height, radius, radius)
  love.graphics.line(x + width * 0.08, y + height * 0.34, x + width * 0.92, y + height * 0.34)
  love.graphics.setColor(0.88, 0.97, 1, 0.95)
  love.graphics.rectangle("fill", x + width * 0.16, y + height * 0.09, width * 0.10, height * 0.18, 1, 1)
  love.graphics.setColor(0.08, 0.13, 0.27, 0.92)
  love.graphics.rectangle("fill", x + width * 0.76, y + height * 0.44, width * 0.07, height * 0.31, 2, 2)
  love.graphics.setLineWidth(1)
end

-- One key split into sections: "top" = bow half, "down" = bit half, full = whole.
-- top-down uses key-top.png (left/right); side view uses key-down.png (up/down).
local function getKeyPieceImage(sprites, section, sideView)
  if sideView then
    return section == "down" and sprites.keyPieceBottomSide or sprites.keyPieceTopSide
  end
  return section == "down" and sprites.keyPieceBottom or sprites.keyPieceTop
end

local function drawKeySprite(centerX, centerY, size, section, full, alpha, sideView)
  alpha = alpha or 1
  if section ~= "down" then
    section = "top"
  end
  local sprites = getTileSprites()
  local pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(love.timer.getTime() * 3.2))

  local function drawGlow(image, scale, ox, oy)
    love.graphics.setColor(1, 0.78, 0.2, 0.18 * alpha * pulse)
    love.graphics.draw(image, centerX, centerY, 0, scale * 1.08, scale * 1.08, ox, oy)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(image, centerX, centerY, 0, scale, scale, ox, oy)
  end

  if full then
    local image = sideView and sprites.keyDown or sprites.keyTop
    local iw, ih = image:getDimensions()
    local target = size * 0.86
    local scale = target / math.max(iw, ih)
    local ox, oy = iw * 0.5, sideView and ih or (ih * 0.5)
    drawGlow(image, scale, ox, oy)
    return
  end

  local image = getKeyPieceImage(sprites, section, sideView)
  local iw, ih = image:getDimensions()
  local target = size * 0.76
  local scale = target / math.max(iw, ih)
  local ox, oy = iw * 0.5, ih * 0.5
  if sideView then
    -- Sit the fragment on the floor line.
    oy = ih
  end
  drawGlow(image, scale, ox, oy)
end

-- Side-view doors share front-wall elevation size (wall height above floor face).
local function drawDoorElevAt(x, floorTop, size, zoom, open, palette)
  local wallH = Perspective.wallHeight(size, 1)
  local wallY = floorTop - wallH
  local depth = size * 0.18
  local wallW = size - 2
  local shade = open and 0.72 or 1

  -- Same extruded block silhouette as front walls.
  love.graphics.setColor(
    palette.side[1] * shade,
    palette.side[2] * shade,
    palette.side[3] * shade,
    0.95
  )
  love.graphics.polygon(
    "fill",
    x + wallW, wallY,
    x + wallW + depth, wallY - depth * 0.4,
    x + wallW + depth, floorTop - depth * 0.4,
    x + wallW, floorTop
  )
  love.graphics.setColor(
    palette.top[1] * shade,
    palette.top[2] * shade,
    palette.top[3] * shade,
    1
  )
  love.graphics.polygon(
    "fill",
    x + 1, wallY,
    x + wallW, wallY,
    x + wallW + depth, wallY - depth * 0.4,
    x + 1 + depth, wallY - depth * 0.4
  )

  if open then
    -- Open: wall-sized frame with hollow center (doorway).
    local frame = math.max(3, size * 0.08)
    love.graphics.setColor(palette.face[1] * 0.55, palette.face[2] * 0.55, palette.face[3] * 0.55, 0.96)
    love.graphics.rectangle("fill", x + 1, wallY, wallW, wallH, 2, 2)
    love.graphics.setColor(0.025, 0.05, 0.08, 0.98)
    love.graphics.rectangle(
      "fill",
      x + 1 + frame,
      wallY + frame,
      wallW - frame * 2,
      wallH - frame * 2,
      1,
      1
    )
    love.graphics.setColor(palette.line[1], palette.line[2], palette.line[3], 0.9)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", x + 1, wallY, wallW, wallH, 2, 2)
    love.graphics.setColor(palette.accent[1], palette.accent[2], palette.accent[3], 0.75)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.line(x + 1 + frame, wallY + frame, x + wallW - frame, wallY + frame)
  else
    love.graphics.setColor(palette.face[1], palette.face[2], palette.face[3], 0.98)
    love.graphics.rectangle("fill", x + 1, wallY, wallW, wallH, 2, 2)
    love.graphics.setColor(palette.line[1], palette.line[2], palette.line[3], 0.95)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", x + 1, wallY, wallW, wallH, 2, 2)

    -- Panel seams (wall-like brick door face).
    love.graphics.setColor(palette.accent[1], palette.accent[2], palette.accent[3], 0.55)
    love.graphics.setLineWidth(1 / zoom)
    local midX = x + 1 + wallW * 0.5
    love.graphics.line(midX, wallY + 5, midX, floorTop - 5)
    love.graphics.line(x + 6, wallY + wallH * 0.48, x + wallW - 4, wallY + wallH * 0.48)

    if palette.knob then
      love.graphics.setColor(palette.accent[1], palette.accent[2], palette.accent[3], 0.95)
      love.graphics.circle("fill", midX + wallW * 0.18, wallY + wallH * 0.48, 2.5)
    end
    if palette.mark == "plus" then
      love.graphics.setColor(palette.accent[1], palette.accent[2], palette.accent[3], 0.9)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(x + wallW * 0.28, wallY + wallH * 0.5, x + wallW * 0.72, wallY + wallH * 0.5)
      love.graphics.line(x + wallW * 0.5, wallY + wallH * 0.30, x + wallW * 0.5, wallY + wallH * 0.70)
    end
  end
end

local PRESSURE_DOOR_PALETTE = {
  side = { 0.12, 0.24, 0.16 },
  top = { 0.42, 0.88, 0.62 },
  face = { 0.14, 0.30, 0.20 },
  line = { 0.42, 0.92, 0.64 },
  accent = { 0.55, 1.0, 0.74 },
  mark = "plus",
}

local function drawPuzzleDoorAt(x, y, size, zoom, side, open)
  local sprites = getTileSprites()
  local image = open and sprites.doorOpen or sprites.doorClosed
  local iw, ih = image:getDimensions()
  local scale = (size * 0.98) / math.max(iw, ih)
  local centerX = x + size * 0.5
  -- Side view: y is floorTop - size. Top-down: center in the tile.
  local anchorY = side and (y + size) or (y + size * 0.5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image,
    centerX,
    anchorY,
    0,
    scale,
    scale,
    iw * 0.5,
    side and ih or (ih * 0.5)
  )
end

local function drawPressureDoorAt(x, y, size, zoom, side, open)
  if side then
    drawDoorElevAt(x, y + size, size, zoom, open, PRESSURE_DOOR_PALETTE)
    return
  end

  local pad = size * 0.1
  local dx = x + pad
  local dy = y + pad
  local dw = size - pad * 2
  local dh = size - pad * 2
  if open then
    love.graphics.setColor(0.03, 0.10, 0.07, 0.96)
    love.graphics.rectangle("fill", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.30, 0.88, 0.60, 0.9)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.42, 1.0, 0.70, 0.8)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.line(dx + dw * 0.22, dy + dh * 0.5, dx + dw * 0.78, dy + dh * 0.5)
    love.graphics.line(dx + dw * 0.50, dy + dh * 0.32, dx + dw * 0.78, dy + dh * 0.5, dx + dw * 0.50, dy + dh * 0.68)
  else
    love.graphics.setColor(0.10, 0.22, 0.16, 0.98)
    love.graphics.rectangle("fill", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.30, 0.78, 0.52, 0.95)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.52, 0.95, 0.70, 0.9)
    love.graphics.setLineWidth(2 / zoom)
    love.graphics.line(dx + dw * 0.28, dy + dh * 0.5, dx + dw * 0.72, dy + dh * 0.5)
    love.graphics.line(dx + dw * 0.5, dy + dh * 0.30, dx + dw * 0.5, dy + dh * 0.70)
  end
end

local function drawPressurePlateAt(centerX, centerY, size, zoom, pressed, side)
  local sprites = getTileSprites()
  local image = pressed and sprites.buttonPressed or sprites.buttonUnpressed
  local iw, ih = image:getDimensions()
  local target = size * 0.88
  local scale = target / math.max(iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image,
    centerX,
    centerY,
    0,
    scale,
    scale,
    iw * 0.5,
    side and ih or (ih * 0.5)
  )
end

local function getBoulderSprite(sprites, boulder)
  if boulder.cracked then
    return sprites.crackedBoulder
  end
  return boulder.variant == 2 and sprites.boulder2 or sprites.boulder
end

local function drawBoulderAt(image, centerX, anchorY, size, side)
  local targetSize = size * 0.98
  local scale = targetSize / math.max(image:getWidth(), image:getHeight())
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image,
    centerX,
    anchorY,
    0,
    scale,
    scale,
    image:getWidth() / 2,
    side and image:getHeight() or image:getHeight() / 2
  )
end

function Grid:drawTopdown(zoom, camera, showGrid, filter)
  local sprites = getTileSprites()
  local width, height = self:worldBounds()
  local minCol, maxCol, minRow, maxRow = self:visibleDrawRange(camera)

  local function include(col, row)
    if not filter then
      return true
    end
    local side = self:isSideView(col, row)
    if filter == "topdown" then
      return not side
    end
    if filter == "side" then
      return side
    end
    return true
  end

  local function isVisible(tile, padding)
    padding = padding or 0
    return tile.col >= minCol - padding
      and tile.col <= maxCol + padding
      and tile.row >= minRow - padding
      and tile.row <= maxRow + padding
  end

  -- Void stays transparent so the menu cave background shows through.

  -- Obstacles and props are layered over terrain. If terrain exists it remains
  -- visible; when the editor stored no underlay, the unused space stays empty.
  local function hidesGround(col, row)
    return false
  end

  local function drawFrontWallTopdown(wall, x, y)
    local fill = wall.half and (wall.fill or 0.5) or 1
    local wallH
    local wallY
    local wallW = self.size
    local wallX = x
    if wall.half and wall.half2 then
      -- Left/right vertical half (like a thick side wall).
      wallW = self.size * fill
      wallH = self.size
      wallY = y
      local lean = wall.lean or "left"
      wallX = lean == "right" and (x + self.size - wallW) or x
    elseif wall.half then
      wallH = self.size * fill
      if wall.align == "up" then
        wallY = y
      else
        wallY = y + self.size - wallH
      end
    else
      wallH = self.size - 2
      wallY = y + 1
    end

    local image = sprites.wall
    local texTile = self.size
    local align = nil
    if wall.half and wall.half2 then
      image = sprites.wallHalf2
      texTile = wallW
      align = wall.lean == "right" and "right" or "left"
    end
    drawWallTexture(image, wallX, wallY, wallW, wallH, texTile, 0.98, align)

    if wall.cracked then
      love.graphics.setColor(0.18, 0.10, 0.06, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(
        wallX + 8, wallY + 6,
        wallX + wallW * 0.42, wallY + wallH * 0.45,
        wallX + 10, wallY + wallH - 7
      )
      love.graphics.line(
        wallX + wallW * 0.42, wallY + wallH * 0.45,
        wallX + wallW - 9, wallY + wallH * 0.28
      )
      love.graphics.line(
        wallX + wallW * 0.38, wallY + wallH * 0.55,
        wallX + wallW - 8, wallY + wallH - 8
      )
    end
  end

  local function getBehindWallAt(col, row)
    local wall = self.wallTiles[self:key(col, row)]
    if not wall then
      return nil
    end
    if wall.texture == "front" and wall.depth == "behind" then
      return wall
    end
    if wall.under then
      return {
        col = col,
        row = row,
        half = wall.under.half,
        fill = wall.under.fill,
        cracked = wall.under.cracked,
        align = wall.under.align,
        half2 = wall.under.half2,
        lean = wall.under.lean,
        depth = "behind",
      }
    end
    return nil
  end

  for row = minRow, maxRow do
    local runStart = nil
    for col = minCol, maxCol + 1 do
      if col <= maxCol and self:hasGround(col, row) and not hidesGround(col, row) and include(col, row) then
        runStart = runStart or col
      elseif runStart then
        local x, y = self:tileOrigin(runStart, row)
        local runLength = col - runStart
        local quad, cellWidth, cellHeight = getTextureQuad(
          sprites.ground,
          groundQuadCache,
          runStart,
          row,
          runLength
        )
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
          sprites.ground,
          quad,
          x,
          y,
          0,
          self.size / cellWidth,
          self.size / cellHeight
        )
        runStart = nil
      end
    end
  end

  for _, ice in pairs(self.iceTiles) do
    if isVisible(ice) and include(ice.col, ice.row) and not getBehindWallAt(ice.col, ice.row) then
      local x, y = self:tileOrigin(ice.col, ice.row)
      local quad, cellWidth, cellHeight = getTextureQuad(
        sprites.ice,
        iceQuadCache,
        ice.col,
        ice.row,
        1
      )
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        sprites.ice,
        quad,
        x,
        y,
        0,
        self.size / cellWidth,
        self.size / cellHeight
      )
    end
  end

  for _, moss in pairs(self.mossTiles) do
    if isVisible(moss) and include(moss.col, moss.row) and not getBehindWallAt(moss.col, moss.row) then
      local x, y = self:tileOrigin(moss.col, moss.row)
      local quad, cellWidth, cellHeight = getTextureQuad(
        sprites.moss,
        mossQuadCache,
        moss.col,
        moss.row,
        1
      )
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        sprites.moss,
        quad,
        x,
        y,
        0,
        self.size / cellWidth,
        self.size / cellHeight
      )
    end
  end

  for _, puddle in pairs(self.puddleTiles) do
    if isVisible(puddle) and include(puddle.col, puddle.row) then
      local x, y = self:tileOrigin(puddle.col, puddle.row)
      local scaleAlong, scaleAcross, directionX, directionY, contentShiftY =
        puddleScales(puddle, self.size, PUDDLE_FRAME_SIZE, PUDDLE_FRAME_SIZE)
      local overlap = self.size * 0.08
      drawPuddleDrag(
        sprites,
        puddle,
        x + self.size * 0.5 + directionX * overlap,
        y + self.size * 0.5 + directionY * overlap - contentShiftY,
        scaleAlong,
        scaleAcross
      )
      local bridgeAlpha = puddleAlpha(puddle)
      eachPuddleBridgeTile(puddle, function(bridgeCol, bridgeRow)
        if include(bridgeCol, bridgeRow) then
          local bridgeX, bridgeY = self:tileOrigin(bridgeCol, bridgeRow)
          local longW = sprites.puddleLong:getWidth()
          local longH = sprites.puddleLong:getHeight()
          local bAlong, bAcross, _, _, bShiftY =
            puddleScales(puddle, self.size, longW, longH)
          love.graphics.setColor(1, 1, 1, bridgeAlpha)
          love.graphics.draw(
            sprites.puddleLong,
            bridgeX + self.size * 0.5,
            bridgeY + self.size * 0.5 - bShiftY,
            0,
            bAlong,
            bAcross,
            longW * 0.5,
            longH * 0.5
          )
        end
      end)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)

  -- Behind full walls get an inset ground pad; all walls retain their ground tile.
  local behindPad = math.max(8, math.floor(self.size * 0.18))
  for col = minCol, maxCol do
    for row = minRow, maxRow do
      local behind = getBehindWallAt(col, row)
      if behind and include(col, row) then
        local x, y = self:tileOrigin(col, row)
        drawFrontWallTopdown(behind, x, y)
        if not behind.half and not hidesGround(col, row) then
          local image = sprites.ground
          local cache = groundQuadCache
          if self:isIceTile(col, row) then
            image = sprites.ice
            cache = iceQuadCache
          elseif self:isMossTile(col, row) then
            image = sprites.moss
            cache = mossQuadCache
          end
          local quad, cellWidth, cellHeight = getTextureQuad(image, cache, col, row, 1)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(
            image,
            quad,
            x + behindPad,
            y + behindPad,
            0,
            (self.size - behindPad * 2) / cellWidth,
            (self.size - behindPad * 2) / cellHeight
          )
        end
      end
    end
  end

  for _, fire in pairs(self.fireTiles) do
    if isVisible(fire, self.fireRadius) and include(fire.col, fire.row) then
      love.graphics.setColor(0.65, 0.20, 0.06, 0.24)
      for row = fire.row - self.fireRadius, fire.row + self.fireRadius do
        for col = fire.col - self.fireRadius, fire.col + self.fireRadius do
          if self:hasGround(col, row) and include(col, row) then
            local x, y = self:tileOrigin(col, row)
            love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
          end
        end
      end
    end
  end

  for _, plate in pairs(self.pressurePlateTiles) do
    if isVisible(plate) and include(plate.col, plate.row) then
      local centerX, centerY = self:tileCenter(plate.col, plate.row)
      drawPressurePlateAt(centerX, centerY, self.size, zoom, plate.pressed, false)
    end
  end

  for _, snowflake in pairs(self.snowflakeTiles) do
    if isVisible(snowflake) and include(snowflake.col, snowflake.row) then
      local centerX, centerY = self:tileCenter(snowflake.col, snowflake.row)
      local targetSize = self.size * 0.82
      local scale = targetSize / math.max(
        sprites.snowflake:getWidth(),
        sprites.snowflake:getHeight()
      )
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        sprites.snowflake,
        centerX,
        centerY,
        0,
        scale,
        scale,
        sprites.snowflake:getWidth() / 2,
        sprites.snowflake:getHeight() / 2
      )
    end
  end

  for _, tea in pairs(self.teaTiles) do
    if isVisible(tea) and include(tea.col, tea.row) then
      local centerX, centerY = self:tileCenter(tea.col, tea.row)
      drawTeaCup(centerX, centerY, zoom, false)
    end
  end


  for _, fridge in pairs(self.fridgeTiles) do
    if isVisible(fridge) and include(fridge.col, fridge.row) then
      local centerX, centerY = self:tileCenter(fridge.col, fridge.row)
      drawFridge(centerX, centerY, self.size, zoom, false)
    end
  end

  for _, piece in pairs(self.puzzlePieceTiles) do
    if isVisible(piece) and include(piece.col, piece.row) then
      local centerX, centerY = self:tileCenter(piece.col, piece.row)
      drawKeySprite(centerX, centerY, self.size, piece.variant or "top", false, 1, false)
    end
  end

  for _, door in pairs(self.pressureDoorTiles) do
    if isVisible(door) and include(door.col, door.row) then
      local x, y = self:tileOrigin(door.col, door.row)
      drawPressureDoorAt(x, y, self.size, zoom, false, self:isPressureDoorOpen())
    end
  end

  for _, door in pairs(self.puzzleDoorTiles) do
    if isVisible(door) and include(door.col, door.row) then
      local x, y = self:tileOrigin(door.col, door.row)
      drawPuzzleDoorAt(x, y, self.size, zoom, false, door.open)
    end
  end

  -- Front / half / cracked walls (half = slab only, no brick under/above).
  for _, wall in pairs(self.wallTiles) do
    if isVisible(wall) and include(wall.col, wall.row) and wall.texture == "front" and wall.depth ~= "behind" then
      local x, y = self:tileOrigin(wall.col, wall.row)
      drawFrontWallTopdown(wall, x, y)
    end
  end

  -- Side walls = strip only, no brick under the open half.
  for _, wall in pairs(self.wallTiles) do
    if isVisible(wall) and include(wall.col, wall.row) and wall.texture == "side" then
      local x, y = self:tileOrigin(wall.col, wall.row)

      local stripW = self.size * 0.5
      local stripX
      local creased = wall.creased and true or false

      if creased then
        local furthestRight = self:getConnectedSideWallFurthestRight(wall.col, wall.row)
        if furthestRight then
          stripX = furthestRight - stripW
          stripX = math.max(x, math.min(x + self.size - stripW, stripX))
        else
          local lean = wall.lean or self:getWallLean(wall.col, wall.row)
          stripX = lean == "right" and (x + self.size - stripW) or x
        end
      else
        local lean = wall.lean or self:getWallLean(wall.col, wall.row)
        stripX = lean == "right" and (x + self.size - stripW) or x
      end

      drawSideWallTexture(
        sprites.brickEnd,
        x,
        y,
        self.size,
        self.size,
        self.size,
        0.98,
        wall.lean or self:getWallLean(wall.col, wall.row)
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

      if wall.cracked then
        love.graphics.setColor(0.08, 0.12, 0.18, 0.95)
        love.graphics.setLineWidth(2 / zoom)
        local midX = stripX + stripW * 0.5
        love.graphics.line(
          midX - 4, y + 5,
          midX + 2, y + self.size * 0.45,
          midX - 3, y + self.size - 6
        )
        love.graphics.line(
          midX + 2, y + self.size * 0.45,
          midX + 6, y + self.size * 0.62
        )
      end
    end
  end

  for _, boulder in pairs(self.boulderTiles) do
    if isVisible(boulder) and include(boulder.col, boulder.row) then
      local centerX, centerY = self:tileCenter(boulder.col, boulder.row)
      drawBoulderAt(getBoulderSprite(sprites, boulder), centerX, centerY, self.size, false)
    end
  end

  if showGrid and filter ~= "side" then
    love.graphics.setColor(0.13, 0.32, 0.47)
    for col = minCol - 1, maxCol do
      local x = col * self.size
      love.graphics.line(x, 0, x, height)
    end
    local pitch = Perspective.rowPitch(self.size)
    for row = minRow - 1, maxRow do
      local y = row * pitch
      love.graphics.line(0, y, width, y)
    end
  end

  for _, fire in pairs(self.fireTiles) do
    if isVisible(fire) and include(fire.col, fire.row) then
      local centerX, centerY = self:tileCenter(fire.col, fire.row)
      local targetSize = self.size * 0.95
      local scale = targetSize / FIRE_FRAME_SIZE
      local time = (love.timer and love.timer.getTime()) or 0
      local frameIndex = math.floor(time / FIRE_FRAME_DURATION) % FIRE_FRAME_COUNT + 1
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        sprites.fire,
        sprites.fireFrames[frameIndex],
        centerX,
        centerY,
        0,
        scale,
        scale,
        FIRE_FRAME_SIZE / 2,
        FIRE_FRAME_SIZE / 2
      )
    end
  end
end

function Grid:drawSide(zoom, camera, showGrid, filter)
  local sprites = getTileSprites()
  local minCol, maxCol, minRow, maxRow = self:visibleDrawRange(camera)
  local pitch, thick, faceH = Perspective.floorMetrics(self.size)
  local size = self.size
  local wallMax = Perspective.wallHeight(size, 1)

  local function include(col, row)
    if not filter then
      return true
    end
    local side = self:isSideView(col, row)
    if filter == "topdown" then
      return not side
    end
    if filter == "side" then
      return side
    end
    return true
  end

  -- Void stays transparent so the menu cave background shows through.

  local function cellFloorTop(col, row)
    return Perspective.floorY(col, row, size, "side")
  end

  local floorFaceQuadCache = {}

  local function getFloorFaceQuad(image, cache, col, row, srcW, srcH)
    local key = col .. ":" .. row .. ":" .. math.floor(srcW) .. ":" .. math.floor(srcH)
    if not cache[key] then
      local imgW, imgH = image:getDimensions()
      local ox = ((col - 1) * srcW) % math.max(1, imgW - srcW)
      local oy = ((row - 1) * srcH) % math.max(1, imgH - srcH)
      cache[key] = love.graphics.newQuad(ox, oy, srcW, srcH, imgW, imgH)
    end
    return cache[key]
  end

  local function drawFloorCell(col, row, floorKind, plateCut)
    local x, y = self:tileOrigin(col, row)
    local floorTop = cellFloorTop(col, row)
    local faceTop = floorTop
    local faceBottom = y + size
    local faceHLocal = faceBottom - faceTop
    local lip = math.min(thick, faceHLocal * 0.38)
    local topH = math.max(2, faceHLocal - lip)

    -- Moss side art is a full green/purple cross-section: fit the whole
    -- silhouette into the floor face so the droops stay visible.
    if floorKind == "moss" then
      local image = sprites.mossSide
      local imgW, imgH = image:getDimensions()
      local function drawMossBand(destX, destW)
        if destW < 1 then
          return
        end
        local sx = ((destX - x) / size) * imgW
        local sw = math.max(1, (destW / size) * imgW)
        local key = "mossface:" .. col .. ":" .. row .. ":" .. math.floor(sx) .. ":" .. math.floor(sw)
        local quad = floorFaceQuadCache[key]
        if not quad then
          quad = love.graphics.newQuad(sx, 0, sw, imgH, imgW, imgH)
          floorFaceQuadCache[key] = quad
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, quad, destX, faceTop, 0, destW / sw, faceHLocal / imgH)
        love.graphics.setColor(0.04, 0.05, 0.10, 0.35)
        love.graphics.rectangle("fill", destX, faceTop + topH, destW, lip)
        love.graphics.setColor(0.45, 0.72, 0.52, 0.40)
        love.graphics.setLineWidth(1 / zoom)
        love.graphics.line(destX, faceTop, destX + destW, faceTop)
      end

      if plateCut then
        local plateW = size * 0.52
        local flank = (size - plateW) * 0.5
        drawMossBand(x, flank)
        drawMossBand(x + flank + plateW, flank)
        return
      end

      drawMossBand(x, size)
      return
    end

    local image = sprites.ground
    local kindTag = "g"
    if floorKind == "ice" then
      image = sprites.ice
      kindTag = "i"
    end
    local imgW, imgH = image:getDimensions()
    -- Same brick scale as top-down (one tile wide), cropped to face height so it isn't stretched.
    local srcW = imgW / TEXTURE_GRID_SIZE
    local texScale = size / srcW
    local srcTopH = topH / texScale
    local srcLipH = lip / texScale
    local topQuad = getFloorFaceQuad(image, floorFaceQuadCache, col, row, srcW, srcTopH)
    local lipQuad = getFloorFaceQuad(
      image,
      floorFaceQuadCache,
      col,
      row + 17,
      srcW,
      math.max(1, srcLipH)
    )

    local function drawFloorBand(destX, destW, srcOffsetX)
      if destW < 1 then
        return
      end
      local srcBandW = math.max(1, destW / texScale)
      local ox, oy = topQuad:getViewport()
      local _, lipOy = lipQuad:getViewport()
      local bandKey = "band:" .. col .. ":" .. row .. ":" .. math.floor(srcOffsetX) .. ":" .. math.floor(srcBandW) .. ":" .. kindTag
      local bandTop = floorFaceQuadCache[bandKey]
      if not bandTop then
        bandTop = love.graphics.newQuad(ox + srcOffsetX, oy, srcBandW, srcTopH, imgW, imgH)
        floorFaceQuadCache[bandKey] = bandTop
      end
      local lipKey = bandKey .. ":lip"
      local bandLip = floorFaceQuadCache[lipKey]
      if not bandLip then
        bandLip = love.graphics.newQuad(ox + srcOffsetX, lipOy, srcBandW, math.max(1, srcLipH), imgW, imgH)
        floorFaceQuadCache[lipKey] = bandLip
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, bandTop, destX, faceTop, 0, texScale, texScale)
      love.graphics.setColor(0.55, 0.55, 0.65, 1)
      love.graphics.draw(image, bandLip, destX, faceTop + topH, 0, texScale, texScale)
      love.graphics.setColor(0.04, 0.05, 0.10, 0.50)
      love.graphics.rectangle("fill", destX, faceTop + topH, destW, lip)
      love.graphics.setColor(0.80, 0.84, 1.0, 0.30)
      love.graphics.setLineWidth(1 / zoom)
      love.graphics.line(destX, faceTop, destX + destW, faceTop)
    end

    if plateCut then
      -- Ground flanks only: plate is recessed in the middle with no brick under it.
      local plateW = size * 0.52
      local flank = (size - plateW) * 0.5
      drawFloorBand(x, flank, 0)
      drawFloorBand(x + flank + plateW, flank, (flank + plateW) / texScale)
      return
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, topQuad, x, faceTop, 0, texScale, texScale)

    love.graphics.setColor(0.55, 0.55, 0.65, 1)
    love.graphics.draw(image, lipQuad, x, faceTop + topH, 0, texScale, texScale)
    love.graphics.setColor(0.04, 0.05, 0.10, 0.50)
    love.graphics.rectangle("fill", x, faceTop + topH, size, lip)
    love.graphics.setColor(0.80, 0.84, 1.0, 0.30)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.line(x, faceTop, x + size, faceTop)
  end

  local function drawFrontWallElev(wall, col, row, behind)
    local x, y = self:tileOrigin(col, row)
    local fill = wall.half and (wall.fill or 0.5) or 1
    local wallMax = Perspective.wallHeight(size, 1)
    local floorTop = cellFloorTop(col, row)
    local lean = wall.lean or "left"
    local wallH
    local wallY
    local wallW
    local joinedHalf = behind and wall.half
    local shade = (behind and not joinedHalf) and 0.78 or 1
    local depth = size * (behind and 0.12 or 0.18)

    if wall.half and wall.half2 then
      -- Left/right vertical half: full wall height, fill controls width.
      wallH = wallMax
      wallY = floorTop - wallH
      wallW = math.max(4, size * fill)
      x = lean == "right" and (x + size - wallW) or x
    else
      wallH = Perspective.wallHeight(size, fill)
      if wall.half and wall.align == "up" then
        wallY = floorTop - wallMax
      else
        wallY = floorTop - wallH
      end
      local inset = (behind and not joinedHalf) and math.max(3, size * 0.10) or 0
      x = x + inset
      wallW = size - inset * 2
      if wallW < 4 then
        wallW = 4
      end
    end

    local polyBottom = wallY + wallH
    love.graphics.setColor(0.32 * shade, 0.20 * shade, 0.14 * shade, 0.95)
    love.graphics.polygon(
      "fill",
      x + wallW, wallY,
      x + wallW + depth, wallY - depth * 0.4,
      x + wallW + depth, polyBottom - depth * 0.4,
      x + wallW, polyBottom
    )
    love.graphics.setColor(0.80 * shade, 0.62 * shade, 0.46 * shade, 1)
    love.graphics.polygon(
      "fill",
      x + 1, wallY,
      x + wallW, wallY,
      x + wallW + depth, wallY - depth * 0.4,
      x + 1 + depth, wallY - depth * 0.4
    )
    local image = sprites.wall
    local texTile = size
    local align = nil
    if wall.half and wall.half2 then
      image = sprites.wallHalf2
      texTile = wallW
      align = lean == "right" and "right" or "left"
    end
    drawWallTexture(image, x, wallY, wallW, wallH, texTile, 0.98 * shade, align)

    if wall.cracked then
      love.graphics.setColor(0.12, 0.07, 0.04, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(
        x + 9, wallY + 7,
        x + wallW * 0.45, wallY + wallH * 0.5,
        x + 11, wallY + wallH - 7
      )
      love.graphics.line(
        x + wallW * 0.45, wallY + wallH * 0.5,
        x + wallW - 9, wallY + wallH * 0.28
      )
    end
  end

  local function getBehindWallAt(col, row)
    local wall = self.wallTiles[self:key(col, row)]
    if not wall then
      return nil
    end
    if wall.texture == "front" and wall.depth == "behind" then
      return wall
    end
    if wall.under then
      return {
        col = col,
        row = row,
        half = wall.under.half,
        fill = wall.under.fill,
        cracked = wall.under.cracked,
        align = wall.under.align,
        half2 = wall.under.half2,
        lean = wall.under.lean,
        depth = "behind",
      }
    end
    return nil
  end

  -- Thin edge-on side walls (same height as front walls, not the same width).
  local function drawSideWallElev(wall, col, row)
    local x, y = self:tileOrigin(col, row)
    local lean = wall.lean or self:getWallLean(col, row)
    local floorTop = cellFloorTop(col, row)
    local wallY = floorTop - wallMax
    local w = size * 0.22
    local sx = lean == "right" and (x + size - w - 1) or (x + 1)
    local drawY = wallY
    local drawH = wallMax

    drawSideWallTexture(sprites.brickEnd, x, drawY, size, drawH, size, 0.98, lean)
    if wall.cracked then
      love.graphics.setColor(0.06, 0.10, 0.14, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      local mid = sx + w * 0.5
      love.graphics.line(mid, drawY + 6, mid + 1, drawY + drawH * 0.55, mid - 1, drawY + drawH - 5)
    end
  end

  -- North (far) rows first so nearer rows paint over rising walls.
  for row = minRow, maxRow do
    -- 1) Behind walls first so the floor sits in front of them.
    for col = minCol, maxCol do
      local wall = getBehindWallAt(col, row)
      if wall and include(col, row) then
        drawFrontWallElev(wall, col, row, true)
      end
    end

    -- 2) Floor strip — in side view, side/half walls still sit on brick.
    for col = minCol, maxCol do
      if self:hasGround(col, row) and include(col, row) then
        local floorKind = "ground"
        if self:isIceTile(col, row) then
          floorKind = "ice"
        elseif self:isMossTile(col, row) then
          floorKind = "moss"
        end
        drawFloorCell(col, row, floorKind, false)
      end
    end

    for col = minCol, maxCol do
      if self:hasGround(col, row) and include(col, row) and self:isInFireZone(col, row) then
        local x = (col - 1) * size
        local floorTop = cellFloorTop(col, row)
        love.graphics.setColor(0.75, 0.25, 0.08, 0.28)
        love.graphics.rectangle("fill", x + 1, floorTop, size - 2, faceH - 1)
      end
    end

    for col = minCol, maxCol do
      if self.puddleTiles[self:key(col, row)] and include(col, row) then
        local puddle = self.puddleTiles[self:key(col, row)]
        local x = (col - 1) * size
        local floorTop = cellFloorTop(col, row)
        local scaleAlong, scaleAcross, directionX, directionY, contentShiftY =
          puddleScales(puddle, size, PUDDLE_FRAME_SIZE, PUDDLE_FRAME_SIZE)
        local overlap = size * 0.08
        drawPuddleDrag(
          sprites,
          puddle,
          x + size * 0.5 + directionX * overlap,
          floorTop - size * 0.5 + directionY * overlap - contentShiftY,
          scaleAlong,
          scaleAcross
        )
        local bridgeAlpha = puddleAlpha(puddle)
        eachPuddleBridgeTile(puddle, function(bridgeCol, bridgeRow)
          if include(bridgeCol, bridgeRow) then
            local bridgeX = (bridgeCol - 1) * size
            local bridgeFloorTop = cellFloorTop(bridgeCol, bridgeRow)
            local longW = sprites.puddleLong:getWidth()
            local longH = sprites.puddleLong:getHeight()
            local bAlong, bAcross, _, _, bShiftY =
              puddleScales(puddle, size, longW, longH)
            love.graphics.setColor(1, 1, 1, bridgeAlpha)
            love.graphics.draw(
              sprites.puddleLong,
              bridgeX + size * 0.5,
              bridgeFloorTop - size * 0.5 - bShiftY,
              0,
              bAlong,
              bAcross,
              longW * 0.5,
              longH * 0.5
            )
          end
        end)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)

    -- 3) Front-layer front / half / cracked walls
    for col = minCol, maxCol do
      local wall = self.wallTiles[self:key(col, row)]
      if wall and include(col, row) and wall.texture == "front" and wall.depth ~= "behind" then
        drawFrontWallElev(wall, col, row, false)
      end
    end

    -- 4) Side walls (can sit over behind walls)
    for col = minCol, maxCol do
      local wall = self.wallTiles[self:key(col, row)]
      if wall and include(col, row) and wall.texture == "side" then
        drawSideWallElev(wall, col, row)
      end
    end

    -- 5) Props seated on the floor top (sprite feet on brick).
    local FIRE_FOOT = 121 -- content bottom of fire-sheet frames (128 tall, 7px pad)
    for col = minCol, maxCol do
      if include(col, row) then
      local key = self:key(col, row)
      local floorTop = cellFloorTop(col, row)
      local centerX = (col - 0.5) * size

      if self.snowflakeTiles[key] then
        local target = size * 0.55
        local scale = target / math.max(sprites.snowflake:getWidth(), sprites.snowflake:getHeight())
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
          sprites.snowflake,
          centerX,
          floorTop,
          0,
          scale,
          scale,
          sprites.snowflake:getWidth() / 2,
          sprites.snowflake:getHeight()
        )
      end

      if self.pressurePlateTiles[key] then
        drawPressurePlateAt(
          centerX,
          floorTop,
          size,
          zoom,
          self.pressurePlateTiles[key].pressed,
          true
        )
      end

      if self.teaTiles[key] then
        drawTeaCup(centerX, floorTop, zoom, true)
       end

      if self.fridgeTiles[key] then
        drawFridge(centerX, floorTop, size, zoom, true)
      end

      if self.puzzlePieceTiles[key] then
        local piece = self.puzzlePieceTiles[key]
        drawKeySprite(centerX, floorTop, size, piece.variant or "top", false, 1, true)
      end

       if self.pressureDoorTiles[key] then
         local x = (col - 1) * size
         local y = floorTop - size
         drawPressureDoorAt(x, y, size, zoom, true, self:isPressureDoorOpen())
       end

       if self.puzzleDoorTiles[key] then
         local x = (col - 1) * size
         local y = floorTop - size
         drawPuzzleDoorAt(x, y, size, zoom, true, self.puzzleDoorTiles[key].open)
       end

      local boulder = self.boulderTiles[key]
      if boulder then
        drawBoulderAt(getBoulderSprite(sprites, boulder), centerX, floorTop, size, true)
      end

      if self.fireTiles[key] then
        local time = (love.timer and love.timer.getTime()) or 0
        local frameIndex = math.floor(time / FIRE_FRAME_DURATION) % FIRE_FRAME_COUNT + 1
        local fireH = size * 0.88
        local scale = fireH / FIRE_FRAME_SIZE
        -- Dig logs into the brick face so the fire overlaps the ground.
        local sink = math.max(4, size * 0.16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
          sprites.fire,
          sprites.fireFrames[frameIndex],
          centerX,
          floorTop + sink,
          0,
          scale,
          scale,
          FIRE_FRAME_SIZE / 2,
          FIRE_FOOT
        )
      end
      end
    end

    if showGrid then
      love.graphics.setColor(0.18, 0.40, 0.55, 0.45)
      local x0 = (minCol - 1) * size
      local x1 = maxCol * size
      local y = (row - 1) * size
      love.graphics.setLineWidth(1 / zoom)
      -- Cell bounds = floor face + wall stack.
      love.graphics.line(x0, y, x1, y)
      love.graphics.line(x0, y + size, x1, y + size)
      for col = minCol - 1, maxCol do
        local x = col * size
        love.graphics.line(x, y, x, y + size)
      end
      -- Floor / wall split inside each cell.
      local floorLine = y + size - faceH
      love.graphics.setColor(0.35, 0.70, 0.90, 0.35)
      love.graphics.line(x0, floorLine, x1, floorLine)
    end
  end
end



return Grid
