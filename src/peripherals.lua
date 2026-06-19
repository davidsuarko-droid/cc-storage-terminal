-- Поиск тикера и монитора по типу (со страховкой override через сторону).
local M = {}

-- Ищет Create_StockTicker (всегда обязателен).
function M.findTicker(config)
  local ticker = config.TICKER_SIDE and peripheral.wrap(config.TICKER_SIDE)
    or peripheral.find("Create_StockTicker")
  if not ticker then
    error("No Create_StockTicker. Attach a Stock Ticker to the computer.", 0)
  end
  return ticker
end

-- Ищет CC Advanced Monitor (нужен только для текстового бэкенда).
function M.findMonitor(config)
  local monitor = config.MONITOR_SIDE and peripheral.wrap(config.MONITOR_SIDE)
    or peripheral.find("monitor")
    or peripheral.find("monitor_advanced")
  if not monitor then
    error("No monitor. Attach an Advanced Monitor.", 0)
  end
  return monitor
end

-- Обратная совместимость: оба сразу (текстовый путь без GPU).
function M.find(config)
  return M.findTicker(config), M.findMonitor(config)
end

return M
