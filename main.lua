--[[
  Ice Cube — LÖVE 11.5
  Main menu: atmospheric layout + rotating 3D ice block (from ice_block.glb).
]]

local g3d = require "g3d"
local Camera = require "game.camera"
local Editor = require "game.editor"
local Grid = require "game.grid"
local Player = require "game.player"
local Perspective = require "game.perspective"

local state = "menu" -- menu | levels | credits | settings | play
local elapsed = 0
local hover = 0
local selected = 1
local snow = {}
local fonts = {}
local mouseX, mouseY = 0, 0

-- level select (Stardew-style blue panel)
local levelList = {}
local levelSelected = 1
local levelHover = 0
local levelSlide = {}
local levelScroll = 0 -- row offset for card grid
local levelIntro = 0
local currentLevelName = nil
local levelCompleteFlash = 0
local progress = { finished = {} }
local levelPreviews = {}
local PROGRESS_FILE = "progress.txt"
local CARD_COLS = 3
local CARD_ROWS = 2
local CARD_W = 230
local CARD_H = 280
local CARD_GAP_X = 28
local CARD_GAP_Y = 22
local PREVIEW_PAD = 14
local MAP_COLS, MAP_ROWS = 256, 256
local TITLE_AREA = 68
local FOOTER_AREA = 44

local function refreshCardMetrics(width, height)
  width = width or love.graphics.getWidth()
  height = height or love.graphics.getHeight()
  local maxGridW = math.floor(width * 0.9)
  local maxGridH = math.floor(height - TITLE_AREA - FOOTER_AREA - 4)
  CARD_GAP_X = math.max(20, math.floor(width * 0.028))
  CARD_GAP_Y = math.max(16, math.floor(height * 0.028))
  local fitW = math.floor((maxGridW - (CARD_COLS - 1) * CARD_GAP_X) / CARD_COLS)
  local fitH = math.floor((maxGridH - (CARD_ROWS - 1) * CARD_GAP_Y) / CARD_ROWS)

  -- card hugs the map preview (20x15) + label strip under it
  PREVIEW_PAD = math.max(8, math.floor(fitW * 0.045))
  local labelStrip = math.max(48, math.floor(fitH * 0.18))
  local maxPrevW = fitW - PREVIEW_PAD * 2
  local maxPrevH = fitH - PREVIEW_PAD * 2 - labelStrip
  -- fit preview into available box keeping map aspect
  local mapAspect = MAP_COLS / MAP_ROWS
  local prevW, prevH
  if maxPrevW / maxPrevH > mapAspect then
    prevH = maxPrevH
    prevW = math.floor(prevH * mapAspect)
  else
    prevW = maxPrevW
    prevH = math.floor(prevW / mapAspect)
  end

  CARD_W = prevW + PREVIEW_PAD * 2
  CARD_H = prevH + PREVIEW_PAD * 2 + labelStrip
end

local iceModel
local iceTex
local iceTexBlush
local iceShader
local cubeCanvas
local cubeCanvasSize = 0
local menuBg
local menuBgW, menuBgH = 1, 1
-- gentle left↔right yaw; face always stays on-camera
local angleBase = 0.35
local angleSwing = 0.55
local swayPhase = 0
local swaySpeed = 0.85
local cubeAngle = angleBase
local pressingCube = false
local blush = 0
local blushTimer = 0
local bobAmount = 0
local usingBlushTex = false
local intro = 0
local menuSlide = {0, 0, 0, 0, 0}
local titlePulse = 0
local glowPulse = 0

local menu = {
  { id = "play", label = "Play" },
  { id = "settings", label = "Settings" },
  { id = "editor", label = "Level Editor", locked = true },
  { id = "credits", label = "Credits" },
  { id = "exit", label = "Exit" },
}

-- settings (wired where possible)
local settings = {
  { id = "fullscreen", label = "Fullscreen", kind = "toggle", value = false },
  { id = "vsync", label = "VSync", kind = "toggle", value = true },
  { id = "screenshake", label = "Screen Shake", kind = "toggle", value = true },
  { id = "snow", label = "Snow FX", kind = "toggle", value = true },
  { id = "music", label = "Music", kind = "slider", value = 0.55 },
  { id = "sfx", label = "SFX", kind = "slider", value = 0.8 },
}
local settingsHover = 0
local settingsSelected = 1

local snowSheet
local snowQuads = {}
local snowBig
local shakeTime = 0
local shakeMag = 0
local shakeX, shakeY = 0, 0
local sfxClick
local sfxToggle
local musicSrc
local musicVol = 0.55
local sfxVol = 0.8

-- gameplay from game/ (water trails, fire, editor) — modules untouched
local SPAWN_COL = math.ceil(MAP_COLS / 2)
local SPAWN_ROW = math.ceil(MAP_ROWS / 2)
local grid, player, camera, editor

-- Smooth camera follow
local cameraFollowX, cameraFollowY
local cameraFollowSpeed = 10

local function loadProgress()
  progress.finished = {}
  local data = love.filesystem.read(PROGRESS_FILE)
  if not data then
    return
  end
  for line in data:gmatch("[^\r\n]+") do
    local name = line:match("^%s*(.-)%s*$")
    if name and name ~= "" then
      progress.finished[name] = true
    end
  end
end

