-- Глаз-чек GPU-рендера: гоняет render_gpu.draw на мок-GPU и печатает
-- сводку вызовов (типы + ключевой текст). Размер пикселей: arg1 x arg2.
package.path = "./src/?.lua;./test/?.lua;" .. package.path
require("mock-cc")
local mockgpu = require("mock-gpu")
local rg = require("render_gpu")
local ui = require("ui_logic")

local W = tonumber(arg[1]) or 328
local H = tonumber(arg[2]) or 200
local g = mockgpu.new(W, H)
local model = {
  items = {
    { id = "create:cogwheel", display = "Cogwheel", count = 128, group = "Create" },
    { id = "create:large_cogwheel", display = "Large Cogwheel", count = 64, group = "Create" },
    { id = "minecraft:iron_ingot", display = "Iron Ingot", count = 999, group = "Resources" },
    { id = "minecraft:redstone", display = "Redstone Dust", count = 4096, group = "Redstone" },
    { id = "minecraft:oak_log", display = "Oak Log", count = 320, group = "Wood" },
  },
  groups = { "All", "Create", "Redstone", "Resources", "Wood" }, group = "All",
  query = "", searchFocus = false, scroll = 0,
  address = "Main", basket = ui.basketNew(), step = 32, toast = nil,
}
ui.basketAdd(model.basket, model.items[1], 32)
ui.basketAdd(model.basket, model.items[3], 64)
local hit = rg.draw(g, model)

local counts = {}
for _, c in ipairs(g._calls) do counts[c.op] = (counts[c.op] or 0) + 1 end
print(string.format("=== GPU preview %dx%d ===", W, H))
for op, n in pairs(counts) do print(string.format("  %-16s x%d", op, n)) end
print("--- text drawn ---")
for _, c in ipairs(g._calls) do
  if c.op == "drawText" then print("  " .. tostring(c.s)) end
end
print(string.format("--- hit: %d tiles, %d chips, step=%s confirm=%s cartUp=%s",
  #hit.tiles, #hit.chips, tostring(hit.step ~= nil), tostring(hit.confirm ~= nil), tostring(hit.cartUp ~= nil)))
