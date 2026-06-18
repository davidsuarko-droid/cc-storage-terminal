-- Smoke: проверяем, что startup парсится и падает ИМЕННО на отсутствии тикера
-- (а не на синтаксической/рантайм-ошибке в модулях).
package.path = "./src/?.lua;./test/?.lua;" .. package.path
require("mock-cc")
-- fs/keys/parallel-стабы, которых нет в хост-Lua
fs = { exists = function() return false end }
keys = { backspace = 259, enter = 257 }
parallel = { waitForAll = function() end }
local ok, err = pcall(function() dofile("src/startup.lua") end)
assert(not ok, "ожидалась ошибка (нет тикера), но startup не упал")
assert(tostring(err):find("Create_StockTicker"),
  "ожидалась ошибка про Create_StockTicker, получили: " .. tostring(err))
print("smoke OK — startup грузится, периферия валидируется")
