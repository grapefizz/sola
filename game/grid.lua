local Grid = {}
Grid.__index = Grid

local Perspective = require "game.perspective"

local TEXTURE_GRID_SIZE = 1
local FIRE_FRAME_SIZE = 128
local FIRE_FRAME_COUNT = 9
local FIRE_FRAME_DURATION = 1 / 12
local tileSprites
local groundQuadCache = {}
local iceQuadCache = {}

local function getTileSprites()
  if tileSprites then
    return tileSprites
  end

  tileSprites = {
    ground = love.graphics.newImage("assets/floor.png"),
    ice = love.graphics.newImage("assets/ice.png"),
    snowflake = love.graphics.newImage("assets/snowflake.png"),
    fire = love.graphics.newImage("assets/fire-sheet.png"),
    keyTop = love.graphics.newImage("assets/key-top.png"),
    keyDown = love.graphics.newImage("assets/key-down.png"),
    keyPieceTop = love.graphics.newImage("assets/key-piece-top.png"),
    keyPieceBottom = love.graphics.newImage("assets/key-piece-bottom.png"),
    keyPieceTopSide = love.graphics.newImage("assets/key-piece-top-side.png"),
    keyPieceBottomSide = love.graphics.newImage("assets/key-piece-bottom-side.png"),
  }
  tileSprites.ground:setFilter("linear", "linear")
  tileSprites.ice:setFilter("linear", "linear")
  tileSprites.snowflake:setFilter("linear", "linear")
  tileSprites.fire:setFilter("linear", "linear")
  tileSprites.keyTop:setFilter("linear", "linear")
  tileSprites.keyDown:setFilter("linear", "linear")
  tileSprites.keyPieceTop:setFilter("linear", "linear")
  tileSprites.keyPieceBottom:setFilter("linear", "linear")
  tileSprites.keyPieceTopSide:setFilter("linear", "linear")
  tileSprites.keyPieceBottomSide:setFilter("linear", "linear")
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
  return tileSprites
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
    groundTiles = {},
    waterTiles = {},
    fireTiles = {},
    iceTiles = {},
    snowflakeTiles = {},
    teaTiles = {},
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
  consider(self.waterTiles)
  consider(self.fireTiles)
  consider(self.iceTiles)
  consider(self.snowflakeTiles)
  consider(self.teaTiles)
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
  self.groundTiles[key] = nil
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.sideViewTiles[key] = nil
end



function Grid:clear()
  self.groundTiles = {}
  self.waterTiles = {}
  self.fireTiles = {}
  self.iceTiles = {}
  self.snowflakeTiles = {}
  self.teaTiles = {}
  self.puzzlePieceTiles = {}
  self.puzzleDoorTiles = {}
  self.pressureDoorTiles = {}
  self.pressurePlateTiles = {}
  self.pressureDoorOpen = false
  self.wallTiles = {}
  self.boulderTiles = {}
  self.sideViewTiles = {}
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



function Grid:clearWater()
  self.waterTiles = {}
end



function Grid:addWater(col, row)
  if self:hasGround(col, row)
    and not self:isInFireZone(col, row)
    and not self:isIceTile(col, row)
    and not self:isTeaTile(col, row)
    and not self:isBlocking(col, row)
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
  self.waterTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.wallTiles[key] = nil
  -- Keep boulder, puzzle pieces, and pressure plates so ice can sit under them.
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
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
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
  return next(self.puzzleDoorTiles) ~= nil
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
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.puzzleDoorTiles[key] = { col = col, row = row }
end

function Grid:removePuzzleDoor(col, row)
  self.puzzleDoorTiles[self:key(col, row)] = nil
end

function Grid:isPuzzleDoor(col, row)
  return self.puzzleDoorTiles[self:key(col, row)] ~= nil
end

function Grid:openPuzzleDoor(col, row)
  local key = self:key(col, row)
  if self.puzzleDoorTiles[key] then
    self.puzzleDoorTiles[key] = nil
    return true
  end
  return false
end

function Grid:openPuzzleDoors()
  self.puzzleDoorTiles = {}
