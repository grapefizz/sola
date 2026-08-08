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
  x = grid.columns * grid.size / 2,
  y = grid.rows * grid.size / 2,
}

function love.load()
  love.window.setTitle("Ice Cube")
  love.graphics.setBackgroundColor(0.04, 0.08, 0.16)
  love.graphics.setDefaultFilter("nearest", "nearest")
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

  local x = (player.col - 1) * grid.size
  local y = (player.row - 1) * grid.size
  local cubeSize = player.startSize * (player.movesRemaining / player.maxMoves)

  if cubeSize > 0 then
    local cubeX = x + (grid.size - cubeSize) / 2
    local cubeY = y + (grid.size - cubeSize) / 2
    local cornerRadius = math.min(5, cubeSize / 4)

    love.graphics.setColor(0.66, 0.92, 1)
    love.graphics.rectangle("fill", cubeX, cubeY, cubeSize, cubeSize, cornerRadius, cornerRadius)
    love.graphics.setColor(0.18, 0.58, 0.86)
    love.graphics.rectangle("line", cubeX, cubeY, cubeSize, cubeSize, cornerRadius, cornerRadius)
  end

  love.graphics.pop()

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
    player.col = nextCol
    player.row = nextRow
    player.movesRemaining = player.movesRemaining - 1
  end
end
