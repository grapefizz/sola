local Camera = require("game.camera")
local Editor = require("game.editor")
local Grid = require("game.grid")
local Player = require("game.player")

local SPAWN_COL = 10
local SPAWN_ROW = 8

local grid = Grid.new(40, 20, 15)
local player
local camera
local editor = Editor.new(SPAWN_COL, SPAWN_ROW)

grid:addFire(13, 8)

local function restartRun()
  grid:clearWater()
  grid:setGround(SPAWN_COL, SPAWN_ROW)
  grid:removeFire(SPAWN_COL, SPAWN_ROW)
  player = Player.new(SPAWN_COL, SPAWN_ROW)
  local cameraX, cameraY = grid:tileCenter(player.col, player.row)
  camera = Camera.new(cameraX, cameraY, 2)
  grid:addWater(player.col, player.row)
end

restartRun()

function love.load()
  love.window.setTitle("Ice Cube")
  love.graphics.setBackgroundColor(0.04, 0.08, 0.16)
  love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.update(dt)
  if editor.active then
    editor:update(dt, grid, camera)
  else
    player:update(dt, grid)
    local pX, pY = grid:tileCenter(player.col, player.row)
  end
end

function love.draw()
  camera:attach()
  grid:draw(camera.zoom)
  camera:detach()

  if editor.active then
    editor:draw(grid, camera)
  else
    player:draw(grid, camera)
    player:drawHud()
    love.graphics.setColor(0.58, 0.75, 0.9)
    love.graphics.print("E: level editor", 18, 58)
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end

  if key == "e" then
    editor:setActive(not editor.active)
    grid:clearWater()
    if not editor.active then
      restartRun()
    end
    return
  end

  if editor.active then
    editor:keypressed(key, grid)
    return
  end

  if key == "r" then
    restartRun()
    return
  end

  player:keypressed(key, grid)
end

function love.mousepressed(x, y, button)
  if editor.active then
    editor:mousepressed(x, y, button, grid, camera)
  end
end

function love.wheelmoved(_, y)
  if editor.active then
    editor:wheelmoved(y, grid, camera)
  end
end
