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

-- сэмпл-модель
local items = {}
local samples = {
  {"Andesite Alloy",128},{"Brass Ingot",64},{"Cogwheel",32},{"Shaft",256},
  {"Iron Ingot",512},{"Gold Nugget",999},{"Redstone",1280},{"Piston",48},
  {"Oak Planks",640},{"Cobblestone",4096},{"White Wool",96},{"Apple",37},
}
for _, s in ipairs(samples) do items[#items+1] = { id="x", display=s[1], count=s[2], group="All" } end

local model = {
  items = items, groups = {"All","Create","Redstone","Resources","Wood","Stone","Building","Other"},
  group = "Create", query = "", searchFocus = false, scroll = 0,
  address = "Main", addresses = {"Main","Core"}, addrIdx = 1,
  toast = nil, keypad = nil,
}

local mon = newMonitor(W, H)
print("\n== Главный экран ==")
render.draw(mon, model)
dump(mon, W, H)

print("\n== С keypad ==")
model.keypad = { entry = items[5], value = 12 }
local mon2 = newMonitor(W, H)
render.draw(mon2, model)
dump(mon2, W, H)
