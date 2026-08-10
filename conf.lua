function love.conf(t)
  t.identity = "ice-cube"
  -- The Love.js runtime used by the web build is based on LÖVE 11.4.
  t.version = "11.4"
  t.window.title = "Ice Cube"
  t.window.width = 960
  t.window.height = 540
  t.window.minwidth = 800
  t.window.minheight = 450
  t.window.resizable = true
  t.window.vsync = 1
end
