-- Поиск тикера и монитора по типу (со страховкой override через сторону).
local M = {}

function M.find(config)
  local ticker = config.TICKER_SIDE and peripheral.wrap(config.TICKER_SIDE)
    or peripheral.find("Create_StockTicker")
  if not ticker then
    error("No Create_StockTicker. Attach a Stock Ticker to the computer.", 0)
  end

  local monitor = config.MONITOR_SIDE and peripheral.wrap(config.MONITOR_SIDE)
    or peripheral.find("monitor")
    or peripheral.find("monitor_advanced")
  if not monitor then
    error("No monitor. Attach an Advanced Monitor.", 0)
  end

  return ticker, monitor
end

return M
