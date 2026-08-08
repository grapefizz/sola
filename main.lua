local player = {
  x = 400,
  y = 300,
  radius = 22,
  speed = 280,
}

local elapsed = 0

function love.load()
  love.window.setTitle("Ice Cube")
  love.graphics.setBackgroundColor(0.04, 0.08, 0.16)
  love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.update(dt)
  elapsed = elapsed + dt

  local dx, dy = 0, 0
  if love.keyboard.isDown("left", "a") then dx = dx - 1 end
  if love.keyboard.isDown("right", "d") then dx = dx + 1 end
  if love.keyboard.isDown("up", "w") then dy = dy - 1 end
  if love.keyboard.isDown("down", "s") then dy = dy + 1 end

  if dx ~= 0 or dy ~= 0 then
    local length = math.sqrt(dx * dx + dy * dy)
    player.x = player.x + dx / length * player.speed * dt
    player.y = player.y + dy / length * player.speed * dt
  end

  local width, height = love.graphics.getDimensions()
  player.x = math.max(player.radius, math.min(width - player.radius, player.x))
  player.y = math.max(player.radius, math.min(height - player.radius, player.y))
end

function love.draw()
  local width, height = love.graphics.getDimensions()

  love.graphics.setColor(0.08, 0.18, 0.31)
  for y = 0, height, 40 do
    for x = 0, width, 40 do
      local wave = math.sin(elapsed * 1.5 + x * 0.03 + y * 0.04)
      love.graphics.circle("fill", x, y + wave * 3, 1.5)
    end
  end

  love.graphics.setColor(0.72, 0.94, 1)
  love.graphics.circle("fill", player.x, player.y, player.radius)
  love.graphics.setColor(0.25, 0.68, 0.93)
  love.graphics.circle("line", player.x, player.y, player.radius, 32)

  love.graphics.setColor(0.92, 0.97, 1)
  love.graphics.print("Ice Cube", 24, 22)
  love.graphics.setColor(0.58, 0.75, 0.9)
  love.graphics.print("Move with arrow keys or WASD", 24, 48)
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end
end
