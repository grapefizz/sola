local Editor = {}
Editor.__index = Editor

local Grid = require "game.grid"
local Perspective = require "game.perspective"

local LEVELS_DIR = "levels"
local HUD_X, HUD_Y = 10, 10
local HUD_W = 188
local BUTTON_X = 18
local BUTTON_W = 172
local BUTTON_H = 28
local BUTTON_GAP = 32
local ICON_SIZE = 22
local ICON_PAD = 3
local DROPDOWN_ITEM_H = 28
local DROPDOWN_MAX_VISIBLE = 8
local HUD_FONT_SIZE = 14
local NAME_MAX_LEN = 24
local DEFAULT_LEVEL_TIME = 40
local MAX_LEVEL_TIME = 999
local DEFAULT_SNOWFLAKE_SECONDS = Grid.DEFAULT_SNOWFLAKE_SECONDS or 3
local MIN_SNOWFLAKE_SECONDS = 1
local MAX_SNOWFLAKE_SECONDS = 99
local LEGEND_H = 132

-- Single source of truth: add a tile tool here (+ applyTool / grid draw)
-- and its left-panel icon is snapshotted automatically.
local TOOLS = {
  { name = "save", label = "Save", icon = "save" },
  { name = "load", label = "Load", icon = "load" },
  { name = "time_limit", label = "Time Limit", icon = "time_limit" },
  { name = "ground", label = "Ground", icon = "tile" },
  { name = "moss", label = "Moss Block", icon = "tile" },
  { name = "fire", label = "Campfire", icon = "tile" },
  { name = "ice", label = "Ice Floor", icon = "tile" },
  { name = "snowflake", label = "Snowflake", icon = "tile" },
  { name = "tea", label = "Iced Tea Goal", icon = "tile" },
  { name = "fridge", label = "Level Fridge", icon = "tile" },
  { name = "puzzle_piece", label = "Key Half", icon = "tile" },
  { name = "pressure_plate", label = "Pressure Plate", icon = "tile" },
  { name = "pressure_door", label = "Pressure Door", icon = "pressure_door" },
  { name = "puzzle_door", label = "Key Door", icon = "puzzle_door" },
  { name = "final_door", label = "Final Door", icon = "final_door" },
  { name = "side_wall", label = "Side Wall", icon = "tile" },
  { name = "front_wall", label = "Front Wall", icon = "tile" },
  { name = "half_wall", label = "Half Wall", icon = "tile" },
  { name = "half_wall2", label = "Half Wall 2", icon = "tile" },
  { name = "cracked_wall", label = "Cracked Wall", icon = "tile" },
  { name = "boulder", label = "Boulder", icon = "tile" },
  { name = "boulder2", label = "Boulder 2", icon = "tile" },
  { name = "cracked_boulder", label = "Cracked Boulder", icon = "tile" },
  { name = "erase", label = "Erase", icon = "erase" },
  { name = "perspective", label = "Side Zone", icon = "perspective" },
}

local TOOL_BUTTON_COUNT = #TOOLS
local ACTION_TOOL_COUNT = 3
local ACTION_GROUP_GAP = 12
local HUD_H = 18 + (TOOL_BUTTON_COUNT - 1) * BUTTON_GAP + BUTTON_H + ACTION_GROUP_GAP + 10

local hudFont
local previewSprites
local toolIconCache = {}
local wallPreviewQuadCache = {}

local function controlIsDown()
  return love.keyboard.isDown("lctrl", "rctrl")
end

local function getHudFont()
  if not hudFont then
    hudFont = love.graphics.newFont("assets/fonts/PixelifySans-Regular.ttf", HUD_FONT_SIZE)
  end
  return hudFont
end

local function getPreviewSprites()
  if previewSprites then
    return previewSprites
  end

  previewSprites = {
    ground = love.graphics.newImage("assets/floor.png"),
    ice = love.graphics.newImage("assets/ice.png"),
    moss = love.graphics.newImage("assets/moss.png"),
    mossSide = love.graphics.newImage("assets/moss-side.png"),
    snowflake = love.graphics.newImage("assets/snowflake.png"),
    fire = love.graphics.newImage("assets/fire.png"),
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
    pressureDoor = love.graphics.newImage("assets/Pressure_door.png"),
    wall = love.graphics.newImage("assets/wall.png"),
    brickEnd = love.graphics.newImage("assets/Brickend.png"),
    wallHalf2 = love.graphics.newImage("assets/wall-half2.png"),
  }
  for _, image in pairs(previewSprites) do
    image:setFilter("linear", "linear")
  end
  return previewSprites
end

local function drawWallPreview(image, x, y, width, height, tileSize, alpha, align)
  local imageWidth, imageHeight = image:getDimensions()
  local sourceWidth = imageWidth * math.min(1, width / tileSize)
  local sourceHeight = imageHeight * math.min(1, height / tileSize)
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
  local quad = wallPreviewQuadCache[key]
  if not quad then
    quad = love.graphics.newQuad(sourceX, sourceY, sourceWidth, sourceHeight, imageWidth, imageHeight)
    wallPreviewQuadCache[key] = quad
  end
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(image, quad, x, y, 0, width / sourceWidth, height / sourceHeight)
end

local function drawSideWallPreview(image, x, y, width, height, tileSize, alpha, lean)
  local imageWidth, imageHeight = image:getDimensions()
  local scaleX = width / imageWidth
  local scaleY = height / imageHeight
  love.graphics.setColor(1, 1, 1, alpha)
  if lean == "left" then
    love.graphics.draw(image, x + width, y, 0, -scaleX, scaleY)
  else
    love.graphics.draw(image, x, y, 0, scaleX, scaleY)
  end
end

local function getKeyPiecePreview(sprites, section, sideView)
  if sideView then
    return section == "down" and sprites.keyPieceBottomSide or sprites.keyPieceTopSide
  end
  return section == "down" and sprites.keyPieceBottom or sprites.keyPieceTop
end

local function withAlpha(r, g, b, a, alpha)
  love.graphics.setColor(r, g, b, a * alpha)
end