end

function Grid:addPressureDoor(col, row)
  if not self:isInside(col, row) then
    return
  end
  self:setGround(col, row)
  local key = self:key(col, row)
  self.waterTiles[key] = nil
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
  self.waterTiles[key] = nil
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
    plate.pressed = plate.col == playerCol and plate.row == playerRow
    if plate.pressed and (sizeRatio or 0) > 0.6 then
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
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
  self.iceTiles[key] = nil
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.boulderTiles[key] = nil

  local fill = nil
  if options.half then
    fill = tonumber(options.fill) or 0.5
    fill = math.max(0.1, math.min(0.9, fill))
    fill = math.floor(fill * 10 + 0.5) / 10
    texture = "front"
  end

  local existing = self.wallTiles[key]
  local under = nil

  -- Side wall on top of a behind front wall keeps the behind wall underneath.
  if texture == "side" and existing then
    if existing.texture == "front" and existing.depth == "behind" then
      under = {
        texture = "front",
        depth = "behind",
        cracked = existing.cracked and true or false,
        half = existing.half and true or false,
        fill = existing.fill,
      }
    elseif existing.under then
      under = existing.under
    end
  end

  -- Behind front wall under an existing side wall: stash as under, keep side.
  if texture == "front" and depth == "behind" and existing and existing.texture == "side" then
    existing.under = {
      texture = "front",
      depth = "behind",
      cracked = options.cracked and true or false,
      half = options.half and true or false,
      fill = fill,
    }
    return
  end

  self.wallTiles[key] = {
    col = col,
    row = row,
    texture = texture,
    lean = texture == "side" and lean or nil,
    creased = options.creased and true or false,
    cracked = options.cracked and true or false,
    half = options.half and true or false,
    fill = fill,
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
function Grid:canPassHalfWall(col, row, sizeRatio)
  local wall = self.wallTiles[self:key(col, row)]
  if not wall then
    return false
  end
  -- Side walls always block; half-pass only applies to front half walls on the front layer.
  if wall.texture == "side" then
    return false
  end
  if not wall.half then
    return false
  end
  local fill = wall.fill or 0.5
  return sizeRatio <= (1 - fill) + 1e-6
end

function Grid:addBoulder(col, row, options)
  if not self:isInside(col, row) then
    return
  end
  options = options or {}
  self:setGround(col, row)
  local key = self:key(col, row)
  self.waterTiles[key] = nil
  self.fireTiles[key] = nil
  -- Keep ice so the boulder can sit on top of it.
  self.snowflakeTiles[key] = nil
  self.teaTiles[key] = nil
  self.puzzlePieceTiles[key] = nil
  self.puzzleDoorTiles[key] = nil
  self.pressureDoorTiles[key] = nil
  self.pressurePlateTiles[key] = nil
  self.wallTiles[key] = nil
  self.boulderTiles[key] = {
    col = col,
    row = row,
    cracked = options.cracked and true or false,
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

-- Optional sizeRatio lets half-walls open when the ice cube is small enough.
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
  if not self:isWallTile(col, row) then
    return false
  end
  if sizeRatio ~= nil and self:canPassHalfWall(col, row, sizeRatio) then
    return false
  end
  return true
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
    return -2
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
        cells[col] = boulder.cracked and "Q" or "O"
      elseif self:isIceTile(col, row) then
        cells[col] = "I"
      elseif self:isSnowflakeTile(col, row) then
        cells[col] = "S"
      elseif self:isBoulderTile(col, row) then
        local boulder = self.boulderTiles[self:key(col, row)]
        cells[col] = boulder.cracked and "P" or "B"
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

  local map = table.concat(lines, "\n")
  if not next(self.sideViewTiles) then
    return map
  end

  local sideLines = { map, "@side" }
  for row = 1, self.rows do
    local cells = {}
    for col = 1, self.columns do
      cells[col] = self:isSideView(col, row) and "#" or "."
    end
    sideLines[#sideLines + 1] = table.concat(cells)
  end
  return table.concat(sideLines, "\n")
end



function Grid:load(serialized)
  self:clear()
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
      elseif cell == "O" then
        self:addIce(col, row)
        self:addBoulder(col, row)
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

local PUZZLE_DOOR_PALETTE = {
  side = { 0.10, 0.18, 0.34 },
  top = { 0.42, 0.68, 0.95 },
  face = { 0.10, 0.22, 0.42 },
  line = { 0.55, 0.78, 1.0 },
  accent = { 0.70, 0.88, 1.0 },
  knob = true,
}

local PRESSURE_DOOR_PALETTE = {
  side = { 0.12, 0.24, 0.16 },
  top = { 0.42, 0.88, 0.62 },
  face = { 0.14, 0.30, 0.20 },
  line = { 0.42, 0.92, 0.64 },
  accent = { 0.55, 1.0, 0.74 },
  mark = "plus",
}

local function drawPuzzleDoorAt(x, y, size, zoom, side, open)
  if side then
    -- Caller passes y = floorTop - size (same convention as before).
    drawDoorElevAt(x, y + size, size, zoom, open, PUZZLE_DOOR_PALETTE)
    return
  end

  local pad = size * 0.1
  local dx = x + pad
  local dy = y + pad
  local dw = size - pad * 2
  local dh = size - pad * 2
  if open then
    love.graphics.setColor(0.025, 0.05, 0.08, 0.96)
    love.graphics.rectangle("fill", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.28, 0.62, 0.95, 0.9)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.45, 0.82, 1.0, 0.75)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.line(dx + 4, dy + 4, dx + dw - 4, dy + 4)
  else
    love.graphics.setColor(0.06, 0.16, 0.34, 0.98)
    love.graphics.rectangle("fill", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.28, 0.62, 0.95, 0.95)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", dx, dy, dw, dh, 2, 2)
    love.graphics.setColor(0.55, 0.80, 1.0, 0.85)
    love.graphics.setLineWidth(2 / zoom)
    local barX = dx + dw * 0.5
    love.graphics.line(barX, dy + 4, barX, dy + dh - 4)
    love.graphics.line(dx + 4, dy + dh * 0.45, dx + dw - 4, dy + dh * 0.45)
    love.graphics.circle("fill", barX + dw * 0.18, dy + dh * 0.45, 2.5)
  end
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

-- Side view: plate is recessed into the floor face; top-down stays a pad on the tile.
local function drawPressurePlateAt(centerX, centerY, size, zoom, pressed, side, faceH)
  if side then
    faceH = faceH or (size * Perspective.FLOOR_FACE)
    local plateW = size * 0.52
    local plateH = math.max(4, faceH * 0.78)
    local px = centerX - plateW * 0.5
    -- Sink slightly into the brick face so ground flanks read as surrounding stone.
    local py = centerY + (faceH - plateH) * 0.45
    love.graphics.setColor(0.06, 0.08, 0.10, 0.98)
    love.graphics.rectangle("fill", px, py, plateW, plateH, 1, 1)
    if pressed then
      love.graphics.setColor(0.28, 0.78, 0.54, 1)
    else
      love.graphics.setColor(0.55, 0.64, 0.72, 0.95)
    end
    love.graphics.setLineWidth(1.25 / zoom)
    love.graphics.rectangle("line", px, py, plateW, plateH, 1, 1)
    love.graphics.setColor(
      pressed and 0.32 or 0.18,
      pressed and 0.88 or 0.42,
      pressed and 0.58 or 0.55,
      0.95
    )
    local inset = math.max(1.5, plateH * 0.18)
    love.graphics.rectangle(
      "fill",
      px + inset,
      py + inset,
      plateW - inset * 2,
      plateH - inset * 2,
      1,
      1
    )
    love.graphics.setColor(0.82, 0.92, 0.98, 0.75)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.line(centerX - plateW * 0.18, py + plateH * 0.5, centerX + plateW * 0.18, py + plateH * 0.5)
    return
  end

  local w = size * 0.72
  local h = size * 0.22
  local y = centerY - h * 0.5
  love.graphics.setColor(0.10, 0.12, 0.15, 0.95)
  love.graphics.rectangle("fill", centerX - w * 0.5, y, w, h, 2, 2)
  if pressed then
    love.graphics.setColor(0.30, 0.82, 0.58, 1)
  else
    love.graphics.setColor(0.62, 0.70, 0.76, 0.95)
  end
  love.graphics.setLineWidth(1.5 / zoom)
  love.graphics.rectangle("line", centerX - w * 0.5, y, w, h, 2, 2)
  love.graphics.setColor(pressed and 0.34 or 0.22, pressed and 0.92 or 0.48, pressed and 0.64 or 0.62, 0.95)
  love.graphics.rectangle("fill", centerX - w * 0.34, y + h * 0.22, w * 0.68, h * 0.56, 1, 1)
  love.graphics.setColor(0.82, 0.92, 0.98, 0.8)
  love.graphics.setLineWidth(1 / zoom)
  love.graphics.line(centerX - w * 0.22, y + h * 0.5, centerX + w * 0.22, y + h * 0.5)
end

local function drawBoulderAt(x, y, size, cracked, zoom, side)
  local pad = size * (side and 0.16 or 0.12)
  local bx = x + pad
  local by = y + pad
  local bsize = size - pad * 2
  if side then
    -- Standing rock: taller than wide.
    by = y + size * 0.08
    bsize = size * 0.72
    local bh = size * 0.88
    if cracked then
      love.graphics.setColor(0.36, 0.34, 0.32, 0.98)
    else
      love.graphics.setColor(0.42, 0.40, 0.38, 0.98)
    end
    love.graphics.rectangle("fill", bx, by + (size - bh) - pad, bsize, bh, 5, 5)
    love.graphics.setColor(0.62, 0.60, 0.56, 0.9)
    love.graphics.setLineWidth(1.5 / zoom)
    love.graphics.rectangle("line", bx, by + (size - bh) - pad, bsize, bh, 5, 5)
    love.graphics.setColor(0.28, 0.26, 0.24, 0.55)
    local top = by + (size - bh) - pad
    love.graphics.line(bx + bsize * 0.28, top + bh * 0.22, bx + bsize * 0.55, top + bh * 0.7)
    love.graphics.line(bx + bsize * 0.6, top + bh * 0.3, bx + bsize * 0.78, top + bh * 0.62)
    if cracked then
      love.graphics.setColor(0.12, 0.10, 0.08, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(
        bx + bsize * 0.2, top + bh * 0.15,
        bx + bsize * 0.45, top + bh * 0.48,
        bx + bsize * 0.22, top + bh * 0.85
      )
      love.graphics.line(
        bx + bsize * 0.45, top + bh * 0.48,
        bx + bsize * 0.82, top + bh * 0.35
      )
    end
    return
  end

  if cracked then
    love.graphics.setColor(0.36, 0.34, 0.32, 0.98)
  else
    love.graphics.setColor(0.42, 0.40, 0.38, 0.98)
  end
  love.graphics.rectangle("fill", bx, by, bsize, bsize, 5, 5)
  love.graphics.setColor(0.62, 0.60, 0.56, 0.9)
  love.graphics.setLineWidth(1.5 / zoom)
  love.graphics.rectangle("line", bx, by, bsize, bsize, 5, 5)
  love.graphics.setColor(0.28, 0.26, 0.24, 0.55)
  love.graphics.line(bx + bsize * 0.28, by + bsize * 0.22, bx + bsize * 0.55, by + bsize * 0.7)
  love.graphics.line(bx + bsize * 0.6, by + bsize * 0.3, bx + bsize * 0.78, by + bsize * 0.62)
  if cracked then
    love.graphics.setColor(0.12, 0.10, 0.08, 0.95)
    love.graphics.setLineWidth(2 / zoom)
    love.graphics.line(
      bx + bsize * 0.2, by + bsize * 0.15,
      bx + bsize * 0.45, by + bsize * 0.48,
      bx + bsize * 0.22, by + bsize * 0.85
    )
    love.graphics.line(
      bx + bsize * 0.45, by + bsize * 0.48,
      bx + bsize * 0.82, by + bsize * 0.35
    )
    love.graphics.line(
      bx + bsize * 0.42, by + bsize * 0.55,
      bx + bsize * 0.78, by + bsize * 0.8
    )
  end
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

  -- Skip full-canvas clear when compositing after another pass.
  if filter ~= "side" then
    love.graphics.setColor(0.025, 0.05, 0.09)
    love.graphics.rectangle("fill", 0, 0, width, height)
  end

  -- Side walls + half walls are wall-only: never paint brick under them.
  local function hidesGround(col, row)
    local wall = self.wallTiles[self:key(col, row)]
    if not wall then
      return false
    end
    if wall.texture == "side" then
      return true
    end
    if wall.half then
      return true
    end
    if wall.under and wall.under.half then
      return true
    end
    return false
  end

  local function drawFrontWallTopdown(wall, x, y)
    local fill = wall.half and (wall.fill or 0.5) or 1
    local wallH
    local wallY
    if wall.half then
      wallH = (self.size - 2) * fill
      wallY = y + self.size - 1 - wallH
    else
      wallH = self.size - 2
      wallY = y + 1
    end

    if wall.cracked then
      love.graphics.setColor(0.48, 0.34, 0.26, 0.95)
    else
      love.graphics.setColor(0.55, 0.38, 0.28, 0.95)
    end
    love.graphics.rectangle("fill", x + 1, wallY, self.size - 2, wallH, 2, 2)
    love.graphics.setColor(0.78, 0.58, 0.42, 0.9)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.rectangle("line", x + 1, wallY, self.size - 2, wallH, 2, 2)

    if wall.cracked then
      love.graphics.setColor(0.18, 0.10, 0.06, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(
        x + 8, wallY + 6,
        x + self.size * 0.42, wallY + wallH * 0.45,
        x + 10, wallY + wallH - 7
      )
      love.graphics.line(
        x + self.size * 0.42, wallY + wallH * 0.45,
        x + self.size - 9, wallY + wallH * 0.28
      )
      love.graphics.line(
        x + self.size * 0.38, wallY + wallH * 0.55,
        x + self.size - 8, wallY + wallH - 8
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

  -- Behind walls: full behind walls get an inset ground pad; half / side stay wall-only.
  local behindPad = math.max(8, math.floor(self.size * 0.18))
  for col = minCol, maxCol do
    for row = minRow, maxRow do
      local behind = getBehindWallAt(col, row)
      if behind and include(col, row) then
        local x, y = self:tileOrigin(col, row)
        drawFrontWallTopdown(behind, x, y)
        if not behind.half and not hidesGround(col, row) then
          local image = self:isIceTile(col, row) and sprites.ice or sprites.ground
          local cache = self:isIceTile(col, row) and iceQuadCache or groundQuadCache
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

  love.graphics.setLineWidth(1 / zoom)
  for _, tile in pairs(self.waterTiles) do
    if isVisible(tile) and include(tile.col, tile.row) then
      local x, y = self:tileOrigin(tile.col, tile.row)
      love.graphics.setColor(0.10, 0.48, 0.72, 0.75)
      love.graphics.rectangle("fill", x + 2, y + 2, self.size - 4, self.size - 4, 3, 3)
      love.graphics.setColor(0.40, 0.78, 0.95, 0.65)
      love.graphics.line(x + 8, y + 13, x + self.size - 8, y + 13)
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
      drawPuzzleDoorAt(x, y, self.size, zoom, false, false)
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

      if wall.cracked then
        love.graphics.setColor(0.26, 0.40, 0.52, 0.95)
      else
        love.graphics.setColor(0.32, 0.48, 0.62, 0.95)
      end
      love.graphics.rectangle("fill", stripX, y + 1, stripW, self.size - 2, 2, 2)
      love.graphics.setColor(0.55, 0.72, 0.88, 0.85)
      love.graphics.setLineWidth(1 / zoom)
      love.graphics.rectangle("line", stripX, y + 1, stripW, self.size - 2, 2, 2)

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
      local x, y = self:tileOrigin(boulder.col, boulder.row)
      drawBoulderAt(x, y, self.size, boulder.cracked, zoom, false)
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

  local originX = (minCol - 1) * size
  local originY = (minRow - 1) * size
  local spanW = (maxCol - minCol + 1) * size
  local spanH = (maxRow - minRow + 1) * size
  -- Full clear only when this is the sole pass (no mixed top-down underlay).
  if filter ~= "side" then
    love.graphics.setColor(0.025, 0.05, 0.09)
    love.graphics.rectangle("fill", originX - size, originY - size, spanW + size * 2, spanH + size * 2)
  end

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

  local function drawFloorCell(col, row, ice, plateCut)
    local x, y = self:tileOrigin(col, row)
    local floorTop = cellFloorTop(col, row)
    local faceTop = floorTop
    local faceBottom = y + size
    local faceHLocal = faceBottom - faceTop
    local lip = math.min(thick, faceHLocal * 0.38)
    local topH = math.max(2, faceHLocal - lip)

    local image = ice and sprites.ice or sprites.ground
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
      local bandKey = "band:" .. col .. ":" .. row .. ":" .. math.floor(srcOffsetX) .. ":" .. math.floor(srcBandW) .. ":" .. (ice and "i" or "g")
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
    local wallH = Perspective.wallHeight(size, fill)
    local floorTop = cellFloorTop(col, row)
    local wallY = floorTop - wallH
    local depth = size * (behind and 0.12 or 0.18)
    local shade = behind and 0.78 or 1
    local inset = behind and math.max(3, size * 0.10) or 0
    x = x + inset
    local wallW = size - 2 - inset * 2
    if wallW < 4 then
      wallW = 4
    end

    love.graphics.setColor(0.32 * shade, 0.20 * shade, 0.14 * shade, 0.95)
    love.graphics.polygon(
      "fill",
      x + wallW, wallY,
      x + wallW + depth, wallY - depth * 0.4,
      x + wallW + depth, floorTop - depth * 0.4,
      x + wallW, floorTop
    )
    love.graphics.setColor(0.80 * shade, 0.62 * shade, 0.46 * shade, 1)
    love.graphics.polygon(
      "fill",
      x + 1, wallY,
      x + wallW, wallY,
      x + wallW + depth, wallY - depth * 0.4,
      x + 1 + depth, wallY - depth * 0.4
    )
    if wall.cracked then
      love.graphics.setColor(0.52 * shade, 0.36 * shade, 0.28 * shade, 1)
    else
      love.graphics.setColor(0.62 * shade, 0.44 * shade, 0.33 * shade, 1)
    end
    love.graphics.rectangle("fill", x + 1, wallY, wallW, wallH, 2, 2)
    love.graphics.setColor(0.90 * shade, 0.74 * shade, 0.56 * shade, 0.9)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.rectangle("line", x + 1, wallY, wallW, wallH, 2, 2)

    if wall.cracked then
      love.graphics.setColor(0.12, 0.07, 0.04, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      love.graphics.line(
        x + 9, wallY + 7,
        x + size * 0.45, wallY + wallH * 0.5,
        x + 11, wallY + wallH - 7
      )
      love.graphics.line(
        x + size * 0.45, wallY + wallH * 0.5,
        x + size - 9 - inset, wallY + wallH * 0.28
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

    if wall.cracked then
      love.graphics.setColor(0.28, 0.40, 0.52, 1)
    else
      love.graphics.setColor(0.36, 0.50, 0.64, 1)
    end
    love.graphics.rectangle("fill", sx, wallY, w, wallMax, 2, 2)
    love.graphics.setColor(0.58, 0.72, 0.88, 1)
    love.graphics.rectangle("fill", sx, wallY, w, 4)
    love.graphics.setColor(0.12, 0.18, 0.26, 0.4)
    love.graphics.rectangle("fill", sx + w - 3, wallY, 3, wallMax)
    love.graphics.setColor(0.70, 0.84, 0.96, 0.85)
    love.graphics.setLineWidth(1 / zoom)
    love.graphics.rectangle("line", sx, wallY, w, wallMax, 2, 2)

    if wall.cracked then
      love.graphics.setColor(0.06, 0.10, 0.14, 0.95)
      love.graphics.setLineWidth(2 / zoom)
      local mid = sx + w * 0.5
      love.graphics.line(mid, wallY + 6, mid + 1, wallY + wallMax * 0.55, mid - 1, floorTop - 5)
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
    --    Pressure plates cut the middle out so the plate sits in the ground.
    for col = minCol, maxCol do
      if self:hasGround(col, row) and include(col, row) then
        local hasPlate = self.pressurePlateTiles[self:key(col, row)] ~= nil
        drawFloorCell(col, row, self:isIceTile(col, row), hasPlate)
        if hasPlate then
          local floorTop = cellFloorTop(col, row)
          local centerX = (col - 0.5) * size
          drawPressurePlateAt(
            centerX,
            floorTop,
            size,
            zoom,
            self.pressurePlateTiles[self:key(col, row)].pressed,
            true,
            faceH
          )
        end
      end
    end

    for col = minCol, maxCol do
      if self:hasGround(col, row) and include(col, row) and self:isInFireZone(col, row) then
        local x = (col - 1) * size
        local floorTop = cellFloorTop(col, row)
        local hasPlate = self.pressurePlateTiles[self:key(col, row)] ~= nil
        if hasPlate then
          local plateW = size * 0.52
          local flank = (size - plateW) * 0.5
          love.graphics.setColor(0.75, 0.25, 0.08, 0.28)
          love.graphics.rectangle("fill", x + 1, floorTop, flank - 1, faceH - 1)
          love.graphics.rectangle("fill", x + flank + plateW, floorTop, flank - 1, faceH - 1)
        else
          love.graphics.setColor(0.75, 0.25, 0.08, 0.28)
          love.graphics.rectangle("fill", x + 1, floorTop, size - 2, faceH - 1)
        end
      end
    end

    for col = minCol, maxCol do
      if self:hasWater(col, row) and include(col, row) then
        local x = (col - 1) * size
        local floorTop = cellFloorTop(col, row)
        love.graphics.setColor(0.12, 0.52, 0.78, 0.85)
        love.graphics.rectangle("fill", x + 3, floorTop + 2, size - 6, math.max(2, faceH - 4), 1, 1)
      end
    end

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

      if self.teaTiles[key] then
        drawTeaCup(centerX, floorTop, zoom, true)
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
         drawPuzzleDoorAt(x, y, size, zoom, true, false)
       end

      local boulder = self.boulderTiles[key]
      if boulder then
        local bh = size * 0.70
        local bw = size * 0.52
        local bx = centerX - bw * 0.5
        local by = floorTop - bh
        local depth = bw * 0.22
        love.graphics.setColor(0.28, 0.26, 0.24, 1)
        love.graphics.polygon("fill", bx + bw, by, bx + bw + depth, by - depth * 0.45, bx + bw + depth, floorTop - depth * 0.45, bx + bw, floorTop)
        love.graphics.setColor(0.58, 0.56, 0.52, 1)
        love.graphics.polygon("fill", bx, by, bx + bw, by, bx + bw + depth, by - depth * 0.45, bx + depth, by - depth * 0.45)
        if boulder.cracked then
          love.graphics.setColor(0.38, 0.36, 0.34, 1)
        else
          love.graphics.setColor(0.46, 0.44, 0.42, 1)
        end
        love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)
        love.graphics.setColor(0.7, 0.68, 0.64, 0.9)
        love.graphics.setLineWidth(1.25 / zoom)
        love.graphics.rectangle("line", bx, by, bw, bh, 4, 4)
        if boulder.cracked then
          love.graphics.setColor(0.08, 0.06, 0.05, 0.95)
          love.graphics.setLineWidth(2 / zoom)
          love.graphics.line(bx + bw * 0.25, by + 8, bx + bw * 0.5, by + bh * 0.55, bx + bw * 0.28, by + bh - 6)
        end
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
