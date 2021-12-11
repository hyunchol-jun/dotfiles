-- GRID
hs.window.animationDuration=0
local hotkey = require "hs.hotkey"
local grid = require "hs.grid"

grid.MARGINX = 0
grid.MARGINY = 0
grid.GRIDHEIGHT = 4
grid.GRIDWIDTH = 6

local mod_resize = {"ctrl", "cmd"}
local mod_move = {"ctrl", "alt"}

-- Move Window
hotkey.bind(mod_move, 'j', grid.pushWindowDown)
hotkey.bind(mod_move, 'k', grid.pushWindowUp)
hotkey.bind(mod_move, 'h', grid.pushWindowLeft)
hotkey.bind(mod_move, 'l', grid.pushWindowRight)

-- Resize Window
hotkey.bind(mod_resize, 'k', grid.resizeWindowShorter)
hotkey.bind(mod_resize, 'j', grid.resizeWindowTaller)
hotkey.bind(mod_resize, 'l', grid.resizeWindowWider)
hotkey.bind(mod_resize, 'h', grid.resizeWindowThinner)