local function drawToolVisual(tool, wallFacing, cx, cy, size, zoom, alpha, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  alpha = alpha or 1
  halfWallFill = halfWallFill or 0.5
  wallDepth = wallDepth or "front"
  keyVariant = keyVariant == "down" and "down" or "top"
  halfWallAlign = halfWallAlign == "up" and "up" or "down"
  local x = cx - size / 2
  local y = cy - size / 2
  local sprites = getPreviewSprites()

  if tool == "ground" then
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(
      sprites.ground,
      x,
      y,
      0,
      size / sprites.ground:getWidth(),
      size / sprites.ground:getHeight()
    )
  elseif tool == "moss" then
    local img = Perspective.isSide() and sprites.mossSide or sprites.moss
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(
      img,
      x,
      y,
      0,
      size / img:getWidth(),
      size / img:getHeight()
    )
  elseif tool == "fire" then
    local targetSize = size * 0.95
    local scale = targetSize / math.max(
      sprites.fire:getWidth(),
      sprites.fire:getHeight()
    )
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(
      sprites.fire,
      cx,
      cy,
      0,
      scale,
      scale,
      sprites.fire:getWidth() / 2,
      sprites.fire:getHeight() / 2
    )
  elseif tool == "ice" then
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(
      sprites.ice,
      x,
      y,
      0,
      size / sprites.ice:getWidth(),
      size / sprites.ice:getHeight()
    )
  elseif tool == "snowflake" then
    local targetSize = size * 0.82
    local scale = targetSize / math.max(
      sprites.snowflake:getWidth(),
      sprites.snowflake:getHeight()
    )
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(
      sprites.snowflake,
      cx,
      cy,
      0,
      scale,
      scale,
      sprites.snowflake:getWidth() / 2,
      sprites.snowflake:getHeight() / 2
    )
  elseif tool == "tea" then
    withAlpha(0.16, 0.08, 0.03, 0.35, alpha)
    love.graphics.ellipse("fill", cx, cy + 13 * zoom, 13 * zoom, 4 * zoom)
    withAlpha(0.72, 0.34, 0.08, 0.95, alpha)
    love.graphics.polygon(
      "fill",
      cx - 10 * zoom, cy - 10 * zoom,
      cx + 10 * zoom, cy - 10 * zoom,
      cx + 7 * zoom, cy + 13 * zoom,
      cx - 7 * zoom, cy + 13 * zoom
    )
    withAlpha(0.78, 0.94, 1, 0.9, alpha)
    love.graphics.setLineWidth(1.5)
    love.graphics.polygon(
      "line",
      cx - 10 * zoom, cy - 10 * zoom,
      cx + 10 * zoom, cy - 10 * zoom,
      cx + 7 * zoom, cy + 13 * zoom,
      cx - 7 * zoom, cy + 13 * zoom
    )
  elseif tool == "fridge" then
    local fw = size * 0.72
    local fh = size * 0.92
    local fx = cx - fw * 0.5
    local fy = cy - fh * 0.5
    local radius = math.max(2, size * 0.07)
    withAlpha(0.72, 0.90, 0.98, 1, alpha)
    love.graphics.rectangle("fill", fx, fy, fw, fh, radius, radius)
    withAlpha(0.40, 0.67, 0.86, 1, alpha)
    love.graphics.rectangle("fill", fx + fw * 0.08, fy + fh * 0.08, fw * 0.84, fh * 0.84, radius * 0.65, radius * 0.65)
    withAlpha(0.08, 0.13, 0.27, 1, alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", fx, fy, fw, fh, radius, radius)
    love.graphics.line(fx + fw * 0.08, fy + fh * 0.34, fx + fw * 0.92, fy + fh * 0.34)
    love.graphics.rectangle("fill", fx + fw * 0.76, fy + fh * 0.44, fw * 0.07, fh * 0.31, 2, 2)
    love.graphics.setLineWidth(1)
  elseif tool == "puzzle_piece" then
    local sideView = Perspective.isSide()
    local img = getKeyPiecePreview(sprites, keyVariant, sideView)
    local iw, ih = img:getDimensions()
    local target = size * 0.78
    local scale = target / math.max(iw, ih)
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif tool == "pressure_plate" then
    local img = sprites.buttonUnpressed
    local iw, ih = img:getDimensions()
    local target = size * 0.88
    local scale = target / math.max(iw, ih)
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif tool == "pressure_door" then
    local img = sprites.pressureDoor
    local iw, ih = img:getDimensions()
    local target = size * 0.98
    local scale = target / math.max(iw, ih)
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif tool == "puzzle_door" then
    local img = sprites.doorClosed
    local iw, ih = img:getDimensions()
    local target = size * 0.98
    local scale = target / math.max(iw, ih)
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif tool == "final_door" then
    local img = sprites.doorOpen
    local iw, ih = img:getDimensions()
    local target = size * 0.98
    local scale = target / math.max(iw, ih)
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif tool == "side_wall" then
    drawSideWallPreview(sprites.brickEnd, x, y, size, size, size, alpha, wallFacing)
  elseif tool == "front_wall" or tool == "cracked_wall" then
    drawWallPreview(sprites.wall, x, y, size, size, size, alpha)
    if tool == "cracked_wall" then
      withAlpha(0.18, 0.10, 0.06, 0.95, alpha)
      love.graphics.setLineWidth(2)
      love.graphics.line(
        x + 8, y + 6,
        x + size * 0.42, y + size * 0.45,
        x + 10, y + size - 7
      )
      love.graphics.line(
        x + size * 0.42, y + size * 0.45,
        x + size - 9, y + size * 0.28
      )
    end
    if wallDepth == "behind" then
      local pad = math.max(8, math.floor(size * 0.18))
      withAlpha(1, 1, 1, 1, alpha)
      love.graphics.draw(
        sprites.ground,
        x + pad,
        y + pad,
        0,
        (size - pad * 2) / sprites.ground:getWidth(),
        (size - pad * 2) / sprites.ground:getHeight()
      )
    end
  elseif tool == "half_wall" then
    local fill = halfWallFill
    local wallH = size * fill
    local wallY = halfWallAlign == "up" and y or (y + size - wallH)
    drawWallPreview(sprites.wall, x, wallY, size, wallH, size, alpha)
  elseif tool == "half_wall2" then
    local fill = halfWallFill
    local wallW = size * fill
    local wallX = wallFacing == "right" and (x + size - wallW) or x
    drawWallPreview(
      sprites.wallHalf2,
      wallX,
      y,
      wallW,
      size,
      wallW,
      alpha,
      wallFacing == "right" and "right" or "left"
    )
  elseif tool == "boulder" or tool == "boulder2" or tool == "cracked_boulder" then
    local image = sprites.boulder
    if tool == "boulder2" then
      image = sprites.boulder2
    elseif tool == "cracked_boulder" then
      image = sprites.crackedBoulder
    end
    local targetSize = size * 0.98
    local scale = targetSize / math.max(image:getWidth(), image:getHeight())
    withAlpha(1, 1, 1, 1, alpha)
    love.graphics.draw(image, cx, cy, 0, scale, scale, image:getWidth() / 2, image:getHeight() / 2)
  elseif tool == "erase" then
    withAlpha(0.95, 0.25, 0.3, 0.85, alpha)
    love.graphics.setLineWidth(2.5)
    love.graphics.line(x + 6, y + 6, x + size - 6, y + size - 6)
    love.graphics.line(x + size - 6, y + 6, x + 6, y + size - 6)
  elseif tool == "perspective" then
    withAlpha(0.35, 0.72, 0.95, 0.45, alpha)
    love.graphics.rectangle("fill", x + 2, y + 2, size - 4, size - 4, 3, 3)
    withAlpha(0.78, 0.58, 0.42, 0.95, alpha)
    love.graphics.rectangle("fill", x + size * 0.55, y + 4, size * 0.28, size - 8, 1, 1)
  end
end

local function drawToolGhost(tool, wallFacing, cx, cy, size, zoom, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  drawToolVisual(tool, wallFacing, cx, cy, size, zoom, 0.5, halfWallFill, wallDepth, keyVariant, halfWallAlign)
end

local function isFrontWallTool(tool)
  return tool == "front_wall" or tool == "cracked_wall"
end

local function placeToolOnGrid(tool, col, row, grid, wallFacing, halfWallFill, wallDepth, keyVariant, halfWallAlign, snowflakeSeconds)
  local hadGround = grid:hasGround(col, row)
  local partialTile = tool ~= "ground"
    and tool ~= "ice"
    and tool ~= "moss"
    and tool ~= "erase"
    and tool ~= "perspective"
  wallDepth = wallDepth or "front"
  if tool ~= "fridge"
      and tool ~= "ground"
      and tool ~= "ice"
      and tool ~= "moss"
      and tool ~= "erase"
      and tool ~= "perspective" then
    grid:removeFridge(col, row)
  end
  if tool == "ground" then
    grid:setGround(col, row)
    grid:removeFire(col, row)
    grid:removeIce(col, row)
    grid:removeMoss(col, row)
    grid:removeSnowflake(col, row)
    grid:removeTea(col, row)
    grid:removeFridge(col, row)
    grid:removePuzzlePiece(col, row)
    grid:removePuzzleCanvas(col, row)
    grid:removePuzzleDoor(col, row)
    grid:removeFinalDoor(col, row)
    grid:removePressurePlate(col, row)
    grid:removeWall(col, row)
    grid:removeBoulder(col, row)
  elseif tool == "moss" then
    grid:addMoss(col, row)
  elseif tool == "fire" then
    grid:addFire(col, row)
  elseif tool == "ice" then
    grid:addIce(col, row)
  elseif tool == "snowflake" then
    grid:addSnowflake(col, row, snowflakeSeconds or DEFAULT_SNOWFLAKE_SECONDS)
  elseif tool == "tea" then
    grid:addTea(col, row)
  elseif tool == "fridge" then
    grid:addFridge(col, row)
  elseif tool == "puzzle_piece" then
    grid:addPuzzlePiece(col, row, keyVariant == "down" and "down" or "top")
  elseif tool == "pressure_plate" then
    grid:addPressurePlate(col, row)
  elseif tool == "pressure_door" then
    grid:addPressureDoor(col, row)
  elseif tool == "puzzle_door" then
    grid:addPuzzleDoor(col, row)
  elseif tool == "final_door" then
    grid:addFinalDoor(col, row)
  elseif tool == "side_wall" then
    grid:addWall(col, row, "side", wallFacing)
  elseif tool == "front_wall" then
    grid:addWall(col, row, "front", nil, { depth = wallDepth })
  elseif tool == "half_wall" then
    grid:addWall(col, row, "front", nil, {
      half = true,
      fill = halfWallFill or 0.5,
      depth = wallDepth,
      align = halfWallAlign == "up" and "up" or nil,
    })
  elseif tool == "half_wall2" then
    grid:addWall(col, row, "front", wallFacing, {
      half = true,
      half2 = true,
      fill = halfWallFill or 0.5,
      depth = wallDepth,
    })
  elseif tool == "cracked_wall" then
    grid:addWall(col, row, "front", nil, { cracked = true, depth = wallDepth })
  elseif tool == "boulder" then
    grid:addBoulder(col, row)
  elseif tool == "boulder2" then
    grid:addBoulder(col, row, { variant = 2 })
  elseif tool == "cracked_boulder" then
    grid:addBoulder(col, row, { cracked = true })
  elseif tool == "perspective" then
    grid:addSideView(col, row)
  elseif tool == "erase" then
    grid:erase(col, row)
  end

  -- Props and obstacles layer over whatever terrain was already present.
  -- Their add methods may create ground for legacy/gameplay compatibility;
  -- remove that implicit ground when the editor tile was originally empty.
  if partialTile and not hadGround then
    grid.groundTiles[grid:key(col, row)] = nil
  end
end

local function drawActionIcon(kind, size)
  local pad = 4
  local x, y = pad, pad
  local w = size - pad * 2

  if kind == "erase" then
    love.graphics.setColor(0.95, 0.32, 0.36, 1)
    love.graphics.setLineWidth(2.5)
    love.graphics.line(x + 2, y + 2, x + w - 2, y + w - 2)
    love.graphics.line(x + w - 2, y + 2, x + 2, y + w - 2)
  elseif kind == "save" then
    love.graphics.setColor(0.35, 0.72, 0.95, 1)
    love.graphics.rectangle("fill", x, y, w, w, 2, 2)
    love.graphics.setColor(0.12, 0.22, 0.34, 1)
    love.graphics.rectangle("fill", x + 4, y + 2, w - 8, w * 0.35, 1, 1)
    love.graphics.setColor(0.85, 0.93, 1, 1)
    love.graphics.rectangle("fill", x + 5, y + w * 0.48, w - 10, w * 0.38, 1, 1)
  elseif kind == "load" then
    love.graphics.setColor(0.95, 0.78, 0.28, 1)
    love.graphics.polygon(
      "fill",
      x, y + 5,
      x + w * 0.38, y + 5,
      x + w * 0.48, y,
      x + w, y,
      x + w, y + w,
      x, y + w
    )
    love.graphics.setColor(0.72, 0.55, 0.12, 1)
    love.graphics.setLineWidth(1)
    love.graphics.polygon(
      "line",
      x, y + 5,
      x + w * 0.38, y + 5,
      x + w * 0.48, y,
      x + w, y,
      x + w, y + w,
      x, y + w
    )
  elseif kind == "perspective" then
    -- Mini top-down square + side standing block.
    love.graphics.setColor(0.35, 0.72, 0.95, 1)
    love.graphics.rectangle("fill", x + 1, y + w * 0.55, w * 0.42, w * 0.35, 1, 1)
    love.graphics.setColor(0.78, 0.58, 0.42, 1)
    love.graphics.rectangle("fill", x + w * 0.52, y + 2, w * 0.38, w * 0.88, 1, 1)
    love.graphics.setColor(0.92, 0.78, 0.58, 1)
    love.graphics.rectangle("fill", x + w * 0.52, y + 2, w * 0.38, 3, 1, 1)
  elseif kind == "pressure_door" then
    local sprites = getPreviewSprites()
    local img = sprites.pressureDoor
    local iw, ih = img:getDimensions()
    local scale = (w * 0.92) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x + w * 0.5, y + w * 0.5, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif kind == "puzzle_door" then
    local sprites = getPreviewSprites()
    local img = sprites.doorClosed
    local iw, ih = img:getDimensions()
    local scale = (w * 0.92) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x + w * 0.5, y + w * 0.5, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif kind == "final_door" then
    local sprites = getPreviewSprites()
    local img = sprites.doorOpen
    local iw, ih = img:getDimensions()
    local scale = (w * 0.92) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x + w * 0.5, y + w * 0.5, 0, scale, scale, iw * 0.5, ih * 0.5)
  elseif kind == "time_limit" then
    love.graphics.setColor(0.18, 0.52, 0.82, 1)
    love.graphics.circle("fill", x + w * 0.5, y + w * 0.5, w * 0.42)
    love.graphics.setColor(0.88, 0.96, 1, 1)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", x + w * 0.5, y + w * 0.5, w * 0.42)
    love.graphics.line(x + w * 0.5, y + w * 0.5, x + w * 0.5, y + w * 0.25)
    love.graphics.line(x + w * 0.5, y + w * 0.5, x + w * 0.70, y + w * 0.62)
  end
end

local function iconCacheKey(toolName, wallFacing, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  if toolName == "side_wall" then
    return toolName .. ":" .. (wallFacing or "left")
  end
  if toolName == "half_wall" then
    local level = math.max(1, math.min(9, math.floor((halfWallFill or 0.5) * 10 + 0.5)))
    return toolName .. ":" .. level .. ":" .. (wallDepth or "front") .. ":" .. (halfWallAlign == "up" and "up" or "down")
  end
  if toolName == "half_wall2" then
    local level = math.max(1, math.min(9, math.floor((halfWallFill or 0.5) * 10 + 0.5)))
    return toolName .. ":" .. level .. ":" .. (wallDepth or "front") .. ":" .. (wallFacing or "left")
  end
  if toolName == "front_wall" or toolName == "cracked_wall" then
    return toolName .. ":" .. (wallDepth or "front")
  end
  if toolName == "puzzle_piece" then
    return toolName .. ":" .. (keyVariant == "down" and "down" or "top")
  end
  return toolName
end

local function clearToolIcon(toolName)
  for key, canvas in pairs(toolIconCache) do
    if key == toolName or key:match("^" .. toolName .. ":") then
      if canvas and canvas.release then
        canvas:release()
      end
      toolIconCache[key] = nil
    end
  end
end

local function buildToolIcon(toolEntry, wallFacing, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  local canvas = love.graphics.newCanvas(ICON_SIZE, ICON_SIZE)
  canvas:setFilter("linear", "linear")

  local prevCanvas = love.graphics.getCanvas()
  local prevFont = love.graphics.getFont()

  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.05, 0.10, 0.16, 1)

  if toolEntry.icon == "tile" then
    if toolEntry.name == "fire" then
      -- Static campfire art for the sidebar; gameplay uses the animated sheet.
      local fire = getPreviewSprites().fire
      local targetSize = ICON_SIZE * 0.92
      local scale = targetSize / math.max(fire:getWidth(), fire:getHeight())
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        fire,
        ICON_SIZE / 2,
        ICON_SIZE / 2,
        0,
        scale,
        scale,
        fire:getWidth() / 2,
        fire:getHeight() / 2
      )
    else
      local tileSize = 40
      local snap = Grid.new(tileSize, 1, 1, false)
      placeToolOnGrid(
        toolEntry.name,
        1,
        1,
        snap,
        wallFacing or "left",
        halfWallFill or 0.5,
        wallDepth or "front",
        keyVariant or "top",
        halfWallAlign or "down"
      )
      local prevMode = Perspective.mode
      Perspective.set("topdown")
      love.graphics.push()
      love.graphics.scale(ICON_SIZE / tileSize, ICON_SIZE / tileSize)
      snap:draw(1)
      love.graphics.pop()
      Perspective.set(prevMode)
    end
  else
    drawActionIcon(toolEntry.icon or toolEntry.name, ICON_SIZE)
  end

  love.graphics.setCanvas(prevCanvas)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
  if prevFont then
    love.graphics.setFont(prevFont)
  end

  return canvas
end

local function ensureToolIcon(toolEntry, wallFacing, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  local key = iconCacheKey(toolEntry.name, wallFacing, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  if not toolIconCache[key] then
    toolIconCache[key] = buildToolIcon(toolEntry, wallFacing, halfWallFill, wallDepth, keyVariant, halfWallAlign)
  end
  return toolIconCache[key]
end

local function sourceLevelsDir()
  if love.filesystem.isFused() then
    return nil
  end
  local source = love.filesystem.getSource()
  if not source or source == "" then
    return nil
  end
  return source .. "/" .. LEVELS_DIR
end

local function ensureLevelsDir()
  love.filesystem.createDirectory(LEVELS_DIR)
  local dir = sourceLevelsDir()
  if dir then
    os.execute(string.format('mkdir -p %q', dir))
  end
end

local function sanitizeLevelName(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("[^%w%-%_ ]", "")
  name = name:gsub("%s+", " ")
  if #name > NAME_MAX_LEN then
    name = name:sub(1, NAME_MAX_LEN)
  end
  return name
end

local function levelPath(name)
  return LEVELS_DIR .. "/" .. name .. ".txt"
end

local function levelTimePath(name)
  return LEVELS_DIR .. "/" .. name .. ".time"
end

local function listLevelNames()
  ensureLevelsDir()
  local seen = {}
  local names = {}

  local function addName(filename)
    local name = filename:match("^(.+)%.txt$")
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  for _, filename in ipairs(love.filesystem.getDirectoryItems(LEVELS_DIR)) do
    addName(filename)
  end

  local dir = sourceLevelsDir()
  if dir then
    local handle = io.popen(string.format('ls -1 %q 2>/dev/null', dir))
    if handle then
      for filename in handle:lines() do
        addName(filename)
      end
      handle:close()
    end
  end

  table.sort(names, function(a, b)
    local na = a:match("^level(%d+)$")
    local nb = b:match("^level(%d+)$")
    if na and nb then
      return tonumber(na) < tonumber(nb)
    end
    if na then
      return true
    end
    if nb then
      return false
    end
    return a:lower() < b:lower()
  end)

  return names
end

local function writeLevelFile(path, contents)
  ensureLevelsDir()

  local dir = sourceLevelsDir()
  if dir then
    local file, err = io.open(dir .. "/" .. path:match("[^/]+$"), "w")
    if not file then
      return false, err
    end
    file:write(contents)
    file:close()
    return true
  end

  return love.filesystem.write(path, contents)
end

local function readLevelFile(path)
  local contents, message = love.filesystem.read(path)
  if contents then
    return contents
  end

  local dir = sourceLevelsDir()
  if dir then
    local file, err = io.open(dir .. "/" .. path:match("[^/]+$"), "r")
    if file then
      local data = file:read("*a")
      file:close()
      return data
    end
    return nil, err or message
  end

  return nil, message
end

function Editor:getLevelTime()
  return self.levelTime or DEFAULT_LEVEL_TIME
end

function Editor:openTimeEditor()
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self.namingOpen = true
  self.timeEditing = true
  self.namingText = tostring(self:getLevelTime())
  self.namingCursorBlink = 0

  if love.keyboard.setTextInput then
    love.keyboard.setTextInput(true)
  end
end

function Editor:confirmTime()
  local value = tonumber(self.namingText)

  if not value or value < 0 or value > MAX_LEVEL_TIME or value ~= math.floor(value) then
    self:setStatus("Time must be 0–999 seconds")
    return
  end

  self.levelTime = value
  self:closeNaming()

  if self.currentLevelName then
    local success, message = writeLevelFile(
      levelTimePath(self.currentLevelName),
      tostring(self.levelTime)
    )
    if not success then
      self:setStatus("Time save failed: " .. tostring(message))
      return
    end
  end

  self:setStatus("Time limit: " .. self.levelTime .. "s")
end

local function buttonY(index)
  local groupGap = index > ACTION_TOOL_COUNT and ACTION_GROUP_GAP or 0
  return 18 + (index - 1) * BUTTON_GAP + groupGap
end

local function snowflakeStatus(seconds)
  return "Snowflake +"
    .. seconds
    .. "s · [ ] / Shift+Wheel change restore time"
end

local function nextDefaultName(existing)
  local used = {}

  for _, name in ipairs(existing) do
    used[name:lower()] = true
  end

  local n = 1
  while used["level" .. n] do
    n = n + 1
  end

  return "level" .. n
end

function Editor.listLevelNames()
  return listLevelNames()
end

function Editor.readLevelContents(name)
  return readLevelFile(levelPath(name))
end

function Editor.new(spawnCol, spawnRow)
  return setmetatable({
    active = false,
    tool = "ground",
    wallFacing = "left",
    wallDepth = "front",
    keyVariant = "top",
    halfWallFill = 0.5,
    halfWallAlign = "down",
    snowflakeSeconds = DEFAULT_SNOWFLAKE_SECONDS,
    spawnCol = spawnCol,
    spawnRow = spawnRow,
    status = "",
    statusTimer = 0,
    panSpeed = 260,
    currentLevelName = nil,
    loadDropdownOpen = false,
    loadDropdownScroll = 0,
    loadOptions = {},
    paintingButton = nil,
    paintedTiles = {},
    rectangle = nil,
    namingOpen = false,
    namingText = "",
    timeEditing = false,
    levelTime = DEFAULT_LEVEL_TIME,
    namingCursorBlink = 0,
  }, Editor)
end

function Editor:setStatus(text)
  self.status = text or ""
  self.statusTimer = (text and text ~= "") and 3 or 0
end

function Editor:setActive(active)
  self.active = active
  self:setStatus(active and "Editor enabled" or "")
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self.rectangle = nil
  self:closeNaming()
end

function Editor:closeNaming()
  self.namingOpen = false
  self.namingText = ""
  self.timeEditing = false
  self.namingCursorBlink = 0

  if love.keyboard.setTextInput then
    love.keyboard.setTextInput(false)
  end
end

function Editor:openNaming()
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self:refreshLoadOptions()
  self.namingOpen = true
  self.namingText = self.currentLevelName or nextDefaultName(self.loadOptions)
  self.namingCursorBlink = 0

  if love.keyboard.setTextInput then
    love.keyboard.setTextInput(true)
  end
end

function Editor:refreshLoadOptions()
  self.loadOptions = listLevelNames()
  self.loadDropdownScroll = math.max(
    0,
    math.min(self:maxDropdownScroll(), self.loadDropdownScroll)
  )
end

function Editor:maxDropdownScroll()
  return math.max(0, #self.loadOptions - DROPDOWN_MAX_VISIBLE)
end

function Editor:scrollDropdown(delta)
  self.loadDropdownScroll = math.max(
    0,
    math.min(
      self:maxDropdownScroll(),
      self.loadDropdownScroll + delta
    )
  )
end

function Editor:getDropdownRect()
  local slots = 1

  if #self.loadOptions > 0 then
    slots = math.min(DROPDOWN_MAX_VISIBLE, #self.loadOptions)
  end

  local x = HUD_X + HUD_W + 6
  local y = buttonY(2)
  local w = 168
  local h = 8 + slots * DROPDOWN_ITEM_H

  return x, y, w, h
end

function Editor:getNamingRect()
  local width, height = love.graphics.getDimensions()
  local w, h = 320, 126
  local x = math.floor((width - w) * 0.5)
  local y = math.floor((height - h) * 0.5)

  return x, y, w, h
end

function Editor:isOverDropdown(x, y)
  if not self.loadDropdownOpen then
    return false
  end

  local dx, dy, dw, dh = self:getDropdownRect()

  return x >= dx
    and x <= dx + dw
    and y >= dy
    and y <= dy + dh
end

function Editor:isOverNaming(x, y)
  if not self.namingOpen then
    return false
  end

  local nx, ny, nw, nh = self:getNamingRect()

  return x >= nx
    and x <= nx + nw
    and y >= ny
    and y <= ny + nh
end

function Editor:isOverHud(x, y)
  if self:isOverNaming(x, y) or self.namingOpen then
    return true
  end

  if self:isOverDropdown(x, y) then
    return true
  end
  local _, height = love.graphics.getDimensions()
  if y >= height - LEGEND_H then
    return true
  end
  return x >= HUD_X
    and x <= HUD_X + HUD_W
    and y >= HUD_Y
    and y <= HUD_Y + HUD_H
end

function Editor:getTileAt(x, y, grid, camera)
  local worldX, worldY = camera:screenToWorld(x, y)
  local col, row = Perspective.worldToTile(worldX, worldY, grid.size)

  if not grid:isInside(col, row) then
    return nil, nil
  end

  return col, row
end

function Editor:togglePerspective(grid, camera)
  local focusCol, focusRow
  if camera and grid then
    focusCol, focusRow = Perspective.worldToTile(camera.x, camera.y, grid.size)
  end

  local mode = Perspective.toggle()

  if camera and grid then
    if not focusCol or not grid:isInside(focusCol, focusRow) then
      focusCol, focusRow = self.spawnCol, self.spawnRow
    end
    camera.x, camera.y = grid:tileCenter(focusCol, focusRow)
  end

  self:setStatus("Preview: " .. Perspective.label() .. "  (V) · paint Side Zone for mixed levels")
  return mode
end

function Editor:protectSpawn(grid)
  grid:setGround(self.spawnCol, self.spawnRow)
  grid:removeFire(self.spawnCol, self.spawnRow)
  grid:removeIce(self.spawnCol, self.spawnRow)
  grid:removeSnowflake(self.spawnCol, self.spawnRow)
  grid:removeTea(self.spawnCol, self.spawnRow)
  grid:removePuzzlePiece(self.spawnCol, self.spawnRow)
  grid:removePuzzleCanvas(self.spawnCol, self.spawnRow)
  grid:removePuzzleDoor(self.spawnCol, self.spawnRow)
  grid:removeFinalDoor(self.spawnCol, self.spawnRow)
  grid:removePressurePlate(self.spawnCol, self.spawnRow)
  grid:removeWall(self.spawnCol, self.spawnRow)
  grid:removeBoulder(self.spawnCol, self.spawnRow)
  grid:addFridge(self.spawnCol, self.spawnRow)
end

function Editor:beginSave()
  self:openNaming()
end

function Editor:confirmSave(grid)
  local name = sanitizeLevelName(self.namingText)

  if name == "" then
    self:setStatus("Enter a level name")
    return
  end

  local path = levelPath(name)
  local data = grid:serialize()

  self:closeNaming()

  local success, message = writeLevelFile(path, data)

  if success then
    local timeSuccess, timeMessage = writeLevelFile(
      levelTimePath(name),
      tostring(self:getLevelTime())
    )
    if not timeSuccess then
      self:setStatus("Time save failed: " .. tostring(timeMessage))
      return
    end
    self.currentLevelName = name
    self:setStatus("Saved")
    self:refreshLoadOptions()
  else
    self:setStatus("Save failed: " .. tostring(message))
  end
end

function Editor:loadLevel(grid, name)
  local path = levelPath(name)
  local contents, message = readLevelFile(path)

  if not contents then
    self:setStatus(
      "Load failed: " ..
      tostring(message or ("missing " .. path))
    )
    return
  end

  grid:load(contents)
  self:protectSpawn(grid)
  local timeContents = readLevelFile(levelTimePath(name))
  local loadedTime = tonumber(timeContents)
  if loadedTime and loadedTime >= 0 and loadedTime <= MAX_LEVEL_TIME then
    self.levelTime = math.floor(loadedTime)
  else
    self.levelTime = DEFAULT_LEVEL_TIME
  end
  self.currentLevelName = name
  self.loadDropdownOpen = false
  self.paintingButton = nil
  self:setStatus("Loaded " .. name)
end

function Editor:toggleLoadDropdown()
  if self.namingOpen then
    return
  end

  self:refreshLoadOptions()

  if #self.loadOptions == 0 then
    self.loadDropdownOpen = false
    self:setStatus("No levels in " .. LEVELS_DIR)
    return
  end

  self.loadDropdownOpen = not self.loadDropdownOpen
end

function Editor:applyTool(tool, col, row, grid)
  if not col then
    return
  end

  -- Side zones may cover spawn; other tools still protect it.
  if col == self.spawnCol and row == self.spawnRow and tool ~= "perspective" then
    self:setStatus("The spawn tile is protected")
    return
  end

  placeToolOnGrid(tool, col, row, grid, self.wallFacing, self.halfWallFill, self.wallDepth, self.keyVariant, self.halfWallAlign, self.snowflakeSeconds)
end

function Editor:paintAt(x, y, button, grid, camera)
  if self:isOverHud(x, y) then
    return
  end

  local col, row = self:getTileAt(x, y, grid, camera)
  if not col then
    return
  end

  local strokeKey = button .. ":" .. col .. ":" .. row
  if self.paintedTiles[strokeKey] then
    return
  end
  self.paintedTiles[strokeKey] = true

  -- Right-click with Side Zone only clears the zone (keeps tiles).
  if button == 2 and self.tool == "perspective" then
    if not grid:isInside(col, row) then
      return
    end
    grid:removeSideView(col, row)
    return
  end

  self:applyTool(
    button == 2 and "erase" or self.tool,
    col,
    row,
    grid
  )
end

function Editor:hitDropdownItem(x, y)
  if not self:isOverDropdown(x, y) or #self.loadOptions == 0 then
    return nil
  end

  local dx, dy, dw = self:getDropdownRect()
  local listW = dw - (
    (#self.loadOptions > DROPDOWN_MAX_VISIBLE)
    and 14
    or 0
  )

  if x > dx + listW then
    return nil
  end

  local localY = y - (dy + 4)

  if localY < 0 then
    return nil
  end

  local row = math.floor(localY / DROPDOWN_ITEM_H) + 1
  local index = row + self.loadDropdownScroll

  if index < 1 or index > #self.loadOptions then
    return nil
  end

  return self.loadOptions[index]
end

function Editor:hitToolButton(x, y)
  if x < BUTTON_X or x > BUTTON_X + BUTTON_W then
    return nil
  end
  for i = 1, TOOL_BUTTON_COUNT do
    local y0 = buttonY(i)

    if y >= y0 and y <= y0 + BUTTON_H then
      return i
    end
  end

  return nil
end

function Editor:hitNamingButton(x, y)
  if not self.namingOpen then
    return nil
  end

  local nx, ny, nw = self:getNamingRect()
  local saveX, saveY = nx + 16, ny + 82
  local cancelX = nx + nw - 16 - 90

  if x >= saveX
    and x <= saveX + 90
    and y >= saveY
    and y <= saveY + 28 then
    return "save"
  end

  if x >= cancelX
    and x <= cancelX + 90
    and y >= saveY
    and y <= saveY + 28 then
    return "cancel"
  end

  return nil
end

function Editor:mousepressed(x, y, button, grid, camera)
  if button ~= 1 and button ~= 2 then
    return
  end

  self.paintingButton = nil
  self.paintedTiles = {}

  if self.namingOpen then
    if button == 1 then
      local action = self:hitNamingButton(x, y)

      if action == "save" then
        if self.timeEditing then
          self:confirmTime()
        else
          self:confirmSave(grid)
        end
      elseif action == "cancel" then
        self:closeNaming()
      end
    end

    return
  end

  if button == 1 then
    if self.loadDropdownOpen then
      local chosen = self:hitDropdownItem(x, y)

      if chosen then
        self:loadLevel(grid, chosen)
        return
      end
    end

    local toolButton = self:hitToolButton(x, y)

    if toolButton then
      local entry = TOOLS[toolButton]

      if entry.name == "save" then
        self.loadDropdownOpen = false
        self:beginSave()
      elseif entry.name == "load" then
        self:toggleLoadDropdown()
      elseif entry.name == "perspective" then
        self.loadDropdownOpen = false
        self.tool = "perspective"
        self:setStatus("Side Zone · paint regions for side view + jump (V = preview mode)")
      elseif entry.name == "time_limit" then
        self.loadDropdownOpen = false
        self:openTimeEditor()
      else
        self.loadDropdownOpen = false
        self.tool = entry.name
        if entry.name == "side_wall" then
          self:setStatus("Side wall · R flips Left/Right (now " .. self.wallFacing .. ")")
        elseif entry.name == "front_wall" or entry.name == "cracked_wall" then
          self:setStatus(
            entry.label
              .. " · R toggles In Front / Behind (now "
              .. (self.wallDepth == "behind" and "Behind" or "In Front")
              .. ")"
          )
        elseif entry.name == "half_wall" then
          self:setStatus(
            "Half wall "
              .. math.floor(self.halfWallFill * 100 + 0.5)
              .. "% · "
              .. (self.halfWallAlign == "up" and "Up" or "Down")
              .. " · R flips Up/Down · [ ] / Shift+Wheel resize"
          )
        elseif entry.name == "half_wall2" then
          self:setStatus(
            "Half wall 2 "
              .. math.floor(self.halfWallFill * 100 + 0.5)
              .. "% · "
              .. (self.wallFacing == "right" and "Right" or "Left")
              .. " · R flips Left/Right · [ ] / Shift+Wheel resize"
          )
        elseif entry.name == "puzzle_piece" then
          self:setStatus(
            "Key half · "
              .. (self.keyVariant == "down" and "Bottom" or "Top")
              .. " section · R toggles Top/Bottom · assemble both for full key"
          )
        elseif entry.name == "puzzle_door" then
          self:setStatus("Key door · walk into it while holding a full key")
        elseif entry.name == "final_door" then
          self:setStatus("Final door · walk into it to finish the level")
        elseif entry.name == "snowflake" then
          self:setStatus(snowflakeStatus(self.snowflakeSeconds))
        end
      end

      return
    end

    if self.loadDropdownOpen then
      self.loadDropdownOpen = false

      if self:isOverHud(x, y) then
        return
      end
    end
  end

  if self:isOverHud(x, y) then
    return
  end

  if button == 1 and love.keyboard.isDown("lshift", "rshift") then
    local col, row = self:getTileAt(x, y, grid, camera)
    if col then
      self.rectangle = {
        startCol = col,
        startRow = row,
        endCol = col,
        endRow = row,
        tool = self.tool,
      }
    end
    return
  end

  self.paintingButton = button
  self:paintAt(x, y, button, grid, camera)
end

function Editor:mousereleased(x, y, button, grid, camera)
  if button == 1 and self.rectangle then
    local col, row = self:getTileAt(x, y, grid, camera)
    if col then
      self.rectangle.endCol = col
      self.rectangle.endRow = row
    end

    local rectangle = self.rectangle
    local minCol = math.min(rectangle.startCol, rectangle.endCol)
    local maxCol = math.max(rectangle.startCol, rectangle.endCol)
    local minRow = math.min(rectangle.startRow, rectangle.endRow)
    local maxRow = math.max(rectangle.startRow, rectangle.endRow)
    self.rectangle = nil

    for tileRow = minRow, maxRow do
      for tileCol = minCol, maxCol do
        self:applyTool(rectangle.tool, tileCol, tileRow, grid)
      end
    end
  end

  if self.paintingButton == button then
    self.paintingButton = nil
  end
  self.paintedTiles = {}
end

function Editor:textinput(text)
  if not self.namingOpen then
    return
  end

  text = text:gsub("[\r\n\t]", "")

  if self.timeEditing then
    text = text:gsub("%D", "")
    if text == "" then
      return
    end
    local nextText = (self.namingText .. text):gsub("%D", "")
    nextText = nextText:sub(-3)
    self.namingText = nextText
    return
  end

  if text == "" then
    return
  end

  local nextText = sanitizeLevelName(self.namingText .. text)
  self.namingText = nextText
end

function Editor:keypressed(key, grid, camera)
  if self.namingOpen then
    if (key == "s" and controlIsDown())
      or key == "return"
      or key == "kpenter" then
      if self.timeEditing then
        self:confirmTime()
      else
        self:confirmSave(grid)
      end

    elseif key == "escape" then
      self:closeNaming()

    elseif key == "backspace" then
      local text = self.namingText

      if #text > 0 then
        self.namingText = text:sub(1, #text - 1)
      end
    end

    return
  end

  if self.loadDropdownOpen then
    if key == "up" then
      self:scrollDropdown(-1)
      return

    elseif key == "down" then
      self:scrollDropdown(1)
      return

    elseif key == "escape" then
      self.loadDropdownOpen = false
      return
    end
  end

  if key == "1" then
    self.tool = "ground"
    self.loadDropdownOpen = false

  elseif key == "2" then
    self.tool = "fire"
    self.loadDropdownOpen = false

  elseif key == "3" then
    self.tool = "ice"
    self.loadDropdownOpen = false
  elseif key == "4" then
    self.tool = "snowflake"
    self.loadDropdownOpen = false
    self:setStatus(snowflakeStatus(self.snowflakeSeconds))
  elseif key == "5" then
    self.tool = "tea"
    self.loadDropdownOpen = false
  elseif key == "o" then
    self.tool = "moss"
    self.loadDropdownOpen = false
    self:setStatus("Moss block · green top-down, mossy side face")
  elseif key == "k" then
    self.tool = "pressure_plate"
    self.loadDropdownOpen = false
    self:setStatus("Pressure plate · standing on it opens doors")
  elseif key == "j" then
    self.tool = "puzzle_piece"
    self.loadDropdownOpen = false
    self:setStatus(
      "Key half · "
        .. (self.keyVariant == "down" and "Bottom" or "Top")
        .. " section · R toggles Top/Bottom · pick one up, touch the other to assemble"
    )
  elseif key == "u" then
    self.tool = "pressure_door"
    self.loadDropdownOpen = false
    self:setStatus("Pressure door · opens only from the pressure plate")
  elseif key == "=" then
    self.tool = "puzzle_door"
    self.loadDropdownOpen = false
    self:setStatus("Key door · walk into it while holding a full key")
  elseif key == "f" then
    self.tool = "final_door"
    self.loadDropdownOpen = false
    self:setStatus("Final door · walk into it to finish the level")
  elseif key == "t" then
    self.loadDropdownOpen = false
    self:openTimeEditor()
  elseif key == "6" then
    self.tool = "side_wall"
    self.loadDropdownOpen = false
    self:setStatus("Side wall · R flips Left/Right (now " .. self.wallFacing .. ")")
  elseif key == "7" then
    self.tool = "front_wall"
    self.loadDropdownOpen = false
    self:setStatus(
      "Front wall · R toggles In Front / Behind (now "
        .. (self.wallDepth == "behind" and "Behind" or "In Front")
        .. ")"
    )
  elseif key == "h" then
    self.tool = "half_wall"
    self.loadDropdownOpen = false
    self:setStatus(
      "Half wall "
        .. math.floor(self.halfWallFill * 100 + 0.5)
        .. "% · "
        .. (self.halfWallAlign == "up" and "Up" or "Down")
        .. " · R flips Up/Down · [ ] resize"
    )
  elseif key == "8" then
    self.tool = "cracked_wall"
    self.loadDropdownOpen = false
    self:setStatus(
      "Cracked wall · R toggles In Front / Behind (now "
        .. (self.wallDepth == "behind" and "Behind" or "In Front")
        .. ")"
    )
  elseif key == "9" then
    self.tool = "boulder"
    self.loadDropdownOpen = false
  elseif key == "b" then
    self.tool = "boulder2"
    self.loadDropdownOpen = false
  elseif key == "-" then
    self.tool = "cracked_boulder"
    self.loadDropdownOpen = false
  elseif key == "0" then
    self.tool = "erase"
    self.loadDropdownOpen = false

  elseif key == "[" or key == "]" then
    if self.tool == "snowflake" then
      local delta = key == "]" and 1 or -1
      self.snowflakeSeconds = math.max(
        MIN_SNOWFLAKE_SECONDS,
        math.min(MAX_SNOWFLAKE_SECONDS, self.snowflakeSeconds + delta)
      )
      self.loadDropdownOpen = false
      self:setStatus(snowflakeStatus(self.snowflakeSeconds))
    else
      local delta = key == "]" and 0.1 or -0.1
      self.halfWallFill = math.max(0.1, math.min(0.9, self.halfWallFill + delta))
      self.halfWallFill = math.floor(self.halfWallFill * 10 + 0.5) / 10
      clearToolIcon("half_wall")
      clearToolIcon("half_wall2")
      self.tool = self.tool == "half_wall2" and "half_wall2" or "half_wall"
      self.loadDropdownOpen = false
      self:setStatus(
        (self.tool == "half_wall2" and "Half wall 2 fill: " or "Half wall fill: ")
          .. math.floor(self.halfWallFill * 100 + 0.5)
          .. "% — cube must be "
          .. math.floor((1 - self.halfWallFill) * 100 + 0.5)
          .. "% size or smaller"
      )
    end

  elseif key == "r" then
    self.loadDropdownOpen = false
    if self.tool == "side_wall" then
      self.wallFacing = self.wallFacing == "left" and "right" or "left"
      clearToolIcon("side_wall")
      clearToolIcon("half_wall2")
      self:setStatus("Side wall facing: " .. self.wallFacing)
    elseif self.tool == "puzzle_piece" then
      self.keyVariant = self.keyVariant == "down" and "top" or "down"
      clearToolIcon("puzzle_piece")
      self:setStatus("Key half: " .. (self.keyVariant == "down" and "Bottom section" or "Top section"))
    elseif self.tool == "half_wall2" then
      self.wallFacing = self.wallFacing == "left" and "right" or "left"
      clearToolIcon("half_wall2")
      clearToolIcon("side_wall")
      self:setStatus("Half wall 2 facing: " .. self.wallFacing)
    elseif self.tool == "half_wall" then
      self.halfWallAlign = self.halfWallAlign == "up" and "down" or "up"
      clearToolIcon("half_wall")
      self:setStatus(
        "Half wall flipped: "
          .. (self.halfWallAlign == "up" and "Up (top of tile)" or "Down (bottom of tile)")
      )
    elseif isFrontWallTool(self.tool) then
      self.wallDepth = self.wallDepth == "behind" and "front" or "behind"
      clearToolIcon("front_wall")
      clearToolIcon("cracked_wall")
      self:setStatus(
        self.wallDepth == "behind"
          and "Front walls: BEHIND ground — place a Side Wall on top to stack"
          or "Front walls: IN FRONT of ground"
      )
    else
      self:setStatus("R: Side/Half2 = Left/Right · Half Wall = Up/Down · Key Half = Top/Bottom · Front/Cracked = In Front/Behind")
    end

  elseif key == "v" then
    self.loadDropdownOpen = false
    self:togglePerspective(grid, camera)

  elseif key == "c" or key == "n" then
    grid:clear()
    self.loadDropdownOpen = false
    self.currentLevelName = nil
    self.levelTime = DEFAULT_LEVEL_TIME
    self:setStatus("New blank level")

  elseif key == "s" and controlIsDown() then
    self:beginSave()

  elseif key == "l" then
    self:toggleLoadDropdown()

  elseif key == "escape" and self.loadDropdownOpen then
    self.loadDropdownOpen = false
  end
end

function Editor:clampCamera(grid, camera)
  local width, height = love.graphics.getDimensions()
  local worldWidth, worldHeight = grid:worldBounds()
  local halfWidth = math.min(
    worldWidth / 2,
    width / camera.zoom / 2
  )
  local halfHeight = math.min(
    worldHeight / 2,
    height / camera.zoom / 2
  )

  camera.x = math.max(
    halfWidth,
    math.min(worldWidth - halfWidth, camera.x)
  )

  camera.y = math.max(
    halfHeight,
    math.min(worldHeight - halfHeight, camera.y)
  )
end

function Editor:update(dt, grid, camera)
  if self.statusTimer > 0 then
    self.statusTimer = self.statusTimer - dt

    if self.statusTimer <= 0 then
      self.status = ""
      self.statusTimer = 0
    end
  end

  if self.namingOpen then
    self.namingCursorBlink = self.namingCursorBlink + dt
    self.paintingButton = nil
    return
  end

  local dx, dy = 0, 0

  if love.keyboard.isDown("left", "a") then
    dx = dx - 1
  end

  if love.keyboard.isDown("right", "d") then
    dx = dx + 1
  end

  if love.keyboard.isDown("up", "w") then
    dy = dy - 1
  end

  if love.keyboard.isDown("down", "s") then
    dy = dy + 1
  end

  camera.x = camera.x + dx * self.panSpeed * dt / camera.zoom
  camera.y = camera.y + dy * self.panSpeed * dt / camera.zoom

  self:clampCamera(grid, camera)

  if self.rectangle and love.mouse.isDown(1) then
    local x, y = love.mouse.getPosition()
    local col, row = self:getTileAt(x, y, grid, camera)
    if col then
      self.rectangle.endCol = col
      self.rectangle.endRow = row
    end
  elseif self.paintingButton and love.mouse.isDown(self.paintingButton) then
    local x, y = love.mouse.getPosition()
    self:paintAt(
      x,
      y,
      self.paintingButton,
      grid,
      camera
    )
  else
    self.paintingButton = nil
    self.paintedTiles = {}
  end
end

function Editor:wheelmoved(y, grid, camera)
  if self.namingOpen then
    return
  end

  if self.loadDropdownOpen then
    self:scrollDropdown(-y)
    return
  end

  if self.tool == "snowflake" and love.keyboard.isDown("lshift", "rshift") then
    local delta = y > 0 and 1 or -1
    self.snowflakeSeconds = math.max(
      MIN_SNOWFLAKE_SECONDS,
      math.min(MAX_SNOWFLAKE_SECONDS, self.snowflakeSeconds + delta)
    )
    self:setStatus(snowflakeStatus(self.snowflakeSeconds))
    return
  end

  if (self.tool == "half_wall" or self.tool == "half_wall2") and love.keyboard.isDown("lshift", "rshift") then
    local delta = y > 0 and 0.1 or -0.1
    self.halfWallFill = math.max(0.1, math.min(0.9, self.halfWallFill + delta))
    self.halfWallFill = math.floor(self.halfWallFill * 10 + 0.5) / 10
    clearToolIcon("half_wall")
    clearToolIcon("half_wall2")
    self:setStatus(
      (self.tool == "half_wall2" and "Half wall 2 fill: " or "Half wall fill: ")
        .. math.floor(self.halfWallFill * 100 + 0.5)
        .. "% — cube must be "
        .. math.floor((1 - self.halfWallFill) * 100 + 0.5)
        .. "% size or smaller"
    )
    return
  end

  camera.zoom = math.max(
    1,
    math.min(3, camera.zoom + y * 0.25)
  )

  self:clampCamera(grid, camera)
end

function Editor:draw(grid, camera)
  local mouseX, mouseY = love.mouse.getPosition()
  local col, row = self:getTileAt(
    mouseX,
    mouseY,
    grid,
    camera
  )

  -- Side-view zone overlay (always visible in editor).
  love.graphics.setLineWidth(1)
  for _, tile in pairs(grid.sideViewTiles) do
    local ox, oy = grid:tileOrigin(tile.col, tile.row)
    local x1, y1 = camera:worldToScreen(ox, oy)
    local x2, y2 = camera:worldToScreen(ox + grid.size, oy + Perspective.rowPitch(grid.size))
    love.graphics.setColor(0.30, 0.70, 1.0, 0.18)
    love.graphics.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(0.55, 0.85, 1.0, 0.55)
    love.graphics.rectangle("line", x1 + 1, y1 + 1, x2 - x1 - 2, y2 - y1 - 2)
  end

  -- Snowflake restore-time labels so non-default pickups are obvious.
  local labelFont = getHudFont()
  local previousLabelFont = love.graphics.getFont()
  love.graphics.setFont(labelFont)
  for _, flake in pairs(grid.snowflakeTiles) do
    local seconds = flake.seconds or DEFAULT_SNOWFLAKE_SECONDS
    local worldX, worldY = grid:tileCenter(flake.col, flake.row)
    local sx, sy = camera:worldToScreen(worldX, worldY)
    local label = "+" .. seconds .. "s"
    local labelW = labelFont:getWidth(label)
    love.graphics.setColor(0.05, 0.12, 0.22, 0.72)
    love.graphics.rectangle(
      "fill",
      sx - labelW / 2 - 3,
      sy + 6,
      labelW + 6,
      labelFont:getHeight() + 2,
      3,
      3
    )
    love.graphics.setColor(0.75, 0.92, 1, 0.95)
    love.graphics.print(label, sx - labelW / 2, sy + 7)
  end
  love.graphics.setFont(previousLabelFont)

  if self.rectangle then
    local rectangle = self.rectangle
    local minCol = math.min(rectangle.startCol, rectangle.endCol)
    local maxCol = math.max(rectangle.startCol, rectangle.endCol)
    local minRow = math.min(rectangle.startRow, rectangle.endRow)
    local maxRow = math.max(rectangle.startRow, rectangle.endRow)
    local left, top = Perspective.tileOrigin(minCol, minRow, grid.size)
    local pitch = Perspective.rowPitch(grid.size)
    local right = maxCol * grid.size
    local bottom = maxRow * pitch
    local x1, y1 = camera:worldToScreen(left, top)
    local x2, y2 = camera:worldToScreen(right, bottom)

    love.graphics.setColor(0.35, 0.78, 1, 0.22)
    love.graphics.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(0.65, 0.92, 1, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x1, y1, x2 - x1, y2 - y1)
  end

  if col and not self.rectangle and not self:isOverHud(mouseX, mouseY) then
    local worldX, worldY = grid:tileCenter(col, row)
    local x, y = camera:worldToScreen(worldX, worldY)
    local sizeW = grid.size * camera.zoom
    local sizeH = Perspective.rowPitch(grid.size) * camera.zoom
    local ghostSize = Perspective.isSide() and math.max(sizeW, sizeH * 1.6) or sizeW

    drawToolGhost(
      self.tool,
      self.wallFacing,
      x,
      y,
      ghostSize,
      camera.zoom,
      self.halfWallFill,
      self.wallDepth,
      self.keyVariant,
      self.halfWallAlign
    )

    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
      "line",
      x - sizeW / 2,
      y - sizeH / 2,
      sizeW,
      sizeH
    )
  end

  local spawnX, spawnY = grid:tileCenter(
    self.spawnCol,
    self.spawnRow
  )

  spawnX, spawnY = camera:worldToScreen(
    spawnX,
    spawnY
  )

  local spawnW = grid.size * camera.zoom
  local spawnH = Perspective.rowPitch(grid.size) * camera.zoom

  love.graphics.setColor(0.35, 1, 0.55, 0.9)
  love.graphics.setLineWidth(3)

  love.graphics.rectangle(
    "line",
    spawnX - spawnW / 2 + 3,
    spawnY - spawnH / 2 + 3,
    spawnW - 6,
    spawnH - 6
  )

  love.graphics.setColor(0.025, 0.05, 0.09, 0.94)
  love.graphics.rectangle("fill", HUD_X, HUD_Y, HUD_W, HUD_H, 6, 6)

  local previousFont = love.graphics.getFont()
  local font = getHudFont()

  love.graphics.setFont(font)

  local textY = math.floor(
    (BUTTON_H - font:getHeight()) * 0.5
  )

  for index, tool in ipairs(TOOLS) do
    local y = buttonY(index)
    local selected = self.tool == tool.name
      or (tool.name == "load" and self.loadDropdownOpen)

    if selected then
      if tool.name == "snowflake" then
        love.graphics.setColor(0.20, 0.55, 0.90, 0.9)
      elseif tool.name == "puzzle_piece" then
        love.graphics.setColor(0.72, 0.58, 0.22, 0.95)
      elseif tool.name == "pressure_plate" then
        love.graphics.setColor(0.20, 0.52, 0.58, 0.95)
       elseif tool.name == "pressure_door" then
         love.graphics.setColor(0.16, 0.48, 0.34, 0.95)
      elseif tool.name == "time_limit" then
        love.graphics.setColor(0.16, 0.48, 0.76, 0.95)
      elseif tool.name == "puzzle_door" then
         love.graphics.setColor(0.28, 0.30, 0.58, 0.95)
      elseif tool.name == "final_door" then
         love.graphics.setColor(0.42, 0.34, 0.62, 0.95)
      elseif tool.name == "side_wall" then
        love.graphics.setColor(0.32, 0.48, 0.62, 0.9)
      elseif tool.name == "front_wall" then
        love.graphics.setColor(0.55, 0.38, 0.28, 0.9)
      elseif tool.name == "half_wall" then
        love.graphics.setColor(0.45, 0.55, 0.62, 0.95)
      elseif tool.name == "half_wall2" then
        love.graphics.setColor(0.38, 0.50, 0.58, 0.95)
      elseif tool.name == "cracked_wall" then
        love.graphics.setColor(0.42, 0.28, 0.20, 0.95)
      elseif tool.name == "boulder" then
        love.graphics.setColor(0.45, 0.43, 0.40, 0.95)
      elseif tool.name == "boulder2" then
        love.graphics.setColor(0.52, 0.51, 0.58, 0.95)
      elseif tool.name == "cracked_boulder" then
        love.graphics.setColor(0.34, 0.32, 0.30, 0.95)
      elseif tool.name == "perspective" then
        love.graphics.setColor(0.42, 0.62, 0.82, 0.95)
      else
        love.graphics.setColor(0.18, 0.58, 0.86, 0.8)
      end
    else
      love.graphics.setColor(0.10, 0.20, 0.31, 0.9)
    end

    love.graphics.rectangle(
      "fill",
      BUTTON_X,
      y,
      BUTTON_W,
      BUTTON_H,
      4,
      4
    )

    local icon = ensureToolIcon(tool, self.wallFacing, self.halfWallFill, self.wallDepth, self.keyVariant, self.halfWallAlign)
    local iconX = BUTTON_X + ICON_PAD
    local iconY = y + math.floor((BUTTON_H - ICON_SIZE) * 0.5)

    love.graphics.setColor(0.04, 0.08, 0.12, 0.85)
    love.graphics.rectangle(
      "fill",
      iconX - 1,
      iconY - 1,
      ICON_SIZE + 2,
      ICON_SIZE + 2,
      3,
      3
    )
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(icon, iconX, iconY)

    local label = tool.label
    if tool.name == "perspective" then
      label = "Side Zone"
    elseif tool.name == "side_wall" then
      label = "Side (" .. (self.wallFacing == "right" and "Right" or "Left") .. ")"
    elseif tool.name == "puzzle_piece" then
      label = "Key Half · " .. (self.keyVariant == "down" and "Bottom" or "Top")
    elseif tool.name == "snowflake" then
      label = "Snowflake +" .. self.snowflakeSeconds .. "s"
    elseif tool.name == "half_wall" then
      label = "Half Wall · " .. (self.halfWallAlign == "up" and "Up" or "Down")
    elseif tool.name == "half_wall2" then
      label = "Half Wall 2 · " .. (self.wallFacing == "right" and "Right" or "Left")
    elseif isFrontWallTool(tool.name) then
      label = tool.label .. (self.wallDepth == "behind" and " · Behind" or " · Front")
    end
    love.graphics.setColor(0.92, 0.97, 1)
    love.graphics.print(
      label,
      iconX + ICON_SIZE + 8,
      y + textY
    )
  end

  if self.loadDropdownOpen then
    local dx, dy, dw, dh = self:getDropdownRect()

    local listW = dw - (
      (#self.loadOptions > DROPDOWN_MAX_VISIBLE)
      and 14
      or 0
    )

    love.graphics.setColor(
      0.025,
      0.05,
      0.09,
      0.98
    )

    love.graphics.rectangle(
      "fill",
      dx,
      dy,
      dw,
      dh,
      6,
      6
    )

    love.graphics.setColor(
      0.18,
      0.58,
      0.86,
      0.7
    )

    love.graphics.setLineWidth(1)

    love.graphics.rectangle(
      "line",
      dx,
      dy,
      dw,
      dh,
      6,
      6
    )

    local itemTextY = math.floor(
      (DROPDOWN_ITEM_H - 2 - font:getHeight()) * 0.5
    )

    local visible = math.min(
      DROPDOWN_MAX_VISIBLE,
      #self.loadOptions
    )

    for i = 1, visible do
      local optionIndex = i + self.loadDropdownScroll
      local levelName = self.loadOptions[optionIndex]
      local itemY = dy + 4 + (i - 1) * DROPDOWN_ITEM_H

      local hovered =
        mouseX >= dx
        and mouseX <= dx + listW
        and mouseY >= itemY
        and mouseY < itemY + DROPDOWN_ITEM_H

      if levelName == self.currentLevelName then
        love.graphics.setColor(
          0.18,
          0.58,
          0.86,
          0.9
        )
      elseif hovered then
        love.graphics.setColor(
          0.14,
          0.36,
          0.55,
          0.95
        )
      else
        love.graphics.setColor(
          0.10,
          0.20,
          0.31,
          0.95
        )
      end

      love.graphics.rectangle(
        "fill",
        dx + 4,
        itemY,
        listW - 8,
        DROPDOWN_ITEM_H - 2,
        3,
        3
      )

      love.graphics.setColor(0.92, 0.97, 1)

      love.graphics.print(
        levelName,
        dx + 12,
        itemY + itemTextY
      )
    end

    local maxScroll = self:maxDropdownScroll()

    if maxScroll > 0 then
      local trackX = dx + dw - 10
      local trackY = dy + 6
      local trackH = dh - 12

      love.graphics.setColor(
        0.08,
        0.14,
        0.2,
        1
      )

      love.graphics.rectangle(
        "fill",
        trackX,
        trackY,
        5,
        trackH,
        2,
        2
      )

      local thumbH = math.max(
        16,
        trackH * (
          DROPDOWN_MAX_VISIBLE /
          #self.loadOptions
        )
      )

      local thumbY = trackY

      if maxScroll > 0 then
        thumbY = trackY
          + (trackH - thumbH)
          * (self.loadDropdownScroll / maxScroll)
      end

      love.graphics.setColor(
        0.35,
        0.7,
        0.95,
        0.95
      )

      love.graphics.rectangle(
        "fill",
        trackX,
        thumbY,
        5,
        thumbH,
        2,
        2
      )
    end
  end

  if self.status ~= "" and not self.namingOpen then
    local statusY = HUD_Y + HUD_H + 8
    love.graphics.setColor(0.025, 0.05, 0.09, 0.9)
    love.graphics.rectangle("fill", 10, statusY, 280, 24, 4, 4)
    love.graphics.setColor(0.85, 0.93, 1)
    love.graphics.print(self.status, 18, statusY + textY)
  end

  local screenWidth, screenHeight = love.graphics.getDimensions()
  local legendY = screenHeight - LEGEND_H
  love.graphics.setColor(0.025, 0.05, 0.09, 0.96)
  love.graphics.rectangle("fill", 0, legendY, screenWidth, LEGEND_H)
  love.graphics.setColor(0.18, 0.58, 0.86, 0.75)
  love.graphics.setLineWidth(1)
  love.graphics.line(0, legendY, screenWidth, legendY)
  love.graphics.setColor(0.85, 0.93, 1)
  love.graphics.printf(
    "1 Ground  ·  2 Fire  ·  3 Ice  ·  4 Snowflake  ·  5 Tea  ·  K Plate  ·  J Key Half  ·  U Pressure Door  ·  = Key Door  ·  F Final Door  ·  6 Side  ·  7 Front  ·  H Half  ·  8 Cracked  ·  9 Boulder  ·  B Boulder 2  ·  - Cracked Boulder  ·  0 Erase",
    12,
    legendY + 7,
    screenWidth - 24,
    "center"
  )
  love.graphics.setColor(0.58, 0.75, 0.9)
  love.graphics.printf(
    "Left-drag Paint  ·  Shift+drag Rect  ·  Right-drag Erase  ·  R = Side L/R · Key Top/Bottom · Front Behind/In-Front  ·  [ ] Half / Snowflake time",
    12,
    legendY + 27,
    screenWidth - 24,
    "center"
  )
  love.graphics.printf(
    "Ctrl+S Save  ·  L Load  ·  N/C New  ·  Behind front walls can take a Side Wall on top",
    12,
    legendY + 47,
    screenWidth - 24,
    "center"
  )
  love.graphics.printf(
    "WASD/Arrows Pan  ·  Wheel Zoom  ·  V Perspective  ·  E Play/Edit  ·  Esc Menu  ·  U Pressure Door  ·  = Key Door  ·  F Final Door",
    12,
    legendY + 67,
    screenWidth - 24,
    "center"
  )
  local rHint
  if self.tool == "side_wall" then
    rHint = "R → Side facing: " .. self.wallFacing
  elseif self.tool == "puzzle_piece" then
    rHint = "R → Key half: " .. (self.keyVariant == "down" and "Bottom section" or "Top section")
  elseif self.tool == "half_wall" then
    rHint = "R → Half wall: " .. (self.halfWallAlign == "up" and "Up (top)" or "Down (bottom)")
  elseif self.tool == "half_wall2" then
    rHint = "R → Half wall 2 facing: " .. self.wallFacing
  elseif isFrontWallTool(self.tool) then
    rHint = "R → Wall depth: " .. (self.wallDepth == "behind" and "Behind ground" or "In front of ground")
  else
    rHint = "R → Side/Half2 = Left/Right · Half Wall = Up/Down · Key Half = Top/Bottom · Front/Cracked = In Front/Behind"
  end
  love.graphics.printf(
    rHint,
    12,
    legendY + 87,
    screenWidth - 24,
    "center"
  )

  if self.namingOpen then
    local nx, ny, nw, nh = self:getNamingRect()

    love.graphics.setColor(
      0,
      0,
      0,
      0.45
    )

    love.graphics.rectangle(
      "fill",
      0,
      0,
      love.graphics.getDimensions()
    )

    love.graphics.setColor(
      0.025,
      0.05,
      0.09,
      0.98
    )

    love.graphics.rectangle(
      "fill",
      nx,
      ny,
      nw,
      nh,
      8,
      8
    )

    love.graphics.setColor(
      0.18,
      0.58,
      0.86,
      0.8
    )

    love.graphics.setLineWidth(2)

    love.graphics.rectangle(
      "line",
      nx,
      ny,
      nw,
      nh,
      8,
      8
    )

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      self.timeEditing and "Set time limit" or "Name this level",
      nx + 16,
      ny + 14
    )

    local fieldX, fieldY, fieldW, fieldH =
      nx + 16,
      ny + 42,
      nw - 32,
      28

    love.graphics.setColor(
      0.08,
      0.16,
      0.24,
      1
    )

    love.graphics.rectangle(
      "fill",
      fieldX,
      fieldY,
      fieldW,
      fieldH,
      4,
      4
    )

    love.graphics.setColor(
      0.25,
      0.55,
      0.8,
      0.9
    )

    love.graphics.rectangle(
      "line",
      fieldX,
      fieldY,
      fieldW,
      fieldH,
      4,
      4
    )

    local display = self.namingText
    if self.timeEditing then
      display = display .. "s"
    end

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      display,
      fieldX + 8,
      fieldY + math.floor(
        (fieldH - font:getHeight()) * 0.5
      )
    )

    if math.floor(self.namingCursorBlink * 2) % 2 == 0 then
      local cursorX =
        fieldX + 8 + font:getWidth(display)

      love.graphics.rectangle(
        "fill",
        cursorX,
        fieldY + 6,
        2,
        fieldH - 12
      )
    end

    local saveX, saveY = nx + 16, ny + 82
    local cancelX = nx + nw - 16 - 90

    local saveHovered =
      mouseX >= saveX
      and mouseX <= saveX + 90
      and mouseY >= saveY
      and mouseY <= saveY + 28

    local cancelHovered =
      mouseX >= cancelX
      and mouseX <= cancelX + 90
      and mouseY >= saveY
      and mouseY <= saveY + 28

    love.graphics.setColor(
      saveHovered and 0.22 or 0.18,
      saveHovered and 0.66 or 0.58,
      saveHovered and 0.92 or 0.86,
      0.95
    )

    love.graphics.rectangle(
      "fill",
      saveX,
      saveY,
      90,
      28,
      4,
      4
    )

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      self.timeEditing and "Set" or "Save",
      saveX + (self.timeEditing and 32 or 28),
      saveY + 6
    )

    love.graphics.setColor(
      cancelHovered and 0.28 or 0.16,
      cancelHovered and 0.28 or 0.22,
      cancelHovered and 0.34 or 0.30,
      0.95
    )

    love.graphics.rectangle(
      "fill",
      cancelX,
      saveY,
      90,
      28,
      4,
      4
    )

    love.graphics.setColor(
      0.92,
      0.97,
      1
    )

    love.graphics.print(
      "Cancel",
      cancelX + 20,
      saveY + 6
    )
  end

  love.graphics.setFont(previousFont)
end

return Editor
