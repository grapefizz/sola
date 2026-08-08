-- Shared top-down vs side presentation. Gameplay stays on the col/row grid;
-- this only remaps how tiles and sprites are drawn.

local Perspective = {}

Perspective.mode = "topdown" -- "topdown" | "side"

-- Side view uses the SAME tile grid as top-down (pitch = tileSize).
-- Walls rise inside the cell from the floor strip upward.
Perspective.WALL_HEIGHT = 0.85
Perspective.FLOOR_FACE = 0.34 -- brick platform face
Perspective.FLOOR_THICK = 0.14 -- front lip under the platform

function Perspective.isSide()
  return Perspective.mode == "side"
end

function Perspective.isTopdown()
  return Perspective.mode == "topdown"
end

function Perspective.set(mode)
  if mode == "side" or mode == "topdown" then
    Perspective.mode = mode
  end
  return Perspective.mode
end

function Perspective.toggle()
  Perspective.mode = Perspective.mode == "side" and "topdown" or "side"
  return Perspective.mode
end

function Perspective.label()
  return Perspective.mode == "side" and "Side View" or "Top-Down"
end

function Perspective.shortLabel()
  return Perspective.mode == "side" and "Side" or "Top"
end

-- Same grid in both modes so camera / picking stay aligned.
function Perspective.rowPitch(tileSize)
  return tileSize
end

function Perspective.tileOrigin(col, row, tileSize)
  return (col - 1) * tileSize, (row - 1) * tileSize
end

function Perspective.tileCenter(col, row, tileSize)
  local x, y = Perspective.tileOrigin(col, row, tileSize)
  if Perspective.mode == "side" then
    -- Feet / prop base sit on the floor top.
    return x + tileSize * 0.5, Perspective.floorY(col, row, tileSize)
  end
  return x + tileSize * 0.5, y + tileSize * 0.5
end

function Perspective.floorY(col, row, tileSize)
  local _, y = Perspective.tileOrigin(col, row, tileSize)
  if Perspective.mode == "side" then
    return y + tileSize - tileSize * Perspective.FLOOR_FACE
  end
  return y + tileSize
end

function Perspective.worldBounds(columns, rows, tileSize)
  return columns * tileSize, rows * tileSize
end

function Perspective.worldToTile(worldX, worldY, tileSize)
  local col = math.floor(worldX / tileSize) + 1
  local row = math.floor(worldY / tileSize) + 1
  return col, row
end

function Perspective.floorMetrics(tileSize)
  local faceH = math.max(4, tileSize * Perspective.FLOOR_FACE)
  local thick = math.max(2, tileSize * Perspective.FLOOR_THICK)
  return tileSize, thick, faceH
end

function Perspective.wallHeight(tileSize, fill)
  fill = fill or 1
  return tileSize * Perspective.WALL_HEIGHT * fill
end

function Perspective.visibleTileRange(camera, tileSize, columns, rows)
  local minCol, maxCol = 1, columns
  local minRow, maxRow = 1, rows
  if not camera then
    return minCol, maxCol, minRow, maxRow
  end

  local screenWidth, screenHeight = love.graphics.getDimensions()
  local halfWidth = screenWidth / (camera.zoom * 2)
  local halfHeight = screenHeight / (camera.zoom * 2)

  minCol = math.max(1, math.floor((camera.x - halfWidth) / tileSize) + 1)
  maxCol = math.min(columns, math.floor((camera.x + halfWidth) / tileSize) + 1)
  minRow = math.max(1, math.floor((camera.y - halfHeight) / tileSize) + 1)
  maxRow = math.min(rows, math.floor((camera.y + halfHeight) / tileSize) + 1)

  if Perspective.mode == "side" then
    -- Walls rise into the cell above.
    minRow = math.max(1, minRow - 1)
    maxRow = math.min(rows, maxRow + 1)
  end

  return minCol, maxCol, minRow, maxRow
end

return Perspective
