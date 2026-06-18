-- Визуальный preview рендера на хост-Lua: мок-монитор пишет в char-grid, печатаем.
-- Не юнит-тест — глаз-чек раскладки. Запуск: lua5.1 test/render-preview.lua [W H]
package.path = "./src/?.lua;./test/?.lua;" .. package.path
require("mock-cc")

local W = tonumber(arg and arg[1]) or 50
local H = tonumber(arg and arg[2]) or 19

local function newMonitor(w, h)
  local grid = {}
  for y = 1, h do grid[y] = {} ; for x = 1, w do grid[y][x] = " " end end
  local cx, cy = 1, 1
  return {
    _grid = grid,
    setTextScale = function() end,
    getSize = function() return w, h end,
    setBackgroundColor = function() end,
    setTextColor = function() end,
    clear = function() for y=1,h do for x=1,w do grid[y][x]=" " end end end,
    setCursorPos = function(x, y) cx, cy = x, y end,
    write = function(s)
      for i = 1, #s do
        local x = cx + i - 1
        if grid[cy] and x >= 1 and x <= w then grid[cy][x] = s:sub(i, i) end
      end
      cx = cx + #s
    end,
  }
end

local function dump(mon, w, h)
  print("+" .. string.rep("-", w) .. "+")
  for y = 1, h do
    print("|" .. table.concat(mon._grid[y]) .. "|")
  end
  print("+" .. string.rep("-", w) .. "+")
end

local render = require("render")

-- сикстант-байты (128-159) = мусор в UTF8-терминале. Подменяем на ASCII-плейсхолдер
-- (две буквы категории) — глаз-чек раскладки, не пиксельной графики.
local sprites = require("sprites")
sprites.draw = function(mon, x, y, name, fg, bg)
  mon.setCursorPos(x, y); mon.write(name:sub(1, 2))
  mon.setCursorPos(x, y + 1); mon.write(name:sub(3, 4) ~= "" and name:sub(3, 4) or "  ")
end

-- сэмпл-модель
local items = {}
local samples = {
  {"Andesite Alloy",128,"Create"},{"Brass Ingot",64,"Resources"},{"Cogwheel",32,"Create"},
  {"Shaft",256,"Create"},{"Iron Ingot",512,"Resources"},{"Gold Nugget",999,"Resources"},
  {"Redstone",1280,"Redstone"},{"Piston",48,"Building"},{"Oak Planks",640,"Wood"},
  {"Cobblestone",4096,"Stone"},{"White Wool",96,"Other"},{"Apple",37,"Other"},
}
for i, s in ipairs(samples) do
  items[#items+1] = { id = "id" .. i, display = s[1], count = s[2], group = s[3] }
end

local model = {
  items = items, groups = {"All","Create","Redstone","Resources","Wood","Stone","Building","Other"},
  group = "Create", query = "", searchFocus = false, scroll = 0,
  address = "Main", addresses = {"Main","Core"}, addrIdx = 1,
  toast = nil, keypad = nil, pressed = "id3",
}

local mon = newMonitor(W, H)
print("\n== Главный экран ==")
render.draw(mon, model)
dump(mon, W, H)

print("\n== С keypad ==")
model.pressed = nil
model.keypad = { entry = items[5], value = 73 }
local mon2 = newMonitor(W, H)
render.draw(mon2, model)
dump(mon2, W, H)
