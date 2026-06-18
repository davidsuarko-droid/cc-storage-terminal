-- Минимальные стабы CC:Tweaked для headless-тестов на хост-Lua 5.1.
local M = {}

-- colors: любой ключ → само имя ключа (рендер не тестируем, важно лишь не падать)
colors = setmetatable({}, { __index = function(_, k) return k end })

-- реестр периферий
local byType, bySide = {}, {}
peripheral = {}
function peripheral.find(t) return byType[t] end
function peripheral.wrap(side) return bySide[side] end
function M.register(t, obj) byType[t] = obj end
function M.registerSide(side, obj) bySide[side] = obj end

-- фейковый Create_StockTicker: stock() отдаёт заданный список,
-- requestFiltered логирует вызовы и возвращает запрошенное количество
function M.ticker(stockList)
  local calls = {}
  return {
    stock = function(_) return stockList end,
    requestFiltered = function(addr, filter)
      calls[#calls + 1] = { addr = addr, filter = filter }
      return filter._requestCount
    end,
    _calls = calls,
  }
end

-- скриптуемая очередь событий для os.pullEvent
local queue = {}
function M.events(list) queue = list end
local realOs = os
os = setmetatable({
  pullEvent = function() return table.remove(queue, 1) end,
  startTimer = function(_) return 1 end,
}, { __index = realOs })

return M
