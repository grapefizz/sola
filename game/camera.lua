local Camera = {}
Camera.__index = Camera

function Camera.new(x, y, zoom)
  return setmetatable({
    x = x,
    y = y,
    zoom = zoom,
  }, Camera)
end

function Camera:attach()
  local width, height = love.graphics.getDimensions()
  love.graphics.push()
  love.graphics.translate(width / 2, height / 2)
  love.graphics.scale(self.zoom)
  love.graphics.translate(-self.x, -self.y)
end

function Camera:detach()
  love.graphics.pop()
end

function Camera:worldToScreen(x, y)
  local width, height = love.graphics.getDimensions()
  return width / 2 + (x - self.x) * self.zoom,
    height / 2 + (y - self.y) * self.zoom
end

function Camera:screenToWorld(x, y)
  local width, height = love.graphics.getDimensions()
  return self.x + (x - width / 2) / self.zoom,
    self.y + (y - height / 2) / self.zoom
end

return Camera
