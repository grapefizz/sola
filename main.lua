local Camera = require("game.camera")
local Grid = require("game.grid")
local Player = require("game.player")

local grid = Grid.new(40, 20, 15)
local player = Player.new(10, 8)
local cameraX, cameraY = grid:tileCenter(player.col, player.row)
local camera = Camera.new(cameraX, cameraY, 2)

grid:addWater(player.col, player.row)

function love.load()
  love.window.setTitle("Ice Cube")
  love.graphics.setBackgroundColor(0.04, 0.08, 0.16)
  love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.update(dt)
  player:update(dt, grid)
end

function love.draw()
  camera:attach()
  grid:draw(camera.zoom)
  camera:detach()

  player:draw(grid, camera)
  player:drawHud()
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end

  player:keypressed(key, grid)
end
