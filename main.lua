local player = {
  col = 10,
  row = 8,
  movesRemaining = 20,
  maxMoves = 20,
  startSize = 30,
}

local grid = {
  size = 40,
  columns = 20,
  rows = 15,
}

local camera = {
  zoom = 2,
  x = (player.col - 0.5) * grid.size,
  y = (player.row - 0.5) * grid.size,
}

local movement = {
  active = false,
  elapsed = 0,
  duration = 0.28,
  fromCol = player.col,
  fromRow = player.row,
  toCol = player.col,
  toRow = player.row,
}

function love.load()
  love.window.setTitle("Ice Cube")
  love.graphics.setBackgroundColor(0.04, 0.08, 0.16)
  love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.update(dt)
  if movement.active then
    movement.elapsed = math.min(movement.elapsed + dt, movement.duration)
    if movement.elapsed >= movement.duration then
      movement.active = false
    end
  end
end

function love.draw()
  local worldWidth = grid.columns * grid.size
  local worldHeight = grid.rows * grid.size
  local screenWidth, screenHeight = love.graphics.getDimensions()

  love.graphics.push()
  love.graphics.translate(screenWidth / 2, screenHeight / 2)
  love.graphics.scale(camera.zoom)
  love.graphics.translate(-camera.x, -camera.y)

  love.graphics.setColor(0.06, 0.16, 0.27)
  love.graphics.rectangle("fill", 0, 0, worldWidth, worldHeight)

  love.graphics.setColor(0.13, 0.32, 0.47)
  love.graphics.setLineWidth(1 / camera.zoom)
  for col = 0, grid.columns do
    local x = col * grid.size
    love.graphics.line(x, 0, x, worldHeight)
  end
  for row = 0, grid.rows do
    local y = row * grid.size
    love.graphics.line(0, y, worldWidth, y)
  end

  local moveProgress = 1
  if movement.active then
    moveProgress = movement.elapsed / movement.duration
  end
  local easedProgress = moveProgress * moveProgress * (3 - 2 * moveProgress)
  local displayedMoves = player.movesRemaining
  if movement.active then
    displayedMoves = displayedMoves + (1 - easedProgress)
  end
  local cubeSize = player.startSize * (displayedMoves / player.maxMoves)

  love.graphics.pop()

  if cubeSize > 0 then
    local displayCol = player.col
    local displayRow = player.row
    if movement.active then
      displayCol = movement.fromCol + (movement.toCol - movement.fromCol) * easedProgress
      displayRow = movement.fromRow + (movement.toRow - movement.fromRow) * easedProgress
    end
    local worldX = (displayCol - 0.5) * grid.size
    local worldY = (displayRow - 0.5) * grid.size
    local cubeX = screenWidth / 2 + (worldX - camera.x) * camera.zoom
    local cubeY = screenHeight / 2 + (worldY - camera.y) * camera.zoom
    local screenCubeSize = cubeSize * camera.zoom
    local halfSize = screenCubeSize / 2
    local cornerRadius = math.min(8, screenCubeSize / 5)

    love.graphics.setColor(0.66, 0.92, 1)
    love.graphics.rectangle(
      "fill",
      cubeX - halfSize,
      cubeY - halfSize,
      screenCubeSize,
      screenCubeSize,
      cornerRadius,
      cornerRadius
    )
    love.graphics.setColor(0.18, 0.58, 0.86)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle(
      "line",
      cubeX - halfSize,
      cubeY - halfSize,
      screenCubeSize,
      screenCubeSize,
      cornerRadius,
      cornerRadius
    )
  end

  love.graphics.setColor(0.92, 0.97, 1)
  love.graphics.print("Ice Cube", 18, 14)
  love.graphics.setColor(0.58, 0.75, 0.9)
  if player.movesRemaining > 0 then
    love.graphics.print("Moves until melted: " .. player.movesRemaining, 18, 38)
  else
    love.graphics.print("The ice cube has melted!", 18, 38)
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end

  if player.movesRemaining == 0 then
    return
  end

  if movement.active then
    return
  end

  local col, row = player.col, player.row

  if key == "left" or key == "a" then
    col = col - 1
  elseif key == "right" or key == "d" then
    col = col + 1
  elseif key == "up" or key == "w" then
    row = row - 1
  elseif key == "down" or key == "s" then
    row = row + 1
  end

  local nextCol = math.max(1, math.min(grid.columns, col))
  local nextRow = math.max(1, math.min(grid.rows, row))

  if nextCol ~= player.col or nextRow ~= player.row then
    movement.active = true
    movement.elapsed = 0
    movement.fromCol = player.col
    movement.fromRow = player.row
    movement.toCol = nextCol
    movement.toRow = nextRow
    player.col = nextCol
    player.row = nextRow
    player.movesRemaining = player.movesRemaining - 1
  end
end