local function saveProgress()
  local names = {}
  for name in pairs(progress.finished) do
    names[#names + 1] = name
  end
  table.sort(names, function(a, b)
    return a:lower() < b:lower()
  end)
  love.filesystem.write(PROGRESS_FILE, table.concat(names, "\n") .. (#names > 0 and "\n" or ""))
end

local function markLevelFinished(name)
  if not name or progress.finished[name] then
    return
  end
  progress.finished[name] = true
  saveProgress()
end

local function prettyLevelName(name)
  local n = name:match("^level(%d+)$")
  if n then
    return "Level " .. tonumber(n)
  end
  return name:gsub("^%l", string.upper):gsub("(%s%l)", string.upper)
end

local function clearLevelPreviews()
  for name, canvas in pairs(levelPreviews) do
    if canvas and canvas.release then
      canvas:release()
    end
    levelPreviews[name] = nil
  end
end

local function buildLevelPreview(name)
  local pw = math.max(64, CARD_W - PREVIEW_PAD * 2)
  local ph = math.max(48, math.floor(pw * MAP_ROWS / MAP_COLS))

  -- load the real level into a throwaway grid and snapshot its draw
  local snap = Grid.new(40, MAP_COLS, MAP_ROWS, false)
  local contents = Editor.readLevelContents(name)
  if contents then
    snap:load(contents)
  end
  snap:setGround(SPAWN_COL, SPAWN_ROW)
  snap:removeFire(SPAWN_COL, SPAWN_ROW)
  snap:removeIce(SPAWN_COL, SPAWN_ROW)
  snap:removeSnowflake(SPAWN_COL, SPAWN_ROW)
  snap:removeTea(SPAWN_COL, SPAWN_ROW)
  snap:removePuzzlePiece(SPAWN_COL, SPAWN_ROW)
  snap:removePuzzleCanvas(SPAWN_COL, SPAWN_ROW)
  snap:removePuzzleDoor(SPAWN_COL, SPAWN_ROW)
  snap:removeWall(SPAWN_COL, SPAWN_ROW)
  snap:addWater(SPAWN_COL, SPAWN_ROW)

  local worldW, worldH = snap:worldBounds()
  local scale = math.min(pw / worldW, ph / worldH)
  local ox = (pw - worldW * scale) * 0.5
  local oy = (ph - worldH * scale) * 0.5

  -- Frame the occupied region instead of the huge void.
  local minCol, maxCol, minRow, maxRow = snap:occupiedBounds(3)
  local x0 = (minCol - 1) * snap.size
  local y0 = (minRow - 1) * snap.size
  local x1 = maxCol * snap.size
  local y1 = maxRow * snap.size
  local contentW = math.max(snap.size, x1 - x0)
  local contentH = math.max(snap.size, y1 - y0)
  scale = math.min(pw / contentW, ph / contentH) * 0.92
  ox = (pw - contentW * scale) * 0.5 - x0 * scale
  oy = (ph - contentH * scale) * 0.5 - y0 * scale

  local canvas = love.graphics.newCanvas(pw, ph)
  canvas:setFilter("linear", "linear")

  local prevCanvas = love.graphics.getCanvas()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.04, 0.08, 0.16, 1)

  love.graphics.push()
  love.graphics.translate(ox, oy)
  love.graphics.scale(scale, scale)
  snap:draw(1)

  -- Spawn ice cube sprite (matches the in-game player).
  local cx, cy = snap:tileCenter(SPAWN_COL, SPAWN_ROW)
  local size = Perspective.isSide() and 30 or 26
  Player.drawSprite(cx, cy, size, 0, Perspective.mode)
  love.graphics.pop()

  love.graphics.setCanvas(prevCanvas)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
  return canvas
end

local function ensureLevelPreview(name)
  if not levelPreviews[name] then
    levelPreviews[name] = buildLevelPreview(name)
  end
  return levelPreviews[name]
end

local function maxLevelScroll()
  local rows = math.ceil(math.max(1, #levelList) / CARD_COLS)
  return math.max(0, rows - CARD_ROWS)
end

local function refreshLevelList()
  refreshCardMetrics()
  levelList = Editor.listLevelNames()
  clearLevelPreviews()
  if levelSelected > #levelList then
    levelSelected = math.max(1, #levelList)
  end
  if levelSelected < 1 then
    levelSelected = 1
  end
  for i = 1, #levelList do
    levelSlide[i] = levelSlide[i] or 0
    ensureLevelPreview(levelList[i])
  end
  levelScroll = math.max(0, math.min(maxLevelScroll(), levelScroll))
end

local function openLevelSelect()
  state = "levels"
  intro = 0
  levelIntro = 0
  levelScroll = 0
  refreshLevelList()
  love.window.setTitle("Ice Cube — Levels")
end

local function restartRun()
  if currentLevelName and editor then
    editor:loadLevel(grid, currentLevelName)
  else
    grid:clearWater()
    grid:setGround(SPAWN_COL, SPAWN_ROW)
    grid:removeFire(SPAWN_COL, SPAWN_ROW)
    grid:removeIce(SPAWN_COL, SPAWN_ROW)
    grid:removeSnowflake(SPAWN_COL, SPAWN_ROW)
    grid:removeTea(SPAWN_COL, SPAWN_ROW)
    grid:removePuzzlePiece(SPAWN_COL, SPAWN_ROW)
    grid:removePuzzleCanvas(SPAWN_COL, SPAWN_ROW)
    grid:removePuzzleDoor(SPAWN_COL, SPAWN_ROW)
    grid:removeWall(SPAWN_COL, SPAWN_ROW)
  end
  player = Player.new(SPAWN_COL, SPAWN_ROW)
  local cameraX, cameraY = grid:tileCenter(player.col, player.row)
  camera = Camera.new(cameraX, cameraY, 2)
  cameraFollowX, cameraFollowY = cameraX, cameraY
  grid:addWater(player.col, player.row)
  levelCompleteFlash = 0
end

local function startPlay(openEditor, levelName)
  grid = Grid.new(40, MAP_COLS, MAP_ROWS, not openEditor)
  editor = Editor.new(SPAWN_COL, SPAWN_ROW)
  currentLevelName = nil

  if openEditor then
    player = Player.new(SPAWN_COL, SPAWN_ROW)
    local cameraX, cameraY = grid:tileCenter(SPAWN_COL, SPAWN_ROW)
    camera = Camera.new(cameraX, cameraY, 2)
    cameraFollowX, cameraFollowY = cameraX, cameraY
    editor:setActive(true)
    love.window.setTitle("Ice Cube — Level Editor")
    return
  end

  editor:setActive(false)
  if levelName then
    currentLevelName = levelName
    editor:loadLevel(grid, levelName)
  else
    grid:addFire(SPAWN_COL + 3, SPAWN_ROW)
  end
  restartRun()
  love.window.setTitle(levelName and ("Ice Cube — " .. prettyLevelName(levelName)) or "Ice Cube — Play")
end

local function startSelectedLevel()
  local name = levelList[levelSelected]
  if not name then
    return
  end
  state = "play"
  startPlay(false, name)
end

local function clamp(v, a, b)
  return math.max(a, math.min(b, v))
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function getSetting(id)
  for _, s in ipairs(settings) do
    if s.id == id then
      return s.value
    end
  end
end

local function setSetting(id, value)
  for _, s in ipairs(settings) do
    if s.id == id then
      s.value = value
      return s
    end
  end
end

local function playSfx(src)
  if not src then return end
  local s = src:clone()
  s:setVolume(sfxVol)
  s:play()
end

local function applyAudioVolumes()
  musicVol = getSetting("music") or 0
  sfxVol = getSetting("sfx") or 0
  if musicSrc then
    musicSrc:setVolume(musicVol * 0.45)
    if musicVol <= 0.01 then
      musicSrc:pause()
    elseif not musicSrc:isPlaying() then
      musicSrc:play()
    end
  end
end

local function applySetting(item)
  if not item then return end
  if item.id == "fullscreen" then
    love.window.setFullscreen(item.value == true)
  elseif item.id == "vsync" then
    love.window.setVSync(item.value and 1 or 0)
  elseif item.id == "music" or item.id == "sfx" then
    applyAudioVolumes()
  end
end

local function bumpShake(mag, time)
  if not getSetting("screenshake") then return end
  shakeMag = math.max(shakeMag, mag)
  shakeTime = math.max(shakeTime, time)
end

local function makeTone(freq, dur, vol, slide)
  local rate = 44100
  local n = math.floor(rate * dur)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local t = i / rate
    local env = math.min(1, t / 0.01) * (1 - t / dur)
    local f = freq + (slide or 0) * (t / dur)
    local v = math.sin(t * f * math.pi * 2) * env * (vol or 0.4)
    sd:setSample(i, v)
  end
  return love.audio.newSource(sd, "static")
end

local function makeMusicLoop()
  local rate = 22050
  local dur = 4.0
  local n = math.floor(rate * dur)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local t = i / rate
    local a = math.sin(t * 110 * math.pi * 2) * 0.12
    local b = math.sin(t * 164.8 * math.pi * 2) * 0.08
    local c = math.sin(t * 220 * math.pi * 2) * 0.05
    local wobble = 0.7 + 0.3 * math.sin(t * 0.4 * math.pi * 2)
    local fade = math.min(1, t / 0.4) * math.min(1, (dur - t) / 0.4)
    sd:setSample(i, (a + b + c) * wobble * fade)
  end
  local src = love.audio.newSource(sd, "static")
  src:setLooping(true)
  return src
end

local function makeSnow(width, height)
  snow = {}
  -- density scales with area so wide windows stay evenly covered
  local count = math.floor(clamp(width * height / 9000, 70, 140))
  for i = 1, count do
    local useBig = (i % 11 == 0)
    snow[i] = {
      x = love.math.random() * width,
      y = love.math.random() * height,
      speed = love.math.random() * 18 + 10,
      drift = love.math.random() * 8 - 4,
      phase = love.math.random() * math.pi * 2,
      spin = love.math.random() * 0.8 + 0.2,
      rot = love.math.random() * math.pi * 2,
      alpha = love.math.random() * 0.45 + 0.35,
      scale = useBig and (love.math.random() * 0.06 + 0.04) or (love.math.random() * 1.4 + 1.1),
      quad = snowQuads[love.math.random(1, #snowQuads)],
      big = useBig,
    }
  end
end

local function drawSnow()
  if not getSetting("snow") then return end
  for _, f in ipairs(snow) do
    local a = f.alpha * (0.55 + 0.45 * math.sin(f.phase + elapsed * 0.9))
    love.graphics.setColor(0.85, 0.94, 1.0, a)
    if f.big then
      local ox = snowBig:getWidth() * 0.5
      local oy = snowBig:getHeight() * 0.5
      love.graphics.draw(snowBig, f.x, f.y, f.rot, f.scale, f.scale, ox, oy)
    else
      love.graphics.draw(snowSheet, f.quad, f.x, f.y, f.rot, f.scale, f.scale, 4.5, 4.5)
    end
  end
end

local function ensureCubeCanvas(size)
  if cubeCanvas and cubeCanvasSize == size then
    return
  end
  cubeCanvasSize = size
  cubeCanvas = love.graphics.newCanvas(size, size)
end

local cubeViewSize, cubeScreenRect, cubeHit

local function loadPixelFont(path, size)
  local f = love.graphics.newFont(path, size)
  f:setFilter("nearest", "nearest")
  return f
end

-- Stardew-style ice panel
local function drawPanel(x, y, w, h, alpha)
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  alpha = alpha or 1

  love.graphics.setColor(0, 0, 0, 0.28 * alpha)
  love.graphics.rectangle("fill", x + 4, y + 4, w, h)

  -- outer border
  love.graphics.setColor(0.10, 0.22, 0.36, alpha)
  love.graphics.rectangle("fill", x, y, w, h)

  -- mid rim
  love.graphics.setColor(0.55, 0.78, 0.95, alpha)
  love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4)

  -- fill
  love.graphics.setColor(0.38, 0.58, 0.78, alpha)
  love.graphics.rectangle("fill", x + 4, y + 4, w - 8, h - 8)

  -- soft highlight
  love.graphics.setColor(0.75, 0.90, 1.0, 0.35 * alpha)
  love.graphics.rectangle("fill", x + 4, y + 4, w - 8, 3)
end

local function drawRowHighlight(x, y, w, h, alpha)
  love.graphics.setColor(0.62, 0.84, 1.0, 0.55 * alpha)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.85, 0.95, 1.0, 0.35 * alpha)
  love.graphics.rectangle("fill", x, y, w, 2)
end

function love.load()
  love.graphics.setBackgroundColor(0.04, 0.07, 0.12)
  love.graphics.setDefaultFilter("linear", "linear")
  love.mouse.setVisible(true)

  local pixel = "assets/fonts/PixelifySans-Regular.ttf"
  fonts.hero = loadPixelFont(pixel, 48)
  fonts.title = loadPixelFont(pixel, 32)
  fonts.menu = loadPixelFont(pixel, 26)
  fonts.small = loadPixelFont(pixel, 14)
  fonts.credits = loadPixelFont(pixel, 18)
  fonts.tag = loadPixelFont(pixel, 14)

  menuBg = love.graphics.newImage("assets/background/night_forest.jpg")
  menuBg:setFilter("linear", "linear")
  menuBgW, menuBgH = menuBg:getDimensions()

  snowSheet = love.graphics.newImage("assets/snow/pixel_snowflakes.png")
  snowSheet:setFilter("nearest", "nearest")
  snowQuads = {}
  do
    local sw, sh = snowSheet:getDimensions()
    local cell, cols, rows = 9, 6, 3
    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        local idx = row * cols + col
        -- skip the tiniest nearly-empty dots
        if idx ~= 12 then
          snowQuads[#snowQuads + 1] = love.graphics.newQuad(
            col * cell, row * cell, cell, cell, sw, sh
          )
        end
      end
    end
  end
  snowBig = love.graphics.newImage("assets/snow/snowflake.png")
  snowBig:setFilter("linear", "linear")

  sfxClick = makeTone(720, 0.05, 0.35, 180)
  sfxToggle = makeTone(520, 0.07, 0.3, -120)
  musicSrc = makeMusicLoop()

  setSetting("fullscreen", love.window.getFullscreen())
  setSetting("vsync", love.window.getVSync() ~= 0)
  applyAudioVolumes()
  if musicSrc then musicSrc:play() end

  local verts = g3d.loadObj("assets/ice_block.obj", false, false)
  iceTex = love.graphics.newImage("assets/ice_albedo.png")
  iceTex:setFilter("linear", "linear")
  iceTexBlush = love.graphics.newImage("assets/ice_albedo_blush.png")
  iceTexBlush:setFilter("linear", "linear")
  iceModel = g3d.newModel(verts, iceTex, {0, 0, 0}, {0.12, 0, 0.35}, 0.88)
  iceShader = love.graphics.newShader("assets/ice.frag", "g3d/g3d.vert")
  iceShader:send("iceAlpha", 0.78)
  iceShader:send("iceTint", {0.88, 0.95, 1.0})

  g3d.camera.fov = math.rad(30)
  g3d.camera.nearClip = 0.1
  g3d.camera.farClip = 100
  g3d.camera.aspectRatio = 1
  g3d.camera.updateProjectionMatrix()

  love.graphics.setDepthMode("always", false)

  local w, h = love.graphics.getDimensions()
  makeSnow(w, h)
  ensureCubeCanvas(cubeViewSize(w, h))
  intro = 0
  loadProgress()
end

function love.resize(w, h)
  makeSnow(w, h)
  ensureCubeCanvas(cubeViewSize(w, h))
  if state == "levels" then
    refreshLevelList()
  else
    refreshCardMetrics(w, h)
  end
end

local function menuPanelWidth(width)
  return math.floor(math.min(300, math.max(250, width * 0.28))) + 15
end

local function menuRowH(height)
  -- +5 per row ≈ +15px taller overall for the 3-item menu
  return math.floor(math.min(54, math.max(46, height * 0.085))) + 5
end

local function menuBlockY(height)
  local rh = menuRowH(height)
  local ph = 32 + #menu * rh
  return math.floor((height - ph) * 0.5)
end

local function drawLockIcon(x, y, alpha)
  -- tiny padlock: shackle + body
  love.graphics.setColor(0.08, 0.18, 0.30, alpha)
  love.graphics.setLineWidth(2.5)
  love.graphics.arc("line", "open", x + 7, y + 5, 5, math.pi, math.pi * 2)
  love.graphics.rectangle("fill", x + 1, y + 8, 12, 10, 2, 2)
  love.graphics.setColor(0.72, 0.82, 0.92, alpha)
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", x + 7, y + 5, 5, math.pi, math.pi * 2)
  love.graphics.rectangle("fill", x + 2, y + 9, 10, 8, 2, 2)
  love.graphics.setColor(0.35, 0.48, 0.62, alpha)
  love.graphics.circle("fill", x + 7, y + 12, 1.6)
  love.graphics.rectangle("fill", x + 6.2, y + 12, 1.6, 3)
  love.graphics.setLineWidth(1)
end

local function menuAnchorX(width)
  return math.floor(width * 0.52)
end

cubeViewSize = function(width, height)
  local menuX = menuAnchorX(width)
  local room = menuX - width * 0.04
  local size = math.min(room, height * 0.55, width * 0.38)
  return math.floor(math.max(200, size))
end

cubeScreenRect = function(width, height)
  local size = cubeViewSize(width, height)
  local menuX = menuAnchorX(width)
  local rh = menuRowH(height)
  local ph = 32 + #menu * rh
  local by = menuBlockY(height)
  local titleH = (fonts.hero and fonts.hero:getHeight()) or 48
  -- sit just left of the menu, vertically aligned with title + menu block
  local blockTop = by - titleH - 18
  local blockH = (by + ph) - blockTop
  local gap = 18
  local x = menuX - size - gap
  local y = blockTop + (blockH - size) * 0.52
  return x, y, size
end

cubeHit = function(mx, my, width, height)
  local cx, cy, size = cubeScreenRect(width, height)
  local bob = bobAmount
  local pad = size * 0.18
  return mx >= cx + pad and mx <= cx + size - pad
     and my >= cy + bob + pad and my <= cy + bob + size - pad * 0.55
end

local function menuItemHit(mx, my, width, height)
  local x = menuAnchorX(width)
  local bw = menuPanelWidth(width)
  local rh = menuRowH(height)
  local by = menuBlockY(height)
  for i = 1, #menu do
    local y = by + 16 + (i - 1) * rh
    if mx >= x and mx <= x + bw and my >= y and my <= y + rh then
      return i
    end
  end
  return 0
end

local function activate(item)
  if type(item) == "string" then
    for _, m in ipairs(menu) do
      if m.id == item then
        item = m
        break
      end
    end
  end
  if not item then
    return
  end
  -- Level Editor stays visually locked (padlock) but still opens
  if item.locked and item.id ~= "editor" then
    playSfx(sfxClick)
    bumpShake(2.5, 0.12)
    return
  end
  playSfx(sfxClick)
  bumpShake(3.5, 0.16)
  local id = item.id
  if id == "play" then
    openLevelSelect()
  elseif id == "editor" then
    state = "play"
    startPlay(true)
  elseif id == "settings" then
    state = "settings"
    intro = 0
    love.window.setTitle("Ice Cube")
  elseif id == "credits" then
    state = "credits"
    intro = 0
    love.window.setTitle("Ice Cube")
  elseif id == "exit" then
    love.event.quit()
  end
end

local function changeSetting(item, newValue, quiet)
  if not item then return end
  item.value = newValue
  applySetting(item)
  if not quiet then
    playSfx(item.kind == "toggle" and sfxToggle or sfxClick)
    bumpShake(2.0, 0.1)
  end
end

local function easeOutCubic(t)
  local u = 1 - t
  return 1 - u * u * u
end

local function levelsGridMetrics(width, height)
  local gridW = CARD_COLS * CARD_W + (CARD_COLS - 1) * CARD_GAP_X
  local gridH = CARD_ROWS * CARD_H + (CARD_ROWS - 1) * CARD_GAP_Y
  local gridX = math.floor((width - gridW) * 0.5)
  local gridY = math.floor(TITLE_AREA + (height - TITLE_AREA - FOOTER_AREA - gridH) * 0.5)
  gridY = math.max(TITLE_AREA + 8, gridY)
  return gridX, gridY, gridW, gridH
end

local function perspectiveButtonRect(width, height)
  local bw, bh = 148, 34
  local x = width - bw - 18
  local y = 18
  return x, y, bw, bh
end

local function perspectiveButtonHit(mx, my, width, height)
  local x, y, w, h = perspectiveButtonRect(width, height)
  if mx >= x and mx <= x + w and my >= y and my <= y + h then
    return true
  end
  return false
end

local function togglePerspectiveView()
  Perspective.toggle()
  clearLevelPreviews()
  playSfx(sfxToggle)
  bumpShake(2.5, 0.12)
end

local function drawPerspectiveButton(width, height, alpha)
  alpha = alpha or 1
  local x, y, w, h = perspectiveButtonRect(width, height)
  local hover = perspectiveButtonHit(mouseX, mouseY, width, height)
  local side = Perspective.isSide()

  love.graphics.setColor(0.05, 0.12, 0.22, 0.82 * alpha)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  if hover or side then
    love.graphics.setColor(0.55, 0.82, 1.0, (hover and 0.85 or 0.55) * alpha)
  else
    love.graphics.setColor(0.35, 0.55, 0.72, 0.55 * alpha)
  end
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2, 5, 5)

  -- Tiny glyph: plan square vs standing block.
  local gx = x + 12
  local gy = y + 8
  if side then
    love.graphics.setColor(0.78, 0.58, 0.42, alpha)
    love.graphics.rectangle("fill", gx + 4, gy, 10, 18, 1, 1)
    love.graphics.setColor(0.92, 0.78, 0.58, alpha)
    love.graphics.rectangle("fill", gx + 4, gy, 10, 3, 1, 1)
  else
    love.graphics.setColor(0.35, 0.72, 0.95, alpha)
    love.graphics.rectangle("fill", gx, gy + 4, 16, 12, 2, 2)
  end

  love.graphics.setFont(fonts.small)
  local label = Perspective.shortLabel() .. " View"
  love.graphics.setColor(0.92, 0.97, 1.0, alpha)
  love.graphics.print(label, x + 34, y + math.floor((h - fonts.small:getHeight()) * 0.5))
end

local function levelCardRect(index, width, height)
  local localIndex = index - levelScroll * CARD_COLS
  if localIndex < 1 or localIndex > CARD_COLS * CARD_ROWS then
    return nil
  end
  local col = ((localIndex - 1) % CARD_COLS)
  local row = math.floor((localIndex - 1) / CARD_COLS)
  local gridX, gridY = levelsGridMetrics(width, height)
  local slideIn = math.floor((1 - easeOutCubic(intro)) * (20 + col * 8))
  local x = gridX + col * (CARD_W + CARD_GAP_X)
  local y = gridY + row * (CARD_H + CARD_GAP_Y) + slideIn
  return x, y, CARD_W, CARD_H
end

local function levelItemHit(mx, my, width, height)
  if #levelList == 0 then
    return 0
  end
  local first = levelScroll * CARD_COLS + 1
  local last = math.min(#levelList, first + CARD_COLS * CARD_ROWS - 1)
  for i = first, last do
    local x, y, w, h = levelCardRect(i, width, height)
    if x and mx >= x and mx <= x + w and my >= y and my <= y + h then
      return i
    end
  end
  return 0
end

local function drawStatusBadge(x, y, finished, alpha)
  local label = finished and "Finished" or "New"
  love.graphics.setFont(fonts.small)
  local tw = fonts.small:getWidth(label)
  local th = fonts.small:getHeight()
  local pad = finished and 22 or 14
  local bw, bh = tw + pad, th + 6
  local bx = math.floor(x - bw * 0.5)

  if finished then
    love.graphics.setColor(0.18, 0.42, 0.28, 0.9 * alpha)
    love.graphics.rectangle("fill", bx, y, bw, bh, 4, 4)
    love.graphics.setColor(0.45, 0.92, 0.62, 0.95 * alpha)
    love.graphics.rectangle("line", bx, y, bw, bh, 4, 4)
    love.graphics.setLineWidth(2)
    love.graphics.line(bx + 6, y + bh * 0.55, bx + 9, y + bh * 0.72, bx + 14, y + bh * 0.32)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.92, 1.0, 0.95, alpha)
    love.graphics.print(label, bx + 18, y + 2)
  else
    love.graphics.setColor(0.22, 0.38, 0.55, 0.8 * alpha)
    love.graphics.rectangle("fill", bx, y, bw, bh, 4, 4)
    love.graphics.setColor(0.65, 0.82, 0.98, 0.7 * alpha)
    love.graphics.rectangle("line", bx, y, bw, bh, 4, 4)
    love.graphics.setColor(0.85, 0.94, 1.0, 0.9 * alpha)
    love.graphics.print(label, bx + 7, y + 2)
  end
  return bw
end

local function keepLevelSelectionVisible()
  local selectedRow = math.floor((levelSelected - 1) / CARD_COLS)
  if selectedRow < levelScroll then
    levelScroll = selectedRow
  elseif selectedRow > levelScroll + CARD_ROWS - 1 then
    levelScroll = selectedRow - CARD_ROWS + 1
  end
  levelScroll = math.max(0, math.min(maxLevelScroll(), levelScroll))
end

function love.update(dt)
  elapsed = elapsed + dt
  local width, height = love.graphics.getDimensions()
  mouseX, mouseY = love.mouse.getPosition()

  glowPulse = 0.55 + 0.45 * math.sin(elapsed * 1.2)
  titlePulse = 0.85 + 0.15 * math.sin(elapsed * 1.6)

  if shakeTime > 0 then
    shakeTime = math.max(0, shakeTime - dt)
    local t = shakeTime > 0 and (shakeMag * (shakeTime / 0.25)) or 0
    shakeX = (love.math.random() * 2 - 1) * t
    shakeY = (love.math.random() * 2 - 1) * t
    if shakeTime <= 0 then
      shakeX, shakeY, shakeMag = 0, 0, 0
    end
  end

  if getSetting("snow") then
    for _, f in ipairs(snow) do
      f.y = f.y + f.speed * dt
      f.x = f.x + math.sin(elapsed * 0.7 + f.phase) * f.drift * dt
      f.rot = f.rot + f.spin * dt
      if f.y > height + 20 then
        f.y = -20
        f.x = love.math.random() * width
      end
    end
  end

  if state == "menu" or state == "credits" or state == "settings" or state == "levels" then
    intro = math.min(1, intro + dt * 1.35)
  end

  if state == "levels" then
    levelIntro = math.min(1, levelIntro + dt * 1.5)
    local hit = levelItemHit(mouseX, mouseY, width, height)
    if hit > 0 then
      levelSelected = hit
      levelHover = hit
    else
      levelHover = 0
    end
    for i = 1, #levelList do
      local target = ((i == levelSelected) or (i == levelHover)) and 1 or 0
      levelSlide[i] = lerp(levelSlide[i] or 0, target, 1 - math.exp(-16 * dt))
    end
    keepLevelSelectionVisible()
  end

  if state == "menu" then
    swayPhase = swayPhase + dt * swaySpeed
    cubeAngle = angleBase + math.sin(swayPhase) * angleSwing
    iceModel:setRotation(0.12, 0, cubeAngle)
    bobAmount = math.sin(elapsed * 0.95) * 3.2

    if blushTimer > 0 then
      blushTimer = blushTimer - dt
      if blushTimer > 1.0 then
        blush = 1
      else
        blush = clamp(blushTimer / 1.0, 0, 1)
      end
      if blushTimer <= 0 then
        blush = 0
      end
    elseif pressingCube then
      blush = math.min(1, blush + dt * 0.8)
    elseif blush > 0 then
      blush = math.max(0, blush - dt * 0.45)
    end

    local wantBlush = blush > 0.2
    if wantBlush ~= usingBlushTex then
      usingBlushTex = wantBlush
      iceModel.mesh:setTexture(wantBlush and iceTexBlush or iceTex)
      iceModel.texture = wantBlush and iceTexBlush or iceTex
    end

    local hit = menuItemHit(mouseX, mouseY, width, height)
    if hit > 0 then
      selected = hit
      hover = hit
    else
      hover = 0
    end

    for i = 1, #menu do
      local target = ((i == selected) or (i == hover)) and 1 or 0
      menuSlide[i] = lerp(menuSlide[i], target, 1 - math.exp(-16 * dt))
    end
  elseif state == "play" then
    if editor.active then
      editor:update(dt, grid, camera)
    else
      player:update(dt, grid)
      local cameraX, cameraY = grid:tileCenter(player.col, player.row)
      local followT = 1 - math.exp(-cameraFollowSpeed * dt)
      cameraFollowX = cameraFollowX + (cameraX - cameraFollowX) * followT
      cameraFollowY = cameraFollowY + (cameraY - cameraFollowY) * followT
      camera.x = cameraFollowX
      camera.y = cameraFollowY
      -- Reaching the iced-tea goal is the only completion condition.
      if currentLevelName
        and player.won
        and not progress.finished[currentLevelName]
      then
        markLevelFinished(currentLevelName)
        levelCompleteFlash = 2.2
        playSfx(sfxToggle)
        bumpShake(4, 0.2)
      end
      if levelCompleteFlash > 0 then
        levelCompleteFlash = math.max(0, levelCompleteFlash - dt)
      end
    end
  end
end

local function drawAtmosphere(width, height)
  -- cover-scale seamless night forest (tile horizontally if needed)
  local scale = math.max(width / menuBgW, height / menuBgH)
  local drawH = menuBgH * scale
  local tileW = menuBgW * scale
  local y = (height - drawH) * 0.5
  local scroll = (elapsed * 12) % tileW

  love.graphics.setColor(1, 1, 1, 1)
  local x = -scroll
  while x < width do
    love.graphics.draw(menuBg, x, y, 0, scale, scale)
    x = x + tileW
  end

  -- soft cool wash so UI panels stay readable
  love.graphics.setColor(0.04, 0.08, 0.14, 0.28)
  love.graphics.rectangle("fill", 0, 0, width, height)

  -- ice glow behind cube
  love.graphics.setColor(0.45, 0.78, 0.95, 0.06 * glowPulse)
  love.graphics.circle("fill", width * 0.24, height * 0.38, height * 0.32)
  love.graphics.setColor(0.70, 0.90, 1.0, 0.04 * glowPulse)
  love.graphics.circle("fill", width * 0.24, height * 0.38, height * 0.16)

  love.graphics.setColor(0, 0, 0, 0.28)
  love.graphics.rectangle("fill", 0, 0, width, 56)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", 0, height - 64, width, 64)
end

local function drawMenuCube(width, height)
  local cx, cy, size = cubeScreenRect(width, height)
  ensureCubeCanvas(size)

  local e = easeOutCubic(intro)
  local slideX = (1 - e) * -40
  local fade = e

  love.graphics.setCanvas({cubeCanvas, depth = true})
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setDepthMode("lequal", true)
  love.graphics.setBlendMode("alpha", "alphamultiply")
  love.graphics.setColor(1, 1, 1, 1)

  g3d.camera.aspectRatio = 1
  g3d.camera.fov = math.rad(30)
  g3d.camera.updateProjectionMatrix()
  g3d.camera.lookAt(3.8, -5.2, 0.95, 0, 0, 0.3)

  iceShader:send("iceAlpha", 0.82 + blush * 0.04)
  iceShader:send("iceTint", {
    0.90 + blush * 0.05,
    0.94 - blush * 0.03,
    1.0 - blush * 0.05,
  })
  iceModel:draw(iceShader)

  love.graphics.setCanvas()
  love.graphics.setDepthMode("always", false)

  local bob = bobAmount
  local midX = cx + size * 0.50 + slideX
  local midY = cy + bob + size * 0.72

  -- soft pool shadow
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(0, 0, 0, 0.28 * fade)
  love.graphics.ellipse("fill", midX, midY + 6, size * 0.20, size * 0.04)
  love.graphics.setColor(0.25, 0.55, 0.75, 0.12 * fade * glowPulse)
  love.graphics.ellipse("fill", midX, midY, size * 0.15, size * 0.03)

  -- premultiplied cube blit so glass edges stay clean
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(fade, fade, fade, fade)
  love.graphics.draw(cubeCanvas, cx + slideX, cy + bob)
  love.graphics.setBlendMode("alpha")

  local gx = cx + slideX + size * 0.55
  local gy = cy + bob + size * 0.32
  local pulse = (0.35 + 0.40 * math.sin(elapsed * 2.0)) * fade
  love.graphics.setColor(0.85, 0.95, 1.0, pulse)
  love.graphics.circle("fill", gx, gy, 1.6)
  love.graphics.setColor(0.85, 0.95, 1.0, pulse * 0.45)
  love.graphics.rectangle("fill", gx - 5, gy - 0.55, 10, 1.1)
  love.graphics.rectangle("fill", gx - 0.55, gy - 5, 1.1, 10)
end

local function drawMenuItems(width, height)
  local x = menuAnchorX(width)
  local bw = menuPanelWidth(width)
  local rh = menuRowH(height)
  local e = easeOutCubic(clamp((intro - 0.12) / 0.55, 0, 1))
  local by = menuBlockY(height) + math.floor((1 - e) * 12)
  local pad = 18
  local ph = pad * 2 + #menu * rh
  local a = e

  drawPanel(x, by, bw, ph, a)

  for i, item in ipairs(menu) do
    local slide = menuSlide[i] or 0
    local rowY = by + pad + (i - 1) * rh
    local locked = item.locked
    local selected = slide > 0.15
    local pulse = selected and (0.85 + 0.15 * math.sin(elapsed * 5)) or 1

    local inset = math.floor(10 - 4 * slide)
    local rowX = x + inset
    local rowW = bw - inset * 2
    local rowH = rh - 8

    if selected and not locked then
      drawRowHighlight(rowX, rowY, rowW, rowH, a * pulse)
      local cx = rowX + 16
      local cy = rowY + math.floor(rowH * 0.5)
      love.graphics.setColor(0.45, 0.78, 1.0, 0.45 * a)
      love.graphics.polygon("fill", cx - 2, cy - 10, cx + 14, cy, cx - 2, cy + 10)
      love.graphics.setColor(1, 1, 1, a)
      love.graphics.polygon("fill", cx, cy - 8, cx + 12, cy, cx, cy + 8)
    elseif selected and locked then
      drawRowHighlight(rowX, rowY, rowW, rowH, a * pulse * 0.75)
      love.graphics.setColor(0.55, 0.72, 0.90, 0.55 * a * pulse)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", rowX + 1, rowY + 1, rowW - 2, rowH - 2)
      love.graphics.setLineWidth(1)
    end

    love.graphics.setFont(fonts.menu)
    local labelA = (0.65 + 0.35 * slide) * a
    if locked then
      labelA = selected and (0.85 * a) or (labelA * 0.45)
    end
    local th = fonts.menu:getHeight()
    local lx = x + 44
    local ly = rowY + math.floor((rowH - th) * 0.5)

    love.graphics.setColor(0.06, 0.16, 0.30, labelA)
    love.graphics.print(item.label, lx + 1, ly + 1)
    if locked then
      if selected then
        love.graphics.setColor(0.92, 0.96, 1.0, labelA)
      else
        love.graphics.setColor(0.70, 0.80, 0.90, labelA)
      end
    else
      love.graphics.setColor(0.95, 0.98, 1.0, labelA)
    end
    love.graphics.print(item.label, lx, ly)

    if locked then
      local lockA = selected and (a * (0.75 + 0.25 * math.sin(elapsed * 6))) or (a * 0.9)
      drawLockIcon(x + 14, rowY + math.floor((rowH - 18) * 0.5), lockA)
    end
  end
end

local function drawMenuTitle(width, height)
  local e = easeOutCubic(intro)
  local title = "Ice Cube"
  love.graphics.setFont(fonts.hero)

  local bw = menuPanelWidth(width)
  local x = menuAnchorX(width)
  local tw = fonts.hero:getWidth(title)
  local th = fonts.hero:getHeight()
  local tx = math.floor(x + (bw - tw) * 0.5)
  local bob = math.sin(elapsed * 1.4) * 2.5
  local ty = math.floor(menuBlockY(height) - th - 18 + bob + (1 - e) * 14)
  local a = e * titlePulse

  -- soft icy glow
  love.graphics.setColor(0.55, 0.82, 1.0, 0.18 * a)
  love.graphics.print(title, tx - 1, ty)
  love.graphics.print(title, tx + 1, ty)
  love.graphics.print(title, tx, ty - 1)
  love.graphics.print(title, tx, ty + 1)

  -- shadow
  love.graphics.setColor(0.05, 0.14, 0.28, 0.55 * a)
  love.graphics.print(title, tx + 2, ty + 3)

  -- fill
  love.graphics.setColor(0.92, 0.98, 1.0, a)
  love.graphics.print(title, tx, ty)

  -- tiny sparkle
  local sx = tx + tw + 6
  local sy = ty + 8 + math.sin(elapsed * 3.2) * 2
  local spark = (0.45 + 0.55 * math.sin(elapsed * 4.5)) * a
  love.graphics.setColor(1, 1, 1, spark)
  love.graphics.circle("fill", sx, sy, 2)
  love.graphics.setColor(0.85, 0.95, 1.0, spark * 0.7)
  love.graphics.rectangle("fill", sx - 5, sy - 0.6, 10, 1.2)
  love.graphics.rectangle("fill", sx - 0.6, sy - 5, 1.2, 10)
end

local function drawMenu(width, height)
  drawAtmosphere(width, height)
  drawMenuCube(width, height)
  drawMenuTitle(width, height)
  drawMenuItems(width, height)
  drawSnow() -- overlay so flakes cover the full screen, not just left of the panel
end

local function drawLevels(width, height)
  drawAtmosphere(width, height)
  local e = easeOutCubic(intro)

  -- floating title only (no big menu panel)
  love.graphics.setFont(fonts.title)
  local t = "Choose a Level"
  local tw = fonts.title:getWidth(t)
  local tx = math.floor((width - tw) * 0.5)
  local ty = math.floor(22 + (1 - e) * 16 + math.sin(elapsed * 1.5) * 2)
  love.graphics.setColor(0.45, 0.78, 1.0, 0.2 * e * titlePulse)
  love.graphics.print(t, tx - 1, ty)
  love.graphics.print(t, tx + 1, ty)
  love.graphics.print(t, tx, ty - 1)
  love.graphics.print(t, tx, ty + 1)
  love.graphics.setColor(0.05, 0.14, 0.28, 0.65 * e)
  love.graphics.print(t, tx + 2, ty + 3)
  love.graphics.setColor(0.95, 0.98, 1.0, e * titlePulse)
  love.graphics.print(t, tx, ty)

  if #levelList == 0 then
    love.graphics.setFont(fonts.credits)
    local empty = "No levels yet — try the editor!"
    love.graphics.setColor(0.78, 0.90, 1.0, 0.85 * e)
    love.graphics.print(empty, math.floor((width - fonts.credits:getWidth(empty)) * 0.5), height * 0.48)
  else
    local first = levelScroll * CARD_COLS + 1
    local last = math.min(#levelList, first + CARD_COLS * CARD_ROWS - 1)
    local _, gridY, _, gridH = levelsGridMetrics(width, height)

    for i = first, last do
      local name = levelList[i]
      local x, y, w, h = levelCardRect(i, width, height)
      if not x then
        break
      end

      local slide = levelSlide[i] or 0
      local active = slide > 0.15
      local pulse = active and (0.88 + 0.12 * math.sin(elapsed * 5)) or 1
      local finished = progress.finished[name] == true
      local lift = math.floor(slide * 6)
      local cardY = y - lift
      local a = e
      local col = ((i - 1) % CARD_COLS)

      -- staggered fade-in per card
      local cardE = easeOutCubic(clamp((intro - 0.05 - col * 0.05) / 0.5, 0, 1))
      a = a * cardE

      -- each card is its own solid panel on the forest bg
      drawPanel(x, cardY, w, h, a)

      if active then
        love.graphics.setColor(0.85, 0.96, 1.0, 0.7 * a * pulse)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x + 2, cardY + 2, w - 4, h - 4)
        love.graphics.setLineWidth(1)
        -- soft glow under selected card
        love.graphics.setColor(0.45, 0.80, 1.0, 0.12 * a * pulse)
        love.graphics.ellipse("fill", x + w * 0.5, cardY + h + 6, w * 0.42, 10)
      end

      -- preview fills the card (card is sized to fit it)
      local preview = ensureLevelPreview(name)
      local prevW = w - PREVIEW_PAD * 2
      local prevH = math.floor(prevW * MAP_ROWS / MAP_COLS)
      local prevX = x + PREVIEW_PAD
      local prevY = cardY + PREVIEW_PAD

      love.graphics.setColor(0.05, 0.12, 0.20, a)
      love.graphics.rectangle("fill", prevX - 2, prevY - 2, prevW + 4, prevH + 4)
      love.graphics.setColor(0.55, 0.78, 0.95, 0.65 * a)
      love.graphics.rectangle("line", prevX - 2, prevY - 2, prevW + 4, prevH + 4)

      if preview then
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.draw(preview, prevX, prevY, 0, prevW / preview:getWidth(), prevH / preview:getHeight())
      end

      -- name + badge in the strip under the preview
      local label = prettyLevelName(name)
      local labelFont = (#label > 12) and fonts.small or fonts.menu
      love.graphics.setFont(labelFont)
      local lx = math.floor(x + (w - labelFont:getWidth(label)) * 0.5)
      local ly = prevY + prevH + 8
      love.graphics.setColor(0.06, 0.16, 0.30, a)
      love.graphics.print(label, lx + 1, ly + 1)
      love.graphics.setColor(0.95, 0.98, 1.0, a)
      love.graphics.print(label, lx, ly)

      drawStatusBadge(x + w * 0.5, ly + labelFont:getHeight() + 4, finished, a)
    end

    -- scrollbar on the right edge of the screen (not inside a menu box)
    local maxScroll = maxLevelScroll()
    if maxScroll > 0 then
      local trackX = width - 22
      local trackY = gridY
      local trackH = gridH
      love.graphics.setColor(0.08, 0.16, 0.28, 0.55 * e)
      love.graphics.rectangle("fill", trackX, trackY, 5, trackH, 2, 2)
      local thumbH = math.max(18, trackH * (CARD_ROWS / (maxScroll + CARD_ROWS)))
      local thumbY = trackY + (trackH - thumbH) * (levelScroll / maxScroll)
      love.graphics.setColor(0.70, 0.88, 1.0, 0.9 * e)
      love.graphics.rectangle("fill", trackX, thumbY, 5, thumbH, 2, 2)
    end
  end

  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.75, 0.88, 1.0, 0.8 * e)
  local tip = "Arrows to move  ·  Enter to play  ·  V perspective  ·  Esc back"
  love.graphics.print(tip, math.floor((width - fonts.small:getWidth(tip)) * 0.5), height - 34)

  drawPerspectiveButton(width, height, e)
  drawSnow()
end

local function drawCredits(width, height)
  drawAtmosphere(width, height)
  local e = easeOutCubic(intro)

  local pw, ph = 360, 280
  local px = math.floor((width - pw) * 0.5)
  local py = math.floor((height - ph) * 0.5 + (1 - e) * 10)
  drawPanel(px, py, pw, ph, e)

  love.graphics.setFont(fonts.title)
  local t = "Credits"
  local tx = math.floor((width - fonts.title:getWidth(t)) * 0.5)
  love.graphics.setColor(0.06, 0.16, 0.30, e)
  love.graphics.print(t, tx + 1, py + 16)
  love.graphics.setColor(0.95, 0.98, 1.0, e)
  love.graphics.print(t, tx, py + 15)

  love.graphics.setColor(0.20, 0.38, 0.55, 0.5 * e)
  love.graphics.rectangle("fill", px + 28, py + 52, pw - 56, 2)

  love.graphics.setFont(fonts.credits)
  local lines = {
    "Made with Love2D",
    "",
    "Game Devs:",
    "Lora Vega",
    "Ari Karakushi",
    "Diell Jashari",
    "Ronin Bekolli",
    "Tuan Bullaku",
    "",
    "Esc to return",
  }
  local y = py + 64
  for _, line in ipairs(lines) do
    local a = (line == "" and 0) or e
    local col = 0.95
    if line:find("[Ee]sc") then
      col = 0.65
    elseif line == "Game Devs:" then
      col = 0.78
    end
    love.graphics.setColor(0.90, 0.96, 1.0, a * col)
    love.graphics.print(line, math.floor((width - fonts.credits:getWidth(line)) * 0.5), y)
    y = y + 20
  end

  drawSnow()
end

local function drawToggle(x, y, on, alpha)
  local w, h = 44, 22
  love.graphics.setColor(0.08, 0.16, 0.28, alpha)
  love.graphics.rectangle("fill", x + 1, y + 1, w, h, 11, 11)
  if on then
    love.graphics.setColor(0.45, 0.78, 1.0, alpha)
  else
    love.graphics.setColor(0.28, 0.40, 0.52, alpha)
  end
  love.graphics.rectangle("fill", x, y, w, h, 11, 11)
  love.graphics.setColor(0.85, 0.94, 1.0, 0.35 * alpha)
  love.graphics.rectangle("fill", x + 2, y + 2, w - 4, 3, 2, 2)
  local kx = on and (x + w - 18) or (x + 4)
  love.graphics.setColor(0.06, 0.14, 0.24, 0.35 * alpha)
  love.graphics.circle("fill", kx + 7, y + 12, 8)
  love.graphics.setColor(0.96, 0.99, 1.0, alpha)
  love.graphics.circle("fill", kx + 7, y + 11, 8)
  return w, h
end

local function drawSlider(x, y, w, value, alpha)
  local h = 10
  love.graphics.setColor(0.10, 0.20, 0.32, alpha)
  love.graphics.rectangle("fill", x, y, w, h, 5, 5)
  love.graphics.setColor(0.35, 0.55, 0.72, alpha)
  love.graphics.rectangle("fill", x + 1, y + 1, w - 2, h - 2, 4, 4)
  local fill = math.floor((w - 2) * clamp(value, 0, 1))
  love.graphics.setColor(0.55, 0.82, 1.0, alpha)
  love.graphics.rectangle("fill", x + 1, y + 1, fill, h - 2, 4, 4)
  local kx = x + 1 + fill
  love.graphics.setColor(0.06, 0.14, 0.24, 0.4 * alpha)
  love.graphics.circle("fill", kx, y + h * 0.5 + 1, 8)
  love.graphics.setColor(0.95, 0.98, 1.0, alpha)
  love.graphics.circle("fill", kx, y + h * 0.5, 8)
  return w, h
end

local function settingsPanelRect(width, height)
  local pw = math.min(420, math.max(340, math.floor(width * 0.42)))
  local rowH = 44
  local ph = 70 + #settings * rowH + 36
  local px = math.floor((width - pw) * 0.5)
  local py = math.floor((height - ph) * 0.5)
  return px, py, pw, ph, rowH
end

local function settingsItemHit(mx, my, width, height)
  local px, py, pw, _, rowH = settingsPanelRect(width, height)
  local y0 = py + 64
  for i = 1, #settings do
    local y = y0 + (i - 1) * rowH
    if mx >= px + 16 and mx <= px + pw - 16 and my >= y and my <= y + rowH - 6 then
      return i
    end
  end
  return 0
end

local function drawSettings(width, height)
  drawAtmosphere(width, height)
  local e = easeOutCubic(intro)
  local px, py, pw, ph, rowH = settingsPanelRect(width, height)
  py = py + math.floor((1 - e) * 12)
  drawPanel(px, py, pw, ph, e)

  love.graphics.setFont(fonts.title)
  local t = "Settings"
  local tx = math.floor((width - fonts.title:getWidth(t)) * 0.5)
  love.graphics.setColor(0.06, 0.16, 0.30, e)
  love.graphics.print(t, tx + 1, py + 16)
  love.graphics.setColor(0.95, 0.98, 1.0, e)
  love.graphics.print(t, tx, py + 15)

  love.graphics.setColor(0.20, 0.38, 0.55, 0.5 * e)
  love.graphics.rectangle("fill", px + 28, py + 52, pw - 56, 2)

  settingsHover = settingsItemHit(mouseX, mouseY, width, height)
  if settingsHover > 0 then
    settingsSelected = settingsHover
  end

  local y0 = py + 64
  for i, item in ipairs(settings) do
    local y = y0 + (i - 1) * rowH
    local active = (i == settingsSelected) or (i == settingsHover)
    local pulse = active and (0.9 + 0.1 * math.sin(elapsed * 5)) or 1

    if active then
      drawRowHighlight(px + 14, y, pw - 28, rowH - 8, e * pulse * 0.85)
    end

    love.graphics.setFont(fonts.menu)
    local ly = y + math.floor((rowH - 8 - fonts.menu:getHeight()) * 0.5)
    love.graphics.setColor(0.06, 0.16, 0.30, e)
    love.graphics.print(item.label, px + 29, ly + 1)
    love.graphics.setColor(0.95, 0.98, 1.0, e)
    love.graphics.print(item.label, px + 28, ly)

    if item.kind == "toggle" then
      drawToggle(px + pw - 72, y + math.floor((rowH - 8 - 22) * 0.5), item.value, e)
    elseif item.kind == "slider" then
      local sw = 120
      drawSlider(px + pw - sw - 28, y + math.floor((rowH - 8 - 10) * 0.5), sw, item.value, e)
    end
  end

  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.75, 0.88, 1.0, 0.7 * e)
  local tip = "Esc to return"
  love.graphics.print(tip, math.floor((width - fonts.small:getWidth(tip)) * 0.5), py + ph - 28)

  drawSnow()
end

function love.draw()
  local width, height = love.graphics.getDimensions()
  love.graphics.setDepthMode("always", false)
  love.graphics.setShader()

  if state == "play" then
    love.graphics.setBackgroundColor(0.04, 0.08, 0.16)
    love.graphics.clear(0.04, 0.08, 0.16)

    camera:attach()
    if editor.active then
      -- Show the tile grid only while editing.
      grid:draw(camera.zoom, camera, true)
    else
      -- Normal gameplay: no editor grid.
      grid:draw(camera.zoom, camera, false)
    end
    camera:detach()

    if editor.active then
      editor:draw(grid, camera)
    else
      player:draw(grid, camera)
      player:drawHud(grid)
      if levelCompleteFlash > 0 then
        local a = math.min(1, levelCompleteFlash)
        love.graphics.setColor(0.04, 0.10, 0.18, 0.45 * a)
        love.graphics.rectangle("fill", 0, 0, width, height)
        love.graphics.setFont(fonts.title)
        local msg = "Level finished!"
        local tw = fonts.title:getWidth(msg)
        love.graphics.setColor(0.06, 0.16, 0.30, a)
        love.graphics.print(msg, math.floor((width - tw) * 0.5) + 1, math.floor(height * 0.42) + 1)
        love.graphics.setColor(0.85, 1.0, 0.92, a)
        love.graphics.print(msg, math.floor((width - tw) * 0.5), math.floor(height * 0.42))
        love.graphics.setFont(fonts.small)
        local tip = "Esc · back to levels"
        love.graphics.setColor(0.75, 0.90, 1.0, 0.85 * a)
        love.graphics.print(tip, math.floor((width - fonts.small:getWidth(tip)) * 0.5), math.floor(height * 0.42) + 42)
      end
    end
    return
  end

  love.graphics.push()
  love.graphics.translate(shakeX, shakeY)

  if state == "menu" then
    drawMenu(width, height)
  elseif state == "levels" then
    drawLevels(width, height)
  elseif state == "credits" then
    drawCredits(width, height)
  elseif state == "settings" then
    drawSettings(width, height)
  end

  love.graphics.pop()
end

function love.keypressed(key)
  if state == "menu" then
    if key == "up" or key == "w" then
      selected = selected - 1
      if selected < 1 then selected = #menu end
      playSfx(sfxClick)
    elseif key == "down" or key == "s" then
      selected = selected + 1
      if selected > #menu then selected = 1 end
      playSfx(sfxClick)
    elseif key == "return" or key == "space" then
      activate(menu[selected])
    elseif key == "escape" then
      love.event.quit()
    end
  elseif state == "levels" then
    if key == "escape" or key == "backspace" then
      state = "menu"
      intro = 0
      love.window.setTitle("Ice Cube")
      playSfx(sfxClick)
    elseif key == "v" then
      togglePerspectiveView()
    elseif #levelList > 0 then
      if key == "left" or key == "a" then
        levelSelected = levelSelected - 1
        if levelSelected < 1 then levelSelected = #levelList end
        keepLevelSelectionVisible()
        playSfx(sfxClick)
      elseif key == "right" or key == "d" then
        levelSelected = levelSelected + 1
        if levelSelected > #levelList then levelSelected = 1 end
        keepLevelSelectionVisible()
        playSfx(sfxClick)
      elseif key == "up" or key == "w" then
        local myCol = ((levelSelected - 1) % CARD_COLS) + 1
        levelSelected = levelSelected - CARD_COLS
        if levelSelected < 1 then
          local lastRowStart = math.floor((#levelList - 1) / CARD_COLS) * CARD_COLS
          levelSelected = math.min(#levelList, lastRowStart + myCol)
        end
        keepLevelSelectionVisible()
        playSfx(sfxClick)
      elseif key == "down" or key == "s" then
        local myCol = ((levelSelected - 1) % CARD_COLS) + 1
        levelSelected = levelSelected + CARD_COLS
        if levelSelected > #levelList then
          levelSelected = myCol
          if levelSelected > #levelList then levelSelected = 1 end
        end
        keepLevelSelectionVisible()
        playSfx(sfxClick)
      elseif key == "return" or key == "space" then
        playSfx(sfxClick)
        bumpShake(3.5, 0.16)
        startSelectedLevel()
      end
    end
  elseif state == "credits" then
    if key == "escape" or key == "return" or key == "space" or key == "backspace" then
      state = "menu"
      intro = 0
      playSfx(sfxClick)
    end
  elseif state == "settings" then
    if key == "escape" or key == "backspace" then
      state = "menu"
      intro = 0
      playSfx(sfxClick)
    elseif key == "up" or key == "w" then
      settingsSelected = settingsSelected - 1
      if settingsSelected < 1 then settingsSelected = #settings end
      playSfx(sfxClick)
    elseif key == "down" or key == "s" then
      settingsSelected = settingsSelected + 1
      if settingsSelected > #settings then settingsSelected = 1 end
      playSfx(sfxClick)
    elseif key == "left" or key == "a" then
      local item = settings[settingsSelected]
      if item.kind == "toggle" then
        changeSetting(item, false)
      elseif item.kind == "slider" then
        changeSetting(item, clamp(item.value - 0.1, 0, 1))
      end
    elseif key == "right" or key == "d" then
      local item = settings[settingsSelected]
      if item.kind == "toggle" then
        changeSetting(item, true)
      elseif item.kind == "slider" then
        changeSetting(item, clamp(item.value + 0.1, 0, 1))
      end
    elseif key == "return" or key == "space" then
      local item = settings[settingsSelected]
      if item.kind == "toggle" then
        changeSetting(item, not item.value)
      end
    end
  elseif state == "play" then
    if editor.active and editor.namingOpen then
      editor:keypressed(key, grid, camera)
      return
    end

    if key == "escape" then
      if editor.active then
        state = "menu"
        intro = 0
        love.window.setTitle("Ice Cube")
      else
        openLevelSelect()
      end
      playSfx(sfxClick)
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
      editor:keypressed(key, grid, camera)
      return
    end

    if key == "v" then
      -- Painted side zones own the view; V only previews levels with no zones.
      if next(grid.sideViewTiles) then
        playSfx(sfxToggle)
        return
      end
      local focusCol, focusRow = Perspective.worldToTile(camera.x, camera.y, grid.size)
      Perspective.toggle()
      if not grid:isInside(focusCol, focusRow) then
        focusCol, focusRow = player.col, player.row
      end
      local cx, cy = grid:tileCenter(focusCol, focusRow)
      cameraFollowX, cameraFollowY = cx, cy
      camera.x, camera.y = cx, cy
      playSfx(sfxToggle)
      return
    end

    if key == "r" then
      restartRun()
      return
    end

    player:keypressed(key, grid)
  end
end

function love.textinput(text)
  if state == "play" and editor and editor.active then
    editor:textinput(text)
  end
end

function love.mousepressed(x, y, button)
  if state == "play" then
    if editor.active then
      editor:mousepressed(x, y, button, grid, camera)
    end
    return
  end

  if button ~= 1 then return end
  local width, height = love.graphics.getDimensions()

  if state == "menu" then
    local hit = menuItemHit(x, y, width, height)
    if hit > 0 then
      selected = hit
      activate(menu[hit])
      return
    end
    if cubeHit(x, y, width, height) then
      pressingCube = true
      blush = 1
      blushTimer = 5.0
      playSfx(sfxToggle)
      bumpShake(5, 0.22)
    end
  elseif state == "levels" then
    if perspectiveButtonHit(x, y, width, height) then
      togglePerspectiveView()
      return
    end
    local hit = levelItemHit(x, y, width, height)
    if hit > 0 then
      levelSelected = hit
      playSfx(sfxClick)
      bumpShake(3.5, 0.16)
      startSelectedLevel()
    end
  elseif state == "credits" then
    state = "menu"
    intro = 0
    playSfx(sfxClick)
  elseif state == "settings" then
    local hit = settingsItemHit(x, y, width, height)
    if hit > 0 then
      settingsSelected = hit
      local item = settings[hit]
      if item.kind == "toggle" then
        changeSetting(item, not item.value)
      elseif item.kind == "slider" then
        local px, _, pw = settingsPanelRect(width, height)
        local sw = 120
        local sx = px + pw - sw - 28
        changeSetting(item, clamp((x - sx) / sw, 0, 1))
      end
    end
  end
end

function love.mousereleased(x, y, button)
  if state == "play" and editor and editor.active then
    editor:mousereleased(x, y, button, grid, camera)
  end
  if button == 1 then
    pressingCube = false
  end
end

function love.mousemoved(x, y, dx, dy)
  if state == "settings" and love.mouse.isDown(1) then
    local width, height = love.graphics.getDimensions()
    local hit = settingsItemHit(x, y, width, height)
    if hit > 0 then
      local item = settings[hit]
      if item.kind == "slider" then
        local px, _, pw = settingsPanelRect(width, height)
        local sw = 120
        local sx = px + pw - sw - 28
        changeSetting(item, clamp((x - sx) / sw, 0, 1), true)
      end
    end
  end
end

function love.wheelmoved(_, y)
  if state == "levels" and y ~= 0 then
    levelScroll = math.max(0, math.min(maxLevelScroll(), levelScroll - y))
    return
  end
  if state == "play" and editor.active then
    editor:wheelmoved(y, grid, camera)
  end
end
